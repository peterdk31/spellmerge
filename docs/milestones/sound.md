# Sound: a generator for every sound the game asks for

**Status (2026-11-18): written with the owner, waiting for approval.** AU1 (this document) is up for review. Written with the owner in an owner session on 2026-11-18, after an interview and three style samples.

**The owner (2026-11-18):** "We need to design a sound generator for the game."

**The owner's answers (2026-11-18):**

1. **Both:** an offline tool bakes `.ogg` files from recipes, and the game adds cheap variation when it plays them (a few baked variants of each sound, small pitch and volume jitter).
2. **Everything:** sound effects, held (looping) sounds, music and UI sounds.
3. **Modern synthesised:** filtered-noise whooshes, roaring fire with crackles, bell-like inharmonic glass, FM shimmer. This was picked from three samples (pure 8-bit, chiptune-plus, modern synth), each playing a cast, a fire hit, a glassy reaction ping and four players casting at once.
4. **Claude writes the recipes and the owner tunes by listening.** The recipe format only needs to be readable, not a contributor-facing editor.
5. **Python in `tools/`**, the `.ogg` committed, so players and CI never run the generator.
6. **A recipe lives beside the sound it makes.** New content means new files.
7. **Music is a pattern sequencer:** a score file per track, instruments from the same synth, and layers baked to exactly one length.
8. **Mixing:** stereo pan by place on screen (gentle), buses with volume settings and ducking, and loudness targets per family, written in docs/STYLE.md.
9. **A hash check:** a test flags an `.ogg` whose recipe changed without a rebake.
10. **Auditioning:** an in-game sound room, and a contact-sheet `.ogg` on each PR.
11. **A new `core/audio` service** for what is shared (buses, ducking, volumes, UI sounds, variants).
12. **The first batch is the core combat set:** `cast`, `hit`, `enemy_death`, `player_downed`, `revive`, `heal` and the fourteen reactions.
13. **Tier `good`** in the manifest; the owner promotes a sound to `final` after listening.

The steps are **AU1 to AU9** (AU for audio). Each is one PR with its tests, in order.

## What is there today

The game already plays sound; it has no files.

- **`gameplay/feel/sounds.gd`** plays one-shots and held sounds by id. It has eight `AudioStreamPlayer2D` voices, at most three per id, and 16 held slots that follow a body and fade out over 0.12 s. Feel caps a frame's hit sounds at half the voices.
- **`gameplay/feel/music.gd`** plays a `MusicTrack`: its layers start together, each fades in at its intensity, and one track crossfades into the next.
- **`gameplay/feel/body_sounds.gd`** picks a boss's held phase sounds and its music. **`gameplay/feel/boss_intro_sound.gd`** plays the intro's cues while the tree is paused.
- **`Registry.get_sound(id)`** finds `<id>.ogg` anywhere under `audio/`. A missing id is silent.
- **38 ids are named and silent:** the cues' `sound`, enemy `death_sound`, `preset.hit_sound`, the cast sound and the boss's two music layers (`boss_broom`, `boss_broom_fire`).
- **The cast sound breaks the rule.** `gameplay/player/player.gd` (`_play_cast_sound`) plays it from a simulation area with its own player. It moves to Feel, which hears `spell_cast` (AU3).
- **All sound is on the Master bus.** There are no volume settings and no shared way for the HUD to make a sound (docs/BACKLOG.md, "Sounds and effects by id only in `feel`").

Nothing here changes how the game plays. Every part of this plan is view only: no state, no tick, no hash. A sound's choice of variant and its jitter use the engine's own random numbers, which is allowed because nothing in the simulation hears them.

## The parts

```
tools/sound.py              the command: bake, sheet, check
tools/sound_synth.py        the synth: sources, envelopes, filters, drive, reverb; stdlib only
tools/sound_score.py        the sequencer: a score into one buffer a layer, each exactly one loop long
tools/sound_meter.py        loudness (BS.1770 K-weighted, gated) and true peak
tools/test_sound*.py        their tests (`python3 -m unittest discover -s tools`)
tools/sound_room.tscn/.gd   the sound room (AU4)

audio/patches/*.patch.json  shared instruments and layers (a "glass", a "whoosh"), named by recipes
audio/sfx/<id>/             a sound: <id>.sound.json, <id>.tres, variants/1.ogg ... n.ogg
audio/music/<track>/        a track: <track>.score.json, one .ogg per layer
content/<...>/sounds/<id>/  a sound of one content item, the same shape, listed in that folder's assets.json

core/audio/                 the Audio service (AU3): buses, volumes, ducking, UI sounds
default_bus_layout.tres     Master > Music, SFX (> Boss), UI
```

### 1. A recipe is data, and the synth is the only code

