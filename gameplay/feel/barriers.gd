extends Node
## The shields' shells (the owner's pick, 2026-11-06: look D, "Mote shell"): everything a Shield
## card's charges guard is drawn as a see-through bubble of motes, a cloud on its surface that
## follows it. Two things hold charges, and both are drawn the same way, by the same rule:
##  - a barrier on an actor (a Shield on its caster, on a move, an enemy's): combat's
##    `barrier_changed` says when it is given, blocks, runs out or goes (`change`);
##  - a shot with shield charges (a shielded bolt, orbit, rune; a wall, whose shell is a capsule
##    round its row of stones): the projectile manager's guarded shots, read every frame
##    (`ProjectileManager.guarded_count`), and its `shot_blocked` for each block (`shot_blocked`).
## Its size follows what it guards (owner, 2026-11-06: a big boss's and a small shot's too): it
## stands out from the hurt circle (an actor's) or the shot's circle by a pad a share of its radius
## (`shell_radius`), and each charge is a run of motes about SPACING apart round it
## (`motes_per_charge`), so every shell is as dense. A block knocks that charge's share off, the
## ones nearest where the hit landed, and they fly away cooling through the spell's ramp, outward
## and along the bounce; the rest close the gap again (they ease to even spacing round the shell).
## The last charge bursts the whole shell outward; a barrier that runs out, or a shot that ends
## with charges left, flickers, cools and goes. Looks only.
##
## The shell's motes are placed motes (`placed_motes.gd`), rewritten every frame where they are now:
## each a `ward` mote just born there, standing still, its age (so its shade, white-hot to the base
## colour) twinkling. What flies off goes into the mote pool as ordinary moments (`Motes.burst`).
## Nothing is allocated per frame: the rows and the shells' numbers are packed arrays that grow only
## when more shells are up at once than ever before. `Motes.density` (the "Particle amount" setting) scales the motes of a
## shell and what flies off; with no pool (particles off) nothing is drawn.

