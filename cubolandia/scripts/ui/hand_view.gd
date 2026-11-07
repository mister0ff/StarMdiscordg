extends Control
## Mão/braço em primeira pessoa, desenhado num SubViewport por cima do mundo (não atravessa paredes).

var main: Node
var _vp: SubViewport
var _cam: Camera3D
var _tex: TextureRect
var _pivot: Node3D
var _arm: MeshInstance3D
var _item: Node3D
var _item_mesh: MeshInstance3D
var _item_id := -1
var _t := 0.0
var _equip := 1.0
var _swing_prev := 0.0
var _swing_anim := 0.0
var _mat_skin: StandardMaterial3D
var _mat_sleeve: StandardMaterial3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.03
	_cam.far = 10.0
	_vp.add_child(_cam)
	_cam.current = true
	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)
	_pivot = Node3D.new()
	_cam.add_child(_pivot)
	_mat_skin = _mk_mat(Color(0.86, 0.66, 0.5))
	_mat_sleeve = _mk_mat(Color(0.25, 0.55, 0.8))
	_arm = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 0.9)
	_arm.mesh = bm
	_arm.material_override = _mat_skin
	_arm.position = Vector3(0, 0, -0.45)
	_pivot.add_child(_arm)
	var sl := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.215, 0.215, 0.5)
	sl.mesh = sm
	sl.material_override = _mat_sleeve
	sl.position = Vector3(0, 0, 0.2)
	_arm.add_child(sl)
	_item = Node3D.new()
	_item.position = Vector3(0, 0.12, -0.8)
	_arm.add_child(_item)
	_item_mesh = MeshInstance3D.new()
	_item.add_child(_item_mesh)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	visible = false


func _mk_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _on_resize() -> void:
	var s := get_viewport().get_visible_rect().size
	if s.x > 16 and s.y > 16:
		_vp.size = Vector2i(int(s.x), int(s.y))


func _set_item(id: int) -> void:
	_item_id = id
	_equip = 1.0
	if id == 0:
		_item_mesh.mesh = null
		return
	if Blocks.is_block(id):
		_item_mesh.mesh = Blocks.block_cube_mesh(id, 0.34)
		_item_mesh.material_override = main.world.mat_solid
		_item_mesh.rotation_degrees = Vector3(10, 40, 0)
		_item_mesh.position = Vector3(0, 0.1, 0)
	else:
		_item_mesh.mesh = Blocks.item_mesh(id, 0.62, 0.08)
		_item_mesh.material_override = null
		_item_mesh.rotation_degrees = Vector3(0, -50, -15)
		_item_mesh.position = Vector3(0, 0.18, 0)


func _process(delta: float) -> void:
	var p: Player = main.local_player
	var show: bool = main.playing and p != null and not p.dead and not p.ui_open and Settings.show_hand
	visible = show
	if not show:
		return
	_cam.fov = 70.0
	_t += delta
	var id := p.held_id()
	if id != _item_id:
		_set_item(id)
	_equip = maxf(0.0, _equip - delta * 4.0)
	# balanço ao andar
	var spd := Vector2(p.velocity.x, p.velocity.z).length()
	var bob := 0.0
	if p.is_on_floor() and spd > 0.5:
		bob = sin(_t * 9.0) * 0.012 * clampf(spd / 4.3, 0.0, 1.5)
	# golpe: p._swing vai de 0.25 até 0
	var sw: float = p.swing_amount()
	var s := sin(sw * PI)
	var base := Vector3(0.52, -0.6 - _equip * 0.5, -0.28)
	_pivot.position = base + Vector3(-s * 0.1, bob - s * 0.05, -s * 0.12)
	_pivot.rotation_degrees = Vector3(20.0 + s * 38.0, 12.0 - s * 18.0, -4.0)
	var l := clampf(main.daylight, 0.45, 1.0)
	modulate = Color(l, l, l, 1.0)
	_mat_skin.albedo_color = Color(0.86, 0.66, 0.5)
	if _item_id != 0 and not Blocks.is_block(_item_id):
		_arm.visible = true
