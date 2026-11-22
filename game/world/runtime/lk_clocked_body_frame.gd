class_name LkClockedBodyFrame
extends "res://game/world/runtime/lk_catalog_body_frame.gd"

var _shared_clock


func _init(id: StringName, spin: Dictionary, clock) -> void:
	super(id, spin, float(clock.now_s()))
	_shared_clock = clock


# Delta argument retained for compatibility with the existing terrain harness.
# The authoritative elapsed time comes ONLY from the shared world clock.
func advance(_delta: float) -> float:
	var target: float = _shared_clock.now_s()
	var elapsed: float = target - world_time_s
	if elapsed < 0.0:
		push_error("ClockedBodyFrame: live world clock moved backwards")
		return 0.0
	world_time_s = target
	_refresh()
	var step: float = angular_speed_rad_s * elapsed
	angle_rad = fposmod(angle_rad + step, TAU)
	return step
