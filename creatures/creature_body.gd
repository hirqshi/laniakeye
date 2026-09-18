class_name CreatureBody
extends Node3D

@export_category("Scene References")

@export var creature_mesh_instance: MeshInstance3D
@export var worm_body_controller: WormBodyController
@export var spider_body_controller: SpiderBodyController
@export var squid_tentacle_lag: SquidTentacleLag

var creature_profile: CreatureProfile

var surface_up_direction: Vector3 = Vector3.UP
var planet_center: Vector3 = Vector3.ZERO
var surface_sampler: PlanetSurfaceSampler

var _generator: CreatureMeshGenerator = CreatureMeshGenerator.new()
var _locomotion_strategy: CreatureLocomotionStrategy

func setup(
	profile: CreatureProfile,
	spawn_transform: Transform3D,
	up_direction: Vector3,
	center: Vector3,
	sampler: PlanetSurfaceSampler
) -> void:
	if profile == null:
		push_error("CreatureBody: cannot setup with a null CreatureProfile")
		return

	if sampler == null:
		push_error("CreatureBody: cannot setup without PlanetSurfaceSampler")
		return

	creature_profile = profile
	surface_up_direction = up_direction.normalized()
	planet_center = center
	surface_sampler = sampler

	transform = spawn_transform

	_apply_visual_controller()
	_apply_locomotion_strategy()
	
func _physics_process(delta: float) -> void:
	if creature_profile == null:
		return

	if _locomotion_strategy == null:
		return

	_locomotion_strategy.update(self, delta)

	if creature_profile.creature_type != CreatureProfile.CreatureType.WORM:
		return

	if worm_body_controller == null:
		return

	worm_body_controller.set_head_position_planet_local(
		position
	)

func reset_worm_trail() -> void:
	if worm_body_controller == null:
		return

	worm_body_controller.reset_path_at_planet_local(position)

func _apply_visual_controller() -> void:
	if creature_profile == null:
		return

	match creature_profile.creature_type:
		CreatureProfile.CreatureType.WORM:
			_setup_worm_visual()
		CreatureProfile.CreatureType.SQUID:
			_setup_squid_visual()
		CreatureProfile.CreatureType.SPIDER:
			_setup_spider_visual()

func _setup_worm_visual() -> void:
	if worm_body_controller == null:
		push_error(
			"CreatureBody: WORM profile requires WormBodyController"
		)
		return

	if creature_mesh_instance == null:
		push_error(
			"CreatureBody: WORM profile requires CreatureMesh"
		)
		return

	creature_mesh_instance.visible = true
	creature_mesh_instance.mesh = null

	worm_body_controller.process_mode = Node.PROCESS_MODE_INHERIT
	worm_body_controller.creature_profile = creature_profile
	worm_body_controller.rebuild()

	creature_mesh_instance.material_override = (
		CreatureMaterialFactory.create_worm_material(
			creature_profile
		)
	)

func _setup_squid_visual() -> void:
	if creature_mesh_instance == null:
		push_error(
			"CreatureBody: SQUID profile requires CreatureMesh"
		)
		return

	creature_mesh_instance.visible = true

	var mesh: ArrayMesh = _generator.generate_squid(
		creature_profile,
		creature_profile.preview_seed
	)

	if mesh == null:
		push_error("CreatureBody: squid mesh generation failed")
		return

	creature_mesh_instance.mesh = mesh
	
	var body_material: ShaderMaterial = (
		CreatureMaterialFactory.create_squid_material(
			creature_profile,
			false,
			creature_profile.squid_body_wiggle_multiplier
		)
	)

	var tentacle_material: ShaderMaterial = (
		CreatureMaterialFactory.create_squid_material(
			creature_profile,
			true,
			1.0
		)
	)

	creature_mesh_instance.set_surface_override_material(
		CreatureMeshGenerator.SQUID_BODY_SURFACE,
		body_material
	)

	if mesh.get_surface_count() > (
		CreatureMeshGenerator.SQUID_TENTACLE_SURFACE
	):
		creature_mesh_instance.set_surface_override_material(
			CreatureMeshGenerator.SQUID_TENTACLE_SURFACE,
			tentacle_material
		)
		
	if squid_tentacle_lag != null:
		squid_tentacle_lag.process_mode = Node.PROCESS_MODE_INHERIT

func _setup_spider_visual() -> void:
	if spider_body_controller == null:
		push_error(
			"CreatureBody: SPIDER profile requires SpiderBodyController"
		)
		return

	if creature_mesh_instance != null:
		creature_mesh_instance.visible = false
		creature_mesh_instance.mesh = null

	spider_body_controller.visible = true
	spider_body_controller.process_mode = Node.PROCESS_MODE_INHERIT
	spider_body_controller.creature_profile = creature_profile
	spider_body_controller.rebuild()

func _apply_locomotion_strategy() -> void:
	if creature_profile == null:
		return

	match creature_profile.locomotion_mode:
		CreatureProfile.LocomotionMode.SURFACE_CLING:
			_locomotion_strategy = SurfaceClingLocomotion.new()
		CreatureProfile.LocomotionMode.SURFACE_HOP:
			_locomotion_strategy = SurfaceHopLocomotion.new()
		CreatureProfile.LocomotionMode.FLYING:
			_locomotion_strategy = FlyingLocomotion.new()
		CreatureProfile.LocomotionMode.SWIMMING:
			_locomotion_strategy = SwimmingLocomotion.new()
		_:
			push_error(
				"CreatureBody: unknown locomotion mode for '%s'"
				% creature_profile.display_name
			)
			_locomotion_strategy = null

	if _locomotion_strategy != null:
		_locomotion_strategy.enter(self)
