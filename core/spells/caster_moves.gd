class_name CasterMoves
extends RefCounted
## The moves carriers make of their caster or of the shot that cast them (`Spells` owns one): a dash
## and a teleport move it (`CarrierMove`), `pull` pulls it to what its carrier hits (`pull`), a swap
## trades it, and recoil pushes it; every move adds up (rules R4 F1). A body is asked through its
## owner (`caster_move_requested`, the way and the distance) and answers where it stopped
## (`caster_move_finished`, `finished`); a shot is moved by the projectile manager and its end comes
## when the move is over (`track`, `step`). The body is the caster's: the wizard's for its own cast,
## or the body that fired a payload (a decoy's; `CarrierKit.caster_body`), whose actor is not the
## card's (`asked`). Where a move ends is its carrier's end point (`end`): the carrier's own part
## there (`Carrier.on_move_end`: a teleport's landing strike), its blast and its `on expire` payload,
## cast by what moved. A move's shield guards what it moves (`shield`).

## The runtime these moves belong to (`CarrierKit`): its projectile manager, event bus and the
## shared end-point path.
var kit: CarrierKit = null
## actor -> the way its last asked move goes, for the payload fired where it ends.
var move_heading: PackedVector2Array = PackedVector2Array()
## tag -> the pulls of the wizard under way whose hit spent their shot, so the arrival is the
## carrier's end point; a shot that flies on ends by itself (rules R4a).
var pull_ends: Dictionary = {}
## Vector2i(body, tag) -> the moves under way of a body that is not the card's caster's (a decoy's
## dash), so its answer (`finished`) is the card's end point too.
var _others: Dictionary = {}
## Moves of shots whose end point is still to come (a dash whose caster is a shot): the shot, its
## sequence number, the carrier's tag, seconds left, its heading and where it was last seen.
var _mv_slot: PackedInt32Array = PackedInt32Array()
var _mv_seq: PackedInt64Array = PackedInt64Array()
var _mv_tag: PackedInt64Array = PackedInt64Array()
var _mv_left: PackedFloat32Array = PackedFloat32Array()
var _mv_heading: PackedVector2Array = PackedVector2Array()
var _mv_at: PackedVector2Array = PackedVector2Array()
var _mv_count: int = 0


func _init(runtime_kit: CarrierKit) -> void:
	kit = runtime_kit
	move_heading.resize(SpellRuntime.ACTORS)
	for column: Variant in [_mv_slot, _mv_seq, _mv_tag, _mv_left, _mv_heading, _mv_at]:
		column.resize(SpellLimits.SHOT_MOVES_START)
	clear()


## No move is under way (`Spells.clear`).
func clear() -> void:
	_mv_count = 0
	move_heading.fill(Vector2.RIGHT)
	pull_ends.clear()
	_others.clear()


## How many moves of shots are still under way (their end point to come).
func under_way() -> int:
	return _mv_count


## `actor` has made no move (a caster opened or closed under its id).
func reset_actor(actor: int) -> void:
	move_heading[actor] = Vector2.RIGHT
	for tag: int in pull_ends.keys():
		if SpellTag.caster_of(tag) == actor:
			pull_ends.erase(tag)
	for key: Vector2i in _others.keys():
		if key.x == actor or SpellTag.caster_of(key.y) == actor:
			_others.erase(key)


## How far a dash or teleport card moves its caster: its `ray_length` (a card made before moves
## had a distance falls back to speed x lifetime).
static func move_distance(length: float, speed: float, lifetime: float) -> float:
	return length if length > 0.0 else speed * lifetime


## How long a dash takes: its distance at its speed (its lifetime when it has no speed).
static func move_seconds(length: float, speed: float, lifetime: float) -> float:
	if length > 0.0 and speed > 0.0:
		return length / speed
	return lifetime


