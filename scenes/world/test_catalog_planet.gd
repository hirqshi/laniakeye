extends "res://scenes/debug/test_voxel_edit_publication.gd"

# Integration harness, NOT a new production scene built on legacy gameplay.
# Reuses only the validated refactor-era voxel reanchor/publication test machinery.
const Definition = preload("res://world/generation/lk_universe_definition.gd")
const Context = preload("res://world/runtime/lk_body_context.gd")
const CatalogFrame = preload("res://world/runtime/lk_catalog_body_frame.gd")
const BodyStore = preload("res://world/runtime/lk_body_journal_store.gd")
const Identity = preload("res://world/generation/lk_world_identity.gd")
const OrbitMotion = preload("res://world/generation/lk_kepler_motion.gd")

# A walk reanchor builds a +-256 m patch around the player. It is a surface-
# support operation: start it only while the player has floor contact.

@export var galaxy_index: int = 0
@export var sector_x: int = 0
@export var sector_y: int = 0
@export var sector_z: int = 0
@export var system_slot: int = 0
@export var planet_slot: int = 0

var _context: Dictionary = {}
var _catalog_frame: CatalogFrame
var _manifest: Dictionary
var _diagnostic_s: float = 0.0
var _orbit_position: Array = [0.0, 0.0, 0.0]
var _initialised: bool = false

# Continuous editing state.
var _holding_dig: bool = false
var _holding_build: bool = false
var _stamp_cooldown_s: float = 0.0
var _stamp_elapsed_s: float = 0.0
var _stamp_count: int = 0
var _last_stamp_center: LkPosition64 = null
var _journal_save_pending: bool = false
var _journal_save_delay_s: float = 0.0
var _journal_autosave_s: float = 0.0

# Each held-button stamp moves the SDF by at most this amount, in metres.
# The operation remains bounded by the original spherical brush target.
const STAMP_AMOUNT_M: float = 0.25
const STAMP_INTERVAL_S: float = 0.25

# Future material hook: all materials currently use the same edit rate.
# A material system will replace this with a per-material rate multiplier.
func _edit_rate_multiplier() -> float:
	return 1.0


class BodyGenerator:
	extends EditedGenerator

	func configure_body(
		source: PlanetVoxelGenerator,
		patch_anchor: LkPosition64,
		records: PackedFloat64Array,
		revision: int,
		manifest: Dictionary
	) -> void:
		surface = source
		anchor = patch_anchor.copy()
		_records = records.duplicate()
		_revision = revision

		for i: int in range(TILE_LOCK_COUNT):
			_tile_locks.append(Mutex.new())

		_build_operation_index()

		var hashes: Array[String] = []

		for path: String in [
			"res://scenes/world/test_catalog_planet.gd",
			"res://scenes/debug/test_voxel_reanchor_edits.gd",
			"res://scenes/debug/test_voxel_rotating_planet.gd",
			"res://scenes/debug/lk_voxel_snapshot_cache.gd",
			"res://voxel/planet_voxel_generator.gd",
		]:
			hashes.append(FileAccess.get_sha256(path))

		var cache: SnapshotCache = SnapshotCache.new()

		if cache.configure(var_to_bytes([
			"catalog-body-snapshot-v2",
			manifest,
			anchor.x,
			anchor.y,
			anchor.z,
			source.planet_radius_m,
			source.terrain_height_m,
			source.noise_seed,
			_revision,
			_records,
			hashes,
		])):
			_snapshot_cache = cache
		else:
			push_warning("CatalogPlanet: snapshot cache disabled")


func _enter_tree() -> void:
	var legacy: Node = get_node_or_null(
		"/root/FloatingOriginManager"
	)

	if legacy != null:
		legacy.call("unregister")
		legacy.set_physics_process(false)


