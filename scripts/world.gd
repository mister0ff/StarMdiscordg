class_name World
extends Node3D
## Mundo voxel procedural: geração por chunks, malha, colisão, raycast, edições.

const CS := 16
const CH := 64
const FLAT_H := 24
const SEA := 20
const DAY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;
uniform vec3 tint = vec3(1.0);
void fragment() {
	vec4 t = texture(atlas, UV);
	if (t.a < 0.5) discard;
	float l = max(mix(0.14, 1.0, daylight), COLOR.a);
	vec3 warm = mix(vec3(1.0, 0.9, 0.75), vec3(1.0), daylight);
	ALBEDO = t.rgb * COLOR.rgb * l * mix(vec3(0.75, 0.8, 1.0) * warm, tint, daylight);
}
"""
const WATER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, blend_mix;
uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;
void fragment() {
	vec4 t = texture(atlas, UV);
	float l = mix(0.14, 1.0, daylight);
	ALBEDO = t.rgb * COLOR.rgb * l;
	ALPHA = 0.68;
}
"""

const FACE_N := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
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
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
	[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
]
const FACE_SHADE := [0.82, 0.82, 1.0, 0.55, 0.7, 0.7]


class Chunk:
	var pos: Vector2i
	var blocks := PackedByteArray()
	var node: MeshInstance3D
	var body: StaticBody3D
	var cshape: CollisionShape3D
	var meshed := false
	var top := 0


var seed_val := 0
var world_type := "normal"
var emitters: Dictionary = {}
var _known := PackedByteArray()
var chunks: Dictionary = {}
var edits: Dictionary = {} # Vector2i -> { idx:int -> id:int }
var centers: Array = [] # Array[Vector3] (posições dos jogadores)
var center_radius: Array = []
var _gen_queue: Array = []
var _dirty: Dictionary = {}
var _mat_solid: ShaderMaterial
var _mat_water: ShaderMaterial
var _noise_h := FastNoiseLite.new()
var _noise_d := FastNoiseLite.new()
var _noise_b := FastNoiseLite.new()
var _noise_c := FastNoiseLite.new()
var _opaque := PackedByteArray()
var _solid := PackedByteArray()
var _face_uv := PackedVector2Array()
var _uv_size := Vector2.ZERO
var daylight := 1.0


func _ready() -> void:
	var sh := Shader.new()
	sh.code = DAY_SHADER
	_mat_solid = ShaderMaterial.new()
	_mat_solid.shader = sh
	var sw := Shader.new()
	sw.code = WATER_SHADER
	_mat_water = ShaderMaterial.new()
	_mat_water.shader = sw
	refresh_tables()


## Recalcula tabelas de blocos (chame depois de ativar/desativar mods).
func refresh_tables() -> void:
	_opaque.resize(256)
	_solid.resize(256)
	_known.resize(256)
	_opaque.fill(0)
	_solid.fill(0)
	_known.fill(0)
	_face_uv.resize(256 * 6)
	for id in Blocks.defs:
		if id > 255 or not Blocks.defs[id]["block"]:
			continue
		_known[id] = 1
		_opaque[id] = 1 if Blocks.is_opaque(id) else 0
		_solid[id] = 1 if Blocks.is_solid(id) else 0
		var tiles: Array = Blocks.defs[id]["tiles"]
		for f in 6:
			var tn: String = tiles[0] if f == 2 else (tiles[2] if f == 3 else tiles[1])
			_face_uv[id * 6 + f] = Blocks.tile_uv(tn)
	_uv_size = Vector2(1.0 / Blocks.ATLAS_COLS, 1.0 / Blocks._atlas_rows())
	if _mat_solid != null:
		_mat_solid.set_shader_parameter("atlas", Blocks.atlas_tex)
		_mat_water.set_shader_parameter("atlas", Blocks.atlas_tex)


func setup(new_seed: int, wtype := "normal") -> void:
	seed_val = new_seed
	world_type = wtype
	_noise_h.seed = new_seed
	_noise_h.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_h.frequency = 0.007
	_noise_h.fractal_octaves = 4
	_noise_d.seed = new_seed + 11
	_noise_d.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_d.frequency = 0.05
	_noise_b.seed = new_seed + 23
	_noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_b.frequency = 0.0035
	_noise_c.seed = new_seed + 37
	_noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_c.frequency = 0.045
	_noise_c.fractal_octaves = 2


