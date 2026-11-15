# Bosses

## Purpose

Boss fights with several phases. A boss is the high point of a biome: spectacle that stays fair and readable for 1 to 4 players.

This README is the guide to making one. The first boss, **the Old Broom** (`old_broom/`, docs/milestones/boss-old-broom.md), is its example. Each step of that plan that adds a general piece brings this guide up to date. Parts marked "coming in OBn" are not built yet.

## What a boss is

A boss is an enemy (content/enemies/README.md) with `boss = true`. It is **data, with no script of its own**: how it fights comes from its staffs and its profiles, as for every enemy (docs/milestones/M2-enemy-ai.md). A behaviour the AI lacks goes into `gameplay/ai/` for every enemy, never into one boss.

- **Its data** is an `EnemyBase` (`core/base/enemy_base.gd`) in the boss's `.tres`: `id` (its folder's name), `display_name` ("The Old Broom"), `lore`, `max_health`, `move_speed`, `contact_damage`, `boss = true`, `size`, `hit_color`, and where it fights (`biomes`, `min_depth`; a run's boss room takes a boss of its biome, docs/milestones/run-generation.md).
- **Its lore** (`lore`): why it fights, in one line of at most 60 characters (docs/STORY.md: "Bosses are powerful old staffs with a grudge, each with a reason"). The story check (`Registry.validate_story`) holds it to the rules, and warns about a boss with none. Its name and story join docs/STORY.md's canon in the same PR. The entrance banner shows it (coming in OB16).
- **Its staffs** are its own: `StaffCards` sub-resources of its `.tres`, never files in `content/wizard/staffs/` (the players' item pool). Each is a `StaffBase` (its `slots`, its `wind_up`, which is the telegraph, its `cooldown` and its own mana) and its cards, player card ids in slot order (docs/milestones/M2-staffs.md, "Reading a staff"). A staff can hold two casts one after the other, each with its own wind-up (the broom's double Sweep: `draw = 1`, two carriers).
- **Its profile** (`profile`, an `AIProfile`): how it plays, also a sub-resource of its `.tres`, never in the shared `content/enemies/profiles/`.
- **Its phases** (`phases`, `EnemyPhase`): each starts by its condition (`health_below` a share of the most, or `after_seconds`), once, in order; the boss stands protected for its `transition`, then fights with the phase's `staffs` (all of them: list again the ones that stay), its `profile` and its `look` (`PhaseLook`: a body texture, a face style and glow, a size). Phase adds (the phase brings its own enemies, so the boss works in any room) and health by player count are coming in OB13.
- **Its scene** is an actor like an enemy's (see the broom's): `Health`, `Hurtbox` (a circle as wide as its body), `Contact`, `Mover`, `Footprint` (its feet against the walls), `Caster`, the `AIController`, its `CreatureLook`, its `Sprite` and a `Face`. A layered body and poses are coming in OB8; actor stats (power, mass, spell scale, resistances) in OB7.
- **Its sounds** are named in its cues, `content/cues/<boss>_*.tres` (cues must sit in `content/cues`, where Feel finds them); held sounds and music with intensity are coming in OB15.
- **Its room** (optional): its best arena, a room of the `boss` kind in its biome (`content/rooms/<biome>/`). The fight must still work in any room.

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
- **A boss can be deleted by deleting its files** (decision 28 of the broom's plan): its folder, its room, its cues (`content/cues/<boss>_*.tres`), its sounds and music in `audio/` with their lines in `audio/manifest.json`, and its lines in docs/STORY.md. So no general code, test or default names a boss or is tuned to it: its numbers live in its own data. A test of boss behaviour builds its own small boss (`tests/gameplay/ai/test_ai_phases.gd`); only the tests that walk all content find bosses, through the registry, and pass with none.

## Allowed files

`.tres`, `.gd` (its test only), `.tscn` (saved as text), sprites (`.png` or `.svg`), `assets.json`, plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Boss audio goes through the Audio area, not this folder. Typed GDScript only; no banned APIs.

## Steps

1. Copy `old_broom/` to `content/bosses/<id>/` and rename its files; set `id` to the folder's name and point `scene` and the sprites at the new folder.
2. Give it a name and its line of lore, and add its name and story to docs/STORY.md.
3. Write its staffs (the cards, the `wind_up` that telegraphs each attack), its profile and its phases in the `.tres`; set `biomes` to the biome whose runs it ends.
4. Replace the sprites and the face's `anchor` and `glow`; list each sprite in its `assets.json`; commit the `.uid` and `.import` files Godot creates.
5. Rewrite its test for its own data. Try it in the sandbox's enemy arena (pause menu, Sandbox: pick it, Spawn, "AI view: On").
6. Run the checks below, then open a PR with a GIF or video of the whole fight.

## Example to copy

`content/bosses/old_broom/` (the Old Broom, v0 of boss OB3): `old_broom.tres` (its Sweep `reach · bigger · dash` with a 0.8 s wind-up, its dust flick `scatter · slow · bolt`, its swat `bigger · heavy · swing`, its profile; phase 2 "Spring cleaning" under 55% health, with a double Sweep that leaves burning pools (`timer · reach · bigger · dash · slow · fire · pool`, twice), a faster profile and its burning look), `old_broom.tscn`, `idle.svg` and `burning.svg` (placeholders until its layered look, OB8 and OB9), `assets.json` and `test_old_broom.gd`.

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
