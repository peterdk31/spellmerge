# Rewards

## Purpose

Per-player rolls from loot tables, unspent rewards and shops.

Built in M3 (see "Gameplay sub-areas" in docs/PLAN.md).

Loot tables are content data read through the registry, so new ones are added without touching this code. Each player rolls their own rewards.

## Contract

- **Public entry script:** `gameplay/rewards/rewards.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `reward_rolled`, `reward_taken`.
  - Listens to: `room_cleared` and `reward_pick_requested` (from the HUD; `reward_taken` is the announced result).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

Arrives with Claude's first code for this area. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here changes how rewards are rolled, kept or bought for each player, reads tables from data, and never makes one player wait for another's choice. Besides the general review:

- Does each player get an independent roll? Are unspent rewards kept and never lost?
- Does it keep to the dependency direction, without calling another area directly?
