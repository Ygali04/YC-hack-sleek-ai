@tool
extends Control

## Enhanced AI dock with integrated OpenRouter support

const AISessionManager = preload("res://addons/sleek_gamedev_ai/core/ai_session_manager.gd")
const ModelRegistry = preload("res://addons/sleek_gamedev_ai/core/model_registry.gd")
const EnvLoader = preload("res://addons/sleek_gamedev_ai/core/env_loader.gd")

# Core components
var ai_session_manager: AISessionManager
var session_to_tab_mapping: Dictionary = {}

# UI Components - Header
var header_container: HBoxContainer
var model_selector: OptionButton
var model_category_selector: OptionButton
var ai_mode_button: Button
var create_mode_button: Button
var options_button: Button
var options_popup: PopupMenu
var close_button: Button

# UI Components - Chat System
var chat_tabs: TabContainer
var add_chat_button: Button
var current_chat_id: int = 0

# UI Components - Message Area
var message_scroll: ScrollContainer
var message_container: VBoxContainer
var input_container: HBoxContainer
var input_field: TextEdit
var attach_button: Button
var clear_attachments_button: Button
var send_button: Button

# Reasoning trace components
var current_reasoning_bubble: Control = null
var reasoning_trace_text: String = ""
var reasoning_update_timer: Timer
var auto_expand_reasoning: bool = true
var pending_attempt_group: Control = null

# UI Components - Close Tab Button
var close_tab_button: Button
var hovered_tab_index: int = -1

# File Attachment
var file_dialog: FileDialog
var attached_files: Array[String] = []

var actions_manager: Node
var markdown_renderer = preload("res://addons/sleek_gamedev_ai/chat/markdown_to_bbcode.gd")
var tagger = preload("res://addons/sleek_gamedev_ai/chat/message_tagger.gd")
var rating_container: HBoxContainer

var favorites_toggle: Button
var delete_button_chat: Button
var custom_instructions_edit: TextEdit

var assets_tab: VBoxContainer
var sd_request: HTTPRequest

var stability: StabilityClient

func _init():
	name = "AI Assistant"
	custom_minimum_size = Vector2(350, 500)
	_setup_styling()
	_initialize_ai_components()
	_build_ui()

func _ready():
	# Wait for the node to be properly added to the scene tree
	await get_tree().process_frame
	
	# Wait for AI session manager to be fully initialized
	if ai_session_manager:
		await get_tree().process_frame
		_create_first_session()
	else:
		print("[AIDock] Error: AI session manager not initialized!")
		_add_error_message_to_ui_direct("AI Session Manager failed to initialize")
	
	if actions_manager:
		actions_manager.action_error_bbcode.connect(func(msg: String):
			_add_ai_message_to_ui(msg)
		)

func _input(event: InputEvent):
	# Handle keyboard shortcuts
	if event is InputEventKey and event.pressed:
		# Only handle shortcuts when focus is inside this dock
		var focus_owner = get_viewport().gui_get_focus_owner()
		if focus_owner == null or (not self.is_ancestor_of(focus_owner) and focus_owner != self):
			return
		# Ignore key repeat
		if event.echo:
			return
		# Cmd+T (macOS) or Ctrl+T (Windows/Linux) to create new chat tab
		if event.keycode == KEY_T and (event.meta_pressed or event.ctrl_pressed):
			_create_new_chat()
			get_viewport().set_input_as_handled()

func _initialize_ai_components():
	# Initialize the AI session manager
	ai_session_manager = AISessionManager.new()
	add_child(ai_session_manager)
	# Actions manager
	actions_manager = preload("res://addons/sleek_gamedev_ai/actions/action_manager.gd").new()
	add_child(actions_manager)
	# Stability client
	stability = preload("res://addons/sleek_gamedev_ai/core/stability_client.gd").new()
	add_child(stability)
	
	# Connect signals
	ai_session_manager.session_created.connect(_on_session_created)
	ai_session_manager.session_switched.connect(_on_session_switched)
	ai_session_manager.session_removed.connect(_on_session_removed)
	ai_session_manager.model_changed.connect(_on_model_changed)
	ai_session_manager.error_occurred.connect(_on_ai_error)
	
	# Try to get API key from environment or .env file
	var api_key = EnvLoader.get_env_var("OPENROUTER_API_KEY")
	if not api_key.is_empty():
		ai_session_manager.set_api_key(api_key)
		print("[AIDock] ✅ OpenRouter API key loaded (", api_key.substr(0, 8), "...)")
	else:
		print("[AIDock] ❌ No OpenRouter API key found!")
		print("[AIDock] Checked both system environment and .env file")
		print("[AIDock] Please either:")
		print("[AIDock] 1. Set system environment: export OPENROUTER_API_KEY='your_key'")
		print("[AIDock] 2. Or add to .env file: OPENROUTER_API_KEY=\"your_key\"")

func _setup_styling():
	# Apply dark theme styling to match Cursor
	add_theme_color_override("background_color", Color(0.12, 0.12, 0.12, 1.0))

func _build_ui():
	# Main layout
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)
	
	_create_header(main_vbox)
	_create_chat_area(main_vbox)
	_create_options_popup()
	_create_file_dialog()
	_create_input_area(main_vbox)  # Move to the end to ensure it's at bottom

func _create_header(parent: VBoxContainer):
	# Header container with dark background - using simple HBoxContainer
	header_container = HBoxContainer.new()
	header_container.custom_minimum_size.y = 50
	header_container.add_theme_color_override("background_color", Color(0.1, 0.1, 0.1, 1.0))
	parent.add_child(header_container)
	
	# Left container for model selectors (will shrink first)
	var left_container = HBoxContainer.new()
	left_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_container.size_flags_stretch_ratio = 0.1  # Low stretch ratio so it shrinks first
	header_container.add_child(left_container)
	
	# Model category selector
	model_category_selector = OptionButton.new()
	model_category_selector.add_item("All Models")
	model_category_selector.add_item("Reasoning")
	model_category_selector.add_item("Text Gen")
	model_category_selector.add_item("Multimodal") 
	model_category_selector.add_item("Image Gen")
	model_category_selector.add_item("Fast")
	model_category_selector.selected = 0
	model_category_selector.custom_minimum_size.x = 80
	model_category_selector.tooltip_text = "Filter models by category"
	left_container.add_child(model_category_selector)
	
	# Model selector dropdown
	model_selector = OptionButton.new()
	model_selector.custom_minimum_size.x = 140
	model_selector.tooltip_text = "Select AI model"
	left_container.add_child(model_selector)
	
	# AI Mode toggle
	ai_mode_button = Button.new()
	ai_mode_button.text = "🤖 Agent"
	ai_mode_button.toggle_mode = true
	ai_mode_button.button_pressed = true
	ai_mode_button.custom_minimum_size.x = 80
	left_container.add_child(ai_mode_button)
	
	# Create mode button
	create_mode_button = Button.new()
	create_mode_button.text = "🎨 Create"
	create_mode_button.toggle_mode = true
	create_mode_button.button_pressed = false
	create_mode_button.custom_minimum_size.x = 80
	left_container.add_child(create_mode_button)
	
	# Spacer (will be hidden first when space is limited)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 0.01  # Very low stretch ratio
	header_container.add_child(spacer)
	
	# Right container for critical buttons (will not shrink)
	var right_container = HBoxContainer.new()
	right_container.size_flags_horizontal = Control.SIZE_SHRINK_END
	right_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Make sure it doesn't block input
	header_container.add_child(right_container)
	
	# Favorites toggle and delete chat
	favorites_toggle = Button.new(); favorites_toggle.text = "☆"; favorites_toggle.tooltip_text = "Favorite this conversation"; right_container.add_child(favorites_toggle)
	delete_button_chat = Button.new(); delete_button_chat.text = "🗑"; delete_button_chat.tooltip_text = "Delete this conversation"; right_container.add_child(delete_button_chat)
	favorites_toggle.pressed.connect(_on_favorite_pressed)
	delete_button_chat.pressed.connect(_on_delete_chat_pressed)
	
	# Options menu (using more compatible character)
	options_button = Button.new()
	options_button.text = "..."
	options_button.custom_minimum_size = Vector2(30, 30)
	right_container.add_child(options_button)
	
	# Close button
	close_button = Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(30, 30)
	right_container.add_child(close_button)
	
	# Connect signals
	options_button.pressed.connect(_on_options_pressed)
	close_button.pressed.connect(_on_close_pressed)
	ai_mode_button.toggled.connect(_on_ai_mode_toggled)
	create_mode_button.toggled.connect(_on_create_mode_toggled)
	model_selector.item_selected.connect(_on_model_selected)
	model_category_selector.item_selected.connect(_on_category_selected)

