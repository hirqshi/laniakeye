extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_auto_surface.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("PREFETCH_HOOKS_V1"):
		print("ApproachInstall: hooks already installed")
		quit(0)
		return
	var old_target: String = "var target_result: Dictionary = AutoPolicy.surface_target(_catalog_frame.inertial_to_body(_flight_absolute), radius)"
	var old_cancel: String = "if not AutoPolicy.in_target(target, _auto_target, 96.0) or height > _auto_limit() * 1.2:"
	var old_start: String = "not AutoPolicy.should_start(height, closing, _auto_limit(), maxf(1.0, auto_surface_horizon_s), maxf(1.0, auto_surface_hover_height_m))"
	var old_activate: String = "if height > 512.0 or not AutoPolicy.in_target(point, _auto_target, 48.0):"
	for token: String in [old_target, old_cancel, old_start, old_activate]:
		if source.count(token) != 1:
			push_error("ApproachInstall: unexpected auto-surface source; nothing changed")
			quit(1)
			return
	var changed: String = source.replace(old_target, "var target_result: Dictionary = _prefetch_surface_target(radius)")
	changed = changed.replace(old_cancel, "if _prefetch_target_invalid(target, height):")
	changed = changed.replace(old_start, "not _prefetch_should_start(height, closing)")
	changed = changed.replace(old_activate, "if height > _prefetch_activation_height() or not AutoPolicy.in_target(point, _auto_target, 48.0):")
	changed += "\n# PREFETCH_HOOKS_V1: defaults preserve original scene behavior.\n"
	changed += "func _prefetch_surface_target(radius: float) -> Dictionary:\n\treturn AutoPolicy.surface_target(_catalog_frame.inertial_to_body(_flight_absolute), radius)\n"
	changed += "\nfunc _prefetch_target_invalid(target: LkPosition64, height: float) -> bool:\n\treturn not AutoPolicy.in_target(target, _auto_target, 96.0) or height > _auto_limit() * 1.2\n"
	changed += "\nfunc _prefetch_should_start(height: float, closing: float) -> bool:\n\treturn AutoPolicy.should_start(height, closing, _auto_limit(), maxf(1.0, auto_surface_horizon_s), maxf(1.0, auto_surface_hover_height_m))\n"
	changed += "\nfunc _prefetch_activation_height() -> float:\n\treturn 512.0\n"
	var backup: String = path + ".pre_seamless_approach.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("ApproachInstall: backup failed")
		quit(1)
		return
	if not _write(path + ".tmp", changed) or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("ApproachInstall: write/replacement failed")
		quit(1)
		return
	print("ApproachInstall: APPLIED four prefetch hooks; old scene defaults preserved")
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
