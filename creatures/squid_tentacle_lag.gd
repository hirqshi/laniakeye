@tool
class_name SquidTentacleLag
extends Node

## Feeds a local inertial lag vector to the squid tentacle material.
## Tracks both translation and rotation, so it works when the owner is
## moved OR rotated in the editor and later during runtime locomotion.

@export var target: Node3D
@export var tentacle_mesh: MeshInstance3D

@export_range(0.0, 20.0, 0.1) var lag_strength: float = 3.0
@export_range(0.1, 30.0, 0.1) var lag_recovery_speed: float = 7.0
@export_range(0.0, 20.0, 0.01, "suffix:m") var max_lag_offset_m: float = 2.0
@export_range(0.01, 100.0, 0.01, "suffix:m")
var rotation_lever_arm_m: float = 1.5

var _previous_global_position: Vector3 = Vector3.ZERO
var _previous_global_basis: Basis = Basis.IDENTITY
var _has_previous_transform: bool = false
var _lag_offset_local: Vector3 = Vector3.ZERO

func _ready() -> void:
	if target == null:
		target = get_parent() as Node3D

func _process(delta: float) -> void:
	if target == null or tentacle_mesh == null or delta <= 0.0:
		return

	if not _has_previous_transform:
		_previous_global_position = target.global_position
		_previous_global_basis = target.global_transform.basis
		_has_previous_transform = true
		return

	var translation_world: Vector3 = (
		_previous_global_position - target.global_position
	)

	var previous_forward_world: Vector3 = (
		-_previous_global_basis.z
	).normalized()
	var current_forward_world: Vector3 = (
		-target.global_transform.basis.z
	).normalized()

	# Turning changes a point behind the body even if global_position
	# does not move. This approximates the inertial direction at the
	# tentacle roots with one configurable lever arm.
	var rotation_world: Vector3 = (
		previous_forward_world - current_forward_world
	) * rotation_lever_arm_m

	_previous_global_position = target.global_position
	_previous_global_basis = target.global_transform.basis

	var total_lag_world: Vector3 = translation_world + rotation_world
	var total_lag_local: Vector3 = (
		target.global_transform.basis.inverse() * total_lag_world
	)

	_lag_offset_local += total_lag_local * lag_strength
	_lag_offset_local = _lag_offset_local.lerp(
		Vector3.ZERO,
		clampf(lag_recovery_speed * delta, 0.0, 1.0)
	)

	if _lag_offset_local.length() > max_lag_offset_m:
		_lag_offset_local = (
			_lag_offset_local.normalized() * max_lag_offset_m
		)

	_apply_lag_to_tentacle_material()

func _apply_lag_to_tentacle_material() -> void:
	if tentacle_mesh == null:
		return

	var mesh: Mesh = tentacle_mesh.mesh
	if mesh == null:
		return

	var tentacle_surface: int = (
		CreatureMeshGenerator.SQUID_TENTACLE_SURFACE
	)

	if tentacle_surface < 0:
		return

	if tentacle_surface >= mesh.get_surface_count():
		return

	var material: ShaderMaterial = (
		tentacle_mesh.get_surface_override_material(
			tentacle_surface
		) as ShaderMaterial
	)

	if material == null:
		return

	material.set_shader_parameter(
		"tentacle_lag_offset_local",
		_lag_offset_local
	)
