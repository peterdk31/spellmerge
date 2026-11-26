# Bosses

## Purpose

Boss fights with several phases, fair and readable for 1 to 4 players. The example is **the Old Broom** (`old_broom/`, docs/milestones/boss-old-broom.md).

## What a boss is

A boss is an enemy (content/enemies/README.md) with `boss = true`: **data, with no script of its own**. A behaviour the AI lacks goes into `gameplay/ai/` for every enemy, never into one boss.

- **Data:** an `EnemyBase` (`core/base/enemy_base.gd`) `.tres`: `id` (the folder's name), `display_name`, `lore`, `max_health`, `health_per_player` (share added per player after the first, live), `move_speed`, `contact_damage`, `boss = true`, `size`, `hit_color`, `stats`, `biomes`, `min_depth`.
- **Stats:** `stats`, an `ActorStats` sub-resource (core/base/actor_stats.gd): `power`, `mass`, `spell_scale` (size, never reach), `resist_burn`, `resist_chill`, `resist_gust`, `resist_hex`, `resist_static`, `resist_possess`. A phase may set its own (`EnemyPhase.stats`; null keeps the last).
- **Lore:** one line, at most 60 characters; `Registry.validate_story` checks it. Add its name and story to docs/STORY.md in the same PR.
- **Staffs:** `StaffCards` sub-resources of its `.tres`, never files in `content/wizard/staffs/`. Each `StaffBase` has `slots`, `wind_up` (the telegraph), `cooldown` (up to 30 s), `first_wait`, its mana, and player card ids in slot order. Moment cues: `wind_cue`, `move_cue`, `cast_cue`, `wall_cue`.
- **Moves** are its cards' (dash, Lumber, Plow, ...): a dash's pass is its hurt shape times `radius_mult`, never times `spell_scale`; keep it inside what the body's art shows. Nothing about a move is the boss's own.
- **Profile:** `profile`, an `AIProfile` sub-resource (never in `content/enemies/profiles/`): `aim_lock`, `turns`. Running up for a long move and walking round props are the AI's.
- **Phases:** `phases`, `EnemyPhase`: a condition (`health_below` or `after_seconds`), once, in order; protected for `transition`; then its `staffs` (list all, including ones that stay), `stats`, `profile`, `look` (`PhaseLook`: texture, face style, `face_row`, size, `parts`, `motes`, `motes_on`, `sound`, `cue`), `intensity`.
- **Adds:** `EnemyPhase.adds` (`EnemyAdds`, core/base/enemy_adds.gd): `enemy` (a `content/enemies/` id, never a boss), `count`, `per_player`, `every`, `wave_count`, `wave_per_player`, `cap`, `cap_per_player`, `at`. They crumble when the boss dies.
- **Scene:** an actor like an enemy's: `Health`, `Hurtbox`, `Contact`, `Mover`, `Footprint`, `Caster`, `AIController`, `CreatureLook` (`full_speed`, `hops`), `Sprite`, `Face`. `Stats` is added by the body from its data.
- **Sounds:** its cues are `content/cues/` files with a prefix of its own (cues must sit in `content/cues`); each names a sound id whose recipe is `audio/sfx/<id>/`. A cue's `held` part lasts as long as its moment. `death_sound` replaces `boss_death`'s.
- **Intro:** `boss_intro`, a `BossIntro` sub-resource (core/base/boss_intro.gd; docs/milestones/boss-intro.md): `portrait` (three 96×96 frames, or 192×192 at `@2x`: rest, mean, eyes), `lines` (at most three, at most 60 characters, the boss alone speaking), `accent` (a docs/STYLE.md ramp), `dark_cue`, `reveal_cue`. Checked by `BossIntro.problems`.
- **Music:** `music`, a `MusicTrack` sub-resource (core/base/music_track.gd): layers `stacked` or entries; each phase raises the intensity.
- **Room (optional):** a `boss` kind room in its biome, in a folder of its own (`content/rooms/<biome>/boss_<id>/`). The fight must work in any room.

### Its look

A **layered body**: its `Sprite` shows no art and holds `BodyPart` nodes (gameplay/actor/body_part.gd) in a tree (`position` is the pivot, `offset` places the art, `show_behind_parent`). Numbers: `lean`, `lag`, `swish`, `swish_rate`, `squash`, `sway`, `wall_squash`, `shudder`, `tap`, `taps`, `tap_every`, `fling`, `carries_face`; `pose_frames` per `BodyPose.Pose` (IDLE, WINDUP, MOVE, WALL, HURT, CAST, TRANSITION). Its face is its own: `Face` names a `FaceArt` (core/base/face_art.gd) with its own eye and brow sheets in the shared layout. On death the parts fly apart (gameplay/feel/remnants.gd). All of it is drawn only. A one-sprite boss still works.

Reviewed in play: `tests/screenshots/shot_boss_looks.gd` films every boss's poses (`boss_<id>_<clip>`, `boss_<id>_sheet`): `ci/build/build.sh --quick --screenshots` with `SHOTS_ONLY=shot_boss_looks`.

### What is still engine work

A boss needing one of these needs the general piece built in the shared engine first:

| Kind of boss | The general piece it needs first |
| --- | --- |
| Several bodies | Bodies that share health or a phase, and a fight that ends when all are down |
| Parts and weak spots | Bodies attached to a body, each with its own health and hit shape |
| Changes the arena | Rooms whose layout changes in play, and floors that hurt |
| Too big for the screen | A body the camera and the room frame differently |
| Hurt only after an action | Invulnerability by a condition |
| Fights with the players' own builds | Reading another body's cards |

## Contract

- A boss is one folder, `content/bosses/<id>/`: its `.tres` (staffs, profiles, phase looks as sub-resources), `.tscn`, sprites, `assets.json` and its own test `test_<id>.gd`. `EnemyBase.problems()` must be empty.
- Each phase changes behaviour clearly; every attack has a visible telegraph (`wind_up` and the cast's lane). Never hit without warning.
- Targeting considers every player (seats 0–3); a downed player can be revived; the fight never waits for anyone.
- Use pools and the projectile manager; respect the projectile cap. Communicate only through `core/` events. Original names and art only.
- **A boss can be deleted by deleting its files:** its folder, its room, its prefixed cues, its `audio/` sounds and music with their `audio/manifest.json` lines, its docs/STORY.md lines. No general code, test or default names a boss or is tuned to it. A boss-behaviour test builds its own small boss (`tests/gameplay/ai/test_ai_phases.gd`); content-walking tests find bosses through the registry and pass with none.

## Allowed files

`.tres`, `.gd` (its test only), `.tscn` (text), sprites (`.png` or `.svg`), `assets.json`, plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB otherwise. Boss audio goes through the Audio area. Typed GDScript only; no banned APIs.

## Steps

1. Copy `old_broom/` to `content/bosses/<id>/`, rename its files; set `id` (the boss's and each staff's) to the folder's name; point `scene` and sprites at the new folder.
2. Give it a name and a line of lore; add both to docs/STORY.md.
3. Write its staffs, profile and phases in the `.tres`; set `biomes`.
4. Replace the parts' art (grids `<part>.grid.json` via `tools/pixel_grid.py`, or `tools/enemy_art.py`), pivots, offsets, frames, numbers, face sheets, `anchor`, `glow`; list each sprite in `assets.json`; commit the `.uid` and `.import` files.
5. Rewrite its test for its own data; play it in a one-room run (`bench/pinned_run.gd`, `fill` boss).
6. Run the checks; open a PR with a GIF or video of the whole fight.

## Example to copy

`content/bosses/old_broom/`: `old_broom.tres` (Sweep, dust flick, swat, Big Sweep; phase 2 "Spring cleaning" under 55%), `old_broom.tscn` (`Head`, `Handle`, `Binding`), `@2x` art, `portrait@2x.svg`, `eyes@2x.svg`, `brows@2x.svg`, `assets.json`, `test_old_broom.gd`.

## Tests

- `content/bosses/<id>/test_<id>.gd`, `tests/content/bosses/test_boss_intros.gd`, `tests/gameplay/ai/test_ai_phases.gd`, `tests/screenshots/shot_boss_looks.gd`.

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

- Is the fight fair: all attacks telegraphed and avoidable? Spectacle and distinct phases?
- Does it scale from 1 to 4 players?
- Can it be deleted by deleting its files, with nothing else naming it?

History and reasons: [docs/history/content-bosses-README.md](../../docs/history/content-bosses-README.md).
