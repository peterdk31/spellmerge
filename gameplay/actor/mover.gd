class_name Mover
extends ActorComponent
## The mover (actors G4, docs/milestones/M2-actors.md, "The components"): everything that sets
## an actor's `velocity`. It walks where the intent says (`speed` × the intent's `move`), and it
## is the one caster kit: the moves an actor's own cards ask for (staffs B4 for wizards, F8c for
## enemies; one implementation since actors G4, docs/DECISIONS.md "The actor kit").
##
## Every move adds up (rules R4 F1, as shots' moves do, `Projectiles.move_shot`): each request
## carries its own `move` (the way and the distance) and its time, and runs on its own, so two
## dashes cast close together stack, two pulls add and a dash and its recoil add. A `teleport` is
## over at once: the actor jumps by its `move`, stopping TELEPORT_CLEARANCE short of the first
## wall, then backing off until the body (its footprint's circle, `Footprint.radius`) is clear of
## walls and of the ground of bodies that cannot move, and inside the room.
## Every other move (`dash`, `pull`, `swap`, `recoil`) is a velocity for its time; a `dash` turns
## toward a target as it goes when its card homes (`CarrierDash.move_homing`), goes at its cards'
## speed curve (`CarrierDash.move_curve`, `MoveCurve`: still its whole way in its time), and ends
## where a wall stops it head on (`held_up`: under about 45 degrees from straight into it; a glancing
## one slides on, boss plan OB10). Each move answers
## `caster_move_finished` where it ended, saying whether a wall ended it (`walled`: so its card's
## `on wall` fires, boss plan OB12): a teleport at once, the others the step after their
## last, once the body has walked it (the last step is shortened, so a move goes exactly its
## distance). A card's move is the actor's own when the card's tag names the actor's caster
## number (`Actor.caster_number`, its actor id), which is also the event's `caster`, unless the
## event names a body that belongs to the actor (its decoy). A body that belongs to an actor (a
## decoy, `Actor.belongs_to`) takes its owner's card's move when the event names it: a payload its
## body fired is cast by that body (owner, 2026-11-06), so its dash or teleport moves it.
##
## A dash is the actor's own legs: it walks instead of the intent while it runs, and statuses
## (`Combat.pace`: chill slows, freeze stops) scale it as they scale walking. The other moves are
## done to the actor (the spell moves it): added on top, not slowed. Combat's push on the actor
## (`Combat.consume_knockback`) is added every step, and so is a carry (Plow, boss plan OB11:
## `Plow.velocity_of`, as far as what carries it moved): done to it too, and its walk loses what
## goes back into its carrier, so it slips off sideways or not at all. A carried step held up head on
## along the way it is carried is a pin (`held_up`, `Plow.pinned`); a body whose carried body was
## pinned ends its dash with that card there (`carry_ended`), as if it met the wall itself. A swap
## card that names the actor as its
## target (`target_move_requested`) puts it there at once. While the actor is down it stands: its
## moves end unanswered and new requests are ignored; in a biome it crawls (`can_crawl`, connected
## biomes CB3). A move never takes it out of a sealed fight (`RoomGrid.may_cross`).
##
## Holes (hub rework HR-H1, docs/milestones/hub-rework.md, "Holes" 2 and 3): its own walk stops at a
## hole's lip; its dashes and everything done to it (its other moves, a carry, Combat's push) cross
## holes. `step` keeps the share of `velocity` that crosses (`crossing`), and the body's move slides
## the two parts apart (`Actor.move`). A jump (a teleport, a swap, a portal's exit) crosses: it puts
## the body there at once, and a walk from over a hole is not pushed back out of it. A teleport's
## back-off from walls never minds holes.
##
## Nothing here allocates in `step` (but the list of moves growing when full).

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## A teleport that meets a wall ends this many pixels short of it, and is then backed off in
## steps of TELEPORT_BACKOFF until the body is clear.
const TELEPORT_CLEARANCE: float = 8.0
const TELEPORT_BACKOFF: float = 4.0
## A downed wizard crawls at this share of its walking speed (connected biomes CB3, decision 13).
const CRAWL_SHARE: float = 0.25
## Room for this many running moves at first; the list doubles when it is full.
const MOVE_ROOM: int = 8
## The shortest time a move takes.
const MIN_SECONDS: float = 0.01
## A dash meets a wall head on when a step held up by it goes less than this share of the way the
## dash asked along its own way: a wall square across it keeps none, one at 45 degrees half (the slide
## keeps the part along the wall), so under about 45 degrees from straight in it ends (`held_up`).
const HEAD_ON_SHARE: float = 0.5

