# Magic Numbers Documentation

This document catalogs magic numbers found during the audit and their intended meaning.

## Galaxy Placement (prototype settings)

- `CELL_WIDTH_LY = 4000000.0` — Prototype cell width, not measured astronomical distribution.
- `MIN_RADIUS_LY = 20000.0` — Minimum galaxy envelope radius.
- `MAX_RADIUS_LY = 200000.0` — Maximum galaxy envelope radius.
- `MIN_GAP_LY = 500000.0` — Minimum gap between galaxies.
- `NUMERIC_PAD_LY = 1.0` — Numeric safety pad.
- `CELL_MIN = -1048576`, `CELL_MAX = 1048575` — 21-bit signed cell coordinates.

## Body Catalog

- `RELIEF_MAX_M = 200000.0` — Maximum terrain relief for solid bodies.
- `RELIEF_FRACTION = 0.05` — Relief as fraction of radius.
- `SOLID_RADIUS_MAX_M + 1` — Boundary between solid and gas giant radius ranges.

## System Placement

- `BOUNDARY_MARGIN_M = 149597870700.0` — 1 AU boundary margin.

## System Motion

- `REFERENCE_MU_M3_S2 = 1.32712440018e20` — Solar GM, used as fixed reference until star physics is introduced.

## Population Audit

- `EXPECTED_PLANETS_MULTIPLIER = 4.4` — Derived from 0.8 (has_planets) × 5.5 (avg planet_count).

## Rotation Periods

- `ROTATION_MIN_PERIOD_S = 1200.0` — 20 minutes.
- `ROTATION_MAX_PERIOD_S = 144000.0` — 40 hours.

## World Catalog

- `SECTOR_WIDTH_LY = 16.0` — Prototype sector width.
- `MAX_SYSTEMS_PER_SECTOR = 4` — Prototype systems per sector.

## Surface Shell Math

- `SHELL_STABLE_FRACTION = 0.25` — Stability threshold as fraction of radius.

## Frame Pacing Monitor

- `PACING_BASELINE_STATES` — States used for baseline calculation.

## Render Pressure Monitor

- `SLOW_ROWS_LIMIT = 256` — Maximum slow-frame rows kept in memory.

## Navigation Projection

- `NAV_EPSILON = 1.0e-5` — Epsilon for view.z check.
- `NAV_EDGE_OFFSET_PX = 34.0` — Edge offset for half-viewport calculation.

## Navigation Overlay

- `OVERLAY_COLLISION_STEP_PX = 40.0` — Step for collision avoidance.

## Flight Math

- `FLIGHT_SPEED_BASE = 5.0`, `FLIGHT_SPEED_COEFF = 0.4`, `FLIGHT_SPEED_EXPONENT = 1.35` — Speed-at-height curve.
- `FLIGHT_MULTIPLIER_MIN = 1.0/1024.0`, `FLIGHT_MULTIPLIER_MAX = 4096.0` — Multiplier clamp.
- `FLIGHT_SPEED_MIN = 0.001`, `FLIGHT_SPEED_MAX = 1.0e11` — Speed clamp.
- `FLIGHT_GUARD_MARGIN_M = 0.25` — Safety margin for sphere radius and entry point.

## Flight Carry

- `FLIGHT_REFERENCE_HEIGHT_M = 250000.0` — Reference height for adaptive band.
- `FLIGHT_HEIGHT_UPPER_M = 5000000.0` — Upper clamp for height.
- `FLIGHT_HEIGHT_LOWER_M = 100.0` — Lower clamp for height.

## Flight CPU Policy

- `NAV_RATE_MIN_HZ = 5.0`, `NAV_RATE_MAX_HZ = 120.0` — Navigation update rate clamp.

## Flight Sphere Pool

- `SPHERE_GUARD_RADIUS_M = 32.0` — Guard radius added to non-active bodies.

## Surface Approach Forecast

- `APPROACH_GUARD_HEIGHT_M = 32.5` — Guard height (32.0 + 0.5).

## Landing Patch Policy

- `LANDING_MIN_HEIGHT_M = 0.5`, `LANDING_MAX_HEIGHT_M = 64.0` — Preparation height range.
- `LANDING_GRID_M = 32.0` — Grid size for lattice snapping.

## Surface Contact Policy

- `CONTACT_CLEARANCE_M = 0.03` — Capsule-plane clearance.

## Auto Surface Policy

- `SURFACE_HORIZON_S = 30.0` — Horizon time for approach.
- `SURFACE_HOVER_HEIGHT_M = 1500.0` — Hover height threshold.

## Auto Transfer Policy

- `TRANSFER_SWITCH_MIN_M = 20000.0`, `TRANSFER_SWITCH_MAX_M = 200000.0` — Switch height clamp.
- `TRANSFER_PREPARE_MULTIPLIER = 3.0`, `TRANSFER_PREPARE_BASE_M = 500000.0` — Prepare height calculation.

## Transfer Frame Math

- `HORIZON_FADE_SINE = 0.02` — Horizon fade threshold.

## Surface Control Policy

- `CONTROL_STATE_INVALID`, `CONTROL_STATE_ASSIST`, `CONTROL_STATE_NORMAL` — Control state strings.

## Far System Shaders

- `SHADER_ACTIVE_CUTOFF_M = 128.0` — Active sphere cutoff distance.
- `SHADER_ACTIVE_FADE_M = 32.0` — Active sphere fade distance.
- `SHADER_DISTANT_AMBIENT = 0.025` — Distant body ambient.
- `SHADER_ACTIVE_AMBIENT_LINEAR` — Active body ambient color (linear).
- `SHADER_ACTIVE_DAY_AMBIENT = 0.18`, `SHADER_ACTIVE_NIGHT_AMBIENT = 0.035` — Day/night ambient energies.
- `SHADER_ACTIVE_HORIZON_FADE_SINE = 0.02` — Horizon fade threshold.
- `SHADER_STAR_RADIUS_PX_*` — Star sprite PSF/exposure mapping.
- `SHADER_STAR_AMPLITUDE_*` — Star sprite amplitude mapping.
