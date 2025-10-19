extends Node
class_name FileUtils

signal progress_updated(current: int, total: int, message: String)

static var _instance: FileUtils
static var _mutex: Mutex
static var _active_threads: Array[Thread] = []
static var _should_cancel: bool = false

static func get_instance() -> FileUtils:
	if not _instance:
		_instance = FileUtils.new()
		_mutex = Mutex.new()
	return _instance

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_threads()

static func scan_res(
			filter_on: bool,
			search_ext: Array,
			exclude_folder: Array,
			exclude_ext: Array,
			exclude_containing: Array,
			keep_paths: Array,
			ignore_on: bool,
			ignore_folder: Array,
			ignore_ext: Array,
			use_threading: bool = true) -> Array:
	
	if use_threading:
		print("Start Multithreaded Scan...")
		return scan_res_threaded(
				filter_on,
				search_ext,
				exclude_folder,
				exclude_ext,
				exclude_containing,
				keep_paths,
				ignore_on,
				ignore_folder,
				ignore_ext
		)
	else:
		print("Start Singletreaded Scan...")
		return scan_res_single_threaded(
				filter_on,
				search_ext,
				exclude_folder,
				exclude_ext,
				exclude_containing,
				keep_paths,
				ignore_on,
				ignore_folder,
				ignore_ext
		)

static func scan_res_single_threaded(
			filter_on: bool,
			search_ext: Array,
			exclude_folder: Array,
			exclude_ext: Array,
			exclude_containing: Array,
			keep_paths: Array,
			ignore_on: bool,
			ignore_folder: Array,
			ignore_ext: Array) -> Array:
	
	var instance = get_instance()
	instance.progress_updated.emit(0, 100, "Scanning files (single-threaded)...")
	
	var all_files = get_all_files(
			"res://",
			exclude_folder,
			exclude_ext,
			exclude_containing)
	
	instance.progress_updated.emit(40, 100, "Analyzing dependencies...")
	var all_dependencies = collect_all_dependencies(all_files)
	
	instance.progress_updated.emit(80, 100, "Filtering results...")
	var no_dependency_files := []
	
	for f in all_files:
		if filter_on and not has_extension(f, search_ext):
			continue
		if keep_paths.has(f):
			continue
		if ignore_on:
			if has_folder(f, ignore_folder):
				continue
			if has_extension(f, ignore_ext):
				continue
		if not all_dependencies.has(f):
			no_dependency_files.append({
				"path": f,
				"size": FileUtils.get_file_size(f),
				"is_checked": false,
			})
	
	instance.progress_updated.emit(100, 100, "Scan complete!")
	return no_dependency_files

static func scan_res_threaded(
			filter_on: bool,
			search_ext: Array,
			exclude_folder: Array,
			exclude_ext: Array,
			exclude_containing: Array,
			keep_paths: Array,
			ignore_on: bool,
			ignore_folder: Array,
			ignore_ext: Array) -> Array:
		
	var instance = get_instance()
	_should_cancel = false
	
	# Clean up any lingering threads from previous operations
	_cleanup_threads()
	
	# Phase 1: Get all files (use same method as single-threaded for consistency)
	instance.progress_updated.emit(0, 100, "Scanning files (multi-threaded)...")
	var all_files = get_all_files(
			"res://",
			exclude_folder,
			exclude_ext,
			exclude_containing)
	
	if _should_cancel:
		return []
	
	# Phase 2: Collect dependencies using threading
	instance.progress_updated.emit(30, 100, "Analyzing dependencies (multi-threaded)...")
	var all_dependencies = collect_all_dependencies_threaded(all_files)
	
	if _should_cancel:
		return []
	
	# Phase 3: Filter files
	instance.progress_updated.emit(60, 100, "Filtering results...")
	var no_dependency_files = filter_files_threaded(
		all_files,
		all_dependencies,
		filter_on,
		search_ext,
		keep_paths,
		ignore_on,
		ignore_folder,
		ignore_ext)
	
	instance.progress_updated.emit(100, 100, "Scan complete!")
	return no_dependency_files

