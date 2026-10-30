class_name CasterMoves
extends RefCounted
## The moves carriers make of their caster or of the shot that cast them (`Spells` owns one): a dash
## and a teleport move it (`CarrierMove`), a hook pulls it and a swap trades it, and recoil pushes
## it. A body is asked through its owner (`caster_move_requested`) and answers where it stopped
## (`caster_move_finished`, `finished`); a shot is moved by the projectile manager and its end comes
## when the move is over (`track`, `step`). Where a move ends is its carrier's end point (`end`):
## the carrier's own part there (`Carrier.on_move_end`: a teleport's landing strike), its blast and
## its `on expire` payload. A move's shield guards what it moves (`shield`).

## The runtime these moves belong to: its projectile manager, event bus and the shared end-point path.
var rt: SpellRuntime = null
## actor -> the way its last asked move goes, for the payload fired where it ends.
var move_heading: PackedVector2Array = PackedVector2Array()
## actor -> 1 when its hook move in progress ends its hook shot (the hit spent it), so the arrival
## is the carrier's end point; 0 when the shot flies on and ends by itself (rules R4a).
var hook_ends: PackedByteArray = PackedByteArray()
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
	hook_ends.resize(SpellRuntime.ACTORS)
	for column: Variant in [_mv_slot, _mv_seq, _mv_tag, _mv_left, _mv_heading, _mv_at]:
		column.resize(SpellLimits.SHOT_MOVES_START)
	clear()


## No move is under way (`Spells.clear`).
func clear() -> void:
	_mv_count = 0
	move_heading.fill(Vector2.RIGHT)
	hook_ends.fill(0)


## How many moves of shots are still under way (their end point to come).
func under_way() -> int:
	return _mv_count


## `actor` has made no move (a caster opened or closed under its id).
func reset_actor(actor: int) -> void:
	move_heading[actor] = Vector2.RIGHT
	hook_ends[actor] = 0


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


## Where a dash, teleport or hook ended: the carrier's end point. Its `blast` and its `on expire`
## payload happen there. A move whose build has been forgotten does nothing.
func finished(actor: int, mode: StringName, position: Vector2, tag: int) -> void:
	if mode != &"dash" and mode != &"teleport" and mode != &"hook":
		return
	if not SpellTag.is_spell_tag(tag) or actor != SpellTag.caster_of(tag) or not position.is_finite():
		return
	if mode == &"hook" and hook_ends[actor] == 0:
		return
	# The caster's body moved, so it casts what its end point fires.
	end(tag, position, move_heading[actor], SpellRuntime.CASTER_WIZARD)


## `shield` on a move, one rule for every spell that moves its caster (dash, teleport, hook, swap;
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
