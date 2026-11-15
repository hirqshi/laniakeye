class_name PlanetFarMesh
extends MeshInstance3D

@export var planet_radius_m: float = 6_371_000.0
@export var terrain_height_m: float = 4_000.0
@export var noise_seed: int = 0
@export_range(256, 2048, 256) var heightmap_width: int = 1024
@export_range(0.1, 0.95, 0.05) var blend_start_fraction: float = 0.6
@export_range(0.1, 1.0, 0.05) var blend_coverage_margin: float = 0.8
@export var blend_enabled: bool = true
@export var far_min_distance_m: float = 5000.0
@export var far_fade_width_m: float = 3000.0
@export_enum("Combined", "Near only", "Far only (raw)", "Layer colors", "Near depth", "Overlay reasons") var display_mode: int = 0

var _horizon_material: ShaderMaterial
var _blend_material: ShaderMaterial
var _depth_material: ShaderMaterial
var _blend_shader: Shader
var _reason_shader: Shader
var _terrain: Node3D
var _terrain_was_visible: bool = true
var _last_mode: int = -1


func _ready() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true
	extra_cull_margin = 16.0
	_horizon_material = ShaderMaterial.new()
	_horizon_material.shader = preload("res://voxel/planet_horizon.gdshader")
	_horizon_material.set_shader_parameter("height_map", _build_heightmap())
	_depth_material = _make_depth_material()
	material_override = _horizon_material
	process_priority = 100
	call_deferred("_attach_terrain_blend")
	_sync_camera()


