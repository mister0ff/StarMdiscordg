class_name StcExpr
extends RefCounted
## Avaliador de expressões seguro (sem acesso ao motor): números, textos, variáveis, and/or/not,
## comparações e funções liberadas. Palavras soltas (ex.: star:dirt) viram texto.

static var _cache: Dictionary = {}

var _t: Array = []
var _p := 0


static func eval(text: String, vars: Dictionary, funcs: Dictionary) -> Variant:
	var ast: Variant = _cache.get(text)
	if ast == null:
		var e := StcExpr.new()
		ast = e._parse_all(text)
		if ast == null:
			return null
		_cache[text] = ast
	return _ev(ast, vars, funcs)


static func truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		var s: String = v.to_lower()
		return s != "" and s != "false" and s != "0" and s != "nao"
	return true


static func _num(v: Variant) -> float:
	if v is bool:
		return 1.0 if v else 0.0
	if v is int or v is float:
		return float(v)
	if v is String and v.is_valid_float():
		return float(v)
	return 0.0


static func _eq(a: Variant, b: Variant) -> bool:
	var an := a is int or a is float
	var bn := b is int or b is float
	if an and bn:
		return is_equal_approx(float(a), float(b))
	if a is bool or b is bool:
		return truthy(a) == truthy(b)
	return str(a).to_lower() == str(b).to_lower()


static func _ev(n: Array, vars: Dictionary, funcs: Dictionary) -> Variant:
	match n[0]:
		"num", "str":
			return n[1]
		"id":
			var name: String = n[1]
			if vars.has(name):
				return vars[name]
			match name.to_lower():
				"true":
					return true
				"false":
					return false
				"null":
					return null
			return name
		"call":
			var args: Array = []
			for a in n[2]:
				args.append(_ev(a, vars, funcs))
			var fname: String = String(n[1]).to_lower()
			if funcs.has(fname):
				return (funcs[fname] as Callable).call(args)
			return null
		"not":
			return not truthy(_ev(n[1], vars, funcs))
		"neg":
			return -_num(_ev(n[1], vars, funcs))
		"bin":
			var op: String = n[1]
			if op == "and":
				return truthy(_ev(n[2], vars, funcs)) and truthy(_ev(n[3], vars, funcs))
			if op == "or":
				return truthy(_ev(n[2], vars, funcs)) or truthy(_ev(n[3], vars, funcs))
			var a: Variant = _ev(n[2], vars, funcs)
			var b: Variant = _ev(n[3], vars, funcs)
			match op:
				"==":
					return _eq(a, b)
				"!=":
					return not _eq(a, b)
				"<":
					return _num(a) < _num(b)
				">":
					return _num(a) > _num(b)
				"<=":
					return _num(a) <= _num(b)
				">=":
					return _num(a) >= _num(b)
				"+":
					if a is String or b is String:
						return Util.fmt_num(a) + Util.fmt_num(b)
					return _num(a) + _num(b)
				"-":
					return _num(a) - _num(b)
				"*":
					return _num(a) * _num(b)
				"/":
					var d := _num(b)
					return _num(a) / d if d != 0.0 else 0.0
				"%":
					var m := _num(b)
					return fmod(_num(a), m) if m != 0.0 else 0.0
	return null


# ------------------------------------------------------------ parser
func _parse_all(text: String) -> Variant:
	_t = _tokens(text)
	_p = 0
	if _t.is_empty():
		return null
	var n: Variant = _or()
	return n


