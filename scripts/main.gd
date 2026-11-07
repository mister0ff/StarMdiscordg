extends Node
## Controlador principal: fluxo do jogo, mundos/servidores, dia/noite, mobs, rede (ENet), PvP, chat, mods.

const DAY_LEN := 1800.0 # duração de um dia inteiro em segundos (30 min). Era 600.
const PORT := 25565

var world: World
var entities: Node3D
var env: Environment
var sun_pivot: Node3D
var hud
var inv_ui
var touch
var menu
var chat_ui
var particles: Particles
var commands: Commands
var local_player: Player

var playing := false
var creative_mode := false
var mobs_enabled := true
var time_of_day := 0.30
var daylight := 1.0
var spawn_point := Vector3(0, 40, 0)
var online := false
var is_host := false
var world_meta: Dictionary = {}
var world_kind := "world" # "world" | "server"
var rules: Dictionary = WorldStore.default_rules()

var mobs: Dictionary = {}
var drops: Dictionary = {}
var remotes: Dictionary = {}
var _next_mob := 1
var _drop_counter := 0
var _spawn_t := 0.0
var _mob_sync_t := 0.0
var _time_sync_t := 0.0
var _autosave_t := 0.0
var _sky_day := Color(0.52, 0.74, 0.96)
var _sky_night := Color(0.015, 0.02, 0.06)
var _pending_welcome := false
var _back_ms := 0
var _open_chest := Vector3i.ZERO


func _ready() -> void:
	get_window().title = "Cubolândia"
	get_tree().set_auto_accept_quit(false)
	_build_environment()
	world = World.new()
	world.name = "World"
	add_child(world)
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)
	particles = Particles.new()
	particles.name = "Particles"
	add_child(particles)
	commands = Commands.new()
	commands.main = self
	Mods.game = self
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_fail)
	multiplayer.server_disconnected.connect(_on_server_gone)
	menu.show_main()
	var args := OS.get_cmdline_user_args()
	if "--autostart" in args:
		start_test_world("--creative" in args, "--flat" in args, 0)
	elif "--host" in args:
		start_test_world(false, false, PORT)
	elif "--join" in args:
		join_server("127.0.0.1", PORT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if playing and (not online or is_host):
			save_game()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if playing and (not online or is_host):
			save_game()


## Botão voltar do Android / ESC: pausa o jogo, fecha telas ou volta no menu.
func handle_back() -> void:
	var now := Time.get_ticks_msec()
	if now - _back_ms < 250:
		return
	_back_ms = now
	if menu.visible:
		menu.go_back()
		return
	if not playing or local_player == null or touch.edit_mode or local_player.dead:
		return
	if inv_ui.visible:
		close_inventory()
	elif chat_ui.is_open:
		chat_ui.close()
	else:
		pause_game()


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _sky_day
	env.fog_enabled = true
	env.fog_light_color = _sky_day
	env.fog_density = 0.02
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun_pivot = Node3D.new()
	add_child(sun_pivot)
	for k in 2:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(26, 26) if k == 0 else Vector2(18, 18)
		pm.orientation = PlaneMesh.FACE_Z
		q.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.95, 0.6) if k == 0 else Color(0.85, 0.88, 0.95)
		m.disable_fog = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material_override = m
		q.position = Vector3(0, 150, 0) if k == 0 else Vector3(0, -150, 0)
		q.look_at_from_position(q.position, Vector3.ZERO, Vector3.FORWARD)
		sun_pivot.add_child(q)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	touch = preload("res://scripts/ui/touch_controls.gd").new()
	touch.main = self
	layer.add_child(touch)
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.main = self
	layer.add_child(hud)
	var layer2 := CanvasLayer.new()
	layer2.layer = 8
	add_child(layer2)
	inv_ui = preload("res://scripts/ui/inventory_ui.gd").new()
	inv_ui.main = self
	layer2.add_child(inv_ui)
	chat_ui = preload("res://scripts/ui/chat_ui.gd").new()
	chat_ui.main = self
	layer2.add_child(chat_ui)
	var layer3 := CanvasLayer.new()
	layer3.layer = 12
	add_child(layer3)
	menu = preload("res://scripts/ui/menu.gd").new()
	menu.main = self
	layer3.add_child(menu)


