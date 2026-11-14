class_name PlanetFarMesh
extends MeshInstance3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0

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
	material_override = _horizon_material
	process_priority = 100
	_sync_camera()


func _process(_delta: float) -> void:
	_sync_camera()


func _sync_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		visible = false
		return
	visible = true
	var planet: Node3D = get_parent() as Node3D
	if planet == null:
		visible = false
		return
	var center: Vector3 = planet.global_position
	var eye: Vector3 = camera.global_position
	var dx: float = float(center.x) - float(eye.x)
	var dy: float = float(center.y) - float(eye.y)
	var dz: float = float(center.z) - float(eye.z)
	var distance_m: float = sqrt(dx * dx + dy * dy + dz * dz)
	var coordinate_scale: float = maxf(distance_m, maxf(planet_radius_m, 1.0))
	var proxy_radius: float = maxf(planet_radius_m - absf(terrain_height_m) - 1.0, 1.0)
	_horizon_material.set_shader_parameter("center_relative", Vector3(
		dx / coordinate_scale, dy / coordinate_scale, dz / coordinate_scale
	))
	_horizon_material.set_shader_parameter("radius_relative", proxy_radius / coordinate_scale)
	global_transform = camera.global_transform
	global_position -= camera.global_basis.z * maxf(camera.near * 2.0, 2.0)
