extends SceneTree

const ReferenceMath = preload("res://game/debug/lk_debug_flight_math.gd")
const PackedMath = preload("res://game/debug/lk_debug_flight_math_packed.gd")
const ReferencePool = preload("res://game/debug/lk_flight_sphere_pool.gd")
const PackedPool = preload("res://game/debug/lk_flight_sphere_pool_packed.gd")

func _initialize() -> void:
	var star: Dictionary = {"id": "star", "radius_m": 1000000.0}
	var planet: Dictionary = {"id": "planet", "radius_m": 1000.0}
	var moon: Dictionary = {"id": "moon", "radius_m": 100.0}
	var layout: Dictionary = {"layout_version": 1, "system_id": "cpu6-bench", "star": star, "planets": [{"body": planet, "moons": [{"body": moon}]}]}
	var states: Dictionary = {"system_id": "cpu6-bench", "time_s": 12.25, "bodies": [
		{"id": "star", "position_m": [0.0, 0.0, 0.0]},
		{"id": "planet", "position_m": [1.0e12 + 0.125, -3.75, 2.5]},
		{"id": "moon", "position_m": [1.0e12 + 10000000.125, -3.75, 2.5]}]}
	var reference_pool = ReferencePool.new()
	var packed_pool = PackedPool.new()
	if not reference_pool.configure(layout, "planet") or not packed_pool.configure(layout, "planet"):
		quit(1)
		return
	var observer: LkPosition64 = LkPosition64.new(1002.0, 3.5, -2.0)
	var rows: Array = reference_pool.build(states, observer, 12.25, true)
	packed_pool.build_packed(states, observer, 12.25, true)
	for index: int in range(10):
		ReferenceMath.safe_step(Vector3(0.0, 0.0, -1.0), 100.0, rows)
		PackedMath.safe_step_packed(Vector3(0.0, 0.0, -1.0), 100.0, packed_pool.centers, packed_pool.radii)
	var reference_us: int = 0
	var packed_us: int = 0
	var iterations: int = 20000
	for index: int in range(iterations):
		var direction: Vector3 = Vector3(0.0, 0.0, -1.0)
		var started: int = Time.get_ticks_usec()
		ReferenceMath.safe_step(direction, 100.0, rows)
		reference_us += Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		PackedMath.safe_step_packed(direction, 100.0, packed_pool.centers, packed_pool.radii)
		packed_us += Time.get_ticks_usec() - started
	print("FlightCPU6Bench: reference_us=%d packed_us=%d iterations=%d mean_ns/ref=%.1f packed=%.1f" % [reference_us, packed_us, iterations, float(reference_us) * 1000.0 / float(iterations), float(packed_us) * 1000.0 / float(iterations)])
	print("FlightCPU6Bench: synthetic 3-sphere microbenchmark only; not whole-game route")
	quit(0)
