#@tool
extends RefCounted
class_name TestFileUtils

## Test class for FileUtils to verify single-threaded and multi-threaded implementations

static func run_all_tests() -> void:
	print("Starting FileUtils tests...")
	
	# Test basic functionality
	test_helper_functions()
	
	# Test scanning (you'll need some test files in your project for this to be meaningful)
	test_scan_comparison()
	
	# Test progress reporting
	test_progress_reporting()
	
	print("All tests completed!")

static func test_helper_functions() -> void:
	print("\n=== Testing Helper Functions ===")
	
	# Test contains_any
	assert(FileUtils.contains_any("test_file.gd", ["test"]) == true, "contains_any should find 'test' in filename")
	assert(FileUtils.contains_any("script.cs", ["test"]) == false, "contains_any should not find 'test' in filename")
	print("✓ contains_any tests passed")
	
	# Test is_in_list
	assert(FileUtils.is_in_list("addons", ["addons", ".git"]) == true, "is_in_list should find 'addons'")
	assert(FileUtils.is_in_list("scripts", ["addons", ".git"]) == false, "is_in_list should not find 'scripts'")
	print("✓ is_in_list tests passed")
	
	# Test has_extension
	assert(FileUtils.has_extension("test.gd", [".gd", ".cs"]) == true, "has_extension should find .gd")
	assert(FileUtils.has_extension("test.txt", [".gd", ".cs"]) == false, "has_extension should not find .txt")
	print("✓ has_extension tests passed")
	
	# Test has_folder
	assert(FileUtils.has_folder("res://scripts/player.gd", ["scripts"]) == true, "has_folder should find 'scripts'")
	assert(FileUtils.has_folder("res://assets/texture.png", ["scripts"]) == false, "has_folder should not find 'scripts'")
	print("✓ has_folder tests passed")

static func test_scan_comparison() -> void:
	print("\n=== Testing Scan Comparison ===")
	
	# Setup test parameters
	var filter_on = false
	var search_ext: Array[String] = []
	var exclude_folder = [".godot", "addons", ".git"]
	var exclude_ext = [".godot", ".import", ".uid"]
	var exclude_containing = ["gitignore", "gitattributes"]
	var keep_paths: Array[String] = []
	var ignore_on = false
	var ignore_folder: Array[String] = []
	var ignore_ext: Array[String] = []
	
	print("Running single-threaded scan...")
	var start_ticks = Time.get_ticks_msec()
	var single_threaded_results = FileUtils.scan_res(
		filter_on, search_ext, exclude_folder, exclude_ext, exclude_containing,
		keep_paths, ignore_on, ignore_folder, ignore_ext, false)
	var single_threaded_ms = Time.get_ticks_msec() - start_ticks
	var single_threaded_time = _format_elapsed_ms(single_threaded_ms)
	
	print("Running multi-threaded scan...")
	start_ticks = Time.get_ticks_msec()
	var multi_threaded_results = FileUtils.scan_res(
		filter_on, search_ext, exclude_folder, exclude_ext, exclude_containing,
		keep_paths, ignore_on, ignore_folder, ignore_ext, true)
	var multi_threaded_ms = Time.get_ticks_msec() - start_ticks
	var multi_threaded_time = _format_elapsed_ms(multi_threaded_ms)
	
	# Compare results
	print("Single-threaded found: %d files in %s" % [single_threaded_results.size(), single_threaded_time])
	print("Multi-threaded found: %d files in %s" % [multi_threaded_results.size(), multi_threaded_time])
	
	# Debug: show first few files from each method
	print("\nFirst 5 single-threaded files:")
	for i in range(min(5, single_threaded_results.size())):
		print("  ", single_threaded_results[i].path)
	
	print("\nFirst 5 multi-threaded files:")
	for i in range(min(5, multi_threaded_results.size())):
		print("  ", multi_threaded_results[i].path)
	
	# If different sizes, show the difference
	if single_threaded_results.size() != multi_threaded_results.size():
		print("\n⚠️  Different result counts detected!")
		print("Difference: %d files" % abs(single_threaded_results.size() - multi_threaded_results.size()))
		
		# Create sets for detailed comparison
		var single_paths = {}
		var multi_paths = {}
		
		for file_info in single_threaded_results:
			single_paths[file_info.path] = true
		for file_info in multi_threaded_results:
			multi_paths[file_info.path] = true
		
		# Find files only in single-threaded
		var only_in_single = []
		for path in single_paths.keys():
			if not multi_paths.has(path):
				only_in_single.append(path)
		
		# Find files only in multi-threaded
		var only_in_multi = []
		for path in multi_paths.keys():
			if not single_paths.has(path):
				only_in_multi.append(path)
		
		if only_in_single.size() > 0:
			print("\nFiles only found by single-threaded (%d):" % only_in_single.size())
			for i in range(min(10, only_in_single.size())):
				print("  ", only_in_single[i])
		
		if only_in_multi.size() > 0:
			print("\nFiles only found by multi-threaded (%d):" % only_in_multi.size())
			for i in range(min(10, only_in_multi.size())):
				print("  ", only_in_multi[i])
	
	# Verify both methods found the same files
	assert(single_threaded_results.size() == multi_threaded_results.size(), 
		"Both methods should find the same number of files")
	
	# Create sets for comparison (files might be in different order)
	var single_paths_comp = {}
	var multi_paths_comp = {}
	
	for file_info in single_threaded_results:
		single_paths_comp[file_info.path] = true
		
	for file_info in multi_threaded_results:
		multi_paths_comp[file_info.path] = true
	
	for path in single_paths_comp.keys():
		assert(multi_paths_comp.has(path), "Multi-threaded should find file: " + path)
	
	for path in multi_paths_comp.keys():
		assert(single_paths_comp.has(path), "Single-threaded should find file: " + path)
	
	print("✓ Both scanning methods produce identical results")
	
	# Performance comparison
	if multi_threaded_ms < single_threaded_ms:
		var improvement = float(single_threaded_ms - multi_threaded_ms) / float(single_threaded_ms) * 100.0
		print("✓ Multi-threaded scan was %.1f%% faster" % improvement)
	else:
		print("! Multi-threaded scan was not faster (possibly due to small dataset or overhead)")

