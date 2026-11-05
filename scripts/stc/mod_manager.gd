extends Node
## Autoload "ModManager": carrega mods .stc (zip), registra blocos/itens/receitas/entidades/scripts/comandos.
## Um mod .stc é um ZIP com: mod.cmd, pack.png, receitas/, item/, bloco/, entidade/, modelo/, script/, textura/.

const ITEM_DIRS := ["item/", "itens/", "items/"]
const BLOCK_DIRS := ["bloco/", "blocos/", "block/", "blocks/"]
const ENTITY_DIRS := ["entidade/", "entidades/", "entity/", "entities/", "mob/", "mobs/"]
const RECIPE_DIRS := ["receitas/", "receita/", "recipes/"]
const SCRIPT_DIRS := ["script/", "scripts/"]
const MODEL_DIRS := ["modelo/", "modelos/", "model/", "models/"]
const TOOL_KINDS := {"picareta": 0, "pickaxe": 0, "machado": 1, "axe": 1, "pa": 2, "shovel": 2, "espada": 3, "sword": 3}
const BEHAVIORS := {
	"passivo": "passive", "passive": "passive", "neutro": "passive",
	"melee": "melee", "corpo_a_corpo": "melee", "zumbi": "melee", "agressivo": "melee",
	"ranged": "ranged", "distancia": "ranged", "esqueleto": "ranged",
	"explosivo": "explode", "explode": "explode", "creeper": "explode",
}
const HOOKS := {
	"ao_usar": ["after-use", "item"], "ao_comer": ["player-eat", "item"], "ao_bater": ["after-hit", "item"],
	"ao_quebrar": ["after-break", "block"], "ao_colocar": ["after-place", "block"], "ao_clicar": ["interact", "block"],
	"ao_morrer": ["entity-death", "entity"],
}

var main: Node
var mods: Array = []
var events: Dictionary = {}
var commands: Dictionary = {}
var hook_table: Dictionary = {}   # evento -> {ctx_key -> {chave -> [cmds]}}
var vars: Dictionary = {}
var errors: Array = []
var active := false
var _budget := 0
var _funcs: Dictionary = {}


func _ready() -> void:
	_funcs = {
		"has_item": func(a: Array): return main != null and main.local_player != null and main.local_player.inv.count_of(Blocks.resolve(a[0])) >= (int(a[1]) if a.size() > 1 else 1),
		"count_item": func(a: Array): return main.local_player.inv.count_of(Blocks.resolve(a[0])) if main != null and main.local_player != null else 0,
		"random": func(_a: Array): return randf(),
		"rand": func(a: Array): return randf_range(float(a[0]), float(a[1])),
		"randint": func(a: Array): return randi_range(int(a[0]), int(a[1])),
		"chance": func(a: Array): return randf() < float(a[0]),
		"min": func(a: Array): return minf(float(a[0]), float(a[1])),
		"max": func(a: Array): return maxf(float(a[0]), float(a[1])),
		"abs": func(a: Array): return absf(float(a[0])),
		"floor": func(a: Array): return floorf(float(a[0])),
		"round": func(a: Array): return roundf(float(a[0])),
		"sqrt": func(a: Array): return sqrt(maxf(0.0, float(a[0]))),
		"len": func(a: Array): return str(a[0]).length(),
		"contains": func(a: Array): return str(a[0]).to_lower().contains(str(a[1]).to_lower()),
		"upper": func(a: Array): return str(a[0]).to_upper(),
		"lower": func(a: Array): return str(a[0]).to_lower(),
		"is_day": func(_a: Array): return main != null and main.daylight > 0.5,
		"var": func(a: Array): return vars.get(str(a[0]), 0),
		"block_at": func(a: Array): return Blocks.key_of(main.world.get_block(floori(float(a[0])), floori(float(a[1])), floori(float(a[2])))) if main != null else "air",
	}


