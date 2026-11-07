extends Node
## Autoload "Blocks": definições de blocos, itens, ferramentas, receitas, atlas de texturas procedural.

# ---- IDs de blocos ----
const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4
const SAND := 5
const WATER := 6
const LOG := 7
const LEAVES := 8
const PLANKS := 9
const COAL_ORE := 10
const IRON_ORE := 11
const DIAMOND_ORE := 12
const BEDROCK := 13
const GLASS := 14
const TABLE := 15
const FURNACE := 16
const SNOW := 17
const GRAVEL := 18
const BRICK := 19
const CHEST := 20
const FURNACE_ON := 21
const MAX_BLOCK := 21

# ---- IDs de itens ----
const STICK := 100
const COAL := 101
const IRON_INGOT := 102
const DIAMOND := 103
const RAW_PORK := 104
const COOKED_PORK := 105
const LEATHER := 106
const RAW_BEEF := 107
const STEAK := 108
const ROTTEN := 109
const BONE := 110
const GUNPOWDER := 111
const APPLE := 112
const TOOL_BASE := 120 # 120 + tier*10 + kind

const KIND_PICK := 0
const KIND_AXE := 1
const KIND_SHOVEL := 2
const KIND_SWORD := 3
const TIER_NAMES := ["Madeira", "Pedra", "Ferro", "Diamante"]
const KIND_NAMES := ["Picareta", "Machado", "Pá", "Espada"]
const TIER_COLORS := [Color(0.62, 0.46, 0.26), Color(0.55, 0.55, 0.57), Color(0.88, 0.88, 0.9), Color(0.35, 0.92, 0.95)]
const TIER_SPEED := [2.0, 4.0, 6.0, 8.0]
const TIER_DUR := [60, 132, 251, 1562]

const ATLAS_COLS := 8
const TILE_NAMES := [
	"grass_top", "grass_side", "dirt", "stone", "cobble", "sand", "water", "log_side",
	"log_top", "leaves", "planks", "coal_ore", "iron_ore", "diamond_ore", "bedrock", "glass",
	"table_top", "table_side", "furnace_side", "furnace_top", "snow", "gravel", "brick",
	"chest_top", "chest_side", "furnace_on",
]

var defs: Dictionary = {}
var recipes: Array = []
var food: Dictionary = {}
var atlas_tex: ImageTexture
var atlas_img: Image
var _icons: Dictionary = {}
var _icon_imgs: Dictionary = {}
var _item_meshes: Dictionary = {}
var _item_mat: StandardMaterial3D
var _tile_index: Dictionary = {}


func _ready() -> void:
	for i in TILE_NAMES.size():
		_tile_index[TILE_NAMES[i]] = i
	_define_blocks()
	_define_items()
	_define_recipes()
	_build_atlas()


# ---------------------------------------------------------------- definições
func _b(id: int, nm: String, hard: float, tool: int, min_tier: int, drop: int, tiles: Array, solid := true, opaque := true) -> void:
	defs[id] = {
		"name": nm, "hard": hard, "tool": tool, "min_tier": min_tier, "drop": drop,
		"tiles": tiles, "solid": solid, "opaque": opaque, "stack": 64, "block": true,
		"icon_tile": tiles[1],
	}


