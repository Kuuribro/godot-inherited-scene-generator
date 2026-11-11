# Adds a new entry to the right-click context menu in the File System.

@tool
extends EditorContextMenuPlugin

# Default material to use if set. Leave blank for no material applied by default.
const DEFAULT_MATERIAL_PATH := ""

# Base path for new inherited scenes. To be modified based on workflow request
const INHERITED_SCENES_ROOT := "res://assets/inherited_scenes"

# Remembers the material the user picked last time for this session.
static var _last_used_material_path: String = ""

# Controls whether generated scenes stay open after generation.
enum KeepOpenChoice { ABORT, NO, YES }

func _popup_menu(paths: PackedStringArray) -> void:
	add_context_menu_item("Generate Inherited Scene(s)", _on_generate)

## Validates selection and opens the confirmation dialog.
func _on_generate(paths: PackedStringArray) -> void:
	# Count valid .glb files first
	var glb_count := 0
	for p in paths:
		if p.get_extension().to_lower() == "glb":
			glb_count += 1
			
	if glb_count == 0:
		push_warning("No .glb files selected.")
		return

	# Build the dialog
	var dialog := ConfirmationDialog.new()
	# dialog.exclusive = false
	dialog.title = "Generate Inherited Scenes"
	dialog.ok_button_text = "Generate"
	dialog.cancel_button_text = "Cancel"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)

	# 1. Confirmation Count
	var count_label := Label.new()
	count_label.text = "You have selected %d .glb files to generate inherited scenes." % glb_count
	vbox.add_child(count_label)

	# 2. Folder Selector
	var folder_hbox := HBoxContainer.new()
	vbox.add_child(folder_hbox)
	
	var save_info_label := Label.new()
	save_info_label.text = "(Leave save location blank to save to use default location: %s)" % INHERITED_SCENES_ROOT
	save_info_label.modulate = Color(1, 1, 1, 0.6) # Faded grey
	vbox.add_child(save_info_label)
	
	var folder_label := Label.new()
	folder_label.text = "Root Save Folder: "
	folder_hbox.add_child(folder_label)
	
	var folder_line := LineEdit.new()
	folder_line.placeholder_text = INHERITED_SCENES_ROOT
	folder_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_hbox.add_child(folder_line)
	
	var folder_btn := Button.new()
	folder_btn.text = "Browse"
	folder_hbox.add_child(folder_btn)
	
	folder_btn.pressed.connect(func() -> void:
		dialog.hide() # Hide the confirmation dialog to release the exclusive lock
		
		var file_dialog := EditorFileDialog.new()
		file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		
		file_dialog.dir_selected.connect(func(path: String) -> void:
			folder_line.text = path
			file_dialog.queue_free()
			dialog.show() # Show the confirmation dialog again
		)
		file_dialog.canceled.connect(func() -> void:
			file_dialog.queue_free()
			dialog.show() # Show the confirmation dialog again
		)
		
		EditorInterface.get_base_control().get_window().add_child(file_dialog)
		file_dialog.popup_file_dialog() # Use default editor size
	)
	
	# 3. Material Selector
	var mat_hbox := HBoxContainer.new()
	vbox.add_child(mat_hbox)
	
	var mat_info_label := Label.new()
	mat_info_label.text = "(Material to apply to all meshes in the inherited scene; leave blank for no overrides.)"
	mat_info_label.modulate = Color(1, 1, 1, 0.6) # Faded grey
	vbox.add_child(mat_info_label)
	
	var mat_label := Label.new()
	mat_label.text = "Material Override: "
	mat_hbox.add_child(mat_label)
	
	var mat_line := LineEdit.new()
	mat_line.placeholder_text = "None"
	mat_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mat_hbox.add_child(mat_line)
	
	var mat_btn := Button.new()
	mat_btn.text = "Browse"
	mat_hbox.add_child(mat_btn)
	
	# Pre-fill with the last used material, or the default constant if none exists yet.
	if _last_used_material_path != "":
		mat_line.text = _last_used_material_path
	elif DEFAULT_MATERIAL_PATH != "":
		mat_line.text = DEFAULT_MATERIAL_PATH

	mat_btn.pressed.connect(func() -> void:
		dialog.hide() # Hide the confirmation dialog to release the exclusive lock
		
		var file_dialog := EditorFileDialog.new()
		file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		file_dialog.add_filter("*.tres, *.material", "Material")
		
		file_dialog.file_selected.connect(func(path: String) -> void:
			mat_line.text = path
			file_dialog.queue_free()
			dialog.show() # Show the confirmation dialog again
		)
		file_dialog.canceled.connect(func() -> void:
			file_dialog.queue_free()
			dialog.show() # Show the confirmation dialog again
		)
		
		EditorInterface.get_base_control().get_window().add_child(file_dialog)
		file_dialog.popup_file_dialog()
	)

	# Mount and popup
	var parent_window := EditorInterface.get_base_control().get_window()
	parent_window.add_child(dialog)

	dialog.confirmed.connect(func() -> void:
		# Gather final values
		var final_folder := folder_line.text
		if final_folder == "":
			final_folder = INHERITED_SCENES_ROOT
			
		var final_material_path := mat_line.text
		var final_material: Material = null
		if final_material_path != "":
			final_material = load(final_material_path) as Material
			if final_material == null:
				push_error("Could not load material at: " + final_material_path)
		
		# Save the path for the next time the user opens the dialog.
		_last_used_material_path = final_material_path
		
		dialog.queue_free()
		_execute_generation.call_deferred(paths, final_material, final_folder)
	)
	
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)

	dialog.popup_centered()


