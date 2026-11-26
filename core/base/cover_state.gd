@tool
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
## Empty: its tufts are not drawn (cover burnt away to bare floor). Animated (`animation_frames`
## above 1), each is the first of its tuft's frames.
@export var frames: PackedInt32Array = PackedInt32Array()
## How many frames each tuft plays (docs/STYLE.md, "Smooth"): each of `frames` is the first of that
## many side by side in the sheet, played in order from when the cell begins to show the state
## (Feel's clock, look only), at `animation_fps`. 1: a still frame.
@export_range(1, 16) var animation_frames: int = 1
## Frames a second, a whole number (Feel's shader takes 1 to 127).
@export_range(1, 127) var animation_fps: int = 8
## True: it loops, each tuft from its own place in the loop (a flame's flicker); false: it plays once
## and holds its last frame (a change: catching, dying down, growing back).
@export var animation_loops: bool = false
## How far its tufts sway in the wind (1: the kind's full sway; 0: still, as ash).
@export_range(0.0, 2.0, 0.05) var sway: float = 1.0
## How far its tufts bend away from a body going through them (1: fully; 0: not at all).
@export_range(0.0, 2.0, 0.05) var bend: float = 1.0
## The frames its tufts draw while trampled (Feel's, look only: decision 4), each tuft picking one
## by the same roll it picks its `frames` by. Empty: its own frames, pressed flat. A state that
## does not bend (`bend` 0) is never trampled.
@export var trampled_frames: PackedInt32Array = PackedInt32Array()
## The motes its cells give off while they show it (Feel's, look only: burning grass's embers and
## smoke; ground cover GC8), each a `MoteSource` read as if the cell were its node: its place round
## the cell's middle, its rate a cell's (`gameplay/feel/cover_motes.gd`). Not a mask nor a standing
## source: a cell has no art. Empty: none (most states).
@export var motes: Array[MoteSource] = []

@export_group("Flat look")
## A flat kind's look (`CoverKind.Look.FLAT`; Feel's `cover_flat.gdshader`): the palette material its
## cells are drawn in (its base, a 1 px edge of its shadow toward an undrawn cell, glints of its
## light). Empty: not drawn (dry floor).
@export var flat_material: StringName = &""
## How its look plays from when a cell begins to show it, over `animation_frames` at `animation_fps`
## (docs/STYLE.md, "Smooth"): still; grown in from the shape's edge; shrunk back to its middle; or
## still with sparks of `flat_spark` that move every frame (a loop).
enum FlatMotion { STILL, GROW, SHRINK, CRACKLE }
@export var flat_motion: FlatMotion = FlatMotion.STILL
## The material shown under it while it grows or shrinks (ice over water: &"water"); empty: nothing.
@export var flat_under: StringName = &""
## CRACKLE: the material of its sparks (&"arc").
@export var flat_spark: StringName = &""
## The detail drawn on its surface (look only; the floor's look, docs/milestones/floor-look.md): PLAIN
## its base and glints; WATER a rim of its light inside its lower right edge and ripples that shimmer;
## ICE a raised sheet, lit along its upper left edge, cracks of its shadow, a shine of its light that
## catches the spell light (brighter where the floor is lit) and twinkles; STEAM wisps of `flat_spark`
## rising off it, thinning as it goes. A new kind of surface (oil's sheen, a fire's flames) is a new
## row here and a branch of the shader's `surface`.
enum FlatSurface { PLAIN, WATER, ICE, STEAM }
@export var flat_surface: FlatSurface = FlatSurface.PLAIN
## The light its cells give into the spell light while shown (live water's Arc, steam's warm Bone):
## the palette material whose light shade it is, and how bright (0 to 1) at a lit patch's middle;
## eased in as a cell begins to show it and out as it ends (Feel's `cover_lights.gd`). Empty: none.
@export var flat_glow: StringName = &""
@export_range(0.0, 1.0) var flat_glow_strength: float = 0.0
## The mark it leaves on a cell when it ends in a state not drawn (dried water's damp, steam's
## scorch): a sparse speckle of this material's shadow, thinning away in 4 steps over
## `flat_trace_seconds` of Feel's clock (look only: the cell is dry). Empty: none.
@export var flat_trace: StringName = &""
@export_range(0.25, 10.0) var flat_trace_seconds: float = 2.0

@export_group("On a body standing in it")
## The status it gives a body standing in it (&"burn", &"chill"; a `ElementBase.status_id`), asked as
## any status is (`Events.status_requested`, GC5). Empty: it does nothing to bodies (most states).
@export var status: StringName = &""
## The status's strength and seconds, as an element gives them.
@export var status_strength: float = 0.0
@export var status_duration: float = 0.0
## Seconds between two of it on the same body standing in it (above 0 when it gives a status or
## strikes).
@export var status_every: float = 0.5
## True: its status hurts nobody (soak, chill on the floor), so the AI's look does not mark it as
## danger (`cover_danger_looked`) though it still gives it. False: a body walks out of it.
@export var harmless: bool = false
## A body standing in it is struck as by a hit of this element (&"lightning": live water), for
## `strike_damage`, on the same timer as its status and after it (`floor_strike_requested`; Combat
## strikes it as a spell's hit of that element, so a soaked body sets off Current). Empty: no strike.
@export var strike_element: StringName = &""
@export var strike_damage: float = 0.0

@export_group("Spread")
## The element it touches its four neighbours with (&"fire": burning grass lights the grass beside
## it). Empty: it spreads nothing.
@export var spreads: StringName = &""
## The chance a second that it touches each neighbour, rolled by the run's chance (GC5): above 1
## for a spread that runs within a few ticks (live water, 25), at most 60 (one a tick).
@export_range(0.0, 60.0, 0.01) var spread_chance: float = 0.0

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


## True when a body standing in it is given something (a status or a strike): what the cover area
## asks bodies for.
func gives() -> bool:
	return status != &"" or strike_element != &""


## True when the AI's look marks it as danger: it gives something and is not `harmless`.
func is_danger() -> bool:
	return gives() and not harmless


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
