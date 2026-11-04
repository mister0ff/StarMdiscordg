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
const MAX_BLOCK := 19

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
]

var defs: Dictionary = {}
var recipes: Array = []
var food: Dictionary = {}
var atlas_tex: ImageTexture
var atlas_img: Image
var _icons: Dictionary = {}
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


func _r(out: int, n: int, ing: Dictionary, st := 0) -> void:
	recipes.append({"out": out, "n": n, "in": ing, "st": st})


func _define_recipes() -> void:
	# st: 0 = qualquer lugar (2x2), 1 = perto de mesa de trabalho, 2 = perto de fornalha (gasta 1 carvão)
	_r(PLANKS, 4, {LOG: 1})
	_r(STICK, 4, {PLANKS: 2})
	_r(TABLE, 1, {PLANKS: 4})
	_r(FURNACE, 1, {COBBLE: 8}, 1)
	_r(BRICK, 2, {STONE: 4}, 1)
	_r(GLASS, 1, {SAND: 1, COAL: 1}, 2)
	var mats := [PLANKS, COBBLE, IRON_INGOT, DIAMOND]
	for t in 4:
		var m: int = mats[t]
		_r(TOOL_BASE + t * 10 + KIND_PICK, 1, {m: 3, STICK: 2}, 1)
		_r(TOOL_BASE + t * 10 + KIND_AXE, 1, {m: 3, STICK: 2}, 1)
		_r(TOOL_BASE + t * 10 + KIND_SHOVEL, 1, {m: 1, STICK: 2}, 1)
		_r(TOOL_BASE + t * 10 + KIND_SWORD, 1, {m: 2, STICK: 1}, 1)
	# fundição
	_r(IRON_INGOT, 1, {IRON_ORE: 1, COAL: 1}, 2)
	_r(STONE, 1, {COBBLE: 1, COAL: 1}, 2)
	_r(COOKED_PORK, 1, {RAW_PORK: 1, COAL: 1}, 2)
	_r(STEAK, 1, {RAW_BEEF: 1, COAL: 1}, 2)


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
		var at := AtlasTexture.new()
		at.atlas = atlas_tex
		var i: int = tile_index(d["icon_tile"])
		at.region = Rect2((i % ATLAS_COLS) * 16, (i / ATLAS_COLS) * 16, 16, 16)
		tex = at
	else:
		tex = ImageTexture.create_from_image(_gen_icon(d))
	_icons[id] = tex
	return tex


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
