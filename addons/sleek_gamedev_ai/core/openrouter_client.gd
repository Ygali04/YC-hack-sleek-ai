@tool
extends Node
class_name OpenRouterClient

## Enhanced OpenRouter API client supporting multiple model types

const EnvLoader = preload("res://addons/sleek_gamedev_ai/core/env_loader.gd")

signal response_received(response: Dictionary)
signal error_occurred(error_message: String)

const API_URL := "https://openrouter.ai/api/v1/chat/completions"
const MODELS_URL := "https://openrouter.ai/api/v1/models"

var api_key: String = ""
var current_request: HTTPRequest = null

enum ModelType {
	TEXT,
	IMAGE_GENERATION,
	MULTIMODAL,
	REASONING
}

func _ready():
	# Try to get API key from environment or .env file
	var env_key = EnvLoader.get_env_var("OPENROUTER_API_KEY")
	if not env_key.is_empty():
		api_key = env_key
		print("[OpenRouter] API key loaded successfully")
	else:
		print("[OpenRouter] Warning: No API key found in environment or .env file")

func set_api_key(key: String) -> void:
	api_key = key

func is_configured() -> bool:
	return not api_key.is_empty()

## Send a chat completion request to OpenRouter
func chat_completion(model: String, messages: Array, options: Dictionary = {}) -> Dictionary:
	if not is_configured():
		var error = {"error": "API key not configured"}
		error_occurred.emit("OpenRouter API key not configured")
		return error
	
	# Cancel any existing request
	if current_request:
		current_request.queue_free()
	
	current_request = HTTPRequest.new()
	add_child(current_request)
	
	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json",
		"HTTP-Referer: https://godot-ai-plugin.local",
		"X-Title: Godot AI Assistant Plugin"
	]
	
	var body = {
		"model": model,
		"messages": messages
	}
	
	# Add optional parameters
	if options.has("temperature"):
		body["temperature"] = options["temperature"]
	if options.has("max_tokens"):
		body["max_tokens"] = options["max_tokens"]
	if options.has("top_p"):
		body["top_p"] = options["top_p"]
	if options.has("frequency_penalty"):
		body["frequency_penalty"] = options["frequency_penalty"]
	if options.has("presence_penalty"):
		body["presence_penalty"] = options["presence_penalty"]
	if options.has("stream"):
		body["stream"] = options["stream"]
	
	var json_body = JSON.stringify(body)
	
	var error = current_request.request(API_URL, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		var error_dict = {"error": "HTTP request failed: " + str(error)}
		error_occurred.emit("Failed to send request: " + str(error))
		current_request.queue_free()
		current_request = null
		return error_dict
	
	var response = await current_request.request_completed
	var response_code = response[1]
	var response_body = response[3].get_string_from_utf8()
	
	current_request.queue_free()
	current_request = null
	
	return _parse_response(response_code, response_body)

## Fetch available models from OpenRouter
func fetch_models() -> Dictionary:
	if not is_configured():
		var error = {"error": "API key not configured"}
		error_occurred.emit("OpenRouter API key not configured")
		return error
	
	var request = HTTPRequest.new()
	add_child(request)
	
	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	]
	
	var error = request.request(MODELS_URL, headers, HTTPClient.METHOD_GET)
	if error != OK:
		var error_dict = {"error": "Failed to fetch models: " + str(error)}
		error_occurred.emit("Failed to fetch models: " + str(error))
		request.queue_free()
		return error_dict
	
	var response = await request.request_completed
	var response_code = response[1]
	var response_body = response[3].get_string_from_utf8()
	
	request.queue_free()
	
	return _parse_response(response_code, response_body)

## Simple text completion (backwards compatibility)
func ask(model: String, messages: Array) -> String:
	var result = await chat_completion(model, messages)
	
	if result.has("error"):
		return "[Error: " + result["error"] + "]"
	
	if result.has("choices") and result["choices"].size() > 0:
		var choice = result["choices"][0]
		if choice.has("message") and choice["message"].has("content"):
			return choice["message"]["content"]
	
	return "[Error: Invalid API response]"

## Generate image using a compatible model
func generate_image(model: String, prompt: String, options: Dictionary = {}) -> Dictionary:
	var messages = [
		{
			"role": "user",
			"content": prompt
		}
	]
	
	var generation_options = options.duplicate()
	if not generation_options.has("max_tokens"):
		generation_options["max_tokens"] = 1000
	
	return await chat_completion(model, messages, generation_options)

## Handle multimodal input (text + images)
func multimodal_completion(model: String, text_content: String, image_paths: Array = [], options: Dictionary = {}) -> Dictionary:
	var content_parts = []
	
	# Add text content
	if not text_content.is_empty():
		content_parts.append({
			"type": "text",
			"text": text_content
		})
	
	# Add image content
	for image_path in image_paths:
		var image_data = _encode_image_to_base64(image_path)
		if not image_data.is_empty():
			content_parts.append({
				"type": "image_url",
				"image_url": {
					"url": "data:image/jpeg;base64," + image_data
				}
			})
	
	var messages = [
		{
			"role": "user",
			"content": content_parts
		}
	]
	
	return await chat_completion(model, messages, options)

