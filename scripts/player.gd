class_name Player
extends CharacterBody3D
## Jogador local: movimento, voo, natação, quebrar/colocar blocos, combate, vida/fome.

signal died
signal damaged
signal station_requested

const GRAVITY := 26.0
const JUMP_V := 8.4
const EYE := 1.62

var game: Node
var world: World
var inv := Inventory.new()
var creative := false
var health := 20.0
var hunger := 20.0
var air := 10.0
var selected := 0
var flying := false
var yaw := 0.0
var pitch := 0.0
var ui_open := false
var frozen := true
var dead := false
var head: Node3D
var cam: Camera3D
var hand: Sprite3D
var outline: MeshInstance3D
var crack: MeshInstance3D
var target: Dictionary = {}
var hit_w := 0.3
var hit_h := 1.8
var arm: MeshInstance3D
var _m_attack := false
var _m_place := false
var _mine_fx := 0.0

var _break_pos := Vector3i(-99999, 0, 0)
var _break_t := 0.0
var _attack_cd := 0.0
var _place_cd := 0.0
var _mine_cd := 0.0
var _inv_time := 0.0
var _kb_time := 0.0
var _fall_peak := -1000.0
var _last_jump_tap := -10.0
var _was_jump := false
var _regen_t := 0.0
var _hunger_t := 0.0
var _starve_t := 0.0
var _drown_t := 0.0
var _swing := 0.0
var _hand_id := -1
var _sync_t := 0.0
var _sprinting := false
var _in_water := false


