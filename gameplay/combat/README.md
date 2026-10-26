# Combat

## Purpose

Damage pipeline, hit and hurt boxes, knockback, status effects, and applying element reactions.

Built in M1 (see "Gameplay sub-areas" in docs/PLAN.md).

Element reactions are content data, so new ones are added without touching this code. Projectiles themselves come from `core/projectiles`; this area decides what a hit does.

## Contract

- **Public entry script:** `gameplay/combat/combat.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. It is the autoload `Combat`. A spell's hits are described by `Spells.hit_profile(tag)`; other spawners (the enemy AI) tell it what a shot does with `Combat.set_hit_profile(tag, damage, knockback)`; enemies register with `Combat.register_enemy(node, health, hurt_radius, contact_damage)` and wizards with `Combat.register_player(index, node, radius)` (which also makes the wizard a projectile target on `LAYER_PLAYER`, so enemy shots can hit it). `Combat.hit(player, target, amount, direction, strength)` is the pipeline for hits that do not come from a projectile.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `enemy_died`, `damage_dealt`, `status_applied`, and from M2 part 8 `reaction_triggered`.
  - Statuses (M2 part 7): `Combat.apply_status(player, enemy, id, duration, strength)` for burn, chill, shock, hex and static (three chills make `freeze`); `status_left`, `has_status`, `chill_stacks`, and `speed_factor(enemy)` for whoever moves an enemy (multiply walking and attack timers by it: 0 when frozen). A spell's hit comes with `Spells.hit_profile(tag)` (damage, knockback, status); other shots use `set_hit_profile`.
  - Static (#243): lightning puts `static` on an enemy (strength is the percent of a hit's damage that discharges). When a player's spell hits an enemy that is static, the hit discharges: every other static enemy within `STATIC_RANGE` takes that share of the damage (at least 1) as plain `hit`s for the same player, and `reaction_triggered(player, &"discharge", position)` and `discharge_arc(player, from, to)` (the struck enemy's place and the zapped one's) are sent for each. It is one step, not a second jump: the discharge starts no reaction, no status and no further discharge (`_discharging` also refuses one started from inside another). The struck enemy is spent when it discharged; the ones zapped stay charged. A hit that names no player, or a shot that is not a spell, discharges nothing. A new status is the `StringName`, the two packed arrays, and a line in each `match` of `combat.gd`; `REACTING_STATUSES` and the validator's `KNOWN_STATUSES` list it, so reaction rows can start from it.
  - Reactions (M2 part 8): when a spell's hit of element B lands on an enemy that has status A, the row for (A, B) in `content/spells/reactions.tres` runs instead of B's own status, after the hit's damage and only if the enemy lived. Four effect kinds, each implemented once: `BURST` (damage in a circle, with an optional pull), `CONSUME` (the status for bonus damage, doubled on a frozen enemy), `EXTEND` (a longer or stronger status; chill becomes a freeze) and `SPREAD` (the status to neighbours). It sends `reaction_triggered(player, reaction_id, position)` first. Reaction damage sets off no more reactions. An enemy reacts at most once per `REACTION_WAIT` (0.5 s), and `EXTEND` is capped (`MAX_FREEZE`, `MAX_EXTENDED_TIME`, `MAX_EXTENDED_PERCENT`). A new element is new rows in the table; `combat` changes only for a new effect kind.
  - Listens to: `projectile_hit` (from `core/projectiles`). For a tag that is a player's spell it asks `Spells.hit_profile(tag)`; for any other tag (an enemy's shot) it uses the table of `set_hit_profile`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/combat/combat.gd` is the example, and `tests/gameplay/combat/test_combat.gd` shows how to test it (damage, knockback, death and contact hits, with several players). Hits arrive as `projectile_hit` events on a test bus; time moves with `Combat.step(delta)`. Combat never moves enemies: whoever moves an enemy adds `Combat.consume_knockback_step(enemy, delta)` to its own velocity each physics frame.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here changes one step of the damage pipeline (a status effect, knockback, a hit or hurt box rule), reads reactions from data, and does not allocate per hit. Besides the general review:

- Is damage applied the same for any player index and any enemy? Does it stay within the frame budget with 1,000+ projectiles?
- Does it keep to the dependency direction, without calling another area directly?
