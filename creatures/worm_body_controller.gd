@tool
class_name WormBodyController
extends Node

@export_category("Scene References")

@export var creature_mesh: MeshInstance3D
@export var creature_profile: CreatureProfile

@export_category("Preview Motion")

@export var preview_enabled: bool = true

@export_range(0.0, 20.0, 0.01, "suffix:m")
var preview_path_radius_m: float = 2.0

@export_range(0.0, 20.0, 0.01, "suffix:m/s")
var preview_speed_m_s: float = 1.5

@export_range(-1.0, 1.0, 0.01, "suffix:m")
var preview_vertical_wave_m: float = 0.25

@export_category("Body Follow")

@export_range(0.02, 2.0, 0.01, "suffix:m")
var path_point_spacing_m: float = 0.12

@export_range(1.0, 10.0, 0.1)
var path_history_length_multiplier: float = 1.5

@export_category("Runtime Motion")

@export var runtime_head_control_enabled: bool = true

var _generator: CreatureMeshGenerator = CreatureMeshGenerator.new()
var _worm_data: WormMeshData

## Positions are stored in CreatureSpawner/planet local space.
var _path_points_planet_local: PackedVector3Array = (
	PackedVector3Array()
)
var _previous_head_position_planet_local: Vector3 = Vector3.ZERO
var _has_head_position: bool = false
var _preview_distance_m: float = 0.0

func _ready() -> void:
	if creature_profile == null:
		return

	if creature_profile.creature_type != CreatureProfile.CreatureType.WORM:
		return

	rebuild()

func _process(delta: float) -> void:
	if _worm_data == null:
		return

	if Engine.is_editor_hint() and preview_enabled:
		_update_preview_motion(delta)

	_update_body_mesh()

func rebuild() -> void:
	if creature_mesh == null or creature_profile == null:
		return

	if creature_profile.creature_type != CreatureProfile.CreatureType.WORM:
		return

	_worm_data = _generator.create_worm(
		creature_profile,
		creature_profile.preview_seed
	)

	creature_mesh.mesh = _worm_data.mesh

	_path_points_planet_local.clear()
	_previous_head_position_planet_local = Vector3.ZERO
	_has_head_position = false
	_preview_distance_m = 0.0

func reset_path_at_planet_local(
	head_position_planet_local: Vector3
) -> void:
	if _worm_data == null:
		return

	_seed_path_at(head_position_planet_local)


func set_head_position_planet_local(
	head_position_planet_local: Vector3
) -> void:
	if _worm_data == null:
		return

	if creature_mesh == null:
		return

	if not _has_head_position:
		_seed_path_at(head_position_planet_local)
		return

	var movement: Vector3 = (
		head_position_planet_local
		- _previous_head_position_planet_local
	)

	var movement_distance_m: float = movement.length()

	if movement_distance_m < 0.0001:
		return

	var movement_direction: Vector3 = (
		movement / movement_distance_m
	)

	var remaining_distance_m: float = movement_distance_m
	var sample_position: Vector3 = (
		_previous_head_position_planet_local
	)

	var new_points: PackedVector3Array = PackedVector3Array()

	while remaining_distance_m >= path_point_spacing_m:
		sample_position += movement_direction * path_point_spacing_m
		new_points.append(sample_position)
		remaining_distance_m -= path_point_spacing_m

	if not new_points.is_empty():
		var combined_points: PackedVector3Array = (
			PackedVector3Array()
		)

		for point: Vector3 in new_points:
			combined_points.append(point)

		for point: Vector3 in _path_points_planet_local:
			combined_points.append(point)

		_path_points_planet_local = combined_points

	_previous_head_position_planet_local = sample_position
	_trim_path()


func _seed_path_at(head_position_planet_local: Vector3) -> void:
	_path_points_planet_local.clear()
	_path_points_planet_local.append(head_position_planet_local)

	_previous_head_position_planet_local = head_position_planet_local
	_has_head_position = true

