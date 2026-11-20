extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_transfer_handover_v2.gd"
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("TRANSFER_TOOL_REBIND_FIX_V1"):
		print("TransferToolFix: already installed")
		quit(0)
		return
	var commit_anchor: String = "\tadd_child(terrain)\n\t_player.setup(_frame, gravity)"
	var rollback_anchor: String = "\t_terrain = saved[\"terrain\"]\n"
	if source.count(commit_anchor) != 1 or source.count(rollback_anchor) != 1 or not source.contains("func _handover_rollback("):
		push_error("TransferToolFix: unexpected V2 source; no changes")
		quit(1)
		return
	var commit_code: String = "\tadd_child(terrain)\n\t_voxel_tool = terrain.get_voxel_tool()\n\t_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF\n\t_voxel_tool.set_raycast_binary_search_iterations(8)\n\t_player.setup(_frame, gravity)"
	var rollback_code: String = rollback_anchor + "\t_voxel_tool = _terrain.get_voxel_tool()\n\t_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF\n\t_voxel_tool.set_raycast_binary_search_iterations(8)\n"
	var changed: String = source.replace(commit_anchor, commit_code).replace(rollback_anchor, rollback_code)
	changed += "\n# TRANSFER_TOOL_REBIND_FIX_V1: voxel tool follows terrain on commit AND rollback.\n"
	var backup: String = path + ".pre_voxel_tool_rebind.bak"
	if not FileAccess.file_exists(backup) and not _write(backup, source):
		push_error("TransferToolFix: backup failed; no changes")
		quit(1)
		return
	if not _write(path + ".tmp", changed) or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("TransferToolFix: replacement failed; inspect original/backup")
		quit(1)
		return
	print("TransferToolFix: APPLIED current-terrain voxel tool on commit and rollback")
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
