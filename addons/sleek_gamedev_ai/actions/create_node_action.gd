@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")
const EditNode = preload("res://addons/sleek_gamedev_ai/actions/edit_node_action.gd")

static func execute(name: String, node_type: String, scene_path: String, parent_path: String, modifications: Dictionary = {}) -> bool:
	var ei = EditorPlugin.new().get_editor_interface()
	var open_scenes: Array = ei.get_open_scenes()
	for scene in open_scenes:
		if scene == scene_path:
			ei.reload_scene_from_path(scene_path)
			return _add_to_open(name, node_type, ei.get_edited_scene_root(), parent_path, modifications)
	return _add_to_closed(name, node_type, scene_path, parent_path, modifications)

static func _find_preferred_parent(scene_root: Node, desired_parent: String, node_type: String) -> Node:
	# If a CharacterBody2D exists, prefer it for AnimatedSprite2D
	var char_parent: Node = scene_root.find_child("CharacterBody2D", true, true)
	if node_type == "AnimatedSprite2D" and char_parent:
		return char_parent
	# Map '.' to scene root
	if desired_parent == "." or desired_parent.is_empty():
		return scene_root
	# Otherwise try to find the named parent
	var p = scene_root.find_child(desired_parent, true, true)
	if p:
		return p
	# Fallbacks
	if char_parent:
		return char_parent
	return scene_root

static func _add_to_open(name: String, node_type: String, scene_root: Node, parent_path: String, modifications: Dictionary) -> bool:
	if !ClassDB.class_exists(node_type):
		push_error("create_node: class '%s' does not exist" % node_type)
		return false
	var node = ClassDB.instantiate(node_type)
	node.name = name
	var parent: Node = _find_preferred_parent(scene_root, parent_path, node_type)
	if not parent:
		push_error("create_node: failed to determine parent for '%s'" % name)
		return false
	parent.add_child(node)
	node.set_owner(scene_root)
	if not modifications.is_empty():
		if not EditNode.apply_property_changes(node, modifications, scene_root):
			return false
	var ei2 = EditorPlugin.new().get_editor_interface()
	return ei2.save_scene() == OK

static func _add_to_closed(name: String, node_type: String, scene_path: String, parent_path: String, modifications: Dictionary) -> bool:
	scene_path = Utils.normalize_res_path(scene_path)
	var packed = load(scene_path)
	if !packed is PackedScene:
		push_error("create_node: failed to load scene '%s' as PackedScene" % scene_path)
		return false
	var root = packed.instantiate()
	if !ClassDB.class_exists(node_type):
		push_error("create_node: class '%s' does not exist" % node_type)
		return false
	var node = ClassDB.instantiate(node_type)
	node.name = name
	var parent: Node = _find_preferred_parent(root, parent_path, node_type)
	if not parent:
		push_error("create_node: failed to determine parent for '%s' in closed scene" % name)
		return false
	parent.add_child(node)
	node.set_owner(root)
	if not modifications.is_empty():
		if not EditNode.apply_property_changes(node, modifications, root):
			return false
	packed.pack(root)
	var ok = ResourceSaver.save(packed, scene_path)
	if ok != OK:
		push_error("create_node: failed to save scene '%s' (Error %d)" % [scene_path, ok])
		return false
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("create_node("):
		var parts = Utils.parse_create_node_args(line)
		if parts.size() < 3:
			return {}
		var mods := {}
		var open_i = line.find("{")
		var close_i = line.rfind("}")
		if open_i != -1 and close_i != -1:
			var obj_text = line.substr(open_i, close_i - open_i + 1)
			mods = Utils.parse_object_map(obj_text)
		var parent_path_val := ""
		if parts.size() > 3:
			parent_path_val = parts[3]
		return {
			"type": "create_node",
			"name": parts[0],
			"node_type": parts[1],
			"scene_path": parts[2],
			"parent_path": parent_path_val,
			"modifications": mods
		}
	return {} 