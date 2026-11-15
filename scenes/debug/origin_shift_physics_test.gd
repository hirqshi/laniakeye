extends Node3D

# Isolated physics gate for LkCoordinateFrame.
# It verifies that a translation-only rebase preserves an actor's absolute
# position through its ACTUAL physics displacement. It does not require
# move_and_slide() to integrate velocity with zero integration error.
# It does NOT test voxel terrain, collision streaming, camera effects,
# RigidBody3D, or save/load.

const SIMULATION_SECONDS: float = 8.0
const SHIFT_THRESHOLD_M: float = 64.0
const MOVE_SPEED_MPS: float = 17.125
const MIN_SHIFTS: int = 2
# Godot's standard Vector3 is 32-bit. After a rebase, restoring a local
# transform can quantize its position; 0.1 mm is a practical gameplay tolerance
# while still detecting meaningful rebase drift.
const POSITION_TOLERANCE_M: float = 0.0001

var _frame: LkCoordinateFrame
var _body: CharacterBody3D
var _landmark: Node3D
var _camera: Camera3D
var _label: Label
var _landmark_absolute: LkPosition64
var _velocity: Vector3
var _elapsed: float = 0.0
var _shifts: int = 0
var _max_error: float = 0.0
var _max_landmark_error: float = 0.0
var _max_speed_error: float = 0.0
var _max_basis_error: float = 0.0
var _started: bool = false
var _finished: bool = false
var _result: String = "RUNNING"

func _ready() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.05, 0.09)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	add_child(sun)
	var ground: StaticBody3D = StaticBody3D.new()
	var ground_shape: BoxShape3D = BoxShape3D.new()
	ground_shape.size = Vector3(512.0, 1.0, 512.0)
	var ground_collision: CollisionShape3D = CollisionShape3D.new()
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	var ground_mesh: MeshInstance3D = MeshInstance3D.new()
	var ground_box: BoxMesh = BoxMesh.new()
	ground_box.size = Vector3(512.0, 1.0, 512.0)
	ground_mesh.mesh = ground_box
	ground.add_child(ground_mesh)
	add_child(ground)
	_frame = LkCoordinateFrame.new()
	_frame.threshold_m = SHIFT_THRESHOLD_M
	var start_absolute: LkPosition64 = LkPosition64.new(149597870700.0, 6371000.0, 0.0)
	if not _frame.initialize_origin(start_absolute):
		push_error("OriginShiftPhysicsTest: failed to initialize coordinate frame")
		set_physics_process(false)
		return
	_body = CharacterBody3D.new()
	_body.name = "PhysicsProbe"
	_body.position = Vector3(0.0, 1.0, 0.0)
	_body.collision_layer = 2
	_body.collision_mask = 1
	_body.floor_max_angle = deg_to_rad(55.0)
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	_body.add_child(collision)
	var camera_pivot: Node3D = Node3D.new()
	camera_pivot.position.y = 0.65
	_body.add_child(camera_pivot)
	_camera = Camera3D.new()
	_camera.near = 0.1
	_camera.far = 1000.0
	_camera.current = true
	camera_pivot.add_child(_camera)
	add_child(_body)
	_landmark = Node3D.new()
	_landmark.name = "Landmark"
	_landmark.position = Vector3(32.0, 0.5, -18.0)
	add_child(_landmark)
	if not (_frame.register_root(_body) and _frame.register_root(_landmark)):
		push_error("OriginShiftPhysicsTest: failed to register roots")
		set_physics_process(false)
		return
	_landmark_absolute = _frame.to_absolute(_landmark.global_position)
	_velocity = Vector3(MOVE_SPEED_MPS, 0.0, 0.0)
	var canvas: CanvasLayer = CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(_label)
	add_child(canvas)
	_started = true
	print("OriginShiftPhysicsTest: CharacterBody3D rebase gate started")

func _physics_process(delta: float) -> void:
	if not _started or _finished:
		return
	_elapsed += delta
	# Snapshot the actor immediately before this physics integration.
	var before_local: Vector3 = _body.global_position
	var before_absolute: LkPosition64 = _frame.to_absolute(before_local)
	# Move using the engine's normal physics integration.
	_body.velocity = _velocity
	_body.move_and_slide()
	# The expected absolute position uses the ACTUAL displacement produced by
	# move_and_slide, not an idealized velocity * delta integration.
	var actual_displacement: Vector3 = _body.global_position - before_local
	var expected_absolute: LkPosition64 = before_absolute.plus_local(actual_displacement)
	# Rebase only after the physics motion boundary.
	if _frame.maybe_shift(_body.global_position):
		_shifts += 1
	var actual_absolute: LkPosition64 = _frame.to_absolute(_body.global_position)
	_max_error = maxf(_max_error, actual_absolute.minus(expected_absolute).length())
	_max_landmark_error = maxf(_max_landmark_error, _frame.to_absolute(_landmark.global_position).minus(_landmark_absolute).length())
	_max_speed_error = maxf(_max_speed_error, absf(_body.velocity.length() - MOVE_SPEED_MPS))
	_max_basis_error = maxf(_max_basis_error, _body.global_basis.get_euler().length())
	if _elapsed >= SIMULATION_SECONDS:
		_finished = true
		_evaluate()
	_update_hud()

func _evaluate() -> void:
	var passed: bool = true
	if _shifts < MIN_SHIFTS:
		passed = false
		push_error("OriginShiftPhysicsTest: expected at least %d rebases, got %d" % [MIN_SHIFTS, _shifts])
	if _max_error > POSITION_TOLERANCE_M:
		passed = false
		push_error("OriginShiftPhysicsTest: actor rebase error %.9f m" % _max_error)
	if _max_landmark_error > POSITION_TOLERANCE_M:
		passed = false
		push_error("OriginShiftPhysicsTest: landmark rebase error %.9f m" % _max_landmark_error)
	if _max_speed_error > 0.000001:
		passed = false
		push_error("OriginShiftPhysicsTest: velocity changed by %.9f m/s" % _max_speed_error)
	if _max_basis_error > 0.000001:
		passed = false
		push_error("OriginShiftPhysicsTest: basis changed by %.9f radians" % _max_basis_error)
	if _body.global_position.length() > SHIFT_THRESHOLD_M + 1.0:
		passed = false
		push_error("OriginShiftPhysicsTest: actor escaped local origin")
	_result = "PASS" if passed else "FAIL"
	print("OriginShiftPhysicsTest: ", _result, " shifts=", _shifts, " max_actor_rebase_error=", _max_error, " max_landmark_error=", _max_landmark_error, " max_speed_error=", _max_speed_error, " max_basis_error=", _max_basis_error)

func _update_hud() -> void:
	var absolute: LkPosition64 = _frame.to_absolute(_body.global_position)
	_label.text = "CharacterBody3D origin-shift gate\nResult: %s | time %.2f / %.2f s\nShifts: %d | threshold %.0f m\nMax actor rebase error: %.9f m\nMax landmark error: %.9f m\nMax speed error: %.9f m/s\nMax basis error: %.9f rad\nAbsolute position: %.3f, %.3f, %.3f m\nLocal position: %s\nVelocity: %.3f m/s\n\nScope: translation-only rebase. No voxel, collision streaming, camera effects, RigidBody3D, or save/load integration." % [
		_result,
		_elapsed,
		SIMULATION_SECONDS,
		_shifts,
		SHIFT_THRESHOLD_M,
		_max_error,
		_max_landmark_error,
		_max_speed_error,
		_max_basis_error,
		absolute.x,
		absolute.y,
		absolute.z,
		_body.global_position,
		_body.velocity.length()
	]