static func test_progress_reporting() -> void:
	print("\n=== Testing Progress Reporting ===")
	
	var progress_updates := []
	var instance = FileUtils.get_instance()
	
	# Connect to progress signal
	var progress_callback = func(current: int, total: int, message: String):
		progress_updates.append({"current": current, "total": total, "message": message})
		print("Progress: %d/%d - %s" % [current, total, message])
	
	instance.progress_updated.connect(progress_callback)
	
	# Run a scan to test progress reporting
	print("Testing progress updates with single-threaded scan...")
	FileUtils.scan_res_single_threaded(false, [], [".godot", "addons"], [".import"], [], [], false, [], [])
	
	# Disconnect the callback
	instance.progress_updated.disconnect(progress_callback)
	
	# Verify we got progress updates
	assert(progress_updates.size() > 0, "Should have received progress updates")
	
	# Verify progress goes from 0 to 100
	assert(progress_updates[0].current == 0, "First progress should start at 0")
	assert(progress_updates[-1].current == 100, "Last progress should end at 100")
	
	# Verify progress is monotonic (always increases)
	for i in range(1, progress_updates.size()):
		assert(progress_updates[i].current >= progress_updates[i-1].current, 
			"Progress should be monotonic: %d >= %d" % [progress_updates[i].current, progress_updates[i-1].current])
	
	print("✓ Progress reporting works correctly")
	print("✓ Received %d progress updates" % progress_updates.size())

static func _format_elapsed_ms(elapsed_ms: int) -> String:
	if elapsed_ms < 1000:
		return "%d ms" % elapsed_ms
	else:
		return "%.2f s" % (elapsed_ms / 1000.0)

# Utility to run tests from the editor
static func run_tests_in_editor() -> void:
	if Engine.is_editor_hint():
		run_all_tests()
	else:
		print("Tests should be run in the editor!")
