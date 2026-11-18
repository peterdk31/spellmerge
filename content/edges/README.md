# content/edges: edge styles

How the edge of a room's ground looks, as data (hub rework, [docs/milestones/hub-rework.md](../../docs/milestones/hub-rework.md), "Built for every room"): a coast against the void, the walls of a crack, the rim of a pit. One folder a style, `content/edges/<id>/`, holding `edge.json`. A room's shape file names its style (`"edge": "magic"`), and `tools/ground_shape.py` draws every edge of that room in it (content/rooms/README.md, "A room's ground from a shape"). What the generator drew is in the room's ground scene and its art (the motes written into that scene as `MoteSource` data, which Feel reads); since connected biomes CB4 the game also reads these files, through the registry (`Registry.get_data`), to draw a room's ground again as it is laid out, mirrored or not (gameplay/feel/README.md, "The ground, drawn as a room is laid out"): a style changed here changes the game's drawing at once, and the baked art when the room is drawn again.

## Contract

`edge.json`. Required: `full_width`, `deep` and `lip`; every other part is optional, and an edge without it has none (a `drip` needs a `seam`: the drips take its bands' colours) (the crypt's walls have no seam, glow, rock face or motes; its floating rooms' edge no seam, glow, top or face):

| Field | What it is |
|---|---|
| `full_width` | A crack this many pixels wide or wider has the whole edge (lip, seam, glow, rock face); narrower, each of them fades smoothly with the width, to nothing at a hairline. |
| `deep` | The colour shown down a crack too thin to cut out of the floor (drawn into it, opaque). |
| `seam.colours` | The palette materials (core/base/palette.gd: `fire`, `ice`, ...) the edge's own pixels are drawn in, in bands along the rim, in this order and round again. Never a player's colour nor Blight. |
| `seam.band_length` | How long a band is along the rim, in pixels; the rim's motes take the same bands (`MoteSource.band_length`). |
| `seam.reach` | How far from the rim a pixel still takes the nearest band (cracks and the rock face), in pixels. |
| `lip.width`, `lip.shades` | The band of ground inside the seam, its width at the whole edge and its two colours (dark, then the fleck). |
| `lip.pebbles` | Pebbles on the lip: one every so many seam pixels (`every`), three colours (outline, base, light). |
| `lip.rubble` | Stones and grit fallen along the edge: one every so many edge pixels (`every`), `sizes` pixels across (smallest, largest), three colours (`shades`: the dark row under it, its base, its lit top row). |
| `top` | Where the void is wall, the wall's own top (tools/ground_walls.py): rough stone in `shades` (dark, stone), flecked with `joint`, a lit `rim` along the floor's edge, falling into `deep` from `fade[0]` to `fade[1]` pixels from the floor. |
| `face` | The face of a wall above the floor, the wall the camera looks at: `height` pixels of masonry in courses `course` high and blocks `block` wide, from `shades[0]` at its foot to `shades[1]` at its top, its joints `joint`, a lit top row `light` under a dark `cap`; `foot`: `[colour, rows]`, the floor's rows under it mixed toward that colour (its contact shadow). Outlines only, never a pit. |
| `rock.depth` | The rock face under an edge that faces down: its depth in pixels, from the first to the second number by noise along the edge. |
| `rock.shades`, `rock.strata`, `rock.roots` | Its two stone colours, the colour of its banded strata and of the roots hanging from it. |
| `glow.blurs` | The glow over the edge: `[radius, strength]` pairs, each a blur of the seam at half size (radius in half-size pixels), added together. |
| `rim.kind`, `rim.per_100px`, `rim.every` | The mote kind (content/motes) rising off the rim, how many a second for every 100 px of rim, and how many pixels of edge apart the rim's points are. `rim.colours` (optional): the palette materials its motes take, at random, instead of the seam's bands. A rim round a pit runs with the pit on its left, so its motes go into the pit. |
| `drip.kind`, `drip.per_100px` | The mote kind falling off the bottom of the rock face, and how many a second for every 100 px of it. |

A colour is a palette material's shade (`leaf.base`, `stone.shadow`) or `#rrggbb`. The hub's styles may go past docs/STYLE.md's palette (the owner, 2026-11-16).

| Style | Used by | Look |
|---|---|---|
| `magic` | the hub | the elements' light in long bands round the coast, a turf lip with pebbles, a banded stone face with roots, embers rising and drips falling (`rim_ember`, `rim_drip`) |
| `crypt_wall` | the crypt's halls (`edge`) | a ragged masonry edge, its face of stone courses, a rough top falling into the dark, rubble along its foot; no seam, glow, rock face or motes |
| `crypt_edge` | the crypt's floating rooms (`edge`; the owner's second round, crypt rework CR-G) | a slab of floor hanging in the dark: a broken flagstone lip with stones and grit fallen along it, the slab's rock underside hanging under its south edges with roots, dust falling off its edge (`pit_dust`); no masonry, no top or face, no seam or glow. The shape's `void` stays `"wall"`, so its edge is an invisible wall |
| `crypt_pit` | the crypt's pits (`pit_edge`) | broken flagstone teeth, a faint cold seam of Mana, the shaft's wall going down into the dark, a still cold glow, dust falling in (`pit_dust`) |

A shape file names one style for its outlines and frame (`edge`) and may name another for its pits and the cracks from them (`pit_edge`); each pixel's edge is drawn in the style of the open ground nearest it.

## Allowed files

`edge.json` and this README. Limit: 1 MB.

## Steps

- **A new style:** copy `magic/`, rename the folder, change the numbers and colours, name it in a room's shape file, and draw the room again (`python3 tools/ground_shape.py <shape file>`). `python3 -m unittest discover -s tools` fails while a room drawn in a changed style is not drawn again.
