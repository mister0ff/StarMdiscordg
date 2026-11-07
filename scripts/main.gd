extends Node
## Controlador principal: fluxo do jogo, dia/noite, mobs, rede (ENet), PvP, chat, salvamento.

const SAVE_PATH := "user://save.dat"
const DAY_LEN := 1800.0
const PROTO := 2
const SERVER_SAVE := "user://server_world.dat"
const PORT := 25565

var world: World
var local_player: Player
var entities: Node3D
var env: Environment
var sun_pivot: Node3D
var hud
var inv_ui
var touch
var menu
var chat_ui
var hand_view
var particles: Particles
var containers := Containers.new()
var dedicated := false
var locked := false
var max_players := 16
var _pending_cb: Callable
var _cache: Dictionary = {}
var _incoming_edits: Dictionary = {}
var _chat_t: Dictionary = {}

var playing := false
var creative_mode := false
var mobs_enabled := true
var time_of_day := 0.30
var daylight := 1.0
var spawn_point := Vector3(0, 40, 0)
var online := false
var is_host := false

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


func _ready() -> void:
	get_window().title = "Cubolândia"
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	_build_environment()
	world = World.new()
	world.name = "World"
	add_child(world)
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)
	particles = Particles.new()
	particles.world = world
	add_child(particles)
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_fail)
	multiplayer.server_disconnected.connect(_on_server_gone)
	menu.show_main(FileAccess.file_exists(SAVE_PATH))
	var args := OS.get_cmdline_user_args()
	var env_srv := OS.get_environment("CUBO_SERVER") == "1"
	if "--server" in args or env_srv:
		var port := int(OS.get_environment("CUBO_PORT")) if OS.get_environment("CUBO_PORT") != "" else PORT
		var ws := OS.get_environment("CUBO_WS") == "1" or "--ws" in args
		var cr := OS.get_environment("CUBO_CREATIVE") == "1" or "--creative" in args
		var sd := int(OS.get_environment("CUBO_SEED")) if OS.get_environment("CUBO_SEED") != "" else 0
		for k in args.size():
			if args[k] == "--port" and k + 1 < args.size():
				port = int(args[k + 1])
			if args[k] == "--seed" and k + 1 < args.size():
				sd = int(args[k + 1])
		start_dedicated(port, ws, cr, sd)
	elif "--autostart" in args:
		start_world("--creative" in args, 4242, true, false)
	elif "--host" in args:
		start_world(false, 4242, true, false, PORT)
	elif "--join" in args:
		join_server("127.0.0.1", PORT)


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
	hand_view = preload("res://scripts/ui/hand_view.gd").new()
	hand_view.main = self
	layer.add_child(hand_view)
	layer.move_child(hand_view, 0)
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
func start_world(creative: bool, seed_val: int, mobs_on: bool, load_save: bool, host_port := 0) -> void:
	_cleanup_world()
	creative_mode = creative
	mobs_enabled = mobs_on
	locked = false
	var data := {}
	if load_save:
		data = _read_save(SAVE_PATH)
		if data.is_empty():
			load_save = false
		else:
			seed_val = data["seed"]
			creative_mode = data["creative"]
			mobs_enabled = data.get("mobs", true)
			time_of_day = data.get("time", 0.3)
	if seed_val == 0:
		seed_val = randi() % 1000000 + 1
	world.setup(seed_val)
	if load_save:
		world.import_edits(data["edits"])
		containers.deserialize(data.get("containers", []))
	spawn_point = world.find_spawn()
	_create_player()
	if load_save and data.has("player"):
		local_player.deserialize(data["player"])
		spawn_point = data.get("spawn", spawn_point)
	else:
		local_player.global_position = spawn_point
		_starter_kit()
	if host_port > 0:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(host_port, 8)
		if err != OK:
			chat_ui.system("Falha ao abrir servidor na porta %d (erro %d)" % [host_port, err])
		else:
			multiplayer.multiplayer_peer = peer
			online = true
			is_host = true
			chat_ui.system("Servidor aberto na porta %d. Seu IP local/público + porta para amigos." % host_port)
	_begin_play()
	if not load_save and mobs_enabled:
		for i in 6:
			_spawn_passive_near(spawn_point, 8.0, 30.0)


