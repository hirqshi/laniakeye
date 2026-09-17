class_name CelestialNameGenerator
extends RefCounted

## Pure, deterministic name generation for planets/moons. Same planet_seed
## always produces the same name - no state, no node, fully testable.
##
## Style: syllable-built name (2-3 syllables, pronounceable but alien)
## + a short catalog code (single letter + 2-3 digits), e.g. "Vetheris K-42".
## The catalog code alone would feel too sterile/sci-fi-generic on its own,
## and the syllable name alone loses the "this was surveyed and logged"
## feel - combining both gives a lived-in universe without needing an
## actual lore/language system.
##
## Moons reuse the parent planet's name as a prefix + roman-numeral-like
## index ("Vetheris K-42 I", "Vetheris K-42 II") - matches real astronomical
## convention (see Jupiter's moons) and makes it immediately clear which
## planet a moon belongs to just from the label.

const SYLLABLES_START: Array[String] = [
	"Ve", "Xa", "Ko", "Ny", "Ze", "Or", "Ka", "Ith", "Ul", "Ae",
	"Vo", "Ry", "Sha", "Tu", "Iv", "Qu", "Ne", "Ax", "El", "Ur",
]

const SYLLABLES_MID: Array[String] = [
	"the", "ra", "lo", "vi", "nu", "ka", "ren", "do", "shi", "ta",
	"mi", "co", "ze", "pha", "gu", "ri", "no", "ve", "sa", "lu",
]

const SYLLABLES_END: Array[String] = [
	"ris", "os", "eth", "ax", "ion", "ul", "an", "ora", "iss", "eon",
	"yr", "tha", "und", "ex", "ir", "om", "as", "yth", "ov", "en",
]

const CATALOG_LETTERS: String = "ABCDEFGHJKLMNPQRSTVXYZ"

const ROMAN_NUMERALS: Array[String] = [
	"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
]

## Generates a name for a top-level planet. seed drives every random
## choice deterministically - same seed, same name, every time.
static func generate_planet_name(planet_seed: int) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = planet_seed

	var syllable_name: String = _build_syllable_name(rng)
	var catalog_code: String = _build_catalog_code(rng)

	return "%s %s" % [syllable_name, catalog_code]

## Generates a moon's name from its own seed AND its parent planet's
## already-generated name - moon_index is the moon's position in its
## parent's moons array (0-based), used for the roman numeral suffix.
static func generate_moon_name(parent_planet_name: String, moon_index: int) -> String:
	var numeral: String = ROMAN_NUMERALS[moon_index] if moon_index < ROMAN_NUMERALS.size() else str(moon_index + 1)
	return "%s %s" % [parent_planet_name, numeral]

static func _build_syllable_name(rng: RandomNumberGenerator) -> String:
	var start: String = SYLLABLES_START[rng.randi_range(0, SYLLABLES_START.size() - 1)]
	var mid: String = SYLLABLES_MID[rng.randi_range(0, SYLLABLES_MID.size() - 1)]
	var end: String = SYLLABLES_END[rng.randi_range(0, SYLLABLES_END.size() - 1)]

	# occasionally skip the middle syllable for shorter, punchier names
	if rng.randf() < 0.3:
		return start + end

	return start + mid + end

static func _build_catalog_code(rng: RandomNumberGenerator) -> String:
	var letter: String = CATALOG_LETTERS[rng.randi_range(0, CATALOG_LETTERS.length() - 1)]
	var number: int = rng.randi_range(1, 999)
	return "%s-%d" % [letter, number]
