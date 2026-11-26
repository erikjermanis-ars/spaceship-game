# Meridian Approach — build contract

A small Godot 4.7 proof of concept: pilot a light courier ship around a large,
busy orbital station in a hopeful near-future setting (think clean, bright,
developed civilisation — big rotating habitat ring, drydocks, cargo yards,
traffic lanes, beacons). The goal is to show off **ship handling**, **level
design**, **art direction** and **sound design**. No menus needed — one
playable sandbox level.

Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot` (v4.7.2).
Project root: `/Users/erikjermanis/work/spaceship-game` (`res://`).
Renderer: **gl_compatibility** (so it can export to the web later). 2D MSAA is
NOT supported here — use `antialiased = true` on lines/polylines instead.
Everything is GDScript and Godot-native nodes. No add-ons, no C#.

## 1. Shared foundation (already exists — do not rewrite)

`res://scripts/autoload/game.gd`, autoloaded as **`Game`**. Read it first. It provides:

* `Game.PX_PER_M = 10.0` — world units are pixels, **1 m = 10 px**. Tune physics in SI and convert.
* Collision layer bit values: `LAYER_WORLD=1` (stations), `LAYER_PLAYER=2`, `LAYER_PROPS=4`
  (containers/debris), `LAYER_TRAFFIC=8` (AI ships), `LAYER_TRIGGERS=16` (Area2D gates/pads),
  `LAYER_WALK=32` (on-foot obstacles only the walker hits), `LAYER_WALKER=64` (the walker).
* Z-index plan (absolute on top-level containers): `Z_BELOW_DECK=-50`, `Z_STRUCTURE=-10`,
  `Z_PROPS=0`, `Z_SHIP=5`, `Z_WALKER=6`, `Z_FX=8`, `Z_WALL_TOP=12` (interior wall tops), `Z_OVERHEAD=20`,
  `Z_OVERHEAD_FX=30`.
* Game mode: `Game.mode` (`Game.Mode.FLIGHT` / `ON_FOOT`) with `mode_changed(mode)`; on-foot milestones
  `disembarked(pad)`, `boarded(pad)`, `entered_interior(name)`, `exited_interior(name)`; `Game.walker` is the
  on-foot character while it exists.
* Signals (the event bus): `impact(pos, normal, speed_mps, source, other)`,
  `scrape(pos, normal, tangent_speed_mps, source)`, `hull_changed(hull, max_hull)`,
  `ship_destroyed(pos)`, `ship_respawned(pos)`, `race_started()`,
  `checkpoint_passed(index, total, split_time)`, `race_finished(time, best)`,
  `docked(pad_name)`, `undocked(pad_name)`, `message(text, duration)`, `debug_draw_changed(enabled)`.
* Shared refs: `Game.player` (set by ship), `Game.camera` (set by camera rig),
  `Game.level` (set by level root), `Game.world_bounds: Rect2` (set by level),
  `Game.debug_draw: bool` (F3 toggles it).
* Helpers: `Game.toast(text, dur)`, `Game.get_loop(path) -> AudioStream` (forces looping),
  `Game.get_variations([paths]) -> AudioStreamRandomizer`.
* Input actions are registered at runtime by `Game` (NOT in project.godot):
  `thrust_forward` (W/↑), `thrust_reverse` (S/↓), `turn_left` (A/←), `turn_right` (D/→),
  `strafe_left` (Q), `strafe_right` (E), `boost` (Space/Shift), `flight_assist` (F),
  `camera_mode` (C), `zoom_in`/`zoom_out` (wheel, =/-), `tuning_panel` (Tab/F1), `help` (H),
  `restart_race` (R), `respawn` (T), `pause` (P/Esc), `radar_toggle` (M), `debug_draw` (F3).
  On foot: `move_up/down/left/right` (WASD/arrows, left stick), `run` (Shift), `interact` (E/Enter),
  `flashlight` (F/L), and `disembark` (X) while docked. Gamepad bindings are included.
