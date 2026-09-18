@tool
class_name TreePreview
extends Node3D

const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage.gdshader")

@export var tree_profile: TreeProfile:
	set(value):
		if tree_profile != null and tree_profile.changed.is_connected(_on_profile_changed):
			tree_profile.changed.disconnect(_on_profile_changed)

		tree_profile = value

		if tree_profile != null and not tree_profile.changed.is_connected(_on_profile_changed):
			tree_profile.changed.connect(_on_profile_changed)

		_regenerate()

@export_category("Shared Preview Base Materials")
@export var bark_material: StandardMaterial3D

@export_category("Scene References")
@export var tree_mesh_instance: MeshInstance3D
@export var preview_camera: Camera3D

@export_category("Actions")
@export var regenerate_preview: bool = false:
	set(value):
		if not value:
			return

		call_deferred("_regenerate")

@export var randomize_seed: bool = false:
	set(value):
		if not value or tree_profile == null:
			return

		tree_profile.preview_seed = randi()
		tree_profile.changed.emit()

var _generator: TreeMeshGenerator = TreeMeshGenerator.new()
var _preview_bark_material: StandardMaterial3D
var _preview_leaf_material: ShaderMaterial

func _ready() -> void:
	_regenerate()

func _exit_tree() -> void:
	if tree_profile != null and tree_profile.changed.is_connected(_on_profile_changed):
		tree_profile.changed.disconnect(_on_profile_changed)

func _on_profile_changed() -> void:
	call_deferred("_regenerate")

func _regenerate() -> void:
	if tree_profile == null or tree_mesh_instance == null:
		return

	var mesh: ArrayMesh = _generator.generate(tree_profile, tree_profile.preview_seed)
	tree_mesh_instance.mesh = mesh

	_apply_preview_materials(mesh)
	_frame_camera(mesh)

func _apply_preview_materials(mesh: ArrayMesh) -> void:
	if bark_material != null:
		_preview_bark_material = bark_material.duplicate() as StandardMaterial3D
	else:
		_preview_bark_material = StandardMaterial3D.new()

	_preview_leaf_material = ShaderMaterial.new()
	_preview_leaf_material.shader = FOLIAGE_SHADER

	_configure_bark_material(_preview_bark_material)
	_configure_leaf_material(_preview_leaf_material)

	if mesh.get_surface_count() > TreeMeshGenerator.BARK_SURFACE:
		tree_mesh_instance.set_surface_override_material(
			TreeMeshGenerator.BARK_SURFACE,
			_preview_bark_material
		)

	if mesh.get_surface_count() > TreeMeshGenerator.LEAF_SURFACE:
		tree_mesh_instance.set_surface_override_material(
			TreeMeshGenerator.LEAF_SURFACE,
			_preview_leaf_material
		)

func _configure_bark_material(material: StandardMaterial3D) -> void:
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = tree_profile.bark_albedo_texture
	material.normal_enabled = tree_profile.bark_normal_texture != null
	material.normal_texture = tree_profile.bark_normal_texture
	material.roughness_texture = tree_profile.bark_roughness_texture
	material.ao_enabled = tree_profile.bark_ao_texture != null
	material.ao_texture = tree_profile.bark_ao_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK

func _configure_leaf_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter(
		"albedo_texture",
		tree_profile.leaf_albedo_texture
	)
	material.set_shader_parameter(
		"normal_texture",
		tree_profile.leaf_normal_texture
	)
	material.set_shader_parameter(
		"roughness_texture",
		tree_profile.leaf_roughness_texture
	)
	material.set_shader_parameter(
		"foliage_tint",
		Color.WHITE
	)
	material.set_shader_parameter("alpha_cutoff", 0.5)
	material.set_shader_parameter(
		"normal_strength",
		1.0
	)
	material.set_shader_parameter(
		"roughness_value",
		0.86
	)
	material.set_shader_parameter(
		"roughness_multiplier",
		1.0
	)

func _frame_camera(mesh: ArrayMesh) -> void:
	if preview_camera == null:
		return

	var aabb: AABB = mesh.get_aabb()
	if aabb.size.length_squared() < 0.0001:
		return

	var target: Vector3 = aabb.get_center()
	var largest_size: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var distance_m: float = maxf(largest_size * 1.8, 4.0)

	preview_camera.global_position = (
		target
		+ Vector3(1.0, 0.7, 1.0).normalized() * distance_m
	)
	preview_camera.look_at(target, Vector3.UP)
