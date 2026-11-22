class_name LkRenderPressureMonitorV2
extends Node

const Samples = preload("res://game/debug/lk_frame_pacing_samples.gd")
var queues: Dictionary = {"generation": -1, "meshing": -1, "main_thread": -1}
var _root_scene: Node
var _engine: Object
var _rs: Object = RenderingServer
var _viewport: RID
var _render_enabled: bool = false
var _samples = Samples.new(1200)
var _last_us: int = 0
var _previous_phase: String = "BOOT"
var _seconds: float = 0.0
var _queue_seconds: float = 0.0
var _query_index: int = 0
var _slow_rows: Array = []
var _file: FileAccess
var _summary: FileAccess
var _cpu_ms: float = -1.0
var _gpu_ms: float = -1.0
var _setup_ms: float = -1.0
var _probe_ms: float = -1.0
var _task_schema_logged: bool = false

func configure(root_scene: Node, enable_render: bool) -> void:
	_root_scene = root_scene
	process_priority = 1100
	_viewport = root_scene.get_viewport().get_viewport_rid()
	_render_enabled = enable_render and DisplayServer.get_name() != "headless"
	for method: String in ["viewport_set_measure_render_time", "viewport_get_measured_render_time_cpu", "viewport_get_measured_render_time_gpu"]:
		_render_enabled = _render_enabled and _rs.has_method(method)
	if _render_enabled:
		_rs.call("viewport_set_measure_render_time", _viewport, true)
	if Engine.has_singleton("VoxelEngine"):
		_engine = Engine.get_singleton("VoxelEngine")
	var folder: String = "user://frame_pacing_v2"
	if DirAccess.make_dir_recursive_absolute(folder) == OK:
		var run: String = "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		var slow_path: String = folder.path_join(run + "_slow.csv")
		var summary_path: String = folder.path_join(run + "_summary.csv")
		_file = FileAccess.open(slow_path, FileAccess.WRITE)
		_summary = FileAccess.open(summary_path, FileAccess.WRITE)
		if _file != null:
			_file.store_csv_line(PackedStringArray(["t_s", "previous_phase", "current_phase", "wall_ms", "render_cpu_ms", "render_gpu_ms", "render_setup_ms", "process_monitor_ms", "physics_monitor_ms", "last_flight_callback_ms", "render_probe_ms", "generation_queue", "meshing_queue", "main_queue"]))
			_file.flush()
			print("Perf2: SLOW_CSV " + slow_path)
		if _summary != null:
			_summary.store_csv_line(PackedStringArray(["t_s", "phase_label", "metric", "n", "mean_ms", "p95_ms", "p99_ms", "max_ms"]))
			_summary.flush()
			print("Perf2: SUMMARY_CSV " + summary_path)
	_last_us = Time.get_ticks_usec()
	print("Perf2: render_timing=%s; viewport CPU != total CPU; GPU may lag phase; no forced sync" % _render_enabled)
	if _engine != null and _engine.has_method("get_thread_count"):
		print("Perf2: ACTUAL_THREADS=%s logical_cpus=%d" % [str(_engine.call("get_thread_count")), OS.get_processor_count()])

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var dt: float = float(now - _last_us) / 1000000.0
	_last_us = now
	if dt <= 0.0 or not is_instance_valid(_root_scene):
		return
	var phase: String = _root_scene.call("_pacing_stage")
	var wall: float = dt * 1000.0
	_samples.add(_previous_phase + "|wall", wall)
	_query_index += 1
	_seconds += dt
	_queue_seconds += dt
	if _queue_seconds >= 0.5:
		_queue_seconds = 0.0
		_read_queues()
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var callback_ms: float = float(_root_scene.get("_v2_last_flight_tick_ms")) if _root_scene.get("_flight_active") else -1.0
	_samples.add(phase + "|process_monitor", process_ms)
	_samples.add(phase + "|physics_monitor", physics_ms)
	_samples.add(phase + "|flight_callback", callback_ms)
	if _render_enabled and (_query_index % 4 == 0 or wall >= 25.0):
		var started: int = Time.get_ticks_usec()
		_cpu_ms = float(_rs.call("viewport_get_measured_render_time_cpu", _viewport))
		_gpu_ms = float(_rs.call("viewport_get_measured_render_time_gpu", _viewport))
		_setup_ms = float(_rs.call("get_frame_setup_time_cpu")) if _rs.has_method("get_frame_setup_time_cpu") else -1.0
		_probe_ms = float(Time.get_ticks_usec() - started) / 1000.0
		_samples.add(phase + "|render_cpu", _cpu_ms)
		_samples.add(phase + "|render_gpu", _gpu_ms)
		_samples.add(phase + "|render_setup", _setup_ms)
		_samples.add(phase + "|render_probe", _probe_ms)
	if wall >= 25.0 and _slow_rows.size() < 256:
		_slow_rows.append(PackedStringArray(["%.3f" % (float(now) / 1000000.0), _previous_phase, phase, "%.3f" % wall, _text(_cpu_ms), _text(_gpu_ms), _text(_setup_ms), _text(process_ms), _text(physics_ms), _text(callback_ms), _text(_probe_ms), str(queues["generation"]), str(queues["meshing"]), str(queues["main_thread"])]))
	_previous_phase = phase
	if _seconds >= 5.0:
		_seconds = 0.0
		_report(phase)

