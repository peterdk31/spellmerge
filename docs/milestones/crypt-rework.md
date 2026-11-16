# Crypt rework: the Vaults

**Status (2026-11-16): a plan, waiting on the owner.** CR1 is this document and the owner's answers to the questions at the end; nothing is built until they are answered. Asked by the owner: "Redesign the crypt. Draw inspiration from the new hub design." The steps are **CR1 to CR7** (CR for crypt rework), one PR each with its tests, in the order of "Steps". The rework changes how the crypt's rooms look, and in a few of them where the floor has fallen in (pits, which are the hub's **holes**). Otherwise the crypt plays as it does today: the same templates, kinds, spawns, doors, exits, pillars on the same cells, enemies, boss and run (docs/milestones/run-generation.md, boss-old-broom.md).

## What is rough today

Seen in `tests/screenshots/shot_rooms.gd`'s shots on main (2026-11-16, `room_arena_01` to `room_boss_broom`), next to `shot_hub.gd`'s:

1. **Every line is straight.** The walls are bands of the same 32 px brick tile on all four sides, the floor a grid of the same brick tile, the low walls and sarcophagi boxes of it. This is what the owner said of the old hub ("way too 'square' and straight"), and the new hub has no straight line left.
2. **The floor is louder than the fight.** A saturated purple brick, with a mortar line every 16 px across the whole room, sits behind every shot, enemy and wizard. The moss fills large patches of it, so the floor is the busiest thing on screen.
3. **The rooms only differ in where the pillars stand.** The antechamber, the nave, the ossuary court, the crossing and the broom's hall have one floor, one wall and one light, so the run's rooms read as the same room. Nothing in a room is a place you remember: no centrepiece, nothing that says what the room was for.
4. **The light is flat.** Torches have a small glow, and the room is evenly lit right up to the walls. Nothing is dark, so nothing feels dangerous, and nothing is warm, so the torches don't read as safety either.
5. **It no longer matches the hub.** The Landing is drawn per pixel, with soft light, a beam from above, motes along its edges and cracks into the void. Coming down from it into a tiled room is a drop in quality, not just a change of place.

## The idea

**The Vaults: the crypt under the Landing.** The hub rework (question 1, answered) puts the crypt directly under the Landing. The Vaults are the old burial halls down there: dug by someone long before the wizard, cracked by the weight of the island hanging above, and pierced by its roots. Today's rooms keep their names and layouts, but each one is drawn as a hall carved from a ragged outline rather than a box:

- **Organic halls.** Every wall follows a rough curve. Masonry gives way to rubble where it has fallen, and the floor's edge is a lip of broken stones and grit. The wall that faces the camera has a real masonry face, so the room reads as dug down into the dark.
- **Quiet flagstones.** The floor is large, irregular flagstones of one quiet shade, softly jointed, darker toward the walls and dusty in the corners. It sits behind the fight instead of competing with it.
- **Warm against cold.** Torches and candles cast warm pools of light, and the corners fall away into the dark. **A shaft of pale light falls from a crack in the vault** in most rooms, the Landing's own light from above ("Home is up"), with motes of dust drifting in it. It is the hub's beam, seen from below.
- **One landmark a room,** each with its own light: the antechamber's broken column under the shaft, the nave's sarcophagus ringed by candles, the ossuary's walls of skulls, the crossing's fallen-in floor and the broom's swept ring.
- **The floor gives way.** In some rooms the floor has fallen into the deep and left **pits**: holes (the hub's, docs/milestones/hub-rework.md, "Holes"). Wizards walk round them and dash over them, and an enemy knocked in is gone. A faint cold light breathes up from below, dust falls in, and cracks run out from the edge. This is the hub's cracks again, in the crypt's own material.

**Mockups** (drawn at 1×, with stand-ins for the wizards, enemies and props; made in the session that wrote this, not part of the repository):

- the antechamber (arena_01's layout): the hall, the shaft on the broken column, the torches' pools (`crypt_antechamber.png`);
- the crossing (arena_04's layout): the sarcophagi with candles, the ring of pillars round the fallen-in floor, its cracks, the shaft into the pit (`crypt_crossing.png`);
- the broom's hall: the swept ring, the drifts and the heaps against the walls (`crypt_broom.png`);
- today next to the rework at a player's view (`before_after_antechamber.png`, `before_after_crossing.png`).

The mockups are darker than the game would be (question 3): they set the mood, and CR3's screenshots in a real fight will set the levels.

## The rooms

The layouts are kept: every spawn, door, exit, pillar, low wall and prop stays on its cell, so the template tests, the AI's ways and the run's balance are unchanged. Only the pits (question 2) change where you can walk.

| Room | Its landmark | Its light | A pit? (question 2) |
|---|---|---|---|
| **arena_01, the antechamber** | The middle pair of pillars: one broken off under the shaft of light, its drums lying round it (decor) | The shaft on the broken column; six torches | No: the first room stays plain |
| **arena_02, the nave** | The sarcophagus in the middle of the nave: a lid with a carved figure, candles round it, the colonnades' shadows falling across | The candles' warm pool in the middle; torches along both walls; a shaft at one end | A collapsed side aisle: one pit along a wall behind a colonnade, a crack running toward the middle |
| **arena_03, the ossuary court** | The low walls built of bones: skull niches in their faces and in the north wall, bones piled at their feet | Torches, low; the court in the middle lit by a shaft | No: the low walls already make the room |
| **arena_04, the crossing** | The ring of pillars round the middle, where the floor fell in: a round pit, two cracks running out of it between the pillars | The shaft falling into the pit; candles on the four sarcophagi | Yes: the pit in the ring, small enough to dash over (about 56×44 px), its cracks narrowing to hairlines |
| **boss_broom, the broom's hall** | The swept ring: the broom keeps the middle of its hall swept, so the floor there is clean stone with stroke marks, and everything (dust, bones, broken stone) has been pushed out into a drift round it and into heaps against the walls; the dust heaps (props) stand in those drifts | Ten torches; a wide shaft on the middle | No: a boss never falls (HR-H2), so a pit in its room would only work against the party |
| **sandbox** | Unchanged (a testing room, question 6) | | |

## The rules

1. **Look only, except for pits.** Every room keeps its rules, placements, events and state. Each new piece is drawn: the ground's art, decals, `light_spot`s, `mote_source`s and Feel's view. A pit is a hole, so it uses the engine HR-H1 and HR-H2 built (walking stops at its edge, dashes, teleports and pushes cross it, a body that ends over it falls, the AI walks round it and shoots across it); nothing new in `core/` or `gameplay/`. Determinism, replays, snapshots and joining are unchanged; `test_content_determinism.gd` and `test_snapshot_game.gd` play every room as today.
2. **The scene is the one place a position is written** (content/rooms/README.md). The floor, walls, faces and pits are drawn from a shape file (`<room>.shape.json`) by `tools/ground_shape.py`, as the hub's are. Pillars, low walls, torches, candles, decor, spawns and props stay in the room's scene, edited by hand. **The walls stay rectangles:** the generator covers every wall pixel's cell with 8 px boxes, as it does for the hub's void, so the walls follow the drawn outline within half a cell. A room's border walls today are 32 px boxes. Drawn, they wander between about 24 and 48 px, and never cover a spawn, a door, an exit or a placement (`keep_clear_round`, as the hub's cracks).
3. **Organic lines everywhere** (the owner's rule for the hub, 2026-11-16). No straight outline: the halls' edges, the pits, the low walls' drawn tops, the sarcophagi's broken corners and the dust drifts all follow curves with noise in them. The 32 grid stays where things stand and are sized.
4. **The pillars stay 2.5D** (content/rooms/README.md, "Example to copy"): a base on its one-tile wall box, a top drawn over bodies, a shadow, all checked by `test_template_pillars.gd`. They are drawn again as round columns, with chipped capitals and one broken variant, and stay shared art in `art/tilesets/crypt/`.
5. **Static decoration is the room's own decals,** as the torches are today (`content/rooms/crypt/decals/`): candles (a cluster, a looping flame, a `light_spot` and a `painted_light` glow, like a torch), the light shaft (the hub's beam decal from HR4, shared, `content/rooms/decor/`), hanging roots, bone piles, the broken column's drums, and the sarcophagus's lid with its figure. No script runs any of it; decor never blocks (`test_template_art.gd`).
6. **Readable first.** The floor is one quiet value, between Stone shadow and Stone base, with joints only a little darker. Shots, enemies and wizards are the brightest and most saturated things on screen, as `docs/STYLE.md`'s "Readability" asks. The dark is at the walls and in the corners, never where the fight is: no spawn, exit or open floor in the middle third of a room falls below the level of the floor in a torch's half-light. CR3 sets this with a screenshot of a real fight in the antechamber (`shot_rooms`), which the owner looks at before CR4 draws the rest.
7. **Past the style guide where it helps, as the hub went** (question 4): soft pools of light, the shaft's gradient, and the pits' cold breath. The ground's art is a PNG drawn per pixel, as the hub's is. The 32 grid, the pixel look and the outline colour stay. The crypt's colours stay in the palette's Stone, Bone, Wood and Fire, plus Mana for the pits' cold light, so the crypt still looks like the crypt next to its enemies.
8. **The cover stays,** redrawn into the new floor: the crypt's moss grows in the halls' damp corners and along the roots, not in large patches across the middle, and the cobwebs stay in the corners. The fields are drawn again round the new places (`test_room_cover.gd`), and the moss is a share of the floor less than today's (question 5).
9. **A room drawn from a shape names its floor-mark and debris colours** in its `.tres`, as the hub does, so its large ground art is never sampled.

## Built for every room

As with the hub, nothing here is the crypt's alone except its shape files and where its things stand. Every piece is general, documented in its area's README, and tested on fixture shapes (`tools/test_ground_shape.py`), not only through the crypt:

| Piece | What any room gets | Where |
|---|---|---|
| **Pits: holes inside the floor** | A shape file's `pits`: outlines cut out of the land (a wavy, rough oval each, as an outline is), always holes whatever the room's `void` says, with cracks that may start from a pit's edge (`"from": "pit"`, its index) as they start from an outline's today. The hub's cracks keep working as they are | `tools/ground_shape.py` (`Ground`: pits and cracks from them; `_grid_rects`: a pit's cells are holes) |
| **An edge style per edge** | Today a room has one `edge`. A shape file may name one for its outlines (`edge`) and another for its pits and their cracks (`pit_edge`), so a hall's walls and its pits each look like themselves | `tools/ground_shape.py`; content/rooms/README.md |
| **A wall face** | An edge style's optional `face`: the masonry face drawn on the wall side of every edge with floor below it (the wall the camera looks at), its height, courses and shades, a dark line at its foot. Where the void is wall, the face's pixels are wall cells like the rest of the wall's art; under a pit it is the shaft's own wall going down into the dark | `content/edges/<id>/edge.json` (`face`), drawn by the generator |
| **A rubble lip** | The lip's `pebbles` grow to stones and grit of several sizes along a wall's foot (`lip.rubble`) | `edge.json` |
| **Edge styles** | `crypt_wall`: a ragged masonry edge, its face, a rubble lip, no seam or glow, no motes. `crypt_pit`: broken flagstone teeth on the lip, a faint cold seam in Mana, the shaft's face going down into the dark, a soft cold glow, dust falling in (`pit_dust`, a new mote kind falling from the lip) | `content/edges/crypt_wall/`, `content/edges/crypt_pit/` |
| **Slabbed ground** | A ground material's optional `slabs`: irregular flagstones (their size, how much it varies, the joint's shade and width, a lit upper edge), drawn per pixel by a seeded cell pattern, never a tile, so no grid shows | `content/grounds/<id>/ground.json` (`slabs`), drawn by the generator |
| **Ground materials** | `flagstone` (the crypt's floor), `dust` (an area: the drifts and the corners' grit), `swept` (an area: clean stone with long stroke marks) | `content/grounds/` |
| **Candles** | A decal like the torch: wax, a looping flame, a `light_spot` and a `painted_light` glow | `content/rooms/crypt/decals/candles.tscn`, with `test_template_torches.gd` learning it (looping, out of step, shared frames) |
| **The light shaft** | The hub's beam (HR4), placed in a crypt room: a column falling from the top of the screen onto a floor slab, falling dust in it from an area `mote_source` (HR4's `falling_dust`) | `content/rooms/decor/beam.tscn`, shared |

