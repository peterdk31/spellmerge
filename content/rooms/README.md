# Rooms

## Purpose

Room templates, one folder per biome. A room is a tile-based arena where a wave of enemies is fought, a reward is picked or a story event happens.

**Built in M3** (Run structure; see docs/ROADMAP.md). A small M1 base class already exists (`core/base/room_base.gd`, `RoomBase`); M3 extends it. The example to copy is the M1 crypt arena (see "Example to copy"); M3 adds more rooms.

## Contract

- A room is a `.tscn` scene with tiles from the shared tileset (M1 uses repeated `Sprite2D` tiles; a `TileMapLayer` is welcome once a tileset resource exists), plus a `.tres` describing it on the room base class (`RoomBase`, with the M1 fields `id`, `scene`, `player_spawns`, `enemy_spawns` and `doors`; M3 extends it). `joiner_spawns` (by seat; the hub's beside its altar) is where a seat that joins the room under way appears; without it, at the player spawn farthest from danger. `prop_ids` and `prop_spawns` (one place an id, marked by a `PropSpawns` marker group) stand the room's props (content/props); `prop_yard` and `prop_yard_return` make a prop yard (the hub's).
- Rooms are discovered by folder through `core/registry`: put it in its biome's folder, no list to edit.
- Space for four: the room must be playable and readable with 4 players, with room to dodge and no spot where a player can get stuck.
- Valid doors and spawns: the required doors, spawn points for 4 players, and enemy spawn points that are reachable and not inside walls. Validators for this arrive when M3 extends the room base class.
- Rooms hold layout only. Enemies come from `content/enemies/` through the spawn points and the `gameplay/` systems; do not reference other areas directly. A room that stands dummies names them by enemy id (`dummy_ids`, read through the registry by Flow), never by path.
- Tiles come from the shared tilesets in `art/tilesets/`; do not add new art here.
- What its walls shed when struck (Feel's chips) takes the colours of its own art: `RoomBase.surface_colors()` samples the sprites on its wall bodies, leaving out the floor's colour. Set `debris_colors` (light, base, shadow) on its `.tres` only when the sample looks wrong. Which motes they are is `surface_kinds` (mote kind ids, content/motes): empty, every `surface` kind (the crypt's chips); a room of another material names its own.
- Its `Floor` sprite is at `z_index` `RoomBase.FLOOR_Z` (-2), so Feel's floor marks (one above it) lie on the floor and under every body (0); `tests/gameplay/feel/test_marks.gd` checks every room. The marks drawn in the floor's own shades take its colours from its art (`RoomBase.floor_colors()`: the `Floor` sprite's most common colours times its modulate); set `floor_mark_colors` (light, base, shadow) only when the sample looks wrong.

## Allowed files

`.tscn` (text), `.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file. Rooms hold layout only and carry no scripts.

## Steps

1. Copy the example room into the right biome folder and rename it.
2. Paint the layout with the shared tileset; place doors and spawn points.
3. Edit the `.tres` values. Commit the `.uid` files Godot creates.
4. Run the checks below, then open a PR with a screenshot of the room.

## Example to copy

`content/rooms/crypt/arena_01.tscn` and `arena_01.tres`: a 20×12-tile (640×384 px) crypt arena with a wall border, six pillars for cover, four player spawns in a row at the bottom, six enemy spawns, and an entry (bottom) and exit (top) door. Pillars look like 2.5D columns: the collision stays in `Walls` at the base footprint (one tile), a base sprite sits on it (`Pillars`, drawn under characters), and a top sprite one tile higher (`PillarTops`, `z_index` 5) is drawn over characters, so players and enemies walk behind the upper part; the floor shadow is a polygon in `Shade`, under the bases. Torches are an instance of `content/rooms/crypt/decals/torch.tscn`: a bracket, a looping flame (an `AnimatedSprite2D`) and a flickering additive glow, each from frames shared by every torch; the room sets only each instance's `speed_scale` and start `frame`, so the flames are out of step. No script runs any of it. Each torch is also a light for spell light: a `Marker2D` named `Light` at the flame, in the group `light_spot`, with `metadata/light_art` naming the flame, so it lights the room round it in its flame's colour (core/base/light_spot.gd has the other metadata). Its painted glow (the additive `Glow` and `Core` sprites) is in the group `painted_light`, so spell light hides it while it draws the spot's light and shows it again when the setting is off: a torch is lit once (S6, item 12). A room's `ambient` in its `.tres` darkens it where nothing lights it (1.0, the default, is the room as drawn; the sandbox's is 0.85). The scene is layout only: the floor and walls are `Sprite2D` nodes with the shared tiles from `art/tilesets/crypt/` repeated, the walls are one `StaticBody2D` on physics layer 1 (the wall layer, see the player README), and spawns and doors are `Marker2D` nodes under `PlayerSpawns`, `EnemySpawns` and `Doors`. The `.tres` repeats the marker positions (the registry and `flow` read the `.tres`, so keep both in step; `tests/content/rooms/test_arena_01.gd` checks they match, that no spawn is inside a wall, and that the scene has no scripts).

The sandbox room (staffs B7), `content/rooms/crypt/sandbox.tscn` and `sandbox.tres` (id `sandbox`): two shooting lanes split by a wall down the middle that stops three tiles short of the bottom, so players walk between the lanes; two player spawns at the bottom of each lane; `dummy_spawns` (a `DummySpawns` marker group) puts the training dummy at the top of the left lane and the shooting dummy at the top of the right one, then a group of four more training dummies round the first in the left lane (`dummy_ids`: training, shooting, then training at every spawn after, its last id standing at every spawn past the list), to try homing, pierce and spreads on. Test: `tests/content/rooms/test_sandbox_data.gd`.

The hub (docs/milestones/online-lobby.md, L1), `content/rooms/hub/hub.tscn` and `hub.tres` (id `hub`): the room the main menu's Play goes to, where players join and start a run. A large island (40×26 tiles) floating in the void, very dark, its edge drawn by motes (the owner's pick "A, mixed elements", 2026-11-10): `Void`, the void's tile over the whole room at z -3; `Floor` and `Floor2` to `Floor11`, the island's dark slab floor as row bands at `RoomBase.FLOOR_Z`; `Walls`, a collision rectangle over every void tile (the island's edge is a wall); `Rim`, a hidden `Line2D` in the group `mote_source` round the island's edge, clockwise, with its look as an inline `MoteSource` line (core/base/mote_source.gd: `rim_ember` motes, 172.8 a second over the whole rim, each cooling through one of fire's, spark's, arc's, ice's or void's palette shades), which Feel gives off (`gameplay/feel/source_motes.gd`; content/motes/README.md): **the look is that node's data and the mote kind (`content/motes/rim_ember.tres`), so changing it touches no code, and deleting the node leaves a dark island with no rim.** The teleporter stone in the middle (`start_stone` in the `.tres`, 96×96) and the multiplayer altar on the right (a dais; guests appear beside it) are **props** (props W8: `content/props/hub_stone`, `hub_altar`), which the room stands by its `prop_ids` at its `prop_spawns` (the `PropSpawns` markers, each at the middle of its slab); Flow puts the stone prop in its state `lit` while every wizard stands on the stone and `unlit` otherwise, so its glowing runes, glimmers, light and cue are the prop's look. The **prop yard** (`prop_yard`, above the stone) is where Flow stands every prop the registry knows that stands in a yard (`PropBase.in_yard`), in rows by id, each fresh again `prop_yard_return` (10) seconds after it is lit, broken or gone: a new prop's folder is all it takes to try it there. Three training dummies together on the left (`DummySpawns`, and `dummy_ids` in the `.tres`), four player spawns below the stone. No enemy spawns: no wave is fought there. `invincible = true`: hits land and take nothing. The art is `art/tilesets/hub/` (void, floor) and the props' folders (stone, lit stone, altar). The room's size is its walls' extent (`RoomBase.size_in`). The scene is written from one island shape by a small generator (not in the repository: the shape is the row spans of the floor; the walls and the rim's points follow from it), so keep the floor bands, the wall rectangles and the rim in step by hand if you edit it; `tests/content/rooms/test_hub_data.gd` checks that every 8-pixel cell is floor or wall and never both, that nothing starts in a wall or on the stone, that the stone prop stands on `start_stone` with its art covering it, that the yard is open floor clear of the stone, the altar and every spawn, and that the rim runs clockwise with the void on its left all the way round. Its multiplayer altar is `RoomBase.altar` (L2), the rectangle the altar prop's art covers: a wizard standing in it may open the party to other machines with A.

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
