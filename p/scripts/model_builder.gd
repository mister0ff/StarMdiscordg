class_name ModelBuilder
extends RefCounted
## Monta modelos de entidades de mods (caixas com UV estilo Minecraft). Unidade do modelo: pixels (16 = 1 bloco).

const FACE_V := [
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)],
	[Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
]
const FACE_UV := [
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
	[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
]


static func _panel(f: int, u: float, v: float, w: float, h: float, d: float) -> Rect2:
	match f:
		5: return Rect2(u + d, v + d, w, h)
		4: return Rect2(u + 2.0 * d + w, v + d, w, h)
		0: return Rect2(u, v + d, d, h)
		1: return Rect2(u + d + w, v + d, d, h)
		2: return Rect2(u + d, v, w, d)
	return Rect2(u + d + w, v, w, d)


static func box_mesh(size: Vector3, uv: Vector2, whole: bool, tex_size: Vector2) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var s := size / 16.0
	for f in 6:
		var r: Rect2
		if whole:
			r = Rect2(0, 0, tex_size.x, tex_size.y)
		else:
			r = _panel(f, uv.x, uv.y, size.x, size.y, size.z)
		var b := verts.size()
		for k in 4:
			var v: Vector3 = FACE_V[f][k]
			verts.append(Vector3((v.x - 0.5) * s.x, (v.y - 0.5) * s.y, (v.z - 0.5) * s.z))
			var lu: Vector2 = FACE_UV[f][k]
			uvs.append(Vector2((r.position.x + lu.x * r.size.x) / maxf(tex_size.x, 1.0), (r.position.y + lu.y * r.size.y) / maxf(tex_size.y, 1.0)))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Preenche model/legs/arms/mats/base com as partes da definição.
static func build(def: Dictionary, model: Node3D, legs: Array, arms: Array, mats: Array, base_cols: Array) -> void:
	var tex: Texture2D = def.get("tex")
	var tex_size: Vector2 = def.get("tex_size", Vector2(16, 16))
	for part in def["parts"]:
		var size: Vector3 = part["size"]
		var center: Vector3 = part["pos"] / 16.0
		var anim: String = part["anim"]
		var pivot_px: Vector3 = part["pivot"]
		var pivot: Vector3
		if pivot_px.is_finite():
			pivot = pivot_px / 16.0
		elif anim.begins_with("perna") or anim.begins_with("leg") or anim.begins_with("braco") or anim.begins_with("arm"):
			pivot = center + Vector3(0, size.y / 32.0, 0)
		else:
			pivot = center
		var mi := MeshInstance3D.new()
		mi.mesh = box_mesh(size, part["uv"], part["whole"], tex_size)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.albedo_color = Color.WHITE
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if tex != null:
			mat.albedo_texture = tex
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		else:
			mat.albedo_color = def.get("color", Color(0.5, 0.75, 0.5)) * (part["color"] as Color)
		mi.material_override = mat
		mi.position = center - pivot
		var pv := Node3D.new()
		pv.position = pivot
		pv.add_child(mi)
		model.add_child(pv)
		mats.append(mat)
		base_cols.append(mat.albedo_color)
		if anim in ["perna_a", "leg_a", "perna", "leg"]:
			pv.set_meta("phase", 0.0)
			legs.append(pv)
		elif anim in ["perna_b", "leg_b"]:
			pv.set_meta("phase", PI)
			legs.append(pv)
		elif anim in ["braco_a", "arm_a"]:
			pv.set_meta("phase", PI)
			legs.append(pv)
		elif anim in ["braco_b", "arm_b"]:
			pv.set_meta("phase", 0.0)
			legs.append(pv)
