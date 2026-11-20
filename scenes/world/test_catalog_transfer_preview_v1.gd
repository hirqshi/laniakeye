extends "res://scenes/world/test_catalog_flight_cpu_v7.gd"

const TransferModel1 = preload("res://world/debug/lk_transfer_target_model.gd")
var _transfer_model = TransferModel1.new()
var _transfer_bound_far: MeshInstance3D
var _transfer_hud_s: float = 1.0
var _transfer_info: String = ""
var _transfer_status: String = "Select target; F8 prepares snapshot only"
var _transfer_request: bool = false
var _transfer_viewport: SubViewport
var _transfer_terrain: VoxelLodTerrain
var _transfer_point: Vector3
var _transfer_up: Vector3
var _transfer_elapsed: float = 0.0
var _transfer_stable: int = 0
var _transfer_warm: bool = false
var _transfer_last_stage: String = ""
var _transfer_body_id: String = ""
var _transfer_revision: int = -1

func _load_target(index: int) -> void:
	super._load_target(index)
	if not _initialised or _failed or _transfer_bound_far == _catalog_far_node:
		return
	if not _transfer_model.configure(_nav_layout, String(_context["body"]["id"])):
		_fail_gate("Transfer1 no selectable surface bodies")
		return
	_transfer_bound_far = _catalog_far_node
	_transfer_hud_s = 1.0
	print("Transfer1: BIND surface_targets=%d active=%s activation_enabled=false" % [_transfer_model.entries.size(), _context["body"]["id"]])
	_transfer_log_target()

func _transfer_log_target() -> void:
	var entry: Dictionary = _transfer_model.current()
	if not entry.is_empty():
		print("Transfer1: SELECT %s body=%s active_unchanged=%s" % [entry["label"], entry["id"], _context["body"]["id"]])

func _transfer_plan() -> Dictionary:
	var observer: LkPosition64 = _flight_absolute if _flight_active else _frame.to_absolute(_player.player_camera.global_position)
	return _transfer_model.plan(_flight_system_states(), String(_context["body"]["id"]), observer, _universe_clock.now_s())

