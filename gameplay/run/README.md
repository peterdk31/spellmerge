# Run

## Purpose

Run lifecycle: start, seed, end and the summary screen.

**Closed until M5.** Built in M3, opens for PRs in M5 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

A run has one seed, so the same seed gives the same rooms and rolls.

## Contract

- **Public entry script:** `gameplay/run/run.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `run_started`, `run_ended`.
  - Listens to: `room_cleared`, `player_downed` and `pause_requested` (from the HUD).
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

A good PR here changes how a run starts, ends or is summarised, keeps runs reproducible from their seed, and works for 1–4 players. Besides the standard criteria:

- Is a run reproducible from its seed? Does the summary cover every player and never wait for one?
- Does it keep to the dependency direction, without calling another area directly?