func _update_preview_motion(delta: float) -> void:
	if delta <= 0.0:
		return

	var spawner: Node3D = _get_spawner()
	if spawner == null:
		return

	_preview_distance_m += preview_speed_m_s * delta

	var safe_radius_m: float = maxf(
		preview_path_radius_m,
		0.01
	)
	var circumference_m: float = TAU * safe_radius_m
	var angle_rad: float = (
		_preview_distance_m / circumference_m * TAU
	)

	var head_position_planet_local: Vector3 = (
		creature_mesh.global_position
	)

	var head_position_world: Vector3 = (
		head_position_planet_local
		+ Vector3(
			cos(angle_rad) * safe_radius_m,
			sin(angle_rad * 2.0) * preview_vertical_wave_m,
			sin(angle_rad) * safe_radius_m
		)
	)

	set_head_position_planet_local(
		spawner.to_local(head_position_world)
	)

func _initialize_straight_path(
	head_position_planet_local: Vector3,
	forward_direction_planet_local: Vector3
) -> void:
	_path_points_planet_local.clear()

	var safe_forward: Vector3 = (
		forward_direction_planet_local.normalized()
	)

	if safe_forward.length_squared() < 0.0001:
		safe_forward = Vector3.FORWARD

	var required_path_length_m: float = (
		_worm_data.length_m * path_history_length_multiplier
	)

	var point_count: int = maxi(
		_worm_data.segment_count + 2,
		ceili(
			required_path_length_m / path_point_spacing_m
		) + 1
	)

	for point_index: int in range(point_count):
		_path_points_planet_local.append(
			head_position_planet_local
			- safe_forward
			* path_point_spacing_m
			* float(point_index)
		)

	_previous_head_position_planet_local = (
		head_position_planet_local
	)
	_has_head_position = true

func _trim_path() -> void:
	var max_path_length_m: float = (
		_worm_data.length_m * path_history_length_multiplier
	)

	var max_point_count: int = maxi(
		_worm_data.segment_count + 2,
		ceili(
			max_path_length_m / path_point_spacing_m
		) + 1
	)

	while _path_points_planet_local.size() > max_point_count:
		_path_points_planet_local.remove_at(
			_path_points_planet_local.size() - 1
		)

func _update_body_mesh() -> void:
	if _worm_data == null:
		return

	if creature_mesh == null:
		return

	if _path_points_planet_local.size() < 2:
		return

	var spawner: Node3D = _get_spawner()
	if spawner == null:
		return

	var body_points_mesh_local: PackedVector3Array = (
		PackedVector3Array()
	)

	for ring_index: int in range(_worm_data.segment_count + 1):
		var t: float = (
			float(ring_index)
			/ float(_worm_data.segment_count)
		)

		var distance_behind_head_m: float = (
			_worm_data.length_m * t
		)

		var point_planet_local: Vector3 = (
			_get_path_position_at_distance(
				distance_behind_head_m
			)
		)

		var point_world: Vector3 = spawner.to_global(
			point_planet_local
		)

		body_points_mesh_local.append(
			creature_mesh.to_local(point_world)
		)

	_generator.update_worm_mesh(
		_worm_data,
		body_points_mesh_local
	)

func _get_path_position_at_distance(
	target_distance_m: float
) -> Vector3:
	var walked_distance_m: float = 0.0

	for point_index: int in range(
		_path_points_planet_local.size() - 1
	):
		var from: Vector3 = (
			_path_points_planet_local[point_index]
		)
		var to: Vector3 = (
			_path_points_planet_local[point_index + 1]
		)
		var segment_length_m: float = from.distance_to(to)

		if walked_distance_m + segment_length_m >= target_distance_m:
			var local_distance_m: float = (
				target_distance_m - walked_distance_m
			)

			var t: float = (
				local_distance_m
				/ maxf(segment_length_m, 0.0001)
			)

			return from.lerp(to, t)

		walked_distance_m += segment_length_m

	return _path_points_planet_local[
		_path_points_planet_local.size() - 1
	]

func _get_forward_planet_local() -> Vector3:
	var spawner: Node3D = _get_spawner()

	if spawner == null:
		return Vector3.FORWARD

	var forward_world: Vector3 = (
		-creature_mesh.global_transform.basis.z
	).normalized()

	var forward_planet_local: Vector3 = (
		spawner.global_transform.basis.inverse()
		* forward_world
	).normalized()

	if forward_planet_local.length_squared() < 0.0001:
		return Vector3.FORWARD

	return forward_planet_local

func _get_spawner() -> Node3D:
	var creature_body: Node = get_parent()

	if creature_body == null:
		return null

	return creature_body.get_parent() as Node3D
