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

func get_distributed_profiles(rng: RandomNumberGenerator, count: int) -> Array[SurfaceProfile]:
	var result: Array[SurfaceProfile] = []

	if profiles.is_empty() or count <= 0:
		return result

	if count <= profiles.size():
		var shuffled: Array[SurfaceProfile] = profiles.duplicate()
		_shuffle(shuffled, rng)
		for i in range(count):
			result.append(shuffled[i])
		return result

	var shuffled_full_set: Array[SurfaceProfile] = profiles.duplicate()
	_shuffle(shuffled_full_set, rng)
	result.append_array(shuffled_full_set)

	var remaining: int = count - profiles.size()
	for i in range(remaining):
		result.append(get_random_profile(rng))

	_shuffle(result, rng)
	return result

func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: Variant = array[i]
		array[i] = array[j]
		array[j] = temp