func _read_queues() -> void:
	if _engine == null or not _engine.has_method("get_stats"):
		return
	var raw: Variant = _engine.call("get_stats")
	if not raw is Dictionary:
		return
	var tasks: Variant = raw.get("tasks", {})
	if not tasks is Dictionary:
		return
	if not _task_schema_logged:
		_task_schema_logged = true
		print("Perf2: TASK_KEYS " + str(tasks.keys()))
	for key: String in queues:
		queues[key] = int(tasks.get(key, -1))

func _text(value: float) -> String:
	return "%.3f" % value if is_finite(value) and value > 0.0 else "NA"

func _mean(phase: String, metric: String) -> String:
	var result: Dictionary = _samples.summary(phase + "|" + metric)
	return _text(result["mean_ms"]) if not result.is_empty() else "NA"

func _report(phase: String) -> void:
	for key: String in _samples.states():
		var value: Dictionary = _samples.summary(key)
		if _summary != null and not value.is_empty():
			var parts: PackedStringArray = key.split("|")
			_summary.store_csv_line(PackedStringArray(["%.3f" % (float(Time.get_ticks_usec()) / 1000000.0), parts[0], parts[1], str(value["n"]), _text(value["mean_ms"]), _text(value["p95_ms"]), _text(value["p99_ms"]), _text(value["max_ms"])]))
	if _file != null:
		for row: PackedStringArray in _slow_rows:
			_file.store_csv_line(row)
		_file.flush()
	_slow_rows.clear()
	if _summary != null:
		_summary.flush()
	print("Perf2: phase=%s mean_ms wall=%s render_cpu=%s gpu=%s setup=%s process=%s physics=%s flight_cb=%s probe=%s queues=%s" % [phase, _mean(phase, "wall"), _mean(phase, "render_cpu"), _mean(phase, "render_gpu"), _mean(phase, "render_setup"), _mean(phase, "process_monitor"), _mean(phase, "physics_monitor"), _mean(phase, "flight_callback"), _mean(phase, "render_probe"), str(queues)])
	print("Perf2: POSE applied=%s skipped=%s" % [str(_root_scene.get("_v2_pose_applied")), str(_root_scene.get("_v2_pose_skipped"))])

func _exit_tree() -> void:
	if _file != null:
		for row: PackedStringArray in _slow_rows:
			_file.store_csv_line(row)
		_file.flush()
		_file.close()
	if _summary != null:
		_summary.flush()
		_summary.close()
