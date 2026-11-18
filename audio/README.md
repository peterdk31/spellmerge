# Audio

## Purpose

Shared sound used by more than one thing: music (`music/`), sound effects (`sfx/`) and the rooms' sound under the music (`ambience/`: the loops and accents an `Ambience` names, docs/milestones/atmosphere.md, D). Sound that belongs to a single item (a spell's cast sound) lives in that item's folder under `content/`, not here.

## Contract

- Audio depends on nothing. It holds files only, no logic.
- **`.ogg` only.** No `.wav`, `.mp3` or other formats.
- Every asset has an entry in `audio/manifest.json` (see below), or, for the sounds of one content folder, in an `assets.json` in that folder in the same shape. A generated sound's entries are in an `assets.json` in its own folder, written by the tool (below).
- Loop music and ambience loops must loop without a click, and are imported to loop (`loop=true` in their `.import`). An ambience accent (a drip, a gust) starts and ends at silence and is not imported to loop. Keep sound effects short, low (docs/STYLE.md, "Sound": deep, never piercing) and balanced in volume with the others.
- Names are original. No ripped game audio, no samples of other works.
- Audio is CC-BY-SA-4.0 by default. A file may instead declare CC0-1.0 or CC-BY-4.0 with a `<file>.license` file (AGENTS.md, hard rules).

## Sound ids

A sound's id is its file's name (`zap` for `audio/sfx/zap.ogg`; the registry finds it anywhere under `audio/`, and under any `sounds/` folder of a content item, for a single item's sound). A sound may instead be `<id>.tres`, an `AudioStreamRandomizer` naming its baked variants in a `variants/` folder beside it (`audio/sfx/<id>/<id>.tres`, `variants/1.ogg` ...; docs/milestones/sound.md, section 3): Godot picks a variant and jitters its pitch and volume on every play, and nothing under `variants/` is an id of its own. An `.ogg` and a `.tres` of one id is a registry warning and a test failure. Cues (`content/cues`: a cue's `sound`, a `held` part's), enemy data (`death_sound`, its phases' held `sound`) and music tracks (`MusicTrack.layers`, as a room's or an enemy's `music`) name them; an id with no file is silent, so the game names its sounds before they are made (boss plan OB15). Every sound plays through the Audio service (core/audio), on its bus of `default_bus_layout.tres`: the music on `MusicDuck` (under `Music`), effects on `SFX`, the rooms' sound on `Ambience`, the menus' on `UI`; each bus has its volume setting. A held sound loops while its moment lasts (the player restarts it), and a music track's layers start together, so make the layers of one track the same length. The Old Broom fight's ids are the boss plan's sound sheet (docs/milestones/boss-old-broom.md, "Sound").

## Allowed files

`.ogg` audio, plus Godot's `.import` files, `.license` files and the manifest; and for generated sound (sound plan, docs/milestones/sound.md) a sound's recipe (`<id>.sound.json`), the `AudioStreamRandomizer` of its variants (`<id>.tres`), a sound folder's `assets.json`, shared instruments (`patches/<name>.patch.json`) and a music track's score (`<track>.score.json`). Limits: **5 MB per `.ogg`**, 1 MB for anything else.

## The origin manifest

`audio/manifest.json` is `{"assets": [ ... ]}`, one entry per asset (keeping it sorted by `path` is a convention, not checked):

```json
{
  "path": "audio/sfx/zap.ogg",
  "origin": "ai",
  "author": "Your Name",
  "license": "CC-BY-SA-4.0",
  "tier": "good",
  "tool": "name of the generator",
  "prompt": "the full prompt"
}
```

- `path`: the file, from the repository root.
- `origin`: `human`, `ai` or `placeholder`.
- `author`: who made it (for AI audio, who ran the tool).
- `license`: an SPDX identifier allowed for assets.
- `tier`: `placeholder`, `good` or `final`.
- For `origin: "ai"` also `tool` and `prompt`. The tool's terms must allow commercial use, and the prompt must not name living artists or franchises.
- Optional: `github` and `source`. A `quarantined` field marks an asset taken out after a copyright report; don't touch it.

The manifest drives the Steam AI disclosure and the list of placeholders still to replace.

### Generated sound