static func get_all_files(
		root: String,
		exclude_folder: Array,
		exclude_ext: Array,
		exclude_containing: Array) -> Array:
	var result := []
	var dir := DirAccess.open(root)
	if not dir:
		return result
	
	dir.list_dir_begin()
	while true:
		if _should_cancel:
			break
			
		var dir_name = dir.get_next()
		if dir_name == "":
			break
		if dir_name in [".", ".."]:
			continue

		var full_path := root.path_join(dir_name)

		if dir.current_is_dir():
			if not is_in_list(dir_name, exclude_folder):
				result += get_all_files(full_path, exclude_folder, exclude_ext, exclude_containing)
		elif not has_extension(dir_name, exclude_ext) and not contains_any(full_path, exclude_containing):
			result.append(full_path)
	
	dir.list_dir_end()
	return result

static func _get_all_files_no_cancel(
		root: String,
		exclude_folder: Array,
		exclude_ext: Array,
		exclude_containing: Array) -> Array:
	var result := []
	var dir := DirAccess.open(root)
	if not dir:
		return result
	
	dir.list_dir_begin()
	while true:
		var dir_name = dir.get_next()
		if dir_name == "":
			break
		if dir_name in [".", ".."]:
			continue

		var full_path := root.path_join(dir_name)

		if dir.current_is_dir():
			if not is_in_list(dir_name, exclude_folder):
				result += _get_all_files_no_cancel(full_path, exclude_folder, exclude_ext, exclude_containing)
		elif not has_extension(dir_name, exclude_ext) and not contains_any(full_path, exclude_containing):
			result.append(full_path)
	
	dir.list_dir_end()
	return result

static func _get_files_in_single_directory(
		root: String,
		exclude_ext: Array,
		exclude_containing: Array) -> Array:
	var result := []
	var dir := DirAccess.open(root)
	if not dir:
		return result
	
	dir.list_dir_begin()
	while true:
		var dir_name = dir.get_next()
		if dir_name == "":
			break
		if dir_name in [".", ".."]:
			continue
		
		var full_path := root.path_join(dir_name)
		
		# Only process files, not subdirectories (subdirectories are handled separately)
		if not dir.current_is_dir():
			if not has_extension(dir_name, exclude_ext) and not contains_any(full_path, exclude_containing):
				result.append(full_path)
	
	dir.list_dir_end()
	return result

static func get_all_files_threaded(
		root: String,
		exclude_folder: Array,
		exclude_ext: Array,
		exclude_containing: Array) -> Array:
	
	var result := []
	var instance = get_instance()
	
	# Get root directories to distribute work
	var root_dirs = _get_root_directories(root, exclude_folder)
	var total_dirs = root_dirs.size()
	
	if total_dirs == 0:
		return result
	
	var threads: Array[Thread] = []
	var results: Array = []
	var processed_dirs = 0
	
	# Initialize results array
	for i in range(total_dirs):
		results.append([])
	
	# Create worker threads
	var max_threads = min(OS.get_processor_count(), total_dirs)
	var dirs_per_thread = ceili(float(total_dirs) / max_threads)
	
	for thread_id in range(max_threads):
		var thread = Thread.new()
		var start_idx = thread_id * dirs_per_thread
		var end_idx = min(start_idx + dirs_per_thread, total_dirs)
		
		if start_idx < total_dirs:
			var thread_data = {
				"thread_id": thread_id,
				"start_idx": start_idx,
				"end_idx": end_idx,
				"root_dirs": root_dirs,
				"exclude_folder": exclude_folder,
				"exclude_ext": exclude_ext,
				"exclude_containing": exclude_containing,
				"results": results
			}
			
			thread.start(_file_scan_worker.bind(thread_data))
			threads.append(thread)
	
	# Store threads for proper cleanup
	_mutex.lock()
	for thread in threads:
		_active_threads.append(thread)
	_mutex.unlock()
	
	# Wait for threads and collect results
	for i in range(threads.size()):
		var thread = threads[i]
		thread.wait_to_finish()
		
		_mutex.lock()
		processed_dirs += 1
		var progress = int((float(processed_dirs) / threads.size()) * 30)  # 30% of total progress
		instance.progress_updated.emit(progress, 100, "Scanning directories... (%d/%d)" % [processed_dirs, threads.size()])
		_mutex.unlock()
	
	# Clean up completed threads
	_mutex.lock()
	for thread in threads:
		_active_threads.erase(thread)
	_mutex.unlock()
	
	# Combine results
	for thread_result in results:
		result += thread_result
	
	return result

