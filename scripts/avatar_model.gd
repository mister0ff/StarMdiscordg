class_name AvatarModel
extends Node3D
## Corpo do jogador local, visível nas perspectivas de 2ª e 3ª pessoa.

var _head: Node3D
var _legs: Array = []
var _arms: Array = []
var _held: Sprite3D
var _anim := 0.0
var _swing_t := 0.0


func _ready() -> void:
	var skin := Color(0.85, 0.65, 0.5)
	add_child(Util.make_box(Vector3(0.5, 0.72, 0.26), Color(0.25, 0.55, 0.85), Vector3(0, 1.1, 0)))
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


func set_held(id: int) -> void:
	_held.texture = Blocks.icon(id) if id != 0 else null


func swing() -> void:
	_swing_t = 0.3


## speed = velocidade horizontal (blocos/s)
func animate(delta: float, speed: float, pitch: float, sneaking: bool) -> void:
	_head.rotation.x = pitch
	if speed > 0.3:
		_anim += delta * speed * 1.8
	var amp := clampf(speed / 4.0, 0.0, 1.0) * 0.8
	var s := sin(_anim)
	_legs[0].rotation.x = s * amp
	_legs[1].rotation.x = -s * amp
	_arms[0].rotation.x = -s * amp
	_arms[1].rotation.x = s * amp
	if _swing_t > 0.0:
		_swing_t = maxf(0.0, _swing_t - delta)
		_arms[1].rotation.x = -1.6 * sin((1.0 - _swing_t / 0.3) * PI)
	position.y = -0.1 if sneaking else 0.0
