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
##
## Packed arrays sized ACTORS, nothing allocated after start. An id outside the table or not
## open is safe everywhere: the questions answer NONE (`budget_of` SHARED, `node_of` null) and
## the changes do nothing. The bodies open their own ids (wizards, enemies that cast, the actor
## kit's actors); every system keys its arrays by them (actors G3).

## How many actors there can be at once: four seats, 256 enemies, room to grow.
const ACTORS: int = 512
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
## No id below this is free: where `open` starts looking.
var _lowest_free: int = 0
var _count: int = 0


func _init() -> void:
	_open.resize(ACTORS)
	_team.resize(ACTORS)
	_ramp.resize(ACTORS)
	_seat.resize(ACTORS)
	_node.resize(ACTORS)
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
	_lowest_free = id + 1
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
	_count -= 1
	if id < _lowest_free:
		_lowest_free = id


## True while `id` is an open actor.
func is_open(id: int) -> bool:
	return id >= 0 and id < ACTORS and _open[id] != 0


## Actors open now.
func open_count() -> int:
	return _count


## Whom it aims at: TEAM_WIZARDS, TEAM_ENEMIES, ...; NONE for no actor.
func team_of(id: int) -> int:
	return _team[id] if is_open(id) else NONE


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


## The node of an actor (null to forget it). Only its instance id is kept.
func set_node(id: int, node: Node) -> void:
	if is_open(id):
		_node[id] = node.get_instance_id() if node != null else 0


## The actor's node, or null: none set, the actor closed, or the node freed.
func node_of(id: int) -> Node:
	if not is_open(id) or _node[id] == 0:
		return null
	return instance_from_id(_node[id]) as Node


## Every actor closed and every seat free (a new run, and tests).
func clear() -> void:
	_open.fill(0)
	_team.fill(NONE)
	_ramp.fill(NONE)
	_seat.fill(NONE)
	_node.fill(0)
	_seat_actor.fill(NONE)
	_home_seat.fill(NONE)
	_seat_home.fill(NONE)
	_lowest_free = 0
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
