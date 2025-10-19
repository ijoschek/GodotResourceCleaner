#@tool
extends Button

## Simple test runner button
## Add this to a button node and it will run FileUtils tests when pressed

@export var test_script : Script

func _ready():
	text = "Run FileUtils Tests"
	pressed.connect(_on_pressed)

func _on_pressed():
	if not test_script:
		return
		
	var separator = ""
	for i in range(50):
		separator += "="
	print("\n" + separator)
	print("RUNNING FILEUTILS TESTS")
	print(separator)
	
	if test_script:
		test_script.run_all_tests()
	else:
		print("Could not load test script!")
		
	print(separator)
