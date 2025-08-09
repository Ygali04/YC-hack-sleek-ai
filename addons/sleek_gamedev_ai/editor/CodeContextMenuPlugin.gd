extends EditorContextMenuPlugin

var dock_ref: Control

func _init(dock: Control):
	dock_ref = dock

func _populate_menu(selected_options: PackedStringArray) -> void:
	add_context_menu_item("Add to Chat", _on_add_to_chat)
	add_context_menu_item("Explain Code", _on_explain_code)

func _on_explain_code(node: Node):
	if not (node is CodeEdit):
		return
	if node.has_selection():
		var text = node.get_selected_text()
		if text:
			var ei = Engine.get_singleton("EditorInterface")
			var scr = ei.get_script_editor().get_current_script()
			if scr:
				text = "Explain this code from %s:\n\n%s" % [scr.resource_path, text]
			if dock_ref:
				var input_node = _find_chat_input(dock_ref)
				if input_node:
					input_node.insert_text_at_caret("\n" + text)

func _on_add_to_chat(node: Node):
	if not (node is CodeEdit):
		return
	if node.has_selection():
		var text = node.get_selected_text()
		if text:
			var ei = Engine.get_singleton("EditorInterface")
			var scr = ei.get_script_editor().get_current_script()
			if scr:
				text = "Snippet from %s:\n%s" % [scr.resource_path, text]
			if dock_ref:
				var input_node = _find_chat_input(dock_ref)
				if input_node:
					input_node.insert_text_at_caret("\n" + text)

func _find_chat_input(dock: Control) -> TextEdit:
	# Best-effort: traverse to find the bottom input TextEdit
	for tab in dock.get_children():
		if tab is TabContainer or tab is VBoxContainer or tab is HBoxContainer or tab is Control:
			var t = _find_textedit_recursive(tab)
			if t:
				return t
	return null

func _find_textedit_recursive(node: Node) -> TextEdit:
	if node is TextEdit and (node as TextEdit).editable == true:
		return node
	for c in node.get_children():
		var res = _find_textedit_recursive(c)
		if res:
			return res
	return null 