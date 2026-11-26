# Enemies

## Purpose

Regular enemies: a body, its staffs and how it plays them, with clear telegraphs, distinct roles, fair at any player count. An enemy is data (`EnemyBase`, `core/base/enemy_base.gd`) and a scene. The example to copy is the Cinder Rod, `content/enemies/ember_imp/`.

## Contract

- **One folder per enemy:** a `.tres` on `EnemyBase` (`id`, `display_name`, `max_health`, `move_speed`, `contact_damage`, `scene`, `size`, `hit_color`, `staffs`, `profile`, `phases`, `lore`, `stats` (an `ActorStats`, null for the defaults)), a `.tscn` scene (an actor) and sprites.
- **No `.gd` per enemy, a boss included:** how it fights comes from its staffs and profile; a kind of behaviour the AI lacks goes into `gameplay/ai/behaviours/` for every enemy.
- **Every enemy plays by the enemy AI** (dummies and swarmers included): its scene has an `AIController`, its data a `profile`.
- **Staffs:** 1–4 `staffs`, each a `StaffCards` (a `StaffBase` with `max_mana`, `mana_regen` and `cards`, player card ids by slot, no more than its slots). No staff = it only chases and hurts by `contact_damage`. The enemy pays mana like a player; range comes from its staffs' reach, its telegraph from the staff's `wind_up`, its lane from the cast card's `wind_cue`.
- **Profiles** (`AIProfile`) are shared presets in `profiles/`: `shooter`, `rusher`, `zoner`, `dummy`, `post`, `swarmer`, `sprayer`. `profiles/aim_tuning.tres` is the enemies' `AimTuning`, not a profile (gameplay/ai/README.md, "Aim").
- `EnemyBase.problems()` must be empty. A boss adds `phases` (`EnemyPhase`) and a `size`.
- The AI targets every actor of another team, never "the player".
- Every attack has a visible telegraph before it deals damage.
- Health and count scale with player count through the base class's scaling, never your own.
- Enemies come from pools; no per-frame allocations. 1 MB per sprite sheet.
- Talk only through `core/` events (`enemy_died`, ...). Original names and art only.
- **Every enemy is a stray** (docs/milestones/M2-living-staffs.md, "The strays"): a 32-unit body sprite (a staff, ferrule at the bottom), the shared `Face` (`gameplay/actor/face.gd`: style `STRAY` or `STRAY_ONE`; `resting_mood` angry; `glow` its element's light shade; `anchor` the left eye's top-left pixel) after its `CreatureLook`. Swarmers (`swarmer` profile) have no staff, so no `Caster` and no `Telegraph`.
- **Where it fights:** `biomes` (`&"crypt"`), `cost` in a room's enemy budget (at least 1) and `min_depth` (first map row it may stand in, 0 the first room). A biome's pool is every enemy naming it; no biome (the dummies) = in no run.
- **Coins and keys:** `coins` (to `coins_most`, rolled once a body by the run's chance) go into its bag; dropped on death by `coin_drop_chance`; a boss's go to every player. Keys it carries drop by `key_drop_chance`. An add carries none.
- **Spawning in:** `spawn_style`, a style id from content/spawn_styles, wins over its biome's (`SpawnStyle.pick`); empty takes the biome's, or `rise`.
- **Standing in a room:** a room places an enemy with an `EnemyStandIn` (tools/enemy_stand_in.gd) under `Dummies`; Flow stands the real enemy (content/rooms/README.md).

## Allowed files

`.tres`, `.gd`, `.tscn` (saved as text), sprites (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs; load only with literal `res://` paths.

## Steps

1. Copy the example folder and rename it.
2. Edit the `.tres` values and the scene; replace the sprites (see `docs/STYLE.md`).
3. Give it `staffs` and a `profile`; set `biomes`, `cost`, `min_depth`; try it in a run of one room (`bench/pinned_run.gd`).
4. List its art in an `assets.json` in its folder (like `splinter/`); commit the `.uid` files Godot creates.
5. Run the checks below, then open a PR with a short GIF of the enemy in action.

## Example to copy

`content/enemies/ember_imp/` (the Cinder Rod): `ember_imp.tres` (its numbers, one `StaffCards`, its `profile`), `ember_imp.tscn` and its body `idle@2x.svg` (drawn by `tools/enemy_art.py` from parts of its own: a new enemy's body is a function there). A new enemy is that folder copied with a new body, face anchor, glow and numbers: no code.

The scene is an **actor**: root a `CharacterBody2D` with `gameplay/actor/actor.gd` (`hand_offset` and `body_offset` (0, -12), `staff_reach` 0), children the actor kit's components filled from the `.tres`: `Health`, `Hurtbox`, `Contact`, `Mover`, `Caster`, the `AIController` (`gameplay/ai/ai.gd`; the scene holds no AI numbers), the `CreatureLook` (`gameplay/ai/creature_look.gd`; a body in `BodyPart`s is a boss's: content/bosses/README.md, "Its look"), the `Face` (after the look), the `Sprite` (named so: Feel and the decoys find it by name) and a `CollisionShape2D`. Leave out what it does not need.

The dummies are actors drawn as staffs staked in the floor (props, no face): `training_dummy/` (huge health, no Mover, no staff, `post` profile, a `DummyLook` from `gameplay/ai/dummy_look.gd`) and `shooting_dummy/`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

Tests: `tests/content/enemies/test_enemy_data.gd` (every enemy's data and scene), `tests/content/enemies/test_strays.gd`, `tests/content/enemies/test_swarmers.gd`, `tests/content/enemies/test_dummies.gd`, `tests/gameplay/ai/test_ai.gd`, and an enemy's own test in its folder (`spitter/test_spitter.gd`).

## Review questions

Besides the general review:

- Are the telegraphs readable at 1× with 4 players and many projectiles on screen?
- Does it scale sensibly from 1 to 4 players?
- Is it a distinct role, not a re-skin of an existing enemy?

History and reasons: [docs/history/content-enemies-README.md](../../docs/history/content-enemies-README.md).