## Determine model type based on model name
func get_model_type(model_name: String) -> ModelType:
	var lower_name = model_name.to_lower()
	
	# Image generation models
	if lower_name.contains("dall-e") or lower_name.contains("dalle") or \
	   lower_name.contains("midjourney") or lower_name.contains("stable-diffusion") or \
	   lower_name.contains("flux"):
		return ModelType.IMAGE_GENERATION
	
	# Reasoning models
	if lower_name.contains("o1") or lower_name.contains("reasoning") or \
	   lower_name.contains("deepseek-r1"):
		return ModelType.REASONING
	
	# Multimodal models (vision capable)
	if lower_name.contains("vision") or lower_name.contains("gpt-4") and lower_name.contains("vision") or \
	   lower_name.contains("claude-3") or lower_name.contains("gemini") and lower_name.contains("pro"):
		return ModelType.MULTIMODAL
	
	# Default to text
	return ModelType.TEXT

func _parse_response(response_code: int, response_body: String) -> Dictionary:
	if response_code >= 200 and response_code < 300:
		var parsed = JSON.parse_string(response_body)
		if parsed != null and typeof(parsed) == TYPE_DICTIONARY:
			# Extract reasoning traces for reasoning models
			_extract_reasoning_traces(parsed)
			response_received.emit(parsed)
			return parsed
		else:
			var error = {"error": "Invalid JSON response"}
			error_occurred.emit("Invalid JSON response")
			return error
	else:
		var error_message = "HTTP Error " + str(response_code)
		var parsed = JSON.parse_string(response_body)
		if parsed != null and typeof(parsed) == TYPE_DICTIONARY:
			if parsed.has("error"):
				if typeof(parsed["error"]) == TYPE_DICTIONARY and parsed["error"].has("message"):
					error_message += ": " + parsed["error"]["message"]
				else:
					error_message += ": " + str(parsed["error"])
		
		var error = {"error": error_message}
		error_occurred.emit(error_message)
		return error

func _extract_reasoning_traces(response: Dictionary):
	# Look for reasoning traces in various places where they might be stored
	var reasoning_content = ""
	
	if response.has("choices") and response["choices"].size() > 0:
		var choice = response["choices"][0]
		# Check for reasoning in message content (some models embed it)
		if choice.has("message") and choice["message"].has("content"):
			var content = choice["message"]["content"]
			# Extract ALL reasoning blocks fully between known tags
			var blocks = _extract_all_reasoning_blocks(content)
			if blocks.size() > 0:
				reasoning_content = "\n\n".join(blocks)
		# Check for reasoning in separate fields
		if reasoning_content.is_empty() and (choice.has("reasoning") or choice.has("thinking") or choice.has("trace")):
			reasoning_content = choice.get("reasoning", choice.get("thinking", choice.get("trace", "")))
		# Check message-level reasoning fields
		if reasoning_content.is_empty() and choice.has("message"):
			var message = choice["message"]
			if message.has("reasoning") or message.has("thinking") or message.has("trace"):
				reasoning_content = message.get("reasoning", message.get("thinking", message.get("trace", "")))
	# Check top-level reasoning fields
	if reasoning_content.is_empty():
		reasoning_content = response.get("reasoning", response.get("thinking", response.get("trace", "")))
	# Emit reasoning trace if found
	if not reasoning_content.is_empty():
		print("[OpenRouter] Found reasoning trace (", reasoning_content.length(), " chars)")
		reasoning_content = reasoning_content.strip_edges()
		if not has_signal("reasoning_trace_received"):
			add_user_signal("reasoning_trace_received", [{"name": "trace", "type": TYPE_STRING}])
		emit_signal("reasoning_trace_received", reasoning_content)
	else:
		print("[OpenRouter] No reasoning trace found in response")

func _extract_reasoning_from_content(content: String) -> String:
	# Legacy single-block extraction retained for compatibility, but prefer _extract_all_reasoning_blocks
	var blocks = _extract_all_reasoning_blocks(content)
	if blocks.size() > 0:
		return blocks[0]
	return ""

func _extract_all_reasoning_blocks(content: String) -> Array:
	# Return all inner texts between <think>...</think>, <thinking>...</thinking>, <reasoning>...</reasoning>
	var out: Array = []
	var tag_pairs = [["<think>", "</think>"], ["<thinking>", "</thinking>"], ["<reasoning>", "</reasoning>"]]
	for pair in tag_pairs:
		var start_tag: String = pair[0]
		var end_tag: String = pair[1]
		var idx := 0
		while true:
			var s = content.find(start_tag, idx)
			if s == -1:
				break
			var e = content.find(end_tag, s + start_tag.length())
			if e == -1:
				# No closing tag; take to end
				var inner = content.substr(s + start_tag.length(), content.length() - (s + start_tag.length()))
				out.append(inner)
				break
			else:
				var inner_len = e - (s + start_tag.length())
				if inner_len > 0:
					out.append(content.substr(s + start_tag.length(), inner_len))
				idx = e + end_tag.length()
	return out

func _encode_image_to_base64(image_path: String) -> String:
	if not FileAccess.file_exists(image_path):
		print("[OpenRouter] Warning: Image file not found: ", image_path)
		return ""
	
	var file = FileAccess.open(image_path, FileAccess.READ)
	if not file:
		print("[OpenRouter] Warning: Could not open image file: ", image_path)
		return ""
	
	var image_data = file.get_buffer(file.get_length())
	file.close()
	
	return Marshalls.raw_to_base64(image_data) 
