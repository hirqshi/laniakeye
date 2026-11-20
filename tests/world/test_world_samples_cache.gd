extends SceneTree

const Samples = preload("res://world/generation/lk_world_samples.gd")
const Identity = preload("res://world/generation/lk_world_identity.gd")
const REFERENCE_ID: String = "5820d532ed6d16e5ecafa04938ae7b85"
var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("WorldSamplesCache: FAIL " + label)


func _reference(id: String, domain: String, version: int) -> float:
	return float(Identity.seed63(id, domain, version) >> 10) / Samples.UNIT_DENOMINATOR


func _worker(worker: int) -> bool:
	for i: int in range(512):
		var domain: String = "cache/thread/" + str(i % 64)
		if Samples.unit(REFERENCE_ID, domain, 1) != _reference(REFERENCE_ID, domain, 1):
			return false
		Samples.unit(REFERENCE_ID, "cache/private/" + str(worker) + "/" + str(i), 1)
	return true


func _initialize() -> void:
	Samples.clear_cache()
	var expected: float = float(380114247880983) / float(9007199254740992)
	_check(Samples.unit(REFERENCE_ID, "catalog/offset_x", 1) == expected, "cold reference")
	_check(Samples.unit(REFERENCE_ID, "catalog/offset_x", 1) == expected, "warm reference")
	_check(Samples.cache_size() == 1, "repeat does not grow cache")
	var other: String = Identity.child_id(REFERENCE_ID, "cache", "other")
	for id: String in [REFERENCE_ID, other]:
		for domain: String in ["catalog/offset_x", "a|2|b", "b"]:
			for version: int in [1, 2]:
				_check(Samples.unit(id, domain, version) == _reference(id, domain, version), "full key parity")
	Samples.clear_cache()
	_check(Samples.cache_size() == 0, "clear")
	for i: int in range(Samples.CACHE_CAPACITY + 17):
		var domain: String = "cache/evict/" + str(i)
		_check(Samples.unit(REFERENCE_ID, domain, 1) == _reference(REFERENCE_ID, domain, 1), "eviction stream parity")
	_check(Samples.cache_size() == Samples.CACHE_CAPACITY, "bounded residency")
	_check(Samples.unit(REFERENCE_ID, "catalog/offset_x", 1) == expected, "reference after eviction")
	for i: int in range(127, -1, -1):
		var domain: String = "cache/evict/" + str(i)
		_check(Samples.unit(REFERENCE_ID, domain, 1) == _reference(REFERENCE_ID, domain, 1), "reverse order parity")
	var sample: float = Samples.unit(REFERENCE_ID, "range", 1)
	_check(Samples.range_int(REFERENCE_ID, "range", 1, -3, 7) == -3 + int(floor(sample * 11.0)), "range mapping")
	var threads: Array[Thread] = []
	for worker: int in range(4):
		var thread: Thread = Thread.new()
		var error: Error = thread.start(_worker.bind(worker))
		_check(error == OK, "thread start")
		if error == OK:
			threads.append(thread)
	for thread: Thread in threads:
		_check(thread.wait_to_finish() == true, "parallel parity")
	_check(Samples.cache_size() <= Samples.CACHE_CAPACITY, "parallel bounded residency")
	Samples.clear_cache()
	if _failures == 0:
		print("WorldSamplesCache: PASS reference, full keys, eviction, reverse order, range, threads=4")
	quit(0 if _failures == 0 else 1)
