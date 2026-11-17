extends "res://scenes/debug/test_voxel_reanchor.gd"

@export var build_mode: bool = false

const EDIT_RADIUS_M: float = 3.0
const EDIT_WAIT_TIMEOUT_S: float = 30.0
const REQUIRED_TRAVEL_M: float = 300.0
const RETURN_RADIUS_M: float = 30.0
const SDF_COMPARE_TOLERANCE: float = 0.0001
const HEIGHT_COMPARE_TOLERANCE_M: float = 0.03

const STREAM_RELEASE_TICKS: int = 5
const STREAM_LOOKAHEAD_M: float = 2.0

var _stream_hold: bool = false
var _stream_hold_reason: String = ""
var _stream_good_ticks: int = 0
var _stream_hold_s: float = 0.0
var _stream_warned: bool = false
var _ground_probe_log_usec: int = 0
var _edit_ray_log_usec: int = 0

class EditedGenerator:
	extends VoxelGeneratorScript

	var surface: PlanetVoxelGenerator
	var anchor: LkPosition64

	var _records: PackedFloat64Array = []
	var _revision: int = 0


	# Call once, before assigning the generator to a terrain.
	func configure(
		source: PlanetVoxelGenerator,
		patch_anchor: LkPosition64,
		records: PackedFloat64Array,
		revision: int
	) -> void:
		surface = source
		anchor = patch_anchor.copy()
		_records = records.duplicate()
		_revision = revision


	func get_revision() -> int:
		return _revision


	func _get_used_channels_mask() -> int:
		return 1 << VoxelBuffer.CHANNEL_SDF


	func _generate_block(
		buffer: VoxelBuffer,
		origin: Vector3i,
		lod: int
	) -> void:
		var base: AnchoredGenerator = AnchoredGenerator.new()
		base.surface = surface
		base.anchor = anchor
		base._generate_block(buffer, origin, lod)

		# Order matters: build-after-dig is not dig-after-build.
		for index: int in range(0, _records.size(), 5):
			_apply_sphere(buffer, origin, lod, index)


	func _apply_sphere(
		buffer: VoxelBuffer,
		origin: Vector3i,
		lod: int,
		index: int
	) -> void:
		var size: Vector3i = buffer.get_size()
		var stride: float = float(1 << lod)

		var cx: float = _records[index] - anchor.x - float(origin.x)
		var cy: float = _records[index + 1] - anchor.y - float(origin.y)
		var cz: float = _records[index + 2] - anchor.z - float(origin.z)

		var radius: float = _records[index + 3]
		var build: bool = _records[index + 4] > 0.5
		var reach: float = radius + 4.0 * stride

		var x0: int = maxi(0, int(ceil((cx - reach) / stride)))
		var y0: int = maxi(0, int(ceil((cy - reach) / stride)))
		var z0: int = maxi(0, int(ceil((cz - reach) / stride)))

		var x1: int = mini(size.x - 1, int(floor((cx + reach) / stride)))
		var y1: int = mini(size.y - 1, int(floor((cy + reach) / stride)))
		var z1: int = mini(size.z - 1, int(floor((cz + reach) / stride)))

		if x0 > x1 or y0 > y1 or z0 > z1:
			return

		var reach_squared: float = reach * reach

		for x: int in range(x0, x1 + 1):
			var dx: float = float(x) * stride - cx

			for y: int in range(y0, y1 + 1):
				var dy: float = float(y) * stride - cy

				for z: int in range(z0, z1 + 1):
					var dz: float = float(z) * stride - cz
					var distance_squared: float = (
						dx * dx + dy * dy + dz * dz
					)

					if distance_squared >= reach_squared:
						continue

					var sphere_sdf: float = (
						sqrt(distance_squared) - radius
					) / stride

					var current: float = buffer.get_voxel_f(
						x, y, z, VoxelBuffer.CHANNEL_SDF
					)

					var result: float
					if build:
						result = minf(current, sphere_sdf)
					else:
						result = maxf(current, -sphere_sdf)

					buffer.set_voxel_f(
						clampf(result, -4.0, 4.0),
						x, y, z,
						VoxelBuffer.CHANNEL_SDF
					)


var _edit_center: LkPosition64
var _edit_grid: Vector3i
var _edit_up: Vector3
var _edit_axes: Basis

var _edit_phase: String = "INITIAL"
var _edit_wait_s: float = 0.0
var _edit_stable: int = 0

