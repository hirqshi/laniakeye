class_name LkConstants
extends RefCounted

# Shared constants extracted from magic numbers across the codebase.
# Each constant documents its origin and intended use.

# Galaxy placement (prototype settings, not measured astronomical distributions)
const CELL_WIDTH_LY: float = 4000000.0
const MIN_RADIUS_LY: float = 20000.0
const MAX_RADIUS_LY: float = 200000.0
const MIN_GAP_LY: float = 500000.0
const NUMERIC_PAD_LY: float = 1.0
const CELL_MIN: int = -1048576
const CELL_MAX: int = 1048575

# Body catalog (physical constants and prototype limits)
const G_SI: float = 6.67430e-11
const SOLAR_MASS_KG: float = 1.98847e30
const SOLAR_RADIUS_M: float = 695700000.0
const SOLID_RADIUS_MAX_M: float = 13000000.0
const JUPITER_REFERENCE_RADIUS_M: float = 71492000.0
const GAS_RADIUS_MAX_M: float = 2.0 * JUPITER_REFERENCE_RADIUS_M
const SOLID_RADIUS_MIN_M: float = 200000.0
const MOON_RADIUS_MIN_M: float = 100.0
const MOON_RADIUS_MAX_M: float = 2700000.0
const MOON_TOTAL_MASS_FRACTION: float = 0.03
const MAX_REQUESTED_MOONS: int = 512
const RELIEF_MAX_M: float = 200000.0
const RELIEF_FRACTION: float = 0.05

# System placement
const LIGHT_YEAR_M: float = 9460730472580800.0
const BOUNDARY_MARGIN_M: float = 149597870700.0  # 1 AU

# System motion (technical central parameter until star physics is introduced)
const REFERENCE_MU_M3_S2: float = 1.32712440018e20

# Population audit
const EXPECTED_PLANETS_MULTIPLIER: float = 4.4

# Rotation periods
const ROTATION_MIN_PERIOD_S: float = 1200.0
const ROTATION_CORE_MIN_S: float = 1800.0
const ROTATION_CORE_MAX_S: float = 10800.0
const ROTATION_MAX_PERIOD_S: float = 144000.0

# World catalog
const SECTOR_WIDTH_LY: float = 16.0
const MAX_SYSTEMS_PER_SECTOR: int = 4
const EARTH_RADIUS_M: float = 6371000.0

# Surface shell math
const SHELL_STABLE_FRACTION: float = 0.25

# Frame pacing monitor
const PACING_BASELINE_STATES: Array[String] = ["FLIGHT", "WALK", "EXPAND"]

# Render pressure monitor
const SLOW_ROWS_LIMIT: int = 256

# Navigation projection
const NAV_EPSILON: float = 1.0e-5
const NAV_EDGE_OFFSET_PX: float = 34.0

# Navigation overlay
const OVERLAY_COLLISION_STEP_PX: float = 40.0

# Flight math
const FLIGHT_SPEED_BASE: float = 5.0
const FLIGHT_SPEED_COEFF: float = 0.4
const FLIGHT_SPEED_EXPONENT: float = 1.35
const FLIGHT_MULTIPLIER_MIN: float = 1.0 / 1024.0
const FLIGHT_MULTIPLIER_MAX: float = 4096.0
const FLIGHT_SPEED_MIN: float = 0.001
const FLIGHT_SPEED_MAX: float = 1.0e11
const FLIGHT_GUARD_MARGIN_M: float = 0.25

# Flight carry
const FLIGHT_REFERENCE_HEIGHT_M: float = 250000.0
const FLIGHT_HEIGHT_UPPER_M: float = 5000000.0
const FLIGHT_HEIGHT_LOWER_M: float = 100.0

# Flight CPU policy
const NAV_RATE_MIN_HZ: float = 5.0
const NAV_RATE_MAX_HZ: float = 120.0

# Flight sphere pool
const SPHERE_GUARD_RADIUS_M: float = 32.0

# Surface approach forecast
const APPROACH_GUARD_HEIGHT_M: float = 32.5

# Landing patch policy
const LANDING_MIN_HEIGHT_M: float = 0.5
const LANDING_MAX_HEIGHT_M: float = 64.0
const LANDING_GRID_M: float = 32.0

# Surface contact policy
const CONTACT_CLEARANCE_M: float = 0.03

# Auto surface policy
const SURFACE_HORIZON_S: float = 30.0
const SURFACE_HOVER_HEIGHT_M: float = 1500.0

# Auto transfer policy
const TRANSFER_SWITCH_MIN_M: float = 20000.0
const TRANSFER_SWITCH_MAX_M: float = 200000.0
const TRANSFER_PREPARE_MULTIPLIER: float = 3.0
const TRANSFER_PREPARE_BASE_M: float = 500000.0

# Transfer frame math
const HORIZON_FADE_SINE: float = 0.02

# Surface control policy
const CONTROL_STATE_INVALID: String = "INVALID"
const CONTROL_STATE_ASSIST: String = "EVA_ASSIST"
const CONTROL_STATE_NORMAL: String = "NORMAL"

# Far system shaders
const SHADER_ACTIVE_CUTOFF_M: float = 128.0
const SHADER_ACTIVE_FADE_M: float = 32.0
const SHADER_DISTANT_AMBIENT: float = 0.025
const SHADER_ACTIVE_AMBIENT_LINEAR: Vector3 = Vector3(0.38, 0.45, 0.60)
const SHADER_ACTIVE_DAY_AMBIENT: float = 0.18
const SHADER_ACTIVE_NIGHT_AMBIENT: float = 0.035
const SHADER_ACTIVE_HORIZON_FADE_SINE: float = 0.02
const SHADER_STAR_RADIUS_PX_MIN: float = 1.15
const SHADER_STAR_RADIUS_PX_COEFF: float = 0.28
const SHADER_STAR_RADIUS_PX_MAX: float = 4.0
const SHADER_STAR_AMPLITUDE_MAX: float = 16.0
const SHADER_STAR_AMPLITUDE_COEFF: float = 0.22
const SHADER_STAR_AMPLITUDE_EXPONENT: float = 0.60
