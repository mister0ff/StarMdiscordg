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
var _cc: CenterContainer
var _extra: Control
var _av_node: Node3D
var _drag := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font_size = 22
	theme = th
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_extra = Control.new()
	_extra.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_extra)
	_cc = CenterContainer.new()
	_cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_cc)
	var panel := PanelContainer.new()
	_cc.add_child(panel)
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
	if is_instance_valid(_av_node) and not _drag:
		_av_node.rotation.y += delta * 0.6
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
		"new", "multi", "edit":
			_page_play()
		"play", "avatar":
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
	_cc.visible = true
	_av_node = null
	for c in _extra.get_children():
		_extra.remove_child(c)
		c.queue_free()
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
	_begin("main", Color(0.05, 0.08, 0.14, 1))
	_cc.visible = false
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	_extra.add_child(hb)
	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(left)
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(380, 0)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 16)
	hb.add_child(mid)
	var t := Label.new()
	t.text = "CUBOLÂNDIA"
	t.add_theme_font_size_override("font_size", 56)
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(t)
	var b1 := _btn("Jogar", _page_play, mid)
	b1.custom_minimum_size = Vector2(0, 72)
	b1.add_theme_font_size_override("font_size", 30)
	var open_opts := func():
		_back_state = "main"
		_page_settings()
	var b2 := _btn("Opções", open_opts, mid)
	b2.custom_minimum_size = Vector2(0, 72)
	b2.add_theme_font_size_override("font_size", 30)
	if OS.has_feature("pc"):
		_btn("Sair", func(): get_tree().quit(), mid)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	var nick := Label.new()
	nick.text = Settings.player_name
	nick.add_theme_font_size_override("font_size", 28)
	nick.add_theme_color_override("font_outline_color", Color.BLACK)
	nick.add_theme_constant_override("outline_size", 8)
	nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(nick)
	right.add_child(_avatar_view(Vector2(260, 360)))
	var row := VBoxContainer.new()
	row.custom_minimum_size = Vector2(260, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(row)
	_btn("Ajustes", _page_avatar, row)
	var cb := _btn("Capas (em breve)", func(): pass, row)
	cb.disabled = true
	var eb := _btn("Emotes (em breve)", func(): pass, row)
	eb.disabled = true


func _make_avatar() -> Node3D:
	var root := Node3D.new()
	var c: Dictionary = Settings.skin
	root.add_child(Util.make_shaded_box(Vector3(0.5, 0.72, 0.26), c["shirt"], Vector3(0, 1.1, 0)))
	root.add_child(Util.make_shaded_box(Vector3(0.5, 0.5, 0.5), c["skin"], Vector3(0, 1.72, 0)))
	root.add_child(Util.make_shaded_box(Vector3(0.52, 0.14, 0.52), c["hair"], Vector3(0, 1.97, 0.01)))
	for sx in [-1.0, 1.0]:
		root.add_child(Util.make_shaded_box(Vector3(0.09, 0.09, 0.03), Color(0.1, 0.2, 0.5), Vector3(sx * 0.12, 1.75, -0.26)))
		root.add_child(Util.make_shaded_box(Vector3(0.23, 0.74, 0.24), c["pants"], Vector3(sx * 0.13, 0.37, 0)))
		root.add_child(Util.make_shaded_box(Vector3(0.2, 0.7, 0.2), c["skin"], Vector3(sx * 0.36, 1.07, 0)))
	return root


func _avatar_view(sz: Vector2) -> SubViewportContainer:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = sz
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.05, 3.8)
	cam.fov = 40.0
	sv.add_child(cam)
	cam.current = true
	_av_node = _make_avatar()
	sv.add_child(_av_node)
	svc.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton:
			_drag = ev.pressed
		elif ev is InputEventMouseMotion and _drag and is_instance_valid(_av_node):
			_av_node.rotation.y += ev.relative.x * 0.012)
	return svc


func _page_avatar() -> void:
	_begin("avatar", Color(0.05, 0.08, 0.14, 1))
	_title("Ajustes do avatar", 36)
	var ne := LineEdit.new()
	ne.text = Settings.player_name
	ne.text_changed.connect(func(t: String):
		if t.strip_edges() != "":
			Settings.player_name = t.strip_edges().substr(0, 16)
			Settings.save_settings())
	_row("Seu nick", ne)
	for k in [["skin", "Pele"], ["hair", "Cabelo"], ["shirt", "Camisa"], ["pants", "Calça"]]:
		var key: String = k[0]
		var cp := ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(0, 44)
		cp.color = Settings.skin[key]
		cp.edit_alpha = false
		cp.color_changed.connect(func(col: Color):
			Settings.skin[key] = col
			Settings.save_settings())
		_row(k[1], cp)
	_btn("Voltar", func(): show_main(_has_save))


func _find_img(base: String) -> Texture2D:
	for ext in [".png", ".jpg", ".jpeg", ".webp"]:
		if ResourceLoader.exists(base + ext):
			var r = load(base + ext)
			if r is Texture2D:
				return r
	return null


const SERVERS := [
	{"id": "starcat", "name": "Starcat Mc", "desc": "Servidor de sobrevivência", "seed": 7001, "color": Color(0.7, 0.15, 0.2)},
	{"id": "auralis", "name": "Auralis Net", "desc": "Servidor criativo e aventura", "seed": 7002, "color": Color(0.15, 0.4, 0.8)},
]


