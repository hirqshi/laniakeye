extends Node3D

@export var moon_scene: PackedScene
@export var moon_surface_profile_set: MoonSurfaceProfileSet
@export var generation_settings: GenerationSettings
@export var moon_container: Node3D
@export_range(0.0, 1.0, 0.001, "suffix:rad/s") var moon_rotation_speed_rad_s: float = 0.05

@export var new_game_button: Button
@export var continue_button: Button
@export var world_select_button: Button
@export var exit_button: Button
@export var world_select_scene: PackedScene
@export var ui_root: CanvasLayer

const GAME_SCENE_PATH: String = "res://scenes/world.tscn"

var _world_select_instance: Control
var _moon_node: Node3D

func _ready() -> void:
	MouseCaptureManager.set_ui_active(true)

	_spawn_menu_moon()

	if new_game_button != null:
		new_game_button.pressed.connect(_on_new_game_pressed)

	if continue_button != null:
		continue_button.pressed.connect(_on_continue_pressed)
		continue_button.disabled = not SaveManager.has_any_save()

	if world_select_button != null:
		world_select_button.pressed.connect(_on_world_select_pressed)

	if exit_button != null:
		exit_button.pressed.connect(_on_exit_pressed)

func _process(delta: float) -> void:
	if is_instance_valid(_moon_node):
		_moon_node.rotate_y(moon_rotation_speed_rad_s * delta)

func _spawn_menu_moon() -> void:
	if moon_scene == null or moon_container == null:
		return

	var moon_data: PlanetData = _generate_random_moon_data()
	_moon_node = moon_scene.instantiate()
	moon_container.add_child(_moon_node)
	_moon_node.set("is_moon", true)
	_moon_node.set("generation_settings", generation_settings)
	_moon_node.call("setup", moon_data)

func _generate_random_moon_data() -> PlanetData:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	var profile: MoonSurfaceProfile = null
	if moon_surface_profile_set != null:
		profile = moon_surface_profile_set.get_random_profile(rng)

	var data: PlanetData = PlanetData.new()
	data.planet_seed = rng.randi()
	data.radius_m = rng.randf_range(10.0, 30.0)
	data.gravity_strength = 2.0
	data.surface_profile = profile
	data.axial_tilt_rad = rng.randf_range(-0.3, 0.3)

	if profile != null:
		data.albedo_color = profile.get_random_albedo_color(rng)
		data.terrain_noise_scale = profile.get_random_terrain_noise_scale(rng)
		data.terrain_height_m = profile.get_random_terrain_height(rng)
	else:
		data.albedo_color = Color.WHITE
		data.terrain_noise_scale = rng.randf_range(1.5, 4.0)
		data.terrain_height_m = rng.randf_range(1.0, 4.0)

	return data

func _on_new_game_pressed() -> void:
	_start_game(0)

func _on_continue_pressed() -> void:
	var last_seed: int = SaveManager.get_last_seed()
	if last_seed == 0:
		return

	_start_game(last_seed)

func _start_game(seed_value: int) -> void:
	SaveManager.pending_seed = seed_value
	MouseCaptureManager.set_ui_active(false)
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_world_select_pressed() -> void:
	if _world_select_instance == null:
		_world_select_instance = world_select_scene.instantiate() as Control
		ui_root.add_child(_world_select_instance)
		_world_select_instance.closed.connect(_on_world_select_closed)

	_world_select_instance.call("open")

func _on_world_select_closed() -> void:
	continue_button.disabled = not SaveManager.has_any_save()

func _on_exit_pressed() -> void:
	get_tree().quit()
