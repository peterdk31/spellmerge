# Combat

## Purpose

Damage pipeline, hit and hurt boxes, knockback, status effects, and applying element reactions.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Element reactions are content data, so contributors add them without touching this code. Projectiles themselves come from `core/projectiles`; this area decides what a hit does.

## Contract

- **Public entry script:** `gameplay/combat/combat.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (**provisional**: `core/events` owns the definitions, and the lists are checked against each other when the event bus is built in M1):
  - Sends: `enemy_died`, `damage_dealt`, `status_applied`.
  - Listens to: projectile and hit events.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## What a good PR looks like

A good PR here changes one step of the damage pipeline (a status effect, knockback, a hit or hurt box rule), reads reactions from data, and does not allocate per hit.

## Steps, tests and validation

Not open yet. When it opens, follow the steps, test layout and checks in [gameplay/README.md](../README.md).

## Rating questions

Besides the standard criteria:

- Is damage applied the same for any player index and any enemy? Does it stay within the frame budget with 1,000+ projectiles?
- Does it keep to the dependency direction, without calling another area directly?
