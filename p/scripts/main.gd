extends Node
## Controlador principal: fluxo do jogo, dia/noite, mobs, rede (ENet), PvP, chat, salvamento.

const DAY_LEN := 1800.0
const PORT := 25565
const PANORAMA_SEED := 20261105

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
var commands: CommandRunner
var meta: Dictionary = {}
var rules: Dictionary = {}
var pan_cam: Camera3D
var panorama_on := false
var _pan_t := 0.0
var _pan_center := Vector3.ZERO
var _sec_t := 0.0

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
	_build_environment()
	world = World.new()
	world.name = "World"
	add_child(world)
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)
	_build_ui()
	commands = CommandRunner.new(self)
	ModManager.main = self
	pan_cam = Camera3D.new()
	pan_cam.far = 300.0
	pan_cam.fov = 70.0
	add_child(pan_cam)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_fail)
	multiplayer.server_disconnected.connect(_on_server_gone)
	var args := OS.get_cmdline_user_args()
	if "--autostart" in args or "--host" in args:
		var m := WorldStore.new_meta("Teste", 4242, "normal", "--creative" in args, WorldStore.DEFAULT_RULES)
		m["id"] = "teste_tmp"
		start_world(m, PORT if "--host" in args else 0)
	elif "--join" in args:
		join_server("127.0.0.1", PORT)
	else:
		# menu primeiro: mesmo que o panorama 3D falhe no celular, a tela inicial aparece
		menu.show_main()
		await get_tree().process_frame
		start_panorama()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		on_back_pressed()


## Botão "voltar" do Android (e equivalente)
func on_back_pressed() -> void:
	if menu != null and menu.visible:
		menu.go_back()
		return
	if not playing or local_player == null or local_player.dead:
		return
	if touch.edit_mode:
		return
	if inv_ui.visible:
		close_inventory()
	elif chat_ui.is_open:
		chat_ui.close()
	else:
		pause_game()


func start_panorama() -> void:
	_cleanup_world()
	world.refresh_tables()
	world.setup(PANORAMA_SEED, "normal")
	_pan_center = world.find_spawn()
	_pan_t = 0.0
	panorama_on = true
	time_of_day = 0.3
	pan_cam.global_position = _pan_center + Vector3(0, 16, 0)
	pan_cam.make_current()


func _panorama_tick(delta: float) -> void:
	_pan_t += delta
	pan_cam.global_position = _pan_center + Vector3(0, 16, 0)
	pan_cam.rotation = Vector3(-0.22, _pan_t * 0.05, 0)
	world.set_centers([pan_cam.global_position], [clampi(Settings.render_distance, 3, 5)])
	daylight = 1.0
	world.set_daylight(1.0)
	env.background_color = _sky_day
	env.fog_light_color = _sky_day
	env.fog_density = 2.3 / float(clampi(Settings.render_distance, 3, 5) * World.CS)
	sun_pivot.global_position = pan_cam.global_position
	sun_pivot.basis = Basis(Vector3(0, 0, 1), 0.3 * TAU - PI * 0.5)


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
func is_admin() -> bool:
	if meta.get("kind", "world") == "server":
		return ServerDefs.is_admin_nick(Settings.player_name)
	return not online or is_host


func start_world(m: Dictionary, host_port := 0) -> void:
	_cleanup_world()
	panorama_on = false
	meta = m
	rules = WorldStore.rules_of(m)
	creative_mode = bool(m.get("creative", false))
	var wtype := str(m.get("type", "normal"))
	ModManager.activate_world(meta)
	WorldStore.save_meta(meta)
	world.refresh_tables()
	var data := WorldStore.read_save(meta["id"])
	var seed_val := int(meta["seed"])
	world.setup(seed_val, wtype)
	time_of_day = 0.3
	var load_save := not data.is_empty()
	if load_save:
		time_of_day = data.get("time", 0.3)
		world.import_edits(data["edits"])
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
			chat_ui.system("Servidor aberto na porta %d." % host_port)
	_begin_play()
	for e in ModManager.errors:
		chat_ui.system("[mod] " + str(e))
	if not load_save and rules.get("mob_spawning", true):
		for i in 6:
			_spawn_passive_near(spawn_point, 8.0, 30.0)


