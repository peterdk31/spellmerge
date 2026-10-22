# Progression

## Purpose

Hub, unlocks, currency and the codex.

Built in M5 (see "Gameplay sub-areas" in docs/PLAN.md).

Saving goes through `core/save`, under `user://` only.

## Contract

- **Public entry script:** `gameplay/progression/progression.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `unlock_gained`, `currency_changed`.
  - Listens to: `run_ended`.
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

A good PR here changes the hub, an unlock rule, currency or the codex, keeps saves under `user://` and does not break older saves. Besides the general review:

- Does it keep older saves working?
- Does it keep to the dependency direction, without calling another area directly?
