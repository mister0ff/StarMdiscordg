extends Control
## Telas de inventário, mesa de trabalho, baú, fornalha e criativo, desenhadas no estilo do Minecraft.

var main: Node
var player: Player
var mode := "player" # player | table | chest | furnace | creative
var cpos := Vector3i.ZERO

var _slots: Array = []   # {"g": grupo, "i": índice, "x": px, "y": px}
var _h := 166.0
var _sc := 3.0
var _org := Vector2.ZERO
var _cursor = null
var _grid: Array = []
var _gw := 2
var _out = null
var _mouse := Vector2.ZERO
var _right_mode := false
var _scroll := 0
var _waiting := false
var _poll_t := 0.0
var _font: Font
var _ids: Array = []
const TOUCH_BTN := Rect2(0, 0, 0, 0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = ThemeDB.fallback_font
	visible = false


# ------------------------------------------------------------ abrir / fechar
func open_mode(p: Player, m: String, pos := Vector3i.ZERO) -> void:
	player = p
	mode = m
	cpos = pos
	_cursor = null
	_waiting = false
	_scroll = 0
	_poll_t = 0.0
	_gw = 3 if m == "table" else 2
	_grid = []
	_grid.resize(_gw * _gw)
	for i in _grid.size():
		_grid[i] = null
	_out = null
	if m == "creative":
		_ids = Blocks.defs.keys()
		_ids.sort()
	_build_layout()
	if not player.inv.changed.is_connected(_changed):
		player.inv.changed.connect(_changed)
	if m == "chest" or m == "furnace":
		main.container_request(cpos)
	visible = true
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		for i in _grid.size():
			if _grid[i] != null:
				_give_back(_grid[i])
				_grid[i] = null
		if _cursor != null:
			_give_back(_cursor)
			_cursor = null
	_out = null


func _give_back(st) -> void:
	if st == null:
		return
	if mode == "creative":
		return
	var left: int = player.inv.add(st[0], st[1], st[2])
	if left > 0:
		var d := -player.cam.global_transform.basis.z
		main.spawn_drop_net(st[0], left, player.cam.global_position + d * 0.6, d * 4.0 + Vector3.UP * 2.0, 1.5)


func _changed() -> void:
	queue_redraw()


# ------------------------------------------------------------ layout
func _add_inv(y_main: float, y_hot: float, x := 8.0) -> void:
	for r in 3:
		for c in 9:
			_slots.append({"g": "inv", "i": 9 + r * 9 + c, "x": x + c * 18.0, "y": y_main + r * 18.0})
	for c in 9:
		_slots.append({"g": "inv", "i": c, "x": x + c * 18.0, "y": y_hot})


func _build_layout() -> void:
	_slots.clear()
	match mode:
		"player":
			_h = 166.0
			_add_inv(84, 142)
			for r in 2:
				for c in 2:
					_slots.append({"g": "grid", "i": r * 2 + c, "x": 98.0 + c * 18.0, "y": 18.0 + r * 18.0})
			_slots.append({"g": "out", "i": 0, "x": 154.0, "y": 28.0})
		"table":
			_h = 166.0
			_add_inv(84, 142)
			for r in 3:
				for c in 3:
					_slots.append({"g": "grid", "i": r * 3 + c, "x": 30.0 + c * 18.0, "y": 17.0 + r * 18.0})
			_slots.append({"g": "out", "i": 0, "x": 124.0, "y": 35.0})
		"chest":
			_h = 168.0
			for r in 3:
				for c in 9:
					_slots.append({"g": "cont", "i": r * 9 + c, "x": 8.0 + c * 18.0, "y": 18.0 + r * 18.0})
			_add_inv(86, 144)
		"furnace":
			_h = 166.0
			_add_inv(84, 142)
			_slots.append({"g": "cont", "i": 0, "x": 56.0, "y": 17.0})
			_slots.append({"g": "cont", "i": 1, "x": 56.0, "y": 53.0})
			_slots.append({"g": "cont", "i": 2, "x": 116.0, "y": 35.0})
		"creative":
			_h = 136.0
			for r in 5:
				for c in 9:
					_slots.append({"g": "pal", "i": r * 9 + c, "x": 9.0 + c * 18.0, "y": 18.0 + r * 18.0})
			for c in 9:
				_slots.append({"g": "inv", "i": c, "x": 9.0 + c * 18.0, "y": 112.0})


func _compute_scale() -> void:
	var vs := get_viewport_rect().size
	var i := Settings.insets
	var aw := vs.x - i.x - i.z
	var ah := vs.y - i.y - i.w - (50.0 if Settings.use_touch() else 0.0)
	_sc = clampf(minf(aw * 0.96 / 176.0, ah * 0.96 / _h), 1.2, 4.0)
	if _sc > 2.0:
		_sc = floorf(_sc * 2.0) * 0.5
	_org = Vector2(i.x + (aw - 176.0 * _sc) * 0.5, i.y + (ah - _h * _sc) * 0.5)


func _slot_rect(s: Dictionary) -> Rect2:
	return Rect2(_org + Vector2(s["x"] - 1.0, s["y"] - 1.0) * _sc, Vector2(18, 18) * _sc)


func _panel_rect() -> Rect2:
	return Rect2(_org, Vector2(176.0, _h) * _sc)


func _touch_btn() -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position.x, p.end.y + 6.0, 150.0, 40.0)