func _create_options_popup():
	# Create the popup menu
	options_popup = PopupMenu.new()
	add_child(options_popup)
	
	# Add menu items
	options_popup.add_item("Close Current Chat", 0)
	options_popup.add_item("Clear All Chats", 1)
	options_popup.add_separator()
	options_popup.add_item("Export Chat as Markdown", 2)
	options_popup.add_separator()
	options_popup.add_item("Refresh Models", 3)
	options_popup.add_item("Test Connection", 4)
	options_popup.add_separator()
	options_popup.add_item("Session Statistics", 5)
	options_popup.add_separator()
	options_popup.add_item("Auto-expand Reasoning", 6)
	options_popup.add_separator()
	options_popup.add_item("Test Reasoning Trace", 7)
	options_popup.add_separator()
	options_popup.add_item("Give Feedback", 8)
	
	# Style the popup
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style_box.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	options_popup.add_theme_stylebox_override("panel", style_box)
	
	# Connect the menu item selection
	options_popup.id_pressed.connect(_on_options_menu_selected)

func _create_chat_area(parent: VBoxContainer):
	# Chat tabs container takes the full area
	chat_tabs = TabContainer.new()
	chat_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	chat_tabs.add_theme_constant_override("margin_left", 5)
	# Ensure tabs are visible
	chat_tabs.tabs_visible = true
	parent.add_child(chat_tabs)
	# Give the TabBar a clear height
	var tb = chat_tabs.get_tab_bar()
	if tb:
		tb.custom_minimum_size.y = 28
	chat_tabs.tab_changed.connect(_on_tab_changed)
	# Ratings container (shared, simple)
	rating_container = HBoxContainer.new()
	rating_container.visible = false
	var up = Button.new(); up.text = "👍"; var down = Button.new(); down.text = "👎"
	rating_container.add_child(up); rating_container.add_child(down)
	parent.add_child(rating_container)
	# Assets tab
	assets_tab = VBoxContainer.new()
	assets_tab.name = "Assets"
	var assets_panel = PanelContainer.new()
	var assets_box = VBoxContainer.new(); assets_panel.add_child(assets_box)
	var prompt = LineEdit.new(); prompt.placeholder_text = "Prompt"; assets_box.add_child(prompt)
	var neg = LineEdit.new(); neg.placeholder_text = "Negative prompt"; assets_box.add_child(neg)
	var model = LineEdit.new(); model.placeholder_text = "Model (e.g. stability-ai/stable-diffusion)"; assets_box.add_child(model)
	var steps = SpinBox.new(); steps.min_value = 1; steps.max_value = 150; steps.value = 30; steps.prefix = "Steps: "; assets_box.add_child(steps)
	var guidance = SpinBox.new(); guidance.min_value = 0; guidance.max_value = 20; guidance.step = 0.1; guidance.value = 7.5; guidance.prefix = "CFG: "; assets_box.add_child(guidance)
	var seed = SpinBox.new(); seed.min_value = 0; seed.max_value = 999999999; seed.value = 0; seed.prefix = "Seed: "; assets_box.add_child(seed)
	var size_hbox = HBoxContainer.new(); var w = SpinBox.new(); w.min_value = 64; w.max_value = 2048; w.value = 512; w.prefix = "W: "; var h = SpinBox.new(); h.min_value = 64; h.max_value = 2048; h.value = 512; h.prefix = "H: "; size_hbox.add_child(w); size_hbox.add_child(h); assets_box.add_child(size_hbox)
	var btn_row = HBoxContainer.new(); var gen_img = Button.new(); gen_img.text = "Generate Image"; var gen_anim = Button.new(); gen_anim.text = "Generate Animation"; btn_row.add_child(gen_img); btn_row.add_child(gen_anim); assets_box.add_child(btn_row)
	var progress = ProgressBar.new(); progress.value = 0; progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL; assets_box.add_child(progress)
	var preview = TextureRect.new(); preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; assets_box.add_child(preview)
	assets_tab.add_child(assets_panel)
	chat_tabs.add_child(assets_tab)
	_refresh_tab_titles()
	# Ensure the plus button exists even before any chat tabs are created
	_add_plus_button_to_tabs()
	# HTTP client for SD
	sd_request = HTTPRequest.new(); add_child(sd_request)
	gen_img.pressed.connect(func(): _on_generate_image(prompt.text, neg.text, model.text, int(steps.value), float(guidance.value), int(seed.value), Vector2i(int(w.value), int(h.value)), progress, preview))
	gen_anim.pressed.connect(func(): _on_generate_animation(prompt.text, neg.text, model.text, int(steps.value), float(guidance.value), int(seed.value), Vector2i(int(w.value), int(h.value)), progress, preview))

func _create_input_area(parent: VBoxContainer):
	# Input container with modern styling - using simple HBoxContainer
	input_container = HBoxContainer.new()
	input_container.custom_minimum_size.y = 60
	input_container.add_theme_color_override("background_color", Color(0.15, 0.15, 0.15, 1.0))
	parent.add_child(input_container)
	
	# Custom instructions area above input
	custom_instructions_edit = TextEdit.new()
	custom_instructions_edit.placeholder_text = "Custom Instructions (sent with each prompt)"
	custom_instructions_edit.custom_minimum_size.y = 60
	custom_instructions_edit.text_changed.connect(_on_custom_instructions_changed)
	parent.add_child(custom_instructions_edit)
	
	# Left container for attachment buttons (lowest priority)
	var left_container = HBoxContainer.new()
	left_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_container.size_flags_stretch_ratio = 0.1  # Low stretch ratio so it shrinks first
	input_container.add_child(left_container)
	
	# Attachment button
	attach_button = Button.new()
	attach_button.text = "📎"
	attach_button.custom_minimum_size = Vector2(40, 40)
	attach_button.flat = true
	left_container.add_child(attach_button)
	
	# Clear attachments button
	clear_attachments_button = Button.new()
	clear_attachments_button.text = "🗑️"
	clear_attachments_button.custom_minimum_size = Vector2(40, 40)
	clear_attachments_button.flat = true
	clear_attachments_button.tooltip_text = "Clear attachments"
	left_container.add_child(clear_attachments_button)
	
	# Input field (TextEdit for multiline support) - will expand to fill available space
	input_field = TextEdit.new()
	input_field.placeholder_text = "Ask the AI assistant... (Shift+Enter to send)"
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.size_flags_stretch_ratio = 0.01  # Very low stretch ratio
	input_field.custom_minimum_size.y = 40
	input_field.scroll_fit_content_height = true
	input_field.gui_input.connect(_on_input_field_gui_input)
	input_container.add_child(input_field)
	
	# Send button container (highest priority, will not shrink)
	var send_container = HBoxContainer.new()
	send_container.size_flags_horizontal = Control.SIZE_SHRINK_END
	send_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Make sure it doesn't block input
	input_container.add_child(send_container)
	
	# Send button
	send_button = Button.new()
	send_button.text = "➤"
	send_button.custom_minimum_size = Vector2(40, 40)
	send_button.flat = true
	send_container.add_child(send_button)
	
	# Connect signals
	send_button.pressed.connect(_on_send_pressed)
	attach_button.pressed.connect(_on_attach_pressed)
	clear_attachments_button.pressed.connect(_on_clear_attachments_pressed)
	input_field.text_changed.connect(_on_input_changed)

func _create_first_session():
	if ai_session_manager:
		print("[AIDock] Creating first session...")
		# Avoid creating duplicates if sessions already exist
		var existing = ai_session_manager.get_sessions()
		if existing.size() == 0:
			var session = ai_session_manager.create_new_session("Chat 1")
			# Immediately create the UI tab for visibility
			_create_session_tab(session)
		else:
			# Still populate model selector if needed
			_populate_model_selector()
			# Ensure the first existing session has a tab
			_create_session_tab(existing[0])
		_populate_model_selector()
		
		# Check if OpenRouter is configured
		if not ai_session_manager.is_configured():
			print("[AIDock] OpenRouter not configured - API key missing")
			_add_error_message_to_ui_direct("OpenRouter API key not found. Please set OPENROUTER_API_KEY environment variable and restart Godot.")
	else:
		print("[AIDock] Error: No AI session manager available")

func _create_new_chat():
	if ai_session_manager:
		# Generate a proper chat name based on existing chat count (ignore Assets tab)
		var chat_count = ai_session_manager.get_sessions().size() + 1
		var chat_name = "Chat " + str(chat_count)
		var session = ai_session_manager.create_new_session(chat_name)

func _populate_model_selector():
	if not ai_session_manager:
		# Add placeholder when AI manager isn't available
		model_selector.clear()
		model_selector.add_item("Setup Required - No API Key")
		model_selector.disabled = true
		return
	
	var category_index = model_category_selector.selected
	var models = []
	
	match category_index:
		0:  # All Models
			models = ai_session_manager.get_available_models()
		1:  # Reasoning
			models = ai_session_manager.get_models_by_category(ModelRegistry.ModelCategory.REASONING)
		2:  # Text Generation
			models = ai_session_manager.get_models_by_category(ModelRegistry.ModelCategory.TEXT_GENERATION)
		3:  # Multimodal
			models = ai_session_manager.get_models_by_category(ModelRegistry.ModelCategory.MULTIMODAL)
		4:  # Image Generation
			models = ai_session_manager.get_models_by_category(ModelRegistry.ModelCategory.IMAGE_GENERATION)
		5:  # Fast Response
			models = ai_session_manager.get_models_by_category(ModelRegistry.ModelCategory.FAST_RESPONSE)
	
	# Clear existing items
	model_selector.clear()
	
	if models.size() == 0:
		# Add placeholder when no models available
		model_selector.add_item("No models available")
		model_selector.disabled = true
		return
	
	# Enable selector when models are available
	model_selector.disabled = false
	
	# Add models to selector
	for model in models:
		var display_name = model.get("name", "Unknown Model")
		var model_type = ai_session_manager.get_model_type_string(model)
		var full_name = display_name + " (" + model_type + ")"
		model_selector.add_item(full_name)
		model_selector.set_item_metadata(model_selector.get_item_count() - 1, model)
	
	# Select first model if available
	if models.size() > 0:
		model_selector.selected = 0
		_on_model_selected(0)