## Servidor dedicado (sem jogador local), para rodar 24h. Veja SERVER.md.
func start_dedicated(port: int, use_ws: bool, creative: bool, seed_val: int) -> void:
	_cleanup_world()
	dedicated = true
	locked = true
	creative_mode = creative
	mobs_enabled = true
	Engine.max_fps = 30
	Engine.physics_ticks_per_second = 30
	var data := _read_save(SERVER_SAVE)
	if not data.is_empty():
		seed_val = data["seed"]
		creative_mode = data["creative"]
		time_of_day = data.get("time", 0.3)
	if seed_val == 0:
		seed_val = randi() % 1000000 + 1
	world.setup(seed_val)
	if not data.is_empty():
		world.import_edits(data["edits"])
		containers.deserialize(data.get("containers", []))
	spawn_point = world.find_spawn()
	var err := OK
	if use_ws:
		var wp := WebSocketMultiplayerPeer.new()
		err = wp.create_server(port)
		multiplayer.multiplayer_peer = wp
	else:
		var ep := ENetMultiplayerPeer.new()
		err = ep.create_server(port, max_players)
		multiplayer.multiplayer_peer = ep
	if err != OK:
		print("[server] ERRO ao abrir porta %d (erro %d)" % [port, err])
		get_tree().quit(1)
		return
	online = true
	is_host = true
	playing = true
	menu.hide_all()
	print("[server] Cubolandia aberto em %s porta %d  semente=%d  modo=%s" % ["WebSocket" if use_ws else "ENet/UDP", port, seed_val, "criativo" if creative_mode else "sobrevivencia"])


func join_server(addr: String, port: int) -> void:
	_cleanup_world()
	addr = addr.strip_edges()
	var err := OK
	if addr.begins_with("ws://") or addr.begins_with("wss://"):
		var wp := WebSocketMultiplayerPeer.new()
		err = wp.create_client(addr)
		if err == OK:
			multiplayer.multiplayer_peer = wp
	else:
		if addr.contains(":") and not addr.contains("["):
			var parts := addr.split(":")
			addr = parts[0]
			port = int(parts[1])
		var peer := ENetMultiplayerPeer.new()
		err = peer.create_client(addr, port)
		if err == OK:
			multiplayer.multiplayer_peer = peer
	if err != OK:
		menu.toast("Não foi possível conectar (erro %d)" % err)
		return
	online = true
	is_host = false
	_pending_welcome = true
	menu.toast("Conectando a %s ..." % addr)


func _create_player() -> void:
	local_player = Player.new()
	local_player.game = self
	local_player.world = world
	local_player.creative = creative_mode
	local_player.died.connect(_on_player_died)
	local_player.damaged.connect(func(): hud.flash_damage())
	local_player.use_block.connect(_on_use_block)
	add_child(local_player)


func _starter_kit() -> void:
	if creative_mode:
		local_player.inv.add(Blocks.GRASS, 64)
		local_player.inv.add(Blocks.STONE, 64)
		local_player.inv.add(Blocks.PLANKS, 64)
		local_player.inv.add(Blocks.GLASS, 64)
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
	if playing and (not online or is_host) and not dedicated:
		save_game()
	_cleanup_world()
	menu.show_main(FileAccess.file_exists(SAVE_PATH))


func _cleanup_world() -> void:
	playing = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	online = false
	is_host = false
	_pending_welcome = false
	if local_player != null:
		local_player.queue_free()
		local_player = null
	for c in entities.get_children():
		c.queue_free()
	mobs.clear()
	drops.clear()
	remotes.clear()
	containers.data.clear()
	_cache.clear()
	world.clear_world()
	world.centers = []
	hud.visible = false
	touch.set_enabled(false)
	inv_ui.close()
	chat_ui.close()
	if not Settings.use_touch() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_view_distance() -> void:
	if local_player == null:
		return
	var d := Settings.render_distance * World.CS
	env.fog_density = 2.3 / float(d)
	local_player.cam.far = float(d) * 1.6 + 40.0


