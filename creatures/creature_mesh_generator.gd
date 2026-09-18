class_name CreatureMeshGenerator
extends RefCounted

const SQUID_BODY_SURFACE: int = 0
const SQUID_TENTACLE_SURFACE: int = 1

func create_worm(
	profile: CreatureProfile,
	creature_seed: int
) -> WormMeshData:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = creature_seed

	var data: WormMeshData = WormMeshData.new()
	data.length_m = profile.get_length_m(rng)
	data.base_radius_m = profile.get_worm_radius_m(rng)
	data.color = profile.get_color(rng)
	data.segment_count = profile.worm_segments
	data.radial_segment_count = profile.worm_radial_segments

	for ring_index: int in range(data.segment_count + 1):
		var t: float = float(ring_index) / float(data.segment_count)
		var taper: float = 1.0 - t * 0.4
		data.ring_radii_m.append(data.base_radius_m * taper)

	_build_worm_topology(data)
	_build_initial_worm_mesh(data)

	return data

func update_worm_mesh(
	data: WormMeshData,
	body_points: PackedVector3Array
) -> void:
	if data == null:
		return

	if body_points.size() != data.segment_count + 1:
		push_error(
			"CreatureMeshGenerator: body_points count must be %d, got %d"
			% [data.segment_count + 1, body_points.size()]
		)
		return

	_update_worm_vertices_and_normals(data, body_points)

	data.mesh.clear_surfaces()
	_add_worm_surface(data)

func _build_worm_topology(data: WormMeshData) -> void:
	var side_vertex_count: int = data.get_side_vertex_count()

	data.vertices.resize(side_vertex_count)
	data.normals.resize(side_vertex_count)
	data.colors.resize(side_vertex_count)
	data.uvs.resize(side_vertex_count)

	for ring_index: int in range(data.segment_count):
		for radial_index: int in range(data.radial_segment_count):
			var next_radial_index: int = (
				(radial_index + 1) % data.radial_segment_count
			)

			var a: int = data.get_ring_vertex_index(
				ring_index,
				radial_index
			)
			var b: int = data.get_ring_vertex_index(
				ring_index,
				next_radial_index
			)
			var c: int = data.get_ring_vertex_index(
				ring_index + 1,
				radial_index
			)
			var d: int = data.get_ring_vertex_index(
				ring_index + 1,
				next_radial_index
			)

			data.indices.append(a)
			data.indices.append(c)
			data.indices.append(b)

			data.indices.append(b)
			data.indices.append(c)
			data.indices.append(d)

	_append_cap_topology(data, true)
	_append_cap_topology(data, false)

func _append_cap_topology(
	data: WormMeshData,
	is_head: bool
) -> void:
	var center_index: int = data.vertices.size()
	var cap_ring_start_index: int = center_index + 1

	data.vertices.append(Vector3.ZERO)
	data.normals.append(Vector3.FORWARD)
	data.colors.append(data.color)
	data.uvs.append(Vector2(0.5, 0.5))

	for radial_index: int in range(data.radial_segment_count):
		data.vertices.append(Vector3.ZERO)
		data.normals.append(Vector3.FORWARD)
		data.colors.append(data.color)
		data.uvs.append(Vector2.ZERO)

	for radial_index: int in range(data.radial_segment_count):
		var next_radial_index: int = (
			(radial_index + 1) % data.radial_segment_count
		)

		var current_index: int = cap_ring_start_index + radial_index
		var next_index: int = cap_ring_start_index + next_radial_index

		if is_head:
			data.indices.append(center_index)
			data.indices.append(next_index)
			data.indices.append(current_index)
		else:
			data.indices.append(center_index)
			data.indices.append(current_index)
			data.indices.append(next_index)

