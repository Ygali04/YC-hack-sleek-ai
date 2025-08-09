@tool
extends Node

const EnvLoader = preload("res://addons/sleek_gamedev_ai/core/env_loader.gd")
const StabilityClient = preload("res://addons/sleek_gamedev_ai/core/stability_client.gd")
const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

# Usage example inside [gds_actions]:
# create_image({ prompt: "pixel art mario idle", aspect_ratio: "1:1", seed: 0, output_format: "png", output_prefix: "mario_idle" })
# create_image({ prompt: "...", exact_output_path: "res://art/mario_idle_12345.png" })
# Default model: sd3.5-large (override with { model: "sd3.5-flash" })

static func _parse_value(v):
	if v is String:
		var s: String = v.strip_edges()
		if s.to_lower() == "true":
			return true
		if s.to_lower() == "false":
			return false
		if s.is_valid_float():
			return float(s)
		return s
	return v

static func _is_valid_aspect_ratio(ar: String) -> bool:
	# Basic pattern check
	var re := RegEx.new()
	re.compile("^\\d+:\\d+$")
	if re.search(ar) == null:
		return false
	# Commonly supported aspect ratios for Stability sd3/sd3.5
	var allowed := [
		"1:1", "3:2", "2:3", "4:3", "3:4", "5:4", "4:5",
		"16:9", "9:16", "21:9", "9:21", "7:5", "5:7"
	]
	return ar in allowed

static func execute(opts: Dictionary) -> bool:
	var prompt := String(opts.get("prompt", ""))
	var aspect_ratio := String(opts.get("aspect_ratio", "1:1"))
	var seed := int(_parse_value(opts.get("seed", 0)))
	var output_format := String(opts.get("output_format", "png")).to_lower()
	var prefix := String(opts.get("output_prefix", "img"))
	var exact_path := String(opts.get("exact_output_path", ""))
	var model := String(opts.get("model", "sd3.5-large")).to_lower()
	if prompt == "":
		push_error("create_image: missing 'prompt'")
		return false
	if not _is_valid_aspect_ratio(aspect_ratio):
		push_error("create_image: unsupported aspect_ratio '%s' (try one of: 1:1, 3:2, 2:3, 4:3, 3:4, 5:4, 4:5, 16:9, 9:16, 21:9, 9:21, 7:5, 5:7)" % aspect_ratio)
		return false
	if output_format != "png" and output_format != "jpeg" and output_format != "jpg":
		push_error("create_image: unsupported output_format '%s' (use 'png' or 'jpeg')" % output_format)
		return false
	var client: StabilityClient = StabilityClient.new()
	client.api_key = EnvLoader.get_env_var("STABILITY_API_KEY")
	client.error_occurred.connect(func(message: String):
		push_error("create_image: " + message)
	)
	if client.api_key == "":
		push_error("create_image: STABILITY_API_KEY not set. Add it to environment or .env")
		return false
	var bytes: PackedByteArray
	match model:
		"sd3.5-flash":
			bytes = await client.text_to_image_sd35_flash(prompt, aspect_ratio, seed, output_format)
		"sd3.5-large":
			bytes = await client.text_to_image_sd35_large(prompt, aspect_ratio, seed, output_format)
		_:
			# Default to large for unknown values
			bytes = await client.text_to_image_sd35_large(prompt, aspect_ratio, seed, output_format)
	if bytes.is_empty():
		push_error("create_image: image generation failed (see previous error)")
		return false
	# Enforce deterministic exact path if not provided by the model
	if exact_path == "":
		var ext: String
		if output_format == "jpeg" or output_format == "jpg":
			ext = "jpeg"
		else:
			ext = "png"
		var suffix := str(seed)
		if seed <= 0:
			suffix = str(Time.get_unix_time_from_system())
		exact_path = "res://art/generated/%s_%s.%s" % [prefix, suffix, ext]
	exact_path = Utils.normalize_res_path(exact_path)
	var saved_path: String = StabilityClient.write_bytes_to_res_named(bytes, exact_path)
	if saved_path == "":
		push_error("create_image: failed to save image to '%s'" % exact_path)
		return false
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("create_image("):
		var open_i = line.find("{")
		var close_i = line.rfind("}")
		if open_i == -1 or close_i == -1:
			return {}
		var map_text = line.substr(open_i, close_i - open_i + 1)
		var props = Utils.parse_object_map(map_text)
		return {"type": "create_image", "options": props}
	return {} 