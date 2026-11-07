class_name Commands
extends RefCounted
## Comandos de chat (/give, /fill, /title ...). Só funcionam se "Comandos" estiver ativado
## nas regras do mundo/servidor (e, em servidores, só para o admin "X EDUHH X").

const MAX_FILL := 30000

var main: Node


func tokenize(text: String) -> Array:
	var out: Array = []
	var cur := ""
	var in_q := false
	for ch in text:
		if ch == "\"":
			in_q = not in_q
			continue
		if ch == " " and not in_q:
			if cur != "":
				out.append(cur)
				cur = ""
			continue
		cur += ch
	if cur != "":
		out.append(cur)
	return out


func say(msg: String) -> void:
	main.chat_ui.system(msg)


## Quem pode usar comandos agora?
func permission_error() -> String:
	if not bool(main.rules.get("commands", true)):
		return "Comandos estão desativados neste mundo/servidor."
	if main.world_kind != "world" and not Settings.is_admin_name(Settings.player_name):
		return "Só o administrador (%s) pode usar comandos aqui." % Settings.ADMIN_NICK
	return ""


func execute(text: String, force := false) -> void:
	text = text.strip_edges()
	if text.begins_with("/"):
		text = text.substr(1)
	var toks := tokenize(text)
	if toks.is_empty() or main.local_player == null:
		return
	var cmd := String(toks[0]).to_lower()
	var args: Array = toks.slice(1)
	if not force:
		var err := permission_error()
		if err != "":
			say(err)
			return
	if Mods.script_commands.has(cmd):
		var sc: Dictionary = Mods.script_commands[cmd]
		if String(sc["perm"]) in ["admin", "adm", "dono"] and not force and not Settings.is_admin_name(Settings.player_name) and main.world_kind != "world":
			say("Só administradores podem usar /%s." % cmd)
			return
		Mods.run_command_script(cmd, args, main.script_ctx({}))
		return
	match cmd:
		"ajuda", "help":
			_help()
		"gm", "gamemode":
			_gm(args)
		"time":
			_time(args)
		"give":
			_give(args)
		"clear":
			_clear(args)
		"itens", "items":
			_items(args)
		"tp", "teleport":
			_tp(args)
		"spawn":
			main.local_player.teleport(main.spawn_point)
		"setworldspawn", "setspawn":
			main.spawn_point = main.local_player.global_position
			say("Spawn definido aqui.")
		"heal":
			main.local_player.health = 20.0
			main.local_player.hunger = 20.0
			say("Vida e fome restauradas.")
		"feed":
			main.local_player.hunger = 20.0
		"kill":
			_kill(args)
		"seed":
			say("Semente: %d" % main.world.seed_val)
		"mob", "summon":
			_summon(args)
		"title":
			_title(args)
		"say":
			if args.is_empty():
				say("Uso: /say <mensagem>")
			else:
				main.send_chat_as("Servidor", " ".join(args))
		"me":
			if not args.is_empty():
				main.send_chat_as("*", "%s %s" % [Settings.player_name, " ".join(args)])
		"fill":
			_fill(args)
		"setblock":
			_setblock(args)
		"gamerule":
			_gamerule(args)
		"particle":
			_particle(args)
		"pos":
			var gp: Vector3 = main.local_player.global_position
			say("Posição: %.1f %.1f %.1f" % [gp.x, gp.y, gp.z])
		"mods":
			_mods()
		_:
			say("Comando desconhecido: /%s  (use /ajuda)" % cmd)


func _help() -> void:
	var s := "/gm c|s  /time dia|noite|N  /give <id> [qtd]  /clear [id]  /itens [filtro]  /tp x y z  /spawn  /setworldspawn  /heal  /feed  /kill [@s|@e]  /seed  /mob <tipo> [x y z]  /title @s title|subtitle|actionbar <texto>  /say <msg>  /me <msg>  /fill x1 y1 z1 x2 y2 z2 <bloco> [replace <bloco>|destroy]  /setblock x y z <bloco>  /gamerule <regra> <true|false>  /particle <tipo>  /pos  /mods"
	say(s)
	if not Mods.script_commands.is_empty():
		var names: Array = []
		for k in Mods.script_commands:
			names.append("/" + String(k))
		say("Comandos de mods: " + ", ".join(names))


func _gm(args: Array) -> void:
	if args.is_empty():
		say("Uso: /gm c|s")
		return
	var a := String(args[0]).to_lower()
	main.set_creative(a.begins_with("c") or a == "1")


func _time(args: Array) -> void:
	if main.online and not main.is_host:
		say("Só o anfitrião muda a hora.")
		return
	if args.is_empty():
		say("Uso: /time dia|noite|<0-1>|add <N>")
		return
	var a := String(args[0]).to_lower()
	var t: float = main.time_of_day
	if a == "set" and args.size() > 1:
		a = String(args[1]).to_lower()
	if a == "add" and args.size() > 1:
		t = fposmod(t + float(String(args[1])) / 24000.0, 1.0)
	elif a == "dia" or a == "day":
		t = 0.3
	elif a == "noite" or a == "night":
		t = 0.78
	elif a.is_valid_float():
		t = fposmod(float(a), 1.0)
	else:
		say("Hora inválida.")
		return
	main.set_time(t)
	say("Hora ajustada.")


