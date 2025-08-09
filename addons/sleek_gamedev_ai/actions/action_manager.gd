@tool
extends Node

signal action_completed(action_type: String, path: String, success: bool, button: Button)
signal set_disable_for_type(action_type: String, disable: bool)
signal action_error_bbcode(message: String)

const Parser = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")
const CreateFile = preload("res://addons/sleek_gamedev_ai/actions/create_file_action.gd")
const CreateScene = preload("res://addons/sleek_gamedev_ai/actions/create_scene_action.gd")
const CreateNode = preload("res://addons/sleek_gamedev_ai/actions/create_node_action.gd")
const EditNode = preload("res://addons/sleek_gamedev_ai/actions/edit_node_action.gd")
const AddSubresource = preload("res://addons/sleek_gamedev_ai/actions/add_subresource_action.gd")
const AssignScript = preload("res://addons/sleek_gamedev_ai/actions/assign_script_action.gd")
const EditScript = preload("res://addons/sleek_gamedev_ai/actions/edit_script_action.gd")
const EditSubresource = preload("res://addons/sleek_gamedev_ai/actions/edit_subresource_action.gd")
const AddExistingScene = preload("res://addons/sleek_gamedev_ai/actions/add_existing_scene_action.gd")
const CreateImage = preload("res://addons/sleek_gamedev_ai/actions/create_image_action.gd")
const SpriteSheetToFrames = preload("res://addons/sleek_gamedev_ai/actions/spritesheet_to_spriteframes_action.gd")

var actions_buttons: Array = []
var actions_vbox: VBoxContainer
var apply_all_button: Button
var in_apply_all: bool = false

func parse_actions_from_text(full_text: String, message_id: int) -> Array:
	var out: Array = []
	var start = full_text.find("[gds_actions]")
	var end = full_text.find("[/gds_actions]")
	if start == -1:
		return out
	var inner_start = start + "[gds_actions]".length()
	var inner_len: int
	if end == -1:
		# Fallback: consume to end of text
		inner_len = full_text.length() - inner_start
	else:
		inner_len = end - inner_start
	var inner = full_text.substr(inner_start, inner_len).strip_edges()
	var lines = inner.split("\n")
	var i := 0
	while i < lines.size():
		var line: String = String(lines[i]).strip_edges()
		if line == "":
			i += 1; continue
		# Handle multi-line create_image blocks: join until the closing ')' appears
		if line.begins_with("create_image(") and not line.contains(")"):
			var joined := line
			var j := i + 1
			while j < lines.size():
				joined += "\n" + lines[j]
				if String(lines[j]).find(")") != -1:
					break
				j += 1
			line = joined.strip_edges()
			i = j  # advance to the line with ')'
		var parsed = _parse_action_line(line, full_text)
		if not parsed.is_empty():
			parsed["message_id"] = message_id
			out.append(parsed)
		i += 1
	# Fallback: detect a raw create_image options map when verb omitted
	if out.size() == 0:
		var open_i = inner.find("{")
		var close_i = inner.rfind("}")
		if open_i != -1 and close_i != -1 and close_i > open_i:
			var map_text = inner.substr(open_i, close_i - open_i + 1)
			var opts = Parser.parse_object_map(map_text)
			if opts.has("prompt"):
				out.append({"type": "create_image", "options": opts, "message_id": message_id})
	return out

func _parse_action_line(line: String, full_text: String) -> Dictionary:
	var handlers = [CreateFile, CreateScene, CreateNode, EditNode, AddSubresource, AssignScript, EditScript, EditSubresource, CreateImage, SpriteSheetToFrames]
	for h in handlers:
		var d = h.parse_line(line, full_text)
		if not d.is_empty():
			return d
	return {}

func clear_rendered_actions(container: Control) -> void:
	if actions_vbox and actions_vbox.is_inside_tree():
		if container.has_node(actions_vbox.get_path()):
			container.remove_child(actions_vbox)
	actions_buttons.clear()

func render_actions(actions: Array, container: Control) -> void:
	clear_rendered_actions(container)
	actions_vbox = VBoxContainer.new()
	actions_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(actions_vbox)
	for action in actions:
		var btn = Button.new()
		btn.text = _label_for_action(action)
		btn.tooltip_text = _tooltip_for_action(action)
		btn.set_meta("action", action)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_action_pressed.bind(btn))
		actions_vbox.add_child(btn)
		actions_buttons.append(btn)
	if actions_buttons.size() > 1:
		apply_all_button = Button.new()
		apply_all_button.text = "Apply All"
		apply_all_button.disabled = false
		apply_all_button.tooltip_text = "Apply the actions listed below from top to bottom"
		apply_all_button.pressed.connect(_on_apply_all_pressed)
		actions_vbox.add_child(apply_all_button)

func _label_for_action(a: Dictionary) -> String:
	var t: String = a.get("type", "")
	match t:
		"create_file":
			return "Create %s" % a.get("path", "")
		"create_scene":
			return "Create %s" % a.get("path", "")
		"create_node":
			return "Create %s \"%s\"" % [a.get("node_type", ""), a.get("name", "")]
		"edit_node":
			return "Edit %s" % a.get("node_name", "")
		"add_subresource":
			return "Add %s to %s" % [a.get("subresource_type", ""), a.get("node_name", "")]
		"assign_script":
			return "Attach %s" % String(a.get("script_path", "")).get_file()
		"edit_script":
			return "Edit %s" % a.get("path", "")
		"create_image":
			return "Generate Image"
		"spritesheet_to_spriteframes":
			return "Spritesheet → SpriteFrames"
		_:
			return a.get("type", "Action")

