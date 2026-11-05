class_name CommandRunner
extends RefCounted
## Comandos de chat e de scripts (/give, /fill, /title, /say, /kill ...).

var main: Node

const HELP := "gm, time, give, clear, tp, spawn, setworldspawn, heal, feed, kill, seed, summon, say, me, title, fill, setblock, effect, particle, gamerule, list, mods, itens, ajuda"


func _init(m: Node) -> void:
	main = m


func _out(t: String) -> void:
	main.chat_ui.system(t)


func tokenize(text: String) -> Array:
	var out: Array = []
	var cur := ""
	var inq := false
	for ch in text:
		if ch == "\"":
			inq = not inq
		elif ch == " " and not inq:
			if cur != "":
				out.append(cur)
				cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


func _coord(tok: String, base: float) -> float:
	if tok.begins_with("~"):
		var rest := tok.substr(1)
		return base + (float(rest) if rest != "" else 0.0)
	return float(tok)


func _pl() -> Player:
	return main.local_player


## Retorna lista de alvos: Player e/ou Mob.
func _targets(sel: String) -> Array:
	var out: Array = []
	var s := sel.to_lower()
	if s == "@s" or s == "@p" or s == "@a" or s.begins_with("@s[") or s.begins_with("@p[") or s.begins_with("@a["):
		if _pl() != null:
			out.append(_pl())
	elif s.begins_with("@e"):
		var typ := ""
		var rad := 1e9
		if s.contains("["):
			for kv in s.substr(s.find("[") + 1).trim_suffix("]").split(","):
				var p := String(kv).split("=")
				if p.size() == 2 and p[0] == "type":
					typ = p[1].trim_prefix("star:")
				elif p.size() == 2 and p[0] in ["r", "distance"]:
					rad = float(p[1])
		for m in main.mobs.values():
			if (typ == "" or m.kind == typ or m.kind.ends_with(":" + typ) or m.kind == "star:" + typ) and _pl() != null and m.global_position.distance_to(_pl().global_position) <= rad:
				out.append(m)
	return out


