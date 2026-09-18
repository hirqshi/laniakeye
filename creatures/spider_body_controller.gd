@tool
class_name SpiderBodyController
extends Node3D

const SPIDER_SHADER: Shader = preload("res://shaders/spider_static.gdshader")

const LEG_SEGMENT_COUNT: int = 2

var _cached_material: ShaderMaterial

@export var creature_profile: CreatureProfile:
	set(value):
		if creature_profile != null:
			if creature_profile.changed.is_connected(
				_on_profile_changed
			):
				creature_profile.changed.disconnect(
					_on_profile_changed
				)

		creature_profile = value

		if creature_profile != null:
			if not creature_profile.changed.is_connected(
				_on_profile_changed
			):
				creature_profile.changed.connect(
					_on_profile_changed
				)

		call_deferred("rebuild")

@export var material_source: MeshInstance3D

@export_category("Actions")

@export var rebuild_spider: bool = false:
	set(value):
		if not value:
			return

		call_deferred("rebuild")

@export_category("Motion")

@export var animate_idle: bool = true

var _generated_root: Node3D
var _leg_roots: Array[Node3D] = []
var _leg_base_rotations: Array[Vector3] = []
var _elapsed_s: float = 0.0

func _ready() -> void:
	call_deferred("rebuild")

func _exit_tree() -> void:
	if creature_profile == null:
		return

	if creature_profile.changed.is_connected(_on_profile_changed):
		creature_profile.changed.disconnect(_on_profile_changed)

func _process(delta: float) -> void:
	if not animate_idle:
		return

	if creature_profile == null:
		return

	if _leg_roots.is_empty():
		return

	_elapsed_s += delta

	var amplitude_rad: float = deg_to_rad(
		creature_profile.spider_idle_step_amplitude_deg
	)
	var leg_count: int = _leg_roots.size()

	for leg_index: int in leg_count:
		var leg_root: Node3D = _leg_roots[leg_index]

		if not is_instance_valid(leg_root):
			continue

		# alternate gait: every other leg around the ring swings
		# out of phase, like a spread tripod gait
		var group_phase: float = (
			0.0 if leg_index % 2 == 0 else PI
		)

		var phase: float = (
			_elapsed_s * creature_profile.spider_idle_step_speed
			+ group_phase
		)

		var swing_rad: float = sin(phase) * amplitude_rad
		var lift_rad: float = cos(phase) * amplitude_rad * 0.4

		leg_root.rotation = (
			_leg_base_rotations[leg_index]
			+ Vector3(lift_rad, 0.0, swing_rad)
		)

func rebuild() -> void:
	_clear_generated()

	if creature_profile == null:
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = creature_profile.preview_seed

	var body_length_m: float = creature_profile.get_length_m(rng)
	if body_length_m <= 0.0:
		push_warning("SpiderBodyController: invalid body_length_m, aborting rebuild")
		return

	_generated_root = Node3D.new()
	_generated_root.name = "GeneratedSpider"
	add_child(_generated_root)

	if Engine.is_editor_hint():
		_generated_root.owner = owner

	var body_radius_m: float = (
		body_length_m * creature_profile.spider_body_radius_ratio
	)

	var leg_count: int = creature_profile.get_leg_count(rng)

	_prepare_material(rng)

	_create_body(body_radius_m)
	_create_legs(rng, leg_count, body_radius_m)

	_apply_stand_height_offset()


## Legs are built hanging below body_radius_m, so the lowest foot tip
## ends up below the controller's own origin - lift the whole generated
## rig up by that amount so the feet touch ground level and the body
## floats above it, instead of the body sitting on the ground with legs
## buried in the terrain.
func _apply_stand_height_offset() -> void:
	if _generated_root == null:
		return

	var local_aabb: AABB = _get_local_aabb(_generated_root)

	if local_aabb.size.length_squared() < 0.0001:
		return

	var lowest_local_y: float = local_aabb.position.y

	if lowest_local_y >= 0.0:
		return

	_generated_root.position.y = -lowest_local_y


func _get_local_aabb(root: Node3D) -> AABB:
	var mesh_instances: Array[MeshInstance3D] = []
	_gather_mesh_instances(root, mesh_instances)

	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false

	for mesh_instance: MeshInstance3D in mesh_instances:
		if mesh_instance.mesh == null:
			continue

		var relative_transform: Transform3D = _get_transform_relative_to(
			mesh_instance,
			root
		)

		var mesh_local_aabb: AABB = mesh_instance.mesh.get_aabb()
		var relative_aabb: AABB = relative_transform * mesh_local_aabb

		if not has_aabb:
			combined_aabb = relative_aabb
			has_aabb = true
		else:
			combined_aabb = combined_aabb.merge(relative_aabb)

	return combined_aabb


