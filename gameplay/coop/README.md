# Co-op

## Purpose

Join and leave mid-run, friendly fire and the shared camera.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Players join with a button press on their own device and can leave at any time. The shared camera fits all players. Nobody ever waits for another player.

## Contract

- **Public entry script:** `gameplay/coop/coop.gd` (autoload `Coop`). Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. What exists (M1 part 17):
  - **Join and leave:** `device_joined` / `device_left` from `core/input` become `player_joined` / `player_left`, once per change, for any slots in any order (joining twice or leaving an empty slot sends nothing). `flow` hears them and adds a wizard at the room's spawn for that slot, or removes it; the run never stops for anyone. If the last standing wizard leaves while the rest are down, the room restarts as usual; a join while everyone is down gives the party a standing wizard and cancels the restart. `joined_count()` and `is_joined(player)` answer from Coop's own record.
  - **Friendly fire**, off by default: `set_friendly_fire(true)` (or `friendly_fire = true`) makes player shots also hit the other players, never the shooter. The switch is `Projectiles.friendly_fire` in `core/projectiles`, read when a shot is spawned; targets registered with an `owner` are skipped by that player's shots. `combat` damages the wizard like any hit. The option lives in memory until `core/save` and the settings screen exist.
  - **Shared camera:** after `room_entered` Coop takes the current `Camera2D` and, each frame, eases it to the middle of all wizards (downed ones too) and zooms out until all fit with `CAMERA_MARGIN` (48 px) to spare, between `MAX_ZOOM` 1.0 and `MIN_ZOOM` 0.5. The room's camera limits (set by `flow`) keep the view inside the room. `snap()` jumps to the target; `step(delta)` is what `_process` calls, so tests move time by fixed deltas.
  - Not built: reviving a downed wizard by standing next to it (see `docs/BACKLOG.md`).
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `player_joined`, `player_left`.
  - Listens to: `device_joined`, `device_left` and `room_entered` (to find the new world's camera).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/coop/coop.gd`, with its test `tests/gameplay/coop/test_coop.gd` (every join order and leave order of 1–4 players, the camera, friendly fire). Run it with `godot --headless --path . --script res://tests/gameplay/coop/test_coop.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here improves joining or leaving mid-run, the friendly-fire rules or the shared camera, and is checked with 1, 2, 3 and 4 players. Besides the standard criteria:

- Does it work for any join order of 1–4 players, and does the camera keep everyone on screen?
- Does it keep to the dependency direction, without calling another area directly?
