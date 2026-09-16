extends Node3D

## Represents both planets and moons. All child node references are wired
## via export, not @onready + $paths.
##
## Reverted to using the SAME mesh for both visuals and collision - the
## smoothed collision mesh experiment did not fix vertical jitter (the
## real cause was in player_controller.gd's velocity resync logic, now
## fixed there), so there's no reason to pay the accuracy cost of a
## separate simplified collider anymore.

const TRIPLANAR_SHADER: Shader = preload("res://shaders/triplanar.gdshader")

@export var mesh_instance: MeshInstance3D
@export var collision_shape: CollisionShape3D
@export var gravity_area: Area3D
@export var gravity_collision_shape: CollisionShape3D
@export var moons_container: Node3D

@export var moon_scene: PackedScene
@export var is_moon: bool = false
@export var generation_settings: GenerationSettings

var planet_data: PlanetData
var moon_nodes: Array[Node3D] = []
var mesh_generator: PlanetMeshGenerator = PlanetMeshGenerator.new()

func setup(data: PlanetData) -> void:
	planet_data = data

	var mesh: ArrayMesh = mesh_generator.generate(
		data.radius_m,
		data.planet_seed,
		data.terrain_noise_scale,
		data.terrain_height_m
	)
	mesh_instance.mesh = mesh

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TRIPLANAR_SHADER
	
	_apply_surface_profile(material, data.surface_profile)
	
	mesh_instance.material_override = material

	collision_shape.shape = mesh.create_trimesh_shape()

	var gravity_multiplier: float = generation_settings.gravity_zone_multiplier if generation_settings else 1.6
	var gravity_shape: SphereShape3D = SphereShape3D.new()
	gravity_shape.radius = data.radius_m * gravity_multiplier
	gravity_collision_shape.shape = gravity_shape

	if not is_moon:
		_spawn_moons()

func _spawn_moons() -> void:
	if planet_data.moons.is_empty() or moon_scene == null:
		return

	for moon_data in planet_data.moons:
		var moon_node: Node3D = moon_scene.instantiate()
		moons_container.add_child(moon_node)
		moon_node.set("is_moon", true)
		moon_node.set("generation_settings", generation_settings)
		moon_node.global_position = moon_data.get_orbit_position(global_position)
		moon_node.call("setup", moon_data)
		moon_nodes.append(moon_node)

func _physics_process(delta: float) -> void:
	if is_moon or planet_data == null:
		return
	for i in range(moon_nodes.size()):
		var moon_data: PlanetData = planet_data.moons[i]
		var moon_node: Node3D = moon_nodes[i]
		if not is_instance_valid(moon_node):
			continue
		moon_data.orbit_angle_rad += moon_data.orbit_speed_rad_s * delta
		moon_node.global_position = moon_data.get_orbit_position(global_position)
		moon_node.rotate_y(moon_data.rotation_speed_rad_s * delta)

func get_gravity_strength() -> float:
	return planet_data.gravity_strength if planet_data else 9.8

func get_radius() -> float:
	return planet_data.radius_m if planet_data else 80.0

func get_gravity_zone_radius() -> float:
	var multiplier: float = generation_settings.gravity_zone_multiplier if generation_settings else 1.6
	return get_radius() * multiplier

func _set_filtered_color_texture(
	material: ShaderMaterial,
	prefix: String,
	texture: Texture2D
) -> void:
	material.set_shader_parameter(prefix + "_linear", texture)
	material.set_shader_parameter(prefix + "_linear_mipmap", texture)
	material.set_shader_parameter(prefix + "_nearest", texture)
	material.set_shader_parameter(prefix + "_nearest_mipmap", texture)

func _set_filtered_data_texture(
	material: ShaderMaterial,
	prefix: String,
	texture: Texture2D
) -> void:
	material.set_shader_parameter(prefix + "_linear", texture)
	material.set_shader_parameter(prefix + "_linear_mipmap", texture)
	material.set_shader_parameter(prefix + "_nearest", texture)
	material.set_shader_parameter(prefix + "_nearest_mipmap", texture)