func _add_tab_close_button(tab_index: int):
	# Get the tab bar and add a close button
	var tab_bar = chat_tabs.get_tab_bar()
	if tab_bar:
		# This is a workaround since Godot doesn't have built-in close buttons
		# We'll handle this with right-click for now
		tab_bar.tab_rmb_clicked.connect(_on_tab_right_clicked)

func _add_plus_button_to_tabs():
	# Access the tab bar and add the + button as a custom control
	var tab_bar = chat_tabs.get_tab_bar()
	if tab_bar:
		# Create the + button
		add_chat_button = Button.new()
		add_chat_button.text = "+"
		add_chat_button.custom_minimum_size = Vector2(25, 25)
		add_chat_button.flat = true
		add_chat_button.tooltip_text = "New Chat"
		add_chat_button.focus_mode = Control.FOCUS_NONE
		
		# Add it as a child to the tab bar
		tab_bar.add_child(add_chat_button)
		
		# Initial positioning and connect to resize for dynamic positioning
		_position_plus_button()
		tab_bar.resized.connect(_position_plus_button)
		
		# Connect signal
		add_chat_button.pressed.connect(_on_add_chat_pressed)
		
		# --- Close button setup ---
		close_tab_button = Button.new()
		close_tab_button.text = "×"
		close_tab_button.custom_minimum_size = Vector2(16, 16)
		close_tab_button.flat = true
		close_tab_button.focus_mode = Control.FOCUS_NONE
		close_tab_button.visible = false
		tab_bar.add_child(close_tab_button)
		close_tab_button.pressed.connect(_on_close_hovered_tab_pressed)
		
		# Connect tab bar input to track hover
		tab_bar.gui_input.connect(_on_tab_bar_gui_input)
	else:
		return

func _position_plus_button():
	var tab_bar = chat_tabs.get_tab_bar()
	if tab_bar and add_chat_button:
		# Place the button at the far right with 4px margin
		var margin = 4
		add_chat_button.position = Vector2(tab_bar.size.x - add_chat_button.size.x - margin, 2)

func _add_welcome_message(container: VBoxContainer):
	var welcome_text = "AI Assistant Ready! 🤖\n\nI can help you with:\n• Generate GDScript code\n• Create game assets\n• Debug your projects\n• Provide coding suggestions\n\nWhat would you like to work on?"
	
	# Check if OpenRouter is configured
	if not ai_session_manager or not ai_session_manager.is_configured():
		welcome_text = "AI Assistant - Setup Required 🔧\n\n⚠️ OpenRouter API key not found!\n\nTo get started:\n1. Visit https://openrouter.ai\n2. Get your API key\n3. Set environment variable:\n   export OPENROUTER_API_KEY='your_key'\n4. Restart Godot\n\nThen you can chat with AI models!"
	
	var welcome_bubble = _create_message_bubble(welcome_text, false, "just now")
	container.add_child(welcome_bubble)

func _create_message_bubble(text: String, is_user: bool, timestamp: String) -> Control:
	# Basic bubble used for simple system/attachment messages
	var bubble_container = HBoxContainer.new()
	bubble_container.custom_minimum_size.y = 60
	
	# Message bubble
	var bubble = PanelContainer.new()
	
	if is_user:
		# User message - right aligned, better width
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.custom_minimum_size.x = 50  # Minimum left margin
		bubble_container.add_child(spacer)
		
		bubble.custom_minimum_size.x = 250  # Increased minimum width
		bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		# AI message - full width
		bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Bubble styling
	var style_box = StyleBoxFlat.new()
	if is_user:
		style_box.bg_color = Color(0.2, 0.4, 0.8, 1.0)  # Blue for user
	else:
		style_box.bg_color = Color(0.2, 0.2, 0.2, 1.0)  # Dark gray for AI
	
	if is_user:
		style_box.corner_radius_bottom_left = 12
		style_box.corner_radius_bottom_right = 12
		style_box.corner_radius_top_left = 12
		style_box.corner_radius_top_right = 4
	else:
		style_box.corner_radius_bottom_left = 4
		style_box.corner_radius_bottom_right = 12
		style_box.corner_radius_top_left = 12
		style_box.corner_radius_top_right = 12
	
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 8
	style_box.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style_box)
	
	# Message content
	var content_vbox = VBoxContainer.new()
	bubble.add_child(content_vbox)
	
	# Message text (selectable)
	var message_label = TextEdit.new()
	message_label.editable = false
	message_label.text = text
	message_label.add_theme_color_override("font_color", Color.WHITE)
	message_label.add_theme_color_override("background_color", Color.TRANSPARENT)
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_label.scroll_fit_content_height = true
	message_label.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content_vbox.add_child(message_label)
	
	# Timestamp
	var time_label = Label.new()
	time_label.text = timestamp
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	time_label.add_theme_font_override("font", ThemeDB.fallback_font)
	time_label.add_theme_constant_override("outline_size", 1)
	# Replace inline conditional with standard if/else
	if is_user:
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content_vbox.add_child(time_label)
	
	bubble_container.add_child(bubble)
	
	if is_user:
		# User messages don't need spacer after
		pass
	else:
		# AI message - no spacer needed since it's full width
		pass
	
	return bubble_container

func _create_error_message_bubble(text: String, timestamp: String) -> Control:
	var bubble_container = HBoxContainer.new()
	bubble_container.custom_minimum_size.y = 60
	
	# Error message - full width with red styling
	var bubble = PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Error bubble styling
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.8, 0.2, 0.2, 0.3)  # Semi-transparent red
	style_box.border_color = Color(0.8, 0.2, 0.2, 1.0)  # Red border
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 8
	style_box.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style_box)
	
	# Message content
	var content_vbox = VBoxContainer.new()
	bubble.add_child(content_vbox)
	
	# Error text (selectable)
	var error_label = TextEdit.new()
	error_label.editable = false
	error_label.text = "⚠️ Error: " + text
	error_label.add_theme_color_override("font_color", Color.WHITE)
	error_label.add_theme_color_override("background_color", Color.TRANSPARENT)
	error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	error_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	error_label.scroll_fit_content_height = true
	error_label.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content_vbox.add_child(error_label)
	
	# Timestamp
	var time_label = Label.new()
	time_label.text = timestamp
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	time_label.add_theme_font_override("font", ThemeDB.fallback_font)
	time_label.add_theme_constant_override("outline_size", 1)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content_vbox.add_child(time_label)
	
	bubble_container.add_child(bubble)
	return bubble_container

func _start_reasoning_trace_simulation():
	# Create timer for updating reasoning traces
	if reasoning_update_timer:
		reasoning_update_timer.queue_free()
	
	reasoning_update_timer = Timer.new()
	reasoning_update_timer.wait_time = 2.5  # Update every 2.5 seconds for detailed steps
	reasoning_update_timer.timeout.connect(_update_reasoning_trace)
	add_child(reasoning_update_timer)
	reasoning_update_timer.start()

func _update_reasoning_trace():
	if not current_reasoning_bubble:
		return
	
	var trace_label = current_reasoning_bubble.get_meta("trace_label", null) as RichTextLabel
	if not trace_label:
		return
	
	# Simulate detailed reasoning steps (more realistic for DeepSeek R1)
	var reasoning_steps = [
		"�� **Initial Analysis**\nLet me carefully examine what the user is asking for. I need to understand the core requirements and any implicit constraints or expectations.",
		
		"💭 **Problem Decomposition** \nBreaking this down into smaller, manageable components:\n- Understanding the domain context\n- Identifying the key technical challenges\n- Considering potential edge cases",
		
		"🧩 **Requirements Analysis**\nKey requirements I've identified:\n- Functional requirements (what it should do)\n- Non-functional requirements (performance, maintainability)\n- Technical constraints and limitations",
		
		"⚙️ **Approach Evaluation**\nConsidering multiple approaches:\n1. Direct implementation vs abstracted solution\n2. Performance vs simplicity trade-offs\n3. Maintenance and extensibility considerations",
		
		"🏗️ **Architecture Planning**\nDesigning the overall structure:\n- Component relationships\n- Data flow patterns\n- Interface definitions\n- Error handling strategies",
		
		"🎯 **Implementation Strategy**\nOptimizing the solution:\n- Following best practices and patterns\n- Ensuring code readability and maintainability\n- Considering future scalability needs",
		
		"✅ **Solution Validation**\nVerifying the approach:\n- Checking against requirements\n- Considering potential issues\n- Ensuring robustness and reliability",
		
		"📝 **Response Preparation**\nStructuring the final response:\n- Clear explanations and examples\n- Step-by-step implementation guidance\n- Additional considerations and next steps"
	]
	
	# Add a new reasoning step
	var current_step_count = reasoning_trace_text.count("**") / 2  # Count completed steps by bold markers
	if current_step_count < reasoning_steps.size():
		var new_step = reasoning_steps[current_step_count]
		if not reasoning_trace_text.is_empty():
			reasoning_trace_text += "\n\n"
		reasoning_trace_text += "[color=cyan]Step " + str(current_step_count + 1) + ":[/color] " + new_step
		
		trace_label.text = reasoning_trace_text
		
		# Auto-scroll the trace area
		await get_tree().process_frame
		var trace_scroll = current_reasoning_bubble.get_meta("trace_scroll", null) as ScrollContainer
		if trace_scroll and trace_scroll.visible:
			trace_scroll.scroll_vertical = trace_scroll.get_v_scroll_bar().max_value

