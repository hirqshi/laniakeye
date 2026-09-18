@tool
class_name CreaturePreview
extends Node3D

const WORM_SHADER: Shader = preload("res://shaders/worm_wiggle.gdshader")
const SQUID_SHADER: Shader = preload("res://shaders/squid_wiggle.gdshader")
const SPIDER_SHADER: Shader = preload("res://shaders/spider_static.gdshader")

@export var creature_profile: CreatureProfile:
	set(value):
		if creature_profile != null and creature_profile.changed.is_connected(_on_profile_changed):
			creature_profile.changed.disconnect(_on_profile_changed)

		creature_profile = value

		if creature_profile != null and not creature_profile.changed.is_connected(_on_profile_changed):
			creature_profile.changed.connect(_on_profile_changed)

		_regenerate()

@export_category("Scene References")
@export var creature_mesh_instance: MeshInstance3D
@export var preview_camera: Camera3D

@export_category("Actions")
@export var regenerate_preview: bool = false:
	set(value):
		if not value:
			return
		call_deferred("_regenerate")

@export var randomize_seed: bool = false:
	set(value):
		if not value or creature_profile == null:
			return

		creature_profile.preview_seed = randi()
		creature_profile.changed.emit()

@export var worm_body_controller: WormBodyController
@export var spider_body_controller: SpiderBodyController
@export var squid_tentacle_lag: SquidTentacleLag

var _generator: CreatureMeshGenerator = CreatureMeshGenerator.new()
var _preview_material: ShaderMaterial
var _preview_secondary_material: ShaderMaterial

var _cached_material: ShaderMaterial

func _ready() -> void:
	_regenerate()

func _exit_tree() -> void:
	if creature_profile != null and creature_profile.changed.is_connected(_on_profile_changed):
		creature_profile.changed.disconnect(_on_profile_changed)

func _on_profile_changed() -> void:
	call_deferred("_regenerate")

func _regenerate() -> void:
	if creature_profile == null or creature_mesh_instance == null:
		return

	var is_worm: bool = (
		creature_profile.creature_type
		== CreatureProfile.CreatureType.WORM
	)

	var is_squid: bool = (
		creature_profile.creature_type
		== CreatureProfile.CreatureType.SQUID
	)

	var is_spider: bool = (
		creature_profile.creature_type
		== CreatureProfile.CreatureType.SPIDER
	)

	if worm_body_controller != null:
		worm_body_controller.process_mode = (
			Node.PROCESS_MODE_ALWAYS
			if is_worm
			else Node.PROCESS_MODE_DISABLED
		)

	if squid_tentacle_lag != null:
		squid_tentacle_lag.process_mode = (
			Node.PROCESS_MODE_ALWAYS
			if is_squid
			else Node.PROCESS_MODE_DISABLED
		)

	if spider_body_controller != null:
		spider_body_controller.process_mode = (
			Node.PROCESS_MODE_ALWAYS
			if is_spider
			else Node.PROCESS_MODE_DISABLED
		)

	if is_worm:
		if worm_body_controller == null:
			push_error(
				"CreaturePreview: Worm Body Controller is not assigned"
			)
			return

		creature_mesh_instance.mesh = null
		worm_body_controller.creature_profile = creature_profile
		worm_body_controller.rebuild()
		return

	if is_spider:
		if spider_body_controller == null:
			push_error(
				"CreaturePreview: Spider Body Controller is not assigned"
			)
			return

		creature_mesh_instance.mesh = null
		spider_body_controller.creature_profile = creature_profile
		spider_body_controller.rebuild()

		var spider_aabb: AABB = spider_body_controller.get_generated_aabb()
		_frame_camera_world_aabb(spider_aabb)
		return

	var mesh: ArrayMesh = _build_mesh_for_type()
	if mesh == null:
		return

	creature_mesh_instance.mesh = mesh
	_apply_preview_material()
	_frame_camera(mesh)

func _frame_camera_world_aabb(world_aabb: AABB) -> void:
	if preview_camera == null:
		return

	if world_aabb.size.length_squared() < 0.0001:
		return

	var target: Vector3 = world_aabb.get_center()
	var largest_size: float = maxf(
		world_aabb.size.x,
		maxf(world_aabb.size.y, world_aabb.size.z)
	)
	var distance_m: float = maxf(largest_size * 1.8, 2.0)

	preview_camera.global_position = (
		target
		+ Vector3(1.0, 0.6, 1.0).normalized() * distance_m
	)
	preview_camera.look_at(target, Vector3.UP)

func _build_mesh_for_type() -> ArrayMesh:
	match creature_profile.creature_type:
		CreatureProfile.CreatureType.WORM:
			var worm_data: WormMeshData = _generator.create_worm(
				creature_profile,
				creature_profile.preview_seed
			)
			return worm_data.mesh
		CreatureProfile.CreatureType.SQUID:
			return _generator.generate_squid(
				creature_profile,
				creature_profile.preview_seed
			)
		CreatureProfile.CreatureType.SPIDER:
			push_warning("CreaturePreview: spider mesh generation not implemented yet")
			return null

	return null