func _define_blocks() -> void:
	_b(GRASS, "Grama", 0.6, KIND_SHOVEL, -1, DIRT, ["grass_top", "grass_side", "dirt"])
	_b(DIRT, "Terra", 0.5, KIND_SHOVEL, -1, DIRT, ["dirt", "dirt", "dirt"])
	_b(STONE, "Pedra", 1.5, KIND_PICK, 0, COBBLE, ["stone", "stone", "stone"])
	_b(COBBLE, "Pedregulho", 2.0, KIND_PICK, 0, COBBLE, ["cobble", "cobble", "cobble"])
	_b(SAND, "Areia", 0.5, KIND_SHOVEL, -1, SAND, ["sand", "sand", "sand"])
	_b(WATER, "Água", -1.0, -1, -1, 0, ["water", "water", "water"], false, false)
	_b(LOG, "Tronco", 2.0, KIND_AXE, -1, LOG, ["log_top", "log_side", "log_top"])
	_b(LEAVES, "Folhas", 0.2, -1, -1, 0, ["leaves", "leaves", "leaves"], true, false)
	_b(PLANKS, "Tábuas", 2.0, KIND_AXE, -1, PLANKS, ["planks", "planks", "planks"])
	_b(COAL_ORE, "Minério de Carvão", 3.0, KIND_PICK, 0, COAL, ["coal_ore", "coal_ore", "coal_ore"])
	_b(IRON_ORE, "Minério de Ferro", 3.0, KIND_PICK, 1, IRON_ORE, ["iron_ore", "iron_ore", "iron_ore"])
	_b(DIAMOND_ORE, "Minério de Diamante", 3.0, KIND_PICK, 2, DIAMOND, ["diamond_ore", "diamond_ore", "diamond_ore"])
	_b(BEDROCK, "Rocha Matriz", -1.0, -1, -1, 0, ["bedrock", "bedrock", "bedrock"])
	_b(GLASS, "Vidro", 0.3, -1, -1, 0, ["glass", "glass", "glass"], true, false)
	_b(TABLE, "Mesa de Trabalho", 2.5, KIND_AXE, -1, TABLE, ["table_top", "table_side", "planks"])
	_b(FURNACE, "Fornalha", 3.5, KIND_PICK, 0, FURNACE, ["furnace_top", "furnace_side", "furnace_top"])
	_b(SNOW, "Neve", 0.3, KIND_SHOVEL, -1, SNOW, ["snow", "snow", "snow"])
	_b(GRAVEL, "Cascalho", 0.6, KIND_SHOVEL, -1, GRAVEL, ["gravel", "gravel", "gravel"])
	_b(BRICK, "Tijolos", 2.0, KIND_PICK, 0, BRICK, ["brick", "brick", "brick"])
	_b(CHEST, "Baú", 2.5, KIND_AXE, -1, CHEST, ["chest_top", "chest_side", "chest_top"])
	_b(FURNACE_ON, "Fornalha", 3.5, KIND_PICK, 0, FURNACE, ["furnace_top", "furnace_on", "furnace_top"])
	defs[GRASS]["icon_tile"] = "grass_side"
	defs[LOG]["icon_tile"] = "log_side"


func _i(id: int, nm: String, shape: String, col: Color, stack := 64) -> void:
	defs[id] = {"name": nm, "block": false, "stack": stack, "shape": shape, "color": col}


func _define_items() -> void:
	_i(STICK, "Graveto", "line", Color(0.55, 0.4, 0.2))
	_i(COAL, "Carvão", "blob", Color(0.12, 0.12, 0.14))
	_i(IRON_INGOT, "Barra de Ferro", "rect", Color(0.85, 0.85, 0.88))
	_i(DIAMOND, "Diamante", "gem", Color(0.35, 0.92, 0.95))
	_i(RAW_PORK, "Porco Cru", "blob", Color(0.95, 0.6, 0.62))
	_i(COOKED_PORK, "Porco Assado", "blob", Color(0.65, 0.35, 0.2))
	_i(LEATHER, "Couro", "rect", Color(0.6, 0.38, 0.2))
	_i(RAW_BEEF, "Carne Crua", "blob", Color(0.8, 0.25, 0.25))
	_i(STEAK, "Bife", "blob", Color(0.5, 0.25, 0.15))
	_i(ROTTEN, "Carne Podre", "blob", Color(0.45, 0.55, 0.3))
	_i(BONE, "Osso", "line", Color(0.95, 0.95, 0.88))
	_i(GUNPOWDER, "Pólvora", "blob", Color(0.4, 0.4, 0.42))
	_i(APPLE, "Maçã", "blob", Color(0.85, 0.15, 0.12))
	food = {RAW_PORK: 2, COOKED_PORK: 8, RAW_BEEF: 2, STEAK: 8, ROTTEN: 1, APPLE: 4}
	for t in 4:
		for k in 4:
			var id: int = TOOL_BASE + t * 10 + k
			defs[id] = {
				"name": "%s de %s" % [KIND_NAMES[k], TIER_NAMES[t]], "block": false, "stack": 1,
				"shape": "tool", "color": TIER_COLORS[t], "tool_kind": k, "tool_tier": t,
				"dur": TIER_DUR[t],
			}


var smelting: Dictionary = {}
var fuels: Dictionary = {}


## Receita em grade. pat = linhas de ids (0 = vazio). Sem forma: shapeless.
func _r(out: int, n: int, pat: Array, shapeless := false) -> void:
	var h: int = pat.size()
	var w: int = pat[0].size()
	recipes.append({"out": out, "n": n, "pat": pat, "w": w, "h": h, "shapeless": shapeless})


