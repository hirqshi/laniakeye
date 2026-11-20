extends "res://scenes/world/test_catalog_surface_boundary_fix.gd"

const PacingMonitor = preload("res://world/debug/lk_frame_pacing_monitor.gd")
const PacingSamples = preload("res://world/debug/lk_frame_pacing_samples.gd")

@export var frame_pacing_enabled: bool = true
@export var pacing_target_fps: float = 60.0
@export var pacing_growth_interval_s: float = 0.75
@export var pacing_warm_check_interval_s: float = 0.2
var _pacing_monitor: PacingMonitor
var _pacing_warm_accum_s: float = 0.0
var _pacing_retire_until_us: int = 0
var _pacing_growth_active: bool = false
var _pacing_growth_terrain: VoxelLodTerrain
var _pacing_growth_s: float = 0.0
var _pacing_growth_log_s: float = 0.0
var _pacing_last_stage: String = "BOOT"

func _ready() -> void:
	_pacing_monitor = PacingMonitor.new()
	_pacing_monitor.name = "FramePacingMonitor"
	_pacing_monitor.configure(self)
	add_child(_pacing_monitor)
	super._ready()

func _pacing_event(kind: String, detail: String) -> void:
	if is_instance_valid(_pacing_monitor):
		_pacing_monitor.event(kind, detail)

func _pacing_stage() -> String:
	if not _initialised or _waiting:
		return "BOOT"
	if Time.get_ticks_usec() < _pacing_retire_until_us:
		return "RETIRE_WINDOW"
	if _auto_busy:
		if _auto_aligning:
			return "ALIGN"
		return "READY_HOLD" if _auto_warm else "PREFETCH_BUILD"
	if _pacing_growth_active:
		return "EXPAND"
	if is_instance_valid(_pending):
		return "WALK_REANCHOR" if not _flight_active else "MANUAL_BUILD"
	return "FLIGHT" if _flight_active else "WALK"

func _prefetch_should_start(height: float, closing: float) -> bool:
	if frame_pacing_enabled and Time.get_ticks_usec() < _pacing_retire_until_us:
		return false
	return super._prefetch_should_start(height, closing)

func _prefetch_promoted_view_distance() -> int:
	if frame_pacing_enabled and is_instance_valid(_terrain):
		return clampi(_terrain.view_distance, 64, 128)
	return 192

func _start_auto_surface(target: LkPosition64, height: float, closing: float) -> void:
	_pacing_growth_active = false
	_pacing_growth_terrain = null
	_pacing_warm_accum_s = 0.0
	_pacing_event("PREPARE", "height_m=%.3f" % height)
	super._start_auto_surface(target, height, closing)

func _poll_auto_surface(delta: float) -> void:
	_pacing_warm_accum_s += delta
	if frame_pacing_enabled and _auto_busy and _auto_warm and not _auto_aligning:
		if _edit_journal.get_revision() != _landing_revision:
			_cancel_landing_patch("journal revision changed during warm hold")
			_pacing_warm_accum_s = 0.0
			return
		if _pacing_warm_accum_s < clampf(pacing_warm_check_interval_s, 0.05, 0.5):
			return
	var elapsed: float = _pacing_warm_accum_s
	_pacing_warm_accum_s = 0.0
	# Delta accumulation preserves elapsed/recovery timers. ALIGN is never throttled.
	super._poll_auto_surface(elapsed)

func _promote_landing_patch() -> void:
	var previous: VoxelLodTerrain = _terrain
	var was_auto: bool = _auto_busy
	var started: int = Time.get_ticks_usec()
	super._promote_landing_patch()
	if is_instance_valid(_terrain) and _terrain != previous:
		_pacing_retire_until_us = Time.get_ticks_usec() + 1000000
		_pacing_event("COMMIT", "cpu_ms=%.3f auto=%s" % [float(Time.get_ticks_usec() - started) / 1000.0, was_auto])
		if frame_pacing_enabled and was_auto:
			_pacing_growth_active = true
			_pacing_growth_terrain = _terrain
			_pacing_growth_s = 0.0
			_pacing_growth_log_s = 0.0
			_set_pacing_view(_terrain.view_distance)

