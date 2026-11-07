class_name Particles
extends Node3D
## Partículas de quebra de bloco (cubinhos coloridos) usando um único MultiMesh.

const MAX := 300

var world: World
var _mm: MultiMesh
var _inst: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _p: Array = [] # cada: [pos, vel, life, color, size]


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	bm.material = _mat
	_mm.mesh = bm
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	_inst = MultiMeshInstance3D.new()
	_inst.multimesh = _mm
	_inst.custom_aabb = AABB(Vector3(-100000, -1000, -100000), Vector3(200000, 2000, 200000))
	add_child(_inst)


func set_light(l: float) -> void:
	var v := clampf(l, 0.35, 1.0)
	_mat.albedo_color = Color(v, v, v)


func burst(block_id: int, pos: Vector3, n: int) -> void:
	if not Settings.particles:
		return
	for i in n:
		_add(block_id, pos + Vector3(randf(), randf(), randf()) - Vector3(0.5, 0.5, 0.5), 2.2)


## Poucas partículas na face que está sendo quebrada.
func chip(block_id: int, bpos: Vector3i, normal: Vector3i, n: int) -> void:
	if not Settings.particles:
		return
	var c := Vector3(bpos) + Vector3(0.5, 0.5, 0.5) + Vector3(normal) * 0.52
	for i in n:
		var off := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.9
		off -= Vector3(normal) * off.dot(Vector3(normal))
		_add(block_id, c + off, 1.0, Vector3(normal) * 1.5)


func _add(block_id: int, pos: Vector3, speed: float, extra := Vector3.ZERO) -> void:
	if _p.size() >= MAX:
		_p.pop_front()
	var v := Vector3(randf_range(-1, 1), randf_range(0.5, 2.2), randf_range(-1, 1)) * speed + extra
	_p.append([pos, v, randf_range(0.5, 1.1), Blocks.block_color(block_id), randf_range(0.06, 0.13)])


func _process(delta: float) -> void:
	var n := _p.size()
	if n == 0:
		if _mm.visible_instance_count != 0:
			_mm.visible_instance_count = 0
		return
	var i := 0
	while i < _p.size():
		var q: Array = _p[i]
		q[2] -= delta
		if q[2] <= 0.0:
			_p[i] = _p[_p.size() - 1]
			_p.pop_back()
			continue
		var v: Vector3 = q[1]
		v.y -= 16.0 * delta
		var pos: Vector3 = q[0]
		var np := pos + v * delta
		if Blocks.is_solid(world.get_block(floori(np.x), floori(np.y), floori(np.z))):
			v = Vector3(v.x * 0.3, 0.0, v.z * 0.3)
			np = pos
		q[0] = np
		q[1] = v
		i += 1
	_mm.visible_instance_count = _p.size()
	for k in _p.size():
		var q2: Array = _p[k]
		var sz: float = q2[4]
		var t := Transform3D(Basis().scaled(Vector3(sz, sz, sz)), q2[0])
		_mm.set_instance_transform(k, t)
		_mm.set_instance_color(k, q2[3])
