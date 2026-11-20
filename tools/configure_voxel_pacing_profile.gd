extends SceneTree

const BACKUP: String = "user://frame_pacing_v1/startup_profile_backup.cfg"
const KEYS: Array[String] = ["voxel/threads/main/time_budget_ms", "voxel/threads/count/minimum", "voxel/threads/count/margin_below_maximum", "voxel/threads/count/ratio_over_maximum"]

func _initialize() -> void:
	var restore: bool = "--restore" in OS.get_cmdline_user_args()
	var backup: ConfigFile = ConfigFile.new()
	if restore:
		if backup.load(BACKUP) != OK or backup.get_value("meta", "schema", 0) != 1:
			push_error("VoxelPacingProfile: valid backup missing; restore refused")
			quit(1)
			return
		for key: String in KEYS:
			if backup.has_section_key("settings", key):
				ProjectSettings.set_setting(key, backup.get_value("settings", key))
				print("VoxelPacingProfile: RESTORE %s=%s" % [key, str(backup.get_value("settings", key))])
		if ProjectSettings.save() != OK:
			push_error("VoxelPacingProfile: cannot save project settings")
			quit(1)
			return
		print("VoxelPacingProfile: RESTORED original saved values; restart editor/game")
		quit(0)
		return
	var available: Array[String] = []
	for key: String in KEYS:
		if ProjectSettings.has_setting(key):
			available.append(key)
		else:
			print("VoxelPacingProfile: UNSUPPORTED " + key)
	if available.is_empty():
		push_error("VoxelPacingProfile: no compatible registered settings; no changes")
		quit(1)
		return
	if FileAccess.file_exists(BACKUP):
		if backup.load(BACKUP) != OK or backup.get_value("meta", "schema", 0) != 1:
			push_error("VoxelPacingProfile: invalid existing backup; no changes")
			quit(1)
			return
	else:
		backup.set_value("meta", "schema", 1)
	for key: String in available:
		if not backup.has_section_key("settings", key):
			backup.set_value("settings", key, ProjectSettings.get_setting(key))
	if DirAccess.make_dir_recursive_absolute(BACKUP.get_base_dir()) != OK or backup.save(BACKUP) != OK:
		push_error("VoxelPacingProfile: backup write failed; no changes")
		quit(1)
		return
	for key: String in available:
		var value: Variant = ProjectSettings.get_setting(key)
		match key:
			"voxel/threads/main/time_budget_ms": value = minf(2.0, maxf(0.25, float(value)))
			"voxel/threads/count/minimum": value = 1
			"voxel/threads/count/margin_below_maximum": value = maxi(2, int(value))
			"voxel/threads/count/ratio_over_maximum": value = minf(0.5, maxf(0.05, float(value)))
		ProjectSettings.set_setting(key, value)
		print("VoxelPacingProfile: SET %s=%s" % [key, str(value)])
	if ProjectSettings.save() != OK:
		push_error("VoxelPacingProfile: project settings save failed; backup retained")
		quit(1)
		return
	print("VoxelPacingProfile: SAVED startup profile. Restart editor/game. No runtime set_thread_count call.")
	print("VoxelPacingProfile: backup=" + BACKUP)
	quit(0)
