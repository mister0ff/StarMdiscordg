extends Control
## Menus: tela inicial (panorama + avatar), Jogar (Mundos/Servidores/Realms), criar/editar mundo,
## mods, pausa e configurações.

var main: Node
var state := "main"

var _bg: ColorRect
var _content: Control
var _toast: Label
var _toast_t := 0.0
var _back_state := "main"
var _ignore_frame := -1
var _listen_action := ""
var _listen_btn: Button
var _tab := "worlds"
var _world_page := 0
var _cur_meta: Dictionary = {}
var _avatar: PlayerModel
var _avatar_idle := 0.0
var _tex_cache: Dictionary = {}
var _confirm := ""
var _file_dialog: FileDialog

const CARD_W := 300.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font_size = 22
	theme = th
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_content = Control.new()
	add_child(_content)
	_toast = Label.new()
	_toast.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.visible = false
	_toast.z_index = 50
	add_child(_toast)
	visible = false


func _process(delta: float) -> void:
	var r := Util.safe_rect(get_viewport())
	_content.position = r.position
	_content.size = r.size
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
	if _avatar != null and is_instance_valid(_avatar):
		_avatar_idle += delta
		_avatar.rotation.y += delta * 0.6
		_avatar.animate(delta, 0.0, false)
	if visible and Input.is_action_just_pressed("ui_cancel") and Engine.get_process_frames() != _ignore_frame and _listen_action == "":
		go_back()


func toast(t: String) -> void:
	_toast.text = t
	_toast.visible = true
	_toast.reset_size()
	_toast.position = Vector2((size.x - _toast.size.x) * 0.5, 14)
	_toast_t = 3.5


func hide_all() -> void:
	visible = false
	state = "none"


func go_back() -> void:
	match state:
		"pause":
			main.resume_game()
		"settings":
			if _back_state == "pause":
				show_pause(main.online, main.is_host)
			else:
				show_main()
		"play", "avatar":
			show_main()
		"new":
			_page_play()
		"edit":
			_page_play()
		"mods":
			_page_edit(_cur_meta)
		"import":
			_page_mods(_cur_meta)


# ------------------------------------------------------------ helpers
func _begin(st: String, bg: Color) -> void:
	state = st
	visible = true
	_bg.color = bg
	_ignore_frame = Engine.get_process_frames()
	var r0 := Util.safe_rect(get_viewport())
	_content.position = r0.position
	_content.size = r0.size
	_avatar = null
	_confirm = ""
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _lbl(t: String, sz := 22, parent: Node = null, center := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if parent != null:
		parent.add_child(l)
	return l


func _btn(t: String, parent: Node, h: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, h)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _style(col: Color, border := Color(1, 1, 1, 0.12)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb


## Coluna central com painel e rolagem.
func _panel_col(min_w: float, title := "", tsz := 36) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(sc)
	var cc := CenterContainer.new()
	cc.custom_minimum_size = Vector2(maxf(get_viewport().get_visible_rect().size.x - 40.0, 300.0), 0)
	sc.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(Color(0.06, 0.08, 0.13, 0.92)))
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(min_w, 0)
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	if title != "":
		_lbl(title, tsz, vb, true)
	return vb


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


func _row(label: String, ctrl: Control, parent: Node) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(200, 0)
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	parent.add_child(h)


func _rules_editor(parent: Node, rules: Dictionary) -> Dictionary:
	var boxes: Dictionary = {}
	var grid := GridContainer.new()
	grid.columns = 2
	for rl in WorldStore.RULE_LABELS:
		var cb := CheckBox.new()
		cb.text = rl[1]
		cb.button_pressed = bool(rules.get(rl[0], WorldStore.DEFAULT_RULES[rl[0]]))
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cb)
		boxes[rl[0]] = cb
	parent.add_child(grid)
	return boxes


