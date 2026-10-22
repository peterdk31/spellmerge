# Bosses

## Purpose

Boss fights with several phases. A boss is the high point of a biome: spectacle that stays fair and readable for 1 to 4 players.

**Opens for PRs in M3** (Run structure; see "Opens for PRs" in docs/ROADMAP.md). **The example to copy arrives with Claude's first boss in M3**; this README is updated then with its path.

## Contract

- A boss is one folder with a `.tres` resource on the boss base class (arrives in M3), a `.gd` for its phases and attack patterns, a `.tscn` scene and sprites.
- Each phase has a clear change in behaviour and a visible telegraph for every attack. Bosses never hit without warning.
- Health, attack density and add counts scale with player count (1–4) through the base class. The fight must be fair solo and not trivial with four.
- Targeting considers all players (indices 0–3); a downed player can be revived and the fight never waits for anyone.
- Use pools and the projectile manager; respect the global projectile cap. Communicate only through `core/` events. Original names and art only.

## Allowed files

`.tres`, `.gd`, `.tscn` (saved as text), sprites (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Boss audio goes through the Audio area, not this folder. Typed GDScript only; no banned APIs.

## Steps

1. Pick an issue labelled `now` in this area and comment `/claim`.
2. Copy the example folder and rename it.
3. Define the phases in the `.tres` and the patterns in the `.gd`.
4. Replace the sprites; add each to `art/manifest.json`; commit `.uid` files.
5. Run the checks below, then open a PR with a GIF or video of the whole fight.

## Example to copy

Arrives with Claude's first content in M3. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Rating questions

Besides the standard criteria:

- Is the fight fair: are all attacks telegraphed and avoidable?
- Does it have spectacle and distinct phases?
- Does it scale from 1 to 4 players?

Art changes (sprites) also need the community vote (👍/👎, 24 hours).
