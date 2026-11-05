class_name WorldStore
extends RefCounted
## Mundos e servidores salvos em disco: user://worlds/<id>/ e user://servers/<id>/
## Cada pasta tem: meta.txt (config), save.dat (blocos/jogador), thumb.png, mods/*.stc

const DEFAULT_RULES := {
	"always_day": false, "mob_spawning": true, "hostile_mobs": true, "commands": true,
	"keep_inventory": false, "fall_damage": true, "pvp": true, "hunger": true, "mob_griefing": true,
}
const RULE_LABELS := [
	["always_day", "Sempre dia"], ["mob_spawning", "Spawn de mobs"], ["hostile_mobs", "Mobs hostis"],
	["commands", "Comandos"], ["keep_inventory", "Manter inventário ao morrer"], ["fall_damage", "Dano de queda"],
	["pvp", "PvP"], ["hunger", "Fome"], ["mob_griefing", "Creeper destrói blocos"],
]


static func dir_of(id: String) -> String:
	return ("user://servers/" if id.begins_with("srv_") else "user://worlds/") + id


static func mods_dir(id: String) -> String:
	return dir_of(id) + "/mods"


static func save_path(id: String) -> String:
	return dir_of(id) + "/save.dat"


static func rules_of(meta: Dictionary) -> Dictionary:
	var r: Dictionary = DEFAULT_RULES.duplicate()
	var saved: Dictionary = meta.get("rules", {})
	for k in saved:
		r[k] = saved[k]
	return r


static func make_id(nm: String) -> String:
	var s := Util.slug(nm)
	if s == "":
		s = "mundo"
	return "%s_%d" % [s.substr(0, 20), Time.get_unix_time_from_system()]


static func new_meta(nm: String, seed_val: int, type: String, creative: bool, rules: Dictionary, kind := "world") -> Dictionary:
	if seed_val == 0:
		seed_val = randi() % 1000000 + 1
	return {
		"id": make_id(nm), "name": nm, "seed": seed_val, "type": type, "creative": creative,
		"rules": rules.duplicate(), "kind": kind, "created": int(Time.get_unix_time_from_system()),
		"idmap": {}, "mods": [],
	}


static func save_meta(meta: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir_of(meta["id"]))
	var f := FileAccess.open(dir_of(meta["id"]) + "/meta.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(var_to_str(meta))
		f.close()


static func load_meta(id: String) -> Dictionary:
	var path := dir_of(id) + "/meta.txt"
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = str_to_var(FileAccess.get_file_as_string(path))
	if d is Dictionary and d.has("id"):
		return d
	return {}


static func list_worlds() -> Array:
	migrate_legacy()
	var out: Array = []
	for d in DirAccess.get_directories_at("user://worlds"):
		var m := load_meta(d)
		if not m.is_empty():
			out.append(m)
	out.sort_custom(func(a, b): return int(a.get("created", 0)) > int(b.get("created", 0)))
	return out


static func ensure_server(def: Dictionary) -> Dictionary:
	var m := load_meta(def["id"])
	if m.is_empty():
		var rules := DEFAULT_RULES.duplicate()
		m = {
			"id": def["id"], "name": def["name"], "seed": def["seed"], "type": def["type"], "creative": def["creative"],
			"rules": rules, "kind": "server", "created": 0, "idmap": {}, "mods": [],
		}
		save_meta(m)
	return m


static func has_save(id: String) -> bool:
	return FileAccess.file_exists(save_path(id))


static func read_save(id: String) -> Dictionary:
	var f := FileAccess.open(save_path(id), FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = f.get_var(false)
	f.close()
	if d is Dictionary and d.has("edits"):
		return d
	return {}


static func write_save(id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir_of(id))
	var f := FileAccess.open(save_path(id), FileAccess.WRITE)
	if f != null:
		f.store_var(data, false)
		f.close()


static func wipe_save(id: String) -> void:
	if FileAccess.file_exists(save_path(id)):
		DirAccess.remove_absolute(save_path(id))
	if FileAccess.file_exists(dir_of(id) + "/thumb.png"):
		DirAccess.remove_absolute(dir_of(id) + "/thumb.png")


static func _rm_rf(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + f)
	for d in DirAccess.get_directories_at(path):
		_rm_rf(path + "/" + d)
	DirAccess.remove_absolute(path)


static func delete_world(id: String) -> void:
	_rm_rf(dir_of(id))


static func migrate_legacy() -> void:
	DirAccess.make_dir_recursive_absolute("user://worlds")
	if not FileAccess.file_exists("user://save.dat"):
		return
	var f := FileAccess.open("user://save.dat", FileAccess.READ)
	var d: Variant = f.get_var(false) if f != null else null
	if f != null:
		f.close()
	if d is Dictionary and d.has("seed") and d.has("edits"):
		var m := new_meta("Mundo salvo", int(d["seed"]), "normal", bool(d.get("creative", false)), DEFAULT_RULES)
		m["rules"]["mob_spawning"] = bool(d.get("mobs", true))
		save_meta(m)
		write_save(m["id"], d)
	DirAccess.rename_absolute("user://save.dat", "user://save.dat.migrado")


## Miniatura do mundo (gera e guarda em cache).
static func thumbnail(meta: Dictionary) -> Texture2D:
	var path := dir_of(meta["id"]) + "/thumb.png"
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			return ImageTexture.create_from_image(img)
	var w := World.new()
	w.setup(int(meta["seed"]), str(meta.get("type", "normal")))
	var im := w.preview_image(96, 240)
	w.free()
	DirAccess.make_dir_recursive_absolute(dir_of(meta["id"]))
	im.save_png(path)
	return ImageTexture.create_from_image(im)
