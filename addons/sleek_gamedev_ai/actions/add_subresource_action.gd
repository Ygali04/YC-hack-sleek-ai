@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(node_name: String, scene_path: String, subresource_type: String, properties: Dictionary) -> bool:
	var ei = EditorPlugin.new().get_editor_interface()
	var open_scenes: Array = ei.get_open_scenes()
	for scene in open_scenes:
		if scene == scene_path:
			ei.reload_scene_from_path(scene_path)
			return _add_to_open(node_name, ei.get_edited_scene_root(), subresource_type, properties)
	return _add_to_closed(node_name, scene_path, subresource_type, properties)

static func _add_to_open(node_name: String, scene_root: Node, subresource_type: String, props: Dictionary) -> bool:
	var target = _find_node(node_name, scene_root)
	if not target:
		return false
	var res = _build_resource(subresource_type, props)
	if not res:
		return false
	if not props.has("assign_to_property"):
		push_error("add_subresource: missing 'assign_to_property'")
		return false
	var prop_name: String = String(props["assign_to_property"]) 
	if not _assign_resource_property(target, prop_name, res):
		push_error("add_subresource: failed to assign resource to property '%s'" % prop_name)
		return false
	var ei2 = EditorPlugin.new().get_editor_interface()
	var ok = ei2.save_scene()
	if ok != OK:
		push_error("add_subresource: failed to save open scene '%s' (Error %d)" % [scene_root.name, ok])
		return false
	return true

static func _add_to_closed(node_name: String, scene_path: String, subresource_type: String, props: Dictionary) -> bool:
	var packed = load(scene_path)
	if !(packed is PackedScene):
		push_error("add_subresource: failed to load scene '%s' as PackedScene" % scene_path)
		return false
	var root = packed.instantiate()
	var target = _find_node(node_name, root)
	if not target:
		return false
	var res = _build_resource(subresource_type, props)
	if not res:
		return false
	if not props.has("assign_to_property"):
		push_error("add_subresource: missing 'assign_to_property'")
		return false
	var prop_name: String = String(props["assign_to_property"]) 
	if not _assign_resource_property(target, prop_name, res):
		push_error("add_subresource: failed to assign resource to property '%s'" % prop_name)
		return false
	packed.pack(root)
	var ok = ResourceSaver.save(packed, scene_path)
	if ok != OK:
		push_error("add_subresource: failed to save scene '%s' (Error %d)" % [scene_path, ok])
		return false
	return true

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

static func _build_resource(res_type: String, props: Dictionary) -> Resource:
	if not ClassDB.class_exists(res_type):
		push_error("Resource type '%s' does not exist." % res_type)
		return null
	var res = ClassDB.instantiate(res_type)
	if not res:
		push_error("Could not instantiate resource of type '%s'." % res_type)
		return null
	for k in props.keys():
		if k == "assign_to_property":
			continue
		var raw = props[k]
		var parsed = _parse_value(raw)
		if parsed == null and raw != null:
			push_error("Failed to parse value '%s' for property '%s'." % [str(raw), k])
			return null
		if not _safe_set_res_prop(res, k, parsed):
			return null
	return res

static func _safe_set_res_prop(res: Resource, name: String, value: Variant) -> bool:
	var plist = res.get_property_list()
	var expected_type = null
	for info in plist:
		if info.name == name:
			expected_type = info.type
			break
	if expected_type == null:
		push_error("Property '%s' doesn't exist on resource '%s'." % [name, res.get_class()])
		return true
	if expected_type == TYPE_COLOR:
		match typeof(value):
			TYPE_VECTOR2:
				value = Color(value.x, value.y, 0, 1.0)
			TYPE_VECTOR3:
				value = Color(value.x, value.y, value.z, 1.0)
			TYPE_VECTOR4:
				value = Color(value.x, value.y, value.z, value.w)
			TYPE_ARRAY:
				if value.size() == 3:
					value = Color(value[0], value[1], value[2], 1.0)
				elif value.size() == 4:
					value = Color(value[0], value[1], value[2], value[3])
	elif expected_type == TYPE_VECTOR3 and typeof(value):
		value = Vector3(value.x, value.y, 0)
	res.set(name, value)
	var actual = res.get(name)
	var ok: bool
	if typeof(value) in [TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4]:
		ok = (typeof(actual) == typeof(value)) and actual.is_equal_approx(value)
	elif typeof(value) == TYPE_FLOAT:
		ok = is_equal_approx(value, actual)
	else:
		ok = (actual == value)
	if typeof(actual) == typeof(value) and not ok:
		push_error("Failed to set resource property '%s' on resource '%s' value: %s " % [name, res.get_class(), value])
		return false
	return true

static func _assign_resource_property(node: Node, prop_name: String, res: Resource) -> bool:
	node.set(prop_name, res)
	return node.get(prop_name) == res

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("add_subresource("):
		var body = line.replace("add_subresource(", "").strip_edges()
		if body.ends_with(")"):
			body = body.substr(0, body.length() - 1)
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
		if open_i == -1 or close_i == -1:
			return {}
		var map_text = body.substr(open_i, close_i - open_i + 1)
		var props = Utils.parse_object_map(map_text)
		# unquote keys that have raw quoted strings
		for key in props.keys():
			var v = props[key]
			if v is String:
				var s = (v as String).strip_edges()
				if s.begins_with('"') and s.ends_with('"') and s.length() > 1:
					props[key] = s.substr(1, s.length() - 2)
		if quoted.size() < 3:
			return {}
		return {
			"type": "add_subresource",
			"node_name": quoted[0],
			"scene_path": quoted[1],
			"subresource_type": quoted[2],
			"properties": props
		}
	return {} 