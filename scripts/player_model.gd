class_name PlayerModel
extends Node3D
## Corpo de jogador em caixas (usado por você em 2ª/3ª pessoa, outros jogadores e o avatar do menu).

var _head: Node3D
var _legs: Array = []
var _arms: Array = []
var _held: Sprite3D
var _mats: Array = []
var _base: Array = []
var _anim := 0.0
var _flash := 0.0


func build(skin: Color, shirt: Color, pants: Color, hair: Color) -> void:
	_box(self, Vector3(0.5, 0.72, 0.26), shirt, Vector3(0, 1.1, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 1.72, 0)
	_box(_head, Vector3(0.5, 0.5, 0.5), skin, Vector3.ZERO)
	for sx in [-1, 1]:
		_box(_head, Vector3(0.09, 0.09, 0.03), Color(0.1, 0.2, 0.5), Vector3(sx * 0.12, 0.03, -0.26))
	_box(_head, Vector3(0.52, 0.14, 0.52), hair, Vector3(0, 0.22, 0.01))
	add_child(_head)
	for sx in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.13, 0.74, 0)
		_box(leg, Vector3(0.23, 0.74, 0.24), pants, Vector3(0, -0.37, 0))
		add_child(leg)
		_legs.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.36, 1.42, 0)
		_box(arm, Vector3(0.2, 0.68, 0.2), skin, Vector3(0, -0.3, 0))
		add_child(arm)
		_arms.append(arm)
	_held = Sprite3D.new()
	_held.pixel_size = 0.025
	_held.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_held.position = Vector3(0, -0.6, -0.3)
	_arms[1].add_child(_held)


func _box(parent: Node3D, size: Vector3, col: Color, off: Vector3) -> void:
	var m := Util.make_box(size, col, off)
	parent.add_child(m)
	_mats.append(m.material_override)
	_base.append(col)


func set_pitch(p: float) -> void:
	_head.rotation.x = p


func set_held(tex: Texture2D) -> void:
	_held.texture = tex


func flash() -> void:
	_flash = 0.35


func animate(delta: float, spd: float, swinging: bool, sneaking := false) -> void:
	_anim += delta * (3.0 + spd * 1.6)
	var amp := clampf(spd / 4.0, 0.0, 1.0) * 0.8
	_legs[0].rotation.x = sin(_anim) * amp
	_legs[1].rotation.x = -sin(_anim) * amp
	_arms[0].rotation.x = -sin(_anim) * amp
	_arms[1].rotation.x = sin(_anim) * amp - (1.2 if swinging else 0.0)
	_head.position.y = 1.58 if sneaking else 1.72
	_flash = maxf(0.0, _flash - delta)
	for i in _mats.size():
		var c: Color = _base[i]
		if _flash > 0.0:
			c = c.lerp(Color(1, 0.15, 0.1), 0.6)
		(_mats[i] as StandardMaterial3D).albedo_color = c
