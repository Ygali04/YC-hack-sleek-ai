extends Control
class_name AIDockRoot

const ChatTabClass = preload("res://addons/sleek_gamedev_ai/ui/chat_tab.gd")
const ChatSessionClass = preload("res://addons/sleek_gamedev_ai/core/chat_session.gd")

var model_registry:ModelRegistry
var client:OpenRouterClient
var tab_container:TabContainer

func _ready():
	# Create the UI structure
	var main_vbox = VBoxContainer.new()
	add_child(main_vbox)
	
	# Header with title and new chat button
	var header_box = HBoxContainer.new()
	main_vbox.add_child(header_box)
	
	var header = Label.new()
	header.text = "🤖 AI Assistant"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_child(header)
	
	var new_chat_btn = Button.new()
	new_chat_btn.text = "+"
	new_chat_btn.tooltip_text = "New Chat"
	new_chat_btn.custom_minimum_size = Vector2(30, 30)
	new_chat_btn.connect("pressed", _create_chat_tab)
	header_box.add_child(new_chat_btn)
	
	# Tab container
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tab_container)
	
	# Add first chat tab
	_create_chat_tab()

func _create_chat_tab():
	var tab = ChatTabClass.new()
	var session = ChatSessionClass.new()
	if model_registry and client:
		var models = model_registry.get_models()
		if models.size() > 0:
			session.configure(client, models[0]["name"])
	tab.bind_session(session)
	tab.name = "Chat %d" % (tab_container.get_child_count() + 1)
	tab_container.add_child(tab)
	tab_container.current_tab = tab_container.get_child_count() - 1 
