extends SceneTree

const SpriteData = preload("res://game/world/rendering/lk_star_sprite_data.gd")
const SpriteRenderer = preload("res://game/world/rendering/lk_star_sprites.gd")
const VisualScene = preload("res://scenes/world/test_catalog_star_sprites.gd")
const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Photo = preload("res://game/world/generation/lk_stellar_photometry.gd")
const FarSnapshot = preload("res://game/world/rendering/lk_far_body_snapshot.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("StarSprites: FAIL " + label)


func _candidate(id: String, distance: float, direction: Array) -> Dictionary:
	return {"star_id": id, "distance_ly": distance, "direction_galaxy": direction}


func _initialize() -> void:
	var root: String = Identity.universe_id("star-sprite-unit-test-v1")
	var ids: Array[String] = []
	for i: int in range(3):
		ids.append(Identity.child_id(root, "star_fixture", str(i)))
	var a: Dictionary = _candidate(ids[0], 10.0, [0.0, 0.0, -1.0])
	var b: Dictionary = _candidate(ids[1], 20.0, [1.0, 0.0, 0.0])
	var c: Dictionary = _candidate(ids[2], 30.0, [0.0, 1.0, 0.0])
	var built: Dictionary = SpriteData.build([a, b, c], 20.0, 8)
	_check(built["ok"] and built["complete"] and built["stars"].size() == 3, "prepare three sprites")
	_check(built == SpriteData.build([c, a, b], 20.0, 8), "input order independent")
	var cap: Dictionary = SpriteData.build([a, b, c], 20.0, 1)
	_check(cap["ok"] and not cap["complete"] and cap["budget_omitted"] == 2, "sprite cap explicit")
	_check(cap["stars"][0] == built["stars"][0], "brightest retained")
	_check(not SpriteData.build([a, a], 20.0)["ok"], "reject duplicate star")
	var invalid: Dictionary = _candidate(ids[0], 10.0, [0.0, 0.0, 2.0])
	_check(not SpriteData.build([invalid], 20.0)["ok"], "reject non-unit direction")
	var near: Dictionary = SpriteData.build([a], 20.0)
	var far: Dictionary = SpriteData.build([_candidate(ids[0], 100.0, [0.0, 0.0, -1.0])], 20.0)
	_check(absf(float(near["stars"][0]["flux_at_limit"]) / float(far["stars"][0]["flux_at_limit"]) - 100.0) < 1.0e-9, "raw flux obeys inverse square")
	var photo: Dictionary = Photo.describe_star(ids[0])
	var rgb: Array = photo["color_srgb"]
	var expected: Color = Color(rgb[0], rgb[1], rgb[2]).srgb_to_linear()
	_check(near["stars"][0]["color_linear"] == expected, "one sRGB-to-linear conversion")
	var empty: Dictionary = SpriteData.build([a, b, c], -30.0)
	_check(empty["ok"] and empty["stars"].is_empty(), "photometric limit actually filters")
	# Occluder rays use exact same normalized-sphere representation as FarMesh.
	var body: Dictionary = {"direction": [0.0, 0.0, -1.0], "radius_relative": 0.1, "distance_m": 1000.0}
	_check(FarSnapshot.ray_distance(body, [0.0, 0.0, -1.0]) > 0.0, "foreground body blocks star ray")
	_check(FarSnapshot.ray_distance(body, [1.0, 0.0, 0.0]) < 0.0, "open sky ray")
	var source: String = FileAccess.get_file_as_string("res://game/world/rendering/lk_star_sprites.gdshader")
	_check(source.contains("scene_depth") and source.contains("occluder_spheres[64]"), "depth and FarMesh mask shader contract")
	_check(source.contains("INSTANCE_CUSTOM.xyz") and source.contains("radius_px"), "directional procedural sprite shader contract")
	print("StarSprites: CPU/contract tests only; GPU image and loading-time need visual test")
	if _failures == 0:
		print("StarSprites: PASS sprite data, brightness, colors, ordering, budget, occlusion geometry, scene parse")
	quit(0 if _failures == 0 else 1)
