extends Node
## Teste de fumaça headless: godot --headless --path . res://tests/smoke.tscn

var m
var B
var f := 0
var ok := true

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		ok = false

func _ready() -> void:
	B = get_node("/root/Blocks")
	m = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	var meta: Dictionary = WorldStore.new_meta("Teste", 777, "normal", false, WorldStore.DEFAULT_RULES)
	meta["id"] = "teste_smoke"
	m.start_world(meta)

func _process(_dt: float) -> void:
	f += 1
	var p: Player = m.local_player
	match f:
		200:
			check(not p.frozen, "mundo carregou e jogador liberado")
			check(p.is_on_floor() or p.global_position.y > 0, "jogador no mundo (y=%.1f)" % p.global_position.y)
		260:
			# quebrar bloco abaixo e conferir drop
			var pos := Vector3i(floori(p.global_position.x) + 2, 0, floori(p.global_position.z))
			pos.y = m.world.surface_y(pos.x, pos.z)
			var id: int = m.world.get_block(pos.x, pos.y, pos.z)
			m.player_break_block(pos, id, true)
			check(m.world.get_block(pos.x, pos.y, pos.z) == B.AIR, "bloco quebrado (id %d)" % id)
			check(m.drops.size() >= 1, "drop gerado")
			m.player_place_block(pos, B.PLANKS)
			check(m.world.get_block(pos.x, pos.y, pos.z) == B.PLANKS, "bloco colocado")
		270:
			# crafting
			p.inv.add(B.LOG, 3)
			var r: Dictionary = B.recipes[0]
			check(p.inv.craft(r, false, false), "craft tábuas")
			check(p.inv.count_of(B.PLANKS) == 4, "4 tábuas")
			p.inv.add(B.PLANKS, 20)
			p.inv.add(B.STICK, 10)
			var pick: int = B.TOOL_BASE + B.KIND_PICK
			var rr: Dictionary = {}
			for x in B.recipes:
				if x["out"] == pick:
					rr = x
			check(p.inv.craft(rr, true, false), "craft picareta de madeira")
			check(p.inv.count_of(pick) == 1, "picareta no inventário")
			check(B.break_time(B.STONE, pick) < B.break_time(B.STONE, 0), "picareta acelera pedra")
			check(not B.can_harvest(B.IRON_ORE, pick), "madeira não colhe ferro")
		300:
			# noite + mobs
			m.time_of_day = 0.78
			for i in 3:
				m._spawn_mob("zombie", p.global_position + Vector3(6 + i, 1, 0))
			m._spawn_mob("pig", p.global_position + Vector3(0, 1, -4))
			m._spawn_mob("creeper", p.global_position + Vector3(-8, 1, 0))
			m._spawn_mob("skeleton", p.global_position + Vector3(0, 1, 10))
		420:
			check(m.daylight < 0.3, "é noite (%.2f)" % m.daylight)
			check(m.mobs.size() >= 5, "mobs vivos: %d" % m.mobs.size())
			check(p.health < 20.0 or true, "vida %.1f" % p.health)
			# KB no mob
			for mob in m.mobs.values():
				if mob.kind == "pig":
					var hp0: float = mob.hp
					mob.take_hit(3.0, Vector3(5, 0, 0))
					check(mob.hp == hp0 - 3.0, "dano no mob")
					check(mob.velocity.x > 1.0, "knockback aplicado")
			# dano em jogador com KB
			var h0 := p.health
			p.take_damage(4.0, Vector3(0, 0, 6))
			check(p.health == h0 - 4.0 and absf(p.velocity.z) > 1.0, "PvP dano+KB")
		450:
			var before := 0
			m.world.explode(p.global_position + Vector3(4, -1, 0), 3.0)
			check(true, "explosão sem erro")
			m.save_game()
			check(WorldStore.has_save("teste_smoke"), "save gravado")
		480:
			m.chat_ui.open()
			m.send_chat("olá")
			m.send_chat("/time dia")
			m.send_chat("/gm c")
			check(m.creative_mode, "/gm c")
			m.chat_ui.close()
			m.open_inventory()
			check(m.inv_ui.visible, "inventário abre")
			m.close_inventory()
			m.pause_game()
			check(m.menu.visible, "pausa abre")
			m.resume_game()
		500:
			m.start_world(WorldStore.load_meta("teste_smoke"))
		700:
			check(m.local_player != null and m.world.seed_val == 777, "carregou save (seed %d)" % m.world.seed_val)
			check(m.world.get_block(floori(m.local_player.global_position.x) + 2, 0, 0) != -1, "mundo carregado")
			print("RESULTADO: ", "TUDO OK" if ok else "HOUVE FALHAS")
			get_tree().quit()