func _resolve_item(tok: String) -> int:
	return Blocks.id_from_string(tok)


func _give(args: Array) -> void:
	var a: Array = args.duplicate()
	if not a.is_empty() and String(a[0]).begins_with("@"):
		a.pop_front()
	if a.is_empty():
		say("Uso: /give <id> [quantidade]  (veja /itens)")
		return
	var id := _resolve_item(String(a[0]))
	if id == 0:
		say("Item desconhecido: %s  (use /itens)" % String(a[0]))
		return
	var n := 1
	if a.size() > 1 and String(a[1]).is_valid_int():
		n = clampi(int(String(a[1])), 1, 2304)
	var left: int = main.local_player.inv.add(id, n)
	if left > 0:
		say("Inventário cheio (%d não couberam)." % left)
	say("Recebeu %s x%d" % [Blocks.name_of(id), n - left])


func _clear(args: Array) -> void:
	var a: Array = args.duplicate()
	if not a.is_empty() and String(a[0]).begins_with("@"):
		a.pop_front()
	var inv: Inventory = main.local_player.inv
	if a.is_empty():
		inv.clear()
		say("Inventário limpo.")
		return
	var id := _resolve_item(String(a[0]))
	if id == 0:
		say("Item desconhecido.")
		return
	var n := inv.count_of(id)
	inv.remove_id(id, n)
	say("Removidos %d de %s." % [n, Blocks.name_of(id)])


func _items(args: Array) -> void:
	var filt := ""
	if not args.is_empty():
		filt = String(args[0]).to_lower()
	var ids: Array = Blocks.defs.keys()
	ids.sort()
	var s := ""
	for k in ids:
		var id: int = k
		var sid := Blocks.string_of(id)
		var nm := Blocks.name_of(id)
		if filt != "" and not sid.contains(filt) and not nm.to_lower().contains(filt):
			continue
		s += "%s (%s), " % [sid, nm]
	if s == "":
		say("Nenhum item encontrado.")
	else:
		say(s.substr(0, 900))


func _coord(tok: String, base: float) -> float:
	if tok.begins_with("~"):
		var rest := tok.substr(1)
		return base + (float(rest) if rest.is_valid_float() else 0.0)
	return float(tok) if tok.is_valid_float() else base


func _tp(args: Array) -> void:
	var a: Array = args.duplicate()
	if not a.is_empty() and String(a[0]).begins_with("@"):
		a.pop_front()
	if a.size() < 3:
		say("Uso: /tp x y z   (aceita ~)")
		return
	var p: Vector3 = main.local_player.global_position
	main.local_player.teleport(Vector3(_coord(String(a[0]), p.x), _coord(String(a[1]), p.y), _coord(String(a[2]), p.z)))


func _kill(args: Array) -> void:
	var sel := "@s"
	if not args.is_empty():
		sel = String(args[0]).to_lower()
	if sel.begins_with("@e"):
		if main.online and not main.is_host:
			say("Só o anfitrião pode matar entidades.")
			return
		var want := ""
		if sel.contains("type="):
			want = sel.split("type=")[1].replace("]", "").strip_edges()
		var n := 0
		for id in main.mobs.keys():
			var m: Mob = main.mobs[id]
			if want == "" or m.kind == want or m.kind.ends_with(":" + want):
				main.kill_mob(m)
				n += 1
		say("%d entidade(s) removida(s)." % n)
		return
	var pl: Player = main.local_player
	var was: bool = pl.creative
	pl.creative = false
	pl.take_damage(9999.0, Vector3.ZERO, 0, true)
	pl.creative = was


func _summon(args: Array) -> void:
	if main.online and not main.is_host:
		say("Só o anfitrião cria mobs.")
		return
	if args.is_empty():
		say("Uso: /mob <tipo> [x y z]   tipos: %s" % ", ".join(Mob.all_kinds()))
		return
	var kind := String(args[0]).to_lower()
	if not Mob.has_type(kind):
		# tenta achar entidade de mod pelo nome curto
		for k in Mods.entities:
			if String(k).ends_with(":" + kind):
				kind = String(k)
	if not Mob.has_type(kind):
		say("Mob desconhecido. Tipos: %s" % ", ".join(Mob.all_kinds()))
		return
	var pl: Player = main.local_player
	var pos: Vector3 = pl.global_position + pl.eye_dir() * 3.0 + Vector3(0, 1, 0)
	if args.size() >= 4:
		var p: Vector3 = pl.global_position
		pos = Vector3(_coord(String(args[1]), p.x), _coord(String(args[2]), p.y), _coord(String(args[3]), p.z))
	main.spawn_mob(kind, pos)


