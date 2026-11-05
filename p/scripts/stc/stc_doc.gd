class_name StcDoc
extends RefCounted
## Leitor dos arquivos de configuração .txt/.cmd dos mods (formato STC: "chave: valor").
## Aceita vírgulas no fim, várias chaves na mesma linha, aspas, listas [a, b] e comentários (# no começo da linha ou //).

var pairs: Array = []      # [chave_normalizada, valor_bruto] na ordem do arquivo
var map: Dictionary = {}   # chave_normalizada -> valor_bruto (último vence)
var grid: Array = []       # linhas de receita: [[a,b,c], ...]

const NO_SPLIT := ["run", "executar", "if", "se", "elseif", "set", "wait", "ao_usar", "ao_bater", "ao_comer",
	"ao_quebrar", "ao_colocar", "ao_clicar", "ao_morrer", "drop", "parte", "part", "caixa"]

static var _re_next_key: RegEx
static var _re_key_colon: RegEx
static var _re_key_space: RegEx
static var _re_grid: RegEx


static func _init_re() -> void:
	if _re_next_key != null:
		return
	_re_next_key = RegEx.create_from_string("^\\s*[\\p{L}_][\\p{L}\\p{N}_\\-]*\\s*:")
	_re_key_colon = RegEx.create_from_string("^([\\p{L}_][\\p{L}\\p{N}_\\-]*)\\s*:\\s*(.*)$")
	_re_key_space = RegEx.create_from_string("^([\\p{L}_][\\p{L}\\p{N}_\\-]*)\\s+(\\S.*)$")
	_re_grid = RegEx.create_from_string("^(\\[[^\\]]*\\]\\s*){3}$")


static func norm_key(k: String) -> String:
	return Util.strip_accents(k.strip_edges()).replace("-", "_")


func _init(text: String = "") -> void:
	_init_re()
	if text != "":
		parse(text)


func parse(text: String) -> void:
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	for raw in text.replace("\r", "").split("\n"):
		var line := _strip_comment(raw).strip_edges()
		if line == "":
			continue
		if _re_grid.search(line) != null:
			grid.append(_grid_cells(line))
			continue
		for seg in _split_pairs(line):
			var kv := _split_kv(seg)
			if kv[0] == "":
				continue
			pairs.append(kv)
			map[kv[0]] = kv[1]


static func _grid_cells(line: String) -> Array:
	var out: Array = []
	var cur := ""
	var inside := false
	for ch in line:
		if ch == "[":
			inside = true
			cur = ""
		elif ch == "]":
			inside = false
			out.append(cur.strip_edges())
		elif inside:
			cur += ch
	return out


static func _strip_comment(line: String) -> String:
	var t := line.strip_edges()
	if t.begins_with("#"):
		return ""
	var inq := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			inq = not inq
		elif not inq and ch == "/" and i + 1 < line.length() and line[i + 1] == "/" and (i == 0 or line[i - 1] != ":"):
			return line.substr(0, i)
	return line


func _split_pairs(line: String) -> Array:
	var first := _split_kv(line)
	if first[0] in NO_SPLIT:
		return [line]
	var out: Array = []
	var cur := ""
	var inq := false
	var depth := 0
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			inq = not inq
		elif not inq:
			if ch == "[" or ch == "(" or ch == "{":
				depth += 1
			elif ch == "]" or ch == ")" or ch == "}":
				depth -= 1
			elif ch == "," and depth <= 0:
				var rest := line.substr(i + 1)
				if _re_next_key.search(rest) != null:
					out.append(cur)
					cur = ""
					continue
		cur += ch
	if cur.strip_edges() != "":
		out.append(cur)
	return out


static func _split_kv(seg: String) -> Array:
	seg = seg.strip_edges()
	var m := _re_key_colon.search(seg)
	if m != null:
		return [norm_key(m.get_string(1)), m.get_string(2).strip_edges()]
	m = _re_key_space.search(seg)
	if m != null:
		return [norm_key(m.get_string(1)), m.get_string(2).strip_edges()]
	return [norm_key(seg.trim_suffix(",")), ""]


static func clean(v: String) -> String:
	v = v.strip_edges()
	while v.ends_with(","):
		v = v.substr(0, v.length() - 1).strip_edges()
	if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
		var inner := v.substr(1, v.length() - 2)
		if inner.count("\"") % 2 == 1:
			inner += "\""
		return inner
	if v.begins_with("\"") and v.count("\"") == 1:
		return v.substr(1)
	if v.length() >= 2 and v.begins_with("'") and v.ends_with("'"):
		return v.substr(1, v.length() - 2)
	return v


static func split_list(raw: String) -> Array:
	var t := raw.strip_edges()
	if t.begins_with("[") and t.ends_with("]"):
		t = t.substr(1, t.length() - 2)
	var out: Array = []
	var cur := ""
	var inq := false
	for ch in t:
		if ch == "\"":
			inq = not inq
			cur += ch
		elif ch == "," and not inq:
			out.append(clean(cur))
			cur = ""
		else:
			cur += ch
	if cur.strip_edges() != "":
		out.append(clean(cur))
	return out


func has_any(names: Array) -> bool:
	for n in names:
		if map.has(n):
			return true
	return false


func raw(names: Array, default := "") -> String:
	for n in names:
		if map.has(n):
			return map[n]
	return default


func text(names: Array, default := "") -> String:
	for n in names:
		if map.has(n):
			return clean(map[n])
	return default


func num(names: Array, default := 0.0) -> float:
	var s := text(names, "")
	if s == "":
		return default
	return float(s) if s.is_valid_float() else default


func flag(names: Array, default := false) -> bool:
	var s := text(names, "").to_lower()
	if s == "":
		return default
	return s in ["true", "sim", "yes", "1", "verdadeiro", "ativado", "on"]


func list(names: Array) -> Array:
	for n in names:
		if map.has(n):
			return split_list(map[n])
	return []


func all(names: Array) -> Array:
	var out: Array = []
	for p in pairs:
		if p[0] in names:
			out.append(clean(p[1]))
	return out


func vec3(names: Array, default: Vector3) -> Vector3:
	var s := text(names, "").replace(",", " ")
	var parts: PackedStringArray = s.split(" ", false)
	if parts.size() < 3:
		return default
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func vec2(names: Array, default: Vector2) -> Vector2:
	var s := text(names, "").replace(",", " ")
	var parts: PackedStringArray = s.split(" ", false)
	if parts.size() < 2:
		return default
	return Vector2(float(parts[0]), float(parts[1]))
