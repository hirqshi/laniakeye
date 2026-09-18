extends Node3D

## ORDERING FIX: Player and Planet are siblings in the scene tree. Godot
## runs _physics_process in tree order UNLESS process_physics_priority says
## otherwise - lower priority runs FIRST (confirmed in official Godot 4
## docs: Node.process_physics_priority, "Nodes whose priority value is
## lower call their process callbacks first, regardless of tree order").
## Forcing this to -100 guarantees the planet rotates before the player
## reads its transform in the same physics tick.

@export var planets_container: Node3D
@export var star_eye_container: Node3D
@export var leviathan_spawner: LeviathanSpawner

@export var planet_scene: PackedScene
@export var star_eye_scene: PackedScene
@export var surface_profile_set: SurfaceProfileSet
@export var moon_surface_profile_set: MoonSurfaceProfileSet
@export var generation_settings: GenerationSettings
@export var system_seed: int = 0

## The star's physical radius - lives here, not on World, because the
## star itself is spawned and owned by StarSystem (star_eye_scene). World
## only borrows this value for ship spawn clearance checks.
@export var star_radius_m: float = 300.0

var system_data: SystemData
var planet_nodes: Array[Node3D] = []

func _ready() -> void:
	process_physics_priority = -100

	if SaveManager.pending_seed != 0:
		system_seed = SaveManager.pending_seed
		SaveManager.pending_seed = 0
	elif system_seed == 0:
		system_seed = randi()

	_build_system(system_seed)

func _build_system(seed_value: int) -> void:
	var generator: SystemGenerator = SystemGenerator.new(surface_profile_set, moon_surface_profile_set, generation_settings)
	system_data = generator.generate(seed_value)

	var star_eye: Node3D = star_eye_scene.instantiate()
	star_eye_container.add_child(star_eye)

	for planet_data in system_data.planets:
		_spawn_planet(planet_data, star_eye)

	if leviathan_spawner != null:
		leviathan_spawner.setup(self, seed_value, star_radius_m)

func _spawn_planet(planet_data: PlanetData, star_node: Node3D) -> void:
	var planet_node: Node3D = planet_scene.instantiate()
	planets_container.add_child(planet_node)

	planet_node.global_position = planet_data.get_orbit_position(global_position)
	planet_node.set("star_node", star_node)

	planet_node.call("setup", planet_data)
	planet_node.process_physics_priority = -100
	planet_nodes.append(planet_node)

func _physics_process(delta: float) -> void:
	for i in range(planet_nodes.size()):
		var planet_data: PlanetData = system_data.planets[i]
		var planet_node: Node3D = planet_nodes[i]
		if not is_instance_valid(planet_node):
			continue

		planet_data.orbit_angle_rad += planet_data.orbit_speed_rad_s * delta
		planet_node.global_position = planet_data.get_orbit_position(global_position)
		planet_node.rotate_y(planet_data.rotation_speed_rad_s * delta)

func get_all_celestial_nodes() -> Array[Node3D]:
	var all_nodes: Array[Node3D] = []
	for planet_node in planet_nodes:
		if not is_instance_valid(planet_node):
			continue
		all_nodes.append(planet_node)
		if planet_node.has_method("get_moon_nodes"):
			var moons: Array = planet_node.call("get_moon_nodes")
			for moon_node in moons:
				if is_instance_valid(moon_node):
					all_nodes.append(moon_node)
	return all_nodes

func get_leviathan_spawner() -> LeviathanSpawner:
	return leviathan_spawner

func get_radius() -> float:
	return star_radius_m
