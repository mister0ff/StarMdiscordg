class_name Mob
extends CharacterBody3D
## Mobs: porco, vaca (passivos), zumbi, esqueleto, creeper (hostis).
## Simulado no host (ou no modo solo); clientes usam "puppet" interpolado.

const TYPES := {
	"pig": {"hp": 8.0, "speed": 2.0, "hostile": false, "w": 0.42, "h": 0.9},
	"cow": {"hp": 10.0, "speed": 1.8, "hostile": false, "w": 0.5, "h": 1.4},
	"zombie": {"hp": 20.0, "speed": 3.0, "hostile": true, "w": 0.3, "h": 1.9},
	"skeleton": {"hp": 16.0, "speed": 2.8, "hostile": true, "w": 0.3, "h": 1.9},
	"creeper": {"hp": 16.0, "speed": 2.6, "hostile": true, "w": 0.3, "h": 1.7},
}

var kind := "pig"
var net_id := 0
var puppet := false
var hp := 10.0
var hit_w := 0.4
var hit_h := 1.0
var hostile := false
var game: Node
var world: World

var _model: Node3D
var _legs: Array = []
var _arms: Array = []
var _mats: Array = []
var _base_cols: Array = []
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _kb := 0.0
var _flash := 0.0
var _atk_cd := 0.0
var _shoot_cd := 2.0
var _fuse := -1.0
var _flee := 0.0
var _burn_t := 0.0
var _tpos := Vector3.ZERO
var _tyaw := 0.0
var _anim_t := 0.0
var _last_pos := Vector3.ZERO
var _speed_now := 0.0


func setup(k: String) -> void:
	kind = k
	var d: Dictionary = TYPES[k]
	hp = d["hp"]
	hit_w = d["w"]
	hit_h = d["h"]
	hostile = d["hostile"]


func _ready() -> void:
	add_to_group("hittable")
	add_to_group("mobs")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = hit_w
	cap.height = hit_h
	cs.shape = cap
	cs.position.y = hit_h * 0.5
	add_child(cs)
	_model = Node3D.new()
	add_child(_model)
	_build_model()
	_tpos = global_position
	_last_pos = global_position
	_wander_t = randf() * 3.0


func _part(size: Vector3, pos: Vector3, col: Color, parent: Node3D = null) -> Node3D:
	## cria caixa; devolve o pivô (para pernas, o pivô fica no topo)
	var m := Util.make_box(size, col, Vector3.ZERO)
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.add_child(m)
	(parent if parent != null else _model).add_child(pivot)
	_mats.append(m.material_override)
	_base_cols.append(col)
	return pivot


