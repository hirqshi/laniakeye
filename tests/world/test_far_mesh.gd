extends SceneTree

const Snapshot = preload("res://game/world/rendering/lk_far_body_snapshot.gd")
const FarRenderer = preload("res://game/world/rendering/lk_catalog_far_mesh.gd")
const VisualScene = preload("res://scenes/world/test_catalog_far_mesh.gd")
const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Bodies = preload("res://game/world/generation/lk_body_catalog.gd")
const Layout = preload("res://game/world/generation/lk_safe_orbit_layout.gd")
const Validator = preload("res://game/world/generation/lk_orbit_layout_validator.gd")
const BodyFrame = preload("res://game/world/runtime/lk_catalog_body_frame.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("CatalogFarMesh: FAIL " + label)


func _sphere(id: String, distance: float, radius: float) -> Dictionary:
	return {"id": id, "direction": [0.0, 0.0, -1.0], "distance_m": distance,
		"radius_relative": radius / distance, "angular_radius_rad": asin(radius / distance),
		"active": false, "star": false}


func _initialize() -> void:
	var renderer_script: Script = FarRenderer
	_check(renderer_script.get_base_script().resource_path == "res://voxel/planet_far_mesh.gd", "extends new PlanetFarMesh, not legacy distant renderer")
	var near_sphere: Dictionary = _sphere("near", 50.0, 5.0)
	var far_sphere: Dictionary = _sphere("far", 100.0, 10.0)
	var ray: Array = [0.0, 0.0, -1.0]
	_check(absf(Snapshot.ray_distance(near_sphere, ray) - 45.0) < 1.0e-10, "near intersection")
	_check(absf(Snapshot.ray_distance(far_sphere, ray) - 90.0) < 1.0e-10, "far intersection")
	_check(Snapshot.ray_distance(near_sphere, ray) < Snapshot.ray_distance(far_sphere, ray), "nearest surface ordering")
	_check(Snapshot.ray_distance(near_sphere, [0.0, 0.0, 1.0]) < 0.0, "no hit behind observer")
	var angle: float = near_sphere["angular_radius_rad"]
	_check(Snapshot.ray_distance(near_sphere, [sin(angle * 0.999), 0.0, -cos(angle * 0.999)]) > 0.0, "inside angular limb")
	_check(Snapshot.ray_distance(near_sphere, [sin(angle * 1.001), 0.0, -cos(angle * 1.001)]) < 0.0, "outside angular limb")

	var definition = Definition.new()
	var catalog = Catalog.new(definition.get_universe_id(), definition.catalog_version)
	var source: Dictionary = catalog.describe_system(0, 0, 0, 0, 0)
	var layout: Dictionary = Layout.build(Bodies.build(source))
	_check(Validator.validate(layout).is_empty(), "valid source layout")
	var expected_count: int = 1
	for planet: Dictionary in layout["planets"]:
		expected_count += 1 + planet["moons"].size()
	for slot: int in [0, 1]:
		var entry: Dictionary = layout["planets"][slot]
		var id: String = entry["body"]["id"]
		var radius: float = entry["body"]["radius_m"]
		for epoch: float in [0.0, 123456.125]:
			var body_frame = BodyFrame.new(StringName(id), entry["spin"], epoch)
			var observer: LkPosition64 = body_frame.body_to_inertial(LkPosition64.new(0.0, radius + 3.0, 0.0))
			var records: Array[Dictionary] = Snapshot.build(layout, id, observer, epoch)
			_check(records.size() == expected_count, "all system bodies sampled")
			var active: Dictionary = {}
			for record: Dictionary in records:
				if record["active"]:
					active = record
				var d: Array = record["direction"]
				var squared: float = float(d[0]) * float(d[0]) + float(d[1]) * float(d[1]) + float(d[2]) * float(d[2])
				_check(absf(squared - 1.0) < 1.0e-12, "normalized relative centre")
				_check(absf(float(record["radius_relative"]) * float(record["distance_m"]) - float(record["radius_m"])) < 1.0e-5, "radius and angular scale preserved")
			_check(not active.is_empty(), "active sphere included")
			if not active.is_empty():
				_check(absf(float(active["distance_m"]) - radius - 3.0) < 1.0e-6, "active centre avoids astronomical cancellation")
				_check(absf(Snapshot.ray_distance(active, active["direction"]) - 3.0) < 1.0e-5, "active near hit")
			var selected: Dictionary = Snapshot.select(records, Vector3.FORWARD, 64, 0.0)
			_check(selected["bodies"][0]["id"] == id, "active sphere first")
			_check(selected["bodies"].size() <= 64, "GPU budget respected")
			var reversed: Array[Dictionary] = records.duplicate()
			reversed.reverse()
			_check(selected == Snapshot.select(reversed, Vector3.FORWARD, 64, 0.0), "selection independent of input order")
			_check(records == Snapshot.build(layout, id, observer, epoch), "repeatable snapshot")
			print("CatalogFarMesh: body=%s epoch=%.3f total=%d selected=%d filtered=%d omitted=%d" % [
				id, epoch, records.size(), selected["bodies"].size(), selected["filtered"], selected["budget_omitted"],
			])

	# Explicit overflow fixture: omitted bodies are reported, never hidden from stats.
	var crowded: Array[Dictionary] = []
	var own: Dictionary = _sphere("active", 20.0, 10.0)
	own["active"] = true
	crowded.append(own)
	var star: Dictionary = _sphere("star", 1000.0, 100.0)
	star["star"] = true
	crowded.append(star)
	for i: int in range(100):
		crowded.append(_sphere("body_%03d" % i, 2000.0 + i, 1.0))
	var crowded_selection: Dictionary = Snapshot.select(crowded, Vector3.FORWARD, 64, 0.0)
	_check(crowded_selection["bodies"].size() == 64 and crowded_selection["budget_omitted"] == 38, "explicit overflow accounting")
	if _failures == 0:
		print("CatalogFarMesh: PASS new FarMesh base, snapshots, angular scale, ray ordering, determinism, budget, scene parse")
	quit(0 if _failures == 0 else 1)
