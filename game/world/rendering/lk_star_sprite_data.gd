class_name LkStarSpriteData
extends RefCounted

const Photo = preload("res://game/world/generation/lk_stellar_photometry.gd")


static func build(candidates: Array, magnitude_limit: float = 6.0, sprite_budget: int = 8192) -> Dictionary:
	if not is_finite(magnitude_limit) or sprite_budget < 1 or sprite_budget > 32768:
		return {"ok": false, "code": "invalid_sprite_parameters"}
	var stars: Array[Dictionary] = []
	var seen: Dictionary = {}
	for candidate: Dictionary in candidates:
		var id: String = candidate["star_id"]
		if seen.has(id):
			return {"ok": false, "code": "duplicate_star"}
		seen[id] = true
		var photo: Dictionary = Photo.describe_star(id)
		if photo.is_empty():
			return {"ok": false, "code": "invalid_star"}
		var observation: Dictionary = Photo.observe(photo, candidate["distance_ly"], magnitude_limit)
		if not observation["ok"]:
			return observation
		if not observation["passes_limit"]:
			continue
		var direction: Array = candidate["direction_galaxy"]
		if direction.size() != 3:
			return {"ok": false, "code": "invalid_direction"}
		var length_squared: float = 0.0
		for component in direction:
			if not is_finite(float(component)):
				return {"ok": false, "code": "invalid_direction"}
			length_squared += float(component) * float(component)
		if absf(length_squared - 1.0) > 1.0e-6:
			return {"ok": false, "code": "direction_not_unit"}
		var rgb: Array = photo["color_srgb"]
		var linear: Color = Color(rgb[0], rgb[1], rgb[2]).srgb_to_linear()
		var magnitude: float = observation["apparent_magnitude_proxy"]
		stars.append({"star_id": id, "direction_galaxy": direction.duplicate(),
			"color_linear": linear, "magnitude_proxy": magnitude,
			"flux_at_limit": pow(10.0, -0.4 * (magnitude - magnitude_limit)),
			"distance_ly": candidate["distance_ly"]})
	stars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["magnitude_proxy"] == b["magnitude_proxy"]:
			return String(a["star_id"]) < String(b["star_id"])
		return float(a["magnitude_proxy"]) < float(b["magnitude_proxy"])
	)
	var passed: int = stars.size()
	if stars.size() > sprite_budget:
		stars.resize(sprite_budget)
	return {"ok": true, "stars": stars, "input_candidates": candidates.size(),
		"passed_magnitude": passed, "budget_omitted": passed - stars.size(),
		"complete": passed <= sprite_budget, "magnitude_limit": magnitude_limit}