func _ready() -> void:
	add_to_group("local_player")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	cam = Camera3D.new()
	cam.fov = Settings.fov
	cam.near = 0.05
	cam.far = 220.0
	cam.current = true
	head.add_child(cam)
	hand = Sprite3D.new()
	hand.pixel_size = 0.028
	hand.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hand.shaded = false
	hand.no_depth_test = true
	hand.render_priority = 10
	hand.position = Vector3(0.42, -0.32, -0.75)
	hand.rotation_degrees = Vector3(0, -20, 8)
	cam.add_child(hand)
	arm = Util.make_shaded_box(Vector3(0.17, 0.17, 0.62), Settings.skin["skin"])
	arm.position = Vector3(0.5, -0.46, -0.62)
	arm.rotation_degrees = Vector3(12, 14, 0)
	var am_mat := arm.material_override as StandardMaterial3D
	am_mat.no_depth_test = true
	am_mat.render_priority = 9
	cam.add_child(arm)
	outline = MeshInstance3D.new()
	outline.top_level = true
	var am := ArrayMesh.new()
	var pts := PackedVector3Array()
	var c := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]
	for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		pts.append(c[e[0]] * 1.004 - Vector3.ONE * 0.002)
		pts.append(c[e[1]] * 1.004 - Vector3.ONE * 0.002)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	outline.mesh = am
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_color = Color(0, 0, 0, 0.9)
	outline.material_override = om
	add_child(outline)
	crack = Util.make_box(Vector3.ONE * 1.006, Color(0, 0, 0, 0.0))
	crack.top_level = true
	(crack.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack.visible = false
	add_child(crack)
	inv.changed.connect(func(): _hand_id = -1)


# ---------------------------------------------------------------- entrada
func apply_look(d: Vector2) -> void:
	yaw -= d.x
	pitch = clampf(pitch - d.y, -1.55, 1.55)
	rotation.y = yaw
	head.rotation.x = pitch


func _unhandled_input(event: InputEvent) -> void:
	if ui_open or dead:
		return
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if not Settings.mouse_seen:
			Settings.mouse_seen = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		apply_look(event.relative * 0.0022 * Settings.look_sens)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var ka: Dictionary = Settings.keys["attack"]
		var kp: Dictionary = Settings.keys["place"]
		if ka["t"] == "m" and int(ka["c"]) == event.button_index:
			_m_attack = event.pressed
		if kp["t"] == "m" and int(kp["c"]) == event.button_index:
			_m_place = event.pressed
	if event.is_action_pressed("hotbar_next"):
		selected = (selected + 1) % 9
	elif event.is_action_pressed("hotbar_prev"):
		selected = (selected + 8) % 9
	elif event.is_action_pressed("fly") and creative:
		flying = not flying
	elif event.is_action_pressed("drop"):
		_drop_selected(Input.is_key_pressed(KEY_CTRL))
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			selected = k - KEY_1


func _drop_selected(whole: bool) -> void:
	var s = inv.slots[selected]
	if s == null or creative:
		return
	var n: int = s[1] if whole else 1
	var id: int = s[0]
	inv.take_from(selected, n)
	var d := -cam.global_transform.basis.z
	game.spawn_drop_net(id, n, cam.global_position + d * 0.5, d * 5.0 + Vector3.UP * 2.0, 1.5)


func held_id() -> int:
	return inv.get_id(selected)


func set_ui_open(v: bool) -> void:
	ui_open = v
	if v:
		_m_attack = false
		_m_place = false
	if not Settings.use_touch() or Settings.mouse_seen:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if v else Input.MOUSE_MODE_CAPTURED
	if v:
		_reset_break()


# ---------------------------------------------------------------- física
func _physics_process(delta: float) -> void:
	if dead:
		return
	if frozen:
		if world.is_loaded(floori(global_position.x), floori(global_position.z)):
			frozen = false
		else:
			return
	_inv_time = maxf(0.0, _inv_time - delta)
	_kb_time = maxf(0.0, _kb_time - delta)
	var pos := global_position
	var feet_id := world.get_block(floori(pos.x), floori(pos.y + 0.2), floori(pos.z))
	var head_id := world.get_block(floori(pos.x), floori(pos.y + EYE), floori(pos.z))
	_in_water = feet_id == Blocks.WATER
	var head_water := head_id == Blocks.WATER

	var iv := Vector2.ZERO
	var jump := false
	var sneak := false
	if not ui_open:
		iv = Input.get_vector("left", "right", "forward", "back")
		jump = Input.is_action_pressed("jump")
		sneak = Input.is_action_pressed("sneak")
	if jump and not _was_jump and creative:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_jump_tap < 0.3:
			flying = not flying
		_last_jump_tap = now
	_was_jump = jump
	if is_on_floor() and flying and not jump:
		flying = false

	_sprinting = false
	var speed := 4.3
	if sneak and not flying:
		speed = 1.7
	elif (Input.is_action_pressed("sprint") or (Settings.use_touch() and iv.length() > 0.96)) and iv.y < -0.1 and hunger > 6.0:
		speed = 5.9
		_sprinting = true
	if _in_water:
		speed *= 0.6
	if flying:
		speed = 11.0 if not _sprinting else 17.0
	var dir := (transform.basis * Vector3(iv.x, 0, iv.y))
	var target_v := dir * speed
	var accel := 45.0 if is_on_floor() or flying else 14.0
	if _kb_time > 0.0:
		accel = 2.5
	velocity.x = move_toward(velocity.x, target_v.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_v.z, accel * delta)
	if sneak and is_on_floor() and not flying:
		if not _has_ground(pos + Vector3(velocity.x * delta, 0, 0)):
			velocity.x = 0.0
		if not _has_ground(pos + Vector3(0, 0, velocity.z * delta)):
			velocity.z = 0.0

	if flying:
		var vy := 0.0
		if jump:
			vy += 8.0
		if sneak:
			vy -= 8.0
		velocity.y = move_toward(velocity.y, vy, 40.0 * delta)
	elif _in_water:
		if jump:
			velocity.y = move_toward(velocity.y, 3.6, 22.0 * delta)
		elif sneak:
			velocity.y = move_toward(velocity.y, -4.0, 14.0 * delta)
		else:
			velocity.y = move_toward(velocity.y, -1.8, 10.0 * delta)
	else:
		velocity.y -= GRAVITY * delta
		if is_on_floor() and jump:
			velocity.y = JUMP_V
		elif is_on_floor() and Settings.use_touch() and iv.length() > 0.3 and is_on_wall():
			_auto_jump(dir)

	# queda
	if not is_on_floor() and not _in_water and not flying:
		_fall_peak = maxf(_fall_peak, pos.y)
	move_and_slide()
	if is_on_floor() and _fall_peak > -999.0:
		var fall := _fall_peak - global_position.y
		if fall > 3.4 and not creative and not _in_water:
			take_damage(floorf(fall - 3.0), Vector3.ZERO, 0, true)
		_fall_peak = -1000.0
	if _in_water or flying:
		_fall_peak = -1000.0

	head.position.y = EYE - (0.18 if sneak and not flying else 0.0)
	if global_position.y < -30.0:
		game.player_fell_into_void()

	# fome / vida / ar
	if not creative:
		_survival_tick(delta, head_water)
	else:
		health = 20.0
		hunger = 20.0
		air = 10.0

	# sincronia de rede
	_sync_t += delta
	if _sync_t > 0.066:
		_sync_t = 0.0
		game.net_send_state(global_position, yaw, pitch, held_id(), _swing > 0.0, sneak)


func _has_ground(p: Vector3) -> bool:
	var fy := floori(p.y - 0.05)
	for sx in [-0.3, 0.3]:
		for sz in [-0.3, 0.3]:
			if Blocks.is_solid(world.get_block(floori(p.x + sx), fy, floori(p.z + sz))):
				return true
	return false


func _auto_jump(dir: Vector3) -> void:
	if dir.length() < 0.1:
		return
	var d := dir.normalized() * 0.55
	var p := global_position
	var fx := floori(p.x + d.x)
	var fz := floori(p.z + d.z)
	var fy := floori(p.y + 0.1)
	if Blocks.is_solid(world.get_block(fx, fy, fz)) \
		and not Blocks.is_solid(world.get_block(fx, fy + 1, fz)) \
		and not Blocks.is_solid(world.get_block(fx, fy + 2, fz)):
		velocity.y = JUMP_V


func _survival_tick(delta: float, head_water: bool) -> void:
	var drain := 0.0
	if _sprinting:
		drain = 0.04
	elif Vector2(velocity.x, velocity.z).length() > 0.5:
		drain = 0.008
	_hunger_t += (drain + 0.004) * delta * 10.0
	if _hunger_t >= 1.0:
		_hunger_t = 0.0
		hunger = maxf(0.0, hunger - 0.5)
	if hunger >= 18.0 and health < 20.0:
		_regen_t += delta
		if _regen_t >= 3.5:
			_regen_t = 0.0
			health = minf(20.0, health + 1.0)
	elif hunger <= 0.0:
		_starve_t += delta
		if _starve_t >= 4.0:
			_starve_t = 0.0
			take_damage(1.0, Vector3.ZERO, 0, true)
	if head_water:
		air = maxf(0.0, air - delta)
		if air <= 0.0:
			_drown_t += delta
			if _drown_t >= 1.0:
				_drown_t = 0.0
				take_damage(2.0, Vector3.ZERO, 0, true)
	else:
		air = minf(10.0, air + delta * 4.0)


# ---------------------------------------------------------------- interação
func _process(delta: float) -> void:
	if dead:
		return
	cam.fov = Settings.fov
	_attack_cd -= delta
	_place_cd -= delta
	_mine_cd -= delta
	_swing = maxf(0.0, _swing - delta)
	_update_hand()
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var reach := 6.0 if creative else 4.8
	target = world.raycast(origin, dir, reach) if not frozen else {}
	if target.is_empty() or ui_open:
		outline.visible = false
	else:
		outline.visible = true
		outline.global_position = Vector3(target["pos"])
		outline.global_transform.basis = Basis.IDENTITY
	if ui_open or frozen:
		crack.visible = false
		return
	var held := held_id()
	if Input.is_action_pressed("attack") or _m_attack:
		var bt: float = target["t"] if not target.is_empty() else reach
		var ent: Node = _entity_target(origin, dir, minf(bt, reach))
		if ent != null:
			_reset_break()
			if _attack_cd <= 0.0:
				_attack_cd = 0.45
				_swing = 0.25
				_do_attack(ent, dir, held)
		elif not target.is_empty():
			_mine(delta, held)
		else:
			_reset_break()
			_swing = 0.12
	else:
		_reset_break()
	if (Input.is_action_pressed("place") or _m_place) and _place_cd <= 0.0:
		_place_cd = 0.3
		_do_place(held)


func _reset_break() -> void:
	_break_t = 0.0
	_break_pos = Vector3i(-99999, 0, 0)
	if crack != null:
		crack.visible = false


func _mine(delta: float, held: int) -> void:
	var bp: Vector3i = target["pos"]
	var bid: int = target["id"]
	if bp != _break_pos:
		_break_pos = bp
		_break_t = 0.0
	_swing = 0.12
	var need := 0.0 if creative else Blocks.break_time(bid, held)
	if is_inf(need):
		crack.visible = false
		return
	if creative:
		if _mine_cd <= 0.0:
			_mine_cd = 0.2
			game.player_break_block(bp, bid, false)
		return
	_mine_fx -= delta
	if _mine_fx <= 0.0:
		_mine_fx = 0.22
		Fx.block_hit(bp, target["normal"], bid)
	_break_t += delta
	crack.visible = true
	crack.global_position = Vector3(bp) + Vector3.ONE * 0.5
	(crack.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, clampf(_break_t / need, 0.0, 1.0) * 0.65)
	if _break_t >= need:
		var harvest := Blocks.can_harvest(bid, held)
		_reset_break()
		game.player_break_block(bp, bid, harvest)
		if Blocks.has_dur(held):
			inv.use_durability(selected, 1)


func _entity_target(origin: Vector3, dir: Vector3, max_t: float) -> Node:
	var best: Node = null
	var best_t := max_t
	for n in get_tree().get_nodes_in_group("hittable"):
		if n == self:
			continue
		var p: Vector3 = n.global_position
		var w: float = n.hit_w
		var t := Util.ray_aabb(origin, dir, p + Vector3(-w, 0, -w), p + Vector3(w, n.hit_h, w))
		if t >= 0.0 and t < best_t:
			best_t = t
			best = n
	return best


func _do_attack(ent: Node, dir: Vector3, held: int) -> void:
	var dmg := Blocks.attack_damage(held)
	var crit := not is_on_floor() and not flying and not _in_water
	if crit:
		dmg *= 1.5
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var kb := flat * (9.0 if _sprinting else 6.5)
	game.player_attack(ent, dmg, kb)
	var tp: Vector3 = ent.global_position + Vector3(0, float(ent.hit_h) * 0.6, 0)
	Fx.hurt(tp)
	if crit:
		Fx.crit(tp + Vector3(0, 0.3, 0))
	if Blocks.has_dur(held) and not creative:
		inv.use_durability(selected, 1)


func _do_place(held: int) -> void:
	_swing = 0.15
	if held != 0 and Blocks.food.has(held):
		if hunger < 20.0 and not creative:
			hunger = minf(20.0, hunger + Blocks.food[held])
			Fx.eat(cam.global_position + (-cam.global_transform.basis.z) * 0.5 + Vector3(0, -0.2, 0), held)
			inv.take_from(selected, 1)
			_place_cd = 0.5
		return
	if target.is_empty():
		return
	var tid: int = target["id"]
	if (tid == Blocks.TABLE or tid == Blocks.FURNACE) and not Input.is_action_pressed("sneak"):
		_place_cd = 0.5
		station_requested.emit()
		return
	if held == 0 or not Blocks.is_block(held):
		return
	var np: Vector3i = target["pos"] + target["normal"]
	if held == Blocks.TORCH and not Blocks.is_solid(world.get_block(np.x, np.y - 1, np.z)):
		return
	var cur := world.get_block(np.x, np.y, np.z)
	if cur != Blocks.AIR and cur != Blocks.WATER:
		return
	if np.y < 0 or np.y >= World.CH:
		return
	# não colocar dentro do próprio corpo
	var p := global_position
	var bmin := Vector3(np)
	var bmax := Vector3(np) + Vector3.ONE
	if p.x + 0.3 > bmin.x and p.x - 0.3 < bmax.x and p.z + 0.3 > bmin.z and p.z - 0.3 < bmax.z \
		and p.y + 1.8 > bmin.y and p.y < bmax.y and Blocks.is_solid(held):
		return
	game.player_place_block(np, held)
	if not creative:
		inv.take_from(selected, 1)


func _update_hand() -> void:
	var id := held_id()
	if id != _hand_id:
		_hand_id = id
		hand.texture = Blocks.icon(id) if id != 0 else null
		hand.visible = id != 0
		if id != 0:
			hand.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var s := sin((0.25 - _swing) * 12.0) if _swing > 0.0 else 0.0
	hand.position = Vector3(0.42, -0.32 - s * 0.05, -0.75 + s * 0.15)
	hand.rotation_degrees = Vector3(s * 35.0, -20.0, 8.0 - s * 20.0)


# ---------------------------------------------------------------- vida
func take_damage(amount: float, kb: Vector3 = Vector3.ZERO, _from := 0, ignore_inv := false) -> void:
	if dead or amount <= 0.0:
		return
	if creative and not is_equal_approx(amount, 9999.0):
		return
	if _inv_time > 0.0 and not ignore_inv:
		return
	_inv_time = 0.5
	health -= amount
	if kb != Vector3.ZERO:
		velocity.x = kb.x
		velocity.z = kb.z
		velocity.y = maxf(velocity.y, 5.0)
		_kb_time = 0.3
	damaged.emit()
	if health <= 0.0:
		health = 0.0
		dead = true
		died.emit()


func respawn(pos: Vector3) -> void:
	dead = false
	health = 20.0
	hunger = 20.0
	air = 10.0
	velocity = Vector3.ZERO
	global_position = pos
	_fall_peak = -1000.0
	_inv_time = 2.0
	frozen = true


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_fall_peak = -1000.0
	frozen = true


func serialize() -> Dictionary:
	return {"pos": global_position, "yaw": yaw, "pitch": pitch, "health": health, "hunger": hunger,
		"inv": inv.to_array(), "sel": selected, "flying": flying}


func deserialize(d: Dictionary) -> void:
	global_position = d.get("pos", global_position)
	apply_look(Vector2.ZERO)
	yaw = d.get("yaw", 0.0)
	pitch = d.get("pitch", 0.0)
	rotation.y = yaw
	head.rotation.x = pitch
	health = d.get("health", 20.0)
	hunger = d.get("hunger", 20.0)
	selected = d.get("sel", 0)
	inv.from_array(d.get("inv", []))
	frozen = true