func _ready() -> void:
	# Deliberately do NOT call the old test scenes' _ready chain.
	process_physics_priority = -100

	var definition = Definition.new()
	_context = Context.resolve(
		definition,
		galaxy_index,
		sector_x,
		sector_y,
		sector_z,
		system_slot,
		planet_slot
	)

	if _context.is_empty():
		_abort_start("cannot resolve target")
		return

	_manifest = _context["manifest"].duplicate(true)

	var loaded: Dictionary = BodyStore.read_journal(_manifest)

	if not loaded["ok"]:
		_abort_start(loaded["error"])
		return

	_edit_journal = loaded["journal"]
	_edit_phase = "PASS"
	_stream = null
	_center = LkPosition64.new()

	var body: Dictionary = _context["body"]
	_catalog_frame = CatalogFrame.new(
		StringName(body["id"]),
		_context["spin"],
		0.0
	)
	_rotation = _catalog_frame

	_surface = PlanetVoxelGenerator.new()
	_surface.planet_radius_m = body["radius_m"]
	_surface.terrain_height_m = 0.0
	_surface.noise_seed = Identity.seed63(
		body["id"],
		"terrain",
		1
	) & 0x7fffffff
	_surface._noise.seed = _surface.noise_seed

	var diagonal: float = 1.0 / sqrt(2.0)
	_q0 = LkPosition64.new(
		diagonal * (float(body["radius_m"]) + 3.0),
		diagonal * (float(body["radius_m"]) + 3.0),
		0.0
	)
	_anchor = LkPosition64.new(
		floorf(_q0.x),
		floorf(_q0.y),
		floorf(_q0.z)
	)
	_anchor_lattice_origin = _anchor.copy()
	_start_fixed = _q0.copy()
	_u0 = Vector3(
		_q0.x - _anchor.x,
		_q0.y - _anchor.y,
		_q0.z - _anchor.z
	)

	_frame = LkCoordinateFrame.new()
	_frame.threshold_m = 64.0
	_frame.initialize_origin(
		_catalog_frame.body_to_inertial(_q0)
	)

	_frame.shifted.connect(func(_shift: Vector3) -> void:
		_shifts += 1
		_update_terrain_transform()
	)

	_gravity = LkGravityService.new()
	_gravity.bodies.append(LkGravityBody.new(
		StringName(body["id"]),
		_center,
		body["radius_m"],
		body["mu_m3_s2"]
	))

	_setup_visuals()

	_terrain = VoxelLodTerrain.new()
	_terrain.name = "CatalogBodyTerrain"
	_terrain.generator = _make_patch_generator(_anchor)
	_terrain.mesher = VoxelMesherTransvoxel.new()
	_terrain.lod_count = 5
	_terrain.lod_distance = 32.0
	_terrain.mesh_block_size = 16
	_terrain.view_distance = 192
	_terrain.voxel_bounds = AABB(
		Vector3(-256.0, -256.0, -256.0),
		Vector3(512.0, 512.0, 512.0)
	)
	_terrain.generate_collisions = true
	_terrain.collision_lod_count = 2
	_terrain.collision_layer = ACTIVE_LAYER
	_terrain.collision_mask = 1
	_terrain.collision_update_delay = 0
	_terrain.threaded_update_enabled = false

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.43, 0.48)
	material.roughness = 1.0
	_terrain.material = material

	add_child(_terrain)

	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_voxel_tool.set_raycast_binary_search_iterations(8)

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
	_update_terrain_transform()
	_begin_spawn()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	print(
		"CatalogPlanet: SELECT body=%s radius=%.3f km g=%.5f m/s2 period=%.3f h"
		% [
			body["id"],
			float(body["radius_m"]) / 1000.0,
			body["surface_gravity_m_s2"],
			float(_context["spin"]["period_s"]) / 3600.0,
		]
	)
	print(
		"CatalogPlanet: JOURNAL found=%s revision=%d path=%s"
		% [
			loaded["found"],
			_edit_journal.get_revision(),
			BodyStore.journal_path(_manifest),
		]
	)
	print(
		"CatalogPlanet: body-following frame; local gravity only; orbit translation retained as metadata"
	)


func _abort_start(reason: String) -> void:
	_failed = true
	set_process(false)
	set_physics_process(false)
	push_error("CatalogPlanet: START FAILED " + reason)


func _setup_visuals() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.035, 0.055)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.7, 0.8)
	environment.ambient_light_energy = 0.6

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	add_child(light)


func _make_patch_generator(
	patch_anchor: LkPosition64
) -> VoxelGeneratorScript:
	var generator: BodyGenerator = BodyGenerator.new()

	generator.configure_body(
		_surface,
		patch_anchor,
		_edit_journal.copy_records(),
		_edit_journal.get_revision(),
		_manifest
	)

	return generator


func _fixed_position() -> LkPosition64:
	return _catalog_frame.inertial_to_body(
		_frame.to_absolute(_player.global_position)
	)


