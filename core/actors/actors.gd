extends Node
## The actor table (autoload `Actors`; actors G2, docs/milestones/M2-actors.md, "Core: the actor
## table and one caster number"): the one place an actor's id, team, look and seat are known, so
## core never infers them from a number. An actor is anything that acts: a wizard, an enemy. Its
## id (0 to ACTORS - 1) is the row every system keeps it in.
##
## - `open(team, ramp, seat)` gives a new actor the lowest free id (-1 when every id is taken),
##   `close(id)` frees it. The lowest free id first, so a run hands out the same ids every time.
## - `team_of` says whom it aims at (teams are for aim only, never for whether a hit lands),
##   `ramp_of` which colour ramp draws its spells (0-3 the hat colours, `RAMP_ENEMY` Blight),
##   `seat_of` which human drives it (0-3, or NONE).
## - `set_driver(id, team, seat)` is a controller change: a possession, or a controller going
##   home. A seat drives one actor at a time: giving a seat to an actor takes it from the actor
##   that held it, which is left with no seat (the newer driver wins). `actor_of_seat(seat)` is
##   the actor a seat drives now.
## - `set_home(id, seat)` names the seat whose own body an actor is (a wizard, from its home
##   controller), and `home_of_seat(seat)` finds it while the seat drives another actor or
##   another controller drives it (possess, G9): the HUD shows the home body (owner, 2026-10-28).
## - `budget_of(id)` is whose share of the shared limits it spends: its seat's when a seat drives
##   it, else `SHARED`, the one budget every actor no seat drives shares.
## - `set_node(id, node)` and `node_of(id)` find the actor's node; only its instance id is kept,
##   so a freed node gives null.
## - `key_of(id)` is the actor's identity (online-ready N5): its id and its birth, the number of
##   opens in this run when it was opened, so an id handed out again is another identity, as a new
##   body is. It is what the simulation keeps for "that body" (a shot's homing target, what it hit,
##   a chain's last body, an AI's target), never an instance id, which differs between machines
##   and runs. The births count from 0 at each run's start (`begin_run`).
##
## Packed arrays sized ACTORS, nothing allocated after start. An id outside the table or not
## open is safe everywhere: the questions answer NONE (`budget_of` SHARED, `node_of` null) and
## the changes do nothing. The bodies open their own ids (wizards, enemies that cast, the actor
## kit's actors); every system keys its arrays by them (actors G3).

## How many actors there can be at once: four seats and a crowd of 500+ enemies with room to
## spare (2026-10-30; kept by the owner, 2026-11-09). It is also the caster field of a spell
## tag (`SpellTag.CASTER_MASK` + 1, 10 bits). Every system sizes per-actor arrays by it; the
## largest is the spell runtime's per staff (ACTORS x 4 rows of a few arrays), a few hundred KB
## in all, allocated once at start.
const ACTORS: int = 1024
## Seats: the humans, 0 to 3.
const SEATS: int = 4
## The budget of every actor no seat drives (`budget_of`); 0-3 are the seats' own.
const SHARED: int = SEATS
## No actor, no seat, no team: the world.
const NONE: int = -1
## The two teams so far; more are possible later.
const TEAM_WIZARDS: int = 0
const TEAM_ENEMIES: int = 1
## The enemy ramp (Blight); 0-3 are the four hat colours.
const RAMP_ENEMY: int = 4

## Not state: services, caches and scratch, set up again (core/sim/README.md); the node of each id,
## kept by its instance id: a lookup from the id (`node_of`), set again by each body as it opens
## (equality only, never an identity: N5).
const DERIVED: Array[StringName] = [&"_node"]

var _open: PackedByteArray = PackedByteArray()
var _team: PackedInt32Array = PackedInt32Array()
var _ramp: PackedInt32Array = PackedInt32Array()
var _seat: PackedInt32Array = PackedInt32Array()
## The node's instance id, 0 for none.
var _node: PackedInt64Array = PackedInt64Array()
## The actor each seat drives, or NONE.
var _seat_actor: PackedInt32Array = PackedInt32Array()
## Per actor: the seat whose own body it is, or NONE; per seat: its own body, or NONE.
var _home_seat: PackedInt32Array = PackedInt32Array()
var _seat_home: PackedInt32Array = PackedInt32Array()
## Seconds each actor is still held by a local stop (hit-stop in co-op, melee I7), and how many
## actors are held now, so a step with none held costs one comparison.
var _held: PackedFloat32Array = PackedFloat32Array()
var held_count: int = 0
## Each open id's birth (`key_of`): `_births` when it was opened; 0 for an id not open.
var _birth: PackedInt64Array = PackedInt64Array()
## How many ids this run has opened: the next birth less one.
var _births: int = 0
## Seconds of each actor's own steps until a plain hold (`hold` with `plain`) takes it again: its
## hold and its rest after it (online-ready N4; Feel kept it in real time before), so a stream of
## hits cannot keep one body held for ever. Spent by its steps, as its hold is (`spend_hold`), so
## it follows the game's time whoever steps the actor. And how many actors rest now.
var _rest: PackedFloat32Array = PackedFloat32Array()
var resting_count: int = 0
## No id below this is free: where `open` starts looking.
var _lowest_free: int = 0
var _count: int = 0
## One past the highest open id (0 when none is open): where `open_ids` stops looking.
var _high: int = 0


