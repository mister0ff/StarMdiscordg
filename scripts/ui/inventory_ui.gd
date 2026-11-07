extends Control
## Inventário + crafting (sobrevivência) ou seletor de itens (criativo).

var main: Node
var player: Player
var creative := false
var near_table := false
var near_furnace := false

var _sel := -1
var _craft_box: Container
var _craft_title: Label
var _buttons: Array = []
var _info: Label
var _drop_btn: Button
var _chest: Array = [] # espaços do baú aberto (referência ao Array do mundo)
var _chest_grid: GridContainer
var _chest_buttons: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	var th := Theme.new()
	th.default_font_size = 18
	theme = th
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var mg := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 12)
	panel.add_child(mg)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	mg.add_child(hb)
	# esquerda: criação
	var left := VBoxContainer.new()
	hb.add_child(left)
	_craft_title = Label.new()
	left.add_child(_craft_title)
	_chest_grid = GridContainer.new()
	_chest_grid.columns = 9
	_chest_grid.visible = false
	left.add_child(_chest_grid)
	for j in 27:
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(54, 58)
		cb.expand_icon = true
		cb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cb.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		cb.add_theme_font_size_override("font_size", 14)
		cb.pressed.connect(_on_slot.bind(100 + j))
		_chest_grid.add_child(cb)
		_chest_buttons.append(cb)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(440, 430)
	sc.name = "CraftScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(holder)
	_craft_box = holder
	# direita: inventário
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	hb.add_child(right)
	var t := Label.new()
	t.text = "Inventário"
	right.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 9
	right.add_child(grid)
	var hot := GridContainer.new()
	hot.columns = 9
	_buttons.resize(Inventory.SIZE)
	for i in range(9, Inventory.SIZE):
		var b := _mk_slot(i)
		grid.add_child(b)
	right.add_child(HSeparator.new())
	right.add_child(hot)
	for i in 9:
		hot.add_child(_mk_slot(i))
	_info = Label.new()
	_info.text = "Toque num item e depois noutro espaço para mover."
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(500, 40)
	right.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	right.add_child(row)
	_drop_btn = Button.new()
	_drop_btn.custom_minimum_size = Vector2(0, 46)
	_drop_btn.pressed.connect(_on_drop)
	row.add_child(_drop_btn)
	var close_b := Button.new()
	close_b.text = "Fechar"
	close_b.custom_minimum_size = Vector2(120, 46)
	close_b.pressed.connect(func(): main.close_inventory())
	row.add_child(close_b)


