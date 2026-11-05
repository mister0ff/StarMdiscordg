class_name Fx
extends RefCounted
## Partículas simples (CPUParticles3D de cubinhos).

static var _mat: StandardMaterial3D


static func burst(parent: Node, pos: Vector3, color: Color, count := 10, speed := 3.0, size := 0.1, life := 0.7, grav := 14.0, spread := 180.0, dir := Vector3.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = count
	p.lifetime = life
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -grav, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	p.color = color
	p.hue_variation_min = -0.02
	p.hue_variation_max = 0.02
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	bm.material = _mat
	p.mesh = bm
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func block_break(parent: Node, bpos: Vector3i, block_id: int) -> void:
	if not Blocks.defs.has(block_id):
		return
	var tiles: Array = Blocks.defs[block_id].get("tiles", ["stone"])
	var col := Blocks.tile_color(str(tiles[1] if tiles.size() > 1 else tiles[0]))
	var c := Vector3(bpos) + Vector3(0.5, 0.5, 0.5)
	burst(parent, c, col, 12, 3.2, 0.12, 0.8)
	burst(parent, c, col.darkened(0.25), 6, 2.4, 0.09, 0.7)


static func crit(parent: Node, pos: Vector3) -> void:
	burst(parent, pos, Color(1.0, 0.95, 0.65), 14, 3.5, 0.07, 0.55, 3.0)
	burst(parent, pos, Color(1, 1, 1), 8, 2.5, 0.05, 0.45, 2.0)


static func hurt(parent: Node, pos: Vector3) -> void:
	burst(parent, pos, Color(0.8, 0.1, 0.1), 7, 2.5, 0.07, 0.5, 12.0)


static func eat(parent: Node, pos: Vector3, item_id: int) -> void:
	var col := Color(0.8, 0.5, 0.3)
	if Blocks.defs.has(item_id):
		col = Blocks.defs[item_id].get("color", col)
	burst(parent, pos, col, 6, 1.8, 0.05, 0.45, 9.0, 60.0, Vector3(0, 0.6, 0.4))
