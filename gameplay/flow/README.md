# Flow

## Purpose

Room sequence, door voting, transitions and waiting for builders.

**Closed until M5.** Built in M3, opens for PRs in M5 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Players in the spell builder never block the others: the rest keep playing.

## Contract

- **Public entry script:** `gameplay/flow/flow.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (**provisional**: `core/events` owns the definitions, and the lists are checked against each other when the event bus is built in M1):
  - Sends: `room_entered`, `room_cleared`, `door_voted`.
  - Listens to: `enemy_died`, `run_started`, `player_downed` and `door_vote_requested` (from the HUD; `door_voted` is flow's announced result of that request).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

Arrives with Claude's first code for this area. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here changes room order, door voting or transitions, and keeps the no-waiting pillar: one player in the builder never stalls the rest. Besides the standard criteria:

- Does a player idling in the builder block anyone? Does voting work for 1–4 players?
- Does it keep to the dependency direction, without calling another area directly?
