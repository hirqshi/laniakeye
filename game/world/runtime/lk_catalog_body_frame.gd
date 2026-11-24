class_name LkCatalogBodyFrame
extends LkRotatingFrame

const Motion = preload("res://game/world/generation/lk_kepler_motion.gd")
var _spin: Dictionary
var world_time_s: float
var _body_axes: Array


func _init(id: StringName, spin: Dictionary, time_s: float = 0.0) -> void:
	super(id, LkPosition64.new(), Vector3.UP, 0.0)
	_spin = spin.duplicate(true)
	world_time_s = time_s
	angular_speed_rad_s = float(spin["direction"]) * TAU / float(spin["period_s"])
	_refresh()


func _refresh() -> void:
	_body_axes = Motion.spin_state(_spin, world_time_s)["body_to_system_axes"]
	var pole: Array = _body_axes[1]
	# Preserve doubles for large-radius carry, rather than round through Vector3.
	_axis = LkPosition64.new(pole[0], pole[1], pole[2])


func advance(delta: float) -> float:
	world_time_s += delta
	_refresh()
	var step: float = angular_speed_rad_s * delta
	angle_rad = fposmod(angle_rad + step, TAU)
	return step


func planet_basis() -> Basis:
	return Basis(
		Vector3(_body_axes[0][0], _body_axes[0][1], _body_axes[0][2]),
		Vector3(_body_axes[1][0], _body_axes[1][1], _body_axes[1][2]),
		Vector3(_body_axes[2][0], _body_axes[2][1], _body_axes[2][2])
	).orthonormalized()


func body_to_inertial(q: LkPosition64) -> LkPosition64:
	return LkPosition64.new(
		float(_body_axes[0][0]) * q.x + float(_body_axes[1][0]) * q.y + float(_body_axes[2][0]) * q.z,
		float(_body_axes[0][1]) * q.x + float(_body_axes[1][1]) * q.y + float(_body_axes[2][1]) * q.z,
		float(_body_axes[0][2]) * q.x + float(_body_axes[1][2]) * q.y + float(_body_axes[2][2]) * q.z
	)


func inertial_to_body(q: LkPosition64) -> LkPosition64:
	return LkPosition64.new(
		float(_body_axes[0][0]) * q.x + float(_body_axes[0][1]) * q.y + float(_body_axes[0][2]) * q.z,
		float(_body_axes[1][0]) * q.x + float(_body_axes[1][1]) * q.y + float(_body_axes[1][2]) * q.z,
		float(_body_axes[2][0]) * q.x + float(_body_axes[2][1]) * q.y + float(_body_axes[2][2]) * q.z
	)
