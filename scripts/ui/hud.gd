extends Control
## HUD: hotbar, vida, fome, ar, mira, flash de dano, tela de morte.

var main: Node
var _dmg: ColorRect
var _water: ColorRect
var _death: Control
var _hit_alpha := 0.0
var _font: Font
var _name_t := 0.0
var _last_id := -2
var _last_sel := -1
var _title := ""
var _subtitle := ""
var _title_t := 0.0
var _action := ""
var _action_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = ThemeDB.fallback_font
	_water = _overlay(Color(0.1, 0.3, 0.7, 0.35))
	_water.visible = false
	_dmg = _overlay(Color(1, 0, 0, 0))
	_death = Control.new()
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.visible = false
	add_child(_death)
	var bg := ColorRect.new()
	bg.color = Color(0.5, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	var l := Label.new()
	l.text = "Você morreu!"
	l.add_theme_font_size_override("font_size", 56)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var b1 := Button.new()
	b1.text = "Renascer"
	b1.custom_minimum_size = Vector2(300, 56)
	b1.add_theme_font_size_override("font_size", 24)
	b1.pressed.connect(func(): main.respawn())
	vb.add_child(b1)
	var b2 := Button.new()
	b2.text = "Menu principal"
	b2.custom_minimum_size = Vector2(300, 56)
	b2.add_theme_font_size_override("font_size", 24)
	b2.pressed.connect(func(): main.go_menu())
	vb.add_child(b2)
	visible = false


func _overlay(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func flash_damage() -> void:
	_hit_alpha = 0.45


func set_underwater(v: bool) -> void:
	_water.visible = v


func show_death() -> void:
	_death.visible = true


func hide_death() -> void:
	_death.visible = false


func show_title(t: String, sub: String) -> void:
	if t != "":
		_title = t
	if sub != "":
		_subtitle = sub
	_title_t = 4.0


func show_action(t: String) -> void:
	_action = t
	_action_t = 2.5


func clear_title() -> void:
	_title = ""
	_subtitle = ""
	_title_t = 0.0


func _process(delta: float) -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	if not visible:
		return
	_title_t = maxf(0.0, _title_t - delta)
	_action_t = maxf(0.0, _action_t - delta)
	_hit_alpha = maxf(0.0, _hit_alpha - delta * 1.2)
	_dmg.color.a = _hit_alpha
	_name_t = maxf(0.0, _name_t - delta)
	queue_redraw()


func _metrics() -> Array:
	var r := Util.safe_rect(get_viewport())
	var sc := Settings.hud_scale
	var sl := clampf(minf(r.size.x / 12.0, 52.0 * sc), 30.0, 70.0)
	var x0 := r.position.x + (r.size.x - sl * 9.0) * 0.5
	var y0 := r.end.y - sl - 10.0
	return [x0, y0, sl]


func hotbar_slot_at(pos: Vector2) -> int:
	var m := _metrics()
	var r := Rect2(m[0], m[1], m[2] * 9.0, m[2])
	if not r.has_point(pos):
		return -1
	return clampi(int((pos.x - m[0]) / m[2]), 0, 8)


func _draw() -> void:
	var p: Player = main.local_player
	if p == null:
		return
	var m := _metrics()
	var x0: float = m[0]
	var y0: float = m[1]
	var sl: float = m[2]
	if not p.ui_open and p.perspective != 2:
		var c := size * 0.5
		draw_rect(Rect2(c.x - 10, c.y - 2, 20, 4), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(c.x - 2, c.y - 10, 4, 20), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(c.x - 9, c.y - 1, 18, 2), Color(1, 1, 1, 0.95))
		draw_rect(Rect2(c.x - 1, c.y - 9, 2, 18), Color(1, 1, 1, 0.95))
	for i in 9:
		var r := Rect2(x0 + i * sl, y0, sl, sl)
		draw_rect(r, Color(0, 0, 0, 0.5))
		draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
		var id := p.inv.get_id(i)
		if id != 0:
			var tex := Blocks.icon(id)
			if tex != null:
				draw_texture_rect(tex, Rect2(r.position + Vector2(7, 7), Vector2(sl - 14, sl - 14)), false)
			var n := p.inv.get_count(i)
			if n > 1:
				draw_string(_font, Vector2(r.position.x, r.end.y - 5), str(n), HORIZONTAL_ALIGNMENT_RIGHT, sl - 4, 16, Color.WHITE)
			if Blocks.is_tool(id):
				var ratio := float(p.inv.slots[i][2]) / float(Blocks.max_dur(id))
				if ratio < 0.999:
					draw_rect(Rect2(r.position.x + 5, r.end.y - 6, (sl - 10), 3), Color(0, 0, 0, 0.8))
					draw_rect(Rect2(r.position.x + 5, r.end.y - 6, (sl - 10) * ratio, 3), Color(1.0 - ratio, ratio, 0.1))
	var sr := Rect2(x0 + p.selected * sl, y0, sl, sl)
	draw_rect(sr, Color(1, 1, 1, 0.95), false, 3.0)
	var sid := p.held_id()
	if sid != _last_id or p.selected != _last_sel:
		_last_id = sid
		_last_sel = p.selected
		_name_t = 2.0
	if _name_t > 0.0 and sid != 0:
		draw_string(_font, Vector2(0, y0 - 56), Blocks.name_of(sid), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, clampf(_name_t, 0.0, 1.0)))
	if not main.creative_mode:
		var hy := y0 - 24.0
		var hs := minf(sl * 0.36, 18.0)
		
		# Vida (Corações à esquerda)
		for i in 10:
			var rr := Rect2(x0 + i * (hs + 3), hy, hs, hs)
			draw_rect(rr, Color(0.2, 0, 0, 0.8))
			var hv := p.health / 2.0 - i
			if hv >= 1.0:
				draw_rect(rr.grow(-2), Color(0.9, 0.1, 0.12))
			elif hv > 0.0:
				draw_rect(Rect2(rr.position + Vector2(2, 2), Vector2((hs - 4) * 0.5, hs - 4)), Color(0.9, 0.1, 0.12))
				
		# Fome (À direita)
		for i in 10:
			var rr := Rect2(x0 + sl * 9.0 - (10 - i) * (hs + 3), hy, hs, hs)
			draw_rect(rr, Color(0.2, 0.1, 0, 0.8))
			var fv := p.hunger / 2.0 - i
			if fv >= 1.0:
				draw_rect(rr.grow(-2), Color(0.8, 0.5, 0.15))
			elif fv > 0.0:
				draw_rect(Rect2(rr.position + Vector2(hs - 2 - (hs - 4) * 0.5, 2), Vector2((hs - 4) * 0.5, hs - 4)), Color(0.8, 0.5, 0.15))
				
		if p.air < 9.9:
			var nb := int(ceil(p.air))
			for i in nb:
				draw_circle(Vector2(x0 + sl * 9.0 - (i + 1) * (hs + 3) + hs * 0.5 + 2, hy - hs), hs * 0.4, Color(0.6, 0.85, 1.0, 0.9))
				
	var sr := Util.safe_rect(get_viewport())
	if _title_t > 0.0:
		var a := clampf(_title_t, 0.0, 1.0)
		if _title != "":
			draw_string(_font, Vector2(sr.position.x, size.y * 0.32), _title, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 54, Color(1, 1, 1, a))
		if _subtitle != "":
			draw_string(_font, Vector2(sr.position.x, size.y * 0.32 + 40), _subtitle, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 28, Color(0.9, 0.9, 0.7, a))
	if _action_t > 0.0:
		draw_string(_font, Vector2(sr.position.x, y0 - 78), _action, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 22, Color(1, 1, 0.8, clampf(_action_t, 0.0, 1.0)))
	var info := ""
	if Settings.show_fps:
		var gp := p.global_position
		var hour := fposmod(main.time_of_day * 24.0 + 6.0, 24.0)
		info = "FPS %d  XYZ %.1f %.1f %.1f  %02d:%02d" % [Engine.get_frames_per_second(), gp.x, gp.y, gp.z, int(hour), int((hour - floor(hour)) * 60.0)]
	elif main.online:
		info = "Online"
	if info != "":
		draw_string(_font, Vector2(sr.position.x + 12, sr.position.y + 28), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	if p.flying:
		draw_string(_font, Vector2(sr.position.x + 12, sr.position.y + 52), "Voando", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.9, 1, 0.9))
