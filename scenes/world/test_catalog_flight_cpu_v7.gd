extends "res://scenes/world/test_catalog_flight_cpu_v5.gd"

const Cpu7SpherePool = preload("res://game/debug/lk_flight_sphere_pool_fused.gd")
const Cpu7Occlusion = preload("res://game/debug/lk_navigation_occlusion_scalar.gd")
@export var cpu7_fused_spheres_enabled: bool = true
@export var cpu7_scalar_occlusion_enabled: bool = true
@export var cpu7_runtime_parity_checks: int = 32
var _cpu7_bound_far: MeshInstance3D
var _cpu7_checks_left: int = 0

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or _cpu7_bound_far == _catalog_far_node:
		return
	if cpu7_fused_spheres_enabled:
		var pool = Cpu7SpherePool.new()
		if not pool.configure(_nav_layout, String(_context["body"]["id"])):
			_fail_gate("CPU7 cannot bind fused sphere pool")
			return
		_cpu4_pool = pool
	_cpu7_checks_left = maxi(cpu7_runtime_parity_checks, 0)
	_cpu7_bound_far = _catalog_far_node
	print("FlightCPU7: BIND fused_spheres=%s scalar_occlusion=%s inherit_navigation_gate=true inherit_approach_guard=true" % [cpu7_fused_spheres_enabled, cpu7_scalar_occlusion_enabled])

# Deliberately DO NOT override _flight_spheres, _flight_safe_step or
# _update_navigation_tick. Ancestor approach sphere, movement guard and30Hz
# throttle remain on their original call paths, including v3 counters.
func _nav_occluded(relative: Array, distance: float, ignore_body: String = "") -> bool:
	if not cpu7_scalar_occlusion_enabled:
		return super._nav_occluded(relative, distance, ignore_body)
	var answer: bool = Cpu7Occlusion.occluded(_nav_records, relative, distance, ignore_body)
	if _cpu7_checks_left > 0:
		var reference: bool = super._nav_occluded(relative, distance, ignore_body)
		if answer != reference:
			_fail_gate("CPU7 navigation occlusion parity failed")
			return true
		_cpu7_checks_left -= 1
		if _cpu7_checks_left == 0:
			print("FlightCPU7: NAV_PARITY PASS rays=%d" % cpu7_runtime_parity_checks)
	return answer

func _close_local_world() -> void:
	_cpu7_bound_far = null
	_cpu7_checks_left = 0
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and _flight_show_telemetry:
		_label.text += "\nFLIGHT CPU7 fused %s | scalar occlusion %s | original navigation/approach chain" % [cpu7_fused_spheres_enabled, cpu7_scalar_occlusion_enabled]
