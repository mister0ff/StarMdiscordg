extends Control
## Tela de partida: confere se os scripts carregam. Se algum falhar, mostra qual (em vez de tela cinza).

const SCRIPTS := [
	"res://scripts/util.gd", "res://scripts/inventory.gd", "res://scripts/world.gd", "res://scripts/fx.gd",
	"res://scripts/item_drop.gd", "res://scripts/arrow.gd", "res://scripts/remote_player.gd", "res://scripts/mob.gd",
	"res://scripts/player.gd", "res://scripts/ui/hud.gd", "res://scripts/ui/touch_controls.gd",
	"res://scripts/ui/inventory_ui.gd", "res://scripts/ui/chat_ui.gd", "res://scripts/ui/menu.gd",
	"res://scripts/main.gd",
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bad: Array = []
	for p in SCRIPTS:
		var sc = load(p)
		if sc == null or (sc is GDScript and not sc.can_instantiate()):
			bad.append(p)
	if bad.is_empty():
		var packed: PackedScene = load("res://scenes/main.tscn")
		call_deferred("_go", packed)
		return
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.03, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var l := Label.new()
	l.text = "ERRO: estes scripts não carregaram:\n\n" + "\n".join(PackedStringArray(bad)) + "\n\nMande esta lista (e o log do Godot) para corrigir."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", 26)
	add_child(l)


func _go(packed: PackedScene) -> void:
	get_tree().change_scene_to_packed(packed)
