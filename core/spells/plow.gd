class_name Plow
extends RefCounted
## Plow (boss plan OB11, `ModifierBase.Behaviour.PLOW`): what a carrier with it hits rides along in
## front of what moves it, instead of being passed. `Spells` owns one and tells it of each hit
## (`carry`); each step it works out how far every carrier moved since the last (`step`), and the
## carried body's own mover moves it that far (`velocity_of`, gameplay/actor/mover.gd), sliding on
## the walls as any move does. What moves a carry is a body a dash moves (the dash's mover, a
## decoy's body too) or a shot: one a dash moves, or a flying shot with Plow, which passes on through
## what it carries (`SpellLimits.PLOW_MOST` more pierce, the compiler).
##
## A carry ends, and `carry_ended` tells Combat and the carrier's mover:
## - **pinned:** the carried body's move this step was held up head on along the way it is carried
##   (`pinned`, told by its mover: walls, a blocking prop's ground, the Wall card's stones, as a dash
##   is held up, `Mover.HEAD_ON_SHARE`). Combat deals the pin the hit armed (`HitProfile.pin`, twice
##   the hit), and a body that carried it ends its dash there, as if it met the wall itself;
## - **let go:** its carrier's move is over (a dash's pass ends, `let_go`; a shot ends): Combat
##   shoves it on along the way it was carried, with the hit's own push;
## - **slipped off:** it walked out aside past the pass (or was put far on ahead) (`hold`: the pass's reach, its own size and
##   `SpellLimits.PLOW_SLIP`), so it is let go with no shove: slipping off sideways costs only the
##   pass;
## - **dropped:** it is gone, down or no longer a target (a downed wizard is never carried), or its
##   carrier's build is forgotten: no pin and no shove.
##
## It never carries a body that cannot move (a still body: a prop, props.md), the body that moves
## it, one carried already (the first carry keeps it) or one that carries a body itself. A shot never
## hits a body it carries again (`rides_on`). Everything here is state (a carried body
## and its node by who they are); nothing allocates in `step` (but the list growing when full).

const ActorsScript := preload("res://core/actors/actors.gd")

## The runtime these carries belong to (`CarrierKit`): its projectile manager and event bus.
var kit: CarrierKit = null
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_node"]
## The carries under way (the first `_count`): the carried actor id and its body; the carrier's tag
## and the actor whose card it is; the body that carries it (an actor id, or -1) or the shot (its
## slot and seq, or -1); where the carrier was at the last step (its hurt circle's middle, or the
## shot); the velocity the body is carried at this step; the way it is carried (unit length); how far
## its middle rides ahead of its carrier's, the two touching (`_front`: their sizes); how far aside
## of its carrier's way it may be before it slips off (`_hold`); and whether its mover found it
## pinned since the last step.
var _body: PackedInt32Array = PackedInt32Array()
var _node: Array[Node2D] = []
var _tag: PackedInt64Array = PackedInt64Array()
var _actor: PackedInt32Array = PackedInt32Array()
var _by_body: PackedInt32Array = PackedInt32Array()
var _by_shot: PackedInt32Array = PackedInt32Array()
var _by_seq: PackedInt64Array = PackedInt64Array()
var _last: PackedVector2Array = PackedVector2Array()
var _velocity: PackedVector2Array = PackedVector2Array()
var _way: PackedVector2Array = PackedVector2Array()
var _front: PackedFloat32Array = PackedFloat32Array()
var _hold: PackedFloat32Array = PackedFloat32Array()
var _pinned: PackedByteArray = PackedByteArray()
## 1 for a carry made since the last step: the hit that made it is being dealt (`rides_on`).
var _fresh: PackedByteArray = PackedByteArray()
var _count: int = 0
## Per actor id: its carry's place in the list plus one (0: not carried), so its mover's read is one
## array read.
var _carry_of: PackedInt32Array = PackedInt32Array()


func _init(runtime_kit: CarrierKit) -> void:
	kit = runtime_kit
	_carry_of.resize(SpellRuntime.ACTORS)
	_grow(SpellLimits.PLOW_ROOM)
	clear()