func _mk_slot(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(54, 58)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(_on_slot.bind(i))
	_buttons[i] = b
	return b


func open(p: Player, is_creative: bool, table: bool, furnace: bool) -> void:
	player = p
	creative = is_creative
	near_table = table
	near_furnace = furnace
	_chest = []
	_chest_grid.visible = false
	_craft_box.get_parent().visible = true
	_sel = -1
	visible = true
	if not player.inv.changed.is_connected(_changed):
		player.inv.changed.connect(_changed)
	_drop_btn.text = "Lixeira" if creative else "Largar"
	_build_craft()
	_refresh()


## Abre o inventário junto com um baú (chest_slots = Array de 27 espaços do mundo).
func open_chest(p: Player, is_creative: bool, chest_slots: Array) -> void:
	player = p
	creative = is_creative
	near_table = false
	near_furnace = false
	_chest = chest_slots
	_sel = -1
	visible = true
	if not player.inv.changed.is_connected(_changed):
		player.inv.changed.connect(_changed)
	_drop_btn.text = "Lixeira" if creative else "Largar"
	_craft_box.get_parent().visible = false
	_chest_grid.visible = true
	_craft_title.text = "Baú"
	_refresh()


func close() -> void:
	visible = false
	_sel = -1
	_chest = []


func _changed() -> void:
	if visible:
		_refresh()
		if not creative and _chest.is_empty():
			_build_craft()


func _get_slot(i: int) -> Variant:
	if i >= 100:
		return _chest[i - 100]
	return player.inv.slots[i]


func _put_slot(i: int, v: Variant) -> void:
	if i >= 100:
		_chest[i - 100] = v
	else:
		player.inv.slots[i] = v


func _move(a: int, b: int) -> void:
	var sa: Variant = _get_slot(a)
	var sb: Variant = _get_slot(b)
	if sa == null:
		return
	if sb != null and sb[0] == sa[0] and Blocks.stack_of(sa[0]) > 1:
		var maxs := Blocks.stack_of(sa[0])
		var t := mini(sa[1], maxs - sb[1])
		sb[1] += t
		sa[1] -= t
		if sa[1] <= 0:
			_put_slot(a, null)
	else:
		_put_slot(a, sb)
		_put_slot(b, sa)
	player.inv.changed.emit()
	if a >= 100 or b >= 100:
		main.chest_changed()


func _refresh() -> void:
	if player == null:
		return
	for i in Inventory.SIZE:
		var b: Button = _buttons[i]
		var id := player.inv.get_id(i)
		b.icon = Blocks.icon(id) if id != 0 else null
		var n := player.inv.get_count(i)
		b.text = str(n) if n > 1 else ""
		b.tooltip_text = Blocks.name_of(id) if id != 0 else ""
		b.modulate = Color(1, 0.9, 0.3) if i == _sel else Color.WHITE
	if not _chest.is_empty():
		for j in 27:
			var cb: Button = _chest_buttons[j]
			var cs: Variant = _chest[j]
			var cid: int = cs[0] if cs != null else 0
			cb.icon = Blocks.icon(cid) if cid != 0 else null
			var cn: int = cs[1] if cs != null else 0
			cb.text = str(cn) if cn > 1 else ""
			cb.tooltip_text = Blocks.name_of(cid) if cid != 0 else ""
			cb.modulate = Color(1, 0.9, 0.3) if (100 + j) == _sel else Color.WHITE
	var sel_slot: Variant = null
	if _sel >= 0:
		sel_slot = _get_slot(_sel)
	if sel_slot != null:
		_info.text = Blocks.name_of(sel_slot[0]) + " — toque em outro espaço para mover/trocar."
	else:
		_info.text = "Toque num item e depois noutro espaço para mover."


func _on_slot(i: int) -> void:
	if i >= 100 and _chest.is_empty():
		return
	if _sel == -1:
		if _get_slot(i) != null:
			_sel = i
	elif _sel == i:
		_sel = -1
	else:
		_move(_sel, i)
		_sel = -1
	_refresh()


func _on_drop() -> void:
	if _sel < 0 or _sel >= 100 or player.inv.get_id(_sel) == 0:
		return
	var id := player.inv.get_id(_sel)
	var n := player.inv.get_count(_sel)
	player.inv.take_from(_sel, n)
	if not creative:
		var d := player.eye_dir()
		main.spawn_drop_net(id, n, player.eye_pos() + d * 0.6, d * 4.0 + Vector3.UP * 2.0, 1.5)
	_sel = -1
	_refresh()


func _build_craft() -> void:
	for c in _craft_box.get_children():
		_craft_box.remove_child(c)
		c.queue_free()
	if creative:
		_craft_title.text = "Itens (criativo)"
		var g := GridContainer.new()
		g.columns = 7
		_craft_box.add_child(g)
		var ids := Blocks.defs.keys()
		ids.sort()
		for id in ids:
			if Blocks.defs[id].has("flow"):
				continue
			var b := Button.new()
			b.custom_minimum_size = Vector2(54, 54)
			b.icon = Blocks.icon(id)
			b.expand_icon = true
			b.tooltip_text = Blocks.name_of(id)
			b.pressed.connect(_give.bind(id))
			g.add_child(b)
		return
	_craft_title.text = "Criação   (mesa: %s | fornalha: %s)" % ["sim" if near_table else "não", "sim" if near_furnace else "não"]
	for r in Blocks.recipes:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 50)
		b.icon = Blocks.icon(r["out"])
		b.expand_icon = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		var ing: Array = []
		for id in r["in"]:
			ing.append("%dx %s" % [r["in"][id], Blocks.name_of(id)])
		var st: String = ["", " [Mesa]", " [Fornalha]"][r["st"]]
		b.text = "%s x%d  ←  %s%s" % [Blocks.name_of(r["out"]), r["n"], ", ".join(ing), st]
		if r.has("grid"):
			b.tooltip_text = String(r["grid"])
		b.disabled = not player.inv.can_craft(r, near_table, near_furnace)
		b.pressed.connect(func(): player.inv.craft(r, near_table, near_furnace))
		_craft_box.add_child(b)


func _give(id: int) -> void:
	var n := 1 if Blocks.stack_of(id) == 1 else 64
	player.inv.add(id, n)
