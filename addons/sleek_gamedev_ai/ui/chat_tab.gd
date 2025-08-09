extends VBoxContainer
class_name ChatTab

var session:ChatSession

var scroll : ScrollContainer
var msg_container : VBoxContainer
var input_edit : TextEdit
var input_box : HBoxContainer
var send_btn : Button
var attach_btn : Button
var file_dialog : FileDialog
var clear_attachments_btn : Button

func _ready():
	# Create the UI structure programmatically
	_build_ui()
	
	# Connect buttons
	send_btn.connect("pressed", _on_send)
	attach_btn.connect("pressed", _on_attach_pressed)
	clear_attachments_btn.connect("pressed", _on_clear_attachments)
	
	# File dialog setup - unified approach for all platforms
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.use_native_dialog = true  # This will use system dialog on all platforms
	file_dialog.add_filter("*", "All Files")
	file_dialog.add_filter("*.txt,*.md,*.pdf,*.doc,*.docx", "Documents")
	file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.gif,*.bmp", "Images")
	file_dialog.connect("file_selected", _on_file_chosen)
	add_child(file_dialog)

func _build_ui():
	# Create scroll area for messages
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	
	# Message container
	msg_container = VBoxContainer.new()
	msg_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(msg_container)
	
	# Input area
	input_box = HBoxContainer.new()
	input_box.custom_minimum_size.y = 40
	add_child(input_box)
	
	# Create attach button
	attach_btn = Button.new()
	attach_btn.text = "📎"
	attach_btn.focus_mode = Control.FOCUS_NONE
	attach_btn.custom_minimum_size = Vector2(30, 30)
	input_box.add_child(attach_btn)
	
	# Create clear attachments button
	clear_attachments_btn = Button.new()
	clear_attachments_btn.text = "🗑️"
	clear_attachments_btn.focus_mode = Control.FOCUS_NONE
	clear_attachments_btn.tooltip_text = "Clear attachments"
	clear_attachments_btn.custom_minimum_size = Vector2(30, 30)
	input_box.add_child(clear_attachments_btn)
	
	# Input field
	input_edit = TextEdit.new()
	input_edit.placeholder_text = "Ask the AI assistant..."
	input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_edit.custom_minimum_size.y = 40
	input_box.add_child(input_edit)
	
	# Send button
	send_btn = Button.new()
	send_btn.text = "➤"
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.custom_minimum_size = Vector2(40, 40)
	input_box.add_child(send_btn)
	
	# Add welcome message
	_add_ai_bubble("AI Assistant Ready! 🤖\n\nI can help you with:\n• Generate GDScript code\n• Create game assets\n• Debug your projects\n• Provide coding suggestions\n\nWhat would you like to work on?")

func bind_session(s:ChatSession):
	session = s
	session.assistant_message.connect(_on_ai_msg)

func _on_send():
	var text = input_edit.text.strip_edges()
	if text.is_empty():
		return
	_add_user_bubble(text)
	input_edit.text = ""
	session.ask(text)

func _on_ai_msg(reply:String):
	_add_ai_bubble(reply)

func _add_user_bubble(text:String):
	var container = HBoxContainer.new()
	var text_edit = TextEdit.new()
	text_edit.text = "You: " + text
	text_edit.editable = false
	text_edit.add_theme_color_override("font_color", Color.WHITE)
	text_edit.add_theme_color_override("background_color", Color.TRANSPARENT)
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.scroll_fit_content_height = true
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	container.add_child(text_edit)
	
	msg_container.add_child(container)

func _add_ai_bubble(text:String):
	var container = HBoxContainer.new()
	var text_edit = TextEdit.new()
	text_edit.text = "AI: " + text
	text_edit.editable = false
	text_edit.add_theme_color_override("font_color", Color.WHITE)
	text_edit.add_theme_color_override("background_color", Color.TRANSPARENT)
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.scroll_fit_content_height = true
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	container.add_child(text_edit)
	
	msg_container.add_child(container)
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value 

func _on_attach_pressed():
	# Use the native file dialog for all platforms including macOS
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_file_chosen(path:String):
	# Store the file path and show in chat
	var file_name = path.get_file()
	var file_size = FileAccess.get_file_as_bytes(path).size()
	_add_user_bubble("[📎 Attached] %s (%d bytes)" % [file_name, file_size])
	
	# TODO: Store the file path for use in LLM context
	# This is where you'd add the file to your session or file store
	if session:
		session.add_attachment(path) 

func _on_clear_attachments():
	if session:
		session.clear_attachments()
		_add_ai_bubble("Attachments cleared.")

func _copy_text_to_clipboard(text: String):
	# Copy to clipboard using DisplayServer
	DisplayServer.clipboard_set(text)
	print("[ChatTab] Text copied to clipboard") 