## No carry is under way (`Spells.clear`, at a run's start): quietly, with no `carry_ended`, as
## Combat renews its rows then too.
func clear() -> void:
	for i in _count:
		_node[i] = null
	_count = 0
	_carry_of.fill(0)


## How many bodies are carried now.
func carried_count() -> int:
	return _count


## A hit of `spell` (with `tag`, a card of `actor`) on `target`, by the shot in `slot` (-1 for a
## strike: a dash's pass): the body is carried from now by what moved the carrier (a flying shot:
## that shot; a dash: the body or the shot it moves, `CasterMoves.moved_by`), within `reach` of it
## (the pass's, or the shot's radius). The cast under way is the hit's (`CarrierKit.caster`).
func carry(spell: CompiledSpell, tag: int, actor: int, target: Node, slot: int, reach: float) -> void:
	if kit.projectiles == null or not is_instance_valid(target) or not (target is Node2D):
		return
	var id: int = kit.projectiles.target_owner_of(target)
	if id < 0 or id >= SpellRuntime.ACTORS or _carry_of[id] != 0:
		return
	var table: ActorsScript = kit.projectiles.actor_table()
	if table != null and table.is_still(id):
		return
	var by_body: int = -1
	var by_shot: int = -1
	var carrier: Carrier = kit.carrier_of(spell)
	if slot >= 0 and carrier.flies():
		by_shot = slot
	elif slot < 0 and carrier.moves_along():
		var moved: int = CasterMoves.moved_by(kit.caster(), actor)
		if moved >= 0:
			by_shot = moved
		else:
			by_body = SpellRuntime.body_of(moved, actor)
	if (by_body < 0 and by_shot < 0) or by_body == id or _carries(id):
		return
	if by_shot >= 0 and not kit.projectiles.is_alive(by_shot):
		return
	var at: Vector2 = _carrier_at(by_body, by_shot, kit.projectiles.get_seq_of(by_shot) if by_shot >= 0 else 0)
	if not at.is_finite():
		return
	if _count == _body.size():
		_grow(_count * 2)
	var i: int = _count
	var node: Node2D = target as Node2D
	_body[i] = id
	_node[i] = node
	_tag[i] = tag
	_actor[i] = actor
	_by_body[i] = by_body
	_by_shot[i] = by_shot
	_by_seq[i] = kit.projectiles.get_seq_of(by_shot) if by_shot >= 0 else 0
	_last[i] = at
	_velocity[i] = Vector2.ZERO
	_way[i] = _way_of(by_body, by_shot, at, kit.projectiles.target_centre(node))
	var size: float = _size_of(node)
	_front[i] = size + (kit.projectiles.get_radius_of(by_shot) if by_shot >= 0 else _size_of(kit.body_node(by_body)))
	_hold[i] = reach + size + SpellLimits.PLOW_SLIP
	_pinned[i] = 0
	_fresh[i] = 1
	_count += 1
	_carry_of[id] = _count


## True while the body of the actor `id` carries a body: it is not carried itself, so two bodies never
## carry each other (each would be moved by the other's move, ever faster).
func _carries(id: int) -> bool:
	for i in _count:
		if _by_body[i] == id:
			return true
	return false


## True when the body of the actor `id` rides on the shot in `slot` from an earlier hit (not the one
## being dealt): a shot never hits a body it carries again (Spells and Combat skip such a hit), as it
## catches up with it at a wall.
func rides_on(id: int, slot: int) -> bool:
	if slot < 0 or id < 0 or id >= _carry_of.size() or _carry_of[id] == 0:
		return false
	var i: int = _carry_of[id] - 1
	return _fresh[i] == 0 and _by_shot[i] == slot and _by_seq[i] == kit.projectiles.get_seq_of(slot)


## True while the body of the actor `id` is carried by a carrier of `tag`.
func carrying(id: int, tag: int) -> bool:
	return id >= 0 and id < _carry_of.size() and _carry_of[id] != 0 and _tag[_carry_of[id] - 1] == tag


