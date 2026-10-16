# Feel

## Purpose

Hit-stop, screen shake and juice presets.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Feel only reacts: it never changes damage or outcomes. Hit-stop is its only effect on timing; it is short and the same for every player.

## Contract

- **Public entry script:** `gameplay/feel/feel.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (**provisional**: `core/events` owns the definitions, and the lists are checked against each other when the event bus is built in M1):
  - Sends: none.
  - Listens to: `damage_dealt`, `enemy_died` and `player_downed`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## What a good PR looks like

A good PR here adds or tunes one juice preset (hit-stop length, shake strength), stays readable with four players hitting at once, and never changes damage or outcomes, with hit-stop kept short and the same for every player.

## Steps, tests and validation

Not open yet. When it opens, follow the steps, test layout and checks in [gameplay/README.md](../README.md).

## Rating questions

Besides the standard criteria:

- Is the effect readable with 4 players on screen? Does it avoid per-frame allocations and stay within the particle limits?
- Does it keep to the dependency direction, without calling another area directly?
