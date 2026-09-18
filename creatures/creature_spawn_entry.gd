@tool
class_name CreatureSpawnEntry
extends Resource

@export var creature_profile: CreatureProfile:
	set(value):
		creature_profile = value
		changed.emit()

@export_range(0, 50, 1) var min_count: int = 1:
	set(value):
		min_count = value
		changed.emit()

@export_range(0, 50, 1) var max_count: int = 3:
	set(value):
		max_count = value
		changed.emit()

func get_spawn_count(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(min_count, max_count)