* **Test harness** via user args after `--`:
  `--spawn=x_px,y_px,heading_deg`, `--input=0.5-3:thrust_forward;1-1.6:turn_left+boost`,
  `--shots=1,2.5` (PNG captures at physics-time seconds), `--shot-dir=/abs/dir`,
  `--quit-at=6`, `--debug-draw`, `--log=0.5` (prints player state).
  Example windowed capture run (works on this Mac; window pops up briefly):
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --path /Users/erikjermanis/work/spaceship-game \
     --fixed-fps 60 --resolution 1280x720 res://scenes/test/my_test.tscn -- \
     --shots=1,3 --shot-dir=/abs/scratch/dir --quit-at=3.2
  ```
  Headless parse/run check: `Godot --headless --path <root> --quit-after 120 res://scenes/x.tscn`.
  After adding NEW asset files (svg/png/wav), run `Godot --headless --path <root> --import`
  once so `.godot/imported` is refreshed. If another agent's file errors, ignore it — only
  fix your own files.

Project settings (already set): physics 120 Hz, zero default gravity & damping,
viewport 1920×1080 with `canvas_items` stretch/expand, window 1600×900.

## 2. File ownership (each workstream ONLY writes inside its own paths)

| Workstream | Owns |
|---|---|
| AUDIO | `tools/audio/**`, `assets/audio/**`, `res://default_bus_layout.tres` |
| ENVIRONMENT (background) | `scripts/environment/**`, `scenes/environment/**`, `assets/art/environment/**` |
| SHIP (flight model, ship art, ship FX & audio, camera, tuning panel) | `scripts/ship/**`, `scenes/ship/**`, `assets/art/ship/**`, `scenes/ui/tuning_panel.tscn`, `scripts/ui/tuning_panel.gd`, `scenes/test/ship_*`, `tests/ship_*` |
| LEVEL (stations, props, traffic, layout) | `scripts/level/**`, `scenes/level/**`, `assets/art/level/**`, `scenes/test/level_*` |
| GAMEPLAY (impact FX, damage, race, docking, boundary, HUD, main scene) | `scripts/systems/**`, `scripts/ui/**` (except tuning_panel.gd), `scenes/ui/**` (except tuning_panel.tscn), `assets/art/fx/**`, `scenes/main.tscn`, `scripts/main.gd`, `scenes/test/gameplay_*` |
| ON-FOOT (walking, landed ship model, pad sites, interiors) | `scripts/onfoot/**`, `scenes/onfoot/**`, `assets/art/onfoot/**`, `scenes/test/onfoot_*`, `tests/onfoot_*` |

The PETREL stage added a second pilotable ship. SHIP owns `scripts/ship/shuttle_*.gd`, `mag_line.gd`,
`landing_probe.gd`, `landing_overlay.gd` and `scenes/ship/shuttle.tscn`. `Game.player` can change at runtime:
use `Game.set_player()` and listen to `Game.player_changed(new, old)`; never cache the ship. `PlayerShip` has
the vehicle API (`park`, `take_control`, `on_boarded`, `can_disembark`, `disembark_hint`, `landed_model`,
`ship_id`, `uses_pad_clamps`, `home_transform`, `damage_scale`) and a virtual `_apply_flight_forces()`. Parked
ships sit on `LAYER_WORLD`, frozen. Static station modules publish deck floors in `LevelArt.walk_decks` (landing
and walking surfaces). New input actions: `ship_hover`, `ship_line`, `ship_reel`, `aim_*`.

The on-foot stage added small hooks outside its own paths. `game.gd` got the layers, mode, signals and actions
above. `CameraRig` got `set_focus()`, `clear_focus()` and `snap_focus()`. `LevelArt.depth_amount` flattens the
2.5D parallax. `DockingSystem` got `is_docked()`, `is_settled()` and `force_dock()`. `AmbientAudio` got
`set_level_offset()`. The HUD got the "X Exit ship" prompt, `HudStyle.key_hint()` and the on-foot help page.

`docs/CONTRACT.md` and `scripts/autoload/game.gd` are frozen: if you truly need a
change, put a note in `docs/requests/<workstream>.md` instead.

## 3. Scene contract (paths are fixed — other workstreams instance these)

* `res://scenes/environment/space_background.tscn` — root `CanvasLayer` (layer −10) or
  equivalent that always renders behind the world, follows `get_viewport().get_camera_2d()`
  for parallax by itself. Zero gameplay coupling.
