extends SceneTree

const Policy4 = preload("res://world/debug/lk_auto_transfer_policy.gd")
const Math4 = preload("res://world/debug/lk_debug_flight_math.gd")
const Scene4 = preload("res://scenes/world/test_catalog_auto_transfer_v4.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("AutoTransfer4: FAIL " + label)

func _initialize() -> void:
	for radius: float in [100.0, 10000.0, 1000000.0, 4600000.0, 1000000000.0]:
		var limits: Dictionary = Policy4.heights(radius)
		_check(limits["switch_m"] >= 20000.0 and limits["switch_m"] <= 200000.0 and limits["prepare_m"] > limits["switch_m"], "thresholds within validated V2 window")
		var offset: LkPosition64 = LkPosition64.new(1.0e10, 0.0, 0.0)
		var guard: Dictionary = Policy4.entry_guard(offset, radius)
		var spheres: Array = [{"center": [0.0, 1.0e12, 0.0], "radius": 1000.0}]
		var first: PackedByteArray = var_to_bytes(spheres[0])
		spheres.append(guard)
		var allowed: float = Math4.safe_step(Vector3.LEFT, 1.0e15, spheres)
		var final_height: float = offset.x - allowed - radius
		_check(absf(final_height - (float(limits["switch_m"]) - 0.5)) < 0.001, "huge full step cannot skip handover entry shell")
		_check(final_height >= 10000.0, "entry shell stays above V2 minimum")
		_check(spheres.size() == 2 and var_to_bytes(spheres[0]) == first, "ancestor sphere remains untouched")
		var inside: LkPosition64 = LkPosition64.new(radius + float(limits["switch_m"]) * 0.75, 0.0, 0.0)
		var inside_spheres: Array = [Policy4.entry_guard(inside, radius)]
		_check(Math4.safe_step(Vector3.LEFT, 100.0, inside_spheres) == 0.0, "pending entry guard blocks deeper penetration")
		_check(Math4.safe_step(Vector3.RIGHT, 100.0, inside_spheres) == 100.0, "entry guard allows outward recovery")
	var entries: Array[Dictionary] = [
		{"id": "P", "label": "planet", "planet_slot": 0, "moon_slot": -1, "body": {"radius_m": 100.0}},
		{"id": "FAR", "label": "far", "planet_slot": 0, "moon_slot": 0, "body": {"radius_m": 10.0}},
		{"id": "NEAR", "label": "near", "planet_slot": 0, "moon_slot": 1, "body": {"radius_m": 10.0}},
		{"id": "OTHER", "label": "other family", "planet_slot": 1, "moon_slot": 0, "body": {"radius_m": 10.0}}]
	var states: Dictionary = {"bodies": [
		{"id": "P", "position_m": [1.0e12, 0.0, 0.0]},
		{"id": "FAR", "position_m": [1.0e12 + 10000.0, 0.0, 0.0]},
		{"id": "NEAR", "position_m": [1.0e12 + 1000.0, 0.0, 0.0]},
		{"id": "OTHER", "position_m": [1.0e12 + 2000.0, 0.0, 0.0]}]}
	var saved: PackedByteArray = var_to_bytes(states)
	var rows: Array[Dictionary] = Policy4.rows(entries, 0, states, "P", LkPosition64.new(101.0, 0.0, 0.0))
	_check(rows.size() == 3 and rows[0]["index"] == 0 and rows[1]["index"] == 2 and rows[2]["index"] == 1, "family filter and nearest moons first")
	_check(rows[0]["active"] and var_to_bytes(states) == saved, "active row and snapshot unchanged")
	var script: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_auto_transfer_v4.gd")
	_check(script.contains("var spheres: Array = super._flight_spheres()") and script.contains("spheres.append(AutoTransferPolicy4.entry_guard"), "inherited sphere chain retained")
	_check(not script.contains("func _tick_flight(") and not script.contains("func _try_flight_landing(") and not script.contains("func _update_navigation_tick("), "original flight/collision/G/navigation tick retained")
	_check(script.contains("super._handover()") and script.contains("_auto4_guard_epoch == _universe_clock.now_s()"), "route audit retained and moving gate bound to current epoch")
	_check(not script.contains("KEY_F8") and not script.contains("KEY_F6") and not script.contains("KEY_F7") and not script.contains("KEY_F9"), "no new F-key shortcuts")
	var parent_source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_transfer_handover_v2.gd")
	_check(parent_source.contains("TRANSFER4_MOTION_HOOK_V1") and parent_source.contains("if not _handover_motion_allowed():"), "installer applied")
	_check(ResourceLoader.load("res://scenes/world/test_catalog_auto_transfer_v4.tscn") is PackedScene, "scene resource parses")
	var instance = Scene4.new()
	instance.set("_flight_actual_speed", 0.0)
	_check(instance._handover_motion_allowed(), "manual stopped gate preserved")
	instance.set("_flight_actual_speed", 10.0)
	_check(not instance._handover_motion_allowed(), "manual moving gate still refuses")
	instance.set("_auto4_request_in_progress", true)
	_check(not instance._handover_motion_allowed(), "private flag alone cannot authorize moving handover")
	instance.free()
	if _failures == 0:
		print("AutoTransfer4: PASS entry-shell full-step/outward recovery, family/nearest list, inherited chain, manual motion gates, scene parse")
	print("AutoTransfer4: moving native handover, UI interaction, preparation latency and moon landing require in-game acceptance")
	quit(0 if _failures == 0 else 1)
