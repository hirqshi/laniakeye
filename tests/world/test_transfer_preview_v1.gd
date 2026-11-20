extends SceneTree

const TargetModel1 = preload("res://world/debug/lk_transfer_target_model.gd")
const Store1 = preload("res://world/runtime/lk_body_journal_store.gd")
const PreviewScene1 = preload("res://scenes/world/test_catalog_transfer_preview_v1.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("Transfer1: FAIL " + label)

func _entry(id: String, family: String, slot: int, radius: float) -> Dictionary:
	return {"body": {"id": id, "family": family, "slot": slot, "radius_m": radius}, "orbit": {}, "spin": {}, "moons": []}

func _initialize() -> void:
	var a_id: String = "11111111111111111111111111111111"
	var b_id: String = "22222222222222222222222222222222"
	var m_id: String = "33333333333333333333333333333333"
	var gas_id: String = "44444444444444444444444444444444"
	var gm_id: String = "55555555555555555555555555555555"
	var a: Dictionary = _entry(a_id, "rocky", 0, 100.0)
	a["moons"].append(_entry(m_id, "rocky", 0, 3.0))
	var gas: Dictionary = _entry(gas_id, "gas_giant", 1, 1000.0)
	gas["moons"].append(_entry(gm_id, "icy", 0, 5.0))
	var b: Dictionary = _entry(b_id, "rocky", 2, 10.0)
	var layout: Dictionary = {"layout_version": 1, "system_id": "fixture", "planets": [a, gas, b]}
	var model = TargetModel1.new()
	_check(model.configure(layout, a_id), "bind")
	_check(model.entries.size() == 4, "solid planets and moons, gas parent excluded")
	_check(model.current()["id"] == m_id, "default selects other body")
	var found_gas_moon: bool = false
	for entry: Dictionary in model.entries:
		_check(entry["id"] != gas_id, "gas giant not landable")
		if entry["id"] == gm_id:
			found_gas_moon = true
	_check(found_gas_moon, "moon of gas giant remains selectable")
	model.selected = 0
	model.cycle(-1)
	_check(model.current()["id"] == b_id, "cycle wraps backwards")
	model.cycle(1)
	_check(model.current()["id"] == a_id, "cycle wraps forward")
	model.selected = 3
	var template: Dictionary = {"body": a["body"], "universe_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "placement": {}, "address": {"planet_slot": 0}, "manifest": {"format": 1, "universe_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "body_id": a_id, "catalog_version": 1, "body_schema_version": 1, "terrain_version": 1, "surface_recipe": "integration_sphere_v1", "radius_m": 100.0}}
	var saved_template: PackedByteArray = var_to_bytes(template)
	var context: Dictionary = model.target_context(template)
	_check(context["manifest"]["body_id"] == b_id and context["manifest"]["radius_m"] == 10.0, "target-specific manifest")
	_check(context["address"]["planet_slot"] == 2 and not context["address"].has("moon_slot"), "planet address")
	_check(Store1.journal_path(context["manifest"]) != Store1.journal_path(template["manifest"]), "separate journal address")
	var axes: Array = [[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]]
	var states: Dictionary = {"system_id": "fixture", "time_s": 12.25, "bodies": [
		{"id": a_id, "position_m": [1.0e12, 0.0, 0.0], "body_to_system_axes": axes},
		{"id": b_id, "position_m": [1.0e12 + 1000.0, 0.0, 0.0], "body_to_system_axes": axes}]}
	var saved_states: PackedByteArray = var_to_bytes(states)
	var observer: LkPosition64 = LkPosition64.new(11.0, 0.0, 0.0)
	var plan: Dictionary = model.plan(states, a_id, observer, 12.25)
	_check(plan["ok"] and plan["distance_m"] == 989.0 and plan["height_m"] == 979.0, "relative target offset in doubles")
	var fixed: LkPosition64 = plan["fixed_surface"]
	_check(fixed.x == 0.0 and fixed.y == 0.0 and fixed.z == 10.0, "transpose target axes to body-fixed surface")
	_check(not model.plan(states, a_id, observer, 12.250001)["ok"], "exact epoch guard")
	var wrong_scope: Dictionary = states.duplicate(true)
	wrong_scope["system_id"] = "other"
	_check(not model.plan(wrong_scope, a_id, observer, 12.25)["ok"], "system guard")
	model.selected = 0
	plan = model.plan(states, a_id, observer, 12.25)
	_check(plan["ok"] and plan["distance_m"] == 11.0, "active-body exact relative position")
	model.selected = 1
	context = model.target_context(template)
	_check(context["body"]["id"] == m_id and context["address"]["planet_slot"] == 0 and context["address"]["moon_slot"] == 0, "moon context")
	_check(var_to_bytes(template) == saved_template and var_to_bytes(states) == saved_states, "inputs unchanged")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_transfer_preview_v1.gd")
	_check(not source.contains("\t_context =") and not source.contains("\t_manifest =") and not source.contains("BodyStore.write_journal("), "no active-context or journal writes")
	_check(source.contains("own_world_3d = true") and source.contains("activation_enabled=false"), "isolation and no activation")
	_check(not source.contains("func _tick_flight(") and not source.contains("func _flight_spheres(") and not source.contains("func _update_navigation_tick("), "working flight and safety chains inherited")
	_check(ResourceLoader.load("res://scenes/world/test_catalog_transfer_preview_v1.tscn") is PackedScene, "scene resource parses")
	var instance = PreviewScene1.new()
	instance.free()
	if _failures == 0:
		print("Transfer1: PASS target selection, gas/moon filtering, immutable manifests, separate journal paths, frame math, exact scope/epoch, scene parse")
	print("Transfer1: isolated voxel generation/collider readiness requires in-game F8 test; no cross-body activation implemented")
	quit(0 if _failures == 0 else 1)