* `res://scenes/level/level.tscn` — root `Node2D` named `Level` with script that sets
  `Game.level = self` and `Game.world_bounds`. Must contain:
  * `Marker2D` named `PlayerSpawn` (group `player_spawn`) — +X of its rotation = initial heading.
  * `Node2D` named `RaceCourse` whose children are `Marker2D` named `Gate01`, `Gate02`, …
    in order. Each gate marker: position = gate centre; the ship is meant to pass travelling
    roughly along the marker's local **+X**; the gate's span runs along local **Y**;
    `set_meta("width_m", float)` = gap between the posts in metres (default 40).
    The final gate is the finish line.
  * Docking pads: `Area2D` nodes in group `docking_pad` on layer `LAYER_TRIGGERS`,
    mask `LAYER_PLAYER`, with `set_meta("pad_name", "Pad 3")`. Their +X = the heading
    the ship should face when docked. One pad is the spawn pad.
  * Structures that should show on the radar: nodes in group `radar_structure` implementing
    `get_radar_polygons() -> Array[PackedVector2Array]` (GLOBAL coordinates, simplified outlines).
    Moving props/traffic join group `radar_prop` / `radar_traffic` (radar uses global_position).
  * Containers/props are `RigidBody2D` (layer `LAYER_PROPS`, mask world|player|props|traffic,
    `contact_monitor` on) that emit `Game.impact` for prop↔world/prop↔prop/prop↔traffic contacts
    only (NEVER for contacts with the player — the player reports those).
  * Traffic ships: `AnimatableBody2D` (layer `LAYER_TRAFFIC`) following lanes, or similar.
  * Colliding structure must be on layer `LAYER_WORLD`. Moving structure (rotating ring,
    crane arm, blast doors) = `AnimatableBody2D` with `sync_to_physics = true`, moved in
    `_physics_process`.
* `res://scenes/ship/player_ship.tscn` — root `RigidBody2D` with `class_name PlayerShip`
  (script `res://scripts/ship/player_ship.gd`), in group `player_ship`, sets `Game.player = self`.
* `res://scenes/ship/camera_rig.tscn` — root `Camera2D` with `class_name CameraRig`, sets
  `Game.camera = self`, follows `Game.player`.
* `res://scenes/ui/tuning_panel.tscn` — `CanvasLayer` with live sliders for the flight model.
* `res://scenes/ui/hud.tscn` — `CanvasLayer` HUD.
* `res://scenes/main.tscn` (+ `res://scripts/main.gd`) — assembled by GAMEPLAY:
  ```
  Main (Node2D, main.gd)
    SpaceBackground   (instance space_background.tscn)
    Level             (instance level.tscn)
    PlayerShip        (instance player_ship.tscn)  -> moved to PlayerSpawn (or --spawn) on start
    CameraRig         (instance camera_rig.tscn)
    Systems (Node)    ImpactFX, DamageSystem, RaceSystem, DockingSystem, BoundarySystem, AmbientAudio
    HUD               (instance hud.tscn)
    TuningPanel       (instance tuning_panel.tscn)
    OnFoot (Node)     OnFootDirector: walker, landed ship, pad site, interiors, on-foot HUD
  ```
* On foot: `res://scenes/onfoot/sites/<pad>_site.tscn` holds pad-specific extras in world coordinates
  (registered in `PadSite.EXTRAS`). It may emit `enter_requested` and provide `get_interior_path()`,
  `outside_point()`, `inside_point()`, `door` and `set_cycling()`. `res://scenes/onfoot/interiors/*.tscn` has an
  `InteriorLevel` root whose origin is placed at the site's origin, plus an `Airlock` node.

## 4. PlayerShip API (SHIP implements, GAMEPLAY/HUD consume)