var _sdf_reference: PackedFloat64Array = []
var _height_reference: PackedFloat64Array = []

var _reference_reanchors: int = 0
var _travelled_far: bool = false
var _max_edit_distance_m: float = 0.0
var _changed_samples: int = 0

var _edit_journal: LkVoxelEditJournal = LkVoxelEditJournal.new()


func _ready() -> void:
	_test_journal_snapshot()
	super._ready()
	_terrain.lod_distance = 32.0
	
	# Place the edit a short distance from spawn, not under the capsule.
	var nearby: LkPosition64 = _q0.plus_local(Vector3(0.0, 0.0, -8.0))
	_edit_up = nearby.direction()
	_edit_axes = _basis_for_up(_edit_up)

	var radius: float = _surface._get_surface_radius(_edit_up)
	var offset: float = 0.5 if build_mode else -0.5

	_edit_center = LkPosition64.new(
		float(_edit_up.x) * (radius + offset),
		float(_edit_up.y) * (radius + offset),
		float(_edit_up.z) * (radius + offset)
	)

	_edit_grid = Vector3i(
		int(roundf(_edit_center.x)),
		int(roundf(_edit_center.y)),
		int(roundf(_edit_center.z))
	)
	
	if not _edit_journal.append_sphere(
		_edit_center,
		EDIT_RADIUS_M,
		build_mode
	):
		_edit_failure("failed to create initial journal operation")
		return
		
	# Replace the initial generator before the first physics frame.
	_terrain.generator = _make_patch_generator(_anchor)

	print("VoxelEditReanchor: mode=%s center=(%.3f, %.3f, %.3f)" % [
		_edit_mode(),
		_edit_center.x,
		_edit_center.y,
		_edit_center.z,
	])


func _edit_mode() -> String:
	return "BUILD" if build_mode else "DIG"


func _configure_pending_patch() -> void:
	_pending.lod_distance = 32.0


func _make_patch_generator(
	patch_anchor: LkPosition64
) -> VoxelGeneratorScript:
	var generator: EditedGenerator = EditedGenerator.new()

	generator.configure(
		_surface,
		patch_anchor,
		_edit_journal.copy_records(),
		_edit_journal.get_revision()
	)

	print(
		"VoxelJournal: generator revision=%d operations=%d anchor=(%.0f,%.0f,%.0f)"
		% [
			generator.get_revision(),
			_edit_journal.get_count(),
			patch_anchor.x,
			patch_anchor.y,
			patch_anchor.z,
		]
	)

	return generator


func _sample_voxel(q: Vector3i) -> Vector3i:
	return Vector3i(
		q.x - int(_anchor.x),
		q.y - int(_anchor.y),
		q.z - int(_anchor.z)
	)


func _edit_area() -> AABB:
	var center: Vector3 = Vector3(_sample_voxel(_edit_grid))
	return AABB(center - Vector3.ONE * 6.0, Vector3.ONE * 12.0)


func _read_edit_samples() -> PackedFloat64Array:
	var values: PackedFloat64Array = []

	for x: int in range(-3, 4):
		for y: int in range(-3, 4):
			for z: int in range(-3, 4):
				var q: Vector3i = _edit_grid + Vector3i(x, y, z)
				values.append(
					_voxel_tool.get_voxel_f(_sample_voxel(q))
				)

	return values


func _count_changed_samples(values: PackedFloat64Array) -> int:
	var changed: int = 0
	var index: int = 0

	for x: int in range(-3, 4):
		for y: int in range(-3, 4):
			for z: int in range(-3, 4):
				var q: Vector3i = _edit_grid + Vector3i(x, y, z)
				var q64: LkPosition64 = LkPosition64.new(q.x, q.y, q.z)

				var base: float = clampf(
					q64.length()
					- _surface._get_surface_radius(q64.direction()),
					-4.0,
					4.0
				)

				var difference: float = values[index] - base
				if (difference < -0.01) if build_mode else (difference > 0.01):
					changed += 1

				index += 1

	return changed


func _fixed_to_local(q: LkPosition64) -> Vector3:
	var rotated: LkPosition64 = _rotation.rotate(q, _rotation.angle_rad)
	var local: LkPosition64 = (
		_center.minus(_frame.get_origin()).plus(rotated)
	)
	return Vector3(local.x, local.y, local.z)


