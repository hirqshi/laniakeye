extends SceneTree
## Headless test. Run:
## godot --headless --path . --script res://tests/game/test_clock_service.gd

const ServiceScript = preload("res://game/world/clock_service.gd")
const ClockStore = preload("res://game/world/runtime/lk_world_clock_store.gd")
const Identity = preload("res://game/world/generation/lk_world_identity.gd")

var _failures: int = 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("ClockService: PASS")
	else:
		printerr("ClockService: FAIL count=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_base_dir()))


func _run() -> void:
	var universe: String = Identity.child_id(Identity.universe_id("clock-service-test"), "test_fixture", "clock_service_v1")
	_check(Identity.is_valid_id(universe), "fixture universe id is valid")
	if not Identity.is_valid_id(universe):
		return
	var path: String = ClockStore.clock_path(universe)
	_remove_fixture(path)

	var failures: Array = []
	var service = ServiceScript.new()
	service.failed.connect(func(reason: String) -> void: failures.append(reason))
	_check(not service.is_open(), "service starts closed")
	_check(not service.advance(0.1), "advance on a closed service is rejected")
	_check(failures.size() == 1 and service.last_error != "", "closed advance reports failure")

	var invalid = ServiceScript.new()
	_check(not invalid.open("invalid"), "invalid universe id is rejected")
	_check(not invalid.is_open(), "failed open leaves the service closed")

	_check(service.open(universe), "open a new universe")
	_check(service.is_open() and not service.loaded_existing, "new universe has no saved clock")
	_check(service.now_s() == 0.0, "new universe starts at zero")
	_check(not service.open(universe), "second open is rejected while open")

	for tick: int in range(600):
		service.advance(1.0 / 60.0)
	_check(absf(service.now_s() - 10.0) < 1.0e-9, "600 ticks of 1/60 s advance exactly 10 s")
	var before: float = service.now_s()
	_check(not service.advance(-1.0) and not service.advance(NAN), "invalid delta is rejected")
	_check(service.now_s() == before, "invalid delta leaves the epoch unchanged")

	_check(not FileAccess.file_exists(path), "no autosave before the interval")
	_check(service.save(), "explicit save")
	_check(FileAccess.file_exists(path), "save wrote the clock file")
	_remove_fixture(path)
	service.autosave_interval_s = 1.0
	_check(service.advance(0.5) and not FileAccess.file_exists(path), "no autosave at half the interval")
	_check(service.advance(0.5) and FileAccess.file_exists(path), "autosave fires when the interval is reached")

	var saved: float = service.now_s()
	_check(service.close(), "close saves and releases the clock")
	_check(not service.is_open() and service.now_s() == 0.0, "closed service reports no clock")

	var reopened = ServiceScript.new()
	_check(reopened.open(universe), "reopen the saved universe")
	_check(reopened.loaded_existing, "saved clock is found")
	_check(reopened.now_s() == saved, "exact epoch round trip with no offline accrual")
	_check(reopened.close(), "close the reopened service")
	_remove_fixture(path)