func _build_initial_worm_mesh(data: WormMeshData) -> void:
	var body_points: PackedVector3Array = PackedVector3Array()

	for ring_index: int in range(data.segment_count + 1):
		var t: float = float(ring_index) / float(data.segment_count)
		body_points.append(Vector3(0.0, 0.0, -data.length_m * t))

	_update_worm_vertices_and_normals(data, body_points)

	data.mesh = ArrayMesh.new()
	_add_worm_surface(data)

func _update_worm_vertices_and_normals(
	data: WormMeshData,
	body_points: PackedVector3Array
) -> void:
	var side_vertex_count: int = data.get_side_vertex_count()

	if data.vertices.size() < side_vertex_count:
		data.vertices.resize(side_vertex_count)
		data.normals.resize(side_vertex_count)
		data.colors.resize(side_vertex_count)
		data.uvs.resize(side_vertex_count)

	for ring_index: int in range(data.segment_count + 1):
		var t: float = float(ring_index) / float(data.segment_count)
		var center: Vector3 = body_points[ring_index]
		var tangent: Vector3 = _get_tangent(body_points, ring_index)
		var ring_basis: Basis = _get_ring_basis(tangent)

		for radial_index: int in range(data.radial_segment_count):
			var radial_t: float = (
				float(radial_index) / float(data.radial_segment_count)
			)
			var angle_rad: float = radial_t * TAU

			var radial_direction: Vector3 = (
				ring_basis.x * cos(angle_rad)
				+ ring_basis.y * sin(angle_rad)
			).normalized()

			var vertex_index: int = data.get_ring_vertex_index(
				ring_index,
				radial_index
			)

			data.vertices[vertex_index] = (
				center
				+ radial_direction * data.ring_radii_m[ring_index]
			)
			data.normals[vertex_index] = radial_direction
			data.colors[vertex_index] = data.color
			data.uvs[vertex_index] = Vector2(radial_t, t)

	_update_cap_vertices(data, body_points, true)
	_update_cap_vertices(data, body_points, false)

func _update_cap_vertices(
	data: WormMeshData,
	body_points: PackedVector3Array,
	is_head: bool
) -> void:
	var side_vertex_count: int = data.get_side_vertex_count()

	var head_cap_vertex_count: int = (
		1 + data.radial_segment_count
	)

	var cap_start_index: int = side_vertex_count
	if not is_head:
		cap_start_index += head_cap_vertex_count

	var ring_index: int = 0 if is_head else data.segment_count
	var center: Vector3 = body_points[ring_index]
	var tangent: Vector3 = _get_tangent(body_points, ring_index)
	var cap_normal: Vector3 = tangent if is_head else -tangent
	var ring_basis: Basis = _get_ring_basis(tangent)
	var radius_m: float = data.ring_radii_m[ring_index]

	data.vertices[cap_start_index] = center
	data.normals[cap_start_index] = cap_normal
	data.colors[cap_start_index] = data.color
	data.uvs[cap_start_index] = Vector2(0.5, 0.5)

	for radial_index: int in range(data.radial_segment_count):
		var radial_t: float = (
			float(radial_index) / float(data.radial_segment_count)
		)
		var angle_rad: float = radial_t * TAU
		var radial_direction: Vector3 = (
			ring_basis.x * cos(angle_rad)
			+ ring_basis.y * sin(angle_rad)
		).normalized()

		var vertex_index: int = cap_start_index + 1 + radial_index

		data.vertices[vertex_index] = (
			center + radial_direction * radius_m
		)
		data.normals[vertex_index] = cap_normal
		data.colors[vertex_index] = data.color
		data.uvs[vertex_index] = Vector2(
			0.5 + radial_direction.x * 0.5,
			0.5 + radial_direction.y * 0.5
		)

func _get_tangent(
	body_points: PackedVector3Array,
	ring_index: int
) -> Vector3:
	var tangent: Vector3

	if ring_index == 0:
		tangent = body_points[0] - body_points[1]
	elif ring_index == body_points.size() - 1:
		tangent = body_points[body_points.size() - 2] - body_points[ring_index]
	else:
		tangent = body_points[ring_index - 1] - body_points[ring_index + 1]

	if tangent.length_squared() < 0.0001:
		return Vector3.FORWARD

	return tangent.normalized()