func _fixed_to_local(q: LkPosition64) -> Vector3:
	return _catalog_frame.body_to_inertial(q).relative_to(
		_frame.get_origin()
	)


func _spawn_up() -> Vector3:
	var up: LkPosition64 = _catalog_frame.body_to_inertial(_q0)
	return Vector3(up.x, up.y, up.z).normalized()


func _set_patch_transform(
	patch: VoxelLodTerrain,
	patch_anchor: LkPosition64
) -> void:
	patch.global_transform = Transform3D(
		_catalog_frame.planet_basis(),
		_fixed_to_local(patch_anchor)
	)
	patch.force_update_transform()


func _update_terrain_transform() -> void:
	if _catalog_frame == null or _frame == null:
		return

	if is_instance_valid(_terrain):
		_set_patch_transform(_terrain, _anchor)

	if is_instance_valid(_pending):
		_set_patch_transform(_pending, _pending_anchor)


func _begin_spawn() -> void:
	_waiting = true
	_wait_s = 0.0
	_stable_ticks = 0
	_player.set_controllable(false)
	_player.detach_from_frame()
	_player.velocity = Vector3.ZERO
	_player.global_position = _fixed_to_local(_q0)
	_player.up_direction = _spawn_up()
	_player.dominant_body_id = StringName(_context["body"]["id"])


func _try_spawn(delta: float) -> void:
	var before: bool = _waiting
	super._try_spawn(delta)

	if before and not _waiting:
		print(
			"CatalogPlanet: READY body=%s revision=%d"
			% [
				_context["body"]["id"],
				_edit_journal.get_revision(),
			]
		)


func _save_journal() -> bool:
	return BodyStore.write_journal(_manifest, _edit_journal)


func _camera_sdf() -> float:
	var camera: Camera3D = _player.player_camera
	var local: Vector3 = _terrain.to_local(
		camera.global_position
	)
	return _voxel_tool.get_voxel_f_interpolated(local)


func _stamp_radius() -> float:
	# Grow smoothly during the first half-second of a held edit.
	var t: float = clampf(_stamp_elapsed_s / 0.5, 0.0, 1.0)
	return lerpf(0.5, STAMP_RADIUS_M, t)


func _accept_stamp(build: bool) -> void:
	var camera: Camera3D = _player.player_camera
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = (
		-camera.global_basis.z.normalized()
	)
	var point: Vector3

	# If the camera is embedded in solid terrain, a collider ray cannot help.
	# Place the first dig stamp just ahead of the camera instead.
	if not build and _camera_sdf() < 0.0:
		point = origin + forward * 1.0
	else:
		var query: PhysicsRayQueryParameters3D = (
			PhysicsRayQueryParameters3D.create(
				origin,
				origin + forward * STAMP_REACH_M,
				ACTIVE_LAYER,
				[_player.get_rid()]
			)
		)

		var hit: Dictionary = (
			get_world_3d().direct_space_state.intersect_ray(query)
		)

		if hit.is_empty():
			return

		point = hit["position"]

	var center: LkPosition64 = _catalog_frame.inertial_to_body(
		_frame.to_absolute(point)
	)
	var radius: float = _stamp_radius()

	var local: Vector3 = Vector3(
		center.x - _anchor.x,
		center.y - _anchor.y,
		center.z - _anchor.z
	)
	var extent: float = radius + 6.0

	if not _voxel_tool.is_area_editable(
		AABB(
			local - Vector3.ONE * extent,
			Vector3.ONE * extent * 2.0
		)
	):
		return

	if not _edit_journal.append_partial_sdf(
		center,
		radius,
		build,
		STAMP_AMOUNT_M
	):
		_fail_gate("cannot record body stamp")
		return

	var changed: int = _apply_local_stamp(
		center,
		radius,
		build,
		LkVoxelEditJournal.MODE_PARTIAL,
		STAMP_AMOUNT_M
	)

	if changed < 0:
		_edit_journal.remove_last()
		return

	if changed == 0:
		_edit_journal.remove_last()
		return

	_publication_center = center
	_last_stamp_center = center
	_stamp_count += 1
	_journal_save_pending = true
	_journal_save_delay_s = 0.3

	if build:
		_resolve_build_overlap(center, radius, point)


