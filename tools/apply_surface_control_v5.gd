extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_debug_flight.gd"
	var source: String = FileAccess.get_file_as_string(path)
	var handover: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_transfer_handover_v2.gd")
	if not handover.contains("TRANSFER_TOOL_REBIND_FIX_V1"):
		push_error("SurfaceControl5Install: apply previous voxel-tool rebind fix first; no changes")
		quit(1)
		return
	if source.contains("SURFACE_CONTROL5_SPEED_HOOK_V1"):
		print("SurfaceControl5Install: already installed")
		quit(0)
		return
	var old_line: String = "\t_flight_requested_speed = FlightMath.speed_at_height(_flight_height, _flight_multiplier * boost)"
	if source.count(old_line) != 1 or source.contains("func _flight_speed_at_height("):
		push_error("SurfaceControl5Install: expected DebugFlight source missing; no changes")
		quit(1)
		return
	var changed: String = source.replace(old_line, "\t_flight_requested_speed = _flight_speed_at_height(_flight_height, _flight_multiplier * boost)")
	changed += "\n# SURFACE_CONTROL5_SPEED_HOOK_V1: legacy scenes keep exact original speed.\nfunc _flight_speed_at_height(height: float, multiplier: float) -> float:\n\treturn FlightMath.speed_at_height(height, multiplier)\n"
	var backup: String = path + ".pre_surface_control5.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("SurfaceControl5Install: backup failed")
		quit(1)
		return
	if not _write(path + ".tmp", changed) or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("SurfaceControl5Install: replacement failed; inspect original/backup")
		quit(1)
		return
	print("SurfaceControl5Install: APPLIED default-preserving speed hook")
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