func _set_pacing_view(distance: int) -> void:
	if not is_instance_valid(_pacing_growth_terrain):
		return
	_pacing_growth_terrain.view_distance = distance
	if is_instance_valid(_auto_viewer):
		_auto_viewer.view_distance = distance
	if is_instance_valid(_flight_viewer):
		_flight_viewer.view_distance = distance

func _update_pacing_growth(delta: float) -> void:
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
	if _pacing_growth_s < maxf(0.25, pacing_growth_interval_s) or Time.get_ticks_usec() < _pacing_retire_until_us:
		return
	var baseline: float = _pacing_monitor.baseline_ms if _pacing_monitor.baseline_samples >= 30 else 0.0
	var target_ms: float = 1000.0 / maxf(10.0, pacing_target_fps)
	var allow: bool = PacingSamples.allow_growth(_pacing_monitor.average_ms, baseline, target_ms, _pacing_monitor.main_queue)
	if not allow:
		if _pacing_growth_log_s >= 2.0:
			_pacing_growth_log_s = 0.0
			_pacing_event("GROW_HOLD", "view=%d avg_ms=%.3f baseline_ms=%.3f main_queue=%d" % [_terrain.view_distance, _pacing_monitor.average_ms, baseline, _pacing_monitor.main_queue])
		return
	var current: int = _terrain.view_distance
	var next_distance: int = 192
	for step: int in [112, 144, 192]:
		if step > current:
			next_distance = step
			break
	_set_pacing_view(next_distance)
	_pacing_growth_s = 0.0
	_pacing_event("GROW", "%d->%d" % [current, next_distance])
	print("FramePacing: GROW %d -> %d" % [current, next_distance])
	if next_distance >= 192:
		_pacing_growth_active = false

func _cancel_landing_patch(reason: String) -> void:
	var was_auto: bool = _auto_busy
	var started: int = Time.get_ticks_usec()
	super._cancel_landing_patch(reason)
	_pacing_warm_accum_s = 0.0
	if was_auto:
		_pacing_retire_until_us = Time.get_ticks_usec() + 1000000
		_pacing_event("CANCEL", "cpu_ms=%.3f %s" % [float(Time.get_ticks_usec() - started) / 1000.0, reason])

func _close_local_world() -> void:
	_pacing_growth_active = false
	_pacing_growth_terrain = null
	_pacing_warm_accum_s = 0.0
	super._close_local_world()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_J:
		frame_pacing_enabled = not frame_pacing_enabled
		_pacing_event("SCENE_GOVERNOR", str(frame_pacing_enabled))
		print("FramePacing: scene governor=%s; startup voxel settings unchanged" % frame_pacing_enabled)
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _process(delta: float) -> void:
	super._process(delta)
	_update_pacing_growth(delta)
	var state: String = _pacing_stage()
	if state != _pacing_last_stage:
		_pacing_event("STATE", _pacing_last_stage + "->" + state)
		_pacing_last_stage = state
	if _initialised and _flight_show_telemetry and is_instance_valid(_pacing_monitor):
		_label.text += "\nFRAME PACING %s | Alt+J | %s | avg %.2f ms | main queue %d" % [frame_pacing_enabled, state, _pacing_monitor.average_ms, _pacing_monitor.main_queue]
		if _pacing_growth_active:
			_label.text += "\nTerrain growth %d ->192 m; waits for frame/queue headroom" % _terrain.view_distance

func _commit_patch() -> void:
	var previous: VoxelLodTerrain = _terrain
	var started: int = Time.get_ticks_usec()
	super._commit_patch()
	if is_instance_valid(_terrain) and _terrain != previous:
		_pacing_retire_until_us = Time.get_ticks_usec() + 1000000
		_pacing_event("WALK_COMMIT", "cpu_ms=%.3f" % (float(Time.get_ticks_usec() - started) / 1000.0))
