# Meridian Approach

A small Godot 4.7 proof of concept: fly a light courier ship around **Meridian Station**, a big, busy orbital
station in a hopeful near-future setting (rotating habitat ring, commerce pier, drydock, cargo yard, solar
field, traffic lanes). It is a single sandbox level meant to show off **ship handling**, **level design**,
**art direction** and **sound design**. Everything (graphics, sound, shaders) is made from scratch in
GDScript, SVG, shader code and a small Python synthesiser. There are no add-ons and no imported asset packs.

Renderer: **Compatibility** (OpenGL), so the project can also be exported to the web.

## Running it

* **Editor:** open `/Users/erikjermanis/work/spaceship-game` in Godot 4.7 and press **Play** (F5). The main
  scene is `res://scenes/main.tscn`.
* **Command line:**
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --path /Users/erikjermanis/work/spaceship-game
  ```

The first second after launch runs slowly while shaders compile and the planet and nebula textures are baked.
After that it runs at the display's refresh rate (110–120 fps measured on an M1 Pro at 1600×900).

## Controls

| Key | Action |
|---|---|
| **W / ↑** | Main engine (thrust is applied at the bow) |
| **S / ↓** | Retro thrust (60 % strength) |
| **A D / ← →** | Bow side thrusters: they turn the ship **and** push it sideways |
| **Q / E** | Strafe thrusters (pure sideways push, no rotation) |
| **Space / Shift** | Boost: doubles all thrust and drains the boost bar. Boost alone pushes forward |
| **F** | Flight assist: damps spin and sideways slip (off by default) |
| **R** | Race: teleport to the pad and start a 3-2-1 countdown |
| **T** | Reset to the last gate you passed (or the spawn pad) |
| **C** | Camera: north-up, or rotate with the ship |
| **Mouse wheel / = / -** | Zoom |
| **M** | Radar, or the full station map |
| **G** | Flight guide (prograde marker and predicted path) |
| **H** | Controls help |
| **Tab / F1** | Live flight-model tuning panel |
| **F3** | Physics debug overlay (collision shapes, forces, contacts) |
| **P / Esc** | Pause |

Gamepads work too: left stick steers, the triggers are throttle and retro, A is boost, Y is flight assist and
the shoulder buttons strafe.

## What to try

* **Learn the ship.** It is modelled on Pat Kerr's 2D-vehicles ship with the side-thrusters option. All thrust
  acts at a point 4 m ahead of the centre of mass, so turning also pushes the whole craft sideways. It keeps
  spinning until you counter-steer, and it drifts. Try a 180° turn and stopping it cleanly, then the same with
  **F** (flight assist). Press **F3** to see the thrust forces, slip and spin live.
* **Fly the Meridian Circuit.** Fly north from Pad 1 through the START gate, past the pier and the commerce pier,
  through the narrow 28 m drydock channels, down the solar-field serpentine, into the rotating ring through any
  gap, around the hub and out another gap, past the swinging cargo crane, and back to the finish. You get splits
  against your best lap, and the best lap is saved.
* **Crash into things.** Light taps clink, medium hits clang and heavy hits crunch with a sub-bass thump. Every
  hit gives sparks, a flash, scorch marks that stay on the hull you hit (even on the rotating ring), camera shake
  and a jolt into the obstacle. Heavy hits also add debris, a shock ring and a brief hit-stop. Sliding along a
  wall plays a grinding scrape with a stream of sparks. Lose all your hull and the ship explodes into shards that
  keep its momentum, then a recovery drone warps you back in.
* **Push cargo.** Cargo Yard C (south) has 43 free-floating containers. Shove them around and knock them into
  each other. The crane boom swings through the yard every 24 s and bats them away.
* **Dock.** Settle on any pad (below 1.5 m/s, aligned with the pad, not spinning) and hold for 1.5 s to get
  clamped, repaired and refuelled. While you keep your hands off the controls the clamps draw the ship onto the
  pad centre and heading and hold it there; any input releases them. The Hangar Bay pad sits behind a blast door
  that cycles open and closed. Its safety interlock holds the leaves while a ship is in the doorway.
* **Watch the traffic.** Eleven AI shuttles, tugs and freighters follow lanes and do not avoid you.
* **Tune the physics live** (Tab). Use presets such as "Nimble racer" and "Heavy freighter", or move any slider
  (thrust, thrust point, inertia, drag, bounce and so on). "Reset to Pat Kerr defaults" restores the reference
  numbers.

## Architecture

Everything talks through the **`Game` autoload** (`scripts/autoload/game.gd`). It holds the shared constants
(1 m = 10 px, collision layers, the z-index plan), the event-bus signals (`impact`, `scrape`, `hull_changed`,
`ship_destroyed`, race and docking events), shared references (`Game.player`, `Game.camera`, `Game.level`),
the runtime input map and the test harness. The build contract is in `docs/CONTRACT.md`, and cross-team notes
are in `docs/requests/*.md`.

**Main scene** (`scenes/main.tscn`, `scripts/main.gd`) instances the background, the level, the ship, the
camera rig, the gameplay systems, the HUD and the tuning panel. It places the ship at `PlayerSpawn`, or at
`--spawn`, by taking it out of the tree and adding it back. Setting `global_transform` on a live
continuous-collision body would sweep it through the station.

**Ship** (`scripts/ship/`). `PlayerShip` is a `RigidBody2D`: 1000 kg, 8.37 m² inertia per kg, 5000 N main
thrust and 2600 N side thrust at the bow point, with drag applied as explicit forces in `_integrate_forces`.
Every physics step it compares its contact list with the one before. It works out the true closing speed,
including its own spin, the surface speed of the rotating ring and each container's velocity from before the
hit. It emits `Game.impact` and `Game.scrape` one tick later, outside the physics callback.
`ship_visuals.gd` and `ship_particles.gd` draw the plumes, the boost shock diamonds, the gas jets from the
correct nozzle, trails, nav lights, damage smoke and sparks. All the particles come from one pooled renderer,
so gas can inherit the ship's velocity. `ship_audio.gd` drives the engine, boost, RCS hiss and puffs, and the
alarm from the thruster outputs. `camera_rig.gd` gives a speed zoom, a critically damped look-ahead, noise
shake and a directional punch. The hull art and the camera use `render_transform()`, which interpolates between the last two physics
steps, so the view scrolls smoothly whatever the frame rate. The ship's own bounce is 0.05: Godot adds the two
materials' bounce together, so against structure (0.3) and containers (0.32) a crash still rebounds at about
0.35. `ship_debug_draw.gd` is the F3 overlay, and `scripts/ui/tuning_panel.gd` is the
Tab panel.

**Level** (`scripts/level/`). Each station piece is a `@tool` `StationModule` subclass. Its `_build()`
describes the piece once with calls such as `hull()`, `deck()`, `truss()`, `windows()`, `beacon()` and
`lamp()`. Those calls produce both the convex collision polygons and a recorded draw list, sorted into depth
bands: BELOW-DECK, which the ship flies over; STRUCTURE, which collides and has bright rims; and OVERHEAD,
which the ship flies under and which is translucent and casts a shadow. Flat fills and antialiased lines are
baked into one triangle array per band, so the whole station costs a few hundred draw calls. Below-deck and
overhead bands get a slight parallax scale for a 2.5D feel, and one shader uniform animates every blinking
light. Moving structure (the ring, the crane boom, the blast doors) uses `AnimatableBody2D`. Containers are
`RigidBody2D` props, and traffic ships are kinematic bodies following lanes. `level.tscn` also holds
`PlayerSpawn`, the 15 `RaceCourse` gates and the docking pads.

**Environment** (`scripts/environment/`). `SpaceBackground` is a CanvasLayer at layer −10 that does its own
parallax from the camera's canvas transform. It has a sky shader with a baked nebula, procedural star layers, a
moon, and a planet with oceans, clouds, city lights on the night side and an atmosphere rim. Around the planet
are an orbital ring, space elevators and satellites. Further in are distant traffic, 15 distant station
silhouettes, and an additive sun-glare pass with lens ghosts.

**Gameplay systems** (`scripts/systems/`). `ImpactFX` turns `Game.impact` and `Game.scrape` into sparks,
flashes, debris, scorch decals, sound and camera feedback, in three tiers by closing speed. `DamageSystem`
applies hull damage as 0.41·(v−3)^1.5. It also handles destruction (`ShipExplosion`) and respawn (`WarpInFX`).
`RaceSystem` builds the gate visuals and does direction-checked gate crossing, splits and the saved best lap.
`DockingSystem` handles pad arming, settling and repair. `BoundarySystem` adds a soft push-back and a warning
at the edge of the world. `AmbientAudio` plays the music bed. `FlightGuide` shows a prograde marker and the
predicted path, computed from the ship's live tuning values.

**HUD** (`scenes/ui/hud.tscn`, `scripts/ui/`). It has a flight panel (speed, heading, drift, hull and boost
bars, assist state and a live thruster diagram), a race panel, a radar that expands into a map, a next-gate
pointer, centre messages, toasts, a damage vignette and the help overlay.

## How the assets were made

* **Sound:** all 38 WAVs in `assets/audio/` are synthesised by a pure-Python DSP script, with no external
  dependencies and fixed seeds, so the output is reproducible. Engines are tuned oscillators and filtered noise,
  impacts are inharmonic modal metal, and the music bed is a slow D-major pad. Loops are built to be seamless
  and carry WAV loop markers.
  ```
  python3 tools/audio/gen_audio.py        # rebuild everything (~40 s), or pass name prefixes
  python3 tools/audio/verify_audio.py     # levels, DC offset, clicks, loop seams
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
  ```
  `assets/audio/README.md` lists the bus and suggested volume for every file. The bus layout
  (`default_bus_layout.tres`) is Master with a limiter, plus SFX (with light reverb), Engine, Ambient and UI.
* **Ship art:** hand-written SVG (`assets/art/ship/ship_hull.svg`, plus `ship_damage.svg` as a scorch overlay
  that fades in as the hull drops), imported at 6× with mipmaps.
* **Station art:** procedural vector drawing from GDScript (`scripts/level/`), built once into cached canvas
  items. The look follows the palette in `docs/CONTRACT.md` §6: pearl hulls, navy and teal accents, warm
  windows, cyan tech lights and red/green nav lights.
* **Background:** GLSL-style Godot shaders in `assets/art/environment/shaders/`. The nebula and the planet
  surface are baked into textures once at startup, and everything else is drawn live.
* **Effects:** additive radial-gradient sprites, `CPUParticles2D`, and the race-gate beam shader in
  `assets/art/fx/`.

## Test harness and checks

Any scene accepts these user arguments after `--` (they are parsed by `Game`):

| Argument | Effect |
|---|---|
| `--spawn=x_px,y_px,heading_deg` | Start the ship here instead of on Pad 1 (1 m = 10 px) |
| `--input=0.3-4:thrust_forward;2-3:turn_right+boost` | Scripted input in physics-time seconds (the clock keeps running while paused, so `pause` spans work) |
| `--shots=1,2.5 --shot-dir=/abs/dir` | Save PNG screenshots at those times |
| `--quit-at=6` | Quit after that much physics time |
| `--log=0.5` | Print the ship's position, velocity, heading and spin every N seconds |
| `--debug-draw` | Start with the F3 overlay on |
| `--no-intro`, `--no-guide`, `--kill-at=T` | Skip the intro card, hide the flight guide, or destroy the ship at time T |
| `--cam-zoom=0.3`, `--cam-rotate`, `--tuning` | Set the camera zoom factor, use rotate mode, or open the tuning panel |

Example: take off from the pad with flight assist on and fly through the first two gates, with screenshots:
```
/Applications/Godot.app/Contents/MacOS/Godot --path . --fixed-fps 60 --resolution 1600x900 res://scenes/main.tscn -- \
  --no-intro --shots=7.4,17.3 --shot-dir=/tmp/shots --quit-at=17.5 \
  "--input=0.1-0.2:flight_assist;0.3-30:thrust_forward;2.0-3.15:turn_right;8.0-8.35:turn_right;6-12:boost"
```

Headless checks (each prints a PASS/OK result):
```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --fixed-fps 120 res://scenes/test/ship_physics_test.tscn     # flight model vs Pat Kerr numbers
$G --headless --path . --fixed-fps 120 res://scenes/test/level_validate.tscn        # level contract, lanes, prop impacts
$G --headless --path . --fixed-fps 120 res://scenes/test/gate_clearance_check.tscn  # every race gate clear of structure
$G --headless --path . --fixed-fps 120 res://scenes/test/gameplay_race_test.tscn    # race logic, splits, best lap saved
$G --headless --path . --quit-after 600 res://scenes/main.tscn                     # whole game: should print nothing
```

Visual test scenes:
* `scenes/test/level_tour.tscn`: a camera tour of the station. Use `--cam=x_m,y_m,zoom` for a fixed view
  (for example `--cam=0,0,0.085` shows the whole station), and `--show-gates` or `--fps` for overlays.
* `scenes/test/ship_sandbox.tscn`: the ship in a test arena with walls, crates and a rotating bar.
* `scenes/test/gameplay_sandbox.tscn`: the full game on a simple stand-in level.
* `scenes/environment/env_test.tscn`: the background on its own.
