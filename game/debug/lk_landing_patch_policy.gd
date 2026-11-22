class_name LkLandingPatchPolicy
extends RefCounted

static func can_prepare(height_m: float) -> bool:
	return is_finite(height_m) and height_m >= 0.5 and height_m <= 64.0

static func plan(fixed: LkPosition64, lattice: LkPosition64, grid_m: float = 32.0) -> Dictionary:
	if not is_finite(grid_m) or grid_m <= 0.0:
		return {"ok": false}
	for value: float in [fixed.x, fixed.y, fixed.z, lattice.x, lattice.y, lattice.z]:
		if not is_finite(value):
			return {"ok": false}
	var anchor: LkPosition64 = LkPosition64.new(
		lattice.x + roundf((fixed.x - lattice.x) / grid_m) * grid_m,
		lattice.y + roundf((fixed.y - lattice.y) / grid_m) * grid_m,
		lattice.z + roundf((fixed.z - lattice.z) / grid_m) * grid_m)
	return {"ok": true, "anchor": anchor}
