# Bosses

## Purpose

Boss fights with several phases. A boss is the high point of a biome: spectacle that stays fair and readable for 1 to 4 players.

This README is the guide to making one. The first boss, **the Old Broom** (`old_broom/`, docs/milestones/boss-old-broom.md), is its example. Each step of that plan that adds a general piece brings this guide up to date. Parts marked "coming in OBn" are not built yet.

## What a boss is

A boss is an enemy (content/enemies/README.md) with `boss = true`. It is **data, with no script of its own**: how it fights comes from its staffs and its profiles, as for every enemy (docs/milestones/M2-enemy-ai.md). A behaviour the AI lacks goes into `gameplay/ai/` for every enemy, never into one boss.

- **Its data** is an `EnemyBase` (`core/base/enemy_base.gd`) in the boss's `.tres`: `id` (its folder's name), `display_name` ("The Old Broom"), `lore`, `max_health`, `move_speed`, `contact_damage`, `boss = true`, `size`, `hit_color`, its `stats` (below), and where it fights (`biomes`, `min_depth`; a run's boss room takes a boss of its biome, docs/milestones/run-generation.md).
- **Its stats** (`stats`, an `ActorStats` sub-resource of its `.tres`, core/base/actor_stats.gd; boss plan OB7): `power` (× the damage of its spell hits, their slams and burns; not its contact damage), `mass` (a shove on it is divided by it), `spell_scale` (× the size of its spells: a shot's radius, a blast, a pool, a pulse's ring, a swing's arc; a big body's attacks are as big as it is; how far a flight or a beam reaches stays its cards', `reach`, decision 16), and a share resisted of each status (`resist_burn`, `resist_chill` (a freeze too), `resist_gust`, `resist_hex`, `resist_static`) and of a possession (`resist_possess`): it lasts (1 - share) as long. A phase may name its own (`EnemyPhase.stats`; null keeps the last). The defaults change nothing. Its numbers are its own data's (the broom's: power 2, then 2.5, mass 6, spell scale 1.5, chill 0.6, burn 0.3, possess 0.7).
- **Its lore** (`lore`): why it fights, in one line of at most 60 characters (docs/STORY.md: "Bosses are powerful old staffs with a grudge, each with a reason"). The story check (`Registry.validate_story`) holds it to the rules, and warns about a boss with none. Its name and story join docs/STORY.md's canon in the same PR. The entrance banner shows it (coming in OB16).
- **Its staffs** are its own: `StaffCards` sub-resources of its `.tres`, never files in `content/wizard/staffs/` (the players' item pool). Each is a `StaffBase` (its `slots`, its `wind_up`, which is the telegraph, its `cooldown` and its own mana) and its cards, player card ids in slot order (docs/milestones/M2-staffs.md, "Reading a staff"). A staff can hold two casts one after the other, each with its own wind-up (the broom's double Sweep: `draw = 1`, two carriers).
- **Its moves** (boss plan OB10) are its cards' too: a dash strikes what its body meets (its pass is as wide as its hurt shape, times its cards' `radius_mult` and its `spell_scale`), ends where a wall, a blocking prop or a Wall card's stones stop it head on (a glancing one slides on), and goes at its cards' speed curve (`move_start`, `move_end`, `move_ease`: Lumber lurches off and drags to a stop), still its whole way in its time. Nothing about a move is the boss's own.
- **Its profile** (`profile`, an `AIProfile`): how it plays, also a sub-resource of its `.tres`, never in the shared `content/enemies/profiles/`.
- **Its phases** (`phases`, `EnemyPhase`): each starts by its condition (`health_below` a share of the most, or `after_seconds`), once, in order (one met while the boss is possessed starts when the possession ends, OB7); the boss stands protected for its `transition`, then fights with the phase's `staffs` (all of them: list again the ones that stay), its `stats`, its `profile` and its `look` (`PhaseLook`: a body texture, a face style and glow, the row of its own face (`face_row`, OB9: the broom's angrier eyes and singed brows), a size, its layered body's parts' art by part name (`parts`) and motes that follow the body from one part (`motes`, `motes_on`: the broom's burning head and its sparks); boss plan OB8). Phase adds (the phase brings its own enemies, so the boss works in any room) and health by player count are coming in OB13.
- **Its scene** is an actor like an enemy's (see the broom's): `Health`, `Hurtbox` (a circle as wide as its body), `Contact`, `Mover`, `Footprint` (its feet against the walls), `Caster`, the `AIController`, its `CreatureLook`, its `Sprite` and a `Face`. Its `Stats` component is added by the body itself, filled from its data's `stats`.
- **Its look** (boss plan OB8) is a **layered body**: its `Sprite` shows no art and holds its parts, `BodyPart` nodes (gameplay/actor/body_part.gd), each a frame of any size (a strip of frames for its poses), in a tree (a part moves in its parent's frame; `show_behind_parent` puts one behind its parent). A part's `position` is where it turns from, its `offset` places its art. Its numbers say how the game moves it: `lean` into the way it goes (it swings back past upright as it brakes, and rears back from its aim as it winds up), `lag`, `swish` and `swish_rate`, `squash` on the floor, `sway` standing, `wall_squash` and `shudder` when its own move meets a wall (and the shudder all through a phase change), `tap`, `taps` and `tap_every` (a part on the floor lifts and drops a few times in quick succession while it stands idle: the broom's impatient tap, OB9), `fling` (how far it flies when it dies) and `carries_face`; `pose_frames` gives the drawn frame of each pose (`BodyPose.Pose`: IDLE, WINDUP, MOVE, WALL, HURT, CAST, TRANSITION), a few drawn frames for the extreme poses (the broom's head has five: rest, wind-up, wall hit, swat, and the straw catching fire through the phase change on its burning head). **Its face is its own** (OB9, decision 14): its `Face` names a `FaceArt` (core/base/face_art.gd, a sub-resource of its scene) with its own eye and brow sheets in the shared layout at any frame size (ten eye columns, nine looks and the blink; a brow a mood; a row a look of the face), drawn in its folder; its `style` still sets its blinks and glances. **Its look is reviewed in play:** `tests/screenshots/shot_boss_looks.gd` plays every boss of the registry in a room of its biome that hosts bosses against a protected wizard and records each pose as a filmstrip named by pose (`boss_<id>_<clip>`: idle, windup, move, wall, cast, hurt, transition, phase_idle, phase_windup, phase_move, death), each frame sized from its art, and a sheet (`boss_<id>_sheet`): `ci/build/build.sh --quick --screenshots` (`SHOTS_ONLY=shot_boss_looks`). Its `CreatureLook` says the speed at which the parts move whole (`full_speed`) and whether it hops (`hops`: false for a body that hovers). **The poses come from states the game has** (`BodyPose`): a phase change, a wall, a hit, a wind-up, its own move, a cast, idle. **When it dies** its parts fly apart where it fell, a remnant Feel draws (gameplay/feel/remnants.gd), and each breaks into a share of its motes. All of it is drawn only. A boss of one sprite still works: its `Sprite` shows its art, as an enemy's does.
- **Its sounds** are named in its cues, `content/cues/` files whose names start with a prefix of its own (the broom's `broom_*.tres`; cues must sit in `content/cues`, where Feel finds them); held sounds and music with intensity are coming in OB15.
- **Its room** (optional): its best arena, a room of the `boss` kind in its biome (`content/rooms/<biome>/`; the broom's: `content/rooms/crypt/boss_broom/`, a folder of its own so it is deleted with the boss). The fight must still work in any room.

### What is still engine work

A boss that needs one of these needs that general piece built first (in the shared engine, so every enemy gains it), before it can be data and art only:

| Kind of boss | The general piece it needs first |
| --- | --- |
| Several bodies (twin staffs, a broom and its dustpan) | Bodies that share health or a phase, and a fight that ends when all are down |
| Parts and weak spots (a crystal to break on a giant staff) | Bodies attached to a body, each with its own health and hit shape |
| Changes the arena (floods it, raises walls, drops the floor) | Rooms whose layout changes in play, and floors that hurt |
| Too big for the screen, or attacking from its edge | A body the camera and the room frame differently |
| Hurt only after an action (a puzzle) | Invulnerability by a condition |
| Fights with the players' own builds (copies a staff) | Reading another body's cards (the inventory comes close) |

## Contract

- A boss is one folder, `content/bosses/<id>/`: its `.tres` (an `EnemyBase` with `boss = true`; its staffs, profiles and phase looks inside it as sub-resources), its `.tscn`, its sprites, its `assets.json` and its own test, `test_<id>.gd`. `EnemyBase.problems()` must be empty.
- Each phase has a clear change in behaviour and a visible telegraph for every attack (its staff's `wind_up` and the cast's lane). Bosses never hit without warning.
- Targeting considers every player (seats 0–3); a downed player can be revived and the fight never waits for anyone.
- Use pools and the projectile manager; respect the global projectile cap. Communicate only through `core/` events. Original names and art only.
- **A boss can be deleted by deleting its files** (decision 28 of the broom's plan): its folder, its room, its cues (`content/cues/` files of its own prefix), its sounds and music in `audio/` with their lines in `audio/manifest.json`, and its lines in docs/STORY.md; this guide's example then moves to another boss. So no general code, test or default names a boss or is tuned to it: its numbers live in its own data. A test of boss behaviour builds its own small boss (`tests/gameplay/ai/test_ai_phases.gd`); only the tests that walk all content find bosses, through the registry, and pass with none.

## Allowed files

`.tres`, `.gd` (its test only), `.tscn` (saved as text), sprites (`.png` or `.svg`), `assets.json`, plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Boss audio goes through the Audio area, not this folder. Typed GDScript only; no banned APIs.

## Steps

1. Copy `old_broom/` to `content/bosses/<id>/` and rename its files; set `id` to the folder's name, the boss's and each of its staffs' (the spell validator holds a staff in an enemy's `.tres` to the folder's name), and point `scene` and the sprites at the new folder.
2. Give it a name and its line of lore, and add its name and story to docs/STORY.md.
3. Write its staffs (the cards, the `wind_up` that telegraphs each attack), its profile and its phases in the `.tres`; set `biomes` to the biome whose runs it ends.
4. Replace the parts' art (the broom's are grids, `<part>.grid.json`, that `tools/pixel_grid.py` makes into SVGs), their pivots, offsets, frames and numbers, the face's own sheets (`eyes`, `brows`) and its `anchor` and `glow`; list each sprite in its `assets.json`; commit the `.uid` and `.import` files Godot creates.
5. Rewrite its test for its own data. Try it in the sandbox's enemy arena (pause menu, Sandbox: pick it, Spawn, "AI view: On").
6. Run the checks below, then open a PR with a GIF or video of the whole fight.

## Example to copy

`content/bosses/old_broom/` (the Old Broom, v0 of boss OB3): `old_broom.tres` (its Sweep `bigger · lumber · dash` (Lumber since OB4) with a 0.8 s wind-up, its dust flick `triple · slow · bolt · slow · bolt · slow · bolt` (three slow bolts at its target with a 10 degree spread, OB10, decision 34; it was `scatter · slow · bolt`, which ignored the aim), its swat `bigger · heavy · swing`, its profile; phase 2 "Spring cleaning" under 55% health, with a double Sweep that leaves burning pools (`timer · bigger · lumber · dash · slow · fire · pool`, twice), a faster profile and its burning look: the head's art and its sparks), `old_broom.tscn` (its layered body since OB8: a bristle `Head` on the floor, swishing, trailing and squashing, with its `Handle` behind it, leaning, and its `Binding`, which carries the face), its look since OB9 (for the owner's review): the parts' placeholder art, `head.svg` and `head_burning.svg` (five frames each), `handle.svg` and `binding.svg`, and its own face, `eyes.svg` and `brows.svg` (an old staff's heavy-lidded eyes and bushy brows, a second row angrier for phase 2), all with their grids, `assets.json` and `test_old_broom.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

Besides the general review:

- Is the fight fair: are all attacks telegraphed and avoidable?
- Does it have spectacle and distinct phases?
- Does it scale from 1 to 4 players?
- Can it be deleted by deleting its files, with nothing else naming it?