`<id>.sound.json` describes one sound. The tool renders it at 44.1 kHz mono, as many times as it has `variants`, each with its own seed, and writes Vorbis `.ogg` files through `ffmpeg -c:a libvorbis` (quality 6).

```json
{
  "version": 1,
  "kind": "sfx",
  "family": "combat",
  "seconds": 0.4,
  "variants": 4,
  "vary": {"pitch": 0.06, "time": 0.08, "seed": 1},
  "layers": [
    {"source": "noise", "filter": {"type": "band", "from": 600, "to": 4100, "q": 3, "curve": "arch"},
     "amp": {"attack": 0.0, "shape": "arch", "power": 1.5}},
    {"patch": "shimmer", "pitch": {"from": 500, "to": 1300}, "gain": -16}
  ],
  "fx": {"reverb": {"mix": 0.35, "size": 1.2}},
  "notes": "A wizard releasing a spell: a soft whoosh, heard every cast from four players."
}
```

- **Sources:** `sine`, `triangle`, `saw`, `square` (with `duty`), `noise` (white or stepped), `fm` (carrier, ratio, index envelope) and `partials` (a list of ratios, gains and decays, for bells and glass).
- **Shapers on each layer:** an amplitude envelope (`attack`/`decay`/`sustain`/`release`, or a named `shape`), a pitch curve (`from`/`to`, linear or exponential), a filter (`low`/`high`/`band`, a state-variable filter with a swept cutoff), `drive` (tanh), `crush` (bits) and a `start` offset. Layers are summed, then the sound's `fx` (reverb, a final low-pass) are applied.
- **`patch`** names a file in `audio/patches/`, with the layer's own keys on top. The game's sounds share a voice through these: the glass of every frost reaction is one patch.
- **`vary`** is how the variants differ: each variant's seed moves its pitch by up to ±`pitch` (as a ratio) and its time by up to ±`time`, and gives it its own noise. Variants differ, but they never stray from the sound's character.
- **Every number is checked.** A key the synth does not know, a value out of range or a missing patch fails the bake with the file and the key. The synth reads only JSON and `audio/patches/`, and writes only beside the recipe.
- **Stdlib only.** The synth uses `math`, `array` and `random.Random(seed)`, as the other tools do (`tools/README.md`); it doesn't depend on numpy. A bake is offline and seconds long. ffmpeg is needed only to bake, never to check or test.
- **Clicks are bugs.** Every layer starts and ends at zero (at least a 2 ms ramp, enforced by the synth), and the bake fails a variant whose first or last sample is not near zero.

### 2. Kinds

