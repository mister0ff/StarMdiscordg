extends Control
## Menus: principal, novo mundo, multijogador, pausa e configurações (teclas + botões de toque).

var main: Node
var state := "main"

var _has_save := false
var _back_state := "main"
var _bg: ColorRect
var _page: VBoxContainer
var _toast: Label
var _toast_t := 0.0
var _listen_action := ""
var _listen_btn: Button
var _ignore_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font_size = 22
	theme = th
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var mg := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 20)
	panel.add_child(mg)
	_page = VBoxContainer.new()
	_page.custom_minimum_size = Vector2(560, 0)
	_page.add_theme_constant_override("separation", 10)
	mg.add_child(_page)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 12
	_toast.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.visible = false
	add_child(_toast)
	visible = false


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
	if visible and state == "pause" and Input.is_action_just_pressed("ui_cancel") and Engine.get_process_frames() != _ignore_frame:
		main.resume_game()


func back() -> void:
	match state:
		"settings":
			Settings.save_settings()
			if _back_state == "pause":
				show_pause(main.online, main.is_host)
			else:
				show_main(_has_save)
		"new", "multi":
			show_main(_has_save)
		"pause":
			main.resume_game()


func toast(t: String) -> void:
	_toast.text = t
	_toast.visible = true
	_toast.reset_size()
	_toast.position.x = (size.x - _toast.size.x) * 0.5
	_toast_t = 3.5


func hide_all() -> void:
	visible = false
	state = "none"


# ------------------------------------------------------------ helpers
func _clear() -> void:
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()


func _begin(st: String, bg: Color) -> void:
	state = st
	visible = true
	_bg.color = bg
	_ignore_frame = Engine.get_process_frames()
	_clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _title(t: String, sz := 40) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(l)
	return l


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(l)
	return l


func _btn(t: String, cb: Callable, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 52)
	b.pressed.connect(cb)
	(parent if parent != null else _page).add_child(b)
	return b


