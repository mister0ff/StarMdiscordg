class_name WorldStore
extends RefCounted
## Mundos e servidores salvos em user://worlds/<id>/ (meta.dat, data.dat, mods/*.stc).

const ROOT := "user://worlds"
const LEGACY := "user://save.dat"

# Servidores fixos (cada um tem seu próprio mundo salvo, mods e regras)
const SERVERS := [
	{
		"id": "server_starcat", "name": "Starcat Mc", "port": 25565,
		"desc": "Servidor oficial da Starcat. Sobrevivência com comandos.",
		"banner": "https://cdn.discordapp.com/attachments/1494815130582651030/1567665980279361637/c96d5540c36c85b35f12f90a7e73faf4.jpg?ex=6aed0237&is=6aebb0b7&hm=85a3ff621e1a98c2ca1d228a629d9fbd5040fab9fad929e9a09e9b9b756e7390&",
		"logo": "https://cdn.discordapp.com/attachments/1494815130582651030/1567665954274545714/file_00000000d230820ebc400062b8fd3b48.png?ex=6aed0231&is=6aebb0b1&hm=915b7a5d15e5e65708709caeb1356c32e0ea0546651d704840db8165b3d4419b&",
		"color": Color(0.85, 0.2, 0.25),
	},
	{
		"id": "server_auralis", "name": "Auralis Net", "port": 25566,
		"desc": "Rede Auralis. Mundo aberto para explorar e construir.",
		"banner": "https://cdn.discordapp.com/attachments/1494815130582651030/1567588489673842750/e39dd536393448737f19074de5038ad0.jpg?ex=6aecba0c&is=6aeb688c&hm=495c1f323641db008a627b838908d2bcd473b9860151464aec262ab0bbe5988c&",
		"logo": "https://cdn.discordapp.com/attachments/1494815130582651030/1567588485529862155/0625c7c102d161152393729090910699.jpg?ex=6aecba0b&is=6aeb688b&hm=0fbcd83d93fe119bed2f5e17f9dc9d7c5fb6e38de17ef9e8899d3278e32f0b31&",
		"color": Color(0.25, 0.55, 0.95),
	},
]

# [chave, rótulo]
const RULE_LABELS := [
	["commands", "Comandos"],
	["always_day", "Sempre dia"],
	["mobs", "Spawn de Mobs"],
	["pvp", "PvP"],
	["keep_inventory", "Manter inventário ao morrer"],
	["explosions", "Explosões quebram blocos"],
]


static func default_rules() -> Dictionary:
	return {"commands": true, "always_day": false, "mobs": true, "pvp": true, "keep_inventory": false, "explosions": true}


static func ensure_root() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)


static func dir_of(id: String) -> String:
	return ROOT + "/" + id


static func mods_dir(id: String) -> String:
	return dir_of(id) + "/mods"


## [endereço, porta] do servidor público. Vazio = ainda não configurado.
## Edite res://servers.cfg (ou user://servers.cfg) com o IP/domínio da máquina que roda o servidor.
static func server_address(sid: String) -> Array:
	var def := server_def(sid)
	var addr := String(def.get("address", ""))
	var port := int(def.get("port", 25565))
	for path in ["res://servers.cfg", "user://servers.cfg"]:
		var cf := ConfigFile.new()
		if cf.load(path) == OK and cf.has_section(sid):
			addr = String(cf.get_value(sid, "address", addr))
			port = int(cf.get_value(sid, "port", port))
	return [addr.strip_edges(), port]


static func server_def(sid: String) -> Dictionary:
	for s in SERVERS:
		if s["id"] == sid:
			return s
	return {}


