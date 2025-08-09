extends Node
class_name FileUtils

static func scan_res(
			filter_on: bool,
			search_ext: Array,
			exclude_folder: Array,
			exclude_ext: Array,
			exclude_containing: Array,
			keep_paths: Array,
			ignore_on: bool,
			ignore_folder: Array,
			ignore_ext: Array) -> Array:
	var all_files = get_all_files(
			"res://",
			exclude_folder,
			exclude_ext,
			exclude_containing)
	var all_dependencies = collect_all_dependencies(all_files)
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
