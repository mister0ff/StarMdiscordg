class_name ScriptEngine
extends RefCounted
## Linguagem de script dos mods (.stc → pasta script/*.txt).
## Compila o texto em uma lista de instruções e executa com variáveis de contexto.
## Condições e contas usam a classe Expression do Godot (and/or/not, ==, <, +, ...).

const MAX_STEPS := 5000

const EVENT_ALIASES := {
	"jogador-entrou": "player-spawn", "entrou": "player-spawn", "ao-entrar": "player-spawn",
	"renascer": "player-respawn", "ao-renascer": "player-respawn",
	"morrer": "player-die", "ao-morrer": "player-die", "jogador-morreu": "player-die",
	"antes-de-bater": "before-hit", "antes-bater": "before-hit",
	"ao-bater": "after-hit", "depois-de-bater": "after-hit",
	"ao-usar": "item-use", "usar": "item-use", "antes-de-usar": "before-use",
	"antes-de-quebrar": "before-break", "ao-quebrar": "after-break",
	"antes-de-colocar": "before-place", "ao-colocar": "after-place",
	"mob-morreu": "entity-die", "entidade-morreu": "entity-die",
	"mensagem": "chat", "chat-mensagem": "chat",
	"a-cada-segundo": "tick",
}

const KEY_ALIASES := {
	"executar": "run", "cmd": "run", "comando-run": "run",
	"if": "se", "elif": "senao-se", "else-if": "senao-se", "else": "senao", "end": "fim", "fimse": "fim",
	"cancel": "cancelar", "stop": "parar", "return": "parar", "retornar": "parar",
	"definir": "set", "wait": "esperar", "repeat": "repetir", "print": "log", "event": "evento",
	"command": "comando", "perm": "permissao", "usage": "uso",
}


## Remove acentos, deixa minúsculo e troca "_" por "-".
static func norm(s: String) -> String:
	var t := s.strip_edges().to_lower()
	var pairs := [["ã", "a"], ["á", "a"], ["â", "a"], ["à", "a"], ["é", "e"], ["ê", "e"], ["í", "i"],
		["ó", "o"], ["ô", "o"], ["õ", "o"], ["ú", "u"], ["ç", "c"]]
	for p in pairs:
		t = t.replace(String(p[0]), String(p[1]))
	return t.replace("_", "-")


## Tira vírgula final e aspas externas.
static func clean(v: String) -> String:
	var t := v.strip_edges()
	while t.ends_with(","):
		t = t.substr(0, t.length() - 1).strip_edges()
	if t.length() >= 2 and ((t.begins_with("\"") and t.ends_with("\"")) or (t.begins_with("'") and t.ends_with("'"))):
		t = t.substr(1, t.length() - 2)
	return t


static func _is_ident_start(c: String) -> bool:
	var u := c.unicode_at(0)
	return (u >= 97 and u <= 122) or (u >= 65 and u <= 90) or u == 95 or u > 127


static func _is_ident_char(c: String) -> bool:
	var u := c.unicode_at(0)
	return _is_ident_start(c) or (u >= 48 and u <= 57)


## Converte "e/ou/nao/sim" para and/or/not/true e coloca aspas em ids como star:dirt.
static func translate(src: String) -> String:
	var out := ""
	var i := 0
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == "\"" or c == "'":
			var j := i + 1
			while j < n and src[j] != c:
				j += 1
			out += src.substr(i, j - i + 1)
			i = j + 1
			continue
		if _is_ident_start(c):
			var j2 := i
			while j2 < n and _is_ident_char(src[j2]):
				j2 += 1
			if j2 + 1 < n and src[j2] == ":" and _is_ident_start(src[j2 + 1]):
				var k := j2 + 1
				while k < n and _is_ident_char(src[k]):
					k += 1
				out += "\"" + src.substr(i, k - i).to_lower() + "\""
				i = k
				continue
			var word := src.substr(i, j2 - i)
			match word.to_lower():
				"e":
					out += " and "
				"ou":
					out += " or "
				"nao", "não":
					out += " not "
				"sim", "verdadeiro":
					out += "true"
				"falso":
					out += "false"
				_:
					out += word
			i = j2
			continue
		out += c
		i += 1
	return out


static func evaluate(expr: String, ctx: Dictionary, globals: Dictionary) -> Variant:
	var merged: Dictionary = globals.duplicate()
	for k in ctx:
		merged[k] = ctx[k]
	var names := PackedStringArray()
	var vals: Array = []
	for k in merged:
		names.append(String(k))
		vals.append(merged[k])
	var ex := Expression.new()
	if ex.parse(translate(expr), names) != OK:
		return null
	var res = ex.execute(vals, null, false)
	if ex.has_execute_failed():
		return null
	return res


