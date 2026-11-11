class_name Reactions
extends ActorComponent
## A prop's reactions and states (props W6, docs/milestones/props.md, "Triggers"): the component
## that makes a body of `PropBase` data react. It holds which of the prop's states the body is in
## (`state`, an index into `prop.states`, the first to start), and fires that state's reactions
## (`PropReaction`) on the moments it hears, all of them its own body's:
##
## - a hit (`Actor.damaged`: `element_hit`), a status put on it (`Actor.status_gained`: `status`), a
##   reaction between statuses on it (`Actor.reacted`: `reaction`), its health falling below a share
##   (`Health.changed`: `health_below`) or running out (`Health.depleted`: `death`);
## - one of its staffs' casts leaving (`Events.cast_left` for its caster number: `cast`), heard only
##   by a prop with a `cast` reaction;
## - a state entered (`entered`).
##
## One hit is up to three moments, in the order its health tells them: `health_below`, `death`, then
## the hit itself (`element_hit`), each read against the state it finds.
##
## **The rule:** on a moment every reaction of the current state that matches fires, in the order
## listed (`cast`: the prop casts that staff, as itself, along its aim); the first of them that names
## a `then` sets the next state, once, after they all fired. A moment inside another (a reaction's
## cast whose blast sets off this prop again) is read against the state then; once it moved the state
## on, the outer moment's reactions stop and its `then` is dropped: that state was left.
##
## **Entering a state:** the casts that state's predecessor wound up and this moment did not cast
## leave no more (a lit barrel shot apart blows now, and its fuse no longer does); its hurt shape and
## footprint follow `hittable` and `blocks`; `prop_state_changed` goes on the bus and `entered` here;
## then its `entered` reactions fire; and a `gone` state, if still the one it is in, frees the body.
## The state it starts in is not entered.
##
## **Death is the prop's own:** it takes the body's 0 health (`Actor.downable`), so Combat neither
## frees it nor tells its death. Its `death` reactions run, and a possession of it ends. It is freed
## only by a `gone` state; without one its health stays empty and it stands.
##
## The state is the body's state (hashed, in snapshots); a fresh prop in its first state rests (props
## W2, `at_rest`).

## The state the body is in now, entered by a reaction (not the one it starts in).
signal entered(state_id: StringName)

## Moments within moments this deep are not fired (a loop in the data, which `PropBase.problems`
## names).
const MAX_DEPTH: int = 16

## Not state: how deep in moments the component is and how many states it entered, only read within
## one moment (scratch).
const DERIVED: Array[StringName] = [&"_depth", &"_entries"]

## The prop's data (set before the body is ready: `PropBody.make`).
@export var prop: PropBase = null
## The index of the state it is in, in `prop.states` (0: the one it starts in).
var state: int = 0
## Its health as last told (`Health.changed`), for `health_below`'s crossing; -1 before it is set up.
var _health_seen: float = -1.0
var _depth: int = 0
var _entries: int = 0


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	if prop == null:
		# No data, no reactions: the body lives and dies as any.
		return
	# Its 0 health is its death reactions', not Combat's (see the class doc).
	actor.downable = true
	actor.damaged.connect(_on_damaged)
	actor.status_gained.connect(_on_status_gained)
	actor.reacted.connect(_on_reacted)
	if actor.health != null:
		if _health_seen < 0.0:
			_health_seen = actor.health.health
		actor.health.changed.connect(_on_health_changed)
		actor.health.depleted.connect(_on_depleted)
	# Its body as its state makes it, before the hurt shape and footprint are attached.
	_shape_body(false)


func attach() -> void:
	if _hears_casts() and not actor.events.cast_left.is_connected(_on_cast_left):
		actor.events.cast_left.connect(_on_cast_left)


func detach() -> void:
	if actor.events != null and is_instance_valid(actor.events) and actor.events.cast_left.is_connected(_on_cast_left):
		actor.events.cast_left.disconnect(_on_cast_left)


## In the state it starts in, its health as told (props W2: a fresh prop rests).
func at_rest() -> bool:
	return state == 0 and (actor.health == null or _health_seen == actor.health.health)