func _get_ring_basis(tangent: Vector3) -> Basis:
	var reference_axis: Vector3 = Vector3.UP

	if absf(tangent.dot(reference_axis)) > 0.95:
		reference_axis = Vector3.RIGHT

	var right: Vector3 = tangent.cross(reference_axis).normalized()
	var up: Vector3 = right.cross(tangent).normalized()

	return Basis(right, up, tangent)

func _add_worm_surface(data: WormMeshData) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_TEX_UV] = data.uvs
	arrays[Mesh.ARRAY_INDEX] = data.indices

	data.mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays
	)

func generate_squid(
	profile: CreatureProfile,
	creature_seed: int
) -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = creature_seed

	var creature_length_m: float = profile.get_length_m(rng)
	var color: Color = profile.get_color(rng)

	var body_length_m: float = (
		creature_length_m * profile.squid_body_length_ratio
	)
	var body_radius_m: float = (
		creature_length_m * profile.squid_body_radius_ratio
	)

	var body_vertices: PackedVector3Array = PackedVector3Array()
	var body_normals: PackedVector3Array = PackedVector3Array()
	var body_colors: PackedColorArray = PackedColorArray()
	var body_uvs: PackedVector2Array = PackedVector2Array()
	var body_indices: PackedInt32Array = PackedInt32Array()

	var tentacle_vertices: PackedVector3Array = PackedVector3Array()
	var tentacle_normals: PackedVector3Array = PackedVector3Array()
	var tentacle_colors: PackedColorArray = PackedColorArray()
	var tentacle_uvs: PackedVector2Array = PackedVector2Array()
	var tentacle_indices: PackedInt32Array = PackedInt32Array()

	_add_squid_body(
		body_vertices,
		body_normals,
		body_colors,
		body_uvs,
		body_indices,
		body_length_m,
		body_radius_m,
		profile.squid_body_rings,
		profile.squid_body_radial_segments,
		color
	)

	_add_squid_tentacles(
		tentacle_vertices,
		tentacle_normals,
		tentacle_colors,
		tentacle_uvs,
		tentacle_indices,
		profile,
		rng,
		body_length_m,
		body_radius_m,
		color
	)

	var mesh: ArrayMesh = ArrayMesh.new()

	_add_surface(
		mesh,
		body_vertices,
		body_normals,
		body_colors,
		body_uvs,
		body_indices
	)

	if not tentacle_vertices.is_empty():
		_add_surface(
			mesh,
			tentacle_vertices,
			tentacle_normals,
			tentacle_colors,
			tentacle_uvs,
			tentacle_indices
		)

	return mesh

func _add_squid_body(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	body_length_m: float,
	body_radius_m: float,
	ring_count: int,
	radial_segments: int,
	color: Color
) -> void:
	for ring_index: int in range(ring_count + 1):
		var t: float = float(ring_index) / float(ring_count)

		# head is at local -Z, tentacles attach at local +Z.
		var z: float = lerpf(-body_length_m * 0.5, body_length_m * 0.5, t)

		# ovoid profile: pointed-ish head and slightly narrowed rear.
		var oval: float = sin(t * PI)
		var head_taper: float = smoothstep(0.0, 0.2, t)
		var rear_taper: float = 1.0 - smoothstep(0.78, 1.0, t) * 0.35
		var radius_m: float = body_radius_m * oval * head_taper * rear_taper

		for radial_index: int in range(radial_segments):
			var radial_t: float = float(radial_index) / float(radial_segments)
			var angle_rad: float = radial_t * TAU

			var radial_direction: Vector3 = Vector3(
				cos(angle_rad),
				sin(angle_rad),
				0.0
			)

			vertices.append(Vector3(
				radial_direction.x * radius_m,
				radial_direction.y * radius_m,
				z
			))
			normals.append(radial_direction)
			colors.append(color)
			uvs.append(Vector2(radial_t, t))

	for ring_index: int in range(ring_count):
		for radial_index: int in range(radial_segments):
			var next_radial_index: int = (
				(radial_index + 1) % radial_segments
			)

			var a: int = ring_index * radial_segments + radial_index
			var b: int = ring_index * radial_segments + next_radial_index
			var c: int = (ring_index + 1) * radial_segments + radial_index
			var d: int = (ring_index + 1) * radial_segments + next_radial_index

			# same winding as the worm's known-good outer surface.
			indices.append(a)
			indices.append(c)
			indices.append(b)

			indices.append(b)
			indices.append(c)
			indices.append(d)

