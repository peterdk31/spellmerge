# Hub rework: the Landing

**Status (2026-11-16): a draft for the owner.** Asked by the owner: "Can you come up with a complete rework of the hub? Right now it looks kinda rough. It should look cool and inviting." Nothing here is built. The steps are **HR1 to HR6** (HR for hub rework), one PR each with its tests, in order, once the owner has answered the questions at the end. It changes how the hub looks and where things stand in it, never what the hub does: the stone, the altar, the lectern, the rack, the dummies, the prop yard, joining and the run's start all work as today (docs/milestones/online-lobby.md, items.md, run-generation.md, ground-cover.md).

## What is rough today

Seen in `tests/screenshots/shot_hub.gd`'s shots on main (2026-11-16):

1. **The floor is nearly black.** `art/tilesets/hub/floor.svg` is Outline (`#14121f`) with Stone shadow joints, and the room's `ambient` (0.9) darkens it again. Docs/STYLE.md says a floor is Stone base and light; the hub's is darker than the void's own tile, so the grass is the only thing that shows.
2. **You cannot see where the island ends.** The void and the floor are almost the same colour, so the edge is only the rim's embers; the "island floating in the void" does not read as an island. Its outline is a staircase of rectangles.
3. **Nothing is a place.** The stone, the lectern, the altar, the dummies and the rack each stand alone on the same dark bricks, with nothing round them saying what they are for or how to get there. The rack is six staffs lying in a row on the floor.
4. **No warmth.** The one light is the stone's, and only once everyone is on it. Nothing in the hub says "stay a while".

## The idea

**The Landing: where the dropped staffs land.** The canon already says a staff that loses a run "lands at the bottom of the shaft again" (docs/STORY.md, canon 7), and the hub's shape is open (STORY.md, "Not fixed yet"). So the hub becomes that spot: an island of turf and old stone floating in the dark under the tower, with a column of pale light falling on it from the hole far above ("Home is up"). The staffs who landed here before made it a camp: a fire, a rack of staffs, a practice ring, a yard of the wizard's junk. The teleporter stone takes you down into the crypt.

The owner's picks stay: an island floating in the void, the rim of embers in the elements' colours (L1, "A, mixed elements"), the stone in the middle, the altar, the dummies together. The void stays dark, because a dark frame is what makes a warm, lit island look inviting.

**Mockups** (drawn at 1×, in the palette, with the game's own art for the stone, altar, lectern, dummies, fire pit, crate, barrel, jar, grass and staff heads, and stand-ins for the rest; made in the session that wrote this, not part of the repository):

- the whole island, labelled (`overview_labeled.png`);
- a player's 640×360 view of the landing, the campfire and the rack (`landing_view.png`);
- all four on the lit stone (`landing_lit_view.png`);
- today's hub next to the new one at the same view (`before_after.png`).

## The layout

One centre, spokes to each place, every place its own landmark with its own light:

| # | Place | What is there | Built from |
|---|---|---|---|
| 1 | **The teleporter plaza**, the middle | A round floor of flagstones in rings (about 240 px across) with an inlay of runes round its edge, the stone in its middle, four lanterns round it. The inlay lights up with the stone. | The stone prop grows a second floor layer, the plaza's runes, lit in its `lit` look (so the plaza is still the prop's, self-contained); lanterns are a decal |
| 2 | **The lectern** | On the plaza, right of the stone, as today | Its zone moves onto the plaza |
| 3 | **The landing**, south of the plaza | A small round stone pad under the light from above, falling dust in the light. The four player spawns are on it. | A floor slab, a `light_spot` and a new mote kind (`falling_dust`) on a box `mote_source`, as the rim's |
| 4 | **The campfire**, south-west | The fire pit, three log benches round it, the warmest light on the island | `fire_pit` (an existing prop, by a `PropStandIn`), benches a decal |
| 5 | **The staff rack**, south-east | A wooden rack behind the premade staffs, so they read as "take one" | The same `ItemStandIn`s, moved in front of a rack decal |
| 6 | **The training ring**, west | A chalk ring in packed earth with the three dummies in it | A floor slab and the dummies' stand-ins |
| 7 | **The altar dais**, east | The altar on a round stone dais; the joiners' spawns beside it; four small crystals, one a seat, lit in that seat's colour while it is taken | A floor slab; the crystals are Feel's (VIEW, from the seats as `altar_code.gd` draws the code) |
| 8 | **The junk yard**, north | A fenced cobbled yard: the prop yard, where every prop with no role stands, as today | The `prop_yard` zone inside a fence decal |
| 9 | **The edge** | A lit lip of turf all round and, under every south edge, the island's rock underside with roots hanging into the void; a few small islets drifting in the void around | The generator (below) and decals |

