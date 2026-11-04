class_name Inventory
extends RefCounted
## 36 slots (0-8 = hotbar). Cada slot: [id, quantidade, durabilidade] ou null.

signal changed

const SIZE := 36
var slots: Array = []


func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = null


func get_id(i: int) -> int:
	return slots[i][0] if slots[i] != null else 0


func get_count(i: int) -> int:
	return slots[i][1] if slots[i] != null else 0


func add(id: int, count: int, dur := -1) -> int:
	## devolve o que sobrou (não coube)
	var maxs := Blocks.stack_of(id)
	if maxs > 1:
		for i in SIZE:
			if count <= 0:
				break
			if slots[i] != null and slots[i][0] == id and slots[i][1] < maxs:
				var t := mini(count, maxs - slots[i][1])
				slots[i][1] += t
				count -= t
	for i in SIZE:
		if count <= 0:
			break
		if slots[i] == null:
			var t := mini(count, maxs)
			var d := dur
			if d < 0:
				d = Blocks.max_dur(id)
			slots[i] = [id, t, d]
			count -= t
	changed.emit()
	return count


func count_of(id: int) -> int:
	var n := 0
	for s in slots:
		if s != null and s[0] == id:
			n += s[1]
	return n


func remove_id(id: int, count: int) -> bool:
	if count_of(id) < count:
		return false
	for i in SIZE:
		if count <= 0:
			break
		if slots[i] != null and slots[i][0] == id:
			var t := mini(count, slots[i][1])
			slots[i][1] -= t
			count -= t
			if slots[i][1] <= 0:
				slots[i] = null
	changed.emit()
	return true


func take_from(i: int, n := 1) -> void:
	if slots[i] == null:
		return
	slots[i][1] -= n
	if slots[i][1] <= 0:
		slots[i] = null
	changed.emit()


func use_durability(i: int, amount := 1) -> bool:
	## devolve true se a ferramenta quebrou
	if slots[i] == null or not Blocks.is_tool(slots[i][0]):
		return false
	slots[i][2] -= amount
	if slots[i][2] <= 0:
		slots[i] = null
		changed.emit()
		return true
	changed.emit()
	return false


func swap(a: int, b: int) -> void:
	var t = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	changed.emit()


func move_stack(a: int, b: int) -> void:
	## junta a em b se mesmo item, senão troca
	if slots[a] == null:
		return
	if slots[b] != null and slots[b][0] == slots[a][0] and Blocks.stack_of(slots[a][0]) > 1:
		var maxs := Blocks.stack_of(slots[a][0])
		var t := mini(slots[a][1], maxs - slots[b][1])
		slots[b][1] += t
		slots[a][1] -= t
		if slots[a][1] <= 0:
			slots[a] = null
		changed.emit()
	else:
		swap(a, b)


func clear() -> void:
	for i in SIZE:
		slots[i] = null
	changed.emit()


func to_array() -> Array:
	var out: Array = []
	for s in slots:
		out.append(s.duplicate() if s != null else null)
	return out


func from_array(a: Array) -> void:
	for i in SIZE:
		slots[i] = null
	for i in mini(a.size(), SIZE):
		slots[i] = a[i].duplicate() if a[i] != null else null
	changed.emit()


## Receitas possíveis agora. st = estações disponíveis perto (0 nada, 1 mesa, 2 fornalha)
func can_craft(r: Dictionary, near_table: bool, near_furnace: bool) -> bool:
	if r["st"] == 1 and not near_table:
		return false
	if r["st"] == 2 and not near_furnace:
		return false
	for id in r["in"]:
		if count_of(id) < r["in"][id]:
			return false
	return true


func craft(r: Dictionary, near_table: bool, near_furnace: bool) -> bool:
	if not can_craft(r, near_table, near_furnace):
		return false
	for id in r["in"]:
		remove_id(id, r["in"][id])
	add(r["out"], r["n"])
	return true
