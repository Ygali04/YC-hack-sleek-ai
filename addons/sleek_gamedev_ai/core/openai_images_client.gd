@tool
class_name OpenAIImagesClient
extends Node

signal error_occurred(message: String)

@export var api_base: String = "https://api.openai.com/v1"
var api_key: String = ""
var organization: String = ""

# When true, remove background from all generated images
@export var auto_remove_background: bool = true
@export var background_tolerance: float = 0.08  # 0..1 color distance threshold

static func write_png_to_res(bytes: PackedByteArray, prefix: String = "img") -> String:
	if bytes.is_empty():
		return ""
	var dir := "res://art/generated"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var ts := str(Time.get_unix_time_from_system())
	var path := "%s/%s_%s.png" % [dir, prefix, ts]
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()
		if Engine.is_editor_hint():
			EditorPlugin.new().get_editor_interface().get_resource_filesystem().scan()
		return path
	return ""

static func write_bytes_to_res_named(bytes: PackedByteArray, absolute_res_path: String) -> String:
	if bytes.is_empty():
		return ""
	var dir = absolute_res_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f = FileAccess.open(absolute_res_path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()
		if Engine.is_editor_hint():
			EditorPlugin.new().get_editor_interface().get_resource_filesystem().scan()
		return absolute_res_path
	return ""

static func load_texture_from_png_bytes(bytes: PackedByteArray) -> Texture2D:
	var img := Image.new()
	var err = img.load_png_from_buffer(bytes)
	if err == OK:
		return ImageTexture.create_from_image(img)
	return null

func _do_json_post(path: String, body: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	var parent_for_req: Node = null
	if is_inside_tree():
		parent_for_req = self
	else:
		var ml = Engine.get_main_loop()
		if ml is SceneTree:
			parent_for_req = (ml as SceneTree).root
	if parent_for_req == null:
		error_occurred.emit("No SceneTree available for HTTPRequest")
		return {"error": "no_scene_tree"}
	parent_for_req.add_child(req)
	var url = api_base.trim_suffix("/") + path
	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json",
		"Accept: application/json"
	])
	if organization != "":
		headers.append("OpenAI-Organization: " + organization)
	var body_str := JSON.stringify(body)
	var err = req.request(url, headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		error_occurred.emit("Failed to start request: " + str(err))
		req.queue_free()
		return {"error": str(err)}
	var result = await req.request_completed
	req.queue_free()
	return {
		"code": result[1],
		"headers": result[2],
		"body": result[3]
	}

# --- Background removal utilities ---
static func _color_distance(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2.0) + pow(a.g - b.g, 2.0) + pow(a.b - b.b, 2.0))

static func _pick_background_color(img: Image) -> Color:
	# Sample corners and a few edge points; choose the most common within small tolerance
	var samples: Array[Color] = []
	var w = img.get_width()
	var h = img.get_height()
	samples.append(img.get_pixel(0, 0))
	samples.append(img.get_pixel(w - 1, 0))
	samples.append(img.get_pixel(0, h - 1))
	samples.append(img.get_pixel(w - 1, h - 1))
	samples.append(img.get_pixel(w / 2, 0))
	samples.append(img.get_pixel(w / 2, h - 1))
	samples.append(img.get_pixel(0, h / 2))
	samples.append(img.get_pixel(w - 1, h / 2))
	# Simple majority by grouping close colors
	var groups: Array = []  # [color, count]
	for c in samples:
		var matched = false
		for g in groups:
			if _color_distance(c, g[0]) < 0.03:
				g[1] += 1
				matched = true
				break
		if not matched:
			groups.append([c, 1])
	groups.sort_custom(func(a, b): return a[1] > b[1])
	return groups[0][0]

static func remove_background_from_png_bytes(bytes: PackedByteArray, tolerance: float = 0.08) -> PackedByteArray:
	if bytes.is_empty():
		return bytes
	var img := Image.new()
	var err = img.load_png_from_buffer(bytes)
	if err != OK:
		return bytes
	img.convert(Image.FORMAT_RGBA8)
	# If image already has transparency, keep as is
	var transparent_count := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a < 0.99:
				transparent_count += 1
				if transparent_count > 1000:
					break
		if transparent_count > 1000:
			break
	if transparent_count <= 1000:
		var bg := _pick_background_color(img)
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c = img.get_pixel(x, y)
				if _color_distance(c, bg) <= tolerance:
					img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
	# Return new PNG bytes
	return img.save_png_to_buffer()

func generate_image(prompt: String, size: String = "1024x1024", background: String = "transparent", quality: String = "high", remove_bg: bool = true, tolerance: float = -1.0) -> PackedByteArray:
	if api_key == "":
		error_occurred.emit("Missing OPENAI_API_KEY")
		return PackedByteArray()
	var payload := {
		"model": "gpt-image-1",
		"prompt": prompt,
		"size": size,
		"background": background,
		"quality": quality
	}
	var res = await _do_json_post("/images/generations", payload)
	var code = int(res.get("code", 0))
	var body_val = res.get("body", PackedByteArray())
	var body_text := ""
	if typeof(body_val) == TYPE_PACKED_BYTE_ARRAY:
		body_text = (body_val as PackedByteArray).get_string_from_utf8()
	elif typeof(body_val) == TYPE_STRING:
		body_text = String(body_val)
	if code != 200:
		error_occurred.emit("OpenAI images failed: HTTP " + str(code) + " " + body_text)
		return PackedByteArray()
	var parsed = JSON.parse_string(body_text)
	if parsed and typeof(parsed) == TYPE_DICTIONARY and parsed.has("data"):
		var arr = parsed["data"]
		if typeof(arr) == TYPE_ARRAY and arr.size() > 0 and typeof(arr[0]) == TYPE_DICTIONARY and arr[0].has("b64_json"):
			var bytes := Marshalls.base64_to_raw(arr[0]["b64_json"])
			# Auto remove background if requested
			var do_remove := remove_bg or auto_remove_background
			var tol := background_tolerance
			if tolerance >= 0.0:
				tol = tolerance
			if do_remove:
				return remove_background_from_png_bytes(bytes, tol)
			return bytes
	error_occurred.emit("OpenAI images: unexpected response")
	return PackedByteArray() 