func join_server(ip: String, port: int) -> void:
	_cleanup_world()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		menu.toast("Não foi possível conectar (erro %d)" % err)
		start_panorama()
		return
	multiplayer.multiplayer_peer = peer
	online = true
	is_host = false
	_pending_welcome = true
	start_panorama_keep_net()
	menu.toast("Conectando a %s:%d ..." % [ip, port])


func start_panorama_keep_net() -> void:
	world.refresh_tables()
	world.setup(PANORAMA_SEED, "normal")
	_pan_center = world.find_spawn()
	panorama_on = true
	pan_cam.make_current()


func _create_player() -> void:
	local_player = Player.new()
	local_player.game = self
	local_player.world = world
	local_player.creative = creative_mode
	local_player.died.connect(_on_player_died)
	local_player.damaged.connect(func(): hud.flash_damage())
	local_player.station_requested.connect(func(): open_inventory())
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
	panorama_on = false
	menu.hide_all()
	hud.visible = true
	local_player.set_ui_open(false)
	touch.set_enabled(Settings.use_touch())
	_apply_view_distance()
	if not is_host and online:
		pass
	chat_ui.system("Bem-vindo! Modo: %s. Digite /ajuda no chat." % ("Criativo" if creative_mode else "Sobrevivência"))
	fire("player-spawn")


func go_menu() -> void:
	if playing and (not online or is_host):
		save_game()
	start_panorama()
	menu.show_main()


func _cleanup_world() -> void:
	playing = false
	if online and multiplayer.multiplayer_peer != null:
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
	world.clear_world()
	world.centers = []
	hud.visible = false
	touch.set_enabled(false)
	inv_ui.close()
	chat_ui.close()
	chat_ui.clear()
	get_tree().paused = false
	ModManager.deactivate()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_view_distance() -> void:
	var d := Settings.render_distance * World.CS
	env.fog_density = 2.3 / float(d)
	local_player.cam.far = float(d) * 1.6 + 40.0


# ================================================================ salvar / carregar
func save_game() -> void:
	if local_player == null or meta.is_empty():
		return
	var d := {
		"seed": world.seed_val, "time": time_of_day, "edits": world.export_edits(),
		"player": local_player.serialize(), "spawn": spawn_point,
	}
	WorldStore.write_save(meta["id"], d)
	meta["rules"] = rules
	WorldStore.save_meta(meta)


func set_rule(nm: String, v: bool) -> void:
	if not rules.has(nm):
		chat_ui.system("Regra desconhecida: " + nm)
		return
	rules[nm] = v
	meta["rules"] = rules
	WorldStore.save_meta(meta)
	chat_ui.system("Regra %s = %s" % [nm, "ligada" if v else "desligada"])


func set_creative(v: bool) -> void:
	creative_mode = v
	meta["creative"] = v
	local_player.creative = v
	if not v:
		local_player.flying = false


# ================================================================ loop
func _process(delta: float) -> void:
	if panorama_on:
		_panorama_tick(delta)
		return
	if not playing or local_player == null:
		return
	# estado inicial de carregamento do mundo
	var pts: Array = [local_player.global_position]
	var radii: Array = [Settings.render_distance]
	if online and is_host:
		for r in remotes.values():
			pts.append(r.global_position)
			radii.append(3)
	world.set_centers(pts, radii)
	# tempo
	if rules.get("always_day", false):
		time_of_day = 0.3
	else:
		time_of_day = fposmod(time_of_day + delta / DAY_LEN, 1.0)
	_update_sky()
	_sec_t += delta
	if _sec_t >= 1.0:
		_sec_t = 0.0
		fire("second")
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
	if Input.is_action_just_pressed("ui_cancel") and not menu.visible and not touch.edit_mode and not local_player.dead:
		on_back_pressed()


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
	if local_player != null:
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
	sun_pivot.global_position = local_player.cam.global_position
	sun_pivot.basis = Basis(Vector3(0, 0, 1), time_of_day * TAU - PI * 0.5)


