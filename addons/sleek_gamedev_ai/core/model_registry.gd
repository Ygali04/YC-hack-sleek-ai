@tool
extends Node
class_name ModelRegistry

## Enhanced model registry supporting different AI model types and capabilities

signal model_list_changed
signal models_fetched(success: bool)

const OpenRouterClient = preload("res://addons/sleek_gamedev_ai/core/openrouter_client.gd")

# Model categories and their associated models
var _models_by_category: Dictionary = {}
var _all_models: Array = []
var _openrouter_client: OpenRouterClient = null

# Model categories
enum ModelCategory {
	REASONING,
	TEXT_GENERATION,
	IMAGE_GENERATION,
	MULTIMODAL,
	CODE_GENERATION,
	FAST_RESPONSE
}

func _ready() -> void:
	_initialize_default_models()

func set_openrouter_client(client: OpenRouterClient) -> void:
	_openrouter_client = client
	if client:
		client.response_received.connect(_on_models_response)
		client.error_occurred.connect(_on_models_error)

## Initialize with curated list of popular OpenRouter models
func _initialize_default_models() -> void:
	_models_by_category = {
		ModelCategory.REASONING: [],
		ModelCategory.TEXT_GENERATION: [],
		ModelCategory.IMAGE_GENERATION: [],
		ModelCategory.MULTIMODAL: [],
		ModelCategory.CODE_GENERATION: [],
		ModelCategory.FAST_RESPONSE: []
	}
	
	# Reasoning models
	add_model({
		"id": "deepseek/deepseek-r1",
		"name": "DeepSeek R1",
		"description": "Advanced reasoning model with step-by-step thinking",
		"category": ModelCategory.REASONING,
		"context_length": 65536,
		"cost_per_1k_tokens": {"input": 0.14, "output": 0.28},
		"capabilities": ["reasoning", "math", "coding", "analysis"]
	})
	
	add_model({
		"id": "openai/o1-preview",
		"name": "OpenAI o1 Preview",
		"description": "Advanced reasoning model for complex problems",
		"category": ModelCategory.REASONING,
		"context_length": 32768,
		"cost_per_1k_tokens": {"input": 15.0, "output": 60.0},
		"capabilities": ["reasoning", "math", "science", "coding"]
	})
	
	# Text generation models
	add_model({
		"id": "anthropic/claude-3.5-sonnet",
		"name": "Claude 3.5 Sonnet",
		"description": "Powerful general-purpose model",
		"category": ModelCategory.TEXT_GENERATION,
		"context_length": 200000,
		"cost_per_1k_tokens": {"input": 3.0, "output": 15.0},
		"capabilities": ["writing", "analysis", "coding", "conversation"]
	})
	
	add_model({
		"id": "openai/gpt-4o",
		"name": "GPT-4o",
		"description": "Latest GPT-4 with improved performance",
		"category": ModelCategory.TEXT_GENERATION,
		"context_length": 128000,
		"cost_per_1k_tokens": {"input": 2.5, "output": 10.0},
		"capabilities": ["writing", "analysis", "coding", "conversation"]
	})
	
	# NEW: OpenAI GPT-5 Mini
	add_model({
		"id": "openai/gpt-5-mini",
		"name": "GPT-5-mini",
		"description": "Compact GPT-5 family model suitable for general text tasks",
		"category": ModelCategory.REASONING,
		"context_length": 131072,
		"cost_per_1k_tokens": {"input": 0.6, "output": 2.4},
		"capabilities": ["reasoning", "writing", "analysis", "coding", "conversation"]
	})

	# NEW: OpenAI GPT-5 Chat
	add_model({
		"id": "openai/gpt-5-chat",
		"name": "GPT-5 Chat",
		"description": "Compact GPT-5 family model suitable for general text tasks",
		"category": ModelCategory.REASONING,
		"context_length": 131072,
		"cost_per_1k_tokens": {"input": 0.6, "output": 2.4},
		"capabilities": ["reasoning", "writing", "analysis", "coding", "conversation"]
	})
	
	add_model({
		"id": "google/gemini-2.5-pro",
		"name": "Gemini 2.5 Pro",
		"description": "Fast, efficient general-purpose model",
		"category": ModelCategory.FAST_RESPONSE,
		"context_length": 1000000,
		"cost_per_1k_tokens": {"input": 0.075, "output": 0.30},
		"capabilities": ["writing", "conversation", "analysis"]
	})
	
	# Multimodal models
	add_model({
		"id": "anthropic/claude-3.7-sonnet",
		"name": "Claude 3.7 Sonnet (Vision)",
		"description": "Multimodal model with vision capabilities",
		"category": ModelCategory.MULTIMODAL,
		"context_length": 200000,
		"cost_per_1k_tokens": {"input": 3.0, "output": 15.0},
		"capabilities": ["vision", "image_analysis", "document_reading", "coding"]
	})
	
	add_model({
		"id": "openai/gpt-4o",
		"name": "GPT-4o Vision",
		"description": "GPT-4 with vision and image understanding",
		"category": ModelCategory.MULTIMODAL,
		"context_length": 128000,
		"cost_per_1k_tokens": {"input": 2.5, "output": 10.0},
		"capabilities": ["vision", "image_analysis", "document_reading", "coding"]
	})
	
	# Image generation models
	add_model({
		"id": "black-forest-labs/flux-1.1-pro",
		"name": "FLUX 1.1 Pro",
		"description": "High-quality image generation model",
		"category": ModelCategory.IMAGE_GENERATION,
		"context_length": 4096,
		"cost_per_1k_tokens": {"input": 0.05, "output": 0.05},
		"capabilities": ["image_generation", "artistic", "photorealistic"]
	})
	
	add_model({
		"id": "openai/dall-e-3",
		"name": "DALL-E 3",
		"description": "Advanced image generation from OpenAI",
		"category": ModelCategory.IMAGE_GENERATION,
		"context_length": 4096,
		"cost_per_1k_tokens": {"input": 0.04, "output": 0.08},
		"capabilities": ["image_generation", "artistic", "detailed"]
	})
	
	# Code generation models
	add_model({
		"id": "anthropic/claude-3.5-sonnet",
		"name": "Claude 3.5 Sonnet (Code)",
		"description": "Excellent for code generation and debugging",
		"category": ModelCategory.CODE_GENERATION,
		"context_length": 200000,
		"cost_per_1k_tokens": {"input": 3.0, "output": 15.0},
		"capabilities": ["coding", "debugging", "code_review", "architecture"]
	})
	
	add_model({
		"id": "deepseek/deepseek-r1",
		"name": "DeepSeek R1 (Code)",
		"description": "Advanced reasoning for complex coding tasks",
		"category": ModelCategory.CODE_GENERATION,
		"context_length": 65536,
		"cost_per_1k_tokens": {"input": 0.14, "output": 0.28},
		"capabilities": ["coding", "debugging", "reasoning", "algorithms"]
	})
	
	add_model({
		"id": "google/gemini-2.0-flash-exp",
		"name": "Gemini 2.0 Flash (Code)",
		"description": "Fast code generation and assistance",
		"category": ModelCategory.FAST_RESPONSE,
		"context_length": 1000000,
		"cost_per_1k_tokens": {"input": 0.075, "output": 0.30},
		"capabilities": ["coding", "fast_response", "debugging"]
	})
	
	_refresh_all_models_list()
	emit_signal("model_list_changed")

