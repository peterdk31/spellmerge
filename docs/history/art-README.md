> The history of [art/README.md](../../art/README.md): the full text of that file as it stood on 2026-11-26, before it was slimmed to a contract. Read it only when a question needs the reasons; the contract is the rule.

# Art

## Purpose

Shared pixel art used by more than one thing: tilesets (`tilesets/`), UI art (`ui/`, with the title type in `ui/fonts/`), visual effects (`vfx/`) the face layers every living staff wears (`faces/`: the eye and brow sheets of `gameplay/actor/face.gd`, at 2x detail, drawn by `tools/face_art.py`) and the intro's own pieces (`story/`: the wizard's Blight hat and the Favourite, for `gameplay/flow/intro.gd`). Art that belongs to a single item (a spell icon, an enemy sprite) lives in that item's folder under `content/`, not here. The look is pixel art on a 32-unit grid, redrawn at 64×64 per cell (2x detail) since the owner's decision of 2026-11-21 (confirmed 2026-11-25; "Redrawing a sprite at 64x64" below); the vision is in docs/DESIGN.md, and the rules are in [docs/STYLE.md](../STYLE.md): the palette, light from the top-left, 1px dark outline, no gradients, at most 3 shades per material, frame counts.

Palette files, grid templates and the one-page checklist are in [kit/](../../art/kit/README.md). The three art direction samples the owner picks from (nothing uses them) are in [samples/](../../art/samples/README.md).

## Contract

- Art depends on nothing. It holds files only, no logic.
- Every asset has an entry in `art/manifest.json` (see below), or, for the files of one content folder, in an `assets.json` in that folder in the same shape (one list per folder, so two PRs never edit the same list; the validator and `tests/core/test_svg_art.gd` read them all).
- Sprites and tiles cover 32×32 world units (or a whole multiple for bigger objects): 64×64 px at 2x detail, in a file named `<name>@2x.<ext>`; 32×32 px for art not yet redrawn.
- Names are original. No ripped game assets, no fan art of other IP, no names from other works.
- Art is CC-BY-SA-4.0 by default. An asset may instead declare CC0-1.0 or CC-BY-4.0 with a `<file>.license` file (AGENTS.md, hard rules).

## Allowed files

`.png` and `.svg` images, plus Godot's `.import` files, `.license` files and the manifest. Limits: **1 MB per image**, 1 MB for anything else. No binaries, archives or other formats.

## The origin manifest

