class_name LkStarCandidateCache
extends RefCounted

const SCHEMA: int = 1
const MAX_BYTES: int = 16777216

static func digest(data: PackedByteArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish()

static func _sources(folder: String, result: Array) -> void:
	var names: PackedStringArray = DirAccess.get_files_at(folder)
	names.sort()
	for name: String in names:
		if name.ends_with(".gd"):
			var path: String = folder.path_join(name)
			result.append([path, FileAccess.get_sha256(path)])
	var dirs: PackedStringArray = DirAccess.get_directories_at(folder)
	dirs.sort()
	for name: String in dirs:
		_sources(folder.path_join(name), result)

static func manifest(definition, address: Array, radius_ly: float) -> Dictionary:
	var settings: Array = []
	for property: Dictionary in definition.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_STORAGE) == 0 or property["name"] == "script":
			continue
		var value: Variant = definition.get(property["name"])
		if typeof(value) == TYPE_OBJECT:
			return {}
		settings.append([String(property["name"]), value])
	var sources: Array = []
	_sources("res://world/generation", sources)
	_sources("res://world/runtime", sources)
	return {"schema": SCHEMA, "universe": definition.get_universe_id(), "settings": settings,
		"address": address.duplicate(), "radius_ly": radius_ly,
		"anchor": "system_star_center_galaxy_axes", "sources": sources,
		"engine": Engine.get_version_info()["string"]}

static func cache_path(key: Dictionary) -> String:
	return "user://star_candidates_v1/%s.bin" % digest(var_to_bytes(key)).hex_encode()

static func compact(report: Dictionary) -> Dictionary:
	if not report.get("ok", false) or not report.get("complete", false):
		return {}
	var stars: Array = []
	for star: Dictionary in report["stars"]:
		stars.append({"star_id": star["star_id"], "distance_ly": star["distance_ly"], "direction_galaxy": star["direction_galaxy"].duplicate()})
	return {"stars": stars, "report": {"ok": true, "complete": true,
		"planned_sectors": report["planned_sectors"], "scanned_sectors": report["scanned_sectors"],
		"matched_stars": report["matched_stars"], "query_radius_ly": report["query_radius_ly"]}}

static func valid(key: Dictionary, payload: Dictionary) -> bool:
	if key.is_empty() or not payload.has_all(["stars", "report"]) or not payload["stars"] is Array or not payload["report"] is Dictionary:
		return false
	var report: Dictionary = payload["report"]
	if not report.has_all(["ok", "complete", "planned_sectors", "scanned_sectors", "matched_stars", "query_radius_ly"]):
		return false
	if report["ok"] != true or report["complete"] != true or report["query_radius_ly"] != key.get("radius_ly", -1.0):
		return false
	for field: String in ["planned_sectors", "scanned_sectors", "matched_stars"]:
		if typeof(report[field]) != TYPE_INT or report[field] < 0:
			return false
	if report["planned_sectors"] != report["scanned_sectors"] or report["planned_sectors"] > 8192 or report["matched_stars"] != payload["stars"].size() or payload["stars"].size() > 32768:
		return false
	var seen: Dictionary = {}
	for star in payload["stars"]:
		if not star is Dictionary or not star.has_all(["star_id", "distance_ly", "direction_galaxy"]):
			return false
		if typeof(star["star_id"]) != TYPE_STRING:
			return false
		var id: String = star["star_id"]
		if id.length() != 32 or not id.is_valid_hex_number(false) or id.begins_with("-") or id.begins_with("+") or seen.has(id):
			return false
		seen[id] = true
		if typeof(star["distance_ly"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(star["distance_ly"])) or float(star["distance_ly"]) <= 0.0 or float(star["distance_ly"]) > float(key["radius_ly"]):
			return false
		if not star["direction_galaxy"] is Array or star["direction_galaxy"].size() != 3:
			return false
		var length_squared: float = 0.0
		for component in star["direction_galaxy"]:
			if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
				return false
			length_squared += float(component) * float(component)
		if absf(length_squared - 1.0) > 1.0e-6:
			return false
	return true

static func load_cache(path: String, key: Dictionary) -> Dictionary:
	if key.is_empty():
		return {"ok": false, "reason": "unsupported_definition"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "absent_or_new_fingerprint"}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "read_failed"}
	var size: int = file.get_length()
	if size < 33 or size > MAX_BYTES:
		return {"ok": false, "reason": "invalid_size"}
	var checksum: PackedByteArray = file.get_buffer(32)
	var bytes: PackedByteArray = file.get_buffer(size - 32)
	file.close()
	if digest(bytes) != checksum:
		return {"ok": false, "reason": "checksum_mismatch"}
	var decoded: Variant = bytes_to_var(bytes)
	if not decoded is Dictionary or not decoded.has_all(["key", "payload"]) or decoded["key"] != key or not decoded["payload"] is Dictionary:
		return {"ok": false, "reason": "identity_or_schema_mismatch"}
	if not valid(key, decoded["payload"]):
		return {"ok": false, "reason": "invalid_or_incomplete_candidates"}
	return {"ok": true, "payload": decoded["payload"]}

static func save_cache(path: String, key: Dictionary, payload: Dictionary) -> bool:
	if not valid(key, payload):
		return false
	var bytes: PackedByteArray = var_to_bytes({"key": key, "payload": payload})
	if bytes.size() + 32 > MAX_BYTES or DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(digest(bytes))
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
