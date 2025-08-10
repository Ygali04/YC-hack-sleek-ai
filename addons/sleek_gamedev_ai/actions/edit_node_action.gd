@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(node_name: String, scene_path: String, modifications: Dictionary) -> bool:
	var ei = EditorPlugin.new().get_editor_interface()
	var open_scenes: Array = ei.get_open_scenes()
	for scene in open_scenes:
		if scene == scene_path:
			ei.reload_scene_from_path(scene_path)
			return _edit_in_open(node_name, ei.get_edited_scene_root(), modifications)
	return _edit_in_closed(node_name, scene_path, modifications)

static func _edit_in_open(node_name: String, scene_root: Node, modifications: Dictionary) -> bool:
	var node = scene_root.find_child(node_name, true, true)
	if not node and node_name == scene_root.name:
		node = scene_root
	if not node:
		push_error("edit_node: node '%s' not found in open scene '%s'" % [node_name, scene_root.name])
		return false
	if not apply_property_changes(node, modifications, scene_root):
		return false
	var ei = EditorPlugin.new().get_editor_interface()
	var ok = ei.save_scene()
	if ok != OK:
		push_error("edit_node: failed to save open scene '%s' (Error %d)" % [scene_root.name, ok])
		return false
	return true

static func _edit_in_closed(node_name: String, scene_path: String, modifications: Dictionary) -> bool:
	scene_path = Utils.normalize_res_path(scene_path)
	var packed = load(scene_path)
	if !(packed is PackedScene):
		push_error("Failed to load scene '%s' as PackedScene." % scene_path)
		return false
	var root = packed.instantiate()
	var node = root.find_child(node_name, true, true)
	if not node and node_name == root.name:
		node = root
	if not node:
		push_error("Node '%s' not found in scene instance root '%s'." % [node_name, root.name])
		return false
	if not apply_property_changes(node, modifications, root):
		return false
	packed.pack(root)
	var ok2 = ResourceSaver.save(packed, scene_path)
	if ok2 != OK:
		push_error("edit_node: failed to save scene '%s' (Error %d)" % [scene_path, ok2])
		return false
	return true

static func _parse_value(v) -> Variant:
	if v is String:
		var s: String = v.strip_edges()
		if s.length() >= 2 and s.begins_with('"') and s.ends_with('"'):
			s = s.substr(1, s.length() - 2)
		elif s.length() >= 2 and s.begins_with("'") and s.ends_with("'"):
			s = s.substr(1, s.length() - 2)
		if s.begins_with("(") and s.ends_with(")"):
			var inner = s.substr(1, s.length() - 2)
			var parts = inner.split(",", false)
			if parts.size() == 2:
				return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
			if parts.size() == 3:
				return Vector3(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()))
			if parts.size() == 4:
				return Vector4(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()), float(parts[3].strip_edges()))
		if s.to_lower() == "true":
			return true
		if s.to_lower() == "false":
			return false
		if s.is_valid_float():
			return float(s)
		return s
	return v

static func apply_property_changes(node: Node, modifications: Dictionary, scene_root: Node = null) -> bool:
	for property_name in modifications.keys():
		var raw_val = modifications[property_name]
		var parsed = _parse_value(raw_val)
		if parsed == null and raw_val != null:
			push_error("Failed to parse value '%s' for property '%s'." % [str(raw_val), property_name])
			return false
		if not _try_set_property(node, property_name, parsed, scene_root):
			return false
	return true

static func _try_set_property(node: Node, prop_name: String, value: Variant, scene_root: Node = null) -> bool:
	# Compatibility: allow 'autoplay' shorthand for AnimatedSprite2D to mean (animation=value, playing=true)
	if node is AnimatedSprite2D and prop_name == "autoplay":
		var anim_name := String(value)
		node.set("animation", anim_name)
		node.set("playing", true)
		return true
	# Compatibility: Godot 4 TileMap no longer has 'cell_size'. Map to TileSet.tile_size if available, or ignore with warning.
	if node is TileMap and prop_name == "cell_size":
		var v2i := Vector2i.ZERO
		match typeof(value):
			TYPE_VECTOR2:
				v2i = Vector2i(int(value.x), int(value.y))
			TYPE_VECTOR3:
				v2i = Vector2i(int(value.x), int(value.y))
			TYPE_ARRAY:
				if value.size() >= 2:
					v2i = Vector2i(int(value[0]), int(value[1]))
		if node.tile_set:
			node.tile_set.tile_size = v2i
			return true
		else:
			print("[edit_node] Warning: TileMap has no TileSet; cannot map 'cell_size'.")
			return true
	if prop_name == "parent":
		if not value is String:
			push_error("Parent value must be a string (name of the new parent)")
			return false
		if scene_root == null:
			push_error("Cannot re-parent without a valid scene root.")
			return false
		var parent_name: String = (value as String).strip_edges()
		var new_parent: Node
		if parent_name == "" or parent_name == scene_root.name:
			new_parent = scene_root
		else:
			new_parent = scene_root.find_child(parent_name, true, true)
			if not new_parent:
				push_error("Failed to find parent node with name: %s" % parent_name)
				return false
		if node.get_parent():
			node.get_parent().remove_child(node)
		new_parent.add_child(node)
		node.set_owner(scene_root)
		return true
	var plist = node.get_property_list()
	for p in plist:
		if p.name == prop_name:
			if p.type == TYPE_COLOR:
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
			elif p.type == TYPE_OBJECT and p.hint == PROPERTY_HINT_RESOURCE_TYPE:
				var hint: String = p.hint_string
				if hint == "Texture2D" or hint.contains("Texture2D"):
					var path_str: String = Utils.normalize_res_path(String(value))
					var tex = load(path_str)
					if "_" in prop_name:
						var parts: Array = prop_name.split("_")
						if parts.size() > 1:
							var suffix = parts[1]
							var method = "set_texture_" + suffix
							if node.has_method(method):
								node.call(method, tex)
								return true
					if node.has_method("set_texture"):
						node.set_texture(tex)
						return true
				elif hint == "Mesh" or hint.contains("Mesh"):
					var mesh_path: String = Utils.normalize_res_path(String(value))
					var mesh = load(mesh_path)
					if not mesh:
						push_error("Failed to load mesh at path: %s" % mesh_path)
						return false
					if "_" in prop_name:
						var parts2: Array = prop_name.split("_")
						if parts2.size() > 1:
							var suffix2 = parts2[1]
							var method2 = "set_mesh_" + suffix2
							if node.has_method(method2):
								node.call(method2, mesh)
								return true
					node.set(prop_name, mesh)
					return true
				elif hint == "AudioStream" or hint.contains("AudioStream"):
					var stream_path: String = Utils.normalize_res_path(String(value))
					var stream = load(stream_path)
					if not stream:
						push_error("Failed to load audio stream at path: %s" % stream_path)
						return false
					node.set(prop_name, stream)
					return true
			# Fallback generic set
			node.set(prop_name, value)
			return true
	if not node.has_method("get") or node.get(prop_name) == null:
		push_error("Property '%s' doesn't exist on node '%s'." % [prop_name, node.name])
		return false
	node.set(prop_name, value)
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("edit_node("):
		var parsed = Utils.parse_edit_node_line(line)
		if parsed.size() == 0:
			return {}
		if not parsed.has("node_name") or not parsed.has("scene_path") or not parsed.has("modifications"):
			return {}
		return {
			"type": "edit_node",
			"node_name": parsed.node_name,
			"scene_path": parsed.scene_path,
			"modifications": parsed.modifications
		}
	return {} 