## The state it is in now (null with no data).
func current() -> PropState:
	if prop == null or state < 0 or state >= prop.states.size():
		return null
	return prop.states[state]


## The id of the state it is in now (&"" with no data).
func state_id() -> StringName:
	var now: PropState = current()
	return now.state_id if now != null else &""


func _hears_casts() -> bool:
	return actor.events != null and prop != null and prop.listens(PropReaction.When.CAST)


func _on_damaged(_by: int, amount: float, element: StringName) -> void:
	_moment(PropReaction.When.ELEMENT_HIT, element, amount)


func _on_status_gained(_by: int, status: StringName) -> void:
	_moment(PropReaction.When.STATUS, status, 0.0)


func _on_reacted(_by: int, reaction: StringName) -> void:
	_moment(PropReaction.When.REACTION, reaction, 0.0)


func _on_health_changed(health: float, max_health: float) -> void:
	var before: float = _health_seen
	_health_seen = health
	if health >= before or max_health <= 0.0:
		return
	_moment(PropReaction.When.HEALTH_BELOW, &"", health / max_health, before / max_health)


func _on_depleted(_killer: int) -> void:
	if actor.possessed_by != null:
		# Its death ends the possession, as a body's does (the seat goes home).
		actor.possessed_by.end()
	_moment(PropReaction.When.DEATH, &"", 0.0)


func _on_cast_left(caster: int, staff: int) -> void:
	if caster == actor.caster_number() and caster >= 0:
		_moment(PropReaction.When.CAST, &"", float(staff + 1))


## A moment of `kind` (see the class doc): every reaction of the state it is in that hears it fires,
## then the first `then` among them is entered.
func _moment(kind: PropReaction.When, name: StringName, amount: float, before: float = 1.0) -> void:
	var now: PropState = current()
	if now == null or actor.is_dying() or actor.is_leaving():
		return
	if _depth >= MAX_DEPTH:
		push_warning("Reactions: %s goes on through moments %d deep; the rest is dropped (a loop in its data?)." % [prop.id, MAX_DEPTH])
		return
	_depth += 1
	var entries: int = _entries
	var next: int = -1
	var cast_bits: int = 0
	for row: PropReaction in now.reactions:
		if _entries != entries:
			# A moment inside this one moved the state on: this state's reactions are over.
			break
		if row == null or not row.heard(kind, name, amount, before):
			continue
		if row.cast > 0 and actor.caster != null and actor.caster.cast(row.cast - 1):
			cast_bits |= 1 << (row.cast - 1)
		if next < 0 and row.then != &"":
			next = prop.state_at(row.then)
	if next >= 0 and _entries == entries:
		_enter(next, cast_bits)
	_depth -= 1


## Enter state `at` (see the class doc); the staffs in `cast_bits` were cast by the moment that
## entered it, so their wind-ups go on.
func _enter(at: int, cast_bits: int) -> void:
	state = at
	_entries += 1
	var entries: int = _entries
	if actor.caster != null:
		for staff in actor.caster.staff_count:
			if cast_bits & (1 << staff) == 0:
				actor.caster.cancel_wind(staff)
	_shape_body(true)
	var now: PropState = current()
	if actor.events != null:
		actor.events.prop_state_changed.emit(actor.id, now.state_id)
	entered.emit(now.state_id)
	_moment(PropReaction.When.ENTERED, &"", 0.0)
	if now.gone and _entries == entries and not actor.is_dying():
		actor.die(-1)


## The hurt shape and the footprint as the state wants them (`hittable`, `blocks`): `live` in play
## (registered or laid at once), else only their fields, before they are attached.
func _shape_body(live: bool) -> void:
	var now: PropState = current()
	if now == null:
		return
	if actor.hurtbox != null:
		if live:
			actor.hurtbox.set_enabled(now.hittable)
		else:
			actor.hurtbox.enabled = now.hittable
	if actor.footprint != null:
		if live:
			actor.footprint.set_solid(now.blocks)
		else:
			actor.footprint.solid = now.blocks
