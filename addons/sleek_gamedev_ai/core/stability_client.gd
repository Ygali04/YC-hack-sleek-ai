@tool
extends Node
class_name StabilityClient

signal error_occurred(message: String)

@export var api_base: String = "https://api.stability.ai"
@export var api_key: String = ""

# Shared request helper
func _make_headers(accept_png: bool = true) -> PackedStringArray:
	var headers := PackedStringArray()
	headers.append("Authorization: Bearer " + api_key)
	headers.append("Content-Type: application/json")
	if accept_png:
		headers.append("Accept: image/png")
	else:
		headers.append("Accept: application/json")
	return headers

func _do_json_post(path: String, body: Dictionary, accept_image: bool = true, accept_format: String = "png") -> Dictionary:
	var req := HTTPRequest.new()
	# Ensure the HTTPRequest is inside the scene tree
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
	var json = JSON.stringify(body)
	var headers := PackedStringArray(["Authorization: Bearer " + api_key, "Content-Type: application/json"])
	if accept_image:
		if accept_format.to_lower() == "jpeg" or accept_format.to_lower() == "jpg":
			headers.append("Accept: image/jpeg")
		else:
			headers.append("Accept: image/png")
	else:
		headers.append("Accept: application/json")
	var err = req.request(url, headers, HTTPClient.METHOD_POST, json)
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

# Text-to-image (SD3 v2beta) – returns PNG bytes if Accept: image/png
# Docs: https://platform.stability.ai/docs/api-reference#tag/Generate/paths/~1v2beta~1stable-image~1generate~1sd3/post
func text_to_image_sd3(prompt: String, negative_prompt: String, width: int, height: int, steps: int, guidance: float, seed: int, model: String = "sd3") -> PackedByteArray:
	var body := {
		"prompt": prompt,
		"negative_prompt": negative_prompt,
		"width": width,
		"height": height,
		"steps": steps,
		"cfg_scale": guidance,
		"seed": seed,
		"model": model,
		"output_format": "png"
	}
	var res = await _do_json_post("/v2beta/stable-image/generate/sd3", body, true, "png")
	if int(res.get("code", 0)) == 200:
		return res["body"] # image bytes
	# Try JSON base64 fallback
	var body_val = res.get("body", PackedByteArray())
	var body_text := ""
	if typeof(body_val) == TYPE_PACKED_BYTE_ARRAY:
		body_text = (body_val as PackedByteArray).get_string_from_utf8()
	elif typeof(body_val) == TYPE_STRING:
		body_text = String(body_val)
	var parsed = JSON.parse_string(body_text)
	if parsed and typeof(parsed) == TYPE_DICTIONARY and parsed.has("image"):
		return Marshalls.base64_to_raw(parsed["image"])
	error_occurred.emit("Stability text_to_image failed: HTTP " + str(res.get("code", -1)))
	return PackedByteArray()


# Image-to-image (generic JSON posting with base64 init image) – engine configurable
# Note: Some endpoints require multipart; adjust if needed per docs.
func image_to_image(engine_path: String, init_image_b64: String, prompt: String, strength: float, steps: int, guidance: float, seed: int) -> PackedByteArray:
	var body := {
		"init_image": init_image_b64,
		"prompt": prompt,
		"image_strength": strength,
		"steps": steps,
		"cfg_scale": guidance,
		"seed": seed,
		"output_format": "png"
	}
	var res = await _do_json_post(engine_path, body, true)
	if int(res.get("code", 0)) == 200:
		return res["body"]
	var body_val = res.get("body", PackedByteArray())
	var body_text := ""
	if typeof(body_val) == TYPE_PACKED_BYTE_ARRAY:
		body_text = (body_val as PackedByteArray).get_string_from_utf8()
	elif typeof(body_val) == TYPE_STRING:
		body_text = String(body_val)
	var parsed = JSON.parse_string(body_text)
	if parsed and typeof(parsed) == TYPE_DICTIONARY and parsed.has("image"):
		return Marshalls.base64_to_raw(parsed["image"])
	error_occurred.emit("Stability image_to_image failed: HTTP " + str(res.get("code", -1)))
	return PackedByteArray()

