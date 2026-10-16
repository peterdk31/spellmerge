# HUD

## Purpose

Everything the players see and click: panels, the spell builder UI, menus, shared widgets and the one theme. It must stay readable with 4 players on one screen and fully usable with a gamepad.

**Opens for PRs in M4** (Polish and variety; see "Opens for PRs" in docs/ROADMAP.md). Until then Claude builds it. A placeholder main menu exists in `hud/menus/main_menu/`.

## Contract

- **Sub-folders:** `panels/` (per-player panels), `builder/` (the spell builder), `menus/` (main menu, pause, summary), `widgets/` (shared, reusable controls), `theme/` (the single theme).
- **The HUD only listens.** It reads state through `core/events` and never calls gameplay directly. Dependency direction: `core` ← `gameplay` ← `content`; the HUD sits beside `gameplay` and uses only `core/`.
- **Public entry script:** none for the area as a whole; each scene's root script is its own entry (for example `hud/menus/main_menu/main_menu.gd`). Other areas never reach into the HUD.
- Widgets build on `core/ui_focus`, so each panel takes input only from its owner (player index 0–3). Nothing assumes a single player, and a player in the builder never makes anyone else wait.
- Use the shared theme; don't style single controls by hand.
- Accessibility: readable text sizes, no information by colour alone, gamepad navigation everywhere.

## Allowed files

`.gd`, `.tscn`, `.tres`, UI art (`.png`, `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs. Tests mirror the tree in `tests/hud/`.

## Steps

1. Pick an issue labelled `now` in this area (once open) and comment `/claim`.
2. Reuse widgets from `widgets/` before adding new ones.
3. Add UI art lines to `art/manifest.json`.
4. Run the checks below, then open a PR using the template, with a screenshot or short GIF.

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
