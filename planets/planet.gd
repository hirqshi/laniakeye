@tool
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
const RING_SHADER: Shader = preload("res://shaders/ring.gdshader")
const ATMOSPHERE_SHADER: Shader = preload("res://shaders/atmosphere.gdshader")
const SPHERE_WATER_SHADER: Shader = preload("res://shaders/sphere_water.gdshader")
const ATMOSPHERE_SPHERE_RINGS: int = 32
const ATMOSPHERE_SPHERE_RADIAL_SEGMENTS: int = 32

@export var mesh_instance: MeshInstance3D
@export var ring_mesh_instance: MeshInstance3D
@export var collision_shape: CollisionShape3D
@export var gravity_area: Area3D
@export var gravity_collision_shape: CollisionShape3D
@export var moons_container: Node3D
@export var atmosphere_mesh_instance: MeshInstance3D
@export var water_mesh_instance: MeshInstance3D

@export var moon_scene: PackedScene
@export var is_moon: bool = false
@export var generation_settings: GenerationSettings

@export var star_node: Node3D

@export var vegetation_spawner: PlanetVegetationSpawner
@export var creature_spawner: CreatureSpawner

var planet_data: PlanetData
var moon_nodes: Array[Node3D] = []
var mesh_generator: PlanetMeshGenerator = PlanetMeshGenerator.new()
var ring_mesh_generator: RingMeshGenerator = RingMeshGenerator.new()
var water_mesh_generator: WaterMeshGenerator = WaterMeshGenerator.new()

var sea_level_radius_m: float = 0.0
var has_ocean: bool = false


func _process(_delta: float) -> void:
	if planet_data == null:
		return

	var light_dir: Vector3 = Vector3.RIGHT
	var has_star: bool = star_node != null and is_instance_valid(star_node)
	if has_star:
		light_dir = (star_node.global_position - global_position).normalized()

	if ring_mesh_instance != null and ring_mesh_instance.visible:
		var ring_material: ShaderMaterial = ring_mesh_instance.material_override as ShaderMaterial
		if ring_material != null:
			ring_material.set_shader_parameter("planet_world_position", global_position)
			ring_material.set_shader_parameter("planet_radius_m", planet_data.radius_m)

	if atmosphere_mesh_instance != null and atmosphere_mesh_instance.visible:
		var atmosphere_material: ShaderMaterial = atmosphere_mesh_instance.material_override as ShaderMaterial
		if atmosphere_material != null:
			atmosphere_material.set_shader_parameter("planet_center_world", global_position)
			if has_star:
				atmosphere_material.set_shader_parameter("light_direction", light_dir)

	if mesh_instance != null:
		var surface_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
		if surface_material != null and has_star:
			surface_material.set_shader_parameter("atmosphere_light_direction", light_dir)

func setup(data: PlanetData) -> void:
	planet_data = data

	var noise_type: int = data.surface_profile.get("terrain_noise_type") if data.surface_profile else 0

	var mesh: ArrayMesh = mesh_generator.generate(
		data.radius_m,
		data.planet_seed,
		data.terrain_noise_scale,
		data.terrain_height_m,
		noise_type,
		data.surface_profile
	)
	mesh_instance.mesh = mesh

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TRIPLANAR_SHADER

	_apply_surface_profile(material, data.surface_profile, data.albedo_color)

	mesh_instance.material_override = material

	collision_shape.shape = mesh.create_trimesh_shape()

	var gravity_multiplier: float = generation_settings.gravity_zone_multiplier if generation_settings else 1.6
	var gravity_shape: SphereShape3D = SphereShape3D.new()
	gravity_shape.radius = data.radius_m * gravity_multiplier
	gravity_collision_shape.shape = gravity_shape

	_setup_atmosphere(data)
	_setup_rings(data)
	_setup_ocean(data)
	_setup_vegetation(data)
	_setup_creatures(data)

	if not is_moon:
		_spawn_moons()

func _setup_creatures(data: PlanetData) -> void:
	if is_moon:
		return

	if creature_spawner == null:
		push_warning("Planet: 'Creature Spawner' export is not assigned")
		return

	creature_spawner.setup(data)