func _resolve_build_overlap(
	center: LkPosition64,
	radius: float,
	surface_point: Vector3
) -> void:
	var up: Vector3 = _player.up_direction.normalized()

	if up.length_squared() < 0.5:
		return

	var player_fixed: LkPosition64 = _fixed_position()
	var toward: LkPosition64 = center.minus(player_fixed)
	var distance: float = toward.length()

	if distance <= 0.0001:
		return

	var target_distance: float = radius + 0.8
	var direction_scale: float = target_distance / distance

	if distance >= target_distance:
		return

	var offset: LkPosition64 = LkPosition64.new(
		float(toward.x) * direction_scale,
		float(toward.y) * direction_scale,
		float(toward.z) * direction_scale
	)
	var corrected: LkPosition64 = center.minus(offset)
	_player.global_position = _fixed_to_local(corrected)

	var along: float = _player.velocity.dot(up)

	if along < 0.0:
		_player.velocity -= up * along

	# The collider may still be stale after the local stamp. Verify the SDF
	# directly and lift the player along up if the new terrain still overlaps.
	for attempt: int in range(4):
		var local: Vector3 = _terrain.to_local(
			_player.global_position
		)
		var sdf: float = _voxel_tool.get_voxel_f_interpolated(local)

		if not is_finite(sdf) or sdf >= 0.0:
			break

		_player.global_position += up * 0.25
		_player.velocity -= up * _player.velocity.dot(up)


func _finish_edit_stroke() -> void:
	if _stamp_count <= 0:
		return

	print(
		"CatalogPlanet: EDIT_STROKE body=%s stamps=%d seconds=%.2f revision=%d"
		% [
			_context["body"]["id"],
			_stamp_count,
			_stamp_elapsed_s,
			_edit_journal.get_revision(),
		]
	)

	_stamp_count = 0
	_stamp_elapsed_s = 0.0
	_last_stamp_center = null
	_journal_save_pending = true
	_journal_save_delay_s = 0.0


func _cancel_pending_patch(reason: String) -> void:
	if not is_instance_valid(_pending):
		return

	remove_child(_pending)
	_pending.queue_free()
	_pending = null
	_pending_stable_ticks = 0
	_pending_time_s = 0.0
	_build_reason = ""

	# A cancelled walk reanchor must not retain the movement pause.
	if _movement_paused:
		_resume_movement()

	print(
		"CatalogPlanet: PATCH CANCELLED reason=%s; flight available"
		% reason
	)


func _reanchor_supported() -> bool:
	# Walk reanchor is a surface-support operation. Airborne EVA terrain is
	# prepared by AutoSurface instead; starting a walk patch in mid-air makes
	# the old collider ray miss and freezes movement until timeout.
	return _player.is_on_floor()


# Descendants that own the pending patch themselves (AutoSurface staging) return
# true so this walking loop does not pause, time out or commit their sandbox.
func _walk_reanchor_blocked() -> bool:
	return false


