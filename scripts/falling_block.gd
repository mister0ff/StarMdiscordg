class_name FallingBlock
extends Node3D
## Bloco em queda (areia, cascalho): cai acelerando e pousa como bloco ao tocar o chão.

var world: World
var block_id := 0
var _vel := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = world.make_block_mesh(block_id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(delta: float) -> void:
	var bx := floori(position.x)
	var bz := floori(position.z)
	if not world.is_loaded(bx, bz):
		return # espera o chunk carregar
	_vel = minf(_vel + 26.0 * delta, 32.0)
	var ny := position.y - _vel * delta
	var cell_y := floori(ny - 0.5 + 0.001)
	var b := world.get_block(bx, cell_y, bz)
	if cell_y < 1 or (b != Blocks.AIR and not Blocks.is_water(b) and b != Blocks.TORCH):
		_land(bx, maxi(cell_y + 1, 1), bz)
		return
	position.y = ny
	if position.y < -20.0:
		queue_free()


func _land(x: int, y: int, z: int) -> void:
	var cy := y
	for i in 4:
		var cur := world.get_block(x, cy, z)
		if cur == Blocks.AIR or Blocks.is_water(cur) or cur == Blocks.TORCH:
			world.set_block(x, cy, z, block_id, false)
			break
		cy += 1
	queue_free()
