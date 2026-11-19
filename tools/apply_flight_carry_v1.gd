extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_debug_flight.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("FLIGHT_ADAPTIVE_CARRY_V1"):
		print("FlightCarryInstall: already installed")
		quit(0)
		return
	var old_carry: String = "\tvar carry: bool = _flight_absolute.length() - float(_context[\"body\"][\"radius_m\"]) < debug_flight_carry_height_m\n"
	old_carry += "\tvar fixed: LkPosition64 = _catalog_frame.inertial_to_body(_flight_absolute)\n"
	old_carry += "\tvar old_axes: Basis = _catalog_frame.planet_basis()\n"
	var new_carry: String = "\t# FLIGHT_ADAPTIVE_CARRY_V1\n"
	new_carry += "\tvar body: Dictionary = _context[\"body\"]\n"
	new_carry += "\t_flight_carry_band = FlightCarry.band(float(body[\"radius_m\"]), float(body[\"surface_gravity_m_s2\"]), debug_flight_carry_height_m, debug_flight_adaptive_carry, debug_flight_carry_override_m)\n"
	new_carry += "\t_flight_carry_weight = FlightCarry.weight(_flight_absolute.length() - float(body[\"radius_m\"]), _flight_carry_band)\n"
	var old_apply: String = "\tif carry:\n"
	old_apply += "\t\t_flight_absolute = _catalog_frame.body_to_inertial(fixed)\n"
	old_apply += "\t\t_flight_basis = (_catalog_frame.planet_basis() * old_axes.inverse() * _flight_basis).orthonormalized()\n"
	var new_apply: String = "\tif _flight_carry_weight > 0.0:\n"
	new_apply += "\t\tvar carry_angle: float = _catalog_frame.angular_speed_rad_s * delta * _flight_carry_weight\n"
	new_apply += "\t\t_flight_absolute = _flight_absolute.plus(_catalog_frame.carry_displacement64(_flight_absolute, carry_angle))\n"
	new_apply += "\t\t_flight_basis = (_catalog_frame.step_basis(carry_angle) * _flight_basis).orthonormalized()\n"
	var old_export: String = "@export var debug_flight_carry_height_m: float = 1000.0"
	var new_export: String = "# Earth-reference midpoint; adaptive sizing enabled by default.\n"
	new_export += "@export var debug_flight_carry_height_m: float = 250000.0\n"
	new_export += "@export var debug_flight_adaptive_carry: bool = true\n"
	new_export += "@export var debug_flight_carry_override_m: float = 0.0\n"
	new_export += "var _flight_carry_band: Dictionary = {}\nvar _flight_carry_weight: float = 0.0"
	var const_anchor: String = "const FlightMath = preload(\"res://world/debug/lk_debug_flight_math.gd\")"
	var hud_anchor: String = "\t\t_label.text += \"\\n\" + _flight_status"
	var hud: String = "\t\tif _flight_active and _flight_carry_band.get(\"ok\", false):\n"
	hud += "\t\t\t_label.text += \"\\nSurface carry %.1f%% | transition %.2f..%.2f km | active body\" % [_flight_carry_weight * 100.0, float(_flight_carry_band[\"inner_m\"]) / 1000.0, float(_flight_carry_band[\"outer_m\"]) / 1000.0]\n"
	hud += hud_anchor
	var anchors: Array[String] = [old_carry, old_apply, old_export, const_anchor, hud_anchor]
	for anchor: String in anchors:
		if source.count(anchor) != 1:
			push_error("FlightCarryInstall: unexpected flight source; nothing changed")
			quit(1)
			return
	var changed: String = source.replace(old_carry, new_carry).replace(old_apply, new_apply)
	changed = changed.replace(old_export, new_export)
	changed = changed.replace(const_anchor, const_anchor + "\nconst FlightCarry = preload(\"res://world/debug/lk_debug_flight_carry.gd\")")
	changed = changed.replace(hud_anchor, hud)
	var backup: String = path + ".pre_adaptive_carry.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("FlightCarryInstall: backup failed")
		quit(1)
		return
	if not _write(path + ".tmp", changed):
		push_error("FlightCarryInstall: temporary write failed")
		quit(1)
		return
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("FlightCarryInstall: replacement failed")
		quit(1)
		return
	print("FlightCarryInstall: APPLIED adaptive 250km reference, smooth position/camera carry, HUD")
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
