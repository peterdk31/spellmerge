class_name CasterMoves
extends RefCounted
## The moves carriers make of their caster or of the shot that cast them (`Spells` owns one): a dash
## and a teleport move it (`CarrierMove`), `pull` pulls it to what its carrier hits (`pull`), a swap
## trades it, and recoil pushes it; every move adds up (rules R4 F1). A body is asked through its
## owner (`caster_move_requested`, the way and the distance) and answers where it stopped
## (`caster_move_finished`, `finished`); a shot is moved by the projectile manager and its end comes
## when the move is over (`track`, `step`). Where a move ends is its carrier's end point (`end`):
## the carrier's own part there (`Carrier.on_move_end`: a teleport's landing strike), its blast and
## its `on expire` payload. A move's shield guards what it moves (`shield`).

## The runtime these moves belong to: its projectile manager, event bus and the shared end-point path.
var rt: SpellRuntime = null
## actor -> the way its last asked move goes, for the payload fired where it ends.
var move_heading: PackedVector2Array = PackedVector2Array()
## tag -> the pulls of the wizard under way whose hit spent their shot, so the arrival is the
## carrier's end point; a shot that flies on ends by itself (rules R4a).
var pull_ends: Dictionary = {}
## Moves of shots whose end point is still to come (a dash whose caster is a shot): the shot, its
## sequence number, the carrier's tag, seconds left, its heading and where it was last seen.
var _mv_slot: PackedInt32Array = PackedInt32Array()
var _mv_seq: PackedInt64Array = PackedInt64Array()
var _mv_tag: PackedInt64Array = PackedInt64Array()
var _mv_left: PackedFloat32Array = PackedFloat32Array()
var _mv_heading: PackedVector2Array = PackedVector2Array()
var _mv_at: PackedVector2Array = PackedVector2Array()
var _mv_count: int = 0


func _init(runtime: SpellRuntime) -> void:
	rt = runtime
	move_heading.resize(SpellRuntime.ACTORS)
	for column: Variant in [_mv_slot, _mv_seq, _mv_tag, _mv_left, _mv_heading, _mv_at]:
		column.resize(SpellLimits.SHOT_MOVES_START)
	clear()


## No move is under way (`Spells.clear`).
func clear() -> void:
	_mv_count = 0
	move_heading.fill(Vector2.RIGHT)
	pull_ends.clear()


## How many moves of shots are still under way (their end point to come).
func under_way() -> int:
	return _mv_count


## `actor` has made no move (a caster opened or closed under its id).
func reset_actor(actor: int) -> void:
	move_heading[actor] = Vector2.RIGHT
	for tag: int in pull_ends.keys():
		if SpellTag.caster_of(tag) == actor:
			pull_ends.erase(tag)


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
	rt.shot_started(tag)
	if seconds <= 0.0:
		end(tag, rt.projectiles.get_position_of(shot), heading, shot)
		rt.shot_ended(tag)
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
	_mv_seq[_mv_count] = rt.projectiles.get_seq_of(shot)
	_mv_tag[_mv_count] = tag
	_mv_left[_mv_count] = seconds
	_mv_heading[_mv_count] = heading
	_mv_at[_mv_count] = rt.projectiles.get_position_of(shot)
	_mv_count += 1


## Runs the shot moves on by `delta`; one that is over ends where its shot is (or was last seen).
func step(delta: float) -> void:
	var i: int = 0
	while i < _mv_count:
		var shot: int = _mv_slot[i]
		var alive: bool = rt.projectiles.is_alive(shot) and rt.projectiles.get_seq_of(shot) == _mv_seq[i]
		if alive:
			_mv_at[i] = rt.projectiles.get_position_of(shot)
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
		rt.shot_ended(tag)


