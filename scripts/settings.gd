extends Node
## Autoload "Settings": teclas, controles de toque, opções gráficas. Salvo em user://settings.cfg

const SAVE_PATH := "user://settings.cfg"
const ADMIN_NICK := "X EDUHH X"

# [id, nome exibido]
const ACTIONS := [
	["forward", "Andar para frente"], ["back", "Andar para trás"],
	["left", "Esquerda"], ["right", "Direita"],
	["jump", "Pular / subir (voo)"], ["sneak", "Agachar / descer (voo)"],
	["sprint", "Correr"], ["attack", "Atacar / quebrar"],
	["place", "Colocar / usar"], ["inventory", "Inventário"],
	["chat", "Chat"], ["fly", "Alternar voo (criativo)"],
	["hotbar_prev", "Item anterior"], ["hotbar_next", "Próximo item"],
	["drop", "Largar item"], ["perspective", "Trocar perspectiva"],
]

const DEFAULT_KEYS := {
	"forward": {"t": "k", "c": KEY_W}, "back": {"t": "k", "c": KEY_S},
	"left": {"t": "k", "c": KEY_A}, "right": {"t": "k", "c": KEY_D},
	"jump": {"t": "k", "c": KEY_SPACE}, "sneak": {"t": "k", "c": KEY_SHIFT},
	"sprint": {"t": "k", "c": KEY_CTRL}, "attack": {"t": "m", "c": MOUSE_BUTTON_LEFT},
	"place": {"t": "m", "c": MOUSE_BUTTON_RIGHT}, "inventory": {"t": "k", "c": KEY_E},
	"chat": {"t": "k", "c": KEY_T}, "fly": {"t": "k", "c": KEY_F},
	"hotbar_prev": {"t": "m", "c": MOUSE_BUTTON_WHEEL_UP},
	"hotbar_next": {"t": "m", "c": MOUSE_BUTTON_WHEEL_DOWN},
	"drop": {"t": "k", "c": KEY_Q},
	"perspective": {"t": "k", "c": KEY_F5},
}

# Botões de toque: posição do centro (fração da tela) e escala
const DEFAULT_TOUCH := {
	"joystick": {"x": 0.13, "y": 0.72, "s": 1.0},
	"jump": {"x": 0.90, "y": 0.58, "s": 1.0},
	"attack": {"x": 0.80, "y": 0.76, "s": 1.1},
	"place": {"x": 0.91, "y": 0.80, "s": 1.0},
	"sneak": {"x": 0.28, "y": 0.86, "s": 0.8},
	"fly": {"x": 0.28, "y": 0.64, "s": 0.7},
	"inventory": {"x": 0.60, "y": 0.10, "s": 0.8},
	"chat": {"x": 0.68, "y": 0.10, "s": 0.7},
	"pause": {"x": 0.95, "y": 0.08, "s": 0.7},
	"view": {"x": 0.95, "y": 0.22, "s": 0.6},
	"hotbar_prev": {"x": 0.36, "y": 0.10, "s": 0.7},
	"hotbar_next": {"x": 0.44, "y": 0.10, "s": 0.7},
}

const TOUCH_LABELS := {
	"joystick": "Direcional", "jump": "Pular", "attack": "Atacar", "place": "Colocar",
	"sneak": "Agachar", "fly": "Voar", "inventory": "Inv", "chat": "Chat",
	"pause": "II", "view": "Cam", "hotbar_prev": "<", "hotbar_next": ">",
}

var keys: Dictionary = {}
var touch_layout: Dictionary = {}
var look_sens := 1.0
var touch_look_sens := 1.0
var render_distance := 24 # alcance total em chunks (terreno distante simplificado)
var detail_distance := 6 # chunks com detalhe completo (blocos, colisão)
var fov := 75.0
var touch_opacity := 0.6
var touch_scale := 1.0
var control_mode := "auto" # auto | touch | keyboard
var show_fps := false
var player_name := "Jogador"
var last_ip := "127.0.0.1"
var volume := 1.0
var hud_scale := 1.0
var hud_margin := 0.0


func _ready() -> void:
	keys = DEFAULT_KEYS.duplicate(true)
	touch_layout = DEFAULT_TOUCH.duplicate(true)
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		detail_distance = 4
	load_settings()
	apply_keys()


func use_touch() -> bool:
	match control_mode:
		"touch":
			return true
		"keyboard":
			return false
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") \
		or DisplayServer.is_touchscreen_available()


func make_event(d: Dictionary) -> InputEvent:
	if d.get("t", "k") == "m":
		var m := InputEventMouseButton.new()
		m.button_index = int(d["c"])
		return m
	var k := InputEventKey.new()
	k.physical_keycode = int(d["c"])
	return k


