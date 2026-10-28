# Art

## Purpose

Shared pixel art used by more than one thing: tilesets (`tilesets/`), UI art (`ui/`), visual effects (`vfx/`) and the face layers every living staff wears (`faces/`: the eye and brow sheets of `gameplay/actor/face.gd`). Art that belongs to a single item (a spell icon, an enemy sprite) lives in that item's folder under `content/`, not here. The look is 32×32 pixel art; the vision is in docs/DESIGN.md, and the rules are in [docs/STYLE.md](../docs/STYLE.md) (provisional until M2): the palette, light from the top-left, 1px dark outline, no gradients, at most 3 shades per material, frame counts.

Palette files, grid templates and the one-page checklist are in [kit/](kit/README.md). The three art direction samples the owner picks from (nothing uses them) are in [samples/](samples/README.md).

## Contract

- Art depends on nothing. It holds files only, no logic.
- Every asset has an entry in `art/manifest.json` (see below), or, for the files of one content folder, in an `assets.json` in that folder in the same shape (one list per folder, so two PRs never edit the same list; the validator and `tests/core/test_svg_art.gd` read them all).
- Sprites and tiles are 32×32 pixels (or a whole multiple for bigger objects).
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

1. Add the file in the right sub-folder (`tilesets/`, `ui/`, `vfx/` or `faces/`).
2. Add its entry to `art/manifest.json`.
3. Run the checks below, then open a PR using the template.

## Example to copy

`art/vfx/hit_spark.svg` with its `art/vfx/hit_spark.svg.import` and its entry in `art/manifest.json` (a placeholder SVG written as rects, see "Placeholder SVGs" in docs/STYLE.md). More: `art/tilesets/crypt/floor.svg` (a flat tile) and `wall.svg` (a lit and shaded tile). Item art sits with its item, for example `content/enemies/ember_imp/idle.svg`. The `.import` files keep Godot's defaults (the project draws textures with nearest-neighbour filtering, see `rendering/textures/canvas_textures/default_texture_filter` in `project.godot`), and scenes that show art set `texture_filter` to nearest as well.

## Validate

```sh
tools/check.sh                   # the hard rules (file types, sizes, licenses), on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```

`tools/check.sh` does not yet check that every asset has a manifest entry. Until that validator exists, the reviewer checks it (see the review questions below), so don't skip the entry.

Add a screenshot of the asset in the game to the PR.

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it match the style guide: palette, light from the top-left, outline rules, frame counts?
- Is it readable at 32×32, next to other art and with four players on screen?
- Is the origin recorded honestly in the manifest?
