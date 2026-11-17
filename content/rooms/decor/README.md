# Room decor (shared)

## Purpose

Decals any room may place, whatever its biome: scenes with no script and no collision, drawn only, each placed by a room's scene under its `Decor`. A biome's own decals live in that biome's folder (`content/rooms/crypt/decals/`: the torch, the candles); a decal that more than one biome shows lives here. Planned by the hub rework (HR4, docs/milestones/hub-rework.md) and built first by the crypt rework's CR3 (docs/milestones/crypt-rework.md, "Built for every room"), which the hub then uses.

## Contract

- A decal is a `.tscn` whose root is a `Node2D`, placed at its foot (where it meets the floor). It holds no script and no collision object (`tests/content/rooms/test_template_art.gd`), and its sprites lie on the floor, never over a wall, but for light (an additive sprite, or one in `painted_light`), which falls on anything.
- Its light for spell light is a `Marker2D` in the group `light_spot` (`core/base/light_spot.gd`), and its painted light (the glow drawn when spell light is off) is in the group `painted_light`, so it is lit once either way (content/rooms/README.md, "Example to copy").
- Its motes are a `MoteSource` on a node in the group `mote_source` (content/motes/README.md).
- Its art is in `art/tilesets/decor/`, listed in `art/manifest.json`.

| Decal | What it is |
|---|---|
| `beam.tscn` | **The light shaft:** a column of pale light falling from the top of the screen onto the floor (`Column`, additive, drawn over the bodies at z 4; its top lies 212 px above the decal's foot, so a room places it at least that far down), its pool on the floor (`Pool`, painted light; the column is not, so it shows with spell light on, which draws the pool's light but not a column), a `light_spot` in its pale colour, and dust drifting down through it (`Dust`, an area `MoteSource` of `falling_dust`). The crypt's shafts ("Home is up", seen from below; docs/STORY.md, the Vaults) and the hub's landing |
| `beam_wide.tscn` | **The wide light shaft:** the light shaft's own parts (column, pool, `light_spot`, falling dust) drawn wider (a 112 px column, 1.75 times the beam's; a 128×56 px pool, 1.6 times as wide and 1.75 times as deep), its light reaching 120 px and its dust falling over a 40 px wide area; its column is 96 px taller, its top 308 px above its foot, so it reaches above a room 512 px tall as well. A great hall's shaft: the broom's hall (crypt rework CR7) |

## Allowed files

`.tscn`, `.uid` and `README.md`. Art goes in `art/tilesets/decor/`.