func _apply_preview_material() -> void:
	if creature_mesh_instance == null or creature_profile == null:
		return

	var mesh: ArrayMesh = creature_mesh_instance.mesh as ArrayMesh
	if mesh == null:
		return

	_preview_material = _create_preview_material(1.0)
	_preview_secondary_material = _create_preview_material(1.0)

	if creature_profile.creature_type == CreatureProfile.CreatureType.WORM:
		_apply_worm_shader_parameters(_preview_material)
		creature_mesh_instance.set_surface_override_material(
			0,
			_preview_material
		)
		return

	if creature_profile.creature_type == CreatureProfile.CreatureType.SQUID:
		var body_material: ShaderMaterial = _create_squid_material(
			false,
			creature_profile.squid_body_wiggle_multiplier
		)
		var tentacle_material: ShaderMaterial = _create_squid_material(
			true,
			1.0
		)

		creature_mesh_instance.set_surface_override_material(
			CreatureMeshGenerator.SQUID_BODY_SURFACE,
			body_material
		)

		if mesh.get_surface_count() > CreatureMeshGenerator.SQUID_TENTACLE_SURFACE:
			creature_mesh_instance.set_surface_override_material(
				CreatureMeshGenerator.SQUID_TENTACLE_SURFACE,
				tentacle_material
			)

		return

func _create_preview_material(
	wiggle_multiplier: float
) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = WORM_SHADER
	material.set_shader_parameter(
		"albedo_texture",
		creature_profile.albedo_texture
	)
	material.set_shader_parameter(
		"normal_texture",
		creature_profile.normal_texture
	)
	material.set_shader_parameter(
		"roughness_texture",
		creature_profile.roughness_texture
	)
	material.set_shader_parameter("normal_strength", 1.0)
	material.set_shader_parameter("roughness_multiplier", 1.0)
	material.set_shader_parameter("wiggle_multiplier", wiggle_multiplier)
	return material

func _create_squid_material(
	is_tentacle_surface: bool,
	wiggle_multiplier: float
) -> ShaderMaterial:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = creature_profile.preview_seed

	var creature_length_m: float = creature_profile.get_length_m(rng)
	var body_radius_m: float = (
		creature_length_m * creature_profile.squid_body_radius_ratio
	)

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SQUID_SHADER
	material.set_shader_parameter(
		"albedo_texture",
		creature_profile.albedo_texture
	)
	material.set_shader_parameter(
		"normal_texture",
		creature_profile.normal_texture
	)
	material.set_shader_parameter(
		"roughness_texture",
		creature_profile.roughness_texture
	)
	material.set_shader_parameter("normal_strength", 1.0)
	material.set_shader_parameter("roughness_multiplier", 1.0)

	material.set_shader_parameter(
		"body_wiggle_multiplier",
		wiggle_multiplier
	)
	material.set_shader_parameter(
		"body_wave_frequency",
		creature_profile.wave_frequency
	)
	material.set_shader_parameter(
		"body_wave_speed",
		creature_profile.wave_speed
	)
	material.set_shader_parameter(
		"body_wave_amplitude_ratio",
		creature_profile.wave_amplitude_ratio
	)
	material.set_shader_parameter("body_radius_m", body_radius_m)

	material.set_shader_parameter(
		"tentacle_wave_frequency",
		creature_profile.tentacle_wave_frequency
	)
	material.set_shader_parameter(
		"tentacle_wave_speed",
		creature_profile.tentacle_wave_speed
	)
	material.set_shader_parameter(
		"tentacle_wave_amplitude_ratio",
		creature_profile.tentacle_wave_amplitude_ratio
	)
	material.set_shader_parameter(
		"tentacle_radius_m",
		body_radius_m * creature_profile.tentacle_radius_ratio
	)
	material.set_shader_parameter(
		"surface_mode",
		1.0 if is_tentacle_surface else 0.0
	)

	return material

func _apply_worm_shader_parameters(
	material: ShaderMaterial
) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = creature_profile.preview_seed

	creature_profile.get_length_m(rng)
	var radius_m: float = creature_profile.get_worm_radius_m(rng)

	material.set_shader_parameter(
		"wave_amplitude_ratio",
		creature_profile.wave_amplitude_ratio
	)
	material.set_shader_parameter(
		"wave_frequency",
		creature_profile.wave_frequency
	)
	material.set_shader_parameter(
		"wave_speed",
		creature_profile.wave_speed
	)
	material.set_shader_parameter("body_radius_m", radius_m)
	material.set_shader_parameter("wiggle_multiplier", 1.0)

func _frame_camera(mesh: ArrayMesh) -> void:
	if preview_camera == null:
		return

	var aabb: AABB = mesh.get_aabb()
	if aabb.size.length_squared() < 0.0001:
		return

	var target: Vector3 = aabb.get_center()
	var largest_size: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var distance_m: float = maxf(largest_size * 1.8, 2.0)

	preview_camera.global_position = (
		target
		+ Vector3(1.0, 0.6, 1.0).normalized() * distance_m
	)
	preview_camera.look_at(target, Vector3.UP)
