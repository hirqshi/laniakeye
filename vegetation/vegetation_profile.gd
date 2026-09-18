@tool
class_name VegetationProfile
extends Resource

@export_category("Global")
@export var is_enabled: bool = true:
	set(value):
		is_enabled = value
		changed.emit()

@export_range(1, 8, 1) var max_active_tree_layers: int = 4:
	set(value):
		max_active_tree_layers = value
		changed.emit()

@export var placement_seed_offset: int = 700_001:
	set(value):
		placement_seed_offset = value
		changed.emit()

@export_category("Tree Layers")
@export var tree_layers: Array[VegetationLayerProfile] = []:
	set(value):
		tree_layers = value
		changed.emit()

@export_category("Streaming")
@export_range(10.0, 500.0, 1.0, "suffix:m")
var chunk_size_m: float = 80.0

@export_range(1, 8, 1)
var active_chunk_radius: int = 2

@export_range(10.0, 2000.0, 1.0, "suffix:m")
var vegetation_view_distance_m: float = 280.0

@export_range(0.0, 200.0, 1.0, "suffix:m")
var vegetation_fade_margin_m: float = 35.0

func get_active_tree_layers() -> Array[VegetationLayerProfile]:
	var result: Array[VegetationLayerProfile] = []

	if not is_enabled:
		return result

	for layer: VegetationLayerProfile in tree_layers:
		if result.size() >= max_active_tree_layers:
			break

		if layer == null:
			continue

		if not layer.is_enabled:
			continue

		if layer.tree_profile == null:
			continue

		result.append(layer)

	return result