# ------------------------------------------------------------ eventos
func has_event(ev: String) -> bool:
	return active and (events.has(ev) or hook_table.has(ev))


func run_event(event: String, ctx: Dictionary) -> void:
	if not active:
		return
	if not ctx.has("__depth"):
		_budget = 4000
		ctx["__depth"] = 0
	for entry in events.get(event, []):
		await _exec(entry, ctx)
	if hook_table.has(event):
		for ck in hook_table[event]:
			var k := str(ctx.get(ck, "")).to_lower()
			var cmds: Array = hook_table[event][ck].get(k, [])
			for c in cmds:
				_run_cmd(_interp(c, ctx), ctx)


func run_custom(cname: String, args: Array, ctx: Dictionary) -> bool:
	if not commands.has(cname):
		return false
	var depth := int(ctx.get("__depth", 0))
	if depth >= 5:
		return true
	var c2 := ctx.duplicate()
	c2["__depth"] = depth + 1
	if depth == 0:
		_budget = 4000
	c2["args"] = " ".join(PackedStringArray(args))
	for i in 9:
		c2["arg%d" % (i + 1)] = args[i] if i < args.size() else ""
	await _exec(commands[cname]["stmts"], c2)
	return true


func _exec(stmts: Array, ctx: Dictionary) -> void:
	for st in stmts:
		_budget -= 1
		if _budget <= 0:
			return
		match st["t"]:
			"run":
				_run_cmd(_interp(st["v"], ctx), ctx)
			"set":
				var v: Variant = _eval(st["expr"], ctx)
				if ctx.has(st["name"]):
					ctx[st["name"]] = v
				else:
					vars[st["name"]] = v
			"wait":
				var secs := clampf(StcExpr._num(_eval(st["expr"], ctx)), 0.0, 60.0)
				await get_tree().create_timer(secs).timeout
			"cancel":
				ctx["__cancel"] = true
			"if":
				for br in st["branches"]:
					if br["cond"] == "" or StcExpr.truthy(_eval(br["cond"], ctx)):
						await _exec(br["body"], ctx)
						break
			"repeat":
				var n := clampi(int(StcExpr._num(_eval(st["expr"], ctx))), 0, 200)
				for i in n:
					ctx["i"] = i
					await _exec(st["body"], ctx)


func _eval(expr: String, ctx: Dictionary) -> Variant:
	var merged := vars.duplicate()
	merged.merge(ctx, true)
	return StcExpr.eval(expr, merged, _funcs)


func _interp(s: String, ctx: Dictionary) -> String:
	if not s.contains("{"):
		return s
	var out := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == "{":
			var j := s.find("}", i)
			if j > i:
				out += Util.fmt_num(_eval(s.substr(i + 1, j - i - 1), ctx))
				i = j + 1
				continue
		out += ch
		i += 1
	return out


func _run_cmd(text: String, ctx: Dictionary) -> void:
	if main == null or main.commands == null:
		return
	var t := text.strip_edges().trim_prefix("/")
	if t != "":
		main.commands.run(t, ctx, true)


# ------------------------------------------------------------ carregar / descarregar
func deactivate() -> void:
	mods.clear()
	events.clear()
	commands.clear()
	hook_table.clear()
	vars.clear()
	errors.clear()
	active = false
	Blocks.reset_mods()


func activate_world(meta: Dictionary) -> void:
	var paths: Array = []
	var dir: String = WorldStore.mods_dir(meta["id"])
	for m in meta.get("mods", []):
		if m.get("enabled", true) and FileAccess.file_exists(dir + "/" + m["file"]):
			paths.append(dir + "/" + m["file"])
	meta["idmap"] = activate_paths(paths, meta.get("idmap", {}))


func collect_buffers(meta: Dictionary) -> Array:
	var out: Array = []
	var dir: String = WorldStore.mods_dir(meta["id"])
	for m in meta.get("mods", []):
		if m.get("enabled", true) and FileAccess.file_exists(dir + "/" + m["file"]):
			out.append({"name": m["file"], "bytes": FileAccess.get_file_as_bytes(dir + "/" + m["file"])})
	return out


