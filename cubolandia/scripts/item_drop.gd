class_name ItemDrop
extends Node3D
## Item caído no chão, em 3D (cubo para blocos, item extrudado e grosso para o resto).

var item_id := 0
var count := 1
var net_id := 0
var vel := Vector3.ZERO
var delay := 0.5
var game: Node
var world: World
var _age := 0.0
var _mesh: MeshInstance3D
var _on_ground := false
var _phase := 0.0


func _ready() -> void:
	_phase = randf() * TAU
	_mesh = MeshInstance3D.new()
	if Blocks.is_block(item_id):
		_mesh.mesh = Blocks.block_cube_mesh(item_id, 0.3)
		_mesh.material_override = world.mat_solid
	else:
		_mesh.mesh = Blocks.item_mesh(item_id, 0.5, 0.12)
	_mesh.position.y = 0.25
	add_child(_mesh)
	if count > 1:
		var m2 := MeshInstance3D.new()
		m2.mesh = _mesh.mesh
		m2.material_override = _mesh.material_override
		m2.position = Vector3(0.08, 0.04, 0.06)
		_mesh.add_child(m2)


func _process(delta: float) -> void:
	_age += delta
	delay -= delta
	if _age > 300.0:
		game.forget_drop(self)
		return
	_mesh.position.y = 0.25 + sin(_age * 2.5 + _phase) * 0.05
	_mesh.rotation.y = _age * 1.6 + _phase
	var p := global_position
	if not world.is_loaded(floori(p.x), floori(p.z)):
		return
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
	if _on_ground and vel.length_squared() < 0.01 and not Blocks.is_solid(world.get_block(floori(p.x), floori(p.y) - 1, floori(p.z))):
		_on_ground = false
	if _on_ground and vel.length_squared() < 0.01:
		return
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
		np.y = floorf(np.y) + 1.0 if np.y < p.y else p.y
	else:
		_on_ground = false
	if _on_ground:
		vel.x = move_toward(vel.x, 0.0, 12.0 * delta)
		vel.z = move_toward(vel.z, 0.0, 12.0 * delta)
	global_position = np
