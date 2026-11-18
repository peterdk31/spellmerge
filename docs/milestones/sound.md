# Sound: a generator for every sound the game asks for

**Status (2026-11-18): approved by the owner, who had the steps built one session each the same day. AU1 done (this document, PR #817). AU2 done (the tool; "Built (AU2)" below). AU3 done (the Audio service; "Built (AU3)" below). AU7 done (music: the sequencer, the Old Broom's two layers and the crypt rooms' track; "Built (AU7)" below).** Written with the owner in an owner session on 2026-11-18, after an interview and three style samples. Reviewed by a fresh-context agent against the code the same day. Its findings are written into the plan: the 45 ids, the cast sound on `staff_cast`, the sound room under `tests/`, ffmpeg in the tools' contract, a sound folder's own `assets.json`, the duck's own bus, momentary loudness and the peak margin, Godot's own `.import` files, the golden fingerprint, `random_pitch` as a scale, and content randomizers loaded lazily.

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

- **A pattern is one bar**, a line of steps per instrument; a layer plays its patterns in order, one a bar, and `bars` is how many it must play. A line's steps share its bar evenly (8 for eighths in 4/4, 16 for sixteenths), so lines of one pattern may differ; there is no `steps` key ("Built (AU7)").
- **One length:** every layer is `bars × beats × 60 / tempo` seconds, exactly that many samples. That is the rule `MusicTrack` already needs, because its layers start together and must stay together. The bake fails a score whose layers' patterns don't fill the bars.
- **Seamless:** a note that rings past the loop's end is added round to its start, and the `fx` run over the loop twice through, of which the second is kept, so the room's tail is heard at the start too (the same as rendering the whole layer twice and keeping the second, for half the work). Its `.import` has `loop` on.

**`.import` files are Godot's own.** For a new file the tool writes only `[params] loop=true` (for a loop), then runs Godot's import (`godot --headless --path . --import`), which fills in the `uid` and `dest_files`, and that is what is committed. A rebake never rewrites an existing `.import`, so there is no churn.
- **A layer is one id** (`boss_broom`, `boss_broom_fire`), as `MusicTrack.layers` and the room's `music` name them now. Nothing in the game changes for music but its bus.
- **Notes:** note names with octaves, `.` for a rest, `-` to hold, `x` for a hit, `+` between the notes of a chord. A line's token count sets its steps. Velocity is an instrument's optional key; swing was not needed ("Built (AU7)"). The sequencer is small on purpose; anything more is a patch.
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

- **Targets by family**, in docs/STYLE.md, "Sound": one-shots by their loudest momentary loudness (400 ms windows, BS.1770; most of them are shorter than the 3 s of short-term), loops and music by integrated loudness, and all by true peak. The bake measures each variant before encoding (the standard library can't decode Vorbis), places the sound on its family's target (or off it by the recipe's `gain`, with a note saying why) and fails a variant outside the window (±1 LU; "Built (AU2)"). Vorbis can overshoot a peak by up to about 1 dB, so the bake holds the peak 1 dB under the family's limit.
- **The manifest entry** is written by the tool, one per `.ogg` file (variants included), in an `assets.json` in the sound's own folder (`audio/sfx/<id>/assets.json`, as a content folder's). That gives one file a sound, so parallel PRs never edit one list, and `audio/manifest.json` keeps hand-made and commissioned audio. audio/README.md says this from AU2:

  ```json
  {"path": "audio/sfx/cast/variants/1.ogg", "origin": "ai", "author": "Claude", "license": "CC-BY-SA-4.0",
   "tier": "good", "tool": "tools/sound.py (procedural synthesis, generator 1)",
   "prompt": "audio/sfx/cast/cast.sound.json", "recipe_hash": "sha256:...", "audio_hash": "sha256:...",
   "loudness": -20.1, "peak": -6.2}
  ```

  `origin: ai` because Claude made it (docs/PLAN.md: Claude's assets are synthesised from code, and the manifest drives the Steam disclosure). `prompt` points to the recipe, which is the whole input. A rebake that leaves a file's audio the same (`audio_hash`, of its 16-bit samples, so another machine's encoder changes nothing) keeps its `tier`. One that changes it sets `final` back to `good` and prints so, because the owner promoted a sound they heard, not this one.
- **The hash check:** `recipe_hash` is a sha256 of the recipe (canonical JSON), every patch it names, its family's row of docs/STYLE.md (its target and jitter are baked in too; found in AU2's review) and `GENERATOR` (the synth's version number, raised when a change to the synth changes its output). `tools/test_sound_hashes.py` walks every recipe and score and fails with the file and the command to run when a hash is stale or an `.ogg` has no recipe. An `.ogg` with no recipe is allowed only when its manifest entry names another source: `origin: human` (a commissioned or contributed sound), or one of the seven ambience files made before the tool (three loops and four accents; the plan first said three loops, but the accents have no recipe either), listed by name in `tools/sound.py` (`UNRECIPED`, which the test reads) until AU6 remakes them as recipes, after which the list is empty and stays so. It reads no audio, so it is fast and needs no ffmpeg, and it is run with the tools' tests. It does not ask the audio to be bit-exact across machines: `math.sin` may differ in its last bit between platforms, and Vorbis does too.
- **A synth change can't slip past.** `GENERATOR` is raised by hand, so `tools/test_sound_golden.py` renders a few reference recipes (one per source and shaper) and compares each with a fingerprint kept in the test: its RMS each 10 ms, rounded to 0.001 (finer than first planned, so a small change to a filter is caught too; a platform's last bit is still far below it). A change to the synth that changes its sound fails the test until the fingerprints and `GENERATOR` are both updated, and then the hash test names every sound to rebake.

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
| **AU6** | **The rest of the effects, and held loops:** the Old Broom's sheet (docs/milestones/boss-old-broom.md, "Sound"), props (`pillar_*`, `dust_*`), `parry`, `deflect`, `shield_block`, `possess`, `enemy_spawn`/`materialize`, `room_start`, `self_hit`, `boss_intro`, and the held loops. The seven ambience files are remade as recipes (`audio/ambience/<id>/`; the three loops as `held`, the four accents as `sfx`), in the same ids, matching their character and levels, so every generated sound comes from the repository's own tool. | As AU5, every held loop is heard looping in the sound room for 30 s with no click, and the test's list of ambience loops with no recipe is empty. |
| **AU7** | **Music:** `tools/sound_score.py`, then `boss_broom` + `boss_broom_fire`, and one crypt room track. | Layers are of one length (tested), loop with no click, and play through intensity in the sound room and in the fight. The owner listens. |
| **AU8** | **UI sounds and volumes:** the HUD's move, choose, back and deny sounds, the builder's card place and remove, the Music, Sound and UI sliders in the pause menu's Audio tab. | The HUD sends only `ui_sound_requested`, and a test opens the menus and counts the requests. |
| **AU9** | **The owner's playtest** with sound, and promotion to `final` of what passes. | The owner's notes are done or in the backlog. |

## Built (AU2)

The choices the plan left open, as built (2026-11-18):

- **The files.** `tools/sound.py` (`bake`, `sheet`, `check`), `tools/sound_synth.py` (the validator and the synth, `GENERATOR` 1) and `tools/sound_meter.py`; their tests are `test_sound_synth.py`, `test_sound_meter.py`, `test_sound_bake.py`, `test_sound_golden.py` and `test_sound_hashes.py` (66 tests, about seven seconds). No sound is committed yet: AU4 bakes the fixtures and AU5 the first set.
- **The level is placed by the bake.** Rather than fail a recipe until its author has tuned its level by trial, the bake scales a sound's variants, all by one factor so they keep their small differences, until their mean is on the family's target (momentary or integrated, as docs/STYLE.md's table says; the table is read from there, so its numbers have one home). The ±1 LU window then holds each variant against that target, so a variant much louder or quieter than the others fails, and the peak is held 1 dB under the family's limit: a sound too spiky for its family fails with what to soften. A recipe's top-level `gain` (in dB) places it off the target, and its `notes` (which every recipe has) say why; that is the reviewer's to check, not the bake's. A held loop is measured as it plays, round and round over 3 s, not as if silence followed it (a 0.1 s loop measured once read 6 dB quiet, so it baked 6 dB loud; found in review). A layer's own `gain` is its level in the mix.
- **The recipe's keys.** A layer's `pitch` and an FM `index` are a number or a curve, `{"from", "to", "curve"}`, with `curve` `exp` (the default; `linear` for `index`), `linear` or `arch` (to `to` at the middle and back); a filter takes the same `from`, `to` and `curve` as its own keys, beside `type` and `q`. `amp` is either a `shape` (`flat`, `arch`, `perc`, `swell`) with `attack` and `power`, or an ADSR (`attack`, `decay`, `sustain`, `release`). `noise` is `color` `white` (no `pitch`) or `stepped` (sample and hold at `pitch` a second, which a band pass makes into crackles); an ADSR takes no `power`. A partial's `decay` is its time to -60 dB and its `gain` is in dB. `length` is a layer's own seconds (the rest of the sound by default). A key a layer's source does not use is an unknown key there. `variants` defaults to the family's count.
- **Patches** are `{"version": 1, "layer": {...}, "notes": "..."}`; a recipe's layer is merged over the patch's, object by object (`"pitch": {"to": 1300}` keeps the patch's `from`). A patch names no other patch.
- **Variants.** Variant n's seed is `vary.seed × 1000 + n`, which draws its pitch and time scales within `vary` and seeds its noise and its partials' phases.
- **Tails.** A one-shot with reverb is its `seconds` plus 0.5 s a unit of `size`, the tail faded out over its last part. A held sound renders a quarter of its `seconds` more (at most 1 s), crossfaded over its start with a fade that keeps the power steady for how alike the two parts are (equal power for noise, near equal gain for a tone), and in a held sound a steady pitch, its partials and its FM modulator are moved to the nearest whole number of cycles in the loop, so a tone runs on in phase through the fold (with plain equal power, found in review, a 997 Hz tone swelled 3 dB there and a 101 Hz one all but cancelled). The reverb (eight damped combs and four all-passes) is scaled to the dry sound's energy, so `mix` is the share heard whatever the room's size, and a tone does not jump in level by where it falls on the room's resonances (found tuning the glass, whose variants differed by 3 LU before).
- **Files.** The `.tres` names its variants by path (no `uid`) with `playback_mode = 0` (random, no repeats), `random_pitch = 1 + jitter` and `random_volume_offset_db`; Godot 4.7.2 loads it as written. A new held loop's `.import` is `[remap] importer="oggvorbisstr"` and `[params] loop=true`, and Godot 4.7.2's import keeps `loop=true` and fills in the rest. A file is rewritten only when its `audio_hash` (of its 16-bit samples) changes, so another machine's ffmpeg rewrites nothing and demotes nothing; the encode is bitexact too. (A rebake on a machine whose maths differs in the last bit may still change a sample and set a `final` back to `good`; the hash check never depends on the audio.) The Godot run is the pinned one in `build/godot`, or `$GODOT`; with neither, the bake says the command to run.
- **Where a recipe lives.** In a folder of its own named for its id, under `audio/` or as a content item's `sounds/<id>/`; anywhere else in the repository it is refused, so a bake never writes over a content item's own `.tres` or `assets.json`. Only the sheet takes a recipe outside the repository. A sound folder's `assets.json` is tab-indented, as the content folders' are.
- **The check** also validates every recipe, names a variant file the recipe no longer has, variants whose recipe is gone, and the files of a sound's old kind (a `.tres` beside a held sound, an `<id>.ogg` beside a one-shot); a bake removes those itself.
- **The sheet** plays each sound's variants with 0.4 s between them, then four at once (0, 23, 51 and 80 ms apart, cycling through the variants), then the first variant of every sound named, together; it is scaled down only if the sum would clip. The `.mp4` is a 1280×720 card listing the ids (ffmpeg's `drawtext`, plain if this ffmpeg has none) with AAC audio.
- **The three samples** are `SAMPLES` in `tools/test_sound_synth.py`: the whoosh (`combat`: a band-passed noise sweep 600 to 4100 Hz and back, a softer low-passed noise under it, an FM shimmer 500 to 1300 Hz at ratio 3.5, a 0.35 room), the fire hit (`combat`: a driven sine thump falling 150 to 45 Hz, a driven band of noise falling 1100 to 380 Hz, crackles of stepped noise thinning from 90 to 25 a second through a band at 3.2 kHz) and the glass ping (`big`: partials 1, 2.76, 5.4 and 8.9 of 1180 Hz, the higher ones quieter and shorter, a 15 ms high tick for the strike, a 1.5 room). Their tests hold each to its family, its partials or its shape.

## Built (AU3)

The choices the plan left open, as built (2026-11-18):

- **The move first, then the additions.** `gameplay/feel/sounds.gd` is gone: its voices are `core/audio/voices.gd` and its held slots `core/audio/held.gd`; `music.gd` moved to `core/audio/` unchanged but for its bus; the room ambience's bed and accent voices are `core/audio/ambience.gd`. Every case of the old tests is kept, checking the same things, and split: the machinery's in `tests/core/audio/` (`test_audio_voices.gd`, `test_audio_music.gd`, `test_audio_buses.gd`), Feel's decisions in `tests/gameplay/feel/test_feel_sounds.gd` and `test_room_ambience.gd`.
- **The over lane is its own call,** `Audio.play_over(id, volume, bus)`, not `play(..., bus = BUS_SFX)` as section 5 had it: a bus does not say whether a voice pauses, so the lane is named by the function. The UI's voices are on the same unpaused lane.
- **Handles.** `hold` returns a number never given twice (0 for none), and takes an earlier handle (`take`) to go on in its slot with no restart: Feel's `held_sounds.gd` keeps (caster, id, `Until`, key) to a handle, so "one held sound a caster and id" is still Feel's rule and Audio knows no caster. An entry lasts while its handle has a slot (held or fading), so a sound taken over while it fades goes on, as before.
- **Audio steps itself** (`_process`, its `World` child only while the tree is not paused); Feel no longer steps any player. Tests step it by hand (`step`, `step_world`).
- **The cast sound** is a world voice from where the cast left (`staff_cast`'s origin), where each seat's was a plain player of its own heard the same everywhere: the one change in what is heard, and the plan's own. It now shares the world's `VOICES` (at most `PER_SOUND` of `cast`), so four players casting fast hold up to three of the eight voices, and a busy frame's oldest sound gives way first. The id is Feel's `CAST_SOUND`.
- **Audio's own clock and registry.** Held seconds and the fades now run on Audio's `_process` delta; Feel's accents still run on Feel's real time (capped at 0.25 s a frame), so after a long hitch the two differ by the hitch. Sounds are asked of Audio's registry (the `Registry` autoload in the game, the same Feel reads), so a test that hands Feel a registry of its own hands its Audio the same one. A Feel leaving the tree silences what it started (`Audio.silence`), and an Audio starts and leaves every bus at its full level, since the engine's buses are shared by every Audio a test makes.
- **Volumes.** The four settings' saved keys are `AudioVolumes` (core/settings); they share `AmbienceVolume`'s stops and curve, so no second curve exists. Each bus eases at 4 shares a second (the ambience's old `VOLUME_RATE`), is written only while it moves (a test's own Audio is never fought), and is muted at 0% in place of stopping its players. The events exist and Audio hears them; only the ambience has a slider until AU8.
- **The duck** keeps up to 8 ducks; the deepest under way wins, the music coming down over 0.05 s and back up over 0.3 s from wherever it is. A cue's `duck` is checked from -24 to 0 dB, and Feel asks it for the cue's sound's length (`Audio.length_of`), so a cue whose sound has no file ducks nothing.
- **Panning:** every world voice's `panning_strength` is `Audio.PAN`, 1.0 (Godot's own default for a player, so nothing heard changed); the owner tunes it by ear.
- **Godot 4.7, checked:** `AudioStreamRandomizer.get_length()` is 0 (`AudioLength.of` is tested against it), and 4.7 has both `random_pitch` and `random_pitch_semitones`. docs/STYLE.md gives pitch jitter in percent, so AU2's `.tres` uses `random_pitch` (1.04 for ±4%).
- **The registry** reads `.ogg` and `.tres` sounds under `audio/` and under any content item's `sounds/` folder (audio's first, then content's, each in path order), never a file under `variants/`; the content scan of `.tres` skips `sounds/` folders. A clash is a warning and a line of `Registry.sound_clashes()`, and `tests/core/test_registry.gd` fails on any in the game's files.
- **A `.tres` is taken as a sound by where it is** (under `audio/` or a `sounds/` folder), not by loading it: a `.tres` there that is no `AudioStream` is an id whose `get_sound` is null. Only sounds belong in those folders (audio/README.md).
- **`test_sim_rules`** names any `Audio`, `AudioServer` or `AudioStreamPlayer` on a line of a simulation script.

## Built (AU7)

The choices the plan left open, as built (2026-11-18):

- **The files.** `tools/sound_score.py` (the sequencer, `VERSION` 1) and its tests, `tools/test_sound_score.py` (37 tests, with a fingerprint of a reference score (holds over a bar, a chord, a note on a pitch curve, the room and the low pass) that guards the sequencer's sound as `test_sound_golden.py` guards the synth's); `tools/sound.py` bakes, checks and sheets scores beside recipes. `sound_synth.py` gained `validate_layer`, `render_layer` and `apply_fx`, split out of what it had, with no change in its sound (`GENERATOR` stays 1, its fingerprints pass). In the game: `tests/content/test_music.gd`.
- **A score.** `version`, `tempo`, `beats`, `bars`, `key` (words only), `instruments`, `patterns`, `layers`, `fx` (a recipe's: reverb, low pass), `gain` and `notes`. An instrument is a synth layer (a `patch` and its own keys over it, merged as in a recipe) plus `ring` (seconds a note sounds past its last held step, so a pluck or a pad's release is heard) and `velocity` (levels 0 to 1, one a step of its line, round again: the hi-hat's accents). A note sets the instrument's pitch; on a pitch curve it keeps the curve's shape from that note (a kick played as `x` keeps its own fall). An instrument takes no `start` or `length` (a note's are the score's), and every note is checked as the synth will play it, so a note out of the synth's range (`C0`, or a kick's fall played too low) fails with its line. A layer is `id`, `play` (a pattern a bar) and an optional `gain` (dB, its level in the track) and `notes`. A line's steps are 1, 2, 3, 4, 6, 8, 12, 16, 24 or 32, so a typo of 7 fails; a hold carries over a bar, but not past a rest or a bar with no line for that instrument; at most 4 layers (`MusicTrack.LAYERS_MOST`); no note rings longer than the loop. **Swing was not built**, as no track needs it. Every check names its key.
- **Notes are rendered once a pattern.** A note's seed is its layer, pattern, instrument, step and chord note, so a pattern played again is the same (its noise too) and is rendered once; a bar never sounds unlike its pattern by chance. A pattern that should vary is another pattern.
- **One scale a track.** The bake renders every layer, sums them, and scales all by one factor until the sum, measured as it plays round, is on the music row's target (plus the score's `gain`); each layer keeps its place in the mix, so a stacked track's first intensity is quieter than its last, as it should be. **A score is a stacked track** (`MusicTrack.stacked`): the bake checks the true peak of every intensity (its first n layers together) and of each layer alone, held 1 dB under the row's limit, and the sheet plays the intensities; a track of entries (`stacked = false`) would need each entry placed alone, which no track needs yet, so a score cannot say it. Each layer's own loudness and peak go in its manifest entry. Its hash is `recipe_hash`, of the score, its patches, the music row, `GENERATOR` and the sequencer's `VERSION`.
- **Mono**, as the effects are: the game's music players are not placed, so stereo would only have widened the pad, and the room's own reverb carries the space.
- **The music's level is lowered to -23 LUFS integrated** (docs/STYLE.md, the `music` row; it was -18). At -18 the music, whole files at that average, sat over the combat family's -20 momentary (the loudest 400 ms of a hit), against the plan's "under the effects". At -23 a track's loudest 400 ms is -19 to -21.5 LUFS momentary (the broom's first layer, both, the crypt's), about a cast's, and its average 3 to 4 LU under that; the bus volume (AU8) and the duck (AU3) are on top.
- **The sheet** plays a track's intensities as a stacked track does: its first layer, then the first two, each round its loop twice.
- **The patches** (`audio/patches/`): `warm_pad` (partials 1 and 1.005 beating slowly, softer harmonics, low-passed, a slow ADSR), `glass_pluck` (the glass of AU2's ping as an instrument: partials 1, 2.76, 5.4), `fm_bass`, `sub_bass` (a low-passed triangle drone), `soft_kick`, `soft_snare`, `brush` (a short band of high noise: the hi-hat, bristles on stone), `ember_crackle` (stepped noise through a band at 3.2 kHz) and `fire_lead` (a driven saw with a closing low pass). Their names and notes say the sound only.
- **`boss_broom`** (`audio/music/boss_broom/`): D minor, 100 beats a minute, 16 bars (38.4 s round): Dm Bb Gm A twice, Gm Dm Eb A, Dm Bb Gm A. The first layer is a brushed tick on sixteenths over a rocking FM bass, a kick on 1 and 3, the warm pad and a glass bell tune that changes each four bars. The second, `boss_broom_fire` (phase 2, the head burning), adds a snare on 2 and 4, kicks between the first layer's, a quiet crackle of embers and a running sixteenth arpeggio on the hot saw, in the same chords. Its first intensity is -25 LUFS, both -23. The data was there (`old_broom.tres`: two stacked layers, phase 2 raises the intensity); nothing in it changed.
- **`crypt_halls`** (`audio/music/crypt_halls/`): A minor, 80 beats a minute, 16 bars (48 s): Am F Dm E (Fmaj7, Dm with an added ninth, E7), a glass arpeggio over the pad, a low drone, a quiet heartbeat kick and a brushed off-beat, in a wide room. One layer, `content/rooms/crypt/crypt_music.tres` (fade 2 s), named as `music` by the four crypt fight rooms (`arena_01` to `arena_04`), which had none. **The broom's hall names none:** its boss brings its music (boss plan decision 17), and its room's would only play under the intro and after the run is won.
- **Balanced by measurement, not by ear.** Each instrument's share was set from its level alone and in three bands (under 100 Hz, all, over 3 kHz) and from spectrograms: the first renders were boomy (the drone and the kick 5 dB over the melody), so the low parts came down and the glass and the brush up. **The owner should listen**, on the contact sheet and in the fight.
- **In the real fight** (a check run once on the game itself after AU3's merge, through `Audio.music` on the `MusicDuck` bus; not kept): in `arena_01` the music is `crypt_halls`; in the broom's hall `boss_broom` alone at intensity 1, then, hurt under 55%, intensity 2 with `boss_broom_fire` faded fully in over the track's 1.5 s. The kept test (`tests/content/test_music.gd`) holds what Godot imports and the data names, for every track of every room and enemy: each layer with a file is an Ogg Vorbis imported to loop, a track's layers are of one length, a boss's phases bring in every layer of its music, and the crypt's fight rooms name music. The sound room's check (AU4) comes when it is built.
- **Not built, from the review:** a recipe whose id is a track's, in the track's folder, would clash with the score's files (no such id exists); the Godot test's phase rule copies `BodySounds.intensity_of`, which needs a live body. **Every id the game names has a file by AU7's end** (Rules) is not met by this step alone: AU5 and AU6 make the effects, which are being built apart; the two music ids are no longer silent.

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