`art/manifest.json` is `{"assets": [ ... ]}`, one entry per asset (keeping it sorted by `path` is a convention, not checked):

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
- `origin`: `human`, `ai` or `placeholder` (a stand-in made by code until real art replaces it).
- `author`: who made it (for AI art, who ran the tool).
- `license`: an SPDX identifier allowed for assets.
- `tier`: `placeholder`, `good` or `final`. Nothing with `placeholder` ships in a player-facing spot in Early Access.
- For `origin: "ai"` also `tool` (the generator) and `prompt` (the full prompt). Prompts must not name living artists or franchises.
- Optional: `github` (the author's login) and `source` (the issue or PR). A `quarantined` field marks an asset taken out after a copyright report; don't touch it.

The manifest drives the Steam AI disclosure and the list of placeholders still to replace.

## Steps

1. Add the file in the right sub-folder (`tilesets/`, `ui/`, `vfx/`, `faces/` or `story/`).
2. Add its entry to `art/manifest.json`.
3. Run the checks below, then open a PR using the template.

## Example to copy

`art/vfx/hit_spark.svg` with its `art/vfx/hit_spark.svg.import` and its entry in `art/manifest.json` (a placeholder SVG written as rects, see "Placeholder SVGs" in docs/STYLE.md). More: `art/tilesets/crypt/floor.svg` (a flat tile) and `wall.svg` (a lit and shaded tile). Item art sits with its item, for example `content/enemies/ember_imp/idle@2x.svg`. The `.import` files keep Godot's defaults (the project draws textures with nearest-neighbour filtering, see `rendering/textures/canvas_textures/default_texture_filter` in `project.godot`), and scenes that show art set `texture_filter` to nearest as well. The one exception is the title type, `art/ui/fonts/title.svg` (docs/milestones/boss-intro.md, rule 7): a sheet of every printable ASCII character, 16 a row on a 12×16 cell, drawn from `title.grid.json` by `tools/pixel_grid.py` in Bone light, and imported by Godot's image font importer (`importer="font_data_image"` in its text `.import`: the ranges `32-126`, 16 columns, 6 rows, ascent 14, descent 2, whole-number scaling only), so it loads as a font with no `.ttf`. A glyph's colour is the art's: a label's `font_color` and shadow colour multiply it. Redraw a glyph in the grid and run the tool. A character past ASCII (`é`) is a cell after the last and its own entry in `character_ranges` (`"233"`); one cell is free in the sixth row, and more take a seventh (`rows=7`, the sheet 112 px tall).

## Validate

```sh
tools/check.sh                   # the hard rules (file types, sizes, licenses), on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```

`tools/check.sh` does not yet check that every asset has a manifest entry. Until that validator exists, the reviewer checks it (see the review questions below), so don't skip the entry.

Add a screenshot of the asset in the game to the PR.

## Redrawing a sprite at 64x64

The owner's decision of 2026-11-21 (confirmed 2026-11-25; docs/STYLE.md, "The picture and the art's detail"): every sprite is redrawn at 64×64 for its 32-unit cell, in this order: players and enemies, spells and effects, rooms and props, HUD and font. ART0 built the picture and the rule and redrew one piece, the curl staff (`content/wizard/staffs/curl/`). One sprite or sheet at a time:

1. **Draw it at twice the size, the same layout.** Every frame twice as wide and tall (a 32×32 frame becomes 64×64, a 48×48 head 96×96, a 16×8 face frame 32×16), every point measured in its art (a grip, an origin, an anchor in a sheet, a mote point) at twice its numbers. The frame counts, columns, rows and their order stay as they are, so the code that picks a frame needs no change. Start from `art/kit/grid_64.svg` (export without it). The palette, the light from the top-left, at most 3 shades a material and the rest of docs/STYLE.md hold; the outline is one art pixel (half as thick as before on screen: finer, which is the point). Keep the old silhouette, so it reads as the same thing.
2. **Name it `<name>@2x.<ext>`** and delete the old file (with its `.import`; rename the `.import` to the new name and fix its `source_file` to keep the texture's uid, or let Godot make a new one). The name is the whole rule (`ArtDetail`, core/display/art_detail.gd): the game draws it at half size. Point what loaded the old file at the new one (a `.tres`, a `.tscn`, a `preload`); `grep -rn "<old path>"` finds them.
3. **Check what reads its pixels.** Anything that measures the art in pixels and was written for 1x (a size check in a test, a crop, a script reading pixel positions) multiplies by `ArtDetail.of(texture)`. Sprites, faces (`FaceArt`), the staff's head, `TexturePage` regions and the cover's batches take the rule already. A look that drew the texture another way (a `draw_texture_rect`, a MultiMesh of its own, a shader that sizes its quad from the texture) takes it the same way: its rect `ArtDetail.size_of(texture)`, its quad `ArtDetail.quad_size(texture, frame_px)`, a sprite's scale `ArtDetail.fit(sprite, pose)` (a look's own stretch times the detail; `sprite.scale * ArtDetail.of(texture)` is the stretch back).
4. **List it** in its folder's `assets.json` (or `art/manifest.json`) with origin, tool and prompt (no living artists or franchises), as before.
5. **Look at it in the game**, at the resting zoom 1 (every art pixel shows) and zoomed out as the camera holds a spread party (0.8 down to 0.5): a one-pixel line breaks there now and then (one art pixel in five is left out at 0.8), so lines that must read even then are two art pixels. `tests/screenshots/shot_art_detail.gd` shows two 2x staffs among 1x enemies and props in play, at zoom 1 and at 0.8, and `shot_players_2x.gd` every head in the four player colours; copy one for a side by side of your sprite. Add the screenshots to the PR.

**Drawn by a shader** (the flat floor states, `gameplay/feel/cover_flat.gdshader`): no file to rename. Done for the floor (docs/milestones/floor-look.md, 2026-11-25): `CoverFlat.DETAIL` is `ArtDetail.DETAIL`, and the shader works its shapes and details out in art pixels at 64 px a cell (rounded, wobbling edges, ripples, cracks, shine, wisps: whole art pixels); a new state's look is its `CoverState.flat_*` data. Done for the shots' cores (ART2): `shot_head.gdshaderinc` (the plain head and the bolt's, `HEAD_DETAIL`) draws a shot's core in art pixels, a shaded bead or gem lit from the top-left with its rays a pixel wide; and for the motes (a shot's tail, a hit's sparks, a cue's bits and smoke): a kind's `shape_2x` (content/motes/README.md). And for Feel's flashes (ART2, 2/3): `shot_flash.gdshader` draws in art pixels (`FLASH_DETAIL`), the kinds' numbers (content/flashes) staying in world pixels and read times it, so its lines are an art pixel thin, its rings two (a world pixel, so they read zoomed out) and its dots a world pixel each, lit from the top-left (a ring's, a star's, a ray's and a cross's lower-right edge a shade down); and for the oil fire's flames (`cover_flat.gdshader`, `flames`): curved tongues that swell and curl, lit on their left, staggered. The pickups (the coin, the key, the potions, the reward reroll) are drawn by `tools/pickup_art.py` from shape and light rules (`tools/sprite_rules.py`).

A generator may draw it (palette colours; an SVG of rects, one a run along a row, as `tests/core/test_svg_art.gd` wants, or a PNG when the rects would pass the 1 MB limit: the curl's head sheet): `tools/staff_art.py` draws the curl's head at 16 drawn directions and its face from shape rules, `tools/face_art.py` the shared face sheets, `tools/head_art.py` the other staff heads from shape and light rules, `tools/redraw_2x.py` redraws a 1x sheet of rects at 2x once, to touch up by hand after (its diagonals smoothed, its outside outline one art pixel, and with `--detail` one-pixel edge light and shadow at the finer pixels; the intro's wizard), `tools/enemy_art.py` the enemies and the Old Broom from parts of their own on `tools/sprite_rules.py` (a change to one is made in its rules there: `--check` holds the files to them), `tools/pixel_grid.py` draws from a grid of characters at any size, `tools/pickup_art.py` the pickups' icons and `tools/icon_art.py` the cards' and sigils' (each `icon@2x.svg`, and its `icon.svg` for the HUD's small cells from the same parts at 1x, `sprite_rules.draw_1x`).

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it match the style guide: palette, light from the top-left, outline rules, frame counts?
- Is it readable at its size in the world (32 units, at the resting zoom 1 and zoomed out to 0.8), next to other art and with four players on screen?
- Redrawn at 2x: is it named `@2x`, the same layout at twice the pixels, and does it keep its silhouette?
- Is the origin recorded honestly in the manifest?
