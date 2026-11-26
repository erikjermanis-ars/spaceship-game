# Meridian Approach: audio

Every sound in this folder is synthesised from scratch by `tools/audio/gen_audio.py`
(pure-Python DSP in `tools/audio/dsp.py`, seeded and reproducible). Regenerate everything and re-import:

```
python3 tools/audio/gen_audio.py            # ~40 s, all files (or pass name prefixes)
python3 tools/audio/verify_audio.py         # levels, DC, clicks, loop seams, smpl chunks
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
```

Format: 44.1 kHz 16-bit PCM WAV, mono except `ambient_space_drone` (stereo). One-shots peak at -1 dBFS
and loops at -3 dBFS, so **set the loudness with `volume_db`**. Suggested starting values are below.
Loops are periodic by construction, so they have no crossfade and no seam. They carry a `smpl` chunk, so
Godot imports them with `loop_mode = Forward` and `loop_end` set to the full length. `Game.get_loop()`
also works on them.

Sound concept: you hear everything from inside the cockpit. Space is silent, but the hull carries sound,
so engines come through as rumble and collisions as the ship's own metal ringing. Music and UI cues are
in **D major**, so chimes always fit the ambient bed (Dmaj9, Gmaj9, Bm9, Asus2, one chord about every 7.5 s).

## Buses (`res://default_bus_layout.tres`, loaded automatically)
`Master` (HardLimiter, ceiling -0.5 dB) receives `SFX` (subtle small-room Reverb, wet 0.12), `Engine`,
`Ambient` and `UI`. To rebuild it, run `Godot --headless --path . --script res://tools/audio/make_bus_layout.gd`.

## Suggested playback

| File | Bus | volume_db | Notes |
|---|---|---|---|
| engine_main_loop | Engine | -16 idle → -3 full | `pitch_scale` 0.75 at idle → 1.25 at full throttle (≈1.35 boosting); smooth it ~0.15 s. Reverse thrust also drives it. |
| engine_boost_loop | Engine | -40 → -4 | crossfade in over ~0.12 s while boosting, out over ~0.3 s; pitch 0.95–1.1 |
| rcs_hiss_loop | Engine | -40 → -12 | level from \|turn\| + \|strafe\| (attack fast, release ~0.1 s); pitch 0.95–1.1 |
| rcs_puff_1..3 | Engine | -12 | on each thruster key press; `Game.get_variations()` |
| engine_ignite | Engine | -6 | when throttle goes from 0 to >0 (cooldown ~0.5 s) |
| boost_kick | Engine | -3 | when boost engages |
| low_hull_alarm | UI | -14 | loop while hull < ~25 % |
| impact_light_1..4 | SFX | -14 … -6 | closing speed ~0.8–4 m/s |
| impact_medium_1..3 | SFX | -8 … -2 | ~4–10 m/s, optionally layered with a light hit at -10 |
| impact_heavy_1..3 | SFX | -4 … 0 | > ~10 m/s, layered with a medium hit (-6) for extra detail |
| scrape_loop | SFX | -30 → -6 | level from tangent speed (1→15 m/s); pitch 0.8 + 0.03·speed (cap 1.3); fade out ~0.1 s after `Game.scrape` stops |
| container_clunk_1..3 | SFX | -10 … 0 | prop↔world / prop↔prop impacts; AudioStreamPlayer2D |
| explosion_ship | SFX | 0 | + `debris_rattle` at -8 about 0.2 s later |
| gate_pass | UI | -6 | checkpoint |
| race_countdown / race_go | UI | -8 / -6 | 3 × countdown at 1 s spacing, then go |
| race_finish | UI | -4 | |
| dock_clamp + dock_chime | SFX / UI | -4 / -8 | play the chime ~0.35 s after the clamp |
| boundary_warning | UI | -12 | loop while out of bounds |
| ui_click | UI | -14 | toggles (assist, camera, radar, panel) |
| ambient_space_drone | Ambient | -14 | music bed; fade in over ~3 s |
| station_hum_loop | SFX | -6 | AudioStreamPlayer2D on big station modules, max_distance ~2500 px, attenuation ~1.5 |
| traffic_engine_loop | SFX | -8 | AudioStreamPlayer2D on each traffic ship, max_distance ~1500 px, random pitch 0.9–1.15 per ship |
| beacon_ping | SFX | -8 | AudioStreamPlayer2D on buoys, every 2–4 s, max_distance ~3000 px |
| door_servo | SFX | -4 | AudioStreamPlayer2D when blast doors or crane arms start moving |
