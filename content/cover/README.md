# content/cover: kinds of ground cover

A kind of ground cover ([docs/milestones/ground-cover.md](../../docs/milestones/ground-cover.md)): grass, cobwebs, the floor. One folder a kind, `content/cover/<id>/`, found by the registry's folder `cover`: its `.tres` on `CoverKind` (core/base/cover_kind.gd documents every field), its tuft sheet (`tufts.svg`, drawn from `tufts.grid.json` by `tools/pixel_grid.py`), its `assets.json` and its own test `test_<id>.gd`. Deleting a kind is deleting its folder.

## Contract

- **What it looks like and what it does are its data alone:** where it grows (`biomes`, `fill_density`, `clump_size`, `wall_gap`, `keep_gap`: `CoverLayout.of`), its tufts (`sheet`, `frame_size`, `tufts_per_cell`, `sway`, `trample_hold`, `trample_spring`) and its states, the first the one every cell starts in. The cover area (gameplay/cover) plays it, Feel (gameplay/feel/cover.gd) draws it; none names a kind.
- **A state** is a look (`frames`, `sway`, `bend`, `trampled_frames`; animated: `animation_frames` at `animation_fps`, `animation_loops`; `motes`, `MoteSource`s at a cell's rate), what it does to a body in it (`status`, `status_strength`, `status_duration`, `status_every`, asked through `status_requested`; `strike_element`, `strike_damage`; `harmless`: a status but no danger to the AI), whether it spreads (`spreads`, `spread_chance` a second) and its triggers to the next state (`element`, `after`).
- **A flat kind** (`look = FLAT`, the floor): no sheet; each state's look is `flat_material`, `flat_motion` (still, grow, shrink, crackle, grow in), `flat_under`, `flat_spark`, `flat_surface`, `flat_under_surface`, `flat_glow`, `flat_glow_strength`, `flat_trace`, `flat_trace_seconds` (docs/milestones/floor-look.md). A new kind of surface is a `FlatSurface` row and a branch of the shader's `surface`.
- **The sheet:** frames of `frame_size` side by side in one row, each tuft drawn from its foot (the frame's bottom middle). An animated state's tuft plays the frames from its first.
- **Smooth** (docs/STYLE.md, "Smooth"): a change of look is a state that plays its frames through (`animation_frames` at least 3, within its `after` seconds), each stage's last frame the next one's first look; a kind of several tuft shapes lists each state's frames in the same order as its rest's (`CoverTufts.frame`).
- **Palette colours only:** growth is **Leaf** (never a player's green), fire Fire and Spark, ash Stone, webs Bone. No outline: tufts are the floor's.
- **A status a body stands in** is asked again every `status_every` seconds; keep a chill shorter than that so cover alone never stacks it into a freeze.
- **Rooms place it** (content/rooms/README.md): each biome's fill, then a room's `CoverField`s over it. A field naming a kind that does not exist is a problem the rooms' test names.

The kinds now: `hub_grass` (the hub: fire lights, spreads, burns, ash, grows back; frost and water put it out; wet grass soaks), `floor` (every open cell no other kind took, `fills_floor`, flat: water, live water under lightning, ice, steam, oil that burns and scorches; docs/milestones/floor.md, docs/milestones/oil-spill.md), `cobweb` (the crypt, sparse: chills; fire burns it away for good). Their states are in their `.tres` files.

## Allowed files

`.tres`, `.svg` (with its `.import`), `.grid.json`, `assets.json`, `.gd` (a kind's test), `.uid` and `.license` files. Limits: 1 MB per image, 1 MB for anything else.

## Steps

- **A new kind:** copy `hub_grass/`, rename the folder, the `.tres` and the test to its new id, set `id`, draw its frames in `tufts.grid.json` and run `tools/pixel_grid.py content/cover/<id>/tufts.grid.json`, list the sheet in `assets.json`, name the biomes it fills, and test its states. Place it in a room by its biome or a `CoverField` (content/rooms/README.md).
- **A new state of the floor:** its fields on `floor`'s `.tres`.
- **A new kind of trigger** is engine work: gameplay/cover/README.md.

## Example to copy

`hub_grass/`: a kind with eleven states (each change animated, each tuft its own strip), a spread, a status, motes and a regrowth.

## Tests

Each kind's own test (`content/cover/<id>/test_<id>.gd`, its states through the real area with `tests/gameplay/cover/cover_kit.gd`), `tests/content/rooms/test_room_cover.gd` (the rooms' cover) and `tests/content/rooms/test_room_places.gd` (every room's cover sound).

History and reasons: [docs/history/content-cover-README.md](../../docs/history/content-cover-README.md).
