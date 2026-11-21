extends SceneTree

const PATHS = [
	"res://world/rendering/lk_far_system.gdshader",
	"res://world/rendering/lk_far_system_flight.gdshader",
]
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FarHitNormalGuard: FAIL " + label)

func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

func _initialize() -> void:
	for path: String in PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		var guarded: String = "vec3 normal_delta = ray * nearest_relative - body_spheres[winner].xyz;\n\tif (!(dot(normal_delta, normal_delta) > 0.0)) { discard; }\n\tvec3 normal_system = normalize(normal_delta);"
		_check(source.contains(guarded), path + " guard precedes normalize")
		_check(not source.contains("normalize(ray * nearest_relative - body_spheres[winner].xyz)"), path + " no unguarded hit normal")
		_check(source.contains("LIGHT_VERTEX = view_ray * nearest;"), path + " lighting position retained")
		_check(source.contains("if (texture(scene_depth, SCREEN_UV).r > 0.0 || active_inside) { discard; }"), path + " depth contract retained")
		var shader: Shader = load(path) as Shader
		_check(shader != null, path + " resource loads")
	# Scalar float32 reference: center = ray = (0, 0, -1).
	# Each rounding is explicit; this is not GPU execution or a pixel test.
	for radius: float in [1.0e-4, 1.0e-6, 1.0e-8]:
		var r: float = _f32(radius)
		var disc: float = _f32(r * r)
		var root: float = _f32(sqrt(disc))
		var hit: float = _f32(1.0 - root)
		var delta: float = _f32(1.0 - hit)
		var squared: float = _f32(delta * delta)
		_check(hit > 0.0, "positive hit radius=" + str(radius))
		if radius < 1.0e-7:
			_check(squared == 0.0, "float32 cancellation reproduced")
		else:
			_check(squared > 0.0, "nonzero normal retained radius=" + str(radius))
	if _failures == 0:
		print("FarHitNormalGuard: PASS source contracts and float32 cancellation reference")
	print("FarHitNormalGuard: GPU compilation and rendered pixels not tested")
	quit(0 if _failures == 0 else 1)