func _tooltip_for_action(a: Dictionary) -> String:
	var lines: Array[String] = []
	var t: String = a.get("type", "")
	match t:
		"create_file":
			lines.append("Create file")
			lines.append("Path: %s" % a.get("path", ""))
		"create_scene":
			lines.append("Create scene")
			lines.append("Path: %s" % a.get("path", ""))
			lines.append("Root: %s" % a.get("root_type", ""))
		"create_node":
			lines.append("Create node")
			lines.append("Scene: %s" % String(a.get("scene_path", "")).get_file())
		"edit_node":
			lines.append("Edit node")
			lines.append("Scene: %s" % String(a.get("scene_path", "")).get_file())
		"add_subresource":
			lines.append("Add subresource")
			lines.append("Scene: %s" % String(a.get("scene_path", "")).get_file())
		"assign_script":
			lines.append("Attach script")
			lines.append("Scene: %s" % String(a.get("scene_path", "")).get_file())
		"edit_script":
			lines.append("Edit script")
		"create_image":
			lines.append("Generate image using Stability AI")
		"spritesheet_to_spriteframes":
			lines.append("Build SpriteFrames from spritesheet and assign to node")
		_:
			pass
	return "\n".join(lines)

func _on_action_pressed(btn: Button) -> void:
	in_apply_all = false
	_execute_button(btn)

func _execute_button(btn: Button) -> void:
	var a: Dictionary = {}
	if btn.has_meta("action"):
		a = btn.get_meta("action")
	btn.disabled = true
	var ok := false
	var t: String = a.get("type", "")
	match t:
		"create_file":
			ok = CreateFile.execute(a.get("path", ""), a.get("content", ""))
		"create_scene":
			ok = CreateScene.execute(a.get("path", ""), a.get("root_name", ""), a.get("root_type", ""))
		"create_node":
			ok = CreateNode.execute(a.get("name", ""), a.get("node_type", ""), a.get("scene_path", ""), a.get("parent_path", ""), a.get("modifications", {}))
		"edit_node":
			ok = EditNode.execute(a.get("node_name", ""), a.get("scene_path", ""), a.get("modifications", {}))
		"add_subresource":
			ok = AddSubresource.execute(a.get("node_name", ""), a.get("scene_path", ""), a.get("subresource_type", ""), a.get("properties", {}))
		"edit_subresource":
			ok = EditSubresource.execute(a.get("node_name", ""), a.get("scene_path", ""), a.get("subresource_property_name", ""), a.get("properties", {}))
		"assign_script":
			ok = AssignScript.execute(a.get("node_name", ""), a.get("scene_path", ""), a.get("script_path", ""))
		"add_existing_scene":
			ok = AddExistingScene.execute(a.get("node_name", ""), a.get("existing_scene_path", ""), a.get("target_scene_path", ""), a.get("parent_path", ""), a.get("modifications", {}))
		"edit_script":
			ok = await EditScript.execute(a)
		"create_image":
			ok = await CreateImage.execute(a.get("options", {}))
		"spritesheet_to_spriteframes":
			ok = SpriteSheetToFrames.execute(a.get("node_name", ""), a.get("scene_path", ""), a.get("options", {}))
		_:
			push_warning("Unrecognized action type: %s" % t)
	action_completed.emit(t, String(a.get("path", a.get("scene_path", ""))), ok, btn)
	if ok:
		btn.text = "✓ " + btn.text
	else:
		btn.self_modulate = Color(1, 0, 0)
		# Emit concise, human-friendly error summary for the chat UI
		match t:
			"create_image":
				action_error_bbcode.emit("[color=red]❌ create_image failed[/color] — check aspect_ratio, output_format, API key, or network. See console for details.")
			"spritesheet_to_spriteframes":
				action_error_bbcode.emit("[color=red]❌ spritesheet_to_spriteframes failed[/color] — missing node, bad texture path, or invalid animations. See console for details.")
			_:
				action_error_bbcode.emit("[color=red]❌ %s failed[/color]. See console for details." % t)
	btn.set_meta("completed", true)
	if t == "edit_script":
		set_disable_for_type.emit(t, false)

func _on_apply_all_pressed() -> void:
	in_apply_all = true
	apply_all_button.disabled = true
	for b in actions_buttons:
		b.disabled = true
	var index := 0
	await _run_next(index, actions_buttons)

func _find_button_for_action(action: Dictionary) -> Button:
	for b in actions_buttons:
		if b.has_meta("action") and b.get_meta("action").hash() == action.hash():
			return b
	return null

func _run_next(idx: int, buttons: Array) -> void:
	if idx >= buttons.size():
		return
	var btn: Button = buttons[idx]
	if not is_instance_valid(btn):
		await get_tree().process_frame
		await _run_next(idx + 1, buttons)
		return
	var on_done = func(_t, _p, _s, done_btn):
		if done_btn == btn:
			await get_tree().create_timer(0.2).timeout
			await _run_next(idx + 1, buttons)
	action_completed.connect(on_done, CONNECT_ONE_SHOT)
	await get_tree().process_frame
	_execute_button(btn) 