func _page_play(tab := 0) -> void:
	_begin("play", Color(0.05, 0.08, 0.14, 1))
	_page.custom_minimum_size = Vector2(900, 0)
	_title("Jogar", 36)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(900, 420)
	_page.add_child(tabs)
	# ---- mundos
	var wv := VBoxContainer.new()
	wv.name = "Mundos"
	wv.add_theme_constant_override("separation", 10)
	tabs.add_child(wv)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	wv.add_child(grid)
	if _has_save:
		var d: Dictionary = main.read_save_public()
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(280, 0)
		grid.add_child(card)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		var img := ColorRect.new()
		img.custom_minimum_size = Vector2(0, 90)
		img.color = Color(0.35, 0.62, 0.22) if d.get("type", "normal") == "normal" else Color(0.45, 0.7, 0.3)
		cv.add_child(img)
		var nm := Label.new()
		nm.text = "Mundo salvo (%s)" % ("Plano" if d.get("type", "normal") == "flat" else "Normal")
		cv.add_child(nm)
		var hrow := HBoxContainer.new()
		cv.add_child(hrow)
		var pb := _btn("Jogar", func(): main.start_world(false, 0, true, true), hrow)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var eb := _btn("Editar", _page_edit, hrow)
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		var lb := Label.new()
		lb.text = "Nenhum mundo ainda. Crie o primeiro!"
		wv.add_child(lb)
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	wv.add_child(pager)
	var pl := _btn("<", func(): pass, pager)
	pl.disabled = true
	var pr := _btn(">", func(): pass, pager)
	pr.disabled = true
	_btn("+ Novo mundo", _page_new, wv)
	# ---- servidores
	var sv := VBoxContainer.new()
	sv.name = "Servidores"
	sv.add_theme_constant_override("separation", 10)
	tabs.add_child(sv)
	var admin: bool = Settings.player_name.strip_edges() == "X EDUHH X"
	for sd in SERVERS:
		var sid: String = sd["id"]
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(0, 120)
		sv.add_child(holder)
		var ban := _find_img("res://assets/servers/%s_banner" % sid)
		if ban != null:
			var tr := TextureRect.new()
			tr.texture = ban
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			holder.add_child(tr)
		else:
			var cr := ColorRect.new()
			cr.color = sd["color"]
			cr.set_anchors_preset(Control.PRESET_FULL_RECT)
			holder.add_child(cr)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.45)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(shade)
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.add_theme_constant_override("separation", 12)
		holder.add_child(h)
		var logo := _find_img("res://assets/servers/%s_logo" % sid)
		var lg := TextureRect.new()
		lg.custom_minimum_size = Vector2(96, 96)
		lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		lg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lg.texture = logo
		h.add_child(lg)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(info)
		var sn := Label.new()
		sn.text = sd["name"]
		sn.add_theme_font_size_override("font_size", 30)
		info.add_child(sn)
		var sdsc := Label.new()
		sdsc.text = str(sd["desc"]) + ("  •  Você é ADM" if admin else "")
		info.add_child(sdsc)
		var jb := Button.new()
		jb.text = "Jogar"
		jb.custom_minimum_size = Vector2(140, 56)
		jb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sseed: int = sd["seed"]
		jb.pressed.connect(func():
			main.start_world(false, sseed, true, false, main.PORT, "normal", false, admin, true))
		h.add_child(jb)
	_btn("Entrar por IP / Hospedar", _page_multi, sv)
	# ---- realms
	var rv := VBoxContainer.new()
	rv.name = "Realms"
	tabs.add_child(rv)
	var rl := Label.new()
	rl.text = "Realms: em breve (beta)."
	rv.add_child(rl)
	tabs.current_tab = tab
	_btn("Voltar", func(): show_main(_has_save))


func _page_edit() -> void:
	_begin("edit", Color(0.05, 0.08, 0.14, 1))
	_title("Editar mundo", 36)
	var d: Dictionary = main.read_save_public()
	if d.is_empty():
		_label("Mundo não encontrado.")
		_btn("Voltar", _page_play)
		return
	var always := CheckBox.new()
	always.text = "Sempre dia"
	always.button_pressed = bool(d.get("always", false))
	_row("Dia", always)
	var mobs := CheckBox.new()
	mobs.text = "Spawn de mobs"
	mobs.button_pressed = bool(d.get("mobs", true))
	_row("Mobs", mobs)
	var cmds := CheckBox.new()
	cmds.text = "Comandos ativados"
	cmds.button_pressed = bool(d.get("cmds", true))
	_row("Comandos", cmds)
	_label("Modelo: %s (não muda depois de criado)" % ("Plano" if d.get("type", "normal") == "flat" else "Normal"))
	_btn("Salvar", func():
		d["always"] = always.button_pressed
		d["mobs"] = mobs.button_pressed
		d["cmds"] = cmds.button_pressed
		main.write_save_public(d)
		toast("Salvo!")
		_page_play())
	_btn("Apagar mundo", func():
		DirAccess.remove_absolute(main.SAVE_PATH)
		_has_save = false
		toast("Mundo apagado")
		_page_play())
	_btn("Voltar", _page_play)


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
	_btn("Voltar", _page_play)


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
