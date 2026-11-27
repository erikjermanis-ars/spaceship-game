# Agent guide: Meridian Approach

This is a Godot 4.7 2D game written only in GDScript: fly a courier (the WREN, with pulse cannons) around an
orbital station, dock, get out and walk, take a cargo shuttle (the PETREL, with a hold), walk aboard a frigate
(the KESTREL or the HALCYON) to fly it from its bridge, land the small ships on its flight deck, and jump it at
light speed to a second station (Vesper Rock). It has no add-ons, no C# and no imported assets. All art, shaders
and sound are made in this repo. This file is the short version. For detail:

* `README.md`: what the game does, the architecture of each subsystem, controls and every harness flag.
* `docs/CONTRACT.md`: conventions and APIs that the code relies on (scene layout, PlayerShip API, flight
  model, art palette, audio files, quality bar).
* `docs/requests/{gameplay,level,ship}.md`: facts about each subsystem's behaviour (pad list, impact timing,
  the damage formula, render ordering). Read the one for the area you are changing.
* `assets/audio/README.md`: every sound file with its bus and volume.

## Commands

```
G=/Applications/Godot.app/Contents/MacOS/Godot      # v4.7.2
tools/run_checks.sh                  # all headless checks, ~80 s; filter with e.g. `tools/run_checks.sh onfoot`
tools/run_checks.sh --audio          # adds the windowed audio test
$G --headless --path . --import      # after adding or replacing any .svg/.png/.wav (refreshes .godot/imported)
$G --path .                          # play the game
```

Run `tools/run_checks.sh` before you say a change is done. The quality bar is no errors and no warnings in the
output. The script treats any `ERROR` or `WARNING` line as a failure.

## Seeing your change

For anything visual, run the game with the test harness, take screenshots and look at the PNGs. Arguments go
after `--` and are parsed by `Game` (`Game.cmd`). The full table is in the README under "Test harness and checks".

```
$G --path . --fixed-fps 60 --resolution 1600x900 res://scenes/main.tscn -- \
  --no-intro --shots=2,5 --shot-dir=/abs/dir --quit-at=5.2 "--input=0.3-4:thrust_forward;1-1.6:turn_left"
```

* `--dock-at=2 --on-foot` starts walking on Pad 2. `--fly=petrel` starts in the PETREL. `--fly=kestrel` (or
  `halcyon`) starts at that frigate's helm in its berth (`--fly=kestrel@x,y,deg` adrift); `--frigate-hits=N`
  damages it for screenshots. `--jump=vesper` jumps a frigate there as soon as it is flown undocked.
  `--spawn=x_px,y_px,deg` places the ship (Vesper Rock is around 90000,0), and `--perf` prints fps and draw calls.
