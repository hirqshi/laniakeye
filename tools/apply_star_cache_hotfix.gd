extends SceneTree

func _initialize() -> void:
	var path: String = "res://scenes/world/test_catalog_debug_navigation.gd"
	if not FileAccess.file_exists(path):
		print("StarCacheHotfix: navigation scene absent; star cache installed, no key changes needed")
		quit(0)
		return
	var source: String = FileAccess.get_file_as_string(path)
	if source.contains("NAV_HOTKEYS_ALT_V1"):
		print("StarCacheHotfix: Alt navigation bindings already installed")
		quit(0)
		return
	var old_lines: Array[String] = [
		"\t\t\tKEY_F8: _nav_show_marks = not _nav_show_marks\n",
		"\t\t\tKEY_F9: _nav_show_planets = not _nav_show_planets\n",
		"\t\t\tKEY_F10: _nav_show_help = not _nav_show_help\n",
	]
	var anchor: String = "\t\tvar handled: bool = true\n\t\tmatch event.keycode:"
	if source.count(anchor) != 1:
		push_error("StarCacheHotfix: unexpected navigation input handler; no file changed")
		quit(1)
		return
	for line: String in old_lines:
		if source.count(line) != 1:
			push_error("StarCacheHotfix: unexpected navigation hotkeys; no file changed")
			quit(1)
			return
	var replacement: String = "\t\t# NAV_HOTKEYS_ALT_V1: handle modifiers BEFORE the plain M action.\n"
	replacement += "\t\tif event.alt_pressed and event.keycode in [KEY_M, KEY_P, KEY_H]:\n"
	replacement += "\t\t\tmatch event.keycode:\n"
	replacement += "\t\t\t\tKEY_M: _nav_show_marks = not _nav_show_marks\n"
	replacement += "\t\t\t\tKEY_P: _nav_show_planets = not _nav_show_planets\n"
	replacement += "\t\t\t\tKEY_H: _nav_show_help = not _nav_show_help\n"
	replacement += "\t\t\tget_viewport().set_input_as_handled()\n\t\t\treturn\n"
	replacement += anchor
	var changed: String = source.replace(anchor, replacement)
	for line: String in old_lines:
		changed = changed.replace(line, "")
	changed = changed.replace("F8 marks %s | F9 planets %s | F10 nav help", "Alt+M marks %s | Alt+P planets %s | Alt+H nav help")
	var backup: String = path + ".pre_star_cache_hotfix.bak"
	if not FileAccess.file_exists(backup):
		var saved: FileAccess = FileAccess.open(backup, FileAccess.WRITE)
		if saved == null:
			push_error("StarCacheHotfix: cannot create navigation backup")
			quit(1)
			return
		saved.store_string(source)
		saved.flush()
		var backup_error: Error = saved.get_error()
		saved.close()
		if backup_error != OK:
			push_error("StarCacheHotfix: navigation backup write failed")
			quit(1)
			return
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("StarCacheHotfix: cannot write navigation script")
		quit(1)
		return
	file.store_string(changed)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_error("StarCacheHotfix: replacement failed; original navigation script retained")
		quit(1)
		return
	print("StarCacheHotfix: APPLIED Alt+M / Alt+P / Alt+H; original navigation script backed up")
	quit(0)
