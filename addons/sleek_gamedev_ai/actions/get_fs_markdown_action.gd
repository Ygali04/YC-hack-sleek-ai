@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("get_fs_markdown("):
		var opts := {}
		if line.find("{") != -1:
			var open_i = line.find("{")
			var close_i = line.rfind("}")
			if open_i != -1 and close_i != -1 and close_i > open_i:
				var map_text = line.substr(open_i, close_i - open_i + 1)
				opts = Utils.parse_object_map(map_text)
		return {"type": "get_fs_markdown", "options": opts}
	return {}

static func _should_skip(path: String) -> bool:
	var skip_dirs = [".git", ".godot", ".import", "__pycache__"]
	for s in skip_dirs:
		if path.find("/" + s + "/") != -1:
			return true
	return false

static func _tree(path: String, depth: int, max_depth: int, out: Array) -> void:
	if depth > max_depth:
		return
	var d = DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entries: Array = []
	while true:
		var name = d.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		entries.append(name)
	d.list_dir_end()
	entries.sort()
	for name in entries:
		var child = path.rstrip("/") + "/" + name
		var indent = "  ".repeat(depth)
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(child)):
			if _should_skip(child):
				continue
			out.append(indent + "- " + name + "/")
			_tree(child, depth + 1, max_depth, out)
		else:
			out.append(indent + "- " + name)

static func execute(opts: Dictionary) -> bool:
	var root := String(opts.get("path", "res://"))
	var max_depth := int(opts.get("max_depth", 2))
	var lines: Array = ["## File System (" + root + ")"]
	_tree(root, 0, max_depth, lines)
	var md := "\n".join(lines)
	print(md)
	return true 