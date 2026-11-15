extends "res://scenes/debug/test_voxel_origin_shift.gd"

# Reuse scene construction and controls only; replace the old test logic.
# Translation-only, loaded-region test. Not disk or streaming persistence.
var _phase: String = "EDIT"
var _initial: PackedFloat64Array = []
var _snapshot: PackedFloat64Array = []
var _profile: PackedFloat64Array = []
var _target64: LkPosition64
var _stroke: bool = false
var _remove: bool = true
var _settle_s: float = 0.0
var _stable: int = 0
var _start_shifts: int = 0
var _area: AABB = AABB(Vector3(-6.0, -8.0, -6.0), Vector3(12.0, 18.0, 12.0))

func _ready() -> void:
	super._ready()
	_body.position = Vector3(5.0, 3.0, 5.0)
	_body.rotation.y = PI / 4.0
	_terrain.collision_update_delay = 0
	_terrain.collision_lod_count = 1
	_terrain.threaded_update_enabled = false
	_terrain.view_distance = 256
	for child: Node in _camera.get_parent().get_children():
		if child is VoxelViewer:
			child.view_distance = 256
	_target64 = _frame.to_absolute(_terrain.to_global(Vector3.ZERO))
	_result = "LMB hold: dig OR RMB hold: build at terrain X=0 Z=0. Release to lock."
	print("BoundaryV2: fixed terrain-local brush, four-quadrant SDF and collider checks")

func _samples() -> PackedFloat64Array:
	var values: PackedFloat64Array = []
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			for y: int in range(-4, 5):
				values.append(_tool.get_voxel_f(Vector3i(x, y, z)))
	return values

func _rays() -> PackedFloat64Array:
	var heights: PackedFloat64Array = []
	for x: float in [-0.5, 0.5]:
		for z: float in [-0.5, 0.5]:
			var top: Vector3 = _terrain.to_global(Vector3(x, 8.0, z))
			var bottom: Vector3 = _terrain.to_global(Vector3(x, -8.0, z))
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(top, bottom, 1, [_body.get_rid()])
			var physical: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
			var voxel: VoxelRaycastResult = _tool.raycast(top, Vector3.DOWN, 16.0)
			if physical.is_empty() or voxel == null:
				return []
			var position: Vector3 = physical["position"]
			var height: float = _terrain.to_local(position).y
			var sdf_height: float = _terrain.to_local(top + Vector3.DOWN * voxel.distance).y
			if absf(height - sdf_height) > 0.25:
				return []
			heights.append(height)
	return heights

func _changed_quadrants(values: PackedFloat64Array) -> bool:
	for quadrant: int in range(4):
		var changed: bool = false
		for j: int in range(9):
			var i: int = quadrant * 9 + j
			var difference: float = values[i] - _initial[i]
			if (difference if _remove else -difference) > 0.01:
				changed = true
		if not changed:
			return false
	return true

func _finish_failure(reason: String) -> void:
	_phase = "FAIL"
	_result = reason
	push_error("BoundaryV2: " + reason)

