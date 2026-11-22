extends "res://scenes/world/test_catalog_transfer_preview_v1.gd"

const TransferFrameMath2 = preload("res://game/debug/lk_transfer_frame_math.gd")
const TransferPool2 = preload("res://game/debug/lk_flight_sphere_pool_fused.gd")
var _handover_requested: bool = false
var _handover_is_moon: bool = false
var _handover_status: String = "Ctrl+Enter: change reference body in space; no teleport"
const HANDOVER_MIN_HEIGHT_M: float = 10000.0
const HANDOVER_MAX_HEIGHT_M: float = 2000000.0
const HANDOVER_MAX_ERROR_M: float = 0.02

func _handover_refuse(reason: String) -> void:
	_handover_status = "Refused: " + reason
	print("Transfer2: REFUSED " + reason + "; active world retained")

func _handover() -> void:
	if _waiting or _failed:
		_handover_refuse("world is not ready for reference handover")
		return
	if not _handover_motion_allowed():
		_handover_refuse("release movement keys and stop first")
		return
	if _auto_busy or _landing_preparing or is_instance_valid(_pending) or _movement_paused or _stream_hold:
		_handover_refuse("current-body preparation/publication is busy")
		return
	if not auto_surface_enabled or not cpu3_optimizations_enabled or not cpu3_share_system_states or not cpu4_optimizations_enabled:
		_handover_refuse("keep AUTO and CPU3/CPU4 enabled for this integration scene")
		return
	if float(_nav_layout.get("epoch_s", NAN)) != 0.0:
		_handover_refuse("nonzero layout epoch not supported by current body frame")
		return
	var entry: Dictionary = _transfer_model.current()
	var old_id: String = String(_context["body"]["id"])
	if entry.is_empty() or entry["id"] == old_id:
		_handover_refuse("select a different body")
		return
	if not _transfer_warm or not is_instance_valid(_transfer_terrain) or _transfer_body_id != entry["id"]:
		_handover_refuse("prepare selected target with F and wait for WARM")
		return
	var epoch: float = _universe_clock.now_s()
	var states: Dictionary = _flight_system_states()
	if states.get("system_id", "") != _nav_layout["system_id"]:
		_handover_refuse("system snapshot mismatch")
		return
	# EVA transfers the player root, not its offset camera.
	var observer: LkPosition64 = _flight_absolute if _flight_active else _player.get_absolute_position()
	# Existing body-relative model: remove old rotational carry, not orbital motion.
	var transfer_velocity: Vector3 = _player.velocity
	if not _flight_active and _player._carrier_id == _catalog_frame.body_id:
		var rel: LkPosition64 = _catalog_frame.relative_position(_frame.get_origin(), _player.global_position)
		transfer_velocity = _catalog_frame.to_inertial_velocity(transfer_velocity, rel)
	if not _flight_active and not transfer_velocity.is_finite():
		_handover_refuse("nonfinite transfer velocity")
		return
	var translated: Dictionary = TransferFrameMath2.rebase(states, old_id, entry["id"], observer, epoch)
	if not translated["ok"]:
		_handover_refuse(str(translated["error"]))
		return
	var new_observer: LkPosition64 = translated["observer"]
	var old_height: float = observer.length() - float(_context["body"]["radius_m"])
	var new_height: float = new_observer.length() - float(entry["body"]["radius_m"])
	if old_height < HANDOVER_MIN_HEIGHT_M or new_height < HANDOVER_MIN_HEIGHT_M or new_height > HANDOVER_MAX_HEIGHT_M:
		_handover_refuse("need >=10km above departure and10..2000km above destination; target height=%.1fkm" % (new_height / 1000.0))
		return
	if translated["roundtrip_error_m"] > HANDOVER_MAX_ERROR_M or translated["system_error_m"] > HANDOVER_MAX_ERROR_M:
		_handover_refuse("position roundtrip exceeds2cm; no approximate teleport allowed")
		return
	var target_context: Dictionary = _transfer_model.target_context(_context)
	if target_context.is_empty():
		_handover_refuse("target context invalid")
		return
	var loaded: Dictionary = BodyStore.read_journal(target_context["manifest"])
	if not loaded["ok"]:
		_handover_refuse("target journal: " + str(loaded["error"]))
		return
	var journal: LkVoxelEditJournal = loaded["journal"]
	if journal.get_revision() != _transfer_revision:
		_handover_refuse("target revision changed; prepare again")
		return
	var target_frame = SharedBodyFrame.new(StringName(entry["id"]), target_context["spin"], _universe_clock)
	var radius: float = float(entry["body"]["radius_m"])
	var fixed_observer: LkPosition64 = target_frame.inertial_to_body(new_observer)
	var q: LkPosition64 = LkPosition64.new(fixed_observer.x / fixed_observer.length() * radius, fixed_observer.y / fixed_observer.length() * radius, fixed_observer.z / fixed_observer.length() * radius)
	# Keep the deterministic lattice used by the old per-body spawn harness.
	var diagonal: float = 1.0 / sqrt(2.0)
	var lattice: LkPosition64 = LkPosition64.new(floorf(diagonal * (radius + 3.0)), floorf(diagonal * (radius + 3.0)), 0.0)
	var anchor_result: Dictionary = LandingPolicy.plan(q, lattice, ANCHOR_GRID_M)
	if not anchor_result["ok"]:
		_handover_refuse("target anchor rejected")
		return
	var anchor: LkPosition64 = anchor_result["anchor"]
	var pool = TransferPool2.new()
	if not pool.configure(_nav_layout, entry["id"]):
		_handover_refuse("target sphere metadata rejected")
		return
	var source: PlanetVoxelGenerator = PlanetVoxelGenerator.new()
	source.planet_radius_m = radius
	source.terrain_height_m = 0.0
	source.noise_seed = Identity.seed63(entry["id"], "terrain", 1) & 0x7fffffff
	source._noise.seed = source.noise_seed
	var generator: BodyGenerator = BodyGenerator.new()
	generator.configure_body(source, anchor, journal.copy_records(), journal.get_revision(), target_context["manifest"])
	if not _terrain.material is StandardMaterial3D:
		_handover_refuse("unsupported surface material")
		return
	var terrain: VoxelLodTerrain = _handover_make_terrain(generator, entry["body"])
	var gravity: LkGravityService = LkGravityService.new()
	var center: LkPosition64 = LkPosition64.new()
	gravity.bodies.append(LkGravityBody.new(StringName(entry["id"]), center, radius, entry["body"]["mu_m3_s2"]))
	if not _save_journal():
		terrain.free()
		_handover_refuse("departure journal/clock save failed")
		return
	# All validation and allocation finished. Do not yield between field swap,
	# origin update and renderer binding. Old terrain kept until swap succeeds.
	var saved: Dictionary = {"context": _context, "manifest": _manifest, "journal": _edit_journal,
		"body_frame": _catalog_frame, "surface": _surface, "gravity": _gravity,
		"terrain": _terrain, "anchor": _anchor, "lattice": _anchor_lattice_origin,
		"q0": _q0, "fixed": _start_fixed, "u0": _u0, "center": _center,
		"pool": _cpu4_pool, "absolute": observer.copy(),
		"velocity": _player.velocity, "carrier": _player._carrier_id,
		"residual": _player._carry_residual.copy(), "basis": _player.global_basis,
		"flight_basis": _flight_basis}
	var camera_id: int = _player.player_camera.get_instance_id()
	var basis_before: Basis = _player.player_camera.global_basis
	_context = target_context
	_manifest = target_context["manifest"].duplicate(true)
	_edit_journal = journal
	_catalog_frame = target_frame
	_rotation = target_frame
	_surface = source
	_gravity = gravity
	_center = center
	_terrain = terrain
	_anchor = anchor.copy()
	_anchor_lattice_origin = lattice
	_q0 = q.copy()
	_start_fixed = q.copy()
	_u0 = q.relative_to(anchor)
	_cpu4_pool = pool
	_flight_absolute = new_observer
	add_child(terrain)
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_voxel_tool.set_raycast_binary_search_iterations(8)
	_player.setup(_frame, gravity)
	if not _flight_active:
		_flight_basis = saved["basis"]
	if not _place_flight_absolute(new_observer):
		_handover_rollback(saved, terrain)
		_handover_refuse("coordinate-frame adapter failed; restored departure")
		return
	_catalog_far_node.configure(_nav_layout, entry["id"], _player.player_camera, _frame, _universe_clock, terrain.material.albedo_color)
	_catalog_far_node.bind_surface_material(terrain.material)
	_catalog_far_node.set_albedo_debug(_catalog_far_node.is_albedo_debug())
	var index: int = -1
	for i: int in range(_targets.size()):
		if _targets[i]["body"]["id"] == entry["id"]:
			index = i
			break
	if index < 0:
		_targets.append(target_context.duplicate(true))
		index = _targets.size() - 1
	_active_index = index
	_handover_is_moon = int(entry["moon_slot"]) >= 0
	_player.dominant_body_id = StringName(entry["id"])
	_player.detach_from_frame()
	_player.velocity = Vector3.ZERO if _flight_active else transfer_velocity
	if not _flight_active:
		print("Transfer2: VELOCITY before=%s after=%s error_mps=%.9f" % [transfer_velocity, _player.velocity, transfer_velocity.distance_to(_player.velocity)])
	_flight_landing_requested = false
	_flight_exit_ticks = 0
	_flight_height = new_height
	_flight_reference = String(entry["id"]).left(8)
	_auto_last_height = NAN
	_auto_target = null
	_auto_candidate = null
	_auto_candidate_s = 0.0
	_auto_retry_s = 0.0
	_auto_warm = false
	_auto_aligning = false
	_auto_elapsed = 0.0
	_auto_align_s = 0.0
	_auto_first_collider_s = -1.0
	_approach_forecast = {}
	_approach_drift_target = null
	_approach_drift_s = 0.0
	_warm_follow_actual = false
	_warm_blocked_s = 0.0
	_warm_recovery_note = ""
	_pending_stable_ticks = 0
	_pending_time_s = 0.0
	_landing_stage = "REFERENCE BODY CHANGED"
	_release_auto_viewer()
	_pacing_growth_active = false
	_pacing_growth_terrain = null
	_pacing_retire_until_us = Time.get_ticks_usec() + 1000000
	_nav_records.clear()
	_nav_refresh = 1.0
	_cpu3_nav_age_s = 1.0
	_cpu3_nav_last_count = -1
	_stellar_has_day_reference = false
	_update_stellar_lighting()
	var old: VoxelLodTerrain = saved["terrain"]
	old.visible = false
	old.collision_layer = 0
	remove_child(old)
	old.queue_free()
	_transfer_cancel("reference handover completed", false)
	_handover_status = "ACTIVE BODY CHANGED; descend; AUTO prepares live terrain; G walks only after checks"
	_flight_status = _handover_status
	print("Transfer2: ACTIVE from=%s to=%s epoch=%.6f height_m=%.3f roundtrip_error_m=%.9f system_error_m=%.9f camera_same=%s basis_preserved=%s journal_revision=%d eva=%s" % [old_id, entry["id"], epoch, new_height, translated["roundtrip_error_m"], translated["system_error_m"], camera_id == _player.player_camera.get_instance_id(), basis_before.is_equal_approx(_player.player_camera.global_basis), journal.get_revision(), not _flight_active])
	print("Transfer2: live_surface_ready=false; original AUTO/collision/G gates remain authoritative; sandbox used for validation/cache warmup only")

