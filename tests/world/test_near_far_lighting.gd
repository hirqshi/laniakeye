extends SceneTree

const FarRenderer = preload("res://game/world/rendering/lk_catalog_far_mesh.gd")
const VisualScene = preload("res://scenes/world/test_catalog_far_mesh.gd")
var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("NearFarLighting: FAIL " + label)


func _srgb(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)


func _initialize() -> void:
	for color: Color in [Color(0.38, 0.43, 0.48), Color(0.55, 0.45, 0.33), Color(0.02, 0.04, 0.08), Color.WHITE, Color.BLACK]:
		var packed: Vector4 = FarRenderer.pack_linear_color(color, false)
		_check(absf(packed.x - _srgb(color.r)) < 2.0e-6, "linear red")
		_check(absf(packed.y - _srgb(color.g)) < 2.0e-6, "linear green")
		_check(absf(packed.z - _srgb(color.b)) < 2.0e-6, "linear blue")
		_check(packed.w == 0.0, "non-emissive flag")
		_check(FarRenderer.pack_linear_color(color, true).w == 1.0, "emissive flag independent of conversion")
	var node = FarRenderer.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.45, 0.33)
	material.roughness = 1.0
	var original: int = material.shading_mode
	node.bind_surface_material(material)
	node.set_albedo_debug(true)
	_check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "explicit albedo diagnostic")
	node.set_albedo_debug(false)
	_check(material.shading_mode == original, "normal shaded material restored")
	_check(not node.is_albedo_debug(), "normal mode default")
	node.free()
	var file: FileAccess = FileAccess.open("res://game/world/rendering/lk_far_system.gdshader", FileAccess.READ)
	_check(file != null, "shader file readable")
	if file != null:
		var source: String = file.get_as_text()
		file.close()
		_check(source.contains("diffuse_burley") and source.contains("specular_schlick_ggx"), "engine material model contract")
		_check(source.contains("LIGHT_VERTEX = view_ray * nearest;"), "analytic lighting position")
		_check(source.contains("NORMAL = normalize(mat3(VIEW_MATRIX) * normal_system);"), "analytic normal in view space")
		_check(not source.contains("render_mode unshaded"), "active surface not forced unshaded")
		_check(source.contains("ALBEDO = body_colors[0].rgb;"), "active uses material albedo")
	print("NearFarLighting: structural/CPU checks only; GPU brightness not measured")
	if _failures == 0:
		print("NearFarLighting: PASS linear colors, material binding, debug restore, shader contract, scene parse")
	quit(0 if _failures == 0 else 1)
