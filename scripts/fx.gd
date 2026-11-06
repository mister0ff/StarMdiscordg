class_name Fx
extends RefCounted
## Partículas leves (CPUParticles3D de disparo único).

static var root: Node = null


static func burst(pos: Vector3, color: Color, amount: int = 12, speed: float = 3.0, size: float = 0.09, life: float = 0.6, grav: float = 12.0) -> void:
	if root == null or not is_instance_valid(root) or not root.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -grav, 0)
	p.scale_amount_min = size
	p.scale_amount_max = size * 1.6
	p.color = color
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	bm.material = mat
	p.mesh = bm
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


static func block_break(pos: Vector3i, id: int) -> void:
	burst(Vector3(pos) + Vector3(0.5, 0.5, 0.5), Blocks.avg_color(id), 14, 3.0, 0.1, 0.7, 14.0)


static func block_hit(pos: Vector3i, normal: Vector3i, id: int) -> void:
	burst(Vector3(pos) + Vector3(0.5, 0.5, 0.5) + Vector3(normal) * 0.55, Blocks.avg_color(id), 3, 1.6, 0.07, 0.4, 10.0)


static func crit(pos: Vector3) -> void:
	burst(pos, Color(1.0, 0.95, 0.5), 14, 4.5, 0.08, 0.5, 2.0)


static func hurt(pos: Vector3) -> void:
	burst(pos, Color(0.85, 0.1, 0.1), 8, 2.5, 0.07, 0.5, 8.0)


static func eat(pos: Vector3, id: int) -> void:
	burst(pos, Blocks.avg_color(id), 6, 1.8, 0.05, 0.45, 9.0)