func _get_transform_relative_to(
	node: Node3D,
	root: Node3D
) -> Transform3D:
	var result: Transform3D = node.transform
	var current: Node = node.get_parent()

	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result

		current = current.get_parent()

	return result

func get_generated_aabb() -> AABB:
	if _generated_root == null:
		return AABB()

	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false

	var mesh_instances: Array[MeshInstance3D] = []
	_gather_mesh_instances(_generated_root, mesh_instances)

	for mesh_instance: MeshInstance3D in mesh_instances:
		if mesh_instance.mesh == null:
			continue

		var local_aabb: AABB = mesh_instance.mesh.get_aabb()
		var global_aabb: AABB = mesh_instance.global_transform * local_aabb

		if not has_aabb:
			combined_aabb = global_aabb
			has_aabb = true
		else:
			combined_aabb = combined_aabb.merge(global_aabb)

	return combined_aabb

func clear_generated() -> void:
	_clear_generated()
	
func _gather_mesh_instances(
	node: Node,
	result: Array[MeshInstance3D]
) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)

		_gather_mesh_instances(child, result)

func _clear_generated() -> void:
	_leg_roots.clear()
	_leg_base_rotations.clear()
	_elapsed_s = 0.0

	if _generated_root != null:
		if is_instance_valid(_generated_root):
			_generated_root.queue_free()

	_generated_root = null

func _create_body(body_radius_m: float) -> void:
	if _generated_root == null:
		push_error("SpiderBodyController: _generated_root is null in _create_body")
		return

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = _build_icosahedron_mesh(body_radius_m)

	var material: Material = _get_body_material()
	if material != null:
		mesh_instance.material_override = material

	_generated_root.add_child(mesh_instance)

	if Engine.is_editor_hint():
		mesh_instance.owner = owner

func _build_icosahedron_mesh(radius_m: float) -> ArrayMesh:
	var golden_ratio: float = (1.0 + sqrt(5.0)) * 0.5

	var raw_vertices: Array[Vector3] = [
		Vector3(-1.0, golden_ratio, 0.0),
		Vector3(1.0, golden_ratio, 0.0),
		Vector3(-1.0, -golden_ratio, 0.0),
		Vector3(1.0, -golden_ratio, 0.0),
		Vector3(0.0, -1.0, golden_ratio),
		Vector3(0.0, 1.0, golden_ratio),
		Vector3(0.0, -1.0, -golden_ratio),
		Vector3(0.0, 1.0, -golden_ratio),
		Vector3(golden_ratio, 0.0, -1.0),
		Vector3(golden_ratio, 0.0, 1.0),
		Vector3(-golden_ratio, 0.0, -1.0),
		Vector3(-golden_ratio, 0.0, 1.0)
	]

	for vertex_index: int in raw_vertices.size():
		raw_vertices[vertex_index] = (
			raw_vertices[vertex_index].normalized() * radius_m
		)

	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7),
		Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2),
		Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6),
		Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10),
		Vector3i(8, 6, 7), Vector3i(9, 8, 1)
	]

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for face: Vector3i in faces:
		var vertex_a: Vector3 = raw_vertices[face.x]
		var vertex_b: Vector3 = raw_vertices[face.z]
		var vertex_c: Vector3 = raw_vertices[face.y]

		var outward_normal: Vector3 = (
			(vertex_a + vertex_b + vertex_c) / 3.0
		).normalized()

		_add_icosahedron_vertex(surface_tool, vertex_a, outward_normal)
		_add_icosahedron_vertex(surface_tool, vertex_b, outward_normal)
		_add_icosahedron_vertex(surface_tool, vertex_c, outward_normal)
	
	surface_tool.generate_tangents()

	return surface_tool.commit()

func _add_icosahedron_vertex(
	surface_tool: SurfaceTool,
	vertex_position: Vector3,
	face_normal: Vector3
) -> void:
	var direction: Vector3 = vertex_position.normalized()

	var u: float = 0.5 + atan2(direction.z, direction.x) / TAU
	var v: float = 0.5 - asin(clampf(direction.y, -1.0, 1.0)) / PI

	surface_tool.set_uv(Vector2(u, v))
	surface_tool.set_normal(face_normal)
	surface_tool.add_vertex(vertex_position)