## Walking speed in pixels per second at full tilt (an enemy's from `EnemyBase.move_speed`).
@export var speed: float = 90.0

## The moves running (the first `_count`): each one's mode, velocity, seconds left (0 or less:
## done, answered next step), its card's tag, its homing (a dash's, or null), its speed curve
## (`MoveCurve`; NONE for an even one), its whole time and whether a wall ended it (`held_up`, a pin
## of what it carried: answered `walled`).
var _modes: Array[StringName] = []
var _velocities: PackedVector2Array = PackedVector2Array()
var _lefts: PackedFloat32Array = PackedFloat32Array()
var _curves: PackedVector3Array = PackedVector3Array()
var _totals: PackedFloat32Array = PackedFloat32Array()
var _tags: PackedInt64Array = PackedInt64Array()
var _walled: PackedByteArray = PackedByteArray()
var _homings: Array[Homing] = []
var _count: int = 0
## How many of the moves the last `step` stepped (the first ones; a move asked since is after
## them), so `held_up` ends only a move the body walked this step, its last, shortened one too.
var _stepped: int = 0
## What the moves added in the last step (pixels per second), for the looks.
var _moved: Vector2 = Vector2.ZERO
## The share of this step's `velocity` that crosses holes (hub rework HR-H1, docs/milestones/
## hub-rework.md, "Holes" 2 and 3): its dashes, its other moves, its carry and Combat's push, all but
## its own walk. Set by `step`, used and emptied by the body's move (`Actor.move`), so it is zero
## between ticks.
var crossing: Vector2 = Vector2.ZERO


func _init() -> void:
	_grow(MOVE_ROOM)


func attach() -> void:
	if actor.events == null:
		return
	if not actor.events.caster_move_requested.is_connected(_on_caster_move_requested):
		actor.events.caster_move_requested.connect(_on_caster_move_requested)
	if not actor.events.target_move_requested.is_connected(_on_target_move_requested):
		actor.events.target_move_requested.connect(_on_target_move_requested)
	if not actor.events.carry_ended.is_connected(_on_carry_ended):
		actor.events.carry_ended.connect(_on_carry_ended)


func detach() -> void:
	if actor.events == null or not is_instance_valid(actor.events):
		return
	if actor.events.caster_move_requested.is_connected(_on_caster_move_requested):
		actor.events.caster_move_requested.disconnect(_on_caster_move_requested)
	if actor.events.target_move_requested.is_connected(_on_target_move_requested):
		actor.events.target_move_requested.disconnect(_on_target_move_requested)
	if actor.events.carry_ended.is_connected(_on_carry_ended):
		actor.events.carry_ended.disconnect(_on_carry_ended)


## Set the actor's `velocity` for this step: the walk (or its dashes), every other move and
## Combat's push. The actor moves the body afterwards (`Actor.move`).
func step(delta: float) -> void:
	if actor.is_down():
		_count = 0
		_stepped = 0
		_homings.fill(null)
		_moved = Vector2.ZERO
		crossing = Vector2.ZERO
		actor.velocity = Vector2.ZERO
		if can_crawl():
			# Downed in a biome (connected biomes CB3, decision 13): it crawls where its intent says,
			# slowly, and nothing else moves it (its controller casts nothing while down).
			var pace: float = actor.combat.own_pace(actor, actor.id) if actor.combat != null else 1.0
			actor.velocity = actor.intent.move.limit_length(1.0) * speed * CRAWL_SHARE * pace
		return
	# The moves whose last step has been walked (the body moved after it) say where they ended
	# (asked only while it has moves: most bodies' steps have none).
	if _count > 0:
		_answer()
	# Combat's pace (chill slows, freeze stops) and its push on the actor, asked by its own id.
	var pace: float = actor.combat.own_pace(actor, actor.id) if actor.combat != null else 1.0
	var legs: bool = false
	_moved = Vector2.ZERO
	for at in _count:
		var velocity: Vector2 = _velocities[at]
		if _homings[at] != null:
			# A homing dash turns toward a target as it goes, as a homing shot does.
			velocity = _homings[at].steer(actor.projectiles, _caster_number(), actor.global_position, velocity, delta)
			_velocities[at] = velocity
		# The last step is shortened, so a move goes exactly its distance; a curved one goes the
		# curve's share of its way this step (`MoveCurve.share`).
		var seconds: float = minf(delta, _lefts[at]) if _curves[at] == MoveCurve.NONE else MoveCurve.share(_curves[at], _totals[at], _lefts[at], delta) * _totals[at]
		var share: Vector2 = velocity * seconds / maxf(delta, 0.0001)
		if _modes[at] == &"dash":
			legs = true
			share *= pace
		_moved += share
		_lefts[at] -= delta
	_stepped = _count
	var carry: Vector2 = _carry()
	var walk: Vector2 = Vector2.ZERO
	if not legs:
		walk = actor.intent.move.limit_length(1.0) * speed * pace
		if carry != Vector2.ZERO:
			# It cannot walk back into what carries it, only out to the side (or on ahead).
			var way: Vector2 = actor.spells.plow().way_of(actor.id)
			walk -= way * minf(walk.dot(way), 0.0)
	# Everything but its own walk crosses holes (`crossing`): its moves, its carry, Combat's push.
	# The velocity is summed in the order it always was, so a room with no holes moves to the bit as
	# before.
	var knockback: Vector2 = actor.combat.own_knockback(actor, actor.id, delta) if actor.combat != null else Vector2.ZERO
	crossing = _moved + carry + knockback
	var velocity: Vector2 = _moved
	if not legs:
		velocity += walk
	actor.velocity = velocity + carry + knockback