func _read_rules(boxes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in boxes:
		out[k] = (boxes[k] as CheckBox).button_pressed
	return out


# ------------------------------------------------------------ imagens (banner/logo)
func _placeholder(col: Color) -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(col)
	return ImageTexture.create_from_image(img)


func _load_image(file: String, url: String, tr: TextureRect, col: Color) -> void:
	if _tex_cache.has(file):
		tr.texture = _tex_cache[file]
		return
	tr.texture = _placeholder(col.darkened(0.4))
	var rp := "res://assets/servers/" + file
	if ResourceLoader.exists(rp):
		var t := load(rp) as Texture2D
		if t != null:
			_tex_cache[file] = t
			tr.texture = t
			return
	var up := "user://cache/" + file
	if FileAccess.file_exists(up):
		var im := Image.load_from_file(up)
		if im != null:
			var t2 := ImageTexture.create_from_image(im)
			_tex_cache[file] = t2
			tr.texture = t2
			return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_res: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code != 200:
			return
		var img2 := Util.image_from_bytes(body)
		if img2 == null:
			return
		DirAccess.make_dir_recursive_absolute("user://cache")
		var f := FileAccess.open(up, FileAccess.WRITE)
		if f != null:
			f.store_buffer(body)
			f.close()
		var t3 := ImageTexture.create_from_image(img2)
		_tex_cache[file] = t3
		if is_instance_valid(tr):
			tr.texture = t3)
	http.request(url, PackedStringArray(["User-Agent: Mozilla/5.0"]))


func _tex_rect(h: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = Vector2(0, h)
	tr.clip_contents = true
	return tr


# ------------------------------------------------------------ avatar 3D
func _make_avatar(sz: Vector2i) -> SubViewportContainer:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(sz)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.size = sz
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 3.6)
	cam.rotation = Vector3(-0.1, 0, 0)
	cam.current = true
	sv.add_child(cam)
	var m := PlayerModel.new()
	m.build(Settings.avatar_skin, Settings.avatar_shirt, Settings.avatar_pants, Settings.avatar_hair)
	sv.add_child(m)
	m.rotation.y = 0.5
	_avatar = m
	svc.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			m.rotation.y += ev.relative.x * 0.015
		elif ev is InputEventScreenDrag:
			m.rotation.y += ev.relative.x * 0.015)
	return svc


# ------------------------------------------------------------ tela inicial
func show_main() -> void:
	_begin("main", Color(0, 0, 0, 0.18))
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_child(cc)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override("separation", 14)
	cc.add_child(col)
	var title := _lbl("CUBOLÂNDIA", 64, col, true)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 12)
	var sub := _lbl("Construa • Sobreviva • Crie mods", 22, col, true)
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 6)
	_btn("Jogar", col, 68, func(): _page_play())
	_btn("Opções", col, 68, func():
		_back_state = "main"
		_page_settings())
	if not OS.has_feature("mobile"):
		_btn("Sair", col, 44, func(): get_tree().quit())
	# avatar à direita
	var av := VBoxContainer.new()
	av.anchor_left = 1.0
	av.anchor_right = 1.0
	av.anchor_top = 0.5
	av.anchor_bottom = 0.5
	av.offset_left = -300
	av.offset_right = -16
	av.offset_top = -250
	av.offset_bottom = 250
	av.add_theme_constant_override("separation", 6)
	_content.add_child(av)
	var nick := _lbl(Settings.player_name, 26, av, true)
	nick.add_theme_color_override("font_outline_color", Color.BLACK)
	nick.add_theme_constant_override("outline_size", 8)
	var view := _make_avatar(Vector2i(270, 340))
	av.add_child(view)
	_btn("Ajustes", av, 48, func(): _page_avatar())


