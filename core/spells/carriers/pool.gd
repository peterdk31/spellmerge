class_name CarrierPool
extends Carrier
## A pool (`&"pool"`): a still patch spread on the floor `ray_length` ahead (short of a wall) that
## strikes every body standing in it, again every `SpellLimits.POOL_TICK` while it lives, so its
## infusion keeps the status on whatever stays (a fire pool keeps burning, a frost slick keeps
## chilling, a mend spring keeps healing). Its hits never spend it. Homing makes it creep toward a
## target, as a rune does.
##
## It is thrown out of the staff and lies where it lands (the owner, 2026-11-16): for
## `SpellLimits.POOL_LAND` seconds it is in the air, held (`freeze_shot`: it hits nothing, its life
## waits), and it touches the floor only once it lands.
##
## Its rows: the live pools' slots (with their birth, `seq`), the time to each one's next tick, the
## time until it lands (0 once it has) and whose it is.
## A row whose slot has ended, or holds another shot, is dropped at its next step.

var _pl_slot: PackedInt32Array = PackedInt32Array()
var _pl_seq: PackedInt64Array = PackedInt64Array()
var _pl_clock: PackedFloat32Array = PackedFloat32Array()
var _pl_land: PackedFloat32Array = PackedFloat32Array()
## The actor whose pool it is, as it was cast (its touches of the floor name it).
var _pl_actor: PackedInt32Array = PackedInt32Array()


func id() -> StringName:
	return &"pool"


## What draws its look: its shots stand still, one quad each.
func look_drawer() -> int:
	return LOOK_STILL


func traits() -> int:
	return STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | SPREAD | OUTWARD | MEETS_SHOTS | CASTS_FROM_SHOT


## After the shots (the projectile manager's) and the other rows: a tick only clears what a pool
## remembers, for the manager's next step.
func step_order() -> int:
	return 6


## One pool of the launch along `heading`: spread `ray_length` (or `SpellLimits.POOL_REACH`) ahead
## of `origin`, short of a wall, never spent by a hit; its row joins the ticking pools.
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, heading: Vector2, n: int, count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var slot: int = spawn_row(spell, tag, actor, origin, direction, heading, n, count, lifetime)
	if slot < 0:
		return 0
	var seq: int = kit.projectiles.get_seq_of(slot)
	var made: int = kit.land_shot(slot, spell, tag, source, chain, prev)
	if made > 0 and kit.projectiles.is_alive(slot):
		# Spat out of the staff to where it lies, for looks (its `shown_cue`: the liquid flying out
		# as far as the pool, landing as it splashes in).
		var lies: Vector2 = kit.projectiles.get_position_of(slot)
		kit.set_cue_tag(tag)
		kit.events.carrier_shown.emit(actor, spell.carrier_card_id, origin, origin.direction_to(lies) if lies != origin else heading, origin.distance_to(lies), spell.tint, spell.look)
		kit.set_cue_tag(0)
	if made > 0 and kit.projectiles.is_alive(slot) and kit.projectiles.get_seq_of(slot) == seq:
		_pl_slot.append(slot)
		_pl_seq.append(seq)
		# Its first strike is as it lands (the manager's, once it is no longer held), so its ticks
		# count from then.
		_pl_clock.append(SpellLimits.POOL_LAND + SpellLimits.POOL_TICK)
		_pl_land.append(SpellLimits.POOL_LAND)
		_pl_actor.append(actor)
	return made


func spawn_row(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, lifetime: float) -> int:
	var reach: float = spell.ray_length if spell.ray_length > 0.0 else SpellLimits.POOL_REACH
	var at: Vector2 = kit.on_floor(spell, kit.projectiles.clip_to_walls(origin, origin + heading * reach))
	var slot: int = kit.projectiles.spawn(actor, at, Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, SpellRuntime.PIERCE_ALL, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	# Spat out ahead: its look spills and splashes the way it was thrown; in the air until it lands.
	kit.projectiles.set_facing(slot, heading)
	kit.projectiles.freeze_shot(slot, SpellLimits.POOL_LAND)
	return slot


## Every live pool's clock runs on by `delta`; one whose tick is due forgets the bodies it touches,
## so the manager's next step strikes each of them again.
func step(delta: float) -> void:
	var i: int = 0
	while i < _pl_slot.size():
		var slot: int = _pl_slot[i]
		if not kit.projectiles.is_alive(slot) or kit.projectiles.get_seq_of(slot) != _pl_seq[i]:
			_drop(i)
			continue
		if _pl_land[i] > 0.0:
			_pl_land[i] -= delta
			if _pl_land[i] <= 0.0:
				# It lands: its elements touch the floor where it lies (ground cover GC5), and
				# again on each tick.
				_pl_land[i] = 0.0
				_touch(slot, _pl_actor[i])
		_pl_clock[i] -= delta
		if _pl_clock[i] <= 0.0:
			_pl_clock[i] += SpellLimits.POOL_TICK
			kit.projectiles.forget_hits(slot)
			_touch(slot, _pl_actor[i])
		i += 1


## The pool in `slot` touches the floor where it lies now (it may creep) with its spell's elements,
## within its radius (`CarrierKit.touch_floor`).
func _touch(slot: int, actor: int) -> void:
	var spell: CompiledSpell = kit.spell_of(kit.projectiles.get_tag_of(slot))
	if spell != null:
		kit.touch_floor(spell, actor, kit.projectiles.get_position_of(slot), spell.radius)


## Takes row `i` off (the last row takes its place).
func _drop(i: int) -> void:
	var last: int = _pl_slot.size() - 1
	_pl_slot[i] = _pl_slot[last]
	_pl_seq[i] = _pl_seq[last]
	_pl_clock[i] = _pl_clock[last]
	_pl_land[i] = _pl_land[last]
	_pl_actor[i] = _pl_actor[last]
	_pl_slot.resize(last)
	_pl_seq.resize(last)
	_pl_clock.resize(last)
	_pl_land.resize(last)
	_pl_actor.resize(last)


## Every pool gone at once (`Spells.clear`): their shots go with the manager's.
func clear() -> void:
	_pl_slot.resize(0)
	_pl_seq.resize(0)
	_pl_clock.resize(0)
	_pl_land.resize(0)
	_pl_actor.resize(0)


## How many pools tick, for tests.
func pool_count() -> int:
	return _pl_slot.size()


func reach_of(spell: CompiledSpell) -> float:
	return (spell.ray_length if spell.ray_length > 0.0 else SpellLimits.POOL_REACH) + spell.radius
