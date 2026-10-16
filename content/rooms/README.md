# Rooms

## Purpose

Room templates, one folder per biome. A room is a tile-based arena where a wave of enemies is fought, a reward is picked or a story event happens.

**Opens for PRs in M3** (Run structure; see "Opens for PRs" in docs/ROADMAP.md). **The example to copy arrives with Claude's first room in M3**; this README is updated then with its path. Biome folders are created with the first content.

## Contract

- A room is a `.tscn` scene with a tilemap, plus a `.tres` describing it on the room base class (arrives in M3).
- Rooms are discovered by folder through `core/registry`: put it in its biome's folder, no list to edit.
- Space for four: the room must be playable and readable with 4 wizards, with room to dodge and no spot where a player can get stuck.
- Valid doors and spawns: the required doors, spawn points for 4 players, and enemy spawn points that are reachable and not inside walls. Validators for this arrive with the room base class.
- Rooms hold layout only. Enemies come from `content/enemies/` through the spawn points and the `gameplay/` systems; do not reference other areas directly.
- Tiles come from the shared tilesets in `art/tilesets/`; do not add new art here.

## Allowed files

`.tscn` (text), `.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file. Rooms hold layout only and carry no scripts.

## Steps

1. Pick an issue labelled `now` in this area and comment `/claim`.
2. Copy the example room into the right biome folder and rename it.
3. Paint the layout with the shared tileset; place doors and spawn points.
4. Edit the `.tres` values. Commit the `.uid` files Godot creates.
5. Run the checks below, then open a PR with a screenshot of the room.

## Example to copy

Arrives with Claude's first content in M3. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Besides the standard criteria:

- Is there space for 4 players to move and dodge?
- Are doors and spawns valid and reachable?
- Is it interesting to fight in (cover, hazards, flow) without hiding enemies from view?
