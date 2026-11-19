extends SceneTree

func _initialize() -> void:
	var path: String = "res://world/debug/lk_debug_navigation_data.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("NAV_PROJECTION_SAFE_V1"):
		print("NavProjectionHotfix: already installed")
		quit(0)
		return
	var signature: String = "static func project_direction(camera: Camera3D, direction: Vector3, viewport: Vector2) -> Dictionary:"
	var start: int = source.find(signature)
	if not source.contains("class_name LkDebugNavigationData") or source.count(signature) != 1:
		push_error("NavProjectionHotfix: unexpected source/signature; no file changed")
		quit(1)
		return
	var end: int = source.find("\nstatic func ", start + signature.length())
	if end == -1:
		end = source.length()
	var old: String = source.substr(start, end - start)
	if not old.contains("camera.unproject_position("):
		push_error("NavProjectionHotfix: expected old projection not found; no file changed")
		quit(1)
		return
	var replacement: String = signature + "\n\t# NAV_PROJECTION_SAFE_V1\n"
	replacement += "\tconst SafeProjection = preload(\"res://world/debug/lk_debug_navigation_projection.gd\")\n"
	replacement += "\treturn SafeProjection.project_direction(camera, direction, viewport)\n\n"
	var changed: String = source.substr(0, start) + replacement + source.substr(end)
	var backup: String = path + ".pre_projection_hotfix.bak"
	if not FileAccess.file_exists(backup):
		if not _write_text(backup, source):
			push_error("NavProjectionHotfix: backup failed; no source changed")
			quit(1)
			return
	if not _write_text(path + ".tmp", changed):
		push_error("NavProjectionHotfix: temporary write failed")
		quit(1)
		return
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("NavProjectionHotfix: replacement failed; original source retained")
		quit(1)
		return
	print("NavProjectionHotfix: APPLIED safe camera-space projection; marker persistence untouched")
	quit(0)

func _write_text(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK
