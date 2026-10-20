# Architecture

How Spellmerge is put together, and where each kind of change goes, so a new feature or a new look never needs a change in the middle of the game. The rules behind it are in [PLAN.md](PLAN.md) and the area READMEs; this page is the map.

## Layers

```
content/   data and scenes: spells, enemies, rooms, the wizard   (found by folder)
gameplay/  the rules: player, combat, ai, flow, feel, coop ...   (talk through events)
core/      services: events, registry, input, projectiles, pools (know nothing above)
hud/       panels and menus (send requests as events, show state from events)
```

- **Dependency direction:** `core` ← `gameplay` ← `content`. A lower layer never names a higher one. One known exception: `flow.gd` preloads `content/wizard/base/wizard.tscn` as the default `wizard_scene` (listed under "Foundation" in BACKLOG.md).
- **Areas never call each other.** They send and listen to typed signals on `Events` (table in [gameplay/README.md](../gameplay/README.md)); each event has one sender.
- **Content is found, not listed.** `Registry` scans the folders, so a new spell, enemy or room is new files only. Code that needs content takes an id (`Flow.room_id_to_play`) and asks the registry; it names no file.
- **Players are indices 0–3.** No system has a "the player".
- **Hot paths are pooled.** Shots are rows in `Projectiles`; nodes come from `Pool`; nothing allocates per frame.

## Where each change goes

| I want to ... | Change | Never touch |
| --- | --- | --- |
| add a room, enemy or spell | copy the example folder in `content/` (see its README) | `flow.gd`, `registry.gd` |
| use another room, enemy or spell in a run | set `Flow.room_id_to_play`, `enemy_id_to_play`, `spell_id_to_play` (a room picker or loadout does this) | the wave or spawn code |
| swap a sprite, tile or animation strip | replace the file, keep the contract below | scripts, node names in scenes, tests |
| re-skin the shot, spark or hostile shot | another `FeelPreset` (or its texture fields), set before `Feel._ready` | `feel.gd` |
| change a wizard's look | the textures in `content/wizard/base/wizard.tscn`, or give `Flow.wizard_scene` another scene | `player.gd` |
| add behaviour that others must react to | a new typed signal in `core/events/events.gd`, one sender, listeners connect | the listeners' siblings |
| tune feel or balance | a preset or a `.tres` number | tests (they do not assert tuning numbers) |

## Art contract (what a replacement must keep)

Art is data: scenes and resources point at files, and scripts never name a texture path (the one exception is a `FeelPreset`'s default textures, so a preset that leaves a field alone still draws something).

- A strip is one row of frames, **32 px high and a whole multiple of 32 wide**. The script reads the frame count from the width (`hframes`), so a strip may have more or fewer frames than today. The ember imp's idle needs two or more to animate.
- The wizard has idle, walk and dash strips for **each of the four players** and a staff; the four idle looks must differ (colour is how players tell themselves apart).
- A replacement `Flow.wizard_scene` must have `player.gd` on its root, the `textures`, `walk_textures` and `dash_textures` arrays (one strip per player), `staff_texture`, and the nodes `player.gd` reads. `tests/content/wizard/test_wizard_art.gd` checks it, and `Flow` starts no run with a scene that has no player script.
- Look rules (palette, rects only, whole numbers) are checked for every SVG at once by `tests/core/test_svg_art.gd`. The wiring (strip sizes, the nodes the AI drives) is checked by `tests/content/**/test_*_art.gd`. Nothing tests a pixel, a colour or a sprite's exact size, so a redraw does not fail a test. If a test fails after an art swap, the art broke the contract above, or the test checked a look and should be fixed.
- Add the file to `art/manifest.json`; commit the `.import` and `.uid` files.

## Tests

Small, one behaviour each, on `tests/support/suite.gd` ([tests/README.md](../tests/README.md)). A test builds what it needs from the real scene or a fixture and checks behaviour, so content and art can change underneath it.

## Known weak spots

Listed in [BACKLOG.md](BACKLOG.md) under "Foundation", so they are fixed when a feature needs them and not in one big rewrite.
