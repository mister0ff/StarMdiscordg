class_name ItemDrop
extends Node3D
## Item caído no chão. Física simples própria (sem colisão de engine).

var item_id := 0
var count := 1
var net_id := 0
var vel := Vector3.ZERO
var delay := 0.5
var game: Node
var world: World
var _age := 0.0
var _spr: Sprite3D
var _on_ground := false


func _ready() -> void:
	_spr = Sprite3D.new()
	_spr.texture = Blocks.icon(item_id)
	_spr.pixel_size = 0.028
	_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_spr.shaded = false
	_spr.position.y = 0.3
	add_child(_spr)


func _process(delta: float) -> void:
	_age += delta
	delay -= delta
	if _age > 300.0:
		queue_free()
		return
	_spr.position.y = 0.3 + sin(_age * 3.0) * 0.06
	var p := global_position
	if not world.is_loaded(floori(p.x), floori(p.z)):
		return
	# magnetismo / coleta (apenas jogador local)
	var pl: Player = game.local_player
	if pl != null and delay <= 0.0 and not pl.dead:
		var to := pl.global_position + Vector3(0, 0.8, 0) - p
		var d := to.length()
		if d < 0.9:
			if game.try_pickup(self):
				return
		elif d < 2.8:
			vel = to.normalized() * 9.0
			_on_ground = false
	if not _on_ground:
		vel.y -= 22.0 * delta
	var np := p + vel * delta
	if Blocks.is_solid(world.get_block(floori(np.x), floori(p.y), floori(np.z))):
		vel.x = 0.0
		vel.z = 0.0
		np.x = p.x
		np.z = p.z
	if Blocks.is_solid(world.get_block(floori(np.x), floori(np.y), floori(np.z))):
		if vel.y < 0.0:
			_on_ground = true
		vel.y = 0.0
		vel.x *= 0.6
		vel.z *= 0.6
		np.y = floorf(np.y) + 1.0 if vel.y <= 0.0 and np.y < p.y else p.y
	else:
		_on_ground = false
	if _on_ground:
		vel.x = move_toward(vel.x, 0.0, 12.0 * delta)
		vel.z = move_toward(vel.z, 0.0, 12.0 * delta)
	global_position = np