func _row(label: String, ctrl: Control, parent: Node = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	(parent if parent != null else _page).add_child(h)
	return h


func _slider(parent: Node, label: String, mn: float, mx: float, step: float, val: float, cb: Callable) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(220, 36)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var v := Label.new()
	v.text = "%.2f" % val if step < 1.0 else str(int(val))
	v.custom_minimum_size = Vector2(56, 0)
	h.add_child(v)
	s.value_changed.connect(func(x: float):
		v.text = "%.2f" % x if step < 1.0 else str(int(x))
		cb.call(x)
		Settings.save_settings())
	parent.add_child(h)


# ------------------------------------------------------------ páginas
func show_main(has_save: bool) -> void:
	_has_save = has_save
	get_tree().paused = false
	_begin("main", Color(0.07, 0.11, 0.18, 1))
	_title("CUBOLÂNDIA", 52)
	var sub := _label("Mundo procedural • Sobrevivência • Criativo • Multijogador")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if has_save:
		_btn("Continuar mundo salvo", func(): main.start_world(false, 0, true, true))
	_btn("Novo mundo", _page_new)
	_btn("Multijogador", _page_multi)
	_btn("Configurações", func():
		_back_state = "main"
		_page_settings())
	_btn("Sair", func(): get_tree().quit())


func _page_new() -> void:
	_begin("new", Color(0.07, 0.11, 0.18, 1))
	_title("Novo mundo", 36)
	var mode := OptionButton.new()
	mode.add_item("Sobrevivência")
	mode.add_item("Criativo")
	_row("Modo", mode)
	var seed_e := LineEdit.new()
	seed_e.placeholder_text = "vazio = aleatória"
	_row("Semente", seed_e)
	var tpl := OptionButton.new()
	tpl.add_item("Normal")
	tpl.add_item("Plano")
	_row("Modelo do mundo", tpl)
	var mobs := CheckBox.new()
	mobs.text = "Spawn de mobs"
	mobs.button_pressed = true
	_row("Mobs", mobs)
	var always := CheckBox.new()
	always.text = "Sempre dia"
	_row("Dia", always)
	var cmds := CheckBox.new()
	cmds.text = "Comandos ativados"
	_row("Comandos", cmds)
	if _has_save:
		_label("Atenção: o novo mundo substitui o salvamento anterior quando o jogo salvar.")
	_btn("Criar mundo", func():
		var t := seed_e.text.strip_edges()
		var sv := 0
		if t != "":
			sv = int(t) if t.is_valid_int() else (t.hash() & 0x7fffffff)
		main.start_world(mode.selected == 1, sv, mobs.button_pressed, false, 0, "flat" if tpl.selected == 1 else "normal", always.button_pressed, cmds.button_pressed))
	_btn("Voltar", func(): show_main(_has_save))


func _page_multi() -> void:
	_begin("multi", Color(0.07, 0.11, 0.18, 1))
	_title("Multijogador", 36)
	var name_e := LineEdit.new()
	name_e.text = Settings.player_name
	_row("Seu nome", name_e)
	var save_name := func():
		var n := name_e.text.strip_edges()
		if n != "":
			Settings.player_name = n.substr(0, 16)
		Settings.save_settings()
	_label("— Hospedar (amigos entram pelo seu IP + porta) —")
	var mode := OptionButton.new()
	mode.add_item("Sobrevivência")
	mode.add_item("Criativo")
	_row("Modo", mode)
	var port_e := LineEdit.new()
	port_e.text = str(main.PORT)
	_row("Porta", port_e)
	_btn("Hospedar novo mundo", func():
		save_name.call()
		main.start_world(mode.selected == 1, 0, true, false, int(port_e.text)))
	if _has_save:
		_btn("Hospedar mundo salvo", func():
			save_name.call()
			main.start_world(false, 0, true, true, int(port_e.text)))
	_label("— Entrar em um servidor —")
	var ip_e := LineEdit.new()
	ip_e.text = Settings.last_ip
	_row("IP", ip_e)
	var jport := LineEdit.new()
	jport.text = str(main.PORT)
	_row("Porta", jport)
	_btn("Entrar", func():
		save_name.call()
		Settings.last_ip = ip_e.text.strip_edges()
		Settings.save_settings()
		main.join_server(Settings.last_ip, int(jport.text)))
	_btn("Voltar", func(): show_main(_has_save))


func show_pause(online: bool, is_host: bool) -> void:
	_begin("pause", Color(0, 0, 0, 0.55))
	_title("Pausado", 40)
	if online and is_host:
		_label("Servidor aberto na porta %d." % main.PORT)
	elif online:
		_label("Conectado a um servidor.")
	_btn("Continuar", func(): main.resume_game())
	_btn("Configurações", func():
		_back_state = "pause"
		_page_settings())
	_btn("Ajustar botões da HUD (celular)", func():
		visible = false
		main.touch.start_edit(func():
			show_pause(main.online, main.is_host)))
	if not online or is_host:
		_btn("Salvar jogo", func():
			main.save_game()
			toast("Jogo salvo!"))
	_btn("Sair para o menu", func(): main.go_menu())


func _page_settings() -> void:
	_begin("settings", Color(0.07, 0.11, 0.18, 1) if _back_state == "main" else Color(0, 0, 0, 0.7))
	_title("Configurações", 34)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(680, 400)
	_page.add_child(tabs)
	_tab_general(_tab(tabs, "Geral"))
	_tab_keys(_tab(tabs, "Teclas"))
	_tab_touch(_tab(tabs, "Toque"))
	_btn("Voltar", func():
		Settings.save_settings()
		if _back_state == "pause":
			show_pause(main.online, main.is_host)
		else:
			show_main(_has_save))


func _tab(tabs: TabContainer, nm: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = nm
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	return vb


func _tab_general(vb: VBoxContainer) -> void:
	var cm := OptionButton.new()
	cm.add_item("Automático")
	cm.add_item("Toque (celular)")
	cm.add_item("Teclado e mouse")
	cm.selected = ["auto", "touch", "keyboard"].find(Settings.control_mode)
	cm.item_selected.connect(func(i: int):
		Settings.control_mode = ["auto", "touch", "keyboard"][i]
		Settings.apply_keys()
		Settings.save_settings())
	_row("Controles", cm, vb)
	_slider(vb, "Sensibilidade mouse", 0.2, 3.0, 0.05, Settings.look_sens, func(x): Settings.look_sens = x)
	_slider(vb, "Sensibilidade toque", 0.2, 3.0, 0.05, Settings.touch_look_sens, func(x): Settings.touch_look_sens = x)
	_slider(vb, "Campo de visão", 50.0, 110.0, 1.0, Settings.fov, func(x): Settings.fov = x)
	_slider(vb, "Distância (chunks)", 2.0, 10.0, 1.0, Settings.render_distance, func(x): Settings.render_distance = int(x))
	_slider(vb, "Tamanho da HUD", 0.6, 1.8, 0.05, Settings.hud_scale, func(x): Settings.hud_scale = x)
	_slider(vb, "Subir HUD (px)", 0.0, 240.0, 5.0, Settings.hud_margin, func(x): Settings.hud_margin = x)
	var ch := CheckBox.new()
	ch.text = "Mostrar mira (crosshair)"
	ch.button_pressed = Settings.show_crosshair
	ch.toggled.connect(func(v: bool):
		Settings.show_crosshair = v
		Settings.save_settings())
	vb.add_child(ch)
	var fps := CheckBox.new()
	fps.text = "Mostrar FPS e coordenadas"
	fps.button_pressed = Settings.show_fps
	fps.toggled.connect(func(v: bool):
		Settings.show_fps = v
		Settings.save_settings())
	vb.add_child(fps)
	var ne := LineEdit.new()
	ne.text = Settings.player_name
	ne.text_changed.connect(func(t: String):
		if t.strip_edges() != "":
			Settings.player_name = t.strip_edges().substr(0, 16)
			Settings.save_settings())
	_row("Nome do jogador", ne, vb)


func _tab_keys(vb: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Clique numa tecla e pressione a nova (tecla ou botão do mouse)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	for a in Settings.ACTIONS:
		var id: String = a[0]
		var b := Button.new()
		b.text = Settings.key_name(id)
		b.custom_minimum_size = Vector2(200, 44)
		b.pressed.connect(func():
			_cancel_listen()
			_listen_action = id
			_listen_btn = b
			b.text = "Pressione...")
		_row(a[1], b, vb)
	var r := Button.new()
	r.text = "Restaurar teclas padrão"
	r.custom_minimum_size = Vector2(0, 48)
	r.pressed.connect(func():
		Settings.reset_keys()
		_page_settings())
	vb.add_child(r)


func _tab_touch(vb: VBoxContainer) -> void:
	_slider(vb, "Opacidade dos botões", 0.15, 1.0, 0.05, Settings.touch_opacity, func(x): Settings.touch_opacity = x)
	_slider(vb, "Tamanho geral", 0.6, 1.8, 0.05, Settings.touch_scale, func(x): Settings.touch_scale = x)
	var e := Button.new()
	e.text = "Ajustar posição e tamanho dos botões"
	e.custom_minimum_size = Vector2(0, 52)
	e.pressed.connect(func():
		visible = false
		main.touch.start_edit(func():
			visible = true
			_page_settings()))
	vb.add_child(e)
	var r := Button.new()
	r.text = "Restaurar botões padrão"
	r.custom_minimum_size = Vector2(0, 48)
	r.pressed.connect(func():
		Settings.reset_touch()
		toast("Botões restaurados"))
	vb.add_child(r)


# ------------------------------------------------------------ reatribuir teclas
func _cancel_listen() -> void:
	if _listen_action != "" and _listen_btn != null and is_instance_valid(_listen_btn):
		_listen_btn.text = Settings.key_name(_listen_action)
	_listen_action = ""
	_listen_btn = null


func _input(event: InputEvent) -> void:
	if _listen_action == "" or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_ESCAPE:
			_cancel_listen()
			return
		Settings.set_key(_listen_action, event)
		_cancel_listen()
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		Settings.set_key(_listen_action, event)
		_cancel_listen()
