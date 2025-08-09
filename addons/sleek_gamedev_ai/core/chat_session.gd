@tool
extends Node
class_name ChatSession

## Enhanced chat session supporting multiple model types and multimodal interactions

signal assistant_message(text: String, metadata: Dictionary)
signal error_occurred(error_message: String)
signal typing_started
signal typing_finished

const OpenRouterClient = preload("res://addons/sleek_gamedev_ai/core/openrouter_client.gd")
const ModelRegistry = preload("res://addons/sleek_gamedev_ai/core/model_registry.gd")

var client: OpenRouterClient
var model_registry: ModelRegistry
var current_model: Dictionary = {}
var messages: Array = []
var attachments: Array = []  # Array of file paths
var image_attachments: Array = []  # Array of image file paths for multimodal

# Chat session settings
var session_id: String = ""
var session_title: String = "New Chat"
var creation_time: float
var model_settings: Dictionary = {
	"temperature": 0.7,
	"max_tokens": 4096,
	"top_p": 0.9
}

func _init():
	creation_time = Time.get_unix_time_from_system()
	session_id = _generate_session_id()

func _ready():
	# Connect client signals if available
	if client:
		_connect_client_signals()

func configure(openrouter_client: OpenRouterClient, model_data: Dictionary, registry: ModelRegistry = null):
	client = openrouter_client
	current_model = model_data
	model_registry = registry
	
	if client:
		_connect_client_signals()

func _connect_client_signals():
	if client.response_received.is_connected(_on_response_received):
		client.response_received.disconnect(_on_response_received)
	if client.error_occurred.is_connected(_on_error_occurred):
		client.error_occurred.disconnect(_on_error_occurred)
	
	client.response_received.connect(_on_response_received)
	client.error_occurred.connect(_on_error_occurred)
	
	# Connect to reasoning trace signal if it exists
	if client.has_signal("reasoning_trace_received"):
		if client.reasoning_trace_received.is_connected(_on_reasoning_trace_received):
			client.reasoning_trace_received.disconnect(_on_reasoning_trace_received)
		client.reasoning_trace_received.connect(_on_reasoning_trace_received)

func set_model(model_data: Dictionary):
	current_model = model_data
	print("[ChatSession] Switched to model: ", model_data.get("name", "Unknown"))

func add_text_attachment(file_path: String):
	if file_path not in attachments:
		attachments.append(file_path)
		print("[ChatSession] Added text attachment: ", file_path)

func add_image_attachment(file_path: String):
	if _is_image_file(file_path) and file_path not in image_attachments:
		image_attachments.append(file_path)
		print("[ChatSession] Added image attachment: ", file_path)
	else:
		print("[ChatSession] Warning: Not a valid image file: ", file_path)

func clear_attachments():
	attachments.clear()
	image_attachments.clear()
	print("[ChatSession] All attachments cleared")

func clear_text_attachments():
	attachments.clear()
	print("[ChatSession] Text attachments cleared")

func clear_image_attachments():
	image_attachments.clear()
	print("[ChatSession] Image attachments cleared")

func get_attachment_count() -> int:
	return attachments.size() + image_attachments.size()

func has_multimodal_content() -> bool:
	return image_attachments.size() > 0

## Send a message with the current model
func ask(user_text: String) -> void:
	if current_model.is_empty():
		emit_signal("error_occurred", "No model selected")
		return
	
	if not client or not client.is_configured():
		emit_signal("error_occurred", "OpenRouter client not configured")
		return
	
	# Add user message to history
	var user_message = {"role": "user", "content": user_text, "timestamp": Time.get_time_dict_from_system()}
	messages.append(user_message)
	
	emit_signal("typing_started")
	
	# Determine the appropriate method based on model type and content
	await _send_message_by_type(user_text)

func _send_message_by_type(user_text: String):
	var model_type = _get_model_type()
	var enhanced_text = _prepare_enhanced_message(user_text)
	
	match model_type:
		OpenRouterClient.ModelType.IMAGE_GENERATION:
			await _handle_image_generation(enhanced_text)
		
		OpenRouterClient.ModelType.MULTIMODAL:
			if has_multimodal_content():
				await _handle_multimodal_request(enhanced_text)
			else:
				await _handle_text_request(enhanced_text)
		
		OpenRouterClient.ModelType.REASONING:
			await _handle_reasoning_request(enhanced_text)
		
		_:
			await _handle_text_request(enhanced_text)

func _handle_text_request(text: String):
	var result = await client.chat_completion(current_model["id"], messages, model_settings)
	_process_response(result)

func _handle_multimodal_request(text: String):
	var result = await client.multimodal_completion(
		current_model["id"],
		text,
		image_attachments,
		model_settings
	)
	_process_response(result)

func _handle_image_generation(prompt: String):
	var generation_settings = model_settings.duplicate()
	generation_settings["max_tokens"] = 1000  # Image generation typically needs fewer tokens
	
	var result = await client.generate_image(current_model["id"], prompt, generation_settings)
	_process_image_generation_response(result)

func _handle_reasoning_request(text: String):
	var reasoning_settings = model_settings.duplicate()
	reasoning_settings["temperature"] = 0.3  # Lower temperature for reasoning
	reasoning_settings["max_tokens"] = 8192  # More tokens for reasoning steps
	
	# For reasoning models, try to enable special reasoning features
	if "deepseek" in current_model.get("id", "").to_lower():
		reasoning_settings["enable_reasoning"] = true
		reasoning_settings["show_reasoning"] = true
	
	var result = await client.chat_completion(current_model["id"], messages, reasoning_settings)
	_process_response(result)

