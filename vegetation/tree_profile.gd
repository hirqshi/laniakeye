@tool
class_name TreeProfile
extends Resource

enum CrownShape {
	ROUND,
	OVAL,
	CONICAL,
	COLUMN,
	UMBRELLA,
	WEEPING,
	WINDSWEPT,
	FLAT_TOP,
	LAYERED,
	DEAD
}

@export_category("Identity")
@export var display_name: String = "Unnamed Tree":
	set(value):
		display_name = value
		changed.emit()

@export var preview_seed: int = 12345:
	set(value):
		preview_seed = value
		changed.emit()

@export_category("Bark Textures")
@export var bark_albedo_texture: Texture2D
@export var bark_normal_texture: Texture2D
@export var bark_roughness_texture: Texture2D
@export var bark_ao_texture: Texture2D
@export_range(0.01, 20.0, 0.01) var bark_uv_scale: float = 1.0

@export_category("Leaf Textures")
@export var leaf_albedo_texture: Texture2D
@export var leaf_normal_texture: Texture2D
@export var leaf_roughness_texture: Texture2D
@export var leaf_ao_texture: Texture2D
@export var leaf_opacity_texture: Texture2D
@export_range(0.01, 20.0, 0.01) var leaf_uv_scale: float = 1.0

@export_category("Shared Material Index")
@export_range(0, 255, 1) var bark_texture_set_index: int = 0
@export_range(0, 255, 1) var leaf_texture_set_index: int = 0

@export_category("Trunk")
@export_range(1.0, 40.0, 0.1, "suffix:m") var min_height_m: float = 4.0:
	set(value):
		min_height_m = value
		changed.emit()

@export_range(1.0, 40.0, 0.1, "suffix:m") var max_height_m: float = 8.0:
	set(value):
		max_height_m = value
		changed.emit()

@export_range(0.03, 3.0, 0.01, "suffix:m") var min_trunk_radius_m: float = 0.12:
	set(value):
		min_trunk_radius_m = value
		changed.emit()

@export_range(0.03, 3.0, 0.01, "suffix:m") var max_trunk_radius_m: float = 0.28:
	set(value):
		max_trunk_radius_m = value
		changed.emit()

@export_range(3, 24, 1) var trunk_segments: int = 9:
	set(value):
		trunk_segments = value
		changed.emit()

@export_range(3, 12, 1) var trunk_radial_segments: int = 6:
	set(value):
		trunk_radial_segments = value
		changed.emit()

@export_range(0.0, 0.95, 0.01) var trunk_taper: float = 0.72:
	set(value):
		trunk_taper = value
		changed.emit()

@export_range(0.0, 2.0, 0.01, "suffix:m") var trunk_bend_amount_m: float = 0.3:
	set(value):
		trunk_bend_amount_m = value
		changed.emit()

@export_range(0.0, 2.0, 0.01) var trunk_twist: float = 0.18:
	set(value):
		trunk_twist = value
		changed.emit()

@export var bark_color_gradient: Gradient:
	set(value):
		bark_color_gradient = value
		changed.emit()

@export_category("Branches")
@export_range(0, 80, 1) var min_branch_count: int = 9:
	set(value):
		min_branch_count = value
		changed.emit()

@export_range(0, 80, 1) var max_branch_count: int = 16:
	set(value):
		max_branch_count = value
		changed.emit()

@export_range(0.1, 15.0, 0.1, "suffix:m") var min_branch_length_m: float = 0.8:
	set(value):
		min_branch_length_m = value
		changed.emit()

@export_range(0.1, 15.0, 0.1, "suffix:m") var max_branch_length_m: float = 2.4:
	set(value):
		max_branch_length_m = value
		changed.emit()

@export_range(2, 12, 1) var branch_segments: int = 4:
	set(value):
		branch_segments = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var branch_start_height_ratio: float = 0.35:
	set(value):
		branch_start_height_ratio = value
		changed.emit()

@export_range(-1.0, 1.0, 0.01) var branch_vertical_bias: float = 0.22:
	set(value):
		branch_vertical_bias = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var branch_curvature: float = 0.22:
	set(value):
		branch_curvature = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var branch_twist: float = 0.32:
	set(value):
		branch_twist = value
		changed.emit()

@export_range(0.02, 1.0, 0.01) var branch_radius_ratio: float = 0.34:
	set(value):
		branch_radius_ratio = value
		changed.emit()

@export_category("Crown")
@export var crown_shape: CrownShape = CrownShape.ROUND:
	set(value):
		crown_shape = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var crown_start_height_ratio: float = 0.42:
	set(value):
		crown_start_height_ratio = value
		changed.emit()

@export_range(0.1, 2.0, 0.01) var crown_radius_ratio: float = 0.46:
	set(value):
		crown_radius_ratio = value
		changed.emit()

@export_range(0.1, 2.0, 0.01) var crown_height_ratio: float = 0.5:
	set(value):
		crown_height_ratio = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var crown_asymmetry: float = 0.15:
	set(value):
		crown_asymmetry = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var hanging_amount: float = 0.0:
	set(value):
		hanging_amount = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var wind_shear_amount: float = 0.0:
	set(value):
		wind_shear_amount = value
		changed.emit()

@export_range(0, 96, 1) var leaf_cluster_count: int = 28:
	set(value):
		leaf_cluster_count = value
		changed.emit()

@export_range(0.05, 6.0, 0.01, "suffix:m") var min_leaf_cluster_radius_m: float = 0.22:
	set(value):
		min_leaf_cluster_radius_m = value
		changed.emit()

@export_range(0.05, 6.0, 0.01, "suffix:m") var max_leaf_cluster_radius_m: float = 0.62:
	set(value):
		max_leaf_cluster_radius_m = value
		changed.emit()

@export_range(0, 3, 1) var leaf_cluster_subdivisions: int = 1:
	set(value):
		leaf_cluster_subdivisions = value
		changed.emit()

@export var leaf_color_gradient: Gradient:
	set(value):
		leaf_color_gradient = value
		changed.emit()

func get_height_m(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(min_height_m, max_height_m)

func get_trunk_radius_m(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(min_trunk_radius_m, max_trunk_radius_m)

func get_branch_count(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(min_branch_count, max_branch_count)

func get_branch_length_m(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(min_branch_length_m, max_branch_length_m)

func get_bark_color(rng: RandomNumberGenerator) -> Color:
	if bark_color_gradient == null:
		return Color(0.34, 0.2, 0.1, 1.0)

	return bark_color_gradient.sample(rng.randf())

func get_leaf_color(rng: RandomNumberGenerator) -> Color:
	if leaf_color_gradient == null:
		return Color(0.18, 0.48, 0.15, 1.0)

	return leaf_color_gradient.sample(rng.randf())