## Generates inherited scenes with chosen path and material override.
func _execute_generation(paths: PackedStringArray, base_material: Material, target_root: String) -> void:
	# Count valid .glb files again for the keep_open prompt
	var glb_count := 0
	for p in paths:
		if p.get_extension().to_lower() == "glb":
			glb_count += 1

	var keep_open := true
	if glb_count > 1:
		# Show a blocking dialog and wait for the user's choice
		var choice := await _ask_keep_scenes_open(glb_count)
		# If the user closed the dialog without choosing, abort
		if choice == KeepOpenChoice.ABORT:
			return
		keep_open = (choice == KeepOpenChoice.YES)
	
	# Remember which scene the editor had open before we started so we can restore it instead of leaving the editor on the last .glb
	var original_scene := EditorInterface.get_edited_scene_root()
	# save the path safely in case it's an unsaved new scene
	var original_path := ""
	if original_scene != null:
		original_path = original_scene.scene_file_path

	for glb_path in paths:
		# skip anything that isn't a .glb
		if glb_path.get_extension().to_lower() != "glb":
			continue

		var new_path := _get_target_scene_path(glb_path, target_root)
		
		# ensure target directory exists before saving into it
		var target_dir := new_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(target_dir):
			DirAccess.make_dir_recursive_absolute(target_dir)

		# do not clobber an existing inherited scene
		if FileAccess.file_exists(new_path):
			print("Skipping (already exists): ", new_path)
			continue

		# create the inherited scene. `true` means "inherit from this scene"
		EditorInterface.open_scene_from_path(glb_path, true)

		# EditorInterface.open_scene_from_path() and save_scene_as.call_deferred() do not resolve in a single frame; waiting two frames prevents race conditions
		await Engine.get_main_loop().process_frame
		await Engine.get_main_loop().process_frame
		
		# inherited scene is now the edited scene. Its root is our hook
		var root := EditorInterface.get_edited_scene_root()
		if root == null:
			push_error("Failed to open inherited scene for: " + glb_path)
			continue

		_strip_suffix2(root, glb_path)

		if base_material != null:
			_apply_material_override(root, base_material)

		# save inherited scene to disk. Use call_deferred because saving during a popup/menu callback can otherwise race the editor state.
		EditorInterface.save_scene_as.call_deferred(new_path, false)

		# wait for the deferred save to complete before opening the next scene, otherwise the next open_scene_from_path could clobber the unsaved scene.
		await Engine.get_main_loop().process_frame
		await Engine.get_main_loop().process_frame

		print("Created inherited scene: ", new_path)
		
		# If the user chose not to keep them open, close this scene now
		if not keep_open:
			EditorInterface.close_scene()

	# restore the scene the user had open before running the tool
	if original_path != "":
		EditorInterface.open_scene_from_path(original_path, false)
		
	# force the FileSystem view to update and show newly generated folders.
	var fs = EditorInterface.get_resource_filesystem()
	if not fs.is_scanning():
		fs.scan()

## Recursively walk the node tree and set set_surface_override_material on every MeshInstance3D
func _apply_material_override(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		# Make sure the node actually has a mesh with surfaces before we try to assign
		if mesh_instance.mesh != null:
			var surface_count := mesh_instance.mesh.get_surface_count()
			for i in range(surface_count):
				mesh_instance.set_surface_override_material(i, material)

	for child in node.get_children():
		_apply_material_override(child, material)

## Godot's importer sometimes appends "2" to the root node if the glb's internal mesh name collides with the file name. 
## Strip it if it exactly matches the file basename + "2"
func _strip_suffix2(root: Node, glb_path: String) -> void:
	var base_name := glb_path.get_file().get_basename()
	if root.name == base_name + "2":
		root.name = base_name
		
## Generates the target .tscn path. mirrors .glb's current folder structure
func _get_target_scene_path(glb_path: String, target_root: String) -> String:
	# Strip the res:// protocol.
	var relative_path := glb_path.trim_prefix("res://")
	
	# If the file is inside an "assets/" folder, strip it so the path doesn't double up.
	if relative_path.begins_with("assets/"):
		relative_path = relative_path.trim_prefix("assets/")
	
	# Replace .glb extension with .tscn
	var relative_tscn := relative_path.get_basename() + ".tscn"
	
	# Append to the new root folder.
	return target_root.path_join(relative_tscn)

## Helper to show dialog to confirm if user wants to keep >1 scenes open or not.
func _ask_keep_scenes_open(count: int) -> KeepOpenChoice:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Keep Scenes Open?"
	dialog.dialog_text = "You are about to generate %d inherited scenes.\n\nWould you like to keep these scenes open after generation?" % count
	dialog.ok_button_text = "Yes"
	dialog.cancel_button_text = "No"

	var parent_window := EditorInterface.get_base_control().get_window()
	parent_window.add_child(dialog)

	# Use a local variable to capture the result
	var result := [KeepOpenChoice.ABORT]
	dialog.confirmed.connect(func() -> void:
		result[0] = KeepOpenChoice.YES
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		result[0] = KeepOpenChoice.NO
		dialog.queue_free()
	)

	dialog.popup_centered()

	while is_instance_valid(dialog):
		await Engine.get_main_loop().process_frame

	return result[0]
