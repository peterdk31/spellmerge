# Difficulty

## Purpose

Scaling by player count, depth and setting.

Built early by run generation RG5 ([docs/milestones/run-generation.md](../../docs/milestones/run-generation.md), "Scaling"); the rest of it in M3 (see "Gameplay sub-areas" in docs/PLAN.md).

A run with 1 player and a run with 4 players should both feel fair.

## The area (run generation RG5)

- **One scale for each room**, from its depth and the number of players in the run: the run definition's `scaling` (`RunScaling`, core/base/run_scaling.gd: a curve per depth and one per extra player, each a start, an end and an easing, `ScaleCurve`), so the owner tunes it in data (content/runs). The run's area works it out once per room as it makes the map (`RunNode.scale`, gameplay/run), where it also grows the room's enemy budget, and names it as the party enters the room (`run_room_scaled`).
- **`difficulty.gd`, the autoload `Difficulty`:** keeps the room's scale as the level (`level`, told as `difficulty_changed` at every room), and sets every enemy and boss Flow is about to stand (`enemy_standing`, the body not yet in the tree) to it (`Actor.stat_scale`), so the body's data's health is multiplied by it when it applies its data. A body already standing keeps the numbers it stood with.
- **The players** are the seats joined at the run's start (Flow's, from the frames service: the same on every machine and in every replay). A wizard joining later plays the run as it was made: nothing standing changes.
- **State:** `level` is the run's state (hashed, saved in snapshots); a run's start renews it to 1 (`begin_run`, `Tick.RUN_ORDER`), so the hub and the sandbox scale nothing.
- **Later:** power and spell size join the same scale with the actor stats (the boss plan's OB7), a boss's adds with OB13; a difficulty setting is one more factor of the level (a run's rule, `SessionRules`, so every machine agrees).
- **Tests:** `tests/gameplay/difficulty/test_difficulty.gd` (the level from the run, told; an enemy standing scaled; the level as state, renewed at a run's start; the hub and the sandbox unscaled; in play, each room's enemies at its scale). The curves themselves: `tests/core/test_run_rules.gd`; the budget: `tests/gameplay/run/test_run_generator.gd`.

## Contract

- **Public entry script:** `gameplay/difficulty/difficulty.gd`, the autoload `Difficulty` (registered in `project.godot`). Other code uses only this script and the events it sends and listens to; nothing else in the folder is public.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/`, the registry and the actor kit (`gameplay/actor`). `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `difficulty_changed`.
  - Listens to: `run_room_scaled` (from run) and `enemy_standing` (from flow); later `run_started`, `player_joined`, `player_left` and `room_entered` (M3).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

The area's entry script `difficulty.gd` and its test `tests/gameplay/difficulty/test_difficulty.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
tools/ptest.sh 8 'test_difficulty|test_run_rules|test_run_generator|test_run\.gd'
```

## Review questions

A good PR here tunes how enemy count, health or rewards scale with players, depth or the chosen setting. Besides the general review:

- Does it feel fair from 1 to 4 players?
- Is every scale a pure function of the run's start and the map (the same on every machine and in every replay)?
- Does it keep to the dependency direction, without calling another area directly?