static func _get_root_directories(root: String, exclude_folder: Array) -> Array:
	var dirs := []
	var dir := DirAccess.open(root)
	if not dir:
		return dirs
	
	# First, add the root directory to process files in root
	dirs.append(root)
	
	# Then add subdirectories
	dir.list_dir_begin()
	while true:
		var dir_name = dir.get_next()
		if dir_name == "":
			break
		if dir_name in [".", ".."]:
			continue
		
		if dir.current_is_dir() and not is_in_list(dir_name, exclude_folder):
			dirs.append(root.path_join(dir_name))
	dir.list_dir_end()
	
	return dirs

static func _file_scan_worker(data: Dictionary) -> void:
	var thread_id = data.thread_id
	var start_idx = data.start_idx
	var end_idx = data.end_idx
	var root_dirs = data.root_dirs
	var exclude_folder = data.exclude_folder
	var exclude_ext = data.exclude_ext
	var exclude_containing = data.exclude_containing
	var results = data.results
	
	var thread_result := []
	
	for i in range(start_idx, end_idx):
		if _should_cancel:
			break
			
		var dir_path = root_dirs[i]
		var dir_files = _get_files_in_single_directory(dir_path, exclude_ext, exclude_containing)
		thread_result += dir_files
	
	_mutex.lock()
	results[thread_id] = thread_result
	_mutex.unlock()

static func contains_any(target: String, list: Array) -> bool:
	for sub in list:
		if target.contains(sub):
			return true
	return false

static func is_in_list(target: String, list: Array) -> bool:
	for item in list:
		if target == item:
			return true
	return false

static func has_extension(path: String, list: Array) -> bool:
	for ext in list:
		if path.ends_with(ext):
			return true
	return false

static func has_folder(path: String, list: Array) -> bool:
	var segments = path.replace("res://", "").split("/")
	for folder in list:
		if folder in segments:
			return true
	return false

static func collect_all_dependencies(paths: Array) -> Array:
	var all_deps := []
	for p in paths:
		for d in ResourceLoader.get_dependencies(p):
			var path : String = d.get_slice("::", 2)
			if !all_deps.has(path):
				all_deps.append(path)
	return all_deps

static func collect_all_dependencies_threaded(paths: Array) -> Array:
	var instance = get_instance()
	var all_deps := []
	var total_files = paths.size()
	
	if total_files == 0:
		return all_deps
	
	var threads: Array[Thread] = []
	var results: Array = []
	var processed_files = 0
	
	var max_threads = min(OS.get_processor_count(), total_files)
	var files_per_thread = ceili(float(total_files) / max_threads)
	
	# Initialize results array
	for i in range(max_threads):
		results.append([])
	
	# Create worker threads
	for thread_id in range(max_threads):
		var thread = Thread.new()
		var start_idx = thread_id * files_per_thread
		var end_idx = min(start_idx + files_per_thread, total_files)
		
		if start_idx < total_files:
			var thread_data = {
				"thread_id": thread_id,
				"start_idx": start_idx,
				"end_idx": end_idx,
				"paths": paths,
				"results": results
			}
			
			thread.start(_dependency_worker.bind(thread_data))
			threads.append(thread)
	
	# Store threads for proper cleanup
	_mutex.lock()
	for thread in threads:
		_active_threads.append(thread)
	_mutex.unlock()
	
	# Wait for threads and collect results
	for i in range(threads.size()):
		var thread = threads[i]
		thread.wait_to_finish()
		
		_mutex.lock()
		processed_files += files_per_thread
		var progress = 30 + int((float(min(processed_files, total_files)) / total_files) * 30)  # 30-60% of total progress
		instance.progress_updated.emit(progress, 100, "Analyzing dependencies... (%d/%d)" % [min(processed_files, total_files), total_files])
		_mutex.unlock()
	
	# Clean up completed threads
	_mutex.lock()
	for thread in threads:
		_active_threads.erase(thread)
	_mutex.unlock()
	
	# Combine and deduplicate results
	var deps_set := {}
	for thread_result in results:
		for dep in thread_result:
			deps_set[dep] = true
	
	return deps_set.keys()

