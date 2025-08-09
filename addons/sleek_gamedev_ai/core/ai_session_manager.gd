@tool
extends Node
class_name AISessionManager

## Central manager for AI chat sessions, model management, and OpenRouter integration

signal session_created(session: ChatSession)
signal session_switched(session: ChatSession)
signal session_removed(session_id: String)
signal model_changed(model: Dictionary)
signal error_occurred(error_message: String)
 
const OpenRouterClient = preload("res://addons/sleek_gamedev_ai/core/openrouter_client.gd")
const ModelRegistry = preload("res://addons/sleek_gamedev_ai/core/model_registry.gd")
const ChatSession = preload("res://addons/sleek_gamedev_ai/core/chat_session.gd")
 
var openrouter_client: OpenRouterClient
var model_registry: ModelRegistry
var chat_sessions: Array[ChatSession] = []
var current_session: ChatSession = null
var current_model: Dictionary = {}

# Settings
var default_model_settings: Dictionary = {
	"temperature": 0.7,
	"max_tokens": 4096,
	"top_p": 0.9
}

# Simple conversation store
var conversation_favorites: Dictionary = {} # session_id -> bool
var custom_instructions: String = ""
const LAST_CONVO_PATH := "user://ai_assistant_last_conversation.txt"

func _ready():
	_initialize_components()
	# Attempt to restore the most recent conversation
	_restore_last_conversation()

func _initialize_components():
	# Initialize OpenRouter client
	openrouter_client = OpenRouterClient.new()
	add_child(openrouter_client)
	
	# Initialize model registry
	model_registry = ModelRegistry.new()
	add_child(model_registry)
	model_registry.set_openrouter_client(openrouter_client)
	
	# Connect signals
	openrouter_client.error_occurred.connect(_on_openrouter_error)
	model_registry.model_list_changed.connect(_on_model_list_changed)
	
	# Set default model if available
	await get_tree().process_frame  # Wait for model registry to initialize
	_set_default_model()

func _set_default_model():
	var models = model_registry.get_models()
	if models.size() > 0:
		set_current_model(models[0])

## Set the OpenRouter API key
func set_api_key(api_key: String) -> bool:
	if openrouter_client:
		openrouter_client.set_api_key(api_key)
		print("[AISessionManager] API key configured")
		return true
	return false

## Check if the system is properly configured
func is_configured() -> bool:
	return openrouter_client and openrouter_client.is_configured()

## Create a new chat session
func create_new_session(title: String = "") -> ChatSession:
	var session = ChatSession.new()
	
	if title.is_empty():
		title = "Chat " + str(chat_sessions.size() + 1)
	
	session.session_title = title
	session.configure(openrouter_client, current_model, model_registry)
	
	# Connect session signals
	session.error_occurred.connect(_on_session_error)
	
	chat_sessions.append(session)
	add_child(session)
	
	# Switch to new session
	switch_to_session(session)
	
	emit_signal("session_created", session)
	print("[AISessionManager] Created new session: ", title)
	
	return session

## Switch to a specific session
func switch_to_session(session: ChatSession):
	if session in chat_sessions:
		current_session = session
		emit_signal("session_switched", session)
		print("[AISessionManager] Switched to session: ", session.session_title)

## Remove a chat session
func remove_session(session: ChatSession) -> bool:
	if session not in chat_sessions:
		return false
	
	var session_id = session.session_id
	
	# Don't remove the last session
	if chat_sessions.size() <= 1:
		print("[AISessionManager] Cannot remove the last session")
		return false
	
	# If removing current session, switch to another
	if current_session == session:
		var current_index = chat_sessions.find(session)
		var new_index: int
		if current_index == chat_sessions.size() - 1:
			new_index = 0
		else:
			new_index = current_index + 1
		switch_to_session(chat_sessions[new_index])
	
	# Remove session
	chat_sessions.erase(session)
	session.queue_free()
	
	emit_signal("session_removed", session_id)
	print("[AISessionManager] Removed session: ", session_id)
	
	return true

## Get all chat sessions
func get_sessions() -> Array[ChatSession]:
	return chat_sessions.duplicate()

## Get current session
func get_current_session() -> ChatSession:
	return current_session

## Set the current model for all new sessions
func set_current_model(model: Dictionary):
	current_model = model
	
	# Update current session if exists
	if current_session:
		current_session.set_model(model)
	
	emit_signal("model_changed", model)
	print("[AISessionManager] Changed model to: ", model.get("name", "Unknown"))

## Get the current model
func get_current_model() -> Dictionary:
	return current_model

## Get available models from registry
func get_available_models() -> Array:
	return model_registry.get_models()

## Get models by category
func get_models_by_category(category: ModelRegistry.ModelCategory) -> Array:
	return model_registry.get_models_by_category(category)

## Get recommended model for a task
func get_recommended_model(task_type: String) -> Dictionary:
	return model_registry.get_recommended_model(task_type)

## Fetch latest models from OpenRouter
func refresh_models() -> void:
	if model_registry:
		await model_registry.fetch_available_models()

## Update default model settings
func update_default_settings(settings: Dictionary):
	for key in settings:
		default_model_settings[key] = settings[key]
	
	# Apply to current session
	if current_session:
		current_session.update_model_settings(settings)
	
	print("[AISessionManager] Updated default settings: ", default_model_settings)

## Send message through current session
func send_message(text: String) -> bool:
	if not current_session:
		emit_signal("error_occurred", "No active chat session")
		return false
	
	if not is_configured():
		emit_signal("error_occurred", "OpenRouter not configured")
		return false
	
	current_session.ask(text)
	return true

