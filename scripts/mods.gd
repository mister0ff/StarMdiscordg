extends Node
## Autoload "Mods": carrega pacotes .stc (arquivos ZIP) por mundo/servidor.
## Um mod pode ter: mod.cmd, pack.png, item/, bloco/, receitas/, entidade/, modelo/, script/, textura/.

var game: Node
var globals: Dictionary = {}
var loaded: Array = [] # [{name, version, description, author, ns, file}]
var entities: Dictionary = {} # "ns:id" -> definição
var script_commands: Dictionary = {} # "nome" -> {usage, perm, prog, mod}
var handlers: Dictionary = {} # evento -> [{prog, mod}]
var warnings: Array = []

var _idmap: Dictionary = {}
var _used_ids: Dictionary = {}
var _tick_t := 0.0


func _process(delta: float) -> void:
	if game == null or not handlers.has("tick"):
		return
	_tick_t += delta
	if _tick_t >= 1.0:
		_tick_t = 0.0
		if game.playing and game.local_player != null:
			emit("tick", game.script_ctx({}))


func warn(msg: String) -> void:
	warnings.append(msg)
	print("[mods] ", msg)


func clear() -> void:
	Blocks.unload_mod_content()
	entities.clear()
	script_commands.clear()
	handlers.clear()
	loaded.clear()
	globals.clear()
	warnings.clear()
	_idmap = {}
	_used_ids.clear()


# ================================================================ leitura básica de texto
static func parse_pairs(text: String) -> Array:
	## Lista [chave_normalizada, valor] na ordem do arquivo. Ignora # e // no início da linha.
	var out: Array = []
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	for line in text.split("\n"):
		var t := String(line).strip_edges()
		if t.is_empty() or t.begins_with("#") or t.begins_with("//"):
			continue
		var ci := t.find(":")
		if ci <= 0:
			continue
		out.append([ScriptEngine.norm(t.substr(0, ci)), t.substr(ci + 1).strip_edges()])
	return out


static func pairs_to_dict(pairs: Array) -> Dictionary:
	var d: Dictionary = {}
	for p in pairs:
		d[String(p[0])] = ScriptEngine.clean(String(p[1]))
	return d


static func _num(d: Dictionary, key: String, def: float) -> float:
	if not d.has(key):
		return def
	var v := String(d[key]).strip_edges().replace(",", ".")
	return float(v) if v.is_valid_float() else def


static func _bool(d: Dictionary, key: String, def: bool) -> bool:
	if not d.has(key):
		return def
	var v := ScriptEngine.norm(String(d[key]))
	if v in ["sim", "true", "1", "yes", "s"]:
		return true
	if v in ["nao", "false", "0", "no", "n"]:
		return false
	return def


static func _first(d: Dictionary, keys: Array, def: String) -> String:
	for k in keys:
		if d.has(k):
			return String(d[k])
	return def


static func _slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		var u := String(ch).unicode_at(0)
		if (u >= 97 and u <= 122) or (u >= 48 and u <= 57):
			out += String(ch)
		else:
			out += "_"
	out = out.strip_edges()
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")


static func _full_id(raw: String, ns: String) -> String:
	var t := raw.strip_edges().to_lower()
	if t.contains(":"):
		return t
	return ns + ":" + t


static func _parse_color(s: String, def: Color) -> Color:
	var t := s.strip_edges()
	if t.begins_with("#") or t.length() == 6 or t.length() == 8:
		if Color.html_is_valid(t):
			return Color.html(t)
	return def


static func _floats(s: String) -> Array:
	var out: Array = []
	for part in s.replace(",", " ").split(" ", false):
		var p := String(part)
		if p.is_valid_float():
			out.append(float(p))
	return out


