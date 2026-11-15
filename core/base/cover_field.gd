@tool
class_name CoverField
extends RoomZone
## A field of ground cover placed by hand in a room's scene (ground cover GC2,
## docs/milestones/ground-cover.md, rule 1): a zone with data, a cover kind and a density over its
## rectangle, moved and sized by its handles. Fields lie over the biome's own fill, in the tree's
## order, each deciding its own cells: a field of no kind clears them. Read by `RoomPlaces` (its data
## beside its rectangle, `zone_data`) and `CoverLayout.of`, and taken out before play as every zone
## is (`RoomPlaces.strip`). It needs no name (`zone_name`): its data says what it is. Its drawing of
## its tufts in the editor is GC3's.

## The cover kind it puts here (a `CoverKind.id`: &"grass"); empty: it clears the cover here.
@export var kind: StringName = &"":
	set(value):
		kind = value
		queue_redraw()
## The share of its cells that get the kind (0-1); the rest get none.
@export_range(0.0, 1.0, 0.01) var density: float = 1.0:
	set(value):
		density = value
		queue_redraw()


## What it puts here (a new `CoverPatch` of its kind and density).
func data() -> Resource:
	return CoverPatch.make(kind, density)