func _transfer_prepare() -> void:
	_transfer_cancel("replaced", false)
	var entry: Dictionary = _transfer_model.current()
	if entry.is_empty() or entry["id"] == _context["body"]["id"]:
		_transfer_status = "Use current-body AUTO for this target"
		return
	var plan: Dictionary = _transfer_plan()
	if not plan["ok"]:
		_transfer_status = "Plan refused: " + str(plan["error"])
		return
	var target_context: Dictionary = _transfer_model.target_context(_context)
	if target_context.is_empty():
		_transfer_status = "Target context refused"
		return
	var manifest: Dictionary = target_context["manifest"]
	var loaded: Dictionary = BodyStore.read_journal(manifest)
	if not loaded["ok"]:
		_transfer_status = "Target journal refused: " + str(loaded["error"])
		push_error("Transfer1: " + _transfer_status)
		return
	var q: LkPosition64 = plan["fixed_surface"]
	var anchor: LkPosition64 = LkPosition64.new(floorf(q.x / 32.0) * 32.0, floorf(q.y / 32.0) * 32.0, floorf(q.z / 32.0) * 32.0)
	var source: PlanetVoxelGenerator = PlanetVoxelGenerator.new()
	source.planet_radius_m = target_context["body"]["radius_m"]
	source.terrain_height_m = 0.0
	source.noise_seed = Identity.seed63(entry["id"], "terrain", 1) & 0x7fffffff
	source._noise.seed = source.noise_seed
	var journal: LkVoxelEditJournal = loaded["journal"]
	var generator: BodyGenerator = BodyGenerator.new()
	generator.configure_body(source, anchor, journal.copy_records(), journal.get_revision(), manifest)
	# Isolated World3D: no foreign collider can enter the live player's space.
	_transfer_viewport = SubViewport.new()
	_transfer_viewport.name = "ForeignSurfaceSandbox"
	_transfer_viewport.size = Vector2i(16, 16)
	_transfer_viewport.own_world_3d = true
	_transfer_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_transfer_viewport)
	_transfer_terrain = VoxelLodTerrain.new()
	_transfer_terrain.name = "ForeignTerrainPreview"
	_transfer_terrain.generator = generator
	_transfer_terrain.mesher = VoxelMesherTransvoxel.new()
	_transfer_terrain.lod_count = 5
	_transfer_terrain.lod_distance = 32.0
	_transfer_terrain.mesh_block_size = 16
	_transfer_terrain.view_distance = 64
	_transfer_terrain.voxel_bounds = AABB(Vector3(-256.0, -256.0, -256.0), Vector3(512.0, 512.0, 512.0))
	_transfer_terrain.generate_collisions = true
	_transfer_terrain.collision_lod_count = 2
	_transfer_terrain.collision_layer = 1
	_transfer_terrain.collision_mask = 1
	_transfer_terrain.collision_update_delay = 0
	_transfer_terrain.threaded_update_enabled = false
	_transfer_terrain.visible = false
	_transfer_viewport.add_child(_transfer_terrain)
	_transfer_point = q.relative_to(anchor)
	_transfer_up = q.direction()
	var viewer: VoxelViewer = VoxelViewer.new()
	viewer.view_distance = 64
	viewer.requires_visuals = true
	viewer.requires_collisions = true
	viewer.position = _transfer_point + _transfer_up * 16.0
	_transfer_viewport.add_child(viewer)
	_transfer_elapsed = 0.0
	_transfer_stable = 0
	_transfer_warm = false
	_transfer_last_stage = ""
	_transfer_body_id = entry["id"]
	_transfer_revision = journal.get_revision()
	_transfer_status = "Preparing foreign snapshot in isolated space"
	print("Transfer1: PREPARE target=%s journal_found=%s revision=%d epoch=%.6f manifest_body=%s active=%s" % [_transfer_body_id, loaded["found"], _transfer_revision, plan["epoch"], manifest["body_id"], _context["body"]["id"]])