const PlacedMotesScript := preload("res://gameplay/feel/placed_motes.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## The mote kind a shell is made of (content/motes/ward.tres), and what flies off it.
const KIND: StringName = &"ward"
## Pixels between a charge's motes round the shell (a wizard's, 14 px round, has 26 a charge), the
## fewest a charge has (a tiny shell), and the most a shell has (more charges block, but add none).
const SPACING: float = 3.4
const FEWEST_PER_CHARGE: int = 6
const MOST_MOTES: int = 512
## The shell stands out from what it guards by this share of its radius, within PAD_RANGE pixels
## (a wizard's hurt circle, 8 px, by 6).
const PAD_SHARE: float = 0.75
const PAD_RANGE: Vector2 = Vector2(3.0, 16.0)
## How fast the motes close a gap (1/s: about 0.4 s to close one).
const CLOSE_RATE: float = 8.0
## How fast the motes run round the shell (rad/s of its perimeter) and how far each sways about its
## place (rad, px).
const SPIN: float = 0.35
const SWAY_ANGLE: float = 0.05
const SWAY_RADIUS: float = 0.9
## A new shell swells out over SWELL seconds, its motes white-hot for HOT seconds.
const SWELL: float = 0.12
const HOT: float = 0.1
## A barrier's last FLICKER seconds flicker (on and off every FLICKER_STEP); one that ran out cools
## and goes over FADE seconds.
const FLICKER: float = 0.15
const FLICKER_STEP: float = 0.035
const FADE: float = 0.2
## A shell mote's life on the shader's clock, and the ages it twinkles between (its shade is
## floor(4 x age / life): white-hot or light while it twinkles, base and shadow as it fades).
const ROW_LIFE: float = 1.0
const TWINKLE_FROM: float = 0.12
const TWINKLE_SPAN: float = 0.35
const FADED_AGE: float = 0.9
## What flies off: speed (px/s), life (s), and how much of a knocked mote's way is the bounce.
const FLY_SPEED: Vector2 = Vector2(25.0, 70.0)
const FLY_LIFE: Vector2 = Vector2(0.35, 0.8)
const FLY_BOUNCE: float = 0.6
## Slow motes shed by a shell that faded.
const FADE_MOTES: int = 8
const FADE_SPEED: Vector2 = Vector2(6.0, 16.0)
## Shells room is made for at first (it doubles when more are up at once).
const FIRST_ROOM: int = 4
## What a shell guards: an actor (by its id) or a shot (by its slot and sequence).
const ON_ACTOR: int = 0
const ON_SHOT: int = 1

## Shells up now (for tests).
var shown: int = 0
## Rows written last frame (for tests).
var rows_written: int = 0

## The shells' motes, placed each frame.
var _placed: PlacedMotesScript = null
var _room: int = 0
## Shell `s`: what it guards (ON_*, and its actor or slot; -1 free; a shot's sequence), its motes,
## charges, radius and half its length (a capsule's: from its middle to one end's centre; zero for
## a circle), when it was given and when it runs out (Feel's clock), when it began to fade (-1 not
## fading), its ramp source and core colour, the offset its motes' even places start from, and
## where its middle was last.
var _on: PackedInt32Array = PackedInt32Array()
var _id: PackedInt32Array = PackedInt32Array()
var _seq: PackedInt32Array = PackedInt32Array()
var _count: PackedInt32Array = PackedInt32Array()
var _charges: PackedInt32Array = PackedInt32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _half: PackedVector2Array = PackedVector2Array()
var _given: PackedFloat32Array = PackedFloat32Array()
var _ends: PackedFloat32Array = PackedFloat32Array()
var _fading: PackedFloat32Array = PackedFloat32Array()
var _source: PackedInt32Array = PackedInt32Array()
var _core: PackedColorArray = PackedColorArray()
var _offset: PackedFloat32Array = PackedFloat32Array()
var _centre: PackedVector2Array = PackedVector2Array()
## The shell of each thing guarded: an actor's id, a shot's -(slot + 2).
var _shell_by: Dictionary = {}
## Mote `i` of shell `s` at `s * MOST_MOTES + i`, in order round the shell: where it is round it (0
## to TAU over the whole perimeter, off the shell's offset and turn), and a phase (its sway and
## twinkle) that is its own.
var _angle: PackedFloat32Array = PackedFloat32Array()
var _phase: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _now: float = 0.0
var _spin: float = 0.0
## The outward way at the last point `_rim` gave.
var _rim_out: Vector2 = Vector2.RIGHT


func _init(z: int = 16) -> void:
	_rng.seed = 0x5e11
	_grow(FIRST_ROOM)
	_placed = PlacedMotesScript.new(z, "Shells", FIRST_ROOM * 2 * motes_per_charge(shell_radius(8.0)))
	add_child(_placed)


## The radius of the shell round a circle (a hurt circle, a shot's) of radius `inner`.
static func shell_radius(inner: float) -> float:
	return maxf(inner, 0.0) + clampf(maxf(inner, 0.0) * PAD_SHARE, PAD_RANGE.x, PAD_RANGE.y)


## The motes a charge adds to a shell of radius `shell` and half length `half` (SPACING apart round
## it).
static func motes_per_charge(shell: float, half: float = 0.0) -> int:
	return maxi(roundi((TAU * shell + 4.0 * half) / SPACING), FEWEST_PER_CHARGE)


# --- What combat says: a barrier on an actor ---------------------------------------

## The barrier on `actor` changed (`barrier_changed`): `charges` left for `seconds`, `way` the way a
## blocked hit flew (zero for no block), `radius` the actor's hurt circle; drawn in the ramp
## `source` (`Motes.spell_source`) with the core colour `core`. `pool` throws what flies off.
func change(actor: int, charges: int, seconds: float, way: Vector2, radius: float, source: int, core: Color, pool: MotesScript) -> void:
	var s: int = _shell_by.get(actor, -1) as int
	# A hit flying `way` struck the side it came from.
	var struck: Vector2 = Vector2.INF
	if s >= 0 and way != Vector2.ZERO and _centre[s].is_finite():
		struck = _centre[s] - way.normalized() * _radius[s]
	if charges <= 0:
		if s < 0:
			return
		if way != Vector2.ZERO:
			_knock(s, _count[s], struck, way, pool)
			_free(s)
		elif _fading[s] < 0.0:
			_fading[s] = _now
		return
	if s < 0:
		s = _open(ON_ACTOR, actor, 0)
	_radius[s] = shell_radius(radius)
	_ends[s] = _now + seconds
	_set_charges(s, charges, struck, way, source, core, pool)


## Shell `s` now has `charges`: a block (`way` set, fewer charges) knocks that share off where it
## `struck`; more charges (given, grown, a recast) remake it white-hot.
func _set_charges(s: int, charges: int, struck: Vector2, way: Vector2, source: int, core: Color, pool: MotesScript) -> void:
	_source[s] = source
	_core[s] = core
	if way != Vector2.ZERO and charges < _charges[s] and _charges[s] > 0:
		var keep: int = roundi(float(_count[s]) * float(charges) / float(_charges[s]))
		_knock(s, _count[s] - keep, struck, way, pool)
	elif charges != _charges[s] or _fading[s] >= 0.0:
		_fill(s, _motes_for(charges, _radius[s], _half[s].length(), pool))
		_given[s] = _now
		_fading[s] = -1.0
	_charges[s] = charges


# --- What the projectile manager says: a shot with shield charges -----------------

## A shot's shield stopped another (`shot_blocked` naming the shielded `shot`, its charge spent):
## its shell loses that charge's share where the blocked shot was (`at`), all of it on the last.
func shot_blocked(shot: int, at: Vector2, projectiles: ProjectileManagerScript, pool: MotesScript) -> void:
	if shot < 0 or projectiles == null:
		return
	var s: int = _shell_by.get(-(shot + 2), -1) as int
	if s < 0 or _seq[s] != projectiles.get_seq_of(shot):
		return
	var left: int = projectiles.get_shield_of(shot)
	var way: Vector2 = (_centre[s] - at).normalized() if _centre[s].is_finite() and at.is_finite() else Vector2.ZERO
	if way == Vector2.ZERO:
		way = Vector2.DOWN
	if left <= 0:
		_knock(s, _count[s], at, way, pool)
		_free(s)
		return
	_set_charges(s, left, at, way, _source[s], _core[s], pool)


## The guarded shots now: a shell for each shot with shield charges that has none yet (in its
## caster's ramp and its own colour and looks), its charges taken up when more were given.
func _take_shots(projectiles: ProjectileManagerScript, table: ActorsScript, pool: MotesScript) -> void:
	for n in projectiles.guarded_count():
		var slot: int = projectiles.guarded_slot(n)
		var charges: int = projectiles.get_shield_of(slot)
		if charges <= 0:
			continue
		var seq: int = projectiles.get_seq_of(slot)
		var s: int = _shell_by.get(-(slot + 2), -1) as int
		if s >= 0 and _seq[s] != seq:
			# The slot was another shot's: that shell fades where it was.
			_let_go(s)
			s = -1
		if s >= 0 and charges <= _charges[s]:
			continue
		if s < 0:
			s = _open(ON_SHOT, slot, seq)
			_centre[s] = projectiles.get_position_of(slot)
		_radius[s] = shell_radius(projectiles.get_radius_of(slot))
		_half[s] = projectiles.get_solid_half_of(slot)
		var actor: int = projectiles.get_actor_of(slot)
		var ramp: int = table.ramp_of(actor) if table != null else ActorsScript.NONE
		_set_charges(s, charges, Vector2.INF, Vector2.ZERO, MotesScript.spell_source(ramp, projectiles.get_look_of(slot)), projectiles.get_core_of(slot), pool)


## Shell `s` guards nothing any more: it fades where it is.
func _let_go(s: int) -> void:
	_shell_by.erase(-(_id[s] + 2) if _on[s] == ON_SHOT else _id[s])
	_id[s] = -1
	if _fading[s] < 0.0:
		_fading[s] = _now


# --- Shells: filling and knocking off ------------------------------------------

## The motes a shell of `charges`, radius `shell` and half length `half` has, with the pool's density.
func _motes_for(charges: int, shell: float, half: float, pool: MotesScript) -> int:
	var density: float = pool.density if pool != null else 1.0
	return clampi(roundi(float(mini(charges * motes_per_charge(shell, half), MOST_MOTES)) * density), 0, MOST_MOTES)


## Shell `s` with `count` motes evenly round it, each with a phase of its own.
func _fill(s: int, count: int) -> void:
	var first: int = s * MOST_MOTES
	for i in count:
		_angle[first + i] = TAU * float(i) / float(count)
		_phase[first + i] = _rng.randf() * TAU
	_count[s] = count
	_offset[s] = 0.0


## Knock `knocked` motes of shell `s` off, the run nearest `struck` (where a hit flying `way` met
## it; INF: anywhere), into the pool; the rest keep their order and close the gap.
func _knock(s: int, knocked: int, struck: Vector2, way: Vector2, pool: MotesScript) -> void:
	var count: int = _count[s]
	knocked = clampi(knocked, 0, count)
	if knocked == 0:
		return
	var first: int = s * MOST_MOTES
	var centre: Vector2 = _centre[s]
	var placed: bool = centre.is_finite()
	if not struck.is_finite() and placed:
		struck = centre - way.normalized() * _radius[s]
	# The mote nearest where it struck, then the run of `knocked` centred on it (round the shell).
	var nearest: int = 0
	if placed and struck.is_finite():
		var best: float = INF
		for i in count:
			var d: float = _rim(s, _angle[first + i] + _offset[s] + _spin, 0.0).distance_squared_to(struck)
			if d < best:
				best = d
				nearest = i
	var start: int = posmod(nearest - knocked / 2, count)
	var thrown: bool = pool != null and placed
	var kind: int = pool.kind_index(KIND) if thrown else -1
	var unit: Vector2 = way.normalized() if way != Vector2.ZERO else Vector2.DOWN
	var reach: float = 2.0 * (_radius[s] + _half[s].length())
	for n in knocked:
		var i: int = (start + n) % count
		if thrown and kind >= 0:
			var p: Vector2 = _rim(s, _angle[first + i] + _offset[s] + _spin, 0.0)
			var out: Vector2 = _rim_out
			var bounce: Vector2 = unit - 2.0 * unit.dot(out) * out
			var near: float = 1.0 - clampf(p.distance_to(struck) / reach, 0.0, 1.0) if struck.is_finite() else 0.0
			var dir: Vector2 = (out * 0.7 + bounce * FLY_BOUNCE * near).normalized()
			var speed: float = _rng.randf_range(FLY_SPEED.x, FLY_SPEED.y)
			var life: float = _rng.randf_range(FLY_LIFE.x, FLY_LIFE.y)
			pool.burst(kind, p, dir, 1, Vector2(speed, speed), 0.0, Vector2.ZERO, Vector2(life, life), _source[s], _core[s])
		# Marked gone; packed below.
		_phase[first + i] = -1.0
	var kept: int = 0
	for i in count:
		if _phase[first + i] < 0.0:
			continue
		_angle[first + kept] = _angle[first + i]
		_phase[first + kept] = _phase[first + i]
		kept += 1
	_count[s] = kept
	# The even places start where the kept motes are on the whole (their mean place off their even
	# places), so the gap closes from both sides and the shell does not turn.
	if kept > 0:
		var sum: Vector2 = Vector2.ZERO
		for i in kept:
			sum += Vector2.from_angle(_angle[first + i] - TAU * float(i) / float(kept))
		var mean: float = sum.angle() if sum != Vector2.ZERO else 0.0
		_offset[s] += mean
		for i in kept:
			_angle[first + i] -= mean


## The point `u` round shell `s` (0 to TAU over its whole perimeter), `out` pixels further out;
## leaves the outward way there in `_rim_out`. A circle, or a capsule round its row: from the end at
## `+half`, along one side, round the other end and back along the other side.
func _rim(s: int, u: float, out: float) -> Vector2:
	var centre: Vector2 = _centre[s]
	var r: float = _radius[s] + out
	var half: Vector2 = _half[s]
	var h: float = half.length()
	if h <= 0.0:
		_rim_out = Vector2.from_angle(u)
		return centre + _rim_out * r
	var along: Vector2 = half / h
	var side: Vector2 = along.orthogonal()
	var cap: float = PI * _radius[s]
	var length: float = 2.0 * cap + 4.0 * h
	var d: float = fposmod(u, TAU) / TAU * length
	if d < cap:
		var a: float = -PI * 0.5 + d / _radius[s]
		_rim_out = along * cos(a) + side * sin(a)
		return centre + half + _rim_out * r
	d -= cap
	if d < 2.0 * h:
		_rim_out = side
		return centre + half - along * d + side * r
	d -= 2.0 * h
	if d < cap:
		var b: float = PI * 0.5 + d / _radius[s]
		_rim_out = along * cos(b) + side * sin(b)
		return centre - half + _rim_out * r
	d -= cap
	_rim_out = -side
	return centre - half + along * d - side * r


# --- Every frame --------------------------------------------------------------

## Once a frame at Feel's clock `now`: the guarded shots taken up, every shell where what it guards
## is now (an actor's body: the actor table's node, else the projectile manager's anchor; a shot
## where it flies; a shell whose actor is gone goes quietly, one whose shot ended fades where it
## was), its motes eased toward even places, written into the batch drawn with `pool`'s material.
func step(now: float, pool: MotesScript, table: ActorsScript, projectiles: ProjectileManagerScript) -> void:
	var delta: float = clampf(now - _now, 0.0, 0.1)
	_now = now
	_spin = fmod(_spin + SPIN * delta, TAU)
	rows_written = 0
	shown = 0
	if not _placed.begin(pool, now):
		return
	if projectiles != null:
		_take_shots(projectiles, table, pool)
	var kind: int = pool.kind_index(KIND)
	var close: float = 1.0 - exp(-CLOSE_RATE * delta)
	var needed: int = 0
	for s in _on.size():
		if _on[s] >= 0:
			needed += _count[s]
	_placed.hold(needed)
	for s in _on.size():
		if _on[s] < 0:
			continue
		if not _follow(s, table, projectiles):
			_free(s)
			continue
		if _fading[s] >= 0.0 and now - _fading[s] >= FADE:
			_shed(s, pool, kind)
			_free(s)
			continue
		shown += 1
		if kind >= 0:
			_write(s, close, kind)
	rows_written = _placed.rows
	_placed.finish()


## Shell `s` moved to where what it guards is now. False when it should go quietly (an actor gone).
func _follow(s: int, table: ActorsScript, projectiles: ProjectileManagerScript) -> bool:
	if _id[s] < 0:
		# Let go: it stays where it was while it fades.
		return _centre[s].is_finite()
	if _on[s] == ON_SHOT:
		if projectiles == null or not projectiles.is_alive(_id[s]) or projectiles.get_seq_of(_id[s]) != _seq[s] or projectiles.get_shield_of(_id[s]) <= 0:
			# Its shot ended (or lost its shield some other way): the shell fades where it was.
			_let_go(s)
			return _centre[s].is_finite()
		_centre[s] = projectiles.get_position_of(_id[s])
		_radius[s] = shell_radius(projectiles.get_radius_of(_id[s]))
		_half[s] = projectiles.get_solid_half_of(_id[s])
		return true
	var centre: Vector2 = _centre_of(_id[s], table, projectiles)
	if not centre.is_finite():
		return false
	_centre[s] = centre
	return true


## Shell `s`'s motes, placed.
func _write(s: int, close: float, kind: int) -> void:
	var first: int = s * MOST_MOTES
	var count: int = _count[s]
	if count == 0:
		return
	var age: float = _now - _given[s]
	var swell: float = clampf(age / SWELL, 0.0, 1.0)
	var grow: float = 0.45 + 0.55 * swell + 0.12 * sin(swell * PI)
	var fade: float = -1.0
	if _fading[s] >= 0.0:
		fade = (_now - _fading[s]) / FADE
	var left: float = _ends[s] - _now
	# Flickering (its last moments, or fading): every other FLICKER_STEP it is not drawn.
	var flicker: bool = fade >= 0.0 or (left < FLICKER and left > 0.0)
	if flicker and posmod(floori(_now / FLICKER_STEP), 2) == 1:
		_ease(s, close)
		return
	var radius: float = _radius[s]
	var half: Vector2 = _half[s]
	# Swelling: the shell drawn smaller, then back to its size.
	_radius[s] = radius * grow
	_half[s] = half * minf(grow, 1.0)
	var source: int = _source[s]
	var core: Color = _core[s]
	var step_angle: float = TAU / float(count)
	for i in count:
		var m: int = first + i
		# Toward its even place.
		_angle[m] += (step_angle * float(i) - _angle[m]) * close
		var phase: float = _phase[m]
		var p: Vector2 = _rim(s, _angle[m] + _offset[s] + _spin + sin(_now * 1.3 + phase) * SWAY_ANGLE, sin(_now * 2.3 + phase) * SWAY_RADIUS)
		var shade_age: float = TWINKLE_FROM + TWINKLE_SPAN * (0.5 + 0.5 * sin(_now * 5.0 + phase * 3.0))
		if age < HOT:
			shade_age = 0.0
		if fade >= 0.0:
			shade_age = lerpf(shade_age, FADED_AGE, clampf(fade, 0.0, 1.0))
		_placed.put(p, kind, source, core, shade_age, phase / TAU, ROW_LIFE)
	_radius[s] = radius
	_half[s] = half


## Shell `s`'s motes eased toward their even places, not drawn (a flicker's off frame).
func _ease(s: int, close: float) -> void:
	var first: int = s * MOST_MOTES
	var count: int = _count[s]
	if count == 0:
		return
	var step_angle: float = TAU / float(count)
	for i in count:
		_angle[first + i] += (step_angle * float(i) - _angle[first + i]) * close


## A faded shell's last few motes, drifting off slowly.
func _shed(s: int, pool: MotesScript, kind: int) -> void:
	if kind < 0 or not _centre[s].is_finite():
		return
	var count: int = roundi(float(FADE_MOTES) * pool.density)
	for n in count:
		var p: Vector2 = _rim(s, _rng.randf() * TAU, 0.0)
		var speed: float = _rng.randf_range(FADE_SPEED.x, FADE_SPEED.y)
		pool.burst(kind, p, _rim_out, 1, Vector2(speed, speed), 0.0, Vector2.ZERO, FLY_LIFE, _source[s], _core[s])


## Where `actor`'s body is: its node's place (an Actor's raised by its body offset, the middle of its
## hurt circle), else its anchor; INF when it has neither.
func _centre_of(actor: int, table: ActorsScript, projectiles: ProjectileManagerScript) -> Vector2:
	if table != null:
		var node: Node = table.node_of(actor)
		if node is Actor:
			var body: Actor = node as Actor
			return body.global_position + body.body_offset
		if node is Node2D:
			return (node as Node2D).global_position
	if projectiles != null:
		return projectiles.get_anchor(actor)
	return Vector2.INF


## Row `row` of the shells' motes as placed last frame (for tests; Motes.DRAW_STRIDE floats).
func row_data(row: int) -> PackedFloat32Array:
	return _placed.row_data(row)


## How many motes the shell of `actor` has now (0 for none; for tests).
func motes_of(actor: int) -> int:
	var s: int = _shell_by.get(actor, -1) as int
	return _count[s] if s >= 0 else 0


## How many motes the shell of the shot in `slot` has now (0 for none; for tests).
func motes_of_shot(slot: int) -> int:
	var s: int = _shell_by.get(-(slot + 2), -1) as int
	return _count[s] if s >= 0 else 0


# --- Shells -------------------------------------------------------------------

## A new shell for what it guards (`on`, `id`, a shot's `seq`), with nothing in it yet.
func _open(on: int, id: int, seq: int) -> int:
	var s: int = -1
	for free in _on.size():
		if _on[free] < 0:
			s = free
			break
	if s < 0:
		s = _room
		_grow(_room * 2)
	_on[s] = on
	_id[s] = id
	_seq[s] = seq
	_shell_by[-(id + 2) if on == ON_SHOT else id] = s
	_given[s] = _now
	_ends[s] = INF
	_fading[s] = -1.0
	_centre[s] = Vector2.INF
	_half[s] = Vector2.ZERO
	_charges[s] = 0
	_count[s] = 0
	_offset[s] = 0.0
	return s


func _free(s: int) -> void:
	if _id[s] >= 0:
		_shell_by.erase(-(_id[s] + 2) if _on[s] == ON_SHOT else _id[s])
	_on[s] = -1
	_id[s] = -1
	_count[s] = 0
	_charges[s] = 0


## Room for `room` shells (only ever grows).
func _grow(room: int) -> void:
	var was: int = _room
	_room = room
	_on.resize(room)
	_id.resize(room)
	_seq.resize(room)
	for s in range(was, room):
		_on[s] = -1
		_id[s] = -1
	_count.resize(room)
	_charges.resize(room)
	_source.resize(room)
	_radius.resize(room)
	_half.resize(room)
	_given.resize(room)
	_ends.resize(room)
	_fading.resize(room)
	_offset.resize(room)
	_core.resize(room)
	_centre.resize(room)
	_angle.resize(room * MOST_MOTES)
	_phase.resize(room * MOST_MOTES)

