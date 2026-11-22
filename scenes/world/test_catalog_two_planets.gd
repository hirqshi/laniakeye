extends "res://scenes/world/test_catalog_planet.gd"

# Two isolated catalog-body worlds. Switching restarts the local body world;
# it is NOT spaceflight, shared physics, or a live cross-body transition.
const Catalog = preload("res://game/world/generation/lk_world_catalog.gd")
const Bodies = preload("res://game/world/generation/lk_body_catalog.gd")
const Layout = preload("res://game/world/generation/lk_safe_orbit_layout.gd")
const Validator = preload("res://game/world/generation/lk_orbit_layout_validator.gd")

@export var second_body_slot: int = -1

var _definition
var _targets: Array[Dictionary] = []
var _active_index: int = -1
var _switching: bool = false


func _enter_tree() -> void:
	var legacy: Node = get_node_or_null("/root/FloatingOriginManager")
	if legacy != null:
		legacy.call("unregister")
		legacy.set_physics_process(false)


func _ready() -> void:
	process_physics_priority = -100
	_definition = Definition.new()
	if not _collect_targets():
		_abort_start("fewer than two solid bodies")
		return
	if second_body_slot < 0:
		second_body_slot = int(_targets[1]["body"]["slot"])
	_load_target(0)


func _collect_targets() -> bool:
	_targets.clear()
	var universe: String = _definition.get_universe_id()
	var catalog = Catalog.new(universe, _definition.catalog_version)
	var source: Dictionary = catalog.describe_system(galaxy_index, sector_x, sector_y, sector_z, system_slot)
	if source.is_empty():
		return false
	var physical: Dictionary = Bodies.build(source)
	var layout: Dictionary = Layout.build(physical)
	if not Validator.validate(layout).is_empty():
		return false
	var solid_slots: Array[int] = []
	for entry: Dictionary in layout["planets"]:
		var body: Dictionary = entry["body"]
		if body["family"] != "gas_giant":
			solid_slots.append(int(body["slot"]))
	if solid_slots.size() < 2:
		return false
	for slot: int in solid_slots:
		var context: Dictionary = Context.resolve(_definition, galaxy_index, sector_x, sector_y, sector_z, system_slot, slot)
		if not context.is_empty():
			_targets.append(context)
	return _targets.size() >= 2


func _target_label(context: Dictionary) -> String:
	var body: Dictionary = context["body"]
	return "%s | slot %d | radius %.1f km | g %.3f" % [
		body["id"], int(body["slot"]), float(body["radius_m"]) / 1000.0, body["surface_gravity_m_s2"],
	]


