extends SceneTree

const Placement = preload("res://game/world/generation/lk_galaxy_placement.gd")
const Identity = preload("res://game/world/generation/lk_world_identity.gd")
const Samples = preload("res://game/world/generation/lk_world_samples.gd")
const COUNT: int = 2048
const TOLERANCE: float = 1.0e-12
var _failures: int = 0
var _worst_norm: float = 0.0
var _worst_dot: float = 0.0
var _worst_det: float = 0.0
var _worst_roundtrip: float = 0.0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		if _failures <= 16:
			push_error("GalaxyOrientation: FAIL " + label)

func _dot(a: Array, b: Array) -> float:
	return float(a[0]) * float(b[0]) + float(a[1]) * float(b[1]) + float(a[2]) * float(b[2])

func _initialize() -> void:
	var universe: String = Identity.universe_id("laniakeye-development-v1")
	var indices: Array[int] = [0, 1, 2, 7, 8, 123456789, 9223372036854775807]
	for i: int in range(COUNT):
		indices.append(i * 104729 + 17)
	for index: int in indices:
		var id: String = Identity.child_id(universe, "galaxy", str(index))
		var u: float = Samples.unit(id, "galaxy_placement/orientation/u", Placement.VERSION)
		var a: float = TAU * Samples.unit(id, "galaxy_placement/orientation/a", Placement.VERSION)
		var b: float = TAU * Samples.unit(id, "galaxy_placement/orientation/b", Placement.VERSION)
		var x: float = sqrt(1.0 - u) * sin(a)
		var y: float = sqrt(1.0 - u) * cos(a)
		var z: float = sqrt(u) * sin(b)
		var w: float = sqrt(u) * cos(b)
		var norm_error: float = absf(x * x + y * y + z * z + w * w - 1.0)
		_worst_norm = maxf(_worst_norm, norm_error)
		_check(norm_error < TOLERANCE, "unit quaternion")
		var axes: Array = Placement._axes(id)
		_check(var_to_bytes(axes) == var_to_bytes(Placement._axes(id)), "repeat determinism")
		for i: int in range(3):
			for j: int in range(3):
				var error: float = absf(_dot(axes[i], axes[j]) - (1.0 if i == j else 0.0))
				_worst_dot = maxf(_worst_dot, error)
				_check(error < TOLERANCE, "orthonormal columns")
		var cross: Array = [
			float(axes[0][1]) * float(axes[1][2]) - float(axes[0][2]) * float(axes[1][1]),
			float(axes[0][2]) * float(axes[1][0]) - float(axes[0][0]) * float(axes[1][2]),
			float(axes[0][0]) * float(axes[1][1]) - float(axes[0][1]) * float(axes[1][0]),
		]
		var determinant_error: float = absf(_dot(cross, axes[2]) - 1.0)
		_worst_det = maxf(_worst_det, determinant_error)
		_check(determinant_error < TOLERANCE, "right-handed determinant")
		var record: Dictionary = {"galaxy_to_universe_axes": axes}
		for point: Array in [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [3.0, -4.0, 12.0]]:
			var rotated: Array[float] = Placement.rotate_local_ly(record, point)
			_check(absf(_dot(rotated, rotated) - _dot(point, point)) < TOLERANCE * maxf(1.0, _dot(point, point)), "length preservation")
			for axis: int in range(3):
				var error: float = absf(_dot(axes[axis], rotated) - float(point[axis]))
				_worst_roundtrip = maxf(_worst_roundtrip, error)
				_check(error < TOLERANCE * 13.0, "transpose inverse roundtrip")
	print("GalaxyOrientation: samples=", indices.size(), " quaternion_error=", _worst_norm,
		" orthogonality_error=", _worst_dot, " determinant_error=", _worst_det,
		" roundtrip_error=", _worst_roundtrip)
	if _failures == 0:
		print("GalaxyOrientation: PASS unit quaternion, orthonormality, handedness, length, inverse, determinism")
	quit(0 if _failures == 0 else 1)
