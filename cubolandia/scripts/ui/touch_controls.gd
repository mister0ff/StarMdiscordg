extends Control
## Controles de toque: direcional, botões, olhar arrastando. Posição/tamanho editáveis.

var main: Node
var enabled := false
var edit_mode := false

var _edit_done: Callable
var _joy_idx := -1
var _joy_vec := Vector2.ZERO
var _look_idx := -1
var _holds: Dictionary = {}
var _down: Dictionary = {}
var _sel_btn := ""
var _drag_btn := ""
var _panel: PanelContainer
var _font: Font

const HOLD := ["jump", "attack", "place", "sneak"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	visible = false
	_build_panel()


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.position.y = 10
	add_child(_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_panel.add_child(hb)
	var l := Label.new()
	l.text = "Arraste os botões. Toque num para selecionar:"
	hb.add_child(l)
	for spec in [["-", -0.1], ["+", 0.1]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(48, 44)
		b.pressed.connect(_scale_sel.bind(spec[1]))
		hb.add_child(b)
	var r := Button.new()
	r.text = "Resetar"
	r.custom_minimum_size = Vector2(0, 44)
	r.pressed.connect(func():
		Settings.reset_touch()
		queue_redraw())
	hb.add_child(r)
	var d := Button.new()
	d.text = "Concluído"
	d.custom_minimum_size = Vector2(0, 44)
	d.pressed.connect(_end_edit)
	hb.add_child(d)


func set_enabled(v: bool) -> void:
	enabled = v
	if not v:
		_release_all()
	visible = enabled or edit_mode
	queue_redraw()


func start_edit(done: Callable) -> void:
	edit_mode = true
	_edit_done = done
	_sel_btn = ""
	_drag_btn = ""
	_panel.visible = true
	visible = true
	queue_redraw()


func _end_edit() -> void:
	edit_mode = false
	_panel.visible = false
	Settings.save_settings()
	visible = enabled
	queue_redraw()
	if _edit_done.is_valid():
		_edit_done.call()


func _scale_sel(delta: float) -> void:
	if _sel_btn == "":
		return
	var L: Dictionary = Settings.touch_layout[_sel_btn]
	L["s"] = clampf(L["s"] + delta, 0.4, 2.5)
	queue_redraw()


func _center(id: String) -> Vector2:
	var L: Dictionary = Settings.touch_layout[id]
	var vs := get_viewport_rect().size
	var i := Settings.insets
	var ar := Rect2(i.x, i.y, maxf(100.0, vs.x - i.x - i.z), maxf(100.0, vs.y - i.y - i.w))
	var r := _radius(id)
	var c := Vector2(ar.position.x + L["x"] * ar.size.x, ar.position.y + L["y"] * ar.size.y)
	return Vector2(clampf(c.x, ar.position.x + r, ar.end.x - r), clampf(c.y, ar.position.y + r, ar.end.y - r))


func _radius(id: String) -> float:
	var L: Dictionary = Settings.touch_layout[id]
	return (78.0 if id == "joystick" else 40.0) * L["s"] * Settings.touch_scale


func _hit_btn(pos: Vector2) -> String:
	for id in Settings.touch_layout:
		if id == "joystick":
			continue
		if pos.distance_to(_center(id)) <= _radius(id) * 1.1:
			return id
	if pos.distance_to(_center("joystick")) <= _radius("joystick") * 1.35:
		return "joystick"
	return ""


# ------------------------------------------------------------ entrada
func _input(event: InputEvent) -> void:
	if edit_mode:
		_edit_input(event)
		return
	if not enabled or main.local_player == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position, event.relative)


func _touch_down(idx: int, pos: Vector2) -> void:
	var s: int = main.hud.hotbar_slot_at(pos)
	if s >= 0:
		main.local_player.selected = s
		return
	var id := _hit_btn(pos)
	if id == "joystick":
		_joy_idx = idx
		_update_joy(pos)
	elif id != "":
		_holds[idx] = id
		_press(id)
	elif _look_idx == -1:
		_look_idx = idx


func _touch_up(idx: int) -> void:
	if idx == _joy_idx:
		_joy_idx = -1
		_joy_vec = Vector2.ZERO
		_release_move()
	if idx == _look_idx:
		_look_idx = -1
	if _holds.has(idx):
		_release(_holds[idx])
		_holds.erase(idx)
	queue_redraw()


func _touch_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == _joy_idx:
		_update_joy(pos)
	elif idx == _look_idx:
		main.local_player.apply_look(rel * 0.0045 * Settings.touch_look_sens)


func _update_joy(pos: Vector2) -> void:
	var v := (pos - _center("joystick")) / _radius("joystick")
	if v.length() > 1.0:
		v = v.normalized()
	_joy_vec = v
	_axis("right", "left", v.x)
	_axis("back", "forward", v.y)
	queue_redraw()


func _axis(pos_a: String, neg_a: String, val: float) -> void:
	if val > 0.12:
		Input.action_press(pos_a, val)
		Input.action_release(neg_a)
	elif val < -0.12:
		Input.action_press(neg_a, -val)
		Input.action_release(pos_a)
	else:
		Input.action_release(pos_a)
		Input.action_release(neg_a)


func _release_move() -> void:
	for a in ["left", "right", "forward", "back"]:
		Input.action_release(a)


func _press(id: String) -> void:
	var pl: Player = main.local_player
	if id in HOLD:
		Input.action_press(id)
		_down[id] = true
	else:
		match id:
			"fly":
				if pl.creative:
					pl.flying = not pl.flying
			"inventory":
				main.open_inventory()
			"chat":
				main.chat_ui.open()
			"pause":
				main.pause_game()
			"hotbar_prev":
				pl.selected = (pl.selected + 8) % 9
			"hotbar_next":
				pl.selected = (pl.selected + 1) % 9
	queue_redraw()


func _release(id: String) -> void:
	if id in HOLD:
		Input.action_release(id)
		_down.erase(id)


func _release_all() -> void:
	for id in HOLD:
		Input.action_release(id)
	_release_move()
	_holds.clear()
	_down.clear()
	_joy_idx = -1
	_look_idx = -1
	_joy_vec = Vector2.ZERO


func _edit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _panel.get_global_rect().has_point(event.position):
				return
			_drag_btn = _hit_btn(event.position)
			if _drag_btn != "":
				_sel_btn = _drag_btn
		else:
			_drag_btn = ""
		queue_redraw()
	elif event is InputEventMouseMotion and _drag_btn != "":
		var L: Dictionary = Settings.touch_layout[_drag_btn]
		var vs := get_viewport_rect().size
		var i := Settings.insets
		L["x"] = clampf((event.position.x - i.x) / maxf(1.0, vs.x - i.x - i.z), 0.03, 0.97)
		L["y"] = clampf((event.position.y - i.y) / maxf(1.0, vs.y - i.y - i.w), 0.05, 0.95)
		queue_redraw()


# ------------------------------------------------------------ desenho
func _draw() -> void:
	if not visible:
		return
	if edit_mode:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.05, 0.07, 0.12, 0.92))
	var alpha := 0.9 if edit_mode else Settings.touch_opacity
	for id in Settings.touch_layout:
		if id == "fly" and not edit_mode and not main.creative_mode:
			continue
		var c := _center(id)
		var r := _radius(id)
		var sel: bool = edit_mode and id == _sel_btn
		var col := Color(1, 0.9, 0.3) if sel else Color.WHITE
		if id == "joystick":
			draw_circle(c, r, Color(1, 1, 1, alpha * 0.15))
			draw_arc(c, r, 0, TAU, 48, Color(col, alpha), 3.0)
			draw_circle(c + _joy_vec * r * 0.55, r * 0.38, Color(col, alpha * 0.55))
		else:
			var f := 0.4 if _down.has(id) else 0.18
			draw_circle(c, r, Color(1, 1, 1, alpha * f))
			draw_arc(c, r, 0, TAU, 40, Color(col, alpha), 3.0)
			var fs := int(clampf(r * 0.42, 12.0, 32.0))
			draw_string(_font, c + Vector2(-r, fs * 0.35), Settings.TOUCH_LABELS[id], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(col, minf(1.0, alpha + 0.2)))
