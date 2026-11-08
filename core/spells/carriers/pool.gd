class_name CarrierPool
extends Carrier
## A pool (`&"pool"`): a still patch spread on the floor `ray_length` ahead (short of a wall) that
## strikes every body standing in it, again every `SpellLimits.POOL_TICK` while it lives, so its
## infusion keeps the status on whatever stays (a fire pool keeps burning, a frost slick keeps
## chilling, a mend spring keeps healing). Its hits never spend it. Homing makes it creep toward a
## target, as a rune does.
##
## Its rows: the live pools' slots (with their birth, `seq`) and the time to each one's next tick.
## A row whose slot has ended, or holds another shot, is dropped at its next step.

var _pl_slot: PackedInt32Array = PackedInt32Array()
var _pl_seq: PackedInt64Array = PackedInt64Array()
var _pl_clock: PackedFloat32Array = PackedFloat32Array()


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
	if made > 0 and kit.projectiles.is_alive(slot) and kit.projectiles.get_seq_of(slot) == seq:
		_pl_slot.append(slot)
		_pl_seq.append(seq)
		_pl_clock.append(SpellLimits.POOL_TICK)
	return made


func spawn_row(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, lifetime: float) -> int:
	var reach: float = spell.ray_length if spell.ray_length > 0.0 else SpellLimits.POOL_REACH
	var at: Vector2 = kit.projectiles.clip_to_walls(origin, origin + heading * reach)
	return kit.projectiles.spawn(actor, at, Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, SpellRuntime.PIERCE_ALL, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)


## Every live pool's clock runs on by `delta`; one whose tick is due forgets the bodies it touches,
## so the manager's next step strikes each of them again.
func step(delta: float) -> void:
	var i: int = 0
	while i < _pl_slot.size():
		var slot: int = _pl_slot[i]
		if not kit.projectiles.is_alive(slot) or kit.projectiles.get_seq_of(slot) != _pl_seq[i]:
			_drop(i)
			continue
		_pl_clock[i] -= delta
		if _pl_clock[i] <= 0.0:
			_pl_clock[i] += SpellLimits.POOL_TICK
			kit.projectiles.forget_hits(slot)
		i += 1


## Takes row `i` off (the last row takes its place).
func _drop(i: int) -> void:
	var last: int = _pl_slot.size() - 1
	_pl_slot[i] = _pl_slot[last]
	_pl_seq[i] = _pl_seq[last]
	_pl_clock[i] = _pl_clock[last]
	_pl_slot.resize(last)
	_pl_seq.resize(last)
	_pl_clock.resize(last)


## Every pool gone at once (`Spells.clear`): their shots go with the manager's.
func clear() -> void:
	_pl_slot.resize(0)
	_pl_seq.resize(0)
	_pl_clock.resize(0)


## How many pools tick, for tests.
func pool_count() -> int:
	return _pl_slot.size()


func reach_of(spell: CompiledSpell) -> float:
	return (spell.ray_length if spell.ray_length > 0.0 else SpellLimits.POOL_REACH) + spell.radius
