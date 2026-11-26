# LEVEL subsystem: notes

## What `res://scenes/level/level.tscn` provides (contract §3)
- Root `Level` (`scripts/level/level.gd`): sets `Game.level` and `Game.world_bounds`
  (x −1100..1100 m, y −900..900 m, so `Rect2(-11000, -9000, 22000, 18000)` px). It is also in group `meridian_level`.
- `PlayerSpawn` (group `player_spawn`) sits on **Pad 1** of the commerce pier at (532, 230) m and faces **west** (rotation π).
- `RaceCourse` → `Gate01`..`Gate15` (meta `width_m`), a loop of about 4.8 km: pier straight → drydock north channel
  (28 m gates) → solar-field serpentine → in through any ring gap, around the hub, out through another gap → crane
  arc in Cargo Yard C → finish at (450, 300) m, just south of the start gate. `Gate13` is inside the crane's slew
  arc: the boom crosses it about every 12 s.
- Docking pads (Area2D, group `docking_pad`, layer TRIGGERS, mask PLAYER, meta `pad_name`): `Pad 1`..`Pad 4`
  (pier, facing west), `Hangar Bay` (inside Hangar 2, facing west, behind the cycling blast door), and `Pad 5` and
  `Pad 6` (tug & service dock, facing east). Each pad's Area2D is a child named `DockTrigger` of the pad module.
  Its +X is the docked heading.
- Frigate berths on the pier's east face (`FrigateBerth`, group `frigate_berth`): **Berth E1** at (656, −138) m,
  bow north, port side to the pier, holding the static HALCYON; **Berth E2** at (656, 138) m, bow south, starboard to
  the pier, the KESTREL's. They replace the old freighters and the pier's east mooring arms (`Pier.mooring_rows_m` is
  empty now). Each has two colliding clamp pylons (forward 46 m, aft 37.5 m long, tips 3.5 m off the hull) and a gangway
  housing; the clamp arms and the gangway are drawn by the module from the frigate's `FrigateDock` state, the gangway
  in the overhead band (registered in `LevelArt.depth_layers` so it gets the parallax).
- `radar_structure`: every station module with collision implements `get_radar_polygons()` (global coordinates,
  simplified, and the rotating ring is returned in its current rotation). `radar_traffic`: the AnimatableBody2D of
  each AI ship (11 ships). `radar_prop`: the 43 cargo containers.

## Physics facts
- All colliding structure is on LAYER_WORLD with mask 0. Moving structure uses AnimatableBody2D with
  `sync_to_physics` and is moved in `_physics_process`: the Meridian Ring spins at 0.026 rad/s (outer rim moves at
  about 6 m/s), two hangar blast-door leaves cycle (open 6 s, close 2.6 s, closed 4.5 s, open 2.6 s), and the cargo
  crane boom swings ±46° with a 24 s period (tip speed up to about 20 m/s).
- Traffic: AnimatableBody2D on LAYER_TRAFFIC (mask 0). They don't avoid anything, so they are hazards.
  `body.get_meta("traffic_kind")` is `"shuttle" | "tug" | "freighter"`.
- Containers (`scripts/level/cargo_box.gd`): RigidBody2D, layer PROPS, mask WORLD|PLAYER|PROPS|TRAFFIC. Mass is
  about 1.8 t for 6 m boxes and 3.6 t for 12 m boxes. They emit `Game.impact(pos, normal, speed_mps, self, other)`
  for prop↔world, prop↔prop (only the lower instance id reports) and prop↔traffic contacts. They never report
  contacts with the player. They are in group `cargo_container` and expose `prev_velocity` (px/s, before the
  current step).
- Physics material: structures bounce 0.3 and friction 0.25. Containers bounce 0.32 and friction 0.35.

## Rendering facts
- Depth bands use absolute z: decks −50..−47, structure −10..−7, overhead shadow 19, overhead 20,
  overhead FX 30/31, debug 35. Traffic ships draw at Z_PROPS (0..3). Blast doors draw at −15 so they slide under
  the hangar walls.
- 2.5D parallax: below-deck layers scale ×0.95 and overhead layers scale ×1.06 about the camera's screen centre.
  The Level does this in `_process` with `process_priority = 1000`, so it runs after the camera rig has moved.
  If you see overhead trusses lag one frame behind the camera, that ordering is the reason.
- Every blinking light is animated by one shader uniform. `Level.beacon_time()` is that clock (the buoy pings use
  it to sync with the flashes).
- F3 / `Game.debug_draw` shows the convex collision pieces of every module, container and traffic ship in
  magenta.

## Audio (all positional, all guarded with `ResourceLoader.exists` and skipped when headless)
- `station_hum_loop.wav`: 14 `AmbientEmitter`s (bus `Ambient`, about 260 m reach, pitch varied per district).
- `traffic_engine_loop.wav`: on each traffic ship (bus `SFX`, freighters lower and louder).
- `beacon_ping.wav`: the Ring Orbit lane buoys, played at the buoy nearest the camera on every second flash.
- `door_servo.wav`: the hangar door when it starts to open or close, and the crane boom when it reverses
  (pitch 0.8).

## Test scenes
- `res://scenes/test/level_tour.tscn`: level plus background with a touring camera. Args after `--`:
  `--cam=x_m,y_m,zoom` for a fixed view, `--show-gates` for the race overlay, `--fps` to log FPS and draw calls,
  `--no-bg`, `--no-level`, `--hide-band=DECK_SHADOW`.
- `res://scenes/test/level_validate.tscn` (headless): contract, spawn, gate and lane clearance, and prop impacts.
  Prints `RESULT: OK`.

## Requests
- GAMEPLAY / RaceSystem: Gates 09 to 12 go through the rotating ring, so there is no fixed line. Players pick
  whichever gap is near. Please don't draw a guide line straight from Gate09 to Gate10 through the ring.
- Nothing else is blocking.