func _setup_atmosphere(data: PlanetData) -> void:
	if atmosphere_mesh_instance == null:
		return

	var profile: Resource = data.surface_profile
	if profile == null or not profile.get("has_atmosphere"):
		atmosphere_mesh_instance.visible = false
		return

	var sphere_mesh: SphereMesh = atmosphere_mesh_instance.mesh as SphereMesh
	if sphere_mesh == null:
		sphere_mesh = SphereMesh.new()
		sphere_mesh.rings = ATMOSPHERE_SPHERE_RINGS
		sphere_mesh.radial_segments = ATMOSPHERE_SPHERE_RADIAL_SEGMENTS
		atmosphere_mesh_instance.mesh = sphere_mesh

	var outer_height_m: float = data.radius_m * float(profile.get("atmosphere_outer_height_ratio"))
	var inner_height_m: float = data.radius_m * float(profile.get("atmosphere_inner_height_ratio"))
	var outer_radius_m: float = data.radius_m + outer_height_m
	sphere_mesh.radius = outer_radius_m
	sphere_mesh.height = outer_radius_m * 2.0

	var material: ShaderMaterial = atmosphere_mesh_instance.material_override as ShaderMaterial
	if material == null or material.shader != ATMOSPHERE_SHADER:
		material = ShaderMaterial.new()
		material.shader = ATMOSPHERE_SHADER
		atmosphere_mesh_instance.material_override = material

	material.set_shader_parameter("planet_radius_m", data.radius_m)
	material.set_shader_parameter("outer_shell_height_m", outer_height_m)
	material.set_shader_parameter("inner_haze_height_m", inner_height_m)
	material.set_shader_parameter("rayleigh_coefficient", profile.get("atmosphere_rayleigh_color"))
	material.set_shader_parameter("mie_coefficient", profile.get("atmosphere_mie_color"))
	material.set_shader_parameter("intensity", profile.get("atmosphere_intensity"))
	material.set_shader_parameter("atmosphere_density", profile.get("atmosphere_density"))
	material.set_shader_parameter("outer_edge_softness", profile.get("atmosphere_outer_edge_softness"))
	material.set_shader_parameter("day_color", profile.get("atmosphere_day_color"))
	material.set_shader_parameter("sunset_color", profile.get("atmosphere_sunset_color"))
	material.set_shader_parameter("terminator_width", profile.get("atmosphere_terminator_width"))
	material.set_shader_parameter("sunset_strength", profile.get("atmosphere_sunset_strength"))

	atmosphere_mesh_instance.visible = true

	var surface_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	if surface_material != null:
		surface_material.set_shader_parameter("has_atmosphere_tint", true)
		surface_material.set_shader_parameter("atmosphere_tint_color", profile.get("atmosphere_rayleigh_color"))
		surface_material.set_shader_parameter("atmosphere_tint_strength", profile.get("atmosphere_surface_tint_strength"))


func _setup_rings(data: PlanetData) -> void:
	if ring_mesh_instance == null:
		return

	var profile: Resource = data.surface_profile
	if profile == null or not profile.get("allow_rings"):
		ring_mesh_instance.visible = false
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = data.planet_seed + 555111

	if not profile.call("should_generate_rings", rng):
		ring_mesh_instance.visible = false
		return

	var inner_ratio: float = rng.randf_range(profile.get("ring_inner_radius_ratio_min"), profile.get("ring_inner_radius_ratio_max"))
	var outer_ratio: float = rng.randf_range(profile.get("ring_outer_radius_ratio_min"), profile.get("ring_outer_radius_ratio_max"))

	var inner_radius_m: float = data.radius_m * inner_ratio
	var outer_radius_m: float = data.radius_m * outer_ratio

	var ring_mesh: ArrayMesh = ring_mesh_generator.generate(inner_radius_m, outer_radius_m)
	ring_mesh_instance.mesh = ring_mesh

	var material: ShaderMaterial = ring_mesh_instance.material_override as ShaderMaterial
	if material == null or material.shader != RING_SHADER:
		material = ShaderMaterial.new()
		material.shader = RING_SHADER
		ring_mesh_instance.material_override = material

	material.set_shader_parameter("ring_gradient_texture", _gradient_to_texture(profile.get("ring_gradient")))

	var tilt_max_rad: float = profile.get("ring_tilt_max_rad")
	ring_mesh_instance.rotation = Vector3(
		rng.randf_range(-tilt_max_rad, tilt_max_rad),
		0.0,
		rng.randf_range(-tilt_max_rad, tilt_max_rad)
	)

	ring_mesh_instance.visible = true


