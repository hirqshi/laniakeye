extends SceneTree

const Policy6 = preload("res://game/debug/lk_surface_contact_policy.gd")
const Scene6 = preload("res://scenes/world/test_catalog_surface_contact_v6.gd")
var _failures: int = 0

class NativeContactProbe:
	extends Node3D
	var actor: CharacterBody3D
	var elapsed: float = 0.0
	var stable: int = 0
	var frames: int = 0
	var done: bool = false
	var completion: Callable

	func _ready() -> void:
		var floor_body: StaticBody3D = StaticBody3D.new()
		floor_body.position.y = -0.5
		floor_body.collision_layer = 1
		var floor_shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(20.0, 1.0, 20.0)
		floor_shape.shape = box
		floor_body.add_child(floor_shape)
		add_child(floor_body)
		actor = CharacterBody3D.new()
		actor.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		actor.up_direction = Vector3.UP
		actor.safe_margin = 0.01
		actor.floor_snap_length = 0.35
		actor.collision_layer = 2
		actor.collision_mask = 1
		var collider: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 1.8
		collider.shape = capsule
		actor.add_child(collider)
		actor.position.y = Policy6.center_height(1.8, 0.35, 1.0)
		add_child(actor)

	func _physics_process(delta: float) -> void:
		if done:
			return
		elapsed += delta
		frames += 1
		actor.velocity = Vector3.DOWN * 9.81 * delta
		actor.move_and_slide()
		if not actor.is_on_floor():
			actor.apply_floor_snap()
		stable = stable + 1 if actor.is_on_floor() and actor.get_floor_normal().dot(Vector3.UP) > 0.99 else 0
		if stable >= 5:
			done = true
			completion.call(true, frames, actor.position.y)
		elif elapsed >= 2.0:
			done = true
			completion.call(false, frames, actor.position.y)

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("SurfaceContact6: FAIL " + label)

func _initialize() -> void:
	for angle: float in [0.0, 15.0, 35.0, 55.0]:
		var cosine: float = cos(deg_to_rad(angle))
		var height: float = Policy6.center_height(1.8, 0.35, cosine)
		var clearance: float = (height - (0.9 - 0.35)) * cosine - 0.35
		_check(absf(clearance - 0.03) < 1.0e-12, "capsule-plane normal clearance")
		_check(0.03 / cosine < 0.35, "candidate within snap distance")
	_check(is_inf(Policy6.center_height(1.0, 1.0, 1.0)), "invalid capsule refused")
	_check(is_inf(Policy6.center_height(1.8, 0.35, 0.0)), "invalid support normal refused")
	var source: String = FileAccess.get_file_as_string("res://scenes/world/test_catalog_surface_contact_v6.gd")
	_check(source.contains("super._try_flight_landing()"), "weak assisted path retained")
	_check(source.contains("_player.move_and_slide()") and source.contains("_player.apply_floor_snap()"), "native contact acquisition")
	_check(source.contains("_contact6_stable >= 5") and source.contains("floor_ok and _flight_local_terrain_ready()"), "native floor and live data required")
	_check(source.count("_universe_clock.advance(delta)") == 1, "one explicit acquisition clock advance")
	_check(source.contains("if _contact6_active:\n\t\t_contact6_tick(delta)\n\t\treturn\n\tsuper._physics_process(delta)"), "acquisition excludes ancestor clock/walking loop")
	_check(not source.contains("func _flight_spheres(") and not source.contains("func _update_navigation_tick("), "sphere and nav algorithms unchanged")
	_check(source.contains("_contact6_abort(\"support timeout") and source.contains("_flight_active = true"), "timeout returns protected flight")
	_check(ResourceLoader.load("res://scenes/world/test_catalog_surface_contact_v6.tscn") is PackedScene, "scene resource parses")
	var instance = Scene6.new()
	instance.free()
	call_deferred("_start_native_test")

func _start_native_test() -> void:
	if _failures > 0:
		quit(1)
		return
	var probe = NativeContactProbe.new()
	probe.completion = Callable(self, "_native_done")
	root.add_child(probe)

func _native_done(ok: bool, frames: int, height: float) -> void:
	_check(ok, "native flat-floor contact reaches five supported ticks")
	_check(height >= 0.88 and height <= 0.95, "native capsule remains at support height")
	if _failures == 0:
		print("SurfaceContact6: PASS capsule/slope math, inherited assist, single acquisition clock path, source guards, scene parse, NATIVE floor contact frames=%d height=%.6f" % [frames, height])
	print("SurfaceContact6: flat native probe is not a full rotating voxel/handover test; game acceptance still required")
	quit(0 if _failures == 0 else 1)
