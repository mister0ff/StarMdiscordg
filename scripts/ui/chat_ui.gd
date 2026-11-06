extends Control
## Chat: ao abrir ocupa a tela toda e mostra todo o histórico (<nick> mensagem).
## Fechado, mostra só as últimas linhas por alguns segundos. O histórico é limpo ao sair do mundo.

var main: Node
var is_open := false

var _log: RichTextLabel
var _panel: Control
var _full: RichTextLabel
var _input: LineEdit
var _lines: Array = []
var _clock := 0.0
var _acc := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 20
	theme = th
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.position = Vector2(12, 8)
	_log.size = Vector2(760, 260)
	_log.add_theme_color_override("font_outline_color", Color.BLACK)
	_log.add_theme_constant_override("outline_size", 6)
	add_child(_log)
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)
	var mg := MarginContainer.new()
	mg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 14)
	_panel.add_child(mg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	mg.add_child(vb)
	var bar := HBoxContainer.new()
	vb.add_child(bar)
	_input = LineEdit.new()
	_input.placeholder_text = "Mensagem ou /comando"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 48)
	_input.text_submitted.connect(_submit)
	bar.add_child(_input)
	var send := Button.new()
	send.text = "Enviar"
	send.custom_minimum_size = Vector2(110, 48)
	send.pressed.connect(func(): _submit(_input.text))
	bar.add_child(send)
	var cl := Button.new()
	cl.text = "Fechar"
	cl.custom_minimum_size = Vector2(110, 48)
	cl.pressed.connect(close)
	bar.add_child(cl)
	_full = RichTextLabel.new()
	_full.bbcode_enabled = true
	_full.scroll_following = true
	_full.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_full)


func _process(delta: float) -> void:
	_clock += delta
	_acc += delta
	if _acc > 0.25:
		_acc = 0.0
		_render_small()


func _render_small() -> void:
	if is_open:
		_log.text = ""
		return
	var out := ""
	var recent: Array = []
	for l in _lines:
		if _clock - float(l[1]) < 10.0:
			recent.append(l[0])
	for i in range(maxi(0, recent.size() - 8), recent.size()):
		out += str(recent[i]) + "\n"
	_log.text = out


func _add(bb: String) -> void:
	_lines.append([bb, _clock])
	while _lines.size() > 300:
		_lines.pop_front()
	_full.append_text(bb + "\n")
	_render_small()


func clear() -> void:
	_lines.clear()
	_full.clear()
	_log.text = ""


func message(nm: String, text: String) -> void:
	_add("[color=#ffe27a]<%s>[/color] %s" % [nm.replace("[", "[lb]"), text.replace("[", "[lb]")])


func system(text: String) -> void:
	_add("[color=#8ad0ff]%s[/color]" % text.replace("[", "[lb]"))


func open() -> void:
	if is_open or main.local_player == null:
		return
	is_open = true
	_panel.visible = true
	_log.text = ""
	main.local_player.set_ui_open(true)
	main.touch.set_enabled(false)
	_input.text = ""
	_input.call_deferred("grab_focus")


func close() -> void:
	var was := is_open
	is_open = false
	_panel.visible = false
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