func _handover_make_terrain(generator: VoxelGeneratorScript, body: Dictionary) -> VoxelLodTerrain:
	var terrain: VoxelLodTerrain = VoxelLodTerrain.new()
	terrain.name = "TransferredBodyTerrain"
	terrain.generator = generator
	terrain.mesher = VoxelMesherTransvoxel.new()
	terrain.lod_count = 5
	terrain.lod_distance = 32.0
	terrain.view_distance = 64
	terrain.voxel_bounds = AABB(Vector3(-256.0, -256.0, -256.0), Vector3(512.0, 512.0, 512.0))
	terrain.generate_collisions = true
	terrain.collision_lod_count = 2
	terrain.collision_layer = 0
	terrain.collision_mask = 1
	terrain.collision_update_delay = 0
	terrain.threaded_update_enabled = false
	terrain.visible = false
	var material: StandardMaterial3D = _terrain.material.duplicate() as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	match String(body.get("family", "")):
		"icy": material.albedo_color = Color(0.65, 0.73, 0.8)
		"solid_moon": material.albedo_color = Color(0.47, 0.48, 0.5)
		_: material.albedo_color = Color(0.43, 0.39, 0.34)
	terrain.material = material
	return terrain

func _handover_rollback(saved: Dictionary, terrain: VoxelLodTerrain) -> void:
	_context = saved["context"]
	_manifest = saved["manifest"]
	_edit_journal = saved["journal"]
	_catalog_frame = saved["body_frame"]
	_rotation = _catalog_frame
	_surface = saved["surface"]
	_gravity = saved["gravity"]
	_center = saved["center"]
	_terrain = saved["terrain"]
	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_voxel_tool.set_raycast_binary_search_iterations(8)
	_anchor = saved["anchor"]
	_anchor_lattice_origin = saved["lattice"]
	_q0 = saved["q0"]
	_start_fixed = saved["fixed"]
	_u0 = saved["u0"]
	_cpu4_pool = saved["pool"]
	_flight_absolute = saved["absolute"]
	_flight_basis = saved["flight_basis"] if _flight_active else saved["basis"]
	_player.setup(_frame, _gravity)
	if not _place_flight_absolute(_flight_absolute):
		_fail_gate("Transfer2 rollback adapter failed; movement stopped")
	_player.velocity = saved["velocity"]
	_player._carrier_id = saved["carrier"]
	_player._carry_residual = saved["residual"].copy()
	_player.global_basis = saved["basis"]
	_flight_basis = saved["flight_basis"]
	remove_child(terrain)
	terrain.queue_free()