func _make_depth_material() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float far_min_distance_m = 5000.0;
uniform float far_fade_width_m = 3000.0;
const int masks[10] = int[10](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);
float digit(vec2 p, int d) {
    int bit = 0;
    if (p.x > 0.2 && p.x < 0.8) {
        if (p.y < 0.14) { bit = 1; }
        else if (p.y > 0.86) { bit = 8; }
        else if (p.y > 0.43 && p.y < 0.57) { bit = 64; }
    }
    if (p.y > 0.12 && p.y < 0.44) {
        if (p.x > 0.8) { bit = 2; } else if (p.x < 0.2) { bit = 32; }
    }
    if (p.y > 0.56 && p.y < 0.88) {
        if (p.x > 0.8) { bit = 4; } else if (p.x < 0.2) { bit = 16; }
    }
    return (masks[clamp(d, 0, 9)] & bit) != 0 ? 1.0 : 0.0;
}
float distance_at(vec2 uv) {
    float d = texture(scene_depth, uv).r;
    if (d <= 0.0) { return -1.0; }
    vec4 v = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, d, 1.0);
    return length(v.xyz / v.w);
}
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
    float meters = distance_at(SCREEN_UV);
    vec3 c = vec3(0.02);
    if (meters >= 0.0) {
        if (meters <= far_min_distance_m) { c = vec3(1.0, 0.1, 0.05); }
        else if (meters < far_min_distance_m + far_fade_width_m) { c = vec3(1.0, 0.85, 0.0); }
        else { c = vec3(0.0, 0.6, 1.0); }
    }
    vec2 pixels = SCREEN_UV * VIEWPORT_SIZE;
    vec2 text = (pixels - vec2(16.0, 16.0)) / vec2(20.0, 32.0);
    if (text.x >= 0.0 && text.x < 8.0 && text.y >= 0.0 && text.y < 1.0) {
        float center_m = distance_at(vec2(0.5));
        c = vec3(0.0);
        if (center_m >= 0.0) {
            float place = pow(10.0, 7.0 - floor(text.x));
            int d = int(mod(floor(min(center_m, 99999999.0) / place), 10.0));
            vec2 p = vec2(fract(text.x) / 0.8, text.y);
            if (p.x <= 1.0) { c = vec3(digit(p, d)); }
        } else { c = vec3(0.5, 0.0, 0.0); }
    }
    if (abs(pixels.x - VIEWPORT_SIZE.x * 0.5) < 4.0 && abs(pixels.y - VIEWPORT_SIZE.y * 0.5) < 1.0) { c = vec3(1.0); }
    ALBEDO = c;
    ALPHA = 1.0;
}"""
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = shader
	result.render_priority = 2
	return result


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_F1 and event.keycode <= KEY_F6:
			display_mode = int(event.keycode - KEY_F1)
			get_viewport().set_input_as_handled()


func _attach_terrain_blend() -> void:
	var planet: Node = get_parent()
	if not planet.has_method("get_terrain"):
		return
	_terrain = planet.call("get_terrain") as Node3D
	if _terrain == null:
		return
	_terrain_was_visible = _terrain.visible
	var terrain_material: Material = _terrain.get("material") as Material
	if terrain_material == null or terrain_material.next_pass != null:
		push_warning("PlanetFarMesh: no free terrain next_pass; blend not attached")
		return
	var source: String = _horizon_material.shader.code
	var guard: String = "if (texture(scene_depth, SCREEN_UV).r > 0.0) { discard; }"
	var vertex_line: String = "POSITION = vec4(VERTEX.xy, 1.0, 1.0);"
	if not source.contains(guard) or not source.contains(vertex_line) or not source.contains("ALPHA = 1.0;") or not source.contains("ALBEDO = color;"):
		push_error("PlanetFarMesh: incompatible horizon shader; blend not attached")
		return
	source = source.replace("shader_type spatial;", "shader_type spatial;\nuniform float blend_start_m = 9600.0;\nuniform float blend_end_m = 16000.0;\nuniform bool blend_enabled = true;\nuniform bool mark_layer = false;")
	source = source.replace(vertex_line, "")
	source = source.replace(guard, """if (!blend_enabled) { discard; }
	float near_depth = texture(scene_depth, SCREEN_UV).r;
	if (near_depth <= 0.0) { discard; }
	vec4 near_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, near_depth, 1.0);
	vec3 near_view = near_point.xyz / near_point.w;
	if (abs(near_view.z - VERTEX.z) > max(0.05, abs(near_view.z) * 0.000001)) { discard; }
	float weight = clamp((length(near_view) - blend_start_m) / max(blend_end_m - blend_start_m, 1.0), 0.0, 1.0);
	weight = weight * weight * weight * (weight * (weight * 6.0 - 15.0) + 10.0);
	if (weight <= 0.0001) { discard; }""")
	source = source.replace("ALPHA = 1.0;", "ALPHA = weight;")
	source = source.replace("ALBEDO = color;", "ALBEDO = mark_layer ? vec3(1.0, 0.0, 1.0) : color;")
	_blend_shader = Shader.new()
	_blend_shader.code = source
	_reason_shader = _make_reason_shader(source)
	_blend_material = ShaderMaterial.new()
	_blend_material.shader = _blend_shader
	_blend_material.render_priority = 1
	terrain_material.next_pass = _blend_material
	_sync_camera()


func _make_reason_shader(source: String) -> Shader:
	var depth_guard: String = "if (abs(near_view.z - VERTEX.z) > max(0.05, abs(near_view.z) * 0.000001)) { discard; }"
	source = source.replace(depth_guard, "if (abs(near_view.z - VERTEX.z) > max(0.05, abs(near_view.z) * 0.000001)) { discard /* visibility */; }")
	var reasons: Dictionary = {
		"exclusion_near_m <= far_min_distance_m": "1.0, 0.0, 0.0",
		"visible_distance_m <= far_min_distance_m": "1.0, 0.0, 0.0",
		"weight <= 0.0001": "0.0, 0.15, 1.0",
		"disc < 0.0": "0.0, 1.0, 1.0",
		"finish <= start": "0.0, 1.0, 1.0",
		"inner_disc < 0.0": "0.0, 1.0, 1.0",
		"start == 0.0 && field(-center_relative) <= 0.5 * meters_to_relative": "1.0, 0.0, 1.0",
		"t <= 0.0": "1.0, 0.0, 1.0",
		"t <= 0.5 * meters_to_relative": "1.0, 0.0, 1.0"
	}
	for condition: String in reasons:
		var original: String = "if (%s) { discard; }" % condition
		if not source.contains(original):
			push_warning("PlanetFarMesh: missing diagnostic guard: " + condition)
		source = source.replace(original, "if (%s) { diagnostic_color = vec3(%s); break; }" % [condition, reasons[condition]])
	source = source.replace("discard;", "diagnostic_color = vec3(0.5); break;")
	source = source.replace("if (!hit) {", "if (!hit) { diagnostic_color = vec3(0.55, 0.0, 1.0);")
	source = source.replace("agreement = 1.0 - smoothstep(allowed_error, allowed_error * 2.0, mismatch);", "agreement = 1.0 - smoothstep(allowed_error, allowed_error * 2.0, mismatch); if (hit && agreement < 0.99) { diagnostic_color = vec3(1.0, 0.8, 0.0); }")
	source = source.replace("void fragment() {", "void fragment() {\nvec3 diagnostic_color = vec3(0.0, 1.0, 0.0);\nfor (int diagnostic_once = 0; diagnostic_once < 1; diagnostic_once++) {")
	source = source.substr(0, source.rfind("}")) + "\n}\nALBEDO = diagnostic_color;\nALPHA = 1.0;\n}\n"
	var result: Shader = Shader.new()
	result.code = source
	return result


func _build_heightmap() -> ImageTexture:
	var width: int = maxi(heightmap_width, 256)
	var height: int = width / 2
	var image: Image = Image.create(width, height, false, Image.FORMAT_RF)
	var generator: PlanetVoxelGenerator = PlanetVoxelGenerator.new()
	generator.planet_radius_m = planet_radius_m
	generator.terrain_height_m = terrain_height_m
	generator.noise_seed = noise_seed
	for y: int in range(height):
		var phi: float = (float(y) + 0.5) / float(height) * PI
		for x: int in range(width):
			var theta: float = (float(x) + 0.5) / float(width) * TAU
			var direction: Vector3 = Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var elevation: float = generator._get_surface_radius(direction) - planet_radius_m
			image.set_pixel(x, y, Color(elevation, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(image)


func _process(_delta: float) -> void:
	_sync_camera()


func _set_parameter(parameter_name: StringName, value: Variant) -> void:
	_horizon_material.set_shader_parameter(parameter_name, value)
	if _blend_material != null:
		_blend_material.set_shader_parameter(parameter_name, value)


func _sync_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		visible = false
		return
	var planet: Node3D = get_parent() as Node3D
	if planet == null:
		visible = false
		return
	display_mode = clampi(display_mode, 0, 5)
	visible = display_mode != 1
	if _terrain != null:
		_terrain.visible = _terrain_was_visible and display_mode != 2
	material_override = _depth_material if display_mode == 4 else _horizon_material
	if _blend_material != null:
		var wanted: Shader = _reason_shader if display_mode == 5 else _blend_shader
		if _blend_material.shader != wanted:
			_blend_material.shader = wanted
		_blend_material.set_shader_parameter("height_map", _horizon_material.get_shader_parameter("height_map"))
	if _last_mode != display_mode:
		var labels: Array[String] = ["F1 Combined", "F2 Near only", "F3 Raw far only", "F4 Cyan background / magenta overlay", "F5 Near depth; 8 digits = center distance in meters; red box = no center depth", "F6 Reasons: green=accepted, red=near cutoff, blue=before blend, yellow=distance disagreement, violet=fallback, cyan=no intersection, magenta=inside/zero hit, gray=other guard; uncolored near=visibility rejection or no overlay coverage"]
		print("PlanetFarMesh: ", labels[display_mode])
		_last_mode = display_mode
	var center: Vector3 = planet.global_position
	var eye: Vector3 = camera.global_position
	var dx: float = float(center.x) - float(eye.x)
	var dy: float = float(center.y) - float(eye.y)
	var dz: float = float(center.z) - float(eye.z)
	var distance_m: float = sqrt(dx * dx + dy * dy + dz * dz)
	var coordinate_scale: float = maxf(distance_m, maxf(planet_radius_m, 1.0))
	_set_parameter("center_relative", Vector3(dx / coordinate_scale, dy / coordinate_scale, dz / coordinate_scale))
	_set_parameter("radius_relative", planet_radius_m / coordinate_scale)
	_set_parameter("height_limit_relative", absf(terrain_height_m) / coordinate_scale)
	_set_parameter("meters_to_relative", 1.0 / coordinate_scale)
	_set_parameter("pixel_angle", deg_to_rad(camera.fov) / maxf(float(get_viewport().get_visible_rect().size.y), 1.0))
	_set_parameter("far_min_distance_m", 0.0 if display_mode == 2 else maxf(far_min_distance_m, 0.0))
	_set_parameter("far_fade_width_m", 1.0 if display_mode == 2 else maxf(far_fade_width_m, 1.0))
	_set_parameter("debug_view", 0)
	_horizon_material.set_shader_parameter("surface_color", Vector3(0.0, 0.8, 1.0) if display_mode == 3 else Vector3(0.35, 0.45, 0.3))
	_depth_material.set_shader_parameter("far_min_distance_m", maxf(far_min_distance_m, 0.0))
	_depth_material.set_shader_parameter("far_fade_width_m", maxf(far_fade_width_m, 1.0))
	if _blend_material != null:
		var coverage_m: float = maxf(float(planet.get("view_distance_m")), 1.0)
		var blend_end: float = maxf(minf(camera.far, coverage_m) * blend_coverage_margin, 1.0)
		_blend_material.set_shader_parameter("blend_start_m", blend_end * blend_start_fraction)
		_blend_material.set_shader_parameter("blend_end_m", blend_end)
		_blend_material.set_shader_parameter("blend_enabled", blend_enabled and (display_mode == 0 or display_mode == 3 or display_mode == 5))
		_blend_material.set_shader_parameter("mark_layer", display_mode == 3)
	global_transform = camera.global_transform
	global_position -= camera.global_basis.z * maxf(camera.near * 2.0, 2.0)