func run(text: String, ctx: Dictionary = {}, from_script := false) -> bool:
	var t := tokenize(text.strip_edges().trim_prefix("/"))
	if t.is_empty():
		return false
	var cmd: String = String(t[0]).to_lower()
	var a: Array = t.slice(1)
	var p := _pl()
	if p == null:
		return false
	match cmd:
		"ajuda", "help":
			var extra := ""
			for c in ModManager.commands:
				extra += ", " + c
			_out("Comandos: " + HELP + extra)
		"gm", "gamemode":
			if a.is_empty():
				_out("Uso: /gm c|s")
				return true
			var v: String = String(a[a.size() - 1]).to_lower()
			main.set_creative(v.begins_with("c") or v == "1")
			_out("Modo: " + ("Criativo" if main.creative_mode else "Sobrevivência"))
		"time":
			_time(a)
		"give":
			var tgt := 0
			if not a.is_empty() and String(a[0]).begins_with("@"):
				tgt = 1
			if a.size() <= tgt:
				_out("Uso: /give [@s] <id> [qtd]  (ex.: star:dirt 10)")
				return true
			var id := Blocks.resolve(a[tgt])
			if id < 0:
				_out("Item desconhecido: %s. Use /itens" % a[tgt])
				return true
			var n := int(a[tgt + 1]) if a.size() > tgt + 1 else 1
			p.inv.add(id, clampi(n, 1, 2304))
			_out("Recebeu %s x%d" % [Blocks.name_of(id), n])
		"clear":
			p.inv.clear()
			_out("Inventário limpo.")
		"tp":
			var o := 1 if (not a.is_empty() and String(a[0]).begins_with("@")) else 0
			if a.size() >= o + 3:
				var pos := p.global_position
				p.teleport(Vector3(_coord(a[o], pos.x), _coord(a[o + 1], pos.y), _coord(a[o + 2], pos.z)))
			else:
				_out("Uso: /tp x y z  (aceita ~)")
		"spawn":
			p.teleport(main.spawn_point)
		"setworldspawn", "spawnpoint":
			main.spawn_point = p.global_position
			_out("Spawn definido aqui.")
		"heal":
			p.health = 20.0
			p.hunger = 20.0
		"feed":
			p.hunger = 20.0
		"kill":
			var tg: Array = _targets(a[0]) if not a.is_empty() else [p]
			for e in tg:
				if e is Player:
					var was: bool = p.creative
					p.creative = false
					p.take_damage(9999.0, Vector3.ZERO, 0, true, "kill")
					p.creative = was
				elif e is Mob:
					e.hp = 0.0
					main.mob_died(e)
		"seed":
			_out("Semente: %d" % main.world.seed_val)
		"summon":
			if a.is_empty():
				_out("Uso: /summon <mob> [x y z]")
				return true
			var kind := _mob_kind(String(a[0]))
			if kind == "":
				_out("Mob desconhecido. Mobs: " + ", ".join(PackedStringArray(main.all_mob_kinds())))
				return true
			var pos2 := p.global_position + (-p.head.global_transform.basis.z) * 3.0 + Vector3(0, 1, 0)
			if a.size() >= 4:
				pos2 = Vector3(_coord(a[1], p.global_position.x), _coord(a[2], p.global_position.y), _coord(a[3], p.global_position.z))
			if not main.online or main.is_host:
				main.spawn_mob(kind, pos2)
		"say":
			var msg := " ".join(PackedStringArray(a))
			main.broadcast_system("[Servidor] " + msg)
		"me":
			main.send_chat_raw("* %s %s" % [Settings.player_name, " ".join(PackedStringArray(a))])
		"title":
			_title(a)
		"fill":
			_fill(a)
		"setblock":
			if a.size() < 4:
				_out("Uso: /setblock x y z <bloco>")
				return true
			var bid := _block_id(a[3])
			if bid < 0:
				_out("Bloco desconhecido: " + a[3])
				return true
			var pp := p.global_position
			main.set_block_net(floori(_coord(a[0], pp.x)), floori(_coord(a[1], pp.y)), floori(_coord(a[2], pp.z)), bid)
		"effect":
			if a.size() >= 2:
				var o2 := 1 if String(a[0]).begins_with("@") else 0
				var secs := float(a[o2 + 1]) if a.size() > o2 + 1 else 30.0
				p.effects[String(a[o2]).to_lower()] = secs
				_out("Efeito %s por %ds" % [a[o2], int(secs)])
			else:
				_out("Uso: /effect @s speed|jump|regeneration|resistance|slowness [segundos]")
		"particle":
			if not a.is_empty():
				var pt := p.global_position + Vector3(0, 1.0, 0) + (-p.head.global_transform.basis.z) * 1.5
				match String(a[0]):
					"crit": Fx.crit(main.entities, pt)
					"hurt": Fx.hurt(main.entities, pt)
					_: Fx.burst(main.entities, pt, Color(1, 0.8, 0.3), 16, 3.0)
		"gamerule":
			if a.size() >= 2:
				main.set_rule(String(a[0]), String(a[1]).to_lower() in ["true", "1", "sim", "on"])
			else:
				_out("Regras: " + ", ".join(PackedStringArray(main.rules.keys())))
		"list":
			var names: Array = [Settings.player_name]
			for r in main.remotes.values():
				names.append(r.pname)
			_out("Jogadores: " + ", ".join(PackedStringArray(names)))
		"mods":
			var ml: Array = []
			for m in ModManager.mods:
				ml.append("%s v%s" % [m["name"], m["version"]])
			_out("Mods ativos: " + (", ".join(PackedStringArray(ml)) if not ml.is_empty() else "nenhum"))
		"itens", "items", "blocks":
			var s := ""
			for id in Blocks.defs:
				s += "%s, " % Blocks.key_of(id)
			_out(s.substr(0, 900))
		_:
			if ModManager.commands.has(cmd):
				var c2 := main.script_ctx(ctx)
				ModManager.run_custom(cmd, a, c2)
				return true
			_out("Comando desconhecido: /%s  (veja /ajuda)" % cmd)
			return false
	return true


func _block_id(ref: String) -> int:
	if ref.to_lower() in ["air", "ar", "star:air"]:
		return 0
	var id := Blocks.resolve(ref)
	return id if (id == 0 or Blocks.is_block(id)) else -1