# ------------------------------------------------------------ dados dos slots
func _cont_data() -> Dictionary:
	return main.container_get(cpos)


func _stack_at(s: Dictionary):
	var i: int = s["i"]
	match s["g"]:
		"inv":
			return player.inv.slots[i]
		"grid":
			return _grid[i]
		"out":
			return _out
		"cont":
			var d := _cont_data()
			if d.is_empty():
				return null
			return d["slots"][i]
		"pal":
			var k: int = _scroll * 9 + i
			if k < _ids.size():
				var id: int = _ids[k]
				return [id, 1, Blocks.max_dur(id)]
	return null


func _update_out() -> void:
	var ids: Array = []
	for g in _grid:
		ids.append(g[0] if g != null else 0)
	var r := Blocks.match_recipe(ids, _gw, _gw)
	if r.is_empty():
		_out = null
	else:
		_out = [r["out"], r["n"], Blocks.max_dur(r["out"])]


func _process(delta: float) -> void:
	if not visible:
		return
	if mode == "chest" or mode == "furnace":
		_poll_t += delta
		if _poll_t > 0.4:
			_poll_t = 0.0
			main.container_request(cpos)
	queue_redraw()


# ------------------------------------------------------------ desenho
func _bevel(r: Rect2, fill: Color, light: Color, dark: Color, w: float) -> void:
	draw_rect(r, fill)
	draw_rect(Rect2(r.position, Vector2(r.size.x, w)), light)
	draw_rect(Rect2(r.position, Vector2(w, r.size.y)), light)
	draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), dark)
	draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), dark)


func _text(t: String, pos: Vector2, fs: int, col: Color, shadow := false) -> void:
	if shadow:
		draw_string(_font, pos + Vector2(_sc * 0.5, _sc * 0.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.15, 0.15, 0.15))
	draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_stack(st, r: Rect2) -> void:
	if st == null:
		return
	var tex := Blocks.icon(st[0])
	if tex != null:
		draw_texture_rect(tex, Rect2(r.position + Vector2(_sc, _sc), Vector2(16, 16) * _sc), false)
	var fs := int(maxf(10.0, 7.0 * _sc))
	if st[1] > 1:
		var t := str(st[1])
		var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2(r.end.x - w - _sc * 1.5, r.end.y - _sc * 2.5)
		_text(t, p, fs, Color.WHITE, true)
	if Blocks.is_tool(st[0]):
		var ratio := float(st[2]) / float(Blocks.max_dur(st[0]))
		if ratio < 0.999:
			var bw := 13.0 * _sc
			var bp := r.position + Vector2(2.0 * _sc, 14.0 * _sc)
			draw_rect(Rect2(bp, Vector2(bw, 2.0 * _sc)), Color(0, 0, 0))
			draw_rect(Rect2(bp, Vector2(bw * ratio, _sc)), Color(1.0 - ratio, ratio, 0.1))


func _title() -> String:
	match mode:
		"table":
			return "Mesa de Trabalho"
		"chest":
			return "Baú"
		"furnace":
			return "Fornalha"
		"creative":
			return "Itens"
	return "Criação"