func _tokens(s: String) -> Array:
	var out: Array = []
	var i := 0
	var L := s.length()
	while i < L:
		var ch := s[i]
		if ch == " " or ch == "\t":
			i += 1
		elif ch == "\"" or ch == "'":
			var q := ch
			var j := i + 1
			var buf := ""
			while j < L and s[j] != q:
				buf += s[j]
				j += 1
			out.append(["str", buf])
			i = j + 1
		elif (ch >= "0" and ch <= "9") or (ch == "." and i + 1 < L and s[i + 1] >= "0" and s[i + 1] <= "9"):
			var j2 := i
			while j2 < L and ((s[j2] >= "0" and s[j2] <= "9") or s[j2] == "."):
				j2 += 1
			out.append(["num", float(s.substr(i, j2 - i))])
			i = j2
		elif (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_" or ch == "@" or ch == "$":
			var j3 := i
			while j3 < L and ((s[j3] >= "a" and s[j3] <= "z") or (s[j3] >= "A" and s[j3] <= "Z") \
				or (s[j3] >= "0" and s[j3] <= "9") or s[j3] in ["_", ":", ".", "@", "$"]):
				j3 += 1
			var w := s.substr(i, j3 - i)
			var lw := w.to_lower()
			if lw == "and" or lw == "or" or lw == "not":
				out.append(["op", lw])
			else:
				out.append(["id", w])
			i = j3
		else:
			var two := s.substr(i, 2)
			if two in ["==", "!=", "<=", ">=", "&&", "||"]:
				out.append(["op", "and" if two == "&&" else ("or" if two == "||" else two)])
				i += 2
			elif ch in ["<", ">", "+", "-", "*", "/", "%"]:
				out.append(["op", ch])
				i += 1
			elif ch == "!":
				out.append(["op", "not"])
				i += 1
			elif ch == "(":
				out.append(["lp", ch])
				i += 1
			elif ch == ")":
				out.append(["rp", ch])
				i += 1
			elif ch == ",":
				out.append(["comma", ch])
				i += 1
			else:
				i += 1
	return out


func _peek_op(ops: Array) -> String:
	if _p < _t.size() and _t[_p][0] == "op" and _t[_p][1] in ops:
		return _t[_p][1]
	return ""


func _or() -> Array:
	var a := _and()
	while _peek_op(["or"]) != "":
		_p += 1
		a = ["bin", "or", a, _and()]
	return a


func _and() -> Array:
	var a := _cmp()
	while _peek_op(["and"]) != "":
		_p += 1
		a = ["bin", "and", a, _cmp()]
	return a


func _cmp() -> Array:
	var a := _add()
	var op := _peek_op(["==", "!=", "<", ">", "<=", ">="])
	while op != "":
		_p += 1
		a = ["bin", op, a, _add()]
		op = _peek_op(["==", "!=", "<", ">", "<=", ">="])
	return a


func _add() -> Array:
	var a := _mul()
	var op := _peek_op(["+", "-"])
	while op != "":
		_p += 1
		a = ["bin", op, a, _mul()]
		op = _peek_op(["+", "-"])
	return a


func _mul() -> Array:
	var a := _unary()
	var op := _peek_op(["*", "/", "%"])
	while op != "":
		_p += 1
		a = ["bin", op, a, _unary()]
		op = _peek_op(["*", "/", "%"])
	return a


func _unary() -> Array:
	if _peek_op(["not"]) != "":
		_p += 1
		return ["not", _unary()]
	if _peek_op(["-"]) != "":
		_p += 1
		return ["neg", _unary()]
	return _primary()


func _primary() -> Array:
	if _p >= _t.size():
		return ["num", 0.0]
	var tk: Array = _t[_p]
	_p += 1
	match tk[0]:
		"num", "str":
			return [tk[0], tk[1]]
		"lp":
			var e := _or()
			if _p < _t.size() and _t[_p][0] == "rp":
				_p += 1
			return e
		"id":
			if _p < _t.size() and _t[_p][0] == "lp":
				_p += 1
				var args: Array = []
				while _p < _t.size() and _t[_p][0] != "rp":
					args.append(_or())
					if _p < _t.size() and _t[_p][0] == "comma":
						_p += 1
				if _p < _t.size():
					_p += 1
				return ["call", tk[1], args]
			return ["id", tk[1]]
	return ["num", 0.0]