func _define_recipes() -> void:
	var P := PLANKS
	var S := STICK
	_r(PLANKS, 4, [[LOG]], true)
	_r(STICK, 4, [[P], [P]])
	_r(TABLE, 1, [[P, P], [P, P]])
	_r(CHEST, 1, [[P, P, P], [P, 0, P], [P, P, P]])
	_r(FURNACE, 1, [[COBBLE, COBBLE, COBBLE], [COBBLE, 0, COBBLE], [COBBLE, COBBLE, COBBLE]])
	_r(BRICK, 4, [[STONE, STONE], [STONE, STONE]])
	var mats := [PLANKS, COBBLE, IRON_INGOT, DIAMOND]
	for t in 4:
		var m: int = mats[t]
		_r(TOOL_BASE + t * 10 + KIND_PICK, 1, [[m, m, m], [0, S, 0], [0, S, 0]])
		_r(TOOL_BASE + t * 10 + KIND_AXE, 1, [[m, m], [m, S], [0, S]])
		_r(TOOL_BASE + t * 10 + KIND_SHOVEL, 1, [[m], [S], [S]])
		_r(TOOL_BASE + t * 10 + KIND_SWORD, 1, [[m], [m], [S]])
	smelting = {IRON_ORE: IRON_INGOT, COBBLE: STONE, SAND: GLASS, RAW_PORK: COOKED_PORK, RAW_BEEF: STEAK, LOG: COAL}
	fuels = {COAL: 80.0, LOG: 15.0, PLANKS: 15.0, STICK: 5.0, TABLE: 15.0, CHEST: 15.0}


## Acha receita para uma grade (Array de ids, row-major, gw x gh). Retorna {} se nenhuma.
func match_recipe(grid: Array, gw: int, gh: int) -> Dictionary:
	var minx := 99
	var miny := 99
	var maxx := -1
	var maxy := -1
	var ids: Array = []
	for y in gh:
		for x in gw:
			var id: int = grid[y * gw + x]
			if id != 0:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
				ids.append(id)
	if ids.is_empty():
		return {}
	var w := maxx - minx + 1
	var h := maxy - miny + 1
	for r in recipes:
		if r["shapeless"]:
			var need: Array = []
			for row in r["pat"]:
				for v in row:
					if v != 0:
						need.append(v)
			if need.size() != ids.size():
				continue
			var a := ids.duplicate()
			a.sort()
			need.sort()
			if a == need:
				return r
			continue
		if r["w"] != w or r["h"] != h:
			continue
		for mirror in 2:
			var ok := true
			for y in h:
				for x in w:
					var px := x if mirror == 0 else (w - 1 - x)
					var want: int = r["pat"][y][px]
					if grid[(miny + y) * gw + minx + x] != want:
						ok = false
			if ok:
				return r
	return {}


func smelt_result(id: int) -> int:
	return smelting.get(id, 0)


func fuel_time(id: int) -> float:
	return fuels.get(id, 0.0)


func is_container(id: int) -> bool:
	return id == CHEST or id == FURNACE or id == FURNACE_ON


# ---------------------------------------------------------------- consultas
func name_of(id: int) -> String:
	return defs[id]["name"] if defs.has(id) else "?"


func is_block(id: int) -> bool:
	return id > 0 and id <= MAX_BLOCK


func is_solid(id: int) -> bool:
	return id != AIR and defs[id]["solid"]


func is_opaque(id: int) -> bool:
	return id != AIR and defs[id]["opaque"]


func is_tool(id: int) -> bool:
	return id >= TOOL_BASE


func tool_kind(id: int) -> int:
	return defs[id]["tool_kind"] if is_tool(id) else -1


func tool_tier(id: int) -> int:
	return defs[id]["tool_tier"] if is_tool(id) else -1


func max_dur(id: int) -> int:
	return defs[id]["dur"] if is_tool(id) else 0


func stack_of(id: int) -> int:
	return defs[id]["stack"] if defs.has(id) else 64


func attack_damage(held: int) -> float:
	if not is_tool(held):
		return 1.0
	var base := [2.0, 3.0, 1.0, 4.0]
	return base[tool_kind(held)] + float(tool_tier(held))


func can_harvest(block: int, held: int) -> bool:
	var d: Dictionary = defs[block]
	if d["min_tier"] < 0:
		return true
	return tool_kind(held) == d["tool"] and tool_tier(held) >= d["min_tier"]


