# content/grounds: ground materials

What the floor of a room's ground is made of, as data (hub rework, [docs/milestones/hub-rework.md](../../docs/milestones/hub-rework.md), "Built for every room"): turf, trodden earth, later flagstones and stepping stones. One folder a material, `content/grounds/<id>/`, holding `ground.json`. A room's shape file names the material of its floor (`"ground": "turf"`) and of each area in it (`"areas": [{"ground": "earth", ...}]`), and `tools/ground_shape.py` draws them (content/rooms/README.md, "A room's ground from a shape"). The game never reads these files.

## Contract

`ground.json`:

| Field | What it is |
|---|---|
| `base` | The colour most of it is. |
| `patches` | Optional: soft patches of another colour (`colour`) wherever smooth noise of these `scales` (pixels, the largest first) is above `above` (0 to 1). |
| `speckle` | Flecks: `[colour, share]` pairs, each that share of its pixels (0.025: one in forty). |
| `about` | A line saying what it is (optional). |

A colour is a palette material's shade (`leaf.shadow`) or `#rrggbb`; the hub's grounds may go past docs/STYLE.md's palette (the owner, 2026-11-16). A floor under ground cover is darker than the cover's tufts, so they show over it.

| Material | Used by | Look |
|---|---|---|
| `turf` | the hub's floor | dark turf, a meadow at night, in soft patches, flecked with Leaf |
| `earth` | areas (clearings, paths) | trodden earth in Wood's shades, flecked with pebbles |

## Allowed files

`ground.json` and this README. Limit: 1 MB.

## Steps

- **A new material:** copy `turf/`, rename the folder, change its colours, name it in a shape file and draw the room again (`python3 tools/ground_shape.py <shape file>`).
