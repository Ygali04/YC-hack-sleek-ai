@tool
extends Node

static func execute(scene_path: String) -> bool:
	var cfg = ProjectSettings
	cfg.set_setting("application/run/main_scene", scene_path)
	var ok = cfg.save()
	if ok != OK:
		push_error("set_main_scene: failed to save ProjectSettings (" + str(ok) + ")")
		return false
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("set_main_scene("):
		var path = line.substr("set_main_scene(\"".length(), line.length()).rstrip(")")
		path = path.strip_edges().trim_prefix("\"").trim_suffix("\"")
		return {"type": "set_main_scene", "path": path}
	return {} 