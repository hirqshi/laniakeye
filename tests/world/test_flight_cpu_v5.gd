extends SceneTree

const Reference = preload("res://world/generation/lk_safe_orbit_layout.gd")
const Compiled = preload("res://world/debug/lk_compiled_orbit_layout.gd")
const Cache = preload("res://world/debug/lk_flight_cpu_compiled_cache.gd")
const Fixture = preload("res://tests/world/flight_cpu5_fixture.gd")
const SceneScript = preload("res://scenes/world/test_catalog_flight_cpu_v5.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FlightCPU5: FAIL " + label)

func _initialize() -> void:
	var layout: Dictionary = Fixture.make_layout()
	var input_bytes: PackedByteArray = var_to_bytes(layout)
	var compiled = Compiled.new()
	_check(compiled.configure(layout), "compile numeric fixture")
	var comparisons: int = 0
	for epoch: float in [-1.0e12, -1234.5, 0.0, 12.25, 1234.5, 12420.783333, 12466.35, 1.0e12]:
		var golden: Dictionary = Reference.evaluate(layout, epoch)
		var candidate: Dictionary = compiled.evaluate(epoch)
		_check(golden["bodies"].size() == 264, "fixture body count")
		_check(var_to_bytes(golden) == var_to_bytes(candidate), "byte-exact entire state at %s" % epoch)
		comparisons += golden["bodies"].size()
	_check(var_to_bytes(layout) == input_bytes, "input layout unchanged")
	var old: Dictionary = compiled.evaluate(100.0)
	var saved: PackedByteArray = var_to_bytes(old)
	compiled.evaluate(101.0)
	_check(var_to_bytes(old) == saved, "new evaluation does not overwrite retained snapshot")
	# Direct evaluator returns independent snapshots, including constant spin axes.
	old["bodies"][1]["body_to_system_axes"][1][0] = 999.0
	old["bodies"][1]["angular_velocity_rad_s"][0] = 999.0
	_check(var_to_bytes(compiled.evaluate(100.0)) == var_to_bytes(Reference.evaluate(layout, 100.0)), "returned arrays do not alias baked constants")
	var cache = Cache.new()
	_check(cache.configure(layout) and cache.matches(layout), "cache signature matches")
	var first: Dictionary = cache.get_states(12.25)
	_check(var_to_bytes(first) == var_to_bytes(cache.get_states(12.25)) and cache.builds == 1 and cache.hits == 1, "exact epoch hit")
	cache.get_states(12.2500001)
	_check(cache.builds == 2, "no epoch quantization")
	cache.set_compiled_enabled(false)
	_check(var_to_bytes(cache.get_states(12.25)) == var_to_bytes(Reference.evaluate(layout, 12.25)), "original evaluator A/B path")
	cache.set_compiled_enabled(true)
	_check(var_to_bytes(cache.get_states(12.25)) == var_to_bytes(Reference.evaluate(layout, 12.25)), "toggle invalidates cached result")
	_check(cache.get_states(NAN).is_empty(), "nonfinite epoch refused")
	compiled.set_profile_enabled(true)
	compiled.evaluate(12420.0)
	_check(compiled.profile_summary()["profiled_evaluations"] == 1, "profile excludes earlier untimed epochs")
	var frozen: Dictionary = layout.duplicate(true)
	layout["planets"][0]["orbit"]["semi_major_axis_m"] *= 2.0
	cache.invalidate()
	_check(var_to_bytes(cache.get_states(12.25)) == var_to_bytes(Reference.evaluate(frozen, 12.25)), "cache binds immutable copied layout")
	_check(not cache.matches(layout), "changed layout signature rejected")
	_check(not cache.configure({}) and cache.get_states(12.25).is_empty(), "failed reconfigure clears prior scope")
	if _failures == 0:
		print("FlightCPU5: PASS byte-exact body states=%d, negative/large epochs, e=0..0.8, retrograde spin, snapshot isolation, cache/A-B/scope, scene parse" % comparisons)
	quit(0 if _failures == 0 else 1)
