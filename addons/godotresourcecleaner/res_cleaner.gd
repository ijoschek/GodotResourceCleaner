@tool
extends EditorPlugin
## Init Plugin

const WINDOW = preload("res://addons/godotresourcecleaner/window.tscn")
const ICON = preload("res://addons/godotresourcecleaner/icon.svg")

var button : Button
var window : Window

func _enter_tree() -> void:
	# Add toolbar button
	button = Button.new()
	button.icon = ICON
	button.tooltip_text = "Open Godot Resource Cleaner"
	button.pressed.connect(_on_button_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, button)

	# Load and attach window
	window = WINDOW.instantiate()
	window.visible = false
	EditorInterface.get_base_control().add_child(window)

func _on_button_pressed() -> void:
	window.popup_centered()
	window.grab_focus()

func _exit_tree() -> void:
	# Clean up plugin
	remove_control_from_container(CONTAINER_TOOLBAR, button)
	button.queue_free()
	window.queue_free()
