@tool
extends Node

static func extract_quoted_string(line: String) -> String:
	var first = line.find('"')
	if first == -1:
		return ""
	var second = line.find('"', first + 1)
	if second == -1:
		return ""
	return line.substr(first + 1, second - (first + 1))

static func extract_block_for_new_file(path: String, full_text: String) -> String:
	var re := RegEx.new()
	re.compile("```.*\\n# New file: " + path + "\\n([\\s\\S]*?)```")
	var m := re.search(full_text)
	if m:
		return m.get_string(1).strip_edges()
	return ""

static func parse_create_scene_args(line: String) -> Array:
	var trimmed = line.replace("create_scene(", "").replace(")", "").strip_edges()
	var parts: Array = []
	var i := 0
	while true:
		var a = trimmed.find('"', i)
		if a == -1:
			break
		var b = trimmed.find('"', a + 1)
		if b == -1:
			break
		parts.append(trimmed.substr(a + 1, b - a - 1))
		i = b + 1
	return parts

static func parse_create_node_args(line: String) -> Array:
	var body = line.replace("create_node(", "")
	var close_idx = body.rfind(")")
	if close_idx != -1:
		body = body.substr(0, close_idx)
	body = body.strip_edges()
	var brace_idx = body.find("{")
	if brace_idx != -1:
		body = body.substr(0, brace_idx).strip_edges()
	var out: Array = []
	var i := 0
	while true:
		var a = body.find('"', i)
		if a == -1:
			break
		var b = body.find('"', a + 1)
		if b == -1:
			break
		out.append(body.substr(a + 1, b - a - 1))
		i = b + 1
	return out

static func parse_object_map(text: String) -> Dictionary:
	var trimmed = text.strip_edges()
	if trimmed.begins_with("{"):
		trimmed = trimmed.substr(1, trimmed.length() - 1)
	if trimmed.ends_with("}"):
		trimmed = trimmed.substr(0, trimmed.length() - 1)
	trimmed = trimmed.strip_edges()
	var entries: Array = []
	var current := ""
	var paren := 0
	var bracket := 0
	var brace := 0
	var in_quotes := false
	for i in range(trimmed.length()):
		var ch: String = trimmed.substr(i, 1)
		if ch == '"':
			in_quotes = !in_quotes
		elif not in_quotes:
			if ch == "(":
				paren += 1
			elif ch == ")":
				paren -= 1
			elif ch == "[":
				bracket += 1
			elif ch == "]":
				bracket -= 1
			elif ch == "{":
				brace += 1
			elif ch == "}":
				brace -= 1
		if ch == "," and !in_quotes and paren == 0 and bracket == 0 and brace == 0:
			entries.append(current.strip_edges())
			current = ""
		else:
			current += ch
	if current != "":
		entries.append(current.strip_edges())
	var result := {}
	for entry in entries:
		var colon = entry.find(":")
		if colon == -1:
			continue
		var key = entry.substr(0, colon).strip_edges()
		var value = entry.substr(colon + 1).strip_edges()
		if key.begins_with('"') and key.ends_with('"') and key.length() >= 2:
			key = key.substr(1, key.length() - 2)
		# If value looks like array/object, try JSON-ish parse first
		if (value.begins_with("[") and value.find("]") != -1) or (value.begins_with("{") and value.find("}") != -1):
			var parsed = parse_jsonish(value)
			if parsed != null:
				result[key] = parsed
				continue
		# Unquote simple string values
		if value.begins_with('"') and value.ends_with('"') and value.length() >= 2:
			value = value.substr(1, value.length() - 2)
		result[key] = value
	return result

# --- Helpers added below ---
static func normalize_res_path(p: String) -> String:
	if p == null:
		return ""
	return String(p).replace("res:/", "res://")

static func _jsonify_object_like(s: String) -> String:
	# Quote bare keys in object maps: { name: "idle" } -> { "name": "idle" }
	var out := s
	var re := RegEx.new()
	re.compile("([\\{,\\[]\\s*)([A-Za-z_][A-Za-z0-9_]*)\\s*:")
	var last := ""
	while last != out:
		last = out
		out = re.sub(out, "\\1\"\\2\":", true)
	return out

static func parse_jsonish(s: String) -> Variant:
	var src := s.strip_edges()
	# Replace single quotes with double quotes cautiously (common in model output)
	# This is a heuristic; valid JSON shouldn't need this.
	var tmp := src
	# First, quote bare keys if it's an object
	if src.begins_with("{"):
		tmp = _jsonify_object_like(tmp)
	# Try JSON parse directly
	var parsed = JSON.parse_string(tmp)
	if parsed != null:
		return parsed
	# Heuristic retry with single->double quotes for strings
	tmp = tmp.replace("'", '"')
	if src.begins_with("{"):
		tmp = _jsonify_object_like(tmp)
	parsed = JSON.parse_string(tmp)
	return parsed

static func parse_edit_node_line(line: String) -> Dictionary:
	var rest = line.replace("edit_node(", "")
	if rest.ends_with(")"):
		rest = rest.substr(0, rest.length() - 1)
	rest = rest.strip_edges()
	var quoted: Array = []
	var i := 0
	while true:
		var a = rest.find('"', i)
		if a == -1:
			break
		var b = rest.find('"', a + 1)
		if b == -1:
			break
		quoted.append(rest.substr(a + 1, b - a - 1))
		i = b + 1
	var brace_open = rest.find("{")
	var brace_close = rest.rfind("}")
	if brace_open == -1 or brace_close == -1:
		return {}
	var map_text = rest.substr(brace_open, brace_close - brace_open + 1)
	var node_name := ""
	if quoted.size() > 0:
		node_name = quoted[0]
	var scene_path := ""
	if quoted.size() > 1:
		scene_path = quoted[1]
	return {
		"node_name": node_name,
		"scene_path": scene_path,
		"modifications": parse_object_map(map_text)
	}

static func parse_edit_script_args(line: String) -> Dictionary:
	var body = line.replace("edit_script(", "")
	if body.ends_with(")"):
		body = body.substr(0, body.length() - 1)
	body = body.strip_edges()
	var parts: Array = []
	var i := 0
	var token := ""
	var in_quotes := false
	var prev := ""
	for c_i in range(body.length()):
		var ch: String = body.substr(c_i, 1)
		if ch == '"' and prev != '\\':
			in_quotes = !in_quotes
			continue
		if ch == "," and !in_quotes:
			parts.append(token.strip_edges())
			token = ""
			continue
		token += ch
		prev = ch
	if token != "":
		parts.append(token.strip_edges())
	if parts.size() < 1:
		return {}
	var path = parts[0].trim_prefix('"').trim_suffix('"')
	var msg_id: int = -1
	if parts.size() > 1:
		msg_id = int(parts[1])
	return {"path": path, "message_id": msg_id} 