class_name StillShotView
extends RefCounted
## What a viewer may know of the still shots of one card body's batch drawn this frame
## (docs/milestones/carrier-looks-fixes.md, phases 1 and 4): the projectile manager hands one out for
## each watched batch as it draws it (`ProjectileManager.watch_body`, `still_shots_drawn`), so
## whoever draws more of a still card (Feel's still motes) reads places, sizes and clocks, never the
## manager's GPU rows: each accessor reads shot `n`'s row through the manager's row readers (`row_*`,
## beside `_write_quad`, the one place a row is read back). Nothing is decoded until asked, so a
## viewer pays only for what it reads (a still card's motes read every shot's clock and the rest only
## of the shots that give off this frame). It holds the rows only while it is handed out: read it
## then, never keep what it says (its rows are the batch's own, written again next frame).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## View only: the manager's drawing fills it, the simulation never reads it (core/sim/README.md).
const VIEW_ONLY: bool = true

## The card body its shots are drawn by (`ProjectileManager.register_body`, from 1), and whether this
## is the enemy ramp's batch of the pair.
var body: int = 0
var enemy: bool = false
## The manager's clock when they were drawn (`sim_time`).
var time: float = 0.0
## How many shots it shows (each piece of a solid one, a wall's, is one); 0 once it is not handed
## out any more.
var count: int = 0

var _rows: PackedFloat32Array = PackedFloat32Array()


## The manager hands it out: the first `count` rows of `rows`, drawn at its clock `now`.
func open(rows: PackedFloat32Array, shots: int, now: float) -> void:
	_rows = rows
	count = mini(shots, rows.size() / ManagerScript.DRAW_STRIDE)
	time = now


## Handed out no more: it lets the batch's rows go (so writing them next frame copies nothing).
func close() -> void:
	# An empty packed array holds no buffer: letting go allocates nothing.
	_rows = PackedFloat32Array()
	count = 0


## Where shot `n` is drawn (its quad's middle, world pixels).
func at(n: int) -> Vector2:
	return ManagerScript.row_place(_rows, n)


## The way shot `n`'s quad's +x runs on the screen, a unit vector: along a solid shot's row (a
## wall's seam).
func across(n: int) -> Vector2:
	return ManagerScript.row_across(_rows, n)


## Shot `n`'s hit size as drawn, in pixels (`ProjectileManager.STILL_HIT` of its quad): the unit a
## still card's look is shaped in (`FormBase.look_shape`).
func reach(n: int) -> float:
	return ManagerScript.row_reach(_rows, n)


## Shot `n`'s hat ramp (0-3) and its look's bits (the kinds, the enemy ramp's flag), as its shader
## reads them.
func ramp(n: int) -> int:
	return ManagerScript.row_ramp(_rows, n)


func look(n: int) -> int:
	return ManagerScript.row_look(_rows, n)


## Shot `n`'s core colour (its first infusion's tint).
func core(n: int) -> Color:
	return ManagerScript.row_core(_rows, n)


## Shot `n`'s still clock (`ProjectileManager.still_code`): x the seconds since it was placed
## (STILL_START once past them), y the seconds of life it has left (STILL_END while it has more).
func clock(n: int) -> Vector2:
	var code: float = ManagerScript.row_code(_rows, n)
	return Vector2(ManagerScript.still_since(code), ManagerScript.still_left(code))
