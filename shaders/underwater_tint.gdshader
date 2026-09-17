
shader_type canvas_item;

// simple fullscreen tint overlay for being underwater, drawn on a
// ColorRect covering the whole viewport. No screen reading - just an
// alpha-blended tinted color, letting Godot's native CanvasItem alpha
// blending darken/tint whatever is already on screen underneath.

uniform vec4 tint_color: source_color = vec4(0.1, 0.3, 0.4, 1.0);
uniform float tint_alpha: hint_range(0.0, 1.0) = 0.0;

// multiplies the tint color's RGB before output - lower values make the
// overlay itself darker regardless of what tint_color happens to be,
// independent of tint_alpha (which controls transparency, not shade).
uniform float darkness_multiplier: hint_range(0.0, 1.0) = 0.4;

void fragment() {
	COLOR = vec4(tint_color.rgb * darkness_multiplier, tint_alpha);
}