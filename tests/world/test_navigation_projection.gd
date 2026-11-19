extends SceneTree

const Safe = preload("res://world/debug/lk_debug_navigation_projection.gd")
var _failures: int = 0
var _cases: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("NavProjection: FAIL " + label)

func _verify(view: Vector3, projection: Projection, size: Vector2) -> Dictionary:
	var result: Dictionary = Safe.project_view(view, projection, size)
	var point: Vector2 = result["point"]
	_check(point.is_finite(), "finite output")
	_check(point.x >= 0.0 and point.x <= size.x and point.y >= 0.0 and point.y <= size.y, "inside viewport")
	_cases += 1
	return result

func _initialize() -> void:
	var projection: Projection = Projection(Vector4(1.0, 0.0, 0.0, 0.0), Vector4(0.0, 1.0, 0.0, 0.0), Vector4(0.0, 0.0, -1.0, -1.0), Vector4(0.0, 0.0, -0.1, 0.0))
	var size: Vector2 = Vector2(1280.0, 720.0)
	var front: Dictionary = _verify(Vector3.FORWARD, projection, size)
	_check(front["point"] == size * 0.5 and not front["edge"], "forward centre")
	var right: Dictionary = _verify(Vector3.RIGHT, projection, size)
	_check(right["edge"] and right["point"].x > size.x * 0.5, "exact camera-plane right")
	var left: Dictionary = _verify(Vector3.LEFT, projection, size)
	_check(left["edge"] and left["point"].x < size.x * 0.5, "exact camera-plane left")
	var up: Dictionary = _verify(Vector3.UP, projection, size)
	_check(up["edge"] and up["point"].y < size.y * 0.5, "exact camera-plane up")
	var down: Dictionary = _verify(Vector3.DOWN, projection, size)
	_check(down["edge"] and down["point"].y > size.y * 0.5, "exact camera-plane down")
	var back: Dictionary = _verify(Vector3.BACK, projection, size)
	_check(back["behind"] and back["edge"], "directly behind")
	var zero: Dictionary = _verify(Vector3.ZERO, projection, size)
	_check(not zero["valid"] and zero["point"] == size * 0.5, "zero direction safe fallback")
	var bad: Dictionary = _verify(Vector3(INF, 0.0, 0.0), projection, size)
	_check(not bad["valid"], "nonfinite input safe fallback")
	for step: int in range(2001):
		var z: float = float(step - 1000) * 1.0e-8
		_verify(Vector3(1.0, 0.3, z), projection, size)
	for step: int in range(721):
		var angle: float = float(step) * TAU / 720.0
		_verify(Vector3(sin(angle), 0.15, -cos(angle)), projection, size)
	var offaxis: Projection = projection
	offaxis.z.x = 0.15
	offaxis.z.y = -0.1
	_verify(Vector3.FORWARD, offaxis, size)
	_verify(Vector3.RIGHT, projection, Vector2(32.0, 20.0))
	var source: String = FileAccess.get_file_as_string("res://world/debug/lk_debug_navigation_data.gd")
	_check(source.contains("NAV_PROJECTION_SAFE_V1") and not source.contains("camera.unproject_position("), "hotfix installed in actual data helper")
	if _failures == 0:
		print("NavProjection: PASS cases=%d finite bounds, camera-plane sweep, back, zero, off-axis, installed wrapper" % _cases)
	print("NavProjection: visual camera rotation remains an integration check")
	quit(0 if _failures == 0 else 1)