```
class_name PlayerShip extends RigidBody2D
var hull: float = 100.0          var max_hull: float = 100.0
var boost_energy: float = 1.0    # 0..1
var flight_assist: bool = false  # F toggles
var alive: bool = true
var controls_enabled: bool = true
# live input readouts for HUD (after assist/boost logic):
var throttle_input: float   # -1..1
var turn_input: float       # -1..1 (negative = left / counter-clockwise on screen)
var strafe_input: float     # -1..1
var boosting: bool
func velocity_mps() -> Vector2
func speed_mps() -> float
func take_damage(amount: float, at: Vector2) -> void   # emits Game.hull_changed; at 0 -> destroy()
func repair(amount: float) -> void
func refill_boost() -> void
func destroy() -> void            # hides ship, disables collision & controls, emits Game.ship_destroyed
func respawn_at(xform: Transform2D) -> void   # resets velocity/hull/boost, emits Game.ship_respawned
```
The ship emits `Game.impact(..., source=self, other=collider)` for every NEW contact with closing
speed > ~0.8 m/s (per-collider cooldown ~0.15 s) and `Game.scrape` every physics frame it is
sliding along something (tangential speed > ~1 m/s). The ship does NOT deal damage to itself —
GAMEPLAY's DamageSystem listens to `Game.impact` and calls `take_damage`.

CameraRig API: `add_trauma(amount: float)` (0..1, shake = trauma²), `punch(direction: Vector2, strength_px: float)`.

## 5. Flight model (SHIP) — reproduce Pat Kerr's "Motion Lab" ship, side-thruster variant

Reference: https://patkerr.co.uk/2d-vehicles/ (ship mode, "Physical · side thrusters").
The ship is modelled as a **barbell**: a light thruster "head" at the bow and a heavier
payload at the stern joined by a rigid massless spine. Mass ratio payload:head = 2:1,
separation 6 m → centre of mass sits 4 m behind the head. ALL thrust is applied at the head:

* mass `m = 1000 kg`; moment of inertia per unit mass `≈ 8.37 m²` (head 1/3 at +4 m with a
  small triangle body, payload 2/3 at −2 m with radius 0.9 m) → `I = m·8.37` kg·m².
* thrust point = **+4 m ahead of the CoM** on the ship's axis.
* main thrust `5000 N` along ship +X (throttle ∈ [−1, 1]; reverse may be scaled, default 0.6).
* side thrust `2600 N` along ship ±Y **at the thrust point** → it both turns the ship AND pushes
  the whole craft sideways (characteristic swinging, drifting feel; you must counter-steer to stop
  rotating). Turn left = bow pushed to the ship's left (−Y local in Godot's y-down space).
* boost ×2 on both main and side thrust; boost pressed alone (no turn) also adds forward thrust.
* linear drag force `−m·0.12·v` (gentle; terminal ≈ 41.7 m/s, ≈ 83 m/s boosted),
  angular drag torque `−I·0.35·ω`. No speed caps.