func _init() -> void:
	_open.resize(ACTORS)
	_team.resize(ACTORS)
	_ramp.resize(ACTORS)
	_seat.resize(ACTORS)
	_node.resize(ACTORS)
	_birth.resize(ACTORS)
	_held.resize(ACTORS)
	_rest.resize(ACTORS)
	_seat_actor.resize(SEATS)
	_home_seat.resize(ACTORS)
	_seat_home.resize(SEATS)
	clear()


## Opens an actor and returns its id, the lowest free one, or NONE when every id is taken. A
## `seat` of 0-3 makes a seat drive it (taken from the actor that held it); anything else is no
## seat.
func open(team: int, ramp: int, seat: int = NONE) -> int:
	var id: int = _lowest_free
	while id < ACTORS and _open[id] != 0:
		id += 1
	if id >= ACTORS:
		_lowest_free = ACTORS
		return NONE
	_open[id] = 1
	_team[id] = team
	_ramp[id] = ramp
	_seat[id] = NONE
	_home_seat[id] = NONE
	_node[id] = 0
	_births += 1
	_birth[id] = _births
	_release_hold(id)
	_lowest_free = id + 1
	_high = maxi(_high, id + 1)
	_count += 1
	_take_seat(id, seat)
	return id


## Frees an actor's id (its seat too): the next `open` may hand it out again.
func close(id: int) -> void:
	if not is_open(id):
		return
	_take_seat(id, NONE)
	set_home(id, NONE)
	_open[id] = 0
	_team[id] = NONE
	_ramp[id] = NONE
	_node[id] = 0
	_birth[id] = 0
	_release_hold(id)
	_count -= 1
	if id < _lowest_free:
		_lowest_free = id
	while _high > 0 and _open[_high - 1] == 0:
		_high -= 1


## True while `id` is an open actor.
func is_open(id: int) -> bool:
	return id >= 0 and id < ACTORS and _open[id] != 0


## Actors open now.
func open_count() -> int:
	return _count


## The open ids, lowest first, written into `out` (grown when short, never shrunk, so a caller
## reuses it); returns how many. The tick steps the bodies in this order (core/sim/tick.gd).
func open_ids(out: PackedInt32Array) -> int:
	if out.size() < _count:
		out.resize(ACTORS)
	var n: int = 0
	for id in _high:
		if _open[id] != 0:
			out[n] = id
			n += 1
	return n


## Whom it aims at: TEAM_WIZARDS, TEAM_ENEMIES, ...; NONE for no actor.
func team_of(id: int) -> int:
	return _team[id] if is_open(id) else NONE


## Every actor's team by id (ACTORS of them), NONE for an id not open: `team_of` of every id at
## once, for a system that reads the teams of hundreds of actors each step (the projectile target
## grid and Combat's step, 2026-10-31: a call per actor cost more than the rest of their work).
## It is the table's own array, not a copy (packed arrays are passed by reference): it always shows
## the teams as they are, and it is read only: never write to it.
func teams() -> PackedInt32Array:
	return _team


## The colour ramp its spells are drawn in (0-3 the hat colours, RAMP_ENEMY); NONE for no actor.
func ramp_of(id: int) -> int:
	return _ramp[id] if is_open(id) else NONE


## The seat (0-3) that drives it, or NONE.
func seat_of(id: int) -> int:
	return _seat[id] if is_open(id) else NONE


## A controller change: the team and seat of whoever drives the actor now (a seat of NONE for an
## AI or no controller). The seat is taken from any actor that held it.
func set_driver(id: int, team: int, seat: int) -> void:
	if not is_open(id):
		return
	_team[id] = team
	_take_seat(id, seat)


## The actor a seat drives now, or NONE.
func actor_of_seat(seat: int) -> int:
	return _seat_actor[seat] if seat >= 0 and seat < SEATS else NONE


## `id` is seat `seat`'s own body (NONE, or anything outside 0-3: no seat's). A seat has one
## home body: naming a new one takes it from the old.
func set_home(id: int, seat: int) -> void:
	if not is_open(id):
		return
	if seat < 0 or seat >= SEATS:
		seat = NONE
	var old: int = _home_seat[id]
	if old == seat:
		return
	if old != NONE and _seat_home[old] == id:
		_seat_home[old] = NONE
	if seat != NONE:
		var holder: int = _seat_home[seat]
		if holder != NONE:
			_home_seat[holder] = NONE
		_seat_home[seat] = id
	_home_seat[id] = seat


## A seat's own body (its wizard, also while the seat drives another actor or another controller
## drives it), or NONE.
func home_of_seat(seat: int) -> int:
	return _seat_home[seat] if seat >= 0 and seat < SEATS else NONE


## Whose share of the shared limits it spends: its seat (0-3) while a seat drives it, else SHARED.
func budget_of(id: int) -> int:
	var seat: int = seat_of(id)
	return seat if seat != NONE else SHARED


