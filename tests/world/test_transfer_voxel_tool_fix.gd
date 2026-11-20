extends SceneTree

func _initialize() -> void:
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_transfer_handover_v2.gd")
	var commit: String = "\tadd_child(terrain)\n\t_voxel_tool = terrain.get_voxel_tool()\n\t_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF\n\t_voxel_tool.set_raycast_binary_search_iterations(8)\n\t_player.setup(_frame, gravity)"
	var rollback: String = "\t_terrain = saved[\"terrain\"]\n\t_voxel_tool = _terrain.get_voxel_tool()\n\t_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF\n\t_voxel_tool.set_raycast_binary_search_iterations(8)"
	if not source.contains("TRANSFER_TOOL_REBIND_FIX_V1") or not source.contains(commit) or not source.contains(rollback):
		push_error("TransferToolFix: FAIL commit/rollback binding missing")
		quit(1)
		return
	if not ResourceLoader.load("res://scenes/world/test_catalog_auto_transfer_v4.tscn") is PackedScene:
		push_error("TransferToolFix: FAIL auto scene parse")
		quit(1)
		return
	print("TransferToolFix: PASS source binding on commit/rollback and scene parse; native crash reproduction still required")
	quit(0)
