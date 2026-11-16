extends "res://scenes/debug/test_voxel_rotating_planet.gd"

const REANCHOR_DISTANCE_M: float = 96.0
const BUILD_GUARD_DISTANCE_M: float = 176.0
const ANCHOR_GRID_M: float = 32.0
const BUILD_TIMEOUT_S: float = 30.0

const ACTIVE_LAYER: int = 1
const STAGING_LAYER: int = 4

const PROFILE_TOLERANCE_M: float = 0.03
const REQUIRED_STABLE_TICKS: int = 5

var _anchor_lattice_origin: LkPosition64
var _pending: VoxelLodTerrain
var _pending_anchor: LkPosition64

var _pending_time_s: float = 0.0
var _pending_stable_ticks: int = 0
var _last_profile_error_m: float = INF
var _build_reason: String = ""

var _reanchors: int = 0
var _movement_paused: bool = false
var _failed: bool = false

var _start_fixed: LkPosition64
var _max_distance_from_start_m: float = 0.0
var _reported_distance_gate: bool = false

var _swap_position_error_m: float = 0.0
var _swap_velocity_error_mps: float = 0.0


func _ready() -> void:
	super._ready()

	_anchor_lattice_origin = _anchor.copy()
	_start_fixed = _q0.copy()

	# Gate 2a does not use the original spawn-area pillars.
	# They would otherwise disappear when the old terrain is removed.
	for child: Node in _terrain.get_children():
		if child is MeshInstance3D:
			child.queue_free()

	print(
		"VoxelReanchor: walk beyond 96 m to build the next patch. "
		+ "T changes spin. No voxel edits in this gate."
	)


func _choose_anchor(fixed: LkPosition64) -> LkPosition64:
	return LkPosition64.new(
		_anchor_lattice_origin.x
			+ roundf(
				(fixed.x - _anchor_lattice_origin.x) / ANCHOR_GRID_M
			) * ANCHOR_GRID_M,
		_anchor_lattice_origin.y
			+ roundf(
				(fixed.y - _anchor_lattice_origin.y) / ANCHOR_GRID_M
			) * ANCHOR_GRID_M,
		_anchor_lattice_origin.z
			+ roundf(
				(fixed.z - _anchor_lattice_origin.z) / ANCHOR_GRID_M
			) * ANCHOR_GRID_M
	)


func _make_patch_generator(patch_anchor: LkPosition64) -> VoxelGeneratorScript:
	var generator: AnchoredGenerator = AnchoredGenerator.new()
	generator.surface = _surface
	generator.anchor = patch_anchor.copy()
	return generator


func _set_patch_transform(
	patch: VoxelLodTerrain,
	patch_anchor: LkPosition64
) -> void:
	var rotated: LkPosition64 = _rotation.rotate(
		patch_anchor,
		_rotation.angle_rad
	)
	var center_local: LkPosition64 = _center.minus(_frame.get_origin())
	var local: LkPosition64 = rotated.plus(center_local)

	patch.global_transform = Transform3D(
		_rotation.planet_basis(),
		Vector3(local.x, local.y, local.z)
	)
	patch.force_update_transform()


func _update_terrain_transform() -> void:
	super._update_terrain_transform()

	if is_instance_valid(_pending):
		_set_patch_transform(_pending, _pending_anchor)


func _start_build() -> void:
	_pending_anchor = _choose_anchor(_fixed_position())

	var generator: VoxelGeneratorScript = _make_patch_generator(_pending_anchor)

	_pending = VoxelLodTerrain.new()
	_pending.name = "StagingTerrain"
	_pending.generator = generator
	_pending.mesher = VoxelMesherTransvoxel.new()

	_pending.lod_count = 5
	_pending.lod_distance = 64.0
	_pending.mesh_block_size = 16
	_pending.view_distance = 192

	_pending.voxel_bounds = AABB(
		Vector3(-256.0, -256.0, -256.0),
		Vector3(512.0, 512.0, 512.0)
	)

	_pending.generate_collisions = true
	_pending.collision_lod_count = 2
	_pending.collision_update_delay = 0
	_pending.threaded_update_enabled = false

	# The player collides with layer 1 only.
	# Layer 4 lets us inspect the new colliders without touching the player.
	_pending.collision_layer = STAGING_LAYER
	_pending.collision_mask = 0

	_pending.material = _terrain.material
	add_child(_pending)
	_pending.visible = false

	_set_patch_transform(_pending, _pending_anchor)

	_pending_time_s = 0.0
	_pending_stable_ticks = 0
	_last_profile_error_m = INF
	_build_reason = "WAITING FOR MESH"

	print(
		"VoxelReanchor: BUILD next_anchor=(%.0f, %.0f, %.0f)" % [
			_pending_anchor.x,
			_pending_anchor.y,
			_pending_anchor.z,
		]
	)


