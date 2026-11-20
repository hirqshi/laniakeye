extends "res://scenes/world/test_catalog_frame_pacing.gd"

const PressureMonitor = preload("res://world/debug/lk_render_pressure_monitor_v2.gd")
const ThreadSchema = preload("res://world/debug/lk_voxel_thread_schema_v2.gd")

@export var pacing2_optimizations_enabled: bool = true
@export var pacing2_measure_render_times: bool = true
var _pressure_monitor: PressureMonitor
var _v2_pose_applied: int = 0
var _v2_pose_skipped: int = 0
var _v2_last_flight_tick_ms: float = -1.0

func _ready() -> void:
	_pressure_monitor = PressureMonitor.new()
	_pressure_monitor.name = "RenderPressureMonitorV2"
	_pressure_monitor.configure(self, pacing2_measure_render_times)
	add_child(_pressure_monitor)
	super._ready()

func _set_patch_transform(patch: VoxelLodTerrain, anchor: LkPosition64) -> void:
	if not pacing2_optimizations_enabled:
		super._set_patch_transform(patch, anchor)
		return
	if _auto_busy and patch == _pending and not _auto_aligning:
		_set_prefetch_sandbox_transform()
		return
	var wanted: Transform3D = Transform3D(_catalog_frame.planet_basis(), _fixed_to_local(anchor))
	if patch.global_transform == wanted:
		_v2_pose_skipped += 1
		return
	patch.global_transform = wanted
	patch.force_update_transform()
	_v2_pose_applied += 1

func _set_prefetch_sandbox_transform() -> void:
	if not pacing2_optimizations_enabled:
		super._set_prefetch_sandbox_transform()
		return
	if not is_instance_valid(_pending):
		return
	if _pending.global_transform == Transform3D.IDENTITY:
		_v2_pose_skipped += 1
		return
	_pending.global_transform = Transform3D.IDENTITY
	_pending.force_update_transform()
	_v2_pose_applied += 1

func _start_auto_surface(target: LkPosition64, height: float, closing: float) -> void:
	approach_initial_view_m = 64 if pacing2_optimizations_enabled else 80
	super._start_auto_surface(target, height, closing)
	print("Pressure2: PREPARE initial_view=%d pose_cache=%s" % [approach_initial_view_m, pacing2_optimizations_enabled])

func _tick_flight(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	super._tick_flight(delta)
	_v2_last_flight_tick_ms = float(Time.get_ticks_usec() - started) / 1000.0

func _update_pacing_growth(delta: float) -> void:
	if not pacing2_optimizations_enabled:
		super._update_pacing_growth(delta)
		return
	if not _pacing_growth_active:
		return
	if not is_instance_valid(_pacing_growth_terrain) or _pacing_growth_terrain != _terrain:
		_pacing_growth_active = false
		return
	if not frame_pacing_enabled:
		_set_pacing_view(192)
		_pacing_growth_active = false
		return
	_pacing_growth_s += delta
	_pacing_growth_log_s += delta
	if _pacing_growth_s < maxf(0.75, pacing_growth_interval_s) or Time.get_ticks_usec() < _pacing_retire_until_us:
		return
	var baseline: float = _pacing_monitor.baseline_ms if _pacing_monitor.baseline_samples >= 30 else 0.0
	var queues: Dictionary = _pressure_monitor.queues
	var queue_ok: bool = ThreadSchema.queue_headroom(queues["generation"], queues["meshing"], queues["main_thread"])
	var frame_ok: bool = PacingSamples.allow_growth(_pacing_monitor.average_ms, baseline, 1000.0 / maxf(10.0, pacing_target_fps), queues["main_thread"])
	if not queue_ok or not frame_ok:
		if _pacing_growth_log_s >= 2.0:
			_pacing_growth_log_s = 0.0
			_pacing_event("PRESSURE2_HOLD", "view=%d avg_ms=%.3f queues=%s" % [_terrain.view_distance, _pacing_monitor.average_ms, str(queues)])
		return
	var previous: int = _terrain.view_distance
	var next_distance: int = 192
	for candidate: int in [80, 96, 128, 160, 192]:
		if candidate > previous:
			next_distance = candidate
			break
	_set_pacing_view(next_distance)
	_pacing_growth_s = 0.0
	_pacing_event("PRESSURE2_GROW", "%d->%d" % [previous, next_distance])
	print("Pressure2: GROW %d -> %d" % [previous, next_distance])
	if next_distance >= 192:
		_pacing_growth_active = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_K:
		pacing2_optimizations_enabled = not pacing2_optimizations_enabled
		print("Pressure2: optimizations=%s; startup worker profile unchanged" % pacing2_optimizations_enabled)
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nPRESSURE V2 %s | Alt+K | initial %dm | CPU/GPU diagnostics | poses %d/%d applied/skipped" % [pacing2_optimizations_enabled, approach_initial_view_m, _v2_pose_applied, _v2_pose_skipped]
