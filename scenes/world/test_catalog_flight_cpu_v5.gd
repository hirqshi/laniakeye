extends "res://scenes/world/test_catalog_flight_cpu_v4.gd"

const ReferenceLayout = preload("res://world/generation/lk_safe_orbit_layout.gd")
const CompiledCache = preload("res://world/debug/lk_flight_cpu_compiled_cache.gd")
@export var cpu5_optimizations_enabled: bool = true
# Fine-grained timing is intentionally off in normal A/B performance runs.
@export var cpu5_profile_details: bool = false
var _cpu5_cache: CompiledCache
var _cpu5_bound_far: MeshInstance3D

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or _cpu5_bound_far == _catalog_far_node:
		return
	_cpu5_cache = CompiledCache.new()
	if not _cpu5_cache.configure(_nav_layout):
		_fail_gate("CPU5 cannot compile validated system layout")
		return
	# Strict startup parity on the actual bound system, without advancing clock.
	for offset: float in [0.0, 60.0, 1000000.0]:
		var epoch: float = _universe_clock.now_s() + offset
		var reference: Dictionary = ReferenceLayout.evaluate(_nav_layout, epoch)
		var candidate: Dictionary = _cpu5_cache.compiled.evaluate(epoch)
		if var_to_bytes(reference) != var_to_bytes(candidate):
			_fail_gate("CPU5 exact startup parity failed at offset=%s" % offset)
			return
	print("FlightCPU5: PARITY actual system PASS epochs=3 byte_exact=true")
	_cpu5_cache.compiled.set_profile_enabled(cpu5_profile_details)
	_cpu5_cache.set_compiled_enabled(cpu5_optimizations_enabled)
	_cpu3_cache = _cpu5_cache
	var far_layout: Dictionary = _catalog_far_node.get("_far_layout")
	_cpu3_far_matches = _cpu3_cache.matches(far_layout)
	_cpu3_sync_providers()
	_cpu5_bound_far = _catalog_far_node
	print("FlightCPU5: BIND compiled=%s shared=%s far_scope_match=%s detail_profile=%s" % [cpu5_optimizations_enabled, cpu3_optimizations_enabled and cpu3_share_system_states, _cpu3_far_matches, cpu5_profile_details])

func _cpu3_report() -> void:
	super._cpu3_report()
	if _cpu5_cache == null:
		return
	print("FlightCPU5: compiled=%s detail_profile=%s" % [cpu5_optimizations_enabled, cpu5_profile_details])
	if cpu5_profile_details:
		print("FlightCPU5: cumulative body phase ms/evaluation %s (instrumented; not A/B wall timing)" % _cpu5_cache.compiled.profile_summary())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_U:
		cpu5_optimizations_enabled = not cpu5_optimizations_enabled
		if _cpu5_cache != null:
			_cpu5_cache.set_compiled_enabled(cpu5_optimizations_enabled)
		_cpu3_sections = PacingSamples.new(1200)
		print("FlightCPU5: compiled=%s sections reset; wall windows/cache totals NOT reset" % cpu5_optimizations_enabled)
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _close_local_world() -> void:
	_cpu5_bound_far = null
	_cpu5_cache = null
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nFLIGHT CPU5 compiled %s | Alt+U | original Kepler solve, exact epoch" % cpu5_optimizations_enabled
