# Combat

## Purpose

Damage pipeline, hit and hurt boxes, knockback, status effects, and applying element reactions.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Element reactions are content data, so contributors add them without touching this code. Projectiles themselves come from `core/projectiles`; this area decides what a hit does.

## Contract

- **Public entry script:** `gameplay/combat/combat.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. It is the autoload `Combat`. Spells are learned from `spell_cast` (below); other spawners (the enemy AI) tell it what a shot does with `Combat.set_hit_profile(tag, damage, knockback)`; enemies register with `Combat.register_enemy(node, health, hurt_radius, contact_damage)` and wizards with `Combat.register_player(index, node, radius)` (which also makes the wizard a projectile target on `LAYER_PLAYER`, so enemy shots can hit it). `Combat.hit(player, target, amount, direction, strength)` is the pipeline for hits that do not come from a projectile.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `enemy_died`, `damage_dealt`, `status_applied`, and from M2 part 8 `reaction_triggered`.
  - Listens to: `projectile_hit` (from `core/projectiles`) and `spell_cast` (from `player`). On the first `spell_cast` of a spell id it asks `core/registry` for that spell and sets a hit profile from its `hit_tag()`, `hit_damage()` and `hit_knockback()`, so spells never call Combat.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/combat/combat.gd` is the example, and `tests/gameplay/combat/test_combat.gd` shows how to test it (damage, knockback, death and contact hits, with several players). Hits arrive as `projectile_hit` events on a test bus; time moves with `Combat.step(delta)`. Combat never moves enemies: whoever moves an enemy adds `Combat.consume_knockback_step(enemy, delta)` to its own velocity each physics frame.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here changes one step of the damage pipeline (a status effect, knockback, a hit or hurt box rule), reads reactions from data, and does not allocate per hit. Besides the standard criteria:

- Is damage applied the same for any player index and any enemy? Does it stay within the frame budget with 1,000+ projectiles?
- Does it keep to the dependency direction, without calling another area directly?
