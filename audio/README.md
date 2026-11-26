# Audio

## Purpose

Shared sound used by more than one thing: music (`music/`), sound effects (`sfx/`) and the rooms' sound under the music (`ambience/`: the loops and accents an `Ambience` names). Sound that belongs to a single item (a spell's cast sound) lives in that item's folder under `content/`, not here. The rules for how it sounds (families, loudness, variants) are in [docs/STYLE.md](../docs/STYLE.md), "Sound".

## Contract

- Audio depends on nothing. It holds files only, no logic.
- **`.ogg` only.** No `.wav`, `.mp3` or other formats.
- Every asset has an entry in `audio/manifest.json`, or, for the sounds of one content folder, in an `assets.json` in that folder in the same shape. A generated sound's entries are written by the tool (below).
- Music and ambience loops loop without a click and are imported to loop (`loop=true` in their `.import`). An ambience accent starts and ends at silence and does not loop. Sound effects are short, low (deep, never piercing) and balanced with the others.
- Names are original. No ripped game audio, no samples of other works.
- Audio is CC-BY-SA-4.0 by default; a file may declare CC0-1.0 or CC-BY-4.0 with a `<file>.license` file.

## Sound ids

- A sound's id is its file's name (`zap` for `audio/sfx/zap.ogg`), found anywhere under `audio/` and under any content item's `sounds/` folder.
- Or `<id>.tres`, an `AudioStreamRandomizer` naming its baked variants in `variants/` beside it (`audio/sfx/<id>/<id>.tres`, `variants/1.ogg` ...); nothing under `variants/` is an id. An `.ogg` and a `.tres` of one id is a registry warning and a test failure.
- Cues (`content/cues`), enemy data (`death_sound`, a phase's held `sound`) and music tracks (`MusicTrack.layers`) name ids; an id with no file is silent, so the game may name a sound before it is made.
- Every sound plays through the Audio service (core/audio) on its bus of `default_bus_layout.tres`: music on `MusicDuck`, effects on `SFX`, rooms on `Ambience`, menus on `UI`.
- A held sound loops while its moment lasts; a track's layers start together, so make them the same length. Ambience ids start `amb_`.

## Allowed files

`.ogg` audio, plus Godot's `.import` files, `.license` files and the manifest; and for generated sound a recipe (`<id>.sound.json`), the `AudioStreamRandomizer` of its variants (`<id>.tres`), a sound folder's `assets.json`, shared instruments (`patches/<name>.patch.json`) and a music track's score (`<track>.score.json`). Limits: **5 MB per `.ogg`**, 1 MB for anything else.

## The origin manifest

`audio/manifest.json` is `{"assets": [ ... ]}`, one entry per asset (sorted by `path` by convention):

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

- `path`, `origin` (`human`, `ai` or `placeholder`), `author`, `license` (an SPDX identifier allowed for assets), `tier` (`placeholder`, `good` or `final`).
- For `origin: "ai"` also `tool` and `prompt`. The tool's terms must allow commercial use; the prompt must not name living artists or franchises.
- Optional: `github` and `source`. Never touch a `quarantined` field.

### Generated sound

A sound made by `tools/sound.py` (tools/README.md) has a folder of its own (`sfx/<id>/`, or a content item's `sounds/<id>/`) holding its recipe `<id>.sound.json`; the bake writes `variants/1.ogg` ... and `<id>.tres` (a one-shot) or `<id>.ogg` (a held loop), and `assets.json`.

- **Never write the baked files by hand:** change the recipe and run `tools/sound.py bake <id>`.
- Entries add `recipe_hash` (recipe, patches and its family's row in docs/STYLE.md), `audio_hash`, `loudness`, `peak`; `prompt` is the recipe's path. `tools/sound.py check` compares them.
- A rebake keeps `tier` while `audio_hash` stays; a changed sound goes from `final` back to `good`.
- The bake fails a sound off its family's level, over its peak or its top (docs/STYLE.md, "Sound"); fix the recipe.
- Hear it before a PR: `tools/sound.py sheet <id> --out <a folder outside the repository>`, and attach the sheet's `.mp4`.
- Music is a score (`music/<track>/<track>.score.json`: instruments from `patches/`, one-bar patterns, layers); `tools/sound.py bake <track>` writes `<layer id>.ogg` a layer, every one a loop of the same length.

## Steps

1. Add the sound in `sfx/`, `music/` or `ambience/` (a generated one: its recipe, then bake).
2. Add its entry to `audio/manifest.json` (the bake writes a generated one's `assets.json`).
3. Run the checks below, then open a PR with a short video or a note of where it plays, how loud and how it loops.

## Example to copy

- A one-shot: `sfx/cast/` (its recipe `cast.sound.json`; the bake made the rest), naming a shared voice from `patches/` (`fire_roar`, `frost_glass`, `storm_gust`, `void_swell`, `water_wash`, `lightning_zap` ...).
- Ambience: `ambience/amb_crypt_air/` (a held loop) and `amb_crypt_drip/` (an accent), named by `content/rooms/crypt/crypt_ambience.tres`.
- Menus: `sfx/ui_choose/`, `sfx/ui_back/`, `sfx/ui_deny/`. Pickups: `sfx/pickup_*/`.
- A card's own sounds: in its folder's `sounds/` (`content/spells/carriers/<id>/sounds/<id>_cast/`, named by its `cast_sound`; docs/milestones/sound.md, "Carrier sounds").
- Music: `music/boss_broom/boss_broom.score.json` (two stacked layers), `music/hub_island/`, `music/crypt_halls/`. Copy a score's folder, rename it and its layers, and bake.

## Validate

```sh
tools/check.sh                     # the hard rules (file types, sizes, licenses), on your changes
ci/build/build.sh --quick --tests  # import, smoke test and every unit test in Godot
python3 -m unittest discover -s tools   # the sound tool's tests
```

`tools/check.sh` does not check manifest entries; the reviewer does.

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it fit the game's mood, and is it still pleasant on the hundredth listen? Does it sit low, under the fight, or does it cut through?
- Is the volume balanced with the other sounds, and does music loop cleanly?
- Is the origin recorded honestly in the manifest?

History and reasons: [docs/history/audio-README.md](../docs/history/audio-README.md).
