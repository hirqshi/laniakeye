class_name UniversePosition
extends RefCounted

var x: float
var y: float
var z: float


func _init(x: float = 0.0, y: float = 0.0, z: float = 0.0) -> void:
	self.x = x
	self.y = y
	self.z = z


func to_vector3() -> Vector3:
	return Vector3(x, y, z)


func from_vector3(v: Vector3) -> void:
	x = v.x
	y = v.y
	z = v.z


static func from_vector3_static(v: Vector3) -> UniversePosition:
	return UniversePosition.new(v.x, v.y, v.z)


func distance_to(other: UniversePosition) -> float:
	var dx: float = x - other.x
	var dy: float = y - other.y
	var dz: float = z - other.z
	return sqrt(dx * dx + dy * dy + dz * dz)


func add(other: UniversePosition) -> UniversePosition:
	return UniversePosition.new(x + other.x, y + other.y, z + other.z)


func subtract(other: UniversePosition) -> UniversePosition:
	return UniversePosition.new(x - other.x, y - other.y, z - other.z)
