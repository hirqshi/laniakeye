extends SceneTree

const Schema = preload("res://game/debug/lk_voxel_thread_schema_v2.gd")
const BACKUP: String = "user://frame_pacing_v2/native_profile_backup.cfg"

func _initialize() -> void:
	var engine: Object
	if Engine.has_singleton("VoxelEngine"):
		engine = Engine.get_singleton("VoxelEngine")
	var names: Array = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var key: String = property["name"]
		if key.begins_with("voxel/threads/"):
			var value: Variant = ProjectSettings.get_setting(key)
			print("VoxelProfile2: REGISTERED %s=%s" % [key, str(value)])
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				names.append(key)
	if engine != null and engine.has_method("get_thread_count"):
		print("VoxelProfile2: CURRENT_PROCESS_THREADS=%s" % str(engine.call("get_thread_count")))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--restore" in args:
		_restore()
		return
	var resolved: Dictionary = Schema.resolve(names)
	for kind: String in ["minimum", "margin", "ratio", "maximum"]:
		print("VoxelProfile2: RESOLVE %s=%s matches=%s" % [kind, str(resolved[kind]), str(resolved[kind + "_matches"])])
	if not "--apply" in args:
		print("VoxelProfile2: READ ONLY; use -- --apply --threads=3 to save detected startup keys")
		quit(0)
		return
	if not resolved["can_cap"]:
		push_error("VoxelProfile2: no unique registered worker-cap key; NO settings changed; send REGISTERED/RESOLVE lines")
		quit(1)
		return
	var cpus: int = maxi(1, OS.get_processor_count())
	var target: int = mini(3, maxi(1, cpus - 2))
	for arg: String in args:
		if arg.begins_with("--threads="):
			var text: String = arg.trim_prefix("--threads=")
			if not text.is_valid_int():
				push_error("VoxelProfile2: invalid thread count")
				quit(1)
				return
			target = clampi(text.to_int(), 1, maxi(1, cpus - 1))
	var values: Dictionary = {}
	if resolved["minimum"] != "":
		values[resolved["minimum"]] = 1
	if resolved["maximum"] != "":
		var old_max: int = int(ProjectSettings.get_setting(resolved["maximum"]))
		values[resolved["maximum"]] = mini(target, old_max) if old_max > 0 else target
	if resolved["margin"] != "":
		values[resolved["margin"]] = maxi(int(ProjectSettings.get_setting(resolved["margin"])), cpus - target)
	if resolved["ratio"] != "":
		var old_ratio: float = float(ProjectSettings.get_setting(resolved["ratio"]))
		var desired: float = float(target) / float(cpus)
		values[resolved["ratio"]] = minf(old_ratio, desired) if old_ratio > 0.0 else desired
	var backup: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(BACKUP) and (backup.load(BACKUP) != OK or backup.get_value("meta", "schema", 0) != 2):
		push_error("VoxelProfile2: invalid backup; NO settings changed")
		quit(1)
		return
	backup.set_value("meta", "schema", 2)
	backup.set_value("meta", "target_threads", target)
	for key: String in values:
		if not backup.has_section_key("before", key):
			backup.set_value("before", key, ProjectSettings.get_setting(key))
	if DirAccess.make_dir_recursive_absolute(BACKUP.get_base_dir()) != OK or backup.save(BACKUP) != OK:
		push_error("VoxelProfile2: backup failed; NO settings changed")
		quit(1)
		return
	for key: String in values:
		ProjectSettings.set_setting(key, values[key])
		print("VoxelProfile2: SET %s=%s" % [key, str(values[key])])
	if ProjectSettings.save() != OK:
		push_error("VoxelProfile2: save failed; backup retained")
		quit(1)
		return
	print("VoxelProfile2: SAVED logical_cpus=%d requested_cap=%d; RESTART editor/game and verify actual count" % [cpus, target])
	quit(0)

func _restore() -> void:
	var backup: ConfigFile = ConfigFile.new()
	if backup.load(BACKUP) != OK or backup.get_value("meta", "schema", 0) != 2:
		push_error("VoxelProfile2: valid backup missing")
		quit(1)
		return
	for key: String in backup.get_section_keys("before"):
		if ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, backup.get_value("before", key))
			print("VoxelProfile2: RESTORE " + key)
	if ProjectSettings.save() != OK:
		quit(1)
		return
	print("VoxelProfile2: RESTORED v2 keys; restart editor/game")
	quit(0)
