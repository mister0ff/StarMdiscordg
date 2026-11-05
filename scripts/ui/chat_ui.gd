extends Control
## Chat: histórico completo em tela cheia (T) + mini-log que some sozinho no jogo.
## Formato: <nick> mensagem. O histórico é apagado ao sair do mundo.

var main: Node
var is_open := false

var _mini: RichTextLabel
var _full: Control
var _log: RichTextLabel
var _input: LineEdit
var _history: Array = []   # [bbcode, tempo]
var _clock := 0.0
var _acc := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 20
	theme = th
	_mini = RichTextLabel.new()
	_mini.bbcode_enabled = true
	_mini.scroll_active = false
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.add_theme_color_override("font_outline_color", Color.BLACK)
	_mini.add_theme_constant_override("outline_size", 6)
	add_child(_mini)
	# tela cheia
	_full = Control.new()
	_full.visible = false
	add_child(_full)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full.add_child(bg)
	var mg := MarginContainer.new()
	mg.set_anchors_preset(Control.PRESET_FULL_RECT)
	for sd in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + sd, 14)
	_full.add_child(mg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	mg.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	var title := Label.new()
	title.text = "Chat"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_b := Button.new()
	close_b.text = "Fechar"
	close_b.custom_minimum_size = Vector2(120, 44)
	close_b.pressed.connect(close)
	top.add_child(close_b)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_log)
	var row := HBoxContainer.new()
	vb.add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = "Mensagem ou /comando"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 48)
	_input.text_submitted.connect(_submit)
	row.add_child(_input)
	var send := Button.new()
	send.text = "Enviar"
	send.custom_minimum_size = Vector2(120, 48)
	send.pressed.connect(func(): _submit(_input.text))
	row.add_child(send)


func _process(delta: float) -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	_full.position = Vector2.ZERO
	_full.size = size
	var sr := Util.safe_rect(get_viewport())
	_mini.position = sr.position + Vector2(12, 8)
	_mini.size = Vector2(minf(760.0, sr.size.x - 24.0), 220)
	_clock += delta
	_acc += delta
	if _acc > 0.25:
		_acc = 0.0
		_render_mini()


func _render_mini() -> void:
	if is_open:
		_mini.text = ""
		return
	var out := ""
	var shown := 0
	for i in range(_history.size() - 1, -1, -1):
		if _clock - _history[i][1] < 10.0 and shown < 7:
			out = _history[i][0] + "\n" + out
			shown += 1
	_mini.text = out


func _add(bb: String) -> void:
	_history.append([bb, _clock])
	while _history.size() > 600:
		_history.pop_front()
	_log.append_text(bb + "\n")


func message(nm: String, text: String) -> void:
	_add("[color=#ffe27a]<%s>[/color] %s" % [nm.replace("[", "[lb]"), text.replace("[", "[lb]")])


func system(text: String) -> void:
	_add("[color=#8ad0ff]%s[/color]" % text.replace("[", "[lb]"))


func clear() -> void:
	_history.clear()
	_log.clear()
	_mini.text = ""


func open() -> void:
	if is_open or main.local_player == null:
		return
	is_open = true
	_full.visible = true
	main.local_player.set_ui_open(true)
	main.touch.set_enabled(false)
	_input.text = ""
	_input.call_deferred("grab_focus")


func close() -> void:
	var was := is_open
	is_open = false
	_full.visible = false
	_input.release_focus()
	if not was:
		return
	var pl: Player = main.local_player
	if pl != null and main.playing and not main.inv_ui.visible and not main.menu.visible and not pl.dead:
		pl.set_ui_open(false)
		main.touch.set_enabled(Settings.use_touch())


func _submit(text: String) -> void:
	main.send_chat(text)
	close()