## True while the body crawls if its intent says so: downed (not falling or spawning) in a world of
## places (a biome, connected biomes CB3, decision 13; a row run's downed wizard stands where it fell
## until CB8 moves every run over).
func can_crawl() -> bool:
	return actor.is_downed() and not actor.is_falling() and not actor.is_spawning() and actor.projectiles != null and actor.projectiles.grid().places() > 0


## True while a move carries the actor.
func is_moving() -> bool:
	return _count > 0


## True while a dash (the actor's own legs, see the class doc) carries the actor, for the looks: a
## body moved by its own move shows its move's pose (boss plan OB8), one pulled or pushed does not.
func is_dashing() -> bool:
	for at in _count:
		if _modes[at] == &"dash":
			return true
	return false


## The actor's move this step was held up (`Actor.move`): it asked to go `asked` and went `got`. A
## dash that meets the wall head on (`HEAD_ON_SHARE`) ends where the body is, answered at the next
## step, so its end point is at the wall; one that glances off slides on. Walls, the ground of bodies
## that cannot move and the Wall card's stones alike (the one grid the body slides on).
func held_up(asked: Vector2, got: Vector2) -> void:
	var carry: Vector2 = _carry()
	if carry != Vector2.ZERO:
		var along: Vector2 = actor.spells.plow().way_of(actor.id)
		var pushed: float = asked.dot(along)
		# Only while the carry itself pushes it on (not a carrier slowing, holding it back).
		if carry.dot(along) > 0.0 and pushed > 0.0 and got.dot(along) < pushed * HEAD_ON_SHARE:
			# Pinned against what it slides on (Plow, boss plan OB11).
			actor.spells.plow().pinned(actor.id)
	# Every move the body walked this step, its last one too (its time is up, answered at the next).
	for at in mini(_stepped, _count):
		if _modes[at] != &"dash" or _velocities[at].is_zero_approx():
			continue
		var way: Vector2 = _velocities[at].normalized()
		var wanted: float = asked.dot(way)
		if wanted > 0.0 and got.dot(way) < wanted * HEAD_ON_SHARE:
			_lefts[at] = 0.0
			_walled[at] = 1


## The velocity the body is carried at this step (Plow, `Plow.velocity_of`), zero when it is not.
func _carry() -> Vector2:
	if actor == null or actor.spells == null or actor.spells.plow().carried_count() == 0:
		return Vector2.ZERO
	return actor.spells.plow().velocity_of(actor.id)


## A carry ended (`carry_ended`): a body this one carried was pinned, so this body's dash with that
## card ends where it is, as if it met the wall itself (boss plan OB11; answered at the next step,
## `walled`, so its `on wall` fires there: OB12).
func _on_carry_ended(_caster: int, _target: Node, carrier: int, _way: Vector2, pinned: bool, tag: int) -> void:
	if not pinned or carrier != actor.id or carrier < 0:
		return
	for at in _count:
		if _modes[at] == &"dash" and _tags[at] == tag:
			_lefts[at] = 0.0
			_walled[at] = 1


## The way the moves went in the last step (unit length, or zero when they cancel), for the looks.
func move_direction() -> Vector2:
	return _moved.normalized()


## End every move now and answer each where the actor is (an overlay opened, a decoy ended).
func stop() -> void:
	for at in _count:
		_lefts[at] = 0.0
	_answer()


## End every move now, quietly, with no answer (a decoy cleared with its room): a body placed again
## starts with none.
func drop() -> void:
	_count = 0
	_stepped = 0
	_homings.fill(null)
	_moved = Vector2.ZERO
	crossing = Vector2.ZERO


