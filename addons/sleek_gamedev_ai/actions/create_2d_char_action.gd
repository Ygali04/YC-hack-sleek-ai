@tool
extends Node

const Orchestrator = preload("res://addons/sleek_gamedev_ai/actions/create_character_from_prompt_action.gd")
const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(prompt: String, opts: Dictionary = {}) -> bool:
	return await Orchestrator.execute(prompt, opts)

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("create_2d_char("):
		var body = line.replace("create_2d_char(", "").rstrip(")").strip_edges()
		var prompt := ""
		var opts := {}
		if body.begins_with("\""):
			var b = body.find("\"", 1)
			if b != -1:
				prompt = body.substr(1, b - 1)
				var rest = body.substr(b + 1).strip_edges().trim_prefix(",").strip_edges()
				if rest != "":
					opts = Utils.parse_object_map(rest)
		else:
			opts = Utils.parse_object_map(body)
		return {"type": "create_2d_char", "prompt": prompt, "options": opts}
	return {} 