func _draw() -> void:
	if player == null:
		return
	_compute_scale()
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.6))
	var pr := _panel_rect()
	draw_rect(Rect2(pr.position - Vector2(_sc, _sc), pr.size + Vector2(_sc, _sc) * 2.0), Color(0, 0, 0))
	_bevel(pr, Color("c6c6c6"), Color.WHITE, Color("555555"), 2.0 * _sc * 0.5)
	var fs := int(maxf(11.0, 7.5 * _sc))
	var tcol := Color("404040")
	match mode:
		"player":
			_text("Criação", _org + Vector2(97, 14) * _sc, fs, tcol)
			_draw_player_preview()
			_text("Inventário", _org + Vector2(8, 80) * _sc, fs, tcol)
		"table":
			_text("Mesa de Trabalho", _org + Vector2(29, 12) * _sc, fs, tcol)
			_text("Inventário", _org + Vector2(8, 80) * _sc, fs, tcol)
			_draw_arrow(Vector2(90, 34))
		"chest":
			_text("Baú", _org + Vector2(8, 14) * _sc, fs, tcol)
			_text("Inventário", _org + Vector2(8, 82) * _sc, fs, tcol)
		"furnace":
			_text("Fornalha", _org + Vector2(60, 12) * _sc, fs, tcol)
			_text("Inventário", _org + Vector2(8, 80) * _sc, fs, tcol)
			_draw_furnace_fx()
		"creative":
			_text("Itens", _org + Vector2(9, 14) * _sc, fs, tcol)
			_draw_scroll_btns()
	if mode == "player":
		_draw_arrow(Vector2(122, 28))
	var hover: Dictionary = {}
	for s in _slots:
		var r := _slot_rect(s)
		_bevel(r, Color("8b8b8b"), Color("373737"), Color.WHITE, maxf(1.0, _sc * 0.5))
		if s["g"] == "out":
			pass
		_draw_stack(_stack_at(s), r)
		if r.has_point(_mouse):
			hover = s
	if not hover.is_empty():
		var hr := _slot_rect(hover)
		draw_rect(Rect2(hr.position + Vector2(_sc, _sc) * 0.5, hr.size - Vector2(_sc, _sc)), Color(1, 1, 1, 0.45))
	if _cursor != null:
		_draw_stack(_cursor, Rect2(_mouse - Vector2(8, 8) * _sc, Vector2(16, 16) * _sc))
	elif not hover.is_empty():
		var st = _stack_at(hover)
		if st != null:
			_draw_tooltip(Blocks.name_of(st[0]), fs)
	if Settings.use_touch():
		var b := _touch_btn()
		_bevel(b, Color("c6c6c6") if not _right_mode else Color("ffd84a"), Color.WHITE, Color("555555"), 2.0)
		_text("Dividir (½): %s" % ("ligado" if _right_mode else "desligado"), b.position + Vector2(8, 26), 16, tcol)


