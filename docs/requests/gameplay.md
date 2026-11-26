# GAMEPLAY workstream: notes and requests

## What GAMEPLAY provides
- `res://scenes/main.tscn` (+ `scripts/main.gd`): instances SpaceBackground, Level, PlayerShip, CameraRig,
  Systems, HUD and TuningPanel statically. `main.gd` also copes with any of them missing (it instances
  scenes at runtime, or falls back to a stand-in ship and a basic camera). It moves the ship to `PlayerSpawn`,
  or to `--spawn=x,y,deg`, by taking the ship out of the tree and adding it back. Don't set `global_transform`
  on the live CCD body: that sweeps it from the origin through the station and destroys it on frame 1.
- Systems (all under `Main/Systems`, found by group):
  `impact_fx` (ImpactFX), `damage_system`, `race_system`, `docking_system`, `boundary_system`,
  `flight_guide`. AmbientAudio has no group.
- `res://scenes/test/gameplay_sandbox.tscn` is main.tscn with `level_scene` pointed at a simple stand-in level.
- Extra harness args (GAMEPLAY only): `--no-intro` (skips the intro card), `--no-guide` (flight guide off),
  `--kill-at=T` (destroys the ship at physics time T, to test the explosion and respawn).
- Extra input action registered at runtime by FlightGuide: `flight_guide` (G).
- Keyboard actions that GAMEPLAY handles are polled with `Input.is_action_just_pressed` in `_process`, so the
  `--input=` harness can drive them: restart_race R, respawn T, radar_toggle M, help H, pause P/Esc, G.

## Behaviour other workstreams should know
- Damage: `0.41 * max(0, v - 3)^1.5` on the closing speed. Props count ×0.55. Scraping costs about
  0.12 hp/s per m/s above 2 m/s. You get 1.2 s of invulnerability after a respawn.
- `Game.checkpoint_passed(index, total, split)`: `index` is **1-based** (gate number). The first gate starts
  the clock (flying start), so its split is 0.
- Race gates: RaceSystem adds a `GateVisual` child to every `Level/RaceCourse/GateNN` marker. Each visual
  has two **solid** pylons (StaticBody2D, LAYER_WORLD, radius 1.4 m) at ±width/2. Keep the marker ends clear
  of structure, or tell GAMEPLAY to turn `solid_posts` off.
- Docking: a pad arms only when the ship flies onto it from outside. Spawning or respawning on a pad never
  docks you. Guidance shows only below 6 m/s.
- ImpactFX parents scorch decals to the body that was hit (z = Z_STRUCTURE + 1), so marks stay on moving
  structure. The decals are pooled (90), and the pool copes with a body being freed.
- ImpactFX drives camera trauma and punch (`punch(-normal, …)`, so the view carries on into the obstacle).
  The camera's `auto_impact_shake` must stay false.
- The hit-stop sets `Engine.time_scale` to 0.12–0.18 for 45–110 ms on heavy player hits and on
  destruction, then restores the previous value. Unpausing always resets it to 1.

## Requests
- AUDIO (optional): `warp_in.wav`, about 0.8 s: a rising shimmer or whoosh that ends in a soft "thup" as the
  ship materialises. It plays on every respawn (death, R, T). Until it exists, WarpInFX layers
  `boost_kick.wav` (pitch 1.35) with `dock_chime.wav` (pitch 1.5).

## Harness: scripted `pause` no longer hangs (applied in game.gd by the lead)

`Game._physics_process` used to return early while the tree was paused, so an `--input` span that pressed
`pause` never released it and `--quit-at` never fired. Input spans, shots and `--quit-at` now run on a
separate harness clock that also advances while paused. `Game.sim_time()` is unchanged (simulated time only).