func break_time(block: int, held: int) -> float:
	var d: Dictionary = defs[block]
	var h: float = d["hard"]
	if h < 0.0:
		return INF
	var good: bool = d["tool"] >= 0 and tool_kind(held) == d["tool"]
	if d["min_tier"] >= 0:
		if good and tool_tier(held) >= d["min_tier"]:
			return h * 1.5 / TIER_SPEED[tool_tier(held)]
		return h * 5.0
	if good:
		return h * 1.5 / TIER_SPEED[tool_tier(held)]
	return h * 1.5


## Retorna [id, quantidade] ou [] se nada cai.
func drops_for(block: int, held: int) -> Array:
	if not can_harvest(block, held):
		return []
	if block == LEAVES:
		var r := randf()
		if r < 0.06:
			return [APPLE, 1]
		if r < 0.2:
			return [STICK, 1]
		return []
	var d: int = defs[block]["drop"]
	if d == 0:
		return []
	return [d, 1]


# ---------------------------------------------------------------- atlas
func tile_index(tname: String) -> int:
	return _tile_index.get(tname, 0)


func tile_uv(tname: String) -> Vector2:
	var i: int = tile_index(tname)
	return Vector2(float(i % ATLAS_COLS) / ATLAS_COLS, float(i / ATLAS_COLS) / _atlas_rows())


func _atlas_rows() -> int:
	return int(ceil(float(TILE_NAMES.size()) / ATLAS_COLS))


func _build_atlas() -> void:
	var rows := _atlas_rows()
	atlas_img = Image.create(16 * ATLAS_COLS, 16 * rows, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0, 0, 0, 0))
	for i in TILE_NAMES.size():
		var t := _gen_tile(TILE_NAMES[i], i)
		atlas_img.blit_rect(t, Rect2i(0, 0, 16, 16), Vector2i((i % ATLAS_COLS) * 16, (i / ATLAS_COLS) * 16))
	atlas_tex = ImageTexture.create_from_image(atlas_img)


func _fill_noise(img: Image, base: Color, amt: float, rng: RandomNumberGenerator) -> void:
	for y in 16:
		for x in 16:
			var d := rng.randf_range(-amt, amt)
			img.set_pixel(x, y, Color(clampf(base.r + d, 0, 1), clampf(base.g + d, 0, 1), clampf(base.b + d, 0, 1), base.a))