func _page_avatar() -> void:
	_begin("avatar", Color(0.04, 0.06, 0.1, 0.88))
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 20)
	_content.add_child(hb)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(left)
	_lbl(Settings.player_name, 32, left, true)
	var view := _make_avatar(Vector2i(360, 480))
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(view)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_constant_override("separation", 10)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(400, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(sc)
	sc.add_child(right)
	_lbl("Ajustes do avatar", 32, right, true)
	for spec in [["Pele", "avatar_skin"], ["Camisa", "avatar_shirt"], ["Calça", "avatar_pants"], ["Cabelo", "avatar_hair"]]:
		var cp := ColorPickerButton.new()
		cp.color = Settings.get(spec[1])
		cp.custom_minimum_size = Vector2(0, 48)
		cp.edit_alpha = false
		cp.color_changed.connect(func(c: Color):
			Settings.set(spec[1], c)
			Settings.save_settings())
		_row(spec[0], cp, right)
	var cap := _btn("Capas  (Beta)", right, 52, func(): toast("Capas: em breve (beta)"))
	cap.disabled = true
	var emo := _btn("Emotes  (Beta)", right, 52, func(): toast("Emotes: em breve (beta)"))
	emo.disabled = true
	_lbl("Capas e Emotes estão trancados porque o jogo está em beta.", 18, right)
	_btn("Voltar", right, 52, func(): show_main())


# ------------------------------------------------------------ Jogar
func _page_play() -> void:
	_begin("play", Color(0.03, 0.05, 0.09, 0.82))
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	_content.add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var back_b := _btn("< Voltar", top, 48, func(): show_main())
	back_b.custom_minimum_size.x = 130
	for t in [["worlds", "Mundos"], ["servers", "Servidores"], ["realms", "Realms"]]:
		var b := _btn(t[1], top, 48, func():
			_tab = t[0]
			_world_page = 0
			_page_play())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = (_tab == t[0])
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	sc.add_child(body)
	match _tab:
		"worlds":
			_tab_worlds(body)
		"servers":
			_tab_servers(body)
		_:
			_tab_realms(body)


func _tab_worlds(body: VBoxContainer) -> void:
	var worlds := WorldStore.list_worlds()
	var hd := HBoxContainer.new()
	body.add_child(hd)
	var l := _lbl("Mundos (%d)" % worlds.size(), 30, hd)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var new_b := _btn("+ Criar mundo", hd, 48, func(): _page_new())
	new_b.custom_minimum_size.x = 200
	var pages := maxi(1, int(ceil(worlds.size() / 9.0)))
	_world_page = clampi(_world_page, 0, pages - 1)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	var start := _world_page * 9
	for i in range(start, mini(start + 9, worlds.size())):
		_world_card(grid, worlds[i])
	if worlds.is_empty():
		_lbl("Nenhum mundo ainda. Toque em \"+ Criar mundo\".", 22, body)
	var pg := HBoxContainer.new()
	pg.alignment = BoxContainer.ALIGNMENT_CENTER
	pg.add_theme_constant_override("separation", 14)
	body.add_child(pg)
	var prev := _btn("<", pg, 44, func():
		_world_page -= 1
		_page_play())
	prev.custom_minimum_size.x = 80
	prev.disabled = _world_page <= 0
	_lbl("%d / %d" % [_world_page + 1, pages], 22, pg)
	var nxt := _btn(">", pg, 44, func():
		_world_page += 1
		_page_play())
	nxt.custom_minimum_size.x = 80
	nxt.disabled = _world_page >= pages - 1


func _world_card(grid: GridContainer, m: Dictionary) -> void:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(CARD_W, 0)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _style(Color(0.1, 0.13, 0.2, 0.95)))
	grid.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var tr := _tex_rect(54)
	tr.texture = WorldStore.thumbnail(m)
	vb.add_child(tr)
	var mode := "Criativo" if m.get("creative", false) else "Sobrevivência"
	var typ := "Plano" if m.get("type", "normal") == "flat" else "Normal"
	var nm := _lbl(str(m["name"]), 22, vb)
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.clip_text = true
	var sub := _lbl("%s • %s" % [mode, typ], 15, vb)
	sub.modulate = Color(1, 1, 1, 0.7)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	var pb := _btn("Jogar", hb, 40, func(): main.start_world(m))
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var eb := _btn("Editar", hb, 40, func(): _page_edit(m))
	eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _tab_servers(body: VBoxContainer) -> void:
	_lbl("Servidores", 30, body)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	body.add_child(hb)
	for def in ServerDefs.SERVERS:
		var m := WorldStore.ensure_server(def)
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.add_theme_stylebox_override("panel", _style(Color(0.08, 0.1, 0.16, 0.96), def["color"]))
		hb.add_child(pc)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		pc.add_child(vb)
		var banner := _tex_rect(130)
		vb.add_child(banner)
		_load_image(def["banner_file"], def["banner_url"], banner, def["color"])
		var info := HBoxContainer.new()
		info.add_theme_constant_override("separation", 10)
		vb.add_child(info)
		var logo := _tex_rect(64)
		logo.custom_minimum_size = Vector2(64, 64)
		info.add_child(logo)
		_load_image(def["logo_file"], def["logo_url"], logo, def["color"])
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(tv)
		_lbl(def["name"], 28, tv)
		var d := _lbl(def["desc"], 15, tv)
		d.modulate = Color(1, 1, 1, 0.7)
		var br := HBoxContainer.new()
		br.add_theme_constant_override("separation", 6)
		vb.add_child(br)
		var jb := _btn("Jogar", br, 46, func(): main.start_world(WorldStore.ensure_server(def)))
		jb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if ServerDefs.is_admin_nick(Settings.player_name):
			var gb := _btn("Gerenciar", br, 46, func(): _page_edit(WorldStore.ensure_server(def)))
			gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not ServerDefs.is_admin_nick(Settings.player_name):
		var n := _lbl("Só o administrador pode gerenciar os servidores.", 16, body)
		n.modulate = Color(1, 1, 1, 0.6)


