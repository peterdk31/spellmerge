# content/edges: edge styles

How the edge of a room's ground looks, as data (hub rework, [docs/milestones/hub-rework.md](../../docs/milestones/hub-rework.md), "Built for every room"): a coast against the void, the walls of a crack, the rim of a pit. One folder a style, `content/edges/<id>/`, holding `edge.json`. A room's shape file names its style (`"edge": "magic"`), and `tools/ground_shape.py` draws every edge of that room in it (content/rooms/README.md, "A room's ground from a shape"). The game never reads these files: what the generator drew is in the room's ground scene and its art; the motes are written into that scene as `MoteSource` data, which Feel reads.

## Contract

`edge.json`, every field required but `about` and `lip.pebbles`:

| Field | What it is |
|---|---|
| `full_width` | A crack this many pixels wide or wider has the whole edge (lip, seam, glow, rock face, motes); narrower, every part of it fades smoothly with the width, to nothing at a hairline. |
| `seam.colours` | The palette materials (core/base/palette.gd: `fire`, `ice`, ...) the edge's own pixels are drawn in, in bands along the rim, in this order and round again. Never a player's colour nor Blight. |
| `seam.band_length` | How long a band is along the rim, in pixels; the rim's motes take the same bands (`MoteSource.band_length`). |
| `seam.reach` | How far from the rim a pixel still takes the nearest band (cracks and the rock face), in pixels. |
| `lip.width`, `lip.shades` | The band of ground inside the seam, its width at the whole edge and its two colours (dark, then the fleck). |
| `lip.pebbles` | Pebbles on the lip: one every so many seam pixels (`every`), three colours (outline, base, light). |
| `rock.depth` | The rock face under an edge that faces down: its depth in pixels, from the first to the second number by noise along the edge. |
| `rock.shades`, `rock.strata`, `rock.roots` | Its two stone colours, the colour of its banded strata and of the roots hanging from it. |
| `glow.blurs` | The glow over the edge: `[radius, strength]` pairs, each a blur of the seam at half size (radius in half-size pixels), added together. |
| `rim.kind`, `rim.per_100px`, `rim.every` | The mote kind (content/motes) rising off the rim, how many a second for every 100 px of rim, and how many pixels of edge apart the rim's points are. |
| `drip.kind`, `drip.per_100px` | The mote kind falling off the bottom of the rock face, and how many a second for every 100 px of it. |

A colour is a palette material's shade (`leaf.base`, `stone.shadow`) or `#rrggbb`. The hub's styles may go past docs/STYLE.md's palette (the owner, 2026-11-16).

| Style | Used by | Look |
|---|---|---|
| `magic` | the hub | the elements' light in long bands round the coast, a turf lip with pebbles, a banded stone face with roots, embers rising and drips falling (`rim_ember`, `rim_drip`) |

## Allowed files

`edge.json` and this README. Limit: 1 MB.

## Steps

- **A new style:** copy `magic/`, rename the folder, change the numbers and colours, name it in a room's shape file, and draw the room again (`python3 tools/ground_shape.py <shape file>`). `python3 -m unittest discover -s tools` fails while a room drawn in a changed style is not drawn again.