func _convert_live_to_permanent_reasoning_trace():
	print("[AIDock] Converting live reasoning trace to permanent")
	if current_reasoning_bubble and not reasoning_trace_text.is_empty():
		# Replace the live typing bubble with a permanent one in the same parent container
		var parent := current_reasoning_bubble.get_parent()
		if parent:
			var idx: int = parent.get_child_index(current_reasoning_bubble)
			var permanent_bubble = _create_permanent_reasoning_trace(reasoning_trace_text)
			parent.add_child(permanent_bubble)
			parent.move_child(permanent_bubble, idx)
			reasoning_trace_text = ""
			current_reasoning_bubble.queue_free()
			current_reasoning_bubble = null

func _on_real_reasoning_trace(trace: String):
	print("[AIDock] Received real reasoning trace from API")
	# Replace the simulated reasoning trace with the real one
	reasoning_trace_text = trace
	
	# Update the live reasoning indicator if it exists
	if current_reasoning_bubble:
		var trace_label = current_reasoning_bubble.get_meta("trace_label", null) as RichTextLabel
		if trace_label:
			trace_label.text = trace
			print("[AIDock] Updated live reasoning trace with real data")

func _on_send_pressed():
	_process_user_input()

func _create_file_dialog():
	# Create file dialog for attachments
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.use_native_dialog = true  # Use native OS file picker
	file_dialog.add_filter("*", "All Files")
	file_dialog.add_filter("*.txt,*.md,*.pdf,*.doc,*.docx", "Documents")
	file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.gif,*.bmp", "Images")
	file_dialog.add_filter("*.gd,*.cs,*.py,*.js,*.ts", "Code Files")
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

func _on_attach_pressed():
	# Open native file picker
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_file_selected(file_path: String):
	# Add file to attachments
	attached_files.append(file_path)
	
	# Show attachment in chat
	var file_name = file_path.get_file()
	var file_size = FileAccess.get_file_as_bytes(file_path).size()
	var attachment_text = "[📎 Attached] %s (%d bytes)" % [file_name, file_size]
	
	# Get current chat container and add attachment message
	var current_chat = chat_tabs.get_current_tab_control()
	var scroll = current_chat.get_child(0) as ScrollContainer
	var msg_container = scroll.get_child(0) as VBoxContainer
	
	var attachment_bubble = _create_message_bubble(attachment_text, true, _get_current_time())
	msg_container.add_child(attachment_bubble)
	
	# Auto-scroll to bottom
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
	
	print("File attached: ", file_path)

func _read_file_content(file_path: String) -> String:
	# Read file content for LLM context
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		return content
	return "[Error: Could not read file]"

func _on_clear_attachments_pressed():
	# Clear all attached files
	if attached_files.size() > 0:
		attached_files.clear()
		
		# Show confirmation in chat
		var current_chat = chat_tabs.get_current_tab_control()
		var scroll = current_chat.get_child(0) as ScrollContainer
		var msg_container = scroll.get_child(0) as VBoxContainer
		
		var clear_bubble = _create_message_bubble("🗑️ Attachments cleared", false, _get_current_time())
		msg_container.add_child(clear_bubble)
		
		# Auto-scroll to bottom
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
		
		print("Attachments cleared")
	else:
		print("No attachments to clear")

func _on_input_changed():
	# Auto-resize input field based on content
	pass

func _on_input_field_gui_input(event: InputEvent):
	# Handle Shift+Enter to send message
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and event.shift_pressed:
			# Prevent the newline from being added
			get_viewport().set_input_as_handled()
			# Send the message
			_process_user_input()



func _on_options_pressed():
	# Show the options popup menu to the left of the button
	var button_pos = options_button.global_position
	var button_size = options_button.size
	var popup_size = Vector2(200, 120)  # Approximate popup size
	
	# Position to the left of the button, within bounds
	var popup_x = button_pos.x - popup_size.x
	var popup_y = button_pos.y + button_size.y
	
	# Ensure popup stays within screen bounds
	if popup_x < 0:
		popup_x = button_pos.x + button_size.x  # Fallback to right side
	
	options_popup.popup()
	options_popup.position = Vector2i(popup_x, popup_y)
	options_popup.size = Vector2i(popup_size.x, popup_size.y)

func _on_options_menu_selected(id: int):
	match id:
		0:  # Close Current Chat
			_close_current_chat()
		1:  # Clear All Chats
			_clear_all_chats()
		2:  # Export Chat as Markdown
			_export_chat_markdown()
		3:  # Refresh Models
			_refresh_models()
		4:  # Test Connection
			_test_connection()
		5:  # Session Statistics
			_show_session_stats()
		6:  # Auto-expand Reasoning
			_toggle_auto_expand_reasoning()
		7:  # Test Reasoning Trace
			_test_reasoning_trace()
		8:  # Give Feedback
			_give_feedback()

func _close_current_chat():
	if ai_session_manager:
		var current_session = ai_session_manager.get_current_session()
		if current_session:
			ai_session_manager.remove_session(current_session)

func _clear_all_chats():
	if ai_session_manager:
		# Clear all sessions (manager keeps one empty session)
		ai_session_manager.clear_all_sessions()
		
		# Remove only chat tabs from UI (keep Assets)
		for i in range(chat_tabs.get_tab_count() - 1, -1, -1):
			var tab = chat_tabs.get_child(i)
			if tab is Control and tab.name != "Assets":
				chat_tabs.remove_child(tab)
				tab.queue_free()
		
		# Clear the mapping for chat sessions
		session_to_tab_mapping.clear()
		
		# Ensure there is a single session and name it Chat 1
		var sessions = ai_session_manager.get_sessions()
		var session
		if sessions.size() == 0:
			session = ai_session_manager.create_new_session("Chat 1")
		else:
			session = sessions[0]
			session.session_title = "Chat 1"
			ai_session_manager.switch_to_session(session)
		
		# Recreate the single chat tab and switch to it
		_create_session_tab(session)
		chat_tabs.current_tab = max(chat_tabs.get_tab_count() - 1, 0)
		current_chat_id = chat_tabs.current_tab
		
		print("All chats cleared; reset to Chat 1 and kept Assets tab")

func _export_chat_markdown():
	if ai_session_manager:
		var markdown_content = ai_session_manager.export_current_session()
		print("Chat exported as markdown:")
		print(markdown_content)
		# TODO: Save to file system when file dialogs are implemented

func _refresh_models():
	if ai_session_manager:
		print("[AIDock] Refreshing models from OpenRouter...")
		ai_session_manager.refresh_models()
		await ai_session_manager.model_registry.models_fetched
		_populate_model_selector()
		print("[AIDock] Models refreshed")

func _test_connection():
	if ai_session_manager:
		print("[AIDock] Testing OpenRouter connection...")
		var success = await ai_session_manager.test_connection()
		if success:
			_add_ai_message_to_ui("✅ Connection test successful! OpenRouter API is working correctly.")
		else:
			_add_error_message_to_ui("❌ Connection test failed. Please check your API key and internet connection.")

func _show_session_stats():
	if ai_session_manager:
		var stats = ai_session_manager.get_session_stats()
		var stats_text = "📊 **Session Statistics**\n\n"
		stats_text += "• Total Sessions: " + str(stats["total_sessions"]) + "\n"
		stats_text += "• Total Messages: " + str(stats["total_messages"]) + "\n"
		stats_text += "• Current Model: " + stats["current_model"] + "\n"
		# Replace inline conditional strings
		if stats["api_configured"]:
			stats_text += "• API Configured: Yes\n"
		else:
			stats_text += "• API Configured: No\n"
		if auto_expand_reasoning:
			stats_text += "• Auto-expand Reasoning: Yes\n"
		else:
			stats_text += "• Auto-expand Reasoning: No\n"
		
		_add_ai_message_to_ui(stats_text)

func _toggle_auto_expand_reasoning():
	auto_expand_reasoning = !auto_expand_reasoning
	var status_text = "🧠 **Reasoning Trace Settings**\n\n"
	if auto_expand_reasoning:
		status_text += "Auto-expand reasoning traces: **Enabled**\n\n"
	else:
		status_text += "Auto-expand reasoning traces: **Disabled**\n\n"
	if auto_expand_reasoning:
		status_text += "Reasoning traces will now automatically expand when using reasoning models like DeepSeek R1."
	else:
		status_text += "You can expand reasoning traces manually using the toggle button on each AI message."
	_add_ai_message_to_ui(status_text)