func _add_squid_body_cap(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	is_head: bool,
	body_length_m: float,
	radius_m: float,
	radial_segments: int,
	color: Color
) -> void:
	var z: float = -body_length_m * 0.5 if is_head else body_length_m * 0.5
	var cap_normal: Vector3 = Vector3.FORWARD if is_head else Vector3.BACK
	var center_index: int = vertices.size()

	vertices.append(Vector3(0.0, 0.0, z))
	normals.append(cap_normal)
	colors.append(color)
	uvs.append(Vector2(0.5, 0.5))

	var ring_start_index: int = vertices.size()

	for radial_index: int in range(radial_segments):
		var radial_t: float = float(radial_index) / float(radial_segments)
		var angle_rad: float = radial_t * TAU
		var direction: Vector3 = Vector3(
			cos(angle_rad),
			sin(angle_rad),
			0.0
		)

		vertices.append(Vector3(
			direction.x * radius_m,
			direction.y * radius_m,
			z
		))
		normals.append(cap_normal)
		colors.append(color)
		uvs.append(Vector2(
			0.5 + direction.x * 0.5,
			0.5 + direction.y * 0.5
		))

	for radial_index: int in range(radial_segments):
		var next_radial_index: int = (
			(radial_index + 1) % radial_segments
		)
		var current_index: int = ring_start_index + radial_index
		var next_index: int = ring_start_index + next_radial_index

		if is_head:
			indices.append(center_index)
			indices.append(next_index)
			indices.append(current_index)
		else:
			indices.append(center_index)
			indices.append(current_index)
			indices.append(next_index)

func _add_squid_tentacles(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	profile: CreatureProfile,
	rng: RandomNumberGenerator,
	body_length_m: float,
	body_radius_m: float,
	color: Color
) -> void:
	var safe_count: int = maxi(profile.tentacle_count, 1)

	for tentacle_index: int in range(safe_count):
		if rng.randf() < profile.tentacle_missing_chance:
			continue

		var base_angle_rad: float = (
			TAU * float(tentacle_index) / float(safe_count)
		)
		var angle_rad: float = (
			base_angle_rad
			+ rng.randf_range(
				-profile.tentacle_angle_variation_rad,
				profile.tentacle_angle_variation_rad
			)
		)

		var length_variation: float = rng.randf_range(
			1.0 - profile.tentacle_length_variation,
			1.0 + profile.tentacle_length_variation
		)
		var tentacle_length_m: float = (
			profile.get_tentacle_length_m(rng) * length_variation
		)

		var radius_variation: float = rng.randf_range(
			1.0 - profile.tentacle_radius_variation,
			1.0 + profile.tentacle_radius_variation
		)
		var tentacle_radius_m: float = (
			body_radius_m
			* profile.tentacle_radius_ratio
			* radius_variation
		)

		var attachment_direction: Vector3 = Vector3(
			cos(angle_rad),
			sin(angle_rad),
			0.0
		)

		var attachment_radius_m: float = body_radius_m * (
			1.0 - profile.tentacle_attachment_inset_ratio
		)

		var attachment_point: Vector3 = Vector3(
			attachment_direction.x * attachment_radius_m,
			attachment_direction.y * attachment_radius_m,
			body_length_m * 0.38
		)

		var tentacle_points: PackedVector3Array = PackedVector3Array()

		for point_index: int in range(profile.tentacle_segments + 1):
			var t: float = (
				float(point_index) / float(profile.tentacle_segments)
			)

			# Grows backwards (+Z), with a small deterministic outward fan.
			var bend_m: float = (
				sin(t * PI)
				* tentacle_length_m
				* 0.12
				* rng.randf_range(0.6, 1.4)
			)

			tentacle_points.append(
				attachment_point
				+ Vector3.BACK * tentacle_length_m * t
				+ attachment_direction * bend_m
			)
			
		var tentacle_phase: float = rng.randf()
		var tentacle_color: Color = Color(
			color.r,
			color.g,
			color.b,
			tentacle_phase
		)

		_add_tube_from_points(
			vertices,
			normals,
			colors,
			uvs,
			indices,
			tentacle_points,
			tentacle_radius_m,
			tentacle_radius_m * (1.0 - profile.tentacle_taper),
			profile.tentacle_radial_segments,
			tentacle_color
		)

