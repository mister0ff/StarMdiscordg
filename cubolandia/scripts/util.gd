class_name Util
extends RefCounted
## Funções utilitárias estáticas.


## Interseção raio x AABB. Retorna distância t (>=0) ou -1.
static func ray_aabb(o: Vector3, d: Vector3, bmin: Vector3, bmax: Vector3) -> float:
	var tmin := 0.0
	var tmax := 1e9
	for i in 3:
		if absf(d[i]) < 1e-8:
			if o[i] < bmin[i] or o[i] > bmax[i]:
				return -1.0
		else:
			var inv := 1.0 / d[i]
			var t1 := (bmin[i] - o[i]) * inv
			var t2 := (bmax[i] - o[i]) * inv
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


static func make_box(size: Vector3, color: Color, offset := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.position = offset
	return m
