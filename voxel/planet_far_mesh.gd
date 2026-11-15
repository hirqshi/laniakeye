class_name PlanetFarMesh
extends MeshInstance3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0
@export_range(256, 2048, 256) var heightmap_width: int = 1024

var _horizon_material: ShaderMaterial


func _ready() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true
	extra_cull_margin = 16.0
	_horizon_material = ShaderMaterial.new()
	_horizon_material.shader = preload("res://voxel/planet_horizon.gdshader")
	_horizon_material.set_shader_parameter("height_map", _build_heightmap())
	material_override = _horizon_material
	process_priority = 100
	_sync_camera()


func _build_heightmap() -> ImageTexture:
	var width: int = maxi(heightmap_width, 256)
	var height: int = width / 2
	var image: Image = Image.create(width, height, false, Image.FORMAT_RF)
	var generator: PlanetVoxelGenerator = PlanetVoxelGenerator.new()
	generator.planet_radius_m = planet_radius_m
	generator.terrain_height_m = terrain_height_m
	generator.noise_seed = noise_seed
	for y: int in range(height):
		var phi: float = (float(y) + 0.5) / float(height) * PI
		for x: int in range(width):
			var theta: float = (float(x) + 0.5) / float(width) * TAU
			var direction: Vector3 = Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var elevation: float = generator._get_surface_radius(direction) - planet_radius_m
			image.set_pixel(x, y, Color(elevation, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(image)


func _process(_delta: float) -> void:
	_sync_camera()


func _sync_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		visible = false
		return
	var planet: Node3D = get_parent() as Node3D
	if planet == null:
		visible = false
		return
	visible = true
	var center: Vector3 = planet.global_position
	var eye: Vector3 = camera.global_position
	var dx: float = float(center.x) - float(eye.x)
	var dy: float = float(center.y) - float(eye.y)
	var dz: float = float(center.z) - float(eye.z)
	var distance_m: float = sqrt(dx * dx + dy * dy + dz * dz)
	var coordinate_scale: float = maxf(distance_m, maxf(planet_radius_m, 1.0))
	_horizon_material.set_shader_parameter("center_relative", Vector3(dx / coordinate_scale, dy / coordinate_scale, dz / coordinate_scale))
	_horizon_material.set_shader_parameter("radius_relative", planet_radius_m / coordinate_scale)
	_horizon_material.set_shader_parameter("height_limit_relative", absf(terrain_height_m) / coordinate_scale)
	_horizon_material.set_shader_parameter("meters_to_relative", 1.0 / coordinate_scale)
	_horizon_material.set_shader_parameter("pixel_angle", deg_to_rad(camera.fov) / maxf(float(get_viewport().get_visible_rect().size.y), 1.0))
	global_transform = camera.global_transform
	global_position -= camera.global_basis.z * maxf(camera.near * 2.0, 2.0)