func _read_edit_heights() -> PackedFloat64Array:
	var heights: PackedFloat64Array = []
	var report: PackedStringArray = []
	var missing: int = 0

	for x: float in [-1.0, 0.0, 1.0]:
		for z: float in [-1.0, 0.0, 1.0]:
			# Fixed millimetre-scale offset avoids deliberately symmetric
			# probe positions. Identical for snapshot and verification.
			var offset: Vector3 = (
				_edit_axes.x * (x + 0.00137)
				+ _edit_axes.z * (z + 0.00219)
			)
			var q: LkPosition64 = _edit_center.plus_local(offset)

			var top: Vector3 = _fixed_to_local(
				q.plus_local(_edit_up * 8.0)
			)
			var bottom: Vector3 = _fixed_to_local(
				q.plus_local(-_edit_up * 8.0)
			)

			var query: PhysicsRayQueryParameters3D = (
				PhysicsRayQueryParameters3D.create(
					top,
					bottom,
					ACTIVE_LAYER,
					[_player.get_rid()]
				)
			)

			var hit: Dictionary = (
				get_world_3d().direct_space_state.intersect_ray(query)
			)

			if hit.is_empty():
				missing += 1
				report.append(
					"(%.0f,%.0f)=MISS" % [x, z]
				)
				continue

			var point: Vector3 = hit["position"]
			var hit_relative: LkPosition64 = (
				_rotation.relative_position(
					_frame.get_origin(),
					point
				)
			)
			var fixed: LkPosition64 = _rotation.rotate(
				hit_relative,
				-_rotation.angle_rad
			)
			var difference: LkPosition64 = fixed.minus(q)

			var height: float = (
				difference.x * float(_edit_up.x)
				+ difference.y * float(_edit_up.y)
				+ difference.z * float(_edit_up.z)
			)

			heights.append(height)
			report.append(
				"(%.0f,%.0f)=%.5f" % [x, z, height]
			)

	if missing > 0:
		var now_usec: int = Time.get_ticks_usec()

		if now_usec - _edit_ray_log_usec >= 2000000:
			_edit_ray_log_usec = now_usec

			var area: AABB = _edit_area()
			var editable: bool = _voxel_tool.is_area_editable(area)
			var sdf_error: float = -1.0

			if editable and not _sdf_reference.is_empty():
				var values: PackedFloat64Array = _read_edit_samples()
				sdf_error = 0.0

				for i: int in range(values.size()):
					sdf_error = maxf(
						sdf_error,
						absf(values[i] - _sdf_reference[i])
					)

			print(
				"VoxelEditRays: phase=%s missing=%d/9 distance=%.2f m anchor=(%.0f,%.0f,%.0f) editable=%s meshed=%s sdf_error=%.8f rays=%s"
				% [
					_edit_phase,
					missing,
					_fixed_position().minus(_edit_center).length(),
					_anchor.x,
					_anchor.y,
					_anchor.z,
					editable,
					_terrain.is_area_meshed(area, 0),
					sdf_error,
					str(report),
				]
			)

		# Do not compare an incomplete profile against the snapshot.
		return []

	return heights


func _edit_failure(reason: String) -> void:
	_edit_phase = "FAIL"
	_fail_gate("EDIT " + reason)


func _stream_readiness_reason() -> String:
	if not is_instance_valid(_terrain):
		return "NO ACTIVE TERRAIN"

	var current: Vector3 = _player.global_position

	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var direction: Vector3 = (
		_player.global_basis
		* Vector3(input_dir.x, 0.0, input_dir.y)
	)

	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
	else:
		direction = Vector3.ZERO

	var points: Array[Vector3] = [
		current,
		current + direction * STREAM_LOOKAHEAD_M,
	]

	var tool: VoxelToolLodTerrain = _terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF

	for i: int in range(points.size()):
		var local: Vector3 = _terrain.to_local(points[i])
		var area: AABB = AABB(
			local - Vector3(3.0, 4.0, 3.0),
			Vector3(6.0, 8.0, 6.0)
		)

		if not tool.is_area_editable(area):
			return "CURRENT DATA" if i == 0 else "NEXT DATA"

	return ""


