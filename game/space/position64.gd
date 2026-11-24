class_name LkPosition64
extends RefCounted

# Keep large values in scalar GDScript floats, never in Vector3.
var x: float
var y: float
var z: float

func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0) -> void:
	x = px
	y = py
	z = pz

func copy() -> LkPosition64:
	return LkPosition64.new(x, y, z)

func plus(other: LkPosition64) -> LkPosition64:
	return LkPosition64.new(x + other.x, y + other.y, z + other.z)

func minus(other: LkPosition64) -> LkPosition64:
	return LkPosition64.new(x - other.x, y - other.y, z - other.z)

func plus_local(offset: Vector3) -> LkPosition64:
	return LkPosition64.new(x + float(offset.x), y + float(offset.y), z + float(offset.z))

func length_squared() -> float:
	return x * x + y * y + z * z

func length() -> float:
	return sqrt(length_squared())

func direction() -> Vector3:
	var magnitude: float = length()
	if magnitude <= 0.000000001:
		return Vector3.ZERO
	return Vector3(x / magnitude, y / magnitude, z / magnitude)

func relative_to(origin: LkPosition64) -> Vector3:
	return Vector3(x - origin.x, y - origin.y, z - origin.z)