func _tab_realms(body: VBoxContainer) -> void:
	_lbl("Realms — multijogador por IP", 30, body)
	var name_e := LineEdit.new()
	name_e.text = Settings.player_name
	_row("Seu nome", name_e, body)
	var save_name := func():
		var n := name_e.text.strip_edges()
		if n != "":
			Settings.player_name = n.substr(0, 16)
		Settings.save_settings()
	_lbl("— Hospedar um mundo (amigos entram pelo seu IP + porta) —", 20, body)
	var worlds := WorldStore.list_worlds()
	var ob := OptionButton.new()
	for w in worlds:
		ob.add_item(str(w["name"]))
	_row("Mundo", ob, body)
	var port_e := LineEdit.new()
	port_e.text = str(main.PORT)
	_row("Porta", port_e, body)
	_btn("Hospedar", body, 50, func():
		if worlds.is_empty():
			toast("Crie um mundo primeiro.")
			return
		save_name.call()
		main.start_world(worlds[ob.selected], int(port_e.text)))
	_lbl("— Entrar em um servidor —", 20, body)
	var ip_e := LineEdit.new()
	ip_e.text = Settings.last_ip
	_row("IP", ip_e, body)
	var jport := LineEdit.new()
	jport.text = str(main.PORT)
	_row("Porta", jport, body)
	_btn("Entrar", body, 50, func():
		save_name.call()
		Settings.last_ip = ip_e.text.strip_edges()
		Settings.save_settings()
		main.join_server(Settings.last_ip, int(jport.text)))


# ------------------------------------------------------------ criar / editar mundo
func _page_new() -> void:
	_begin("new", Color(0.03, 0.05, 0.09, 0.85))
	var vb := _panel_col(640, "Criar mundo", 34)
	var name_e := LineEdit.new()
	name_e.text = "Novo mundo"
	_row("Nome", name_e, vb)
	var mode := OptionButton.new()
	mode.add_item("Sobrevivência")
	mode.add_item("Criativo")
	_row("Modo", mode, vb)
	var typ := OptionButton.new()
	typ.add_item("Normal")
	typ.add_item("Plano")
	_row("Modelo do mundo", typ, vb)
	var seed_e := LineEdit.new()
	seed_e.placeholder_text = "vazio = aleatória"
	_row("Semente", seed_e, vb)
	_lbl("Regras do mundo", 24, vb)
	var boxes := _rules_editor(vb, WorldStore.DEFAULT_RULES)
	_btn("Criar e jogar", vb, 56, func():
		var t := seed_e.text.strip_edges()
		var sv := 0
		if t != "":
			sv = int(t) if t.is_valid_int() else (t.hash() & 0x7fffffff)
		var nm := name_e.text.strip_edges()
		if nm == "":
			nm = "Novo mundo"
		var m := WorldStore.new_meta(nm, sv, "flat" if typ.selected == 1 else "normal", mode.selected == 1, _read_rules(boxes))
		WorldStore.save_meta(m)
		main.start_world(m))
	_btn("Voltar", vb, 48, func(): _page_play())