func _gen_tile(tname: String, idx: int) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + idx * 17
	match tname:
		"dirt":
			_fill_noise(img, Color(0.47, 0.33, 0.2), 0.05, rng)
		"grass_top":
			_fill_noise(img, Color(0.35, 0.62, 0.22), 0.06, rng)
		"grass_side":
			_fill_noise(img, Color(0.47, 0.33, 0.2), 0.05, rng)
			for x in 16:
				var depth := 3 + (1 if rng.randf() < 0.5 else 0)
				for y in depth:
					var d := rng.randf_range(-0.05, 0.05)
					img.set_pixel(x, y, Color(0.35 + d, 0.62 + d, 0.22 + d))
		"stone":
			_fill_noise(img, Color(0.5, 0.5, 0.52), 0.05, rng)
		"cobble":
			_fill_noise(img, Color(0.47, 0.47, 0.48), 0.07, rng)
			for y in 16:
				for x in 16:
					if y % 5 == 0 or (x + (y / 5) * 4) % 7 == 0:
						img.set_pixel(x, y, Color(0.28, 0.28, 0.3))
		"sand":
			_fill_noise(img, Color(0.86, 0.8, 0.55), 0.04, rng)
		"water":
			_fill_noise(img, Color(0.2, 0.42, 0.85, 0.6), 0.03, rng)
		"log_side":
			_fill_noise(img, Color(0.4, 0.3, 0.18), 0.03, rng)
			for y in 16:
				for x in 16:
					if x % 4 == 0:
						img.set_pixel(x, y, Color(0.28, 0.2, 0.11))
		"log_top":
			for y in 16:
				for x in 16:
					var dist := Vector2(x - 7.5, y - 7.5).length()
					var c := Color(0.72, 0.57, 0.35) if int(dist) % 2 == 0 else Color(0.6, 0.45, 0.27)
					if dist > 7.2:
						c = Color(0.38, 0.28, 0.16)
					img.set_pixel(x, y, c)
		"leaves":
			_fill_noise(img, Color(0.2, 0.5, 0.15), 0.08, rng)
			for y in 16:
				for x in 16:
					if rng.randf() < 0.18:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
		"planks":
			_fill_noise(img, Color(0.65, 0.5, 0.3), 0.03, rng)
			for x in 16:
				img.set_pixel(x, 3, Color(0.45, 0.33, 0.18))
				img.set_pixel(x, 7, Color(0.45, 0.33, 0.18))
				img.set_pixel(x, 11, Color(0.45, 0.33, 0.18))
				img.set_pixel(x, 15, Color(0.45, 0.33, 0.18))
		"coal_ore", "iron_ore", "diamond_ore":
			_fill_noise(img, Color(0.5, 0.5, 0.52), 0.05, rng)
			var col := Color(0.1, 0.1, 0.1)
			if tname == "iron_ore":
				col = Color(0.85, 0.65, 0.5)
			elif tname == "diamond_ore":
				col = Color(0.35, 0.92, 0.95)
			for n in 9:
				var cx := rng.randi_range(1, 14)
				var cy := rng.randi_range(1, 14)
				img.set_pixel(cx, cy, col)
				img.set_pixel(cx + 1, cy, col)
				img.set_pixel(cx, cy + 1, col.darkened(0.2))
		"bedrock":
			_fill_noise(img, Color(0.2, 0.2, 0.21), 0.12, rng)
		"glass":
			img.fill(Color(0, 0, 0, 0))
			for i in 16:
				for c in [Vector2i(i, 0), Vector2i(i, 15), Vector2i(0, i), Vector2i(15, i)]:
					img.set_pixelv(c, Color(0.8, 0.92, 1.0, 1.0))
			for i in range(3, 8):
				img.set_pixel(i, i, Color(1, 1, 1, 0.8))
		"table_top":
			_fill_noise(img, Color(0.62, 0.47, 0.27), 0.03, rng)
			for i in 16:
				if i % 5 == 0:
					for j in 16:
						img.set_pixel(i, j, Color(0.4, 0.28, 0.15))
						img.set_pixel(j, i, Color(0.4, 0.28, 0.15))
		"table_side":
			_fill_noise(img, Color(0.65, 0.5, 0.3), 0.03, rng)
			for y in 5:
				for x in 16:
					img.set_pixel(x, y, Color(0.45, 0.3, 0.16))
			for x in range(3, 13):
				img.set_pixel(x, 8, Color(0.55, 0.55, 0.58))
				img.set_pixel(x, 9, Color(0.4, 0.4, 0.42))
		"furnace_side":
			_fill_noise(img, Color(0.45, 0.45, 0.47), 0.05, rng)
			for y in range(5, 12):
				for x in range(4, 12):
					img.set_pixel(x, y, Color(0.08, 0.08, 0.08))
			for x in range(5, 11):
				img.set_pixel(x, 10, Color(0.95, 0.5, 0.1))
				img.set_pixel(x, 11, Color(0.9, 0.3, 0.05))
		"furnace_top":
			_fill_noise(img, Color(0.4, 0.4, 0.42), 0.04, rng)
		"snow":
			_fill_noise(img, Color(0.95, 0.97, 1.0), 0.02, rng)
		"gravel":
			_fill_noise(img, Color(0.55, 0.52, 0.5), 0.13, rng)
		"brick":
			_fill_noise(img, Color(0.62, 0.28, 0.22), 0.04, rng)
			for y in 16:
				for x in 16:
					var row := y / 4
					if y % 4 == 3 or (x + (row % 2) * 4) % 8 == 0:
						img.set_pixel(x, y, Color(0.75, 0.72, 0.68))
	return img


# ---------------------------------------------------------------- ícones de itens
func icon(id: int) -> Texture2D:
	if id <= 0 or not defs.has(id):
		return null
	if _icons.has(id):
		return _icons[id]
	var tex: Texture2D
	var d: Dictionary = defs[id]
	if d["block"]:
		tex = ImageTexture.create_from_image(_gen_block_icon(d))
	else:
		tex = ImageTexture.create_from_image(icon_image(id))
	_icons[id] = tex
	return tex


func icon_image(id: int) -> Image:
	if _icon_imgs.has(id):
		return _icon_imgs[id]
	var im := _gen_icon(defs[id])
	_outline(im)
	_icon_imgs[id] = im
	return im