## A move by the carrier `tag` ended at `at`: a teleport strikes what is where it landed
## (`Carrier.on_move_end`), its `blast` goes off there and its `on expire` payload leaves from there,
## cast by `caster` (the wizard, the shot that moved, or the point).
func end(tag: int, at: Vector2, heading: Vector2, caster: int) -> void:
	var spell: CompiledSpell = rt._profiles.get(tag)
	var actor: int = SpellTag.caster_of(tag)
	if spell == null or not at.is_finite():
		return
	rt._carrier_of(spell).on_move_end(spell, tag, actor, at, heading)
	rt._blast(spell, tag, actor, at)
	if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
		rt._fire(spell.payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), at, heading, null, caster)


## Where a dash or teleport ended, or a pull whose hit spent its shot (`pull_ends`): the carrier's
## end point. Its `blast` and its `on expire` payload happen there. A move whose build has been
## forgotten does nothing.
func finished(actor: int, mode: StringName, position: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag) or actor != SpellTag.caster_of(tag) or not position.is_finite():
		return
	if mode == &"pull" and pull_ends.get(tag, 0) > 0:
		pull_ends[tag] -= 1
		if pull_ends[tag] == 0:
			pull_ends.erase(tag)
	elif mode != &"dash" and mode != &"teleport":
		return
	# The caster's body moved, so it casts what its end point fires.
	end(tag, position, move_heading[actor], SpellRuntime.CASTER_WIZARD)


## `pull` (rules R4 F1): the caster of the carrier with `tag` is pulled to `position`, where it hit
## (a hit of the shot in `slot`, -1 for a line or a strike): the body through its owner, or the shot
## that cast this one; a point cannot move, so one cast from a point moves the wizard (rules R4c).
## Its shield guards the move (`shield`). A shot this hit spent ends where what it pulls arrives
## (rules R4a); one with pierce left flies on and ends by itself, and a line or a strike ends as it
## does. True when it pulled, so the hit's blast waits for the arrival.
func pull(spell: CompiledSpell, tag: int, actor: int, position: Vector2, slot: int, spent: bool) -> bool:
	var caster: int = rt.projectiles.caster_shot_of(slot) if slot >= 0 and not rt.projectiles.is_cast_by_wizard(slot) else -1
	if caster < 0:
		var anchor: Vector2 = rt.projectiles.get_anchor(actor)
		if rt.events == null or not anchor.is_finite():
			return false
		move_heading[actor] = anchor.direction_to(position) if not anchor.is_equal_approx(position) else Vector2.RIGHT
		rt.events.caster_move_requested.emit(actor, &"pull", position - anchor, SpellLimits.PULL_SECONDS, tag)
		if spent:
			pull_ends[tag] = pull_ends.get(tag, 0) + 1
		shield(spell, tag, actor, -1, SpellLimits.PULL_SECONDS)
		return true
	var from: Vector2 = rt.projectiles.get_position_of(caster)
	if not rt.projectiles.move_shot(caster, position - from, SpellLimits.PULL_SECONDS):
		return false
	shield(spell, tag, actor, caster, SpellLimits.PULL_SECONDS)
	if spent:
		track(caster, tag, SpellLimits.PULL_SECONDS, from.direction_to(position))
	return true


## `shield` on a move, one rule for every spell that moves its caster (dash, teleport, pull, swap;
## rules R4c): what it moves is guarded for the move, the wizard (`shot` -1) by a barrier
## (`shield_caster`), a shot by that many more shield charges, kept until they are spent.
func shield(spell: CompiledSpell, tag: int, actor: int, shot: int, seconds: float) -> void:
	if shot < 0:
		shield_caster(spell, tag, actor, seconds)
		return
	var charges: int = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	if charges > 0:
		rt.projectiles.set_shield(shot, rt.projectiles.get_shield_of(shot) + charges)


## `shield` on the caster itself: a barrier on the casting actor with the card's charges, for as
## long as the carrier lasts (a move's own time at least). It comes with every move of the
## wizard (`shield`) and the cards landing on the caster. Combat gives it a minimum time.
func shield_caster(spell: CompiledSpell, tag: int, actor: int, move_seconds: float) -> void:
	var charges: int = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	if charges > 0 and rt.events != null:
		rt.events.wizard_shield_requested.emit(actor, charges, maxf(spell.lifetime, move_seconds), tag)
