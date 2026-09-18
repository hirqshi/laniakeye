@tool
class_name LeviathanProfile
extends Resource

enum LeviathanType { WORM, SQUID }

@export_category("Identity")
@export var display_name: String = "Unnamed Leviathan"
@export var leviathan_type: LeviathanType = LeviathanType.WORM
@export var creature_scene: PackedScene

@export_category("Base Creature")
## The regular CreatureProfile this leviathan scales up from - reuses all
## existing worm/squid mesh generation, wiggle shaders, and color/length
## rolls instead of duplicating that data.
@export var base_creature_profile: CreatureProfile

@export_category("Leviathan Scale")
@export_range(2.0, 5000.0, 1.0)
var size_multiplier: float = 20.0

@export_range(0.1, 20.0, 0.1)
var speed_multiplier: float = 3.0

@export_category("Roaming")
@export_range(1.0, 100.0, 1.0, "suffix:m/s")
var base_speed_mps: float = 8.0

@export_range(10.0, 20000.0, 10.0, "suffix:m")
var avoidance_lookahead_m: float = 400.0

@export_range(0.0, 5000.0, 5.0, "suffix:m")
var avoidance_margin_m: float = 100.0

@export_range(0.1, 10.0, 0.1)
var avoidance_turn_speed_rad_s: float = 0.6

@export_range(5.0, 300.0, 5.0, "suffix:s")
var course_change_interval_min_s: float = 20.0

@export_range(5.0, 300.0, 5.0, "suffix:s")
var course_change_interval_max_s: float = 60.0

@export_range(0.0, 3.14159, 0.01, "suffix:rad")
var course_change_jitter_rad: float = 0.8

@export_category("Bioluminescence")

@export var emission_color: Color = Color(0.2, 0.9, 1.0)

@export_range(0.0, 20.0, 0.1)
var emission_energy_multiplier: float = 4.0

func get_effective_speed_mps() -> float:
	return base_speed_mps * speed_multiplier