# ------------------------------------------------------------ metadados
static func load_meta(id: String) -> Dictionary:
	var f := FileAccess.open(dir_of(id) + "/meta.dat", FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var(false)
	f.close()
	if d is Dictionary and d.has("id"):
		var m: Dictionary = d
		# completa campos que faltarem (saves antigos)
		var rules: Dictionary = default_rules()
		var cur: Dictionary = m.get("rules", {})
		for k in cur:
			rules[k] = cur[k]
		m["rules"] = rules
		if not m.has("mods"):
			m["mods"] = []
		if not m.has("idmap"):
			m["idmap"] = {}
		return m
	return {}


static func save_meta(meta: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir_of(String(meta["id"])))
	var f := FileAccess.open(dir_of(String(meta["id"])) + "/meta.dat", FileAccess.WRITE)
	if f != null:
		f.store_var(meta, false)
		f.close()


static func new_meta(id: String, kind: String, nm: String, creative: bool, template: String, seed_val: int) -> Dictionary:
	return {
		"id": id, "kind": kind, "name": nm, "creative": creative, "template": template,
		"seed": seed_val, "rules": default_rules(), "mods": [], "idmap": {},
		"created": int(Time.get_unix_time_from_system()), "played": 0,
	}


static func create_world(nm: String, creative: bool, template: String, seed_val: int, rules: Dictionary) -> Dictionary:
	ensure_root()
	var id := "w%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	if seed_val == 0:
		seed_val = randi() % 1000000 + 1
	var m := new_meta(id, "world", nm, creative, template, seed_val)
	m["rules"] = rules
	DirAccess.make_dir_recursive_absolute(mods_dir(id))
	save_meta(m)
	return m


## Meta do servidor (cria na primeira vez).
static func server_meta(sid: String) -> Dictionary:
	ensure_root()
	var m := load_meta(sid)
	if not m.is_empty():
		return m
	var sd := server_def(sid)
	if sd.is_empty():
		return {}
	m = new_meta(sid, "server", String(sd["name"]), false, "normal", 0)
	m["seed"] = String(sd["name"]).hash() & 0x7fffff
	if int(m["seed"]) == 0:
		m["seed"] = 4242
	m["port"] = int(sd["port"])
	DirAccess.make_dir_recursive_absolute(mods_dir(sid))
	save_meta(m)
	return m


static func list_worlds() -> Array:
	ensure_root()
	migrate_legacy()
	var out: Array = []
	var d := DirAccess.open(ROOT)
	if d == null:
		return out
	for sub in d.get_directories():
		var m := load_meta(sub)
		if not m.is_empty() and m.get("kind", "world") == "world":
			out.append(m)
	out.sort_custom(func(a, b): return int(a.get("played", 0)) > int(b.get("played", 0)))
	return out


## Apaga só o mapa salvo (mantém configurações e mods). Usado para reiniciar servidores.
static func delete_data(id: String) -> void:
	DirAccess.remove_absolute(dir_of(id) + "/data.dat")


static func delete_world(id: String) -> void:
	_rm_rf(dir_of(id))


static func _rm_rf(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path + "/" + f)
	for sub in d.get_directories():
		_rm_rf(path + "/" + sub)
	DirAccess.remove_absolute(path)


# ------------------------------------------------------------ dados do mundo
static func has_data(id: String) -> bool:
	return FileAccess.file_exists(dir_of(id) + "/data.dat")


static func read_data(id: String) -> Dictionary:
	var f := FileAccess.open(dir_of(id) + "/data.dat", FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var(false)
	f.close()
	if d is Dictionary and d.has("seed") and d.has("edits"):
		return d
	return {}


static func write_data(id: String, d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir_of(id))
	var f := FileAccess.open(dir_of(id) + "/data.dat", FileAccess.WRITE)
	if f != null:
		f.store_var(d, false)
		f.close()


## Importa o save antigo (user://save.dat) como um mundo, uma única vez.
static func migrate_legacy() -> void:
	if not FileAccess.file_exists(LEGACY):
		return
	var f := FileAccess.open(LEGACY, FileAccess.READ)
	if f == null:
		return
	var d = f.get_var(false)
	f.close()
	if d is Dictionary and d.has("seed") and d.has("edits"):
		var data: Dictionary = d
		var m := create_world("Mundo salvo", bool(data.get("creative", false)), "normal", int(data["seed"]), default_rules())
		var r: Dictionary = m["rules"]
		r["mobs"] = bool(data.get("mobs", true))
		save_meta(m)
		write_data(String(m["id"]), data)
	DirAccess.rename_absolute(LEGACY, "user://save_migrado.dat")


# ------------------------------------------------------------ miniatura procedural
static func make_thumb(meta: Dictionary, w := 160, h := 90) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sd: int = int(meta.get("seed", 1))
	var flat := String(meta.get("template", "normal")) == "flat"
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var ph1 := rng.randf() * 6.0
	var ph2 := rng.randf() * 6.0
	var tint := rng.randf() * 0.12
	for y in h:
		var t := float(y) / float(h)
		var sky := Color(0.35 + tint, 0.62, 0.95).lerp(Color(0.75, 0.88, 1.0), t)
		for x in w:
			img.set_pixel(x, y, sky)
	for x in w:
		var fx := float(x) / float(w)
		var top: int
		if flat:
			top = int(h * 0.62)
		else:
			top = int(h * (0.5 + 0.14 * sin(fx * 7.0 + ph1) + 0.08 * sin(fx * 15.0 + ph2)))
		for y in range(maxi(top, 0), h):
			var depth := y - top
			var c := Color(0.3, 0.62, 0.22)
			if depth > 2 and depth <= 14:
				c = Color(0.47, 0.33, 0.2)
			elif depth > 14:
				c = Color(0.5, 0.5, 0.52)
			if (x / 4 + y / 4) % 2 == 0:
				c = c.darkened(0.06)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
