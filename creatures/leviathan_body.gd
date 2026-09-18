class_name LeviathanBody
extends Node3D

@export var creature_mesh_instance: MeshInstance3D
@export var worm_body_controller: WormBodyController
@export var squid_tentacle_lag: SquidTentacleLag

var leviathan_profile: LeviathanProfile
var _generator: CreatureMeshGenerator = CreatureMeshGenerator.new()
var _locomotion: LeviathanLocomotion = LeviathanLocomotion.new()
var _obstacles_provider: Callable


func setup(profile: LeviathanProfile, spawn_position: Vector3, obstacles_provider: Callable) -> void:
	if profile == null:
		push_error("LeviathanBody: cannot setup with a null LeviathanProfile")
		return

	leviathan_profile = profile
	_obstacles_provider = obstacles_provider

	global_position = spawn_position
	scale = Vector3.ONE * profile.size_multiplier

	print("Leviathan spawned with size_multiplier=", profile.size_multiplier, " actual scale=", scale)

	_apply_visual()
	_locomotion.enter(self, profile)


func _physics_process(delta: float) -> void:
	if leviathan_profile == null:
		return

	var obstacles: Array[Dictionary] = []

	if _obstacles_provider.is_valid():
		obstacles = _obstacles_provider.call()

	_locomotion.update(self, leviathan_profile, obstacles, delta)

	if leviathan_profile.leviathan_type != LeviathanProfile.LeviathanType.WORM:
		return

	if worm_body_controller == null:
		return

	## Worm body controller expects planet-local space, but leviathans
	## have no planet - feed it position in this node's OWN parent
	## space instead, which is flat open-space world coordinates here.
	worm_body_controller.set_head_position_planet_local(position)


func _apply_visual() -> void:
	if leviathan_profile == null:
		return

	var base_profile: CreatureProfile = leviathan_profile.base_creature_profile

	if base_profile == null:
		push_error("LeviathanBody: LeviathanProfile has no base_creature_profile")
		return

	match leviathan_profile.leviathan_type:
		LeviathanProfile.LeviathanType.WORM:
			_setup_worm_visual(base_profile)
		LeviathanProfile.LeviathanType.SQUID:
			_setup_squid_visual(base_profile)


func _setup_worm_visual(base_profile: CreatureProfile) -> void:
	if worm_body_controller == null:
		push_error("LeviathanBody: WORM leviathan requires WormBodyController")
		return

	if creature_mesh_instance == null:
		push_error("LeviathanBody: WORM leviathan requires CreatureMesh")
		return

	creature_mesh_instance.visible = true
	creature_mesh_instance.mesh = null

	worm_body_controller.creature_profile = base_profile
	worm_body_controller.rebuild()

	creature_mesh_instance.material_override = (
		CreatureMaterialFactory.create_worm_material(
			base_profile,
			leviathan_profile.emission_color,
			leviathan_profile.emission_energy_multiplier
		)
	)

	worm_body_controller.reset_path_at_planet_local(position)


func _setup_squid_visual(base_profile: CreatureProfile) -> void:
	if creature_mesh_instance == null:
		push_error("LeviathanBody: SQUID leviathan requires CreatureMesh")
		return

	creature_mesh_instance.visible = true

	var mesh: ArrayMesh = _generator.generate_squid(
		base_profile,
		base_profile.preview_seed
	)

	if mesh == null:
		push_error("LeviathanBody: squid mesh generation failed")
		return

	creature_mesh_instance.mesh = mesh

	var body_material: ShaderMaterial = (
		CreatureMaterialFactory.create_squid_material(
			base_profile,
			false,
			base_profile.squid_body_wiggle_multiplier,
			leviathan_profile.emission_color,
			leviathan_profile.emission_energy_multiplier
		)
	)

	var tentacle_material: ShaderMaterial = (
		CreatureMaterialFactory.create_squid_material(
			base_profile,
			true,
			1.0,
			leviathan_profile.emission_color,
			leviathan_profile.emission_energy_multiplier
		)
	)

	creature_mesh_instance.set_surface_override_material(
		CreatureMeshGenerator.SQUID_BODY_SURFACE,
		body_material
	)

	if mesh.get_surface_count() > CreatureMeshGenerator.SQUID_TENTACLE_SURFACE:
		creature_mesh_instance.set_surface_override_material(
			CreatureMeshGenerator.SQUID_TENTACLE_SURFACE,
			tentacle_material
		)

	if squid_tentacle_lag != null:
		squid_tentacle_lag.process_mode = Node.PROCESS_MODE_INHERIT