func _test_reasoning_trace():
	print("[AIDock] Testing reasoning trace creation...")
	var test_trace = "[color=cyan]Step 1:[/color] 🔍 This is a test reasoning step\n"
	test_trace += "[color=cyan]Step 2:[/color] 💭 Testing the reasoning trace display\n"
	test_trace += "[color=cyan]Step 3:[/color] 🎯 Checking if the UI works correctly\n"
	test_trace += "[color=cyan]Step 4:[/color] ✅ Test reasoning trace complete!"
	
	_add_reasoning_trace_to_ui(test_trace)
	_add_ai_message_to_ui("🧪 **Test reasoning trace created!** Check above for the reasoning bubble.")

func _give_feedback():
	print("Opening feedback form...")
	# TODO: Implement feedback submission
	pass

func _on_close_pressed():
	# Hide the AI Assistant dock
	if get_parent():
		visible = false

func _on_ai_mode_toggled(pressed: bool):
	if pressed:
		ai_mode_button.text = "🤖 Agent"
	else:
		ai_mode_button.text = "💬 Chat"

func _on_create_mode_toggled(pressed: bool):
	if pressed:
		create_mode_button.text = "🎨 Create"
		# When entering Create mode, we keep chat flow but expect final action to include create_image
	else:
		create_mode_button.text = "🎨 Create"

func _on_add_chat_pressed():
	_create_new_chat()

func _on_tab_changed(tab_index: int):
	current_chat_id = tab_index

func _on_tab_right_clicked(tab_index: int):
	# Close tab on right click
	if ai_session_manager and ai_session_manager.get_sessions().size() > 1:  # Don't close if it's the only tab
		_close_chat_tab(tab_index)

func _close_chat_tab(tab_index: int):
	# Find the session corresponding to this tab using the mapping
	if ai_session_manager and tab_index >= 0 and tab_index < chat_tabs.get_tab_count():
		# Find session ID by tab index
		var session_id_to_remove = ""
		for session_id in session_to_tab_mapping:
			if session_to_tab_mapping[session_id] == tab_index:
				session_id_to_remove = session_id
				break
		
		# Remove the session if found
		if not session_id_to_remove.is_empty():
			var sessions = ai_session_manager.get_sessions()
			for session in sessions:
				if session.session_id == session_id_to_remove:
					ai_session_manager.remove_session(session)
					break
		else:
			print("[AIDock] Warning: Could not find session for tab index ", tab_index)

func _process_user_input():
	var user_text = input_field.text.strip_edges()
	if user_text.is_empty():
		return
	_add_user_message_to_ui(user_text)
	if Engine.is_editor_hint():
		var ei = Engine.get_singleton("EditorInterface")
		user_text = tagger.apply_tags(user_text, ei)
	# Prepend small instruction preamble and custom instructions
	var preamble = "First, write a concise explanation (2-4 sentences). Then output a [gds_actions]...[/gds_actions] block with one command per line using ONLY these verbs and exact signatures:\n- create_file(\"res://path\") + a fenced code block with '# New file: res://path' and file contents\n- create_scene(\"res://path.tscn\", \"RootName\", \"RootType\")\n- create_node(\"Name\", \"NodeType\", \"res://scene.tscn\", \"ParentPath\", { property: value })\n- edit_node(\"NodeName\", \"res://scene.tscn\", { property: value })\n- add_subresource(\"NodeName\", \"res://scene.tscn\", \"SubResType\", { property: value })\n- edit_subresource(\"NodeName\", \"res://scene.tscn\", \"SubResPropName\", { property: value })\n- assign_script(\"NodeName\", \"res://scene.tscn\", \"res://script.gd\")\n- edit_script(\"res://script.gd\") with the updated content included in a fenced code block\n- create_image({ prompt: string, aspect_ratio: string (e.g. '1:1'), seed: int, output_format: string ('png' or 'jpeg'), output_prefix: string, exact_output_path: string (e.g. 'res://art/generated/<prefix>_<seed>.<ext>') })  // SD-3.5-Flash only\n- spritesheet_to_spriteframes(\"NodePath\", \"res://scene.tscn\", { texture: \"res://path.png\", rows: int, cols: int, frame_width: int, frame_height: int, animations: [ { name: string, start: int, length: int, speed: float, loop: bool } ], assign_to_property: \"sprite_frames\" })\nDo NOT invent other verbs (e.g. edit_project_settings). Close the actions with [/gds_actions].\n\n"
	var ci = ""
	if ai_session_manager:
		ci = ai_session_manager.get_custom_instructions()
	if ci != "":
		user_text = preamble + ci + "\n\n" + user_text
	else:
		user_text = preamble + user_text
	# Apply context tags
	for file_path in attached_files:
		var is_image = _is_image_file(file_path)
		ai_session_manager.add_attachment(file_path, is_image)
	# Clear input and attachments
	input_field.text = ""
	attached_files.clear()
	# Mark the last user group as pending for this response
	# If in Create mode and the user says to generate, we still let the model output create_image actions; otherwise normal
	if not ai_session_manager.send_message(user_text):
		_add_error_message_to_ui("Failed to send message. Please check your configuration.")

func _add_user_message_to_ui(text: String):
	var current_chat = chat_tabs.get_current_tab_control()
	if current_chat:
		var scroll = current_chat.get_child(0) as ScrollContainer
		var msg_container = scroll.get_child(0) as VBoxContainer
		
		# Create a collapsible group for this user prompt and its attempts
		# The first attempt is created immediately; further attempts added on re-run
		# Group structure: VBoxContainer -> user header + attempts controls + attempts stack
		var group = _build_attempt_group(text)
		msg_container.add_child(group)
		pending_attempt_group = group
		
		# Auto-scroll to bottom
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

func _add_ai_message_to_ui(text: String, metadata: Dictionary = {}):
	var current_chat = chat_tabs.get_current_tab_control()
	if current_chat:
		var scroll = current_chat.get_child(0) as ScrollContainer
		var msg_container = scroll.get_child(0) as VBoxContainer
		var enhanced_text = text
		if metadata.has("usage"):
			var usage = metadata["usage"]
			if usage.has("total_tokens"):
				enhanced_text += "\n\n*Tokens used: " + str(usage["total_tokens"]) + "*"
		enhanced_text = markdown_renderer.render(enhanced_text)
		var ai_bubble = _create_ai_bubble_bbcode(enhanced_text, _get_current_time())
		msg_container.add_child(ai_bubble)
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
		var actions = actions_manager.parse_actions_from_text(text, 0)
		if actions.size() > 0:
			actions_manager.render_actions(actions, msg_container)
			# Ensure the newly added buttons are visible
			await get_tree().process_frame
			scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
		rating_container.visible = true

func _add_error_message_to_ui(error_text: String):
	var current_chat = chat_tabs.get_current_tab_control()
	if current_chat:
		var scroll = current_chat.get_child(0) as ScrollContainer
		var msg_container = scroll.get_child(0) as VBoxContainer
		
		var error_bubble = _create_error_message_bubble(error_text, _get_current_time())
		msg_container.add_child(error_bubble)
		
		# Auto-scroll to bottom
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

func _is_image_file(file_path: String) -> bool:
	var extension = file_path.get_extension().to_lower()
	return extension in ["png", "jpg", "jpeg", "gif", "bmp", "webp", "svg"]

func _add_reasoning_trace_to_ui(trace_text: String):
	print("[AIDock] Adding reasoning trace to UI with text: ", trace_text.substr(0, 50), "...")
	
	var current_chat = chat_tabs.get_current_tab_control()
	if current_chat:
		var scroll = current_chat.get_child(0) as ScrollContainer
		var msg_container = scroll.get_child(0) as VBoxContainer
		
		var reasoning_bubble = _create_permanent_reasoning_trace(trace_text)
		msg_container.add_child(reasoning_bubble)
		
		print("[AIDock] Reasoning bubble added to message container")
		
		# Auto-scroll to bottom
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
	else:
		print("[AIDock] ERROR: No current chat found!")

