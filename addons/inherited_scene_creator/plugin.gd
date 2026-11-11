@tool
extends EditorPlugin

var _context_menu: EditorContextMenuPlugin

func _enter_tree() -> void:
	var MenuScript = preload("res://addons/inherited_scene_creator/inherited_context_menu.gd")
	_context_menu = MenuScript.new()  # Key: instantiate first
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _context_menu)
	
	set_input_event_forwarding_always_enabled()

func _exit_tree() -> void:
	if is_instance_valid(_context_menu):
		remove_context_menu_plugin(_context_menu)
