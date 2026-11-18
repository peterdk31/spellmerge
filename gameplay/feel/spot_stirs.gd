extends RefCounted
## The room's lights take notice (docs/milestones/atmosphere.md, E): a candle's or a torch's light
## (a spot row of the spell light's, `LightSpot`) ducks and leans away when a shot passes close, and
## leans out from a blast's wave, then eases back. The spectacle steps it once a frame while spell
## light is on, with the world's stirs (`stirs.gd`: the shots read this frame near each spot, and the
## blasts' push) and the spell light's spots; it hands the moved rows back (`SpellLight.show_spots`).
## It knows nothing of where the shots come from, and the spell light nothing of why its spots move.
##
## **Each spot's own ease:** its lean (px) and how much it ducks (a share of its strength) follow
## what the stirs ask (`target`) at most LEAN_IN px and DUCK_IN a second toward more and LEAN_OUT,
## DUCK_OUT back, so a shot's pass is a few frames in and a slower settle, never a jump. A frame
## with every spot at rest after a stir hands the rows as placed back once, and from then on costs
## a look at the stirs a spot.
##
## Nothing is allocated a frame: its arrays are sized when the room's spots change (and then start
## at rest).

const StirsScript := preload("res://gameplay/feel/stirs.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")

## How near a shot must pass to stir a light (px), how far it leans it away at most and how much of
## its strength it takes; a blast's push leans it BLAST_LEAN px at its fullest and ducks it by
## BLAST_DUCK. A lean is at most LEAN_MOST px, a duck at most DUCK_MOST.
const SHOT_REACH: float = 30.0
const SHOT_LEAN: float = 3.0
const SHOT_DUCK: float = 0.35
const BLAST_LEAN: float = 5.0
const BLAST_DUCK: float = 0.5
const LEAN_MOST: float = 5.0
const DUCK_MOST: float = 0.5
## How fast a lean and a duck follow (toward more, and back: px and shares a second).
const LEAN_IN: float = 40.0
const LEAN_OUT: float = 9.0
const DUCK_IN: float = 4.0
const DUCK_OUT: float = 1.2

## Each spot's lean and duck now. Read only.
var leans: PackedVector2Array = PackedVector2Array()
var ducks: PackedFloat32Array = PackedFloat32Array()
## The rows as drawn (the spell light's as placed, moved), handed over while any spot is stirred.
var rows: PackedFloat32Array = PackedFloat32Array()
## True while any spot is not at rest (its rows are handed over each frame).
var stirred: bool = false
## The spell light's `spots_written` the arrays are for, and Feel's clock at the last step.
var _written: int = -1
var _now: float = 0.0


## Once a frame, at Feel's clock `now`: each of `light`'s spots eased toward what `stirs` asks of it,
## and their rows handed back to `light` while any is stirred.
func step(light: SpellLightScript, stirs: StirsScript, now: float) -> void:
	var delta: float = clampf(now - _now, 0.0, 0.25)
	_now = now
	if light == null or stirs == null:
		return
	var placed: PackedFloat32Array = light.spot_rows()
	var count: int = mini(light.spot_count(), placed.size() / SpellLightScript.STRIDE)
	if light.spots_written != _written or leans.size() != count:
		_written = light.spots_written
		leans.resize(count)
		leans.fill(Vector2.ZERO)
		ducks.resize(count)
		ducks.fill(0.0)
		rows.resize(count * SpellLightScript.STRIDE)
		stirred = false
	var was: bool = stirred
	stirred = false
	for at in count:
		var i: int = at * SpellLightScript.STRIDE
		var where := Vector2(placed[i + SpellLightScript.ROW_X], placed[i + SpellLightScript.ROW_Y])
		var want: Vector3 = target(stirs, where, now)
		var lean: Vector2 = leans[at]
		var to := Vector2(want.x, want.y)
		lean = lean.move_toward(to, (LEAN_IN if to.length_squared() > lean.length_squared() else LEAN_OUT) * delta)
		var duck: float = move_toward(ducks[at], want.z, (DUCK_IN if want.z > ducks[at] else DUCK_OUT) * delta)
		leans[at] = lean
		ducks[at] = duck
		if lean != Vector2.ZERO or duck > 0.0:
			stirred = true
	if stirred:
		for k in count * SpellLightScript.STRIDE:
			rows[k] = placed[k]
		for at in count:
			SpellLightScript.move_spot_row(rows, at, leans[at], ducks[at], placed[at * SpellLightScript.STRIDE + SpellLightScript.SPOT_ROW_STRENGTH])
		light.show_spots(rows)
	elif was:
		light.show_spots(PackedFloat32Array())


## What the stirs ask of a light at `where` at Feel's clock `now`: its lean (x, y: px, away from the
## shots passing within SHOT_REACH and out from a blast's wave; at most LEAN_MOST) and its duck (z).
static func target(stirs: StirsScript, where: Vector2, now: float) -> Vector3:
	var shots: Vector3 = stirs.shots_near(where, SHOT_REACH)
	var away := Vector2(shots.x, shots.y)
	var lean: Vector2 = (away.normalized() * shots.z * SHOT_LEAN if away.length_squared() > 0.0 else Vector2.ZERO)
	var push: Vector2 = stirs.blast_push(where, now)
	lean = (lean + push * BLAST_LEAN).limit_length(LEAN_MOST)
	var duck: float = minf(maxf(shots.z * SHOT_DUCK, push.length() * BLAST_DUCK), DUCK_MOST)
	return Vector3(lean.x, lean.y, duck)
