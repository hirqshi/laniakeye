extends SceneTree

const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
const Context = preload("res://game/world/runtime/lk_body_context.gd")
const BodyFrame = preload("res://game/world/runtime/lk_catalog_body_frame.gd")
const Store = preload("res://game/world/runtime/lk_body_journal_store.gd")
const Identity = preload("res://game/world/generation/lk_world_identity.gd")
# Parse the visual scene script as part of this smoke test.
const IntegrationScene = preload("res://scenes/world/test_catalog_planet.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("CatalogBridge: FAIL " + label)


func _initialize() -> void:
	var definition = Definition.new()
	var a: Dictionary = Context.resolve(definition, 0, 0, 0, 0, 0, 0)
	var b: Dictionary = Context.resolve(definition, 0, 0, 0, 0, 0, 1)
	_check(not a.is_empty() and not b.is_empty(), "two solid target contexts")
	if a.is_empty() or b.is_empty():
		quit(1)
		return
	_check(a["body"]["id"] != b["body"]["id"], "distinct body IDs")
	_check(Store.journal_path(a["manifest"]) != Store.journal_path(b["manifest"]), "body save namespace separation")
	_check(a == Context.resolve(definition, 0, 0, 0, 0, 0, 0), "repeatable context")
	var body_frame = BodyFrame.new(StringName(a["body"]["id"]), a["spin"], 0.0)
	var q: LkPosition64 = LkPosition64.new(9000000.125, -7000000.375, 2500000.0625)
	var worst: float = 0.0
	for i: int in range(10):
		var round_trip: LkPosition64 = body_frame.inertial_to_body(body_frame.body_to_inertial(q))
		worst = maxf(worst, round_trip.minus(q).length())
		var before: LkPosition64 = body_frame.body_to_inertial(q)
		var step: float = body_frame.advance(0.125)
		var expected: LkPosition64 = body_frame.body_to_inertial(q).minus(before)
		var carried: LkPosition64 = body_frame.carry_displacement64(before, step)
		_check(expected.minus(carried).length() < 1.0e-6, "full orientation and carry agree")
	_check(worst < 1.0e-6, "double precision rotation inverse")
	var body: Dictionary = a["body"]
	var gravity: LkGravityBody = LkGravityBody.new(StringName(body["id"]), LkPosition64.new(), body["radius_m"], body["mu_m3_s2"])
	var acceleration: Vector3 = gravity.acceleration_at(LkPosition64.new(body["radius_m"], 0.0, 0.0))
	_check(absf(acceleration.length() - float(body["surface_gravity_m_s2"])) / float(body["surface_gravity_m_s2"]) < 1.0e-6, "catalog gravity adapter")

	# Test namespace is distinct from actual world saves. Remove only our test file.
	var manifest: Dictionary = a["manifest"].duplicate(true)
	manifest["universe_id"] = Identity.child_id(a["universe_id"], "test_fixture", "journal_bridge_v1")
	var journal: LkVoxelEditJournal = LkVoxelEditJournal.new()
	journal.append_sphere(q, 1.5, false)
	journal.append_sphere(q.plus(LkPosition64.new(0.125, 0.25, -0.5)), 2.0, true)
	_check(Store.write_journal(manifest, journal), "write binary journal")
	var loaded: Dictionary = Store.read_journal(manifest)
	_check(loaded["ok"], "read binary journal")
	if loaded["ok"]:
		_check(loaded["found"], "saved journal found")
		var restored: LkVoxelEditJournal = loaded["journal"]
		_check(restored.copy_records() == journal.copy_records(), "exact float64 journal round trip")
	var mismatch: Dictionary = manifest.duplicate(true)
	mismatch["terrain_version"] = 999
	_check(not Store.read_journal(mismatch)["ok"], "reject mismatched terrain manifest")
	var file_path: String = Store.journal_path(manifest)
	if FileAccess.file_exists(file_path):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path)) == OK, "remove isolated test journal")
	print("CatalogBridge: target=%s inverse_error=%.9f m" % [body["id"], worst])
	if _failures == 0:
		print("CatalogBridge: PASS context, frame, carry, gravity, body journal, scene parse")
	quit(0 if _failures == 0 else 1)