func _create_permanent_reasoning_trace(trace_text: String) -> Control:
	var bubble_container = HBoxContainer.new()
	bubble_container.custom_minimum_size.y = 60
	bubble_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var bubble = PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Reasoning trace bubble styling
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.2, 0.3, 0.7)  # Semi-transparent blue
	style_box.border_color = Color(0.3, 0.5, 0.7, 1.0)  # Blue border
	style_box.border_width_left = 2
	style_box.border_width_right = 2  
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 12
	style_box.corner_radius_top_left = 12
	style_box.corner_radius_top_right = 12
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 8
	style_box.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style_box)
	
	# Content container
	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_child(content_vbox)
	
	# Header with expand/collapse
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(header_hbox)
	
	var header_label = Label.new()
	header_label.text = "🧠 Reasoning Trace"
	header_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_label)
	

	
	var expand_button = Button.new()
	# Replace inline conditional
	if auto_expand_reasoning:
		expand_button.text = "▲"
	else:
		expand_button.text = "▼"
	expand_button.flat = true
	expand_button.custom_minimum_size = Vector2(25, 25)
	expand_button.tooltip_text = "Show/hide reasoning steps"
	header_hbox.add_child(expand_button)
	
	# Reasoning content (respects auto-expand setting)
	var trace_scroll = ScrollContainer.new()
	trace_scroll.custom_minimum_size.y = 120
	trace_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trace_scroll.visible = auto_expand_reasoning
	trace_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_vbox.add_child(trace_scroll)
	
	var trace_label = TextEdit.new()
	trace_label.editable = false
	trace_label.text = trace_text
	trace_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	trace_label.add_theme_color_override("background_color", Color.TRANSPARENT)
	trace_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trace_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trace_label.scroll_fit_content_height = true
	trace_label.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	trace_scroll.add_child(trace_label)
	
	# Connect expand button
	expand_button.pressed.connect(_toggle_reasoning_trace.bind(trace_scroll, expand_button))
	
	# Timestamp
	var time_label = Label.new()
	time_label.text = _get_current_time()
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	time_label.add_theme_font_override("font", ThemeDB.fallback_font)
	time_label.add_theme_constant_override("outline_size", 1)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content_vbox.add_child(time_label)
	
	bubble_container.add_child(bubble)
	return bubble_container

func _add_error_message_to_ui_direct(error_text: String):
	# Add error message directly without needing current chat
	print("[AIDock] Direct Error: ", error_text)

func _get_current_time() -> String:
	var time = Time.get_datetime_dict_from_system()
	var am_pm: String
	if time.hour < 12:
		am_pm = "AM"
	else:
		am_pm = "PM"
	var hour: int
	if time.hour <= 12:
		hour = time.hour
	else:
		hour = time.hour - 12
	if hour == 0:
		hour = 12
	return "%d:%02d %s" % [hour, time.minute, am_pm]

func _copy_text_to_clipboard(text: String):
	# Remove BBCode formatting before copying
	var plain_text = text
	
	# Simple BBCode tag removal (handles most common cases)
	var regex = RegEx.new()
	regex.compile("\\[/?[^\\]]*\\]")
	plain_text = regex.sub(plain_text, "", true)
	
	# Copy to clipboard
	DisplayServer.clipboard_set(plain_text)
	
	# Show a brief confirmation (optional)
	print("[AIDock] Text copied to clipboard") 

func _on_tab_bar_gui_input(event: InputEvent):
	var tab_bar = chat_tabs.get_tab_bar()
	if event is InputEventMouseMotion:
		var pos = event.position
		var idx = tab_bar.get_tab_idx_at_point(pos)
		if idx >= 0:
			hovered_tab_index = idx
			_show_close_button_for_tab(idx)
		else:
			hovered_tab_index = -1
			close_tab_button.visible = false

func _show_close_button_for_tab(tab_index: int):
	var tab_bar = chat_tabs.get_tab_bar()
	if not tab_bar:
		return
	var rect = tab_bar.get_tab_rect(tab_index)
	close_tab_button.position = Vector2(rect.position.x + rect.size.x - close_tab_button.size.x - 2, rect.position.y + 2)
	close_tab_button.visible = true

func _on_close_hovered_tab_pressed():
	if hovered_tab_index >= 0:
		_close_chat_tab(hovered_tab_index)
		close_tab_button.visible = false

# New signal handlers for AI integration

func _on_model_selected(index: int):
	if model_selector.get_item_count() > index:
		var model_data = model_selector.get_item_metadata(index)
		if model_data and ai_session_manager:
			ai_session_manager.set_current_model(model_data)
			print("[AIDock] Selected model: ", model_data.get("name", "Unknown"))

func _on_category_selected(index: int):
	_populate_model_selector()

func _on_session_created(session):
	# Create UI tab for the new session
	_create_session_tab(session)

func _on_session_switched(session):
	# Switch to the corresponding tab
	if session_to_tab_mapping.has(session.session_id):
		var tab_index = session_to_tab_mapping[session.session_id]
		if tab_index < chat_tabs.get_tab_count():
			chat_tabs.current_tab = tab_index
			current_chat_id = tab_index

func _on_session_removed(session_id: String):
	# Remove the corresponding tab
	if session_to_tab_mapping.has(session_id):
		var tab_index = session_to_tab_mapping[session_id]
		_remove_session_tab(session_id, tab_index)

func _on_model_changed(model: Dictionary):
	# Update UI to reflect model change
	print("[AIDock] Model changed to: ", model.get("name", "Unknown"))
	
	# Update model selector if needed
	for i in range(model_selector.get_item_count()):
		var metadata = model_selector.get_item_metadata(i)
		if metadata and metadata.get("id") == model.get("id"):
			model_selector.selected = i
			break

func _on_ai_error(error_message: String):
	print("[AIDock] AI Error: ", error_message)
	_add_error_message_to_ui(error_message)

func _create_session_tab(session):
	# Skip if we already have a tab for this session
	if session_to_tab_mapping.has(session.session_id):
		return
	var tab_index = chat_tabs.get_tab_count()
	
	# Create chat tab container
	var chat_container = VBoxContainer.new()
	chat_container.name = session.session_title
	
	# Message scroll area
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_container.add_child(scroll)
	
	# Message container
	var msg_container = VBoxContainer.new()
	msg_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(msg_container)
	
	chat_tabs.add_child(chat_container)
	# Ensure the tab shows the proper title
	chat_tabs.set_tab_title(tab_index, session.session_title)
	_refresh_tab_titles()
	
	# Map session to tab
	session_to_tab_mapping[session.session_id] = tab_index
	
	# Connect session signals for this specific session
	if not session.assistant_message.is_connected(_on_assistant_message):
		session.assistant_message.connect(_on_assistant_message)
	if not session.typing_started.is_connected(_on_typing_started):
		session.typing_started.connect(_on_typing_started)
	if not session.typing_finished.is_connected(_on_typing_finished):
		session.typing_finished.connect(_on_typing_finished)
	
	# Connect reasoning trace signal if available
	if session.has_signal("reasoning_trace_updated"):
		if not session.reasoning_trace_updated.is_connected(_on_real_reasoning_trace):
			session.reasoning_trace_updated.connect(_on_real_reasoning_trace)
	
	# Add tab management buttons if this is the first tab
	if add_chat_button == null or !is_instance_valid(add_chat_button):
		_add_plus_button_to_tabs()
		_add_tab_close_button(max(chat_tabs.get_tab_count() - 1, 0))
	
	# Add welcome message
	_add_welcome_message(msg_container)
	
	# Switch to new tab
	chat_tabs.current_tab = tab_index
	current_chat_id = tab_index
	print("[AIDock] Created tab #", tab_index, " titled ", session.session_title)

func _remove_session_tab(session_id: String, tab_index: int):
	if tab_index >= 0 and tab_index < chat_tabs.get_tab_count():
		var tab_to_remove = chat_tabs.get_child(tab_index)
		chat_tabs.remove_child(tab_to_remove)
		tab_to_remove.queue_free()
		
		# Update mapping for remaining tabs
		session_to_tab_mapping.erase(session_id)
		for id in session_to_tab_mapping:
			if session_to_tab_mapping[id] > tab_index:
				session_to_tab_mapping[id] -= 1

func _on_assistant_message(text: String, metadata: Dictionary):
	# Check if this was a reasoning model and preserve the trace
	var current_model = ai_session_manager.get_current_model()
	var is_reasoning = ai_session_manager.is_model_reasoning(current_model)
	
	print("[AIDock] Assistant message received. Is reasoning model: ", is_reasoning)
	print("[AIDock] Reasoning trace text length: ", reasoning_trace_text.length())
	
	# Route the AI response into the active attempt
	_append_assistant_to_current_attempt(text, metadata)
	
	# For reasoning models, the live trace should have already been converted to permanent
	# No need to add any additional reasoning traces here
	if is_reasoning:
		print("[AIDock] Reasoning model completed - live trace already converted to permanent")

func _on_typing_started():
	# Show typing indicator
	var current_chat = chat_tabs.get_current_tab_control()
	if current_chat:
		var scroll = current_chat.get_child(0) as ScrollContainer
		var msg_container = scroll.get_child(0) as VBoxContainer
		
		# Check if current model is a reasoning model
		var current_model = ai_session_manager.get_current_model()
		var is_reasoning = ai_session_manager.is_model_reasoning(current_model)
		
		# Place live reasoning indicator into the active attempt's reasoning region
		var target_group: VBoxContainer = pending_attempt_group
		if target_group == null or !is_instance_valid(target_group):
			for i in range(msg_container.get_child_count() - 1, -1, -1):
				var child = msg_container.get_child(i)
				if child is VBoxContainer and String(child.get_meta("type", "")) == "attempt_group":
					target_group = child
					break
		if target_group:
			var stack := target_group.get_node("attempts_stack") as VBoxContainer
			var idx := int(target_group.get_meta("current_attempt_index"))
			var attempt := stack.get_child(idx) as VBoxContainer
			var reasoning_region := attempt.get_meta("reasoning_region") as VBoxContainer
			var typing_bubble = _create_reasoning_indicator(is_reasoning)
			typing_bubble.name = "typing_indicator"
			reasoning_region.add_child(typing_bubble)
			current_reasoning_bubble = typing_bubble
		else:
			var typing_bubble_fallback = _create_reasoning_indicator(is_reasoning)
			typing_bubble_fallback.name = "typing_indicator"
			msg_container.add_child(typing_bubble_fallback)
			current_reasoning_bubble = typing_bubble_fallback
		
		# Start reasoning trace timer for reasoning models
		if is_reasoning:
			_start_reasoning_trace_simulation()
		
		# Auto-scroll to bottom
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

