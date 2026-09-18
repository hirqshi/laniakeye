extends Node

## Persists a flat list of {seed, timestamp} entries to a single JSON
## file. No world/player state - just enough to regenerate the same
## system via SystemGenerator later.

const SAVE_PATH: String = "user://saves.json"

## Set by MainMenu/WorldSelect right before changing scene to the game
## world; StarSystem reads and clears this in its own _ready().
var pending_seed: int = 0

func save_seed(seed_value: int) -> void:
	var saves: Array[Dictionary] = get_saved_seeds()

	for entry: Dictionary in saves:
		if int(entry.get("seed", 0)) == seed_value:
			entry["timestamp"] = Time.get_unix_time_from_system()
			_write_saves(saves)
			return

	saves.append({
		"seed": seed_value,
		"timestamp": Time.get_unix_time_from_system(),
	})
	_write_saves(saves)

func get_saved_seeds() -> Array[Dictionary]:
	if not FileAccess.file_exists(SAVE_PATH):
		return []

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return []

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	var result: Array[Dictionary] = []

	if parsed is Array:
		for entry: Variant in parsed:
			if entry is Dictionary:
				result.append(entry)

	return result

func delete_seed(seed_value: int) -> void:
	var filtered: Array[Dictionary] = []

	for entry: Dictionary in get_saved_seeds():
		if int(entry.get("seed", 0)) != seed_value:
			filtered.append(entry)

	_write_saves(filtered)

func has_any_save() -> bool:
	return not get_saved_seeds().is_empty()

func get_last_seed() -> int:
	var saves: Array[Dictionary] = get_saved_seeds()
	if saves.is_empty():
		return 0

	var latest: Dictionary = saves[0]
	for entry: Dictionary in saves:
		if int(entry.get("timestamp", 0)) > int(latest.get("timestamp", 0)):
			latest = entry

	return int(latest.get("seed", 0))

func _write_saves(saves: Array) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to open %s for writing" % SAVE_PATH)
		return

	file.store_string(JSON.stringify(saves, "\t"))
	file.close()
