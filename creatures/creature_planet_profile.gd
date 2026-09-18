@tool
class_name CreaturePlanetProfile
extends Resource

@export var is_enabled: bool = true:
	set(value):
		is_enabled = value
		changed.emit()

@export var spawn_entries: Array[CreatureSpawnEntry] = []:
	set(value):
		spawn_entries = value
		changed.emit()

@export var placement_seed_offset: int = 800001:
	set(value):
		placement_seed_offset = value
		changed.emit()

func get_active_entries() -> Array[CreatureSpawnEntry]:
	var result: Array[CreatureSpawnEntry] = []

	if not is_enabled:
		return result

	for entry: CreatureSpawnEntry in spawn_entries:
		if entry == null or entry.creature_profile == null:
			continue
		result.append(entry)

	return result
