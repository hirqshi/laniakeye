class_name LkDebugNavigationOverlay
extends Control

var items: Array = []
var marks_visible: bool = true
var planets_visible: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var viewport: Vector2 = get_viewport_rect().size
	var occupied: Array[Rect2] = []
	for item: Dictionary in items:
		if (item["marker"] and not marks_visible) or (not item["marker"] and not planets_visible):
			continue
		var point: Vector2 = item["point"]
		var color: Color = Color(0.35, 0.95, 1.0) if item["marker"] else Color(1.0, 0.75, 0.3)
		if item.get("active", false):
			color = Color(0.45, 1.0, 0.5)
		if item["blocked"]:
			color = color.darkened(0.3)
		draw_arc(point, 5.0, 0.0, TAU, 16, color, 1.5, true)
		if item["edge"]:
			var toward: Vector2 = (point - viewport * 0.5).normalized()
			var side: Vector2 = toward.orthogonal()
			draw_line(point + toward * 8.0, point - toward * 2.0 + side * 4.0, color, 1.5, true)
			draw_line(point + toward * 8.0, point - toward * 2.0 - side * 4.0, color, 1.5, true)
		var line1: String = item["name"]
		var line2: String = item["distance"] + (" | occluded" if item["blocked"] else "")
		var width: float = maxf(font.get_string_size(line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, font.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x) + 12.0
		var box: Rect2 = Rect2(Vector2(clampf(point.x + 10.0, 2.0, maxf(2.0, viewport.x - width - 2.0)), clampf(point.y - 25.0, 2.0, maxf(2.0, viewport.y - 40.0))), Vector2(width, 38.0))
		for attempt: int in range(12):
			var collision: bool = false
			for previous: Rect2 in occupied:
				if previous.intersects(box):
					collision = true
					break
			if not collision:
				break
			box.position.y = fposmod(box.position.y + 40.0, maxf(1.0, viewport.y - 40.0))
		occupied.append(box)
		draw_line(point, box.get_center(), Color(color, 0.35), 1.0, true)
		draw_style_box(_background(), box)
		draw_string(font, box.position + Vector2(6.0, 15.0), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		draw_string(font, box.position + Vector2(6.0, 31.0), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

var _panel: StyleBoxFlat
func _background() -> StyleBoxFlat:
	if _panel == null:
		_panel = StyleBoxFlat.new()
		_panel.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	return _panel
