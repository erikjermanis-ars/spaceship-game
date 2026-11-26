# Agent guide: Meridian Approach

This is a Godot 4.7 2D game written only in GDScript: fly a ship around an orbital station, dock, get out and
walk, take a second ship (the PETREL), and walk aboard a frigate (the KESTREL) to fly it from its bridge. It has no add-ons, no C# and no imported assets. All art, shaders and
sound are made in this repo. This file is the short version. For detail:

* `README.md`: what the game does, the architecture of each subsystem, controls and every harness flag.
* `docs/CONTRACT.md`: conventions and APIs that the code relies on (scene layout, PlayerShip API, flight
  model, art palette, audio files, quality bar).
* `docs/requests/{gameplay,level,ship}.md`: facts about each subsystem's behaviour (pad list, impact timing,
  the damage formula, render ordering). Read the one for the area you are changing.
* `assets/audio/README.md`: every sound file with its bus and volume.

## Commands

```
G=/Applications/Godot.app/Contents/MacOS/Godot      # v4.7.2
tools/run_checks.sh                  # all headless checks, ~25 s; filter with e.g. `tools/run_checks.sh onfoot`
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

* `--dock-at=2 --on-foot` starts walking on Pad 2. `--fly=petrel` starts in the PETREL. `--fly=kestrel` starts at
  the frigate's helm in its berth (`--fly=kestrel@x,y,deg` adrift); `--frigate-hits=N` damages it for screenshots. `--spawn=x_px,y_px,deg`
  places the ship, and `--perf` prints fps and draw calls.
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
| Frigate damage model, berth docking, generated hull shape | `scripts/ship/frigate_*.gd`, `tools/art/frigate_svg.py` | `frigate_damage.gd`, `frigate_dock.gd` |
| Frigate berths (clamp pylons, gangway, guidance) | `scripts/level/modules/frigate_berth.gd` | |
| Station modules, props, traffic, layout | `scripts/level/`, `scenes/level/level.tscn` | `station_module.gd`, `level_art.gd` |
| Gameplay systems (impact FX, damage, race, docking, boundary, flight guide) | `scripts/systems/` | |
| HUD, tuning panel | `scripts/ui/`, `scenes/ui/` | `hud.gd` |
| On foot (walker, pad sites, interiors, interactables) | `scripts/onfoot/`, `scenes/onfoot/` | `on_foot_director.gd` |
| Frigate interior (bridge, chair, reactor, systems table) | `scripts/onfoot/frigate/`, `scenes/onfoot/interiors/frigate_deck.tscn` | `frigate_deck.gd` |
| Background (sky, planet, distant stations) | `scripts/environment/`, `assets/art/environment/shaders/` | |
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
  as well, and so does every node under `Systems` except `AmbientAudio`. A new flight-only system goes in
  `FLIGHT_SYSTEMS`. A new node that must keep running indoors needs a change in `_suspend_world()`.
* **New pad site** = one scene plus one line in `WalkSite.PAD_EXTRAS`. **New interactable** = extend
  `Interactable`. **Interior to interior** (no exterior between) = an `InteriorPortal` with a `target_scene` and an
  `arrival` marker name in the target.
* **Frigate geometry is generated.** `scripts/ship/frigate_shape.gd` and the frigate SVGs come from
  `tools/art/frigate_svg.py`; change the generator, rerun it, then `--import`.
* **Tests are scenes.** A new check is a scene in `scenes/test/` with a script that prints a result line and
  calls `get_tree().quit(0 or 1)`. Add it to `tools/run_checks.sh`.
* Write typed GDScript, keep scripts small, and use comments to explain *why*, as the existing code does.
