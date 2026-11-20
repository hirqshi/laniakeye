class_name LkFlightVisualBridge
extends Node3D

const FlightShader = preload("res://world/rendering/lk_far_system_flight.gdshader")
const LightMath = preload("res://world/runtime/lk_stellar_lighting.gd")
const FAR_LAYER: int = 1 << 19

var _root: Node3D
var _far: MeshInstance3D
var _surface_sun: DirectionalLight3D
var _camera: Camera3D
var _disk_sun: DirectionalLight3D
var _material: ShaderMaterial
var _old_shader: Shader
var _old_far_layers: int
var _old_sun_mask: int
var _old_camera_mask: int
var _bound: bool = false

func configure(root: Node3D, far_mesh: MeshInstance3D, surface_sun: DirectionalLight3D, camera: Camera3D) -> bool:
	_material = far_mesh.material_override as ShaderMaterial
	if _material == null:
		return false
	_root = root
	_far = far_mesh
	_surface_sun = surface_sun
	_camera = camera
	_old_shader = _material.shader
	_old_far_layers = _far.layers
	_old_sun_mask = _surface_sun.light_cull_mask
	_old_camera_mask = _camera.cull_mask
	_material.shader = FlightShader
	_far.layers = FAR_LAYER
	_camera.cull_mask |= FAR_LAYER
	_surface_sun.light_cull_mask = _old_sun_mask & ~FAR_LAYER
	_disk_sun = DirectionalLight3D.new()
	_disk_sun.name = "ObserverIndependentDiskSun"
	_disk_sun.light_cull_mask = FAR_LAYER
	_disk_sun.shadow_enabled = false
	_disk_sun.light_energy = 0.0
	add_child(_disk_sun)
	process_priority = 120 # After FarMesh100 and star sprites110.
	_bound = true
	_process(0.0)
	return true

func _process(_delta: float) -> void:
	if not _bound or not is_instance_valid(_far) or not is_instance_valid(_surface_sun) or not is_instance_valid(_disk_sun):
		return
	var environment: Environment = _root.get("_stellar_environment") as Environment
	if environment == null:
		_disk_sun.light_energy = 0.0
		return
	var ambient: Color = environment.ambient_light_color.srgb_to_linear()
	_material.set_shader_parameter("active_ambient_linear", Vector3(ambient.r, ambient.g, ambient.b))
	_material.set_shader_parameter("active_day_ambient", maxf(float(_root.get("day_ambient_energy")), 0.0))
	_material.set_shader_parameter("active_night_ambient", maxf(float(_root.get("night_ambient_energy")), 0.0))
	_material.set_shader_parameter("active_horizon_fade_sine", 0.02)
	var suns: Variant = _material.get_shader_parameter("body_suns")
	if suns is PackedVector3Array and suns.size() > 0:
		var sun: Vector3 = suns[0]
		if sun.length_squared() > 0.5:
			_disk_sun.global_basis = LightMath.directional_basis([sun.x, sun.y, sun.z])
			_disk_sun.light_color = _surface_sun.light_color
			_disk_sun.light_specular = _surface_sun.light_specular
			# Deliberately NOT _surface_sun.light_energy (observer horizon masked).
			_disk_sun.light_energy = maxf(float(_root.get("stellar_light_energy")), 0.0)
			return
	_disk_sun.light_energy = 0.0

func _exit_tree() -> void:
	if not _bound:
		return
	if is_instance_valid(_far):
		_far.layers = _old_far_layers
	if is_instance_valid(_material):
		_material.shader = _old_shader
	if is_instance_valid(_surface_sun):
		_surface_sun.light_cull_mask = _old_sun_mask
	if is_instance_valid(_camera):
		_camera.cull_mask = _old_camera_mask
	_bound = false
