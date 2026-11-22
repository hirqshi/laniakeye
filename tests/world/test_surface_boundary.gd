extends SceneTree

const Shell = preload("res://game/debug/lk_surface_shell_math.gd")
const SceneScript = preload("res://scenes/world/test_catalog_surface_boundary_fix.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SurfaceBoundary: FAIL " + label)

func _initialize() -> void:
	var radius: float = 4473080.0
	var cases: int = 0
	for offset: float in [-1.0, -0.6, -0.5, -0.25, -0.001, 0.0, 0.001, 0.01, 0.25, 0.5, 1.0, 32.5]:
		var distance: float = radius + offset
		var state: Dictionary = Shell.coefficients(distance, radius)
		if offset <= 0.0:
			_check(not state["valid"] and Shell.entry_relative(1.0, state) < 0.0, "inside never chooses far exit")
		else:
			_check(state["valid"] and state["stable"], "outside stable near-shell mode")
			var hit: float = Shell.entry_relative(1.0, state) * distance
			_check(absf(hit - float(state["height_m"])) < 1.0e-6, "stable nadir intersection")
		for along: float in [-1.0, -0.5, -0.0001, 0.0]:
			_check(Shell.entry_relative(along, state) < 0.0, "outward sky never hit by active sphere")
		cases += 1
	for i: int in range(1001):
		var offset: float = float(i) / 1000.0 + 0.0001
		var distance: float = radius + offset
		var state: Dictionary = Shell.coefficients(distance, radius)
		var c32: float = PackedFloat32Array([state["c"]])[0]
		var t32: float = PackedFloat32Array([c32 / (1.0 + sqrt(1.0 - c32))])[0]
		_check(absf(t32 * distance - float(state["height_m"])) < 1.0e-5, "quantized coefficient/nadir regression")
		cases += 1
	var distant: Dictionary = Shell.coefficients(radius * 10.0, radius)
	_check(distant["valid"] and not distant["stable"], "far angular-size path retained")
	_check(not Shell.coefficients(INF, radius)["valid"], "invalid state")
	_check(Shell.slope_degrees(Vector3.UP, Vector3.UP) < 0.001, "flat support")
	_check(absf(Shell.slope_degrees(Vector3.RIGHT, Vector3.UP) - 90.0) < 0.001, "wall support")
	var normal: Vector3 = Vector3(sin(deg_to_rad(70.0)), cos(deg_to_rad(70.0)), 0.0)
	_check(Shell.slope_degrees(normal, Vector3.UP) > 55.0, "actual steep landing support refused")
	_check(not is_finite(Shell.slope_degrees(Vector3.ZERO, Vector3.UP)), "invalid support normal")
	var far: String = FileAccess.get_file_as_string("res://game/world/rendering/lk_far_system_surface_shell.gdshader")
	var stars: String = FileAccess.get_file_as_string("res://game/world/rendering/lk_star_sprites_surface_shell.gdshader")
	_check(not far.contains("|| active_inside") and not stars.contains("observer_inside ||"), "no global underground sky suppression")
	_check(far.contains("hit = active_shell_c / denominator") and stars.contains("active_shell_c / denominator"), "shared stable active intersection")
	_check(far.contains("IRRADIANCE") and far.contains("active_day_ambient"), "terminator fix retained")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_surface_boundary_fix.gd")
	var start: int = source.find("func _surface_patch_geometry_ready()")
	var end: int = source.find("func _try_flight_landing()")
	var geometry: String = source.substr(start, end - start)
	_check(geometry.contains("get_voxel_f_interpolated") and geometry.contains("is_area_meshed"), "publish keeps geometry checks")
	_check(not geometry.contains("intersect_shape") and not geometry.contains("floor_max_angle_deg"), "publish not blocked by standing pose")
	_check(source.contains("slope > _player.floor_max_angle_deg") and source.contains("super._try_flight_landing()"), "final support gate plus inherited capsule gate")
	if _failures == 0:
		print("SurfaceBoundary: PASS shell cases=%d, signed crossing, quantized coefficients, sky entry, slope math, readiness separation, scene parse" % cases)
	print("SurfaceBoundary: GPU pit crossing, native terrain activation and actual G landing still require visual integration")
	quit(0 if _failures == 0 else 1)
