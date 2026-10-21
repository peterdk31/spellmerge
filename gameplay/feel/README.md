# Feel

## Purpose

Hit-stop, screen shake and juice presets.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Feel only reacts: it never changes damage or outcomes. Hit-stop is its only effect on timing; it is short and the same for every player.

## Contract

- **Public entry script:** `gameplay/feel/feel.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. It is the autoload `Feel`. The setting `Feel.shake_enabled` turns screen shake off (kept in memory; saving it belongs to `core/save`, not built yet); hit-stop, particles and sound stay. The limit `Feel.PARTICLE_LIMIT` (48 live hit particles in all, across every player) is the one other code reads.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: none.
  - Listens to: `damage_dealt`, `enemy_died`, `player_downed`, `spell_cast`, `wizard_cast` and `projectile_impact`.
- **Hits on characters:** when a shot hits an enemy or a wizard, the hit burst is a spray along the way the shot flew (`projectile_impact` comes just before the damage and names the direction and the spot), in ember for an enemy and in the wizard's own colour for a wizard (the node in group `players` with an `index`), and a little bigger or smaller for each damage point above or below 5. Damage with no impact (a contact hit) is still the old round puff. A kill makes the hit's burst bigger, in the same colour.
- **Walls and pillars:** a shot that ends on a wall throws stone chips back along where it came from (one burst, only while two bursts stay free for hits on characters) and a short spark in the shot's colour (4 spark sprites of their own).
- **What it shows:** hit-stop, shake, hit and death particles, a white flash and squash on the hit node's `Sprite` child (name your sprite `Sprite` to get it), a death puff and a death animation (a white copy of the dead enemy's `Sprite` that collapses and fades; the enemy is freed at once), a muzzle flash turned along the aim in the player's colour, a thin-and-tall squash of the caster's `Sprite` (from `wizard_cast`) and a small camera kick on a cast. At most `REACT_SLOTS` (16) sprites react at once; past that a hit skips its flash and squash. If the sprite's owner changes its scale during a squash, Feel takes that as the new size to return to. Sounds are asked from `core/registry` and stay silent when missing.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd`, `.tres` and `.gdshader`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet (the first preset is `presets/punchy.tres`). When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/feel/presets/punchy.tres`, a `FeelPreset` (`presets/feel_preset.gd`): hit-stop length, shake strength and decay, particle speed and life, and the sound ids. Copy it, change the numbers and load it as `Feel.preset` before Feel's `_ready` (the art is read once, then). A preset only tunes reactions; it has no field that touches damage. It also names the art feel draws (`spark_texture`, `bolt_texture`, `hostile_texture`), so a re-skin is a preset, never an edit to `feel.gd`. Tests: `tests/gameplay/feel/test_feel.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here adds or tunes one juice preset (hit-stop length, shake strength), stays readable with four players hitting at once, and never changes damage or outcomes, with hit-stop kept short and the same for every player. Besides the standard criteria:

- Is the effect readable with 4 players on screen? Does it avoid per-frame allocations and stay within the particle limits?
- Does it keep to the dependency direction, without calling another area directly?
