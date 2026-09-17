@tool
class_name MoonSurfaceProfileSet
extends Resource

## Container for all available MOON surface profiles - separate catalog
## from SurfaceProfileSet (planets). Add/remove MoonSurfaceProfile assets
## in the inspector - no code changes needed.

@export var profiles: Array[MoonSurfaceProfile] = []

func get_random_profile(rng: RandomNumberGenerator) -> MoonSurfaceProfile:
	if profiles.is_empty():
		push_error("MoonSurfaceProfileSet has no profiles assigned")
		return null
	var index: int = rng.randi_range(0, profiles.size() - 1)
	return profiles[index]

func get_profile_by_name(profile_name: String) -> MoonSurfaceProfile:
	for profile in profiles:
		if profile.profile_name == profile_name:
			return profile
	return null
