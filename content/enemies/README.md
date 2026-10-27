# Enemies

## Purpose

Regular enemies and their attack patterns. Enemies create the "readable chaos" of the game: clear telegraphs, distinct roles, fair at any player count.

**Built in M3** (Run structure; see docs/ROADMAP.md). A small M1 base class already exists (`core/base/enemy_base.gd`, `EnemyBase`); M3 extends it. The example to copy is the M1 ember imp, `content/enemies/ember_imp/`.

## Contract

- An enemy is one folder with a `.tres` resource on the enemy base class (`EnemyBase`, with the M1 fields `id`, `demo`, `max_health`, `move_speed`, `contact_damage` and `scene`; M3 extends it), an optional `.gd` for a new attack pattern, a `.tscn` scene and sprites.
- Use the shared behaviours from `gameplay/ai` (steering, targeting) through the base class; do not reimplement them. Targeting considers all players, indices 0–3.
- Every attack has a visible telegraph before it deals damage.
- Enemy health and count scale with player count; use the scaling the base class provides rather than your own.
- Enemies come from pools; no per-frame allocations. Respect the particle and sprite sheet limits (1 MB per sprite sheet; validators for the rest arrive when M3 extends the base class).
- Communicate only through `core/` events (`enemy_died`, ...). Original names and art only.

- **Coming in M2 (staffs phase F, docs/milestones/M2-staffs.md "Enemy staffs"):** an enemy attacks by casting a staff of player cards (`staff`, `cards`, `max_mana`, `mana_regen` on `EnemyBase`) and pays mana like a wizard; its telegraph is drawn from the next cast. A new enemy type is then a sprite and a staff, with no code. Until part F9 the imp and the shooting dummy keep the attack exports below.

## Allowed files

`.tres`, `.gd`, `.tscn` (saved as text), sprites (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs; load only with literal `res://` paths.

## Steps

1. Copy the example folder and rename it.
2. Edit the `.tres` values and the scene; replace the sprites (see `docs/STYLE.md`).
3. Add an attack pattern `.gd` only if the existing ones do not fit.
4. Add each asset to `art/manifest.json`; commit the `.uid` files Godot creates.
5. Run the checks below, then open a PR with a short GIF of the enemy in action.

## Example to copy

`content/enemies/ember_imp/`: `ember_imp.tres` (an `EnemyBase` with `id`, `max_health`, `move_speed`, `contact_damage` and `scene`), `ember_imp.tscn` (a `CharacterBody2D` whose root script is `gameplay/ai/ai.gd`, with a collision shape, a `Sprite` and a `Telegraph` line that shows during the windup) and the sprite `idle.svg` (with `idle.svg.import` and its entry in `art/manifest.json`). The attack numbers (range, windup, damage) are exports on the scene root. The imp has no contact damage: its only damage is the telegraphed shot. Its test is `tests/gameplay/ai/test_ai.gd`.

The sandbox dummies (staffs B7), which flow stands only in the sandbox room: `training_dummy/` (its own `training_dummy.gd`: never dies, Combat holds a billion health for it, and never moves; damage numbers from `damage_dealt`, damage per second over the last 5 s from its health in Combat so burn ticks count, its statuses and the last reaction) and `shooting_dummy/` (`gameplay/ai/ai.gd` with no walking and a slow shot behind a long telegraph, aimed at the nearest wizard). Both are `demo`, so the web preview has them. Test: `tests/content/enemies/test_dummies.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

Besides the general review:

- Are the telegraphs readable at 1× with 4 players and many projectiles on screen?
- Does it scale sensibly from 1 to 4 players?
- Is it a distinct role, not a re-skin of an existing enemy?
