# content/cover: kinds of ground cover

A kind of ground cover (ground cover GC8, [docs/milestones/ground-cover.md](../../docs/milestones/ground-cover.md)): grass, moss, cobwebs. One folder a kind, `content/cover/<id>/`, found by the registry's folder `cover`: its `.tres` on `CoverKind` (core/base/cover_kind.gd documents every field), its tuft sheet (`tufts.svg`, drawn from `tufts.grid.json` by `tools/pixel_grid.py`), its `assets.json` and its own test `test_<id>.gd`. Deleting a kind is deleting its folder: no room names it but by its fields, and a field naming a kind there is none of is a problem the rooms' test names.

## Contract

- **What it looks like and what it does are its data alone** (rule 3): where it grows by itself (`biomes`, and the fill's `fill_density`, `clump_size`, `wall_gap`, `keep_gap`: `CoverLayout.of`), its tufts (`sheet`, `frame_size`, `tufts_per_cell`, `sway`, and how long a trampled cell lies flat and springs back: `trample_hold`, `trample_spring`) and its states, the first the one every cell starts in. A state is a look (`frames`, `sway`, `bend`, `trampled_frames`; animated, `animation_frames` played at `animation_fps`, once or looping (`animation_loops`), from when a cell begins to show it, each of `frames` the first of a tuft's strip: docs/STYLE.md, "Smooth"; and the `motes` its cells give off while in it: `MoteSource`s read as if the cell were their node, their rate a cell's, never a mask nor a standing one; Feel's `cover_motes.gd`), what it does to a body standing in it (`status`, `status_strength`, `status_duration`, `status_every`, asked through `status_requested`, so Combat applies it by its own rules), whether it spreads (`spreads`, `spread_chance` a second, rolled by the run's chance) and its triggers to the next state (`element`, `after`). The cover area (gameplay/cover) plays it, Feel (gameplay/feel/cover.gd) draws it, the editor's preview shows it; none names a kind.
- **The sheet:** frames of `frame_size` side by side in one row, each tuft drawn from its foot, the frame's bottom middle. An animated state's tuft plays the frames side by side from its first.
- **Smooth** (docs/STYLE.md, "Smooth"): a change of look is a state that plays its frames through (`animation_frames` at least 3, played out within its `after` seconds), each stage's last frame the next one's first look; a kind drawn in tufts of several shapes lists each state's frames in the same order as its rest's, so a tuft keeps its own shape through every change (`CoverTufts.frame` picks the same place in each list). Palette colours only (docs/STYLE.md): growth is **Leaf** (a dull olive, never a player's green), fire Fire and Spark, ash Stone, webs Bone. No outline: tufts are the floor's, as a tile's details are.
- **A status a body stands in** is asked again every `status_every` seconds while it stays: a chill shorter than that wears off between two (the cobwebs' 0.45 s every 0.5 s), so cover alone never stacks it into a freeze.
- **Rooms place it** (content/rooms/README.md): each biome's fill, then a room's `CoverField`s over it.
- `tests/content/rooms/test_room_cover.gd` checks the rooms' cover (the hub's ways clear, the crypt's cobwebs few, a `CoverPreview` in every covered room), `tests/content/rooms/test_room_places.gd` every room's cover sound, and each kind's own test its data and its states through the real area (`tests/gameplay/cover/cover_kit.gd`).

| Kind | Fills | What it does | States |
|---|---|---|---|
| `hub_grass` (Grass) | the hub | fire lights it, every stage a strip of each tuft's own frames: it catches (flames climbing its blades), burns down (the blades in flames), smoulders (embers dying into the ash, harming nobody), lies as ash and grows back; catching or burning, it burns whoever stands in it (burn 2 for 1.5 s, every 0.5 s) and spreads fire (0.6 a second a neighbour), giving off embers and smoke; frost puts it out (its flames going out, `doused`); water wets it (puts its fire out too, its flames going out, `quenched`, soaking already): wet grass does not light, glints with drips and soaks whoever stands in it (soak 25 for 1 s, every 0.5 s) until it dries | `rest` −fire→ `catching` (0.3 s) → `burning` (0.9 s) → `smouldering` (1 s) → `ash` (30 s) → `growing` (1.5 s) → `rest`; `catching` −frost→ `doused` (0.3 s) → `rest`; `catching` −water→ `quenched` (0.3 s) → `wet`; `burning` −frost→ `burning_doused` (0.35 s, its burnt-down flames going out as its blades grow back) → `rest`; `burning` −water→ `burning_quenched` (0.35 s) → `wet`; `rest`, `growing`, `doused`, `burning_doused` −water→ `wet` (8 s) → `rest`; `growing`, `doused`, `burning_doused` −fire→ `catching` |
| `crypt_moss` (Moss) | the crypt | look only: sways a little, bends, is trampled; fire and frost leave it | `rest` |
| `cobweb` (Cobwebs) | the crypt, sparsely, a web a cell | chills whoever walks through it (30% slower); fire burns it away fast, for good, with embers; frost or water puts a burning web out | `rest` −fire→ `burning` (0.5 s) → `gone`; `burning` −frost or water→ `rest` |

## Allowed files

`.tres`, `.svg` (with its `.import`), `.grid.json`, `assets.json`, `.gd` (a kind's test), `.uid` and `.license` files. Limits: 1 MB per image, 1 MB for anything else.

## Steps

- **A new kind:** copy `hub_grass/`, rename the folder, the `.tres` and the test to its new id, set `id`, draw its frames in `tufts.grid.json` and run `tools/pixel_grid.py content/cover/<id>/tufts.grid.json`, list the sheet in `assets.json`, name the biomes it fills, and test its states. Place it in a room by its biome or a `CoverField` (content/rooms/README.md).
- **A new kind of trigger** (a trample that plays, `walked`) is engine work: gameplay/cover/README.md.

## Example to copy

`hub_grass/`: a kind with eleven states (each change animated, each tuft its own strip), a spread, a status, motes and a regrowth.