func _on_typing_finished():
	# Stop reasoning trace updates
	if reasoning_update_timer:
		reasoning_update_timer.stop()
	
	# Convert the live reasoning bubble to a permanent one
	_convert_live_to_permanent_reasoning_trace()
	
	# Remove typing indicator
	var current_chat = chat_tabs.get_current_tab_control()
	if current_chat:
		var scroll = current_chat.get_child(0) as ScrollContainer
		var msg_container = scroll.get_child(0) as VBoxContainer
		
		# Find and remove typing indicator
		for child in msg_container.get_children():
			if child.name == "typing_indicator":
				child.queue_free()
				break
	
	# Clear live reasoning bubble reference but keep the trace text for potential reuse
	current_reasoning_bubble = null

func _create_reasoning_indicator(is_reasoning_model: bool) -> Control:
	var bubble_container = VBoxContainer.new()
	bubble_container.custom_minimum_size.y = 60
	bubble_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var bubble = PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Bubble styling with different colors for reasoning models
	var style_box = StyleBoxFlat.new()
	if is_reasoning_model:
		style_box.bg_color = Color(0.15, 0.25, 0.35, 1.0)  # Slightly blue for reasoning
	else:
		style_box.bg_color = Color(0.2, 0.2, 0.2, 1.0)  # Standard gray
	
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 12
	style_box.corner_radius_top_left = 12
	style_box.corner_radius_top_right = 12
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 8
	style_box.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style_box)
	
	# Content container
	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_child(content_vbox)
	
	# Header with expand/collapse button
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(header_hbox)
	
	# Status text
	var status_label = Label.new()
	if is_reasoning_model:
		status_label.text = "🧠 AI is reasoning step-by-step..."
	else:
		status_label.text = "🤖 AI is thinking..."
	status_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(status_label)
	
	if is_reasoning_model:
		# Expand/collapse button for reasoning traces
		var expand_button = Button.new()
		expand_button.text = "▼"
		expand_button.flat = true
		expand_button.custom_minimum_size = Vector2(25, 25)
		expand_button.tooltip_text = "Show/hide reasoning trace"
		header_hbox.add_child(expand_button)
		
		# Reasoning trace area (initially collapsed, unless auto-expand is enabled)
		var trace_scroll = ScrollContainer.new()
		trace_scroll.custom_minimum_size.y = 150
		trace_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trace_scroll.visible = auto_expand_reasoning
		trace_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content_vbox.add_child(trace_scroll)
		
		var trace_label = RichTextLabel.new()
		trace_label.bbcode_enabled = true
		trace_label.fit_content = false  # Let it wrap properly
		trace_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trace_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		trace_label.text = "[color=cyan]Reasoning trace will appear here...[/color]"
		trace_label.add_theme_color_override("default_color", Color(0.8, 0.9, 1.0, 1.0))
		trace_scroll.add_child(trace_label)
		
		# Set initial button state
		if auto_expand_reasoning:
			expand_button.text = "▲"
		else:
			expand_button.text = "▼"
		
		# Connect expand button
		expand_button.pressed.connect(_toggle_reasoning_trace.bind(trace_scroll, expand_button))
		
		# Store references for updates
		bubble_container.set_meta("trace_label", trace_label)
		bubble_container.set_meta("trace_scroll", trace_scroll)
	
	bubble_container.add_child(bubble)
	return bubble_container

func _toggle_reasoning_trace(trace_scroll: ScrollContainer, expand_button: Button):
	trace_scroll.visible = !trace_scroll.visible
	if trace_scroll.visible:
		expand_button.text = "▲"
	else:
		expand_button.text = "▼"
	
	# Auto-scroll to show the trace
	if trace_scroll.visible:
		await get_tree().process_frame
		var current_chat = chat_tabs.get_current_tab_control()
		if current_chat:
			var scroll = current_chat.get_child(0) as ScrollContainer
			scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value 

func _create_ai_bubble_bbcode(bbcode_text: String, timestamp: String) -> Control:
	var bubble_container = HBoxContainer.new()
	bubble_container.custom_minimum_size.y = 60
	var bubble = PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 12
	style_box.corner_radius_top_left = 12
	style_box.corner_radius_top_right = 12
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 8
	style_box.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style_box)
	var content_vbox = VBoxContainer.new()
	bubble.add_child(content_vbox)
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.selection_enabled = true
	rtl.context_menu_enabled = true
	rtl.text = bbcode_text
	# Keyboard shortcuts for selection/copy
	rtl.gui_input.connect(_on_rtl_gui_input.bind(rtl))
	content_vbox.add_child(rtl)
	# Copy row
	var copy_row = HBoxContainer.new()
	copy_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spacer = Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; copy_row.add_child(spacer)
	var copy_btn = Button.new(); copy_btn.text = "Copy"; copy_btn.flat = true; copy_btn.tooltip_text = "Copy message"; copy_btn.pressed.connect(func(): _copy_text_to_clipboard(bbcode_text)); copy_row.add_child(copy_btn)
	content_vbox.add_child(copy_row)
	var time_label = Label.new()
	time_label.text = timestamp
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content_vbox.add_child(time_label)
	bubble_container.add_child(bubble)
	return bubble_container 

func _on_rtl_gui_input(event: InputEvent, rtl: RichTextLabel):
	if event is InputEventKey and event.pressed:
		var meta_or_ctrl: bool = event.meta_pressed or event.ctrl_pressed
		if meta_or_ctrl and event.keycode == KEY_A:
			rtl.select_all()
			get_viewport().set_input_as_handled()
		elif meta_or_ctrl and event.keycode == KEY_C:
			var sel := ""
			if rtl.has_method("get_selected_text"):
				sel = rtl.get_selected_text()
			if sel.is_empty():
				_copy_text_to_clipboard(rtl.text)
			else:
				DisplayServer.clipboard_set(sel)
			get_viewport().set_input_as_handled()

func _on_favorite_pressed():
	if ai_session_manager and ai_session_manager.get_current_session():
		var fav = !ai_session_manager.is_favorite(ai_session_manager.get_current_session())
		ai_session_manager.set_favorite(ai_session_manager.get_current_session(), fav)
		if fav:
			favorites_toggle.text = "★"
		else:
			favorites_toggle.text = "☆"

func _on_delete_chat_pressed():
	if ai_session_manager and ai_session_manager.get_current_session():
		ai_session_manager.delete_conversation(ai_session_manager.get_current_session())

func _on_custom_instructions_changed():
	if ai_session_manager:
		ai_session_manager.set_custom_instructions(custom_instructions_edit.text) 

func _on_generate_image(prompt: String, negative: String, model: String, steps: int, guidance: float, seed: int, size: Vector2i, progress: ProgressBar, preview: TextureRect) -> void:
	progress.value = 10
	stability.api_key = EnvLoader.get_env_var("STABILITY_API_KEY")
	var bytes = await stability.text_to_image_sd3(prompt, negative, size.x, size.y, steps, guidance, seed, model)
	progress.value = 70
	if bytes.is_empty():
		_add_error_message_to_ui("Stable Diffusion generation failed")
		progress.value = 0
		return
	var path = StabilityClient.write_png_to_res(bytes, "img")
	progress.value = 90
	var tex = StabilityClient.load_texture_from_png_bytes(bytes)
	if tex:
		preview.texture = tex
	progress.value = 100
	_add_ai_message_to_ui("Generated image saved: " + path)

func _on_generate_animation(prompt: String, negative: String, model: String, steps: int, guidance: float, seed: int, size: Vector2i, progress: ProgressBar, preview: TextureRect) -> void:
	# Simple N frames loop (example: 8 variants by changing seed)
	stability.api_key = EnvLoader.get_env_var("STABILITY_API_KEY")
	var paths: Array[String] = []
	for i in range(8):
		progress.value = (i * 100) / 8
		var bytes = await stability.text_to_image_sd3(prompt, negative, size.x, size.y, steps, guidance, seed + i, model)
		if bytes.is_empty():
			continue
		var path = StabilityClient.write_png_to_res(bytes, "anim")
		paths.append(path)
		if i == 0:
			var tex = StabilityClient.load_texture_from_png_bytes(bytes)
			if tex:
				preview.texture = tex
	progress.value = 100
	_add_ai_message_to_ui("Generated animation frames: \n" + "\n".join(paths)) 

func _refresh_tab_titles():
	if chat_tabs == null:
		return
	for i in range(chat_tabs.get_tab_count()):
		var child = chat_tabs.get_child(i)
		if child is Control:
			chat_tabs.set_tab_title(i, (child as Control).name)

