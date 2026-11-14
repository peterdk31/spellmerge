# Co-op

## Purpose

Join and leave mid-run, and revives.

Built in M1 (see "Gameplay sub-areas" in docs/PLAN.md).

Players join with a button press on their own device and can leave at any time. The camera is not Coop's: each machine's camera holds the wizards played on it (Feel's party camera, [gameplay/feel/README.md](../feel/README.md)). Nobody ever waits for another player.

## Contract

- **Public entry script:** `gameplay/coop/coop.gd` (autoload `Coop`). Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. What exists (M1 part 17):
  - **Join and leave:** the simulation's seats, `seat_joined` / `seat_left` from the frames service (core/sim; offline as a device joins or leaves, while a replay plays as its frames say), become `player_joined` / `player_left`, once per change, for any slots in any order (joining twice or leaving an empty slot sends nothing). `flow` hears them and adds a player at the room's spawn for that slot, or removes it; the run never stops for anyone. If the last standing player leaves while the rest are down, the room restarts as usual; a join while everyone is down gives the party a standing player and cancels the restart. `joined_count()` and `is_joined(player)` answer from Coop's own record.
  - **An unplugged gamepad** (owner, 2026-11-13): the seat does not leave. `core/input` sends the command `pad_wait_requested(player, on)`; while a seat that plays waits, the game is stopped for everyone (`Sim.stop`, one reason a seat: `PAD_OF`), until the seat has a gamepad again or leaves. `pad_wait_changed(seats)` says who is waited for (a bit a seat; sent on each change and when a room is entered), for the HUD; `Coop.pad_waits(sim)` answers the same. This is the one case where everyone waits for a player: the owner's decision (docs/DECISIONS.md).
  - **Friendly fire is not a setting any more** (actors G3c, owner 2026-10-28: "Everything should be able to damage everything"): a player's shots always hit the other players, and the shooter too once a shot has left them (owner, 2026-11-06: a spell spares only the body it is cast from, until it has left it; `Spells._launch`), and `combat` damages the player like any hit.
  - **Revive:** a standing player within `REVIVE_RANGE` (48 px) of a downed one fills that player's progress in `REVIVE_HOLD_TIME` (2 s); then Coop calls the player's `Downed.revive(reviver)` (the seat of the nearest standing player) and `Downed.protect(REVIVE_PROTECTION)` (1.5 s). Out of range the progress drains at twice the fill rate; a downed player never revives another; each downed player has its own progress, by its seat (`Downed.seat`, its home controller's), any seats 0-3. `step_revive(delta)` is what the tick calls (`step_rules`); `revive_progress_of(player)` answers the progress. Reasons for the numbers: `docs/DECISIONS.md`. Deliberate exception to "areas never call each other": Coop preloads the player area's `Downed` component to read `seat()`/`is_down()` and call `revive`/`protect` (see DECISIONS; actors G7). Coop finds each player's Downed once, when it reads the group, so a frame allocates nothing. `revive_progress` is sent each tick while the progress changes.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `player_joined`, `player_left`, `revive_progress`.
  - Listens to: `seat_joined`, `seat_left` (never a device's events), and `room_entered` (a new world's wizards and revives).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/coop/coop.gd`, with its test `tests/gameplay/coop/test_coop.gd` (every join order and leave order of 1–4 players, Feel's party camera with a whole party, a shot hitting a teammate). Run it with `godot --headless --path . --script res://tests/gameplay/coop/test_coop.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here improves joining or leaving mid-run, the friendly-fire rules or revives, and is checked with 1, 2, 3 and 4 players. Besides the general review:

- Does it work for any join order of 1–4 players, and does the camera keep everyone played on one machine on screen?
- Does it keep to the dependency direction, without calling another area directly?
