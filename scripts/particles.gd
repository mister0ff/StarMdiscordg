class_name Particles
extends Node3D
## Partículas simples (CPUParticles3D de uso único): quebrar bloco, comer, crítico, fogo...


func burst(kind: String, pos: Vector3, color := Color(1, 1, 1), count := 0) -> void:
	var p := CPUParticles3D.new()
	var amount := 14
	var life := 0.7
	var vel_min := 1.5
	var vel_max := 3.5
	var grav := Vector3(0, -12, 0)
	var size := 0.09
	var dir := Vector3(0, 1, 0)
	var spread := 180.0
	var col := color
	match kind:
		"crit":
			amount = 16
			life = 0.5
			col = Color(0.95, 0.95, 0.5)
			size = 0.07
			vel_min = 2.0
			vel_max = 4.5
			grav = Vector3(0, -3, 0)
		"eat":
			amount = 10
			life = 0.6
			size = 0.06
			vel_min = 1.0
			vel_max = 2.5
			dir = Vector3(0, 1, 0)
			spread = 60.0
		"flame", "fogo":
			amount = 12
			life = 0.6
			col = Color(1.0, 0.55, 0.1)
			grav = Vector3(0, 3, 0)
			vel_min = 0.5
			vel_max = 1.5
			spread = 30.0
		"smoke", "fumaca":
			amount = 12
			life = 1.0
			col = Color(0.4, 0.4, 0.42)
			grav = Vector3(0, 1.5, 0)
			vel_min = 0.3
			vel_max = 1.0
			spread = 40.0
		"magic", "magia":
			amount = 20
			life = 0.9
			col = Color(0.7, 0.35, 0.95)
			grav = Vector3(0, 1.0, 0)
		"hurt":
			amount = 10
			life = 0.5
			col = Color(0.85, 0.1, 0.1)
		"break":
			amount = 16
			life = 0.8
		_:
			col = Color(1, 1, 1)
	if count > 0:
		amount = count
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.gravity = grav
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	p.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	p.material_override = mat
	p.top_level = true
	add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := get_tree().create_timer(life + 0.4)
	t.timeout.connect(p.queue_free)


func block_break(pos: Vector3i, id: int) -> void:
	burst("break", Vector3(pos) + Vector3(0.5, 0.5, 0.5), Blocks.avg_color(id), 16)


func eat(pos: Vector3, id: int) -> void:
	burst("eat", pos, Blocks.avg_color(id), 8)