# Planet lighting stays exactly on the old path. Moon lighting must include
# parent's orbital translation: use full state provided by shared exact cache.
func _update_stellar_lighting() -> void:
	if not _handover_is_moon:
		super._update_stellar_lighting()
		return
	if not _initialised or not is_instance_valid(_player) or not is_instance_valid(_stellar_light_node):
		return
	var states: Dictionary = _flight_system_states()
	var state: Dictionary = {}
	for value: Dictionary in states.get("bodies", []):
		if value["id"] == _context["body"]["id"]:
			state = value
			break
	if state.is_empty():
		_stellar_light_node.light_energy = 0.0
		return
	var fixed: LkPosition64 = _fixed_position()
	_stellar_sample = TransferFrameMath2.lighting(state, [fixed.x, fixed.y, fixed.z])
	if _stellar_sample.is_empty():
		_stellar_light_node.light_energy = 0.0
		return
	_stellar_light_node.global_basis = StellarLighting.directional_basis(_stellar_sample["to_star_system"])
	var visibility: float = _stellar_sample["horizon_visibility"]
	_stellar_light_node.light_energy = maxf(stellar_light_energy, 0.0) * visibility
	_stellar_environment.ambient_light_energy = lerpf(maxf(night_ambient_energy, 0.0), maxf(day_ambient_energy, 0.0), visibility)
	_stellar_has_day_reference = true
	_stellar_was_day = _stellar_sample["above_horizon"]

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _handover_requested:
		_handover_requested = false
		if _initialised and not _failed:
			_handover()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_handover_requested = true
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _close_local_world() -> void:
	_handover_requested = false
	_handover_is_moon = false
	super._close_local_world()

func _process(delta: float) -> void:
	super._process(delta)
	if _initialised and not _failed:
		_label.text = _label.text.replace("PREVIEW ONLY: no body switch; G still lands on ACTIVE body", "TRANSFER2: Ctrl+Enter reference handover in space (10..2000km above target)")
		_label.text += "\n" + _handover_status

# TRANSFER4_MOTION_HOOK_V1: manual/default path still requires stop.
# Flight uses _flight_actual_speed; EVA uses live player velocity.
func _handover_motion_allowed() -> bool:
	var speed: float = _flight_actual_speed if _flight_active else _player.velocity.length()
	return speed <= 0.01

# TRANSFER_TOOL_REBIND_FIX_V1: voxel tool follows terrain on commit AND rollback.