func _page_edit(m: Dictionary) -> void:
	_cur_meta = m
	var is_server: bool = m.get("kind", "world") == "server"
	_begin("edit", Color(0.03, 0.05, 0.09, 0.85))
	var vb := _panel_col(640, ("Gerenciar servidor" if is_server else "Editar mundo"), 34)
	var name_e := LineEdit.new()
	name_e.text = str(m["name"])
	name_e.editable = not is_server
	_row("Nome", name_e, vb)
	var mode := OptionButton.new()
	mode.add_item("Sobrevivência")
	mode.add_item("Criativo")
	mode.selected = 1 if m.get("creative", false) else 0
	_row("Modo", mode, vb)
	var typ := OptionButton.new()
	typ.add_item("Normal")
	typ.add_item("Plano")
	typ.selected = 1 if m.get("type", "normal") == "flat" else 0
	_row("Modelo do mundo", typ, vb)
	var seed_e := LineEdit.new()
	seed_e.text = str(m["seed"])
	_row("Semente", seed_e, vb)
	var warn := _lbl("Mudar o modelo ou a semente recria o terreno (apaga as construções).", 16, vb)
	warn.modulate = Color(1, 0.8, 0.4)
	_lbl("Regras", 24, vb)
	var boxes := _rules_editor(vb, WorldStore.rules_of(m))
	_btn("Mods", vb, 52, func(): _page_mods(m))
	_btn("Salvar alterações", vb, 52, func():
		var changed_terrain := false
		var new_type := "flat" if typ.selected == 1 else "normal"
		var ts := seed_e.text.strip_edges()
		var new_seed := int(ts) if ts.is_valid_int() else int(m["seed"])
		if new_type != m.get("type", "normal") or new_seed != int(m["seed"]):
			changed_terrain = true
		if not is_server:
			m["name"] = name_e.text.strip_edges() if name_e.text.strip_edges() != "" else m["name"]
		m["creative"] = mode.selected == 1
		m["type"] = new_type
		m["seed"] = new_seed
		m["rules"] = _read_rules(boxes)
		if changed_terrain:
			WorldStore.wipe_save(m["id"])
		WorldStore.save_meta(m)
		toast("Salvo!" + (" Terreno recriado." if changed_terrain else "")))
	_btn("Recriar mundo (nova semente)", vb, 48, func():
		m["seed"] = randi() % 1000000 + 1
		WorldStore.wipe_save(m["id"])
		WorldStore.save_meta(m)
		toast("Mundo recriado com nova semente."))
	var del := Button.new()
	del.text = "Apagar servidor (reiniciar mundo)" if is_server else "Apagar mundo"
	del.custom_minimum_size = Vector2(0, 48)
	del.pressed.connect(func():
		if _confirm != "del":
			_confirm = "del"
			del.text = "Tem certeza? Toque de novo para apagar"
			return
		if is_server:
			WorldStore.wipe_save(m["id"])
			m["idmap"] = {}
			WorldStore.save_meta(m)
			toast("Mundo do servidor reiniciado.")
			_page_play()
		else:
			WorldStore.delete_world(m["id"])
			toast("Mundo apagado.")
			_page_play())
	vb.add_child(del)
	_btn("Voltar", vb, 48, func(): _page_play())


# ------------------------------------------------------------ mods
func _page_mods(m: Dictionary) -> void:
	_cur_meta = m
	_begin("mods", Color(0.03, 0.05, 0.09, 0.88))
	var vb := _panel_col(680, "Mods — %s" % str(m["name"]), 32)
	var can_add: bool = m.get("kind", "world") != "server" or ServerDefs.is_admin_nick(Settings.player_name)
	if can_add:
		_btn("+ Importar mod (.stc)", vb, 54, func(): _page_import(m))
	else:
		_lbl("Só o admin pode adicionar mods.", 18, vb)
	var list := ModManager.list_installed(m)
	if list.is_empty():
		_lbl("Nenhum mod instalado neste mundo.", 20, vb)
	for info in list:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _style(Color(0.1, 0.13, 0.2, 0.95)))
		vb.add_child(pc)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		pc.add_child(hb)
		var ic := _tex_rect(72)
		ic.custom_minimum_size = Vector2(72, 72)
		ic.texture = info["icon"] if info.get("icon") != null else _placeholder(Color(0.3, 0.3, 0.4))
		hb.add_child(ic)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(tv)
		_lbl("%s  v%s" % [info["name"], info.get("version", "?")], 22, tv)
		var d := _lbl(str(info.get("description", "")), 16, tv)
		d.modulate = Color(1, 1, 1, 0.75)
		var st := _lbl("Ativado" if info["enabled"] else "Desativado", 15, tv)
		st.modulate = Color(0.5, 1, 0.5) if info["enabled"] else Color(1, 0.6, 0.5)
		if can_add:
			var bv := VBoxContainer.new()
			hb.add_child(bv)
			_btn("Desativar" if info["enabled"] else "Ativar", bv, 40, func():
				ModManager.set_enabled(m, info["file"], not info["enabled"])
				_page_mods(m))
			_btn("Apagar", bv, 40, func():
				ModManager.remove(m, info["file"])
				_page_mods(m))
	_lbl("Os mods são carregados quando você entra no mundo.", 16, vb)
	_btn("Voltar", vb, 48, func(): _page_edit(m))


func _scan_stc() -> Array:
	var dirs: Array = [OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
		"/storage/emulated/0/Download", "/storage/emulated/0/Documents", "/sdcard/Download", "user://mods_inbox"]
	var out: Array = []
	var seen: Dictionary = {}
	for d in dirs:
		if str(d) == "" or seen.has(d):
			continue
		seen[d] = true
		for f in DirAccess.get_files_at(d):
			if str(f).to_lower().ends_with(".stc"):
				out.append(str(d).path_join(f))
	return out


func _page_import(m: Dictionary) -> void:
	_cur_meta = m
	_begin("import", Color(0.03, 0.05, 0.09, 0.9))
	OS.request_permissions()
	DirAccess.make_dir_recursive_absolute("user://mods_inbox")
	var vb := _panel_col(680, "Importar mod", 32)
	_lbl("Copie o arquivo .stc para a pasta Download (ou Documentos) do aparelho e escolha abaixo.", 18, vb)
	var files := _scan_stc()
	if files.is_empty():
		_lbl("Nenhum .stc encontrado nas pastas padrão.", 18, vb)
	for path in files:
		_btn("%s   (%s)" % [str(path).get_file(), str(path).get_base_dir()], vb, 48, func(): _do_install(m, path))
	_btn("Procurar arquivo...", vb, 52, func():
		if _file_dialog == null:
			_file_dialog = FileDialog.new()
			_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
			_file_dialog.filters = PackedStringArray(["*.stc ; Mod Cubolândia"])
			_file_dialog.set("use_native_dialog", true)
			_file_dialog.size = Vector2i(800, 500)
			add_child(_file_dialog)
		for c in _file_dialog.file_selected.get_connections():
			_file_dialog.file_selected.disconnect(c["callable"])
		_file_dialog.file_selected.connect(func(p: String): _do_install(m, p))
		_file_dialog.popup_centered())
	_btn("Voltar", vb, 48, func(): _page_mods(m))


func _do_install(m: Dictionary, path: String) -> void:
	var r := ModManager.install(m, path)
	if r.get("ok", false):
		toast("Mod \"%s\" instalado!" % r["name"])
		_page_mods(m)
	else:
		toast(str(r.get("error", "Falha ao importar.")))


