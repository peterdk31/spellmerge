# Core

## Purpose

The shared services every other area stands on: the event bus, the content registry, input, per-player UI focus, saving, base classes, the projectile manager and object pools. Gameplay, HUD and content build on it; it builds on nothing of theirs.

**Closed to outside PRs.** Claude maintains `core/` alone. An outside PR touching it is closed with "open an issue": describe the problem or the missing hook there, and Claude decides how `core/` should change.

## Contract

- **Dependency direction:** `core` ← `gameplay` ← `content`. `core/` depends on none of `gameplay/`, `hud/` or `content/`. It finds content by folder through `core/registry`.
- **Sub-folders, one per service:**
  - `events/`: the event bus (`spell_cast`, `enemy_died`, `player_downed`, `room_cleared`, ...). Areas talk only through it; the HUD only listens.
  - `registry/`: discovers content by folder from a manifest generated at build time. It is the only place that loads by a computed path.
  - `input/`: the player manager; devices join with a button press and each player gets their own device.
  - `ui_focus/`: per-player UI focus, because Godot has one global focus. Every widget builds on it.
  - `save/`: reading and writing under `user://` only.
  - `base/`: base classes and build info (`build_info.gd`).
  - `projectiles/`: the projectile manager for thousands of projectiles.
  - `pools/`: object pools; no per-frame allocations.
- Most services arrive in M1 (docs/ROADMAP.md). Folders without code yet only hold a `.gitkeep`. Each service gets its entry script and a section here when it is built.
- Every service takes a player index 0–3. Nothing assumes a single player.

## Allowed files

Claude only. Typed GDScript, no banned APIs, file access only in `user://`. Tests mirror the tree in `tests/core/`.

## Steps

Outside contributors: open an issue instead of a PR. Claude: follow docs/NEXT.md.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Not applicable to outside PRs, which are closed. For Claude's own changes: is it needed by more than one area, does it keep the dependency direction, and does it stay inside the performance budgets?
