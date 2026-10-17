# Core

## Purpose

The shared services every other area stands on: the event bus, the content registry, input, per-player UI focus, saving, base classes, the projectile manager and object pools. Gameplay, HUD and content build on it; it builds on nothing of theirs.

**Closed to outside PRs.** Claude maintains `core/` alone. An outside PR touching it is closed with "open an issue": describe the problem or the missing hook there, and Claude decides how `core/` should change.

## Contract

- **Dependency direction:** `core` ← `gameplay` ← `content`. `core/` depends on none of `gameplay/`, `hud/` or `content/`. It finds content by folder through `core/registry`.
- **Sub-folders, one per service:**
  - `events/`: the event bus (`spell_cast`, `enemy_died`, `player_downed`, `room_cleared`, ...). One autoload, `Events` (`events/events.gd`), with a typed signal per event and the player index first. Areas talk only through it. It owns the event definitions; each area's README lists only which events the area sends and listens to.
  - `registry/`: discovers content by folder, so no central list is edited. Everyone else loads with literal paths only.
  - `input/`: one autoload, `PlayerInput` (`input/input_manager.gd`); devices join with a button press and each player gets their own device. A gamepad takes the lowest free index; the keyboard and mouse only take P1 (index 0), so P2–P4 are gamepads. The `leave` action or an unplugged gamepad frees the slot. Bots add a virtual device per index (`add_virtual_device`, `send_virtual`) that goes through the same `handle_event` path as real input. Gameplay asks by player index (`get_move`, `is_action_pressed`, `is_action_just_pressed`) and never reads `Input` itself. The actions (`move_left`, `move_right`, `move_up`, `move_down`, `dodge`, `cast`, `overlay`, `join`, `leave`) are in `project.godot`. It sends `device_joined` and `device_left`; `coop` turns them into `player_joined` and `player_left`.
  - `ui_focus/`: per-player UI focus, because Godot has one global focus. Every widget builds on it.
  - `save/`: reading and writing under `user://` only.
  - `base/`: base classes (`spell_base.gd`, `enemy_base.gd`, `room_base.gd`: small M1 resources with `id` and `demo`; M2 and M3 replace or extend them) and build info (`build_info.gd`).
  - `projectiles/`: the projectile manager for thousands of projectiles.
  - `pools/`: object pools; no per-frame allocations.
- Most services arrive in M1 (docs/ROADMAP.md). Folders without code yet only hold a `.gitkeep`; so far `base/`, `events/` and `input/` have code. Each service gets its entry script and a section here when it is built.
- Services that act per player take a player index 0–3. Nothing assumes a single player.

## Allowed files

Claude only. Typed GDScript, no banned APIs, file access only in `user://`. Tests for `core/` go in `tests/core/`; the runner and naming are documented in `tests/README.md`, which a later task writes.

## Steps

Outside contributors: open an issue instead of a PR. Claude: follow docs/NEXT.md.

## Example to copy

None: `core/` is closed, so there is nothing for outside PRs to copy.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Not applicable to outside PRs, which are closed. For Claude's own changes: is it needed by more than one area, does it keep the dependency direction, and does it stay inside the performance budgets?
