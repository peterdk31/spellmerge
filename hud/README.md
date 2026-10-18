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

- **The theme** is `theme/spellmerge_theme.tres`, set as the project theme (`gui/theme/custom`), so every control uses it. Player colours are type variations: `PlayerPanel1-4` (panel border), `PlayerLabel1-4` (text), plus `HealthBar` and `ManaBar`. Add a new look there, not as an override on one control. Colours are from `docs/STYLE.md`.
- **The panels** (`panels/`): `panels.tscn` is the autoload `Hud`, a `CanvasLayer` with one `player_panel/` per player in a corner (P1 top left, P2 top right, P3 bottom left, P4 bottom right; about 112×55 px each, so four fit a 640×360 view; the background is 60% translucent so a wizard or enemy under a corner panel still shows). It hears `player_joined`, `player_left`, `room_entered`, `player_stats_changed` (from `player`) and `UIFocus.opened`/`closed`, and shows only that. A panel shows for a joined player after the first room; it takes no input. It says "P1".."P4", "HP", "MP" with numbers, "DOWN" at 0 health and "MENU" while that player's overlay is open (priority DOWN), so nothing is shown by colour alone.
- **The overlay** (`panels/overlay/`): a small per-player menu under (P1, P2) or over (P3, P4) that player's corner panel (nodes `Root/Overlay1-4` of `panels.tscn`). `panels.gd` toggles it when its owner presses the `overlay` action (read from `core/input` press counts, so a quick tap is not lost; a slot with no device is ignored). Opening goes through `UIFocus.open`, so only the owner's device moves (up/left, down/right), activates (`cast`) or goes back (`dodge`), the owner's wizard stands still and the other three players carry on. It never pauses the game, and it closes when the owner closes it, when the device leaves, or when another request replaces it. Controls: "Resume" and "Build slot 1", a stub that only sends `build_change_requested(player, 0, &"stub")` (the real spell builder comes in a later milestone; gameplay refuses what it doesn't know). The focused control is marked with "> ", not by colour alone. While it is open the corner panel shows "MENU".
- **The hurt vignette** (`panels/vignette/`, node `Root/Vignette` of `panels.tscn`, created by `panels.gd`): a red glow at the screen edges, strongest toward the corner of the wizard whose health fell, fading in half a second. It comes only from a drop in the health of `player_stats_changed`, takes no input and never covers the panels. A hit adds glow by the share of maximum health it took, and less the more wizards are playing (divided by the square root of their number), so a four-player fight does not keep the screen red; the middle of the screen stays clear. The setting `Hud.get_vignette().enabled = false` turns it off (kept in memory, like `Feel.shake_enabled`; saving it waits for `core/save` and the settings screen).
- Events the HUD listens to: `player_joined`, `player_left`, `room_entered`, `player_stats_changed`, `run_started`, `run_ended`, and `UIFocus` signals. Events it sends: `build_change_requested` (the overlay's stub button).

## Allowed files

`.gd`, `.tscn`, `.tres`, UI art (`.png`, `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs. Tests for the HUD go in `tests/hud/`; the runner and naming are documented in `tests/README.md`, which a later task writes.

## Steps

1. Pick an issue labelled `now` in this area (once open) and comment `/claim`.
2. Reuse widgets from `widgets/` before adding new ones.
3. Add UI art lines to `art/manifest.json`.
4. Run the checks below, then open a PR using the template, with a screenshot or short GIF.

## Example to copy

`hud/menus/main_menu/main_menu.tscn` and `main_menu.gd`: the main menu with the Play button. Play sends `play_requested(0)` through the `Events` autoload and nothing else: it never calls `flow` and never changes the scene (flow does, on the event). The test is in `tests/gameplay/flow/test_flow.gd` (it presses the button and scans the script). For a panel, copy `hud/panels/player_panel/` (`player_panel.tscn` and `.gd`: the root script gets its numbers through methods, listens to nothing, and styles itself only through theme variations); its container is `hud/panels/panels.gd`, and the tests are `tests/hud/test_panels.gd` and `tests/gameplay/player/test_player_stats.gd`. For the overlay, copy `hud/panels/overlay/` (it answers only the signals that name its own player index); its test is `tests/hud/test_overlay.gd` (with one overlay open the other three players still move).

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
