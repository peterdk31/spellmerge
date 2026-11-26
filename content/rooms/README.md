# Rooms

## Purpose

Room templates, one folder per biome. A room is an arena where the enemies the run's map puts in it are fought, a reward is picked or a story event happens. Base class: `core/base/room_base.gd` (`RoomBase`).

## Contract

- A room is a `.tscn` scene plus a `.tres` on `RoomBase`: `id`, `scene`, `biome`, `kinds` (`fight`, `boss`, `start`, `reward`, `shop`, `fountain`, `treasure`, `secret`, `challenge`; content/room_kinds), `stand_up_after`, `ambient`, `shade`, `air` (a `MoteSource`), `music` (`MusicTrack`), `ambience`, `mist` (`RoomMist`), `ground_shape`, `cover_fill`, `falls_free`, `seam`, `walkway`, `floor_mark_colors`, `debris_colors`, `surface_kinds`. A file with no `id` is not a room.
- Rooms are discovered by folder through `core/registry`: no list to edit.
- **The scene is the one place a position is written.** The game builds the layout (`RoomBase.build()`) and reads it (`RoomPlaces.read`), at any depth, in tree order:
  - spawns and doors: `Marker2D`s under `PlayerSpawns` (by seat), `EnemySpawns`, `Doors`, `JoinerSpawns` (by seat);
  - what stands in it: a `RoomPlacement` (core/base), edited as `PropStandIn`, `EnemyStandIn` or `ItemStandIn` (editor scripts in tools/). A new kind of placed thing is a new placement class and data class, nothing in the reader;
  - zones: a `RoomZone` (`zone_name`), for a place that is no thing or a prop the room must not name (the game stands the registry's prop of that role there). A zone means what Flow makes of its name, never anything in `RoomBase`. A thing that means something is a self-contained prop (`PropBase.role`, `PropBase.area_size`) instead;
  - ground cover: a `CoverField` (`kind`, `density`) under a `Cover` node, plus one `CoverPreview` (tools/) to see it in the editor;
  - sockets: `RoomSocket`s (`SocketEast`, ...; on the 32 px grid, facing out, a 64 px mouth, `RoomSocket.MOUTH`), held open by a `pins` rectangle in the shape; a `SocketPreview` (tools/) draws them.
- Places are whole translations: never rotate, skew or scale a node on the way to a place (`RoomPlaces.problems()`).
- The game strips placements, zones and sockets (`RoomPlaces.strip`) and stands the real bodies (`RoomContents`, gameplay/flow). These editor scripts are the only scripts a room's scene holds; never game code.
- Rooms hold layout only. Enemies come from `content/enemies/` through the run's map; never reference other areas directly.
- A template with `kinds` must name its `biome` (`RoomBase.template_problems`); a room with no kinds (the hub) is offered for no run.
- Sockets: a fight room has two at least, a boss's hall one, the start room four. Open floor on each socket's landing, every socket walkable to every other, in all four mirrorings (`PieceShape.problems`). A walkway is never turned, only mirrored.
- Every crypt room marks a 24 px `RoomZone` `rune` under `Zones`, clear of doorways, props and spawns. A zone `key` is where a dropped key lies.
- Seams (`content/rooms/crypt/seams/`) are laid only between a secret room and the room whose wall it stands against.
- Space for four: playable and readable with 4 players, room to dodge, no spot to get stuck; every way at least 24 px wide.
- Tiles come from `art/tilesets/`, a shape's ground art from `art/grounds/<room>/`; no art here.
- The `Floor` sprite is at `RoomBase.FLOOR_Z` (-2). Walls inside the room block spell light; walls and light-blocking props fit `LightBlockers.MAX` (32) boxes. A crypt room's cobwebs stay at most 6% of its floor.
- Set `debris_colors` / `floor_mark_colors` only when the sample looks wrong, and always on a room whose ground is drawn from a large shape.

### Decoration

Static art is the scene's sprites and tiles, with `mote_source` and `light_spot` nodes. Decor that only reacts to bodies is Feel's (a decor field node in a group, never simulation). Decor that changes the game is one simulation grid of cells placed as a `RoomZone` with data, never an actor per tuft. A torch is an instance of `content/rooms/crypt/decals/torch.tscn` (set only `speed_scale` and start `frame`); candles are `content/rooms/crypt/decals/candles.tscn`.

## A room's ground from a shape

A room may draw its floor from `<room>.shape.json` beside its scene: `size`, `outlines` (or a `frame`, a hall inside walls: `inset`, `corner`, `rough`, `wander`, `pins`, `bays`, `clear`; or polygon `points`), `cracks`, `pits`, `areas`, `edge` (content/edges), `pit_edge`, `ground` (content/grounds), `void`. `python3 tools/ground_shape.py <shape file>` writes `<room>_ground.tscn` (instanced as `Floor`, with its walls, holes, rock face, glow and `MoteSource` lines) and its art in `art/grounds/<room>/`.

- **Never edit a ground scene by hand:** edit the shape and draw it again. `python3 -m unittest discover -s tools` fails when a shape, the room's placements, edge style, ground or generator changed since.
- A room whose `.tres` names `ground_shape` is drawn again by the game as Flow lays it out, mirrored or not (gameplay/feel/README.md, "The ground, drawn as a room is laid out"); a new room drawn from a shape must name it.
- A floating room (edge style `crypt_edge`, `void` a wall) hangs in the world's void; a biome's room, bridge or seam places no backdrop of its own.
- **Holes:** a `StaticBody2D` whose `collision_layer` is exactly `RoomBase.HOLE_LAYER` (2), with `RectangleShape2D`s over the cells (`RoomPlaces.hole_rects`); a wall wins over a hole. Outside a room with holes is a hole too. A spawn, door or placement over a hole is a problem. Falls: `Actor` (gameplay/actor/README.md), `HoleRules` (core/base).

## Allowed files

`.tscn` (text), `.tres`, a room's `<room>.shape.json`, plus `.uid` and `.license` files. Limit: 1 MB per file. Rooms hold layout only and carry no game scripts (their placements and zones, editor scripts, aside); a ground's art is in `art/grounds/<room>/`.

## Steps

1. Copy the example room into the right biome folder (a folder of its own) and rename it.
2. Edit its shape and draw the ground; place spawns, doors, sockets, props, the `rune` zone and cover fields in the editor.
3. Edit the `.tres` values. Commit the `.uid` files Godot creates.
4. Run the checks below, then open a PR with a screenshot of the room.

## Example to copy

`content/rooms/crypt/arena_01.tscn`, `arena_01.tres` and `arena_01.shape.json` ("Crypt antechamber"): a floating room, 640×384 px, its ground drawn from the shape (`python3 tools/ground_shape.py content/rooms/crypt/arena_01.shape.json`, never `arena_01_ground.tscn`), pillars as `crypt_pillar` `PropStandIn`s under `Props`, sockets on all four lips, four player spawns, six enemy spawns, `Doors` entry and exit, candles and the shared light shaft (`content/rooms/decor/`), two cobweb fields. A boss's hall (`crypt/boss_broom/`) belongs to its boss and is deleted with it.

## Tests

Every template is checked by itself (`RoomScan.templates`, `tests/content/rooms/room_scan.gd`): `tests/content/rooms/test_template_layout.gd`, `test_template_art.gd`, `test_template_torches.gd`, `test_room_templates.gd`, `test_room_places.gd`, `test_room_sockets.gd`, `test_room_cover.gd`, `test_rune_zones.gd`, `test_crypt_fight_set.gd`, `test_hub_data.gd`, `test_<id>_data.gd`; `tests/content/runs/test_runs.gd`, `tests/gameplay/ai/test_ai_pit_rooms.gd`, `tests/gameplay/feel/test_shadows.gd`, `test_marks.gd`, `test_ground_drawing.gd`; screenshots `tests/screenshots/shot_rooms.gd`, `shot_cover.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

Besides the general review:

- Is there space for 4 players to move and dodge?
- Are doors and spawns valid and reachable?
- Is it interesting to fight in (cover, hazards, flow) without hiding enemies from view?

History and reasons: [docs/history/content-rooms-README.md](../../docs/history/content-rooms-README.md).
