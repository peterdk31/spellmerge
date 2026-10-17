# Core

## Purpose

The shared services every other area stands on: the event bus, the content registry, input, per-player UI focus, saving, base classes, the projectile manager and object pools. Gameplay, HUD and content build on it; it builds on nothing of theirs.

**Closed to outside PRs.** Claude maintains `core/` alone. An outside PR touching it is closed with "open an issue": describe the problem or the missing hook there, and Claude decides how `core/` should change.

## Contract

- **Dependency direction:** `core` ← `gameplay` ← `content`. `core/` depends on none of `gameplay/`, `hud/` or `content/`. It finds content by folder through `core/registry`.
- **Sub-folders, one per service:**
  - `events/`: the event bus (`spell_cast`, `enemy_died`, `player_downed`, `room_cleared`, ...). One autoload, `Events` (`events/events.gd`), with a typed signal per event and the player index first. Areas talk only through it. It owns the event definitions; each area's README lists only which events the area sends and listens to.
  - `registry/`: discovers content by folder, so no central list is edited. Everyone else loads with literal paths only.
  - `input/`: one autoload, `PlayerInput` (`input/input_manager.gd`); devices join with a button press and each player gets their own device. A gamepad takes the lowest free index; the keyboard and mouse only take P1 (index 0), so P2–P4 are gamepads. The `leave` action or an unplugged gamepad frees the slot. Bots add a virtual device per index (`add_virtual_device`, `send_virtual`) that goes through the same `handle_event` path as real input. Gameplay asks by player index (`get_move`, `is_action_pressed`, `is_action_just_pressed`) and never reads `Input` itself (call `is_action_just_pressed` only from `_process` or `_physics_process`). Each physical input is tracked on its own and an action takes the strongest, so releasing one of two held inputs does not cancel the other. The actions (`move_left`, `move_right`, `move_up`, `move_down`, `dodge`, `cast`, `overlay`, `join`, `leave`) are in `project.godot`. It sends `device_joined` and `device_left`; `coop` turns them into `player_joined` and `player_left`. `set_captured(player, true)` hides a player's move, `cast` and `dodge` from those gameplay questions (`overlay` stays) while their UI panel is open, so gameplay needs no check of its own; `get_press_count` counts presses and is never captured, so UI code loses no quick tap.
  - `ui_focus/`: per-player UI focus, because Godot has one global focus. One autoload, `UIFocus` (`ui_focus/ui_focus.gd`). `open(player, controls)` gives a player a panel; only that player's input (through `PlayerInput`) moves it: up/left and down/right step through the controls, `cast` activates, `dodge` cancels (presses come from `get_press_count`, so a quick tap is not lost). An open panel captures its owner's gameplay input through `PlayerInput.set_captured`, so their wizard does not walk, cast or dodge meanwhile; opening needs a joined device. A focused control that gets disabled, hidden or freed loses focus and is never activated. It has its own signals (`opened`, `closed`, `focus_changed`, `activated`, `cancelled`, player index first); a widget checks that the player is its owner. It never calls `grab_focus`, never pauses, and closes a panel when its player's device leaves. Every widget builds on it.
  - `save/`: reading and writing under `user://` only.
  - `base/`: base classes (`spell_base.gd`, `enemy_base.gd`, `room_base.gd`: small M1 resources with `id` and `demo`; M2 and M3 replace or extend them) and build info (`build_info.gd`).
  - `projectiles/`: the projectile manager, one autoload, `Projectiles` (`projectiles/projectile_manager.gd`). Projectiles are rows in packed arrays, not nodes: `spawn(player, position, velocity, lifetime, radius, hit_layers, pierce)` starts one, and the manager moves them all in `_physics_process` and draws them all in one `MultiMeshInstance2D`. Things that can be hit are Node2Ds registered with `add_target(node, radius, layer)` (`LAYER_ENEMY`, `LAYER_PLAYER`); a spatial grid of the targets keeps hit tests cheap, and the path of each step is checked as a segment and the search widens with the largest target radius, so neither fast shots nor big targets are missed; a piercing shot hits each overlapping target once. A hit sends `projectile_hit(player, target, position)` and ends the projectile unless it has `pierce` left; damage is `combat`'s job. The global cap (`DEFAULT_CAP_WEB` 1,000 or `DEFAULT_CAP_DESKTOP` 3,000 by platform; `set_cap` changes it) never refuses a new shot: it drops the oldest projectile of whoever owns the most, and `dropped` counts these. Nothing allocates per frame. Tests step it by hand with `step(delta)`.
  - `pools/`: object pools; no per-frame allocations. `pools/pool.gd` is a fixed-size pool typed by its factory Callable: it makes every object up front, `acquire()` returns an object or `null` when all are out (it never grows), `release()` takes one back (a double or foreign release is refused), and optional `on_acquire` and `on_release` hooks reset state. `clear()` frees every object, including ones still handed out, so drop your references first. Pools are for nodes and effects (enemies, damage numbers); projectiles are packed-array rows and do not use them. Use `preload("res://core/pools/pool.gd")`.
- Most services arrive in M1 (docs/ROADMAP.md). Folders without code yet only hold a `.gitkeep`; so far `base/`, `events/`, `input/`, `pools/`, `projectiles/` and `ui_focus/` have code. Each service gets its entry script and a section here when it is built.
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