func _leg(size: Vector3, top: Vector3, col: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = top
	var m := Util.make_box(size, col, Vector3(0, -size.y * 0.5, 0))
	pivot.add_child(m)
	_model.add_child(pivot)
	_mats.append(m.material_override)
	_base_cols.append(col)
	_legs.append(pivot)
	return pivot


func _eyes(head: Node3D, z: float, y := 0.04, gap := 0.12) -> void:
	for sx in [-1, 1]:
		var e := Util.make_box(Vector3(0.07, 0.07, 0.03), Color(0.05, 0.05, 0.05), Vector3(sx * gap, y, z))
		head.add_child(e)


func _build_model() -> void:
	match kind:
		"pig":
			var pink := Color(0.93, 0.66, 0.66)
			_part(Vector3(0.6, 0.5, 0.95), Vector3(0, 0.55, 0), pink)
			var h := _part(Vector3(0.45, 0.42, 0.42), Vector3(0, 0.7, -0.62), pink)
			_eyes(h, -0.22)
			h.add_child(Util.make_box(Vector3(0.22, 0.16, 0.08), Color(0.97, 0.5, 0.55), Vector3(0, -0.06, -0.24)))
			for p in [Vector3(-0.2, 0.3, -0.3), Vector3(0.2, 0.3, -0.3), Vector3(-0.2, 0.3, 0.3), Vector3(0.2, 0.3, 0.3)]:
				_leg(Vector3(0.18, 0.3, 0.18), p, pink.darkened(0.1))
		"cow":
			var brown := Color(0.32, 0.22, 0.16)
			_part(Vector3(0.75, 0.7, 1.2), Vector3(0, 0.95, 0), brown)
			_part(Vector3(0.4, 0.3, 0.5), Vector3(0.1, 1.0, 0.1), Color(0.95, 0.95, 0.95))
			var h := _part(Vector3(0.5, 0.5, 0.45), Vector3(0, 1.2, -0.78), brown)
			_eyes(h, -0.23)
			h.add_child(Util.make_box(Vector3(0.3, 0.2, 0.1), Color(0.85, 0.75, 0.7), Vector3(0, -0.12, -0.25)))
			h.add_child(Util.make_box(Vector3(0.08, 0.14, 0.08), Color(0.9, 0.9, 0.8), Vector3(-0.28, 0.28, 0)))
			h.add_child(Util.make_box(Vector3(0.08, 0.14, 0.08), Color(0.9, 0.9, 0.8), Vector3(0.28, 0.28, 0)))
			for p in [Vector3(-0.25, 0.6, -0.42), Vector3(0.25, 0.6, -0.42), Vector3(-0.25, 0.6, 0.42), Vector3(0.25, 0.6, 0.42)]:
				_leg(Vector3(0.2, 0.6, 0.2), p, brown.darkened(0.1))
		"zombie", "skeleton":
			var skin := Color(0.35, 0.6, 0.35) if kind == "zombie" else Color(0.86, 0.86, 0.8)
			var shirt := Color(0.25, 0.35, 0.7) if kind == "zombie" else Color(0.8, 0.8, 0.74)
			var pants := Color(0.22, 0.22, 0.5) if kind == "zombie" else Color(0.75, 0.75, 0.7)
			var w := 0.5 if kind == "zombie" else 0.36
			_part(Vector3(w, 0.72, 0.28), Vector3(0, 1.1, 0), shirt)
			var h := _part(Vector3(0.5, 0.5, 0.5), Vector3(0, 1.72, 0), skin)
			_eyes(h, -0.26, 0.04, 0.12)
			_leg(Vector3(w * 0.45, 0.74, 0.26), Vector3(-w * 0.25, 0.74, 0), pants)
			_leg(Vector3(w * 0.45, 0.74, 0.26), Vector3(w * 0.25, 0.74, 0), pants)
			for sx in [-1, 1]:
				var arm := Node3D.new()
				arm.position = Vector3(sx * (w * 0.5 + 0.1), 1.42, 0)
				var am := Util.make_box(Vector3(0.18, 0.7, 0.18), skin, Vector3(0, -0.3, 0))
				arm.add_child(am)
				_mats.append(am.material_override)
				_base_cols.append(skin)
				_model.add_child(arm)
				_arms.append(arm)
				if kind == "zombie":
					arm.rotation.x = deg_to_rad(-85)
		"creeper":
			var g := Color(0.3, 0.72, 0.3)
			_part(Vector3(0.5, 0.75, 0.32), Vector3(0, 0.85, 0), g)
			var h := _part(Vector3(0.5, 0.5, 0.5), Vector3(0, 1.45, 0), g.lightened(0.05))
			_eyes(h, -0.26, 0.06, 0.12)
			h.add_child(Util.make_box(Vector3(0.14, 0.18, 0.03), Color(0.05, 0.05, 0.05), Vector3(0, -0.12, -0.26)))
			for p in [Vector3(-0.12, 0.48, -0.2), Vector3(0.12, 0.48, -0.2), Vector3(-0.12, 0.48, 0.2), Vector3(0.12, 0.48, 0.2)]:
				_leg(Vector3(0.2, 0.48, 0.2), p, g.darkened(0.15))


# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_update_tint()
	if puppet:
		global_position = global_position.lerp(_tpos, clampf(delta * 12.0, 0.0, 1.0))
		_model.rotation.y = lerp_angle(_model.rotation.y, _tyaw, clampf(delta * 12.0, 0.0, 1.0))
		_speed_now = (global_position - _last_pos).length() / maxf(delta, 0.001)
		_last_pos = global_position
		_animate(delta)
		return
	if not world.is_loaded(floori(global_position.x), floori(global_position.z)):
		return
	_kb = maxf(0.0, _kb - delta)
	_atk_cd = maxf(0.0, _atk_cd - delta)
	_flee = maxf(0.0, _flee - delta)

	var d: Dictionary = TYPES[kind]
	var speed: float = d["speed"]
	var tgt := _nearest_player()
	var want := Vector3.ZERO
	var face := Vector3.ZERO
	if hostile and not tgt.is_empty() and tgt["dist"] < 18.0:
		var to: Vector3 = tgt["pos"] - global_position
		to.y = 0.0
		var dist := to.length()
		var dn := to.normalized() if dist > 0.01 else Vector3.ZERO
		face = dn
		match kind:
			"zombie":
				want = dn * speed
				if dist < 1.4 and absf(tgt["pos"].y - global_position.y) < 1.8 and _atk_cd <= 0.0:
					_atk_cd = 1.0
					game.damage_player(tgt["id"], 3.0, dn * 7.0)
			"skeleton":
				if dist > 9.0:
					want = dn * speed
				elif dist < 5.0:
					want = -dn * speed
				_shoot_cd -= delta
				if _shoot_cd <= 0.0 and dist < 16.0:
					_shoot_cd = 2.0
					var from := global_position + Vector3(0, 1.5, 0)
					var v: Vector3 = (tgt["pos"] + Vector3(0, 1.3, 0) - from).normalized() * 17.0
					v.y += dist * 0.12
					game.spawn_arrow_net(from, v)
			"creeper":
				if _fuse >= 0.0:
					_fuse += delta
					want = Vector3.ZERO
					if dist > 5.0:
						_fuse = -1.0
					elif _fuse >= 1.5:
						game.creeper_explode(self)
						return
				else:
					want = dn * speed
					if dist < 2.8:
						_fuse = 0.0
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 6.0)
			if randf() < 0.35:
				_wander = Vector3.ZERO
			else:
				var a := randf() * TAU
				_wander = Vector3(cos(a), 0, sin(a))
		want = _wander * speed * 0.6
		if _flee > 0.0 and not tgt.is_empty():
			var away: Vector3 = global_position - tgt["pos"]
			away.y = 0.0
			want = away.normalized() * speed * 1.7
		face = want
	if _fuse >= 0.0:
		want = Vector3.ZERO
	# queimar de dia
	if kind in ["zombie", "skeleton"] and game.daylight > 0.75:
		var sx := floori(global_position.x)
		var sz := floori(global_position.z)
		if world.surface_y(sx, sz) <= floori(global_position.y) + 1:
			_burn_t += delta
			if _burn_t >= 1.0:
				_burn_t = 0.0
				take_hit(2.0, Vector3.ZERO)
				_flash = 0.3
	if face.length() > 0.05:
		var ty := atan2(-face.x, -face.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, ty, clampf(delta * 8.0, 0.0, 1.0))
	var in_water := world.get_block(floori(global_position.x), floori(global_position.y + 0.3), floori(global_position.z)) == Blocks.WATER
	var accel := 20.0 if _kb <= 0.0 else 2.0
	velocity.x = move_toward(velocity.x, want.x, accel * delta)
	velocity.z = move_toward(velocity.z, want.z, accel * delta)
	if in_water:
		velocity.y = move_toward(velocity.y, 2.0, 20.0 * delta)
	else:
		velocity.y -= 26.0 * delta
	if is_on_floor() and is_on_wall() and want.length() > 0.1 and _kb <= 0.0:
		velocity.y = 8.0
	move_and_slide()
	_speed_now = Vector2(velocity.x, velocity.z).length()
	_animate(delta)
	if global_position.y < -20.0:
		hp = 0
		game.mob_died(self)


