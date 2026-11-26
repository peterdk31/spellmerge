extends RefCounted
## The floor's lights (docs/milestones/floor-look.md): the cells of a flat cover kind whose state glows
## (`CoverState.flat_glow`: live water's Arc, steam's warm Bone) light the spell light round them.
## Each room's flat look (`cover_flat.gd`, `write_lights`) gathers its glowing cells into patches of
## PATCH x PATCH cells, one spot row a patch at the middle of its glowing cells, as bright as its
## cells' glow over its share of the patch; this holds the rows for every room, at most MOST a frame,
## and the spectacle hands them to the spell light (`SpellLight.light_floor`). It knows rows, not rooms.
##
## Smooth (docs/STYLE.md): a cell's glow eases in over EASE_SECONDS as it begins to show its state and
## out as it ends (the flat look's own clock), so a lake lighting up never pops; the light's bands step
## it. View only: allocates nothing a frame once made.

const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")

## The most rows a frame, every room's together (a lake beyond it lights its first patches only).
const MOST: int = 48
## A patch's side, in cells (2: 32 world px), and how far its light reaches (px).
const PATCH: int = 2
const REACH: float = 34.0
## How long a cell's glow takes to come in or go out (s; 9 frames at 60 a second).
const EASE_SECONDS: float = 0.15
## A floor light's flicker (live water crackles).
const FLICKER: float = 0.25

## The rows (MOST of them, made once) and how many are written this frame. Read only.
var rows: PackedFloat32Array = PackedFloat32Array()
var count: int = 0


func _init() -> void:
	rows.resize(MOST * SpellLightScript.STRIDE)


## A new frame: no rows yet.
func begin() -> void:
	count = 0


## Whether another row fits this frame.
func has_room() -> bool:
	return count < MOST


## One more light at `where`, `strength` bright, in `colour`.
func add(where: Vector2, strength: float, colour: Color) -> void:
	if count >= MOST or strength <= 0.0:
		return
	var seed: float = fposmod(where.x * 0.137 + where.y * 0.311, 1.0)
	SpellLightScript.write_spot_row(rows, count, where, REACH, colour, strength, FLICKER, seed)
	count += 1


## How much of its glow a cell gives `age` seconds after it began to show its state, `glows` its
## state's strength and `glowed` the state's before it (each eased over EASE_SECONDS).
static func share_of(age: float, glows: float, glowed: float) -> float:
	var t: float = clampf(age / EASE_SECONDS, 0.0, 1.0)
	return glows * t + glowed * (1.0 - t)