## The identity of the open actor `id` (online-ready N5): its id and its birth in one number, never
## 0, the same on every machine and in every run that opens the same ids in the same order; an id
## opened again is another key. 0 for an id not open.
func key_of(id: int) -> int:
	return _birth[id] * ACTORS + id if is_open(id) else 0


## The open actor whose key is `key` (`key_of`), or NONE: closed since, or never.
func id_of_key(key: int) -> int:
	if key <= 0:
		return NONE
	var id: int = key % ACTORS
	return id if key_of(id) == key else NONE


## A run starts (`Tick.begin_run`, after every area that frees bodies): the births count from 0
## again, so a run's keys are the same whatever ran before it in the game. Every body of the last
## run has closed its id by now (it left the tree, or its area's `begin_run` freed it); an id still
## open would keep a key of the last run's count, so it is named.
func begin_run() -> void:
	if _count > 0:
		var open: PackedStringArray = PackedStringArray()
		for id in _high:
			if _open[id] != 0:
				var node: Node = node_of(id)
				open.append("%d (%s)" % [id, node.get_path() if node != null and node.is_inside_tree() else "no node"])
		push_error("Actors.begin_run: %d actors are still open (%s); the last run's bodies must close their ids before a run starts" % [_count, ", ".join(open)])
		return
	_births = 0
	_birth.fill(0)


## The node of an actor (null to forget it). Only its instance id is kept.
func set_node(id: int, node: Node) -> void:
	if is_open(id):
		_node[id] = node.get_instance_id() if node != null else 0


## The actor's node, or null: none set, the actor closed, or the node freed.
func node_of(id: int) -> Node:
	if not is_open(id) or _node[id] == 0:
		return null
	return instance_from_id(_node[id]) as Node


## Holds the actor `id` where it stands for `seconds` (a local stop: its body does nothing
## meanwhile while the rest of the game runs on). The longer of two stops stands. After it the
## actor rests for `rest` seconds more of its own steps, and a `plain` hold (a plain hit's) does
## not take it while it rests; any other hold (a kill, a reaction, a cue's) always does. Returns
## false for an actor that is not open, or a plain hold refused. An actor that rests or is held is
## stepped through `spend_hold` (`held_count` or `resting_count` above 0).
func hold(id: int, seconds: float, rest: float = 0.0, plain: bool = false) -> bool:
	if not is_open(id) or seconds <= 0.0:
		return false
	if plain and _rest[id] > 0.0:
		return false
	if _rest[id] <= 0.0:
		resting_count += 1
	_rest[id] = maxf(_rest[id], seconds + rest)
	if _held[id] <= 0.0:
		held_count += 1
	_held[id] = maxf(_held[id], seconds)
	return true


## Seconds left of the local stop on `id` (0 when it is not held).
func held_left(id: int) -> float:
	return _held[id] if id >= 0 and id < ACTORS else 0.0


## Spends the actor's local stop on a step of `delta` seconds and returns how many seconds of the
## step it still runs: `delta` when it is not held, 0 while the stop covers the whole step (the
## actor's own step calls it, and does nothing then).
func spend_hold(id: int, delta: float) -> float:
	if id < 0 or id >= ACTORS:
		return delta
	if _rest[id] > 0.0:
		_spend_rest(id, delta)
	if _held[id] <= 0.0:
		return delta
	var held: float = _held[id]
	if held > delta:
		_held[id] = held - delta
		return 0.0
	_held[id] = 0.0
	held_count -= 1
	return delta - held


func _spend_rest(id: int, delta: float) -> void:
	_rest[id] -= delta
	if _rest[id] <= 0.0:
		_rest[id] = 0.0
		resting_count -= 1


func _release_hold(id: int) -> void:
	if _rest[id] > 0.0:
		_rest[id] = 0.0
		resting_count -= 1
	if _held[id] > 0.0:
		_held[id] = 0.0
		held_count -= 1


## Every actor closed and every seat free (a new run, and tests).
func clear() -> void:
	_open.fill(0)
	_team.fill(NONE)
	_ramp.fill(NONE)
	_seat.fill(NONE)
	_node.fill(0)
	_birth.fill(0)
	_births = 0
	_held.fill(0.0)
	_rest.fill(0.0)
	resting_count = 0
	held_count = 0
	_seat_actor.fill(NONE)
	_home_seat.fill(NONE)
	_seat_home.fill(NONE)
	_lowest_free = 0
	_high = 0
	_count = 0


## Seats `id` at `seat` (NONE, or anything outside 0-3, unseats it); whoever held that seat
## loses it.
func _take_seat(id: int, seat: int) -> void:
	if seat < 0 or seat >= SEATS:
		seat = NONE
	var old: int = _seat[id]
	if old == seat:
		return
	if old != NONE:
		_seat_actor[old] = NONE
	if seat != NONE:
		var holder: int = _seat_actor[seat]
		if holder != NONE:
			_seat[holder] = NONE
		_seat_actor[seat] = id
	_seat[id] = seat
