# EVA (near-zero gravity movement)

## Principle
Gravity stays real and tiny. EVA is thrust, not walking.

## Rules
- Keys add acceleration in the player's local axes (forward/side/up). Releasing keys keeps velocity.
- Brake key applies bounded deceleration relative to the reference body surface velocity.
- Mouse changes orientation only; it never rotates the existing velocity vector.
- Contact is handled by collisions only. No ground lock, no sticking, no forced WALK.
- Terrain streaming, collider readiness and voxel reanchor do not depend on floor contact.
- Entering/leaving EVA must not zero or double-apply velocity (carry_with_frame already converts inertial/relative velocity).

## Mode selection
`has_up` alone must not decide WALK. WALK requires gravity above a threshold AND confirmed support. Below the threshold the player stays in EVA/flight.

## Status
`player/lk_eva_drive.gd` is the integrator only. Wiring into LkPlayerController._fly, the `eva_brake` input action, and the weak-gravity threshold are not done in this commit; the repository controller is older than the local project and was not modified.

## First test (weak-gravity moon)
1. Enter EVA a few metres above ground.
2. Short thrust, release keys: velocity persists.
3. Brake: velocity relative to the surface decays.
4. Touch the ground: no WALK, no sticking.
5. Leave EVA to flight at any time.
