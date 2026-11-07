extends Control
## Menus: inicial (Jogar / Opções), Jogar (Mundos / Servidores), criar/editar mundo,
## mods, pausa e configurações (geral, teclas, toque).

const BG := Color(0.06, 0.09, 0.16, 1)
const PER_PAGE := 9

var main: Node
var state := "main"

var _bg: ColorRect
var _deco: Control
var _page: VBoxContainer
var _panel: PanelContainer
var _toast: Label
var _toast_t := 0.0
var _listen_action := ""
var _listen_btn: Button
var _ignore_frame := -1
var _back: Callable = Callable()
var _settings_back := "main"
var _tab := 0 # 0 mundos, 1 servidores
var _world_page := 0


# ------------------------------------------------------------ decoração (fundo simples e leve)
class Deco:
	extends Control

	func _draw() -> void:
		var s := get_viewport_rect().size
		for i in 14:
			var h := s.y * (0.22 + 0.12 * sin(i * 1.7))
			var w := s.x / 14.0
			var c := Color(0.1, 0.2 + 0.015 * (i % 4), 0.28, 0.55)
			draw_rect(Rect2(i * w, s.y - h, w + 1.0, h), c)
			draw_rect(Rect2(i * w, s.y - h, w + 1.0, 8.0), Color(0.2, 0.45, 0.25, 0.7))
		for i in 18:
			var x := fmod(i * 197.0, s.x)
			var y := fmod(i * 83.0, s.y * 0.5)
			draw_rect(Rect2(x, y, 6, 6), Color(1, 1, 1, 0.18))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font_size = 22
	theme = th
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = BG
	add_child(_bg)
	_deco = Deco.new()
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deco)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	_panel = PanelContainer.new()
	cc.add_child(_panel)
	var mg := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 18)
	_panel.add_child(mg)
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
	if visible and Input.is_action_just_pressed("ui_cancel") and Engine.get_process_frames() != _ignore_frame and _listen_action == "":
		go_back()


func go_back() -> void:
	if _listen_action != "":
		_cancel_listen()
		return
	if state == "pause":
		main.resume_game()
	elif _back.is_valid():
		_back.call()


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


func _begin(st: String, bg := BG, width := 560.0) -> void:
	state = st
	visible = true
	_bg.color = bg
	_deco.visible = bg.a > 0.9
	_ignore_frame = Engine.get_process_frames()
	_page.custom_minimum_size = Vector2(width, 0)
	_clear()
	if not Settings.use_touch():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _title(t: String, sz := 40) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(l)
	return l


func _label(t: String, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(parent if parent != null else _page).add_child(l)
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
	l.custom_minimum_size = Vector2(200, 0)
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


func _gradient_tex(c: Color) -> ImageTexture:
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	for x in 64:
		for y in 16:
			img.set_pixel(x, y, c.darkened(0.55).lerp(c, float(x) / 63.0 * 0.8 + float(y) / 40.0))
	return ImageTexture.create_from_image(img)


func _tex_from_bytes(b: PackedByteArray) -> ImageTexture:
	if b.size() < 8:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if b[0] == 0xFF and b[1] == 0xD8:
		err = img.load_jpg_from_buffer(b)
	elif b[0] == 0x89 and b[1] == 0x50:
		err = img.load_png_from_buffer(b)
	elif b[0] == 0x52 and b[1] == 0x49:
		err = img.load_webp_from_buffer(b)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


## Procura em res://assets/servers/<chave>.(jpg|png|webp), depois no cache, depois baixa da URL.
func _load_image(url: String, key: String, tr: TextureRect) -> void:
	for ext in ["jpg", "png", "webp"]:
		var p := "res://assets/servers/%s.%s" % [key, ext]
		if ResourceLoader.exists(p):
			var t = load(p)
			if t is Texture2D:
				tr.texture = t
				return
	DirAccess.make_dir_recursive_absolute("user://cache")
	var cache := "user://cache/%s.img" % key
	if FileAccess.file_exists(cache):
		var ct := _tex_from_bytes(FileAccess.get_file_as_bytes(cache))
		if ct != null:
			tr.texture = ct
			return
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and is_instance_valid(tr):
			var nt := _tex_from_bytes(body)
			if nt != null:
				tr.texture = nt
				var f := FileAccess.open(cache, FileAccess.WRITE)
				if f != null:
					f.store_buffer(body)
					f.close()
		http.queue_free())
	if http.request(url) != OK:
		http.queue_free()


