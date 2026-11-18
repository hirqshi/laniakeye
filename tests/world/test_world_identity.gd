extends SceneTree

const Identity = preload("res://world/generation/lk_world_identity.gd")
const Definition = preload("res://world/generation/lk_universe_definition.gd")

var _failures: int = 0


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("WorldIdentity: FAIL " + label)


func _initialize() -> void:
	var universe: String = Identity.universe_id("laniakeye-development-v1")
	var system: String = Identity.child_id(universe, "system", "0,0,0/0")
	var planet: String = Identity.child_id(system, "planet", "0")

	_check(universe == "2ea0fa38efd55e55b229a89c681b9900", "universe reference vector")
	_check(system == "f1bf917f8354b63772455287b857445d", "system reference vector")
	_check(planet == "5990985abf681fa3cd22f119c8501470", "planet reference vector")
	_check(Identity.seed63(planet, "terrain", 1) == 2286056696237334204,
		"seed reference vector")
	_check(Identity.is_valid_id(planet), "canonical 128-bit ID")
	_check(not Identity.is_valid_id(planet.to_upper()), "reject noncanonical ID")
	_check(not Identity.is_valid_id("abc"), "reject invalid length")

	var terrain_before: int = Identity.seed63(planet, "terrain", 1)
	var materials: int = Identity.seed63(planet, "materials", 1)
	var terrain_after: int = Identity.seed63(planet, "terrain", 1)
	_check(terrain_before == terrain_after, "request order independence")
	_check(terrain_before != materials, "domain separation sample")
	_check(terrain_before != Identity.seed63(planet, "terrain", 2),
		"generation version separation sample")
	_check(Identity.child_id(system, "planet", "0") !=
		Identity.child_id(system, "moon", "0"), "object domain separation sample")
	_check(Identity.child_id(system, "ab", "c") !=
		Identity.child_id(system, "a", "bc"), "field boundary framing")

	var settings = Definition.new()
	_check(settings.get_universe_id() == universe, "definition root")
	settings.terrain_version = 2
	_check(settings.get_universe_id() == universe, "version does not rename universe")

	var serialized: String = JSON.stringify({"planet_id": planet})
	var decoded: Variant = JSON.parse_string(serialized)
	if decoded is Dictionary:
		_check(decoded.get("planet_id", "") == planet, "JSON round trip")
	else:
		_check(false, "JSON parse")

	print("WorldIdentity: universe=%s system=%s planet=%s" % [
		universe, system, planet,
	])
	if _failures == 0:
		print("WorldIdentity: PASS reference vectors, domains, order, versions, serialization")
	quit(0 if _failures == 0 else 1)