# ================================================================ ZIP
class Pack:
	extends RefCounted
	var zr: ZIPReader
	var files: Dictionary = {} # caminho relativo em minúsculas -> caminho real no zip
	var prefix := ""

	func open(path: String) -> bool:
		zr = ZIPReader.new()
		if zr.open(path) != OK:
			return false
		var best := ""
		var best_depth := 999
		for f in zr.get_files():
			var fs := String(f)
			if fs.ends_with("/"):
				continue
			var base := fs.get_file().to_lower()
			if base == "mod.cmd":
				var depth := fs.count("/")
				if depth < best_depth:
					best_depth = depth
					best = fs
		if best.is_empty():
			zr.close()
			return false
		prefix = best.substr(0, best.length() - "mod.cmd".length())
		for f in zr.get_files():
			var fs2 := String(f)
			if fs2.ends_with("/") or not fs2.begins_with(prefix):
				continue
			files[fs2.substr(prefix.length()).to_lower()] = fs2
		return true

	func close() -> void:
		if zr != null:
			zr.close()

	func has(rel: String) -> bool:
		return files.has(rel.to_lower())

	func text(rel: String) -> String:
		if not files.has(rel.to_lower()):
			return ""
		var t: String = zr.read_file(String(files[rel.to_lower()])).get_string_from_utf8()
		if t.begins_with("\ufeff"):
			t = t.substr(1)
		return t

	func bytes(rel: String) -> PackedByteArray:
		if not files.has(rel.to_lower()):
			return PackedByteArray()
		return zr.read_file(String(files[rel.to_lower()]))

	func list(folder: String, ext: String) -> Array:
		var out: Array = []
		var pre := folder.to_lower()
		for k in files:
			var ks := String(k)
			if ks.begins_with(pre) and ks.ends_with(ext):
				out.append(ks)
		out.sort()
		return out

	func image(rel: String) -> Image:
		## tenta rel, rel.png, rel.jpg
		var p := rel.strip_edges().to_lower().trim_prefix("./").trim_prefix("/")
		for cand in [p, p + ".png", p + ".jpg", p + ".jpeg", p + ".webp"]:
			if files.has(cand):
				var b := bytes(cand)
				var img := Image.new()
				var err := ERR_FILE_UNRECOGNIZED
				if cand.ends_with(".jpg") or cand.ends_with(".jpeg"):
					err = img.load_jpg_from_buffer(b)
				elif cand.ends_with(".webp"):
					err = img.load_webp_from_buffer(b)
				else:
					err = img.load_png_from_buffer(b)
				if err != OK:
					err = img.load_png_from_buffer(b)
				if err != OK:
					err = img.load_jpg_from_buffer(b)
				if err == OK:
					return img
		return null


static func placeholder_image() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var on := ((x / 4) + (y / 4)) % 2 == 0
			img.set_pixel(x, y, Color(0.9, 0.1, 0.9) if on else Color(0.1, 0.1, 0.1))
	return img


## Lê o resumo de um .stc sem registrar nada. {ok, error, name, version, description, author, ns, icon, counts}
static func inspect(path: String) -> Dictionary:
	var pk := Pack.new()
	if not pk.open(path):
		return {"ok": false, "error": "Arquivo inválido: não é um .stc (zip) com mod.cmd."}
	var d := pairs_to_dict(parse_pairs(pk.text("mod.cmd")))
	var nm := _first(d, ["name", "nome"], path.get_file().get_basename())
	var info := {
		"ok": true, "error": "", "name": nm,
		"version": _first(d, ["version", "versao"], "1.0"),
		"description": _first(d, ["description", "descripion", "descricao", "desc"], ""),
		"author": _first(d, ["author", "autor"], ""),
		"ns": _slug(_first(d, ["id", "namespace", "espaco"], nm)),
		"icon": null,
		"counts": {
			"item": pk.list("item/", ".txt").size(), "bloco": pk.list("bloco/", ".txt").size(),
			"receitas": pk.list("receitas/", ".txt").size(), "entidade": pk.list("entidade/", ".txt").size(),
			"script": pk.list("script/", ".txt").size(),
		},
	}
	if String(info["ns"]).is_empty():
		info["ns"] = "mod"
	var ic := pk.image("pack.png")
	if ic != null:
		info["icon"] = ImageTexture.create_from_image(ic)
	pk.close()
	return info


