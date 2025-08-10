@tool
extends Node

static func execute() -> void:
	if Engine.is_editor_hint():
		var ei = EditorPlugin.new().get_editor_interface()
		# Play the main scene
		ei.play_main_scene()

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("run_project("):
		return {"type": "run_project"}
	return {} 