extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_debug_flight.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("FLIGHT_CPU6_HOOKS_V1"):
		print("FlightCPU6Install: already installed")
		quit(0)
		return
	var spheres_line: String = "\tvar spheres: Array = _flight_spheres()\n"
	var step_line: String = "\tvar allowed: float = FlightMath.safe_step(direction, requested, spheres)\n"
	var marker: String = "FLIGHT_SPHERE_CPU4_HOOKS_V1"
	if not source.contains(marker) or source.count(spheres_line) != 1 or source.count(step_line) != 1:
		push_error("FlightCPU6Install: expected CPU4 source missing; nothing changed")
		quit(1)
		return
	var changed: String = source.replace(spheres_line, "\tvar spheres: Variant = _flight_spheres()\n")
	changed = changed.replace(step_line, "\tvar allowed: float = _flight_safe_step(direction, requested, spheres)\n")
	changed += "\n# FLIGHT_CPU6_HOOKS_V1: default movement guard remains original FlightMath.safe_step.\n"
	changed += "func _flight_safe_step(direction: Vector3, requested: float, spheres: Variant) -> float:\n\treturn FlightMath.safe_step(direction, requested, spheres)\n"
	var backup: String = path + ".pre_flight_cpu6.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("FlightCPU6Install: backup failed")
		quit(1)
		return
	if not _write(path + ".tmp", changed) or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("FlightCPU6Install: write/replacement failed; backup retained")
		quit(1)
		return
	print("FlightCPU6Install: APPLIED Variant spheres and virtual safe-step hook")
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