func is_day() -> bool:
	return daylight > 0.5


# ================================================================ mobs (host/solo)
func _host_tick(delta: float) -> void:
	if not rules.get("mob_spawning", true) and mobs.is_empty():
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


func all_mob_kinds() -> Array:
	var out: Array = Mob.TYPES.keys()
	out.append_array(Blocks.mob_defs.keys())
	return out


func spawn_mob(kind: String, pos: Vector3) -> Mob:
	return _spawn_mob(kind, pos)


func _try_spawn_mob() -> void:
	if not rules.get("mob_spawning", true):
		return
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
	var night := daylight < 0.3
	if night and hostile_n < 12 and rules.get("hostile_mobs", true):
		var pos := _random_ground(base, 18.0, 36.0)
		if pos != Vector3.INF:
			var pool: Array = ["zombie", "zombie", "skeleton", "creeper"]
			for k in Blocks.mob_defs:
				if Blocks.mob_defs[k]["spawn"] in ["noite", "night", "sempre", "always"] and Blocks.mob_defs[k]["hostile"]:
					pool.append(k)
			_spawn_mob(pool[randi() % pool.size()], pos)
	elif not night and pass_n < 12 and randf() < 0.4:
		for k in Blocks.mob_defs:
			if Blocks.mob_defs[k]["spawn"] in ["dia", "day", "sempre", "always"] and not Blocks.mob_defs[k]["hostile"] and randf() < 0.3:
				var p2 := _random_ground(base, 20.0, 40.0)
				if p2 != Vector3.INF:
					_spawn_mob(k, p2)
				return
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


func mob_died(m: Mob) -> void:
	if not mobs.has(m.net_id):
		return
	fire("entity-death", {"entity": m.kind})
	for d in m.drops():
		spawn_drop_net(d[0], d[1], m.global_position + Vector3(0, 0.6, 0), Vector3(randf_range(-2, 2), 4, randf_range(-2, 2)), 0.4)
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
	Fx.block_break(entities, pos, bid)
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
		r_block.rpc(x, y, z, id)


func player_attack(ent: Node, dmg: float, kb: Vector3) -> void:
	if ent is Mob:
		var m: Mob = ent
		if not online or is_host:
			m.take_hit(dmg, kb)
		else:
			r_hit_mob.rpc_id(1, m.net_id, dmg, kb)
	elif ent is RemotePlayer:
		if rules.get("pvp", true):
			r_hit_player.rpc_id(ent.peer_id, dmg, kb)


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
	fire("player-death")
	if not creative_mode and not rules.get("keep_inventory", false):
		for i in Inventory.SIZE:
			var s = local_player.inv.slots[i]
			if s != null:
				spawn_drop_net(s[0], s[1], local_player.global_position + Vector3(0, 1, 0), Vector3(randf_range(-3, 3), 4, randf_range(-3, 3)), 1.5)
		local_player.inv.clear()
	chat_ui.system("Você morreu!")
	local_player.set_ui_open(true)
	touch.set_enabled(false)
	hud.show_death()


func respawn() -> void:
	hud.hide_death()
	local_player.respawn(spawn_point)
	local_player.set_ui_open(false)
	touch.set_enabled(Settings.use_touch())
	fire("player-spawn")


# ================================================================ scripts / eventos
func script_ctx(extra: Dictionary = {}) -> Dictionary:
	var c := {"player": Settings.player_name, "online": online, "day": daylight > 0.5, "time": time_of_day,
		"world": str(meta.get("name", "")), "item": "air", "block": "air", "entity": ""}
	var p := local_player
	if p != null:
		c["health"] = p.health
		c["hunger"] = p.hunger
		c["sneaking"] = Input.is_action_pressed("sneak")
		c["sprinting"] = p.velocity.length() > 5.0
		c["flying"] = p.flying
		c["creative"] = creative_mode
		c["on_ground"] = p.is_on_floor()
		c["x"] = floori(p.global_position.x)
		c["y"] = floori(p.global_position.y)
		c["z"] = floori(p.global_position.z)
		var h := p.held_id()
		c["item"] = Blocks.key_of(h) if h != 0 else "air"
	c.merge(extra, true)
	return c


## Dispara um evento de script. Retorna o contexto (com "__cancel" se cancelado e "damage" possivelmente alterado).
func fire(event: String, extra: Dictionary = {}) -> Dictionary:
	if not ModManager.has_event(event):
		return extra
	var ctx := script_ctx(extra)
	ModManager.run_event(event, ctx)
	return ctx


# ================================================================ chat e comandos
func broadcast_system(text: String) -> void:
	chat_ui.system(text)
	if online:
		r_sys.rpc(text)


func send_chat_raw(text: String) -> void:
	broadcast_system(text)


func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	if text.begins_with("/"):
		if not rules.get("commands", true):
			chat_ui.system("Comandos estão desativados nas regras deste mundo/servidor.")
			return
		if not is_admin():
			chat_ui.system("Só o admin pode usar comandos aqui.")
			return
		commands.run(text, {})
		return
	var ctx := fire("before-chat", {"message": text})
	if ctx.get("__cancel", false):
		return
	chat_ui.message(Settings.player_name, text)
	if online:
		r_chat.rpc(Settings.player_name, text)


# ================================================================ rede
func net_send_state(pos: Vector3, yaw: float, pitch: float, held: int, swing: bool, sneak: bool) -> void:
	if online and multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		r_state.rpc(pos, yaw, pitch, held, swing, sneak)


func _on_peer_connected(id: int) -> void:
	if is_host and playing:
		r_welcome.rpc_id(id, world.seed_val, creative_mode, true, time_of_day, world.export_edits(), spawn_point, world.world_type, rules, meta.get("idmap", {}), ModManager.collect_buffers(meta))


func _on_peer_disconnected(id: int) -> void:
	if remotes.has(id):
		chat_ui.system("%s saiu." % remotes[id].pname)
		remotes[id].queue_free()
		remotes.erase(id)


func _on_connected_ok() -> void:
	menu.toast("Conectado! Baixando mundo...")


func _on_connect_fail() -> void:
	start_panorama()
	menu.show_main()
	menu.toast("Falha na conexão.")


func _on_server_gone() -> void:
	start_panorama()
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
func r_welcome(seed_val: int, creative: bool, _mobs_on: bool, tod: float, edits: Dictionary, spawn: Vector3, wtype: String, rules_d: Dictionary, idmap: Dictionary, mod_bufs: Array) -> void:
	if not _pending_welcome:
		return
	_pending_welcome = false
	panorama_on = false
	var keep_peer := multiplayer.multiplayer_peer
	creative_mode = creative
	rules = rules_d
	meta = {"id": "remote", "name": "Online", "kind": "remote", "idmap": idmap}
	time_of_day = tod
	if local_player != null:
		local_player.queue_free()
	world.clear_world()
	ModManager.activate_buffers(mod_bufs, idmap)
	world.refresh_tables()
	world.setup(seed_val, wtype)
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
	var old := world.get_block(x, y, z)
	if old != Blocks.AIR and id == Blocks.AIR:
		Fx.block_break(entities, Vector3i(x, y, z), old)
	world.set_block(x, y, z, id)


@rpc("any_peer", "reliable")
func r_sys(text: String) -> void:
	chat_ui.system(text)


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
			var m := _spawn_mob(s[1], s[2], id)
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
	if local_player == null or creative_mode or not rules.get("pvp", true):
		return
	local_player.take_damage(dmg, kb, 0, false, "player")


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
	if rules.get("mob_griefing", true):
		world.explode(pos, radius)
	Fx.burst(entities, pos, Color(0.9, 0.9, 0.9), 24, 6.0, 0.25, 0.9)
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
