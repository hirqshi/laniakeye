# surface_type_util.gd
class_name SurfaceTypeUtil
extends RefCounted

const COUNT: int = 5

static func get_color_for(surface_type: PlanetData.SurfaceType, rng: RandomNumberGenerator) -> Color:
	match surface_type:
		PlanetData.SurfaceType.ROCKY:
			return Color(rng.randf_range(0.4, 0.6), rng.randf_range(0.35, 0.5), rng.randf_range(0.3, 0.45))
		PlanetData.SurfaceType.OCEANIC:
			return Color(rng.randf_range(0.1, 0.25), rng.randf_range(0.3, 0.5), rng.randf_range(0.5, 0.7))
		PlanetData.SurfaceType.ICY:
			return Color(rng.randf_range(0.75, 0.9), rng.randf_range(0.8, 0.95), rng.randf_range(0.9, 1.0))
		PlanetData.SurfaceType.VOLCANIC:
			return Color(rng.randf_range(0.3, 0.5), rng.randf_range(0.1, 0.2), rng.randf_range(0.05, 0.15))
		PlanetData.SurfaceType.BARREN:
			return Color(rng.randf_range(0.5, 0.65), rng.randf_range(0.48, 0.6), rng.randf_range(0.45, 0.55))
		_:
			return Color.WHITE
