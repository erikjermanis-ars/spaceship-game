# Meridian Approach

A small Godot 4.7 proof of concept: fly a light courier ship around **Meridian Station**, a big, busy orbital
station in a hopeful near-future setting (rotating habitat ring, commerce pier, drydock, cargo yard, solar
field, traffic lanes). It is a single sandbox level meant to show off **ship handling**, **level design**,
**art direction** and **sound design**. Dock on a pad and you can **get out and walk**: around the pad, and on
Pad 2 through an airlock into the pier's crew concourse (see [On foot](#on-foot)). In Hangar 2 a second ship
waits: the **PETREL**, a heavy cargo hover shuttle with a magnetic towline that can land on any station deck
(see [The PETREL](#the-petrel)). Everything (graphics, sound, shaders) is made from scratch in
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
| **W / ↑** | Main engine at the throttle setting (thrust is applied at the bow) |
| **S / ↓** | Retro thrust (a fixed 27.5 % of full thrust, whatever the throttle setting) |
| **A D / ← →** | Bow side thrusters: they turn the ship **and** push it sideways |
| **Q / E** | Strafe thrusters (pure sideways push, no rotation) |
| **Shift / Ctrl or Z** | Throttle up / down (hold). W fires the main engine at this setting; 100 % is full power |
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
| **X** | Docked and clamped: get out of the ship |

On foot:

| Key | Action |
|---|---|
| **W A S D / arrows** | Walk |
| **Shift** | Run |
| **E / Enter** | Use: doors, light switches, lamps, terminals, the vending machine, shutters, the hologram, board the ship |
| **F** | Helmet flashlight |
| **Mouse wheel / = / -** | Zoom |
| **H** | Controls help (shows the on-foot controls while walking) |

Flying the PETREL (the hangar shuttle):

| Key | Action |
|---|---|
| **W S Q E, Shift / Ctrl·Z, F** | Same as the WREN: main engines at the throttle setting, retro, strafe, throttle, flight assist |
| **A D / ← →** | Turn in place: the bow and stern thrusters push opposite ways |
| **Space (hold)** | Hover: brake to a stop with the heading held; W/S and Q/E slide, A/D yaw. Keep holding over any station deck to land |
| **Left mouse / V (hold)** | Mag-line: hook the highlighted cargo, structure or traffic; let go to release (fling) |
| **Right mouse / B (hold)** | Reel the line in |
| **L** | Floodlights |
| **X** | Get out (when landed). Any flight input lifts off |

Gamepads work too: left stick steers, the triggers are main engine and retro, D-pad up/down move the throttle
setting, Y is flight assist and the shoulder buttons strafe. In the PETREL, A hovers, B hooks, X reels and the
left-stick click switches the floodlights.

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
* **Get out and walk.** Dock on Pad 2 (the next pad north of the start pad, on the pier's west side) and
  press **X**. The camera zooms all the way down to the pad, the ship's hatch opens and its stairs unfold, and
  you step out in an EVA suit. Follow the painted walkway east to **Airlock 7B** on the pier wall and press
  **E**. Inside the crew concourse: switch lights on and off (the quarters start dark; try the flashlight),
  turn on the desk lamp, get a drink from the vending machine, open and close the lounge window shutters,
  switch the ops hologram, and read the crew and traffic logs. Leave through the airlock, walk back to the ship
  and press **E** at the stairs to board. Any other pad lets you walk around the pad itself.
* **Take the shuttle.** Dock the WREN on the Hangar Bay pad (inside Hangar 2 at the north end of the pier,
  behind the cycling blast doors) and press **X**. Take the stairs on the pad's east edge down to the hangar
  floor, walk to the teal PETREL in its painted bay and press **E** at its ramp. Lift off with any direction,
  fly out through the blast doors, then hold **Space** over any deck to land: the cargo yard apron, the drydock
  floor, the fuel depot, a pad, back in the hangar. Get out, walk around, and board whichever ship is parked
  nearby. Hook a container with the **left mouse button** and fling it, or hook a pier corner at speed and swing
  round it.
* **Watch the traffic.** Eleven AI shuttles, tugs and freighters follow lanes and do not avoid you.
* **Tune the physics live** (Tab, in either ship). Move any slider (thrust, thrust points, turn couple,
  inertia, drag, bounce and so on). "WREN default" and "PETREL default" load either ship's stock numbers into
  the ship you are flying, so you can also fly the WREN like a heavy shuttle or the other way round.

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

**Ship** (`scripts/ship/`). `PlayerShip` is a `RigidBody2D`: 1000 kg, 8.37 m² inertia per kg, 10.9 kN
main thrust at 100 % throttle (5.45 kN at the default 50 %, about the original 5 kN reference), 2600 N side
thrust at the bow point and 2080 N strafe at the centre of mass, with drag applied as explicit forces in `_integrate_forces`.
Every physics step it compares its contact list with the one before. It works out the true closing speed,
including its own spin, the surface speed of the rotating ring and each container's velocity from before the
hit. It emits `Game.impact` and `Game.scrape` one tick later, outside the physics callback.
`ship_visuals.gd` and `ship_particles.gd` draw the plumes (they grow with the throttle; shock diamonds fade in above 50 %), the gas jets from the
correct nozzle, trails, nav lights, damage smoke and sparks. All the particles come from one pooled renderer,
so gas can inherit the ship's velocity. `ship_audio.gd` drives the engine (rumble up to 50 % throttle, the high-power roar and its kick above), RCS hiss and puffs, and the
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

**HUD** (`scenes/ui/hud.tscn`, `scripts/ui/`). It has a flight panel (speed, heading, drift, hull bar and
throttle gauge, assist state and a live thruster diagram), a race panel, a radar that expands into a map, a next-gate
pointer, centre messages, toasts, a damage vignette and the help overlay.

## On foot

Getting out of the ship and walking around is a second layer on top of the flight game, run by
`OnFootDirector` (`scripts/onfoot/on_foot_director.gd`, node `Main/OnFoot`). Everything on foot uses the same
units as flight (1 m = 10 px), so the walker, the ship and the station share one physics world and one camera.

```
FLIGHT ──X (docked)──▶ EXTERIOR ──airlock──▶ INTERIOR
   ▲                     │  ▲                   │
   └──E at the stairs────┘  └─────airlock───────┘
```

**Why the outside is the same scene, zoomed in.** The station is already loaded and simulated, so getting out
is a camera move: `CameraRig.set_focus()` blends position, zoom (≈1 → 8.5) and rotation from the ship to the
walker in one continuous shot, with no loading and traffic still flying past. Systems that only make sense in
flight (race, damage, boundary, docking, flight guide, tuning panel, flight HUD) are paused. Only small on-foot
pieces are added, and they are freed when you take off:
* the **walker** (`walker.gd` + `walker_art.gd`), a `CharacterBody2D` with a procedurally animated top-down
  astronaut. The walk cycle is driven by distance travelled, so the feet never slide, and footsteps are
  triggered by the same cycle;
* the **landed ship** (`landed_ship.gd`), a much more detailed model (`assets/art/onfoot/ship_landed.svg`,
  imported at 12×) with an animated hatch, boarding stairs, nav lights and cooling engines. It is cross-faded
  with the flight sprite during the zoom. Swapping models by camera distance is the classic *level of detail*
  (LOD) technique;
* the **pad site** (`pad_site.gd`): safety railings, invisible walls at the deck edge and close-up deck detail
  for any pad, plus pad-specific extras listed in `PadSite.EXTRAS` (Pad 2: `scenes/onfoot/sites/pad2_site.tscn`
  with the airlock vestibule, walkway, crates, fuel cart and a detailed pier facade).

The station's fake-3D parallax (decks drawn slightly smaller, overhead parts slightly larger around the camera)
is flattened on foot (`LevelArt.depth_amount` → 0). You are standing *on* the deck, so it has to stay locked to
the colliders.

**Why the inside is a separate scene (level).** An interior is a different space with its own lighting, and
none of the station is visible from it. Keeping the whole station running behind it would waste time, so the
director *suspends* the flight world: `process_mode = DISABLED` stops its scripts and audio and removes its
physics bodies from the simulation, and it is hidden. Then the director adds the interior scene
(`scenes/onfoot/interiors/pier7_concourse.tscn`) behind a short fade. Leaving resumes the world exactly where
it was. The interior is placed where the pier really is, so the stars outside the lounge window line up. It is
**preloaded on a background thread** (`ResourceLoader.load_threaded_request`) while you walk to the airlock,
so the swap doesn't hitch. When you leave, it is freed and its state (lights, shutters, lamp, hologram, drinks
left, log position) is saved by the director and restored next time. Suspension is reference-counted, because
the flight layer and the interior both pause some of the same nodes.

**Building interiors.** Interiors are authored as nodes, so they can be edited in the Godot editor (all
`@tool`): `InteriorRoom` rectangles with a floor style, `SlidingDoor`s on shared edges, `InteriorWindow`s on wall
lines, `RoomLight`, `LightSwitch`, `InteriorProp` furniture (beds, desks, consoles, crates and more, all drawn in
code), and interactive pieces (`DeskLamp`, `VendingMachine`, `HoloTable`, `WindowShutter`, `InfoTerminal`,
`Airlock`). `InteriorLevel` builds the **walls automatically** from the room edges: it merges shared edges, cuts
gaps for doors and windows, makes the outer edges thick hull, and creates the collision, the light occluders
and the cached wall art. A new room is one node.

**Lighting.** Interiors use Godot's 2D lights. A `CanvasModulate` makes everything dark, and lights add
brightness back. Each `RoomLight` uses a box-shaped falloff texture stretched to its room, so it fills the room
and stops at the walls without shadow maps. Only the helmet flashlight and the desk lamp cast real shadows (walls,
doors and tall furniture have `LightOccluder2D`s). Screens, LEDs and the space outside the windows use an
*unshaded* material, so they glow in the dark.

**Interacting.** Anything you can press E on is an `Interactable` (group `interactable`). Each frame the director
picks the nearest usable one in reach, preferring what you face. A distance check is cheaper and simpler than an
`Area2D` per object for the handful in range at any time.

**Performance.** In the Compatibility renderer every antialiased line or circle drawn with `draw_*` becomes its
own draw call, and a detailed floor is thousands of them (the first version measured about 10 500 draw calls and
26 fps on foot). All on-foot art therefore goes through `OnFootPainter`, which collects shapes into one triangle
array per canvas item with a one-pixel transparent "feather" for antialiasing. The station's own art is batched
the same way. Measured on an M1 Pro at 1600×900 (`--perf`), every mode holds the 120 fps vsync cap: flight about
340–390 draw calls, on the pad about 155, in the interior about 145. Animated screens redraw at about 10 Hz
instead of every frame.

**Sound on foot** (same "you hear what your body carries" idea as the cockpit). Outside, in vacuum, footsteps are
muffled mag-boot thuds heard through the suit. Through the airlock the air comes back: the pressurisation roar
starts as a low rumble and opens up as the pressure rises, and then steps are crisp heel-and-toe on deck plate,
with room tone, door whooshes, switch clicks, flickering lights and console blips. The ship's engine bus fades out
while you're away and back when you board, and the music bed sits a little lower indoors.

## The PETREL

A second pilotable ship: a heavy cargo shuttle. It flies on the WREN's controls and flight model, with its
own numbers and a few tools of its own.

* **Same model, heavier numbers** (`scripts/ship/shuttle_ship.gd`, a `PlayerShip` subclass). 2.6 t against the
  WREN's 1 t, 12 kN of main thrust (about 4.6 m/s² at full throttle against 10.9), 46 m/s terminal at 100 %
  (23 m/s at the default 50 %), retro about 1.4 m/s², and a slow spin-up. The stock numbers live in `ShuttleShip.PETREL_DEFAULTS` (the WREN's in
  `PlayerShip.WREN_DEFAULTS`).
* **Turns in place.** Its turn thrusters fire as a couple (`turn_couple = 1`): the bow quads push one way and
  the stern quads the other, so A/D rotate the shuttle about its centre with no sideways shove. The WREN
  (`turn_couple = 0`) fires only at the bow, so its turns also swing it sideways.
* **Hover and land anywhere.** Holding Space brakes to a stop with the heading held (A/D yaw it slowly). Over a station deck the
  shuttle then descends (fake altitude 3 m → 0) onto magnetic skids and freezes in place. `LandingProbe`
  checks a deck is under every skid, nothing is in the way, and you are slow and not spinning. A footprint ghost
  on the deck shows the result before you try (green, amber for an edge, red if obstructed), and the touchdown
  is graded SILK / FIRM / SKID, or BULLSEYE on a pad centre (pads also repair you). "Decks" are the station's
  floor polygons, which every station module registers (`StationModule.deck()` → `LevelArt.walk_decks`; the
  spinning ring is excluded). When you get out, the walk area is built from those same decks.
* **Mag-line** (`scripts/ship/mag_line.gd`). A tension-only rope: tension = stiffness × stretch +
  damping × stretch rate. A free container is pulled toward you with an equal and opposite force (towing, and
  flinging when you let go). Fixed or moving structure only pulls you: hook a corner at speed and you swing
  round it. A slip clutch pays out line above 45 kN (up to 40 m), and the line snaps if overloaded at full
  length. The winch reels in at 4 m/s and stalls under load.
* **Two ships, one game.** Systems follow `Game.player`; boarding emits `Game.player_changed`. Damage, docking,
  race (best laps are stored per ship), camera, flight guide and tuning panel react to it. A ship nobody is in is
  *parked*: frozen on the static world layer (so the other ship and the walker bump into it), silent, and shown
  with its detailed landed model. `PlayerShip` has a small vehicle API the on-foot director uses for any ship:
  `park()`, `take_control()`, `on_boarded()`, `can_disembark()`, `landed_model()`, `ship_id()`,
  `uses_pad_clamps()`, `home_transform()`, `damage_scale()`. The PETREL adds hover and the mag-line pull on
  top of the shared `_apply_flight_forces()`. Keys pressed when you board are latched until released, so the E or Shift you were
  holding on foot doesn't fire the ship's controls.
* **Hangar 2 on foot** (`scenes/onfoot/sites/hangar_site.tscn`). The Hangar Bay pad is a raised platform. A gap
  in its railing leads to stairs down to the hangar floor, which is walkable up to a safety barrier at the blast
  doors. The site applies wherever you get out inside the hangar (`WalkSite.PAD_EXTRAS` `covers`), so the stairs
  connect whichever ships are parked there.
* **Art and sound.** The flight sprite (`assets/art/ship/shuttle_hull.svg`) and the landed close-up with skids,
  door and ramp (`assets/art/onfoot/shuttle_landed.svg`) are new SVGs. There are 20 new synthesized sounds: twin
  engines, a high-power layer (used above 50 % throttle), a valve whine (kept, currently unused), hover hum, skid
  deploy, mag clamps, the landing chime and abort warble, lift-off, and the line's fire, latch, creak, clutch
  scream, winch, snap and release. The PETREL's RCS (the A/D turn couple, Q/E strafe, S retro and hover
  station-keeping) uses the WREN's hiss loop and valve puffs, and S also adds a low rumble to the engine bed.
  `tests/ship_audio_test.gd` (run windowed) checks which sound every flight key makes on both ships.

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
  that fades in as the hull drops), imported at 6× with mipmaps. The landed close-up model is
  `assets/art/onfoot/ship_landed.svg`, imported at 12×.