func _title(args: Array) -> void:
	var a: Array = args.duplicate()
	if not a.is_empty() and String(a[0]).begins_with("@"):
		a.pop_front()
	if a.is_empty():
		say("Uso: /title @s title|subtitle|actionbar|clear <texto>")
		return
	var kind := String(a[0]).to_lower()
	if kind in ["title", "subtitle", "actionbar"]:
		a.pop_front()
		main.hud.show_title(kind, " ".join(a))
	elif kind == "clear" or kind == "reset":
		main.hud.show_title("clear", "")
	else:
		main.hud.show_title("title", " ".join(a))


func _block_arg(tok: String) -> int:
	var id := Blocks.id_from_string(tok)
	if id == 0 and ScriptEngine.norm(tok) in ["air", "ar"]:
		return 0
	if id != 0 and not Blocks.is_block(id):
		return -1
	if id == 0 and ScriptEngine.norm(tok) not in ["air", "ar"]:
		return -1
	return id


func _fill(args: Array) -> void:
	if args.size() < 7:
		say("Uso: /fill x1 y1 z1 x2 y2 z2 <bloco> [replace <bloco>|destroy]")
		return
	var p: Vector3 = main.local_player.global_position
	var a := Vector3i(floori(_coord(String(args[0]), p.x)), floori(_coord(String(args[1]), p.y)), floori(_coord(String(args[2]), p.z)))
	var b := Vector3i(floori(_coord(String(args[3]), p.x)), floori(_coord(String(args[4]), p.y)), floori(_coord(String(args[5]), p.z)))
	var id := _block_arg(String(args[6]))
	if id < 0:
		say("Bloco inválido: %s" % String(args[6]))
		return
	var mode := "replace_all"
	var filter_id := 0
	if args.size() > 7:
		var m := String(args[7]).to_lower()
		if m == "replace" and args.size() > 8:
			mode = "replace"
			filter_id = _block_arg(String(args[8]))
			if filter_id < 0:
				say("Bloco do filtro inválido.")
				return
		elif m == "destroy":
			mode = "replace_all"
		elif m == "keep":
			mode = "keep"
	var size := Vector3i(absi(a.x - b.x) + 1, absi(a.y - b.y) + 1, absi(a.z - b.z) + 1)
	var total := size.x * size.y * size.z
	if total > MAX_FILL:
		say("Área grande demais (%d blocos, máximo %d)." % [total, MAX_FILL])
		return
	var n: int = main.fill_blocks(a, b, id, mode, filter_id, true)
	say("%d bloco(s) alterado(s)." % n)


func _setblock(args: Array) -> void:
	if args.size() < 4:
		say("Uso: /setblock x y z <bloco>")
		return
	var p: Vector3 = main.local_player.global_position
	var pos := Vector3i(floori(_coord(String(args[0]), p.x)), floori(_coord(String(args[1]), p.y)), floori(_coord(String(args[2]), p.z)))
	var id := _block_arg(String(args[3]))
	if id < 0:
		say("Bloco inválido: %s" % String(args[3]))
		return
	if pos.y < 1 or pos.y >= World.CH:
		say("Altura inválida (1 a %d)." % (World.CH - 1))
		return
	main.set_block_net(pos.x, pos.y, pos.z, id)
	say("Bloco colocado.")


func _gamerule(args: Array) -> void:
	if args.size() < 2:
		var s := ""
		for r in WorldStore.RULE_LABELS:
			s += "%s=%s  " % [r[0], str(main.rules.get(r[0], false))]
		say("Regras: " + s + "  (uso: /gamerule <regra> <true|false>)")
		return
	var key := ScriptEngine.norm(String(args[0])).replace("-", "_")
	var aliases := {"comandos": "commands", "sempredia": "always_day", "sempre_dia": "always_day", "mobs": "mobs",
		"spawnmobs": "mobs", "keepinventory": "keep_inventory", "explosoes": "explosions"}
	if aliases.has(key):
		key = String(aliases[key])
	var valid := false
	for r in WorldStore.RULE_LABELS:
		if r[0] == key:
			valid = true
	if not valid:
		say("Regra desconhecida: %s" % String(args[0]))
		return
	var v := String(args[1]).to_lower() in ["true", "sim", "1", "on", "ligado"]
	main.set_rule(key, v)
	say("%s = %s" % [key, str(v)])


func _particle(args: Array) -> void:
	var kind := "crit"
	if not args.is_empty():
		kind = String(args[0]).to_lower()
	var pl: Player = main.local_player
	var pos: Vector3 = pl.global_position + pl.eye_dir() * 2.0 + Vector3(0, 1.2, 0)
	if args.size() >= 4:
		var p: Vector3 = pl.global_position
		pos = Vector3(_coord(String(args[1]), p.x), _coord(String(args[2]), p.y), _coord(String(args[3]), p.z))
	main.particles.burst(kind, pos)


func _mods() -> void:
	if Mods.loaded.is_empty():
		say("Nenhum mod carregado.")
		return
	for m in Mods.loaded:
		say("• %s v%s %s" % [m["name"], m["version"], ("— " + m["description"]) if String(m["description"]) != "" else ""])
	if not Mods.warnings.is_empty():
		say("%d aviso(s) dos mods (veja o log)." % Mods.warnings.size())