func _physics_process(delta: float) -> void:
	if _terrain == null or _body == null:
		return
	if _phase == "EDIT" and _initial.is_empty():
		_wait_time += delta
		if _tool.is_area_editable(_area) and _terrain.is_area_meshed(_area, 0) and _rays().size() == 4:
			_initial = _samples()
		elif _wait_time > 30.0:
			_finish_failure("Initial SDF/collision readiness timeout")
		_absolute = _frame.to_absolute(_body.global_position)
		_update_hud()
		return
	if _phase not in ["PASS", "FAIL"]:
		_move_and_dig_controls(delta)
		if _frame.maybe_shift(_body.global_position):
			_shifts += 1
			print("BoundaryV2: rebase #", _shifts)
	var distance: Vector3 = _frame.to_local(_target64) - _body.global_position
	distance.y = 0.0
	if _phase == "EDIT":
		var left: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var right: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if left != right and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if distance.length() <= 8.0 and _tool.is_area_editable(_area):
				if not _stroke:
					_remove = left
					_stroke = true
				if left == _remove:
					_tool.mode = VoxelTool.MODE_REMOVE if _remove else VoxelTool.MODE_ADD
					_tool.grow_sphere(Vector3(0.0, -0.5 if _remove else 0.5, 0.0), 3.0, 0.35)
					_result = "Editing fixed local boundary (0, y, 0); release to lock"
		elif _stroke:
			_phase = "SETTLE"
			_settle_s = 0.0
			_result = "Waiting for changed SDF and matching colliders in all 4 quadrants"
	elif _phase == "SETTLE":
		_settle_s += delta
		if _tool.is_area_editable(_area):
			var values: PackedFloat64Array = _samples()
			var rays: PackedFloat64Array = _rays()
			var valid: bool = _changed_quadrants(values) and rays.size() == 4
			for height: float in rays:
				valid = valid and ((height < -0.05) if _remove else (height > 0.05))
			_stable = _stable + 1 if valid else 0
			if _stable >= 10:
				_snapshot = values
				_profile = rays
				_start_shifts = _shifts
				_phase = "TRAVEL"
				_result = "Snapshot locked. Trigger 2 more rebases, return within 7 m of boundary."
				print("BoundaryV2: 36 SDF samples + 4 collision heights locked: ", _profile)
		if _phase == "SETTLE" and _settle_s > 15.0:
			_finish_failure("Edit too small or SDF/collision mismatch; restart and hold brush longer")
	elif _phase == "TRAVEL" and _shifts - _start_shifts >= 2 and distance.length() <= 7.0:
		_phase = "VERIFY"
		_settle_s = 0.0
		_stable = 0
	elif _phase == "VERIFY":
		_settle_s += delta
		if _tool.is_area_editable(_area):
			var values: PackedFloat64Array = _samples()
			var rays: PackedFloat64Array = _rays()
			var valid: bool = rays.size() == 4
			for i: int in range(values.size()):
				valid = valid and absf(values[i] - _snapshot[i]) < 0.0001
			for i: int in range(rays.size()):
				valid = valid and absf(rays[i] - _profile[i]) < 0.03
			valid = valid and _frame.to_absolute(_terrain.to_global(Vector3.ZERO)).minus(_target64).length() < 0.0001
			_stable = _stable + 1 if valid else 0
			if _stable >= 10:
				_phase = "PASS"
				_result = "36 real SDF samples, 4 collider heights and absolute anchor preserved"
				print("BoundaryV2: PASS mode=", "DIG" if _remove else "BUILD", " shifts=", _shifts - _start_shifts)
		if _phase == "VERIFY" and _settle_s > 15.0:
			_finish_failure("SDF, collision profile or absolute anchor changed after rebase")
	_absolute = _frame.to_absolute(_body.global_position)
	_update_hud()

func _move_and_dig_controls(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = _body.global_basis * Vector3(input.x, 0.0, input.y)
	var vertical: float = _body.velocity.y
	if _body.is_on_floor():
		vertical = maxf(vertical, 0.0)
		if Input.is_action_just_pressed("jump"):
			vertical = 5.0
	var speed: float = 7.0 if Input.is_action_pressed("run") else 4.0
	var terrain_position: Vector3 = _terrain.to_local(_body.global_position)
	if Vector2(terrain_position.x, terrain_position.z).length() > 150.0 and direction.dot(Vector3(terrain_position.x, 0.0, terrain_position.z)) > 0.0:
		direction = Vector3.ZERO
	_body.velocity = direction * speed + Vector3.UP * (vertical - 9.81 * delta)
	_body.move_and_slide()

func _update_hud() -> void:
	var target: Vector3 = _frame.to_local(_target64) - _body.global_position
	_label.text = "BoundaryV2 | %s\n%s\nRebases after snapshot: %d / 2\nBoundary offset: x=%.2f z=%.2f m\nWASD / Shift / Space / mouse / Esc\nHold LMB OR RMB near spawn, release, travel out and back.\nRestart scene to test the opposite mode. Loaded-region test only; no persistence." % [_phase, _result, maxi(0, _shifts - _start_shifts), target.x, target.z]