A sound made by `tools/sound.py` (tools/README.md) has a folder of its own: `sfx/<id>/` (or any folder of its own under `audio/`, or a content item's `sounds/<id>/`) holds its recipe `<id>.sound.json`, and the bake writes beside it `variants/1.ogg` ... `n.ogg` and `<id>.tres` (a one-shot), or `<id>.ogg` (a held loop), and `assets.json`, one entry a file, so parallel PRs never edit one list. Never write these by hand: change the recipe and run `tools/sound.py bake <id>`. Its entries add `recipe_hash` (of the recipe, its patches and its family's row in docs/STYLE.md: what `tools/sound.py check` and its test compare), `audio_hash` (of its samples), `loudness` (LUFS) and `peak` (dBTP), and `prompt` is the recipe's path, which is the whole input:

```json
{"path": "audio/sfx/cast/variants/1.ogg", "origin": "ai", "author": "Claude", "license": "CC-BY-SA-4.0",
 "tier": "good", "tool": "tools/sound.py (procedural synthesis, generator 1)",
 "prompt": "audio/sfx/cast/cast.sound.json", "recipe_hash": "sha256:...", "audio_hash": "sha256:...",
 "loudness": -20.1, "peak": -6.2}
```

A rebake keeps a file's `tier` while its audio (`audio_hash`) stays the same; one that changes it sets `final` back to `good`, because the owner promoted the sound they heard. The bake fails a sound that is off its family's level, over its peak, or too loud above 2 kHz (its top; docs/STYLE.md, "Sound"); the fix it names is the recipe's. Hear a sound before a PR with `tools/sound.py sheet <id> --out <a folder outside the repository>`, and attach or link the sheet's `.mp4`.

Music is made the same way from a score: `music/<track>/<track>.score.json` (sound plan, section 4; tools/README.md) names its instruments (patches from `patches/`), its one-bar patterns and its layers, and `tools/sound.py bake <track>` writes `<layer id>.ogg` a layer beside it, every one a loop of the same length (its `.import` with `loop=true`), and the folder's `assets.json`. A layer's id is the sound id a `MusicTrack` names; the layers of one track are placed together on the music target in docs/STYLE.md.

## Steps

1. Add the `.ogg` in `sfx/`, `music/` or `ambience/`.
2. Add its entry to `audio/manifest.json`.
3. Run the checks below, then open a PR using the template.

## Example to copy

The rooms' ambience (atmosphere D) is in `ambience/`, a folder a sound, generated as the rest (sound plan AU6): the crypt's `amb_crypt_air/` (a 12 s held loop) and its accents `amb_crypt_drip/`, `amb_crypt_drip_double/` and `amb_crypt_rumble/` (one-shots of the `ambience` family, docs/STYLE.md), named by `content/rooms/crypt/crypt_ambience.tres`; the hub's loops `amb_hub_wind/` and `amb_hub_void/` and its accent `amb_hub_gust/`, named by `content/rooms/hub/hub_ambience.tres`. Ambience ids start `amb_`. The menus' sounds (sound plan AU8) are `sfx/ui_move/` and its five siblings (`ui_choose`, `ui_back`, `ui_deny`, `ui_card_place`, `ui_card_remove`), each its recipe, its `variants/`, its `.tres` and its `assets.json`. The first generated sounds are the combat set (sound plan AU5) in `sfx/`: copy `sfx/cast/` (its recipe `cast.sound.json`, a Roman candle's deep thoomp; the bake made the rest) for a one-shot, and name a shared voice from `patches/` (`fire_roar`, `frost_glass`, `storm_gust`, `void_swell`, `water_wash`, `lightning_zap` ...) as the reactions do.

The first music is generated (sound plan AU7): `music/boss_broom/boss_broom.score.json` makes the Old Broom's two stacked layers, `boss_broom` and `boss_broom_fire` (named by its `MusicTrack` in `content/bosses/old_broom/old_broom.tres`), and `music/crypt_halls/` the crypt fight rooms' one layer (each 32 bars in two halves, the second a contrast: sound plan, "The owner's first listen") (named by `content/rooms/crypt/crypt_music.tres`). Copy a score's folder, rename it and its layers, and bake.

## Validate

```sh
tools/check.sh                     # the hard rules (file types, sizes, licenses), on your changes
ci/build/build.sh --quick --tests  # import, smoke test and every unit test in Godot
```

`tools/check.sh` does not yet check that every asset has a manifest entry. Until that validator exists, the reviewer checks it (see the review questions below), so don't skip the entry.

Add a short video, or a note saying where the sound plays in the game, how loud it is and how it loops, to the PR.

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it fit the game's mood, and is it still pleasant on the hundredth listen? Does it sit low, under the fight, or does it cut through?
- Is the volume balanced with the other sounds, and does music loop cleanly?
- Is the origin recorded honestly in the manifest?