## Add a model to the registry
func add_model(model: Dictionary) -> void:
	if not model.has("category"):
		model["category"] = ModelCategory.TEXT_GENERATION
	
	var category = model["category"]
	if not _models_by_category.has(category):
		_models_by_category[category] = []
	
	_models_by_category[category].append(model)
	_refresh_all_models_list()
	emit_signal("model_list_changed")

## Remove a model by ID
func remove_model(model_id: String) -> void:
	for category in _models_by_category:
		var models = _models_by_category[category]
		for i in range(models.size()):
			if models[i]["id"] == model_id:
				models.remove_at(i)
				_refresh_all_models_list()
				emit_signal("model_list_changed")
				return

## Get all models
func get_models() -> Array:
	return _all_models.duplicate()

## Get models by category
func get_models_by_category(category: ModelCategory) -> Array:
	if _models_by_category.has(category):
		return _models_by_category[category].duplicate()
	return []

## Get model by ID
func get_model(model_id: String) -> Dictionary:
	for model in _all_models:
		if model["id"] == model_id:
			return model.duplicate()
	return {}

## Get models with specific capability
func get_models_with_capability(capability: String) -> Array:
	var result = []
	for model in _all_models:
		if model.has("capabilities") and capability in model["capabilities"]:
			result.append(model)
	return result