func _outline(img: Image) -> void:
	var src := img.duplicate() as Image
	for y in 16:
		for x in 16:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and nx < 16 and ny >= 0 and ny < 16 and src.get_pixel(nx, ny).a > 0.5:
					img.set_pixel(x, y, src.get_pixel(nx, ny).darkened(0.65))
					break


func _tile_pixel(tname: String, tx: float, ty: float) -> Color:
	var i: int = tile_index(tname)
	var px := clampi(int(tx * 16.0), 0, 15) + (i % ATLAS_COLS) * 16
	var py := clampi(int(ty * 16.0), 0, 15) + (i / ATLAS_COLS) * 16
	return atlas_img.get_pixel(px, py)


## Ícone de bloco em cubo isométrico (estilo Minecraft), 32x32.
func _gen_block_icon(d: Dictionary) -> Image:
	var N := 32
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tiles: Array = d["tiles"]
	for py in N:
		for px in N:
			var sx := (px + 0.5) / N * 2.0 - 1.0
			var sy := (py + 0.5) / N * 2.0 - 1.0
			var u := (sx + 2.0 * (sy + 1.0)) * 0.5
			var v := (2.0 * (sy + 1.0) - sx) * 0.5
			var col := Color(0, 0, 0, 0)
			if u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0:
				col = _tile_pixel(tiles[0], u, v)
			else:
				var vr := 1.0 - sx
				var wr := (1.0 + vr) * 0.5 - sy
				if vr >= 0.0 and vr <= 1.0 and wr >= 0.0 and wr <= 1.0:
					col = _tile_pixel(tiles[1], sx, 1.0 - wr)
					col = Color(col.r * 0.62, col.g * 0.62, col.b * 0.62, col.a)
				else:
					var ul := sx + 1.0
					var wl := (ul + 1.0) * 0.5 - sy
					if ul >= 0.0 and ul <= 1.0 and wl >= 0.0 and wl <= 1.0:
						col = _tile_pixel(tiles[1], ul, 1.0 - wl)
						col = Color(col.r * 0.82, col.g * 0.82, col.b * 0.82, col.a)
			if col.a > 0.5:
				col.a = 1.0
			img.set_pixel(px, py, col)
	return img


## Malha extrudada (item grosso) a partir do ícone 16x16. Retorna ArrayMesh com cores por vértice.
func item_mesh(id: int, size := 0.5, thick := 0.12) -> ArrayMesh:
	var key := "%d_%.2f_%.2f" % [id, size, thick]
	if _item_meshes.has(key):
		return _item_meshes[key]
	var img := icon_image(id)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var px := size / 16.0
	var hz := thick * 0.5
	for y in 16:
		for x in 16:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var x0 := (x - 8) * px
			var x1 := x0 + px
			var y1 := (8 - y) * px
			var y0 := y1 - px
			_quad(verts, cols, idx, [Vector3(x0, y0, hz), Vector3(x1, y0, hz), Vector3(x1, y1, hz), Vector3(x0, y1, hz)], c)
			_quad(verts, cols, idx, [Vector3(x1, y0, -hz), Vector3(x0, y0, -hz), Vector3(x0, y1, -hz), Vector3(x1, y1, -hz)], c.darkened(0.15))
			var sc := c.darkened(0.3)
			if x == 0 or img.get_pixel(x - 1, y).a < 0.5:
				_quad(verts, cols, idx, [Vector3(x0, y0, -hz), Vector3(x0, y0, hz), Vector3(x0, y1, hz), Vector3(x0, y1, -hz)], sc)
			if x == 15 or img.get_pixel(x + 1, y).a < 0.5:
				_quad(verts, cols, idx, [Vector3(x1, y0, hz), Vector3(x1, y0, -hz), Vector3(x1, y1, -hz), Vector3(x1, y1, hz)], sc)
			if y == 0 or img.get_pixel(x, y - 1).a < 0.5:
				_quad(verts, cols, idx, [Vector3(x0, y1, hz), Vector3(x1, y1, hz), Vector3(x1, y1, -hz), Vector3(x0, y1, -hz)], sc.lightened(0.1))
			if y == 15 or img.get_pixel(x, y + 1).a < 0.5:
				_quad(verts, cols, idx, [Vector3(x0, y0, -hz), Vector3(x1, y0, -hz), Vector3(x1, y0, hz), Vector3(x0, y0, hz)], sc.darkened(0.1))
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, item_material())
	_item_meshes[key] = mesh
	return mesh


