extends Control
## Chat: log no canto superior esquerdo (some depois de alguns segundos) + caixa de texto.

var main: Node
var is_open := false

var _log: RichTextLabel
var _bar: HBoxContainer
var _input: LineEdit
var _lines: Array = []
var _clock := 0.0
var _acc := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 20
	theme = th
	_bar = HBoxContainer.new()
	_bar.position = Vector2(12, 8)
	_bar.custom_minimum_size = Vector2(620, 46)
	_bar.visible = false
	add_child(_bar)
	_input = LineEdit.new()
	_input.placeholder_text = "Mensagem ou /comando"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(480, 44)
	_input.text_submitted.connect(_submit)
	_bar.add_child(_input)
	var send := Button.new()
	send.text = "Enviar"
	send.custom_minimum_size = Vector2(100, 44)
	send.pressed.connect(func(): _submit(_input.text))
	_bar.add_child(send)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.position = Vector2(12, 62)
	_log.size = Vector2(700, 300)
	_log.add_theme_color_override("font_outline_color", Color.BLACK)
	_log.add_theme_constant_override("outline_size", 6)
	add_child(_log)


func _process(delta: float) -> void:
	_clock += delta
	_acc += delta
	if _acc > 0.2:
		_acc = 0.0
		_render()


func _render() -> void:
	var out := ""
	for l in _lines:
		if is_open or _clock - l[1] < 10.0:
			out += l[0] + "\n"
	_log.text = out


func _add(bb: String) -> void:
	_lines.append([bb, _clock])
	while _lines.size() > 14:
		_lines.pop_front()
	_render()


func message(nm: String, text: String) -> void:
	_add("[color=#ffe27a]<%s>[/color] %s" % [nm.replace("[", "[lb]"), text.replace("[", "[lb]")])


func system(text: String) -> void:
	_add("[color=#8ad0ff]%s[/color]" % text.replace("[", "[lb]"))


func open() -> void:
	if is_open or main.local_player == null:
		return
	is_open = true
	_bar.visible = true
	main.local_player.set_ui_open(true)
	main.touch.set_enabled(false)
	_input.text = ""
	_input.call_deferred("grab_focus")


func close() -> void:
	var was := is_open
	is_open = false
	_bar.visible = false
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
