extends SceneTree

const Bridge = preload("res://world/rendering/lk_flight_visual_bridge.gd")
const SceneScript = preload("res://scenes/world/test_catalog_flight_visuals.gd")
const ShaderResource = preload("res://world/rendering/lk_far_system_flight.gdshader")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("FlightVisuals: FAIL " + label)

func _initialize() -> void:
	var shader: String = FileAccess.get_file_as_string("res://world/rendering/lk_far_system_flight.gdshader")
	var bridge: String = FileAccess.get_file_as_string("res://world/rendering/lk_flight_visual_bridge.gd")
	_check(not shader.contains("nearest <= active_cutoff_m"), "no blind active distance cutout")
	_check(not shader.contains("opacity = smoothstep"), "no empty near-distance fade")
	_check(shader.contains("texture(scene_depth, SCREEN_UV).r > 0.0"), "opaque terrain wins per pixel")
	_check(shader.contains("active_inside"), "existing inside/cave exclusion retained")
	_check(shader.contains("IRRADIANCE = vec4(active_ambient_linear * ambient_energy, 1.0)"), "per-hit irradiance override")
	_check(shader.contains("dot(normal_system, normalize(body_suns[0]))"), "ambient uses surface point, not camera horizon")
	_check(shader.contains("diffuse_burley") and shader.contains("specular_schlick_ggx") and not shader.contains("render_mode unshaded"), "engine PBR path retained")
	_check((Bridge.FAR_LAYER & (Bridge.FAR_LAYER - 1)) == 0 and (Bridge.FAR_LAYER & 1) == 0, "isolated single render layer")
	_check(bridge.contains("_old_sun_mask & ~FAR_LAYER") and bridge.contains("_disk_sun.light_cull_mask = FAR_LAYER"), "disjoint light masks")
	_check(bridge.contains('_disk_sun.light_energy = maxf(float(_root.get("stellar_light_energy")), 0.0)'), "disk energy independent of horizon-masked light")
	_check(bridge.contains("material.shader = _old_shader") and bridge.contains("_surface_sun.light_cull_mask = _old_sun_mask"), "cleanup restoration contract")
	var energies: Array[float] = []
	for cosine: float in [-1.0, 0.0, 0.01, 0.02, 1.0]:
		var visibility: float = smoothstep(0.0, 0.02, cosine)
		energies.append(lerpf(0.035, 0.18, visibility))
	_check(is_equal_approx(energies[0], 0.035) and is_equal_approx(energies[4], 0.18), "ambient endpoint reference")
	_check(is_equal_approx(energies[2], 0.1075), "ambient midpoint reference")
	if _failures == 0:
		print("FlightVisuals: PASS no-cutout/depth contracts, per-hit ambient, PBR path, light masks, restoration, scene parse")
	print("FlightVisuals: GPU visual tests REQUIRED: fallback, terminator, near/far brightness, pits; loading performance unchanged")
	quit(0 if _failures == 0 else 1)
