extends SceneTree

const Cache = preload("res://game/world/runtime/lk_star_candidate_cache.gd")
const Definition = preload("res://game/world/generation/lk_universe_definition.gd")
const SpriteScene = preload("res://scenes/world/test_catalog_star_sprites.gd")
var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("StarCache: FAIL " + label)

func _initialize() -> void:
	var path: String = "user://star_cache_test_%d/cache.bin" % Time.get_ticks_usec()
	var key: Dictionary = {"schema": 1, "radius_ly": 128.0, "scope": "fixture"}
	var report: Dictionary = {"ok": true, "complete": true, "planned_sectors": 20,
		"scanned_sectors": 20, "matched_stars": 2, "query_radius_ly": 128.0,
		"stars": [{"star_id": "0123456789abcdef0123456789abcdef", "distance_ly": 12.345678901234, "direction_galaxy": [0.0, 0.0, -1.0], "location": {"heavy": "must not be cached"}},
		{"star_id": "abcdef0123456789abcdef0123456789", "distance_ly": 22.5, "direction_galaxy": [1.0, 0.0, 0.0]}]}
	var payload: Dictionary = Cache.compact(report)
	_check(Cache.valid(key, payload), "complete compact candidates")
	_check(not payload["stars"][0].has("location"), "no heavy placement/body data")
	_check(not Cache.load_cache(path, key)["ok"], "missing cache is miss")
	_check(Cache.save_cache(path, key, payload), "save")
	var loaded: Dictionary = Cache.load_cache(path, key)
	_check(loaded["ok"] and loaded["payload"] == payload, "roundtrip parity including doubles")
	var other: Dictionary = key.duplicate(true)
	other["scope"] = "other system"
	_check(not Cache.load_cache(path, other)["ok"], "reject different identity")
	var incomplete: Dictionary = payload.duplicate(true)
	incomplete["report"]["complete"] = false
	_check(not Cache.save_cache(path, key, incomplete), "reject incomplete result")
	_check(Cache.load_cache(path, key)["payload"] == payload, "rejected save preserves old cache")
	var duplicate: Dictionary = payload.duplicate(true)
	duplicate["stars"][1]["star_id"] = duplicate["stars"][0]["star_id"]
	_check(not Cache.valid(key, duplicate), "duplicate rejection")
	var nonunit: Dictionary = payload.duplicate(true)
	nonunit["stars"][0]["direction_galaxy"] = [0.0, 0.0, 2.0]
	_check(not Cache.valid(key, nonunit), "unit direction validation")
	var nonfinite: Dictionary = payload.duplicate(true)
	nonfinite["stars"][0]["distance_ly"] = INF
	_check(not Cache.valid(key, nonfinite), "finite distance validation")
	_check(Cache.save_cache(path, key, payload), "replace existing cache")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	bytes[bytes.size() - 1] = bytes[bytes.size() - 1] ^ 1
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	_check(Cache.load_cache(path, key).get("reason") == "checksum_mismatch", "corruption is miss before decoding")
	var definition = Definition.new()
	var a: Dictionary = Cache.manifest(definition, [0, 0, 0, 0, 0], 128.0)
	var b: Dictionary = Cache.manifest(definition, [0, 0, 0, 0, 0], 128.0)
	_check(not a.is_empty() and Cache.cache_path(a) == Cache.cache_path(b), "stable current fingerprint")
	_check(Cache.cache_path(a) != Cache.cache_path(Cache.manifest(definition, [0, 0, 0, 0, 1], 128.0)), "system invalidation")
	_check(Cache.cache_path(a) != Cache.cache_path(Cache.manifest(definition, [0, 0, 0, 0, 0], 64.0)), "radius invalidation")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	DirAccess.remove_absolute(path.get_base_dir())
	if _failures == 0:
		print("StarCache: PASS compact candidates, disk parity, identity, completeness, corruption, replacement, fingerprint")
	print("StarCache: run scene TWICE; second launch must log HIT and no cold sector progress")
	quit(0 if _failures == 0 else 1)
