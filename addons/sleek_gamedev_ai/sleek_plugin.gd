@tool
extends EditorPlugin

const AIDock = preload("res://addons/sleek_gamedev_ai/dock/ai_dock.gd")
var dock_instance
var code_menu_plugin: EditorContextMenuPlugin

func _enter_tree() -> void:
	# Create and add the Sleek Gamedev AI dock
	dock_instance = AIDock.new()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock_instance)
	print("Sleek Gamedev AI plugin activated")
	# Add code editor context menu items
	var ScriptMenu := preload("res://addons/sleek_gamedev_ai/editor/CodeContextMenuPlugin.gd")
	code_menu_plugin = ScriptMenu.new(dock_instance)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, code_menu_plugin)

func _exit_tree() -> void:
	# Clean up when plugin is disabled
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.queue_free()
	if code_menu_plugin:
		remove_context_menu_plugin(code_menu_plugin)
	print("Sleek Gamedev AI plugin deactivated") 