func _process_response(result: Dictionary):
	emit_signal("typing_finished")
	
	if result.has("error"):
		emit_signal("error_occurred", result["error"])
		return
	
	if result.has("choices") and result["choices"].size() > 0:
		var choice = result["choices"][0]
		if choice.has("message") and choice["message"].has("content"):
			var response_text = choice["message"]["content"]
			var metadata = _extract_response_metadata(result)
			
			# Add AI message to history
			var ai_message = {
				"role": "assistant", 
				"content": response_text, 
				"timestamp": Time.get_time_dict_from_system(),
				"metadata": metadata
			}
			messages.append(ai_message)
			
			# Clear attachments after successful response
			clear_attachments()
			
			emit_signal("assistant_message", response_text, metadata)
		else:
			emit_signal("error_occurred", "Invalid response format")
	else:
		emit_signal("error_occurred", "No response received")

func _process_image_generation_response(result: Dictionary):
	emit_signal("typing_finished")
	
	if result.has("error"):
		emit_signal("error_occurred", result["error"])
		return
	
	# Handle image generation response
	# This might contain URLs or base64 data depending on the model
	var response_text = "Image generated successfully!"
	var metadata = _extract_response_metadata(result)
	metadata["type"] = "image_generation"
	
	# Add AI message to history
	var ai_message = {
		"role": "assistant", 
		"content": response_text, 
		"timestamp": Time.get_time_dict_from_system(),
		"metadata": metadata
	}
	messages.append(ai_message)
	
	clear_attachments()
	emit_signal("assistant_message", response_text, metadata)

func _prepare_enhanced_message(user_text: String) -> String:
	var enhanced_message = user_text
	
	# Add text file attachments
	if attachments.size() > 0:
		enhanced_message += "\n\nAttached files:\n"
		for file_path in attachments:
			var file_name = file_path.get_file()
			var file_content = _read_file_content(file_path)
			enhanced_message += "--- %s ---\n%s\n\n" % [file_name, file_content]
	
	return enhanced_message

func _read_file_content(file_path: String) -> String:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		return content
	return "[Error reading file: " + file_path + "]"

func _is_image_file(file_path: String) -> bool:
	var extension = file_path.get_extension().to_lower()
	return extension in ["png", "jpg", "jpeg", "gif", "bmp", "webp", "svg"]

func _get_model_type() -> OpenRouterClient.ModelType:
	if client and current_model.has("id"):
		return client.get_model_type(current_model["id"])
	return OpenRouterClient.ModelType.TEXT

func _generate_session_id() -> String:
	var time_stamp = str(Time.get_unix_time_from_system())
	var random_id = str(randi() % 10000).pad_zeros(4)
	return "chat_" + time_stamp + "_" + random_id

func _extract_response_metadata(result: Dictionary) -> Dictionary:
	var metadata = {}
	
	# Extract usage information if available
	if result.has("usage"):
		metadata["usage"] = result["usage"]
	
	# Extract model information
	if result.has("model"):
		metadata["model_used"] = result["model"]
	
	# Extract finish reason
	if result.has("choices") and result["choices"].size() > 0:
		var choice = result["choices"][0]
		if choice.has("finish_reason"):
			metadata["finish_reason"] = choice["finish_reason"]
	
	return metadata

## Get conversation history for export
func get_conversation_history() -> Array:
	return messages.duplicate()

## Export chat as markdown
func export_as_markdown() -> String:
	var markdown = "# " + session_title + "\n\n"
	markdown += "Generated on: " + Time.get_datetime_string_from_system() + "\n"
	markdown += "Model: " + current_model.get("name", "Unknown") + "\n\n"
	
	for message in messages:
		var role = message["role"].capitalize()
		var content = message["content"]
		var timestamp = ""
		
		if message.has("timestamp"):
			var time_dict = message["timestamp"]
			timestamp = " (%02d:%02d)" % [time_dict.get("hour", 0), time_dict.get("minute", 0)]
		
		markdown += "## " + role + timestamp + "\n\n"
		markdown += content + "\n\n"
		
		if message.has("metadata") and message["metadata"].has("usage"):
			var usage = message["metadata"]["usage"]
			markdown += "*Tokens used: " + str(usage.get("total_tokens", 0)) + "*\n\n"
	
	return markdown

## Update session settings
func update_model_settings(new_settings: Dictionary):
	for key in new_settings:
		model_settings[key] = new_settings[key]
	print("[ChatSession] Model settings updated: ", model_settings)

func set_temperature(temp: float):
	model_settings["temperature"] = clamp(temp, 0.0, 2.0)

func set_max_tokens(tokens: int):
	model_settings["max_tokens"] = max(tokens, 1)

func set_top_p(top_p: float):
	model_settings["top_p"] = clamp(top_p, 0.0, 1.0)

## Clear conversation history
func clear_history():
	messages.clear()
	print("[ChatSession] Conversation history cleared")

## Get session info
func get_session_info() -> Dictionary:
	return {
		"id": session_id,
		"title": session_title,
		"creation_time": creation_time,
		"message_count": messages.size(),
		"current_model": current_model,
		"settings": model_settings
	}

func _on_response_received(response: Dictionary):
	# Handle successful response
	pass

func _on_error_occurred(error_message: String):
	emit_signal("typing_finished")
	emit_signal("error_occurred", error_message)

func _on_reasoning_trace_received(trace: String):
	print("[ChatSession] Received reasoning trace: ", trace.substr(0, 100), "...")
	# Emit raw reasoning trace without transformations
	if not has_signal("reasoning_trace_updated"):
		add_user_signal("reasoning_trace_updated", [{"name": "trace", "type": TYPE_STRING}])
	emit_signal("reasoning_trace_updated", trace)

func _format_reasoning_trace(trace: String) -> String:
	# Deprecated: keep for compatibility, but return input as-is
	return trace 
