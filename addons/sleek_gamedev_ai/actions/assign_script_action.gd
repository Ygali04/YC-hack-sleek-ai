@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(node_name: String, scene_path: String, script_path: String) -> bool:
	var ei = EditorPlugin.new().get_editor_interface()
	var open_scenes: Array = ei.get_open_scenes()
	for scene in open_scenes:
		if scene == scene_path:
			ei.reload_scene_from_path(scene_path)
			return _assign_in_open(node_name, ei.get_edited_scene_root(), script_path)
	return _assign_in_closed(node_name, scene_path, script_path)

static func _assign_in_open(node_name: String, root: Node, script_path: String) -> bool:
	var target = root.find_child(node_name, true, true)
	if not target and node_name == root.name:
		target = root
	if not target:
		push_error("Node '%s' not found in open scene root '%s'." % [node_name, root.name])
		return false
	var spath: String = Utils.normalize_res_path(script_path)
	var script = load(spath)
	if not script:
		push_error("Failed to load script at path: %s" % spath)
		return false
	target.set_script(script)
	var ei2 = EditorPlugin.new().get_editor_interface()
	var ok = ei2.save_scene()
	if ok != OK:
		push_error("assign_script: failed to save open scene '%s' (Error %d)" % [root.name, ok])
		return false
	return true

static func _assign_in_closed(node_name: String, scene_path: String, script_path: String) -> bool:
	var sp: String = Utils.normalize_res_path(scene_path)
	var packed = load(sp)
	if !(packed is PackedScene):
		push_error("Failed to load scene '%s' as PackedScene." % sp)
		return false
	var root = packed.instantiate()
	var target = root.find_child(node_name, true, true)
	if not target and node_name == root.name:
		target = root
	if not target:
		push_error("Node '%s' not found in scene instance root '%s'." % [node_name, root.name])
		return false
	var spath: String = Utils.normalize_res_path(script_path)
	var script = load(spath)
	if not script:
		push_error("Failed to load script at path: %s" % spath)
		return false
	target.set_script(script)
	packed.pack(root)
	var ok2 = ResourceSaver.save(packed, sp)
	if ok2 != OK:
		push_error("assign_script: failed to save scene '%s' (Error %d)" % [sp, ok2])
		return false
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("assign_script("):
		var body = line.replace("assign_script(", "").replace(")", "").strip_edges()
		var strings: Array = []
		var i := 0
		while true:
			var a = body.find('"', i)
			if a == -1:
				break
			var b = body.find('"', a + 1)
			if b == -1:
				break
			strings.append(body.substr(a + 1, b - a - 1))
			i = b + 1
		if strings.size() != 3:
			return {}
		return {
			"type": "assign_script",
			"node_name": strings[0],
			"scene_path": strings[1],
			"script_path": strings[2]
		}
	return {} 