class_name Containers
extends RefCounted
## Dados de baús e fornalhas (por posição) e regras de clique em pilhas, estilo Minecraft.

const CHEST_SLOTS := 27
const SMELT_TIME := 10.0

var data: Dictionary = {} # Vector3i -> {"type", "slots", "burn", "burn_max", "cook"}
var _check_t := 0.0


func ensure(pos: Vector3i, block_id: int) -> Dictionary:
	if data.has(pos):
		return data[pos]
	var d := {}
	if block_id == Blocks.CHEST:
		d = {"type": "chest", "slots": _empty(CHEST_SLOTS), "burn": 0.0, "burn_max": 0.0, "cook": 0.0}
	else:
		d = {"type": "furnace", "slots": _empty(3), "burn": 0.0, "burn_max": 0.0, "cook": 0.0}
	data[pos] = d
	return d


func _empty(n: int) -> Array:
	var a: Array = []
	a.resize(n)
	for i in n:
		a[i] = null
	return a


## Clique em um espaço. button 1 = esquerdo, 2 = direito. Retorna o novo cursor (Array ou null).
static func click(slots: Array, idx: int, button: int, cursor):
	var s = slots[idx]
	if button == 1:
		if cursor == null:
			slots[idx] = null
			return s
		if s == null:
			slots[idx] = cursor
			return null
		if s[0] == cursor[0] and Blocks.stack_of(s[0]) > 1:
			var room: int = Blocks.stack_of(s[0]) - s[1]
			var t: int = mini(room, cursor[1])
			s[1] += t
			cursor[1] -= t
			return cursor if cursor[1] > 0 else null
		slots[idx] = cursor
		return s
	# direito
	if cursor == null:
		if s == null:
			return null
		var half: int = (s[1] + 1) / 2
		var take := [s[0], half, s[2]]
		s[1] -= half
		if s[1] <= 0:
			slots[idx] = null
		return take
	if s == null:
		slots[idx] = [cursor[0], 1, cursor[2]]
		cursor[1] -= 1
		return cursor if cursor[1] > 0 else null
	if s[0] == cursor[0] and Blocks.stack_of(s[0]) > 1 and s[1] < Blocks.stack_of(s[0]):
		s[1] += 1
		cursor[1] -= 1
		return cursor if cursor[1] > 0 else null
	slots[idx] = cursor
	return s


## Move uma pilha (shift+clique) de src para dst; devolve o que sobrou na origem (ou null).
static func quick_move(src_stack, dst: Array, from: int, to: int):
	var st = src_stack
	var maxs: int = Blocks.stack_of(st[0])
	if maxs > 1:
		for i in range(from, to):
			if st == null:
				break
			if dst[i] != null and dst[i][0] == st[0] and dst[i][1] < maxs:
				var t: int = mini(st[1], maxs - dst[i][1])
				dst[i][1] += t
				st[1] -= t
				if st[1] <= 0:
					st = null
	for i in range(from, to):
		if st == null:
			break
		if dst[i] == null:
			dst[i] = st
			st = null
	return st


func tick(world: World, game: Node, delta: float) -> void:
	for pos in data.keys():
		var d: Dictionary = data[pos]
		if d["type"] == "furnace":
			_tick_furnace(pos, d, delta, world, game)
	_check_t += delta
	if _check_t > 1.0:
		_check_t = 0.0
		for pos in data.keys():
			if not world.is_loaded(pos.x, pos.z):
				continue
			var b := world.get_block(pos.x, pos.y, pos.z)
			if not Blocks.is_container(b):
				game.container_destroyed(pos, data[pos])
				data.erase(pos)


func _tick_furnace(pos: Vector3i, d: Dictionary, delta: float, world: World, game: Node) -> void:
	var sl: Array = d["slots"]
	var inp = sl[0]
	var fuel = sl[1]
	var out = sl[2]
	var res := 0
	if inp != null:
		res = Blocks.smelt_result(inp[0])
	var can: bool = res != 0 and (out == null or (out[0] == res and out[1] < Blocks.stack_of(res)))
	if d["burn"] > 0.0:
		d["burn"] -= delta
	if d["burn"] <= 0.0 and can and fuel != null and Blocks.fuel_time(fuel[0]) > 0.0:
		d["burn_max"] = Blocks.fuel_time(fuel[0])
		d["burn"] = d["burn_max"]
		fuel[1] -= 1
		if fuel[1] <= 0:
			sl[1] = null
	if d["burn"] > 0.0 and can:
		d["cook"] += delta
		if d["cook"] >= SMELT_TIME:
			d["cook"] = 0.0
			inp[1] -= 1
			if inp[1] <= 0:
				sl[0] = null
			if out == null:
				sl[2] = [res, 1, Blocks.max_dur(res)]
			else:
				out[1] += 1
	else:
		d["cook"] = maxf(0.0, d["cook"] - delta * 2.0)
	var lit: bool = d["burn"] > 0.0
	if world.is_loaded(pos.x, pos.z):
		var cur := world.get_block(pos.x, pos.y, pos.z)
		if lit and cur == Blocks.FURNACE:
			game.set_block_net(pos.x, pos.y, pos.z, Blocks.FURNACE_ON)
		elif not lit and cur == Blocks.FURNACE_ON:
			game.set_block_net(pos.x, pos.y, pos.z, Blocks.FURNACE)


func all_items(d: Dictionary) -> Array:
	var out: Array = []
	for s in d["slots"]:
		if s != null:
			out.append(s)
	return out


func serialize() -> Array:
	var out: Array = []
	for pos in data:
		out.append([pos, data[pos].duplicate(true)])
	return out


func deserialize(arr: Array) -> void:
	data.clear()
	for e in arr:
		data[e[0]] = e[1]
