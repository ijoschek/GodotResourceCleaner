@tool
extends Window
## Godot Resource Cleaner Main Script

enum Sort {
	NONE,
	SIZE_ASC,
	SIZE_DESC,
	PATH_ASC,
	PATH_DESC,
}
var sort : Sort = Sort.NONE

enum Exception {
	IGN_FOLDER,
	IGN_EXTENSION,
	EXCL_FOLDER,
	EXCL_EXTENSION,
	EXCL_CONTAINING,
}

const SETTING_USE_MULTITHREADING := "ResCleaner/data/use_multithreading"
const SETTING_KEEP_LIST := "ResCleaner/data/keep_list"
const SETTING_IGNORE_FOLDER := "ResCleaner/data/ignore_folder"
const SETTING_IGNORE_EXT := "ResCleaner/data/ignore_ext"
const SETTING_EXCLUDE_FOLDER := "ResCleaner/data/exclude_folder"
const SETTING_EXCLUDE_EXT := "ResCleaner/data/exclude_ext"
const SETTING_EXCLUDE_CONTAINING := "ResCleaner/data/exclude_containing"

const EXCLUDE_FOLDER_DEFAULT := [".godot", "addons", ".git"]
const EXCLUDE_EXT_DEFAULT := [".godot", ".import", ".uid"]
const EXCLUDE_CONTAINING_DEFAULT := ["gitignore", "gitattributes"]

## Main Screen
@onready var main: PanelContainer = %Main
@onready var setting: PanelContainer = %Setting
@onready var keep_list: PanelContainer = %KeepList
@onready var overlay: ColorRect = %Overlay
@onready var button_scan: Button = %ButtonScan

## Overlay screen nodes
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var progress_label: Label = %ProgressLabel
@onready var cancel_button: Button = %CancelButton

## Setting screen nodes
@onready var use_multithreading_check_button: CheckButton = %UseMultithreadingCheckButton

var exclude_folder := []
var exclude_ext := []
var exclude_containing := []

var ignore_folder := []
var ignore_ext := []

var search_ext : Array[String] = []

var keep_paths : Array[String] = []
var unused_files := []

var scan_thread : Thread

var selected_count := 0
var filter_on := false
var ignore_on := false
var use_multithreading := true
var is_scanning := false

func _ready() -> void:
	if Engine.is_editor_hint():
		var theme_icon := EditorInterface.get_base_control()
		%ButtonSetting.icon = theme_icon.get_theme_icon("Tools", "EditorIcons")
		%ButtonKeepList.icon = theme_icon.get_theme_icon("FileList", "EditorIcons")
		button_scan.icon = theme_icon.get_theme_icon("Search", "EditorIcons")
		%ButtonClean.icon = theme_icon.get_theme_icon("Clear", "EditorIcons")
		%ButtonKeep.icon = theme_icon.get_theme_icon("Pin", "EditorIcons")
		%ButtonDelete.icon = theme_icon.get_theme_icon("Remove", "EditorIcons")
		%ButtonDoneSetting.icon = theme_icon.get_theme_icon("Back", "EditorIcons")
		%ButtonDoneKL.icon = theme_icon.get_theme_icon("Back", "EditorIcons")
		%ButtonSettingReset.icon = theme_icon.get_theme_icon("Reload", "EditorIcons")
		%ExcludeButton.icon = theme_icon.get_theme_icon("NodeWarning", "EditorIcons")
		%ButtonRemoveAll.icon = theme_icon.get_theme_icon("Remove", "EditorIcons")
	
	%HBoxFilter.visible = filter_on
	%VBoxIgnore.visible = ignore_on
	main.visible = true
	overlay.visible = false
	setting.visible = false
	
	# Setup progress UI elements
	cancel_button.pressed.connect(_on_cancel_scan_pressed)
	_hide_progress_ui()
	
	# Connect to FileUtils progress signal
	FileUtils.get_instance().progress_updated.connect(_on_scan_progress_updated)
	
	# Load Settings
	if ProjectSettings.has_setting(SETTING_KEEP_LIST):
		keep_paths = ProjectSettings.get(SETTING_KEEP_LIST)
		for path in keep_paths:
			%VBoxKeepList.add_child(_add_keep_list_row(path))
			
	if ProjectSettings.has_setting(SETTING_USE_MULTITHREADING):
		use_multithreading = ProjectSettings.get(SETTING_USE_MULTITHREADING)
	use_multithreading_check_button.button_pressed = use_multithreading
		
	_load_exceptions(SETTING_IGNORE_FOLDER, Exception.IGN_FOLDER)
	_load_exceptions(SETTING_IGNORE_EXT, Exception.IGN_EXTENSION)
	_load_exceptions_wdefault(SETTING_EXCLUDE_FOLDER, EXCLUDE_FOLDER_DEFAULT, Exception.EXCL_FOLDER)
	_load_exceptions_wdefault(SETTING_EXCLUDE_EXT, EXCLUDE_EXT_DEFAULT, Exception.EXCL_EXTENSION)
	_load_exceptions_wdefault(SETTING_EXCLUDE_CONTAINING, EXCLUDE_CONTAINING_DEFAULT, Exception.EXCL_CONTAINING)

