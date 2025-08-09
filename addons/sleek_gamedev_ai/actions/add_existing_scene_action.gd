@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(node_name: String, existing_scene_path: String, target_scene_path: String, parent_path: String, modifications: Dictionary) -> bool:
	var ei = EditorPlugin.new().get_editor_interface()
	var open_scenes: Array = ei.get_open_scenes()
	for s in open_scenes:
		if s == target_scene_path:
			ei.reload_scene_from_path(target_scene_path)
			return _add_to_open(node_name, existing_scene_path, ei.get_edited_scene_root(), parent_path, modifications)
	return _add_to_closed(node_name, existing_scene_path, target_scene_path, parent_path, modifications)

static func _add_to_open(node_name: String, src_scene: String, root: Node, parent_path: String, modifications: Dictionary) -> bool:
	src_scene = Utils.normalize_res_path(src_scene)
	var src_ps = load(src_scene)
	if !(src_ps is PackedScene):
		push_error("add_existing_scene: failed to load source scene '%s'" % src_scene)
		return false
	var inst = src_ps.instantiate()
	inst.name = node_name
	var parent: Node
	if parent_path.is_empty() or parent_path == root.name:
		parent = root
	else:
		parent = root.find_child(parent_path, true, true)
	if not parent:
		if parent_path == root.name:
			parent = root
		else:
			push_error("add_existing_scene: parent '%s' not found in open scene" % parent_path)
			return false
	parent.add_child(inst)
	inst.set_owner(root)
	if modifications and modifications.size() > 0:
		for k in modifications.keys():
			inst.set(k, modifications[k])
	var ei2 = EditorPlugin.new().get_editor_interface()
	var ok = ei2.save_scene()
	if ok != OK:
		push_error("add_existing_scene: failed to save open scene '%s' (Error %d)" % [root.name, ok])
		return false
	return true

static func _add_to_closed(node_name: String, src_scene: String, dst_scene: String, parent_path: String, modifications: Dictionary) -> bool:
	dst_scene = Utils.normalize_res_path(dst_scene)
	var dst_ps = load(dst_scene)
	if !(dst_ps is PackedScene):
		push_error("add_existing_scene: failed to load target scene '%s'" % dst_scene)
		return false
	var dst_root = dst_ps.instantiate()
	src_scene = Utils.normalize_res_path(src_scene)
	var src_ps = load(src_scene)
	if !(src_ps is PackedScene):
		push_error("add_existing_scene: failed to load source scene '%s'" % src_scene)
		return false
	var inst = src_ps.instantiate()
	inst.name = node_name
	var parent: Node
	if parent_path.is_empty() or parent_path == dst_root.name:
		parent = dst_root
	else:
		parent = dst_root.find_child(parent_path, true, true)
	if not parent:
		if parent_path == dst_root.name:
			parent = dst_root
		else:
			push_error("add_existing_scene: parent '%s' not found in '%s'" % [parent_path, dst_scene])
			return false
	parent.add_child(inst)
	inst.set_owner(dst_root)
	if modifications and modifications.size() > 0:
		for k in modifications.keys():
			inst.set(k, modifications[k])
	dst_ps.pack(dst_root)
	var ok2 = ResourceSaver.save(dst_ps, dst_scene)
	if ok2 != OK:
		push_error("add_existing_scene: failed to save scene '%s' (Error %d)" % [dst_scene, ok2])
		return false
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("add_existing_scene("):
		var body = line.replace("add_existing_scene(", "")
		if body.ends_with(")"):
			body = body.substr(0, body.length() - 1)
		body = body.strip_edges()
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
		var mods := {}
		var open_i = body.find("{")
		var close_i = body.rfind("}")
		if open_i != -1 and close_i != -1:
			mods = Utils.parse_object_map(body.substr(open_i, close_i - open_i + 1))
		if strings.size() < 3:
			return {}
		var parent_val := ""
		if strings.size() > 3:
			parent_val = strings[3]
		return {
			"type": "add_existing_scene",
			"node_name": strings[0],
			"existing_scene_path": strings[1],
			"target_scene_path": strings[2],
			"parent_path": parent_val,
			"modifications": mods
		}
	return {} 