func _update_stream_guard(delta: float) -> bool:
	var reason: String = _stream_readiness_reason()

	if not reason.is_empty():
		_stream_good_ticks = 0
		_stream_hold_s += delta

		if not _stream_hold or reason != _stream_hold_reason:
			print(
				"VoxelEditReanchor: STREAM HOLD reason=%s anchor_distance=%.1f m pending=%s"
				% [
					reason,
					_anchor_distance_m(),
					is_instance_valid(_pending),
				]
			)

		_stream_hold = true
		_stream_hold_reason = reason

		if _player.is_physics_processing():
			print(
				"StreamGuardTrace: PAUSE reason=%s airborne=%s pending=%s"
				% [
					reason,
					not _player.is_on_floor(),
					is_instance_valid(_pending),
				]
			)

		_player.set_physics_process(false)

		if _stream_hold_s >= 15.0 and not _stream_warned:
			_stream_warned = true
			push_warning(
				"VoxelEditReanchor: stream hold exceeded 15 s; "
				+ "player remains paused, inspect readiness reason"
			)

		return false

	if _stream_hold:
		_stream_good_ticks += 1

		if _stream_good_ticks < STREAM_RELEASE_TICKS:
			_player.set_physics_process(false)
			return false

		print(
			"VoxelEditReanchor: STREAM RESUME after %.2f s; reason=%s"
			% [_stream_hold_s, _stream_hold_reason]
		)

		_stream_hold = false
		_stream_hold_reason = ""
		_stream_hold_s = 0.0
		_stream_good_ticks = 0
		_stream_warned = false

	# The build guard or a failed gate may still own the pause.
	if not _movement_paused and not _failed:
		_player.set_physics_process(true)

	return true


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if _waiting or _failed:
		return

	if not _update_stream_guard(delta):
		return

	if _edit_phase in ["PASS", "FAIL"]:
		return

	var edit_distance: float = _fixed_position().minus(_edit_center).length()
	_max_edit_distance_m = maxf(_max_edit_distance_m, edit_distance)

	if _edit_phase == "TRAVEL":
		if (
			edit_distance >= REQUIRED_TRAVEL_M
			and _reanchors - _reference_reanchors >= 3
		):
			_travelled_far = true

		if _travelled_far and edit_distance <= RETURN_RADIUS_M:
			_edit_phase = "VERIFY"
			_edit_wait_s = 0.0
			_edit_stable = 0
			print("VoxelEditReanchor: returned; verifying actual SDF and colliders")
		return

	_edit_wait_s += delta

	var area: AABB = _edit_area()
	if (
		not _voxel_tool.is_area_editable(area)
		or not _terrain.is_area_meshed(area, 0)
	):
		if _edit_wait_s > EDIT_WAIT_TIMEOUT_S:
			_edit_failure("data/mesh readiness timeout")
		return

	var values: PackedFloat64Array = _read_edit_samples()
	var heights: PackedFloat64Array = _read_edit_heights()

	if heights.size() != 9:
		_edit_stable = 0
		if _edit_wait_s > EDIT_WAIT_TIMEOUT_S:
			_edit_failure("expected 9 physical ray hits")
		return

	if _edit_phase == "INITIAL":
		_changed_samples = _count_changed_samples(values)

		# All nine hits must be on the edited side of the original
		# spherical brush centre: mound above, cavity below.
		var edited_profile: bool = true
		for height: float in heights:
			edited_profile = edited_profile and (
				height > 0.5 if build_mode else height < -0.5
			)

		if _changed_samples == 0 or not edited_profile:
			_edit_stable = 0
			if _edit_wait_s > EDIT_WAIT_TIMEOUT_S:
				_edit_failure("edit did not change both SDF and collision profile")
			return

		_edit_stable += 1
		if _edit_stable >= 10:
			_sdf_reference = values
			_height_reference = heights
			_reference_reanchors = _reanchors
			_edit_phase = "TRAVEL"

			print((
				"VoxelEditReanchor: SNAPSHOT mode=%s samples=%d changed=%d "
				+ "physical_hits=%d. Walk 300 m away, then return."
			) % [
				_edit_mode(),
				values.size(),
				_changed_samples,
				heights.size(),
			])
		return

	var max_sdf_error: float = 0.0
	var max_height_error: float = 0.0

	for i: int in range(values.size()):
		max_sdf_error = maxf(
			max_sdf_error,
			absf(values[i] - _sdf_reference[i])
		)

	for i: int in range(heights.size()):
		max_height_error = maxf(
			max_height_error,
			absf(heights[i] - _height_reference[i])
		)

	var valid: bool = (
		max_sdf_error <= SDF_COMPARE_TOLERANCE
		and max_height_error <= HEIGHT_COMPARE_TOLERANCE_M
	)
	_edit_stable = _edit_stable + 1 if valid else 0

	if _edit_stable >= 10:
		_edit_phase = "PASS"
		print((
			"VoxelEditReanchor: PASS mode=%s samples=343 hits=9 "
			+ "swaps=%d max_distance=%.1f m sdf_error=%.8f "
			+ "height_error=%.3f mm"
		) % [
			_edit_mode(),
			_reanchors - _reference_reanchors,
			_max_edit_distance_m,
			max_sdf_error,
			max_height_error * 1000.0,
		])
	elif _edit_wait_s > EDIT_WAIT_TIMEOUT_S:
		_edit_failure(
			"verification mismatch sdf=%.8f height=%.6f m" % [
				max_sdf_error,
				max_height_error,
			]
		)


