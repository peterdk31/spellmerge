# Enemies

## Purpose

Regular enemies and their attack patterns. Enemies create the "readable chaos" of the game: clear telegraphs, distinct roles, fair at any player count.

**Built in M3** (Run structure; see docs/ROADMAP.md). A small M1 base class already exists (`core/base/enemy_base.gd`, `EnemyBase`); M3 extends it. The example to copy is the Cinder Rod, `content/enemies/ember_imp/`.

## Contract

- An enemy is one folder with a `.tres` resource on the enemy base class (`EnemyBase`, with the M1 fields `id`, `demo`, `max_health`, `move_speed`, `contact_damage` and `scene`, and its staff; M3 extends it), a `.tscn` scene (an actor: see the example) and sprites; an optional `.gd` only for a new kind of behaviour.
- Use the shared behaviours from `gameplay/ai` (steering, targeting) through the base class; do not reimplement them. Targeting considers every actor of another team (the wizards, whatever their seat).
- Every attack has a visible telegraph before it deals damage.
- Enemy health and count scale with player count; use the scaling the base class provides rather than your own.
- Enemies come from pools; no per-frame allocations. Respect the particle and sprite sheet limits (1 MB per sprite sheet; validators for the rest arrive when M3 extends the base class).
- Communicate only through `core/` events (`enemy_died`, ...). Original names and art only.

- **Enemies cast staffs (staffs F8a, docs/milestones/M2-staffs.md "Enemy staffs"):** set `staff` (a `StaffBase`), `cards` (player card ids by slot), `max_mana` and `mana_regen` on the `.tres`, and the enemy attacks by casting them like a wizard and paying mana; its telegraph shows the next cast's reach. A new enemy type is then a sprite, a scene and a staff, with no code. An enemy without a staff only chases (and hurts by touch with `contact_damage`); the attack's own numbers are the `AIController`'s exports `attack_range`, `windup_time` and `recover_time`. The ember imp casts `fire · bolt` (10 mana, 3 a second back) and the shooting dummy `slow · bolt` (5 mana, 2 a second back), each staff a sub-resource of the enemy's `.tres` (staffs F9a).
- **Every enemy is a stray** (living staffs H5, docs/milestones/M2-living-staffs.md, "The strays"): one of the wizard's earlier staffs, thrown out like the players and gone sour. A stray is a 32×32 body sprite (a staff, its ferrule at the bottom), the shared `Face` (`gameplay/actor/face.gd`: style `STRAY`, or `STRAY_ONE` for one eye; `resting_mood` angry; `glow` the light shade of its element's ramp; `anchor` the left eye's top-left pixel in the actor's space) after its `CreatureLook` in the scene, and a staff of player cards. It hops; its face goes furious while it winds up. The strays now: **the Cinder Rod** (`ember_imp/`, the id kept: fire · bolt, the shooter), **the Splinter** (`splinter/`: dash, a swarmer that lunges and hurts by touch, one eye) and **the Storm Fork** (`storm_fork/`: triple · lightning · bolt, the spreader). Waiting for their cards: the Rime Crook (frost · hook: needs `hook`) and the Bone Scepter (void · rain: needs `rain`).

## Allowed files

`.tres`, `.gd`, `.tscn` (saved as text), sprites (`.png` or `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs; load only with literal `res://` paths.

## Steps

1. Copy the example folder and rename it.
2. Edit the `.tres` values and the scene; replace the sprites (see `docs/STYLE.md`).
3. Add an attack pattern `.gd` only if the existing ones do not fit.
4. Add each asset to `art/manifest.json`; commit the `.uid` files Godot creates.
5. Run the checks below, then open a PR with a short GIF of the enemy in action.

## Example to copy

`content/enemies/ember_imp/` (the Cinder Rod): `ember_imp.tres` (an `EnemyBase` with `id`, `max_health`, `move_speed`, `contact_damage`, `scene`, and its staff: `staff`, `cards`, `max_mana`, `mana_regen`), `ember_imp.tscn` and its body `idle.svg` (with its `.import` and its entry in `art/manifest.json`; a new enemy lists its art in an `assets.json` in its folder, like `splinter/`). A new enemy type is that folder copied, with a new body, face anchor and glow, and numbers: no code.

Since actors G6 (docs/milestones/M2-actors.md) the scene is an **actor**: its root is a `CharacterBody2D` with `gameplay/actor/actor.gd` (`hand_offset` and `body_offset` (0, -12), `staff_reach` 0, so its spells start at its body), and its children are the actor kit's components, which the actor fills from the `.tres`: `Health`, `Hurtbox` (radius 11, offset (0, -12)), `Contact`, `Mover`, `Caster`; the `AIController` (`gameplay/ai/ai.gd`: chase the nearest actor of another team, telegraph, cast; its exports `attack_range`, `windup_time` and `recover_time` are the attack's numbers); the `CreatureLook` (`gameplay/ai/creature_look.gd`: the hop, the flash, the telegraph, and optional poses `windup_texture` and `hurt_texture` that no stray uses); the `Face` (after the look); the `Telegraph` (a `Sprite2D` on `art/vfx/beam.svg` with a scene-local `ShaderMaterial` of `gameplay/ai/telegraph.gdshader`, its colours in `ramp_base` and `ramp_light`, Fire for the imp; the look sets its length, lane and progress); the `Sprite` (named so: Feel and the decoys find it by name) and a `CollisionShape2D` (walls). Leave out what an enemy does not need: no staff in the `.tres` means no attack (it chases and hurts by `contact_damage`). The imp has no contact damage: its only damage is the telegraphed cast. Its tests are `tests/gameplay/ai/test_ai.gd` and `tests/content/enemies/test_strays.gd` (every stray).

The sandbox dummies (staffs B7), which flow stands only in the sandbox room, are actors too, drawn as staffs staked in the floor (living staffs H5; no face: they are props, not strays): `training_dummy/` (Health with a billion, a Hurtbox at (0, -14), no controller and no Mover, so it never dies or moves; on the enemies' team by its `idle_team`, so enemies never target it; its `DummyLook` from `gameplay/ai/dummy_look.gd` shows damage numbers from `damage_dealt`, damage per second over the last 5 s from its health in Combat so burn ticks count, its statuses and the last reaction) and `shooting_dummy/` (the imp's parts with no walking speed and a slow cast behind a long telegraph, aimed at the nearest wizard). Both are `demo`, so the web preview has them. Test: `tests/content/enemies/test_dummies.gd`.

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