func _draw_tooltip(t: String, fs: int) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + _sc * 6.0
	var h := fs + _sc * 5.0
	var p := _mouse + Vector2(12, -14)
	var vs := get_viewport_rect().size
	p.x = minf(p.x, vs.x - w - 4.0)
	p.y = maxf(p.y, 4.0)
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(w + 4, h + 4)), Color("1a0a2e"))
	draw_rect(Rect2(p, Vector2(w, h)), Color(0.06, 0.02, 0.1, 0.95))
	draw_string(_font, p + Vector2(_sc * 3.0, fs + _sc * 0.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_arrow(p: Vector2, frac := 1.0) -> void:
	var base := Rect2(_org + p * _sc, Vector2(22, 15) * _sc)
	draw_rect(Rect2(base.position + Vector2(0, 5) * _sc, Vector2(14, 5) * _sc), Color("8b8b8b"))
	draw_colored_polygon(PackedVector2Array([base.position + Vector2(14, 0) * _sc, base.position + Vector2(22, 7.5) * _sc, base.position + Vector2(14, 15) * _sc]), Color("8b8b8b"))
	if frac > 0.0:
		var w := 22.0 * frac
		draw_rect(Rect2(base.position + Vector2(0, 5) * _sc, Vector2(minf(w, 14.0), 5) * _sc), Color("4a4a4a"))
		if w > 14.0:
			draw_colored_polygon(PackedVector2Array([base.position + Vector2(14, 0) * _sc, base.position + Vector2(14 + (w - 14.0), 7.5) * _sc, base.position + Vector2(14, 15) * _sc]), Color("4a4a4a"))


func _draw_furnace_fx() -> void:
	var d := _cont_data()
	if d.is_empty():
		_draw_arrow(Vector2(79, 34), 0.0)
		return
	var cook: float = d["cook"] / Containers.SMELT_TIME
	_draw_arrow(Vector2(79, 34), cook)
	var fl := Rect2(_org + Vector2(56, 36) * _sc, Vector2(14, 14) * _sc)
	draw_rect(fl, Color("6b6b6b"))
	if d["burn"] > 0.0 and d["burn_max"] > 0.0:
		var f: float = clampf(d["burn"] / d["burn_max"], 0.0, 1.0)
		draw_rect(Rect2(fl.position.x, fl.end.y - fl.size.y * f, fl.size.x, fl.size.y * f), Color("ff8a1a"))
		draw_rect(Rect2(fl.position.x + _sc * 3.0, fl.end.y - fl.size.y * f * 0.6, fl.size.x - _sc * 6.0, fl.size.y * f * 0.6), Color("ffd84a"))


func _draw_scroll_btns() -> void:
	for k in 2:
		var r := Rect2(_org + Vector2(150 + k * 14, 4) * _sc, Vector2(12, 10) * _sc)
		_bevel(r, Color("c6c6c6"), Color.WHITE, Color("555555"), _sc * 0.5)
		var c := r.get_center()
		var up := k == 0
		var pts := PackedVector2Array([c + Vector2(0, -3 if up else 3) * _sc, c + Vector2(-3, 2 if up else -2) * _sc, c + Vector2(3, 2 if up else -2) * _sc])
		draw_colored_polygon(pts, Color("404040"))


func _scroll_rect(k: int) -> Rect2:
	return Rect2(_org + Vector2(150 + k * 14, 4) * _sc, Vector2(12, 10) * _sc)


func _draw_player_preview() -> void:
	var o := _org + Vector2(51, 70) * _sc
	var u := _sc
	draw_rect(Rect2(_org + Vector2(26, 8) * u, Vector2(50, 70) * u), Color("2b2b2b"))
	draw_rect(Rect2(_org + Vector2(27, 9) * u, Vector2(48, 68) * u), Color("1a1a1a"))
	draw_rect(Rect2(o + Vector2(-10, -42) * u, Vector2(20, 20) * u), Color("dba67f"))
	draw_rect(Rect2(o + Vector2(-10, -42) * u, Vector2(20, 7) * u), Color("5a3a1e"))
	draw_rect(Rect2(o + Vector2(-5, -33) * u, Vector2(3, 3) * u), Color("3b4bb0"))
	draw_rect(Rect2(o + Vector2(2, -33) * u, Vector2(3, 3) * u), Color("3b4bb0"))
	draw_rect(Rect2(o + Vector2(-10, -22) * u, Vector2(20, 26) * u), Color("3fa0c8"))
	draw_rect(Rect2(o + Vector2(-16, -22) * u, Vector2(6, 24) * u), Color("dba67f"))
	draw_rect(Rect2(o + Vector2(10, -22) * u, Vector2(6, 24) * u), Color("dba67f"))
	draw_rect(Rect2(o + Vector2(-10, 4) * u, Vector2(10, 22) * u), Color("3a3a9a"))
	draw_rect(Rect2(o + Vector2(0, 4) * u, Vector2(10, 22) * u), Color("3a3a9a"))


# ------------------------------------------------------------ entrada
func _slot_at(pos: Vector2) -> Dictionary:
	for s in _slots:
		if _slot_rect(s).has_point(pos):
			return s
	return {}


func _gui_input(event: InputEvent) -> void:
	if not visible or player == null:
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		return
	if event is InputEventMouseButton:
		_mouse = event.position
		if event.pressed and mode == "creative" and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var maxrow: int = maxi(0, int(ceil(_ids.size() / 9.0)) - 5)
			_scroll = clampi(_scroll + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, maxrow)
			return
		if not event.pressed:
			return
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return
		var btn := 1 if event.button_index == MOUSE_BUTTON_LEFT else 2
		if _right_mode and btn == 1:
			btn = 2
		_click(event.position, btn, Input.is_key_pressed(KEY_SHIFT))
		accept_event()


func _click(pos: Vector2, btn: int, shift: bool) -> void:
	if Settings.use_touch() and _touch_btn().has_point(pos):
		_right_mode = not _right_mode
		return
	if mode == "creative":
		for k in 2:
			if _scroll_rect(k).has_point(pos):
				var maxrow: int = maxi(0, int(ceil(_ids.size() / 9.0)) - 5)
				_scroll = clampi(_scroll + (-1 if k == 0 else 1), 0, maxrow)
				return
	var s := _slot_at(pos)
	if s.is_empty():
		if not _panel_rect().has_point(pos):
			_drop_cursor(btn)
		return
	var i: int = s["i"]
	match s["g"]:
		"inv":
			if shift and player.inv.slots[i] != null:
				_quick_from_inv(i)
			else:
				_cursor = Containers.click(player.inv.slots, i, btn, _cursor)
				player.inv.changed.emit()
		"grid":
			_cursor = Containers.click(_grid, i, btn, _cursor)
			_update_out()
		"out":
			_click_out(shift)
		"pal":
			_click_pal(i, shift)
		"cont":
			_click_cont(i, btn, shift)


func _drop_cursor(btn: int) -> void:
	if _cursor == null:
		return
	if mode == "creative":
		_cursor = null
		return
	var n: int = _cursor[1] if btn == 1 else 1
	var d := -player.cam.global_transform.basis.z
	main.spawn_drop_net(_cursor[0], n, player.cam.global_position + d * 0.6, d * 4.0 + Vector3.UP * 2.0, 1.5)
	_cursor[1] -= n
	if _cursor[1] <= 0:
		_cursor = null


func _click_pal(i: int, shift: bool) -> void:
	var st = _stack_at({"g": "pal", "i": i})
	if _cursor != null:
		_cursor = null
		return
	if st == null:
		return
	var id: int = st[0]
	var n: int = 1 if Blocks.stack_of(id) == 1 else 64
	if shift:
		player.inv.add(id, n)
	else:
		_cursor = [id, n, Blocks.max_dur(id)]


func _click_out(shift: bool) -> void:
	if _out == null:
		return
	if shift:
		var guard := 0
		while _out != null and guard < 64 and player.inv.room_for(_out[0]) >= _out[1]:
			player.inv.add(_out[0], _out[1], _out[2])
			_consume_grid()
			guard += 1
		return
	if _cursor == null:
		_cursor = [_out[0], _out[1], _out[2]]
		_consume_grid()
	elif _cursor[0] == _out[0] and Blocks.stack_of(_cursor[0]) > 1 and _cursor[1] + _out[1] <= Blocks.stack_of(_cursor[0]):
		_cursor[1] += _out[1]
		_consume_grid()


func _consume_grid() -> void:
	for i in _grid.size():
		if _grid[i] != null:
			_grid[i][1] -= 1
			if _grid[i][1] <= 0:
				_grid[i] = null
	_update_out()


func _quick_from_inv(i: int) -> void:
	var st = player.inv.slots[i]
	if mode == "chest" or mode == "furnace":
		var d := _cont_data()
		if d.is_empty() or _waiting:
			return
		var target := -1
		if mode == "chest":
			var cs: Array = d["slots"]
			for k in cs.size():
				if cs[k] != null and cs[k][0] == st[0] and Blocks.stack_of(st[0]) > 1 and cs[k][1] < Blocks.stack_of(st[0]):
					target = k
					break
			if target < 0:
				for k in cs.size():
					if cs[k] == null:
						target = k
						break
		else:
			if Blocks.smelt_result(st[0]) != 0:
				target = 0
			elif Blocks.fuel_time(st[0]) > 0.0:
				target = 1
		if target < 0:
			return
		player.inv.slots[i] = null
		var moving = st
		_waiting = true
		main.container_click(cpos, target, 1, moving, func(nc):
			_waiting = false
			if nc != null:
				var left: int = player.inv.add(nc[0], nc[1], nc[2])
				if left > 0:
					player.inv.slots[i] = [nc[0], left, nc[2]]
			player.inv.changed.emit())
		return
	# entre hotbar e inventário principal
	var rest = st
	player.inv.slots[i] = null
	if i < 9:
		rest = Containers.quick_move(rest, player.inv.slots, 9, 36)
	else:
		rest = Containers.quick_move(rest, player.inv.slots, 0, 9)
	if rest != null:
		player.inv.slots[i] = rest
	player.inv.changed.emit()


func _click_cont(i: int, btn: int, shift: bool) -> void:
	if _waiting:
		return
	var d := _cont_data()
	if d.is_empty():
		return
	_waiting = true
	var want_quick: bool = shift and _cursor == null
	main.container_click(cpos, i, 1 if want_quick else btn, _cursor, func(nc):
		_waiting = false
		_cursor = nc
		if want_quick and _cursor != null:
			var rest = Containers.quick_move(_cursor, player.inv.slots, 0, 36)
			_cursor = rest
			player.inv.changed.emit())