func _ground_hit(point: Vector3, mask: int) -> Dictionary:
	var up: Vector3 = _player.up_direction.normalized()
	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			point + up * 8.0,
			point - up * 12.0,
			mask,
			[_player.get_rid()]
		)
	)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _check_pending() -> bool:
	var local: Vector3 = _pending.to_local(_player.global_position)
	var area: AABB = AABB(
		local - Vector3(12.0, 12.0, 12.0),
		Vector3(24.0, 24.0, 24.0)
	)

	if not _pending.is_area_meshed(area, 0):
		_build_reason = "WAITING FOR MESH"
		return false

	var up: Vector3 = _player.up_direction.normalized()
	var flat: Basis = _basis_for_up(up)

	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		flat.x * 2.0,
		-flat.x * 2.0,
		flat.z * 2.0,
		-flat.z * 2.0,
	]

	var worst: float = 0.0

	for offset: Vector3 in offsets:
		var point: Vector3 = _player.global_position + offset
		var old_hit: Dictionary = _ground_hit(point, ACTIVE_LAYER)
		var new_hit: Dictionary = _ground_hit(point, STAGING_LAYER)

		if old_hit.is_empty():
			_build_reason = "OLD COLLIDER RAY MISSED"
			return false

		if new_hit.is_empty():
			_build_reason = "NEW COLLIDER RAY MISSED"
			return false

		var old_point: Vector3 = old_hit["position"]
		var new_point: Vector3 = new_hit["position"]
		worst = maxf(worst, old_point.distance_to(new_point))

	_last_profile_error_m = worst

	if worst > PROFILE_TOLERANCE_M:
		_build_reason = "COLLIDER PROFILE MISMATCH"
		return false

	_build_reason = "READY"
	return true


func _pause_movement() -> void:
	if _movement_paused:
		return

	# Keep is_controllable=true: carry_with_frame still needs to run.
	# Only the player's own walking/physics callback is paused.
	_player.set_physics_process(false)
	_movement_paused = true

	print("VoxelReanchor: movement paused at build guard; rotation continues")


func _resume_movement() -> void:
	if not _movement_paused:
		return

	_player.set_physics_process(true)
	_movement_paused = false


func _commit_patch() -> void:
	var before_position: Vector3 = _player.global_position
	var before_velocity: Vector3 = _player.velocity

	var old: VoxelLodTerrain = _terrain

	# Remove the old collider before activating the replacement.
	# Both operations happen before the player's physics callback.
	remove_child(old)

	_terrain = _pending
	_anchor = _pending_anchor.copy()
	_pending = null

	_terrain.collision_layer = ACTIVE_LAYER
	_terrain.collision_mask = 1
	_terrain.visible = true
	_terrain.force_update_transform()

	_voxel_tool = _terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_voxel_tool.set_raycast_binary_search_iterations(8)

	old.queue_free()

	_reanchors += 1
	_swap_position_error_m = (
		_player.global_position.distance_to(before_position)
	)
	_swap_velocity_error_mps = (
		_player.velocity.distance_to(before_velocity)
	)

	_resume_movement()
	_reset_stand()

	print((
		"VoxelReanchor: SWAP #%d build=%.2f s "
		+ "profile_error=%.3f mm position_change=%.6f mm "
		+ "velocity_change=%.9f m/s"
	) % [
		_reanchors,
		_pending_time_s,
		_last_profile_error_m * 1000.0,
		_swap_position_error_m * 1000.0,
		_swap_velocity_error_mps,
	])


func _fail_gate(reason: String) -> void:
	_failed = true
	_pause_movement()
	push_error("VoxelReanchor: FAIL " + reason)


func _physics_process(delta: float) -> void:
	if _waiting:
		_try_spawn(delta)
		return

	# Same rotation/carry order as Gate 1.
	var step: float = _rotation.advance(delta)
	_update_terrain_transform()
	_player.carry_with_frame(_rotation, step, CARRY_LIMIT_M)

	if _failed:
		return

	var distance: float = _anchor_distance_m()

	if not is_instance_valid(_pending):
		if distance >= REANCHOR_DISTANCE_M:
			_start_build()
	else:
		_pending_time_s += delta

		if distance >= BUILD_GUARD_DISTANCE_M:
			_pause_movement()

		if _check_pending():
			_pending_stable_ticks += 1
		else:
			_pending_stable_ticks = 0

		if _pending_stable_ticks >= REQUIRED_STABLE_TICKS:
			_commit_patch()
		elif _pending_time_s > BUILD_TIMEOUT_S:
			_fail_gate(
				"build timeout: %s; profile_error=%.6f m" % [
					_build_reason,
					_last_profile_error_m,
				]
			)

	var from_start: float = _fixed_position().minus(_start_fixed).length()
	_max_distance_from_start_m = maxf(
		_max_distance_from_start_m,
		from_start
	)

	if (
		not _reported_distance_gate
		and _reanchors >= 3
		and _max_distance_from_start_m >= 500.0
	):
		_reported_distance_gate = true
		print((
			"VoxelReanchor: DISTANCE CHECK reached "
			+ "swaps=%d distance_from_start=%.1f m. "
			+ "Return toward the starting area to test the reverse route."
		) % [
			_reanchors,
			_max_distance_from_start_m,
		])


func _unhandled_input(event: InputEvent) -> void:
	# R in the parent returns to the original spawn, which may be outside
	# the current patch. Disable that shortcut for this gate.
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_R:
			return

	super._unhandled_input(event)


func _process(delta: float) -> void:
	super._process(delta)

	var stage: String = "IDLE"
	if is_instance_valid(_pending):
		stage = "%s %.1f s | stable %d/%d" % [
			_build_reason,
			_pending_time_s,
			_pending_stable_ticks,
			REQUIRED_STABLE_TICKS,
		]

	if _failed:
		stage = "FAIL — inspect Output"

	_label.text += (
		"\n\nREANCHOR GATE 2a"
		+ "\nSwaps: %d | max distance from start: %.1f m"
		+ "\nBuild: %s"
		+ "\nRelative movement paused: %s"
		+ "\nLast collider profile difference: %.3f mm"
		+ "\nNo edits. R disabled; restart scene to reset."
	) % [
		_reanchors,
		_max_distance_from_start_m,
		stage,
		_movement_paused,
		_last_profile_error_m * 1000.0,
	]