func _hide_progress_ui() -> void:
	overlay.visible = false
	if progress_bar:
		progress_bar.visible = false
	if progress_label:
		progress_label.visible = false
	if cancel_button:
		cancel_button.visible = false

func _show_progress_ui() -> void:
	overlay.visible = true
	if progress_bar:
		progress_bar.visible = true
		progress_bar.value = 0
	if progress_label:
		progress_label.visible = true
		progress_label.text = "Starting scan..."
	if cancel_button:
		cancel_button.visible = true

func _on_scan_progress_updated(current: int, total: int, message: String) -> void:
	# Use call_deferred to ensure UI updates happen on the main thread
	_update_progress_ui.call_deferred(current, total, message)

func _update_progress_ui(current: int, total: int, message: String) -> void:
	if progress_bar:
		progress_bar.value = (float(current) / total) * 100
	if progress_label:
		progress_label.text = message

func _on_cancel_scan_pressed() -> void:
	if is_scanning:
		FileUtils.cancel_scan()
		if scan_thread:
			scan_thread.wait_to_finish()
			scan_thread = null
		is_scanning = false
		_update_scan_cancelled_ui.call_deferred()

func _update_scan_cancelled_ui() -> void:
	button_scan.disabled = false
	_hide_progress_ui()
	if progress_label:
		progress_label.text = "Scan cancelled"

func _load_exceptions(setting: String, type: Exception) -> void:
	if not ProjectSettings.has_setting(setting):
		return
	var items : Array = ProjectSettings.get(setting)
	for i in items:
		_add_exception(i, type, false)

func _load_exceptions_wdefault(setting: String, default_list: Array, type: Exception) -> void:
	var items : Array = ProjectSettings.get(setting) if ProjectSettings.has_setting(setting) else default_list
	for i in items:
		_add_exception(i, type, false)

#region Main
# Close Plugin
func _on_close_requested() -> void:
	visible = false

# Press Settings Button
func _on_button_setting_pressed() -> void:
	%Setting.show()

# Press Keep List Button
func _on_button_keep_list_pressed() -> void:
	%KeepList.show()

# Press Scan Button
func _on_button_scan_pressed() -> void:
	if is_scanning:
		return
		
	is_scanning = true
	button_scan.disabled = true
	_show_progress_ui()
	
	# Run the scan in a separate thread to avoid blocking the UI
	scan_thread = Thread.new()
	scan_thread.start(_perform_scan_async)

func _perform_scan_async() -> void:
	selected_count = 0
	unused_files = FileUtils.scan_res(
			filter_on,
			search_ext,
			exclude_folder,
			exclude_ext,
			exclude_containing,
			keep_paths,
			ignore_on,
			ignore_folder,
			ignore_ext,
			use_multithreading) # Use threading
	
	# Switch back to main thread for UI updates
	_on_scan_completed.call_deferred()

func _on_scan_completed() -> void:
	is_scanning = false
	button_scan.disabled = false
	_hide_progress_ui()
	
	FileUtils.sorting(unused_files, sort)
	_draw_result()
	
	if scan_thread:
		scan_thread.wait_to_finish()
		scan_thread = null

# Press Clean import Button
func _on_button_clean_pressed() -> void:
	%CBImport.button_pressed = true
	%CBUid.button_pressed = true
	%CBFolders.button_pressed = true
	%ConfirmationDialogClean.show()
	
