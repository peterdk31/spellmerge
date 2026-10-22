# Audio

## Purpose

Shared sound used by more than one thing: music (`music/`) and sound effects (`sfx/`). Sound that belongs to a single item (a spell's cast sound) lives in that item's folder under `content/`, not here.

## Contract

- Audio depends on nothing. It holds files only, no logic.
- **`.ogg` only.** No `.wav`, `.mp3` or other formats.
- Every asset has an entry in `audio/manifest.json` (see below). Item-specific sounds are listed there too, wherever they live.
- Loop music must loop without a click. Keep sound effects short and balanced in volume with the others.
- Names are original. No ripped game audio, no samples of other works.
- Audio is CC-BY-SA-4.0 by default. A file may instead declare CC0-1.0 or CC-BY-4.0 with a `<file>.license` file (AGENTS.md, hard rules).

## Allowed files

`.ogg` audio, plus Godot's `.import` files, `.license` files and the manifest. Limits: **5 MB per `.ogg`**, 1 MB for anything else.

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

## Steps

1. Add the `.ogg` in `sfx/` or `music/`.
2. Add its entry to `audio/manifest.json`.
3. Run the checks below, then open a PR using the template.

## Example to copy

Arrives with Claude's first audio in M1; this README is updated then with its path. Do not guess its layout before then.

## Validate

```sh
tools/check.sh                     # the hard rules (file types, sizes, licenses), on your changes
ci/build/build.sh --quick --tests  # import, smoke test and every unit test in Godot
```

`tools/check.sh` does not yet check that every asset has a manifest entry. Until that validator exists, the reviewer checks it (see the review questions below), so don't skip the entry.

Add a short video, or a note saying where the sound plays in the game, how loud it is and how it loops, to the PR.

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it fit the game's mood, and is it still pleasant on the hundredth listen?
- Is the volume balanced with the other sounds, and does music loop cleanly?
- Is the origin recorded honestly in the manifest?
