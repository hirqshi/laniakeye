extends SceneTree

const Bridge = preload("res://world/rendering/lk_surface_shell_bridge.gd")
const Shell = preload("res://world/rendering/lk_surface_shell_math.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SurfaceShellCache: FAIL " + label)

func _verify(bridge, far: ShaderMaterial, stars: ShaderMaterial, distance: float, radius: float) -> void:
	var expected: Dictionary = Shell.coefficients(distance, radius)
	bridge._update_shell(distance, radius)
	_check(bridge._shell_state == expected, "exact coefficient parity")
	_check(bridge.signed_height_m == expected["height_m"], "signed height current")
	for material: ShaderMaterial in [far, stars]:
		_check(material.get_shader_parameter("active_shell_valid") == expected["valid"], "valid uploaded")
		_check(material.get_shader_parameter("active_shell_stable") == expected["stable"], "stable uploaded")
		_check(is_equal_approx(float(material.get_shader_parameter("active_shell_c")), float(expected["c"])), "coefficient uploaded")

func _initialize() -> void:
	var bridge = Bridge.new()
	var far: MeshInstance3D = MeshInstance3D.new()
	var stars: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var far_material: ShaderMaterial = ShaderMaterial.new()
	var stars_material: ShaderMaterial = ShaderMaterial.new()
	var old_far: Shader = Shader.new()
	var old_stars: Shader = Shader.new()
	far_material.shader = old_far
	stars_material.shader = old_stars
	far.material_override = far_material
	stars.material_override = stars_material
	# No camera: configure binds native materials without requiring a world scene.
	_check(bridge.configure(null, null, far, stars), "configure")
	_check(not bridge.coefficient_cache_stats()["cached"], "configure invalidates")
	_verify(bridge, far_material, stars_material, 1100.0, 1000.0)
	_check(bridge.coefficient_cache_stats()["evaluations"] == 1, "first calculation")
	_verify(bridge, far_material, stars_material, 1100.0, 1000.0)
	_check(bridge.coefficient_cache_stats()["evaluations"] == 1, "unchanged inputs reuse")
	# Corrupt a uniform, not the cache: unchanged inputs must still synchronize.
	far_material.set_shader_parameter("active_shell_valid", false)
	_verify(bridge, far_material, stars_material, 1100.0, 1000.0)
	_check(bridge.coefficient_cache_stats()["evaluations"] == 1, "upload without recomputing")
	_verify(bridge, far_material, stars_material, 1100.000001, 1000.0)
	_check(bridge.coefficient_cache_stats()["evaluations"] == 2, "no distance tolerance")
	_verify(bridge, far_material, stars_material, 1100.000001, 999.0)
	_check(bridge.coefficient_cache_stats()["evaluations"] == 3, "radius change invalidates")
	for distance: float in [999.0, 1000.0, 1000.000001, 1250.0, 1250.000001, 2000.0, 0.0, -1.0, INF, NAN]:
		_verify(bridge, far_material, stars_material, distance, 1000.0)
	for radius: float in [0.0, -1.0, INF, NAN, 1000.0]:
		_verify(bridge, far_material, stars_material, 1100.0, radius)
	_verify(bridge, far_material, stars_material, 1100.0, 1000.0)
	var evaluations: int = bridge.coefficient_cache_stats()["evaluations"]
	bridge._exit_tree()
	_check(not bridge.coefficient_cache_stats()["cached"], "detach invalidates")
	_check(far_material.shader == old_far and stars_material.shader == old_stars, "original shaders restored")
	_check(bridge.configure(null, null, far, stars), "reconfigure")
	_verify(bridge, far_material, stars_material, 1100.0, 1000.0)
	_check(bridge.coefficient_cache_stats()["evaluations"] == evaluations + 1, "rebind recomputes identical inputs")
	bridge._exit_tree()
	bridge.free()
	far.free()
	stars.free()
	if _failures == 0:
		print("SurfaceShellCache: PASS exact inputs, boundary parity, invalid inputs, native material uniforms, detach/rebind")
	quit(0 if _failures == 0 else 1)
