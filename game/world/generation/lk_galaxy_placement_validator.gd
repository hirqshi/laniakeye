class_name LkGalaxyPlacementValidator
extends RefCounted

const Placement = preload("res://game/world/generation/lk_galaxy_placement.gd")
const Identity = preload("res://game/world/generation/lk_world_identity.gd")


static func _canonical_integer(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 20 or not value.is_valid_int():
		return false
	var text: String = value
	var negative: bool = text.begins_with("-")
	var digits: String = text.substr(1) if negative else text
	var limit: String = "9223372036854775808" if negative else "9223372036854775807"
	if digits.length() > 19 or (digits.length() == 19 and digits > limit):
		return false
	return str(text.to_int()) == text


# Validates schema-shaped data from generator/storage, not arbitrary object graphs.
# Geometry is checked independently, not by comparing to a regenerated record.
static func validate(record: Dictionary, universe_id: String) -> Array[String]:
	var errors: Array[String] = []
	if not Identity.is_valid_id(universe_id) or record.get("universe_id", "") != universe_id:
		errors.append("universe identity mismatch")
		return errors
	if int(record.get("placement_version", -1)) != Placement.VERSION:
		errors.append("unsupported placement version")
	var index_text: Variant = record.get("galaxy_index", null)
	if not _canonical_integer(index_text) or String(index_text).to_int() < 0:
		errors.append("invalid galaxy index")
		return errors
	var index: int = String(index_text).to_int()
	if record.get("galaxy_id", "") != Identity.child_id(universe_id, "galaxy", str(index)):
		errors.append("galaxy ID mismatch")
	var address: Variant = record.get("cell_address", null)
	if not address is Dictionary:
		errors.append("invalid cell address")
		return errors
	var cell: Array[int] = []
	for key: String in ["x", "y", "z"]:
		var value: Variant = address.get(key, null)
		if not _canonical_integer(value):
			errors.append("invalid cell coordinate")
			return errors
		cell.append(String(value).to_int())
	if Placement.index_from_cell(cell[0], cell[1], cell[2]) != index:
		errors.append("cell does not belong to galaxy index")
	var radius: float = record.get("envelope_radius_ly", -1.0)
	if not is_finite(radius) or radius < Placement.MIN_RADIUS_LY or radius > Placement.MAX_RADIUS_LY:
		errors.append("invalid envelope radius")
		return errors
	var offset: Variant = record.get("center_offset_ly", null)
	if not offset is Array or offset.size() != 3:
		errors.append("invalid offset")
		return errors
	for coordinate in offset:
		var value: float = coordinate
		if not is_finite(value) or absf(value) + radius + Placement.MIN_GAP_LY * 0.5 > Placement.CELL_WIDTH_LY * 0.5:
			errors.append("envelope crosses padded cell boundary")
	var axes: Variant = record.get("galaxy_to_universe_axes", null)
	if not axes is Array or axes.size() != 3:
		errors.append("invalid axes")
		return errors
	for axis in axes:
		if not axis is Array or axis.size() != 3:
			errors.append("invalid axis dimensions")
			return errors
		for component in axis:
			if not is_finite(float(component)):
				errors.append("nonfinite orientation")
				return errors
	for i: int in range(3):
		for j: int in range(3):
			var dot: float = 0.0
			for k: int in range(3):
				dot += float(axes[i][k]) * float(axes[j][k])
			if absf(dot - (1.0 if i == j else 0.0)) > 1.0e-12:
				errors.append("orientation not orthonormal")
	var determinant: float = float(axes[0][0]) * (float(axes[1][1]) * float(axes[2][2]) - float(axes[1][2]) * float(axes[2][1]))
	determinant -= float(axes[1][0]) * (float(axes[0][1]) * float(axes[2][2]) - float(axes[0][2]) * float(axes[2][1]))
	determinant += float(axes[2][0]) * (float(axes[0][1]) * float(axes[1][2]) - float(axes[0][2]) * float(axes[1][1]))
	if absf(determinant - 1.0) > 1.0e-12:
		errors.append("orientation not right handed")
	return errors


static func pair_clearance_ly(a: Dictionary, b: Dictionary) -> float:
	if a["universe_id"] != b["universe_id"] or a["galaxy_id"] == b["galaxy_id"]:
		return NAN
	var squared: float = 0.0
	# Deliberately reconstruct from address differences here, independently of
	# placement.relative_centres_ly(), so the pair test can catch its mistakes.
	for axis: int in range(3):
		var key: String = ["x", "y", "z"][axis]
		var integer_difference: int = String(a["cell_address"][key]).to_int() - String(b["cell_address"][key]).to_int()
		var delta: float = float(integer_difference) * Placement.CELL_WIDTH_LY + float(a["center_offset_ly"][axis]) - float(b["center_offset_ly"][axis])
		squared += delta * delta
	return sqrt(squared) - float(a["envelope_radius_ly"]) - float(b["envelope_radius_ly"])