# ================================================================ página inicial
func show_main() -> void:
	get_tree().paused = false
	_back = Callable()
	_begin("main", BG, 460.0)
	_title("CUBOLÂNDIA", 56)
	var sub := _label("Mundos • Servidores • Mods")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var play := _btn("Jogar", _page_play)
	play.custom_minimum_size = Vector2(0, 64)
	var opt := _btn("Opções", func():
		_settings_back = "main"
		_page_settings())
	opt.custom_minimum_size = Vector2(0, 64)
	if not Settings.is_mobile():
		_btn("Sair", func(): get_tree().quit())


# ================================================================ Jogar
func _page_play() -> void:
	_back = show_main
	_begin("play", BG, 940.0)
	_title("Jogar", 38)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_page.add_child(tabs)
	var group := ButtonGroup.new()
	var names := ["Mundos", "Servidores"]
	for i in 2:
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == _tab
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			_tab = i
			_page_play())
		tabs.add_child(b)
	match _tab:
		0:
			_tab_worlds()
		_:
			_tab_servers()
	_btn("Voltar", show_main)


func _tab_worlds() -> void:
	var worlds := WorldStore.list_worlds()
	var pages := maxi(1, int(ceil(float(worlds.size()) / float(PER_PAGE))))
	_world_page = clampi(_world_page, 0, pages - 1)
	if worlds.is_empty():
		_label("Você ainda não tem mundos. Toque em \"Criar novo mundo\".")
	else:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 330)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_page.add_child(sc)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(grid)
		var from := _world_page * PER_PAGE
		for i in range(from, mini(from + PER_PAGE, worlds.size())):
			grid.add_child(_world_card(worlds[i]))
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	_page.add_child(nav)
	var on_prev := func():
		_world_page -= 1
		_page_play()
	var prev := _btn("<", on_prev, nav)
	prev.custom_minimum_size = Vector2(70, 46)
	prev.disabled = _world_page <= 0
	var pl := Label.new()
	pl.text = "Página %d/%d" % [_world_page + 1, pages]
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(pl)
	var on_next := func():
		_world_page += 1
		_page_play()
	var nxt := _btn(">", on_next, nav)
	nxt.custom_minimum_size = Vector2(70, 46)
	nxt.disabled = _world_page >= pages - 1
	_btn("Criar novo mundo", _page_new_world)