func _physics_process(delta: float) -> void:
	if not _initialised or _failed:
		return

	if _waiting:
		_try_spawn(delta)
		return

	var step: float = _catalog_frame.advance(delta)
	_update_terrain_transform()
	_player.carry_with_frame(
		_rotation,
		step,
		float(_context["body"]["physical_bound_radius_m"]) + 1000.0
	)

	var distance: float = _anchor_distance_m()

	if not is_instance_valid(_pending):
		if (
			distance >= REANCHOR_DISTANCE_M
			and _reanchor_supported()
		):
			_start_build()
	elif not _walk_reanchor_blocked():
		_pending_time_s += delta

		if (
			not _player.is_on_floor()
			and _build_reason == "OLD COLLIDER RAY MISSED"
		):
			# The player left the surface after the walk reanchor began; the old
			# collider is no longer beneath them. Cancel now instead of freezing
			# movement until the full build timeout.
			_cancel_pending_patch(
				"airborne old collider ray missed"
			)
		else:
			if distance >= BUILD_GUARD_DISTANCE_M:
				_pause_movement()

			if _check_pending():
				_pending_stable_ticks += 1
			else:
				_pending_stable_ticks = 0

			if _pending_stable_ticks >= REQUIRED_STABLE_TICKS:
				_commit_patch()
			elif _pending_time_s > BUILD_TIMEOUT_S:
				if _build_reason == "OLD COLLIDER RAY MISSED":
					_cancel_pending_patch(
						"old collider ray missed"
					)
				else:
					_fail_gate(
						"catalog patch timeout: " + _build_reason
					)

	if _failed or not _update_stream_guard(delta):
		return

	# Continuous editing: hold LMB to dig or RMB to build.
	_stamp_cooldown_s = maxf(
		0.0,
		_stamp_cooldown_s - delta
	)

	var digging: bool = _holding_dig and not _holding_build
	var building: bool = _holding_build and not _holding_dig

	if digging or building:
		_stamp_elapsed_s += delta

		if (
			_stamp_cooldown_s <= 0.0
			and not is_instance_valid(_pending)
			and not _movement_paused
		):
			_accept_stamp(building)
			_stamp_cooldown_s = (
				STAMP_INTERVAL_S
				/ maxf(_edit_rate_multiplier(), 0.0001)
			)
	else:
		_finish_edit_stroke()

	# Preserve an interrupted stroke while terrain preparation or a movement
	# guard pauses editing. The next save flushes the already-applied changes.
	if (
		(_holding_dig or _holding_build)
		and (
			is_instance_valid(_pending)
			or _movement_paused
		)
	):
		_journal_save_pending = true
		_journal_save_delay_s = 0.0

	# Defer the relatively expensive full-journal file write until the stroke
	# pauses or a short autosave interval passes.
	if _journal_save_pending:
		_journal_save_delay_s -= delta

		if _journal_save_delay_s <= 0.0:
			_journal_save_pending = false

			if not _save_journal():
				_fail_gate("cannot save body journal")

	_journal_autosave_s += delta

	if _journal_autosave_s >= 1.5:
		_journal_autosave_s = 0.0

		if _holding_dig or _holding_build:
			if not _save_journal():
				_fail_gate("cannot autosave body journal")

	_diagnostic_s += delta

	if _diagnostic_s >= 5.0:
		_diagnostic_s = 0.0
		_orbit_position = OrbitMotion.evaluate(
			_context["orbit"],
			_catalog_frame.world_time_s
		)["position_m"]

		print(
			"CatalogPlanet: STATUS body=%s t=%.2f swaps=%d shifts=%d sdf_hit=%.5f"
			% [
				_context["body"]["id"],
				_catalog_frame.world_time_s,
				_reanchors,
				_shifts,
				_ground_mismatch_m(),
			]
		)


func _unhandled_input(event: InputEvent) -> void:
	if not _initialised:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = (
				Input.MOUSE_MODE_VISIBLE
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED
			)
		elif event.keycode == KEY_F5:
			_journal_save_pending = false
			print(
				"CatalogPlanet: SAVE ok=%s" % _save_journal()
			)
		return

	if (
		event is InputEventMouseButton
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		if event.button_index == MOUSE_BUTTON_LEFT:
			_holding_dig = event.pressed

			if event.pressed:
				_holding_build = false
				_stamp_elapsed_s = 0.0
				_stamp_count = 0
				_last_stamp_center = null
			else:
				_finish_edit_stroke()

			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_RIGHT:
			_holding_build = event.pressed

			if event.pressed:
				_holding_dig = false
				_stamp_elapsed_s = 0.0
				_stamp_count = 0
				_last_stamp_center = null
			else:
				_finish_edit_stroke()

			get_viewport().set_input_as_handled()
			return

	super._unhandled_input(event)


func _process(_delta: float) -> void:
	if not _initialised:
		return

	var body: Dictionary = _context["body"]
	_label.text = (
		"CATALOG PLANET | %s\nRadius %.2f km | g %.3f m/s2 | rotation %.2f h"
		+ "\nBody-following local frame | epoch %.1f s"
		+ "\nWaiting %s | failed %s | swaps %d | shifts %d"
		+ "\nRevision %d | anchor distance %.1f m"
		+ "\nHold LMB DIG / RMB BUILD | Esc mouse | F5 save"
		+ "\nNo spaceflight or other-body gravity in this integration slice"
	) % [
		body["id"],
		float(body["radius_m"]) / 1000.0,
		body["surface_gravity_m_s2"],
		float(_context["spin"]["period_s"]) / 3600.0,
		_catalog_frame.world_time_s,
		_waiting,
		_failed,
		_reanchors,
		_shifts,
		_edit_journal.get_revision(),
		_anchor_distance_m(),
	]