func _on_confirmation_dialog_clean_confirmed() -> void:
	var any_clean := false
	if %CBImport.button_pressed:
		any_clean = true
		FileUtils.clean_import("res://", exclude_folder)
	if %CBUid.button_pressed:
		any_clean = true
		FileUtils.clean_uid("res://", exclude_folder)
	if %CBFolders.button_pressed:
		any_clean = true
		FileUtils.clean_empty_folders("res://", exclude_folder)
		
	if any_clean:
		_refresh_filesystem()
	
# Press Sort Size Button
func _on_size_button_pressed() -> void:
	sort = Sort.SIZE_DESC if sort == Sort.SIZE_ASC else Sort.SIZE_ASC
	FileUtils.sorting(unused_files, sort)
	_draw_result()
	
# Press Sort Path Button
func _on_path_button_pressed() -> void:
	sort = Sort.PATH_DESC if sort == Sort.PATH_ASC else Sort.PATH_ASC
	FileUtils.sorting(unused_files, sort)
	_draw_result()

# Refresh the whole Scan
func _refresh() -> void:
	selected_count = 0
	unused_files = FileUtils.scan_res(
			filter_on,
			search_ext,
			exclude_folder,
			exclude_ext,
			exclude_containing,
			keep_paths,
			ignore_on,
			ignore_folder,
			ignore_ext,
			use_multithreading)
	FileUtils.sorting(unused_files, sort)
	_draw_result()

func _refresh_filesystem() -> void:
	print("REFRESH FILESYS")
	EditorInterface.get_resource_filesystem().scan()

# Checkbox logic
func _on_first_checkbox_toggled(is_toggled: bool) -> void:
	for file in unused_files:
		file.checkbox.button_pressed = is_toggled

func _on_checkbox_toggled(is_toggled: bool, file: Dictionary) -> void:
	file.is_checked = is_toggled
	selected_count += 1 if is_toggled else -1

# Press Keep Files Button
func _on_button_keep_pressed() -> void:
	if unused_files.is_empty():
		print("Please press scan first")
		return
		
	if selected_count == 0:
		print("Nothing selected")
		return
		
	for ndf in unused_files:
		if ndf.is_checked:
			var path = ndf.path
			if !keep_paths.has(path):
				keep_paths.append(path)
				%VBoxKeepList.add_child(_add_keep_list_row(path))
				
	ProjectSettings.set(SETTING_KEEP_LIST, keep_paths)
	ProjectSettings.save()
	_refresh()

# Press Delete Files Button
func _on_button_delete_pressed() -> void:
	if unused_files.is_empty():
		print("Please press scan first")
		return
		
	if selected_count == 0:
		print("Nothing selected")
		return
		
	%ConfirmationDialog.dialog_text = "Are you sure you want to permanently delete all selected files (%d)? This action cannot be undone." % selected_count
	%ConfirmationDialog.show()
	
# Actually Delete selected Files
func _on_confirmation_dialog_confirmed() -> void:
	FileUtils.delete_selected(unused_files)
	_refresh_filesystem()
	_refresh()
	
# Filter File Paths
func _on_le_filter_text_changed(new_text: String) -> void:
	var filter : String = new_text.strip_edges().to_lower()
	
	for c in %VBoxMain.get_children():
		var p_label : Label = c.get_node_or_null("PathLabel")
		if p_label:
			var path_text : String = p_label.text.to_lower()
			c.visible = filter == "" or path_text.contains(filter)

#endregion

#region UI Drawing
	
func _draw_result() -> void:
	for child in %VBoxMain.get_children():
		child.queue_free()
		
	if unused_files.is_empty():
		return
		
	%VBoxMain.add_child(_add_first_row())
	%VBoxMain.add_child(HSeparator.new())
	
	for ndf in unused_files:
		%VBoxMain.add_child(_add_row(ndf))

func _add_first_row() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	
	var c_box := CheckBox.new()
	c_box.toggled.connect(_on_first_checkbox_toggled)
	
	var placeholder = Container.new()
	placeholder.custom_minimum_size = Vector2(48, 48)
	
	var s_button := Button.new()
	s_button.text = "Size"
	s_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	s_button.custom_minimum_size.x = 80.0
	s_button.pressed.connect(_on_size_button_pressed)
	
	var p_button := Button.new()
	p_button.text = "Path"
	p_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	p_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_button.pressed.connect(_on_path_button_pressed)
	
	hbox.add_child(c_box)
	hbox.add_child(placeholder)
	hbox.add_child(s_button)
	hbox.add_child(p_button)
	
	return hbox
	