## Waits for the end of the move of `shot` (`seconds` from now; at once for 0), which is the end
## point of the carrier `tag`: its `blast` and its `on expire` payload happen there. The carrier
## counts as a live shot until then.
func track(shot: int, tag: int, seconds: float, heading: Vector2) -> void:
	kit.shot_started(tag)
	if seconds <= 0.0:
		end(tag, kit.projectiles.get_position_of(shot), heading, shot)
		kit.shot_ended(tag)
		return
	if _mv_count == _mv_slot.size():
		var size: int = _mv_count * 2
		_mv_slot.resize(size)
		_mv_seq.resize(size)
		_mv_tag.resize(size)
		_mv_left.resize(size)
		_mv_heading.resize(size)
		_mv_at.resize(size)
	_mv_slot[_mv_count] = shot
	_mv_seq[_mv_count] = kit.projectiles.get_seq_of(shot)
	_mv_tag[_mv_count] = tag
	_mv_left[_mv_count] = seconds
	_mv_heading[_mv_count] = heading
	_mv_at[_mv_count] = kit.projectiles.get_position_of(shot)
	_mv_count += 1


## Runs the shot moves on by `delta`; one that is over ends where its shot is (or was last seen).
func step(delta: float) -> void:
	var i: int = 0
	while i < _mv_count:
		var shot: int = _mv_slot[i]
		var alive: bool = kit.projectiles.is_alive(shot) and kit.projectiles.get_seq_of(shot) == _mv_seq[i]
		if alive:
			_mv_at[i] = kit.projectiles.get_position_of(shot)
		_mv_left[i] -= delta
		if _mv_left[i] > 0.0:
			i += 1
			continue
		var tag: int = _mv_tag[i]
		var at: Vector2 = _mv_at[i]
		var heading: Vector2 = _mv_heading[i]
		_mv_count -= 1
		_mv_slot[i] = _mv_slot[_mv_count]
		_mv_seq[i] = _mv_seq[_mv_count]
		_mv_tag[i] = _mv_tag[_mv_count]
		_mv_left[i] = _mv_left[_mv_count]
		_mv_heading[i] = _mv_heading[_mv_count]
		_mv_at[i] = _mv_at[_mv_count]
		end(tag, at, heading, shot if alive else SpellRuntime.CASTER_POINT)
		kit.shot_ended(tag)


## A move by the carrier `tag` ended at `at`: it is shown ending there (`carrier_ended`, its card's
## impact cue: where a teleport lands), a teleport strikes what is where it landed
## (`Carrier.on_move_end`), its `blast` goes off there and its `on expire` payload leaves from there,
## cast by `caster` (a value as `CarrierKit.caster`: the body or the shot that moved, or the point).
func end(tag: int, at: Vector2, heading: Vector2, caster: int) -> void:
	var spell: CompiledSpell = kit.spell_of(tag)
	var actor: int = SpellTag.caster_of(tag)
	if spell == null or not at.is_finite():
		return
	if kit.events != null:
		kit.set_cue_tag(tag)
		kit.events.carrier_ended.emit(actor, spell.carrier_card_id, at, heading, spell.radius, spell.tint, spell.look)
		kit.set_cue_tag(0)
	# What it does where it lands hits as the move's caster (a teleport's strike, its pulls).
	kit.cast_as(caster, kit.projectiles.get_seq_of(caster) if caster >= 0 else 0)
	kit.carrier_of(spell).on_move_end(spell, tag, actor, at, heading)
	kit.cast_done()
	kit.blast(spell, tag, actor, at)
	for trigger in spell.triggers:
		if trigger.event == TriggerBase.Event.EXPIRE:
			kit.fire(trigger.payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), at, heading, null, caster)


## The body of the actor `body` was asked to make a move for the card `tag` that it answers with
## `caster_move_finished` (a dash, a teleport, a pull whose hit spent its shot): one that is not
## the card's caster's is noted, so its answer counts (`finished`).
func asked(body: int, tag: int) -> void:
	if body != SpellTag.caster_of(tag):
		var key := Vector2i(body, tag)
		_others[key] = int(_others.get(key, 0)) + 1


