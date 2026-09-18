class_name TreeMeshGenerator
extends RefCounted

const BARK_SURFACE: int = 0
const LEAF_SURFACE: int = 1

var _profile: TreeProfile
var _rng: RandomNumberGenerator
var _runtime_geometry_quality: float = 1.0
var _bark_vertices: PackedVector3Array = PackedVector3Array()
var _bark_normals: PackedVector3Array = PackedVector3Array()
var _bark_colors: PackedColorArray = PackedColorArray()
var _bark_uvs: PackedVector2Array = PackedVector2Array()
var _bark_indices: PackedInt32Array = PackedInt32Array()

var _leaf_vertices: PackedVector3Array = PackedVector3Array()
var _leaf_normals: PackedVector3Array = PackedVector3Array()
var _leaf_colors: PackedColorArray = PackedColorArray()
var _leaf_uvs: PackedVector2Array = PackedVector2Array()
var _leaf_indices: PackedInt32Array = PackedInt32Array()

func generate(
	profile: TreeProfile,
	seed: int,
	runtime_geometry_quality: float = 1.0
) -> ArrayMesh:
	_profile = profile
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed
	_runtime_geometry_quality = clampf(
		runtime_geometry_quality,
		0.1,
		1.0
	)

	_clear_buffers()

	var height_m: float = _profile.get_height_m(_rng)
	var trunk_radius_m: float = _profile.get_trunk_radius_m(_rng)
	var bark_color: Color = _profile.get_bark_color(_rng)
	var leaf_color: Color = _profile.get_leaf_color(_rng)

	var trunk_points: PackedVector3Array = _build_trunk_points(height_m)
	_add_tube(
		trunk_points,
		trunk_radius_m,
		trunk_radius_m * (1.0 - _profile.trunk_taper),
		bark_color
	)

	var branch_tips: PackedVector3Array = _build_branches(
		trunk_points,
		height_m,
		trunk_radius_m,
		bark_color
	)

	_add_leaf_clusters(
		trunk_points,
		branch_tips,
		height_m,
		leaf_color
	)

	return _build_mesh()

func _clear_buffers() -> void:
	_bark_vertices.clear()
	_bark_normals.clear()
	_bark_colors.clear()
	_bark_uvs.clear()
	_bark_indices.clear()

	_leaf_vertices.clear()
	_leaf_normals.clear()
	_leaf_colors.clear()
	_leaf_uvs.clear()
	_leaf_indices.clear()

func _build_trunk_points(height_m: float) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	var lateral_offset: Vector2 = Vector2.ZERO
	var twist_angle: float = _rng.randf_range(0.0, TAU)
	var trunk_segments: int = _get_runtime_trunk_segments()

	for segment_index: int in range(trunk_segments + 1):
		var t: float = float(segment_index) / float(trunk_segments)
		var bend_step: Vector2 = Vector2(
			cos(twist_angle + t * TAU * _profile.trunk_twist),
			sin(twist_angle + t * TAU * _profile.trunk_twist)
		)

		lateral_offset += (
			bend_step
			* _profile.trunk_bend_amount_m
			* _rng.randf_range(-0.12, 0.12)
		)

		var point: Vector3 = Vector3(
			lateral_offset.x * t,
			height_m * t,
			lateral_offset.y * t
		)
		points.append(point)

	return points

func _build_branches(
	trunk_points: PackedVector3Array,
	height_m: float,
	trunk_radius_m: float,
	bark_color: Color
) -> PackedVector3Array:
	var tips: PackedVector3Array = PackedVector3Array()
	var branch_count: int = _get_runtime_branch_count()
	var branch_segments: int = _get_runtime_branch_segments()

	if branch_count <= 0:
		return tips

	var minimum_height_m: float = height_m * _profile.branch_start_height_ratio
	var maximum_height_m: float = height_m * 0.94

	for branch_index: int in range(branch_count):
		var branch_height_m: float = _rng.randf_range(
			minimum_height_m,
			maximum_height_m
		)
		var branch_start: Vector3 = _sample_polyline_by_height(
			trunk_points,
			branch_height_m
		)
		var branch_length_m: float = _profile.get_branch_length_m(_rng)

		var azimuth: float = (
			TAU * float(branch_index) / float(maxi(branch_count, 1))
			+ _rng.randf_range(-0.45, 0.45)
		)

		var horizontal_direction: Vector3 = Vector3(
			cos(azimuth),
			0.0,
			sin(azimuth)
		).normalized()

		var branch_points: PackedVector3Array = PackedVector3Array()

		for segment_index: int in range(branch_segments + 1):
			var t: float = float(segment_index) / float(branch_segments)
			var radial_distance: float = branch_length_m * t

			var side_direction: Vector3 = Vector3(
				-horizontal_direction.z,
				0.0,
				horizontal_direction.x
			)

			var curve_offset: float = (
				sin(t * PI)
				* _profile.branch_curvature
				* branch_length_m
			)

			var twist_offset: float = (
				sin(t * TAU * _profile.branch_twist + azimuth)
				* _profile.branch_curvature
				* 0.35
			)

			var vertical_offset: float = (
				t * branch_length_m * _profile.branch_vertical_bias
				- t * t * branch_length_m * _profile.hanging_amount
			)

			var point: Vector3 = (
				branch_start
				+ horizontal_direction * radial_distance
				+ side_direction * (curve_offset + twist_offset)
				+ Vector3.UP * vertical_offset
			)
			branch_points.append(point)

		var branch_start_radius_m: float = (
			trunk_radius_m
			* _profile.branch_radius_ratio
			* _rng.randf_range(0.75, 1.15)
		)
		var branch_end_radius_m: float = branch_start_radius_m * 0.16

		_add_tube(
			branch_points,
			branch_start_radius_m,
			branch_end_radius_m,
			bark_color
		)

		tips.append(branch_points[branch_points.size() - 1])

	return tips

