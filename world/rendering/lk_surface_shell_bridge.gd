class_name LkSurfaceShellBridge
extends Node3D

const Shell = preload("res://world/rendering/lk_surface_shell_math.gd")
const FarShader = preload("res://world/rendering/lk_far_system_surface_shell.gdshader")
const StarsShader = preload("res://world/rendering/lk_star_sprites_surface_shell.gdshader")
var _root: Node3D
var _camera: Camera3D
var _far_material: ShaderMaterial
var _stars_material: ShaderMaterial
var _old_far: Shader
var _old_stars: Shader
var _bound: bool = false
var signed_height_m: float = 0.0
var _shell_cached: bool = false
var _shell_distance: float = NAN
var _shell_radius: float = NAN
var _shell_state: Dictionary = {}
var _shell_evaluations: int = 0

func configure(root: Node3D, camera: Camera3D, far: MeshInstance3D, stars: MultiMeshInstance3D) -> bool:
	_shell_cached = false
	_shell_state = {}
	_far_material = far.material_override as ShaderMaterial
	_stars_material = stars.material_override as ShaderMaterial
	if _far_material == null or _stars_material == null:
		return false
	_root = root
	_camera = camera
	_old_far = _far_material.shader
	_old_stars = _stars_material.shader
	_far_material.shader = FarShader
	_stars_material.shader = StarsShader
	process_priority = 130 # Far100, stars110, daylight bridge120, shell130.
	_bound = true
	_process(0.0)
	return true

func coefficient_cache_stats() -> Dictionary:
	return {"evaluations": _shell_evaluations, "cached": _shell_cached}

# Only coefficient calculation is cached. Upload on every call so material
# synchronization remains unchanged. Exact inputs: no altitude quantization.
func _update_shell(distance: float, radius: float) -> void:
	if not _shell_cached or distance != _shell_distance or radius != _shell_radius:
		_shell_state = Shell.coefficients(distance, radius)
		_shell_distance = distance
		_shell_radius = radius
		_shell_cached = true
		_shell_evaluations += 1
	signed_height_m = _shell_state["height_m"]
	for material: ShaderMaterial in [_far_material, _stars_material]:
		material.set_shader_parameter("active_shell_valid", _shell_state["valid"])
		material.set_shader_parameter("active_shell_stable", _shell_state["stable"])
		material.set_shader_parameter("active_shell_c", _shell_state["c"])

func _process(_delta: float) -> void:
	if not _bound or not is_instance_valid(_camera):
		return
	var frame: LkCoordinateFrame = _root.get("_frame")
	var context: Dictionary = _root.get("_context")
	if frame == null or context.is_empty():
		return
	var observer: LkPosition64 = frame.to_absolute(_camera.global_position)
	_update_shell(observer.length(), float(context["body"]["radius_m"]))

func _exit_tree() -> void:
	_shell_cached = false
	_shell_state = {}
	if not _bound:
		return
	if is_instance_valid(_far_material):
		_far_material.shader = _old_far
	if is_instance_valid(_stars_material):
		_stars_material.shader = _old_stars
	_bound = false