func _create_legs(
	rng: RandomNumberGenerator,
	leg_count: int,
	body_radius_m: float
) -> void:
	if leg_count <= 0:
		return

	# distribute legs evenly around the body, tilted slightly
	# downward so the creature actually stands on them
	var angle_step_rad: float = TAU / float(leg_count)

	for leg_index: int in leg_count:
		var angle_rad: float = angle_step_rad * float(leg_index)
		var leg_length_m: float = creature_profile.get_leg_length_m(rng)

		var attach_direction: Vector3 = Vector3(
			cos(angle_rad),
			-0.15,
			sin(angle_rad)
		).normalized()

		## Build the leg's orientation from explicit forward/up vectors
		## instead of raw Euler angles - guarantees the leg's local X
		## axis (what the knee bends around) stays horizontal, so the
		## knee always folds upward in world space regardless of which
		## way around the body this leg points.
		var outward: Vector3 = Vector3(
			attach_direction.x,
			0.0,
			attach_direction.z
		)

		if outward.length_squared() < 0.0001:
			outward = Vector3.FORWARD
		else:
			outward = outward.normalized()

		var bend_axis: Vector3 = Vector3.UP.cross(outward).normalized()

		if bend_axis.length_squared() < 0.0001:
			bend_axis = Vector3.RIGHT

		var leg_forward: Vector3 = outward.rotated(
			bend_axis,
			deg_to_rad(65.0)
		)

		var leg_basis: Basis = Basis(
			bend_axis,
			bend_axis.cross(leg_forward).normalized(),
			leg_forward
		).orthonormalized()

		var leg_root: Node3D = Node3D.new()
		leg_root.name = "Leg_%d" % (leg_index + 1)
		leg_root.position = attach_direction * body_radius_m
		leg_root.basis = leg_basis

		_generated_root.add_child(leg_root)

		if Engine.is_editor_hint():
			leg_root.owner = owner

		_leg_roots.append(leg_root)
		_leg_base_rotations.append(leg_root.rotation)

		_create_leg_chain(leg_root, leg_length_m)

func _create_leg_chain(
	leg_root: Node3D,
	leg_length_m: float
) -> void:
	var segment_lengths: Array[float] = [
		leg_length_m * 0.55,
		leg_length_m * 0.45
	]

	var bend_degrees: Array[float] = [
		30.0 * creature_profile.spider_leg_bend,
		-75.0 * creature_profile.spider_leg_bend
	]

	var current_parent: Node3D = leg_root

	for segment_index: int in LEG_SEGMENT_COUNT:
		var segment_pivot: Node3D = Node3D.new()
		segment_pivot.name = "SegmentPivot_%d" % (segment_index + 1)

		if segment_index > 0:
			segment_pivot.position = Vector3(
				0.0,
				0.0,
				segment_lengths[segment_index - 1]
			)

		segment_pivot.rotation_degrees = Vector3(
			bend_degrees[segment_index],
			0.0,
			0.0
		)

		current_parent.add_child(segment_pivot)

		if Engine.is_editor_hint():
			segment_pivot.owner = owner

		var segment_mesh: MeshInstance3D = _create_leg_segment_mesh(
			segment_lengths[segment_index]
		)

		segment_pivot.add_child(segment_mesh)

		if Engine.is_editor_hint():
			segment_mesh.owner = owner

		current_parent = segment_pivot

func _create_leg_segment_mesh(length_m: float) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()

	var prism_mesh: CylinderMesh = CylinderMesh.new()
	prism_mesh.top_radius = creature_profile.spider_leg_radius_m * 0.7
	prism_mesh.bottom_radius = creature_profile.spider_leg_radius_m
	prism_mesh.height = length_m
	prism_mesh.radial_segments = 3
	prism_mesh.rings = 0
	prism_mesh.cap_top = false
	prism_mesh.cap_bottom = false

	mesh_instance.mesh = prism_mesh
	mesh_instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	mesh_instance.position = Vector3(0.0, 0.0, length_m * 0.5)

	var material: Material = _get_body_material()
	if material != null:
		mesh_instance.material_override = material

	return mesh_instance

func _prepare_material(rng: RandomNumberGenerator) -> void:
	if creature_profile == null:
		return

	if _cached_material == null:
		_cached_material = ShaderMaterial.new()
		_cached_material.shader = SPIDER_SHADER

	_cached_material.set_shader_parameter(
		"albedo_texture",
		creature_profile.albedo_texture
	)
	_cached_material.set_shader_parameter(
		"normal_texture",
		creature_profile.normal_texture
	)
	_cached_material.set_shader_parameter(
		"roughness_texture",
		creature_profile.roughness_texture
	)
	_cached_material.set_shader_parameter("normal_strength", 1.0)
	_cached_material.set_shader_parameter("roughness_multiplier", 1.0)

	var tint_color: Color = creature_profile.get_color(rng)
	_cached_material.set_shader_parameter("albedo_tint", tint_color)

func _get_body_material() -> Material:
	return _cached_material

func _on_profile_changed() -> void:
	call_deferred("rebuild")