## The body that carries the actor `id` (an actor id), or -1: not carried, or carried by a shot.
func carrier_body_of(id: int) -> int:
	return _by_body[_carry_of[id] - 1] if id >= 0 and id < _carry_of.size() and _carry_of[id] != 0 else -1


## The velocity the actor `id`'s body is carried at this step (zero when it is not carried, or is no
## longer the target it was), for its
## mover: added to its own, not slowed by its statuses (it is done to the body, as a pull is).
func velocity_of(id: int) -> Vector2:
	if id < 0 or id >= _carry_of.size() or _carry_of[id] == 0:
		return Vector2.ZERO
	var i: int = _carry_of[id] - 1
	# Not a body that has left the targets (down) or taken the id since: dropped at the next step.
	if not is_instance_valid(_node[i]) or kit.projectiles.target_owner_of(_node[i]) != id:
		return Vector2.ZERO
	return _velocity[i]


## The way the actor `id`'s body is carried (unit length; zero when it is not carried).
func way_of(id: int) -> Vector2:
	return _way[_carry_of[id] - 1] if id >= 0 and id < _carry_of.size() and _carry_of[id] != 0 else Vector2.ZERO


## The mover of the actor `id` found its carried body held up head on along the way it is carried
## (`Mover.held_up`): it is pinned, and the carry ends at the next step (`step`).
func pinned(id: int) -> void:
	if id >= 0 and id < _carry_of.size() and _carry_of[id] != 0:
		_pinned[_carry_of[id] - 1] = 1


## The carry of the actor `id`'s body ends quietly, with no pin and no shove: its hit did not land
## (Combat: a barrier took it whole).
func drop(id: int) -> void:
	if id >= 0 and id < _carry_of.size() and _carry_of[id] != 0:
		_end(_carry_of[id] - 1, Vector2.ZERO, false)


## The move of the carrier `tag` by the body `by_body` (an actor id, or -1) or the shot `by_shot`
## is over (a dash's pass ended, `CarrierDash`): what it carries is let go with a shove.
func let_go(tag: int, by_body: int, by_shot: int) -> void:
	var i: int = _count - 1
	while i >= 0:
		if _tag[i] == tag and _by_body[i] == by_body and _by_shot[i] == by_shot:
			# A pin its mover found in the move's last step still counts.
			_end(i, Vector2.ZERO if _pinned[i] != 0 else _way[i], _pinned[i] != 0)
		i -= 1


## Every carry of `actor`'s cards, or of its body, ends quietly (a caster opened or closed under its
## id).
func reset_actor(actor: int) -> void:
	var i: int = _count - 1
	while i >= 0:
		if _actor[i] == actor or _by_body[i] == actor or _body[i] == actor:
			_end(i, Vector2.ZERO, false)
		i -= 1


## Runs the carries on (`Spells.step`, after the carriers): each ends as the class doc says, or is
## carried this step as far as its carrier moved since the last.
func step(delta: float) -> void:
	var i: int = _count - 1
	while i >= 0:
		_step_carry(i, delta)
		i -= 1


func _step_carry(i: int, delta: float) -> void:
	_fresh[i] = 0
	var node: Node2D = _node[i]
	if not is_instance_valid(node) or kit.projectiles.target_owner_of(node) != _body[i] or kit.spell_of(_tag[i]) == null:
		_end(i, Vector2.ZERO, false)
		return
	if _pinned[i] != 0:
		_end(i, Vector2.ZERO, true)
		return
	var at: Vector2 = _carrier_at(_by_body[i], _by_shot[i], _by_seq[i])
	if not at.is_finite():
		# Its carrier is gone (a shot ended, a body freed): let go where it is.
		_end(i, _way[i], false)
		return
	var moved: Vector2 = at - _last[i]
	_last[i] = at
	if not moved.is_zero_approx():
		_way[i] = moved.normalized()
	var way: Vector2 = _way[i]
	var off: Vector2 = kit.projectiles.target_centre(node) - at
	var along: float = off.dot(way)
	var aside: float = absf(off.dot(way.orthogonal()))
	if aside > _hold[i] or along > _front[i] + _hold[i]:
		# Out past the pass, to the side (or far on ahead: a teleport, another hit's knock): slipped off.
		_end(i, Vector2.ZERO, false)
		return
	# It rides ahead of its carrier, the two just touching: its middle `ahead` along the way at its
	# offset aside, from where its carrier will be after this step (about as far on as it went the
	# step before). Its move takes it there, sliding on the walls: from behind that (a pass strikes
	# what it reaches, often level with it) or from on ahead (its carrier slowing goes less far).
	var ahead: float = sqrt(maxf(_front[i] * _front[i] - aside * aside, 0.0))
	_velocity[i] = (moved + way * (ahead - along)) / delta if delta > 0.0 else Vector2.ZERO


