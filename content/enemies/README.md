# Enemies

## Purpose

Regular enemies and their attack patterns. Enemies create the "readable chaos" of the game: clear telegraphs, distinct roles, fair at any player count.

**Opens for PRs in M3** (Run structure; see "Opens for PRs" in docs/ROADMAP.md). **The example to copy arrives with Claude's first enemy in M3**; this README is updated then with its path.

## Contract

- An enemy is one folder with a `.tres` resource on the enemy base class (arrives in M3), an optional `.gd` for a new attack pattern, a `.tscn` scene and sprites.
- Use the shared behaviours from `gameplay/ai` (steering, targeting) through the base class; do not reimplement them. Targeting considers all players, indices 0–3.
- Every attack has a visible telegraph before it deals damage.
- Enemy health and count scale with player count; use the scaling the base class provides rather than your own.
- Enemies come from pools; no per-frame allocations. Respect the particle and sprite sheet limits (enforced by validators).
- Communicate only through `core/` events (`enemy_died`, ...). Original names and art only.

## Allowed files

`.tres`, `.gd`, `.tscn` (saved as text), sprites (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs; load only with literal `res://` paths.

## Steps

1. Pick an issue labelled `now` in this area and comment `/claim`.
2. Copy the example folder and rename it.
3. Edit the `.tres` values and the scene; replace the sprites (see `docs/STYLE.md`).
4. Add an attack pattern `.gd` only if the existing ones do not fit.
5. Add each asset to `art/manifest.json`; commit the `.uid` files Godot creates.
6. Run the checks below, then open a PR with a short GIF of the enemy in action.

## Example to copy

Arrives with Claude's first content in M3. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Besides the standard criteria:

- Are the telegraphs readable at 1× with 4 players and many projectiles on screen?
- Does it scale sensibly from 1 to 4 players?
- Is it a distinct role, not a re-skin of an existing enemy?

Art and gameplay changes here also need the community vote (👍/👎, 24 hours).