func _sample_polyline_by_height(points: PackedVector3Array, target_height_m: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO

	if points.size() == 1:
		return points[0]

	for point_index: int in range(points.size() - 1):
		var from: Vector3 = points[point_index]
		var to: Vector3 = points[point_index + 1]

		if target_height_m >= from.y and target_height_m <= to.y:
			var height_delta: float = max(to.y - from.y, 0.0001)
			var t: float = clamp((target_height_m - from.y) / height_delta, 0.0, 1.0)
			return from.lerp(to, t)

	return points[points.size() - 1]

func _add_tube(
	points: PackedVector3Array,
	start_radius_m: float,
	end_radius_m: float,
	color: Color
) -> void:
	if points.size() < 2:
		return

	var radial_segments: int = _get_runtime_trunk_radial_segments()
	var first_vertex: int = _bark_vertices.size()

	for point_index: int in range(points.size()):
		var t: float = float(point_index) / float(points.size() - 1)
		var radius_m: float = lerpf(start_radius_m, end_radius_m, t)

		var tangent: Vector3
		if point_index == 0:
			tangent = (points[1] - points[0]).normalized()
		elif point_index == points.size() - 1:
			tangent = (points[point_index] - points[point_index - 1]).normalized()
		else:
			tangent = (points[point_index + 1] - points[point_index - 1]).normalized()

		var reference_axis: Vector3 = Vector3.UP
		if absf(tangent.dot(reference_axis)) > 0.94:
			reference_axis = Vector3.RIGHT

		var ring_right: Vector3 = tangent.cross(reference_axis).normalized()
		var ring_forward: Vector3 = ring_right.cross(tangent).normalized()

		for radial_index: int in range(radial_segments):
			var radial_t: float = float(radial_index) / float(radial_segments)
			var angle: float = radial_t * TAU
			var radial_direction: Vector3 = (
				ring_right * cos(angle)
				+ ring_forward * sin(angle)
			).normalized()

			_bark_vertices.append(points[point_index] + radial_direction * radius_m)
			_bark_normals.append(radial_direction)
			_bark_colors.append(color)
			_bark_uvs.append(Vector2(radial_t, t))

	for point_index: int in range(points.size() - 1):
		for radial_index: int in range(radial_segments):
			var next_radial_index: int = (radial_index + 1) % radial_segments

			var a: int = first_vertex + point_index * radial_segments + radial_index
			var b: int = first_vertex + point_index * radial_segments + next_radial_index
			var c: int = first_vertex + (point_index + 1) * radial_segments + radial_index
			var d: int = first_vertex + (point_index + 1) * radial_segments + next_radial_index

			_bark_indices.append(a)
			_bark_indices.append(c)
			_bark_indices.append(b)

			_bark_indices.append(b)
			_bark_indices.append(c)
			_bark_indices.append(d)

func _add_leaf_clusters(
	trunk_points: PackedVector3Array,
	branch_tips: PackedVector3Array,
	height_m: float,
	base_color: Color
) -> void:
	if _profile.crown_shape == TreeProfile.CrownShape.DEAD:
		return

	var crown_start_y: float = height_m * _profile.crown_start_height_ratio
	var crown_height_m: float = max(height_m * _profile.crown_height_ratio, 0.1)
	var crown_radius_m: float = max(height_m * _profile.crown_radius_ratio, 0.1)
	var crown_center: Vector3 = _sample_polyline_by_height(
		trunk_points,
		crown_start_y + crown_height_m * 0.5
	)

	var leaf_cluster_count: int = _get_runtime_leaf_cluster_count()

	for cluster_index: int in range(leaf_cluster_count):
		var point: Vector3 = _get_crown_cluster_position(
			crown_center,
			crown_radius_m,
			crown_height_m,
			cluster_index
		)

		if not branch_tips.is_empty() and _rng.randf() < 0.68:
			var tip: Vector3 = branch_tips[_rng.randi_range(0, branch_tips.size() - 1)]
			point = point.lerp(tip, _rng.randf_range(0.35, 0.8))
		else:
			point.y = max(point.y, crown_start_y)

		var radius_m: float = _rng.randf_range(
			_profile.min_leaf_cluster_radius_m,
			_profile.max_leaf_cluster_radius_m
		)

		var color_variation: float = _rng.randf_range(0.82, 1.12)
		var color: Color = Color(
			base_color.r * color_variation,
			base_color.g * color_variation,
			base_color.b * color_variation,
			1.0
		)

		_add_leaf_card_cluster(point, radius_m, color)

func _get_crown_cluster_position(
	center: Vector3,
	radius_m: float,
	height_m: float,
	cluster_index: int
) -> Vector3:
	var angle: float = _rng.randf_range(0.0, TAU)
	var normalized_height: float = _rng.randf_range(-1.0, 1.0)
	var normalized_radius: float = sqrt(_rng.randf())

	var shape_radius_multiplier: float = _get_crown_radius_multiplier(normalized_height)
	var horizontal_radius: float = radius_m * normalized_radius * shape_radius_multiplier

	var position: Vector3 = center + Vector3(
		cos(angle) * horizontal_radius,
		normalized_height * height_m * 0.5,
		sin(angle) * horizontal_radius
	)

	var asymmetry_direction: Vector3 = Vector3(
		cos(float(cluster_index) * 2.39996323),
		0.0,
		sin(float(cluster_index) * 2.39996323)
	)
	position += asymmetry_direction * radius_m * _profile.crown_asymmetry * _rng.randf()

	match _profile.crown_shape:
		TreeProfile.CrownShape.WEEPING:
			position.y -= absf(normalized_height) * height_m * _profile.hanging_amount

		TreeProfile.CrownShape.WINDSWEPT:
			position += Vector3.RIGHT * radius_m * _profile.wind_shear_amount * (normalized_height + 1.0)

		TreeProfile.CrownShape.FLAT_TOP:
			position.y = min(position.y, center.y + height_m * 0.32)

		TreeProfile.CrownShape.LAYERED:
			var layer_height: float = height_m * 0.22
			position.y = snappedf(position.y, layer_height)

	return position

func _get_crown_radius_multiplier(normalized_height: float) -> float:
	var t: float = clamp((normalized_height + 1.0) * 0.5, 0.0, 1.0)

	match _profile.crown_shape:
		TreeProfile.CrownShape.ROUND:
			return sqrt(max(0.0, 1.0 - normalized_height * normalized_height))

		TreeProfile.CrownShape.OVAL:
			return sqrt(max(0.0, 1.0 - normalized_height * normalized_height)) * 0.78

		TreeProfile.CrownShape.CONICAL:
			return max(0.08, 1.0 - t)

		TreeProfile.CrownShape.COLUMN:
			return 0.82

		TreeProfile.CrownShape.UMBRELLA:
			return smoothstep(0.15, 0.8, t)

		TreeProfile.CrownShape.WEEPING:
			return sqrt(max(0.0, 1.0 - normalized_height * normalized_height)) * 1.15

		TreeProfile.CrownShape.WINDSWEPT:
			return sqrt(max(0.0, 1.0 - normalized_height * normalized_height))

		TreeProfile.CrownShape.FLAT_TOP:
			return 0.95 if t > 0.45 else t * 2.1

		TreeProfile.CrownShape.LAYERED:
			return 0.3 + 0.7 * (1.0 - t)

		TreeProfile.CrownShape.DEAD:
			return 0.0

	return 1.0

func _add_leaf_card_cluster(center: Vector3, radius_m: float, color: Color) -> void:
	var yaw_offset: float = _rng.randf_range(0.0, TAU)
	var card_count: int = _get_runtime_leaf_cards_per_cluster()

	for card_index: int in range(card_count):
		var angle: float = yaw_offset + TAU * float(card_index) / float(card_count)
		var right: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var up: Vector3 = Vector3.UP

		var width_m: float = radius_m * _rng.randf_range(1.45, 2.0)
		var height_m: float = radius_m * _rng.randf_range(1.35, 1.9)

		var local_offset: Vector3 = Vector3(
			_rng.randf_range(-radius_m * 0.18, radius_m * 0.18),
			_rng.randf_range(-radius_m * 0.12, radius_m * 0.12),
			_rng.randf_range(-radius_m * 0.18, radius_m * 0.18)
		)

		_add_double_sided_leaf_card(
			center + local_offset,
			right,
			up,
			width_m,
			height_m,
			color
		)

func _add_double_sided_leaf_card(
	center: Vector3,
	right: Vector3,
	up: Vector3,
	width_m: float,
	height_m: float,
	color: Color
) -> void:
	var first_vertex: int = _leaf_vertices.size()
	var half_width_m: float = width_m * 0.5
	var half_height_m: float = height_m * 0.5

	var bottom_left: Vector3 = center - right * half_width_m - up * half_height_m
	var bottom_right: Vector3 = center + right * half_width_m - up * half_height_m
	var top_right: Vector3 = center + right * half_width_m + up * half_height_m
	var top_left: Vector3 = center - right * half_width_m + up * half_height_m

	var normal: Vector3 = up.cross(right).normalized()

	_leaf_vertices.append(bottom_left)
	_leaf_normals.append(normal)
	_leaf_colors.append(color)
	_leaf_uvs.append(Vector2(0.0, 1.0))

	_leaf_vertices.append(bottom_right)
	_leaf_normals.append(normal)
	_leaf_colors.append(color)
	_leaf_uvs.append(Vector2(1.0, 1.0))

	_leaf_vertices.append(top_right)
	_leaf_normals.append(normal)
	_leaf_colors.append(color)
	_leaf_uvs.append(Vector2(1.0, 0.0))

	_leaf_vertices.append(top_left)
	_leaf_normals.append(normal)
	_leaf_colors.append(color)
	_leaf_uvs.append(Vector2(0.0, 0.0))

	_leaf_indices.append(first_vertex)
	_leaf_indices.append(first_vertex + 2)
	_leaf_indices.append(first_vertex + 1)

	_leaf_indices.append(first_vertex)
	_leaf_indices.append(first_vertex + 3)
	_leaf_indices.append(first_vertex + 2)

func _build_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()

	if not _bark_vertices.is_empty():
		var bark_arrays: Array = []
		bark_arrays.resize(Mesh.ARRAY_MAX)
		bark_arrays[Mesh.ARRAY_VERTEX] = _bark_vertices
		bark_arrays[Mesh.ARRAY_NORMAL] = _bark_normals
		bark_arrays[Mesh.ARRAY_COLOR] = _bark_colors
		bark_arrays[Mesh.ARRAY_TEX_UV] = _bark_uvs
		bark_arrays[Mesh.ARRAY_INDEX] = _bark_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark_arrays)

	if not _leaf_vertices.is_empty():
		var leaf_arrays: Array = []
		leaf_arrays.resize(Mesh.ARRAY_MAX)
		leaf_arrays[Mesh.ARRAY_VERTEX] = _leaf_vertices
		leaf_arrays[Mesh.ARRAY_NORMAL] = _leaf_normals
		leaf_arrays[Mesh.ARRAY_COLOR] = _leaf_colors
		leaf_arrays[Mesh.ARRAY_TEX_UV] = _leaf_uvs
		leaf_arrays[Mesh.ARRAY_INDEX] = _leaf_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaf_arrays)

	return mesh

func _get_runtime_trunk_segments() -> int:
	return maxi(
		3,
		roundi(
			float(_profile.trunk_segments)
			* _runtime_geometry_quality
		)
	)

func _get_runtime_trunk_radial_segments() -> int:
	return maxi(
		3,
		roundi(
			float(_profile.trunk_radial_segments)
			* _runtime_geometry_quality
		)
	)

func _get_runtime_branch_count() -> int:
	var configured_count: int = _profile.get_branch_count(_rng)

	return maxi(
		0,
		roundi(
			float(configured_count)
			* _runtime_geometry_quality
		)
	)

func _get_runtime_branch_segments() -> int:
	return maxi(
		2,
		roundi(
			float(_profile.branch_segments)
			* _runtime_geometry_quality
		)
	)

func _get_runtime_leaf_cluster_count() -> int:
	return maxi(
		1,
		roundi(
			float(_profile.leaf_cluster_count)
			* _runtime_geometry_quality
		)
	)

func _get_runtime_leaf_cards_per_cluster() -> int:
	if _runtime_geometry_quality >= 0.8:
		return 3

	if _runtime_geometry_quality >= 0.45:
		return 2

	return 1
