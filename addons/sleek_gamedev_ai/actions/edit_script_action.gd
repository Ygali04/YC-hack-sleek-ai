@tool
extends Node

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

# This action expects updated content embedded in the assistant message, or provided externally.
static func write_and_refresh(path: String, content: String) -> bool:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()
		var ei = EditorPlugin.new().get_editor_interface()
		ei.get_resource_filesystem().scan()
		await Engine.get_main_loop().process_frame
		var script = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
		ei.edit_script(script)
		return true
	return false

static func execute(action: Dictionary) -> bool:
	var path: String = action.get("path", "")
	var new_content: String = action.get("new_content", "")
	if path == "" or new_content == "":
		push_error("edit_script missing path or new_content")
		return false
	return await write_and_refresh(path, new_content)

static func parse_line(line: String, full_text: String) -> Dictionary:
	if line.begins_with("edit_script("):
		var args = Utils.parse_edit_script_args(line)
		if not args.is_empty():
			var path = args.get("path", "")
			var updated = _extract_updated_content_for_path(full_text, path)
			return {
				"type": "edit_script",
				"path": path,
				"message_id": args.get("message_id", -1),
				"new_content": updated
			}
	return {}

static func _extract_updated_content_for_path(text: String, path: String) -> String:
	# Try multiple markers: Updated file / File / New file
	var patterns = [
		"```.*\\n# Updated file: "+path+"\\n([\\s\\S]*?)```",
		"```.*\\n# File: "+path+"\\n([\\s\\S]*?)```",
		"```.*\\n# New file: "+path+"\\n([\\s\\S]*?)```",
		"```gd\\n([\\s\\S]*?)```",
		"```\\n([\\s\\S]*?)```"
	]
	for p in patterns:
		var re := RegEx.new(); re.compile(p)
		var m = re.search(text)
		if m:
			return m.get_string(1).strip_edges()
	return "" 