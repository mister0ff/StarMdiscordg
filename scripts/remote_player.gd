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
var _model: PlayerModel
var _label: Label3D
var _swing := false
var _last := Vector3.ZERO
var _sneak := false


func _ready() -> void:
	add_to_group("hittable")
	add_to_group("remote_players")
	var rng := RandomNumberGenerator.new()
	rng.seed = peer_id * 7919
	_model = PlayerModel.new()
	_model.build(Color(0.85, 0.65, 0.5), Color.from_hsv(rng.randf(), 0.6, 0.85), Color(0.2, 0.25, 0.55), Color(0.25, 0.15, 0.08))
	add_child(_model)
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


func flash() -> void:
	_model.flash()


func net_apply(pos: Vector3, yaw: float, pitch: float, held: int, swing: bool, sneak: bool) -> void:
	_tpos = pos
	_tyaw = yaw
	_tpitch = pitch
	_swing = swing
	_sneak = sneak
	_model.set_held(Blocks.icon(held) if held != 0 else null)
	_label.position.y = 2.05 if sneak else 2.25


func _process(delta: float) -> void:
	global_position = global_position.lerp(_tpos, clampf(delta * 14.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _tyaw, clampf(delta * 14.0, 0.0, 1.0))
	_model.set_pitch(_tpitch)
	var spd := (global_position - _last).length() / maxf(delta, 0.001)
	_last = global_position
	_model.animate(delta, spd, _swing, _sneak)
