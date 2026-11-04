class_name Arrow
extends Node3D
## Flecha de esqueleto. Simulada em todos os pares; só machuca o jogador local.

var vel := Vector3.ZERO
var game: Node
var world: World
var _age := 0.0


func _ready() -> void:
	var m := Util.make_box(Vector3(0.06, 0.06, 0.6), Color(0.8, 0.75, 0.6))
	add_child(m)
	m.add_child(Util.make_box(Vector3(0.12, 0.12, 0.08), Color(0.9, 0.9, 0.9), Vector3(0, 0, 0.3)))


func _process(delta: float) -> void:
	_age += delta
	if _age > 8.0:
		queue_free()
		return
	vel.y -= 10.0 * delta
	var np := global_position + vel * delta
	if Blocks.is_solid(world.get_block(floori(np.x), floori(np.y), floori(np.z))):
		queue_free()
		return
	global_position = np
	if vel.length() > 0.1:
		look_at(global_position + vel, Vector3.UP)
	var pl: Player = game.local_player
	if pl != null and not pl.dead:
		var c := pl.global_position + Vector3(0, 0.9, 0)
		if absf(c.x - np.x) < 0.45 and absf(c.z - np.z) < 0.45 and absf(c.y - np.y) < 1.0:
			pl.take_damage(3.0, Vector3(vel.x, 0, vel.z).normalized() * 3.0)
			queue_free()
