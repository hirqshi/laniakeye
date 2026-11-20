class_name LkFramePacingMonitor
extends Node

const Samples = preload("res://world/debug/lk_frame_pacing_samples.gd")
var latest_ms: float = 16.667
var average_ms: float = 16.667
var baseline_ms: float = 16.667
var baseline_samples: int = 0
var main_queue: int = -1
var _owner_scene: Node
var _voxel_engine: Object
var _samples = Samples.new(1200)
var _last_us: int = 0
var _report_s: float = 0.0
var _queues_s: float = 0.0
var _generation: int = -1
var _meshing: int = -1
var _gpu_tasks: int = -1
var _frames: FileAccess
var _events: FileAccess

func configure(scene: Node) -> void:
	_owner_scene = scene
	process_priority = 1000
	if Engine.has_singleton("VoxelEngine"):
		_voxel_engine = Engine.get_singleton("VoxelEngine")
	var folder: String = "user://frame_pacing_v1"
	if DirAccess.make_dir_recursive_absolute(folder) == OK:
		var run: String = "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		var frame_path: String = folder.path_join(run + "_frames.csv")
		var event_path: String = folder.path_join(run + "_events.csv")
		_frames = FileAccess.open(frame_path, FileAccess.WRITE)
		_events = FileAccess.open(event_path, FileAccess.WRITE)
		if _frames != null:
			_frames.store_csv_line(PackedStringArray(["uptime_s", "state", "window_samples", "seen", "mean_ms", "p95_ms", "p99_ms", "max_ms", "queue_snapshot_at_report", "generation_tasks", "meshing_tasks", "main_tasks", "gpu_tasks"]))
			_frames.flush()
			print("FramePacing: FRAMES " + frame_path)
		if _events != null:
			_events.store_csv_line(PackedStringArray(["uptime_s", "event", "detail"]))
			_events.flush()
			print("FramePacing: EVENTS " + event_path)
	_last_us = Time.get_ticks_usec()
	print("FramePacing: wall-clock render-loop intervals, rolling1200/state; not GPU timestamps")
	for key: String in ["voxel/threads/main/time_budget_ms", "voxel/threads/count/minimum", "voxel/threads/count/margin_below_maximum", "voxel/threads/count/ratio_over_maximum"]:
		print("FramePacing: SETTING %s=%s" % [key, str(ProjectSettings.get_setting(key)) if ProjectSettings.has_setting(key) else "UNSUPPORTED"])
	if _voxel_engine != null:
		for method: String in ["get_thread_count", "get_threaded_graphics_resource_building_enabled", "get_version_git_hash"]:
			if _voxel_engine.has_method(method):
				print("FramePacing: ENGINE %s=%s" % [method, str(_voxel_engine.call(method))])

func event(kind: String, detail: String) -> void:
	if _events != null:
		_events.store_csv_line(PackedStringArray(["%.3f" % (float(Time.get_ticks_usec()) / 1000000.0), kind, detail]))

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var seconds: float = float(now - _last_us) / 1000000.0
	_last_us = now
	if seconds <= 0.0 or not is_instance_valid(_owner_scene):
		return
	latest_ms = seconds * 1000.0
	average_ms = lerpf(average_ms, latest_ms, 0.08)
	var state: String = _owner_scene.call("_pacing_stage")
	_samples.add(state, latest_ms)
	if state in ["FLIGHT", "WALK"] or (state == "EXPAND" and main_queue <= 0 and _generation <= 0 and _meshing <= 0):
		baseline_ms = lerpf(baseline_ms, latest_ms, 0.03)
		baseline_samples += 1
	_queues_s += seconds
	_report_s += seconds
	if _queues_s >= 1.0:
		_queues_s = 0.0
		_read_queues()
	if _report_s >= 5.0:
		_report_s = 0.0
		_report(state)

func _read_queues() -> void:
	if _voxel_engine == null or not _voxel_engine.has_method("get_stats"):
		return
	var raw: Variant = _voxel_engine.call("get_stats")
	if not raw is Dictionary:
		return
	var tasks: Variant = raw.get("tasks", {})
	if tasks is Dictionary:
		_generation = int(tasks.get("generation", -1))
		_meshing = int(tasks.get("meshing", -1))
		main_queue = int(tasks.get("main_thread", -1))
		_gpu_tasks = int(tasks.get("gpu", -1))

func _report(current_state: String) -> void:
	for state: String in _samples.states():
		var value: Dictionary = _samples.summary(state)
		if _frames != null and not value.is_empty():
			_frames.store_csv_line(PackedStringArray(["%.3f" % (float(Time.get_ticks_usec()) / 1000000.0), state, str(value["n"]), str(value["seen"]), "%.3f" % value["mean_ms"], "%.3f" % value["p95_ms"], "%.3f" % value["p99_ms"], "%.3f" % value["max_ms"], current_state, str(_generation), str(_meshing), str(main_queue), str(_gpu_tasks)]))
	if _frames != null:
		_frames.flush()
	if _events != null:
		_events.flush()
	var report: Dictionary = _samples.summary(current_state)
	if not report.is_empty():
		print("FramePacing: state=%s n=%d mean=%.2f p95=%.2f p99=%.2f max=%.2f ms queues(gen/mesh/main)=%d/%d/%d" % [current_state, report["n"], report["mean_ms"], report["p95_ms"], report["p99_ms"], report["max_ms"], _generation, _meshing, main_queue])

func _exit_tree() -> void:
	if _frames != null:
		_frames.flush()
		_frames.close()
	if _events != null:
		_events.flush()
		_events.close()
