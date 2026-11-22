extends "res://scenes/world/test_catalog_flight_cpu_v3.gd"

const SpherePool = preload("res://game/debug/lk_flight_sphere_pool.gd")
@export var cpu4_optimizations_enabled: bool = true
var _cpu4_pool: SpherePool
var _cpu4_bound_far: MeshInstance3D

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or _cpu4_bound_far == _catalog_far_node:
		return
	_cpu4_pool = SpherePool.new()
	if not _cpu4_pool.configure(_nav_layout, String(_context["body"]["id"])):
		_fail_gate("CPU4 cannot bind sphere metadata")
		return
	_cpu4_bound_far = _catalog_far_node
	set("flight_sphere_sections_enabled", true)
	print("FlightCPU4: BIND pooled=%s exact-epoch states unchanged; radii/IDs bound once" % cpu4_optimizations_enabled)

func _build_flight_body_spheres(states: Dictionary, local_ready: bool) -> Array:
	if not cpu4_optimizations_enabled:
		return super._build_flight_body_spheres(states, local_ready)
	if _cpu4_pool == null:
		_fail_gate("CPU4 sphere pool missing")
		return []
	var rows: Array = _cpu4_pool.build(states, _flight_absolute, _universe_clock.now_s(), local_ready)
	if not _cpu4_pool.valid:
		_fail_gate("CPU4 sphere pool rejected state: " + _cpu4_pool.error)
		return []
	_flight_height = _cpu4_pool.nearest_height
	_flight_reference = _cpu4_pool.nearest_label
	return rows

func _flight_sphere_section(section: String, elapsed_us: int) -> void:
	_flight_cpu_section("sphere_" + section, elapsed_us)

func _cpu3_report() -> void:
	super._cpu3_report()
	if not _flight_active:
		return
	var parts: PackedStringArray = []
	for section: String in ["sphere_states", "sphere_terrain_readiness", "sphere_relative_build"]:
		var value: Dictionary = _cpu3_sections.summary(_cpu3_tick_stage + "|" + section)
		if not value.is_empty():
			parts.append("%s=%.3f/%.3f" % [section, value["mean_ms"], value["p95_ms"]])
	print("FlightCPU4: tick_phase=%s mean/p95_ms %s pooled=%s calls=%d" % [_cpu3_tick_stage, " ".join(parts), cpu4_optimizations_enabled, _cpu4_pool.calls if _cpu4_pool != null else 0])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_O:
		cpu4_optimizations_enabled = not cpu4_optimizations_enabled
		_cpu3_sections = PacingSamples.new(1200)
		print("FlightCPU4: pooled=%s sections reset; wall/render windows NOT reset" % cpu4_optimizations_enabled)
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _close_local_world() -> void:
	_cpu4_bound_far = null
	_cpu4_pool = null
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nFLIGHT CPU4 pool %s | Alt+O | fresh centres, fixed metadata, split sphere timings" % cpu4_optimizations_enabled