# Edit image (inpainting/outpainting) with optional mask – pass init_image_b64 and mask_b64
func edit_image_sd3(init_image_b64: String, mask_b64: String, prompt: String, steps: int, guidance: float, seed: int) -> PackedByteArray:
	var body := {
		"prompt": prompt,
		"init_image": init_image_b64,
		"mask": mask_b64,
		"steps": steps,
		"cfg_scale": guidance,
		"seed": seed,
		"output_format": "png"
	}
	var res = await _do_json_post("/v2beta/stable-image/edit/sd3", body, true)
	if int(res.get("code", 0)) == 200:
		return res["body"]
	var body_val = res.get("body", PackedByteArray())
	var body_text := ""
	if typeof(body_val) == TYPE_PACKED_BYTE_ARRAY:
		body_text = (body_val as PackedByteArray).get_string_from_utf8()
	elif typeof(body_val) == TYPE_STRING:
		body_text = String(body_val)
	var parsed = JSON.parse_string(body_text)
	if parsed and typeof(parsed) == TYPE_DICTIONARY and parsed.has("image"):
		return Marshalls.base64_to_raw(parsed["image"])
	error_occurred.emit("Stability edit_image failed: HTTP " + str(res.get("code", -1)))
	return PackedByteArray()

# Structure/Sketch control – control image as base64
func structure_sketch_sd3(prompt: String, control_b64: String, steps: int, guidance: float, seed: int) -> PackedByteArray:
	var body := {
		"prompt": prompt,
		"control_image": control_b64,
		"steps": steps,
		"cfg_scale": guidance,
		"seed": seed,
		"output_format": "png"
	}
	var res = await _do_json_post("/v2beta/stable-image/control/sd3", body, true)
	if int(res.get("code", 0)) == 200:
		return res["body"]
	var body_val = res.get("body", PackedByteArray())
	var body_text := ""
	if typeof(body_val) == TYPE_PACKED_BYTE_ARRAY:
		body_text = (body_val as PackedByteArray).get_string_from_utf8()
	elif typeof(body_val) == TYPE_STRING:
		body_text = String(body_val)
	var parsed = JSON.parse_string(body_text)
	if parsed and typeof(parsed) == TYPE_DICTIONARY and parsed.has("image"):
		return Marshalls.base64_to_raw(parsed["image"])
	error_occurred.emit("Stability structure_sketch failed: HTTP " + str(res.get("code", -1)))
	return PackedByteArray()

# Helpers
static func file_to_base64(path: String) -> String:
	var data = FileAccess.get_file_as_bytes(path)
	return Marshalls.raw_to_base64(data)

static func write_png_to_res(bytes: PackedByteArray, file_name_prefix: String = "gen") -> String:
	if bytes.is_empty():
		return ""
	var dir = "res://art/generated"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var ts = Time.get_unix_time_from_system()
	var path = dir + "/" + file_name_prefix + "_" + str(ts) + ".png"
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()
		if Engine.is_editor_hint():
			EditorPlugin.new().get_editor_interface().get_resource_filesystem().scan()
		return path
	return ""

static func write_bytes_to_res(bytes: PackedByteArray, file_name_prefix: String = "gen", extension: String = "png") -> String:
	if bytes.is_empty():
		return ""
	var dir = "res://art/generated"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var ts = Time.get_unix_time_from_system()
	var ext = extension.to_lower()
	if ext == "jpg":
		ext = "jpeg"
	var path = dir + "/" + file_name_prefix + "_" + str(ts) + "." + ext
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
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
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