* semi-implicit Euler at fixed 120 Hz (Godot's RigidBody2D integrator does this). Disable
  Godot's own damping (`linear_damp_mode/angular_damp_mode = REPLACE`, value 0) and apply drag
  as forces so the numbers match.
* In Godot units: forces ×PX_PER_M, inertia ×PX_PER_M², positions ×PX_PER_M.
  Use `center_of_mass_mode = CUSTOM`, CoM at the body origin, custom `inertia`.
  `apply_force(force, offset)` takes the offset in GLOBAL orientation relative to the origin.
Additions beyond the reference (all tunable live in the tuning panel):
* strafe thrusters (Q/E): small lateral force at the CoM (default 1200 N), no torque.
* boost energy: drains while boosting, recharges after a short delay.
* optional **flight assist** (F, OFF by default): counters rotation with a pure torque (capped by
  side thruster authority) when no turn input, and bleeds lateral slip with strafe thrusters.
* collisions: `continuous_cd = CCD_MODE_CAST_SHAPE`, `contact_monitor = true`,
  PhysicsMaterial bounce ≈ 0.45 / friction ≈ 0.2 (tunable).

## 6. Art direction (everyone)

Hopeful, clean, high-tech civilisation. Top-down, slightly stylised "illustrated tech" look:
* Hulls: pearl white `#E9EEF3`, light grey `#C9D2DC`, panel-line grey `#8E9AA8`, deep accent
  navy `#1D3557`, secondary accent teal `#2A9D8F`.
* Lights: warm habitat windows `#FFE2A0`, cool tech/cyan `#7FE6FF`, nav red `#FF3B3B` (port),
  nav green `#3BFF7A` (starboard), white strobes, amber hazard `#FFB000` with diagonal stripes
  on docking/hazard areas.
* Space: near-black blue `#04060C`, nebula violet/teal haze, a big planet with city lights on
  the night side, a sun glare.
* Glow is faked with **additive** soft sprites (`CanvasItemMaterial.blend_mode = BLEND_MODE_ADD`
  with a radial `GradientTexture2D`) — renderer-agnostic and cheap. Lines antialiased.
* Depth: three bands. BELOW-DECK (non-colliding, darker, drawn under the ship), STRUCTURE
  (colliding, brightest, crisp outlines), OVERHEAD (non-colliding trusses/bridges/spokes drawn
  above the ship, semi-transparent ~0.55–0.75 alpha, with a soft shadow). Players instantly read
  what they can hit: colliding structure has a bright rim/outline; non-colliding layers don't.
* Ship size ≈ 9 m long ⇒ ~90 px. Station ring radius hundreds of metres. Default camera shows
  ~190 m × 110 m; speed zoom pulls out to ~2.2× that.

## 7. Audio file contract (AUDIO produces, others play) — `res://assets/audio/`

16-bit PCM WAV, 44.1 kHz, mono unless noted. Loops must be seamless (and contain a `smpl`
loop chunk if possible); everyone should still load loops via `Game.get_loop(path)`.

| File | Use | Owner of playback |
|---|---|---|
| `engine_main_loop.wav` | main engine rumble/roar, loop ~3 s | SHIP |
| `engine_boost_loop.wav` | boost afterburner roar, loop ~3 s | SHIP |
| `rcs_hiss_loop.wav` | RCS gas jet hiss, loop ~2 s | SHIP |
| `rcs_puff_1..3.wav` | RCS valve pop/puff ~0.12 s | SHIP |
| `engine_ignite.wav` | thump+whoosh when throttle starts ~0.5 s | SHIP |
| `boost_kick.wav` | boost engage punch ~0.6 s | SHIP |
| `low_hull_alarm.wav` | warning beep loop ~1 s | SHIP |
| `impact_light_1..4.wav` | light metal taps/clinks | GAMEPLAY |
| `impact_medium_1..3.wav` | solid metal clangs | GAMEPLAY |
| `impact_heavy_1..3.wav` | big crunchy hull hits with low thump | GAMEPLAY |
| `scrape_loop.wav` | metal-on-metal grinding loop ~2 s | GAMEPLAY |
| `container_clunk_1..3.wav` | hollow cargo container knocks | GAMEPLAY |
| `explosion_ship.wav` | ship destruction ~3 s | GAMEPLAY |
| `debris_rattle.wav` | small debris tinkles ~1 s | GAMEPLAY |
| `gate_pass.wav` | checkpoint chime | GAMEPLAY |
| `race_countdown.wav` / `race_go.wav` / `race_finish.wav` | race cues | GAMEPLAY |
| `dock_clamp.wav` / `dock_chime.wav` | docking complete clamp + chime | GAMEPLAY |
| `boundary_warning.wav` | out-of-bounds warning loop ~1 s | GAMEPLAY |
| `ui_click.wav` | UI toggles | GAMEPLAY/SHIP |
| `ambient_space_drone.wav` | **stereo** ambient music pad loop ~30 s | GAMEPLAY (AmbientAudio) |
| `station_hum_loop.wav` | machinery hum loop ~4 s, positional | LEVEL |
| `traffic_engine_loop.wav` | small craft engine whine loop ~2 s, positional | LEVEL |
| `beacon_ping.wav` | navigation buoy ping ~1 s, positional | LEVEL |
| `door_servo.wav` | heavy blast door / crane servo motion ~1.5 s | LEVEL |

Audio buses (`res://default_bus_layout.tres`): `Master` (limiter), `SFX`, `Engine`, `Ambient`,
`UI` — all routed to Master. Use `bus = &"SFX"` etc. Positional sounds use `AudioStreamPlayer2D`
(Godot 2D audio pans/attenuates relative to the active Camera2D).

## 8. Quality bar

* No errors or warnings spam in the Godot output when running the scene headless.
* Typed GDScript, small focused scripts, clear names, comments explaining *why*.
* Must run at a smooth 60+ fps on an M1 Pro in the Compatibility renderer: prefer
  `_draw()` cached geometry (only `queue_redraw()` when something actually changes),
  `CPUParticles2D` for effects, shaders for backgrounds; avoid per-frame allocations.
* Verify visually: take screenshots with the harness and LOOK at them (Read the PNG).
