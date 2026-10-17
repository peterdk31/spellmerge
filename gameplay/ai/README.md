# AI

## Purpose

Shared enemy behaviours: steering, targeting and attack patterns.

**Closed until M3.** Built across M1 to M3 (the plan gives the range, not one milestone), opens for PRs in M3 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Enemies in `content/enemies/` pick and configure behaviours from here instead of writing their own. Targeting chooses among all active players, never "the player".

## Contract

- **Public entry script:** `gameplay/ai/ai.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: none yet. How an attack is requested is decided in M1.
  - Listens to: `room_entered` and `player_downed`.
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

A good PR here adds or improves one reusable behaviour that several enemies can configure, targets any of the 1–4 players, and stays cheap with 100–200 enemies. Besides the standard criteria:

- Are behaviours reusable by several enemies? Do 100–200 enemies stay within the frame budget?
- Does it keep to the dependency direction, without calling another area directly?
