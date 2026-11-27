# Art

## Purpose

Shared pixel art used by more than one thing: tilesets (`tilesets/`), UI art (`ui/`, the title type in `ui/fonts/`), visual effects (`vfx/`), the face layers every living staff wears (`faces/`: eye and brow sheets at 2x, drawn by `tools/face_art.py`) and the intro's pieces (`story/`). Art that belongs to one item (a spell icon, an enemy sprite) lives in that item's folder under `content/`. The rules are in [docs/STYLE.md](../docs/STYLE.md). Palette files, grid templates and the checklist are in [kit/](kit/README.md); the art direction samples in [samples/](samples/README.md).

## Contract

- Art depends on nothing. It holds files only, no logic.
- Every asset has an entry in `art/manifest.json`, or, for the files of one content folder, in an `assets.json` in that folder in the same shape (one list per folder).
- Sprites and tiles cover 32×32 world units (or a whole multiple): 64×64 px at 2x detail, named `<name>@2x.<ext>`; 32×32 px for art not yet redrawn.
- Names are original. No ripped game assets, no fan art of other IP, no names from other works.
- Art is CC-BY-SA-4.0 by default; an asset may declare CC0-1.0 or CC-BY-4.0 with a `<file>.license` file.
- `.import` files keep Godot's defaults (the project filters nearest); scenes that show art set `texture_filter` to nearest.

## Allowed files

`.png` and `.svg` images, plus Godot's `.import` files, `.license` files and the manifest. Limits: **1 MB per image**, 1 MB for anything else. No binaries, archives or other formats.

## The origin manifest

`art/manifest.json` is `{"assets": [ ... ]}`, one entry per asset (sorted by `path` by convention):

```json
{
  "path": "art/vfx/spark.png",
  "origin": "human",
  "author": "Your Name",
  "license": "CC-BY-SA-4.0",
  "tier": "good"
}
```

- `path`: the file, from the repository root.
- `origin`: `human`, `ai` or `placeholder` (a stand-in made by code).
- `author`: who made it (for AI art, who ran the tool).
- `license`: an SPDX identifier allowed for assets.
- `tier`: `placeholder`, `good` or `final`. Nothing `placeholder` ships in a player-facing spot in Early Access.
- For `origin: "ai"` also `tool` and `prompt` (the full prompt). Prompts must not name living artists or franchises.
- Optional: `github` (the author's login) and `source` (the issue or PR). Never touch a `quarantined` field.

## Steps

1. Add the file in the right sub-folder (`tilesets/`, `ui/`, `vfx/`, `faces/` or `story/`).
2. Add its entry to `art/manifest.json`.
3. Run the checks below, then open a PR with a screenshot of it in the game.

## Example to copy

`art/vfx/hit_spark.svg` with its `.import` and its manifest entry (a placeholder SVG of rects: docs/STYLE.md, "Placeholder SVGs"). More: `art/tilesets/crypt/floor@2x.svg` (flat) and `wall@2x.svg` (lit and shaded), both drawn by `tools/room_art.py`. The title type `art/ui/fonts/title.svg` is drawn from `title.grid.json` by `tools/pixel_grid.py` and imported as an image font (`importer="font_data_image"`, ranges `32-126`, 16 columns); redraw a glyph in the grid and run the tool; a character past ASCII is a cell after the last and its own entry in `character_ranges`. Every other text is drawn in the game's pixel font: `art/ui/fonts/text.png` and `text.json`, drawn from glyph parts by `tools/font_art.py` (change a glyph's parts there and run it) and made into the FontFile by `core/display/pixel_font.gd`.

## Validate

```sh
tools/check.sh                   # the hard rules (file types, sizes, licenses), on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```

`tools/check.sh` does not check manifest entries; the reviewer does. `tests/core/test_svg_art.gd` checks every SVG against docs/STYLE.md.

## Redrawing a sprite at 64x64

Every sprite is redrawn at 64×64 for its 32-unit cell (docs/STYLE.md, "The picture and the art's detail"), players and enemies first, then spells and effects, rooms and props, HUD and font. One sprite or sheet at a time:

1. **Draw it at twice the size, the same layout.** Every frame and every point (grip, origin, anchor) at twice its numbers; frame counts, columns, rows and their order stay, so code needs no change. Start from `art/kit/grid_64.svg`. The outline is one art pixel; keep the old silhouette.
2. **Name it `<name>@2x.<ext>`** and delete the old file (rename its `.import` and fix `source_file` to keep the uid). Point what loaded the old file at the new one (`grep -rn "<old path>"`).
3. **Check what reads its pixels.** Code measuring the art in pixels multiplies by `ArtDetail.of(texture)`; a look drawing it its own way uses `ArtDetail.size_of(texture)`, `ArtDetail.quad_size(texture, frame_px)` or `ArtDetail.fit(sprite, pose)`.
4. **List it** in its folder's `assets.json` (or `art/manifest.json`) with origin, tool and prompt.
5. **Look at it in the game** at zoom 1 and zoomed out (0.8 to 0.5): lines that must read there are two art pixels. Copy `tests/screenshots/shot_art_detail.gd` or `shot_players_2x.gd` for a side by side; add the screenshots to the PR.

**Drawn by a shader** (no file to rename): the flat floor states (`gameplay/feel/cover_flat.gdshader`, `CoverFlat.DETAIL`), shot cores (`shot_head.gdshaderinc`, `ART_DETAIL`), motes (a kind's `shape_2x`, content/motes/README.md) and flashes (`shot_flash.gdshader`, `ART_DETAIL`) work in art pixels already.

**Generators** (palette colours; an SVG of rects, one a run along a row, or a PNG past 1 MB): `tools/staff_art.py` (the curl's head), `tools/face_art.py` (faces), `tools/head_art.py` (other staff heads), `tools/redraw_2x.py` (a 1x sheet of rects at 2x, to touch up by hand), `tools/enemy_art.py` (enemies, on `tools/sprite_rules.py`; `--check` holds the files to the rules), `tools/prop_art.py` (props and their crumbles, on the same rules; a raised stone part takes its shadow shade), `tools/room_art.py` (the crypt's tiles and set pieces, torches and candles with their flames and glows, the hub's void, stone and altar, and the shaft of light; on the same rules, a tile repeating with no seam and a light with no outline), `tools/pixel_grid.py` (a grid of characters), `tools/pickup_art.py` (pickups) and `tools/icon_art.py` (cards' and sigils' `icon@2x.svg` and `icon.svg`). Change a generated sprite in its rules, not by hand. Their tests: `python3 -m unittest discover -s tools`.

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it match the style guide: palette, light from the top-left, outline rules, frame counts?
- Is it readable at its size in the world (32 units, at the resting zoom 1 and zoomed out to 0.8), next to other art and with four players on screen?
- Redrawn at 2x: is it named `@2x`, the same layout at twice the pixels, and does it keep its silhouette?
- Is the origin recorded honestly in the manifest?

History and reasons: [docs/history/art-README.md](../docs/history/art-README.md).
