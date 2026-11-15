# Coordinate and gravity foundation v1

Isolated prototype. Not an autoload and not connected to existing gameplay.
Run scenes/debug/coordinate_gravity_test.tscn with Run Current Scene.
Expect ALL PASS in the HUD and Output. These tests have not been run by the author in Godot.

## Coordinate contract

Distances are meters, time is seconds, mu is GM in m^3/s^2.
LkPosition64 stores three scalar GDScript floats (64-bit). Ordinary Vector3 is NOT a double vector in a standard single-precision build. Subtract large coordinates before converting to Vector3. Copy mutable positions at ownership boundaries. Absolute positions eventually belong in persistence; local positions do not.
The absolute frame is a fixed nonrotating reference frame. No orbital integration is implemented. Body centers can later be supplied by an ephemeris/orbit service. Planet-relative coordinates are absolute_position.minus(body.center).
LkCoordinateFrame is translation-only. Its axes remain fixed. It does not rotate the world or align the horizon. A rotating planetary frame requires velocity transformations and inertial terms and is out of scope.

## Gravity contract

Gravity is the sum of all registered bodies. Dominant body uses optional hysteresis and is metadata, not an abrupt physical force switch. A spherical uniform-density interior avoids a central singularity; this is an explicit prototype model, not geology. Zero resultant acceleration returns has_up=false and up=ZERO; controllers must retain a valid prior orientation or use free-flight handling.

## Rebase contract and limitations

Initialize origin before registering roots. Register only independent, top-level local-world roots; never both parent and child. Do not register distant celestial render proxies as local physics objects. maybe_shift is explicit: the future physics coordinator must choose an execution boundary shared by all active objects. The default threshold is 512 m, not a proven production setting.
Rebase snapshots root absolute positions, moves the origin, regenerates local transforms, resets interpolation, then emits shifted. It changes neither basis nor velocity. No frame-rotation or velocity-origin shifting exists yet. Long relocations must be handled from absolute coordinates, not by first constructing a huge Vector3.
Node3D smoke tests are not proof of atomic physics integration. RigidBody3D roots are explicitly unsupported. Rigid-body descendants, joints, particles, trails, shader world coordinates, navigation, audio, camera history and voxel streaming need dedicated adapters/tests. Caller must not register a parent containing unsupported descendants. Landmark error will eventually increase if distant landmarks remain active local nodes; stream them out or use distant proxies.

## Next gates

1. Audit project.godot, autoloads, existing player, ship, planets and coordinate code before wiring anything into gameplay.
2. Test capsule movement across rebases with a fixed physics boundary and unchanged velocities/contact behavior.
3. Design voxel sampling anchor separately from scene origin: shifting terrain nodes must not change sample locations or lose edited voxel addresses.
4. Validate rebases across chunk boundaries with dug terrain, remeshing and real collision updates.
5. Add frame rotation, moving bodies and interplanetary handoff only with explicit position AND velocity transforms.

Existing player, ship, main scene and working voxel sandbox are unchanged.
