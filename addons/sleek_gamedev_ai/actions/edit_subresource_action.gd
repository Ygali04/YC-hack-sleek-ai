@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(node_name: String, scene_path: String, subresource_property_name: String, properties: Dictionary) -> bool:
	var ei = EditorPlugin.new().get_editor_interface()
	var open_scenes: Array = ei.get_open_scenes()
	for scene in open_scenes:
		if scene == scene_path:
			ei.reload_scene_from_path(scene_path)
			return _edit_in_open(node_name, ei.get_edited_scene_root(), subresource_property_name, properties)
	return _edit_in_closed(node_name, scene_path, subresource_property_name, properties)

static func _edit_in_open(node_name: String, root: Node, sub_prop: String, props: Dictionary) -> bool:
	var node = _find_node(node_name, root)
	if not node:
		return false
	var res: Resource = node.get(sub_prop)
	if not res:
		push_error("Subresource property '%s' not found on node '%s'" % [sub_prop, node_name])
		return false
	if not _apply_res_props(res, props):
		return false
	var ei2 = EditorPlugin.new().get_editor_interface()
	return ei2.save_scene() == OK

static func _edit_in_closed(node_name: String, scene_path: String, sub_prop: String, props: Dictionary) -> bool:
	var packed = load(scene_path)
	if !(packed is PackedScene):
		return false
	var root = packed.instantiate()
	var node = _find_node(node_name, root)
	if not node:
		return false
	var res: Resource = node.get(sub_prop)
	if not res:
		push_error("Subresource property '%s' not found on node '%s'" % [sub_prop, node_name])
		return false
	if not _apply_res_props(res, props):
		return false
	packed.pack(root)
	return ResourceSaver.save(packed, scene_path) == OK

static func _find_node(name: String, root: Node) -> Node:
	var node = root.find_child(name, true, true)
	if not node and name == root.name:
		node = root
	if not node:
		push_error("Node '%s' not found in the scene." % name)
		return null
	return node

static func _parse_value(v) -> Variant:
	if v is String:
		var s: String = v.strip_edges()
		if s.begins_with("(") and s.ends_with(")"):
			var inner = s.substr(1, s.length() - 2)
			var parts = inner.split(",", false)
			if parts.size() == 2:
				return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
			elif parts.size() == 3:
				return Vector3(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()))
			elif parts.size() == 4:
				return Vector4(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()), float(parts[3].strip_edges()))
		if s.to_lower() == "true":
			return true
		if s.to_lower() == "false":
			return false
		if s.is_valid_float():
			return float(s)
		return s
	return v

static func _apply_res_props(res: Resource, props: Dictionary) -> bool:
	for k in props.keys():
		var raw = props[k]
		var parsed = _parse_value(raw)
		if parsed == null and raw != null:
			push_error("Failed to parse value '%s' for subresource property '%s'." % [str(raw), k])
			return false
		res.set(k, parsed)
		if res.get(k) != parsed:
			push_error("Failed to set property '%s' on resource '%s'" % [k, res.get_class()])
			return false
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("edit_subresource("):
		var body = line.replace("edit_subresource(", "")
		if body.ends_with(")"):
			body = body.substr(0, body.length() - 1)
		body = body.strip_edges()
		var quoted: Array = []
		var i := 0
		while true:
			var a = body.find('"', i)
			if a == -1:
				break
			var b = body.find('"', a + 1)
			if b == -1:
				break
			quoted.append(body.substr(a + 1, b - a - 1))
			i = b + 1
		var open_i = body.find("{")
		var close_i = body.rfind("}")
		if open_i == -1 or close_i == -1 or quoted.size() < 3:
			return {}
		var prop_map = Utils.parse_object_map(body.substr(open_i, close_i - open_i + 1))
		return {
			"type": "edit_subresource",
			"node_name": quoted[0],
			"scene_path": quoted[1],
			"subresource_property_name": quoted[2],
			"properties": prop_map
		}
	return {} 