func _quad(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, q: Array, c: Color) -> void:
	var b := verts.size()
	for v in q:
		verts.append(v)
		cols.append(c)
	idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])


func item_material() -> StandardMaterial3D:
	if _item_mat == null:
		_item_mat = StandardMaterial3D.new()
		_item_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_item_mat.vertex_color_use_as_albedo = true
		_item_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _item_mat


func set_item_light(l: float) -> void:
	var v := clampf(l, 0.3, 1.0)
	item_material().albedo_color = Color(v, v, v)


## Cubo 3D de bloco (para drops e mão) com UVs do atlas. Usa material do mundo.
func block_cube_mesh(id: int, size := 0.3) -> ArrayMesh:
	var key := "b%d_%.2f" % [id, size]
	if _item_meshes.has(key):
		return _item_meshes[key]
	var tiles: Array = defs[id]["tiles"]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var e := 0.0006
	var us := 1.0 / ATLAS_COLS - 2.0 * e
	var vs := 1.0 / _atlas_rows() - 2.0 * e
	for f in 6:
		var tn: String = tiles[0] if f == 2 else (tiles[2] if f == 3 else tiles[1])
		var buv := tile_uv(tn)
		var b := verts.size()
		var sh: float = World.FACE_SHADE[f]
		for k in 4:
			var v: Vector3 = World.FACE_V[f][k]
			verts.append((v - Vector3(0.5, 0.5, 0.5)) * size)
			var lu: Vector2 = World.FACE_UV[f][k]
			uvs.append(buv + Vector2(e + lu.x * us, e + lu.y * vs))
			cols.append(Color(sh, sh, sh, 1))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_item_meshes[key] = mesh
	return mesh


## Cor aleatória de um pixel do bloco (para partículas).
func block_color(id: int) -> Color:
	if not defs.has(id) or not defs[id]["block"]:
		return Color(0.6, 0.6, 0.6)
	var tn: String = defs[id]["tiles"][1]
	return _tile_pixel(tn, randf(), randf())


func _gen_icon(d: Dictionary) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col: Color = d["color"]
	var dark := col.darkened(0.35)
	var wood := Color(0.5, 0.35, 0.18)
	match d["shape"]:
		"line":
			for i in range(2, 14):
				img.set_pixel(i, 15 - i, col)
				img.set_pixel(i + 1, 15 - i, dark)
		"blob":
			for y in 16:
				for x in 16:
					var dist := Vector2(x - 7.5, y - 7.5).length()
					if dist < 5.5:
						img.set_pixel(x, y, col if dist < 4.5 else dark)
		"rect":
			for y in range(5, 12):
				for x in range(3, 13):
					img.set_pixel(x, y, col if (y < 10 and x < 12) else dark)
		"gem":
			for y in 16:
				for x in 16:
					if abs(x - 7.5) + abs(y - 7.5) < 6.0:
						img.set_pixel(x, y, col if abs(x - 7.5) + abs(y - 7.5) < 4.5 else dark)
		"tool":
			var k: int = d["tool_kind"]
			if k == KIND_SWORD:
				for i in range(4, 14):
					img.set_pixel(i, 15 - i, col)
					img.set_pixel(i + 1, 15 - i, col.darkened(0.25))
					img.set_pixel(i, 14 - i, col.lightened(0.15))
				for i in range(3, 7):
					img.set_pixel(i, 9 + (i - 3) * 0, wood)
				img.set_pixel(3, 12, wood)
				img.set_pixel(2, 13, wood)
				img.set_pixel(5, 10, wood)
				img.set_pixel(6, 9, wood)
			else:
				for i in range(2, 11):
					img.set_pixel(i, 15 - i, wood)
				match k:
					KIND_PICK:
						for x in range(5, 14):
							img.set_pixel(x, 3, col)
							img.set_pixel(x, 4, col.darkened(0.25))
						for y in range(4, 8):
							img.set_pixel(5, y, col)
							img.set_pixel(13, y, col)
					KIND_AXE:
						for y in range(2, 8):
							for x in range(8, 14):
								if x - 8 + (y - 2) < 8:
									img.set_pixel(x, y, col if y < 5 else col.darkened(0.25))
					KIND_SHOVEL:
						for y in range(2, 7):
							for x in range(10, 14):
								img.set_pixel(x, y, col if x < 13 else col.darkened(0.25))
	return img