Paths of stepping stones join the plaza to each place, so a new player sees where to go without a word. The landing stays close: at a wizard's 90 px a second, no more than about 2 seconds from a spawn to the stone's edge (today's is about 1).

## The rules

1. **The look only.** The hub keeps its rules, its props, its events and its state. Every new piece is drawn: sprites, decals, `light_spot`s, `mote_source`s and Feel's view. No new simulation member, so determinism, replays, snapshots and joining are unchanged; the content determinism and snapshot tests cover the hub as they do today.
2. **The scene is the one place a position is written** (content/rooms/README.md), so everything moved is moved in `hub.tscn`, and the owner can keep moving it in the editor.
3. **The island's shape is a file, its scene written from it.** Today the scene is "written from one island shape by a small generator (not in the repository)", so its floor bands, walls and rim must be kept in step by hand. The rework adds the shape as data (`content/rooms/hub/island.grid.json`, a character a tile: turf, slab, void) and the generator to `tools/` (`tools/hub_island.py`, with `tools/test_hub_island.py`), which writes the floor sprites, the wall rectangles, the rim's points and the underside's sprites into `hub.tscn` between two marker comments, leaving every other node as it is. A test fails when the scene and the shape disagree.
4. **Static decoration is the room's own decals,** as the crypt's torches are (`content/rooms/crypt/decals/torch.tscn`): lanterns, benches, the rack's frame, the fence, the islets, in `content/rooms/hub/decals/`, scenes of sprites with no script, each lantern a `light_spot` with its painted glow in `painted_light`. Decor is never a prop: every prop with no role would stand in the junk yard (`PropYard`).
5. **Only palette colours, the 32 grid, rects only** (docs/STYLE.md). The light from above, the lanterns and the fire are spell light, drawn by the game over the art; no art bakes a glow. The room's `ambient` goes back to 1.0.
6. **The grass's floor.** The cover's tufts are Leaf, so on a Leaf floor they vanish (found drawing the mockups). The turf is Leaf shadow with Leaf base specks, the tufts Leaf base and light over it: see question 2.
7. **The seats' crystals use the player colours,** which docs/STYLE.md keeps for the players: a crystal is a seat's marker, as a HUD panel's border is, so it means a player. They are drawn only while that seat is taken.

## Steps

- **HR1: this plan,** and the owner's answers. *Needs the owner.*
- **HR2: the island.** The shape file and `tools/hub_island.py`; the new turf floor tile and the lit lip; the rock underside under the south edges; walls and rim written from the shape; `ambient` 1.0. `test_hub_data.gd` keeps every rule it has (every 8 px cell floor or wall and never both; the rim clockwise, the void on its left); the shape test in `tools/`. Screenshots: `shot_hub.gd`'s, and the island from above (a new shot, the camera zoomed out). *The biggest step; everything after it is placing.*
- **HR3: the plaza and the paths.** The plaza's ring floor and the stone prop's rune layer (lit with the stone; `test_hub_stone.gd`), the lanterns, the stepping-stone paths, the stone and the lectern's zone placed. The cover's fields drawn again round the new places (`test_room_cover.gd`).
- **HR4: the places.** The landing (spawns, its light, `falling_dust`), the campfire, the rack, the training ring, the altar dais with the joiners' spawns, the junk yard's fence round `prop_yard`. `test_hub_data.gd`'s clearances (nothing starts in a wall, the yard clear of the stone, the altar and every spawn, the lectern clear) hold for the new places.
- **HR5: the void and the seats.** The drifting islets and a far layer of stars (a `Parallax2D` node, drawn only, no script), the seats' crystals on the altar (Feel; `tests/gameplay/feel/test_altar_seats.gd`). The ember rim follows the new edge.
- **HR6: the owner's playtest on `/preview/`,** and the fixes it asks for.

## Questions for the owner

1. **The Landing:** the bottom of the shaft, the light from the tower above, a camp the dropped staffs made (written into docs/STORY.md as canon when HR2 merges)? Or keep it an island in the void with no story place?
2. **The floor:** turf (Leaf shadow, a dark meadow, the grass over it) with stone only on the plaza, the paths and the slabs? Or stone everywhere with grass on it, as today but in Stone base and light?
3. **Brightness:** ambient 1.0 and warm lights everywhere (the mockups), with the void kept dark? Or keep it moody, lit only round the places?
4. **Size:** the mockups' island is about 44×28 tiles (today 40×26), so the places have room between them. Keep that, or fit it into today's size?
5. **The seats' crystals in the player colours** on the altar: yes, or a plain light?
