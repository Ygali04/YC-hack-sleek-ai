@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(path: String, content: String) -> bool:
	path = Utils.normalize_res_path(path)
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()
		if Engine.is_editor_hint():
			EditorPlugin.new().get_editor_interface().get_resource_filesystem().scan()
		return true
	push_error("create_file: failed to open '%s' for writing" % path)
	return false

static func parse_line(line: String, full_text: String) -> Dictionary:
	# Accept both strict and lenient forms:
	# 1) create_file("res://path") with a matching '# New file: res://path' block
	# 2) create_file (no args) and infer the first '# New file: <path>' in the message
	if line.begins_with("create_file"):
		if line.begins_with("create_file("):
			var path = Utils.extract_quoted_string(line)
			return {
				"type": "create_file",
				"path": path,
				"content": Utils.extract_block_for_new_file(path, full_text)
			}
		else:
			# Try to infer path from the first '# New file:' marker
			var re := RegEx.new()
			re.compile("# New file: ([^\n\r]+)")
			var m := re.search(full_text)
			if m:
				var inferred_path = m.get_string(1).strip_edges()
				return {
					"type": "create_file",
					"path": inferred_path,
					"content": Utils.extract_block_for_new_file(inferred_path, full_text)
				}
	return {} 