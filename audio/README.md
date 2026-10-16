# Audio

## Purpose

Shared sound used by more than one thing: music (`music/`) and sound effects (`sfx/`). Sound that belongs to a single item (a spell's cast sound) lives in that item's folder under `content/`, not here.

**Opens for PRs in M1** (see "Opens for PRs" in docs/ROADMAP.md). Until then, PRs to this folder are a gamble. **The example to copy arrives with Claude's first audio in M1**; this README is updated then with its path.

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

`audio/manifest.json` is `{"assets": [ ... ]}`, one entry per asset, sorted by `path`:

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
- Optional: `github` and `source`. A `quarantined` field is set by the copyright process; don't touch it.

The manifest drives the Steam AI disclosure and the "Replace placeholder" issues.

## Steps

1. Pick an issue labelled `now` in this area and comment `/claim`.
2. Add the `.ogg` in `sfx/` or `music/`.
3. Add its entry to `audio/manifest.json`.
4. Run the checks below, then open a PR using the template.

## Validate

```sh
tools/check.sh                   # the hard rules (file types, sizes, licenses), on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```

## Rating questions

Besides the standard criteria (fit, fun, quality, value, performance, risk, scope):

- Does it fit the game's mood, and is it still pleasant on the hundredth listen?
- Is the volume balanced with the other sounds, and does music loop cleanly?
- Is the origin recorded honestly in the manifest?

Audio also needs the community vote (👍/👎, 24 hours).