## Get model categories as strings for UI
func get_category_names() -> Array:
	return [
		"Reasoning",
		"Text Generation", 
		"Image Generation",
		"Multimodal",
		"Code Generation",
		"Fast Response"
	]

## Get category from enum
func get_category_name(category: ModelCategory) -> String:
	match category:
		ModelCategory.REASONING:
			return "Reasoning"
		ModelCategory.TEXT_GENERATION:
			return "Text Generation"
		ModelCategory.IMAGE_GENERATION:
			return "Image Generation"
		ModelCategory.MULTIMODAL:
			return "Multimodal"
		ModelCategory.CODE_GENERATION:
			return "Code Generation"
		ModelCategory.FAST_RESPONSE:
			return "Fast Response"
		_:
			return "Unknown"

## Fetch available models from OpenRouter API
func fetch_available_models() -> void:
	if not _openrouter_client or not _openrouter_client.is_configured():
		print("[ModelRegistry] OpenRouter client not configured")
		emit_signal("models_fetched", false)
		return
	
	print("[ModelRegistry] Fetching models from OpenRouter...")
	var result = await _openrouter_client.fetch_models()
	
	if result.has("error"):
		print("[ModelRegistry] Error fetching models: ", result["error"])
		emit_signal("models_fetched", false)
	else:
		_process_openrouter_models(result)
		emit_signal("models_fetched", true)

## Get the best model for a specific task
func get_recommended_model(task_type: String) -> Dictionary:
	match task_type.to_lower():
		"reasoning", "math", "logic":
			var reasoning_models = get_models_by_category(ModelCategory.REASONING)
			if reasoning_models.size() > 0:
				return reasoning_models[0]
			return {}
		
		"image", "generation", "art":
			var image_models = get_models_by_category(ModelCategory.IMAGE_GENERATION)
			if image_models.size() > 0:
				return image_models[0]
			return {}
		
		"vision", "multimodal", "analyze":
			var multimodal_models = get_models_by_category(ModelCategory.MULTIMODAL)
			if multimodal_models.size() > 0:
				return multimodal_models[0]
			return {}
		
		"code", "programming", "debug":
			var code_models = get_models_by_category(ModelCategory.CODE_GENERATION)
			if code_models.size() > 0:
				return code_models[0]
			return {}
		
		"fast", "quick", "chat":
			var fast_models = get_models_by_category(ModelCategory.FAST_RESPONSE)
			if fast_models.size() > 0:
				return fast_models[0]
			return {}
		
		_:
			var text_models = get_models_by_category(ModelCategory.TEXT_GENERATION)
			if text_models.size() > 0:
				return text_models[0]
			return {}

func _refresh_all_models_list() -> void:
	_all_models.clear()
	for category in _models_by_category:
		_all_models.append_array(_models_by_category[category])

func _process_openrouter_models(response: Dictionary) -> void:
	if not response.has("data"):
		return
	
	var openrouter_models = response["data"]
	print("[ModelRegistry] Received ", openrouter_models.size(), " models from OpenRouter")
	
	# You could integrate these with your existing models
	# For now, we'll just log the availability
	for model in openrouter_models:
		if model.has("id"):
			var existing_model = get_model(model["id"])
			if not existing_model.is_empty():
				# Update existing model with fresh data
				if model.has("pricing"):
					existing_model["pricing"] = model["pricing"]
				if model.has("context_length"):
					existing_model["context_length"] = model["context_length"]

func _on_models_response(response: Dictionary) -> void:
	# Handle successful model fetch response
	pass

func _on_models_error(error_message: String) -> void:
	print("[ModelRegistry] Error: ", error_message)
	emit_signal("models_fetched", false) 
