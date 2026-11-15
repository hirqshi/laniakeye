class_name PlanetFarMesh
extends MeshInstance3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0
@export_range(256, 2048, 256) var heightmap_width: int = 1024
@export_range(0.1, 0.95, 0.05) var blend_start_fraction: float = 0.6
@export_range(0.1, 1.0, 0.05) var blend_coverage_margin: float = 0.8
@export var blend_enabled: bool = true

var _horizon_material: ShaderMaterial
var _blend_material: ShaderMaterial


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
	call_deferred("_attach_terrain_blend")
	_sync_camera()


func _attach_terrain_blend() -> void:
	var planet: Node = get_parent()
	if not planet.has_method("get_terrain"):
		return
	var terrain: Node = planet.call("get_terrain") as Node
	if terrain == null:
		return
	var terrain_material: Material = terrain.get("material") as Material
	if terrain_material == null or terrain_material.next_pass != null:
		push_warning("PlanetFarMesh: no free terrain next_pass; blend not attached")
		return
	var source: String = _horizon_material.shader.code
	var depth_guard: String = "if (texture(scene_depth, SCREEN_UV).r > 0.0) { discard; }"
	var quad_vertex: String = "POSITION = vec4(VERTEX.xy, 1.0, 1.0);"
	if not source.contains(depth_guard) or not source.contains(quad_vertex) or not source.contains("ALPHA = 1.0;"):
		push_error("PlanetFarMesh: horizon shader changed; refusing unsafe blend variant")
		return
	source = source.replace("shader_type spatial;", "shader_type spatial;\nuniform float blend_start_m = 9600.0;\nuniform float blend_end_m = 16000.0;\nuniform bool blend_enabled = true;")
	source = source.replace(quad_vertex, "")
	source = source.replace(depth_guard, """if (!blend_enabled) { discard; }
	float near_depth = texture(scene_depth, SCREEN_UV).r;
	if (near_depth <= 0.0) { discard; }
	vec4 near_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, near_depth, 1.0);
	vec3 near_view = near_point.xyz / near_point.w;
	// Manual visible-surface check: preserve objects in front of terrain.
	if (abs(near_view.z - VERTEX.z) > max(0.05, abs(near_view.z) * 0.000001)) { discard; }
	float weight = clamp((length(near_view) - blend_start_m) / max(blend_end_m - blend_start_m, 1.0), 0.0, 1.0);
	weight = weight * weight * weight * (weight * (weight * 6.0 - 15.0) + 10.0);
	if (weight <= 0.0001) { discard; }""")
	source = source.replace("ALPHA = 1.0;", "ALPHA = weight;")
	var blend_shader: Shader = Shader.new()
	blend_shader.code = source
	_blend_material = ShaderMaterial.new()
	_blend_material.shader = blend_shader
	_blend_material.render_priority = 1
	_blend_material.set_shader_parameter("height_map", _horizon_material.get_shader_parameter("height_map"))
	terrain_material.next_pass = _blend_material
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


func _set_parameter(parameter_name: StringName, value: Variant) -> void:
	_horizon_material.set_shader_parameter(parameter_name, value)
	if _blend_material != null:
		_blend_material.set_shader_parameter(parameter_name, value)


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
	_set_parameter("center_relative", Vector3(dx / coordinate_scale, dy / coordinate_scale, dz / coordinate_scale))
	_set_parameter("radius_relative", planet_radius_m / coordinate_scale)
	_set_parameter("height_limit_relative", absf(terrain_height_m) / coordinate_scale)
	_set_parameter("meters_to_relative", 1.0 / coordinate_scale)
	_set_parameter("pixel_angle", deg_to_rad(camera.fov) / maxf(float(get_viewport().get_visible_rect().size.y), 1.0))
	if _blend_material != null:
		var coverage_m: float = maxf(float(planet.get("view_distance_m")), 1.0)
		var blend_end: float = maxf(minf(camera.far, coverage_m) * blend_coverage_margin, 1.0)
		_blend_material.set_shader_parameter("blend_start_m", blend_end * blend_start_fraction)
		_blend_material.set_shader_parameter("blend_end_m", blend_end)
		_blend_material.set_shader_parameter("blend_enabled", blend_enabled)
	global_transform = camera.global_transform
	global_position -= camera.global_basis.z * maxf(camera.near * 2.0, 2.0)
