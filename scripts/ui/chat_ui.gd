extends Control
## Chat: mensagens recentes no canto (somem após alguns segundos) e, ao abrir,
## uma tela cheia com TODO o histórico "<nick> <mensagem>". O histórico some quando você sai do mundo.

const MAX_HISTORY := 500

var main: Node
var is_open := false

var _recent: RichTextLabel
var _full: Control
var _hist: RichTextLabel
var _input: LineEdit
var _margin: MarginContainer
var _lines: Array = [] # [bbcode, tempo]
var _all: Array = [] # bbcode (histórico completo)
var _clock := 0.0
var _acc := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 20
	theme = th
	_recent = RichTextLabel.new()
	_recent.bbcode_enabled = true
	_recent.scroll_active = false
	_recent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recent.position = Vector2(12, 8)
	_recent.size = Vector2(760, 260)
	_recent.add_theme_color_override("font_outline_color", Color.BLACK)
	_recent.add_theme_constant_override("outline_size", 6)
	add_child(_recent)
	_full = Control.new()
	_full.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full.visible = false
	add_child(_full)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full.add_child(bg)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full.add_child(_margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_margin.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	_input = LineEdit.new()
	_input.placeholder_text = "Mensagem ou /comando"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(240, 48)
	_input.text_submitted.connect(_submit)
	top.add_child(_input)
	var send := Button.new()
	send.text = "Enviar"
	send.custom_minimum_size = Vector2(110, 48)
	send.pressed.connect(func(): _submit(_input.text))
	top.add_child(send)
	var cl := Button.new()
	cl.text = "X"
	cl.custom_minimum_size = Vector2(56, 48)
	cl.pressed.connect(func(): close())
	top.add_child(cl)
	_hist = RichTextLabel.new()
	_hist.bbcode_enabled = true
	_hist.scroll_active = true
	_hist.scroll_following = true
	_hist.selection_enabled = true
	_hist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_hist)


func _process(delta: float) -> void:
	_clock += delta
	_acc += delta
	if _acc > 0.25:
		_acc = 0.0
		if not is_open:
			_render_recent()


func _render_recent() -> void:
	var out := ""
	for l in _lines:
		if _clock - float(l[1]) < 10.0:
			out += String(l[0]) + "\n"
	_recent.text = out


func _add(bb: String) -> void:
	_lines.append([bb, _clock])
	while _lines.size() > 8:
		_lines.pop_front()
	_all.append(bb)
	while _all.size() > MAX_HISTORY:
		_all.pop_front()
	if is_open:
		_hist.text = "\n".join(_all)
	else:
		_render_recent()


## Apaga todo o histórico (ao sair do mundo).
func clear() -> void:
	_lines.clear()
	_all.clear()
	_recent.text = ""
	_hist.text = ""


func message(nm: String, text: String) -> void:
	_add("[color=#ffe27a]<%s>[/color] %s" % [nm.replace("[", "[lb]"), text.replace("[", "[lb]")])


func system(text: String) -> void:
	_add("[color=#8ad0ff]%s[/color]" % text.replace("[", "[lb]"))


func open() -> void:
	if is_open or main.local_player == null:
		return
	is_open = true
	var mg := Settings.safe_margins(get_viewport_rect().size)
	_margin.add_theme_constant_override("margin_left", int(mg.position.x) + 14)
	_margin.add_theme_constant_override("margin_top", int(mg.position.y) + 12)
	_margin.add_theme_constant_override("margin_right", int(mg.size.x) + 14)
	_margin.add_theme_constant_override("margin_bottom", 14)
	_full.visible = true
	_recent.visible = false
	_hist.text = "\n".join(_all)
	main.local_player.set_ui_open(true)
	main.touch.set_enabled(false)
	_input.text = ""
	_input.call_deferred("grab_focus")


func close() -> void:
	var was := is_open
	is_open = false
	_full.visible = false
	_recent.visible = true
	_input.release_focus()
	if not was:
		return
	var pl: Player = main.local_player
	if pl != null and main.playing and not main.inv_ui.visible and not main.menu.visible and not pl.dead:
		pl.set_ui_open(false)
		main.touch.set_enabled(Settings.use_touch())


func _submit(text: String) -> void:
	if text.strip_edges() != "":
		main.send_chat(text)
	close()