## Where the carrier is: the middle of the body's hurt circle (an actor id), or the live shot (its
## slot and seq); INF when it is gone.
func _carrier_at(by_body: int, by_shot: int, seq: int) -> Vector2:
	if by_body >= 0:
		return kit.projectiles.target_centre(kit.body_node(by_body))
	if kit.projectiles.is_alive(by_shot) and kit.projectiles.get_seq_of(by_shot) == seq:
		return kit.projectiles.get_position_of(by_shot)
	return Vector2.INF


## How far a registered body's hurt shape reaches round its middle: the radius it is rounded by and
## the larger half of its box (0 for none).
func _size_of(node: Node) -> float:
	var half: Vector2 = kit.projectiles.target_half(node)
	return kit.projectiles.target_round(node) + maxf(half.x, half.y)


## The way a carry by `by_body` or `by_shot` starts: the shot's flight, or the
## way the body's move goes (`CasterMoves.move_heading`), else from the carrier at `from` to the body
## at `to`.
func _way_of(by_body: int, by_shot: int, from: Vector2, to: Vector2) -> Vector2:
	if by_shot >= 0 and not kit.projectiles.get_velocity_of(by_shot).is_zero_approx():
		return kit.projectiles.get_velocity_of(by_shot).normalized()
	if by_body >= 0 and by_body < kit.moves().move_heading.size():
		return kit.moves().move_heading[by_body]
	return from.direction_to(to) if to.is_finite() and not from.is_equal_approx(to) else Vector2.RIGHT


## The carry `i` ends: `carry_ended` (a shove along `way`, none when zero; `pinned` against a wall),
## and the last carry takes its place.
func _end(i: int, way: Vector2, pin: bool) -> void:
	var node: Node2D = _node[i]
	var tag: int = _tag[i]
	var actor: int = _actor[i]
	var by_body: int = _by_body[i]
	_carry_of[_body[i]] = 0
	_count -= 1
	if i != _count:
		_body[i] = _body[_count]
		_node[i] = _node[_count]
		_tag[i] = _tag[_count]
		_actor[i] = _actor[_count]
		_by_body[i] = _by_body[_count]
		_by_shot[i] = _by_shot[_count]
		_by_seq[i] = _by_seq[_count]
		_last[i] = _last[_count]
		_velocity[i] = _velocity[_count]
		_way[i] = _way[_count]
		_front[i] = _front[_count]
		_hold[i] = _hold[_count]
		_pinned[i] = _pinned[_count]
		_fresh[i] = _fresh[_count]
		_carry_of[_body[i]] = i + 1
	_node[_count] = null
	if kit.events != null and is_instance_valid(node):
		kit.events.carry_ended.emit(actor, node, by_body, way, pin, tag)


func _grow(size: int) -> void:
	_body.resize(size)
	_node.resize(size)
	_tag.resize(size)
	_actor.resize(size)
	_by_body.resize(size)
	_by_shot.resize(size)
	_by_seq.resize(size)
	_last.resize(size)
	_velocity.resize(size)
	_way.resize(size)
	_front.resize(size)
	_hold.resize(size)
	_pinned.resize(size)
	_fresh.resize(size)