func _save_last_conversation():
	if ai_session_manager:
		var ok = ai_session_manager.save_current_conversation_to_disk()
		if ok:
			_add_ai_message_to_ui("📝 Saved the most recent conversation locally. It will be restored on reload.")
		else:
			_add_error_message_to_ui("Failed to save the current conversation.")

func _build_attempt_group(prompt_text: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.set_meta("type", "attempt_group")
	group.set_meta("prompt_text", prompt_text)
	group.set_meta("attempts", [])
	group.set_meta("current_attempt_index", 0)
	
	# User message bubble (right-aligned blue) spans the dock width
	var user_bubble := _create_message_bubble(prompt_text, true, _get_current_time())
	group.add_child(user_bubble)
	
	# Controls row BELOW the user message: ◀ Attempt N ▶    Re-run
	var controls_h := HBoxContainer.new()
	controls_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_h.add_theme_constant_override("separation", 6)
	group.add_child(controls_h)
	
	var left_btn := Button.new(); left_btn.text = "◀"; left_btn.flat = true; left_btn.custom_minimum_size = Vector2(22, 22); left_btn.tooltip_text = "Previous attempt"; controls_h.add_child(left_btn)
	var attempt_label := Label.new(); attempt_label.text = "Attempt 1"; attempt_label.add_theme_font_size_override("font_size", 12); controls_h.add_child(attempt_label)
	var right_btn := Button.new(); right_btn.text = "▶"; right_btn.flat = true; right_btn.custom_minimum_size = Vector2(22, 22); right_btn.tooltip_text = "Next attempt"; controls_h.add_child(right_btn)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; controls_h.add_child(spacer)
	var rerun_btn := Button.new(); rerun_btn.text = "Re-run"; rerun_btn.flat = true; rerun_btn.custom_minimum_size = Vector2(56, 22); rerun_btn.tooltip_text = "Re-run this prompt"; controls_h.add_child(rerun_btn)
	
	# Attempts stack (each attempt contains reasoning region + output region)
	var attempts_stack := VBoxContainer.new()
	attempts_stack.name = "attempts_stack"
	attempts_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(attempts_stack)
	
	# Create first attempt container and mark as active
	var first_attempt := _create_attempt_container()
	attempts_stack.add_child(first_attempt)
	_set_active_attempt(group, 0)
	_update_attempt_label(group)
	
	# Wire up signals
	left_btn.pressed.connect(_on_attempt_prev.bind(group))
	right_btn.pressed.connect(_on_attempt_next.bind(group))
	rerun_btn.pressed.connect(_on_attempt_rerun.bind(group))
	
	# Keep references
	group.set_meta("left_btn", left_btn)
	group.set_meta("right_btn", right_btn)
	group.set_meta("attempt_label", attempt_label)
	
	return group

func _create_attempt_container() -> VBoxContainer:
	var attempt := VBoxContainer.new()
	attempt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attempt.visible = true
	# Reasoning region (will host live/permanent reasoning trace)
	var reason_v := VBoxContainer.new()
	reason_v.name = "reasoning_region"
	reason_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attempt.add_child(reason_v)
	# Output region (AI messages)
	var out_v := VBoxContainer.new()
	out_v.name = "output_region"
	out_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attempt.add_child(out_v)
	# Keep quick refs via meta
	attempt.set_meta("reasoning_region", reason_v)
	attempt.set_meta("ai_container", out_v)
	return attempt

func _set_active_attempt(group: VBoxContainer, index: int) -> void:
	var stack := group.get_node("attempts_stack") as VBoxContainer
	for i in range(stack.get_child_count()):
		stack.get_child(i).visible = (i == index)
	group.set_meta("current_attempt_index", index)
	_update_attempt_label(group)

func _update_attempt_label(group: VBoxContainer) -> void:
	var stack := group.get_node("attempts_stack") as VBoxContainer
	var label := group.get_meta("attempt_label") as Label
	label.text = "Attempt %d" % int(group.get_meta("current_attempt_index") + 1)
	# Enable/disable arrows
	var left_btn := group.get_meta("left_btn") as Button
	var right_btn := group.get_meta("right_btn") as Button
	left_btn.disabled = (group.get_meta("current_attempt_index") <= 0)
	right_btn.disabled = (group.get_meta("current_attempt_index") >= stack.get_child_count() - 1)

func _on_attempt_prev(group: VBoxContainer) -> void:
	var idx := int(group.get_meta("current_attempt_index"))
	if idx > 0:
		_set_active_attempt(group, idx - 1)

func _on_attempt_next(group: VBoxContainer) -> void:
	var stack := group.get_node("attempts_stack") as VBoxContainer
	var idx := int(group.get_meta("current_attempt_index"))
	if idx < stack.get_child_count() - 1:
		_set_active_attempt(group, idx + 1)

func _on_attempt_rerun(group: VBoxContainer) -> void:
	# Add a new attempt container and make it active; then resend prompt
	var stack := group.get_node("attempts_stack") as VBoxContainer
	var new_attempt := _create_attempt_container()
	stack.add_child(new_attempt)
	_set_active_attempt(group, stack.get_child_count() - 1)
	pending_attempt_group = group
	# Re-send the original prompt text without adding another user bubble
	var original_text := String(group.get_meta("prompt_text"))
	_resend_prompt(original_text)

func _resend_prompt(original_text: String) -> void:
	var text := original_text
	if Engine.is_editor_hint():
		var ei = Engine.get_singleton("EditorInterface")
		text = tagger.apply_tags(text, ei)
	# Build full prompt with preamble and custom instructions (mirrors _process_user_input)
	var preamble = "First, write a concise explanation (2-4 sentences). Then output a [gds_actions]...[/gds_actions] block with one command per line using ONLY these verbs and exact signatures:\n- create_file(\"res://path\") + a fenced code block with '# New file: res://path' and file contents\n- create_scene(\"res://path.tscn\", \"RootName\", \"RootType\")\n- create_node(\"Name\", \"NodeType\", \"res://scene.tscn\", \"ParentPath\", { property: value })\n- edit_node(\"NodeName\", \"res://scene.tscn\", { property: value })\n- add_subresource(\"NodeName\", \"res://scene.tscn\", \"SubResType\", { property: value })\n- edit_subresource(\"NodeName\", \"res://scene.tscn\", \"SubResPropName\", { property: value })\n- assign_script(\"NodeName\", \"res://scene.tscn\", \"res://script.gd\")\n- edit_script(\"res://script.gd\") with the updated content included in a fenced code block\n- create_image({ prompt: string, aspect_ratio: string (e.g. '1:1'), seed: int, output_format: string ('png' or 'jpeg'), output_prefix: string, exact_output_path: string (e.g. 'res://art/generated/<prefix>_<seed>.<ext>') })  // SD-3.5-Flash only\n- spritesheet_to_spriteframes(\"NodePath\", \"res://scene.tscn\", { texture: \"res://path.png\", rows: int, cols: int, frame_width: int, frame_height: int, animations: [ { name: string, start: int, length: int, speed: float, loop: bool } ], assign_to_property: \"sprite_frames\" })\nDo NOT invent other verbs (e.g. edit_project_settings). Close the actions with [/gds_actions].\n\n"
	var ci = ""
	if ai_session_manager:
		ci = ai_session_manager.get_custom_instructions()
	if ci != "":
		text = preamble + ci + "\n\n" + text
	else:
		text = preamble + text
	# Re-send
	if not ai_session_manager.send_message(text):
		_add_error_message_to_ui("Failed to send message. Please check your configuration.")

func _append_assistant_to_current_attempt(text: String, metadata: Dictionary) -> void:
	# Find the most recent attempt group to attach the assistant message
	var current_chat = chat_tabs.get_current_tab_control()
	if current_chat == null:
		return
	var scroll = current_chat.get_child(0) as ScrollContainer
	var msg_container = scroll.get_child(0) as VBoxContainer
	
	var target_group: VBoxContainer = pending_attempt_group
	if target_group == null or !is_instance_valid(target_group):
		# Fallback: scan from bottom to find last attempt_group
		for i in range(msg_container.get_child_count() - 1, -1, -1):
			var child = msg_container.get_child(i)
			if child is VBoxContainer and String(child.get_meta("type", "")) == "attempt_group":
				target_group = child
				break
	if target_group == null:
		# No group found; fallback to simple AI bubble
		_add_ai_message_to_ui(text, metadata)
		return
	
	# Append bbcode AI bubble inside active attempt's ai_container
	var stack := target_group.get_node("attempts_stack") as VBoxContainer
	var idx := int(target_group.get_meta("current_attempt_index"))
	var attempt := stack.get_child(idx) as VBoxContainer
	var ai_container := attempt.get_meta("ai_container") as VBoxContainer
	var enhanced_text := text
	if metadata.has("usage"):
		var usage = metadata["usage"]
		if usage.has("total_tokens"):
			enhanced_text += "\n\n*Tokens used: " + str(usage["total_tokens"]) + "*"
	enhanced_text = markdown_renderer.render(enhanced_text)
	var ai_bubble = _create_ai_bubble_bbcode(enhanced_text, _get_current_time())
	ai_container.add_child(ai_bubble)
	
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
