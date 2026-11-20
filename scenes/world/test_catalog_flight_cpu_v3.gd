extends "res://scenes/world/test_catalog_frame_pressure_v2.gd"

const CpuStateCache = preload("res://world/debug/lk_flight_cpu_state_cache.gd")
const CpuPolicy = preload("res://world/debug/lk_flight_cpu_policy.gd")

@export var cpu3_optimizations_enabled: bool = true
@export var cpu3_share_system_states: bool = true
@export var cpu3_navigation_throttle: bool = true
@export var cpu3_navigation_hz: float = 30.0
var _cpu3_cache: CpuStateCache
var _cpu3_far_matches: bool = false
var _cpu3_bound_far: MeshInstance3D
var _cpu3_sections = PacingSamples.new(1200)
var _cpu3_tick_stage: String = "BOOT"
var _cpu3_report_s: float = 0.0
var _cpu3_file: FileAccess
var _cpu3_nav_age_s: float = 0.0
var _cpu3_nav_last_count: int = -1
var _cpu3_nav_last_marks: bool = false
var _cpu3_nav_last_planets: bool = false
var _cpu3_nav_calls: int = 0
var _cpu3_nav_skipped: int = 0

func _ready() -> void:
	var folder: String = "user://flight_cpu_v3"
	if DirAccess.make_dir_recursive_absolute(folder) == OK:
		var path: String = folder.path_join("%d_%d_sections.csv" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
		_cpu3_file = FileAccess.open(path, FileAccess.WRITE)
		if _cpu3_file != null:
			_cpu3_file.store_csv_line(PackedStringArray(["t_s", "phase_at_tick_start", "section", "n", "seen", "mean_ms", "p95_ms", "p99_ms", "max_ms"]))
			_cpu3_file.flush()
			print("FlightCPU3: CSV " + path)
	super._ready()

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or _cpu3_bound_far == _catalog_far_node:
		return
	_cpu3_cache = CpuStateCache.new()
	if not _cpu3_cache.configure(_nav_layout):
		_fail_gate("CPU3 cannot bind system state scope")
		return
	var far_layout: Dictionary = _catalog_far_node.get("_far_layout")
	_cpu3_far_matches = _cpu3_cache.matches(far_layout)
	_cpu3_bound_far = _catalog_far_node
	set("flight_cpu_sections_enabled", true)
	_cpu3_sync_providers()
	print("FlightCPU3: BIND shared=%s far_scope_match=%s navigation_hz=%.1f" % [cpu3_optimizations_enabled and cpu3_share_system_states, _cpu3_far_matches, cpu3_navigation_hz])

func _cpu3_sync_providers() -> void:
	var use_shared: bool = cpu3_optimizations_enabled and cpu3_share_system_states and _cpu3_cache != null
	set("cpu_nav_state_provider", _cpu3_cache if use_shared else null)
	if is_instance_valid(_catalog_far_node):
		_catalog_far_node.set("cpu_state_provider", _cpu3_cache if use_shared and _cpu3_far_matches else null)

func _flight_system_states() -> Dictionary:
	if cpu3_optimizations_enabled and cpu3_share_system_states and _cpu3_cache != null:
		return _cpu3_cache.get_states(_universe_clock.now_s())
	return super._flight_system_states()

func _tick_flight(delta: float) -> void:
	_cpu3_tick_stage = _pacing_stage()
	var started: int = Time.get_ticks_usec()
	super._tick_flight(delta)
	_flight_cpu_section("outer_total", Time.get_ticks_usec() - started)

func _flight_cpu_section(section: String, elapsed_us: int) -> void:
	if elapsed_us > 0:
		_cpu3_sections.add(_cpu3_tick_stage + "|" + section, float(elapsed_us) / 1000.0)

func _update_navigation_tick(delta: float) -> void:
	if not cpu3_optimizations_enabled or not cpu3_navigation_throttle:
		_cpu3_nav_calls += 1
		super._update_navigation_tick(delta + _cpu3_nav_age_s)
		_cpu3_nav_age_s = 0.0
		return
	if not _initialised or _waiting or _failed or not is_instance_valid(_nav_overlay):
		super._update_navigation_tick(delta)
		return
	_cpu3_nav_age_s = minf(1.0, _cpu3_nav_age_s + delta)
	var force: bool = (_nav_place_requested or _cpu3_nav_last_count != _nav_marks.size()
		or _cpu3_nav_last_marks != _nav_show_marks or _cpu3_nav_last_planets != _nav_show_planets)
	if not _nav_show_marks and not _nav_show_planets and not force:
		_cpu3_nav_skipped += 1
		return
	if not CpuPolicy.navigation_due(_cpu3_nav_age_s, cpu3_navigation_hz, force):
		_cpu3_nav_skipped += 1
		return
	_cpu3_nav_calls += 1
	var elapsed: float = _cpu3_nav_age_s
	_cpu3_nav_age_s = 0.0
	super._update_navigation_tick(elapsed)
	_cpu3_nav_last_count = _nav_marks.size()
	_cpu3_nav_last_marks = _nav_show_marks
	_cpu3_nav_last_planets = _nav_show_planets

func _close_local_world() -> void:
	if is_instance_valid(_catalog_far_node):
		_catalog_far_node.set("cpu_state_provider", null)
	set("cpu_nav_state_provider", null)
	_cpu3_bound_far = null
	_cpu3_nav_age_s = 0.0
	_cpu3_nav_last_count = -1
	super._close_local_world()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_I:
		cpu3_optimizations_enabled = not cpu3_optimizations_enabled
		if _cpu3_cache != null:
			_cpu3_cache.invalidate()
		_cpu3_sync_providers()
		_cpu3_sections = PacingSamples.new(1200)
		print("FlightCPU3: optimizations=%s; sections reset, V2 render windows NOT reset" % cpu3_optimizations_enabled)
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _cpu3_report() -> void:
	var stage: String = _cpu3_tick_stage
	var parts: PackedStringArray = []
	for section: String in ["clock_carry", "place_before", "spheres", "movement_guard", "place_after", "lighting", "navigation", "tail", "outer_total"]:
		var value: Dictionary = _cpu3_sections.summary(stage + "|" + section)
		if not value.is_empty():
			parts.append("%s=%.3f/%.3f" % [section, value["mean_ms"], value["p95_ms"]])
	if _flight_active and not parts.is_empty():
		print("FlightCPU3: tick_phase=%s mean/p95_ms %s" % [stage, " ".join(parts)])
	if _cpu3_cache != null:
		print("FlightCPU3: cache builds=%d hits=%d eval_cpu_total_ms=%.3f nav_calls=%d nav_skipped=%d" % [_cpu3_cache.builds, _cpu3_cache.hits, float(_cpu3_cache.evaluate_us) / 1000.0, _cpu3_nav_calls, _cpu3_nav_skipped])
	if _cpu3_file != null:
		for key: String in _cpu3_sections.states():
			var value: Dictionary = _cpu3_sections.summary(key)
			var split: PackedStringArray = key.split("|")
			_cpu3_file.store_csv_line(PackedStringArray(["%.3f" % (float(Time.get_ticks_usec()) / 1000000.0), split[0], split[1], str(value["n"]), str(value["seen"]), "%.4f" % value["mean_ms"], "%.4f" % value["p95_ms"], "%.4f" % value["p99_ms"], "%.4f" % value["max_ms"]]))
		_cpu3_file.flush()

func _process(delta: float) -> void:
	super._process(delta)
	_cpu3_report_s += delta
	if _cpu3_report_s >= 5.0:
		_cpu3_report_s = 0.0
		_cpu3_report()
	if _initialised and _flight_show_telemetry:
		_label.text += "\nFLIGHT CPU3 %s | Alt+I | shared exact epoch | navigation %.0fHz cosmetic" % [cpu3_optimizations_enabled, cpu3_navigation_hz]

func _exit_tree() -> void:
	if _cpu3_file != null:
		_cpu3_report()
		_cpu3_file.flush()
		_cpu3_file.close()
