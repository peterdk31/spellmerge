# Sound: a generator for every sound the game asks for

**Status (2026-11-18): written with the owner, waiting for approval.** AU1 (this document) is up for review. Written with the owner in an owner session on 2026-11-18, after an interview and three style samples. Reviewed by a fresh-context agent against the code the same day. Its findings are written into the plan: the 45 ids, the cast sound on `staff_cast`, the sound room under `tests/`, ffmpeg in the tools' contract, a sound folder's own `assets.json`, the duck's own bus, momentary loudness and the peak margin, Godot's own `.import` files, the golden fingerprint, `random_pitch` as a scale, and content randomizers loaded lazily.

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
12. **One central place:** every player and all playback machinery are in `core/audio`; Feel only decides what plays (section 5).
13. **The first batch is the core combat set:** `cast`, `hit`, `enemy_death`, `player_downed`, `revive`, `heal` and the fourteen reactions.
14. **Tier `good`** in the manifest; the owner promotes a sound to `final` after listening.

The steps are **AU1 to AU9** (AU for audio). Each is one PR with its tests, in order.

## What is there today

The game already plays sound; it has no files.

- **`gameplay/feel/sounds.gd`** plays one-shots and held sounds by id. It has eight `AudioStreamPlayer2D` voices, at most three per id, and 16 held slots that follow a body and fade out over 0.12 s. Feel caps a frame's hit sounds at half the voices.
- **`gameplay/feel/music.gd`** plays a `MusicTrack`: its layers start together, each fades in at its intensity, and one track crossfades into the next.
- **`gameplay/feel/body_sounds.gd`** picks a boss's held phase sounds and its music. **`gameplay/feel/boss_intro_sound.gd`** plays the intro's cues while the tree is paused.
- **`Registry.get_sound(id)`** finds `<id>.ogg` anywhere under `audio/`. A missing id is silent.
- **45 ids were named and silent when this was written:** 37 cues' and phases' `sound` (`broom_burning` among them), the `held` parts' sounds (`broom_scrape`, `broom_big_scrape`, `broom_swish`), `death_sound` (`broom_splinter`), `preset.hit_sound` (`hit`), the cast sound and the boss's two music layers (`boss_broom`, `boss_broom_fire`). The sound room counts them from the data (section 7), so this number is never kept by hand.
- **The cast sound breaks the rule.** `gameplay/player/player.gd` (`_play_cast_sound`) plays it from a simulation area with its own player, on every cast. It moves to Feel, which hears `staff_cast` (sent on every cast, where `spell_cast` is sent only for a cast with a carrier card). The `_sound_player` member, its `VIEW` entry and gameplay/player/README.md's line on it go (AU3).
- **The room's ambience** (atmosphere D, docs/milestones/atmosphere.md) is built: `gameplay/feel/room_ambience.gd` plays a room's `Ambience` (looping layers and random accents) on players of its own. Its three loops in `audio/ambience/` were made by a numpy generator kept out of the repository, with tier `placeholder`. Its volume (`ambience_volume`, core/settings) scales its own players, because there were no buses. The pause menu has an Audio tab with that one slider, and the atmosphere doc leaves buses and the other volumes to a later plan: this one.
- **All sound is on the Master bus.** The only volume setting is ambience's, and there is no shared way for the HUD to make a sound (docs/BACKLOG.md, "Sounds and effects by id only in `feel`").

Nothing here changes how the game plays. Every part of this plan is view only: no state, no tick, no hash. A sound's choice of variant and its jitter use the engine's own random numbers, which is allowed because nothing in the simulation hears them.

## The parts

