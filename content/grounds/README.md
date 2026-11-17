# content/grounds: ground materials

What the floor of a room's ground is made of, as data (hub rework, [docs/milestones/hub-rework.md](../../docs/milestones/hub-rework.md), "Built for every room"): turf, trodden earth, later flagstones and stepping stones. One folder a material, `content/grounds/<id>/`, holding `ground.json`. A room's shape file names the material of its floor (`"ground": "turf"`) and of each area in it (`"areas": [{"ground": "earth", ...}]`), and `tools/ground_shape.py` draws them (content/rooms/README.md, "A room's ground from a shape"). The game never reads these files.

## Contract

`ground.json`:

| Field | What it is |
|---|---|
| `base` | The colour most of it is. |
| `patches` | Optional: soft patches of another colour (`colour`) wherever smooth noise of these `scales` (pixels, the largest first) is above `above` (0 to 1). |
| `speckle` | Flecks: `[colour, share]` pairs, each that share of its pixels (0.025: one in forty). |
| `slabs` | Optional: irregular flagstones from a seeded cell pattern, never a tile: their `size` (pixels), how far each slab's middle strays (`jitter`, 0 to 1), how much flatter than wide (`squash`), a colour each slab's tone leans toward by chance (`tone`, up to `vary`), the joints' colour and width (`joint`, `joint_width`) and a lit upper edge (`light`, `light_width`). |
| `toward_edge` | Optional: a colour mixed in by noise, more of it the nearer the floor's edge, a wall's or a pit's alike (dust and grit: a material, not a shadow): within `reach` pixels, at most `most` of a pixel, its noise's `scales`. |
| `strokes` | Optional: faint broken arcs going round the area's middle (`centre`; the room's middle for its floor) in `colour`: rings `spacing` pixels apart, a pixel wide, wavering with the angle, `share` of each ring drawn in pieces about 40 px long, from `inner` pixels out (a broom's sweeping, round and round). |
| `about` | A line saying what it is (optional). |

A colour is a palette material's shade (`leaf.shadow`) or `#rrggbb`; the hub's grounds may go past docs/STYLE.md's palette (the owner, 2026-11-16). A floor under ground cover is darker than the cover's tufts, so they show over it.

| Material | Used by | Look |
|---|---|---|
| `turf` | the hub's floor | dark turf, a meadow at night, in soft patches, flecked with Leaf |
| `earth` | areas (clearings, paths) | trodden earth in Wood's shades, flecked with pebbles |
| `flagstone` | the crypt's floor | large irregular flagstones of one cool, quiet Stone, softly jointed, grit toward the floor's edges |
| `dust` | areas (drifts) | dust and grit lying thick enough to hide the stone, a shade darker than the swept stone, in soft patches, heaped a little paler toward the floor's edge (`toward_edge`) |
| `swept` | areas (the broom's ring) | flagstones swept clean, the strokes of a broom round the area's middle |

How a material is drawn is `tools/ground_materials.py`. Areas are drawn in order, a later one over an earlier one (the broom's ring: `dust` over the hall, then `swept` inside it).

## Allowed files

`ground.json` and this README. Limit: 1 MB.

## Steps

- **A new material:** copy `turf/`, rename the folder, change its colours, name it in a shape file and draw the room again (`python3 tools/ground_shape.py <shape file>`).