static func _dependency_worker(data: Dictionary) -> void:
	var thread_id = data.thread_id
	var start_idx = data.start_idx
	var end_idx = data.end_idx
	var paths = data.paths
	var results = data.results
	
	var thread_deps := []
	
	for i in range(start_idx, end_idx):
		if _should_cancel:
			break
			
		var p = paths[i]
		var deps = ResourceLoader.get_dependencies(p)
		for d in deps:
			var path: String = d.get_slice("::", 2)
			if not thread_deps.has(path):
				thread_deps.append(path)
	
	_mutex.lock()
	results[thread_id] = thread_deps
	_mutex.unlock()

static func filter_files_threaded(
		all_files: Array,
		all_dependencies: Array,
		filter_on: bool,
		search_ext: Array,
		keep_paths: Array,
		ignore_on: bool,
		ignore_folder: Array,
		ignore_ext: Array) -> Array:
	
	var instance = get_instance()
	var no_dependency_files := []
	var total_files = all_files.size()
	var processed_files = 0
	
	for i in range(total_files):
		if _should_cancel:
			break
			
		var f = all_files[i]
		if filter_on and not has_extension(f, search_ext):
			continue
		if keep_paths.has(f):
			continue
		if ignore_on:
			if has_folder(f, ignore_folder):
				continue
			if has_extension(f, ignore_ext):
				continue
		if not all_dependencies.has(f):
			no_dependency_files.append({
				"path": f,
				"size": FileUtils.get_file_size(f),
				"is_checked": false,
			})
		
		processed_files += 1
		if processed_files % 50 == 0:  # Update every 50 files
			var progress = 60 + int((float(processed_files) / total_files) * 40)  # 60-100% of total progress
			instance.progress_updated.emit(progress, 100, "Filtering results... (%d/%d)" % [processed_files, total_files])
	
	return no_dependency_files

static func cancel_scan() -> void:
	_should_cancel = true
	_cleanup_threads()

static func _cleanup_threads() -> void:
	if not _mutex:
		return
		
	var threads_to_wait : Array
	_mutex.lock()
	threads_to_wait = _active_threads.duplicate()
	_active_threads.clear()
	_mutex.unlock()
	
	# Wait for all active threads to complete
	for thread in threads_to_wait:
		if thread and thread is Thread:
			if thread.is_alive():
				thread.wait_to_finish()
			thread = null  # Explicitly release reference
	
	_mutex.lock()
	_active_threads.clear()
	_mutex.unlock()

static func sorting(no_dependency_files: Array, sort: int) -> void:
	if no_dependency_files.is_empty():
		return
		
	match sort:
		0: # NONE:
			pass
		1: # SIZE_ASC
			no_dependency_files.sort_custom(func(a, b):
				if a.size == b.size:
					return a.path < b.path
				return a.size < b.size)
		2: # SIZE_DESC
			no_dependency_files.sort_custom(func(a, b):
				if a.size == b.size:
					return a.path < b.path
				return a.size > b.size)
		3: # PATH_ASC
			no_dependency_files.sort_custom(func(a, b):
				return a.path < b.path)
		4: # PATH_DESC
			no_dependency_files.sort_custom(func(a, b):
				return a.path > b.path)

