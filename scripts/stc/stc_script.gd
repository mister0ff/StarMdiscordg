class_name StcScript
extends RefCounted
## Interpretador de scripts dos mods. Estrutura de um arquivo:
##
##   player-spawn                 <- nome do evento (ou  "evento: player-spawn")
##   run: title @s title "Bem-vindo"
##   if: item == star:dirt and sneaking
##   run: say agachado com terra
##   elseif: health < 5
##   run: heal @s
##   else:
##   run: say nada
##   end:
##
##   comando: curar               <- cria o comando  /curar
##   run: heal @s
##
## Instruções: run, if / elseif / else / end, set, wait, repeat, cancel.

const RESERVED := ["run", "executar", "if", "se", "elseif", "senaose", "else", "senao", "end", "fim", "set",
	"definir", "wait", "esperar", "cancel", "cancelar", "repeat", "repetir", "evento", "event", "on",
	"comando", "command"]

static var _re_head: RegEx


## Retorna {"events": {nome: [stmts,...]}, "commands": {nome: {"stmts": [...], "desc": ""}}}
static func parse(text: String) -> Dictionary:
	if _re_head == null:
		_re_head = RegEx.create_from_string("^[a-z][a-z0-9_\\-]*$")
	var events: Dictionary = {}
	var commands: Dictionary = {}
	var cur: Array = []
	var stack: Array = []
	var root: Array = []
	var started := false
	for raw in text.replace("\r", "").split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with("//"):
			continue
		var key := ""
		var val := ""
		var ci := line.find(":")
		var first_word := line.split(" ", false)[0].to_lower()
		if ci > 0 and not line.substr(0, ci).contains(" "):
			key = Util.strip_accents(line.substr(0, ci))
			val = line.substr(ci + 1).strip_edges()
		else:
			key = Util.strip_accents(first_word)
			val = line.substr(first_word.length()).strip_edges()
		# cabeçalhos
		var header := ""
		var header_kind := ""
		if key in ["evento", "event", "on"]:
			header = _norm_event(StcDoc.clean(val))
			header_kind = "event"
		elif key in ["comando", "command"]:
			header = StcDoc.clean(val).split(" ", false)[0].to_lower() if StcDoc.clean(val) != "" else ""
			header_kind = "command"
		elif not (key in RESERVED) and ci < 0 and _re_head.search(line.to_lower()) != null:
			header = _norm_event(line)
			header_kind = "event"
		if header != "":
			stack.clear()
			root = []
			cur = root
			started = true
			if header_kind == "event":
				if not events.has(header):
					events[header] = []
				events[header].append(root)
			else:
				var desc := StcDoc.clean(val).substr(header.length()).strip_edges()
				commands[header] = {"stmts": root, "desc": StcDoc.clean(desc)}
			continue
		if not started:
			continue
		match key:
			"run", "executar":
				cur.append({"t": "run", "v": StcDoc.clean(val)})
			"set", "definir":
				var eq := val.find("=")
				if eq > 0:
					cur.append({"t": "set", "name": val.substr(0, eq).strip_edges(), "expr": val.substr(eq + 1).strip_edges()})
			"wait", "esperar":
				cur.append({"t": "wait", "expr": val})
			"cancel", "cancelar":
				cur.append({"t": "cancel"})
			"if", "se":
				var node := {"t": "if", "branches": []}
				var body: Array = []
				node["branches"].append({"cond": val, "body": body})
				cur.append(node)
				stack.append({"node": node, "parent": cur})
				cur = body
			"elseif", "senaose":
				if not stack.is_empty():
					var body2: Array = []
					stack[-1]["node"]["branches"].append({"cond": val, "body": body2})
					cur = body2
			"else", "senao":
				if not stack.is_empty():
					var body3: Array = []
					stack[-1]["node"]["branches"].append({"cond": "", "body": body3})
					cur = body3
			"repeat", "repetir":
				var rn := {"t": "repeat", "expr": val, "body": []}
				cur.append(rn)
				stack.append({"node": rn, "parent": cur})
				cur = rn["body"]
			"end", "fim":
				if not stack.is_empty():
					cur = stack[-1]["parent"]
					stack.pop_back()
	return {"events": events, "commands": commands}


static func _norm_event(s: String) -> String:
	return s.strip_edges().to_lower().replace("_", "-")
