@tool
class_name CoverPatch
extends Resource
## What a cover field puts over its rectangle (ground cover GC2, docs/milestones/ground-cover.md,
## rule 1): a `CoverField`'s data (`RoomZone.data()`), kept by `RoomPlaces` beside its rectangle
## (`zone_data`) and read by `CoverLayout.of`. It has no `id`, so the registry never takes it for
## content.

## The cover kind it puts there (a `CoverKind.id`); empty: it clears the cover there.
@export var kind: StringName = &""
## The share of its cells that get the kind (0-1); the rest get none.
@export_range(0.0, 1.0, 0.01) var density: float = 1.0


## A patch of `kind_id` at `share` (tests and code-made fields).
static func make(kind_id: StringName, share: float = 1.0) -> CoverPatch:
	var made := CoverPatch.new()
	made.kind = kind_id
	made.density = share
	return made