func _nearest_player() -> Dictionary:
	var best := {}
	var bd := INF
	for p in game.player_targets():
		var dd: float = p["pos"].distance_to(global_position)
		if dd < bd:
			bd = dd
			best = {"id": p["id"], "pos": p["pos"], "dist": dd}
	return best


func _animate(delta: float) -> void:
	_anim_t += delta * (4.0 + _speed_now * 2.5)
	var amp := clampf(_speed_now / 3.0, 0.0, 1.0) * 0.8
	for i in _legs.size():
		var ph := 0.0 if (i == 0 or i == 3) else PI
		_legs[i].rotation.x = sin(_anim_t + ph) * amp
	if kind == "skeleton":
		for i in _arms.size():
			_arms[i].rotation.x = deg_to_rad(-80)
	elif kind != "zombie":
		pass
	var s := 1.0
	if _fuse >= 0.0:
		s = 1.0 + sin(_fuse * 24.0) * 0.08 + _fuse * 0.12
	_model.scale = Vector3.ONE * s


func _update_tint() -> void:
	for i in _mats.size():
		var base: Color = _base_cols[i]
		var c := base
		if _flash > 0.0:
			c = base.lerp(Color(1, 0.15, 0.1), 0.6)
		elif _fuse >= 0.0 and int(_fuse * 12.0) % 2 == 0:
			c = base.lerp(Color(1, 1, 1), 0.7)
		(_mats[i] as StandardMaterial3D).albedo_color = c


## chamado no host: aplica dano e knockback
func take_hit(dmg: float, kb: Vector3) -> void:
	hp -= dmg
	_flash = 0.35
	_flee = 3.0
	if kb != Vector3.ZERO:
		velocity.x = kb.x
		velocity.z = kb.z
		velocity.y = 5.5
		_kb = 0.3
	if hp <= 0.0 and not puppet:
		game.mob_died(self)


func net_apply(pos: Vector3, yaw: float, new_hp: float, fuse: bool) -> void:
	_tpos = pos
	_tyaw = yaw
	if new_hp < hp:
		_flash = 0.35
	hp = new_hp
	_fuse = 0.5 if fuse else -1.0


func net_state() -> Array:
	return [net_id, kind, global_position, _model.rotation.y, hp, _fuse >= 0.0]


func drops() -> Array:
	var out: Array = []
	match kind:
		"pig":
			out.append([Blocks.RAW_PORK, randi_range(1, 3)])
		"cow":
			out.append([Blocks.RAW_BEEF, randi_range(1, 3)])
			var l := randi_range(0, 2)
			if l > 0:
				out.append([Blocks.LEATHER, l])
		"zombie":
			var r := randi_range(0, 2)
			if r > 0:
				out.append([Blocks.ROTTEN, r])
			if randf() < 0.05:
				out.append([Blocks.IRON_INGOT, 1])
		"skeleton":
			var b := randi_range(0, 2)
			if b > 0:
				out.append([Blocks.BONE, b])
		"creeper":
			var g := randi_range(0, 2)
			if g > 0:
				out.append([Blocks.GUNPOWDER, g])
	return out
