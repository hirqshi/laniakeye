extends SceneTree

const Reference = preload("res://world/generation/lk_safe_orbit_layout.gd")
const Compiled = preload("res://world/debug/lk_compiled_orbit_layout.gd")
const Fixture = preload("res://tests/world/flight_cpu5_fixture.gd")

func _summary(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in values:
		total += value
	return {"n": values.size(), "mean_ms": total / float(values.size()), "p95_ms": sorted[int(ceil(0.95 * float(sorted.size()))) - 1]}

func _initialize() -> void:
	var layout: Dictionary = Fixture.make_layout()
	var compiled = Compiled.new()
	if not compiled.configure(layout):
		quit(1)
		return
	for index: int in range(10):
		Reference.evaluate(layout, 12420.0 + float(index) / 60.0)
		compiled.evaluate(12420.0 + float(index) / 60.0)
	var baseline: Array[float] = []
	var optimized: Array[float] = []
	var rows: Array = []
	for index: int in range(80):
		var epoch: float = 12421.0 + float(index) / 60.0
		# Alternate order, no cache hits, fine timers off in both cases.
		for pass_index: int in range(2):
			var use_compiled: bool = (index + pass_index) % 2 == 0
			var started: int = Time.get_ticks_usec()
			var value: Dictionary = compiled.evaluate(epoch) if use_compiled else Reference.evaluate(layout, epoch)
			var elapsed: float = float(Time.get_ticks_usec() - started) / 1000.0
			if value.is_empty():
				quit(1)
				return
			if use_compiled:
				optimized.append(elapsed)
			else:
				baseline.append(elapsed)
			rows.append([index, "compiled" if use_compiled else "reference", elapsed])
	var folder: String = "user://flight_cpu_v5"
	if DirAccess.make_dir_recursive_absolute(folder) == OK:
		var path: String = folder.path_join("%d_benchmark.csv" % Time.get_ticks_usec())
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_csv_line(PackedStringArray(["sample", "mode", "elapsed_ms"]))
			for row: Array in rows:
				file.store_csv_line(PackedStringArray([str(row[0]), str(row[1]), str(row[2])]))
			file.close()
			print("FlightCPU5Bench: CSV " + path)
	print("FlightCPU5Bench: reference=%s compiled=%s" % [_summary(baseline), _summary(optimized)])
	print("FlightCPU5Bench: numeric 264-body microbenchmark only; not whole-game FPS or real-system route")
	quit(0)
