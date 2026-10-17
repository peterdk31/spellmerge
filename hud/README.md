# HUD

## Purpose

Everything the players see and click: panels, the spell builder UI, menus, shared widgets and the one theme. It must stay readable with 4 players on one screen and fully usable with a gamepad.

**Opens for PRs in M4** (Polish and variety; see "Opens for PRs" in docs/ROADMAP.md). Until then Claude builds it.

## Contract

- **Sub-folders:** `panels/` (per-player panels), `builder/` (the spell builder), `menus/` (main menu, pause, summary), `widgets/` (shared, reusable controls), `theme/` (the single theme).
- **Events both ways.** The HUD listens to state events from `core/events` and shows only what they say. It also sends player-intent events: requests that carry the player index (0–3), never a finished outcome. It never calls gameplay directly; gameplay checks each request, applies or refuses it, and announces the result as a normal state event (docs/DECISIONS.md, "The HUD sends player-intent events"). Dependency direction: `core` ← `gameplay` ← `content`; the HUD sits beside `gameplay` and uses only `core/`.
- **Events the HUD sends** (`core/events/events.gd` owns the definitions): `play_requested` and `door_vote_requested` (received by `flow`), `build_change_requested` (`player`), `reward_pick_requested` (`rewards`) and `pause_requested` (`run`) (table in [gameplay/README.md](../gameplay/README.md)). The HUD is the only sender of these events and sends no state events, so each event keeps one sender. Gameplay areas listen to them.
- **Public entry script:** none for the area as a whole; each scene's root script is its own entry (for example a menu scene's script under `menus/`). Other areas never reach into the HUD.
- Widgets build on `core/ui_focus`, so each panel takes input only from its owner (player index 0–3). Nothing assumes a single player, and a player in the builder never makes anyone else wait.
- Use the shared theme; don't style single controls by hand.
- Accessibility: readable text sizes, no information by colour alone, gamepad navigation everywhere.

## Allowed files

`.gd`, `.tscn`, `.tres`, UI art (`.png`, `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs. Tests for the HUD go in `tests/hud/`; the runner and naming are documented in `tests/README.md`, which a later task writes.

## Steps

1. Pick an issue labelled `now` in this area (once open) and comment `/claim`.
2. Reuse widgets from `widgets/` before adding new ones.
3. Add UI art lines to `art/manifest.json`.
4. Run the checks below, then open a PR using the template, with a screenshot or short GIF.

## Example to copy

Arrives with Claude's first HUD scene. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Besides the standard criteria:

- Is it readable with 4 players at 1× on a small screen?
- Can it be fully used with a gamepad, and does each panel respond only to its owner?
- Does it reuse the shared theme and widgets?