## Where a dash or teleport ended, or a pull whose hit spent its shot (`pull_ends`): the carrier's
## end point. Its `blast` and its `on expire` payload happen there, cast by the body that moved. A
## move whose build has been forgotten, or that no card of `tag` asked of that body, does nothing.
func finished(actor: int, mode: StringName, position: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag) or not position.is_finite() or (mode != &"pull" and mode != &"dash" and mode != &"teleport"):
		return
	if actor != SpellTag.caster_of(tag):
		var key := Vector2i(actor, tag)
		if not _others.has(key):
			return
		_others[key] = int(_others[key]) - 1
		if _others[key] <= 0:
			_others.erase(key)
	if mode == &"pull" and pull_ends.get(tag, 0) > 0:
		pull_ends[tag] -= 1
		if pull_ends[tag] == 0:
			pull_ends.erase(tag)
	elif mode == &"pull":
		return
	# The body moved, so it casts what its end point fires.
	end(tag, position, move_heading[actor], SpellRuntime.body_caster(actor))


## `pull` (rules R4 F1): the caster of the carrier with `tag` is pulled to `position`, where it hit
## (a hit of the shot in `slot`, -1 for a line or a strike): the body through its owner, or the shot
## that cast this one; a point cannot move, so one cast from a point moves the wizard (rules R4c).
## Its shield guards the move (`shield`). A shot this hit spent ends where what it pulls arrives
## (rules R4a); one with pierce left flies on and ends by itself, and a line or a strike ends as it
## does. True when it pulled, so the hit's blast waits for the arrival.
func pull(spell: CompiledSpell, tag: int, actor: int, position: Vector2, slot: int, spent: bool) -> bool:
	var moved: int = moved_by(kit.shot_caster(slot) if slot >= 0 else kit.caster(), actor)
	if moved < 0:
		var body: int = SpellRuntime.body_of(moved, actor)
		var anchor: Vector2 = kit.projectiles.get_anchor(body)
		if kit.events == null or not anchor.is_finite():
			return false
		move_heading[body] = anchor.direction_to(position) if not anchor.is_equal_approx(position) else Vector2.RIGHT
		if spent:
			pull_ends[tag] = pull_ends.get(tag, 0) + 1
			asked(body, tag)
		kit.events.caster_move_requested.emit(body, &"pull", position - anchor, SpellLimits.PULL_SECONDS, tag)
		shield(spell, tag, body, -1, SpellLimits.PULL_SECONDS)
		return true
	var from: Vector2 = kit.projectiles.get_position_of(moved)
	if not kit.projectiles.move_shot(moved, position - from, SpellLimits.PULL_SECONDS):
		return false
	shield(spell, tag, -1, moved, SpellLimits.PULL_SECONDS)
	if spent:
		track(moved, tag, SpellLimits.PULL_SECONDS, from.direction_to(position))
	return true


## What a move by a card of `actor` whose caster is `caster` (a value as `CarrierKit.caster`) moves:
## that shot (its slot) or that body (`SpellRuntime.body_caster`); a point cannot move, so a move
## cast by one moves the wizard's body (rules R4c). One rule for dash, teleport, pull and swap.
static func moved_by(caster: int, actor: int) -> int:
	if caster >= 0 or SpellRuntime.body_of(caster, actor) >= 0:
		return caster
	return SpellRuntime.body_caster(actor)


## `shield` on a move, one rule for every spell that moves its caster (dash, teleport, pull, swap;
## rules R4c): what it moves is guarded for the move, the body of `body` (`shot` -1) by a barrier
## (`shield_caster`), a shot by that many more shield charges, kept until they are spent.
func shield(spell: CompiledSpell, tag: int, body: int, shot: int, seconds: float) -> void:
	if shot < 0:
		shield_caster(spell, tag, body, seconds)
		return
	var charges: int = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	if charges > 0:
		kit.projectiles.set_shield(shot, kit.projectiles.get_shield_of(shot) + charges)


## `shield` on a body: a barrier on the actor `actor` with the card's charges, for as long as the
## carrier lasts (a move's own time at least). It comes with every move of the wizard (`shield`),
## the cards landing on the caster or on the body that fired a payload (`CarrierBearer`), and a
## decoy's body (`CarrierDecoy`). Combat gives it a minimum time; its block is the card `tag`'s.
func shield_caster(spell: CompiledSpell, tag: int, actor: int, move_seconds: float) -> void:
	var charges: int = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	if charges > 0 and kit.events != null:
		kit.events.wizard_shield_requested.emit(actor, charges, maxf(spell.lifetime, move_seconds), tag)
