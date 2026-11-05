class_name ServerDefs
extends RefCounted
## Servidores fixos do menu (mundos persistentes com banner/logo). Apenas o admin pode gerenciar.

const ADMIN_NICK := "X EDUHH X"

const SERVERS := [
	{
		"id": "srv_starcat", "name": "Starcat Mc", "seed": 20260101, "type": "normal", "creative": false,
		"desc": "Sobrevivência • Spawn de mobs • PvP",
		"banner_file": "starcat_banner.jpg", "logo_file": "starcat_logo.png",
		"banner_url": "https://cdn.discordapp.com/attachments/1494815130582651030/1567665980279361637/c96d5540c36c85b35f12f90a7e73faf4.jpg?ex=6aed0237&is=6aebb0b7&hm=85a3ff621e1a98c2ca1d228a629d9fbd5040fab9fad929e9a09e9b9b756e7390&",
		"logo_url": "https://cdn.discordapp.com/attachments/1494815130582651030/1567665954274545714/file_00000000d230820ebc400062b8fd3b48.png?ex=6aed0231&is=6aebb0b1&hm=915b7a5d15e5e65708709caeb1356c32e0ea0546651d704840db8165b3d4419b&",
		"color": Color(0.55, 0.25, 0.85),
	},
	{
		"id": "srv_auralis", "name": "Auralis Net", "seed": 777001, "type": "normal", "creative": false,
		"desc": "Sobrevivência • Comunidade",
		"banner_file": "auralis_banner.jpg", "logo_file": "auralis_logo.jpg",
		"banner_url": "https://cdn.discordapp.com/attachments/1494815130582651030/1567588489673842750/e39dd536393448737f19074de5038ad0.jpg?ex=6aecba0c&is=6aeb688c&hm=495c1f323641db008a627b838908d2bcd473b9860151464aec262ab0bbe5988c&",
		"logo_url": "https://cdn.discordapp.com/attachments/1494815130582651030/1567588485529862155/0625c7c102d161152393729090910699.jpg?ex=6aecba0b&is=6aeb688b&hm=0fbcd83d93fe119bed2f5e17f9dc9d7c5fb6e38de17ef9e8899d3278e32f0b31&",
		"color": Color(0.2, 0.6, 0.9),
	},
]


static func is_admin_nick(nick: String) -> bool:
	return nick.strip_edges().to_upper() == ADMIN_NICK


static func by_id(id: String) -> Dictionary:
	for s in SERVERS:
		if s["id"] == id:
			return s
	return {}