func _add_tube_from_points(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	points: PackedVector3Array,
	start_radius_m: float,
	end_radius_m: float,
	radial_segments: int,
	color: Color
) -> void:
	if points.size() < 2:
		return

	var first_vertex_index: int = vertices.size()

	for point_index: int in range(points.size()):
		var t: float = float(point_index) / float(points.size() - 1)
		var radius_m: float = lerpf(start_radius_m, end_radius_m, t)
		var tangent: Vector3 = _get_polyline_tangent(points, point_index)
		var ring_basis: Basis = _get_tube_ring_basis(tangent)

		for radial_index: int in range(radial_segments):
			var radial_t: float = float(radial_index) / float(radial_segments)
			var angle_rad: float = radial_t * TAU
			var radial_direction: Vector3 = (
				ring_basis.x * cos(angle_rad)
				+ ring_basis.y * sin(angle_rad)
			).normalized()

			vertices.append(points[point_index] + radial_direction * radius_m)
			normals.append(radial_direction)
			colors.append(color)
			uvs.append(Vector2(radial_t, t))

	for point_index: int in range(points.size() - 1):
		for radial_index: int in range(radial_segments):
			var next_radial_index: int = (
				(radial_index + 1) % radial_segments
			)

			var a: int = (
				first_vertex_index
				+ point_index * radial_segments
				+ radial_index
			)
			var b: int = (
				first_vertex_index
				+ point_index * radial_segments
				+ next_radial_index
			)
			var c: int = (
				first_vertex_index
				+ (point_index + 1) * radial_segments
				+ radial_index
			)
			var d: int = (
				first_vertex_index
				+ (point_index + 1) * radial_segments
				+ next_radial_index
			)

			indices.append(a)
			indices.append(c)
			indices.append(b)

			indices.append(b)
			indices.append(c)
			indices.append(d)

func _get_polyline_tangent(
	points: PackedVector3Array,
	point_index: int
) -> Vector3:
	var tangent: Vector3

	if point_index == 0:
		tangent = points[1] - points[0]
	elif point_index == points.size() - 1:
		tangent = points[point_index] - points[point_index - 1]
	else:
		tangent = points[point_index + 1] - points[point_index - 1]

	if tangent.length_squared() < 0.0001:
		return Vector3.FORWARD

	return tangent.normalized()

func _get_tube_ring_basis(tangent: Vector3) -> Basis:
	var reference_axis: Vector3 = Vector3.UP

	if absf(tangent.dot(reference_axis)) > 0.95:
		reference_axis = Vector3.RIGHT

	var right: Vector3 = tangent.cross(reference_axis).normalized()
	var up: Vector3 = right.cross(tangent).normalized()

	return Basis(right, up, tangent)

func _add_surface(
	mesh: ArrayMesh,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