func _apply_surface_profile(
	material: ShaderMaterial,
	profile: SurfaceProfile
) -> void:
	if profile == null:
		return

	material.set_shader_parameter(
		"use_albedo_texture",
		profile.albedo_texture != null
	)
	material.set_shader_parameter(
		"albedo_texture",
		profile.albedo_texture
	)
	material.set_shader_parameter(
		"albedo_tint",
		profile.albedo_tint
	)

	material.set_shader_parameter(
		"use_normal_map",
		profile.normal_texture != null
	)
	material.set_shader_parameter(
		"normal_texture",
		profile.normal_texture
	)
	material.set_shader_parameter(
		"normal_strength",
		profile.normal_strength
	)

	material.set_shader_parameter(
		"use_roughness_texture",
		profile.roughness_texture != null
	)
	material.set_shader_parameter(
		"roughness_texture",
		profile.roughness_texture
	)
	material.set_shader_parameter(
		"roughness_value",
		profile.roughness_value
	)
	material.set_shader_parameter(
		"roughness_multiplier",
		profile.roughness_multiplier
	)

	material.set_shader_parameter(
		"use_metallic_texture",
		profile.metallic_texture != null
	)
	material.set_shader_parameter(
		"metallic_texture",
		profile.metallic_texture
	)
	material.set_shader_parameter(
		"metallic_value",
		profile.metallic_value
	)
	material.set_shader_parameter(
		"metallic_multiplier",
		profile.metallic_multiplier
	)

	material.set_shader_parameter(
		"use_ao_texture",
		profile.ao_texture != null
	)
	material.set_shader_parameter(
		"ao_texture",
		profile.ao_texture
	)
	material.set_shader_parameter(
		"ao_strength",
		profile.ao_strength
	)

	material.set_shader_parameter(
		"use_height_texture",
		profile.height_texture != null
	)
	material.set_shader_parameter(
		"height_texture",
		profile.height_texture
	)
	material.set_shader_parameter(
		"height_strength",
		profile.height_strength
	)
	material.set_shader_parameter(
		"use_height_parallax",
		profile.use_height_parallax
	)

	material.set_shader_parameter(
		"use_emission_texture",
		profile.emission_texture != null
	)
	material.set_shader_parameter(
		"emission_texture",
		profile.emission_texture
	)
	material.set_shader_parameter(
		"emission_color",
		profile.emission_color
	)
	material.set_shader_parameter(
		"emission_energy",
		profile.emission_energy
	)

	material.set_shader_parameter(
		"triplanar_scale",
		profile.triplanar_scale
	)
	material.set_shader_parameter(
		"blend_sharpness",
		profile.triplanar_blend_sharpness
	)
	material.set_shader_parameter(
		"triplanar_offset",
		profile.triplanar_offset
	)
	
	material.set_shader_parameter(
		"texture_filter_mode",
		int(profile.texture_filter)
	)
	_set_filtered_data_texture(
		material,
		"normal",
		profile.normal_texture
	)

	material.set_shader_parameter(
		"use_normal_map",
		profile.normal_texture != null
	)
	material.set_shader_parameter(
		"normal_strength",
		profile.normal_strength
	)
	_set_filtered_color_texture(
		material,
		"albedo",
		profile.albedo_texture
	)

	_set_filtered_data_texture(
		material,
		"roughness",
		profile.roughness_texture
	)

	_set_filtered_data_texture(
		material,
		"metallic",
		profile.metallic_texture
	)

	_set_filtered_data_texture(
		material,
		"ao",
		profile.ao_texture
	)

	_set_filtered_color_texture(
		material,
		"emission",
		profile.emission_texture
	)

func get_landscape_type() -> String:
	if planet_data == null or planet_data.surface_profile == null:
		return "unknown"
	return planet_data.surface_profile.profile_name

func get_moon_nodes() -> Array[Node3D]:
	return moon_nodes