A crypt room is still free to keep its tiles: the template tests check what a room holds, not how it was drawn. The rework just draws every crypt room from a shape.

## Tests that change

- `test_template_art.gd`: "the floor covers the room" reads the floor from its art (the ground's opaque pixels), as `test_hub_data.gd` does since HR2. "Every wall drawn" becomes every wall cell under the ground's art or a pillar's or low wall's sprite. "No rubble or skull over a wall" holds for the decor decals.
- `test_template_layout.gd` keeps every check (spawns, doors, exits, the reach from the first spawn). With pits, "every floor cell reached from the first player spawn" walks round holes, so it also shows that no pit cuts a room in two (a pit always has a way round it). The boss check (every boss fits at its first spawn clear of walls and props) also checks holes.
- `test_template_pillars.gd`, `test_template_torches.gd`: the new pillars' art, the candles.
- `test_room_cover.gd`: the fields drawn again; no cover on a pit's cell (HR-H2's rule, already checked).
- `tools/test_ground_shape.py`: pits, a crack from a pit, two edge styles in one room, the face, slabs, rubble, all on fixture shapes; every crypt room's ground up to date.
- `tests/gameplay/feel/test_marks.gd` (every room's `Floor` at `FLOOR_Z`, as the ground scene's root is).

## Steps

