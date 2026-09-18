@tool
class_name PlanetVegetationSpawner
extends Node3D

const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage.gdshader")

@export_category("Global Generation")
@export_range(100, 100_000, 100) var candidate_count_per_layer: int = 8_000
@export_range(0, 20_000, 1) var max_instances_per_layer: int = 1_500

@export_category("Placement")
@export_range(-1.0, 1.0, 0.001, "suffix:m") var surface_offset_m: float = -0.5
@export_range(0.0, 10.0, 0.01, "suffix:m") var water_clearance_m: float = 0.25

@export_category("Runtime Mesh Quality")
@export_range(0.1, 1.0, 0.05)
var tree_geometry_quality: float = 0.5

@export_category("Editor")
@export var generate_in_editor: bool = false
@export var regenerate_now: bool = false:
	set(value):
		if not value:
			return

		regenerate_now = false

		if Engine.is_editor_hint():
			_regenerate_from_current_data()

var _planet_data: PlanetData
var _surface_profile: Resource
var _vegetation_profile: VegetationProfile
var _surface_sampler: PlanetSurfaceSampler = PlanetSurfaceSampler.new()
var _tree_mesh_generator: TreeMeshGenerator = TreeMeshGenerator.new()
var _tree_mesh_cache: Dictionary[TreeProfile, ArrayMesh] = {}

func setup(planet_data: PlanetData) -> void:
	if Engine.is_editor_hint() and not generate_in_editor:
		return

	_planet_data = planet_data
	_regenerate_from_current_data()

func regenerate_for_preview(planet_data: PlanetData) -> void:
	_planet_data = planet_data
	_regenerate_from_current_data()

func _regenerate_from_current_data() -> void:
	_clear_layers()
	_tree_mesh_cache.clear()

	if _planet_data == null:
		return

	_surface_profile = _planet_data.surface_profile
	if _surface_profile == null:
		return

	_vegetation_profile = (
		_surface_profile.get("vegetation_profile") as VegetationProfile
	)
	if _vegetation_profile == null or not _vegetation_profile.is_enabled:
		return

	var terrain_noise_type: int = int(
		_surface_profile.get("terrain_noise_type")
	)

	_surface_sampler.setup(
		_planet_data.radius_m,
		_planet_data.planet_seed,
		_planet_data.terrain_noise_scale,
		_planet_data.terrain_height_m,
		terrain_noise_type,
		_surface_profile
	)

	var active_layers: Array[VegetationLayerProfile] = (
		_vegetation_profile.get_active_tree_layers()
	)

	for layer_index: int in range(active_layers.size()):
		_spawn_global_layer(active_layers[layer_index], layer_index)

func _clear_layers() -> void:
	for child: Node in get_children():
		child.queue_free()

func _spawn_global_layer(
	layer: VegetationLayerProfile,
	layer_index: int
) -> void:
	if layer == null or layer.tree_profile == null:
		return

	var tree_mesh: ArrayMesh = _get_tree_mesh(layer.tree_profile)
	if tree_mesh == null:
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (
		_planet_data.planet_seed
		+ _vegetation_profile.placement_seed_offset
		+ layer.seed_offset
		+ layer_index * 104_729
	)

	var biome_noise: FastNoiseLite = _create_noise(
		rng.seed + 17,
		layer.biome_noise_type,
		layer.biome_noise_frequency,
		layer.biome_noise_octaves
	)

	var cluster_noise: FastNoiseLite = _create_noise(
		rng.seed + 71_117,
		FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
		0.01 / maxf(layer.cluster_scale_m, 1.0),
		2
	)

	var transforms: Array[Transform3D] = []
	var minimum_slope_dot: float = layer.get_max_slope_cos()

	for candidate_index: int in range(candidate_count_per_layer):
		if transforms.size() >= max_instances_per_layer:
			break

		var direction: Vector3 = _random_unit_vector(rng)

		if not _surface_sampler.is_surface_above_water(
			direction,
			water_clearance_m
		):
			continue

		var surface_normal: Vector3 = _surface_sampler.get_surface_normal(direction)
		if surface_normal.dot(direction) < minimum_slope_dot:
			continue

		var spawn_probability: float = _get_spawn_probability(
			direction,
			layer,
			biome_noise,
			cluster_noise,
			rng
		)

		if spawn_probability <= 0.0:
			continue

		if rng.randf() > spawn_probability:
			continue

		var scale_factor: float = rng.randf_range(
			layer.min_scale,
			layer.max_scale
		)

		var yaw_rad: float = rng.randf_range(-PI, PI)

		var local_position: Vector3 = (
			_surface_sampler.get_surface_position(direction)
			+ surface_normal * surface_offset_m
		)

		transforms.append(
			_make_surface_transform(
				local_position,
				surface_normal,
				yaw_rad,
				scale_factor
			)
		)

	if transforms.is_empty():
		return

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = transforms.size()
	multimesh.mesh = tree_mesh
	multimesh.visible_instance_count = transforms.size()

	for transform_index: int in range(transforms.size()):
		multimesh.set_instance_transform(
			transform_index,
			transforms[transform_index]
		)

	multimesh.custom_aabb = _get_global_vegetation_aabb(layer)

	var multimesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	multimesh_instance.name = "TreeLayer_%02d_%s" % [
		layer_index,
		layer.display_name
	]
	multimesh_instance.multimesh = multimesh

	add_child(multimesh_instance)