func _mob_kind(ref: String) -> String:
	var r := ref.to_lower()
	if Mob.TYPES.has(r):
		return r
	if Mob.TYPES.has(r.trim_prefix("star:")):
		return r.trim_prefix("star:")
	if Blocks.mob_defs.has(r):
		return r
	return ""


func _time(a: Array) -> void:
	if main.online and not main.is_host:
		_out("Só o anfitrião muda a hora.")
		return
	if a.is_empty():
		_out("Uso: /time set day|night|<0-24000> | add <n>")
		return
	var op := String(a[0]).to_lower()
	var arg := String(a[1]).to_lower() if a.size() > 1 else ""
	if op in ["set", "dia", "day", "noite", "night"]:
		var v := arg if op == "set" else op
		match v:
			"day", "dia":
				main.time_of_day = 0.3
			"night", "noite":
				main.time_of_day = 0.78
			"noon", "meio-dia":
				main.time_of_day = 0.25
			_:
				var f := float(v)
				main.time_of_day = fposmod(f / 24000.0 if f > 1.0 else f, 1.0)
	elif op == "add":
		main.time_of_day = fposmod(main.time_of_day + float(arg) / 24000.0, 1.0)
	else:
		main.time_of_day = fposmod(float(op) / 24000.0 if float(op) > 1.0 else float(op), 1.0)
	if main.online:
		main.r_time.rpc(main.time_of_day)
	_out("Hora ajustada.")


func _title(a: Array) -> void:
	var o := 1 if (not a.is_empty() and String(a[0]).begins_with("@")) else 0
	if a.size() <= o:
		_out("Uso: /title @s title|subtitle|actionbar|clear <texto>")
		return
	var mode := String(a[o]).to_lower()
	var txt := " ".join(PackedStringArray(a.slice(o + 1)))
	match mode:
		"title":
			main.hud.show_title(txt, "")
		"subtitle":
			main.hud.show_title("", txt)
		"actionbar":
			main.hud.show_action(txt)
		"clear":
			main.hud.clear_title()
		_:
			main.hud.show_title(" ".join(PackedStringArray(a.slice(o))), "")


func _fill(a: Array) -> void:
	if a.size() < 7:
		_out("Uso: /fill x1 y1 z1 x2 y2 z2 <bloco> [replace <alvo>|hollow]")
		return
	var pp := _pl().global_position
	var x1 := floori(_coord(a[0], pp.x))
	var y1 := floori(_coord(a[1], pp.y))
	var z1 := floori(_coord(a[2], pp.z))
	var x2 := floori(_coord(a[3], pp.x))
	var y2 := floori(_coord(a[4], pp.y))
	var z2 := floori(_coord(a[5], pp.z))
	var bid := _block_id(a[6])
	if bid < 0:
		_out("Bloco desconhecido: " + a[6])
		return
	var mode := String(a[7]).to_lower() if a.size() > 7 else ""
	var target := -1
	if mode == "replace" and a.size() > 8:
		target = _block_id(a[8])
	var minx := mini(x1, x2)
	var maxx := maxi(x1, x2)
	var miny := clampi(mini(y1, y2), 1, World.CH - 1)
	var maxy := clampi(maxi(y1, y2), 1, World.CH - 1)
	var minz := mini(z1, z2)
	var maxz := maxi(z1, z2)
	var vol := (maxx - minx + 1) * (maxy - miny + 1) * (maxz - minz + 1)
	if vol > 32768:
		_out("Área grande demais (%d blocos, máx. 32768)." % vol)
		return
	var n := 0
	for x in range(minx, maxx + 1):
		for y in range(miny, maxy + 1):
			for z in range(minz, maxz + 1):
				if mode == "hollow" and x > minx and x < maxx and y > miny and y < maxy and z > minz and z < maxz:
					continue
				var cur: int = main.world.get_block(x, y, z)
				if cur == Blocks.BEDROCK:
					continue
				if target >= 0 and cur != target:
					continue
				main.set_block_net(x, y, z, bid)
				n += 1
	_out("%d blocos alterados." % n)