## A card of this actor asked to move it by `move` over `seconds` (see the class doc).
func _on_caster_move_requested(player: int, mode: StringName, move: Vector2, seconds: float, tag: int) -> void:
	if not _owns(player, tag) or actor.is_down() or not move.is_finite():
		return
	if mode == &"teleport":
		_teleport(move, tag)
		return
	if _count == _lefts.size():
		# Full: grow (rare; the steady state allocates nothing).
		_grow(_count * 2)
	var time: float = maxf(seconds, MIN_SECONDS)
	_modes[_count] = mode
	_velocities[_count] = move / time
	_lefts[_count] = time
	_tags[_count] = tag
	_walled[_count] = 0
	var dash: CarrierDash = CarrierDash.of(actor.spells) if mode == &"dash" and actor.spells != null else null
	_homings[_count] = dash.move_homing(_caster_number()) if dash != null else null
	_curves[_count] = dash.move_curve(_caster_number()) if dash != null else MoveCurve.NONE
	_totals[_count] = time
	_count += 1


func _grow(size: int) -> void:
	_modes.resize(size)
	_velocities.resize(size)
	_lefts.resize(size)
	_tags.resize(size)
	_walled.resize(size)
	_homings.resize(size)
	_curves.resize(size)
	_totals.resize(size)


## True when the move the event names `player` asks with the card `tag` is this actor's: a card of
## its own caster number, unless the event names a body of its own (that body moves), or a card of
## its owner's that the event names it for (see the class doc).
func _owns(player: int, tag: int) -> bool:
	var number: int = _caster_number()
	if number < 0 or not SpellTag.is_spell_tag(tag):
		return false
	var card: int = SpellTag.caster_of(tag)
	if card == number:
		return player == number or _owner_of(player) != number
	return player == number and card == actor.belongs_to


## The actor the body of the actor `id` belongs to (its owner: a decoy's wizard), or Actors.NONE.
func _owner_of(id: int) -> int:
	var body: Actor = actor.actors.node_of(id) as Actor if actor.actors != null else null
	return body.belongs_to if body != null else ActorsScript.NONE


func _caster_number() -> int:
	return actor.caster_number()


## Jump by `move` at once, stopping short of the first wall, then backing off along the path
## until the whole body is clear of walls and inside the room (or staying put), and say where the
## actor landed.
func _teleport(move: Vector2, tag: int) -> void:
	var start: Vector2 = actor.global_position
	var goal: Vector2 = start + move
	if actor.projectiles != null:
		var grid: RoomGrid = actor.projectiles.grid()
		# Across a doorway for a body a wizard drives, never out of a sealed fight (connected biomes
		# CB3, decision 11: `Actor.passes_mouths`); else a mouth stops it as a wall does.
		var through: bool = grid.has_mouths() and actor.passes_mouths()
		var reached: Vector2 = grid.clip_past_mouths(start, goal) if through else grid.clip_to_walls(start, goal)
		if reached != goal:
			reached = reached.move_toward(start, TELEPORT_CLEARANCE)
		goal = reached
		while goal != start and grid.circle_blocked(goal, actor.wall_radius()):
			goal = goal.move_toward(start, TELEPORT_BACKOFF)
	actor.global_position = goal
	if actor.events != null:
		actor.events.caster_move_finished.emit(_caster_number(), &"teleport", goal, tag, false)


## Answers the moves that are done where the actor is, so their cards go off there (blast, a
## trigger), and takes them off the list. A move asked while answering (a payload that moves
## again) is added at the end and runs.
func _answer() -> void:
	var at: int = 0
	while at < _count:
		if _lefts[at] > 0.0:
			at += 1
			continue
		var mode: StringName = _modes[at]
		var tag: int = _tags[at]
		var walled: bool = _walled[at] != 0
		_count -= 1
		_modes[at] = _modes[_count]
		_velocities[at] = _velocities[_count]
		_lefts[at] = _lefts[_count]
		_tags[at] = _tags[_count]
		_walled[at] = _walled[_count]
		_curves[at] = _curves[_count]
		_totals[at] = _totals[_count]
		_homings[at] = _homings[_count]
		_homings[_count] = null
		if actor.events != null:
			actor.events.caster_move_finished.emit(_caster_number(), mode, actor.global_position, tag, walled)


## A swap card moved this actor (it was the target): it is there at once, its move and aim kept.
func _on_target_move_requested(_player: int, moved: Node, to: Vector2) -> void:
	if moved == actor and to.is_finite():
		# Never out of a sealed fight (connected biomes CB3, decisions 11 and 12): a swap or a
		# portal that would take it out does nothing to it.
		if actor.projectiles != null and not actor.projectiles.grid().may_cross(actor.global_position, to):
			return
		actor.global_position = to
