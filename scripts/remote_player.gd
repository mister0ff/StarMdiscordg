class_name RemotePlayer
extends Node3D
## Representação de outro jogador na rede.

var peer_id := 0
var pname := "Jogador"
var hit_w := 0.3
var hit_h := 1.8
var _tpos := Vector3.ZERO
var _tyaw := 0.0
var _tpitch := 0.0
var _head: Node3D
var _legs: Array = []
var _arms: Array = []
var _held: Sprite3D
var _label: Label3D
var _anim := 0.0
var _swing := false
var _last := Vector3.ZERO
var _shirt: Color
var _flash := 0.0
var _flash_mats: Array = []


func _ready() -> void:
	add_to_group("hittable")
	add_to_group("remote_players")
	var rng := RandomNumberGenerator.new()
	rng.seed = peer_id * 7919
	_shirt = Color.from_hsv(rng.randf(), 0.6, 0.85)
	var skin := Color(0.85, 0.65, 0.5)
	add_child(Util.make_box(Vector3(0.5, 0.72, 0.26), _shirt, Vector3(0, 1.1, 0)))
	_head = Node3D.new()
	_head.position = Vector3(0, 1.72, 0)
	_head.add_child(Util.make_box(Vector3(0.5, 0.5, 0.5), skin))
	for sx in [-1, 1]:
		_head.add_child(Util.make_box(Vector3(0.09, 0.09, 0.03), Color(0.1, 0.2, 0.5), Vector3(sx * 0.12, 0.03, -0.26)))
	_head.add_child(Util.make_box(Vector3(0.52, 0.14, 0.52), Color(0.25, 0.15, 0.08), Vector3(0, 0.22, 0.01)))
	add_child(_head)
	for sx in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.13, 0.74, 0)
		leg.add_child(Util.make_box(Vector3(0.23, 0.74, 0.24), Color(0.2, 0.25, 0.55), Vector3(0, -0.37, 0)))
		add_child(leg)
		_legs.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.36, 1.42, 0)
		arm.add_child(Util.make_box(Vector3(0.2, 0.68, 0.2), skin, Vector3(0, -0.3, 0)))
		add_child(arm)
		_arms.append(arm)
	_held = Sprite3D.new()
	_held.pixel_size = 0.025
	_held.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_held.position = Vector3(0, -0.6, -0.3)
	_arms[1].add_child(_held)
	_label = Label3D.new()
	_label.text = pname
	_label.position = Vector3(0, 2.25, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.008
	_label.font_size = 48
	_label.outline_size = 12
	add_child(_label)
	_tpos = global_position
	_last = global_position


func net_apply(pos: Vector3, yaw: float, pitch: float, held: int, swing: bool, sneak: bool) -> void:
	_tpos = pos
	_tyaw = yaw
	_tpitch = pitch
	_swing = swing
	_held.texture = Blocks.icon(held) if held != 0 else null
	_label.position.y = 2.05 if sneak else 2.25


func hurt() -> void:
	_flash = 0.3
	if _flash_mats.is_empty():
		_collect_mats(self)


func _collect_mats(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			_flash_mats.append([c.material_override, (c.material_override as StandardMaterial3D).albedo_color])
		_collect_mats(c)


func _update_flash(delta: float) -> void:
	if _flash_mats.is_empty():
		return
	var on := _flash > 0.0
	_flash = maxf(0.0, _flash - delta)
	for e in _flash_mats:
		var m: StandardMaterial3D = e[0]
		var base: Color = e[1]
		m.albedo_color = base.lerp(Color(1, 0.15, 0.1), 0.6) if on else base


func _process(delta: float) -> void:
	_update_flash(delta)
	global_position = global_position.lerp(_tpos, clampf(delta * 14.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _tyaw, clampf(delta * 14.0, 0.0, 1.0))
	_head.rotation.x = _tpitch
	var spd := (global_position - _last).length() / maxf(delta, 0.001)
	_last = global_position
	_anim += delta * (3.0 + spd * 1.6)
	var amp := clampf(spd / 4.0, 0.0, 1.0) * 0.8
	_legs[0].rotation.x = sin(_anim) * amp
	_legs[1].rotation.x = -sin(_anim) * amp
	_arms[0].rotation.x = -sin(_anim) * amp
	_arms[1].rotation.x = sin(_anim) * amp - (1.2 if _swing else 0.0)
