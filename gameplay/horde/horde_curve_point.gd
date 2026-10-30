class_name HordeCurvePoint
extends Resource
## One point of the horde's curve (`HordeCurve`, docs/milestones/horde.md): from `seconds` into
## the run, how many enemies appear a second, how many may be alive at once, and who they are.
## Between two points every number is interpolated.

## Seconds into the run (the clock stops in build breaks).
@export var seconds: float = 0.0
## Enemies that appear a second.
@export var spawns_per_second: float = 1.0
## The most horde enemies alive at once.
@export var cap_alive: int = 30
## How likely each enemy is, by its registry id (`content/enemies/`): a share of the total, not
## a percentage. An id missing here weighs 0 at this point.
@export var weights: Dictionary[StringName, float] = {}