func clear_world() -> void:
	for c in chunks.values():
		c.node.queue_free()
	chunks.clear()
	_gen_queue.clear()
	_dirty.clear()
	edits.clear()
	emitters.clear()


func set_daylight(v: float) -> void:
	daylight = v
	_mat_solid.set_shader_parameter("daylight", v)
	_mat_water.set_shader_parameter("daylight", v)
	var warm := Vector3(1.0, 1.0, 1.0)
	if v < 0.6 and v > 0.2:
		warm = Vector3(1.0, 0.8, 0.65)
	_mat_solid.set_shader_parameter("tint", warm)


# ------------------------------------------------------------ ruído e terreno
func _rand01(x: int, y: int, z: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + z * 2147483629 + seed_val * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


func height_at(wx: int, wz: int) -> int:
	if world_type == "flat":
		return FLAT_H
	var n: float = _noise_h.get_noise_2d(wx, wz)
	var m: float = _noise_b.get_noise_2d(wx, wz)
	var h: float = SEA + 4.0 + n * 13.0 + _noise_d.get_noise_2d(wx, wz) * 2.5
	if m > 0.25:
		h += (m - 0.25) * 45.0
	return clampi(int(h), 2, CH - 12)


func is_desert(wx: int, wz: int) -> bool:
	return world_type == "normal" and _noise_b.get_noise_2d(wx, wz) < -0.3


func _surface_block(wx: int, wz: int, h: int) -> int:
	if h <= SEA + 1:
		return Blocks.SAND
	if is_desert(wx, wz):
		return Blocks.SAND
	if h >= 44:
		return Blocks.SNOW
	return Blocks.GRASS


func _idx(x: int, y: int, z: int) -> int:
	return x + z * CS + y * CS * CS


func _gen_chunk(pos: Vector2i) -> void:
	var c := Chunk.new()
	c.pos = pos
	c.blocks.resize(CS * CH * CS)
	c.blocks.fill(0)
	var ox: int = pos.x * CS
	var oz: int = pos.y * CS
	var top := 0
	for z in CS:
		for x in CS:
			var wx: int = ox + x
			var wz: int = oz + z
			var h := height_at(wx, wz)
			var surf := _surface_block(wx, wz, h)
			var sub := Blocks.SAND if surf == Blocks.SAND else Blocks.DIRT
			for y in range(0, h + 1):
				var id: int
				if y == 0:
					id = Blocks.BEDROCK
				elif y == h:
					id = surf
				elif y >= h - 3:
					id = sub
				else:
					id = Blocks.STONE
					if world_type == "flat":
						pass
					elif y > 2 and y < h - 4 and _noise_c.get_noise_3d(wx, y * 1.4, wz) > 0.52:
						id = Blocks.AIR
					else:
						var r := _rand01(wx, y, wz)
						if y < 48 and r < 0.012:
							id = Blocks.COAL_ORE
						elif y < 40 and r > 0.5 and r < 0.5075:
							id = Blocks.IRON_ORE
						elif y < 16 and r > 0.9 and r < 0.9025:
							id = Blocks.DIAMOND_ORE
						elif y > h - 12 and _noise_d.get_noise_3d(wx * 1.7, y * 1.7, wz * 1.7) > 0.62:
							id = Blocks.GRAVEL
				c.blocks[_idx(x, y, z)] = id
			for y in range(h + 1, SEA + 1):
				c.blocks[_idx(x, y, z)] = Blocks.WATER
			top = maxi(top, maxi(h + 1, SEA + 1) if h < SEA else h + 1)
	# árvores (inclui as que nascem em chunks vizinhos)
	for tz in range(-2, CS + 2):
		for tx in range(-2, CS + 2):
			var wx: int = ox + tx
			var wz: int = oz + tz
			if world_type == "flat" or _rand01(wx, 77, wz) > 0.011:
				continue
			var h := height_at(wx, wz)
			if _surface_block(wx, wz, h) != Blocks.GRASS or h <= SEA + 1:
				continue
			var th := 4 + int(_rand01(wx, 78, wz) * 2.0)
			for i in range(1, th + 1):
				_put(c, tx, h + i, tz, Blocks.LOG, false)
			for dy in range(th - 2, th + 2):
				var rad := 2 if dy < th + 1 else 1
				for dx in range(-rad, rad + 1):
					for dz in range(-rad, rad + 1):
						if rad == 2 and absi(dx) == 2 and absi(dz) == 2:
							continue
						if dy == th + 1 and absi(dx) + absi(dz) > 1:
							continue
						_put(c, tx + dx, h + dy, tz + dz, Blocks.LEAVES, true)
			top = maxi(top, h + th + 2)
	if edits.has(pos):
		for k in edits[pos]:
			c.blocks[k] = edits[pos][k]
			top = maxi(top, k / (CS * CS) + 1)
	c.top = mini(CH, top + 1)
	c.node = MeshInstance3D.new()
	c.node.position = Vector3(ox, 0, oz)
	c.body = StaticBody3D.new()
	c.cshape = CollisionShape3D.new()
	c.body.add_child(c.cshape)
	c.node.add_child(c.body)
	add_child(c.node)
	chunks[pos] = c
	_dirty[pos] = true


func _put(c: Chunk, x: int, y: int, z: int, id: int, only_air: bool) -> void:
	if x < 0 or x >= CS or z < 0 or z >= CS or y < 0 or y >= CH:
		return
	var i := _idx(x, y, z)
	if only_air and c.blocks[i] != Blocks.AIR:
		return
	c.blocks[i] = id


# ------------------------------------------------------------ acesso a blocos
func get_block(wx: int, y: int, wz: int) -> int:
	if y < 0:
		return Blocks.BEDROCK
	if y >= CH:
		return Blocks.AIR
	var c: Chunk = chunks.get(Vector2i(floori(wx / float(CS)), floori(wz / float(CS))))
	if c == null:
		return Blocks.AIR
	var gid: int = c.blocks[_idx(posmod(wx, CS), y, posmod(wz, CS))]
	return gid if _known[gid] == 1 or gid == 0 else Blocks.AIR


func is_loaded(wx: int, wz: int) -> bool:
	var c: Chunk = chunks.get(Vector2i(floori(wx / float(CS)), floori(wz / float(CS))))
	return c != null and c.meshed


func set_block(wx: int, y: int, wz: int, id: int) -> bool:
	if y < 0 or y >= CH:
		return false
	var cp := Vector2i(floori(wx / float(CS)), floori(wz / float(CS)))
	var lx := posmod(wx, CS)
	var lz := posmod(wz, CS)
	var i := _idx(lx, y, lz)
	if not edits.has(cp):
		edits[cp] = {}
	edits[cp][i] = id
	_track_emitter(Vector3i(wx, y, wz), id, cp)
	var c: Chunk = chunks.get(cp)
	if c == null:
		return true
	c.blocks[i] = id
	if y + 1 > c.top:
		c.top = mini(CH, y + 2)
	_build_mesh(c)
	if lx == 0:
		_mark(cp + Vector2i(-1, 0))
	if lx == CS - 1:
		_mark(cp + Vector2i(1, 0))
	if lz == 0:
		_mark(cp + Vector2i(0, -1))
	if lz == CS - 1:
		_mark(cp + Vector2i(0, 1))
	return true


func _track_emitter(pos: Vector3i, id: int, cp: Vector2i) -> void:
	var lv := Blocks.light_of(id)
	var had := emitters.has(pos)
	if lv > 0:
		emitters[pos] = lv
	elif had:
		emitters.erase(pos)
	if lv > 0 or had:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if dx != 0 or dz != 0:
					_mark(cp + Vector2i(dx, dz))


func _mark(p: Vector2i) -> void:
	if chunks.has(p):
		_dirty[p] = true


func surface_y(wx: int, wz: int) -> int:
	for y in range(CH - 1, -1, -1):
		var id := get_block(wx, y, wz)
		if id != Blocks.AIR and id != Blocks.WATER and id != Blocks.LEAVES:
			return y
	return 0


func find_spawn() -> Vector3:
	if world_type == "flat":
		return Vector3(0.5, FLAT_H + 2.0, 0.5)
	for r in range(0, 200, 4):
		for a in range(0, 360, 45):
			var wx := int(cos(deg_to_rad(a)) * r)
			var wz := int(sin(deg_to_rad(a)) * r)
			var h := height_at(wx, wz)
			if h > SEA + 1 and h < 40:
				return Vector3(wx + 0.5, h + 2.0, wz + 0.5)
	return Vector3(0.5, SEA + 20, 0.5)


# ------------------------------------------------------------ explosão
func explode(center: Vector3, radius: float) -> void:
	var cx := int(floor(center.x))
	var cy := int(floor(center.y))
	var cz := int(floor(center.z))
	var r := int(ceil(radius))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dy * dy + dz * dz > radius * radius:
					continue
				var id := get_block(cx + dx, cy + dy, cz + dz)
				if id != Blocks.AIR and id != Blocks.BEDROCK and id != Blocks.WATER:
					set_block(cx + dx, cy + dy, cz + dz, Blocks.AIR)


# ------------------------------------------------------------ raycast voxel (DDA)
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	dir = dir.normalized()
	var x := int(floor(origin.x))
	var y := int(floor(origin.y))
	var z := int(floor(origin.z))
	var sx := 1 if dir.x > 0 else -1
	var sy := 1 if dir.y > 0 else -1
	var sz := 1 if dir.z > 0 else -1
	var tdx := absf(1.0 / dir.x) if dir.x != 0.0 else INF
	var tdy := absf(1.0 / dir.y) if dir.y != 0.0 else INF
	var tdz := absf(1.0 / dir.z) if dir.z != 0.0 else INF
	var tmx := INF
	var tmy := INF
	var tmz := INF
	if dir.x != 0.0:
		tmx = ((x + 1 - origin.x) if sx > 0 else (origin.x - x)) * tdx
	if dir.y != 0.0:
		tmy = ((y + 1 - origin.y) if sy > 0 else (origin.y - y)) * tdy
	if dir.z != 0.0:
		tmz = ((z + 1 - origin.z) if sz > 0 else (origin.z - z)) * tdz
	var n := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var id := get_block(x, y, z)
		if id != Blocks.AIR and id != Blocks.WATER:
			return {"pos": Vector3i(x, y, z), "normal": n, "id": id, "t": t}
		if tmx < tmy and tmx < tmz:
			x += sx
			t = tmx
			tmx += tdx
			n = Vector3i(-sx, 0, 0)
		elif tmy < tmz:
			y += sy
			t = tmy
			tmy += tdy
			n = Vector3i(0, -sy, 0)
		else:
			z += sz
			t = tmz
			tmz += tdz
			n = Vector3i(0, 0, -sz)
	return {}


# ------------------------------------------------------------ streaming
func set_centers(pts: Array, radii: Array) -> void:
	centers = pts
	center_radius = radii
	var need: Dictionary = {}
	for k in pts.size():
		var p: Vector3 = pts[k]
		var r: int = radii[k]
		var cc := Vector2i(floori(p.x / CS), floori(p.z / CS))
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dz * dz <= r * r + 1:
					var q := cc + Vector2i(dx, dz)
					if not need.has(q) or need[q] > dx * dx + dz * dz:
						need[q] = dx * dx + dz * dz
	for q in need:
		if not chunks.has(q) and not _gen_queue.has(q):
			_gen_queue.append(q)
	_gen_queue = _gen_queue.filter(func(q): return need.has(q))
	_gen_queue.sort_custom(func(a, b): return need[a] < need[b])
	# descarregar chunks longe
	var drop: Array = []
	for q in chunks:
		var keep := false
		for k in pts.size():
			var p: Vector3 = pts[k]
			var cc := Vector2i(floori(p.x / CS), floori(p.z / CS))
			var rr: int = radii[k] + 2
			if (q - cc).length_squared() <= rr * rr:
				keep = true
				break
		if not keep:
			drop.append(q)
	for q in drop:
		chunks[q].node.queue_free()
		chunks.erase(q)
		_dirty.erase(q)


func pending_work() -> int:
	return _gen_queue.size() + _dirty.size()


func _process(_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 7000:
		if not _step():
			break


func _step() -> bool:
	if not _gen_queue.is_empty():
		var q: Vector2i = _gen_queue.pop_front()
		if not chunks.has(q):
			_gen_chunk(q)
		return true
	if not _dirty.is_empty():
		var best = null
		var bd := INF
		var p0 := Vector3.ZERO
		if not centers.is_empty():
			p0 = centers[0]
		for q in _dirty:
			var d := Vector2(q.x * CS + 8 - p0.x, q.y * CS + 8 - p0.z).length_squared()
			if d < bd:
				bd = d
				best = q
		_dirty.erase(best)
		if chunks.has(best):
			_build_mesh(chunks[best])
		return true
	return false


# ------------------------------------------------------------ malha
func _build_mesh(c: Chunk) -> void:
	var bl: PackedByteArray = c.blocks
	var ox: int = c.pos.x * CS
	var oz: int = c.pos.y * CS
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var wverts := PackedVector3Array()
	var wuvs := PackedVector2Array()
	var wcols := PackedColorArray()
	var widx := PackedInt32Array()
	var col_faces := PackedVector3Array()
	var em: Array = []
	for ep in emitters:
		var lvl: int = emitters[ep]
		var rad := lvl * 0.6
		if ep.x > ox - rad and ep.x < ox + CS + rad and ep.z > oz - rad and ep.z < oz + CS + rad:
			em.append([Vector3(ep.x + 0.5, ep.y + 0.5, ep.z + 0.5), rad, minf(1.0, lvl / 14.0)])
	var e := 0.0006
	var su := _uv_size.x - 2.0 * e
	var sv := _uv_size.y - 2.0 * e
	for y in range(0, c.top):
		for z in CS:
			for x in CS:
				var id: int = bl[x + z * CS + y * CS * CS]
				if id == 0 or _known[id] == 0:
					continue
				if id == Blocks.TORCH:
					_add_torch(x, y, z, verts, uvs, cols, idx)
					continue
				var is_water := id == Blocks.WATER
				var lower_top := false
				if is_water:
					var above := 0 if y + 1 >= CH else bl[x + z * CS + (y + 1) * CS * CS]
					lower_top = above != Blocks.WATER
				for f in 6:
					var n: Vector3i = FACE_N[f]
					var nx := x + n.x
					var ny := y + n.y
					var nz := z + n.z
					var nid := 0
					if ny < 0:
						nid = Blocks.STONE
					elif ny >= CH:
						nid = 0
					elif nx >= 0 and nx < CS and nz >= 0 and nz < CS:
						nid = bl[nx + nz * CS + ny * CS * CS]
					else:
						nid = get_block(ox + nx, ny, oz + nz)
					var vis := false
					if is_water:
						vis = nid == 0 or (_opaque[nid] == 0 and nid != Blocks.WATER)
					else:
						vis = _opaque[nid] == 0 and not (nid == id and id == Blocks.GLASS)
					var colf: bool = _solid[id] == 1 and _solid[nid] == 0
					if not vis and not colf:
						continue
					var fv: Array = FACE_V[f]
					if vis:
						var base_uv: Vector2 = _face_uv[id * 6 + f]
						var shade: float = FACE_SHADE[f]
						var bl := 0.0
						if not em.is_empty() and not is_water:
							bl = _block_light(Vector3(ox + x + 0.5 + n.x * 0.5, y + 0.5 + n.y * 0.5, oz + z + 0.5 + n.z * 0.5), em)
						var color := Color(shade, shade, shade, bl)
						var fu: Array = FACE_UV[f]
						if is_water:
							var b := wverts.size()
							for k in 4:
								var v: Vector3 = fv[k]
								var py := v.y
								if lower_top and py > 0.5:
									py = 0.9
								wverts.append(Vector3(x + v.x, y + py, z + v.z))
								var lu: Vector2 = fu[k]
								wuvs.append(base_uv + Vector2(e + lu.x * su, e + lu.y * sv))
								wcols.append(color)
							widx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
						else:
							var b := verts.size()
							for k in 4:
								var v: Vector3 = fv[k]
								verts.append(Vector3(x + v.x, y + v.y, z + v.z))
								var lu: Vector2 = fu[k]
								uvs.append(base_uv + Vector2(e + lu.x * su, e + lu.y * sv))
								cols.append(color)
							idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
					if colf:
						var p0 := Vector3(x, y, z)
						var a: Vector3 = p0 + fv[0]
						var b2: Vector3 = p0 + fv[1]
						var c2: Vector3 = p0 + fv[2]
						var d2: Vector3 = p0 + fv[3]
						col_faces.append_array([a, b2, c2, a, c2, d2])
	var mesh := ArrayMesh.new()
	var si := 0
	if verts.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(si, _mat_solid)
		si += 1
	if wverts.size() > 0:
		var arr2 := []
		arr2.resize(Mesh.ARRAY_MAX)
		arr2[Mesh.ARRAY_VERTEX] = wverts
		arr2[Mesh.ARRAY_TEX_UV] = wuvs
		arr2[Mesh.ARRAY_COLOR] = wcols
		arr2[Mesh.ARRAY_INDEX] = widx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
		mesh.surface_set_material(si, _mat_water)
	c.node.mesh = mesh
	if col_faces.size() > 0:
		var shp := ConcavePolygonShape3D.new()
		shp.set_faces(col_faces)
		c.cshape.shape = shp
	else:
		c.cshape.shape = null
	c.meshed = true


func _block_light(p: Vector3, em: Array) -> float:
	var best := 0.0
	for e in em:
		var d := p.distance_to(e[0])
		if d < e[1]:
			var v := pow(1.0 - d / e[1], 1.5) * e[2]
			if v > best:
				best = v
	return best


func _add_torch(x: int, y: int, z: int, verts: PackedVector3Array, uvs: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
	var base_uv: Vector2 = _face_uv[Blocks.TORCH * 6 + 0]
	for f in 6:
		var fv: Array = FACE_V[f]
		var fu: Array = FACE_UV[f]
		var b := verts.size()
		for k in 4:
			var v: Vector3 = fv[k]
			verts.append(Vector3(x + 0.4375 + v.x * 0.125, y + v.y * 0.625, z + 0.4375 + v.z * 0.125))
			var lu: Vector2 = fu[k]
			var px := 7.0 + lu.x * 2.0
			var py := 6.0 + lu.y * 10.0
			if f == 2:
				py = 4.0 + lu.y * 2.0
			uvs.append(base_uv + Vector2(px / 16.0 * _uv_size.x, py / 16.0 * _uv_size.y))
			cols.append(Color(1, 1, 1, 1))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])


## Miniatura vista de cima (para os cards de mundo).
func preview_image(sz: int, span: int) -> Image:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	for py in sz:
		for px in sz:
			var wx := int((px - sz / 2) * span / float(sz))
			var wz := int((py - sz / 2) * span / float(sz))
			var h := height_at(wx, wz)
			var col := Color(0.30, 0.58, 0.2).lightened(clampf((h - SEA) * 0.01, 0.0, 0.25))
			if world_type == "flat":
				col = Color(0.32, 0.6, 0.22) if (px / 8 + py / 8) % 2 == 0 else Color(0.3, 0.56, 0.21)
			elif h <= SEA:
				col = Color(0.15, 0.35, 0.75).darkened(clampf((SEA - h) * 0.03, 0.0, 0.5))
			elif h <= SEA + 1 or is_desert(wx, wz):
				col = Color(0.86, 0.8, 0.55)
			elif h >= 44:
				col = Color(0.95, 0.97, 1.0)
			img.set_pixel(px, py, col)
	return img


# ------------------------------------------------------------ salvar / carregar
func export_edits() -> Dictionary:
	return edits.duplicate(true)


func import_edits(d: Dictionary) -> void:
	for cp in d:
		if not edits.has(cp):
			edits[cp] = {}
		for i in d[cp]:
			edits[cp][i] = d[cp][i]
			if Blocks.light_of(d[cp][i]) > 0:
				emitters[Vector3i(cp.x * CS + int(i) % CS, int(i) / (CS * CS), cp.y * CS + (int(i) / CS) % CS)] = Blocks.light_of(d[cp][i])
		var c: Chunk = chunks.get(cp)
		if c != null:
			for i in d[cp]:
				c.blocks[i] = d[cp][i]
				c.top = maxi(c.top, mini(CH, int(i) / (CS * CS) + 2))
			_dirty[cp] = true
