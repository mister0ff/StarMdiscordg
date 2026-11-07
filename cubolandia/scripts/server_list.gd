class_name ServerList
## Lista de servidores públicos. Depois de hospedar o seu (veja SERVER.md), coloque o endereço aqui.
## addr: "ip:porta" (UDP/ENet) ou "ws://host:porta" / "wss://host" (WebSocket).
## REMOTE_URL (opcional): um JSON publicado na internet, ex.: raw.githubusercontent.com/.../servers.json
## com o formato [{"name": "Meu servidor", "addr": "1.2.3.4:25565", "desc": "Survival 24h"}]
## assim você atualiza a lista sem recompilar o jogo.

const REMOTE_URL := ""

const SERVERS := [
	{"name": "Local (teste neste PC)", "addr": "127.0.0.1:25565", "desc": "Servidor dedicado rodando na sua máquina"},
]
