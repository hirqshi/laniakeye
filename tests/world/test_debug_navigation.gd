extends SceneTree

const Data = preload("res://world/debug/lk_debug_navigation_data.gd")
const SceneScript = preload("res://scenes/world/test_catalog_debug_navigation.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("DebugNavigation: FAIL " + label)

func _initialize() -> void:
	var path: String = "user://debug_navigation_test_%d/markers.bin" % Time.get_ticks_usec()
	var scope: String = "test-scope"
	var marks: Array = [{"serial": 1, "body_id": "0123456789abcdef0123456789abcdef", "q": [1.0e12 + 0.125, -3.25, 6.5], "name": "Marker 001"}]
	_check(Data.load_marks(path, scope)["ok"], "absent file is empty store")
	_check(Data.validate(scope, marks, 2), "valid body-fixed record")
	_check(Data.save_marks(path, scope, marks, 2), "initial save")
	var loaded: Dictionary = Data.load_marks(path, scope)
	_check(loaded["ok"] and loaded["marks"] == marks and loaded["next_id"] == 2, "binary roundtrip retains doubles")
	_check(not Data.load_marks(path, "different-scope")["ok"], "reject foreign system scope")
	var changed: Array = marks.duplicate(true)
	changed[0]["name"] = "Updated"
	_check(Data.save_marks(path, scope, changed, 2), "replace existing save")
	_check(Data.load_marks(path, scope)["marks"] == changed, "replacement committed")
	var bad: Array = marks.duplicate(true)
	bad[0]["q"][0] = INF
	_check(not Data.save_marks(path, scope, bad, 2), "reject non-finite coordinate")
	_check(Data.load_marks(path, scope)["marks"] == changed, "failed validation preserves previous file")
	_check(not Data.validate(scope, [marks[0], marks[0]], 2), "reject duplicate serial")
	_check(not Data.validate(scope, marks, 1), "serial must precede next id")
	_check(Data.distance_text(12.5) == "12.5 m", "metres")
	_check(Data.distance_text(12500.0) == "12.50 km", "kilometres")
	_check(Data.distance_text(149597870700.0) == "1.0000 AU", "astronomical units")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	bytes[bytes.size() - 1] = bytes[bytes.size() - 1] ^ 1
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	_check(not Data.load_marks(path, scope)["ok"], "checksum rejects corruption before decoding")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	DirAccess.remove_absolute(path.get_base_dir())
	if _failures == 0:
		print("DebugNavigation: PASS marker validation, scope, persistence, replacement, precision, corruption guard, units, scene parse")
	print("DebugNavigation: visual projection, terrain occlusion and 1/2 need integration testing; NO FLIGHT in this patch")
	quit(0 if _failures == 0 else 1)