func _setup_ocean(data: PlanetData) -> void:
	has_ocean = false
	sea_level_radius_m = 0.0

	if is_moon:
		if water_mesh_instance != null:
			water_mesh_instance.visible = false
		return

	if water_mesh_instance == null:
		return

	var profile: Resource = data.surface_profile
	if profile == null or not profile.get("has_ocean"):
		water_mesh_instance.visible = false
		return

	sea_level_radius_m = data.radius_m * float(profile.get("sea_level_radius_ratio"))

	water_mesh_instance.mesh = water_mesh_generator.generate_sphere(sea_level_radius_m)

	var material: ShaderMaterial = water_mesh_instance.material_override as ShaderMaterial
	if material == null or material.shader != SPHERE_WATER_SHADER:
		material = ShaderMaterial.new()
		material.shader = SPHERE_WATER_SHADER
		water_mesh_instance.material_override = material

	material.set_shader_parameter("sky_color", profile.get("water_sky_color"))
	material.set_shader_parameter("surface_albedo", profile.get("water_surface_color"))
	material.set_shader_parameter("high_color", profile.get("water_high_color"))
	material.set_shader_parameter("low_color", profile.get("water_low_color"))
	material.set_shader_parameter("transmit_color", profile.get("water_transmit_color"))
	material.set_shader_parameter("depth_fade_distance", sea_level_radius_m * float(profile.get("depth_fade_distance_ratio")))
	
	water_mesh_instance.visible = true

	has_ocean = true

func _setup_vegetation(data: PlanetData) -> void:
	if is_moon:
		return

	if vegetation_spawner == null:
		push_warning("Planet: 'Vegetation Spawner' export is not assigned")
		return

	vegetation_spawner.setup(data)

func regenerate_vegetation_for_preview() -> void:
	if is_moon:
		return

	if vegetation_spawner == null:
		push_warning("Planet: 'Vegetation Spawner' export is not assigned")
		return

	if planet_data == null:
		push_warning("Planet: cannot regenerate preview vegetation before setup(data)")
		return

	vegetation_spawner.regenerate_for_preview(planet_data)

func regenerate_creatures_for_preview() -> void:
	if is_moon:
		return

	if creature_spawner == null:
		push_warning("Planet: 'Creature Spawner' export is not assigned")
		return

	if planet_data == null:
		push_warning("Planet: cannot regenerate preview creatures before setup(data)")
		return

	creature_spawner.regenerate_for_preview(planet_data)

func _gradient_to_texture(gradient: Gradient) -> GradientTexture1D:
	if gradient == null:
		return null
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	return texture


func _spawn_moons() -> void:
	if planet_data.moons.is_empty() or moon_scene == null:
		return

	for moon_data in planet_data.moons:
		var moon_node: Node3D = moon_scene.instantiate()
		moons_container.add_child(moon_node)
		moon_node.set("is_moon", true)
		moon_node.set("generation_settings", generation_settings)
		moon_node.set("star_node", star_node)
		moon_node.global_position = moon_data.get_orbit_position(global_position)
		moon_node.call("setup", moon_data)
		moon_nodes.append(moon_node)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
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

func get_ambient_loop() -> AudioStream:
	if planet_data == null or planet_data.surface_profile == null:
		return null
	var ambient: Variant = planet_data.surface_profile.get("ambient_loop")
	return ambient as AudioStream
	

func get_gravity_zone_radius() -> float:
	var multiplier: float = generation_settings.gravity_zone_multiplier if generation_settings else 1.6
	return get_radius() * multiplier


## returns true if the given world-space distance from this planet's
## center is below the sea level - used by the player controller to
## apply the underwater gravity/speed multiplier and screen tint,
## without needing a dedicated Area3D trigger.
func is_point_underwater(world_position: Vector3) -> bool:
	if not has_ocean:
		return false
	return global_position.distance_to(world_position) < sea_level_radius_m


func get_underwater_gravity_multiplier() -> float:
	if planet_data == null or planet_data.surface_profile == null:
		return 1.0
	return planet_data.surface_profile.get("underwater_gravity_multiplier")


func get_underwater_speed_multiplier() -> float:
	if planet_data == null or planet_data.surface_profile == null:
		return 1.0
	return planet_data.surface_profile.get("underwater_speed_multiplier")


func get_water_gradient() -> Gradient:
	if planet_data == null or planet_data.surface_profile == null:
		return null
	return planet_data.surface_profile.get("water_gradient")


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
	profile: Resource,
	albedo_color: Color
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
		albedo_color
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

	# atmosphere surface tint - only turned on here if the profile
	# actually has an atmosphere; _setup_atmosphere() re-drives these
	# same params (it runs after this function during setup()), this
	# early pass just makes sure has_atmosphere_tint defaults correctly
	# even if _setup_atmosphere bails early for any reason.
	material.set_shader_parameter(
		"has_atmosphere_tint",
		profile.get("has_atmosphere") if profile.get("has_atmosphere") != null else false
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


func get_display_name() -> String:
	return planet_data.display_name if planet_data else "???"
