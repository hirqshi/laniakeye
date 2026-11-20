class_name LkWorldSamples
extends RefCounted

const Identity = preload("res://world/generation/lk_world_identity.gd")
const UNIT_DENOMINATOR: float = 9007199254740992.0
const CACHE_CAPACITY: int = 4096

static var _cache: Dictionary = {}
static var _keys: Array[String] = []
static var _cursor: int = 0
static var _mutex: Mutex = Mutex.new()


# Protocol v1 is unchanged; cache residency never affects sample values.
static func unit(object_id: String, domain: String, version: int) -> float:
	# Successful IDs have fixed width; version precedes the arbitrary domain.
	var key: String = object_id + "|" + str(version) + "|" + domain
	_mutex.lock()
	if _cache.has(key):
		var cached: float = _cache[key]
		_mutex.unlock()
		return cached
	_mutex.unlock()

	# Hash outside the lock. Invalid requests retain Identity's diagnostics.
	var bits: int = Identity.seed63(object_id, domain, version)
	if bits < 0:
		return -1.0
	var sample: float = float(bits >> 10) / UNIT_DENOMINATOR
	_mutex.lock()
	# Another thread may have published this key while hashing.
	if not _cache.has(key):
		if _keys.size() < CACHE_CAPACITY:
			_keys.append(key)
		else:
			_cache.erase(_keys[_cursor])
			_keys[_cursor] = key
			_cursor = (_cursor + 1) % CACHE_CAPACITY
		_cache[key] = sample
	_mutex.unlock()
	return sample


static func clear_cache() -> void:
	_mutex.lock()
	_cache.clear()
	_keys.clear()
	_cursor = 0
	_mutex.unlock()


static func cache_size() -> int:
	_mutex.lock()
	var count: int = _cache.size()
	_mutex.unlock()
	return count


static func range_int(
	object_id: String,
	domain: String,
	version: int,
	minimum: int,
	maximum: int
) -> int:
	if maximum < minimum:
		push_error("LkWorldSamples: invalid range")
		return minimum
	var sample: float = unit(object_id, domain, version)
	if sample < 0.0:
		return minimum
	return minimum + int(floor(sample * float(maximum - minimum + 1)))
