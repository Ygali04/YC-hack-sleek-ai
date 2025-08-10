@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

# Syntax:
# read_file({ path: "res://scripts/player.gd", start: 1, end: 200 })
# If start/end omitted, returns full file content (capped length printed)

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if not line.begins_with("read_file("):
		return {}
	var open_i = line.find("{")
	var close_i = line.rfind("}")
	if open_i == -1 or close_i == -1 or close_i <= open_i:
		return {}
	var map_text = line.substr(open_i, close_i - open_i + 1)
	var opts = Utils.parse_object_map(map_text)
	if not opts.has("path"):
		return {}
	return {"type": "read_file", "options": opts}

static func execute(opts: Dictionary) -> bool:
	var path := String(opts.get("path", ""))
	if path == "":
		push_error("read_file: missing 'path'")
		return false
	if not FileAccess.file_exists(path):
		push_error("read_file: file not found: %s" % path)
		return false
	var start := int(opts.get("start", 1))
	var end := int(opts.get("end", -1))
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("read_file: failed to open: %s" % path)
		return false
	var content = f.get_as_text()
	f.close()
	var lines = content.split("\n")
	var out_lines: Array[String] = []
	var s := clamp(start, 1, max(1, lines.size()))
	var e := end
	if e <= 0:
		e = lines.size()
	else:
		e = clamp(e, s, lines.size())
	for i in range(s - 1, e):
		out_lines.append(str(i + 1).pad_zeros(4) + ": " + String(lines[i]))
	print("[read_file] " + path + " (" + str(s) + "-" + str(e) + ")\n" + "\n".join(out_lines))
	return true 