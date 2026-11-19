class_name LkStellarPhotometry
extends RefCounted

const Identity = preload("res://world/generation/lk_world_identity.gd")
const Samples = preload("res://world/generation/lk_world_samples.gd")
const Bodies = preload("res://world/generation/lk_body_catalog.gd")
const VERSION: int = 1
const PARSEC_LY: float = 3.261563777167433
const SOLAR_MAGNITUDE_PROXY: float = 4.83


# Approximate MAIN-SEQUENCE visual proxy. No new star masses/radii, giants,
# extinction, bolometric correction or spectral integration are introduced.
static func describe_star(star_id: String) -> Dictionary:
	if not Identity.is_valid_id(star_id) or Bodies.BODY_SCHEMA_VERSION != 1:
		return {}
	var mass: float = Bodies.SOLAR_MASS_KG * (0.5 + Samples.unit(star_id, "bodies/star_mass", 1))
	var ratio: float = mass / Bodies.SOLAR_MASS_KG
	var radius: float = Bodies.SOLAR_RADIUS_M * pow(ratio, 0.8)
	var luminosity: float = pow(ratio, 4.0)
	var temperature: float = 5772.0 * pow(luminosity / pow(radius / Bodies.SOLAR_RADIUS_M, 2.0), 0.25)
	var color: Color
	if temperature < 5772.0:
		color = Color(1.0, 0.65, 0.40).lerp(Color(1.0, 0.94, 0.88), clampf((temperature - 3500.0) / (5772.0 - 3500.0), 0.0, 1.0))
	else:
		color = Color(1.0, 0.94, 0.88).lerp(Color(0.78, 0.86, 1.0), clampf((temperature - 5772.0) / (8000.0 - 5772.0), 0.0, 1.0))
	return {"photometry_version": VERSION, "star_id": star_id,
		"mass_kg": mass, "radius_m": radius,
		"luminosity_solar_proxy": luminosity, "temperature_k_proxy": temperature,
		"absolute_magnitude_proxy": SOLAR_MAGNITUDE_PROXY - 2.5 * log(luminosity) / log(10.0),
		"color_srgb": [color.r, color.g, color.b]}


static func apparent_magnitude(absolute_proxy: float, distance_ly: float) -> float:
	if not is_finite(absolute_proxy) or not is_finite(distance_ly) or distance_ly <= 0.0:
		return NAN
	return absolute_proxy + 5.0 * log(distance_ly / (10.0 * PARSEC_LY)) / log(10.0)


static func observe(star: Dictionary, distance_ly: float, limit_proxy: float = 6.0) -> Dictionary:
	var magnitude: float = apparent_magnitude(star["absolute_magnitude_proxy"], distance_ly)
	if not is_finite(magnitude) or not is_finite(limit_proxy):
		return {"ok": false, "code": "invalid_photometry_input"}
	return {"ok": true, "apparent_magnitude_proxy": magnitude,
		"relative_flux": pow(10.0, -0.4 * magnitude), "passes_limit": magnitude <= limit_proxy}