## Copia um .stc para a pasta de mods do mundo. Retorna {ok, error, file, info}.
func import_to_world(world_id: String, src: String) -> Dictionary:
	var info := inspect(src)
	if not bool(info["ok"]):
		return info
	var dir := WorldStore.mods_dir(world_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var base := _slug(src.get_file().get_basename())
	if base.is_empty():
		base = "mod"
	var fname := base + ".stc"
	var n := 2
	while FileAccess.file_exists(dir + "/" + fname):
		fname = "%s_%d.stc" % [base, n]
		n += 1
	var fin := FileAccess.open(src, FileAccess.READ)
	if fin == null:
		return {"ok": false, "error": "Não consegui abrir o arquivo."}
	var data := fin.get_buffer(fin.get_length())
	fin.close()
	var fout := FileAccess.open(dir + "/" + fname, FileAccess.WRITE)
	if fout == null:
		return {"ok": false, "error": "Não consegui salvar o mod no mundo."}
	fout.store_buffer(data)
	fout.close()
	return {"ok": true, "error": "", "file": fname, "info": info}


# ================================================================ carregar para um mundo
func load_for_world(meta: Dictionary) -> void:
	clear()
	_idmap = meta["idmap"]
	for k in _idmap:
		_used_ids[int(_idmap[k])] = true
	var pending: Array = []
	var entries: Array = meta["mods"]
	for e in entries:
		if not bool(e.get("enabled", true)):
			continue
		var path := WorldStore.mods_dir(String(meta["id"])) + "/" + String(e["file"])
		_load_mod(path, String(e["file"]), pending)
	_resolve_recipes(pending)
	Blocks.rebuild_atlas()


func _alloc(sid: String, as_block: bool) -> int:
	if _idmap.has(sid):
		var v := int(_idmap[sid])
		_used_ids[v] = true
		return v
	var n := Blocks.MOD_BLOCK_MIN if as_block else Blocks.MOD_ITEM_BASE
	if as_block:
		while n <= 255 and (_used_ids.has(n) or (n >= 100 and n <= 153)):
			n += 1
		if n > 255:
			return -1
	else:
		while _used_ids.has(n):
			n += 1
	_used_ids[n] = true
	_idmap[sid] = n
	return n


func _load_mod(path: String, file: String, pending: Array) -> void:
	var pk := Pack.new()
	if not pk.open(path):
		warn("Não foi possível abrir o mod '%s'." % file)
		return
	var d := pairs_to_dict(parse_pairs(pk.text("mod.cmd")))
	var nm := _first(d, ["name", "nome"], file.get_basename())
	var ns := _slug(_first(d, ["id", "namespace", "espaco"], nm))
	if ns.is_empty():
		ns = "mod"
	loaded.append({
		"name": nm, "version": _first(d, ["version", "versao"], "1.0"),
		"description": _first(d, ["description", "descripion", "descricao", "desc"], ""),
		"author": _first(d, ["author", "autor"], ""), "ns": ns, "file": file,
	})
	for rel in pk.list("item/", ".txt"):
		_load_item(pk, String(rel), ns, nm)
	for rel in pk.list("bloco/", ".txt"):
		_load_block(pk, String(rel), ns, nm)
	for rel in pk.list("entidade/", ".txt"):
		_load_entity(pk, String(rel), ns, nm)
	for rel in pk.list("receitas/", ".txt"):
		_parse_recipe(pk.text(String(rel)), ns, nm, String(rel), pending)
	for rel in pk.list("script/", ".txt"):
		_load_script(pk.text(String(rel)), nm + "/" + String(rel))
	pk.close()


func _tool_kind_from(word: String) -> int:
	match ScriptEngine.norm(word):
		"picareta", "pickaxe":
			return Blocks.KIND_PICK
		"machado", "axe":
			return Blocks.KIND_AXE
		"pa", "shovel":
			return Blocks.KIND_SHOVEL
		"espada", "sword":
			return Blocks.KIND_SWORD
	return -1


func _icon_from(pk: Pack, tex_path: String, nm: String, label: String) -> Image:
	var img: Image = null
	if tex_path != "":
		img = pk.image(tex_path)
	if img == null:
		warn("%s: textura '%s' não encontrada (usando quadriculado)." % [label, tex_path])
		return placeholder_image()
	var im: Image = img.duplicate()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != 16 or im.get_height() != 16:
		im.resize(16, 16, Image.INTERPOLATE_NEAREST)
	return im


func _load_item(pk: Pack, rel: String, ns: String, mod_name: String) -> void:
	var d := pairs_to_dict(parse_pairs(pk.text(rel)))
	var raw_id := _first(d, ["id"], rel.get_file().get_basename())
	var sid := _full_id(raw_id, ns)
	var id := _alloc(sid, false)
	var label := "%s/%s" % [mod_name, rel]
	var def := {
		"name": _first(d, ["nome", "name"], raw_id), "block": false,
		"stack": clampi(int(_num(d, "empilhavel", 64.0)), 1, 64),
		"shape": "mod", "color": Color(0.8, 0.8, 0.8), "mod": true,
		"desc": _first(d, ["descricao", "description"], ""),
		"icon_img": _icon_from(pk, _first(d, ["textura", "texture"], ""), raw_id, label),
	}
	var dur := int(_num(d, "durabilidade", 0.0))
	if dur > 0:
		def["dur"] = dur
		def["stack"] = 1
	if d.has("dano"):
		def["damage"] = _num(d, "dano", 1.0)
	var kind := _tool_kind_from(String(d.get("ferramenta", "")))
	if kind >= 0:
		def["tool_kind"] = kind
		def["tool_tier"] = clampi(int(_num(d, "nivel", 0.0)), 0, 3)
		if d.has("velocidade"):
			def["speed"] = _num(d, "velocidade", 2.0)
	Blocks.defs[id] = def
	Blocks.mod_ids.append(id)
	Blocks.register_string_id(sid, id)
	if d.has("comida"):
		Blocks.food[id] = int(_num(d, "comida", 1.0))


func _load_block(pk: Pack, rel: String, ns: String, mod_name: String) -> void:
	var d := pairs_to_dict(parse_pairs(pk.text(rel)))
	var raw_id := _first(d, ["id"], rel.get_file().get_basename())
	var sid := _full_id(raw_id, ns)
	var id := _alloc(sid, true)
	var label := "%s/%s" % [mod_name, rel]
	if id < 0:
		warn("%s: limite de blocos de mods atingido." % label)
		return
	var base_tex := _first(d, ["textura", "texture"], "")
	var t_top := _first(d, ["textura-topo", "textura-cima"], base_tex)
	var t_side := _first(d, ["textura-lado"], base_tex)
	var t_bot := _first(d, ["textura-baixo", "textura-fundo"], base_tex)
	var tiles: Array = []
	var key_base := "mod:%s/%s" % [ns, _slug(raw_id)]
	var seen: Dictionary = {}
	for pair in [["top", t_top], ["side", t_side], ["bot", t_bot]]:
		var tpath := String(pair[1])
		var tname := key_base + "_" + String(pair[0])
		if seen.has(tpath):
			tname = String(seen[tpath])
		else:
			Blocks.add_extra_tile(tname, _icon_from(pk, tpath, raw_id, label))
			seen[tpath] = tname
		tiles.append(tname)
	var kind := _tool_kind_from(String(d.get("ferramenta", "")))
	var min_tier := -1
	if kind >= 0 and d.has("nivel"):
		min_tier = clampi(int(_num(d, "nivel", 0.0)), 0, 3)
	var transparent := _bool(d, "transparente", false)
	var drop_id := id
	var drop_raw := _first(d, ["solta", "drop"], "self").strip_edges().to_lower()
	var drop_kw := ScriptEngine.norm(drop_raw)
	if drop_kw in ["nenhum", "nada", "none", "0"]:
		drop_id = 0
	elif drop_kw != "self" and drop_kw != "si" and drop_kw != "proprio":
		drop_id = -1 # resolvido depois (pode ser item do mesmo mod)
	var def := {
		"name": _first(d, ["nome", "name"], raw_id), "hard": _num(d, "dureza", 1.5),
		"tool": kind, "min_tier": min_tier, "drop": drop_id, "drop_n": clampi(int(_num(d, "solta-qtd", 1.0)), 1, 64),
		"tiles": tiles, "solid": _bool(d, "solido", true), "opaque": not transparent,
		"stack": 64, "block": true, "icon_tile": tiles[1], "mod": true,
		"desc": _first(d, ["descricao", "description"], ""),
	}
	var light := clampi(int(_num(d, "luz", 0.0)), 0, 15)
	if light > 0:
		def["light"] = light
	if _num(d, "dureza", 1.5) < 0.0:
		def["hard"] = -1.0
	Blocks.defs[id] = def
	Blocks.mod_ids.append(id)
	Blocks.register_string_id(sid, id)
	if drop_id == -1:
		_pending_drops.append([id, drop_raw, ns])


var _pending_drops: Array = []


func _load_entity(pk: Pack, rel: String, ns: String, mod_name: String) -> void:
	var pairs := parse_pairs(pk.text(rel))
	var d := pairs_to_dict(pairs)
	var raw_id := _first(d, ["id"], rel.get_file().get_basename())
	var sid := _full_id(raw_id, ns)
	var label := "%s/%s" % [mod_name, rel]
	var def := {
		"id": sid, "name": _first(d, ["nome", "name"], raw_id), "hp": _num(d, "vida", 10.0),
		"speed": _num(d, "velocidade", 2.0), "hostile": _bool(d, "hostil", false),
		"damage": _num(d, "dano", 2.0), "w": _num(d, "largura", 0.4), "h": _num(d, "altura", 1.0),
		"spawn": ScriptEngine.norm(_first(d, ["spawn", "nasce"], "nenhum")),
		"spawn_chance": _num(d, "chance", 0.2), "spawn_max": int(_num(d, "maximo", 4.0)),
		"color": _parse_color(_first(d, ["cor", "color"], "#9a9a9a"), Color(0.6, 0.6, 0.6)),
		"texture": null, "parts": [], "drops": [], "mod": true,
	}
	var tp := _first(d, ["textura", "texture"], "")
	if tp != "":
		var im := pk.image(tp)
		if im == null:
			warn("%s: textura '%s' não encontrada." % [label, tp])
		else:
			var ii: Image = im.duplicate()
			if ii.is_compressed():
				ii.decompress()
			ii.convert(Image.FORMAT_RGBA8)
			def["texture"] = ImageTexture.create_from_image(ii)
	var mp := _first(d, ["modelo", "model"], "")
	if mp != "":
		var mtext := pk.text(mp if pk.has(mp) else mp + ".txt")
		if mtext.is_empty():
			warn("%s: modelo '%s' não encontrado." % [label, mp])
		else:
			def["parts"] = _parse_model(mtext)
	if (def["parts"] as Array).is_empty():
		var hh: float = def["h"]
		var ww: float = def["w"]
		(def["parts"] as Array).append({"kind": "part", "pos": Vector3(0, hh * 0.5, 0), "size": Vector3(ww * 1.6, hh, ww * 1.6), "color": null})
	for p in pairs:
		if String(p[0]) == "drop" or String(p[0]) == "solta":
			var parts := String(p[1]).strip_edges().split(" ", false)
			if parts.size() == 0:
				continue
			var item_raw := ScriptEngine.clean(String(parts[0]))
			var nums: Array = []
			for k in range(1, parts.size()):
				var tok := ScriptEngine.clean(String(parts[k]))
				if tok.is_valid_float():
					nums.append(float(tok))
			var mn := int(nums[0]) if nums.size() > 0 else 1
			var mx := int(nums[1]) if nums.size() > 1 else mn
			var ch := float(nums[2]) if nums.size() > 2 else 1.0
			(def["drops"] as Array).append({"item": _full_id(item_raw, ns), "min": mn, "max": maxi(mn, mx), "chance": ch})
	entities[sid] = def


func _parse_model(text: String) -> Array:
	var parts: Array = []
	for line in text.split("\n"):
		var t := String(line).strip_edges()
		if t.is_empty() or t.begins_with("#") or t.begins_with("//"):
			continue
		var ci := t.find(":")
		if ci <= 0:
			continue
		var key := ScriptEngine.norm(t.substr(0, ci))
		var rest := t.substr(ci + 1).strip_edges()
		var kind := ""
		match key:
			"parte", "caixa", "box":
				kind = "part"
			"perna", "leg":
				kind = "leg"
			"braco", "arm":
				kind = "arm"
		if kind == "":
			continue
		var col = null
		var tokens := rest.replace(",", " ").split(" ", false)
		var nums: Array = []
		for tk in tokens:
			var tks := String(tk)
			if tks.begins_with("#"):
				col = _parse_color(tks, Color(0.6, 0.6, 0.6))
			elif tks.is_valid_float():
				nums.append(float(tks))
		if nums.size() < 6:
			continue
		parts.append({
			"kind": kind, "pos": Vector3(nums[0], nums[1], nums[2]),
			"size": Vector3(maxf(0.02, nums[3]), maxf(0.02, nums[4]), maxf(0.02, nums[5])), "color": col,
		})
	return parts


## Receita em grade:  resultado: "x:y"  +  linhas [a] [b] [c]  +  a: "star:log"
func _parse_recipe(text: String, ns: String, mod_name: String, rel: String, pending: Array) -> void:
	var result := ""
	var qty := 1
	var station := -1
	var rows: Array = []
	var map: Dictionary = {}
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	var re := RegEx.new()
	re.compile("\\[([^\\]]*)\\]")
	for line in text.split("\n"):
		var t := String(line).strip_edges()
		if t.is_empty() or t.begins_with("#") or t.begins_with("//"):
			continue
		if t.begins_with("["):
			var row: Array = []
			for m in re.search_all(t):
				row.append(m.get_string(1).strip_edges().to_lower())
			if not row.is_empty():
				rows.append(row)
			continue
		var ci := t.find(":")
		if ci <= 0:
			continue
		var key := ScriptEngine.norm(t.substr(0, ci))
		var val := ScriptEngine.clean(t.substr(ci + 1))
		if key == "resultado" or key == "result":
			var sp := val.split(" ", false)
			if sp.size() > 0:
				result = _full_id(ScriptEngine.clean(String(sp[0])), ns)
			if sp.size() > 1 and String(sp[1]).is_valid_int():
				qty = int(String(sp[1]))
		elif key == "quantidade" or key == "qtd":
			qty = maxi(1, int(val))
		elif key == "estacao" or key == "station":
			match ScriptEngine.norm(val):
				"nenhuma", "nenhum", "mao", "none":
					station = 0
				"mesa", "bancada", "table":
					station = 1
				"fornalha", "furnace":
					station = 2
		elif key.length() == 1:
			map[key] = _full_id(val, "star") if not val.contains(":") else val.to_lower()
	if result == "" or rows.is_empty():
		warn("%s/%s: receita sem 'resultado:' ou sem grade [x]." % [mod_name, rel])
		return
	if station < 0:
		var big := rows.size() > 2
		for r in rows:
			if (r as Array).size() > 2:
				big = true
		station = 1 if big else 0
	pending.append({"result": result, "n": qty, "rows": rows, "map": map, "st": station, "label": "%s/%s" % [mod_name, rel]})


func _resolve_recipes(pending: Array) -> void:
	for pd in _pending_drops:
		var bid: int = pd[0]
		var item := Blocks.id_from_string(_full_id(String(pd[1]), String(pd[2])))
		if item == 0 and Blocks.str_to_id.has(String(pd[1])):
			item = int(Blocks.str_to_id[String(pd[1])])
		if Blocks.defs.has(bid):
			Blocks.defs[bid]["drop"] = item
			if item == 0:
				warn("Bloco %s: item de drop '%s' não existe." % [Blocks.string_of(bid), String(pd[1])])
	_pending_drops.clear()
	for pr in pending:
		var out := Blocks.id_from_string(String(pr["result"]))
		if out == 0:
			warn("%s: resultado '%s' não existe." % [pr["label"], pr["result"]])
			continue
		var counts: Dictionary = {}
		var ok := true
		var map: Dictionary = pr["map"]
		for row in pr["rows"]:
			for sym in row:
				var s := String(sym)
				if s == "" or s == " " or s == "-" or s == "_" or s == "0":
					continue
				if not map.has(s):
					warn("%s: símbolo [%s] sem definição." % [pr["label"], s])
					ok = false
					continue
				var iid := Blocks.id_from_string(String(map[s]))
				if iid == 0:
					warn("%s: ingrediente '%s' não existe." % [pr["label"], map[s]])
					ok = false
					continue
				counts[iid] = int(counts.get(iid, 0)) + 1
		if not ok or counts.is_empty():
			continue
		var grid_txt: Array = []
		for row in pr["rows"]:
			var cells: Array = []
			for sym in row:
				var s2 := String(sym)
				if map.has(s2):
					cells.append(Blocks.name_of(Blocks.id_from_string(String(map[s2]))))
				else:
					cells.append("-")
			grid_txt.append(" | ".join(cells))
		Blocks.recipes.append({"out": out, "n": int(pr["n"]), "in": counts, "st": int(pr["st"]), "mod": true, "grid": "\n".join(grid_txt)})


func _load_script(text: String, label: String) -> void:
	var res := ScriptEngine.compile(text, label)
	for e in res["errors"]:
		warn(String(e))
	for h in res["handlers"]:
		var ev := String(h["event"])
		if not handlers.has(ev):
			handlers[ev] = []
		(handlers[ev] as Array).append({"prog": h["prog"], "mod": label})
	for c in res["commands"]:
		script_commands[String(c["name"])] = {"usage": c["usage"], "perm": c["perm"], "prog": c["prog"], "mod": label}


# ================================================================ eventos e comandos de script
func has_handlers(ev: String) -> bool:
	return handlers.has(ev)


## Executa os scripts do evento. Retorna {"cancel": bool}.
func emit(ev: String, ctx: Dictionary) -> Dictionary:
	var result := {"cancel": false}
	if not handlers.has(ev):
		return result
	for h in handlers[ev]:
		var st := {"cancel": false, "counters": {}}
		ScriptEngine.run(self, h["prog"], ctx, st, 0)
		if bool(st["cancel"]):
			result["cancel"] = true
	return result


func run_command_script(cmd: String, args: Array, ctx: Dictionary) -> void:
	if not script_commands.has(cmd):
		return
	var c: Dictionary = script_commands[cmd]
	ctx["args"] = args.size()
	for i in 9:
		ctx["arg%d" % (i + 1)] = args[i] if i < args.size() else ""
	var st := {"cancel": false, "counters": {}}
	ScriptEngine.run(self, c["prog"], ctx, st, 0)


func exec_command(text: String, ctx: Dictionary) -> void:
	if game != null and game.commands != null:
		game.commands.execute("/" + text.lstrip("/"), true)


func schedule(secs: float, prog: Array, ctx: Dictionary, state: Dictionary, pc: int) -> void:
	await get_tree().create_timer(secs).timeout
	if game == null or not game.playing:
		return
	ScriptEngine.run(self, prog, ctx, state, pc)


## Escolhe uma entidade de mod para nascer (ou "" se nenhuma).
func pick_spawn(night: bool) -> String:
	var options: Array = []
	for id in entities:
		var d: Dictionary = entities[id]
		var sp := String(d["spawn"])
		if sp == "nenhum":
			continue
		if sp == "noite" and not night:
			continue
		if sp == "dia" and night:
			continue
		options.append(id)
	if options.is_empty():
		return ""
	var pick: String = options[randi() % options.size()]
	if randf() < float(entities[pick]["spawn_chance"]):
		return pick
	return ""
