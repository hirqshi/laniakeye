extends SceneTree

const Snapshot = preload("res://game/world/rendering/lk_far_body_snapshot.gd")
const Layout = preload("res://game/world/generation/lk_safe_orbit_layout.gd")
const Bodies = preload("res://game/world/generation/lk_body_catalog.gd")
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FarSnapshotCache: FAIL " + label)


func _verify(layout: Dictionary, active: String, observer: LkPosition64, epoch: float) -> Array[Dictionary]:
	var states: Dictionary = Layout.evaluate(layout, epoch)
	var before: PackedByteArray = var_to_bytes(states)
	var expected: Array[Dictionary] = Snapshot.build(layout, active, observer, epoch, states)
	var actual: Array[Dictionary] = Snapshot.build(layout, active, observer, epoch)
	_check(var_to_bytes(actual) == var_to_bytes(expected), "byte-exact provider parity")
	_check(var_to_bytes(states) == before, "provided states unchanged")
	return actual


func _initialize() -> void:
	var definition = Definition.new()
	var catalog = Catalog.new(definition.get_universe_id(), 1)
	var layout: Dictionary = Layout.build(Bodies.build(catalog.describe_system(0, 0, 0, 0, 0)))
	_check(not layout.is_empty() and not layout["planets"].is_empty(), "planet fixture")
	if layout.is_empty() or layout["planets"].is_empty():
		quit(1)
		return
	var active: String = layout["planets"][0]["body"]["id"]
	var radius: float = layout["planets"][0]["body"]["radius_m"]
	var observer: LkPosition64 = LkPosition64.new(radius + 1000.0, 2.5, -3.75)
	var epoch: float = 123.25
	Snapshot.clear_fallback_cache()
	var baseline: Array[Dictionary] = _verify(layout, active, observer, epoch)
	_check(not baseline.is_empty(), "nonempty snapshot")
	_check(Snapshot.fallback_cache_stats() == {"resident": 1, "evaluations": 1, "hits": 0}, "cold evaluation")
	_verify(layout.duplicate(true), active, observer, epoch)
	_check(Snapshot.fallback_cache_stats()["evaluations"] == 1 and Snapshot.fallback_cache_stats()["hits"] == 1, "equal layout hits")
	_verify(layout, active, LkPosition64.new(radius + 2000.0, -4.5, 9.0), epoch)
	_verify(layout, layout["star"]["id"], observer, epoch)
	_check(Snapshot.fallback_cache_stats()["evaluations"] == 1, "observer and active body reuse states")
	var exported: Array[Dictionary] = Snapshot.build(layout, active, observer, epoch)
	if not exported.is_empty():
		exported[0]["center_m"][0] = -999.0
		exported[0]["sun_direction"][0] = -999.0
		exported.clear()
	_check(var_to_bytes(Snapshot.build(layout, active, observer, epoch)) == var_to_bytes(baseline), "export isolation")
	_verify(layout, active, observer, epoch + 0.000001)
	_check(Snapshot.fallback_cache_stats()["evaluations"] == 2, "no time quantization")
	_verify(layout, active, observer, epoch)
	_check(Snapshot.fallback_cache_stats()["evaluations"] == 3, "single entry replaces old epoch")
	var changed: Dictionary = layout.duplicate(true)
	changed["epoch_s"] = 10.0
	_verify(changed, active, observer, epoch)
	_check(Snapshot.fallback_cache_stats()["evaluations"] == 4, "same system changed layout misses")
	changed["epoch_s"] = 20.0
	_verify(changed, active, observer, epoch)
	_check(Snapshot.fallback_cache_stats()["evaluations"] == 5, "cached layout detached")
	var other: Dictionary = layout.duplicate(true)
	other["system_id"] = "other-cache-test-system"
	_verify(other, active, observer, epoch)
	_check(Snapshot.fallback_cache_stats()["evaluations"] == 6 and Snapshot.fallback_cache_stats()["resident"] == 1, "system separation and bound")
	var stats: Dictionary = Snapshot.fallback_cache_stats()
	var provided: Dictionary = Layout.evaluate(layout, epoch + 50.0)
	Snapshot.build(layout, active, observer, epoch + 50.0, provided)
	_check(Snapshot.fallback_cache_stats() == stats, "provider bypasses fallback cache")
	Snapshot.clear_fallback_cache()
	_check(Snapshot.fallback_cache_stats() == {"resident": 0, "evaluations": 0, "hits": 0}, "clear")
	if _failures == 0:
		print("FarSnapshotCache: PASS exact epoch, layout scope, provider parity, observer/active changes, isolation, single-entry bound")
	quit(0 if _failures == 0 else 1)