static func delete_selected(no_dependency_files: Array) -> void:
	var dir = DirAccess.open("res://")
	if not dir:
		return
		
	var deleted_count := 0
	var space_freed := 0
	
	for ndf in no_dependency_files:
		if ndf.is_checked:
			var path = ndf.path
			if dir.file_exists(path):
				var err = dir.remove(path)
				if err == OK:
					deleted_count += 1
					space_freed += ndf.size
					print("File deleted: ", path)
					
					# Check for .import file of same folder
					var import_path = path + ".import"
					if dir.file_exists(import_path):
						var import_err = dir.remove(import_path)
						if import_err == OK:
							print("Associated .import file deleted: ", import_path)
						else:
							print("Failed to delete .import file: ", import_path)
							
					# Check for .uid file of same folder
					var uid_path = path + ".uid"
					if dir.file_exists(uid_path):
						var uid_err = dir.remove(uid_path)
						if uid_err == OK:
							print("Associated .uid file deleted: ", uid_path)
						else:
							print("Failed to delete .uid file: ", uid_path)
				else:
					print("Failed to delete File: ", path)
					
	print("Deleted %d unused files, freed %s" % [deleted_count, FileUtils.format_file_size(space_freed)])

static func clean_import(root: String, exclude_folder: Array) -> void:
	var deleted_count := [0]  # use an array to pass by reference
	_clean_orphaned_files(root, ".import", exclude_folder, deleted_count)
	print("Deleted %d orphaned .import files" % deleted_count[0])

static func clean_uid(root: String, exclude_folder: Array) -> void:
	var deleted_count := [0]  # use an array to pass by reference
	_clean_orphaned_files(root, ".uid", exclude_folder, deleted_count)
	print("Deleted %d orphaned .uid files" % deleted_count[0])

static func _clean_orphaned_files(root: String, extension: String, exclude_folder: Array, count: Array) -> void:
	var dir := DirAccess.open(root)
	if not dir:
		return
		
	dir.list_dir_begin()
	while true:
		var dir_name = dir.get_next()
		if dir_name == "":
			break
		if dir_name in [".", ".."]:
			continue
		
		var path = root.path_join(dir_name)
		
		if dir.current_is_dir():
			if not is_in_list(dir_name, exclude_folder):
				_clean_orphaned_files(path, extension, exclude_folder, count)
		elif dir_name.ends_with(extension):
			var source_path = path.replace(extension, "")
			if not FileAccess.file_exists(source_path):
				var err = dir.remove(path)
				if err == OK:
					count[0] += 1
					print("Deleted:", path)
				else:
					print("Failed to delete:", path)
	dir.list_dir_end()

static func clean_empty_folders(root: String, exclude_folder: Array) -> void:
	var deleted_count := [0]  # use an array to pass by reference
	_remove_empty_dirs(root, exclude_folder, deleted_count)
	print("Deleted %d empty folders" % deleted_count[0])

static func _remove_empty_dirs(root: String, exclude_folder: Array, deleted_count: Array) -> bool:
	var dir := DirAccess.open(root)
	if not dir:
		return false

	var is_empty := true
	dir.list_dir_begin()
	while true:
		var dir_name = dir.get_next()
		if dir_name == "":
			break
		if dir_name in [".", ".."]:
			continue
			
		var path = root.path_join(dir_name)
		
		if dir.current_is_dir():
			if not is_in_list(dir_name, exclude_folder):
				if not _remove_empty_dirs(path, exclude_folder, deleted_count):
					is_empty = false
		else:
			is_empty = false
	dir.list_dir_end()

	if is_empty:
		var parent_dir := DirAccess.open(root.get_base_dir())
		if parent_dir and parent_dir.remove(root) == OK:
			deleted_count[0] += 1
			print("Deleted empty folder:", root)
		return true
	return false

static func get_file_size(path: String) -> int:
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			return file.get_length()
	return 0

static func format_file_size(bytes: int) -> String:
	if bytes >= 1_073_741_824:
		return "%.1f GB" % (bytes / 1_073_741_824.0)
	elif bytes >= 1_048_576:
		return "%.1f MB" % (bytes / 1_048_576.0)
	elif bytes >= 1024:
		return "%.1f KB" % (bytes / 1024.0)
	else:
		return "%d B" % bytes
