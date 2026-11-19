extends SceneTree

const Definition = preload("res://world/generation/lk_universe_definition.gd")
const Context = preload("res://world/runtime/lk_body_context.gd")
const Store = preload("res://world/runtime/lk_body_journal_store.gd")
const Identity = preload("res://world/generation/lk_world_identity.gd")

const Catalog = preload("res://world/generation/lk_world_catalog.gd")
const Bodies = preload("res://world/generation/lk_body_catalog.gd")
const Layout = preload("res://world/generation/lk_safe_orbit_layout.gd")

const TwoPlanets = preload("res://scenes/world/test_catalog_two_planets.gd")

var _failures: int = 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("CatalogTwoPlanets: FAIL " + label)


func _initialize() -> void:
	var definition = Definition.new()
	var first: Dictionary = Context.resolve(definition, 0, 0, 0, 0, 0, 0)
	_check(not first.is_empty(), "first solid body exists")
	if first.is_empty():
		quit(1)
		return
	var catalog = Catalog.new(definition.get_universe_id(), definition.catalog_version)
	var source: Dictionary = catalog.describe_system(0, 0, 0, 0, 0)
	var physical: Dictionary = Bodies.build(source)
	var layout: Dictionary = Layout.build(physical)
	var solid: Array[int] = []
	for entry: Dictionary in layout["planets"]:
		if entry["body"]["family"] != "gas_giant":
			solid.append(int(entry["body"]["slot"]))
	_check(solid.size() >= 2, "at least two solid bodies")
	if solid.size() < 2:
		quit(1)
		return
	var second: Dictionary = Context.resolve(definition, 0, 0, 0, 0, 0, solid[1])
	_check(not second.is_empty(), "second solid body exists")
	_check(first["body"]["id"] != second["body"]["id"], "distinct body IDs")
	_check(Store.journal_path(first["manifest"]) != Store.journal_path(second["manifest"]), "distinct journal paths")
	_check(first["manifest"] != second["manifest"], "distinct cache manifests")
	var test_universe: String = Identity.child_id(first["universe_id"], "test_fixture", "two_planet_isolation_v1")
	for index: int in range(2):
		var context: Dictionary = first if index == 0 else second
		var manifest: Dictionary = context["manifest"].duplicate(true)
		manifest["universe_id"] = test_universe
		var journal: LkVoxelEditJournal = LkVoxelEditJournal.new()
		var center: LkPosition64 = LkPosition64.new(1000000.125 + index, 2000000.25, 3000000.5)
		journal.append_sphere(center, 1.0 + index, index == 0)
		_check(Store.write_journal(manifest, journal), "write journal " + str(index))
		var loaded: Dictionary = Store.read_journal(manifest)
		_check(loaded["ok"] and loaded["found"], "read journal " + str(index))
		if loaded["ok"] and loaded["found"]:
			var restored: LkVoxelEditJournal = loaded["journal"]
			_check(restored.copy_records() == journal.copy_records(), "exact journal round trip " + str(index))
			_check(restored.get_revision() == 1, "revision round trip " + str(index))
		var other: Dictionary = (second if index == 0 else first)["manifest"].duplicate(true)
		other["universe_id"] = test_universe
		var cross: Dictionary = Store.read_journal(other)
		_check(cross["ok"], "other journal readable")
		if cross["ok"] and cross["found"]:
			var other_journal: LkVoxelEditJournal = cross["journal"]
			_check(other_journal.copy_records() != journal.copy_records(), "journal isolation " + str(index))
		var path: String = Store.journal_path(manifest)
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "remove isolated journal " + str(index))
	print("CatalogTwoPlanets: body_a=%s body_b=%s" % [first["body"]["id"], second["body"]["id"]])
	if _failures == 0:
		print("CatalogTwoPlanets: PASS distinct bodies, journals, cache manifests, isolation")
	quit(0 if _failures == 0 else 1)