# ================================================================ fluxo
## Inicia um mundo ou servidor salvo (meta vem do WorldStore).
func start_world_meta(meta: Dictionary) -> void:
	_cleanup_world()
	world_meta = meta
	world_kind = String(meta.get("kind", "world"))
	rules = meta["rules"]
	Mods.game = self
	Mods.load_for_world(meta)
	world.refresh_tables()
	WorldStore.save_meta(meta) # guarda os ids de mods alocados
	var data := WorldStore.read_data(String(meta["id"]))
	var has_data := not data.is_empty()
	var seed_val: int = int(meta["seed"])
	creative_mode = bool(meta.get("creative", false))
	time_of_day = 0.3
	if has_data:
		creative_mode = bool(data.get("creative", creative_mode))
		time_of_day = float(data.get("time", 0.3))
	world.setup(seed_val, String(meta.get("template", "normal")))
	if has_data:
		world.import_edits(data["edits"])
		world.chests = data.get("chests", {})
	mobs_enabled = bool(rules.get("mobs", true))
	spawn_point = world.find_spawn()
	_create_player()
	if has_data and data.has("player"):
		local_player.deserialize(data["player"])
		spawn_point = data.get("spawn", spawn_point)
	else:
		local_player.global_position = spawn_point
		_starter_kit()
	var host_port := 0
	if world_kind == "server":
		host_port = int(meta.get("port", PORT))
	elif bool(meta.get("lan", false)):
		host_port = PORT
	if host_port > 0:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(host_port, 8)
		if err != OK:
			chat_ui.system("Não foi possível abrir a porta %d (erro %d). Jogando offline." % [host_port, err])
		else:
			multiplayer.multiplayer_peer = peer
			online = true
			is_host = true
	_begin_play()
	if online and is_host:
		chat_ui.system("Aberto para amigos na porta %d (use seu IP + porta)." % host_port)
	if not has_data and mobs_enabled:
		for i in 6:
			_spawn_passive_near(spawn_point, 8.0, 30.0)
	if world_kind == "server" and not Settings.is_admin_name(Settings.player_name):
		chat_ui.system("Você não é administrador deste servidor (admin: %s)." % Settings.ADMIN_NICK)
	elif world_kind == "server":
		chat_ui.system("Você é o dono/administrador do servidor.")
	if not Mods.warnings.is_empty():
		chat_ui.system("Mods: %d aviso(s). Primeiro: %s" % [Mods.warnings.size(), String(Mods.warnings[0])])
	fire_event("player-spawn", {})


func start_test_world(creative: bool, flat: bool, host_port: int) -> void:
	var m := WorldStore.new_meta("teste_auto", "world", "Teste", creative, "flat" if flat else "normal", 4242)
	if host_port > 0:
		m["lan"] = true
	start_world_meta(m)


