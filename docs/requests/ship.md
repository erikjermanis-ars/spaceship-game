# SHIP subsystem: notes and requests

## Provided (contract §3/§4 and some extras)
- `res://scenes/ship/player_ship.tscn` (`PlayerShip`), `res://scenes/ship/camera_rig.tscn` (`CameraRig`),
  `res://scenes/ui/tuning_panel.tscn`. The full §4 API is implemented.
- Extra read-only PlayerShip fields (HUD/FX may use them):
  `main_output` (signed fraction of full main thrust: 1 = 100 % throttle, retro goes down to −`reverse_scale`),
  `bow_lateral_output` / `stern_lateral_output` (signed: + = force toward starboard, so gas leaves the port side),
  `dbg_main_force`, `dbg_side_force`, `dbg_strafe_force` (N, world-oriented), `recent_contacts`,
  `thrust_point_local()`, and the local signal `contact_impact(pos, normal, speed_mps, other)`.
- All flight tunables are exported SI vars, e.g. `main_thrust_n`, `side_thrust_n`, `thrust_point_m`, `mass_kg`,
  `inertia_per_mass_m2`, `linear_drag`, `angular_drag`, `reverse_scale`, `turn_couple`, `strafe_thrust_n`,
  `bounce`, `friction`. Setting them at runtime works (mass, inertia and material update live).

## Behaviour other code should know
- **Impact events** come out one physics tick (8 ms) after the contact. They are queued in `_integrate_forces` and
  emitted from `_physics_process`, so listeners never run inside the physics server callback.
  `speed_mps` is the closing speed along the normal, measured from the PRE-contact relative velocity at the contact
  point. It accounts for the ship's spin, the surface velocity of AnimatableBody2D (a rotating ring is handled), and
  the pre-step velocity of RigidBody2D props (the ship caches nearby props through a sensor Area2D).
  Verified: Godot 4.7 `get_contact_local_position()` returns GLOBAL coordinates, and `get_contact_local_normal()`
  points from the collider toward the ship (see `tests/ship_contact_probe.gd`).
- **Scrape**: emitted every physics frame while the ship is in contact and sliding (tangent > 1 m/s). Short gaps
  between micro-bounces (up to 0.12 s, while the ship stays within 0.6 m of the surface) are bridged, so the scrape
  loop doesn't chatter.
- **Camera shake**: `CameraRig.auto_impact_shake` is **false** by default, because GAMEPLAY's ImpactFX already calls
  `add_trauma()` / `punch()`. `punch()` clamps `strength_px` to 48. The camera adds its own light rumble when
  the main engine runs in its top range (trauma floor up to 0.2 above 60 % output, about 1 px).
- On impact the ship does only ship-local reactions: a hull flash and white paint flecks. Sparks, sounds and decals
  are left to ImpactFX.
- The ship **does not** handle the `respawn` (T) key. DamageSystem / RaceSystem call `respawn_at()` as they do now.
- The engine exhaust has a `PointLight2D` (additive, low energy, about 25 m reach behind the ship) that lightly
  lights nearby world-canvas items. Any CanvasItem that shouldn't be lit can set `light_mask = 0`. The background
  CanvasLayer is not affected.
- The drop shadow is drawn at absolute z `Z_BELOW_DECK + 4` (offset 1.2 m right and 1.6 m down in world space), so it
  only falls on below-deck art and empty space, never on colliding structure.
- The tuning panel is CanvasLayer `layer = 60`. It handles `tuning_panel` in `_input` and marks the event handled.
  All its controls use `FOCUS_NONE`.
- Harness extras: `--cam-zoom=2.5` (manual zoom factor), `--cam-rotate`, `--tuning` (open the panel at start). The
  sandbox only: `--hull=20`, `--no-env`, `--no-fx`.

## Requests
- Resolved: judder on displays whose refresh rate isn't a divisor of 120 Hz. The hull art and the camera follow
  `render_transform()`, which interpolates between the last two physics steps.
- Headless runs print `N resources still in use at exit` for AudioStreamPlayers that were still playing at quit
  (dummy audio driver never releases playbacks; windowed runs exit clean). The ship's audio node skips creating
  players when `DisplayServer.get_name() == "headless"`. Other code can use the same guard to keep test logs clean.

## Frigate notes (KESTREL and HALCYON)
- `FrigateShip` overrides `_apply_flight_forces()` completely: three main engines at their positions (impulse at
  (−66, 0) m, drive rings at (−38, ±34) m), the turn couple with per-section efficiency, strafe, assist / all
  stop, venting forces, drag. During soft capture it applies only `FrigateDock.apply_capture()`, and during a
  quantum jump only `jump_ctl.apply()` (pilot forces are ignored in both).
- Hull damage goes through `take_damage()` into `FrigateDamage.hit()`; `hull` is the sections' weighted average.
  Damage is ignored while clamped (frozen). `damage_scale()` is 0.3 for props. Sections by hit position:
  drive rings beyond |y| 21 m (aft of x 0), bow forward of x 30 m, Engineering aft of x −18 m.
- Its collision is one convex `CollisionPolygon2D` per part from `FrigateShape.PARTS` (43 parts: the hull in
  slices, the hangar block, the two bay arms, four pylons and 16 quads per drive ring; the first keeps the name
  `CollisionPolygon2D`); `destroy()` / `respawn_at()` toggle all of them. The flight deck between the arms has no
  collision: small ships fly into it. `max_contacts_reported` is 12 and the prop sensor radius 95 m.
- `warp_to(xf, velocity)` moves a live frigate safely (in-callback teleport); the jump uses it.
- Signals for presentation: `dock_event(event)` ("capture", "lock", "gangway", "undock", "unclamp", "release") and
  `damage_event(kind, data)` ("hit", "shields_down", "shields_up", "alert", "core_breach", "destroyed").