- **`sfx`**: a one-shot, as above.
- **`held`**: a loop for a held sound (`broom_burning`, a cue's `held` part). The tool renders `seconds` plus a tail and folds the tail back over the start, so the file loops with no click and no gap. It writes the `.import` with `loop` on. A held sound has one variant, because a loop that changes file mid-loop clicks.
- **`ui`**: a one-shot on the UI bus. It is quieter, never reverberant, and under 0.15 s.
- **Music** is not a `.sound.json` (section 4).

### 3. Variants and jitter in the game

The tool writes `<id>.tres`, an `AudioStreamRandomizer` naming `variants/1.ogg` to `n.ogg`, with `playback_mode` RANDOM_NO_REPEATS, `random_pitch` and `random_volume_offset_db` taken from the family (docs/STYLE.md, "Sound"). Godot then picks a variant and jitters it on every play, with no code of ours. Four casts in a row, or four players casting at once, never sound like one file played four times.

- **`Registry` learns `.tres` sounds, and content folders' sounds.** It scans only `audio/` today, although audio/README.md says a single item's sound lives in its content folder; AU3 adds a content folder's `sounds/` to the scan. Under either, a `<id>.tres` that is an `AudioStream` is the sound `<id>`. Files under a `variants/` folder are never ids of their own. An `.ogg` and a `.tres` with one id is a registry warning and a test failure. This is a `core/registry` change, with its test (AU3).
- **A sound's length is its longest variant.** `Sounds` holds a voice for `get_length()`, and a randomizer's length is 0. `Audio.length(stream)` returns the longest variant's length, and `Sounds` uses it. AU3 checks what Godot 4.7 returns and tests it.
- **Held sounds and music layers** are plain `.ogg` files, as now.

### 4. Music: a score a track

`audio/music/<track>/<track>.score.json`:

```json
{
  "version": 1,
  "tempo": 96, "beats": 4, "bars": 16, "key": "D minor",
  "instruments": {"pad": {"patch": "warm_pad"}, "pluck": {"patch": "glass_pluck"}, "kick": {"patch": "soft_kick"}},
  "patterns": {"a": {"pluck": "D4 . F4 . A4 . C5 ."}, "beat": {"kick": "x . . . x . . ."}},
  "layers": [
    {"id": "boss_broom", "play": ["a", "a", "b", "a"], "with": ["pad"]},
    {"id": "boss_broom_fire", "play": ["beat", "beat", "beat", "fill"]}
  ]
}
```

- **One length:** every layer is `bars × beats × 60 / tempo` seconds, exactly that many samples. That is the rule `MusicTrack` already needs, because its layers start together and must stay together. The bake fails a score whose layers' patterns don't fill the bars.
- **Seamless:** each layer is rendered twice through, and the second pass is kept, so notes that ring past the loop's end are heard at its start. The `.import` sets `loop` on.
- **A layer is one id** (`boss_broom`, `boss_broom_fire`), as `MusicTrack.layers` and the room's `music` name them now. Nothing in the game changes for music but its bus.
- **Notes:** note names with octaves, `.` for a rest, `-` to hold, `x` for a hit. A pattern is one bar per eight steps by default, or `steps` sets it. Velocity and swing are optional keys. The sequencer is small on purpose; anything more is a patch.
- The plan's honest limit stands (docs/PLAN.md, "Art and music"): this music is `good` until the owner says otherwise, and a commissioned soundtrack may replace it, id for id.

### 5. The Audio service (`core/audio`)

`core/audio/audio.gd`, autoload `Audio`, is view only, has no tick and is not hashed. It holds what more than one area needs:

- **Buses:** `default_bus_layout.tres` (project root, set in `project.godot`), Master > `Music`, `SFX` > `Boss`, and `UI`. `Audio.BUS_MUSIC`, `BUS_SFX`, `BUS_BOSS` and `BUS_UI` are the names, so nobody writes a bus as a string. Feel's `Sounds` puts its voices on `SFX` (a cue may say `bus: boss`), `Music` its players on `Music`, and the boss intro's sound on `Boss`.
- **Volumes:** three machine settings, Music, SFX and UI (0 to 100%, plus mute), in `core/settings` beside the others and saved with them. They are a machine's, not a run's rules: they change nothing in the simulation. The pause menu's settings page shows them (AU8).
- **Ducking:** `Events.music_duck_requested(decibels, seconds)` (core/events, new). Audio lowers the Music bus by the most asked for, and lets it back up over 0.3 s once the seconds are out. A cue asks for it with a new key, `duck: -6.0`, read by Feel when it plays the cue's sound, so a reaction or a boss's slam ducks the music through data. No sound names the music.
- **UI sounds:** `Events.ui_sound_requested(id)` (new). Audio plays it on the UI bus on one of four `AudioStreamPlayer` voices (not placed, not paused with the tree), at most one per id per frame. The HUD sends the event and never touches a player.
- **Panning:** a gentle pan by place, set as `audio/general/2d_panning_strength` (0.5) in `project.godot`, so a sound at the screen's edge is mostly, never wholly, on one side. Feel's voices keep their attenuation by distance.
- Feel keeps its world voices, held sounds and music. They are the world's (placed at bodies, paused with the tree), and moving them is a refactor with no gain. Audio gives them their buses and the variant length. The two areas meet only through core (constants and events).

### 6. Loudness and the manifest

- **Targets by family**, in docs/STYLE.md, "Sound": one-shots by short-term loudness (the loudest 400 ms) and true peak; loops and music by integrated loudness. The bake measures each variant and fails it outside its family's window (±1 LU), unless the recipe sets `gain` to place it, with a note saying why.
- **The manifest entry** is written by the tool, one per `.ogg` file (variants included) in `audio/manifest.json`, or the content folder's `assets.json`:

  ```json
  {"path": "audio/sfx/cast/variants/1.ogg", "origin": "ai", "author": "Claude", "license": "CC-BY-SA-4.0",
   "tier": "good", "tool": "tools/sound.py (procedural synthesis, generator 1)",
   "prompt": "audio/sfx/cast/cast.sound.json", "recipe_hash": "sha256:...", "loudness": -20.1, "peak": -3.2}
  ```

  `origin: ai` because Claude made it (docs/PLAN.md: Claude's assets are synthesised from code, and the manifest drives the Steam disclosure). `prompt` points to the recipe, which is the whole input. The tool never changes `tier` once it is set, so a rebake does not undo the owner's `final`.
- **The hash check:** `recipe_hash` is a sha256 of the recipe (canonical JSON), every patch it names and `GENERATOR` (the synth's version number, raised when a change to the synth changes its output). `tools/test_sound_hashes.py` walks every recipe and score and fails with the file and the command to run when a hash is stale or an `.ogg` has no recipe. It reads no audio, so it is fast and needs no ffmpeg, and it is run with the tools' tests. It does not ask the audio to be bit-exact across machines: `math.sin` may differ in its last bit between platforms, and Vorbis does too.

### 7. Auditioning

- **The contact sheet:** `tools/sound.py sheet <ids or a family>` writes one `.ogg` into the scratchpad (never committed): each sound's variants in turn with a gap, then four of it at once (four players), then the family together. It is attached to the PR, and the owner listens there.
- **The sound room** (`tools/sound_room.tscn`, run with `godot --path . res://tools/sound_room.tscn`, a `tools/` scene, never in a build): every sound id the game names (read from the cues, the enemies, `MusicTrack`s and `preset.hit_sound` through the registry) beside every id that has a file. Missing ones are shown red, and so are ids with a file that nothing names. A row plays the sound (each press a new variant) on its bus, or loops a held sound. A music track has a slider for its intensity, through the real `music.gd`. The bus volumes and a duck button are on the side. It is a check of the real game path, not a second synth.

## Steps

| Step | What | Done when |
| --- | --- | --- |
| **AU1** | This document; docs/STYLE.md "Sound" (targets, families, jitter); the ROADMAP line. | The owner approves. |
| **AU2** | **The tool.** `tools/sound.py` (`bake`, `sheet`, `check`), `sound_synth.py`, `sound_meter.py`, the recipe validator, the manifest writer and the hash test. Golden examples: the AU1 interview's three modern-synth samples remade as recipes (a whoosh, a fire hit, a glass ping), the meter against reference tones, a held loop's seam, a recipe's unknown key. `tools/README.md` is updated. | `python3 -m unittest discover -s tools` passes, and the three recipes bake and sound as the samples did. |
| **AU3** | **The game's side.** `core/audio` (buses, volumes, ducking, UI sounds, `length`), `default_bus_layout.tres`, the panning setting, `Registry` `.tres` sounds and `variants/`, Feel's voices and music on buses, a cue's `duck`, and the cast sound moved from `gameplay/player` to Feel. `audio/README.md` (the new shape, its example) and `core/README.md` are updated. | Tests: buses and volumes, the duck's most-wins and let-up, the UI voice cap, the registry with variants and the clash, a randomizer's length in `Sounds`, the cast sound on `spell_cast` from Feel and none from player.gd (`test_sim_rules` still clean). |
| **AU4** | **The sound room.** | It lists all 38 named ids red, then plays AU2's examples on the right buses. |
| **AU5** | **The core combat set:** `cast`, `hit`, `enemy_death`, `player_downed`, `revive`, `heal`, and `reaction_` + `current`, `discharge`, `douse`, `drown`, `flare`, `kindle`, `overload`, `rift`, `rime`, `shatter`, `squall`, `stillness`, `superconduct`, `thaw`. Patches shared by element (fire, frost, storm, void, water). | The contact sheet is on the PR, the owner has listened to it, and their changes are made. A four-player bot fight is recorded with sound. |
| **AU6** | **The rest of the effects, and held loops:** the Old Broom's sheet (docs/milestones/boss-old-broom.md, "Sound"), props (`pillar_*`, `dust_*`), `parry`, `deflect`, `shield_block`, `possess`, `enemy_spawn`/`materialize`, `room_start`, `self_hit`, `boss_intro`, and the held loops. | As AU5, and every held loop is heard looping in the sound room for 30 s with no click. |
| **AU7** | **Music:** `tools/sound_score.py`, then `boss_broom` + `boss_broom_fire`, and one crypt room track. | Layers are of one length (tested), loop with no click, and play through intensity in the sound room and in the fight. The owner listens. |
| **AU8** | **UI sounds and volumes:** the HUD's move, choose, back and deny sounds, the builder's card place and remove, the volume sliders in the pause menu. | The HUD sends only `ui_sound_requested`, and a test opens the menus and counts the requests. |
| **AU9** | **The owner's playtest** with sound, and promotion to `final` of what passes. | The owner's notes are done or in the backlog. |

## Rules for every step

- **View only.** Nothing under `core/audio`, the tool or Feel's sounds is read by the simulation. Sound never waits on anything and never makes anything wait.
- **No allocation per play.** Voices are made once (Audio's four UI voices, Feel's as now). A play sets a stream and plays.
- **Names are ours.** A recipe's `notes` describe the sound in plain words. No recipe, patch or note names another work, artist or franchise.
- **Smooth sound:** no click at a start, an end, a loop or a duck. Every change of level is a ramp (docs/STYLE.md, "Smooth", for the ear).
- **Every id the game names has a file by AU7's end,** and the sound room shows none red. After that, a new id ships with its sound.

## Open for later

- **Live synthesis** for a sound that follows the game (a beam's hum by its length, a charge's rising pitch) was asked about and not chosen. It would be a new view-only area with its own budget, planned when a card needs it.
- **Music beyond the boss and the crypt** (the hub, other biomes) comes with those biomes.
- **A manifest validator** for every asset is still docs/BACKLOG.md's own item. The hash test here covers only generated sound.
