class_name LkDebugNavigationProjection
extends RefCounted

const EPSILON: float = 1.0e-5

static func project_direction(camera: Camera3D, direction: Vector3, viewport: Vector2) -> Dictionary:
	var view: Vector3 = camera.get_camera_transform().basis.inverse() * direction
	return project_view(view, camera.get_camera_projection(), viewport)

static func project_view(view: Vector3, projection: Projection, viewport: Vector2) -> Dictionary:
	if not viewport.is_finite() or viewport.x <= 0.0 or viewport.y <= 0.0:
		return {"point": Vector2.ZERO, "edge": false, "behind": false, "valid": false}
	var center: Vector2 = viewport * 0.5
	if not view.is_finite() or not is_finite(view.length_squared()) or view.length_squared() < 1.0e-20:
		return {"point": center, "edge": false, "behind": false, "valid": false}
	view = view.normalized()
	var half: Vector2 = Vector2(maxf(viewport.x * 0.5 - 34.0, 0.0), maxf(viewport.y * 0.5 - 34.0, 0.0))
	var behind: bool = view.z >= 0.0
	var clip: Vector4 = projection * Vector4(view.x, view.y, view.z, 1.0)
	var delta: Vector2
	if view.z < -EPSILON and clip.is_finite() and clip.w > EPSILON:
		delta = Vector2(clip.x, -clip.y) / clip.w * viewport * 0.5
		if delta.is_finite() and absf(delta.x) <= half.x and absf(delta.y) <= half.y:
			return {"point": center + delta, "edge": false, "behind": false, "valid": true}
	# Direct angular edge pointer. Never divide by w near the camera plane.
	if clip.is_finite():
		delta = Vector2(clip.x, -clip.y) * viewport * 0.5
	else:
		delta = Vector2(view.x, -view.y)
	if not delta.is_finite() or delta.length_squared() < 1.0e-12:
		delta = Vector2.DOWN
	# Normalize by largest component, avoiding huge products or squared lengths.
	delta /= maxf(absf(delta.x), absf(delta.y))
	var factor: float = minf(half.x / maxf(absf(delta.x), 1.0e-12), half.y / maxf(absf(delta.y), 1.0e-12))
	var point: Vector2 = center + delta * factor
	point.x = clampf(point.x, 0.0, viewport.x)
	point.y = clampf(point.y, 0.0, viewport.y)
	return {"point": point, "edge": true, "behind": behind, "valid": true}