* **On-foot art:** the character, interiors, furniture and pad details are vector-drawn in GDScript through
  `OnFootPainter` (batched triangles). Light falloff textures are generated at runtime (`OnFootArt`).
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
| `--input=0.3-4:thrust_forward;2-3:turn_right+throttle_up` | Scripted input in physics-time seconds (the clock keeps running while paused, so `pause` spans work) |
| `--shots=1,2.5 --shot-dir=/abs/dir` | Save PNG screenshots at those times |
| `--quit-at=6` | Quit after that much physics time |
| `--log=0.5` | Print the ship's position, velocity, heading and spin every N seconds |
| `--debug-draw` | Start with the F3 overlay on |
| `--no-intro`, `--no-guide`, `--kill-at=T` | Skip the intro card, hide the flight guide, or destroy the ship at time T |
| `--cam-zoom=0.3`, `--cam-rotate`, `--tuning` | Set the camera zoom factor, use rotate mode, or open the tuning panel |
| `--dock-at=2` | Put the ship on that pad and dock it straight away (add `--on-foot` to also get out) |
| `--perf` | Print fps, frame time and draw calls every 2 s |
| `--dock-at=HangarBay` | Any pad by name (spaces optional) |
| `--fly=petrel` or `--fly=petrel@x_px,y_px,deg` | Start aboard the PETREL (on its berth, or flying at that spot); the WREN is parked |