# --- New helpers for multipart and header parsing ---
func _get_header(headers: PackedStringArray, key: String) -> String:
	var lc = key.to_lower() + ":"
	for h in headers:
		var hs = String(h)
		if hs.to_lower().begins_with(lc):
			return hs.substr(hs.find(":") + 1).strip_edges()
	return ""

func _do_multipart_form_post(path: String, fields: Dictionary, accept_image: bool = true) -> Dictionary:
	var req := HTTPRequest.new()
	# Ensure the HTTPRequest is inside the scene tree
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
	# Build multipart body
	var boundary = "----GodotBoundary" + str(Time.get_unix_time_from_system())
	var body := PackedByteArray()
	for k in fields.keys():
		var v = fields[k]
		var part = "--" + boundary + "\r\n"
		part += "Content-Disposition: form-data; name=\"" + k + "\"\r\n\r\n"
		part += str(v) + "\r\n"
		body.append_array(part.to_utf8_buffer())
	var closing = "--" + boundary + "--\r\n"
	body.append_array(closing.to_utf8_buffer())
	var headers := PackedStringArray(["Authorization: Bearer " + api_key, "Content-Type: multipart/form-data; boundary=" + boundary])
	if accept_image:
		headers.append("Accept: image/*")
	else:
		headers.append("Accept: application/json")
	var err = req.request_raw(url, headers, HTTPClient.METHOD_POST, body)
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

# SD3.5-Flash – aspect_ratio + output_format, now multipart per official sample
func text_to_image_sd35_flash(prompt: String, aspect_ratio: String = "1:1", seed: int = 0, output_format: String = "png") -> PackedByteArray:
	var fields := {
		"prompt": prompt,
		"aspect_ratio": aspect_ratio,
		"seed": str(seed),
		"output_format": output_format,
		"model": "sd3.5-flash"
	}
	var res = await _do_multipart_form_post("/v2beta/stable-image/generate/sd3", fields, true)
	var code = int(res.get("code", 0))
	if code == 200:
		# Expect raw image bytes
		return res["body"]
	# Fallback: parse JSON for base64
	var body_val = res.get("body", PackedByteArray())
	var body_text := ""
	if typeof(body_val) == TYPE_PACKED_BYTE_ARRAY:
		body_text = (body_val as PackedByteArray).get_string_from_utf8()
	elif typeof(body_val) == TYPE_STRING:
		body_text = String(body_val)
	var parsed = JSON.parse_string(body_text)
	if parsed and typeof(parsed) == TYPE_DICTIONARY and parsed.has("image"):
		return Marshalls.base64_to_raw(parsed["image"])
	error_occurred.emit("Stability sd3.5-flash failed: HTTP " + str(res.get("code", -1)))
	return PackedByteArray()

# SD3.5-Large – aspect_ratio + output_format, multipart
func text_to_image_sd35_large(prompt: String, aspect_ratio: String = "1:1", seed: int = 0, output_format: String = "png") -> PackedByteArray:
	var fields := {
		"prompt": prompt,
		"aspect_ratio": aspect_ratio,
		"seed": str(seed),
		"output_format": output_format,
		"model": "sd3.5-large"
	}
	var res = await _do_multipart_form_post("/v2beta/stable-image/generate/sd3", fields, true)
	var code = int(res.get("code", 0))
	if code == 200:
		return res["body"]
	var body_val = res.get("body", PackedByteArray())
	var body_text := ""
	if typeof(body_val) == TYPE_PACKED_BYTE_ARRAY:
		body_text = (body_val as PackedByteArray).get_string_from_utf8()
	elif typeof(body_val) == TYPE_STRING:
		body_text = String(body_val)
	var parsed = JSON.parse_string(body_text)
	if parsed and typeof(parsed) == TYPE_DICTIONARY and parsed.has("image"):
		return Marshalls.base64_to_raw(parsed["image"])
	error_occurred.emit("Stability sd3.5-large failed: HTTP " + str(res.get("code", -1)))
	return PackedByteArray() 