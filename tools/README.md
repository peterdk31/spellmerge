# Tools

## Purpose

Scripts that contributors and Claude run on their own checkout. **Not an area for content PRs:** scripts here run on contributors' machines, so they change only through Claude's PRs or the owner's.

## The tools

- `tools/check.sh`: the same hard rules as CI's `rules` check, on your changes (below).
- `tools/ptest.sh [jobs] [path-regex]`: the Godot unit tests in parallel (needs the pinned Godot from `ci/build/build.sh --quick`); failures explained by `ptest_failures.py`.
- `tools/atlas.py <out>`: the Spell atlas data (`atlas.json`; format in `ci/smbot/clips.py`). Standard library only.
- **Art from rules** (each with `--check`: writes nothing, fails when a file differs from what the rules draw): `staff_art.py` (the curl staff and `art/kit/golden_staff@2x.svg`), `face_art.py` (`art/faces/eyes@2x.svg`, `brows@2x.svg`), `head_art.py` (other staff heads), `enemy_art.py` (enemies and the Old Broom, on `sprite_rules.py`), and `redraw_2x.py IN.svg OUT@2x.(svg|png)` (a one-off 2x redraw; `--blocky`, `--detail`). Palette colours are read from docs/STYLE.md. See art/README.md, "Redrawing a sprite at 64x64".
- `tools/font_art.py`: the game's text font from glyph parts to `art/ui/fonts/text.png` (the glyph sheet: every face, its outline and its outline with a shadow) and `text.json` (its metrics), read by `core/display/pixel_font.gd`; `--check`, `--preview out.png`.
- `tools/pixel_grid.py <name>.grid.json...`: a grid of characters to `<name>.svg` (rects, one per run of a colour along a row) and `<name>_motes.svg` (mote points, `*`); `--check`.
- `tools/ground_shape.py <shape file>...`: a room's `<room>_ground.tscn` and its art in `art/grounds/<room>/` from its shape file (with `ground_materials.py`, `ground_walls.py`); `--check`. **The game draws the same ground:** `gameplay/feel/ground/` (GDScript) and `native/src/ground_kernel.cpp` mirror it, so a change to the drawing is made in all three in the same PR (`tests/gameplay/feel/test_ground_drawing.gd`). A length is `length_of`, never `math.hypot` or `math.dist`. Keep its hot loops cheap (the CI job has 5 minutes).
- `tools/platform_hashes.py run | play NAME --build DIR | compare LOG...`: exports and plays recorded runs on Linux, Windows (WSL) and web, naming the first tick, area and members where a platform parts from Linux (`tests/platforms/replay_hashes_runner.gd`). Writes only under `build/`.
- Online: `tools/online_pair.sh [ticks]`, `tools/online_signal.sh`, `tools/online_room.sh [ticks]`, `tools/online_party.sh [ticks]` (Node 22+ for the last three): play the real game across processes and pass when every hash check agreed.
- **The sound tools:** `tools/sound.py bake [recipe or id ...]` bakes `<id>.sound.json` recipes (in a folder of their own named `<id>`: `audio/sfx/<id>/` or a content item's `sounds/<id>/`; instruments in `audio/patches/<name>.patch.json`) with `sound_synth.py` and `sound_meter.py` (targets read from docs/STYLE.md, "Sound"). It writes in the recipe's folder only: `variants/N.ogg` and `<id>.tres` (one-shot) or `<id>.ogg` with a `loop=true` `.import` (held), and the folder's `assets.json`; unchanged audio and existing `.import` files are never rewritten. **Music** is `<track>.score.json` under `audio/music/<track>/`, rendered by `sound_score.py` into `<layer id>.ogg` layers. `sound.py sheet ... --out DIR` writes a contact sheet outside the repository. `sound.py check` reads no audio: recipes valid, outputs present with a current `recipe_hash`, no `.ogg` without a recipe unless `origin: human` (`UNRECIPED` stays empty). Raise `GENERATOR` (and `VERSION` in `sound_score.py`) when the synth's sound changes.
- `tools/sound_fixtures.py bake | check`: the sound room's fixtures in `tests/sound_room/fixtures/<id>/`.
- **Editor scripts** (`@tool`, allowed only here and in core/; AGENTS.md hard rule 4): `cover_preview.gd` (`CoverPreview`), `prop_stand_in.gd` (`PropStandIn`), `enemy_stand_in.gd` (`EnemyStandIn`), `item_stand_in.gd` (`ItemStandIn`), `socket_preview.gd` (`SocketPreview`). They never run in play: Flow takes them out of the room and reads only their `prop`, `enemy` or `item`.

## Contract

- Tools only read the repository and report, or write the files they are asked for (`atlas.py` its out file, `pixel_grid.py` a grid's SVGs, `font_art.py` the font's sheet and metrics, `ground_shape.py` the named shapes' ground, `sound.py bake` each recipe's own folder then Godot's import, `sheet` only outside the repository). They never change anything else, push or open PRs.
- They depend on git and Python 3.10 or newer, standard library only, nothing else (`ptest.sh` also needs bash and the pinned Godot). Only `sound.py bake` and `sheet` need ffmpeg (libvorbis; the video libx264 and aac); a bake without it stops and says what to install; `sound.py check` and every test need only Python.
- Pipeline Python lives in `ci/smbot/` (owner-only); `check.sh` is a thin wrapper around it.
- They work in any clone with an `origin` remote, and still run on the local copy when they can't fetch.
- Generated art and ground are deterministic: the same inputs give the same bytes.

## Allowed files

`.sh` and `.py` scripts and the editor scripts (`.gd`, with their `.uid` files) (Claude's PRs only) and this README. No binaries, archives or downloaded tools.

## Steps

Run the check from the repository root before every PR:

```sh
tools/check.sh
```

It fetches `origin/main` and checks everything you changed (committed, uncommitted, new) with `python3 -m smbot.rules --base origin/main --worktree`; extra flags are passed on:

- `--author LOGIN`: decides the path rules (default: an outside contributor; `--author 'spellmerge-bot[bot]'` for Claude's wider rules).
- `--format text|github|json`.

Each problem is printed as rule, file and line, what is wrong and how to fix it. Exit 1 on an error, 0 on warnings only or nothing. Empty sandbox placeholders (`.bashrc`, `.gitconfig`, `.idea/`, ...) are skipped.

## Example to copy

`tools/check.sh`: a short POSIX `sh` script that changes to the repository root, fetches `origin/main` and runs the Python module with `PYTHONPATH=ci`.

## Tests

`python3 -m unittest discover -s tools`: `test_atlas.py`, `test_staff_art.py`, `test_face_art.py`, `test_head_art.py`, `test_enemy_art.py`, `test_redraw_2x.py`, `test_pixel_grid.py` (every grid in the repository), `test_font_art.py` (the font's sheet up to date), `test_ground_shape.py` (every shape file up to date), `test_ptest_failures.py`, `test_platform_hashes.py`, `test_sound_synth.py`, `test_sound_meter.py`, `test_sound_bake.py`, `test_sound_golden.py`, `test_sound_hashes.py`, `test_sound_score.py`, `test_sound_fixtures.py`.

```sh
tools/check.sh                              # your change, as an outside contributor
tools/check.sh --author 'spellmerge-bot[bot]'  # Claude's own PRs
PYTHONPATH=ci python3 -m unittest discover -s ci/tests -t ci   # the rules' own tests
```

## Rating questions

- Does it only read and report, with no side effects on the checkout or GitHub?
- Does it run with just git and Python 3.10+ (and ffmpeg, only to bake sound), and keep working offline?
- Does it give the same answer as the `rules` check in CI?

History and reasons: [docs/history/tools-README.md](../docs/history/tools-README.md).
