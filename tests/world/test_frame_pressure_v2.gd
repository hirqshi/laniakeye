extends SceneTree

const Schema = preload("res://world/debug/lk_voxel_thread_schema_v2.gd")
const SceneScript = preload("res://scenes/world/test_catalog_frame_pressure_v2.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("Pressure2: FAIL " + label)

func _initialize() -> void:
	# Synthetic schemas, NOT claims about installed module key names.
	var fields: Array = ["voxel/threads/count/minimum", "voxel/threads/count/margin_below_max", "voxel/threads/count/ratio_over_max"]
	var resolved: Dictionary = Schema.resolve(fields)
	_check(resolved["can_cap"] and resolved["margin"] == fields[1] and resolved["ratio"] == fields[2], "resolve actually supplied names")
	var unknown: Dictionary = Schema.resolve(["voxel/threads/count/minimum"])
	_check(not unknown["can_cap"] and unknown["ratio"] == "", "no invented missing cap")
	var ambiguous: Dictionary = Schema.resolve(["voxel/threads/count/ratio_over_max", "voxel/threads/count/second_ratio_over_max"])
	_check(not ambiguous["can_cap"] and ambiguous["ratio"] == "", "ambiguous schema refused")
	_check(Schema.queue_headroom(0, 16, 0), "small queue")
	_check(not Schema.queue_headroom(0, 17, 0) and not Schema.queue_headroom(17, 0, 0), "all worker queues gate growth")
	_check(Schema.queue_headroom(-1, -1, -1), "unsupported queues fall back to frame gate")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_frame_pressure_v2.gd")
	_check(source.contains("patch == _pending and not _auto_aligning") and source.contains("_set_prefetch_sandbox_transform()"), "sandbox bypasses world pose")
	_check(source.contains("patch.global_transform == wanted") and source.contains("_pending.global_transform == Transform3D.IDENTITY"), "unchanged poses skipped")
	_check(source.contains("64 if pacing2_optimizations_enabled else 80"), "smaller initial request with baseline")
	var base: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_auto_surface.gd")
	_check(base.contains("PACING_SANDBOX_HOOK_V2"), "hook installed")
	var monitor: String = FileAccess.get_file_as_string("res://world/debug/lk_render_pressure_monitor_v2.gd")
	_check(monitor.contains("viewport_get_measured_render_time_cpu") and monitor.contains("viewport_get_measured_render_time_gpu"), "viewport timing methods gated")
	_check(not monitor.contains('call("force_sync"') and not monitor.contains('call("force_draw"'), "no explicit rendering synchronization")
	if _failures == 0:
		print("Pressure2: PASS schema resolution, ambiguity guards, queue gates, pose contracts, initial request, timing contracts, scene parse")
	print("Pressure2: CPU/GPU backend results, pool cap and frame-time improvement need actual game run")
	quit(0 if _failures == 0 else 1)
