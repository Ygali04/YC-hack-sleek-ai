@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

# Syntax:
# grep({ query: "regex or text", path: "res://scripts" , include: "*.gd", exclude: "*.import", max_results: 100 })
# If path not provided, searches under res://

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if not line.begins_with("grep("):
		return {}
	var open_i = line.find("{")
	var close_i = line.rfind("}")
	if open_i == -1 or close_i == -1 or close_i <= open_i:
		return {}
	var map_text = line.substr(open_i, close_i - open_i + 1)
	var opts = Utils.parse_object_map(map_text)
	if not opts.has("query"):
		return {}
	return {"type": "grep", "options": opts}

static func _match_glob(name: String, pattern: String) -> bool:
	# Use String.match with wildcard patterns (not regex)
	if pattern == "" or pattern == "*":
		return true
	return name.match(pattern)

static func _should_skip(path: String) -> bool:
	var skip_dirs = [".git", ".godot", ".import", "__pycache__"]
	for s in skip_dirs:
		if path.find("/" + s + "/") != -1:
			return true
	return false

static func _search_in_file(path: String, query: String, use_regex: bool) -> Array:
	var results: Array = []
	if not FileAccess.file_exists(path):
		return results
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return results
	var content = f.get_as_text()
	f.close()
	var lines = content.split("\n")
	if use_regex:
		var re := RegEx.new()
		var ok = re.compile(query)
		if ok != OK:
			return results
		for i in range(lines.size()):
			if re.search(lines[i]) != null:
				results.append({"file": path, "line": i + 1, "text": lines[i]})
	else:
		for i in range(lines.size()):
			if lines[i].find(query) != -1:
				results.append({"file": path, "line": i + 1, "text": lines[i]})
	return results

static func execute(opts: Dictionary) -> bool:
	var query := String(opts.get("query", ""))
	if query == "":
		push_error("grep: missing 'query'")
		return false
	var root := String(opts.get("path", "res://"))
	var include_glob := String(opts.get("include", ""))
	var exclude_glob := String(opts.get("exclude", ""))
	var max_results := int(opts.get("max_results", 100))
	var use_regex := bool(opts.get("regex", true))
	var matches: Array = []
	var stack: Array[String] = [root]
	while stack.size() > 0 and matches.size() < max_results:
		var p = stack.pop_back()
		if _should_skip(p):
			continue
		var gpath = ProjectSettings.globalize_path(p)
		if DirAccess.dir_exists_absolute(gpath):
			var d = DirAccess.open(p)
			if d == null:
				continue
			d.list_dir_begin()
			while true:
				var name = d.get_next()
				if name == "": break
				if name.begins_with("."): continue
				var child = p.rstrip("/") + "/" + name
				if d.current_is_dir():
					stack.append(child)
				else:
					if include_glob != "" and not _match_glob(name, include_glob):
						continue
					if exclude_glob != "" and _match_glob(name, exclude_glob):
						continue
					matches.append_array(_search_in_file(child, query, use_regex))
			d.list_dir_end()
		else:
			if FileAccess.file_exists(p):
				matches.append_array(_search_in_file(p, query, use_regex))
	# Emit results to console (and return true so UI marks success)
	print("[grep] results (", matches.size(), ")")
	for m in matches.slice(0, max_results):
		print("- ", m["file"], ":", m["line"], " | ", m["text"].left(200))
	return true 