func activate_buffers(list: Array, idmap_in: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute("user://tmp_mods")
	var paths: Array = []
	for e in list:
		var p := "user://tmp_mods/" + str(e["name"])
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f != null:
			f.store_buffer(e["bytes"])
			f.close()
			paths.append(p)
	return activate_paths(paths, idmap_in)


func activate_paths(paths: Array, idmap_in: Dictionary) -> Dictionary:
	deactivate()
	var idmap: Dictionary = {}
	for k in idmap_in:
		idmap[k] = int(idmap_in[k])
	var pend := {"drops": [], "recipes": [], "entities": []}
	for path in paths:
		var files := _read_zip(path)
		if files.is_empty() or not files.has("mod.cmd"):
			errors.append("%s: mod.cmd não encontrado (o .stc precisa ser um zip com mod.cmd)." % str(path).get_file())
			continue
		_load_one(files, str(path).get_file(), idmap, pend)
	_resolve(pend)
	Blocks.rebuild_atlas()
	active = not mods.is_empty()
	return idmap


func _read_zip(path: String) -> Dictionary:
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return {}
	var out: Dictionary = {}
	for f in zr.get_files():
		if str(f).ends_with("/"):
			continue
		out[str(f).replace("\\", "/").to_lower()] = zr.read_file(f)
	zr.close()
	var prefix := ""
	var best := 9999
	for k in out:
		if str(k).ends_with("mod.cmd") and str(k).length() < best:
			best = str(k).length()
			prefix = str(k).substr(0, str(k).length() - 7)
	if prefix == "":
		return out
	var out2: Dictionary = {}
	for k in out:
		if str(k).begins_with(prefix):
			out2[str(k).substr(prefix.length())] = out[k]
	return out2


func _info_from(files: Dictionary, label: String) -> Dictionary:
	var doc := StcDoc.new(files["mod.cmd"].get_string_from_utf8())
	var nm := doc.text(["nome", "name"], label.get_basename())
	var info := {
		"ok": true, "file": label, "name": nm, "version": doc.text(["versao", "version"], "1.0"),
		"description": doc.text(["descricao", "description", "descripion", "desc"], ""),
		"author": doc.text(["autor", "author"], ""),
		"ns": Util.slug(doc.text(["namespace", "ns"], nm)),
		"icon": null,
	}
	if info["ns"] == "":
		info["ns"] = "mod"
	if files.has("pack.png"):
		var img := Util.image_from_bytes(files["pack.png"])
		if img != null:
			info["icon"] = ImageTexture.create_from_image(img)
	return info


func inspect_path(path: String) -> Dictionary:
	var files := _read_zip(path)
	if files.is_empty() or not files.has("mod.cmd"):
		return {"ok": false, "error": "Arquivo inválido: precisa ser um .stc (zip) com mod.cmd."}
	return _info_from(files, path.get_file())


func _paths_in(files: Dictionary, dirs: Array) -> Array:
	var out: Array = []
	for k in files:
		var ks: String = k
		for d in dirs:
			if ks.begins_with(d) and (ks.ends_with(".txt") or ks.ends_with(".cmd") or ks.ends_with(".stc")):
				out.append(ks)
				break
	out.sort()
	return out


func _txt(files: Dictionary, path: String) -> String:
	return (files[path] as PackedByteArray).get_string_from_utf8()


func _alloc(key: String, is_block: bool, idmap: Dictionary) -> int:
	if idmap.has(key):
		var existing: int = idmap[key]
		if not Blocks.defs.has(existing):
			return existing
	var used: Dictionary = {}
	for k in idmap:
		used[int(idmap[k])] = true
	var lo := Blocks.MOD_BLOCK_FIRST if is_block else Blocks.MOD_ITEM_FIRST
	var hi := Blocks.MOD_BLOCK_LAST if is_block else 9999
	for id in range(lo, hi + 1):
		if not used.has(id) and not Blocks.defs.has(id):
			idmap[key] = id
			return id
	return -1


func _key(rawid: String, ns: String, nm: String) -> String:
	var k := rawid.strip_edges().to_lower()
	if k == "":
		return ns + ":" + Util.slug(nm)
	if not k.contains(":"):
		return ns + ":" + k
	return k


func _find_image(files: Dictionary, ref: String) -> Image:
	if ref == "":
		return null
	var r := ref.replace("\\", "/").to_lower().strip_edges()
	if r.begins_with("./"):
		r = r.substr(2)
	var cands: Array = [r, r + ".png"]
	for pre in ["textura/", "texturas/", "textures/", "texture/"]:
		cands.append(pre + r)
		cands.append(pre + r + ".png")
	for c in cands:
		if files.has(c):
			return Util.image_from_bytes(files[c])
	return null


func _tile_for(files: Dictionary, ref: String, ns: String) -> String:
	if ref == "":
		return ""
	var r := ref.strip_edges().to_lower()
	var base := r.trim_prefix("star:")
	if Blocks.TILE_NAMES.has(base) and _find_image(files, ref) == null:
		return base
	var img := _find_image(files, ref)
	if img == null:
		return ""
	var tname := ns + "/" + r.replace("\\", "/")
	Blocks.add_mod_tile(tname, img)
	return tname


func _missing_tile(ns: String) -> String:
	var tname := ns + "/_faltando"
	if not Blocks.mod_tiles.has(tname):
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				img.set_pixel(x, y, Color(0.9, 0.1, 0.9) if ((x / 8) + (y / 8)) % 2 == 0 else Color(0.1, 0.1, 0.1))
		Blocks.add_mod_tile(tname, img)
	return tname


func _placeholder_icon() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(2, 14):
		for x in range(2, 14):
			img.set_pixel(x, y, Color(0.9, 0.1, 0.9) if ((x / 6) + (y / 6)) % 2 == 0 else Color(0.15, 0.15, 0.15))
	return img


func _add_hooks(doc: StcDoc, key: String) -> void:
	for hk in HOOKS:
		var cmds := doc.all([hk])
		if cmds.is_empty():
			continue
		var ev: String = HOOKS[hk][0]
		var ck: String = HOOKS[hk][1]
		if not hook_table.has(ev):
			hook_table[ev] = {}
		if not hook_table[ev].has(ck):
			hook_table[ev][ck] = {}
		hook_table[ev][ck][key] = cmds


func _load_one(files: Dictionary, label: String, idmap: Dictionary, pend: Dictionary) -> void:
	var info := _info_from(files, label)
	var ns: String = info["ns"]
	mods.append(info)
	for p in _paths_in(files, ITEM_DIRS):
		_reg_item(files, ns, StcDoc.new(_txt(files, p)), idmap, label, p)
	for p in _paths_in(files, BLOCK_DIRS):
		_reg_block(files, ns, StcDoc.new(_txt(files, p)), idmap, label, p, pend)
	for p in _paths_in(files, ENTITY_DIRS):
		_reg_entity(files, ns, StcDoc.new(_txt(files, p)), label, p, pend)
	for p in _paths_in(files, RECIPE_DIRS):
		pend["recipes"].append({"doc": StcDoc.new(_txt(files, p)), "ns": ns, "label": label, "path": p})
	for p in _paths_in(files, SCRIPT_DIRS):
		var parsed := StcScript.parse(_txt(files, p))
		for ev in parsed["events"]:
			if not events.has(ev):
				events[ev] = []
			for stmts in parsed["events"][ev]:
				events[ev].append(stmts)
		for cn in parsed["commands"]:
			commands[cn] = parsed["commands"][cn]


func _reg_item(files: Dictionary, ns: String, doc: StcDoc, idmap: Dictionary, label: String, path: String) -> void:
	var nm := doc.text(["nome", "name"], "Item")
	var key := _key(doc.text(["id"], ""), ns, nm)
	var id := _alloc(key, false, idmap)
	if id < 0:
		errors.append("%s: sem IDs livres para %s" % [label, key])
		return
	var dur := int(doc.num(["durabilidade", "durability"], 0))
	var d := {"name": nm, "block": false, "stack": int(doc.num(["empilhavel", "stack", "max_stack"], 1 if dur > 0 else 64)),
		"shape": "tex", "color": Color(0.8, 0.8, 0.85)}
	var img := _find_image(files, doc.text(["textura", "texture", "icone", "icon"], ""))
	if img == null:
		errors.append("%s (%s): textura do item não encontrada, usando placeholder." % [label, path])
		img = _placeholder_icon()
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	d["icon_tex"] = ImageTexture.create_from_image(img)
	if dur > 0:
		d["dur"] = dur
	var kind := String(doc.text(["ferramenta", "tool"], "")).to_lower()
	if TOOL_KINDS.has(Util.strip_accents(kind)):
		d["tool_kind"] = TOOL_KINDS[Util.strip_accents(kind)]
		d["tool_tier"] = int(doc.num(["nivel", "tier"], 0))
		if not d.has("dur"):
			d["dur"] = 250
	if doc.has_any(["velocidade", "speed", "velocidade_quebra"]):
		d["mine_speed"] = doc.num(["velocidade", "speed", "velocidade_quebra"], 2.0)
	if doc.has_any(["dano", "damage", "attack"]):
		d["attack"] = doc.num(["dano", "damage", "attack"], 1.0)
	if doc.has_any(["quebra_blocos", "quebra_bloco", "can_break"]):
		d["can_break"] = doc.flag(["quebra_blocos", "quebra_bloco", "can_break"], true)
	d["tags"] = doc.list(["tags", "tag"])
	if doc.has_any(["comida", "food"]):
		Blocks.food[id] = int(doc.num(["comida", "food"], 2))
	Blocks.define_mod_entry(id, key, d)
	_add_hooks(doc, key)


func _reg_block(files: Dictionary, ns: String, doc: StcDoc, idmap: Dictionary, label: String, path: String, pend: Dictionary) -> void:
	var nm := doc.text(["nome", "name"], "Bloco")
	var key := _key(doc.text(["id"], ""), ns, nm)
	var id := _alloc(key, true, idmap)
	if id < 0:
		errors.append("%s: sem IDs de bloco livres (21-99) para %s" % [label, key])
		return
	var all := _tile_for(files, doc.text(["textura", "texture"], ""), ns)
	var side := _tile_for(files, doc.text(["textura_lado", "lado", "side"], ""), ns)
	var top := _tile_for(files, doc.text(["textura_topo", "topo", "top"], ""), ns)
	var bot := _tile_for(files, doc.text(["textura_baixo", "baixo", "fundo", "bottom"], ""), ns)
	if all == "" and side == "":
		all = _missing_tile(ns)
		errors.append("%s (%s): textura do bloco não encontrada." % [label, path])
	if side == "":
		side = all
	if top == "":
		top = all if all != "" else side
	if bot == "":
		bot = all if all != "" else side
	var kind := Util.strip_accents(String(doc.text(["ferramenta", "tool"], "")).to_lower())
	var d := {
		"name": nm, "hard": doc.num(["dureza", "hardness"], 1.5), "tool": TOOL_KINDS.get(kind, -1),
		"min_tier": int(doc.num(["nivel", "tier"], -1)), "drop": id, "drop_n": int(doc.num(["drop_quantidade", "drop_n"], 1)),
		"tiles": [top, side, bot], "solid": doc.flag(["solido", "solid"], true), "opaque": doc.flag(["opaco", "opaque"], true),
		"stack": 64, "block": true, "icon_tile": side, "light": int(doc.num(["luz", "light"], 0)),
	}
	if doc.has_any(["drop", "solta"]):
		pend["drops"].append({"id": id, "ref": doc.text(["drop", "solta"], ""), "ns": ns})
	Blocks.define_mod_entry(id, key, d)
	_add_hooks(doc, key)


func _parse_model(text: String) -> Dictionary:
	var parts: Array = []
	var tex_size := Vector2(0, 0)
	for raw in text.replace("\r", "").split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with("//"):
			continue
		var ci := line.find(":")
		if ci < 0:
			continue
		var k := Util.strip_accents(line.substr(0, ci)).replace("-", "_")
		var v := line.substr(ci + 1).strip_edges()
		if k in ["textura_tamanho", "tamanho_textura", "tex_size", "texture_size"]:
			var nums := v.replace(",", " ").split(" ", false)
			if nums.size() >= 2:
				tex_size = Vector2(float(nums[0]), float(nums[1]))
		elif k in ["parte", "part", "caixa", "box"]:
			var segs := v.split("|")
			var part := {"name": StcDoc.clean(segs[0]), "size": Vector3(4, 4, 4), "pos": Vector3.ZERO,
				"uv": Vector2.ZERO, "whole": false, "anim": "", "pivot": Vector3.INF, "color": Color.WHITE}
			for i in range(1, segs.size()):
				var si := String(segs[i]).find(":")
				if si < 0:
					continue
				var sk := Util.strip_accents(String(segs[i]).substr(0, si).strip_edges())
				var sv := String(segs[i]).substr(si + 1).strip_edges()
				var n3 := sv.replace(",", " ").split(" ", false)
				match sk:
					"tam", "size", "tamanho":
						if n3.size() >= 3:
							part["size"] = Vector3(float(n3[0]), float(n3[1]), float(n3[2]))
					"pos", "posicao":
						if n3.size() >= 3:
							part["pos"] = Vector3(float(n3[0]), float(n3[1]), float(n3[2]))
					"pivo", "pivot":
						if n3.size() >= 3:
							part["pivot"] = Vector3(float(n3[0]), float(n3[1]), float(n3[2]))
					"uv":
						if sv.to_lower() in ["todos", "all", "inteira"]:
							part["whole"] = true
						elif n3.size() >= 2:
							part["uv"] = Vector2(float(n3[0]), float(n3[1]))
					"anim", "anima":
						part["anim"] = Util.strip_accents(StcDoc.clean(sv).to_lower())
					"cor", "color":
						part["color"] = Color.from_string(StcDoc.clean(sv), Color.WHITE)
			parts.append(part)
	return {"parts": parts, "tex_size": tex_size}


func _reg_entity(files: Dictionary, ns: String, doc: StcDoc, label: String, path: String, pend: Dictionary) -> void:
	var nm := doc.text(["nome", "name"], "Entidade")
	var key := _key(doc.text(["id"], ""), ns, nm)
	var hostile := doc.flag(["hostil", "hostile"], false)
	var beh_raw := Util.strip_accents(doc.text(["comportamento", "behavior"], "melee" if hostile else "passive").to_lower())
	var w := doc.num(["largura", "width"], 0.6)
	var h := doc.num(["altura", "height"], 1.8)
	var d := {
		"name": nm, "hp": doc.num(["vida", "hp", "health"], 20.0), "speed": doc.num(["velocidade", "speed"], 2.5),
		"hostile": hostile, "w": minf(w * 0.5, h * 0.5), "h": h, "behavior": BEHAVIORS.get(beh_raw, "passive"),
		"dmg": doc.num(["dano", "damage"], 3.0), "burns": doc.flag(["queima_de_dia", "burns"], false),
		"spawn": Util.strip_accents(doc.text(["spawn", "aparece"], "nunca").to_lower()),
		"parts": [], "tex": null, "tex_size": Vector2(16, 16), "color": Color.from_string(doc.text(["cor", "color"], "#7fbf7f"), Color(0.5, 0.75, 0.5)),
		"drops": [], "key": key,
	}
	var img := _find_image(files, doc.text(["textura", "texture"], ""))
	if img != null:
		d["tex"] = ImageTexture.create_from_image(img)
		d["tex_size"] = Vector2(img.get_width(), img.get_height())
	var mref := doc.text(["modelo", "model"], "")
	if mref != "":
		var r := mref.replace("\\", "/").to_lower()
		var cands: Array = [r, r + ".txt"]
		for pre in MODEL_DIRS:
			cands.append(pre + r)
			cands.append(pre + r + ".txt")
		for c in cands:
			if files.has(c):
				var mdl := _parse_model(_txt(files, c))
				d["parts"] = mdl["parts"]
				if mdl["tex_size"] != Vector2.ZERO:
					d["tex_size"] = mdl["tex_size"]
				break
		if d["parts"].is_empty():
			errors.append("%s (%s): modelo '%s' não encontrado, usando cubo." % [label, path, mref])
	if d["parts"].is_empty():
		d["parts"] = [{"name": "corpo", "size": Vector3(w * 16.0, h * 16.0, w * 16.0), "pos": Vector3(0, h * 8.0, 0),
			"uv": Vector2.ZERO, "whole": true, "anim": "", "pivot": Vector3.INF, "color": Color.WHITE}]
	Blocks.mob_defs[key] = d
	pend["entities"].append({"key": key, "drops": doc.all(["drop", "solta"]), "ns": ns})
	_add_hooks(doc, key)


func _res(ref: String, ns: String) -> int:
	var r := Blocks.resolve(ref)
	if r < 0 and not ref.contains(":"):
		r = Blocks.resolve(ns + ":" + ref)
	return r


func _resolve(pend: Dictionary) -> void:
	for p in pend["drops"]:
		var ref: String = str(p["ref"]).strip_edges().to_lower()
		var id: int = p["id"]
		if ref in ["nenhum", "none", "nada", "ar", "air"]:
			Blocks.defs[id]["drop"] = 0
		else:
			var rid := _res(ref, p["ns"])
			if rid >= 0:
				Blocks.defs[id]["drop"] = rid
			else:
				errors.append("%s: drop '%s' não existe." % [Blocks.key_of(id), ref])
	for e in pend["entities"]:
		var arr: Array = []
		for line in e["drops"]:
			var tk := str(line).split(" ", false)
			if tk.is_empty():
				continue
			var did := _res(tk[0], e["ns"])
			if did < 0:
				errors.append("%s: drop '%s' não existe." % [e["key"], tk[0]])
				continue
			var mn := int(tk[1]) if tk.size() > 1 else 1
			var mx := int(tk[2]) if tk.size() > 2 else mn
			var ch := float(tk[3]) if tk.size() > 3 else 1.0
			arr.append([did, mn, mx, ch])
		Blocks.mob_defs[e["key"]]["drops"] = arr
	for r in pend["recipes"]:
		_reg_recipe(r)


func _reg_recipe(r: Dictionary) -> void:
	var doc: StcDoc = r["doc"]
	var ns: String = r["ns"]
	var out_id := _res(doc.text(["resultado", "result", "output", "saida"], ""), ns)
	if out_id < 0:
		errors.append("%s (%s): resultado da receita inválido." % [r["label"], r["path"]])
		return
	var counts: Dictionary = {}
	var rows: Array = []
	if not doc.grid.is_empty():
		var sym: Dictionary = {}
		for pr in doc.pairs:
			if String(pr[0]).length() == 1:
				sym[pr[0]] = StcDoc.clean(pr[1])
		for row in doc.grid:
			var names: Array = []
			for cell in row:
				var c := String(cell).to_lower()
				if c == "" or c == " ":
					names.append("-")
					continue
				var rid := _res(str(sym.get(c, c)), ns)
				if rid < 0:
					errors.append("%s (%s): ingrediente '%s' inválido." % [r["label"], r["path"], c])
					return
				counts[rid] = int(counts.get(rid, 0)) + 1
				names.append(Blocks.name_of(rid))
			rows.append(names)
	else:
		for ing in doc.list(["ingredientes", "ingredients"]):
			var parts := str(ing).split("*")
			var rid2 := _res(parts[0], ns)
			if rid2 < 0:
				errors.append("%s (%s): ingrediente '%s' inválido." % [r["label"], r["path"], parts[0]])
				return
			counts[rid2] = int(counts.get(rid2, 0)) + (int(parts[1]) if parts.size() > 1 else 1)
	if counts.is_empty():
		return
	var st_name := Util.strip_accents(doc.text(["estacao", "station", "local"], "bancada" if not doc.grid.is_empty() else "nenhuma").to_lower())
	var st := 0
	if st_name in ["bancada", "mesa", "table", "workbench", "crafting"]:
		st = 1
	elif st_name in ["fornalha", "forno", "furnace"]:
		st = 2
	Blocks.recipes.append({"out": out_id, "n": int(doc.num(["quantidade", "count", "qtd"], 1)), "in": counts, "st": st, "mod": true, "grid": rows})


# ------------------------------------------------------------ instalar / remover (por mundo)
func list_installed(meta: Dictionary) -> Array:
	var out: Array = []
	var dir: String = WorldStore.mods_dir(meta["id"])
	for m in meta.get("mods", []):
		var info := inspect_path(dir + "/" + m["file"])
		if not info.get("ok", false):
			info = {"ok": false, "name": m["file"], "version": "?", "description": info.get("error", "arquivo ausente"), "icon": null}
		info["file"] = m["file"]
		info["enabled"] = m.get("enabled", true)
		out.append(info)
	return out


func install(meta: Dictionary, src_path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		return {"ok": false, "error": "Não consegui ler o arquivo (permissão de armazenamento?)."}
	DirAccess.make_dir_recursive_absolute("user://tmp_mods")
	var tmp := "user://tmp_mods/_inspect.stc"
	var tf := FileAccess.open(tmp, FileAccess.WRITE)
	if tf == null:
		return {"ok": false, "error": "Erro ao preparar o arquivo."}
	tf.store_buffer(bytes)
	tf.close()
	var info := inspect_path(tmp)
	if not info.get("ok", false):
		return info
	var dir: String = WorldStore.mods_dir(meta["id"])
	DirAccess.make_dir_recursive_absolute(dir)
	var fname := src_path.get_file()
	if not fname.to_lower().ends_with(".stc"):
		fname = fname.get_basename() + ".stc"
	var n := 1
	var base := fname.get_basename()
	while FileAccess.file_exists(dir + "/" + fname):
		n += 1
		fname = "%s_%d.stc" % [base, n]
	var f := FileAccess.open(dir + "/" + fname, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Erro ao gravar o mod."}
	f.store_buffer(bytes)
	f.close()
	if not meta.has("mods"):
		meta["mods"] = []
	meta["mods"].append({"file": fname, "enabled": true})
	WorldStore.save_meta(meta)
	return {"ok": true, "file": fname, "name": info["name"]}


func remove(meta: Dictionary, file: String) -> void:
	var dir: String = WorldStore.mods_dir(meta["id"])
	DirAccess.remove_absolute(dir + "/" + file)
	var keep: Array = []
	for m in meta.get("mods", []):
		if m["file"] != file:
			keep.append(m)
	meta["mods"] = keep
	WorldStore.save_meta(meta)


func set_enabled(meta: Dictionary, file: String, on: bool) -> void:
	for m in meta.get("mods", []):
		if m["file"] == file:
			m["enabled"] = on
	WorldStore.save_meta(meta)