func _world_card(meta: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var tr := TextureRect.new()
	tr.texture = WorldStore.make_thumb(meta)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = Vector2(0, 92)
	vb.add_child(tr)
	var nm := Label.new()
	nm.text = String(meta["name"])
	nm.clip_text = true
	nm.add_theme_font_size_override("font_size", 20)
	vb.add_child(nm)
	var sub := Label.new()
	sub.text = "%s • %s" % ["Criativo" if bool(meta.get("creative", false)) else "Sobrevivência", "Plano" if String(meta.get("template", "normal")) == "flat" else "Normal"]
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(1, 1, 1, 0.65)
	vb.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	var pb := _btn("Jogar", func(): main.start_world_meta(meta), row)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.custom_minimum_size = Vector2(0, 44)
	var eb := _btn("Editar", func(): _page_edit(meta), row)
	eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eb.custom_minimum_size = Vector2(0, 44)
	return card


## Servidor público: entra no endereço configurado (todos os jogadores caem no mesmo mundo).
## Sem endereço configurado, abre o servidor localmente (modo de teste/anfitrião).
func _play_server(sd: Dictionary) -> void:
	var ad: Array = WorldStore.server_address(String(sd["id"]))
	if String(ad[0]) != "":
		main.join_server(String(ad[0]), int(ad[1]))
		return
	toast("Sem endereço público (servers.cfg): abrindo em modo local.")
	main.start_world_meta(WorldStore.server_meta(String(sd["id"])))


func _tab_servers() -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 340)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(sc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(hb)
	for sd in WorldStore.SERVERS:
		hb.add_child(_server_card(sd))
	_btn("Entrar por IP (amigos)", _page_ip)


func _server_card(sd: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var banner := TextureRect.new()
	banner.texture = _gradient_tex(sd["color"])
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	banner.custom_minimum_size = Vector2(0, 120)
	vb.add_child(banner)
	_load_image(String(sd["banner"]), String(sd["id"]) + "_banner", banner)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var logo := TextureRect.new()
	logo.texture = _gradient_tex(sd["color"])
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	logo.custom_minimum_size = Vector2(56, 56)
	head.add_child(logo)
	_load_image(String(sd["logo"]), String(sd["id"]) + "_logo", logo)
	var nm := Label.new()
	nm.text = String(sd["name"])
	nm.add_theme_font_size_override("font_size", 26)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nm)
	var d := _label(String(sd["desc"]), vb)
	d.add_theme_font_size_override("font_size", 16)
	d.modulate = Color(1, 1, 1, 0.75)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	var pb := _btn("Jogar", func(): _play_server(sd), row)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_admin := Settings.is_admin_name(Settings.player_name)
	var eb := _btn("Editar", func(): _page_edit(WorldStore.server_meta(String(sd["id"]))), row)
	eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eb.disabled = not is_admin
	eb.tooltip_text = "Só o administrador (%s) pode editar." % Settings.ADMIN_NICK
	if not is_admin:
		var hint := _label("Edição só para o admin (%s)." % Settings.ADMIN_NICK, vb)
		hint.add_theme_font_size_override("font_size", 13)
		hint.modulate = Color(1, 1, 1, 0.5)
	return card


func _page_ip() -> void:
	_back = _page_play
	_begin("ip", BG, 560.0)
	_title("Entrar por IP", 34)
	var name_e := LineEdit.new()
	name_e.text = Settings.player_name
	_row("Seu nome", name_e)
	var ip_e := LineEdit.new()
	ip_e.text = Settings.last_ip
	_row("IP", ip_e)
	var jport := LineEdit.new()
	jport.text = str(main.PORT)
	_row("Porta", jport)
	_btn("Entrar", func():
		var n := name_e.text.strip_edges()
		if n != "":
			Settings.player_name = n.substr(0, 16)
		Settings.last_ip = ip_e.text.strip_edges()
		Settings.save_settings()
		main.join_server(Settings.last_ip, int(jport.text)))
	_btn("Voltar", _page_play)


# ================================================================ criar mundo
func _rule_checks(parent: Node, rules: Dictionary, boxes: Dictionary) -> void:
	for r in WorldStore.RULE_LABELS:
		var cb := CheckBox.new()
		cb.text = String(r[1])
		cb.button_pressed = bool(rules.get(r[0], false))
		parent.add_child(cb)
		boxes[r[0]] = cb


func _page_new_world() -> void:
	_back = _page_play
	_begin("new", BG, 620.0)
	_title("Criar novo mundo", 34)
	var name_e := LineEdit.new()
	name_e.text = "Novo mundo"
	_row("Nome", name_e)
	var mode := OptionButton.new()
	mode.add_item("Sobrevivência")
	mode.add_item("Criativo")
	_row("Modo", mode)
	var tmpl := OptionButton.new()
	tmpl.add_item("Normal")
	tmpl.add_item("Plano")
	_row("Modelo de mundo", tmpl)
	var seed_e := LineEdit.new()
	seed_e.placeholder_text = "vazio = aleatória"
	_row("Semente", seed_e)
	_label("Regras do mundo:")
	var boxes: Dictionary = {}
	_rule_checks(_page, WorldStore.default_rules(), boxes)
	_btn("Criar mundo", func():
		var t := seed_e.text.strip_edges()
		var sv := 0
		if t != "":
			sv = int(t) if t.is_valid_int() else (t.hash() & 0x7fffffff)
		var rules: Dictionary = {}
		for k in boxes:
			rules[k] = (boxes[k] as CheckBox).button_pressed
		var nm := name_e.text.strip_edges()
		if nm == "":
			nm = "Novo mundo"
		var meta := WorldStore.create_world(nm.substr(0, 28), mode.selected == 1, "flat" if tmpl.selected == 1 else "normal", sv, rules)
		main.start_world_meta(meta))
	_btn("Voltar", _page_play)


# ================================================================ editar mundo / servidor
func _page_edit(meta: Dictionary) -> void:
	_back = _page_play
	var is_server := String(meta.get("kind", "world")) == "server"
	var can_edit := (not is_server) or Settings.is_admin_name(Settings.player_name)
	_begin("edit", BG, 620.0)
	_title("Editar servidor" if is_server else "Editar mundo", 34)
	if not can_edit:
		_label("Só o administrador (%s) pode configurar este servidor." % Settings.ADMIN_NICK)
		_btn("Voltar", _page_play)
		return
	var name_e := LineEdit.new()
	name_e.text = String(meta["name"])
	name_e.editable = not is_server
	_row("Nome", name_e)
	var tmpl := OptionButton.new()
	tmpl.add_item("Normal")
	tmpl.add_item("Plano")
	tmpl.selected = 1 if String(meta.get("template", "normal")) == "flat" else 0
	_row("Modelo de mundo", tmpl)
	_label("Trocar o modelo só afeta áreas ainda não exploradas. Para recomeçar do zero, apague o mundo.")
	var mode := OptionButton.new()
	mode.add_item("Sobrevivência")
	mode.add_item("Criativo")
	mode.selected = 1 if bool(meta.get("creative", false)) else 0
	_row("Modo", mode)
	var lan := CheckBox.new()
	lan.text = "Abrir para amigos na rede (porta %d)" % main.PORT
	lan.button_pressed = bool(meta.get("lan", false))
	if not is_server:
		_page.add_child(lan)
	_label("Regras:")
	var boxes: Dictionary = {}
	_rule_checks(_page, meta["rules"], boxes)
	var save := func():
		var rules: Dictionary = meta["rules"]
		for k in boxes:
			rules[k] = (boxes[k] as CheckBox).button_pressed
		if not is_server and name_e.text.strip_edges() != "":
			meta["name"] = name_e.text.strip_edges().substr(0, 28)
		meta["template"] = "flat" if tmpl.selected == 1 else "normal"
		meta["creative"] = mode.selected == 1
		meta["lan"] = lan.button_pressed
		WorldStore.save_meta(meta)
	_btn("Mods", func():
		save.call()
		_page_mods(meta))
	_btn("Salvar e voltar", func():
		save.call()
		toast("Salvo!")
		_page_play())
	var del := Button.new()
	del.text = "Reiniciar mapa do servidor" if is_server else "Apagar mundo"
	del.custom_minimum_size = Vector2(0, 52)
	del.modulate = Color(1, 0.6, 0.6)
	var armed := [false]
	del.pressed.connect(func():
		if not armed[0]:
			armed[0] = true
			del.text = "Toque de novo para confirmar"
			return
		if is_server:
			WorldStore.delete_data(String(meta["id"]))
			toast("Mapa do servidor reiniciado.")
		else:
			WorldStore.delete_world(String(meta["id"]))
			toast("Mundo apagado.")
		_page_play())
	_page.add_child(del)
	_btn("Voltar sem salvar", _page_play)


# ================================================================ mods do mundo
func _page_mods(meta: Dictionary) -> void:
	_back = func(): _page_edit(meta)
	_begin("mods", BG, 760.0)
	_title("Mods — %s" % String(meta["name"]), 32)
	var entries: Array = meta["mods"]
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 320)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	if entries.is_empty():
		_label("Nenhum mod instalado. Toque em \"Importar mod\" para adicionar um arquivo .stc.", list)
	for i in entries.size():
		var e: Dictionary = entries[i]
		list.add_child(_mod_card(meta, entries, i, e))
	_btn("Importar mod (.stc)", func(): _page_import(meta))
	_btn("Voltar", func(): _page_edit(meta))


