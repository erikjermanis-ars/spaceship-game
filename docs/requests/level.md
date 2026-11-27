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
  bow north, port side to the pier, the HALCYON's home; **Berth E2** at (656, 138) m, bow south, starboard to the
  pier, the KESTREL's. Both are real `FrigateShip`s (instanced in `main.tscn`), and either can use any free berth.
  Each berth has two colliding clamp pylons built from the hull's hardpoints in `FrigateShape` (forward about 48 m
  long to the hull's rim, aft about 23 m to the outer face of a drive ring, tips 3.5 m off the hull) and a gangway
  housing; the clamp arms and the gangway are drawn by the module from the `FrigateDock` state of the ship using
  the berth, the gangway in the overhead band (registered in `LevelArt.depth_layers` so it gets the parallax).
  `gangway_scene` / `gangway_arrival` name the interior behind the gangway (E2: the Pier 7 concourse; E1: Pier 7
  North).
- Frigates arriving from a jump drop out at (890, 0) m heading west, between the two berths' approach lanes and
  inside the Perimeter traffic lane (`Sectors.DEFS`). Keep that spot clear of structure.
- The gunnery range is at (−450, 425) m; the Yards Supply Intake (a `FreightReceiver`, id `yards`) at (0, −420) m.
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

## Vesper Rock (the `Outpost` subtree)
All positions are metres in Vesper's frame; add (9000, 0) for world metres, ×10 for px. Sector: ±800 × ±650.
- `Level/Outpost` is an instance of `scenes/level/outpost.tscn` at world (90000, 0) px. `Level.bounds_m` is still
  Meridian's: the sector system switches world bounds.
- **Berth V1** (`Outpost/BerthV1`, `FrigateBerth`, `berth_id = "V1"`): origin (0, 0) = Vesper's origin, rotation 0
  (bow east), `pier_side = 1` (starboard to the pier), `pier_dist_m = 71`. The pier wall is the north face of the
  spar: y = 71, x −110..110, 24 m deep, real hull (`Outpost/Spar`). Airlock side of the wall is x ≈ +12.
- **Frigate lane** = the berth axis, y = 0. Nothing collides within 90 m of it on the open (north) side anywhere
  in the sector, and nothing within 90 m on either side west of x = −112 or east of x = +112. Jump arrival is
  (−560, 0) heading east: 560 m of straight lane to the capture position. Lane lights (below-deck, no collision)
  stand at y = ±56, |x| = 140..500.
- **The rock** (`Outpost/Base/VesperRock`): x −206..117, y 97..341. `Outpost/Base` is at (0, 230); the rock,
  apron and pads are authored in its frame. The trunk from the pier to HAB A is x −6..6, y 93..165; buttresses at
  x = ±72.
- **Apron** (`Outpost/Base/VesperApron`, a registered walk deck named "Vesper Apron"): the open part is
  x −161..51, y 282..372 (the south edge is open). Pads `Vesper 1` at (−120, 330) and `Vesper 2` at (−48, 330),
  both heading east (rotation 0), labels V1 / V2. Ore hoppers (colliding): x 12..45, y 285..299.
  **Free slot for the freight intake: x −3..27, y 320..340** (centre (12, 330), 30 × 20 m), nothing on it.
- **Asteroid field** (`Outpost/Field`, `asteroid_field.gd`, seed 4211, 40 rocks, 10 of them ore). Rocks are
  children of `Field/Rocks` (so are fragments and ore canisters). Keep-clear areas are exports on the node:
  the lane strip (|y| < 100 across the sector), the rock and apron, 120 m circles on both pads and a 140 m circle
  on the jump arrival point; a rock's home is at least its own reach (size + drift circle, up to 43 m) outside them.
  The field is asleep (`Rocks.process_mode = DISABLED`, hidden) unless a camera or a `player_ship` is within
  2400 m of the outpost.
- **Rocks** (`scripts/level/asteroid.gd`, `class_name Asteroid`): `RigidBody2D`, layer PROPS, mask
  WORLD|PLAYER|PROPS|TRAFFIC, groups `asteroid` and `radar_prop`, expose `prev_velocity` / `prev_velocity2`.

  | class | radius | mass | hit points |
  |---|---|---|---|
  | 0 small | 2 m | 8 t | 30 |
  | 1 medium | 4.5 m | 70 t | 90 |
  | 2 large | 9 m | 500 t | 240 |

  Mass is scaled by the outline's area (0.6..1.2). They report `Game.impact` for rock↔world, rock↔rock (lower
  instance id) and rock↔traffic; never for the player, and never for a container (the container reports that
  one). `take_shot(damage, at, dir, shooter)`: impulse 500 N·s per point of damage along `dir` at `at`; at zero a
  rock becomes 2 or 3 rocks of the class below (set by its seed) flying apart at 2 to 4.5 m/s, class 0 just
  bursts, and `Game.target_destroyed("asteroid")` is emitted once per rock destroyed. An ore rock (any class)
  drops one canister when it is destroyed; its fragments are plain rock. The canister is a `cargo_box.gd`
  (6.1 × 2.44 m, 1.8 t, brand `ORE`, groups `cargo_container`, `radar_prop`, `ore_canister`).
- Station keeping: each rock is pulled toward `home` like a spring with a 150 s period (capped at 0.05 m/s²),
  speed above 1.6 m/s and spin above 0.35 rad/s bleed off at 0.3/s. Rocks drift on circles of 6 to 24 m at up to
  1 m/s.
- Sounds, by file name through `GameplayUtil.load_audio()` (missing files are skipped): `rock_crack_1.wav`,
  `rock_crack_2.wav` (a chip), `rock_shatter.wav` (a break). Bus `SFX`, positional.
- 4 `AmbientEmitter` hums: rock, crusher, apron (under `Base`) and spar.
- Draw calls: the whole outpost in view is about 110; a rock is 1 (2 with ore glints, +1 once cracked).
- `scenes/test/outpost_test.tscn` (headless) checks the field on its own; `level_validate` has an `[outpost]`
  section (berth, lane, pads, apron slot, field seed and placement).

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