func _load_target(index: int) -> void:
	if index < 0 or index >= _targets.size() or _switching:
		return
	_switching = true
	if _active_index >= 0 and is_instance_valid(_edit_journal):
		_save_journal()
	_close_local_world()
	_active_index = index
	_context = _targets[index].duplicate(true)
	_manifest = _context["manifest"].duplicate(true)
	var loaded: Dictionary = BodyStore.read_journal(_manifest)
	if not loaded["ok"]:
		_abort_start(loaded["error"])
		_switching = false
		return
	_edit_journal = loaded["journal"]
	_edit_phase = "PASS"
	_stream = null
	_center = LkPosition64.new()
	var body: Dictionary = _context["body"]
	_catalog_frame = CatalogFrame.new(StringName(body["id"]), _context["spin"], 0.0)
	_rotation = _catalog_frame
	_surface = PlanetVoxelGenerator.new()
	_surface.planet_radius_m = body["radius_m"]
	_surface.terrain_height_m = 0.0
	_surface.noise_seed = Identity.seed63(body["id"], "terrain", 1) & 0x7fffffff
	_surface._noise.seed = _surface.noise_seed
	var diagonal: float = 1.0 / sqrt(2.0)
	_q0 = LkPosition64.new(diagonal * (float(body["radius_m"]) + 3.0), diagonal * (float(body["radius_m"]) + 3.0), 0.0)
	_anchor = LkPosition64.new(floorf(_q0.x), floorf(_q0.y), floorf(_q0.z))
	_anchor_lattice_origin = _anchor.copy()
	_start_fixed = _q0.copy()
	_u0 = Vector3(_q0.x - _anchor.x, _q0.y - _anchor.y, _q0.z - _anchor.z)
	_frame = LkCoordinateFrame.new()
	_frame.threshold_m = 64.0
	_frame.initialize_origin(_catalog_frame.body_to_inertial(_q0))
	_frame.shifted.connect(func(_shift: Vector3) -> void:
		_shifts += 1
		_update_terrain_transform()
	)
	_gravity = LkGravityService.new()
	_gravity.bodies.append(LkGravityBody.new(StringName(body["id"]), _center, body["radius_m"], body["mu_m3_s2"]))
	_setup_visuals()
	_terrain = VoxelLodTerrain.new()
	_terrain.name = "CatalogBodyTerrain"
	_terrain.generator = _make_patch_generator(_anchor)
	_terrain.mesher = VoxelMesherTransvoxel.new()
	_terrain.lod_count = 5
	_terrain.lod_distance = 32.0
	_terrain.mesh_block_size = 16
	_terrain.view_distance = 192
	_terrain.voxel_bounds = AABB(Vector3(-256.0, -256.0, -256.0), Vector3(512.0, 512.0, 512.0))
	_terrain.generate_collisions = true
	_terrain.collision_lod_count = 2
	_terrain.collision_layer = ACTIVE_LAYER
	_terrain.collision_mask = 1
	_terrain.collision_update_delay = 0
	_terrain.threaded_update_enabled = false
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.43, 0.48) if index == 0 else Color(0.55, 0.45, 0.33)
	material.roughness = 1.0
	_terrain.material = material
	add_child(_terrain)
	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_player = LkPlayerController.new()
	_player.name = "CatalogPlayer"
	_player.collision_layer = 2
	_player.collision_mask = ACTIVE_LAYER
	_player.safe_margin = 0.01
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = 1.8
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = _capsule
	_player.add_child(collision)
	var pivot: Node3D = Node3D.new()
	pivot.position.y = 0.65
	_player.add_child(pivot)
	var camera: Camera3D = Camera3D.new()
	camera.near = 0.05
	camera.far = 2000.0
	pivot.add_child(camera)
	var viewer: VoxelViewer = VoxelViewer.new()
	viewer.view_distance = 192
	viewer.requires_visuals = true
	viewer.requires_collisions = true
	_player.add_child(viewer)
	_player.camera_pivot = pivot
	_player.player_camera = camera
	_player.setup(_frame, _gravity)
	_player.set_controllable(false)
	add_child(_player)
	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(_label)
	add_child(canvas)
	_initialised = true
	_switching = false
	_update_terrain_transform()
	_begin_spawn()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("CatalogTwoPlanets: SWITCH target=%d body=%s journal=%s revision=%d" % [
		index, body["id"], BodyStore.journal_path(_manifest), _edit_journal.get_revision(),
	])


func _close_local_world() -> void:
	_initialised = false
	_waiting = true
	_failed = false
	_pending_stable_ticks = 0
	_pending_time_s = 0.0
	_reanchors = 0
	_shifts = 0
	_movement_paused = false
	_stream_hold = false
	_stream_hold_reason = ""
	_stream_hold_s = 0.0
	_stream_good_ticks = 0
	_stream_warned = false
	_publication_samples_checked = false
	_request_stamp = false
	_request_build = false
	_diagnostic_s = 0.0
	if is_instance_valid(_pending):
		remove_child(_pending)
		_pending.queue_free()
		_pending = null
	if is_instance_valid(_terrain):
		remove_child(_terrain)
		_terrain.queue_free()
		_terrain = null
	if is_instance_valid(_player):
		remove_child(_player)
		_player.queue_free()
		_player = null
	for child: Node in get_children():
		if child is CanvasLayer or child is WorldEnvironment or child is DirectionalLight3D:
			remove_child(child)
			child.queue_free()


func _make_patch_generator(patch_anchor: LkPosition64) -> VoxelGeneratorScript:
	var generator: BodyGenerator = BodyGenerator.new()
	generator.configure_body(_surface, patch_anchor, _edit_journal.copy_records(), _edit_journal.get_revision(), _manifest)
	return generator


func _unhandled_input(event: InputEvent) -> void:
	if not _initialised or _switching:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_load_target(0)
			return
		if event.keycode == KEY_2:
			_load_target(1)
			return
		if event.keycode == KEY_F5:
			print("CatalogTwoPlanets: SAVE body=%s ok=%s" % [_context["body"]["id"], _save_journal()])
			return
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and not _waiting and not _failed and not is_instance_valid(_pending):
			_request_stamp = true
			_request_build = event.button_index == MOUSE_BUTTON_RIGHT


func _process(_delta: float) -> void:
	if not _initialised:
		return
	var body: Dictionary = _context["body"]
	_label.text = ("CATALOG TWO PLANETS | active %d/2\n%s"
		+ "\nJournal revision %d | swaps %d | shifts %d"
		+ "\nWaiting %s | failed %s | switching %s"
		+ "\n1 / 2 switch isolated body world | F5 save | Esc mouse"
		+ "\nLMB DIG / RMB BUILD | aim 6-14 m away"
		+ "\nNo spaceflight or simultaneous multi-body gravity") % [
		_active_index + 1, _target_label(_context), _edit_journal.get_revision(),
		_reanchors, _shifts, _waiting, _failed, _switching,
	]