# ------------------------------------------------------------ pausa
func show_pause(online: bool, is_host: bool) -> void:
	_begin("pause", Color(0, 0, 0, 0.55))
	var vb := _panel_col(460, "Pausado", 40)
	if online and is_host:
		_lbl("Servidor aberto na porta %d." % main.PORT, 18, vb)
	elif online:
		_lbl("Conectado a um servidor.", 18, vb)
	_btn("Continuar", vb, 54, func(): main.resume_game())
	var pers := _btn("Perspectiva: %s" % ["1ª pessoa", "3ª pessoa", "2ª pessoa"][main.local_player.perspective], vb, 48, func():
		main.local_player.cycle_perspective()
		show_pause(online, is_host))
	_btn("Chat", vb, 48, func():
		main.resume_game()
		main.chat_ui.open())
	if Settings.use_touch():
		_btn("Ajustar botões (toque)", vb, 48, func():
			visible = false
			main.touch.start_edit(func():
				visible = true
				show_pause(online, is_host)))
	_btn("Configurações", vb, 48, func():
		_back_state = "pause"
		_page_settings())
	if not online or is_host:
		_btn("Salvar jogo", vb, 48, func():
			main.save_game()
			toast("Jogo salvo!"))
	_btn("Sair para o menu", vb, 48, func(): main.go_menu())


# ------------------------------------------------------------ configurações
func _page_settings() -> void:
	_begin("settings", Color(0.05, 0.07, 0.12, 0.9) if _back_state == "main" else Color(0, 0, 0, 0.7))
	var vb := _panel_col(700, "Configurações", 34)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(700, 360)
	vb.add_child(tabs)
	_tab_general(_tab_box(tabs, "Geral"))
	_tab_keys(_tab_box(tabs, "Teclas"))
	_tab_touch(_tab_box(tabs, "Toque"))
	_btn("Voltar", vb, 52, func(): go_back())


func _tab_box(tabs: TabContainer, nm: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = nm
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v


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
	_lbl("Usa mouse no celular/emulador? Escolha \"Teclado e mouse\".", 15, vb)
	var pv := OptionButton.new()
	pv.add_item("1ª pessoa")
	pv.add_item("3ª pessoa (atrás)")
	pv.add_item("2ª pessoa (de frente)")
	pv.selected = Settings.perspective
	pv.item_selected.connect(func(i: int):
		Settings.perspective = i
		if main.local_player != null:
			main.local_player.perspective = i
		Settings.save_settings())
	_row("Perspectiva", pv, vb)
	_slider(vb, "Sensibilidade mouse", 0.2, 3.0, 0.05, Settings.look_sens, func(x): Settings.look_sens = x)
	_slider(vb, "Sensibilidade toque", 0.2, 3.0, 0.05, Settings.touch_look_sens, func(x): Settings.touch_look_sens = x)
	_slider(vb, "Campo de visão", 50.0, 110.0, 1.0, Settings.fov, func(x): Settings.fov = x)
	_slider(vb, "Distância (chunks)", 2.0, 10.0, 1.0, Settings.render_distance, func(x): Settings.render_distance = int(x))
	_slider(vb, "Tamanho da HUD", 0.7, 1.6, 0.05, Settings.hud_scale, func(x): Settings.hud_scale = x)
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
	_lbl("Clique numa tecla e pressione a nova (tecla ou botão do mouse).", 16, vb)
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
	_btn("Restaurar teclas padrão", vb, 48, func():
		Settings.reset_keys()
		_page_settings())


func _tab_touch(vb: VBoxContainer) -> void:
	_slider(vb, "Opacidade dos botões", 0.15, 1.0, 0.05, Settings.touch_opacity, func(x): Settings.touch_opacity = x)
	_slider(vb, "Tamanho geral", 0.6, 1.8, 0.05, Settings.touch_scale, func(x): Settings.touch_scale = x)
	_btn("Ajustar posição e tamanho dos botões", vb, 52, func():
		visible = false
		main.touch.start_edit(func():
			visible = true
			_page_settings()))
	_btn("Restaurar botões padrão", vb, 48, func():
		Settings.reset_touch()
		toast("Botões restaurados"))


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
