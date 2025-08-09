@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(path: String, root_name: String, root_type: String) -> bool:
	path = Utils.normalize_res_path(path)
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	if !ClassDB.class_exists(root_type):
		push_error("create_scene: class '%s' does not exist" % root_type)
		return false
	var ps := PackedScene.new()
	var root := ClassDB.instantiate(root_type)
	root.name = root_name
	ps.pack(root)
	var ok = ResourceSaver.save(ps, path)
	if ok != OK:
		push_error("create_scene: failed to save scene '%s' (Error %d)" % [path, ok])
		return false
	if ok == OK and Engine.is_editor_hint():
		EditorPlugin.new().get_editor_interface().get_resource_filesystem().scan()
	return ok == OK

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("create_scene("):
		var parts = Utils.parse_create_scene_args(line)
		if parts.size() >= 3:
			return {
				"type": "create_scene",
				"path": parts[0],
				"root_name": parts[1],
				"root_type": parts[2]
			}
	return {} 