## Add attachment to current session
func add_attachment(file_path: String, is_image: bool = false):
	if not current_session:
		emit_signal("error_occurred", "No active chat session")
		return
	
	if is_image:
		current_session.add_image_attachment(file_path)
	else:
		current_session.add_text_attachment(file_path)

## Clear attachments from current session
func clear_attachments():
	if current_session:
		current_session.clear_attachments()

## Export current session as markdown
func export_current_session() -> String:
	if current_session:
		return current_session.export_as_markdown()
	return ""

func save_current_conversation_to_disk() -> bool:
	var md = export_current_session()
	if md == "":
		return false
	var f = FileAccess.open(LAST_CONVO_PATH, FileAccess.WRITE)
	if not f:
		push_error("AISessionManager: failed to open last conversation file for writing: %s" % LAST_CONVO_PATH)
		return false
	f.store_string(md)
	f.close()
	print("[AISessionManager] Saved most recent conversation to ", LAST_CONVO_PATH)
	return true

func _restore_last_conversation() -> void:
	if not FileAccess.file_exists(LAST_CONVO_PATH):
		return
	var f = FileAccess.open(LAST_CONVO_PATH, FileAccess.READ)
	if not f:
		push_error("AISessionManager: failed to read last conversation file: %s" % LAST_CONVO_PATH)
		return
	var md = f.get_as_text()
	f.close()
	if md.strip_edges() == "":
		return
	# Create a new session and load the markdown content as a single assistant message for now
	var session = create_new_session("Chat 1")
	# Very simple import: dump markdown into first assistant message so user can scroll/search
	session.messages.append({
		"role": "assistant",
		"content": md,
		"timestamp": Time.get_time_dict_from_system(),
		"metadata": {"imported": true}
	})
	emit_signal("session_switched", session)
	print("[AISessionManager] Restored last conversation from ", LAST_CONVO_PATH)

## Clear all sessions (keep one empty session)
func clear_all_sessions():
	# Remove all but the first session
	while chat_sessions.size() > 1:
		var session_to_remove = chat_sessions[-1]
		remove_session(session_to_remove)
	
	# Clear the remaining session
	if current_session:
		current_session.clear_history()
	
	# Also clear last saved file
	if FileAccess.file_exists(LAST_CONVO_PATH):
		DirAccess.remove_absolute(LAST_CONVO_PATH)
	
	print("[AISessionManager] Cleared all sessions")

## Get session statistics
func get_session_stats() -> Dictionary:
	var stats = {
		"total_sessions": chat_sessions.size(),
		"total_messages": 0,
		"current_model": current_model.get("name", "None"),
		"api_configured": is_configured()
	}
	
	for session in chat_sessions:
		stats["total_messages"] += session.messages.size()
	
	return stats

## Handle model type detection for UI
func is_model_multimodal(model: Dictionary) -> bool:
	if model.has("capabilities"):
		return "vision" in model["capabilities"] or "image_analysis" in model["capabilities"]
	return false

func is_model_image_generator(model: Dictionary) -> bool:
	if model.has("capabilities"):
		return "image_generation" in model["capabilities"]
	return false

func is_model_reasoning(model: Dictionary) -> bool:
	var model_name = model.get("name", "").to_lower()
	var model_id = model.get("id", "").to_lower()
	
	# Check by name/id first (more reliable)
	var is_reasoning_by_name = ("deepseek" in model_name and "r1" in model_name) or \
							  ("deepseek" in model_id and "r1" in model_id) or \
							  ("o1" in model_name) or ("o1" in model_id)
	
	# Check by capabilities
	var is_reasoning_by_capabilities = false
	if model.has("capabilities"):
		is_reasoning_by_capabilities = "reasoning" in model["capabilities"]
	
	var final_result = is_reasoning_by_name or is_reasoning_by_capabilities
	
	print("[AISessionManager] Model ", model.get("name", "Unknown"), " is reasoning: ", final_result)
	print("[AISessionManager] By name: ", is_reasoning_by_name, ", by capabilities: ", is_reasoning_by_capabilities)
	
	return final_result

## Get model type for UI display
func get_model_type_string(model: Dictionary) -> String:
	if is_model_image_generator(model):
		return "Image Generation"
	elif is_model_reasoning(model):
		return "Reasoning"
	elif is_model_multimodal(model):
		return "Multimodal"
	else:
		return "Text Generation"

## Test API connection
func test_connection() -> bool:
	if not is_configured():
		return false
	
	# Simple test with a lightweight model
	var test_models = model_registry.get_models_by_category(ModelRegistry.ModelCategory.FAST_RESPONSE)
	if test_models.size() == 0:
		test_models = model_registry.get_models()
	
	if test_models.size() == 0:
		return false
	
	var test_model = test_models[0]
	var test_messages = [{"role": "user", "content": "Hi"}]
	
	var result = await openrouter_client.chat_completion(test_model["id"], test_messages, {"max_tokens": 10})
	return not result.has("error")

func _on_openrouter_error(error_message: String):
	emit_signal("error_occurred", "OpenRouter: " + error_message)

func _on_session_error(error_message: String):
	emit_signal("error_occurred", "Session: " + error_message)

func _on_model_list_changed():
	print("[AISessionManager] Model list updated")
	
	# If no current model set, set the first available
	if current_model.is_empty():
		_set_default_model()

func set_custom_instructions(text: String) -> void:
	custom_instructions = text

func get_custom_instructions() -> String:
	return custom_instructions

func set_favorite(session: ChatSession, fav: bool) -> void:
	conversation_favorites[session.session_id] = fav

func is_favorite(session: ChatSession) -> bool:
	return conversation_favorites.get(session.session_id, false)

func delete_conversation(session: ChatSession) -> bool:
	return remove_session(session) 