Example: dock at Pad 2, get out, run to the airlock and go inside (on-foot actions are `move_up/down/left/right`,
`run`, `interact`, `flashlight`):
```
/Applications/Godot.app/Contents/MacOS/Godot --path . --fixed-fps 60 --resolution 1600x900 res://scenes/main.tscn -- \
  --no-intro --dock-at=2 --on-foot --shots=12,18 --shot-dir=/tmp/shots --quit-at=18.2 \
  "--input=6.0-7.75:move_down+run;7.9-13.4:move_right+run;13.6-13.7:interact"
```

Example: take off from the pad with flight assist on and fly through the first two gates, with screenshots:
```
/Applications/Godot.app/Contents/MacOS/Godot --path . --fixed-fps 60 --resolution 1600x900 res://scenes/main.tscn -- \
  --no-intro --shots=7.4,17.3 --shot-dir=/tmp/shots --quit-at=17.5 \
  "--input=0.1-0.2:flight_assist;0.3-30:thrust_forward;2.0-3.15:turn_right;8.0-8.35:turn_right;6-7:throttle_up"
```

Headless checks (each prints a PASS/OK result):
```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --fixed-fps 120 res://scenes/test/ship_physics_test.tscn     # WREN flight model, throttle, turn and assist
$G --headless --path . --fixed-fps 120 res://scenes/test/level_validate.tscn        # level contract, lanes, prop impacts
$G --headless --path . --fixed-fps 120 res://scenes/test/gate_clearance_check.tscn  # every race gate clear of structure
$G --headless --path . --fixed-fps 120 res://scenes/test/gameplay_race_test.tscn    # race logic, splits, best lap saved
$G --headless --path . --fixed-fps 120 res://scenes/test/onfoot_flow_test.tscn      # disembark, airlock, interior, state, board
$G --headless --path . --fixed-fps 120 res://scenes/test/vehicles_flow_test.tscn    # hangar stairs, board PETREL, land anywhere, swap ships
$G --headless --path . --fixed-fps 120 res://scenes/test/shuttle_flight_test.tscn   # PETREL turn-in-place, terminal speed, hover, mag-line tow
$G --path . --fixed-fps 120 res://scenes/test/ship_audio_test.tscn                 # windowed (needs audio): which sound each flight key makes, both ships
$G --headless --path . --quit-after 600 res://scenes/main.tscn                     # whole game: should print nothing
```

Visual test scenes:
* `scenes/test/level_tour.tscn`: a camera tour of the station. Use `--cam=x_m,y_m,zoom` for a fixed view
  (for example `--cam=0,0,0.085` shows the whole station), and `--show-gates` or `--fps` for overlays.
* `scenes/test/ship_sandbox.tscn`: the ship in a test arena with walls, crates and a rotating bar.
* `scenes/test/gameplay_sandbox.tscn`: the full game on a simple stand-in level.
* `scenes/environment/env_test.tscn`: the background on its own.
