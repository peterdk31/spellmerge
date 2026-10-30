# Rooms

## Purpose

Room templates, one folder per biome. A room is a tile-based arena where a wave of enemies is fought, a reward is picked or a story event happens.

**Built in M3** (Run structure; see docs/ROADMAP.md). A small M1 base class already exists (`core/base/room_base.gd`, `RoomBase`); M3 extends it. The example to copy is the M1 crypt arena (see "Example to copy"); M3 adds more rooms.

## Contract

- A room is a `.tscn` scene with tiles from the shared tileset (M1 uses repeated `Sprite2D` tiles; a `TileMapLayer` is welcome once a tileset resource exists), plus a `.tres` describing it on the room base class (`RoomBase`, with the M1 fields `id`, `demo`, `scene`, `player_spawns`, `enemy_spawns` and `doors`; M3 extends it).
- Rooms are discovered by folder through `core/registry`: put it in its biome's folder, no list to edit.
- Space for four: the room must be playable and readable with 4 players, with room to dodge and no spot where a player can get stuck.
- Valid doors and spawns: the required doors, spawn points for 4 players, and enemy spawn points that are reachable and not inside walls. Validators for this arrive when M3 extends the room base class.
- Rooms hold layout only. Enemies come from `content/enemies/` through the spawn points and the `gameplay/` systems; do not reference other areas directly.
- Tiles come from the shared tilesets in `art/tilesets/`; do not add new art here.

## Allowed files

`.tscn` (text), `.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file. Rooms hold layout only and carry no scripts.

## Steps

1. Copy the example room into the right biome folder and rename it.
2. Paint the layout with the shared tileset; place doors and spawn points.
3. Edit the `.tres` values. Commit the `.uid` files Godot creates.
4. Run the checks below, then open a PR with a screenshot of the room.

## Example to copy

`content/rooms/crypt/arena_01.tscn` and `arena_01.tres`: a 20×12-tile (640×384 px) crypt arena with a wall border, six pillars for cover, four player spawns in a row at the bottom, six enemy spawns, and an entry (bottom) and exit (top) door. Pillars look like 2.5D columns: the collision stays in `Walls` at the base footprint (one tile), a base sprite sits on it (`Pillars`, drawn under characters), and a top sprite one tile higher (`PillarTops`, `z_index` 5) is drawn over characters, so players and enemies walk behind the upper part; the floor shadow is a polygon in `Shade`, under the bases. Torches are an instance of `content/rooms/crypt/decals/torch.tscn`: a bracket, a looping flame (an `AnimatedSprite2D`) and a flickering additive glow, each from frames shared by every torch; the room sets only each instance's `speed_scale` and start `frame`, so the flames are out of step. No script runs any of it. The scene is layout only: the floor and walls are `Sprite2D` nodes with the shared tiles from `art/tilesets/crypt/` repeated, the walls are one `StaticBody2D` on physics layer 1 (the wall layer, see the player README), and spawns and doors are `Marker2D` nodes under `PlayerSpawns`, `EnemySpawns` and `Doors`. The `.tres` repeats the marker positions (the registry and `flow` read the `.tres`, so keep both in step; `tests/content/rooms/test_arena_01.gd` checks they match, that no spawn is inside a wall, and that the scene has no scripts).

The sandbox room (staffs B7), `content/rooms/crypt/sandbox.tscn` and `sandbox.tres` (id `sandbox`, `demo` so the web preview has it): two shooting lanes split by a wall down the middle that stops three tiles short of the bottom, so players walk between the lanes; two player spawns at the bottom of each lane; `dummy_spawns` (a `DummySpawns` marker group) puts the training dummy at the top of the left lane and the shooting dummy at the top of the right one, then a group of four more training dummies round the first in the left lane (Flow stands a training dummy at every spawn after the first two), to try homing, pierce and spreads on. Test: `tests/content/rooms/test_sandbox_data.gd`.

The horde arena (docs/milestones/horde.md), `content/rooms/horde/horde.tscn` and `horde.tres` (id `horde`, `demo`, since the Horde button is in every build): one open, walled crypt room of 1280×720 (the `Floor` sprite covers it all, and flow takes the room's size from it), built like arena_01 (wall tiles 32 px thick on every side, so the open floor is `Rect2(32, 32, 1216, 656)`), with torches, rubble and skulls but no pillars, so the director's spawns never land in cover. The four player spawns stand round the middle; the eight enemy spawns by the walls are a fallback only (the director picks its own points). Test: `tests/content/rooms/test_horde_room.gd`.

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
