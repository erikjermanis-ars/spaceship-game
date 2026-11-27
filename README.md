# Meridian Approach

A small Godot 4.7 proof of concept of a space-travel game: fly ships around **Meridian Station**, a big, busy
orbital station in a hopeful near-future setting (rotating habitat ring, commerce pier, drydock, cargo yard,
solar field, traffic lanes), get out and walk its interiors, and take a frigate at light speed to a second
station. It is a sandbox meant to show off **ship handling**, **level design**, **art direction** and **sound
design**, and what a few connected systems add up to:

* The **WREN**, a light courier with twin pulse cannons (see [Weapons](#weapons-and-the-gunnery-range)).
* The **PETREL**, a heavy cargo hover shuttle that lands on any deck, tows with a magnetic line and takes ten
  containers into its hold (see [The PETREL](#the-petrel)).
* Two frigates, the **KESTREL** and the **HALCYON**: 150 m ships you walk aboard, fly from the bridge, land the
  small ships on, and jump between stations with (see [The frigates](#the-frigates)).
* **On foot**: pads, airlocks, the pier's concourses, a transit line between four stops, the frigates' decks and
  the outpost's hab (see [On foot](#on-foot)).
* **Vesper Rock**, a mining outpost in an asteroid belt, reachable only by a frigate's quantum drive (see
  [Vesper Rock](#vesper-rock)).
* **Contracts** that tie it together: haul freight, shoot drones, break rocks, bring ore home (see
  [Contracts](#contracts)).

Everything (graphics, sound, shaders) is made from scratch in GDScript, SVG, shader code and a small Python
synthesiser. There are no add-ons and no imported asset packs.

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
| **Space / left mouse (hold)** | Pulse cannons (WREN only). They build heat and lock out at 100 %: watch the HEAT gauge |
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
| **Right mouse / B (hold)** | Reel the line in. A container reeled alongside goes into the hold |
| **U (hold to repeat)** | Unload one container out of the stern (in flight, with clear space behind) |
| **L** | Floodlights |
| **X** | Get out (when landed). Any flight input lifts off |

Flying a frigate (the KESTREL or the HALCYON):

| Key | Action |
|---|---|
| **W S A D Q E, Shift / Ctrl·Z, F** | As the WREN: impulse and drive rings at the throttle setting, retro, turn, strafe, throttle, flight assist (ON by default) |
| **A D / ← →** | Turn in place: the bow and engineering RCS fire as a couple |
| **Space (hold)** | All stop: every thruster brakes the drift and the spin |
| **any flight key (hold, docked)** | Undock: the gangway retracts, the clamps open and push the ship off |
| **N** | Star map: A/D or the mouse picks a destination, E lays in the course, C clears it |
| **J (hold)** | Quantum drive: spool for 3.2 s, then jump (undocked, a ship's length clear of structure) |
| **X** | Leave the bridge (clamped in a berth, or at all stop) |

Gamepads work too: left stick steers, the triggers are main engine and retro, D-pad up/down move the throttle
setting, Y is flight assist and the shoulder buttons strafe. In the WREN, A fires the cannons. In the PETREL, A
hovers, B hooks, X reels, the left-stick click switches the floodlights and the right-stick click unloads cargo.

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
* **Haul freight.** In the PETREL, hook a container in Cargo Yard C and hold the **right mouse button** to reel
  it in: the hold swallows it (ten slots, shown on the HUD and as lamps across the stern). Fly the load round
  the ring to the **Yards Supply Intake**, the striped pad south of the drydock under the MERIDIAN YARDS sign
  (the HUD shows its bearing and distance while you carry cargo). Hover over the pad and hold **U**: the
  containers slide out of the stern and the intake takes them one by one.
* **Take a frigate.** Get out on Pad 2, go in through Airlock 7B and walk south through the concourse to the
  Berth E2 lounge. With the KESTREL clamped in, the gangway door opens: ride the moving walkway out to the ship,
  press **E** at the hatch, take the lift (or walk the main corridor) to the bridge and press **E** at the
  captain's chair. Hold any flight key to undock. To come back, fly the ship's centre into the capture box of any
  free berth (the guidance shows the box, your heading error and closing speed), parallel to the pier, under
  1.2 m/s: the clamp arms reach out, close on the hardpoints and draw the ship onto its mark, then the gangway
  runs out to the airlock. Hit something to see the deflector shield ripple; keep hitting things to lose it,
  breach the hull and watch a hurt drive ring drag the ship off line. Press **X** at all stop to walk the ship in
  deep space. The **HALCYON** in Berth E1 is the same class: ride the transit pod to Pier 7 North for its gangway.
* **Land on the flight deck.** Fly the WREN in through the open stern of a berthed frigate (dead astern, slowly)
  and settle on pad A or B like on any station pad; or hold Space over the deck in the PETREL. Press **X**: you
  step out into the frigate's hangar, next to your ship. Whatever is parked on the deck when someone takes the
  helm rides with the frigate.
* **Jump to Vesper Rock.** At the KESTREL's helm (or at the nav table on its bridge) open the star map with
  **N**, pick VESPER ROCK and press **E**. Undock, back away from the pier until the drive strip says DRIVE
  READY, and hold **J**: the rings spool, the stars stretch, and five seconds later you drop out beside a ringed
  gas giant with the outpost's berth dead ahead. Dock at Berth V1 and cross the gangway into the hab, or take
  the lift aft to the hangar and fly the WREN you brought into the asteroid belt.
* **Work the contracts** (the panel top right). Carry containers from Cargo Yard C to the Yards intake; burst
  drones at the gunnery range; take a hold full of containers to Vesper's supply drop; break up belt rocks and
  bring the ore canisters they leave home to Meridian.
* **Watch the traffic.** Eleven AI shuttles, tugs and freighters follow lanes and do not avoid you.
* **Tune the physics live** (Tab, in either ship). Move any slider (thrust, thrust points, turn couple,
  inertia, drag, bounce and so on). "WREN default" and "PETREL default" load either ship's stock numbers into
  the ship you are flying, so you can also fly the WREN like a heavy shuttle or the other way round.

## Architecture

Everything talks through the **`Game` autoload** (`scripts/autoload/game.gd`). It holds the shared constants
(1 m = 10 px, collision layers, the z-index plan), the event-bus signals (`impact`, `scrape`, `hull_changed`,
`ship_destroyed`, race and docking events), shared references (`Game.player`, `Game.camera`, `Game.level`),
the runtime input map and the test harness. The build contract is in `docs/CONTRACT.md`, notes on how each
subsystem behaves are in `docs/requests/*.md`, and `AGENTS.md` is a short guide for coding agents.

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

The backdrop has two *looks*, one per place, and `SpaceBackground.set_look(id, world_origin)` swaps them in one
frame (`look()` returns the current id; the node is in group `space_background`). Parallax is computed from
`camera - world_origin`, so each look frames its own station. `&"meridian"` is the sky above, around (0, 0).
`&"vesper"` is VESPER ROCK, around (90000, 0): a ringed gas giant with storms (`GasGiant`, globe and rings in one
shader quad so each shadows the other), a smaller and whiter sun in the lower-left, an icy and a dark moon, a
warm dust nebula with a denser star band, and three parallax depths of drifting asteroid-belt rocks with a dust
band (`AsteroidBelt`, one mesh per depth) in place of stations and traffic. A look is a `SkyLook`: its parallax
layers under one root node plus uniform overrides for the shared sky and sun passes. The Vesper look
(`VesperSky`) is built and baked about 1.5 s after startup, a step per frame, and drawn hidden under the sky for
three frames so its shaders are compiled before the first jump.

**Light-speed effect** (`scripts/environment/warp_fx.gd`, shaders `assets/art/fx/warp_*`). `WarpFX` is a
CanvasLayer at layer 5 (above the world, below the HUD) that the jump sequence drives every frame through plain
properties: `charge` (motes spiral in and the picture is pinched towards the ship), `streak` (the stars on screen
smear into radial streaks, with a shock ring), `flash`, `tunnel` (an opaque log-polar tunnel of layered streaks,
filaments and a breathing vanishing point ahead of the ship), `progress` and `direction` (the tunnel's colour
drifts between Meridian's cool blue and Vesper's amber) and `heading`. `set_ship_snapshot()` draws a texture of
the ship over the tunnel inside a warp bubble with a bow shock. With every property at zero its rects are hidden.

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
FLIGHT ──X (docked)──▶ EXTERIOR ──airlock──▶ INTERIOR ◀──gangway──▶ INTERIOR (KESTREL)
   ▲                     │  ▲                   │                          │    ▲
   └──E at the stairs────┘  └─────airlock───────┘    FLIGHT (KESTREL) ◀──chair   X┘
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
* the **walk site** (`walk_site.gd`): safety railings, invisible walls at the deck edge and close-up deck detail
  for any pad or deck, plus pad-specific extras listed in `WalkSite.PAD_EXTRAS` (Pad 2:
  `scenes/onfoot/sites/pad2_site.tscn` with the airlock vestibule, walkway, crates, fuel cart and a detailed
  pier facade).

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
* **Cargo hold and freight** (`scripts/ship/cargo_hold.gd`, `cargo_handler.gd`,
  `scripts/level/modules/freight_receiver.gd`). The hold has 10 slots: a 6 m container takes one, a 12 m one
  two. **Stow:** hook a container and reel. When it is within 1.5 m of the hull and closing slower than 5 m/s, the
  stern hatch takes it (towing without reeling never stows). The container is taken out of the scene tree and
  kept, so the same node, livery and serial comes back out. A full hold refuses, once per attempt. **Unload:** U
  pushes the last one stowed out of the stern at 1.5 m/s (the ship gets the opposite nudge); holding U repeats
  every 0.4 s once the space behind is clear. Only in flight (cruise or hover). **Weight:** each used slot adds
  160 kg, so a full hold makes the 2.6 t shuttle 4.2 t: slower to accelerate, turn and stop, and slower flat out.
  `mass_kg` carries the cargo; the dry mass is kept apart, so tuning presets and respawns can't lose it.
  **Losing the ship** spills the hold around the wreck with the ship's momentum. Parking, landing and getting
  out keep it. The HUD shows `HOLD n/10` over ten slot boxes in the liveries aboard, the added weight and the way
  to the nearest intake; ten lamps across the stern show the same count on the hull. A `FreightReceiver` is a
  below-deck set-down pad with an intake hatch: any container resting inside its striped border (under 1 m/s for
  0.6 s; a soft mag-brake slows cargo there) is drawn into the hatch and freed, whether you unloaded it there or
  shoved it in with the hull. It can be limited to some brands (`accepts`). Each delivery emits
  `Game.cargo_delivered(brand, receiver_id, slots)` and is tallied in `FreightLedger`. Meridian has one, the
  **Yards Supply Intake** (`receiver_id` `yards`) at (0, −420) m, 100 m south of the drydock, with a conveyor
  trunk running under the Yards traffic lane to the dock. The containers start in Cargo Yard C on the far side
  of the ring.
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

## The frigates

Two KESTREL-class civil exploration frigates: the **KESTREL** (teal, home Berth E2) and the **HALCYON** (coral,
home Berth E1). Where the WREN and the PETREL are boarded from the deck, a frigate is a place: you walk aboard,
fly it from its bridge, park the small ships on its flight deck and jump it to another station.

* **The hull** is generated (`tools/art/frigate_svg.py`): a 152 m arrowhead hull with the bridge near the bow and
  rows of warm windows along the rim, a waist, and a hangar block whose stern is an open **flight deck** recessed
  between two engine arms. Either side hangs a **drive ring** on two pylons: a closed hoop 60 m long with an
  emitter channel that lights up with the throttle and blazes when the quantum drive spools (the WREN can thread
  a ring). The script writes three art layers (painted hull, livery tinted per ship, window lights) and
  `scripts/ship/frigate_shape.gd`: 43 convex collision parts, the outlines, hardpoints, airlock, bay rectangle and
  pad positions. Art, physics, docking, the HUD schematic and the deck plan all read that one file.
* **Flight** (`scripts/ship/frigate_ship.gd`, a `PlayerShip` subclass). 120 t, 360 kN of main thrust (3 m/s² at
  full throttle, 50 m/s terminal at 100 %), a slow turn couple (bow RCS one way, Engineering's the other, about
  14°/s at most), flight assist on by default, and **Space = all stop**. The main thrust comes from three engines
  at their real positions: the impulse deck in the stern (40 %) and the two drive rings (30 % each). The stock
  numbers are `FrigateShip.FRIGATE_DEFAULTS` ("KESTREL default" in the tuning panel, whose slider ranges stretch
  to fit). The camera sits further out for it (`camera_zoom_scale()`).
* **Docking** (`frigate_dock.gd`, `scripts/level/modules/frigate_berth.gd`). A berth has two heavy clamp pylons
  sized to the ship's hardpoints (the forward one on the hull's rim, the aft one on the outer face of a drive
  ring) and a third, lighter pylon: the telescoping personnel gangway. A frigate can put in at **any free berth**
  (E1 and E2 at Meridian, V1 at Vesper Rock), either side to the pier: adrift, its guidance aims at the nearest
  free one. Fly the ship's centre into a small capture box (5 m fore/aft, 2.5 m toward the pier, 5 m away), within
  4° of the berth heading, under 1.2 m/s and not turning, and hold it for 1 s. Then **soft capture**: the clamp
  rams run out and their jaws close while a critically damped spring draws the ship onto its mark. **Hard dock**
  freezes it, the gangway telescopes out to the airlock and the berth repairs the ship. Holding any flight key
  undocks (gangway in, clamps open, a gentle push off the pier). Each berth names the station interior behind its
  gangway (`gangway_scene`, `gangway_arrival`), so a frigate's airlock opens onto whatever station it is docked at.
* **The flight deck** (`frigate_bay.gd`, `frigate_bay_pad.gd`). The bay is 29 m wide and 29 m deep, open to space
  astern behind an atmosphere field. Its two pads are ordinary docking triggers (`KESTREL Bay A`, `Bay B`), so
  the WREN docks on them like on a station pad, and the deck is published as a landable deck that follows the
  ship, so the PETREL sets down on it with Space. **X** in a ship parked there takes you into the frigate's
  interior, standing by your ship in the hangar (`OnFootDirector._disembark_to_hangar`); **E** at its hatch flies
  it again (`board_stowed`). When someone takes the helm, every ship parked on the deck is **stowed**: it is held
  at its place on the deck each physics tick, the hull doesn't collide with it, and it is drawn at the frigate's
  interpolated transform so the two never slide against each other. Frigates draw one z-step under the small
  ships (`Game.Z_CAPITAL`).
* **The quantum drive** (`scripts/systems/jump_system.gd`, `scripts/ui/star_map.gd`, `scripts/systems/sectors.gd`).
  Every station lives in the same world scene, kilometres apart (Meridian at the origin, Vesper Rock at
  (9000, 0) m); `Sectors` lists them with their bounds, arrival points and star-map positions. `JumpSystem`
  watches where the player's ship is and keeps `Game.sector`, `Game.world_bounds` and the sky in step, whatever
  moved the ship. The **star map** (N at the helm, or the nav table on the bridge) lays in a course; charted
  places without a jump beacon are shown but can't be picked. The **jump**: hold J for 3.2 s to spool (needs an
  undocked ship and 40 m of clear space beyond the hull; letting go aborts), then the drive takes the helm
  (`FrigateShip.jump_ctl`), the stars stretch, a flash hides the cut, 4.6 s in the tunnel while the ship and
  everything on its flight deck are moved to the destination's arrival point, a second flash, and the ship drops
  out at 60 m/s and brakes to a crawl in about 40 m. The look of each stage is `WarpFX`'s (see Environment); the
  drive strip at the bottom of the HUD shows the course, why the drive won't spool, the spool bar and the route.
  Small ships can't jump: the boundary keeps them in the sector they are in, and a ship lost away from home is
  recovered to the nearest pad of the station it is at.
* **Damage model** (`frigate_damage.gd`). A **deflector shield** takes hits first (1.5 shield points per hull point,
  10 % bleeds through), shows a hex ripple where it was hit (`assets/art/fx/frigate_shield.gdshader`) and regenerates
  after 2.5 s of quiet, powered by Engineering. What gets through lands on one of **six sections** (bow, port and
  starboard hull, Engineering, two drive rings) by where you were hit; the HUD hull number is their weighted
  average. Sections matter: a hurt ring loses thrust (so full throttle pulls to that side), sputters below 40 %
  and goes dark when wrecked; the bow and Engineering carry the turn couple; the hull sides carry the strafe
  quads; a weak Engineering means a weak shield. Hard hits leave **breaches** (scorched holes with glowing edges)
  that **vent atmosphere** while their section is badly hurt, and the gas pushes the ship. **Red alert** (shields
  down, a section under 35 % or a failing core) turns the window lights red. Engineering at zero is a **core
  breach**: an 8 s countdown, then the ship is lost, and it comes back clamped in its home berth. Inside, red alert
  lights the deck red, hurt sections have failing lights and sparking conduits, the reactor stutters, and the
  systems table in Engineering shows every section live.
* **The deck** (`scenes/onfoot/interiors/frigate_deck.tscn`, `scripts/onfoot/frigate/frigate_deck.gd`). One scene
  serves both ships (`FrigateShip.aboard` says which one you are on; their saved states are kept apart). The 19
  rooms sit at their **true positions inside the hull**, 1 m = 1 m, bow up, so the deck plan follows the ship's
  shape: a ready room in the prow, the bridge behind it, the observation lounge and science lab, mess and crew
  quarters where the hull is widest, sickbay and an arboretum, a port and a starboard airlock (the gangway hatch
  works on whichever side faces the pier), Engineering with the reactor core at the waist (its windows look out
  at the drive rings), stores and the quantum drive room in the flare, flight control and the pilots' ready room
  over the hangar door, and the flight deck itself, with the pad markings, the atmosphere field across its mouth
  and every parked ship as its detailed landed model. The hull's outline and both rings are drawn under the rooms
  as a cut-away, notched where a window looks out. A **lift** runs along the keel between the bridge and the
  hangar (`ShipLift`, `OnFootDirector.ride_lift`). The bridge has helm and ops stations, a command ring, a split
  tactical rail, wall stations, a floor-projected tactical hologram and the **nav table** (the star map).
  **E at the captain's chair** (`take_helm`) cuts to the ship outside with you at the helm; **X** (`leave_helm`)
  puts you back on the bridge.
* **Art and sound.** `frigate_visuals.gd` adds the live glows (impulse exhausts, the light that runs round the
  drive rings, the nose deflector, the flight deck's field), RCS, nav lights, breaches, venting and the shield.
  Sounds (see `assets/audio/README.md`): drive hum and impulse throb, deep RCS thuds, clamp engage and release,
  gangway extend and retract, shield hit/down/up, hull breach, venting, red alert, core breach, hull groan,
  corridor door swish, bridge ambience, helm engage, the synthesizer and the walkway, and for the drive: spool,
  engage, the tunnel loop, arrival, abort, and the star map's cues.

## Contracts

Five standing contracts give the sandbox something to do (`scripts/systems/contracts.gd`, node
`Main/Systems/Contracts`; the HUD panel is `scripts/ui/hud_contracts.gd`). Each one only counts things other
systems already announce on the `Game` bus, so nothing else knows contracts exist:

| Contract | What counts | Where |
|---|---|---|
| YARDS SUPPLY | a container delivered to the Yards Supply Intake (`cargo_delivered(brand, "yards")`) | Meridian |
| GUNNERY QUAL | a target drone burst (`target_destroyed("drone")`) | Meridian |
| VESPER RESUPPLY | a container delivered to Vesper's supply drop (`cargo_delivered(brand, "vesper")`) | Vesper Rock |
| BELT CLEARANCE | a belt rock destroyed (`target_destroyed("asteroid")`) | Vesper Rock |
| ORE RUN | an ORE canister delivered to the Yards intake | both: mined at Vesper, delivered at Meridian |

Filling a target pays credits and raises the next target (x1.5, with a bigger reward). Credits are a score for
the session; there is nothing to spend them on in this demo. The ORE RUN is the long loop that uses everything:
land the WREN and the PETREL on a frigate's flight deck, jump to Vesper, crack ore-bearing rocks with the WREN's
cannons, collect the canisters into the PETREL's hold, jump home and unload at the Yards intake. Vesper's supply
drop turns ore away (`FreightReceiver.rejects`): the outpost ships it out.

## Weapons and the gunnery range

The WREN carries twin pulse cannons, and Meridian has a gunnery range to try them on: fly south-west of the ring
to the amber "GUNNERY RANGE" sign at (−450, 425) m and hold **Space**.

* **Guns** (`scripts/ship/wren_guns.gd`, node `Guns` in `player_ship.tscn`; the PETREL and the KESTREL have their
  own scenes and no guns). Two fixed cannons at the wing roots fire alternately, 6 shots a second, toed in so the
  two lines cross 90 m ahead. There is no recoil on the ship, only a small camera kick. **Heat:** each shot adds
  4.5 %, so 23 shots (3.7 s of holding the trigger) lock the guns out. They cool at 28 % a second once they have
  been quiet for 0.25 s, and a lockout ends when the heat is back under 30 % (2.5 s). You see it as barrel glow,
  vent steam and the HEAT gauge in the flight panel (amber when hot, flashing red OVERHEAT). The guns are dead
  while the controls are off, the ship is destroyed or parked, or you are on foot, and a trigger held while you
  board stays latched until you let go (`PlayerShip.pilot_action()`).
* **Bolts** (`scripts/systems/weapon_system.gd`, node `Main/Systems/Weapons`, group `weapon_system`). Anything can
  shoot with `fire(origin, dir, inherit_velocity, shooter)`. A bolt flies at 260 m/s plus the shooter's velocity
  for 500 m, then fades. Bolts are data in a fixed pool of 64, not nodes. Each physics tick a bolt casts a ray
  from where it was to where it will be (station, props and traffic; never the shooter), so it cannot tunnel
  through a thin wall. All of them are drawn by two `MultiMesh` layers, so a full spray costs two draw calls.
  Additive light vanishes over the pearl station, so the bolt's body is a normal-blended dart (white core, orange
  flank, dark red rim) and only its halo is additive.
* **What a hit does.** Always sparks, a flash, a scorch mark with a cooling ember and a positional sound
  (`weapon_hit_fx.gd`, pooled). Then: a collider with `take_shot(damage, at, dir, shooter)` gets that call (10
  damage a bolt) and decides for itself; a free prop is shoved along the bolt (400 N·s: a 1.8 t container gains
  0.22 m/s per hit); another ship takes a 1.5 hp scratch (a parked one never drops below half hull this way);
  structure and traffic only show the effects. Every hit
  also emits `Game.shot_hit(pos, normal, collider, shooter)`.
* **Aim line** (`gun_aim_line.gd`). Shown only while firing and for a moment after. Bolts keep the ship's
  velocity, so when you drift they do not go where the nose points: the line follows the track a bolt fired now
  will take through the world. Its reticle sits on whatever the line touches and turns amber on a target.
* **The range** (`scripts/level/modules/gunnery_range.gd`). A 150 × 104 m octagon of open space marked by a dashed
  holographic boundary and eight amber buoys, with eight **target drones** (`scripts/level/target_drone.gd`, groups
  `target_drone` and `radar_prop`). A drone is a light free body that holds station on an under-damped spring and
  drifts along a gentle pattern (side to side, a circle or a figure of eight). The first hit staggers it and turns
  its ring red, the second bursts it (`Game.target_destroyed("drone")`), and it shimmers back after 6 s. You can
  bump them; they spring back. A scoreboard projected on the range floor (`range_scoreboard.gd`) shows hits,
  kills, the current streak (drones destroyed with no more than 5 s between kills) and the best streak of the
  session.
* **Art and sound.** The gun pods (`assets/art/ship/wren_guns.svg`, an overlay on the hull) and the drone
  (`assets/art/level/target_drone.svg` and `target_drone_hit.svg`) are hand-written SVGs imported at 6×; bolt and
  muzzle textures are generated in `weapon_textures.gd`. Sounds are loaded if the files exist and skipped quietly
  if not: `pulse_shot_1..3.wav` (your own guns, not positional), `pulse_hit_1..3.wav` (positional),
  `gun_overheat.wav`, `gun_ready.wav`, `drone_pop.wav` (positional), all on the SFX bus.
## Vesper Rock

A second, remote station in the same world: a mining and survey outpost bolted onto an asteroid, in an asteroid
field. It is the `Outpost` node of `level.tscn` (an instance of `scenes/level/outpost.tscn`) at world
(90000, 0) px, 9 km east of Meridian, with a sector of ±800 m × ±650 m around that origin. Small ships cannot
fly there; it is where the frigate's jump comes out. The sky, the sector switch and the interiors belong to other
systems; this is the exterior.

* **The rock** (`modules/rock_base.gd`, `rock_art.gd`). About 320 m × 245 m, a seeded low-poly mesh: the outline
  plus a jittered grid of interior points are Delaunay-triangulated, and every triangle is one flat facet shaded
  from a height field that rises from the edge to a plateau. So the sunward rim is bright, the far rim dark and
  the top reads as level ground, with strata bands, bedding lines, craters, loose boulders and an open-cut pit.
  The whole outline collides (convex pieces) and has the lit rim of colliding structure. It is one triangle array
  in the STRUCTURE band.
* **The works** (`modules/rock_works.gd`) are paint on top of it: HAB A (with the name on its roof) and HAB B, a
  hydroponics dome and a survey dome, the ops block with the control cupola, the ore plant (pit head, conveyors,
  crusher, screen house, stockpile, an elevated belt down to the apron), three tanks, a relay dish, the antenna
  mast and two solar racks. Each block casts a short shadow on the ground.
* **The landing apron** (`modules/outpost_apron.gd`) is a deck in a terrace cut into the rock's south face, so
  the PETREL can land on it and you can walk on it. Pads **Vesper 1** and **Vesper 2** stand on it (heading
  east), three colliding ore hoppers sit against the back wall, and a 30 m × 20 m patch east of the pads is kept
  free for a freight intake.
* **The docking spar** (`modules/outpost_spar.gd`) is a 220 m pier standing off the rock's north rim, joined to
  HAB A by a pressurised trunk. Its north face is the wall of **Berth V1** (`FrigateBerth`, bow east, starboard
  to the pier). The berth's capture position is Vesper's origin, and its axis is the frigate lane: clear from one
  side of the sector to the other and lined with lane lights whose flashes run inbound (green to starboard and
  red to port coming in from the west, amber on the way out to the east).
* **The asteroid field** (`asteroid.gd`, `modules/asteroid_field.gd`, `rock_fx.gd`). About 40 `RigidBody2D` rocks
  in three sizes (4 m, 9 m and 18 m across; 8 t, 70 t and 500 t), planted from a seed in loose clusters and kept
  out of the lane, the apron and a 120 m ring around the pads. Each rock circles a home point on a very soft
  tether with a soft speed limit, so the field drifts and tumbles but is still in place hours later. A rock is
  one cached triangle array: its facets carry their normals in the UVs and `asteroid_lit.gdshader` lights them
  in world space, so the lit side keeps facing the sun while the rock turns and nothing is redrawn. Rocks report
  impacts like containers do (never contacts with the player). `take_shot(damage, at, dir, shooter)` chips a rock
  (dust, a crack, a nudge); at zero hit points (30 / 90 / 240) it breaks into two or three rocks of the next
  size down, or bursts if it is the smallest, and emits `Game.target_destroyed("asteroid")`. One rock in four
  carries ore (teal veins that glint) and leaves an **ORE canister** when destroyed: a `cargo_box.gd` container,
  so the mag-line can tow it. When fewer than 70 % of the rocks are left, the field adds one where nobody is
  looking. The whole field sleeps (out of the physics space, not drawn) while no camera or ship is within 2.4 km.

See it with `scenes/test/level_tour.tscn -- --cam=8960,200,0.24` (the outpost) or `--cam=9000,0,0.075` (the
sector), or fly there: `scenes/main.tscn -- --no-intro --fly=kestrel@84400,0,0`.

## How the assets were made

* **Sound:** all 126 WAVs in `assets/audio/` are synthesised by a pure-Python DSP script, with no external
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
  that fades in as the hull drops), imported at 6× with mipmaps. The frigate's three SVG layers are generated by
  `python3 tools/art/frigate_svg.py` (hull imported at 2×, livery and lights at 1×). The landed close-up model is
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
| `--sky-look=vesper` | Start with the Vesper sky look, composed around world (90000, 0) px (`env_test.tscn` moves its camera there) |
| `--warp-demo` | `env_test.tscn` only: loop a scripted light-speed jump there and back (`--warp-heading=deg`, `--warp-ship=res://texture@scale`) |
| `--dock-at=HangarBay` | Any pad by name (spaces optional), including `KESTRELBayA` (a frigate's flight deck) and `Vesper1` |
| `--fly=petrel` or `--fly=petrel@x_px,y_px,deg` | Start aboard the PETREL (on its berth, or flying at that spot); the WREN is parked |
| `--fly=kestrel` or `--fly=kestrel@x_px,y_px,deg` | Start at the KESTREL's helm (clamped in Berth E2, or adrift at that spot); `--fly=halcyon` is the other frigate |
| `--jump=vesper` | Lay in that course and jump as soon as a frigate is flown undocked (skips the spool and the clearance check) |
| `--interior=res://scenes/onfoot/interiors/x.tscn@Marker` | Start on foot inside that interior, at that `Marker2D` (or its airlock). `--interior=frigate:kestrel@DeckStand` is a frigate's deck |
| `--walk-to=Marker` | Each time an interior is entered, start at that marker |
| `--foot-zoom=0.1` | On-foot camera zoom factor (1 = normal): small values show a whole interior |
| `--frigate-hits=N` | N seeded 25 hp hits across the frigate's hull at start (shield, breaches, red alert) |
| `--hold=N` | Start with N slots of generated containers in the PETREL's hold (use with `--fly=petrel`) |

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

Headless checks (each prints a PASS/OK result). `tools/run_checks.sh` runs all of them and prints one line per
check (pass words to filter, e.g. `tools/run_checks.sh onfoot`, or `--audio` to add the windowed audio test):
```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --fixed-fps 120 res://scenes/test/ship_physics_test.tscn     # WREN flight model, throttle, turn and assist
$G --headless --path . --fixed-fps 120 res://scenes/test/level_validate.tscn        # level contract, lanes, prop impacts
$G --headless --path . --fixed-fps 120 res://scenes/test/gate_clearance_check.tscn  # every race gate clear of structure
$G --headless --path . --fixed-fps 120 res://scenes/test/gameplay_race_test.tscn    # race logic, splits, best lap saved
$G --headless --path . --fixed-fps 120 res://scenes/test/onfoot_flow_test.tscn      # disembark, airlock, interior, state, board
$G --headless --path . --fixed-fps 120 res://scenes/test/vehicles_flow_test.tscn    # hangar stairs, board PETREL, land anywhere, swap ships
$G --headless --path . --fixed-fps 120 res://scenes/test/shuttle_flight_test.tscn   # PETREL turn-in-place, terminal speed, hover, mag-line tow
$G --headless --path . --fixed-fps 120 res://scenes/test/cargo_hold_test.tscn       # PETREL hold: stow on reel, slots, mass, unload, spill, freight delivery
$G --headless --path . --fixed-fps 120 res://scenes/test/frigate_test.tscn          # KESTREL thrust, turn couple, all stop, shield, sections, core breach
$G --headless --path . --fixed-fps 120 res://scenes/test/frigate_flow_test.tscn     # gangway, frigate deck, helm, undock, re-dock, leave helm, way back
$G --headless --path . --fixed-fps 120 res://scenes/test/weapons_test.tscn          # bolts, take_shot protocol, drone kill and respawn, heat lockout
$G --headless --path . --fixed-fps 120 res://scenes/test/outpost_test.tscn          # Vesper asteroid field: seed, shots, splits, ore canister, refill, sleep
$G --headless --path . --fixed-fps 120 res://scenes/test/carrier_jump_test.tscn     # two frigates, flight deck, lift, stowed ship, quantum jump to Vesper, contracts
$G --path . --fixed-fps 120 res://scenes/test/ship_audio_test.tscn                 # windowed (needs audio): which sound each flight key makes, all three ships
$G --headless --path . --quit-after 600 res://scenes/main.tscn                     # whole game: should print nothing
```

Visual test scenes:
* `scenes/test/level_tour.tscn`: a camera tour of the station. Use `--cam=x_m,y_m,zoom` for a fixed view
  (for example `--cam=0,0,0.085` shows the whole station), and `--show-gates` or `--fps` for overlays.
* `scenes/test/ship_sandbox.tscn`: the ship in a test arena with walls, crates and a rotating bar.
* `scenes/test/gameplay_sandbox.tscn`: the full game on a simple stand-in level.
* `scenes/environment/env_test.tscn`: the background on its own (`--cam=x,y,zoom`, `--sky-look=vesper`), and
  the light-speed effect with `--warp-demo` (charge from 1 s, leap at 4.2 s, tunnel 5.1 to 9.7 s, arrival after).
