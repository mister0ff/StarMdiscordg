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


## Retângulo seguro da tela (notch / barra de navegação) em coordenadas do canvas.
static func safe_rect(vp: Viewport) -> Rect2:
	var vr := vp.get_visible_rect()
	var full := Rect2(Vector2.ZERO, vr.size)
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return full
	var win := DisplayServer.window_get_size()
	var sa := DisplayServer.get_display_safe_area()
	if win.x <= 0 or win.y <= 0 or sa.size.x <= 0 or sa.size.y <= 0:
		return full
	var sc := Vector2(vr.size.x / float(win.x), vr.size.y / float(win.y))
	var r := Rect2(Vector2(sa.position) * sc, Vector2(sa.size) * sc)
	r = r.intersection(full)
	if r.size.x < vr.size.x * 0.5 or r.size.y < vr.size.y * 0.5:
		return full
	return r


static func image_from_bytes(b: PackedByteArray) -> Image:
	if b.size() < 8:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if b[0] == 0x89 and b[1] == 0x50:
		err = img.load_png_from_buffer(b)
	elif b[0] == 0xFF and b[1] == 0xD8:
		err = img.load_jpg_from_buffer(b)
	elif b[0] == 0x52 and b[1] == 0x49:
		err = img.load_webp_from_buffer(b)
	if err != OK:
		return null
	return img


static func strip_accents(s: String) -> String:
	var from := "áàâãäéèêëíìîïóòôõöúùûüçñ"
	var to := "aaaaaeeeeiiiiooooouuuucn"
	var out := ""
	for ch in s.to_lower():
		var i := from.find(ch)
		out += to[i] if i >= 0 else ch
	return out


static func slug(s: String) -> String:
	var t := strip_accents(s.strip_edges())
	var out := ""
	for ch in t:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif out != "" and not out.ends_with("_"):
			out += "_"
	return out.trim_suffix("_")


static func fmt_num(v: Variant) -> String:
	if v is float and is_equal_approx(v, roundf(v)):
		return str(int(v))
	if v is float:
		return "%.2f" % v
	return str(v)
