extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_auto_surface.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("PACING_SANDBOX_HOOK_V2"):
		print("Pacing2Install: sandbox hook already installed")
		quit(0)
		return
	var original: String = "\t\t\t_pending.global_transform = Transform3D.IDENTITY\n\t\t\t_pending.force_update_transform()"
	if source.count(original) != 1 or not source.contains("FRAME_PACING_VIEW_HOOK_V1"):
		push_error("Pacing2Install: unexpected auto-surface source; nothing changed")
		quit(1)
		return
	var changed: String = source.replace(original, "\t\t\t_set_prefetch_sandbox_transform()")
	changed += "\n# PACING_SANDBOX_HOOK_V2: preserve legacy default behavior.\nfunc _set_prefetch_sandbox_transform() -> void:\n\t_pending.global_transform = Transform3D.IDENTITY\n\t_pending.force_update_transform()\n"
	var backup: String = path + ".pre_frame_pacing_v2.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		quit(1)
		return
	if not _write(path + ".tmp", changed) or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		quit(1)
		return
	print("Pacing2Install: APPLIED sandbox pose hook; baseline behavior retained")
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