func _mod_card(meta: Dictionary, entries: Array, idx: int, e: Dictionary) -> Control:
	var path := WorldStore.mods_dir(String(meta["id"])) + "/" + String(e["file"])
	var info := Mods.inspect(path)
	var card := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	card.add_child(hb)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if bool(info["ok"]) and info["icon"] != null:
		icon.texture = info["icon"]
	else:
		icon.texture = _gradient_tex(Color(0.5, 0.4, 0.8))
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var nm := Label.new()
	var enabled := bool(e.get("enabled", true))
	if bool(info["ok"]):
		nm.text = "%s  v%s" % [info["name"], info["version"]]
	else:
		nm.text = String(e["file"]) + "  (arquivo inválido)"
	nm.add_theme_font_size_override("font_size", 22)
	vb.add_child(nm)
	var ds := Label.new()
	if bool(info["ok"]):
		var c: Dictionary = info["counts"]
		ds.text = "%s\nitens %d • blocos %d • entidades %d • receitas %d • scripts %d" % [info["description"], c["item"], c["bloco"], c["entidade"], c["receitas"], c["script"]]
	else:
		ds.text = String(info["error"])
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.add_theme_font_size_override("font_size", 14)
	ds.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(ds)
	var col := VBoxContainer.new()
	hb.add_child(col)
	var tb := Button.new()
	tb.text = "Desativar" if enabled else "Ativar"
	tb.custom_minimum_size = Vector2(130, 44)
	tb.pressed.connect(func():
		e["enabled"] = not enabled
		WorldStore.save_meta(meta)
		_page_mods(meta))
	col.add_child(tb)
	var db := Button.new()
	db.text = "Apagar"
	db.custom_minimum_size = Vector2(130, 44)
	db.modulate = Color(1, 0.6, 0.6)
	db.pressed.connect(func():
		DirAccess.remove_absolute(path)
		entries.remove_at(idx)
		WorldStore.save_meta(meta)
		toast("Mod apagado.")
		_page_mods(meta))
	col.add_child(db)
	if not enabled:
		card.modulate = Color(1, 1, 1, 0.6)
	return card


