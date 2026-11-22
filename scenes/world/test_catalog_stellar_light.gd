extends "res://scenes/world/test_catalog_two_planets.gd"

# Additional scene only; no changes to the validated single-/two-body harness.
const StellarLighting = preload("res://game/world/runtime/lk_stellar_lighting.gd")

@export var stellar_light_energy: float = 1.0
@export var day_ambient_energy: float = 0.18
@export var night_ambient_energy: float = 0.035

var _stellar_light_node: DirectionalLight3D
var _stellar_environment: Environment
var _stellar_sample: Dictionary = {}
var _stellar_log_s: float = 0.0
var _stellar_was_day: bool = false
var _stellar_has_day_reference: bool = false


func _setup_visuals() -> void:
	# Replaces ONLY the test harness's fixed-angle lighting setup.
	# Called by parent again when a different body world is created.
	_stellar_environment = Environment.new()
	_stellar_environment.background_mode = Environment.BG_COLOR
	_stellar_environment.background_color = Color(0.008, 0.012, 0.02)
	_stellar_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_stellar_environment.ambient_light_color = Color(0.65, 0.7, 0.8)
	_stellar_environment.ambient_light_energy = night_ambient_energy
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = _stellar_environment
	add_child(environment_node)
	_stellar_light_node = DirectionalLight3D.new()
	_stellar_light_node.name = "CatalogStellarLight"
	_stellar_light_node.light_energy = 0.0
	_stellar_light_node.shadow_enabled = true
	_stellar_light_node.directional_shadow_max_distance = 256.0
	add_child(_stellar_light_node)
	_stellar_sample.clear()
	_stellar_has_day_reference = false
	_stellar_log_s = 0.0


func _load_target(index: int) -> void:
	super._load_target(index)
	if _initialised and not _failed:
		_update_stellar_lighting()
		print("StellarLighting: SELECT body=%s period=%.3f min altitude=%.3f deg" % [
			_context["body"]["id"], float(_context["spin"]["period_s"]) / 60.0,
			rad_to_deg(float(_stellar_sample.get("altitude_rad", 0.0))),
		])


func _update_stellar_lighting() -> void:
	if not _initialised or not is_instance_valid(_player) or not is_instance_valid(_stellar_light_node):
		return
	var fixed: LkPosition64 = _fixed_position()
	_stellar_sample = StellarLighting.evaluate(
		_context["orbit"], _context["spin"], _catalog_frame.world_time_s,
		[fixed.x, fixed.y, fixed.z]
	)
	if _stellar_sample.is_empty():
		_stellar_light_node.light_energy = 0.0
		return
	_stellar_light_node.global_basis = StellarLighting.directional_basis(_stellar_sample["to_star_system"])
	var visibility: float = _stellar_sample["horizon_visibility"]
	_stellar_light_node.light_energy = maxf(stellar_light_energy, 0.0) * visibility
	_stellar_environment.ambient_light_energy = lerpf(maxf(night_ambient_energy, 0.0), maxf(day_ambient_energy, 0.0), visibility)
	var day: bool = _stellar_sample["above_horizon"]
	if not _stellar_has_day_reference or day != _stellar_was_day:
		print("StellarLighting: %s body=%s t=%.2f altitude=%.3f deg" % [
			"DAY" if day else "NIGHT", _context["body"]["id"],
			_catalog_frame.world_time_s, rad_to_deg(float(_stellar_sample["altitude_rad"])),
		])
	_stellar_has_day_reference = true
	_stellar_was_day = day


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _initialised:
		return
	_update_stellar_lighting()
	_stellar_log_s += delta
	if _stellar_log_s >= 30.0 and not _stellar_sample.is_empty():
		_stellar_log_s = 0.0
		print("StellarLighting: STATUS body=%s t=%.2f altitude=%.3f deg light=%.3f" % [
			_context["body"]["id"], _catalog_frame.world_time_s,
			rad_to_deg(float(_stellar_sample["altitude_rad"])), _stellar_light_node.light_energy,
		])


func _process(delta: float) -> void:
	super._process(delta)
	if not _initialised or _stellar_sample.is_empty():
		return
	_label.text += ("\n\nSTELLAR LIGHT | %s | altitude %.2f deg"
		+ "\nRotation %.2f min | direct light %.3f"
		+ "\nOrbit + spin, one clock; no atmosphere or star disc yet") % [
		"DAY" if _stellar_sample["above_horizon"] else "NIGHT",
		rad_to_deg(float(_stellar_sample["altitude_rad"])),
		float(_context["spin"]["period_s"]) / 60.0, _stellar_light_node.light_energy,
	]