- **CR1: this plan,** and the owner's answers. *Needs the owner.*
- **CR2: the generator's new pieces,** on fixture shapes only: pits and cracks from them, an edge style per edge, the wall face, the rubble lip, slabbed ground; `content/edges/crypt_wall/` and `crypt_pit/`, `content/grounds/flagstone/`, `dust/` and `swept/`, the mote kind `pit_dust`; the READMEs (content/rooms "A room's ground from a shape", content/edges, content/grounds, content/motes). No room changes.
- **CR3: the antechamber,** the first room drawn from a shape: arena_01's `arena_01.shape.json` and ground scene, the new pillars, candles, roots and bone decals, the shaft (HR4's beam decal; if HR4 has not landed yet, CR3 builds the beam decal and HR4 reuses it), the cover's fields, its `.tres` colours. The template tests changed as above. **The owner looks at its screenshots in a fight** (rule 6) before CR4.
- **CR4: the nave and the ossuary court:** arena_02 with its side pit (question 2) and the sarcophagus and its candles, arena_03 with the bone walls (the low walls' art drawn again, skull niches in the faces).
- **CR5: the crossing:** arena_04 with its pit and cracks in the ring, the shaft into it, the sarcophagi's candles; the template layout's pit check.
- **CR6: the broom's hall:** the swept ring (`swept` and `dust` areas), the drifts and heaps against the walls round the dust heap props, the shaft. Then the old crypt tiles that nothing uses any more are deleted (`floor.svg`, `wall.svg`, `wall_top.svg`; the sandbox keeps whatever it uses, question 6).
- **CR7: the owner's playtest on `/preview/`,** and the fixes it asks for.

Each step updates the docs it touches: the crypt's paragraphs in content/rooms/README.md, content/cover/README.md (the crypt's fields), docs/STYLE.md (rule 7, as the hub's line), docs/STORY.md (the Vaults, with a yes to question 1), and docs/ROADMAP.md (an entry for this plan once the owner approves it).

## The questions

1. **The Vaults:** the crypt as the old burial halls under the Landing, cracked by its weight, with its roots coming through and its light falling in as shafts ("Home is up", seen from below)? docs/STORY.md's canon 4 gains a line. Or keep the crypt's story as it is and use only the look?
2. **Pits:** the floor fallen in (holes) in the nave's side aisle and in the crossing's ring, as the plan picks? Or in every fight room? Or nowhere, keeping the crypt's gameplay exactly as it is and the rework only a look? A fall in a run costs a wizard a fifth of its most health (HR-H2), and an enemy knocked in is gone. The plan's pick is the two rooms: it gives the run some rooms where pushes matter, without making every room about the edges.
3. **How dark:** the mockups' mood (dark corners, warm pools, the walls falling into black), checked against a real fight in CR3? Or brighter, closer to today's evenly lit rooms, with the light only as accents? The plan's pick is the mood, with rule 6 keeping the middle of every room readable.
4. **Past the style guide:** the soft light, the shaft and the pits' glow as the hub does it (the plan's pick)? Or stay inside docs/STYLE.md's palette and banded light, with the crypt as the guide's own reference biome?
5. **The moss:** much less of it, in the damp corners and along the roots (the plan's pick, so the floor stays quiet)? Or as much as today?
6. **The sandbox:** leave it as it is (it is a testing room nobody reaches in a run; the plan's pick), or draw it again with the crypt?
7. **The floor's colour:** the cool, quiet Stone of the mockups (the plan's pick, so the warm light and the spells stand out)? Or keep today's stronger purple?
