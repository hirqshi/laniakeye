shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

// Renders the far-viewport's texture as a true 3D background plane.
// depth_draw_never means this quad NEVER writes to the depth buffer,
// so real 3D objects (ship, player, terrain) always draw in front of
// it regardless of their actual distance - same trick a custom skybox
// material uses, just sourced from a second camera's SubViewport
// instead of a cubemap/panorama.

uniform sampler2D far_viewport_texture : source_color, filter_linear;

void fragment() {
	ALBEDO = texture(far_viewport_texture, SCREEN_UV).rgb;
}