func _import_dirs() -> Array:
	var out: Array = ["user://mods_inbox"]
	var dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dl != "":
		out.append(dl)
	out.append("/storage/emulated/0/Download")
	out.append("/storage/emulated/0/Cubolandia")
	out.append("/storage/emulated/0/Cubolandia/mods")
	out.append(OS.get_executable_path().get_base_dir())
	return out


func _page_import(meta: Dictionary) -> void:
	_back = func(): _page_mods(meta)
	_begin("mods_import", BG, 700.0)
	_title("Importar mod", 32)
	DirAccess.make_dir_recursive_absolute("user://mods_inbox")
	_label("Arquivos .stc encontrados (Downloads e pasta de mods). Você também pode colocar o arquivo em: %s" % ProjectSettings.globalize_path("user://mods_inbox"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 240)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var found := 0
	var seen: Dictionary = {}
	for dir in _import_dirs():
		var d := DirAccess.open(String(dir))
		if d == null:
			continue
		for f in d.get_files():
			if not String(f).to_lower().ends_with(".stc"):
				continue
			var full := String(dir) + "/" + String(f)
			if seen.has(full):
				continue
			seen[full] = true
			found += 1
			_btn(String(f), func(): _do_import(meta, full), list)
	if found == 0:
		_label("Nenhum .stc encontrado nessas pastas.", list)
	_btn("Procurar arquivo...", func(): _browse_mod(meta))
	_btn("Voltar", func(): _page_mods(meta))


func _browse_mod(meta: Dictionary) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.stc ; Mods do Cubolândia", "*.zip ; Pacote ZIP"])
	fd.title = "Escolha o mod (.stc)"
	fd.set("use_native_dialog", true)
	fd.file_selected.connect(func(p: String):
		fd.queue_free()
		_do_import(meta, p))
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered_ratio(0.85)


func _do_import(meta: Dictionary, path: String) -> void:
	var r: Dictionary = Mods.import_to_world(String(meta["id"]), path)
	if not bool(r["ok"]):
		toast(String(r["error"]))
		return
	var entries: Array = meta["mods"]
	entries.append({"file": r["file"], "enabled": true})
	WorldStore.save_meta(meta)
	toast("Mod \"%s\" importado!" % String(r["info"]["name"]))
	_page_mods(meta)


# ================================================================ pausa
func show_pause(online: bool, is_host: bool) -> void:
	_back = Callable()
	_begin("pause", Color(0, 0, 0, 0.55), 520.0)
	_title("Pausado", 40)
	if not main.world_meta.is_empty():
		var wl := _label(String(main.world_meta["name"]))
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if online and is_host:
		_label("Aberto para amigos (porta %d)." % main.PORT)
	elif online:
		_label("Conectado a um servidor.")
	_btn("Continuar", func(): main.resume_game())
	_btn("Configurações", func():
		_settings_back = "pause"
		_page_settings())
	if not online or is_host:
		_btn("Salvar jogo", func():
			main.save_game()
			toast("Jogo salvo!"))
	_btn("Sair para o menu", func(): main.go_menu())


# ================================================================ configurações
func _page_settings() -> void:
	_back = func():
		Settings.save_settings()
		if _settings_back == "pause":
			show_pause(main.online, main.is_host)
		else:
			show_main()
	_begin("settings", BG if _settings_back == "main" else Color(0, 0, 0, 0.7), 720.0)
	_title("Opções", 34)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(680, 400)
	_page.add_child(tabs)
	_tab_general(_tab_box(tabs, "Geral"))
	_tab_keys(_tab_box(tabs, "Teclas"))
	_tab_touch(_tab_box(tabs, "Toque / HUD"))
	_btn("Voltar", func(): go_back())


func _tab_box(tabs: TabContainer, nm: String) -> VBoxContainer:
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
	_slider(vb, "Alcance total (chunks)", 4.0, 24.0, 1.0, Settings.render_distance, func(x): Settings.render_distance = int(x))
	_slider(vb, "Detalhe completo (chunks)", 2.0, 12.0, 1.0, Settings.detail_distance, func(x): Settings.detail_distance = int(x))
	var hint2 := Label.new()
	hint2.text = "Além do detalhe completo, o terreno aparece simplificado (baixa qualidade) até o alcance total."
	hint2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint2.add_theme_font_size_override("font_size", 14)
	vb.add_child(hint2)
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
	_slider(vb, "Tamanho geral dos botões", 0.6, 1.8, 0.05, Settings.touch_scale, func(x): Settings.touch_scale = x)
	_slider(vb, "Tamanho da barra (hotbar/vida)", 0.6, 1.6, 0.05, Settings.hud_scale, func(x): Settings.hud_scale = x)
	_slider(vb, "Margem da tela (se cortar)", 0.0, 80.0, 1.0, Settings.hud_margin, func(x): Settings.hud_margin = x)
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
