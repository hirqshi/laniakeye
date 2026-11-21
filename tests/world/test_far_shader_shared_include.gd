extends SceneTree

const SHADERS = [
	"res://world/rendering/lk_far_system.gdshader",
	"res://world/rendering/lk_far_system_flight.gdshader",
	"res://world/rendering/lk_far_system_surface_shell.gdshader",
]
const INCLUDE_PATH: String = "res://world/rendering/lk_far_system_common.gdshaderinc"
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FarShaderSharedInclude: FAIL " + label)

func _initialize() -> void:
	var shared: String = FileAccess.get_file_as_string(INCLUDE_PATH)
	_check(not shared.is_empty(), "shared include exists")
	_check(shared.contains("uniform sampler2D scene_depth"), "shared depth uniform")
	_check(shared.contains("uniform vec4 body_spheres[64];"), "shared sphere uniform")
	_check(shared.contains("void vertex() {"), "shared vertex stage")
	_check(shared.contains("POSITION = clip;"), "shared vertex contract")
	for path: String in SHADERS:
		var source: String = FileAccess.get_file_as_string(path)
		_check(source.contains("#include \"" + INCLUDE_PATH + "\""), path + " includes shared stage")
		_check(not source.contains("uniform sampler2D scene_depth"), path + " no duplicate depth uniform")
		_check(not source.contains("void vertex() {"), path + " no duplicate vertex stage")
		_check(source.contains("shader_type spatial;"), path + " shader type retained")
		_check(source.contains("render_mode skip_vertex_transform"), path + " render mode retained")
		var shader: Shader = load(path) as Shader
		_check(shader != null, path + " resource loads")
	_check(FileAccess.get_file_as_string(SHADERS[0]).contains("active_cutoff_m"), "base cutoff behavior retained via shared uniforms")
	_check(FileAccess.get_file_as_string(SHADERS[1]).contains("active_ambient_linear"), "flight ambient behavior retained")
	_check(FileAccess.get_file_as_string(SHADERS[2]).contains("active_shell_valid"), "surface shell behavior retained")
	if _failures == 0:
		print("FarShaderSharedInclude: PASS shared uniforms/vertex, shader-specific fragments retained")
	print("FarShaderSharedInclude: GPU compilation and rendered pixels require an actual renderer run")
	quit(0 if _failures == 0 else 1)
