extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_debug_flight.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("FLIGHT_SPHERE_CPU4_HOOKS_V1"):
		print("FlightCPU4Install: already installed")
		quit(0)
		return
	var signature: String = "func _flight_spheres() -> Array:\n"
	var stop: String = "\nfunc _flight_local_terrain_ready()"
	var state_line: String = "\tvar states: Dictionary = _flight_system_states()\n"
	var ready_line: String = "\tvar local_ready: bool = _flight_local_terrain_ready()\n"
	var flag: String = "var flight_cpu_sections_enabled: bool = false"
	var movement: String = "\tvar spheres: Array = _flight_spheres()\n"
	if not source.contains("FLIGHT_CPU3_HOOKS_V1") or source.count(signature) != 1 or source.count(flag) != 1 or source.count(movement) != 1:
		push_error("FlightCPU4Install: expected installed CPU3 source missing; nothing changed")
		quit(1)
		return
	var begin: int = source.find(signature)
	var end: int = source.find(stop, begin)
	if end < 0:
		push_error("FlightCPU4Install: sphere method boundary not found; no changes")
		quit(1)
		return
	var old_body: String = source.substr(begin + signature.length(), end - begin - signature.length())
	if not old_body.begins_with(state_line) or old_body.count(ready_line) != 1 or not old_body.contains("return spheres"):
		push_error("FlightCPU4Install: unexpected sphere builder; nothing changed")
		quit(1)
		return
	var legacy: String = old_body.substr(state_line.length()).replace(ready_line, "")
	var replacement: String = signature
	replacement += "\tvar sphere_us: int = Time.get_ticks_usec() if flight_sphere_sections_enabled else 0\n"
	replacement += state_line
	replacement += "\tsphere_us = _flight_sphere_boundary(\"states\", sphere_us)\n"
	replacement += "\tif states.is_empty():\n\t\t_fail_gate(\"empty flight system states\")\n\t\treturn []\n"
	replacement += ready_line
	replacement += "\tsphere_us = _flight_sphere_boundary(\"terrain_readiness\", sphere_us)\n"
	replacement += "\tvar result: Array = _build_flight_body_spheres(states, local_ready)\n"
	replacement += "\tsphere_us = _flight_sphere_boundary(\"relative_build\", sphere_us)\n\treturn result\n"
	var changed: String = source.substr(0, begin) + replacement + source.substr(end)
	changed = changed.replace(flag, flag + "\nvar flight_sphere_sections_enabled: bool = false")
	changed = changed.replace(movement, movement + "\tif _failed:\n\t\treturn # Fail closed before any movement if sphere data was rejected.\n")
	changed += "\n# FLIGHT_SPHERE_CPU4_HOOKS_V1: original builder retained as default.\n"
	changed += "func _build_flight_body_spheres(states: Dictionary, local_ready: bool) -> Array:\n" + legacy
	changed += "\nfunc _flight_sphere_boundary(section: String, started: int) -> int:\n\tif not flight_sphere_sections_enabled:\n\t\treturn 0\n\tvar now: int = Time.get_ticks_usec()\n\t_flight_sphere_section(section, now - started)\n\treturn now\n"
	changed += "\nfunc _flight_sphere_section(_section: String, _elapsed_us: int) -> void:\n\tpass\n"
	var backup: String = path + ".pre_flight_cpu4.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("FlightCPU4Install: backup failed")
		quit(1)
		return
	if not _write(path + ".tmp", changed) or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("FlightCPU4Install: write/replacement failed; backup retained")
		quit(1)
		return
	print("FlightCPU4Install: APPLIED sphere scopes, legacy-builder hook and fail-closed movement check")
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
