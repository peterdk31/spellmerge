class_name CoverState
extends Resource
## One state of a cover kind (ground cover GC2, docs/milestones/ground-cover.md, rule 3): how its
## tufts look, what it does to a body standing in it, whether it spreads, and its triggers to the
## next state. A row of `CoverKind.states`, shaped like a prop's state (`PropState`) on purpose. Data
## only: Feel draws the look (GC3), the cover area plays the rest (GC5). It has no `id` field the
## registry would read (its name is `state_id`), so it is never taken for content.

## Its name (&"rest", &"burning", &"ash"), unique in its kind; triggers go to it by this.
@export var state_id: StringName = &""

@export_group("Look")
## The tuft frames of its kind's sheet (`CoverKind.sheet`) it draws, by index; each tuft picks one.
## Empty: its tufts are not drawn (cover burnt away to bare floor).
@export var frames: PackedInt32Array = PackedInt32Array()
## How far its tufts sway in the wind (1: the kind's full sway; 0: still, as ash).
@export_range(0.0, 2.0, 0.05) var sway: float = 1.0
## How far its tufts bend away from a body going through them (1: fully; 0: not at all).
@export_range(0.0, 2.0, 0.05) var bend: float = 1.0

@export_group("On a body standing in it")
## The status it gives a body standing in it (&"burn", &"chill"; a `ElementBase.status_id`), asked as
## any status is (`Events.status_requested`, GC5). Empty: it does nothing to bodies (most states).
@export var status: StringName = &""
## The status's strength and seconds, as an element gives them.
@export var status_strength: float = 0.0
@export var status_duration: float = 0.0
## Seconds between two of it on the same body standing in it (above 0 when it gives a status).
@export var status_every: float = 0.5

@export_group("Spread")
## The element it touches its four neighbours with (&"fire": burning grass lights the grass beside
## it). Empty: it spreads nothing.
@export var spreads: StringName = &""
## The chance a second that it touches each neighbour (0-1), rolled by the run's chance (GC5).
@export_range(0.0, 1.0, 0.01) var spread_chance: float = 0.0

@export_group("")
## Its triggers, in order: the first that fires moves the cell on.
@export var triggers: Array[CoverTrigger] = []


## A state named `id` drawing `look_frames`, with `rows` (tests and code-made kinds).
static func make(id: StringName, rows: Array[CoverTrigger] = [], look_frames: PackedInt32Array = PackedInt32Array([0])) -> CoverState:
	var made := CoverState.new()
	made.state_id = id
	made.triggers = rows
	made.frames = look_frames
	return made


## True when one of its triggers fires on an element touching it: a state the cover area queues
## touches for.
func listens_to_elements() -> bool:
	for row in triggers:
		if row != null and row.when == CoverTrigger.When.ELEMENT:
			return true
	return false


## The state its trigger on `element` goes to (the first such row's `then`), &"" for none.
func on_element(element: StringName) -> StringName:
	for row in triggers:
		if row != null and row.when == CoverTrigger.When.ELEMENT and row.element == element:
			return row.then
	return &""