func apply_keys() -> void:
	for a in ACTIONS:
		var id: String = a[0]
		if InputMap.has_action(id):
			InputMap.action_erase_events(id)
		else:
			InputMap.add_action(id)
		var d: Dictionary = keys[id]
		# em modo toque, o mouse emulado não pode disparar atacar/colocar
		if d["t"] == "m" and use_touch() and int(d["c"]) <= MOUSE_BUTTON_MIDDLE:
			continue
		InputMap.action_add_event(id, make_event(d))


func set_key(action: String, ev: InputEvent) -> void:
	if ev is InputEventKey:
		keys[action] = {"t": "k", "c": ev.physical_keycode}
	elif ev is InputEventMouseButton:
		keys[action] = {"t": "m", "c": ev.button_index}
	else:
		return
	apply_keys()
	save_settings()


func key_name(action: String) -> String:
	var d: Dictionary = keys.get(action, {})
	if d.is_empty():
		return "-"
	if d["t"] == "m":
		match int(d["c"]):
			MOUSE_BUTTON_LEFT: return "Mouse Esq"
			MOUSE_BUTTON_RIGHT: return "Mouse Dir"
			MOUSE_BUTTON_MIDDLE: return "Mouse Meio"
			MOUSE_BUTTON_WHEEL_UP: return "Roda ↑"
			MOUSE_BUTTON_WHEEL_DOWN: return "Roda ↓"
		return "Mouse %d" % int(d["c"])
	return OS.get_keycode_string(int(d["c"]))


func reset_keys() -> void:
	keys = DEFAULT_KEYS.duplicate(true)
	apply_keys()
	save_settings()


func reset_touch() -> void:
	touch_layout = DEFAULT_TOUCH.duplicate(true)
	save_settings()


func save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("s", "keys", keys)
	c.set_value("s", "touch_layout", touch_layout)
	c.set_value("s", "look_sens", look_sens)
	c.set_value("s", "touch_look_sens", touch_look_sens)
	c.set_value("s", "far_distance", render_distance)
	c.set_value("s", "detail_distance", detail_distance)
	c.set_value("s", "fov", fov)
	c.set_value("s", "touch_opacity", touch_opacity)
	c.set_value("s", "touch_scale", touch_scale)
	c.set_value("s", "control_mode", control_mode)
	c.set_value("s", "show_fps", show_fps)
	c.set_value("s", "player_name", player_name)
	c.set_value("s", "last_ip", last_ip)
	c.set_value("s", "volume", volume)
	c.set_value("s", "hud_scale", hud_scale)
	c.set_value("s", "hud_margin", hud_margin)
	c.save(SAVE_PATH)


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	var k = c.get_value("s", "keys", {})
	if k is Dictionary:
		for id in k:
			if keys.has(id):
				keys[id] = k[id]
	var t = c.get_value("s", "touch_layout", {})
	if t is Dictionary:
		for id in t:
			if touch_layout.has(id):
				touch_layout[id] = t[id]
	look_sens = c.get_value("s", "look_sens", look_sens)
	touch_look_sens = c.get_value("s", "touch_look_sens", touch_look_sens)
	render_distance = clampi(int(c.get_value("s", "far_distance", render_distance)), 2, 24)
	detail_distance = clampi(int(c.get_value("s", "detail_distance", detail_distance)), 2, 12)
	fov = c.get_value("s", "fov", fov)
	touch_opacity = c.get_value("s", "touch_opacity", touch_opacity)
	touch_scale = c.get_value("s", "touch_scale", touch_scale)
	control_mode = c.get_value("s", "control_mode", control_mode)
	show_fps = c.get_value("s", "show_fps", show_fps)
	player_name = c.get_value("s", "player_name", player_name)
	last_ip = c.get_value("s", "last_ip", last_ip)
	volume = c.get_value("s", "volume", volume)
	hud_scale = c.get_value("s", "hud_scale", hud_scale)
	hud_margin = c.get_value("s", "hud_margin", hud_margin)


func is_admin_name(n: String) -> bool:
	return n.strip_edges() == ADMIN_NICK


func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


## Margens (em pixels do viewport) para não desenhar a HUD sob barras/recortes do aparelho.
func safe_margins(vp_size: Vector2) -> Rect2:
	var m := hud_margin
	var l := m
	var t := m
	var r := m
	var b := m
	if is_mobile():
		var win := Vector2(DisplayServer.window_get_size())
		var sa := DisplayServer.get_display_safe_area()
		if win.x > 1.0 and win.y > 1.0 and sa.size.x > 0 and sa.size.y > 0:
			var sx := vp_size.x / win.x
			var sy := vp_size.y / win.y
			l += maxf(0.0, float(sa.position.x) * sx)
			t += maxf(0.0, float(sa.position.y) * sy)
			r += maxf(0.0, (win.x - float(sa.end.x)) * sx)
			b += maxf(0.0, (win.y - float(sa.end.y)) * sy)
		b += 6.0
	return Rect2(l, t, r, b) # x=esq, y=topo, w=dir, h=baixo