# ================================================================ salvar / carregar
func save_game() -> void:
	if local_player == null and not dedicated:
		return
	var d := {
		"seed": world.seed_val, "creative": creative_mode, "mobs": mobs_enabled,
		"time": time_of_day, "edits": world.export_edits(),
		"spawn": spawn_point, "containers": containers.serialize(),
	}
	if local_player != null:
		d["player"] = local_player.serialize()
	var f := FileAccess.open(SERVER_SAVE if dedicated else SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_var(d, false)
		f.close()


func _read_save(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var(false)
	f.close()
	if d is Dictionary and d.has("seed") and d.has("edits"):
		return d
	return {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and playing and (not online or is_host):
		save_game()


# ================================================================ loop
var _insets_t := 0.0


func _process(delta: float) -> void:
	_insets_t -= delta
	if _insets_t <= 0.0:
		_insets_t = 0.5
		Settings.update_insets(get_viewport())
	if not playing:
		return
	var pts: Array = []
	var radii: Array = []
	if local_player != null:
		pts.append(local_player.global_position)
		radii.append(Settings.render_distance)
	if online and is_host:
		for r in remotes.values():
			pts.append(r.global_position)
			radii.append(3 if local_player != null else 4)
	world.set_centers(pts, radii)
	time_of_day = fposmod(time_of_day + delta / DAY_LEN, 1.0)
	_update_sky()
	if is_host or not online:
		_host_tick(delta)
		containers.tick(world, self, delta)
	if is_host and online:
		_time_sync_t += delta
		if _time_sync_t > 5.0:
			_time_sync_t = 0.0
			s_time.rpc(time_of_day)
	_autosave_t += delta
	if _autosave_t > (60.0 if dedicated else 90.0) and (not online or is_host):
		_autosave_t = 0.0
		save_game()
	if local_player == null:
		return
	if Input.is_action_just_pressed("ui_cancel") and not menu.visible and not touch.edit_mode and not local_player.dead:
		if inv_ui.visible:
			close_inventory()
		elif chat_ui.is_open:
			chat_ui.close()
		else:
			pause_game()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var m := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if m == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
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


func _open_ui(m: String, pos := Vector3i.ZERO) -> void:
	if not playing:
		return
	local_player.set_ui_open(true)
	touch.set_enabled(false)
	inv_ui.open_mode(local_player, m, pos)


func open_inventory() -> void:
	_open_ui("creative" if creative_mode else "player")


func close_inventory() -> void:
	inv_ui.close()
	if not menu.visible and not chat_ui.is_open and local_player != null:
		local_player.set_ui_open(false)
		touch.set_enabled(Settings.use_touch())


func _on_use_block(pos: Vector3i, id: int) -> void:
	if id == Blocks.TABLE:
		_open_ui("table")
	elif id == Blocks.CHEST:
		_open_ui("chest", pos)
	elif id == Blocks.FURNACE or id == Blocks.FURNACE_ON:
		_open_ui("furnace", pos)


func _update_sky() -> void:
	var s := sin(time_of_day * TAU)
	daylight = smoothstep(-0.25, 0.3, s)
	var col := _sky_night.lerp(_sky_day, daylight)
	var dusk := clampf(1.0 - absf(daylight - 0.5) * 2.0, 0.0, 1.0)
	col = col.lerp(Color(0.95, 0.5, 0.3), dusk * 0.4 * (1.0 if absf(s) < 0.45 else 0.0))
	world.set_daylight(daylight)
	Blocks.set_item_light(0.25 + 0.75 * daylight)
	particles.set_light(0.25 + 0.75 * daylight)
	if local_player == null:
		return
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
	hud.set_underwater(underwater)
	sun_pivot.global_position = cp
	sun_pivot.basis = Basis(Vector3(0, 0, 1), time_of_day * TAU - PI * 0.5)


func is_day() -> bool:
	return daylight > 0.5


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
			s_mobs.rpc(arr)


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
			_spawn_mob("zombie" if r < 0.5 else ("skeleton" if r < 0.75 else "creeper"), pos)
	elif pass_n < 12 and randf() < 0.4:
		_spawn_passive_near(base, 20.0, 40.0)


func _spawn_passive_near(base: Vector3, rmin: float, rmax: float) -> void:
	var pos := _random_ground(base, rmin, rmax)
	if pos == Vector3.INF:
		return
	var below := world.get_block(floori(pos.x), floori(pos.y) - 1, floori(pos.z))
	if below == Blocks.GRASS:
		_spawn_mob("pig" if randf() < 0.5 else "cow", pos)


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


func _spawn_mob(kind: String, pos: Vector3, id := -1) -> Mob:
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


# ================================================================ ações do jogador local
func player_break_block(pos: Vector3i, bid: int, harvest: bool) -> void:
	particles.burst(bid, Vector3(pos) + Vector3(0.5, 0.5, 0.5), 18)
	set_block_net(pos.x, pos.y, pos.z, Blocks.AIR)
	if harvest and not creative_mode:
		var dr := Blocks.drops_for(bid, local_player.held_id())
		if not dr.is_empty():
			spawn_drop_net(dr[0], dr[1], Vector3(pos) + Vector3(0.5, 0.5, 0.5), Vector3(randf_range(-1, 1), 3, randf_range(-1, 1)), 0.3)


func player_place_block(pos: Vector3i, id: int) -> void:
	set_block_net(pos.x, pos.y, pos.z, id)


func set_block_net(x: int, y: int, z: int, id: int) -> void:
	world.set_block(x, y, z, id)
	if online:
		if is_host:
			s_block.rpc(x, y, z, id)
		else:
			c_block.rpc_id(1, x, y, z, id)


func player_attack(ent: Node, dmg: float, kb: Vector3) -> void:
	if ent is Mob:
		var m: Mob = ent
		if not online or is_host:
			m.take_hit(dmg, kb)
		else:
			c_hit_mob.rpc_id(1, m.net_id, dmg, kb)
	elif ent is RemotePlayer:
		if is_host:
			s_damage.rpc_id(ent.peer_id, dmg, kb)
		else:
			c_hit_player.rpc_id(1, ent.peer_id, dmg, kb)


func spawn_drop_net(item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	_drop_counter += 1
	var me := multiplayer.get_unique_id() if online else 1
	var nid := me * 1000000 + _drop_counter
	_spawn_drop(nid, item, count, pos, vel, delay)
	if online:
		if is_host:
			s_drop.rpc(nid, item, count, pos, vel, delay)
		else:
			c_drop.rpc_id(1, nid, item, count, pos, vel, delay)


func _spawn_drop(nid: int, item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	if drops.has(nid) or not Blocks.defs.has(item):
		return
	if drops.size() > 250:
		var oldest: int = drops.keys()[0]
		forget_drop(drops[oldest])
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


func forget_drop(d: ItemDrop) -> void:
	drops.erase(d.net_id)
	d.queue_free()


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
		if is_host:
			s_pickup.rpc(d.net_id)
		else:
			c_pickup.rpc_id(1, d.net_id)
	return true


func spawn_arrow_net(pos: Vector3, vel: Vector3) -> void:
	if online:
		s_arrow.rpc(pos, vel)
	else:
		s_arrow(pos, vel)


func player_fell_into_void() -> void:
	local_player.teleport(spawn_point)


func _on_player_died() -> void:
	if not creative_mode:
		for i in Inventory.SIZE:
			var s = local_player.inv.slots[i]
			if s != null:
				spawn_drop_net(s[0], s[1], local_player.global_position + Vector3(0, 1, 0), Vector3(randf_range(-3, 3), 4, randf_range(-3, 3)), 1.5)
		local_player.inv.clear()
	chat_ui.system("Você morreu!")
	inv_ui.close()
	local_player.set_ui_open(true)
	touch.set_enabled(false)
	hud.show_death()


func respawn() -> void:
	hud.hide_death()
	local_player.respawn(spawn_point)
	local_player.set_ui_open(false)
	touch.set_enabled(Settings.use_touch())


func damage_player(id: int, dmg: float, kb: Vector3) -> void:
	var me := multiplayer.get_unique_id() if online else 1
	if local_player != null and id == me:
		local_player.take_damage(dmg, kb)
	elif online and id != me:
		s_damage.rpc_id(id, dmg, kb)


func mob_died(m: Mob) -> void:
	if not mobs.has(m.net_id):
		return
	for d in m.drops():
		spawn_drop_net(d[0], d[1], m.global_position + Vector3(0, 0.6, 0), Vector3(randf_range(-2, 2), 4, randf_range(-2, 2)), 0.4)
	_remove_mob(m.net_id)


func creeper_explode(m: Mob) -> void:
	var pos := m.global_position + Vector3(0, 0.8, 0)
	_remove_mob(m.net_id)
	if online:
		s_explode.rpc(pos, 3.3)
	else:
		s_explode(pos, 3.3)


# ================================================================ contêineres (baú / fornalha)
func container_get(pos: Vector3i) -> Dictionary:
	if not online or is_host:
		if not containers.data.has(pos):
			var b := world.get_block(pos.x, pos.y, pos.z)
			if Blocks.is_container(b):
				containers.ensure(pos, b)
		return containers.data.get(pos, {})
	return _cache.get(pos, {})


func container_request(pos: Vector3i) -> void:
	if online and not is_host:
		c_creq.rpc_id(1, pos)
	else:
		container_get(pos)


func container_click(pos: Vector3i, idx: int, btn: int, cursor, cb: Callable) -> void:
	if not online or is_host:
		var d := container_get(pos)
		if d.is_empty():
			cb.call(cursor)
			return
		cb.call(_cont_click(d, idx, btn, cursor))
	else:
		_pending_cb = cb
		c_cclick.rpc_id(1, pos, idx, btn, cursor)


func _cont_click(d: Dictionary, idx: int, btn: int, cursor):
	var sl: Array = d["slots"]
	if idx < 0 or idx >= sl.size():
		return cursor
	if cursor != null and (not (cursor is Array) or cursor.size() < 3 or not Blocks.defs.has(int(cursor[0])) or int(cursor[1]) < 1 or int(cursor[1]) > 64):
		return null
	if d["type"] == "furnace":
		if idx == 2:
			if cursor != null:
				var o = sl[2]
				if o != null and o[0] == cursor[0] and Blocks.stack_of(o[0]) > 1:
					var t: int = mini(o[1], Blocks.stack_of(o[0]) - cursor[1])
					cursor[1] += t
					o[1] -= t
					if o[1] <= 0:
						sl[2] = null
				return cursor
		elif idx == 1 and cursor != null and Blocks.fuel_time(cursor[0]) <= 0.0:
			return cursor
	return Containers.click(sl, idx, btn, cursor)


func container_destroyed(pos: Vector3i, d: Dictionary) -> void:
	for st in containers.all_items(d):
		spawn_drop_net(st[0], st[1], Vector3(pos) + Vector3(0.5, 0.5, 0.5), Vector3(randf_range(-1, 1), 3, randf_range(-1, 1)), 0.3)


# ================================================================ chat e comandos
func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	if text.begins_with("/"):
		_command(text)
		return
	if online and not is_host:
		c_chat.rpc_id(1, text)
	else:
		_broadcast_chat(Settings.player_name, text)


func _broadcast_chat(nm: String, text: String) -> void:
	chat_ui.message(nm, text)
	if dedicated:
		print("[chat] <%s> %s" % [nm, text])
	if online and is_host:
		s_chat.rpc(nm, text)


func _command(text: String) -> void:
	var p := text.substr(1).split(" ", false)
	if p.is_empty():
		return
	var cheat := not locked
	match p[0]:
		"ajuda", "help":
			chat_ui.system("/gm c|s  /time dia|noite|<0-1>  /give <id> [qtd]  /tp x y z  /spawn  /heal  /kill  /seed  /mob <tipo>  /itens" if cheat else "Servidor público: /spawn  /kill  /seed")
		"gm", "gamemode":
			if cheat and p.size() > 1:
				creative_mode = p[1].begins_with("c") or p[1] == "1"
				local_player.creative = creative_mode
				if not creative_mode:
					local_player.flying = false
				chat_ui.system("Modo: %s" % ("Criativo" if creative_mode else "Sobrevivência"))
		"time":
			if cheat and p.size() > 1 and (not online or is_host):
				match p[1]:
					"dia", "day":
						time_of_day = 0.3
					"noite", "night":
						time_of_day = 0.78
					_:
						time_of_day = fposmod(float(p[1]), 1.0)
				if online:
					s_time.rpc(time_of_day)
				chat_ui.system("Hora ajustada.")
			else:
				chat_ui.system("Só o anfitrião muda a hora.")
		"give":
			if cheat and p.size() > 1:
				var id := int(p[1])
				var n := int(p[2]) if p.size() > 2 else 1
				if Blocks.defs.has(id):
					local_player.inv.add(id, n)
					chat_ui.system("Recebeu %s x%d" % [Blocks.name_of(id), n])
				else:
					chat_ui.system("ID inválido. Use /itens")
		"itens":
			var s := ""
			for id in Blocks.defs:
				s += "%d=%s, " % [id, Blocks.name_of(id)]
			chat_ui.system(s.substr(0, 700))
		"tp":
			if cheat and p.size() >= 4:
				local_player.teleport(Vector3(float(p[1]), float(p[2]), float(p[3])))
		"spawn":
			local_player.teleport(spawn_point)
		"heal":
			if cheat:
				local_player.health = 20.0
				local_player.hunger = 20.0
		"kill":
			var was := local_player.creative
			local_player.creative = false
			local_player.take_damage(9999.0, Vector3.ZERO, 0, true)
			local_player.creative = was
		"seed":
			chat_ui.system("Semente: %d" % world.seed_val)
		"mob":
			if cheat and p.size() > 1 and Mob.TYPES.has(p[1]) and (not online or is_host):
				_spawn_mob(p[1], local_player.global_position + (-local_player.cam.global_transform.basis.z) * 3.0 + Vector3(0, 1, 0))
		_:
			chat_ui.system("Comando desconhecido. /ajuda")


# ================================================================ rede
func net_send_state(pos: Vector3, yaw: float, pitch: float, held: int, swing: bool, sneak: bool) -> void:
	if not online or multiplayer.multiplayer_peer == null \
		or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if is_host:
		s_state.rpc(1, pos, yaw, pitch, held, swing, sneak)
	else:
		c_state.rpc_id(1, pos, yaw, pitch, held, swing, sneak)


func _others(except: int) -> Array:
	var out: Array = []
	for pid in multiplayer.get_peers():
		if pid != except and remotes.has(pid):
			out.append(pid)
	return out


func _on_peer_connected(id: int) -> void:
	if is_host:
		print("[net] conexão id=", id)


func _on_peer_disconnected(id: int) -> void:
	if remotes.has(id):
		chat_ui.system("%s saiu." % remotes[id].pname)
		if dedicated:
			print("[net] saiu: ", remotes[id].pname)
		remotes[id].queue_free()
		remotes.erase(id)
		if is_host:
			s_player_left.rpc(id)


func _on_connected_ok() -> void:
	menu.toast("Conectado! Baixando mundo...")
	c_join.rpc_id(1, Settings.player_name, PROTO)


func _on_connect_fail() -> void:
	_cleanup_world()
	menu.show_main(FileAccess.file_exists(SAVE_PATH))
	menu.toast("Falha na conexão.")


func _on_server_gone() -> void:
	_cleanup_world()
	menu.show_main(FileAccess.file_exists(SAVE_PATH))
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
	chat_ui.system("%s entrou." % nm)


func _valid_reach(sender: int, x: int, y: int, z: int) -> bool:
	if y < 0 or y >= World.CH or absi(x) > 30000000 or absi(z) > 30000000:
		return false
	if remotes.has(sender):
		var p: Vector3 = remotes[sender].global_position
		return Vector3(x + 0.5, y + 0.5, z + 0.5).distance_to(p + Vector3(0, 1, 0)) < 12.0
	return false


# ---- cliente -> servidor
@rpc("any_peer", "reliable")
func c_join(nm: String, ver: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if ver != PROTO:
		s_kick.rpc_id(sender, "Versão do jogo diferente do servidor.")
		return
	if remotes.size() >= max_players:
		s_kick.rpc_id(sender, "Servidor cheio.")
		return
	nm = nm.strip_edges().substr(0, 16)
	if nm == "":
		nm = "Jogador"
	s_welcome.rpc_id(sender, world.seed_val, creative_mode, mobs_enabled, time_of_day, spawn_point, locked)
	var ed := world.export_edits()
	var batch: Array = []
	for cp in ed:
		var keys := PackedInt32Array()
		var ids := PackedByteArray()
		for k in ed[cp]:
			keys.append(int(k))
			ids.append(int(ed[cp][k]))
		batch.append([cp.x, cp.y, keys, ids])
		if batch.size() >= 40:
			s_edits.rpc_id(sender, batch)
			batch = []
	if batch.size() > 0:
		s_edits.rpc_id(sender, batch)
	var plist: Array = []
	if local_player != null:
		plist.append([1, Settings.player_name])
	for rid in remotes:
		plist.append([rid, remotes[rid].pname])
	s_ready.rpc_id(sender, plist)
	_add_remote(sender, nm)
	for pid in _others(sender):
		s_player_joined.rpc_id(pid, sender, nm)
	if dedicated:
		print("[net] entrou: %s id=%d (%d online)" % [nm, sender, remotes.size()])


@rpc("any_peer", "unreliable")
func c_state(pos: Vector3, yaw: float, pitch: float, held: int, swing: bool, sneak: bool) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not remotes.has(sender):
		return
	remotes[sender].net_apply(pos, yaw, pitch, held, swing, sneak)
	for pid in _others(sender):
		s_state.rpc_id(pid, sender, pos, yaw, pitch, held, swing, sneak)


@rpc("any_peer", "reliable")
func c_block(x: int, y: int, z: int, id: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _valid_reach(sender, x, y, z) or id < 0 or id > Blocks.MAX_BLOCK:
		s_block.rpc_id(sender, x, y, z, world.get_block(x, y, z))
		return
	if world.get_block(x, y, z) == Blocks.BEDROCK:
		s_block.rpc_id(sender, x, y, z, Blocks.BEDROCK)
		return
	world.set_block(x, y, z, id)
	for pid in _others(sender):
		s_block.rpc_id(pid, x, y, z, id)


@rpc("any_peer", "reliable")
func c_chat(text: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not remotes.has(sender):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_chat_t.get(sender, -10.0)) < 0.6:
		return
	_chat_t[sender] = now
	_broadcast_chat(remotes[sender].pname, text.strip_edges().substr(0, 200))


@rpc("any_peer", "reliable")
func c_hit_mob(id: int, dmg: float, kb: Vector3) -> void:
	if is_host and mobs.has(id) and dmg > 0.0 and dmg < 30.0:
		mobs[id].take_hit(dmg, kb.limit_length(12.0))


@rpc("any_peer", "reliable")
func c_hit_player(target: int, dmg: float, kb: Vector3) -> void:
	if not is_host or dmg <= 0.0 or dmg > 30.0:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not remotes.has(sender):
		return
	kb = kb.limit_length(12.0)
	if target == 1 and local_player != null:
		local_player.take_damage(dmg, kb)
	elif remotes.has(target):
		s_damage.rpc_id(target, dmg, kb)


@rpc("any_peer", "reliable")
func c_drop(nid: int, item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	if not is_host or count < 1 or count > 64:
		return
	var sender := multiplayer.get_remote_sender_id()
	_spawn_drop(nid, item, count, pos, vel, delay)
	for pid in _others(sender):
		s_drop.rpc_id(pid, nid, item, count, pos, vel, delay)


@rpc("any_peer", "reliable")
func c_pickup(nid: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if drops.has(nid):
		forget_drop(drops[nid])
	for pid in _others(sender):
		s_pickup.rpc_id(pid, nid)


@rpc("any_peer", "reliable")
func c_creq(pos: Vector3i) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if remotes.has(sender):
		var d := container_get(pos)
		if not d.is_empty():
			s_cdata.rpc_id(sender, pos, d)


@rpc("any_peer", "reliable")
func c_cclick(pos: Vector3i, idx: int, btn: int, cursor) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not remotes.has(sender):
		return
	var d := container_get(pos)
	if d.is_empty():
		s_cres.rpc_id(sender, pos, cursor, {})
		return
	var nc = _cont_click(d, idx, btn, cursor)
	s_cres.rpc_id(sender, pos, nc, d)


# ---- servidor -> clientes
@rpc("authority", "reliable")
func s_welcome(seed_val: int, creative: bool, mobs_on: bool, tod: float, spawn: Vector3, is_locked: bool) -> void:
	if not _pending_welcome:
		return
	creative_mode = creative
	mobs_enabled = mobs_on
	time_of_day = tod
	locked = is_locked
	spawn_point = spawn
	if local_player != null:
		local_player.queue_free()
		local_player = null
	world.clear_world()
	world.setup(seed_val)
	_incoming_edits = {}


@rpc("authority", "reliable")
func s_edits(batch: Array) -> void:
	for e in batch:
		var cp := Vector2i(e[0], e[1])
		var keys: PackedInt32Array = e[2]
		var ids: PackedByteArray = e[3]
		var dct := {}
		for i in keys.size():
			dct[keys[i]] = ids[i]
		_incoming_edits[cp] = dct


@rpc("authority", "reliable")
func s_ready(plist: Array) -> void:
	if not _pending_welcome:
		return
	_pending_welcome = false
	world.import_edits(_incoming_edits)
	_incoming_edits = {}
	_create_player()
	local_player.global_position = spawn_point
	_starter_kit()
	online = true
	is_host = false
	_begin_play()
	for e in plist:
		_add_remote(int(e[0]), str(e[1]))


@rpc("authority", "reliable")
func s_kick(msg: String) -> void:
	_cleanup_world()
	menu.show_main(FileAccess.file_exists(SAVE_PATH))
	menu.toast(msg)


@rpc("authority", "reliable")
func s_player_joined(id: int, nm: String) -> void:
	_add_remote(id, nm)


@rpc("authority", "reliable")
func s_player_left(id: int) -> void:
	if remotes.has(id):
		chat_ui.system("%s saiu." % remotes[id].pname)
		remotes[id].queue_free()
		remotes.erase(id)


@rpc("authority", "unreliable")
func s_state(id: int, pos: Vector3, yaw: float, pitch: float, held: int, swing: bool, sneak: bool) -> void:
	if remotes.has(id):
		remotes[id].net_apply(pos, yaw, pitch, held, swing, sneak)


@rpc("authority", "reliable")
func s_block(x: int, y: int, z: int, id: int) -> void:
	world.set_block(x, y, z, id)


@rpc("authority", "reliable")
func s_chat(nm: String, text: String) -> void:
	chat_ui.message(nm, text)


@rpc("authority", "unreliable")
func s_mobs(arr: Array) -> void:
	if is_host or local_player == null:
		return
	var seen: Dictionary = {}
	for s in arr:
		var id: int = s[0]
		seen[id] = true
		if not mobs.has(id):
			var m := _spawn_mob(s[1], s[2], id)
			m.puppet = true
		(mobs[id] as Mob).net_apply(s[2], s[3], s[4], s[5])
	for id in mobs.keys():
		if not seen.has(id):
			_remove_mob(id)


@rpc("authority", "reliable")
func s_damage(dmg: float, kb: Vector3) -> void:
	if local_player != null:
		local_player.take_damage(dmg, kb)


@rpc("authority", "reliable")
func s_drop(nid: int, item: int, count: int, pos: Vector3, vel: Vector3, delay: float) -> void:
	_spawn_drop(nid, item, count, pos, vel, delay)


@rpc("authority", "reliable")
func s_pickup(nid: int) -> void:
	if drops.has(nid):
		forget_drop(drops[nid])


@rpc("authority", "reliable", "call_local")
func s_arrow(pos: Vector3, vel: Vector3) -> void:
	var a := Arrow.new()
	a.vel = vel
	a.game = self
	a.world = world
	a.position = pos
	entities.add_child(a)


@rpc("authority", "reliable", "call_local")
func s_explode(pos: Vector3, radius: float) -> void:
	world.explode(pos, radius)
	if local_player != null and not local_player.dead:
		var to := local_player.global_position + Vector3(0, 0.9, 0) - pos
		var d := to.length()
		if d < radius * 1.8:
			var dmg := (1.0 - d / (radius * 1.8)) * 16.0
			var kb := Vector3(to.x, 0, to.z).normalized() * 9.0
			local_player.take_damage(dmg, kb, 0, true)


@rpc("authority", "unreliable")
func s_time(t: float) -> void:
	time_of_day = t


@rpc("authority", "reliable")
func s_cdata(pos: Vector3i, d: Dictionary) -> void:
	_cache[pos] = d


@rpc("authority", "reliable")
func s_cres(pos: Vector3i, cursor, d: Dictionary) -> void:
	if not d.is_empty():
		_cache[pos] = d
	if _pending_cb.is_valid():
		var cb := _pending_cb
		_pending_cb = Callable()
		cb.call(cursor)
