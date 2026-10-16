# Art

## Purpose

Shared pixel art used by more than one thing: tilesets (`tilesets/`), UI art (`ui/`) and visual effects (`vfx/`). Art that belongs to a single item (a spell icon, an enemy sprite) lives in that item's folder under `content/`, not here. The look is 32×32 pixel art; the vision is in docs/DESIGN.md, and the style guide (`docs/STYLE.md`) arrives with M1.

**Opens for PRs in M1** (see "Opens for PRs" in docs/ROADMAP.md). Until then, PRs to this folder are a gamble. **The example to copy arrives with Claude's first art in M1**; this README is updated then with its path.

## Contract

- Art depends on nothing. It holds files only, no logic.
- Every asset has an entry in `art/manifest.json` (see below). Item-specific art is listed there too, wherever it lives.
- Sprites and tiles are 32×32 pixels (or a whole multiple for bigger objects).
- Names are original. No ripped game assets, no fan art of other IP, no names from other works.
- Art is CC-BY-SA-4.0 by default. An asset may instead declare CC0-1.0 or CC-BY-4.0 with a `<file>.license` file (AGENTS.md, hard rules).

## Allowed files

`.png` and `.svg` images, plus Godot's `.import` files, `.license` files and the manifest. Limits: **1 MB per image**, 1 MB for anything else. No binaries, archives or other formats.

## The origin manifest

`art/manifest.json` is `{"assets": [ ... ]}`, one entry per asset, sorted by `path`:

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
- Optional: `github` (the author's login) and `source` (the issue or PR). A `quarantined` field is set by the copyright process; don't touch it.

The manifest drives the Steam AI disclosure and the "Replace placeholder" issues.

## Steps

1. Pick an issue labelled `now` in this area and comment `/claim`.
2. Add the file in the right sub-folder (`tilesets/`, `ui/` or `vfx/`).
3. Add its entry to `art/manifest.json`.
4. Run the checks below, then open a PR using the template.

## Validate

```sh
tools/check.sh                   # the hard rules (file types, sizes, licenses), on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```

Add a screenshot of the asset in the game to the PR.

## Rating questions

Besides the standard criteria (fit, fun, quality, value, performance, risk, scope):

- Does it match the style guide: palette, light from the top-left, outline rules, frame counts?
- Is it readable at 32×32, next to other art and with four players on screen?
- Is the origin recorded honestly in the manifest?

Art also needs the community vote (👍/👎, 24 hours).