func _add_row(ndf: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	
	var c_box := CheckBox.new()
	c_box.toggled.connect(_on_checkbox_toggled.bind(ndf))
	ndf["checkbox"] = c_box
	
	var tex_rec = TextureRect.new()
	tex_rec.custom_minimum_size = Vector2(48, 48)
	tex_rec.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
	var s_label := Label.new()
	s_label.text = FileUtils.format_file_size(ndf.size)
	s_label.custom_minimum_size.x = 80.0
	
	var p_label := Label.new()
	p_label.name = "PathLabel"
	p_label.text = ndf.path
	hbox.add_child(c_box)
	hbox.add_child(tex_rec)
	hbox.add_child(s_label)
	hbox.add_child(p_label)
	
	if Engine.is_editor_hint():
		var preview = EditorInterface.get_resource_previewer()
		preview.queue_resource_preview(ndf.path, self, "_on_preview_ready", tex_rec)
	
	return hbox

func _add_keep_list_row(path: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	var rem_button := Button.new()
	rem_button.icon = EditorInterface.get_base_control().get_theme_icon("Remove", "EditorIcons")
#	rem_button.text = "Remove"
	rem_button.pressed.connect(_on_button_remove_from_kl_pressed.bind(path, hbox))
	var sep := VSeparator.new()
	var tex_rec = TextureRect.new()
	tex_rec.custom_minimum_size = Vector2(48, 48)
	tex_rec.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var p_label := Label.new()
	p_label.text = path
	hbox.add_child(rem_button)
	hbox.add_child(sep)
	hbox.add_child(tex_rec)
	hbox.add_child(p_label)
	var preview = EditorInterface.get_resource_previewer()
	preview.queue_resource_preview(path, self, "_on_preview_ready", tex_rec)
	
	return hbox
	
#endregion
	
#region Keep List
	
func _on_button_remove_from_kl_pressed(path: String, node: Node) -> void:
	if keep_paths.has(path):
		keep_paths.erase(path)
		
		node.queue_free()
			
		ProjectSettings.set(SETTING_KEEP_LIST, keep_paths)
		ProjectSettings.save()

func _on_preview_ready(path: String, preview: Texture2D, thumbnail_preview: Texture2D, tex_rec):
	if preview and tex_rec:
		tex_rec.texture = preview
	else:
		tex_rec.texture = EditorInterface.get_base_control().get_theme_icon("File", "EditorIcons")
	

func _on_button_remove_all_pressed() -> void:
	if not keep_paths.is_empty():
		%ConfirmationDialogKLRemoveAll.show()
	else:
		print("No Files in the Keep List")
	
func _on_confirmation_dialog_kl_remove_all_confirmed() -> void:
	keep_paths.clear()
	for c in %VBoxKeepList.get_children():
		c.queue_free()
		
	ProjectSettings.set(SETTING_KEEP_LIST, keep_paths)
	ProjectSettings.save()
	
#endregion
	
#region Settings

# Filter Section
func _on_check_button_toggled(toggled_on: bool) -> void:
	filter_on = toggled_on
	%HBoxFilter.visible = filter_on
	
func _on_button_done_pressed() -> void:
	%Setting.hide()

func _on_button_done_kl_pressed() -> void:
	%KeepList.hide()

func on_checkbox_toggled(toggled_on: bool, ext: String) -> void:
	if toggled_on:
		search_ext.append(ext)
	else:
		if search_ext.has(ext):
			search_ext.erase(ext)
			
func _add_exception(txt: String, exception: Exception, save: bool) -> void:
	var hbox := HBoxContainer.new()
	var new_button := Button.new()
	
	if Engine.is_editor_hint(): new_button.icon = EditorInterface.get_base_control().get_theme_icon("Remove", "EditorIcons")#"Del"
	
	new_button.pressed.connect(_on_delete_exception.bind(exception, txt, hbox))
	var new_sep := VSeparator.new()
	var new_label := Label.new()
	new_label.text = txt
	
	hbox.add_child(new_button)
	hbox.add_child(new_sep)
	hbox.add_child(new_label)
	
	match exception:
		Exception.IGN_FOLDER:
			if not ignore_folder.has(txt):
				ignore_folder.append(txt)
				%VBoxIgnFolder.add_child(hbox)
				if save:
					ProjectSettings.set(SETTING_IGNORE_FOLDER, ignore_folder)
		Exception.IGN_EXTENSION:
			if not ignore_ext.has(txt):
				ignore_ext.append(txt)
				%VBoxIgnExt.add_child(hbox)
				if save:
					ProjectSettings.set(SETTING_IGNORE_EXT, ignore_ext)
		Exception.EXCL_FOLDER:
			if not exclude_folder.has(txt):
				exclude_folder.append(txt)
				%VBoxFolder.add_child(hbox)
				if save:
					ProjectSettings.set(SETTING_EXCLUDE_FOLDER, exclude_folder)
		Exception.EXCL_EXTENSION:
			if not exclude_ext.has(txt):
				exclude_ext.append(txt)
				%VBoxExt.add_child(hbox)
				if save:
					ProjectSettings.set(SETTING_EXCLUDE_EXT, exclude_ext)
		Exception.EXCL_CONTAINING:
			if not exclude_containing.has(txt):
				exclude_containing.append(txt)
				%VBoxContains.add_child(hbox)
				if save:
					ProjectSettings.set(SETTING_EXCLUDE_CONTAINING, exclude_containing)
	if save:
		ProjectSettings.save()
		
func _on_delete_exception(exception: Exception, txt: String, node: Node) -> void:
	node.queue_free()
	
	match exception:
		Exception.IGN_FOLDER:
			if ignore_folder.has(txt):
				ignore_folder.erase(txt)
			ProjectSettings.set(SETTING_IGNORE_FOLDER, ignore_folder)
		Exception.IGN_EXTENSION:
			if ignore_ext.has(txt):
				ignore_ext.erase(txt)
			ProjectSettings.set(SETTING_IGNORE_EXT, ignore_ext)
		Exception.EXCL_FOLDER:
			if exclude_folder.has(txt):
				exclude_folder.erase(txt)
			ProjectSettings.set(SETTING_EXCLUDE_FOLDER, exclude_folder)
		Exception.EXCL_EXTENSION:
			if exclude_ext.has(txt):
				exclude_ext.erase(txt)
			ProjectSettings.set(SETTING_EXCLUDE_EXT, exclude_ext)
		Exception.EXCL_CONTAINING:
			if exclude_containing.has(txt):
				exclude_containing.erase(txt)
			ProjectSettings.set(SETTING_EXCLUDE_CONTAINING, exclude_containing)
	
	ProjectSettings.save()
		
# Ignore Section
func _on_ignore_check_button_toggled(toggled_on: bool) -> void:
	ignore_on = toggled_on
	%VBoxIgnore.visible = toggled_on

func _on_button_ign_folder_pressed() -> void:
	var txt : String = %TextEditIgnFolder.text.strip_edges()
	if not txt.is_empty():
		%TextEditIgnFolder.text = ""
		_add_exception(txt, Exception.IGN_FOLDER, true)

func _on_button_ign_ext_pressed() -> void:
	var txt : String = %TextEditIgnExt.text.strip_edges()
	if not txt.is_empty():
		%TextEditIgnExt.text = ""
		_add_exception(txt, Exception.IGN_EXTENSION, true)

func _on_use_multithreading_check_button_toggled(toggled_on: bool) -> void:
	use_multithreading = toggled_on
	
	ProjectSettings.set(SETTING_USE_MULTITHREADING, use_multithreading)
	ProjectSettings.save()

# Exclude Section
func _on_exclude_check_button_toggled(toggled_on: bool) -> void:
	%VBoxExclude.visible = toggled_on

func _on_button_exclude_folder_pressed() -> void:
	var txt : String = %TextEditExcFolder.text.strip_edges()
	if not txt.is_empty():
		%TextEditExcFolder.text = ""
		_add_exception(txt, Exception.EXCL_FOLDER, true)

func _on_button_exclude_ext_pressed() -> void:
	var txt : String = %TextEditExcExt.text.strip_edges()
	if not txt.is_empty():
		%TextEditExcExt.text = ""
		_add_exception(txt, Exception.EXCL_EXTENSION, true)

func _on_button_exclude_cont_pressed() -> void:
	var txt : String = %TextEditExcContaining.text.strip_edges()
	if not txt.is_empty():
		%TextEditExcContaining.text = ""
		_add_exception(txt, Exception.EXCL_CONTAINING, true)

#endregion