func join_server(ip: String, port: int) -> void:
	_cleanup_world()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		menu.toast("Não foi possível conectar (erro %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	online = true
	is_host = false
	_pending_welcome = true
	menu.toast("Conectando a %s:%d ..." % [ip, port])


func _create_player() -> void:
	local_player = Player.new()
	local_player.game = self
	local_player.world = world
	local_player.creative = creative_mode
	local_player.died.connect(_on_player_died)
	local_player.damaged.connect(func(): hud.flash_damage())
	local_player.station_requested.connect(func(): open_inventory())
	local_player.chest_requested.connect(open_chest)
	add_child(local_player)


func _starter_kit() -> void:
	if creative_mode:
		local_player.inv.add(Blocks.GRASS, 64)
		local_player.inv.add(Blocks.STONE, 64)
		local_player.inv.add(Blocks.PLANKS, 64)
		local_player.inv.add(Blocks.GLASS, 64)
		local_player.inv.add(Blocks.TORCH, 64)
		local_player.inv.add(Blocks.CHEST, 4)
		local_player.inv.add(Blocks.TOOL_BASE + 30 + Blocks.KIND_PICK, 1)
		local_player.inv.add(Blocks.TOOL_BASE + 30 + Blocks.KIND_SWORD, 1)


func _begin_play() -> void:
	playing = true
	menu.hide_all()
	hud.visible = true
	local_player.set_ui_open(false)
	touch.set_enabled(Settings.use_touch())
	_apply_view_distance()
	chat_ui.system("Bem-vindo! Modo: %s. Digite /ajuda no chat." % ("Criativo" if creative_mode else "Sobrevivência"))


func go_menu() -> void:
	if playing and (not online or is_host):
		save_game()
	_cleanup_world()
	menu.show_main()


func _cleanup_world() -> void:
	playing = false
	if online and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	online = false
	is_host = false
	_pending_welcome = false
	get_tree().paused = false
	if local_player != null:
		local_player.queue_free()
		local_player = null
	for c in entities.get_children():
		c.queue_free()
	mobs.clear()
	drops.clear()
	remotes.clear()
	world.clear_world()
	world.centers = []
	Mods.clear()
	world.refresh_tables()
	world_meta = {}
	world_kind = "world"
	rules = WorldStore.default_rules()
	hud.visible = false
	touch.set_enabled(false)
	inv_ui.close()
	chat_ui.close()
	chat_ui.clear() # o chat é limpo ao sair do mundo
	if not Settings.use_touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_view_distance() -> void:
	var d := Settings.render_distance * World.CS
	env.fog_density = 2.3 / float(d)
	local_player.cam.far = float(d) * 1.6 + 40.0


# ================================================================ salvar
func save_game() -> void:
	if local_player == null or world_meta.is_empty():
		return
	var d := {
		"seed": world.seed_val, "creative": creative_mode, "mobs": mobs_enabled,
		"time": time_of_day, "edits": world.export_edits(),
		"player": local_player.serialize(), "spawn": spawn_point, "chests": world.chests,
	}
	WorldStore.write_data(String(world_meta["id"]), d)
	world_meta["played"] = int(Time.get_unix_time_from_system())
	world_meta["creative"] = creative_mode
	WorldStore.save_meta(world_meta)


# ================================================================ loop
func _process(delta: float) -> void:
	if not playing or local_player == null:
		return
	var pts: Array = [local_player.global_position]
	var radii: Array = [Settings.render_distance]
	if online and is_host:
		for r in remotes.values():
			pts.append(r.global_position)
			radii.append(3)
	world.set_centers(pts, radii)
	if bool(rules.get("always_day", false)):
		time_of_day = 0.3
	else:
		time_of_day = fposmod(time_of_day + delta / DAY_LEN, 1.0)
	_update_sky()
	if is_host or not online:
		_host_tick(delta)
	if is_host and online:
		_time_sync_t += delta
		if _time_sync_t > 5.0:
			_time_sync_t = 0.0
			r_time.rpc(time_of_day)
	_autosave_t += delta
	if _autosave_t > 90.0 and (not online or is_host):
		_autosave_t = 0.0
		save_game()
	if Input.is_action_just_pressed("ui_cancel") and not menu.visible and not touch.edit_mode:
		handle_back()


func _unhandled_input(event: InputEvent) -> void:
	if not playing or local_player == null or menu.visible:
		return
	if event.is_action_pressed("inventory"):
		if inv_ui.visible:
			close_inventory()
		elif not chat_ui.is_open:
			open_inventory()
	elif event.is_action_pressed("chat") and not inv_ui.visible and not chat_ui.is_open:
		get_viewport().set_input_as_handled()
		chat_ui.open()


func pause_game() -> void:
	local_player.set_ui_open(true)
	touch.set_enabled(false)
	menu.show_pause(online, is_host)
	if not online:
		get_tree().paused = true


func resume_game() -> void:
	get_tree().paused = false
	menu.hide_all()
	local_player.set_ui_open(false)
	touch.set_enabled(Settings.use_touch())
	_apply_view_distance()


func open_inventory() -> void:
	if not playing:
		return
	local_player.set_ui_open(true)
	touch.set_enabled(false)
	inv_ui.open(local_player, creative_mode, near_block(Blocks.TABLE, 4), near_block(Blocks.FURNACE, 4))


func open_chest(pos: Vector3i) -> void:
	if not playing:
		return
	if online and not is_host:
		chat_ui.system("Baús só funcionam no anfitrião do servidor (por enquanto).")
		return
	var slots: Array = []
	if world.chests.has(pos):
		slots = world.chests[pos]
	if slots.size() != 27:
		slots = []
		slots.resize(27)
		for i in 27:
			slots[i] = null
		world.chests[pos] = slots
	_open_chest = pos
	local_player.set_ui_open(true)
	touch.set_enabled(false)
	inv_ui.open_chest(local_player, creative_mode, slots)


func chest_changed() -> void:
	pass # os espaços do baú são o próprio Array guardado no mundo


func close_inventory() -> void:
	inv_ui.close()
	if not menu.visible and not chat_ui.is_open:
		local_player.set_ui_open(false)
		touch.set_enabled(Settings.use_touch())


func near_block(id: int, r: int) -> bool:
	var p := local_player.global_position
	var cx := floori(p.x)
	var cy := floori(p.y)
	var cz := floori(p.z)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if world.get_block(cx + dx, cy + dy, cz + dz) == id:
					return true
	return false


func _update_sky() -> void:
	var s := sin(time_of_day * TAU)
	daylight = smoothstep(-0.25, 0.3, s)
	var col := _sky_night.lerp(_sky_day, daylight)
	var dusk := clampf(1.0 - absf(daylight - 0.5) * 2.0, 0.0, 1.0)
	col = col.lerp(Color(0.95, 0.5, 0.3), dusk * 0.4 * (1.0 if absf(s) < 0.45 else 0.0))
	var underwater := false
	var cp := local_player.cam.global_position
	underwater = world.get_block(floori(cp.x), floori(cp.y), floori(cp.z)) == Blocks.WATER
	if underwater:
		col = Color(0.08, 0.2, 0.45).lerp(col, 0.1) * (0.35 + 0.65 * daylight)
		env.fog_density = 0.12
	else:
		env.fog_density = 2.3 / float(Settings.render_distance * World.CS)
	env.background_color = col
	env.fog_light_color = col
	world.set_daylight(daylight)
	hud.set_underwater(underwater)
	sun_pivot.global_position = cp
	sun_pivot.basis = Basis(Vector3(0, 0, 1), time_of_day * TAU - PI * 0.5)


func is_day() -> bool:
	return daylight > 0.5


func set_creative(v: bool) -> void:
	creative_mode = v
	local_player.creative = v
	if not v:
		local_player.flying = false
	chat_ui.system("Modo: %s" % ("Criativo" if v else "Sobrevivência"))


func set_time(t: float) -> void:
	time_of_day = t
	if online:
		r_time.rpc(t)


func set_rule(key: String, v: bool) -> void:
	rules[key] = v
	if key == "mobs":
		mobs_enabled = v
	if not world_meta.is_empty():
		WorldStore.save_meta(world_meta)
	if online and is_host:
		r_rules.rpc(rules)


# ================================================================ eventos de script (mods)
func script_ctx(extra: Dictionary) -> Dictionary:
	var held := 0
	var gp := Vector3.ZERO
	var hp := 20.0
	var hg := 20.0
	var sneaking := false
	if local_player != null:
		held = local_player.held_id()
		gp = local_player.global_position
		hp = local_player.health
		hg = local_player.hunger
		sneaking = Input.is_action_pressed("sneak")
	var d := {
		"player": Settings.player_name,
		"item": Blocks.string_of(held) if held != 0 else "air",
		"sneaking": sneaking, "health": hp, "hunger": hg,
		"gamemode": "creative" if creative_mode else "survival",
		"x": gp.x, "y": gp.y, "z": gp.z, "ix": floori(gp.x), "iy": floori(gp.y), "iz": floori(gp.z),
		"is_day": daylight > 0.5, "time": time_of_day,
		"admin": Settings.is_admin_name(Settings.player_name),
	}
	for k in extra:
		d[k] = extra[k]
	return d


## Dispara um evento de mod. Retorna true se algum script pediu "cancelar".
func fire_event(ev: String, extra: Dictionary) -> bool:
	if local_player == null or not Mods.has_handlers(ev):
		return false
	var r := Mods.emit(ev, script_ctx(extra))
	return bool(r["cancel"])


# ================================================================ mobs (host/solo)
func _host_tick(delta: float) -> void:
	if not mobs_enabled:
		return
	_spawn_t += delta
	if _spawn_t > 2.0:
		_spawn_t = 0.0
		_try_spawn_mob()
		_despawn_far()
	if online and is_host:
		_mob_sync_t += delta
		if _mob_sync_t > 0.08:
			_mob_sync_t = 0.0
			var arr: Array = []
			for m in mobs.values():
				arr.append(m.net_state())
			r_mobs.rpc(arr)


func player_targets() -> Array:
	var out: Array = []
	if local_player != null and not local_player.dead and not local_player.creative:
		out.append({"id": multiplayer.get_unique_id() if online else 1, "pos": local_player.global_position})
	for r in remotes.values():
		out.append({"id": r.peer_id, "pos": r.global_position})
	return out


func _all_player_positions() -> Array:
	var out: Array = []
	if local_player != null:
		out.append(local_player.global_position)
	for r in remotes.values():
		out.append(r.global_position)
	return out


func _try_spawn_mob() -> void:
	var pls := _all_player_positions()
	if pls.is_empty():
		return
	var hostile_n := 0
	var pass_n := 0
	for m in mobs.values():
		if m.hostile:
			hostile_n += 1
		else:
			pass_n += 1
	var base: Vector3 = pls[randi() % pls.size()]
	if daylight < 0.3 and hostile_n < 12:
		var pos := _random_ground(base, 18.0, 36.0)
		if pos != Vector3.INF:
			var r := randf()
			spawn_mob("zombie" if r < 0.5 else ("skeleton" if r < 0.75 else "creeper"), pos)
	elif pass_n < 12 and randf() < 0.4:
		_spawn_passive_near(base, 20.0, 40.0)
	# entidades criadas por mods
	var cust := Mods.pick_spawn(daylight < 0.3)
	if cust != "":
		var n := 0
		for m in mobs.values():
			if m.kind == cust:
				n += 1
		if n < int(Mods.entities[cust]["spawn_max"]):
			var cp := _random_ground(base, 14.0, 36.0)
			if cp != Vector3.INF:
				spawn_mob(cust, cp)


func _spawn_passive_near(base: Vector3, rmin: float, rmax: float) -> void:
	var pos := _random_ground(base, rmin, rmax)
	if pos == Vector3.INF:
		return
	var below := world.get_block(floori(pos.x), floori(pos.y) - 1, floori(pos.z))
	if below == Blocks.GRASS:
		spawn_mob("pig" if randf() < 0.5 else "cow", pos)


func _random_ground(base: Vector3, rmin: float, rmax: float) -> Vector3:
	var a := randf() * TAU
	var d := randf_range(rmin, rmax)
	var wx := floori(base.x + cos(a) * d)
	var wz := floori(base.z + sin(a) * d)
	if not world.is_loaded(wx, wz):
		return Vector3.INF
	var y := world.surface_y(wx, wz)
	if y <= World.SEA - 1 or world.get_block(wx, y, wz) == Blocks.WATER:
		return Vector3.INF
	return Vector3(wx + 0.5, y + 1.05, wz + 0.5)


func spawn_mob(kind: String, pos: Vector3, id := -1) -> Mob:
	var m := Mob.new()
	m.setup(kind)
	m.game = self
	m.world = world
	m.net_id = _next_mob if id < 0 else id
	if id < 0:
		_next_mob += 1
	m.position = pos
	entities.add_child(m)
	mobs[m.net_id] = m
	return m


func _despawn_far() -> void:
	var pls := _all_player_positions()
	for id in mobs.keys():
		var m: Mob = mobs[id]
		var near := false
		for p in pls:
			if p.distance_to(m.global_position) < 80.0:
				near = true
				break
		if not near or (m.hostile and daylight > 0.9 and randf() < 0.1):
			_remove_mob(id)


func _remove_mob(id: int) -> void:
	if mobs.has(id):
		mobs[id].queue_free()
		mobs.erase(id)


func kill_mob(m: Mob) -> void:
	mob_died(m)


func mob_died(m: Mob) -> void:
	if not mobs.has(m.net_id):
		return
	for d in m.drops():
		spawn_drop_net(d[0], d[1], m.global_position + Vector3(0, 0.6, 0), Vector3(randf_range(-2, 2), 4, randf_range(-2, 2)), 0.4)
	particles.burst("smoke", m.global_position + Vector3(0, 0.5, 0), Color(1, 1, 1), 10)
	fire_event("entity-die", {"entity": m.kind})
	_remove_mob(m.net_id)


func creeper_explode(m: Mob) -> void:
	var pos := m.global_position + Vector3(0, 0.8, 0)
	_remove_mob(m.net_id)
	if online:
		r_explode.rpc(pos, 3.3)
	else:
		r_explode(pos, 3.3)


func damage_player(id: int, dmg: float, kb: Vector3) -> void:
	var me := multiplayer.get_unique_id() if online else 1
	if id == me:
		local_player.take_damage(dmg, kb)
	elif online:
		r_damage.rpc_id(id, dmg, kb)


# ================================================================ ações do jogador local
func player_break_block(pos: Vector3i, bid: int, harvest: bool) -> void:
	if bid == Blocks.CHEST and world.chests.has(pos):
		var slots: Array = world.chests[pos]
		for s in slots:
			if s != null:
				spawn_drop_net(int(s[0]), int(s[1]), Vector3(pos) + Vector3(0.5, 0.6, 0.5), Vector3(randf_range(-1.5, 1.5), 3, randf_range(-1.5, 1.5)), 0.3)
		world.chests.erase(pos)
	set_block_net(pos.x, pos.y, pos.z, Blocks.AIR)
	if harvest and not creative_mode:
		var dr := Blocks.drops_for(bid, local_player.held_id())
		if not dr.is_empty():
			spawn_drop_net(dr[0], dr[1], Vector3(pos) + Vector3(0.5, 0.5, 0.5), Vector3(randf_range(-1, 1), 3, randf_range(-1, 1)), 0.3)
	fire_event("after-break", {"block": Blocks.string_of(bid), "bx": pos.x, "by": pos.y, "bz": pos.z})


func player_place_block(pos: Vector3i, id: int) -> bool:
	var ctx := {"block": Blocks.string_of(id), "bx": pos.x, "by": pos.y, "bz": pos.z}
	if fire_event("before-place", ctx):
		return false
	set_block_net(pos.x, pos.y, pos.z, id)
	fire_event("after-place", ctx)
	return true


func _apply_block(x: int, y: int, z: int, id: int) -> void:
	var old := world.get_block(x, y, z)
	world.set_block(x, y, z, id)
	if id == Blocks.AIR and old != Blocks.AIR and old != Blocks.WATER:
		particles.block_break(Vector3i(x, y, z), old)


func set_block_net(x: int, y: int, z: int, id: int) -> void:
	_apply_block(x, y, z, id)
	if online:
		r_block.rpc(x, y, z, id)


## Preenche uma área (usado por /fill). Retorna quantos blocos mudaram.
func fill_blocks(a: Vector3i, b: Vector3i, id: int, mode: String, filter_id: int, broadcast: bool) -> int:
	var mn := Vector3i(mini(a.x, b.x), maxi(1, mini(a.y, b.y)), mini(a.z, b.z))
	var mx := Vector3i(maxi(a.x, b.x), mini(World.CH - 1, maxi(a.y, b.y)), maxi(a.z, b.z))
	var n := 0
	for x in range(mn.x, mx.x + 1):
		for y in range(mn.y, mx.y + 1):
			for z in range(mn.z, mx.z + 1):
				var cur := world.get_block(x, y, z)
				if cur == id:
					continue
				if mode == "keep" and cur != Blocks.AIR:
					continue
				if mode == "replace" and cur != filter_id:
					continue
				world.set_block(x, y, z, id, false)
				n += 1
	if broadcast and online:
		r_fill.rpc(a, b, id, mode, filter_id)
	return n


func player_attack(ent: Node, dmg: float, kb: Vector3) -> void:
	if ent is Mob:
		var m: Mob = ent
		if not online or is_host:
			m.take_hit(dmg, kb)
		else:
			r_hit_mob.rpc_id(1, m.net_id, dmg, kb)
		particles.burst("hurt", m.global_position + Vector3(0, m.hit_h * 0.6, 0), Color(1, 1, 1), 6)
	elif ent is RemotePlayer:
		if not bool(rules.get("pvp", true)):
			chat_ui.system("PvP está desativado neste mundo/servidor.")
			return
		var rp: RemotePlayer = ent
		rp.hurt()
		particles.burst("hurt", rp.global_position + Vector3(0, 1.2, 0), Color(1, 1, 1), 8)
		r_hit_player.rpc_id(rp.peer_id, dmg, kb)


func spawn_drop_net(item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	_drop_counter += 1
	var me := multiplayer.get_unique_id() if online else 1
	var nid := me * 1000000 + _drop_counter
	_spawn_drop(nid, item, count, pos, vel, delay)
	if online:
		r_drop.rpc(nid, item, count, pos, vel, delay)


func _spawn_drop(nid: int, item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	if drops.has(nid) or not Blocks.defs.has(item):
		return
	var d := ItemDrop.new()
	d.item_id = item
	d.count = count
	d.net_id = nid
	d.vel = vel
	d.delay = delay
	d.game = self
	d.world = world
	d.position = pos
	entities.add_child(d)
	drops[nid] = d


func try_pickup(d: ItemDrop) -> bool:
	if not drops.has(d.net_id):
		return false
	var left := local_player.inv.add(d.item_id, d.count)
	if left >= d.count:
		return false
	if left > 0:
		d.count = left
		return false
	drops.erase(d.net_id)
	d.queue_free()
	if online:
		r_pickup.rpc(d.net_id)
	return true


func spawn_arrow_net(pos: Vector3, vel: Vector3) -> void:
	if online:
		r_arrow.rpc(pos, vel)
	else:
		r_arrow(pos, vel)


func player_fell_into_void() -> void:
	local_player.teleport(spawn_point)


func _on_player_died() -> void:
	if not creative_mode and not bool(rules.get("keep_inventory", false)):
		for i in Inventory.SIZE:
			var s = local_player.inv.slots[i]
			if s != null:
				spawn_drop_net(s[0], s[1], local_player.global_position + Vector3(0, 1, 0), Vector3(randf_range(-3, 3), 4, randf_range(-3, 3)), 1.5)
		local_player.inv.clear()
	chat_ui.system("Você morreu!")
	local_player.set_ui_open(true)
	touch.set_enabled(false)
	hud.show_death()
	fire_event("player-die", {})


func respawn() -> void:
	hud.hide_death()
	local_player.respawn(spawn_point)
	local_player.set_ui_open(false)
	touch.set_enabled(Settings.use_touch())
	fire_event("player-respawn", {})


# ================================================================ chat
func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty() or local_player == null:
		return
	if text.begins_with("/"):
		commands.execute(text)
		return
	if fire_event("chat", {"message": text}):
		return
	send_chat_as(Settings.player_name, text)


func send_chat_as(nm: String, text: String) -> void:
	chat_ui.message(nm, text)
	if online:
		r_chat.rpc(nm, text)


# ================================================================ rede
func net_send_state(pos: Vector3, yaw: float, pitch: float, held: int, swing: bool, sneak: bool) -> void:
	if online and multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		r_state.rpc(pos, yaw, pitch, held, swing, sneak)


func _on_peer_connected(id: int) -> void:
	if is_host and playing:
		r_welcome.rpc_id(id, world.seed_val, creative_mode, time_of_day, world.export_edits(), spawn_point, rules, String(world_meta.get("template", "normal")))


func _on_peer_disconnected(id: int) -> void:
	if remotes.has(id):
		chat_ui.system("%s saiu." % remotes[id].pname)
		remotes[id].queue_free()
		remotes.erase(id)


func _on_connected_ok() -> void:
	menu.toast("Conectado! Baixando mundo...")


func _on_connect_fail() -> void:
	_cleanup_world()
	menu.show_main()
	menu.toast("Falha na conexão.")


func _on_server_gone() -> void:
	_cleanup_world()
	menu.show_main()
	menu.toast("Desconectado do servidor.")


func _add_remote(id: int, nm: String) -> void:
	if remotes.has(id) or id == multiplayer.get_unique_id():
		return
	var r := RemotePlayer.new()
	r.peer_id = id
	r.pname = nm
	r.position = Vector3(0, 100, 0)
	entities.add_child(r)
	remotes[id] = r
	print("[net] jogador entrou: ", nm, " id=", id)
	chat_ui.system("%s entrou." % nm)


@rpc("authority", "reliable")
func r_welcome(seed_val: int, creative: bool, tod: float, edits: Dictionary, spawn: Vector3, host_rules: Dictionary, template: String) -> void:
	if not _pending_welcome:
		return
	_pending_welcome = false
	var keep_peer := multiplayer.multiplayer_peer
	creative_mode = creative
	rules = WorldStore.default_rules()
	for k in host_rules:
		rules[k] = host_rules[k]
	world_kind = "server"
	world_meta = {}
	mobs_enabled = bool(rules.get("mobs", true))
	time_of_day = tod
	if local_player != null:
		local_player.queue_free()
	world.clear_world()
	Mods.clear()
	world.refresh_tables()
	world.setup(seed_val, template)
	world.import_edits(edits)
	spawn_point = spawn
	_create_player()
	local_player.global_position = spawn
	_starter_kit()
	multiplayer.multiplayer_peer = keep_peer
	online = true
	is_host = false
	_begin_play()
	r_announce.rpc(Settings.player_name)


@rpc("authority", "reliable")
func r_rules(new_rules: Dictionary) -> void:
	if is_host:
		return
	for k in new_rules:
		rules[k] = new_rules[k]
	mobs_enabled = bool(rules.get("mobs", true))


@rpc("any_peer", "reliable")
func r_announce(nm: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_add_remote(sender, nm)
	r_announce_reply.rpc_id(sender, Settings.player_name)


@rpc("any_peer", "reliable")
func r_announce_reply(nm: String) -> void:
	_add_remote(multiplayer.get_remote_sender_id(), nm)


@rpc("any_peer", "unreliable")
func r_state(pos: Vector3, yaw: float, pitch: float, held: int, swing: bool, sneak: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if remotes.has(sender):
		remotes[sender].net_apply(pos, yaw, pitch, held, swing, sneak)


@rpc("any_peer", "reliable")
func r_block(x: int, y: int, z: int, id: int) -> void:
	_apply_block(x, y, z, id)


@rpc("any_peer", "reliable")
func r_fill(a: Vector3i, b: Vector3i, id: int, mode: String, filter_id: int) -> void:
	fill_blocks(a, b, id, mode, filter_id, false)


@rpc("any_peer", "reliable")
func r_chat(nm: String, text: String) -> void:
	chat_ui.message(nm, text)


@rpc("authority", "unreliable")
func r_mobs(arr: Array) -> void:
	if is_host:
		return
	var seen: Dictionary = {}
	for s in arr:
		var id: int = s[0]
		seen[id] = true
		if not mobs.has(id):
			var m := spawn_mob(s[1], s[2], id)
			m.puppet = true
		(mobs[id] as Mob).net_apply(s[2], s[3], s[4], s[5])
	for id in mobs.keys():
		if not seen.has(id):
			_remove_mob(id)


@rpc("any_peer", "reliable")
func r_hit_mob(id: int, dmg: float, kb: Vector3) -> void:
	if is_host and mobs.has(id):
		mobs[id].take_hit(dmg, kb)


@rpc("any_peer", "reliable")
func r_hit_player(dmg: float, kb: Vector3) -> void:
	if local_player == null or creative_mode or not bool(rules.get("pvp", true)):
		return
	local_player.take_damage(dmg, kb)


@rpc("any_peer", "reliable")
func r_damage(dmg: float, kb: Vector3) -> void:
	if local_player != null:
		local_player.take_damage(dmg, kb)


@rpc("any_peer", "reliable")
func r_drop(nid: int, item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	_spawn_drop(nid, item, count, pos, vel, delay)


@rpc("any_peer", "reliable")
func r_pickup(nid: int) -> void:
	if drops.has(nid):
		drops[nid].queue_free()
		drops.erase(nid)


@rpc("any_peer", "reliable", "call_local")
func r_arrow(pos: Vector3, vel: Vector3) -> void:
	var a := Arrow.new()
	a.vel = vel
	a.game = self
	a.world = world
	a.position = pos
	entities.add_child(a)


@rpc("any_peer", "reliable", "call_local")
func r_explode(pos: Vector3, radius: float) -> void:
	particles.burst("smoke", pos, Color(1, 1, 1), 24)
	if bool(rules.get("explosions", true)):
		world.explode(pos, radius)
	if local_player != null and not local_player.dead:
		var to := local_player.global_position + Vector3(0, 0.9, 0) - pos
		var d := to.length()
		if d < radius * 1.8:
			var dmg := (1.0 - d / (radius * 1.8)) * 16.0
			var kb := Vector3(to.x, 0, to.z).normalized() * 9.0
			local_player.take_damage(dmg, kb, 0, true)


@rpc("authority", "reliable")
func r_time(t: float) -> void:
	time_of_day = t
