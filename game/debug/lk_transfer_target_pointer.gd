extends Control

var projection: Dictionary = {}
var caption: String = ""
var blocked: bool = false

func _draw() -> void:
	if not projection.get("valid", false):
		return
	var point: Vector2 = projection["point"]
	var color: Color = Color(1.0, 0.67, 0.2) if blocked else Color(0.2, 0.95, 1.0)
	var diamond: PackedVector2Array = PackedVector2Array([point + Vector2(0, -10), point + Vector2(10, 0), point + Vector2(0, 10), point + Vector2(-10, 0), point + Vector2(0, -10)])
	draw_polyline(diamond, color, 2.0, true)
	if projection.get("edge", false):
		var toward: Vector2 = (point - size * 0.5).normalized()
		var side: Vector2 = Vector2(-toward.y, toward.x)
		draw_colored_polygon(PackedVector2Array([point + toward * 12.0, point - toward * 5.0 + side * 6.0, point - toward * 5.0 - side * 6.0]), color)
	var text: String = caption
	if blocked:
		text += " [OCCLUDED]"
	if projection.get("behind", false):
		text += " [BEHIND CAMERA]"
	var font: Font = ThemeDB.fallback_font
	var x: float = clampf(point.x + 15.0, 8.0, maxf(8.0, size.x - 430.0))
	var y: float = clampf(point.y + 23.0, 24.0, maxf(24.0, size.y - 12.0))
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, 420.0, 16, color)
