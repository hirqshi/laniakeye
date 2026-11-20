extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_transfer_handover_v2.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("TRANSFER4_MOTION_HOOK_V1"):
		print("AutoTransfer4Install: already installed")
		quit(0)
		return
	var condition: String = "\tif absf(_flight_actual_speed) > 0.01:\n"
	if source.count(condition) != 1 or not source.contains("func _handover() -> void:") or source.contains("func _handover_motion_allowed("):
		push_error("AutoTransfer4Install: expected working Handover2 source not found; nothing changed")
		quit(1)
		return
	var changed: String = source.replace(condition, "\tif not _handover_motion_allowed():\n")
	changed += "\n# TRANSFER4_MOTION_HOOK_V1: manual/default path still requires stop.\nfunc _handover_motion_allowed() -> bool:\n\treturn absf(_flight_actual_speed) <= 0.01\n"
	var backup: String = path + ".pre_auto_transfer4.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("AutoTransfer4Install: backup failed; nothing changed")
		quit(1)
		return
	if not _write(path + ".tmp", changed) or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("AutoTransfer4Install: replacement failed; original/backup retained")
		quit(1)
		return
	print("AutoTransfer4Install: APPLIED motion hook; default stopped handover unchanged")
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