func _get_global_vegetation_aabb(
	layer: VegetationLayerProfile
) -> AABB:
	var tree_profile: TreeProfile = layer.tree_profile
	var maximum_scale: float = layer.max_scale

	var maximum_tree_height_m: float = (
		tree_profile.max_height_m
		* maximum_scale
	)

	var maximum_crown_radius_m: float = (
		tree_profile.max_height_m
		* tree_profile.crown_radius_ratio
		* maximum_scale
	)

	var outer_radius_m: float = (
		_planet_data.radius_m
		+ maximum_tree_height_m
		+ maximum_crown_radius_m
		+ 2.0
	)

	return AABB(
		Vector3.ONE * -outer_radius_m,
		Vector3.ONE * outer_radius_m * 2.0
	)

func _get_tree_mesh(tree_profile: TreeProfile) -> ArrayMesh:
	if _tree_mesh_cache.has(tree_profile):
		return _tree_mesh_cache[tree_profile]

	var mesh: ArrayMesh = _tree_mesh_generator.generate(
		tree_profile,
		tree_profile.preview_seed,
		tree_geometry_quality
	)

	var bark_material: StandardMaterial3D = _create_bark_material(
		tree_profile
	)
	var leaf_material: ShaderMaterial = _create_leaf_material(
		tree_profile
	)

	if mesh.get_surface_count() > TreeMeshGenerator.BARK_SURFACE:
		mesh.surface_set_material(
			TreeMeshGenerator.BARK_SURFACE,
			bark_material
		)

	if mesh.get_surface_count() > TreeMeshGenerator.LEAF_SURFACE:
		mesh.surface_set_material(
			TreeMeshGenerator.LEAF_SURFACE,
			leaf_material
		)

	_tree_mesh_cache[tree_profile] = mesh
	return mesh

func _create_bark_material(
	tree_profile: TreeProfile
) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()

	material.vertex_color_use_as_albedo = true
	material.albedo_texture = tree_profile.bark_albedo_texture
	material.normal_enabled = tree_profile.bark_normal_texture != null
	material.normal_texture = tree_profile.bark_normal_texture
	material.roughness_texture = tree_profile.bark_roughness_texture
	material.ao_enabled = tree_profile.bark_ao_texture != null
	material.ao_texture = tree_profile.bark_ao_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK

	return material

func _create_leaf_material(
	tree_profile: TreeProfile
) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = FOLIAGE_SHADER

	material.set_shader_parameter(
		"albedo_texture",
		tree_profile.leaf_albedo_texture
	)
	material.set_shader_parameter(
		"normal_texture",
		tree_profile.leaf_normal_texture
	)
	material.set_shader_parameter(
		"roughness_texture",
		tree_profile.leaf_roughness_texture
	)
	material.set_shader_parameter(
		"foliage_tint",
		Color.WHITE
	)
	material.set_shader_parameter("alpha_cutoff", 0.5)
	material.set_shader_parameter("normal_strength", 1.0)
	material.set_shader_parameter("roughness_value", 0.86)
	material.set_shader_parameter("roughness_multiplier", 1.0)

	return material

func _create_noise(
	seed: int,
	noise_type: int,
	frequency: float,
	octaves: int
) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = noise_type
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.5
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	return noise

func _get_spawn_probability(
	direction: Vector3,
	layer: VegetationLayerProfile,
	biome_noise: FastNoiseLite,
	cluster_noise: FastNoiseLite,
	rng: RandomNumberGenerator
) -> float:
	var biome_value: float = (
		biome_noise.get_noise_3dv(direction * 100.0) + 1.0
	) * 0.5

	var threshold_center: float = (
		layer.biome_noise_threshold + 1.0
	) * 0.5

	var threshold_min: float = maxf(
		0.0,
		threshold_center - layer.biome_noise_softness
	)
	var threshold_max: float = minf(
		1.0,
		threshold_center + layer.biome_noise_softness
	)

	var biome_factor: float = smoothstep(
		threshold_min,
		threshold_max,
		biome_value
	)

	var cluster_value: float = (
		cluster_noise.get_noise_3dv(direction * 100.0) + 1.0
	) * 0.5

	var cluster_factor: float = lerpf(
		1.0,
		cluster_value,
		layer.cluster_strength
	)

	var isolated_tree: bool = rng.randf() < layer.isolated_tree_chance
	var clustered_probability: float = (
		layer.density
		* biome_factor
		* cluster_factor
	)

	if isolated_tree:
		return maxf(clustered_probability, layer.density * 0.25)

	return clampf(clustered_probability, 0.0, 1.0)

func _make_surface_transform(
	local_position: Vector3,
	surface_normal: Vector3,
	yaw_rad: float,
	scale_factor: float
) -> Transform3D:
	var up: Vector3 = surface_normal.normalized()
	var reference_axis: Vector3 = Vector3.FORWARD

	if absf(reference_axis.dot(up)) > 0.98:
		reference_axis = Vector3.RIGHT

	var right: Vector3 = reference_axis.cross(up).normalized()
	var forward: Vector3 = up.cross(right).normalized()

	var basis: Basis = Basis(right, up, forward)
	basis = basis.rotated(up, yaw_rad)
	basis = basis.scaled(Vector3.ONE * scale_factor)

	return Transform3D(basis, local_position)

func _random_unit_vector(rng: RandomNumberGenerator) -> Vector3:
	var y: float = rng.randf_range(-1.0, 1.0)
	var angle_rad: float = rng.randf_range(0.0, TAU)
	var horizontal_radius: float = sqrt(maxf(0.0, 1.0 - y * y))

	return Vector3(
		cos(angle_rad) * horizontal_radius,
		y,
		sin(angle_rad) * horizontal_radius
	)