static func interpolate(text: String, ctx: Dictionary, globals: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var re := RegEx.new()
	re.compile("\\{([^{}]+)\\}")
	var out := ""
	var last := 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		var v = evaluate(m.get_string(1), ctx, globals)
		if v != null:
			out += str(v)
		last = m.get_end()
	out += text.substr(last)
	return out


# ------------------------------------------------------------ compilação
## Retorna {"handlers": [{event, prog}], "commands": [{name, usage, perm, prog}], "errors": [String]}
static func compile(text: String, mod_name: String) -> Dictionary:
	var handlers: Array = []
	var commands: Array = []
	var errors: Array = []
	var cur: Dictionary = {}
	var lines := text.split("\n")
	for n in lines.size():
		var raw := lines[n].strip_edges()
		if raw.is_empty() or raw.begins_with("#") or raw.begins_with("//"):
			continue
		var key := ""
		var val := ""
		var ci := raw.find(":")
		if ci > 0:
			key = norm(raw.substr(0, ci))
			val = raw.substr(ci + 1).strip_edges()
		else:
			key = norm(raw)
		key = key.replace(" ", "-")
		if KEY_ALIASES.has(key):
			key = String(KEY_ALIASES[key])
		var where := "%s linha %d" % [mod_name, n + 1]
		match key:
			"evento":
				_finish(cur, handlers, commands, errors, where)
				var ev := norm(clean(val))
				if EVENT_ALIASES.has(ev):
					ev = String(EVENT_ALIASES[ev])
				cur = {"kind": "event", "name": ev, "prog": [], "frames": []}
			"comando":
				_finish(cur, handlers, commands, errors, where)
				var cn := clean(val).to_lower().lstrip("/")
				cur = {"kind": "command", "name": cn, "prog": [], "frames": [], "usage": "/" + cn, "perm": "todos"}
			"uso":
				if not cur.is_empty():
					cur["usage"] = clean(val)
			"permissao":
				if not cur.is_empty():
					cur["perm"] = norm(clean(val))
			_:
				if cur.is_empty():
					errors.append("%s: instrução fora de um bloco 'evento:' ou 'comando:'" % where)
					continue
				_instruction(cur, key, val, errors, where)
	_finish(cur, handlers, commands, errors, "%s (fim do arquivo)" % mod_name)
	return {"handlers": handlers, "commands": commands, "errors": errors}


static func _instruction(cur: Dictionary, key: String, val: String, errors: Array, where: String) -> void:
	var prog: Array = cur["prog"]
	var frames: Array = cur["frames"]
	match key:
		"run":
			var t := val.strip_edges()
			while t.ends_with(","):
				t = t.substr(0, t.length() - 1).strip_edges()
			if t.length() >= 2 and t.begins_with("\"") and t.ends_with("\""):
				t = t.substr(1, t.length() - 2)
			elif t.begins_with("\""):
				t = t.substr(1)
			prog.append({"op": "run", "text": t.lstrip("/")})
		"log":
			prog.append({"op": "run", "text": "say " + clean(val)})
		"se":
			prog.append({"op": "if", "expr": clean(val), "else": -1})
			frames.append({"type": "if", "if_idx": prog.size() - 1, "jumps": []})
		"senao-se":
			if frames.is_empty() or frames[frames.size() - 1]["type"] != "if" or int(frames[frames.size() - 1]["if_idx"]) < 0:
				errors.append("%s: 'senao-se' sem 'se'" % where)
				return
			var fr: Dictionary = frames[frames.size() - 1]
			prog.append({"op": "jump", "to": -1})
			var fr_jumps: Array = fr["jumps"]
			fr_jumps.append(prog.size() - 1)
			var old_if: Dictionary = prog[int(fr["if_idx"])]
			old_if["else"] = prog.size()
			prog.append({"op": "if", "expr": clean(val), "else": -1})
			fr["if_idx"] = prog.size() - 1
		"senao":
			if frames.is_empty() or frames[frames.size() - 1]["type"] != "if" or int(frames[frames.size() - 1]["if_idx"]) < 0:
				errors.append("%s: 'senao' sem 'se'" % where)
				return
			var fr2: Dictionary = frames[frames.size() - 1]
			prog.append({"op": "jump", "to": -1})
			var fr2_jumps: Array = fr2["jumps"]
			fr2_jumps.append(prog.size() - 1)
			var old_if2: Dictionary = prog[int(fr2["if_idx"])]
			old_if2["else"] = prog.size()
			fr2["if_idx"] = -1
		"repetir":
			prog.append({"op": "loop", "expr": clean(val), "end": -1})
			frames.append({"type": "loop", "begin": prog.size() - 1})
		"fim":
			if frames.is_empty():
				errors.append("%s: 'fim' sem 'se' ou 'repetir'" % where)
				return
			var top: Dictionary = frames.pop_back()
			_close_frame(prog, top)
		"cancelar":
			prog.append({"op": "cancel"})
		"parar":
			prog.append({"op": "stop"})
		"esperar":
			prog.append({"op": "wait", "expr": clean(val)})
		"set":
			var eq := val.find("=")
			if eq <= 0:
				errors.append("%s: use 'set: nome = valor'" % where)
				return
			var nm := val.substr(0, eq).strip_edges()
			var ok := nm.length() > 0 and _is_ident_start(nm)
			for ch in nm:
				if not _is_ident_char(ch):
					ok = false
			if not ok:
				errors.append("%s: nome de variável inválido '%s'" % [where, nm])
				return
			prog.append({"op": "set", "name": nm, "expr": clean(val.substr(eq + 1))})
		_:
			errors.append("%s: instrução desconhecida '%s'" % [where, key])


static func _close_frame(prog: Array, top: Dictionary) -> void:
	if top["type"] == "loop":
		prog.append({"op": "loop_end", "begin": int(top["begin"])})
		var lp: Dictionary = prog[int(top["begin"])]
		lp["end"] = prog.size()
	else:
		if int(top["if_idx"]) >= 0:
			var ifd: Dictionary = prog[int(top["if_idx"])]
			ifd["else"] = prog.size()
		var jl: Array = top["jumps"]
		for j in jl:
			var jd: Dictionary = prog[int(j)]
			jd["to"] = prog.size()


static func _finish(cur: Dictionary, handlers: Array, commands: Array, errors: Array, where: String) -> void:
	if cur.is_empty():
		return
	var frames: Array = cur["frames"]
	var prog: Array = cur["prog"]
	if not frames.is_empty():
		errors.append("%s: faltou 'fim' (fechado automaticamente)" % where)
		while not frames.is_empty():
			var top2: Dictionary = frames.pop_back()
			_close_frame(prog, top2)
	if String(cur["name"]).is_empty():
		errors.append("%s: bloco sem nome" % where)
		return
	if cur["kind"] == "event":
		handlers.append({"event": cur["name"], "prog": prog})
	else:
		commands.append({"name": cur["name"], "usage": cur.get("usage", ""), "perm": cur.get("perm", "todos"), "prog": prog})


# ------------------------------------------------------------ execução
## host: nó com .globals (Dictionary), .exec_command(texto, ctx) e .schedule(...)
## state: {"cancel": bool, "counters": {}} (reutilizado entre esperas)
static func run(host: Node, prog: Array, ctx: Dictionary, state: Dictionary, start_pc: int) -> Dictionary:
	var globals: Dictionary = host.globals
	var pc := start_pc
	var steps := 0
	while pc >= 0 and pc < prog.size():
		steps += 1
		if steps > MAX_STEPS:
			host.warn("Script interrompido: passos demais (loop infinito?)")
			break
		var ins: Dictionary = prog[pc]
		match String(ins["op"]):
			"run":
				host.exec_command(interpolate(String(ins["text"]), ctx, globals), ctx)
				pc += 1
			"if":
				if bool(evaluate(String(ins["expr"]), ctx, globals)):
					pc += 1
				else:
					pc = int(ins["else"])
			"jump":
				pc = int(ins["to"])
			"set":
				globals[String(ins["name"])] = evaluate(String(ins["expr"]), ctx, globals)
				pc += 1
			"cancel":
				state["cancel"] = true
				pc += 1
			"stop":
				break
			"wait":
				var secs := 0.0
				var sv = evaluate(String(ins["expr"]), ctx, globals)
				if sv != null:
					secs = clampf(float(sv), 0.0, 3600.0)
				host.schedule(secs, prog, ctx, state, pc + 1)
				break
			"loop":
				var cnt: Dictionary = state["counters"]
				if not cnt.has(pc):
					var cv = evaluate(String(ins["expr"]), ctx, globals)
					var total := 0
					if cv != null:
						total = clampi(int(cv), 0, 500)
					cnt[pc] = {"left": total, "i": 0}
				var c: Dictionary = cnt[pc]
				if int(c["left"]) <= 0:
					cnt.erase(pc)
					pc = int(ins["end"])
				else:
					c["left"] = int(c["left"]) - 1
					ctx["i"] = int(c["i"])
					c["i"] = int(c["i"]) + 1
					pc += 1
			"loop_end":
				pc = int(ins["begin"])
			_:
				pc += 1
	return state