func _transfer_readiness() -> String:
	if not is_instance_valid(_transfer_terrain):
		return "WAIT TERRAIN"

	if not _transfer_terrain.is_inside_tree():
		return "WAIT TERRAIN TREE"

	var sandbox_world: World3D = _transfer_terrain.get_world_3d()
	if sandbox_world == null:
		return "WAIT SANDBOX WORLD"

	if sandbox_world == get_world_3d():
		return "ERROR WORLD NOT ISOLATED"

	var space: PhysicsDirectSpaceState3D = sandbox_world.direct_space_state
	if space == null:
		return "WAIT PHYSICS SPACE"
	var basis: Basis = _basis_for_up(_transfer_up)
	var offsets: Array[Vector3] = [Vector3.ZERO, basis.x * 0.6, -basis.x * 0.6, basis.z * 0.6, -basis.z * 0.6]
	var tool: VoxelToolLodTerrain = _transfer_terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var ground: Vector3 = Vector3.ZERO
	for index: int in range(offsets.size()):
		var point: Vector3 = _transfer_point + offsets[index]
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + _transfer_up * 48.0, point - _transfer_up * 48.0, 1)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return "WAIT COLLIDERS"
		var local: Vector3 = _transfer_terrain.to_local(hit["position"])
		var area: AABB = AABB(local - Vector3.ONE * 4.0, Vector3.ONE * 8.0)
		if not tool.is_area_editable(area) or not _transfer_terrain.is_area_meshed(area, 0):
			return "WAIT FLOOR DATA/MESH"
		var sdf: float = tool.get_voxel_f_interpolated(local)
		if not is_finite(sdf) or absf(sdf) > 0.1:
			return "WAIT SDF/COLLIDER"
		var normal: Vector3 = hit["normal"]
		if normal.dot(_transfer_up) < cos(deg_to_rad(_player.floor_max_angle_deg)):
			return "TARGET TOO STEEP"
		if index == 0:
			ground = hit["position"]
	var shape: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape.shape = _capsule
	shape.transform = Transform3D(basis, ground + _transfer_up * 1.4)
	shape.collision_mask = 1
	shape.margin = 0.02
	if not space.intersect_shape(shape, 1).is_empty():
		return "TARGET CAPSULE BLOCKED"
	return "SANDBOX READY"

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _initialised or _failed or _waiting:
		return
	if _transfer_request:
		_transfer_request = false
		_transfer_prepare()
	if not is_instance_valid(_transfer_viewport) or _transfer_warm:
		return
	_transfer_elapsed += delta
	var stage: String = _transfer_readiness()
	_transfer_stable = _transfer_stable + 1 if stage == "SANDBOX READY" else 0
	if stage != _transfer_last_stage:
		_transfer_last_stage = stage
		print("Transfer1: STAGE %s t=%.2f data=%d mesh=%d" % [stage, _transfer_elapsed, _transfer_terrain.debug_get_data_block_count(), _transfer_terrain.debug_get_mesh_block_count()])
	if _transfer_stable >= 5:
		_transfer_warm = true
		_transfer_status = "SANDBOX WARM; NOT ACTIVATED; F9 releases it"
		print("Transfer1: WARM target=%s revision=%d seconds=%.3f isolated=true active_unchanged=%s activation_enabled=false" % [_transfer_body_id, _transfer_revision, _transfer_elapsed, _context["body"]["id"]])
	elif _transfer_elapsed > 90.0 or stage == "ERROR WORLD NOT ISOLATED":
		_transfer_cancel("readiness failed: " + stage)
	else:
		_transfer_status = "%s %.1fs stable=%d/5" % [stage, _transfer_elapsed, _transfer_stable]

func _transfer_cancel(reason: String, report: bool = true) -> void:
	_transfer_request = false
	if is_instance_valid(_transfer_viewport):
		_transfer_viewport.queue_free()
	_transfer_viewport = null
	_transfer_terrain = null
	_transfer_warm = false
	_transfer_stable = 0
	_transfer_status = "Preview released: " + reason
	if report:
		print("Transfer1: CANCEL %s; active world unchanged" % reason)

func _unhandled_input(event: InputEvent) -> void:
	if _initialised and not _failed and event is InputEventKey and event.pressed and not event.echo and not event.alt_pressed and not event.ctrl_pressed and not event.shift_pressed:
		if event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_BRACKETRIGHT:
			_transfer_cancel("selection changed", false)
			_transfer_model.cycle(-1 if event.keycode == KEY_BRACKETLEFT else 1)
			_transfer_hud_s = 1.0
			_transfer_log_target()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F:
			_transfer_request = true
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_X:
			_transfer_cancel("X")
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _close_local_world() -> void:
	_transfer_cancel("active world closing", false)
	_transfer_bound_far = null
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if not _initialised or _failed:
		return
	_transfer_hud_s += delta
	if _transfer_hud_s >= 0.2 and not _waiting:
		_transfer_hud_s = 0.0
		var entry: Dictionary = _transfer_model.current()
		if not entry.is_empty():
			var plan: Dictionary = _transfer_plan()
			_transfer_info = "%d/%d %s | %s" % [_transfer_model.selected + 1, _transfer_model.entries.size(), entry["label"], String(entry["id"]).left(8)]
			if plan["ok"]:
				_transfer_info += " | surface gap %s" % NavData.distance_text(plan["height_m"])
	_label.text += "\n\nTRANSFER1: [ / ] target | F prepare isolated snapshot | X cancel"
	_label.text += "\n" + _transfer_info + "\n" + _transfer_status
	_label.text += "\nPREVIEW ONLY: no body switch; G still lands on ACTIVE body"
