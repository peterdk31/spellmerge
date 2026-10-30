# Architecture

How Spellmerge is put together, and where each kind of change goes, so a new feature or a new look never needs a change in the middle of the game. The rules behind it are in [PLAN.md](PLAN.md) and the area READMEs; this page is the map.

## Layers

```
content/   data and scenes: spells, enemies, rooms, the player   (found by folder)
gameplay/  the rules: actor, player, combat, ai, flow, feel, coop (talk through events)
core/      services: events, registry, input, projectiles, pools (know nothing above)
hud/       panels and menus (send requests as events, show state from events)
```

- **Dependency direction:** `core` ← `gameplay` ← `content`. A lower layer never names a higher one. One known exception: `flow.gd` preloads `content/wizard/base/wizard.tscn` as the default `wizard_scene` (listed under "Foundation" in BACKLOG.md).
- **Areas never call each other.** They send and listen to typed signals on `Events` (table in [gameplay/README.md](../gameplay/README.md)); each event has one sender. One stated exception: every area may use the actor kit's public scripts (`gameplay/actor/`).
- **Content is found, not listed.** `Registry` scans the folders, so a new spell, enemy or room is new files only. Code that needs content takes an id (`Flow.room_id_to_play`) and asks the registry; it names no file.
- **Everything that acts is an actor** (phase G, [M2-actors.md](milestones/M2-actors.md)): a body (`Actor`) made of components (Health, Hurtbox, Contact, Mover, Caster; Downed and a look for players) and driven by one controller (`PlayerController`, which is a seat 0–3; `AIController`). Core keys everything by the actor id from `Actors`; it asks an actor's team only to aim, its ramp to draw, its seat for the HUD and its budget for the shared limits. Every spell hurts every actor it hits. No system has a "the player".
- **Components hold configuration, systems hold the hot state.** Combat, Spells and the projectile manager keep per-actor state in packed arrays indexed by actor id; only the actor runs `_physics_process`, stepping its components in a fixed order.
- **Hot paths are pooled.** Shots are rows in `Projectiles`; nodes come from `Pool`; nothing allocates per frame.

## Where each change goes

| I want to ... | Change | Never touch |
| --- | --- | --- |
| add a room, enemy or spell | copy the example folder in `content/` (see its README); a new enemy is a sprite, an actor scene and a `.tres`, no code | `flow.gd`, `registry.gd` |
| add a carrier (a new kind of form: what a form card fires) | a script in `core/spells/carriers/` that runs its own part and lists the cards that do nothing on it, with the builder's sentence (docs/CARRIERS.md; `tests/core/test_card_rules.gd` names any card missing from the list) | `spells.gd`'s launch, `staff_compiler.gd`'s rules |
| add a modifier behaviour or a trigger | the enum value and its code; `test_card_rules.gd` then names each carrier where it does nothing, for a line in that carrier's list (docs/CARRIERS.md) | the other carriers' code |
| add a body behaviour (a new kind of part every actor may have) | a new component in `gameplay/actor/` (see its README), put in the scenes that want it | `player.gd`, `ai.gd` |
| let something else drive a body (an AI teammate, a takeover) | a controller (`ActorController`), handed over with `Actor.drive` | the body's components |
| use another room or enemy in a run | set `Flow.room_id_to_play`, `enemy_id_to_play` (a room picker does this) | the wave or spawn code |
| start a run with other staffs | set `Flow.start_cards` (four lists of card ids) and the staffs in `content/wizard/staffs/` (`starter`, `dev`, by build channel); every player builds them itself | `flow.gd`'s spawn code, `player.gd` |
| change what a player may build with | the player's `bag` (filled from the registry until M3's rewards fill it); builds arrive as `staff_change_requested`, `card_move_requested` and `staff_cards_requested` | the builder, `core/spells` |
| swap a sprite, tile or animation strip | replace the file, keep the contract below | scripts, node names in scenes, tests |
| re-skin the shot, spark or hostile shot | another `FeelPreset` (or its texture fields), set before `Feel._ready` | `feel.gd` |
| change a player's or an enemy's look | the textures on the look component in its scene (`StaffLook` with the staffs' `head` sheets, `CreatureLook`; the `Face` for everyone), or a new look component | the controllers, the other components |
| add behaviour that others must react to | a new typed signal in `core/events/events.gd`, one sender, listeners connect | the listeners' siblings |
| tune feel or balance | a preset or a `.tres` number | tests (they do not assert tuning numbers) |

## Art contract (what a replacement must keep)

Art is data: scenes and resources point at files, and scripts never name a texture path (the one exception is a `FeelPreset`'s default textures, so a preset that leaves a field alone still draws something).

- A stray's body is one 32×32 frame (a strip of whole 32 px frames is still allowed; the look reads the frame count from the width). A player's body is a head sheet per staff: 48×48 frames, 16 directions × 4 player ramps, the grip at (24, 27) (`StaffBase.head`). The face is not in either: it is the shared `Face` over the body (docs/STYLE.md, "The living staffs").
- A replacement `Flow.wizard_scene` must have an `Actor` root with a `PlayerController` child, and a `StaffLook` (with a `default_head`) drawing on its `Sprite` node, and a `Face`. `tests/content/wizard/test_wizard_art.gd` checks it, and `Flow` starts no run with a scene that is not an actor with a player controller.
- Look rules (palette, rects only, whole numbers) are checked for every SVG at once by `tests/core/test_svg_art.gd`. The wiring (strip sizes, the nodes the AI drives) is checked by `tests/content/**/test_*_art.gd`. Nothing tests a pixel, a colour or a sprite's exact size, so a redraw does not fail a test. If a test fails after an art swap, the art broke the contract above, or the test checked a look and should be fixed.
- Add the file to `art/manifest.json`; commit the `.import` and `.uid` files.

## Tests

Small, one behaviour each, on `tests/support/suite.gd` ([tests/README.md](../tests/README.md)). A test builds what it needs from the real scene or a fixture and checks behaviour, so content and art can change underneath it.

## Known weak spots

Listed in [BACKLOG.md](BACKLOG.md) under "Foundation", so they are fixed when a feature needs them and not in one big rewrite.
