class_name LkStarSprites
extends MultiMeshInstance3D

const SpriteShader = preload("res://world/rendering/lk_star_sprites.gdshader")
var _sprites_material: ShaderMaterial
var _sprite_camera: Camera3D
var _far_occluders: MeshInstance3D
var exposure_gain: float = 0.8


func configure(stars: Array, camera: Camera3D, far_mesh: MeshInstance3D) -> void:
	_sprite_camera = camera
	_far_occluders = far_mesh
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var batch: MultiMesh = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.use_custom_data = true
	batch.mesh = quad
	batch.instance_count = stars.size()
	batch.custom_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	for i: int in range(stars.size()):
		var star: Dictionary = stars[i]
		var d: Array = star["direction_galaxy"]
		batch.set_instance_transform(i, Transform3D.IDENTITY)
		batch.set_instance_color(i, star["color_linear"])
		batch.set_instance_custom_data(i, Color(d[0], d[1], d[2], star["flux_at_limit"]))
	multimesh = batch
	_sprites_material = ShaderMaterial.new()
	_sprites_material.shader = SpriteShader
	_sprites_material.render_priority = -10
	material_override = _sprites_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true
	extra_cull_margin = 16.0
	# FarMesh updates its public ShaderMaterial uniforms at process priority 100.
	process_priority = 110


func _process(_delta: float) -> void:
	if not is_instance_valid(_sprite_camera) or not is_instance_valid(_far_occluders) or not _far_occluders.visible:
		visible = false
		return
	var source: ShaderMaterial = _far_occluders.material_override as ShaderMaterial
	if source == null:
		visible = false
		return
	var count: Variant = source.get_shader_parameter("body_count")
	var spheres: Variant = source.get_shader_parameter("body_spheres")
	if count == null or spheres == null:
		visible = false
		return
	_sprites_material.set_shader_parameter("occluder_count", count)
	_sprites_material.set_shader_parameter("occluder_spheres", spheres)
	_sprites_material.set_shader_parameter("observer_inside", source.get_shader_parameter("active_inside"))
	_sprites_material.set_shader_parameter("viewport_pixels", get_viewport().get_visible_rect().size)
	_sprites_material.set_shader_parameter("star_gain", maxf(exposure_gain, 0.0))
	global_position = _sprite_camera.global_position
	visible = true
