@tool
extends Node3D
class_name PlanetPreview

## Editor-time testbed for iterating on a single SurfaceProfile without
## running the game at all. Builds one PlanetData by hand from the
## exported fields below and feeds it into Planet.setup() - no
## SystemGenerator, no star, no orbits.
##
## @tool means this script runs INSIDE the editor. rebuild() is only ever
## triggered explicitly (via toggling "Rebuild Now", or when you flip
## surface_profile/radius_m/planet_seed in the inspector) - never
## automatically every frame.
##
## The generated planet node is added WITHOUT an owner, so it does NOT get
## saved into the .tscn file when you save the scene - it's purely a live
## preview, regenerated fresh every time this scene is opened/edited.

@export var planet_scene: PackedScene
@export var generation_settings: GenerationSettings

@export var surface_profile: SurfaceProfile:
	set(value):
		surface_profile = value
		if Engine.is_editor_hint():
			rebuild()

@export_group("Body")
@export var radius_m: float = 80.0:
	set(value):
		radius_m = value
		if Engine.is_editor_hint():
			rebuild()
@export var gravity_strength: float = 9.8
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
@export var terrain_noise_scale_override: float = 1.0:
	set(value):
		terrain_noise_scale_override = value
		if Engine.is_editor_hint():
			rebuild()
@export var override_terrain_height: bool = false:
	set(value):
		override_terrain_height = value
		if Engine.is_editor_hint():
			rebuild()
@export var terrain_height_override_m: float = 5.0:
	set(value):
		terrain_height_override_m = value
		if Engine.is_editor_hint():
			rebuild()

@export_group("Rebuild")
## Toggle this checkbox to force a rebuild with a FRESH random seed -
## the fastest way to roll through variety within the current profile.
## Resets itself back to false immediately - behaves like a button, not
## a persistent setting. Reassigning planet_seed below triggers its own
## setter, which calls rebuild() - no need to call rebuild() again here.
@export var rebuild_now: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			planet_seed = randi()
		rebuild_now = false

var _current_planet_node: Node3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	rebuild()

## Tears down the current preview planet (if any) and builds a fresh one
## from the currently exported fields. Safe to call repeatedly, in-editor
## or at runtime.
func rebuild() -> void:
	if planet_scene == null:
		push_warning("PlanetPreview: 'Planet Scene' export is not assigned")
		return
	if surface_profile == null:
		push_warning("PlanetPreview: 'Surface Profile' export is not assigned")
		return

	if is_instance_valid(_current_planet_node):
		_current_planet_node.queue_free()

	var data: PlanetData = _build_preview_data()

	var planet_node: Node3D = planet_scene.instantiate()
	add_child(planet_node)
	# owner intentionally left unset (null) - keeps the generated preview
	# OUT of the saved .tscn, it's regenerated fresh every time this
	# scene is opened/edited, never persisted to disk.
	planet_node.set("generation_settings", generation_settings)
	planet_node.call("setup", data)

	_current_planet_node = planet_node

func _build_preview_data() -> PlanetData:
	_rng.seed = planet_seed

	var data: PlanetData = PlanetData.new()
	data.planet_seed = planet_seed
	data.radius_m = radius_m
	data.gravity_strength = gravity_strength
	data.surface_profile = surface_profile

	data.albedo_color = surface_profile.get_random_albedo_color(_rng)
	data.vegetation_density = surface_profile.get_random_vegetation_density(_rng)
	data.has_vegetation = data.vegetation_density > 0.0

	data.terrain_noise_scale = terrain_noise_scale_override if override_terrain_noise_scale else surface_profile.get_random_terrain_noise_scale(_rng)
	data.terrain_height_m = terrain_height_override_m if override_terrain_height else surface_profile.get_random_terrain_height(_rng)

	data.display_name = CelestialNameGenerator.generate_planet_name(planet_seed)

	return data