```
tools/sound.py              the command: bake, sheet, check
tools/sound_synth.py        the synth: sources, envelopes, filters, drive, reverb; stdlib only
tools/sound_score.py        the sequencer: a score into one buffer a layer, each exactly one loop long
tools/sound_meter.py        loudness (BS.1770 K-weighted, gated) and true peak
tools/test_sound*.py        their tests (`python3 -m unittest discover -s tools`); their recipes are dicts in the tests
tests/sound_room/           the sound room (AU4) and its fixture sounds; tests/ is never exported

audio/patches/*.patch.json  shared instruments and layers (a "glass", a "whoosh"), named by recipes
audio/sfx/<id>/             a sound: <id>.sound.json, <id>.tres, variants/1.ogg ... n.ogg
audio/music/<track>/        a track: <track>.score.json, one .ogg per layer
content/<...>/sounds/<id>/  a sound of one content item, the same shape, listed in that folder's assets.json

core/audio/                 the Audio service (AU3): every voice, held sound and music player, buses, volumes, ducking
default_bus_layout.tres     Master > Music > MusicDuck, SFX, UI
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
- **Every number is checked.** A key the synth does not know, a value out of range or a missing patch fails the bake with the file and the key. The synth reads only JSON and `audio/patches/`, and writes only in the recipe's folder: the `.ogg` files, the `.tres` and the folder's `assets.json` (section 6).
- **Python's standard library, plus ffmpeg to bake.** The synth uses `math`, `array` and `random.Random(seed)`, as the other tools do, and no numpy. Encoding Vorbis needs `ffmpeg` with libvorbis, which is new to the tools' contract (tools/README.md: git and Python only). AU2 writes the exception into tools/README.md: ffmpeg is needed by `bake` and `sheet` only, never by `check` or a test, and a missing ffmpeg stops the bake with what to install. A bake is offline and takes seconds.
- **Clicks are bugs.** Every layer starts and ends at zero (at least a 2 ms ramp, enforced by the synth), and the bake fails a variant whose first or last sample is not near zero.

### 2. Kinds

- **`sfx`**: a one-shot, as above.
- **`held`**: a loop for a held sound (`broom_burning`, a cue's `held` part). The tool renders `seconds` plus a tail and folds the tail back over the start, so the file loops with no click and no gap. Its `.import` has `loop` on (below). A held sound has one variant, because a loop that changes file mid-loop clicks.
- **`ui`**: a one-shot on the UI bus. It is quieter, never reverberant, and under 0.15 s.
- **Music** is not a `.sound.json` (section 4).

### 3. Variants and jitter in the game

The tool writes `<id>.tres`, an `AudioStreamRandomizer` naming `variants/1.ogg` to `n.ogg`, with `playback_mode` RANDOM_NO_REPEATS, and `random_pitch` and `random_volume_offset_db` from the family (docs/STYLE.md, "Sound"). `random_pitch` is a scale, with a play's pitch drawn between 1/r and r, so ±4% is `random_pitch = 1.04`; AU3 checks whether 4.7 has `random_pitch_semitones` and uses whichever says the table's number plainly. Godot then picks a variant and jitters it on every play, with no code of ours. Four casts in a row, or four players casting at once, never sound like one file played four times.

- **`Registry` learns `.tres` sounds, and content folders' sounds.** It scans only `audio/` today, although audio/README.md says a single item's sound lives in its content folder; AU3 adds a content folder's `sounds/` to the scan. Under either, a `<id>.tres` that is an `AudioStream` is the sound `<id>`. Files under a `variants/` folder are never ids of their own. The content scan, which loads every `.tres` at start (`_read_folder`), skips `sounds/` folders, so their variants load when first asked for, as `audio/`'s do. An `.ogg` and a `.tres` with one id is a registry warning and a test failure. This is a `core/registry` change, with its test (AU3).
- **A sound's length is its longest variant.** A voice is held for its stream's `get_length()`, and a randomizer's length is 0. `AudioLength.of(stream)` (a static function in core/audio) returns the longest variant's length, and the voices use it. AU3 checks what Godot 4.7 returns and tests it.
- **Held sounds and music layers** are plain `.ogg` files, as now.

### 4. Music: a score a track

`audio/music/<track>/<track>.score.json`:

```json
{
  "version": 1,
  "tempo": 96, "beats": 4, "bars": 4, "key": "D minor",
  "instruments": {"pad": {"patch": "warm_pad"}, "pluck": {"patch": "glass_pluck"}, "kick": {"patch": "soft_kick"}},
  "patterns": {
    "a": {"pluck": "D4 . F4 . A4 . C5 .", "pad": "D3 - - - - - - -"},
    "b": {"pluck": "C5 . A4 . F4 . E4 .", "pad": "A2 - - - - - - -"},
    "beat": {"kick": "x . . . x . . ."},
    "fill": {"kick": "x . x . x x x x"}
  },
  "layers": [
    {"id": "boss_broom", "play": ["a", "a", "b", "a"]},
    {"id": "boss_broom_fire", "play": ["beat", "beat", "beat", "fill"]}
  ]
}
```

- **A pattern is one bar**, a line of steps per instrument; a layer plays its patterns in order, one a bar, and `bars` is how many it must play.
- **One length:** every layer is `bars × beats × 60 / tempo` seconds, exactly that many samples. That is the rule `MusicTrack` already needs, because its layers start together and must stay together. The bake fails a score whose layers' patterns don't fill the bars.
- **Seamless:** each layer is rendered twice through, and the second pass is kept, so notes that ring past the loop's end are heard at its start. Its `.import` has `loop` on.

**`.import` files are Godot's own.** For a new file the tool writes only `[params] loop=true` (for a loop), then runs Godot's import (`godot --headless --path . --import`), which fills in the `uid` and `dest_files`, and that is what is committed. A rebake never rewrites an existing `.import`, so there is no churn.
- **A layer is one id** (`boss_broom`, `boss_broom_fire`), as `MusicTrack.layers` and the room's `music` name them now. Nothing in the game changes for music but its bus.
- **Notes:** note names with octaves, `.` for a rest, `-` to hold, `x` for a hit. A pattern is one bar per eight steps by default, or `steps` sets it. Velocity and swing are optional keys. The sequencer is small on purpose; anything more is a patch.
- The plan's honest limit stands (docs/PLAN.md, "Art and music"): this music is `good` until the owner says otherwise, and a commissioned soundtrack may replace it, id for id.

### 5. The Audio service (`core/audio`): every way of playing a sound

**The owner (2026-11-18):** "You should move Feel's audio stuff into the new Audio service. One central place for all audio related functions."

`core/audio/` (autoload `Audio`) is view only, has no tick and is not hashed. It is the only code in the game that makes or drives an `AudioStreamPlayer`. Everything else asks it. The line between it and Feel is **how against what**:

- **Audio knows how to play.** That means voices, caps, held slots and fades, music layers, buses, volumes, ducking, variants and panning. It knows nothing of bodies, spells, cues, phases or rooms: a held sound follows a `Node2D` it is handed, and ends when it is told to, when its seconds run out or when that node leaves the tree.
- **Feel decides what to play and when.** It reads a hit's or a cue's sound and its `duck`, caps a frame's hit sounds, picks the body to follow, lets a held sound go when its wind-up or carrier ends (`Spells.is_winding`, `end_carrier`; read by Feel each frame), and picks the boss's music from its phase (`body_sounds.gd`). These are gameplay facts, and core never depends on gameplay.

**What moves (AU3):**

| Now | In `core/audio/` |
| --- | --- |
| `gameplay/feel/sounds.gd`: the one-shot voices, `PER_SOUND`, oldest-first stealing | `voices.gd`: `play(id, at, volume, bus) -> int`, `stop(voice)` |
| `sounds.gd`: the held slots, follow, fade, `HELD_SLOTS` | `held.gd`: `hold(id, follow, at, seconds, volume, bus) -> int` (a handle), `release(handle)`, `release_all()`. The `Until` kinds, `end_carrier` and `release(caster, until)` stay in Feel, as a small `held_sounds.gd` that maps a caster and key to Audio's handles. |
| `gameplay/feel/room_ambience.gd`'s players (its layers and accents) | `ambience.gd`: `play_bed(ambience)`, on the `Ambience` bus; Feel keeps hearing `room_entered` and choosing the room's `Ambience`, and the accents' timing stays Feel's. `RoomAmbience.set_volume` goes: the setting becomes the bus's. |
| `gameplay/feel/music.gd`: layers, intensity, crossfade | `music.gd`: `play_track(track, intensity)`, unchanged in behaviour |
| `gameplay/feel/boss_intro_sound.gd`'s own players | Audio's **unpaused lane**: `play(..., bus = BUS_SFX)` on voices that keep playing while the tree is paused. Feel's node keeps the timing (the dark and reveal cues), with no player of its own. |
| `gameplay/player/player.gd`'s `_sound_player` (the cast sound, in a simulation area) | Feel hears `staff_cast` (every cast) and calls `Audio.play(&"cast", ...)`, so the player has no player. |
| `tests/gameplay/feel/test_feel_sounds.gd` | split into `tests/core/audio/` (the machinery) and a Feel test for the decisions (`Until`, the hit cap, the body followed) |

**Two lanes.** World sounds (one-shots, held sounds, music) are paused with the tree, as now, under a pausable child of Audio. The **over** lane (UI sounds, the boss intro) never pauses. A world voice is an `AudioStreamPlayer2D`, so it pans and falls off by its place from the picture's middle, as now. An over voice is a plain `AudioStreamPlayer`. Feel calls `Audio.clear_world()` where it clears its own sounds now (a room's or a run's end).

**How it is reached.** Feel and the sound room are handed Audio as Feel is handed the registry now (`audio: Node`, set where Feel is made), so tests can use their own. The HUD never calls it: it sends `Events.ui_sound_requested(id)` (core/events, new), and Audio hears it. The simulation never reaches it, and `test_sim_rules` gains a line that names any `Audio` or `AudioStreamPlayer` in a simulation folder.

**What Audio adds:**

- **Buses:** `default_bus_layout.tres` (project root, named in `project.godot`): Master > `Music` > `MusicDuck`, `SFX`, `Ambience` and `UI`. `Audio.BUS_MUSIC`, `BUS_SFX`, `BUS_AMBIENCE` and `BUS_UI` are the names, so no other script writes a bus name. The music players are on `MusicDuck`: its volume is the duck's alone, and `Music`'s is the player's setting, so the two never fight over one number. There is no boss bus: nothing needs to set the boss's sounds apart yet.
- **Volumes:** four machine settings, Music, Sound, Ambience and UI, made as `ambience_volume` already is (0 to 100% by 10, a perceptual curve, `AmbienceVolume.share_of`): their numbers in `core/settings`, saved through `SaveFile.set_setting`, and each change sent by the menu as its own `*_volume_changed` event that Audio applies to its bus. `ambience_volume` keeps its name and saved value, and only where it is applied moves. They are the machine's, not a run's rules, because they change nothing in the simulation. The pause menu's Audio tab shows them (AU8), beside the ambience slider it has now.
- **Ducking:** `Audio.duck(decibels, seconds)`. It lowers `MusicDuck` by the most asked for, over 0.05 s, and lets it back up over 0.3 s once the seconds are out: a ramp both ways, never a step. A cue asks for it with a new key, `duck: -6.0` (`CueBase` and content/cues/README.md, AU3), which Feel passes on when it plays the cue's sound. A reaction or a boss's slam ducks the music through data.
- **UI sounds:** four over-lane voices on the UI bus, at most one per id per frame.
- **Variants:** `AudioLength.of(stream)`, a randomizer's longest variant, which the voices use to hold a voice (section 3).
- **Panning:** a gentle pan by place. Audio sets each world voice's own `panning_strength` (`PAN`, a constant; Godot's project default of 0.5 stays), so a sound at the screen's edge is mostly, never wholly, on one side. AU3 starts `PAN` at 1.0 and the owner tunes it by ear.
- **Nothing is allocated per play:** every voice is made in `_ready`, as Feel's are now.

### 6. Loudness and the manifest

- **Targets by family**, in docs/STYLE.md, "Sound": one-shots by their loudest momentary loudness (400 ms windows, BS.1770; most of them are shorter than the 3 s of short-term), loops and music by integrated loudness, and all by true peak. The bake measures each variant before encoding (the standard library can't decode Vorbis) and fails it outside its family's window (±1 LU), unless the recipe sets `gain` to place it, with a note saying why. Vorbis can overshoot a peak by up to about 1 dB, so the bake holds the peak 1 dB under the family's limit.
- **The manifest entry** is written by the tool, one per `.ogg` file (variants included), in an `assets.json` in the sound's own folder (`audio/sfx/<id>/assets.json`, as a content folder's). That gives one file a sound, so parallel PRs never edit one list, and `audio/manifest.json` keeps hand-made and commissioned audio. audio/README.md says this from AU2:

  ```json
  {"path": "audio/sfx/cast/variants/1.ogg", "origin": "ai", "author": "Claude", "license": "CC-BY-SA-4.0",
   "tier": "good", "tool": "tools/sound.py (procedural synthesis, generator 1)",
   "prompt": "audio/sfx/cast/cast.sound.json", "recipe_hash": "sha256:...", "loudness": -20.1, "peak": -3.2}
  ```

  `origin: ai` because Claude made it (docs/PLAN.md: Claude's assets are synthesised from code, and the manifest drives the Steam disclosure). `prompt` points to the recipe, which is the whole input. A rebake that leaves a file's audio the same keeps its `tier`. One that changes it sets `final` back to `good` and prints so, because the owner promoted a sound they heard, not this one.
- **The hash check:** `recipe_hash` is a sha256 of the recipe (canonical JSON), every patch it names and `GENERATOR` (the synth's version number, raised when a change to the synth changes its output). `tools/test_sound_hashes.py` walks every recipe and score and fails with the file and the command to run when a hash is stale or an `.ogg` has no recipe. An `.ogg` with no recipe is allowed only when its manifest entry names another source: `origin: human` (a commissioned or contributed sound), or one of the three ambience loops, listed by name in the test until AU6 remakes them as recipes, after which the list is empty and stays so. It reads no audio, so it is fast and needs no ffmpeg, and it is run with the tools' tests. It does not ask the audio to be bit-exact across machines: `math.sin` may differ in its last bit between platforms, and Vorbis does too.
- **A synth change can't slip past.** `GENERATOR` is raised by hand, so `tools/test_sound_golden.py` renders a few reference recipes (one per source and shaper) and compares each with a fingerprint kept in the test: its RMS each 10 ms, rounded to 0.01. A change to the synth that changes its sound fails the test until the fingerprints and `GENERATOR` are both updated, and then the hash test names every sound to rebake.

### 7. Auditioning

- **The contact sheet:** `tools/sound.py sheet <ids or a family> --out <dir>` writes, outside the repository (never committed), one `.ogg` and the same audio as an `.mp4` over a still card of the ids in order, because GitHub takes no `.ogg` as an attachment. It holds each sound's variants in turn with a gap, then four of it at once (four players), then the family together. The `.mp4` is attached to the PR, and the owner listens there.
- **The sound room** (`tests/sound_room/sound_room.tscn`, run with `godot --path . res://tests/sound_room/sound_room.tscn`; under `tests/`, which `export_presets.cfg` leaves out of every build, because tools/ allows no scenes and is exported): every sound id the game names (read from the cues, the enemies, `MusicTrack`s and `preset.hit_sound` through the registry) beside every id that has a file. Missing ones are shown red, and so are ids with a file that nothing names. A row plays the sound (each press a new variant) on its bus, or loops a held sound. A music track has a slider for its intensity, through Audio's real `music.gd`. The bus volumes and a duck button are on the side. It is a check of the real game path, not a second synth.

