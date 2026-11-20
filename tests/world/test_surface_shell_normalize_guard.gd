extends SceneTree

const PATH: String = "res://world/rendering/lk_far_system_surface_shell.gdshader"
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SurfaceShellNormalizeGuard: FAIL " + label)

func _diffuse(normal: Vector3, sun: Vector3) -> float:
	if sun.dot(sun) > 0.0:
		return maxf(normal.dot(sun.normalized()), 0.0)
	return 0.0

func _initialize() -> void:
	var source: String = FileAccess.get_file_as_string(PATH)
	_check(not source.is_empty(), "shader exists")
	var normal_guard: int = source.find("if (!(dot(normal_delta, normal_delta) > 0.0)) { discard; }")
	var normal_use: int = source.find("vec3 normal_system = normalize(normal_delta);")
	_check(normal_guard >= 0 and normal_use > normal_guard, "normal guard precedes normalize")
	_check(source.contains("float solar_altitude = -1.0;\n\t\tif (dot(body_suns[0], body_suns[0]) > 0.0) {\n\t\t\tsolar_altitude = dot(normal_system, normalize(body_suns[0]));"), "active sun normalization guarded")
	_check(source.contains("float diffuse = 0.0;\n\t\tif (dot(body_suns[winner], body_suns[winner]) > 0.0) {\n\t\t\tdiffuse = max(dot(normal_system, normalize(body_suns[winner])), 0.0);"), "remote sun normalization guarded")
	_check(source.contains("if (!active_shell_valid || along <= 0.0) { continue; }"), "active outside-entry contract retained")
	_check(source.contains("if (texture(scene_depth, SCREEN_UV).r > 0.0) { discard; }"), "terrain depth contract retained")
	_check(source.contains("diffuse_burley") and source.contains("specular_schlick_ggx"), "PBR path retained")
	_check(_diffuse(Vector3.UP, Vector3.ZERO) == 0.0, "zero sun reference")
	_check(_diffuse(Vector3.UP, Vector3.UP) == 1.0, "day reference")
	_check(_diffuse(Vector3.UP, Vector3.DOWN) == 0.0, "night reference")
	var tiny: Vector3 = Vector3(1.0e-10, 0.0, 0.0)
	_check(tiny.dot(tiny) > 0.0, "no broad epsilon disc cutoff")
	var shader: Shader = load(PATH) as Shader
	_check(shader != null, "shader resource loads")
	if _failures == 0:
		print("SurfaceShellNormalizeGuard: PASS source guards, CPU fallback references, shader resource")
	print("SurfaceShellNormalizeGuard: source/CPU checks only; GPU compilation and rendered pixels require an actual renderer run")
	quit(0 if _failures == 0 else 1)
