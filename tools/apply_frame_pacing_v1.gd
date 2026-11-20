extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_auto_surface.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("FRAME_PACING_VIEW_HOOK_V1"):
		print("FramePacingInstall: view hook already installed")
		quit(0)
		return
	var a: String = "_terrain.view_distance = 192"
	var b: String = "_auto_viewer.view_distance = 192"
	if not source.contains("PREFETCH_HOOKS_V1") or source.count(a) != 1 or source.count(b) != 1:
		push_error("FramePacingInstall: unexpected auto-surface source; no file changed")
		quit(1)
		return
	var changed: String = source.replace(a, "_terrain.view_distance = _prefetch_promoted_view_distance()")
	changed = changed.replace(b, "_auto_viewer.view_distance = _prefetch_promoted_view_distance()")
	changed += "\n# FRAME_PACING_VIEW_HOOK_V1: legacy scenes keep their original view.\nfunc _prefetch_promoted_view_distance() -> int:\n\treturn 192\n"
	var backup: String = path + ".pre_frame_pacing.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("FramePacingInstall: backup failed")
		quit(1)
		return
	if not _write(path + ".tmp", changed) or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("FramePacingInstall: write/replacement failed")
		quit(1)
		return
	print("FramePacingInstall: APPLIED view hook; old scenes default192 unchanged")
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
