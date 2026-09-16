class_name SurfaceProfileSet
extends Resource

## Container for all available surface profiles in the game.
## Add/remove SurfaceProfile assets in the inspector - no code changes needed.

@export var profiles: Array[SurfaceProfile] = []

func get_random_profile(rng: RandomNumberGenerator) -> SurfaceProfile:
	if profiles.is_empty():
		push_error("SurfaceProfileSet has no profiles assigned")
		return null
	var index: int = rng.randi_range(0, profiles.size() - 1)
	return profiles[index]

func get_profile_by_name(profile_name: String) -> SurfaceProfile:
	for profile in profiles:
		if profile.profile_name == profile_name:
			return profile
	return null