## Steps

| Step | What | Done when |
| --- | --- | --- |
| **AU1** | This document; docs/STYLE.md "Sound" (targets, families, jitter); the ROADMAP line. | The owner approves. |
| **AU2** | **The tool.** `tools/sound.py` (`bake`, `sheet`, `check`), `sound_synth.py`, `sound_meter.py`, the recipe validator, the manifest writer and the hash test. Golden examples: the AU1 interview's three modern-synth samples remade as recipes (a whoosh, a fire hit, a glass ping), the meter against reference tones, a held loop's seam, a recipe's unknown key. Also the golden fingerprint test. `tools/README.md` (the sound tools, and ffmpeg for baking) and `audio/README.md` (its allowed files: `.tres`, `.sound.json`, `.patch.json`, `.score.json` and a sound folder's `assets.json`) are updated. The three recipes are dicts in the tests, since tools/ takes no `.json`. | `python3 -m unittest discover -s tools` passes, and the three recipes bake and sound as the samples did (a contact sheet on the PR). |
| **AU3** | **The Audio service.** `core/audio` with Feel's voices, held slots and music moved into it (section 5's table), the boss intro's and the player's players gone, two lanes, buses (`default_bus_layout.tres`), volumes, `duck`, UI sounds, `length`, the panning setting, `Registry` `.tres` sounds, content `sounds/` and `variants/`, and a cue's `duck`. A move first, with no change in what is heard, then the additions. `audio/README.md` (the new shape, its example), `core/README.md` `gameplay/feel/README.md` and docs/milestones/atmosphere.md (its "on the node, not a bus" line, now buses) are updated. | `test_feel_sounds.gd`'s cases pass, split between `tests/core/audio/` and Feel. New tests: buses and volumes, the duck's most-wins and let-up, the UI voice cap, the over lane playing while paused, the registry with variants and the clash, a randomizer's length, the cast sound coming from Feel on `staff_cast`, a cast with no carrier card included, and `test_sim_rules` naming audio in a simulation folder. |
| **AU4** | **The sound room**, with fixture sounds under `tests/sound_room/fixtures/` (AU2's three examples baked, a held loop, a two-layer track). | It lists every named id from the data (45 today, all red), and plays, loops, ducks and steps the fixtures' intensity on the right buses. |
| **AU5** | **The core combat set:** `cast`, `hit`, `enemy_death`, `player_downed`, `revive`, `heal`, and `reaction_` + `current`, `discharge`, `douse`, `drown`, `flare`, `kindle`, `overload`, `rift`, `rime`, `shatter`, `squall`, `stillness`, `superconduct`, `thaw`. Patches shared by element (fire, frost, storm, void, water). | The contact sheet is on the PR, the owner has listened to it, and their changes are made. A four-player bot fight is recorded with sound. |
| **AU6** | **The rest of the effects, and held loops:** the Old Broom's sheet (docs/milestones/boss-old-broom.md, "Sound"), props (`pillar_*`, `dust_*`), `parry`, `deflect`, `shield_block`, `possess`, `enemy_spawn`/`materialize`, `room_start`, `self_hit`, `boss_intro`, and the held loops. The three ambience loops are remade as `held` recipes (`audio/ambience/<id>/`), in the same ids, matching their character and levels, so every generated sound comes from the repository's own tool. | As AU5, every held loop is heard looping in the sound room for 30 s with no click, and the test's list of ambience loops with no recipe is empty. |
| **AU7** | **Music:** `tools/sound_score.py`, then `boss_broom` + `boss_broom_fire`, and one crypt room track. | Layers are of one length (tested), loop with no click, and play through intensity in the sound room and in the fight. The owner listens. |
| **AU8** | **UI sounds and volumes:** the HUD's move, choose, back and deny sounds, the builder's card place and remove, the Music, Sound and UI sliders in the pause menu's Audio tab. | The HUD sends only `ui_sound_requested`, and a test opens the menus and counts the requests. |
| **AU9** | **The owner's playtest** with sound, and promotion to `final` of what passes. | The owner's notes are done or in the backlog. |

## Rules for every step

- **View only.** Nothing under `core/audio`, the tool or Feel's sounds is read by the simulation. Sound never waits on anything and never makes anything wait.
- **No allocation per play.** Every voice is Audio's, made once. A play sets a stream and plays.
- **Names are ours.** A recipe's `notes` describe the sound in plain words. No recipe, patch or note names another work, artist or franchise.
- **Smooth sound:** no click at a start, an end, a loop or a duck. Every change of level is a ramp (docs/STYLE.md, "Smooth", for the ear).
- **Every id the game names has a file by AU7's end,** and the sound room shows none red. After that, a new id ships with its sound.

## Open for later

- **Live synthesis** for a sound that follows the game (a beam's hum by its length, a charge's rising pitch) was asked about and not chosen. It would be a new view-only area with its own budget, planned when a card needs it.
- **Music beyond the boss and the crypt** (the hub, other biomes) comes with those biomes.
- **A manifest validator** for every asset is still docs/BACKLOG.md's own item. The hash test here covers only generated sound.
