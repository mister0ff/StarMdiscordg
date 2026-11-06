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


## Caixa com sombreamento por face (cores de vértice). Centrada na origem.
static func make_shaded_box(size: Vector3, color: Color, offset := Vector3.ZERO) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for f in 6:
		var fv: Array = World.FACE_V[f]
		var shade: float = World.FACE_SHADE[f]
		var b := verts.size()
		for k in 4:
			var v: Vector3 = fv[k]
			verts.append((v - Vector3(0.5, 0.5, 0.5)) * size)
			cols.append(Color(color.r * shade, color.g * shade, color.b * shade, color.a))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := MeshInstance3D.new()
	m.mesh = am
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	m.material_override = mat
	m.position = offset
	return m


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


## Margens seguras (esq, topo, dir, baixo) em unidades do viewport (só celular).
static func safe_insets(vp: Viewport) -> Vector4:
	if not is_mobile():
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return Vector4.ZERO
	var sa: Rect2i = DisplayServer.get_display_safe_area()
	if sa.size.x <= 0 or sa.size.y <= 0:
		return Vector4.ZERO
	var scr := Vector2(DisplayServer.screen_get_size())
	var vs := vp.get_visible_rect().size
	var k := Vector2(vs.x / win.x, vs.y / win.y)
	var l := clampf(float(sa.position.x), 0.0, win.x * 0.2) * k.x
	var t := clampf(float(sa.position.y), 0.0, win.y * 0.2) * k.y
	var r := clampf(scr.x - float(sa.end.x), 0.0, win.x * 0.2) * k.x
	var b := clampf(scr.y - float(sa.end.y), 0.0, win.y * 0.2) * k.y
	return Vector4(l, t, r, b)


## Área útil da HUD (dentro das margens seguras e da margem escolhida pelo jogador).
static func hud_rect(vp: Viewport) -> Rect2:
	var vs := vp.get_visible_rect().size
	var ins := safe_insets(vp)
	var bottom := ins.w + Settings.hud_margin
	var r := Rect2(ins.x, ins.y, vs.x - ins.x - ins.z, vs.y - ins.y - bottom)
	if r.size.x < 200.0 or r.size.y < 150.0:
		return Rect2(Vector2.ZERO, vs)
	return r