func _log_ground_probe_failure(point: Vector3) -> void:
	var now_usec: int = Time.get_ticks_usec()

	if now_usec - _ground_probe_log_usec < 1000000:
		return

	_ground_probe_log_usec = now_usec

	var up: Vector3 = _player.up_direction.normalized()
	var flat: Basis = _basis_for_up(up)

	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		flat.x * 0.15,
		-flat.x * 0.15,
		flat.z * 0.15,
		-flat.z * 0.15,
	]

	var results: PackedStringArray = []

	for offset: Vector3 in offsets:
		var hit: Dictionary = _ground_hit(
			point + offset,
			ACTIVE_LAYER
		)

		if hit.is_empty():
			results.append("MISS")
		else:
			var hit_point: Vector3 = hit["position"]
			var height: float = (point - hit_point).dot(up)
			results.append("%.4f" % height)

	var terrain_local: Vector3 = _terrain.to_local(point)

	print(
		"GroundProbeDebug: floor=%s layer=%d player_mask=%d terrain_local=%s probes_center_right_left_back_forward=%s"
		% [
			_player.is_on_floor(),
			_terrain.collision_layer,
			_player.collision_mask,
			terrain_local,
			str(results),
		]
	)


func _test_journal_snapshot() -> void:
	var journal: LkVoxelEditJournal = LkVoxelEditJournal.new()
	var source_center: LkPosition64 = LkPosition64.new(
		4505204.761,
		4505204.761,
		-8.0
	)

	var added_first: bool = journal.append_sphere(
		source_center,
		3.0,
		true
	)
	var first: PackedFloat64Array = journal.copy_records()

	# Mutating the input object must not change a recorded operation.
	source_center.x = 123.0

	var added_second: bool = journal.append_sphere(
		LkPosition64.new(4505204.761, 4505204.761, -8.0),
		1.0,
		false
	)
	var second: PackedFloat64Array = journal.copy_records()

	var passed: bool = (
		added_first
		and added_second
		and first.size() == 5
		and second.size() == 10
		and first[0] == 4505204.761
		and second[0] == 4505204.761
		and first[4] == 1.0
		and second[9] == 0.0
		and journal.get_revision() == 2
		and journal.get_count() == 2
	)

	# Mutating a returned array must not change journal storage.
	second[0] = -999.0
	var third: PackedFloat64Array = journal.copy_records()
	passed = passed and third[0] == 4505204.761

	if passed:
		print(
			"VoxelJournal: PASS snapshot isolation, input copy, operation order, revision"
		)
	else:
		push_error("VoxelJournal: FAIL snapshot isolation test")


func _process(delta: float) -> void:
	super._process(delta)

	var edit_distance: float = _fixed_position().minus(_edit_center).length()
	var toward: LkPosition64 = _edit_center.minus(_fixed_position())

	_label.text += (
		"\n\nEDIT GATE 2b | %s | %s"
		+ "\nDistance to edit: %.1f m | max %.1f m"
		+ "\nSwaps after snapshot: %d | travelled far: %s"
		+ "\nPlanet-fixed direction to edit: (%.1f, %.1f, %.1f)"
	) % [
		_edit_mode(),
		_edit_phase,
		edit_distance,
		_max_edit_distance_m,
		_reanchors - _reference_reanchors,
		_travelled_far,
		toward.x,
		toward.y,
		toward.z,
	]
	_label.text += "\nStream hold: %s | reason: %s | wait: %.1f s" % [
		_stream_hold,
		_stream_hold_reason,
		_stream_hold_s,
	]
