@tool
extends Node3D
class_name MoonPreview

## Editor-time testbed for iterating on a single MoonSurfaceProfile,
## mirroring PlanetPreview but using MoonSurfaceProfile instead of
## SurfaceProfile. Builds one PlanetData by hand and feeds it into
## Planet.setup() with is_moon = true - no SystemGenerator, no planet
## parent, no orbits.

@export var moon_scene: PackedScene
@export var generation_settings: GenerationSettings

@export var moon_surface_profile: MoonSurfaceProfile:
	set(value):
		moon_surface_profile = value
		if Engine.is_editor_hint():
			rebuild()

@export_group("Body")
@export var radius_m: float = 20.0:
	set(value):
		radius_m = value
		if Engine.is_editor_hint():
			rebuild()
@export var gravity_strength: float = 1.5
@export var planet_seed: int = 12345:
	set(value):
		planet_seed = value
		if Engine.is_editor_hint():
			rebuild()

@export_group("Terrain Overrides")
@export var override_terrain_noise_scale: bool = false:
	set(value):
		override_terrain_noise_scale = value
		if Engine.is_editor_hint():
			rebuild()
@export var terrain_noise_scale_override: float = 2.0:
	set(value):
		terrain_noise_scale_override = value
		if Engine.is_editor_hint():
			rebuild()
@export var override_terrain_height: bool = false:
	set(value):
		override_terrain_height = value
		if Engine.is_editor_hint():
			rebuild()
@export var terrain_height_override_m: float = 2.0:
	set(value):
		terrain_height_override_m = value
		if Engine.is_editor_hint():
			rebuild()

@export_group("Rebuild")
## Toggle to force a rebuild with a fresh random seed. Resets itself back
## to false immediately - behaves like a button.
@export var rebuild_now: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			planet_seed = randi()
		rebuild_now = false

var _current_moon_node: Node3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	if moon_scene == null:
		push_warning("MoonPreview: 'Moon Scene' export is not assigned")
		return
	if moon_surface_profile == null:
		push_warning("MoonPreview: 'Moon Surface Profile' export is not assigned")
		return

	if is_instance_valid(_current_moon_node):
		_current_moon_node.queue_free()

	var data: PlanetData = _build_preview_data()

	var moon_node: Node3D = moon_scene.instantiate()
	add_child(moon_node)
	moon_node.set("is_moon", true)
	moon_node.set("generation_settings", generation_settings)
	moon_node.call("setup", data)

	_current_moon_node = moon_node

func _build_preview_data() -> PlanetData:
	_rng.seed = planet_seed

	var data: PlanetData = PlanetData.new()
	data.planet_seed = planet_seed
	data.radius_m = radius_m
	data.gravity_strength = gravity_strength
	data.surface_profile = moon_surface_profile

	data.albedo_color = moon_surface_profile.get_random_albedo_color(_rng)

	data.terrain_noise_scale = terrain_noise_scale_override if override_terrain_noise_scale else moon_surface_profile.get_random_terrain_noise_scale(_rng)
	data.terrain_height_m = terrain_height_override_m if override_terrain_height else moon_surface_profile.get_random_terrain_height(_rng)

	data.display_name = CelestialNameGenerator.generate_planet_name(planet_seed)

	return data
