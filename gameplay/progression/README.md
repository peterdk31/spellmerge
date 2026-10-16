# Progression

## Purpose

Hub, unlocks, currency and the codex.

**Closed until M6.** Built in M5, opens for PRs in M6 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Saving goes through `core/save`, under `user://` only.

## Contract

- **Public entry script:** `gameplay/progression/progression.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (**provisional**: `core/events` owns the definitions, and the lists are checked against each other when the event bus is built in M1):
  - Sends: `unlock_gained`, `currency_changed`.
  - Listens to: `run_ended`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## What a good PR looks like

A good PR here changes the hub, an unlock rule, currency or the codex, keeps saves under `user://` and does not break older saves.

## Steps, tests and validation

Not open yet. When it opens, follow the steps, test layout and checks in [gameplay/README.md](../README.md).

## Rating questions

Besides the standard criteria:

- Does it keep older saves working?
- Does it keep to the dependency direction, without calling another area directly?
