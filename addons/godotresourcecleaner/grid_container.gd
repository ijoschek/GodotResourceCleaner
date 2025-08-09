@tool
extends GridContainer
## Setting and handling filters

@export var root_window : Window
@export var button : Button

func _ready() -> void:
	# Name checkboxes
	for c in get_children():
		c.text = "." + c.name
	
	# Toggle all button
	button.pressed.connect(_toggle_all)
	
	# Connect and set every CheckBox
	if root_window:
		for c in get_children():
			if c is CheckBox:
				c.toggled.connect(root_window.on_checkbox_toggled.bind(c.text))
#				c.button_pressed = true
#				root_window.on_checkbox_toggled(true, c.text)

func _toggle_all() -> void:
	# Determine if all checkboxes are pressed
	var all_pressed := true
	for c in get_children():
		if c is CheckBox:
			if !c.button_pressed:
				all_pressed = false
				break
	
	# Toggle all checkboxes based on current state
	for c in get_children():
		if c is CheckBox:
			if all_pressed:
				c.button_pressed = false
			else:
				c.button_pressed = true
