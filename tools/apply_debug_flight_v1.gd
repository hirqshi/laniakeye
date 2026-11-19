extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_debug_navigation.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("func _update_navigation_tick(delta: float) -> void:"):
		print("DebugFlightInstall: navigation tick hook already installed")
		quit(0)
		return
	var anchor: String = "func _physics_process(delta: float) -> void:\n\tsuper._physics_process(delta)\n"
	if source.count(anchor) != 1 or not source.contains("const NavData"):
		push_error("DebugFlightInstall: unexpected navigation source; no file changed")
		quit(1)
		return
	var replacement: String = anchor + "\t_update_navigation_tick(delta)\n\nfunc _update_navigation_tick(delta: float) -> void:\n"
	var changed: String = source.replace(anchor, replacement)
	var backup: String = path + ".pre_debug_flight.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("DebugFlightInstall: backup failed")
		quit(1)
		return
	if not _write(path + ".tmp", changed):
		push_error("DebugFlightInstall: temporary write failed")
		quit(1)
		return
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("DebugFlightInstall: replacement failed")
		quit(1)
		return
	print("DebugFlightInstall: APPLIED navigation tick hook; walking callback still calls same navigation logic")
	quit(0)

func _write(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK
