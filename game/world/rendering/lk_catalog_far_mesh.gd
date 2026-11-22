class_name LkCatalogFarMesh
extends "res://voxel/planet_far_mesh.gd"

const FarSnapshot = preload("res://game/world/rendering/lk_far_body_snapshot.gd")
const BatchShader = preload("res://game/world/rendering/lk_far_system.gdshader")
const MAX_BODIES: int = 64

var cpu_state_provider: RefCounted
var _far_layout: Dictionary = {}
var _far_active_id: String = ""
var _far_camera: Camera3D
var _far_coordinate_frame: LkCoordinateFrame
var _far_clock
var _far_batch_ready: bool = false
var _far_active_color: Color = Color(0.38, 0.43, 0.48)
# Retained for v1 API compatibility; engine environment now handles active ambient.
var active_ambient_energy: float = 0.18
var sunlight_energy: float = 1.0
var last_stats: Dictionary = {}
var _surface_source: StandardMaterial3D
var _surface_original_shading: int = BaseMaterial3D.SHADING_MODE_PER_PIXEL
var _surface_albedo_debug: bool = false


func configure(layout: Dictionary, active_id: String, camera: Camera3D, coordinate_frame: LkCoordinateFrame, clock, active_color: Color) -> void:
	_far_layout = layout
	_far_active_id = active_id
	_far_camera = camera
	_far_coordinate_frame = coordinate_frame
	_far_clock = clock
	_far_active_color = active_color


func bind_surface_material(material: StandardMaterial3D) -> void:
	_surface_source = material
	_surface_original_shading = material.shading_mode
	_far_active_color = material.albedo_color


func set_albedo_debug(enabled: bool) -> void:
	_surface_albedo_debug = enabled
	if is_instance_valid(_surface_source):
		_surface_source.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if enabled else _surface_original_shading


func is_albedo_debug() -> bool:
	return _surface_albedo_debug


static func pack_linear_color(color: Color, emissive: bool) -> Vector4:
	var linear: Color = color.srgb_to_linear()
	return Vector4(linear.r, linear.g, linear.b, 1.0 if emissive else 0.0)


func _ready() -> void:
	super._ready()
	_horizon_material.shader = BatchShader
	material_override = _horizon_material
	_far_batch_ready = true
	_sync_camera()


func _build_heightmap() -> ImageTexture:
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RF)
	image.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(image)


func _make_depth_material() -> ShaderMaterial:
	return ShaderMaterial.new()


func _attach_terrain_blend() -> void:
	pass


func _unhandled_key_input(_event: InputEvent) -> void:
	pass


func _color_for(record: Dictionary) -> Color:
	if record["active"]:
		return _surface_source.albedo_color if is_instance_valid(_surface_source) else _far_active_color
	if record["star"]:
		return Color(1.0, 0.92, 0.78)
	match String(record["family"]):
		"gas_giant": return Color(0.66, 0.52, 0.36)
		"icy": return Color(0.65, 0.73, 0.8)
		"solid_moon": return Color(0.47, 0.48, 0.5)
	return Color(0.43, 0.39, 0.34)


func _sync_camera() -> void:
	if not _far_batch_ready or _far_layout.is_empty() or not is_instance_valid(_far_camera):
		visible = false
		return
	var observer: LkPosition64 = _far_coordinate_frame.to_absolute(_far_camera.global_position)
	var snapshot_epoch: float = _far_clock.now_s()
	var shared_states: Dictionary = {}
	if cpu_state_provider != null:
		shared_states = cpu_state_provider.call("get_states", snapshot_epoch)
	var records: Array[Dictionary] = FarSnapshot.build(_far_layout, _far_active_id, observer, snapshot_epoch, shared_states)
	var pixels: float = maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	var min_angle: float = deg_to_rad(_far_camera.fov) / pixels * 0.25
	last_stats = FarSnapshot.select(records, -_far_camera.global_basis.z, MAX_BODIES, min_angle)
	var chosen: Array = last_stats["bodies"]
	if chosen.is_empty() or not chosen[0]["active"]:
		visible = false
		return
	var spheres: PackedVector4Array = []
	var scales: PackedFloat32Array = []
	var colors: PackedVector4Array = []
	var suns: PackedVector3Array = []
	spheres.resize(MAX_BODIES)
	scales.resize(MAX_BODIES)
	colors.resize(MAX_BODIES)
	suns.resize(MAX_BODIES)
	for i: int in range(chosen.size()):
		var record: Dictionary = chosen[i]
		var d: Array = record["direction"]
		var sun: Array = record["sun_direction"]
		spheres[i] = Vector4(d[0], d[1], d[2], record["radius_relative"])
		scales[i] = record["distance_m"]
		colors[i] = pack_linear_color(_color_for(record), record["star"])
		suns[i] = Vector3(sun[0], sun[1], sun[2])
	_horizon_material.set_shader_parameter("body_count", chosen.size())
	_horizon_material.set_shader_parameter("body_spheres", spheres)
	_horizon_material.set_shader_parameter("body_scales", scales)
	_horizon_material.set_shader_parameter("body_colors", colors)
	_horizon_material.set_shader_parameter("body_suns", suns)
	_horizon_material.set_shader_parameter("active_inside", chosen[0]["inside"])
	_horizon_material.set_shader_parameter("sun_energy", sunlight_energy)
	_horizon_material.set_shader_parameter("debug_active_albedo", _surface_albedo_debug)
	if is_instance_valid(_surface_source):
		_horizon_material.set_shader_parameter("surface_roughness", _surface_source.roughness)
		_horizon_material.set_shader_parameter("surface_metallic", _surface_source.metallic)
		_horizon_material.set_shader_parameter("surface_specular", _surface_source.metallic_specular)
	global_transform = _far_camera.global_transform
	global_position -= _far_camera.global_basis.z * maxf(_far_camera.near * 2.0, 2.0)
	visible = true

# FARMESH_CPU3_PROVIDER_V1: optional exact-epoch provider, null by default.
