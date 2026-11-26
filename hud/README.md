# HUD

## Purpose

Everything the players see and click: panels, the radial spell builder, menus, shared widgets and the one theme. Readable with 4 players on one screen, fully usable with a gamepad.

## Contract

- **Sub-folders:** `panels/` (the autoload `Hud`, `panels.tscn`/`panels.gd`, corner panels, overlays), `builder/` (the radial builder, `builder/rings/` its ring styles), `menus/` (main, pause, inventory, reward), `widgets/` (shared controls), `theme/`.
- **Events both ways.** The HUD shows only what `core/events` state events say, and sends player-intent requests carrying the seat (0–3), never an outcome. It never calls gameplay or names `net/`, sends no state events, and uses only `core/`. Other areas never reach into the HUD; each scene's root script is its own entry.
- **A request the simulation hears is a command:** listed in `InputFrame.COMMAND_NAMES` (core/sim/README.md, "Input"), e.g. `run_requested`, `staff_cards_requested`, `reward_pick_requested`, `quick_use_requested`. The HUD is the one sender of its requests; definitions in `core/events/events.gd`, listeners in [gameplay/README.md](../gameplay/README.md).
- A request about a body names it by the key `inventory_announced` gave (`body`), so a seat refuses one for a body it no longer shows.
- **No single player:** widgets build on `core/ui_focus`, so a panel takes input only from its owner; only the pause menu pauses the game.
- **Buttons:** staffs on the shoulders (`staff_1`–`staff_4`); `accept` (A), `back` (B), `alternate` (X) are the menus'; `back` opens the builder, `inventory` (Select) the inventory, `pause` (Start) the pause menu; `take` (A, F, Enter; never Space) takes an item. The d-pad never walks: in play it is `quick_use_requested(seat, slot)`, in a menu it steps focus, under the held Y map it moves the teleport pick.
- **Layout pixels at the picture's scale:** lay out in 640×360 layout pixels (drawn 2x); use `PictureGrid.keep_fitted`, `PictureGrid.fit_control`, `PictureGrid.layout_of(viewport)`, never `get_viewport_rect()`.
- **The theme** is `theme/spellmerge_theme.tres` (the project theme). Use it; never style single controls by hand. Player colours: `PlayerPanel1-4`, `PlayerLabel1-4`. It names no file (no `ext_resource`; `tests/hud/test_title_type.gd`): a look needing one gets a theme of its own beside it (`theme/title_theme.tres`).
- **Accessibility:** readable text, nothing by colour alone (words: DOWN, MENU, WAIT, ONLINE), gamepad everywhere. **Smooth** (docs/STYLE.md): changes step by whole pixels over at least 3 frames.
- **A panel is always the seat's own** staffs and numbers, also while possessing or possessed; a possession is drawn in the world.
- **A seat's corner on the equal split** (`panels/seat_corners.gd`): each seat's panel, builder, inventory and reward menu sit by `hud_corners_changed` in its own quarter of its pane; two players sharing a half have each their own quarter of it; never on a remote seat's home spot. A panel hides only while its own menu covers it. Tests: `tests/hud/test_seat_corners.gd`, `tests/hud/test_shared_half_menus.gd`.
- **The corner panels are drawn once** (`widgets/cached_view.gd`, `CachedView`): a widget changes its look only through `queue_redraw` (no bare `modulate`, no TIME shader) and only when its pixels change; what moves every frame goes on the live layer (`PlayerPanel._draw_live`). Test: `tests/hud/test_cached_view.gd`.
- **Draw calls and glyphs:** icons come from `widgets/icon_atlas.gd` (`IconAtlas.region_of`, uploaded by `TextureUpload`); draw shapes, then icons, then text. A label at a new font size or outline adds its pair to `GlyphWarmup.GAME_SIZES`.
- **Sounds and rumbles:** the HUD never plays a sound or names Audio; it sends `ui_sound_requested(id)` (`UiSounds`: `ui_choose`, `ui_back`, `ui_deny`) and rumbles with `UiHaptics`; one press is one sound or rumble; moving is felt, not heard. Test: `tests/hud/test_ui_sounds.gd`.
- **Menus show mirrors, hold no rules:** the builder and inventory read `widgets/inventory_mirror.gd` (`bag_changed`, `owned_staff_changed`, `hands_changed`, forgotten on `inventory_announced`); both use the shared `widgets/radial_menu.gd`.
- **Settings:** a new saved setting takes its default from core/settings, saves under its key, and is sent on its core event when changed (and on bind only if not default). A setting that changes the game is a run rule, sent as a command (`shot_cap_requested`).

## The words for playing online

`widgets/online_words.gd` is the one place playing online is worded: reasons come as `OnlineWhy` names with facts (`core/events/online_why.gd`), never sentences; the main menu's online box and `widgets/online_line.gd` ask `OnlineWords.said` and `OnlineWords.line`. A new `OnlineWhy` name needs its sentence here (`tests/hud/test_online_words.gd`). The altar's code is Feel's (`gameplay/feel/altar_code.gd`).

## Allowed files

`.gd`, `.tscn`, `.tres`, UI art (`.png`, `.svg`), plus `.uid`, `.import` and `.license` files. Limits: 1 MB per image, 1 MB for anything else. Typed GDScript only; no banned APIs. Tests go in `tests/hud/`.

## Steps

1. Reuse widgets from `widgets/` before adding new ones.
2. Add UI art lines to `art/manifest.json`.
3. Run the checks below, then open a PR using the template, with a screenshot or short GIF.

## Example to copy

- A menu button: `hud/menus/main_menu/` (Play sends `hub_requested(0)` and nothing else; test `tests/gameplay/flow/test_flow.gd`).
- A panel: `hud/panels/player_panel/` (gets numbers through methods, listens to nothing, styles through theme variations); container `hud/panels/panels.gd`; tests `tests/hud/test_panels.gd`, `tests/hud/test_staff_strip.gd`.
- The builder: `hud/builder/` (`tests/hud/test_radial_*.gd`). A ring style is one file in `builder/rings/`, its test, and its entry in `PauseMenu.Ring` and `panels.gd`.
- A ring menu: `hud/menus/inventory/` (`tests/hud/test_inventory_menu.gd`).
- A page menu: `hud/menus/pause/` (one UIFocus list, answering only signals naming its player; `tests/hud/test_pause_menu.gd`).
- More tests: `tests/hud/` (`test_quick_use`, `test_map_picker`, `test_key_count`, `test_cheat_code`, `test_boss_intro`, ...); screenshots `tests/screenshots/shot_*.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

- Is it readable with 4 players at 1× on a small screen?
- Can it be fully used with a gamepad, and does each panel respond only to its owner?
- Does it reuse the shared theme and widgets?

History and reasons: [docs/history/hud-README.md](../docs/history/hud-README.md).
