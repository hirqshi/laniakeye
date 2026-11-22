extends "res://scenes/world/test_catalog_world_clock.gd"

const CatalogFarMesh = preload("res://game/world/rendering/lk_catalog_far_mesh.gd")
var _catalog_far_node: CatalogFarMesh
var _catalog_far_report_s: float = 0.0


func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed:
		return
	if is_instance_valid(_catalog_far_node):
		return
	var catalog = Catalog.new(_clock_universe_id, _definition.catalog_version)
	var source: Dictionary = catalog.describe_system(galaxy_index, sector_x, sector_y, sector_z, system_slot)
	var layout: Dictionary = Layout.build(Bodies.build(source))
	if not Validator.validate(layout).is_empty():
		_fail_gate("FarMesh: invalid system layout")
		return
	_catalog_far_node = CatalogFarMesh.new()
	_catalog_far_node.name = "CatalogFarMesh"
	var material: StandardMaterial3D = _terrain.material as StandardMaterial3D
	_catalog_far_node.configure(layout, _context["body"]["id"], _player.player_camera, _frame, _universe_clock, material.albedo_color)
	_catalog_far_node.bind_surface_material(material)
	_catalog_far_node.sunlight_energy = stellar_light_energy
	add_child(_catalog_far_node)
	print("CatalogFarMesh: ATTACH body=%s epoch=%.3f shading=engine-PBR color=linear" % [_context["body"]["id"], _universe_clock.now_s()])


func _close_local_world() -> void:
	if is_instance_valid(_catalog_far_node):
		_catalog_far_node.set_albedo_debug(false)
		remove_child(_catalog_far_node)
		_catalog_far_node.queue_free()
		_catalog_far_node = null
	super._close_local_world()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		if is_instance_valid(_catalog_far_node):
			_catalog_far_node.set_albedo_debug(not _catalog_far_node.is_albedo_debug())
			print("CatalogFarMesh: ALBEDO_DEBUG %s" % _catalog_far_node.is_albedo_debug())
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _process(delta: float) -> void:
	super._process(delta)
	if not _initialised or not is_instance_valid(_catalog_far_node):
		return
	_catalog_far_node.active_ambient_energy = _stellar_environment.ambient_light_energy
	_catalog_far_node.sunlight_energy = stellar_light_energy
	var stats: Dictionary = _catalog_far_node.last_stats
	if not stats.is_empty():
		_label.text += "\nFAR MESH bodies=%d drawn=%d filtered=%d budget_omitted=%d" % [
			stats["total"], stats["bodies"].size(), stats["filtered"], stats["budget_omitted"],
		]
	_label.text += "\nNear/Far engine PBR | F7 albedo diagnostic: %s" % _catalog_far_node.is_albedo_debug()
	_catalog_far_report_s += delta
	if _catalog_far_report_s >= 30.0 and not stats.is_empty():
		_catalog_far_report_s = 0.0
		print("CatalogFarMesh: STATUS total=%d drawn=%d filtered=%d budget_omitted=%d" % [
			stats["total"], stats["bodies"].size(), stats["filtered"], stats["budget_omitted"],
		])