* `--interior=res://scenes/onfoot/interiors/x.tscn@Marker` starts on foot inside an interior
  (`--interior=frigate:kestrel@DeckStand` for a frigate's deck); `--foot-zoom=0.1` zooms the on-foot camera out
  for a whole-interior overview; `--walk-to=Marker` starts at a marker in every interior entered.
* The checks write their logs to `$TMPDIR/meridian_checks`. Two runs at once overwrite each other's logs: give
  parallel runs their own `TMPDIR`.
* `--input` takes action names (`thrust_forward`, `move_right`, `interact`, ...). They are registered in
  `Game._register_inputs()`.
* Faster visual test scenes: `scenes/test/level_tour.tscn -- --cam=x_m,y_m,zoom`, `scenes/test/ship_sandbox.tscn`,
  `scenes/environment/env_test.tscn`.

## Where things are

| Area | Path | Start reading at |
|---|---|---|
| Shared constants, event bus, input map, harness | `scripts/autoload/game.gd` (autoload `Game`) | the whole file |
| Scene assembly, spawn placement | `scenes/main.tscn`, `scripts/main.gd` | |
| Ships (flight model, FX, audio, camera, mag-line, landing) | `scripts/ship/` | `player_ship.gd`, `shuttle_ship.gd`, `frigate_ship.gd` |
| PETREL cargo hold (stow on reel, unload, spill) and freight intakes | `scripts/ship/cargo_hold.gd`, `cargo_handler.gd`, `scripts/level/modules/freight_receiver.gd`, `scripts/systems/freight_ledger.gd` | `cargo_handler.gd` |
| Frigate damage model, berth docking, flight deck, generated hull shape | `scripts/ship/frigate_*.gd`, `tools/art/frigate_svg.py` | `frigate_damage.gd`, `frigate_dock.gd`, `frigate_bay.gd` |
| Sectors (stations), the quantum jump, the star map | `scripts/systems/sectors.gd`, `jump_system.gd`, `scripts/ui/star_map.gd` | `jump_system.gd` |
| Contracts (objectives) and their HUD panel | `scripts/systems/contracts.gd`, `scripts/ui/hud_contracts.gd` | |
| Vesper Rock (outpost exterior, asteroid field) | `scenes/level/outpost.tscn`, `scripts/level/modules/rock_*.gd`, `outpost_*.gd`, `asteroid_field.gd`, `scripts/level/asteroid.gd` | |
| Frigate berths (clamp pylons, gangway, guidance) | `scripts/level/modules/frigate_berth.gd` | |
| Station modules, props, traffic, layout | `scripts/level/`, `scenes/level/level.tscn` | `station_module.gd`, `level_art.gd` |
| Gameplay systems (impact FX, damage, race, docking, boundary, flight guide) | `scripts/systems/` | |
| Weapons (bolts, hit protocol, hit FX; the WREN's guns, heat, aim line) | `scripts/systems/weapon_*.gd`, `scripts/ship/wren_guns.gd`, `gun_aim_line.gd` | `weapon_system.gd` |
| Gunnery range (target drones, scoreboard) | `scripts/level/modules/gunnery_range.gd`, `scripts/level/target_drone.gd`, `range_scoreboard.gd` | |
| HUD, tuning panel | `scripts/ui/`, `scenes/ui/` | `hud.gd` |
| On foot (walker, pad sites, interiors, interactables) | `scripts/onfoot/`, `scenes/onfoot/` | `on_foot_director.gd` |
| Frigate interior (deck plan in the hull, bridge, nav table, lift, flight deck) | `scripts/onfoot/frigate/`, `scenes/onfoot/interiors/frigate_deck.tscn` | `frigate_deck.gd` |
| Station interiors, transit line, airlock doors in outer walls | `scenes/onfoot/interiors/`, `scripts/onfoot/interior/`, `scripts/onfoot/exterior_doors.gd`, `exterior_door.gd` | `interior_portal.gd`, `exterior_doors.gd` |
| Background (sky looks: Meridian planet and stations, Vesper gas giant and belt) | `scripts/environment/`, `assets/art/environment/shaders/` | `space_background.gd`, `vesper_sky.gd` |
| Light-speed jump screen effect | `scripts/environment/warp_fx.gd`, `assets/art/fx/warp_*` | `warp_fx.gd`, `warp_demo.gd` |
| Sound generation | `tools/audio/` (Python, no dependencies) | `gen_audio.py` |
| Tests | `tests/`, `scripts/*/test/`, `scripts/*/sandbox/`, scenes in `scenes/test/` | |

## Rules that are easy to break

* **Units.** 1 m = 10 px (`Game.PX_PER_M`). Tune in SI units and convert. Exported tunables are SI.
* **Never cache the ship.** `Game.player` changes when you switch ships. Read it each time, or listen to
  `Game.player_changed(new, old)`. Do the same for `Game.walker`, which only exists on foot.
* **Never set `global_transform` on a live ship.** It is a continuous-collision body, so it sweeps through
  the station and dies on the first frame. Take it out of the tree, set the transform, then add it back
  (`main.gd` does this), or use `respawn_at()`.
* **Collision layers and z-index** come from `Game.LAYER_*` and `Game.Z_*`. Don't use raw numbers. Colliding
  structure is `LAYER_WORLD`. Moving structure is an `AnimatableBody2D` that is moved in `_physics_process`.
* **Impacts are reported once.** The ship reports its own contacts. Props never report contacts with the
  player. `DamageSystem` applies damage from `Game.impact`, and the ship never damages itself.
* **Draw calls.** In the Compatibility renderer every `draw_*` call is a separate draw call. Draw station art
  through `StationModule` / `LevelArt` and on-foot art through `OnFootPainter`, which batch shapes into
  triangles. Call `queue_redraw()` only when something changes. There is no MSAA, so use antialiased lines.
* **Input actions are registered at runtime** in `game.gd`, not in `project.godot`. Add new ones there.
* **On foot, parts of the game are paused.** `OnFootDirector` sets `process_mode = DISABLED` on them, with
  a reference count so nested pauses work. When you get out, the flight systems and flight HUD in
  `FLIGHT_SYSTEMS` / `FLIGHT_HUD` stop. Inside an interior, everything under `Main` except `KEEP_INSIDE` stops
  as well, and so does every node under `Systems` except those in `KEEP_SYSTEMS` (the music, the jump system
  with its star map, contracts). A new flight-only system goes in `FLIGHT_SYSTEMS`; a new system that must keep
  running indoors goes in `KEEP_SYSTEMS`.
* **New pad site** = one scene plus one line in `WalkSite.PAD_EXTRAS`. **New interactable** = extend
  `Interactable`. **Interior to interior** (no exterior between) = an `InteriorPortal`: a fixed `target_scene` +
  `arrival` marker (add `ride = true` for a transit pod), a station gangway (`berth_id`: leads aboard whichever
  frigate is docked there), or a frigate's airlock (`frigate_side`). **A door from a deck into an interior** = an
  entry in `ExteriorDoors.DOORS` plus an `Airlock` in the interior whose `exit_point` is the same world point.
* **There are two frigates and one deck scene.** Never look a frigate up with "first node in group `frigate`".
  On foot, the ship you are aboard is `FrigateShip.aboard`; a berth's ship is `FrigateShip.docked_at(tree, id)`;
  a frigate's own berth is `dock.berth` (it can dock anywhere), its home is `home_berth`.
* **Sectors.** Every station is in the same world scene, far apart (`Sectors.DEFS`). `Game.sector` and
  `Game.world_bounds` follow the player's ship (`JumpSystem`); code that assumes Meridian (race, pads, respawn)
  must check the sector. A ship parked on a frigate's flight deck is carried (`FrigateBay.stowed`): don't move it
  yourself, and read its place with `render_transform()` if you draw something on it.
* **Stowed cargo is out of the tree.** A container in the PETREL's hold (`ShuttleShip.hold`, a `CargoHold`) is
  the same node, removed from the scene tree until it is ejected. Don't keep it alive elsewhere or look for it
  in groups. Put one back with `CargoHold.put_in_world()` (it sets the position before the node enters the tree).
  `ShuttleShip.mass_kg` includes the cargo: setting it from outside sets the dry mass.
* **Deliveries** go through `FreightReceiver` (group `freight_receiver`): it emits
  `Game.cargo_delivered(brand, receiver_id, slots)` and tallies in the static `FreightLedger`. `--hold=N` starts
  the PETREL with N slots filled.
* **Shootable things implement `take_shot(damage, at, dir, shooter)`** on the body the bolt's ray hits (layer
  WORLD, PROPS or TRAFFIC). `WeaponSystem` (group `weapon_system`) then leaves the reaction to them; without it a
  prop is shoved, another ship is scratched and structure only sparks. Fire with
  `WeaponSystem.fire(origin, dir, inherit_velocity, shooter)`; never spawn a node per shot. Details:
  `docs/CONTRACT.md` "Weapons".
* **Frigate geometry is generated.** `scripts/ship/frigate_shape.gd` and the frigate SVGs come from
  `tools/art/frigate_svg.py`; change the generator, rerun it, then `--import`.
* **Tests are scenes.** A new check is a scene in `scenes/test/` with a script that prints a result line and
  calls `get_tree().quit(0 or 1)`. Add it to `tools/run_checks.sh`.
* Write typed GDScript, keep scripts small, and use comments to explain *why*, as the existing code does.
