@tool
class_name VegetationLayerProfile
extends Resource

@export_category("Identity")
@export var display_name: String = "Unnamed Tree Layer":
	set(value):
		display_name = value
		changed.emit()

@export_category("Tree")
@export var tree_profile: TreeProfile:
	set(value):
		tree_profile = value
		changed.emit()

@export_category("Distribution")
@export var is_enabled: bool = true:
	set(value):
		is_enabled = value
		changed.emit()

@export_range(0.0, 1.0, 0.001) var density: float = 0.35:
	set(value):
		density = value
		changed.emit()

@export_range(1.0, 100.0, 0.1, "suffix:m") var minimum_spacing_m: float = 10.0:
	set(value):
		minimum_spacing_m = value
		changed.emit()

@export var seed_offset: int = 0:
	set(value):
		seed_offset = value
		changed.emit()

@export_category("Biome Noise")
@export var biome_noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH:
	set(value):
		biome_noise_type = value
		changed.emit()

@export_range(0.0001, 2.0, 0.0001) var biome_noise_frequency: float = 0.04:
	set(value):
		biome_noise_frequency = value
		changed.emit()

@export_range(1, 8, 1) var biome_noise_octaves: int = 3:
	set(value):
		biome_noise_octaves = value
		changed.emit()

@export_range(-1.0, 1.0, 0.01) var biome_noise_threshold: float = 0.05:
	set(value):
		biome_noise_threshold = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var biome_noise_softness: float = 0.22:
	set(value):
		biome_noise_softness = value
		changed.emit()

@export_category("Clusters")
@export_range(0.0, 1.0, 0.01) var cluster_strength: float = 0.75:
	set(value):
		cluster_strength = value
		changed.emit()

@export_range(1.0, 2000.0, 1.0, "suffix:m") var cluster_scale_m: float = 80.0:
	set(value):
		cluster_scale_m = value
		changed.emit()

@export_range(0.0, 1.0, 0.01) var isolated_tree_chance: float = 0.02:
	set(value):
		isolated_tree_chance = value
		changed.emit()

@export_category("Surface Constraints")
@export_range(0.0, 89.0, 0.1, "suffix:°") var max_slope_deg: float = 35.0:
	set(value):
		max_slope_deg = value
		changed.emit()

@export_category("Instance Variation")
@export_range(0.1, 4.0, 0.01) var min_scale: float = 0.8:
	set(value):
		min_scale = value
		changed.emit()

@export_range(0.1, 4.0, 0.01) var max_scale: float = 1.2:
	set(value):
		max_scale = value
		changed.emit()

@export_range(0.0, 360.0, 1.0, "suffix:°") var max_yaw_variation_deg: float = 180.0:
	set(value):
		max_yaw_variation_deg = value
		changed.emit()

func get_max_slope_cos() -> float:
	return cos(deg_to_rad(max_slope_deg))
