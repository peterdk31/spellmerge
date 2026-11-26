class_name CarrierField
extends Carrier
## A field (`&"field"`; docs/milestones/field.md; the owner's design of 2026-11-26): a round field on
## the floor `ray_length` ahead (short of a wall) with a trembling edge. Every shot that comes into it,
## anyone's (a teammate's, an enemy's, its caster's own: one rule), is pulled in to its middle and held
## there, and the field grows with every shot it holds. When it ends it lets them all go at once, one
## burst from its middle, each the way it was going when it came in (a shot that came in from the west
## going east leaves to the east), and each takes the field's cards as it leaves: its infusion, its
## homing and its behaviours (a fire field's burst is fire). Its numbers shape the field itself
## (Bigger, Reach, Slow, Growth).
##
## It is a still shot of the projectile manager that hits nothing (`set_field`), so its life, Hold,
## Split, Orbit, its triggers and its end are the shots' own. Each step the manager's field pass
## (`shots_into_fields`, natively `ShotKernel.field_pass`) hands back the shots that came into a field;
## this carrier holds each (a local stop: its life waits), keeping only the way it came in, in WAYS
## steps (no position), and draws it in toward the middle step by step. A field holds as many as come
## (the owner, 2026-11-26: "No limits"); its rows grow by doubling (Packed arrays), never a step's
## allocation once grown, and its burst and its drawing in walk them once.
## How many ways a held shot's way in is kept to (a byte: 32 steps round).
const WAYS: int = 32
## Pixels a field's radius grows with each shot it takes, with no most (the owner: "No limits"; the
## manager keeps any shot's radius within the room, `set_field_radius`).
const GROW_PER_SHOT: float = 1.5
## A held shot is drawn in to the middle by this share of the way left each step.
const DRAW_IN: float = 0.2
## The most shots a burst lets go in one step (the owner, 2026-11-26: a big burst may take a few
## ticks): a field holding more lets them go over the next steps, in the order it caught them, all
## from its middle, so it still reads as one burst. About 1 ms of a step at this count
## (`tests/core/test_field_budget.gd`).
const BURST_PER_STEP: int = 200
## How far short of a wall a field cast at one lies (pixels).
const WALL_GAP: float = 2.0

## Not state: scratch, refilled before every use (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_fields_now"]

## The live fields: each one's slot, its shot's birth (`ProjectileManager.get_seq_of`), its spell
## (what its burst gives), where its middle is (kept each step, for the burst after its shot is
## gone), its card's radius, how many shots it holds (for its burst's look) and whether it is
## bursting, in the order they were cast. A row whose slot ended, or holds another shot, bursts from
## the next step on (BURST_PER_STEP shots a step) and is dropped once it holds none.
var _fd_slot: PackedInt32Array = PackedInt32Array()
var _fd_seq: PackedInt64Array = PackedInt64Array()
var _fd_spell: Array[CompiledSpell] = []
var _fd_at: PackedVector2Array = PackedVector2Array()
var _fd_radius: PackedFloat32Array = PackedFloat32Array()
var _fd_held: PackedInt32Array = PackedInt32Array()
var _fd_bursting: PackedByteArray = PackedByteArray()
## The held shots: each one's slot and birth, the birth of the field that holds it, and the way it
## came in (0 to WAYS - 1, round from east).
var _hd_slot: PackedInt32Array = PackedInt32Array()
var _hd_seq: PackedInt64Array = PackedInt64Array()
var _hd_field: PackedInt64Array = PackedInt64Array()
var _hd_way: PackedByteArray = PackedByteArray()

var _fields_now: PackedInt32Array = PackedInt32Array()


func id() -> StringName:
	return &"field"


## What draws its look: its shot stands still, one quad (its card's `look_shader`).
func look_drawer() -> int:
	return LOOK_STILL


## It stays where it is cast for its life (Slow keeps it longer), Reach puts it further, Split makes
## more of them, fanned; it hits nothing and does not travel. What it gives (GIVES) is what a
## behaviour's need names it for (`ModifierBase.RULES`).
func traits() -> int:
	return STAYS | LASTS | REACHES | SHOTS | SPREAD | CASTS_FROM_SHOT | GIVES


## After the shots (the projectile manager's step) and the portals: it reads where each shot was
## before the step and is now.
func step_order() -> int:
	return 5


func required_fields() -> Dictionary:
	return {
		"ray_length": "A field needs a `ray_length` above 0 (how far ahead it lies).",
		"radius": "A field needs a `radius` above 0 (how big its circle is).",
	}


## What leaves it takes its infusion (as what leaves a portal), so an infusion counts on it although
## it hits nothing.
func takes_infusion(_blasts: bool) -> bool:
	return true


## What leaves it takes an infusion's element and status, not its heal: an infusion with no status
## (mend) counts only when a blast carries it.
func takes_element(element: ElementBase, blasts: bool) -> bool:
	return blasts or element.status_id != &""


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length + spell.radius


# --- Casting -----------------------------------------------------------------------------------

## One field of the launch along `heading`: its still shot, set up as a shot (its triggers, its
## growth: `land_shot`), marked a field and joining the live ones. It touches no floor itself.
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, heading: Vector2, n: int, count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var slot: int = spawn_row(spell, tag, actor, origin, direction, heading, n, count, lifetime)
	if slot < 0:
		return 0
	var seq: int = kit.projectiles.get_seq_of(slot)
	var made: int = kit.land_shot(slot, spell, tag, source, chain, prev)
	if made <= 0 or not kit.projectiles.is_alive(slot) or kit.projectiles.get_seq_of(slot) != seq:
		return made
	kit.projectiles.set_field(slot)
	kit.projectiles.set_trail(slot, false)
	var lies: Vector2 = kit.projectiles.get_position_of(slot)
	_fd_slot.append(slot)
	_fd_seq.append(seq)
	_fd_spell.append(spell)
	_fd_at.append(lies)
	_fd_radius.append(spell.radius)
	_fd_held.append(0)
	_fd_bursting.append(0)
	if kit.events != null:
		kit.set_cue_tag(tag)
		kit.events.carrier_shown.emit(actor, spell.carrier_card_id, lies, heading, spell.radius, spell.tint, spell.look)
		kit.set_cue_tag(0)
	return made


## Its still shot `ray_length` ahead of `origin` along `heading`, short of a wall, hitting nothing
## (no hit layers, `set_field`) and never spent.
func spawn_row(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, lifetime: float) -> int:
	var to: Vector2 = origin + heading * spell.ray_length
	var clipped: Vector2 = kit.projectiles.grid().clip_to_walls(origin, to)
	if not clipped.is_equal_approx(to):
		# Short of the wall, never on it (a shot in a wall ends).
		clipped -= heading * minf(WALL_GAP, origin.distance_to(clipped))
	var at: Vector2 = kit.on_floor(spell, clipped)
	var slot: int = kit.projectiles.spawn(actor, at, Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, SpellRuntime.PIERCE_ALL, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	kit.projectiles.set_facing(slot, heading)
	return slot


# --- Each step ---------------------------------------------------------------------------------

## The fields that ended burst (their held shots go); the held shots are drawn in; every shot that
## came into a field in the manager's last step is held.
func step(_delta: float) -> void:
	if _fd_slot.is_empty():
		return
	_burst_ended()
	if _fd_slot.is_empty():
		return
	for n in _fd_slot.size():
		if _fd_bursting[n] == 0:
			_fd_at[n] = kit.projectiles.get_position_of(_fd_slot[n])
	_draw_in()
	# A bursting field catches nothing more (its slot may hold another shot already).
	_fields_now.resize(_fd_slot.size())
	for n in _fd_slot.size():
		_fields_now[n] = _fd_slot[n] if _fd_bursting[n] == 0 else -1
	var found: int = kit.projectiles.shots_into_fields(_fields_now, _fields_now.size())
	for i in found:
		_take(kit.projectiles.field_shot(i), kit.projectiles.field_of(i))


## Every row whose field ended (its slot dead or holding another shot) bursts: from its middle as it
## was, BURST_PER_STEP of its shots a step, until it holds none and goes.
func _burst_ended() -> void:
	var i: int = 0
	while i < _fd_slot.size():
		if _fd_bursting[i] == 0:
			var slot: int = _fd_slot[i]
			if kit.projectiles.is_alive(slot) and kit.projectiles.get_seq_of(slot) == _fd_seq[i]:
				i += 1
				continue
			_fd_bursting[i] = 1
			_burst_look(i)
		if _burst(i, BURST_PER_STEP) > 0:
			i += 1
			continue
		_fd_slot.remove_at(i)
		_fd_seq.remove_at(i)
		_fd_spell.remove_at(i)
		_fd_at.remove_at(i)
		_fd_radius.remove_at(i)
		_fd_held.remove_at(i)
		_fd_bursting.remove_at(i)


## The shot `shot` came into field row `row`: held where it is (its life waits until the burst),
## keeping the way it was going; the field grows.
func _take(shot: int, row: int) -> void:
	var manager := kit.projectiles
	if not manager.is_alive(shot):
		return
	var field: int = _fd_slot[row]
	if not manager.freeze_shot(shot, manager.get_life_of(field) + 1.0):
		return
	var at: Vector2 = manager.get_position_of(shot)
	var going: Vector2 = manager.get_velocity_of(shot)
	if going.is_zero_approx():
		going = at.direction_to(_fd_at[row]) if not at.is_equal_approx(_fd_at[row]) else Vector2.RIGHT
	_hd_slot.append(shot)
	_hd_seq.append(manager.get_seq_of(shot))
	_hd_field.append(_fd_seq[row])
	_hd_way.append(posmod(roundi(DMath.angle(going) / TAU * float(WAYS)), WAYS))
	_fd_held[row] += 1
	manager.set_field_radius(field, manager.get_radius_of(field) + GROW_PER_SHOT)
	_shown(&"field_through", at, going, manager.get_radius_of(shot), field)


## Every held shot of a field that is not bursting moves DRAW_IN of the way left to its field's middle
## (it is held, so it hits nothing on the way).
func _draw_in() -> void:
	var manager := kit.projectiles
	for h in _hd_slot.size():
		var row: int = _fd_seq.find(_hd_field[h])
		if row < 0 or _fd_bursting[row] != 0:
			continue
		var shot: int = _hd_slot[h]
		if not manager.is_alive(shot) or manager.get_seq_of(shot) != _hd_seq[h]:
			continue
		var at: Vector2 = manager.get_position_of(shot)
		var to: Vector2 = at.lerp(_fd_at[row], DRAW_IN)
		if to.distance_squared_to(_fd_at[row]) < 0.25:
			to = _fd_at[row]
		if to != at:
			manager.pass_shot(shot, to, manager.get_velocity_of(shot))


## Field row `row` lets go of up to `most` of the shots it holds, the first it caught first: each
## leaves from its middle the way it came in, at the speed it had, and takes the field's cards
## (`_give`). Returns how many it still holds. The held rows are walked once, the rest kept in their
## order.
func _burst(row: int, most: int) -> int:
	var manager := kit.projectiles
	var spell: CompiledSpell = _fd_spell[row]
	var at: Vector2 = _fd_at[row]
	var released: int = 0
	var left: int = 0
	var kept: int = 0
	for h in _hd_slot.size():
		if _hd_field[h] != _fd_seq[row] or released >= most:
			if _hd_field[h] == _fd_seq[row]:
				left += 1
			_hd_slot[kept] = _hd_slot[h]
			_hd_seq[kept] = _hd_seq[h]
			_hd_field[kept] = _hd_field[h]
			_hd_way[kept] = _hd_way[h]
			kept += 1
			continue
		var shot: int = _hd_slot[h]
		if not manager.is_alive(shot) or manager.get_seq_of(shot) != _hd_seq[h]:
			continue
		var way: Vector2 = DMath.from_angle(float(_hd_way[h]) * TAU / float(WAYS))
		var speed: float = manager.get_velocity_of(shot).length()
		manager.pass_shot(shot, at + way * (manager.get_radius_of(shot) + 1.0), way * speed)
		manager.release_shot(shot)
		if spell != null:
			_give(shot, spell)
		released += 1
	_hd_slot.resize(kept)
	_hd_seq.resize(kept)
	_hd_field.resize(kept)
	_hd_way.resize(kept)
	return left


## Field row `row` begins to burst: its look (`field_burst`), as big as it grew.
func _burst_look(row: int) -> void:
	if _fd_held[row] <= 0 or kit.events == null:
		return
	var spell: CompiledSpell = _fd_spell[row]
	var tint: Color = spell.tint if spell != null else Color.WHITE
	kit.events.cue_shown.emit(-1, &"field_burst", _fd_at[row], Vector2.RIGHT, _fd_radius[row] + GROW_PER_SHOT * float(_fd_held[row]), tint, 0)


## The shot in `shot` leaves the field of `field`: it takes the field's cards, at least the field's of
## each (what it has of one already stays).
func _give(shot: int, field: CompiledSpell) -> void:
	var manager := kit.projectiles
	if _gives_status(field.hit):
		kit.infuse_shot(shot, field.hit, field.tint)
	if field.homing_range > 0.0 and not manager.is_homing(shot):
		manager.set_homing_curve(shot, field.homing_curve, field.homing_range)
	var bounce: int = roundi(field.behaviour(ModifierBase.Behaviour.BOUNCE))
	if bounce > manager.get_bounce_of(shot):
		manager.set_bounce(shot, bounce)
	if field.behaviour(ModifierBase.Behaviour.GHOST) > 0.0:
		manager.set_ghost(shot)
	var spiral: float = field.behaviour(ModifierBase.Behaviour.SPIRAL)
	if spiral > 0.0 and not manager.has_flags(shot, SpellRuntime.ProjectilesScript.F_WAVE):
		manager.set_spiral(shot, spiral)
	if field.behaviour(ModifierBase.Behaviour.RETURN) > 0.0 and not manager.has_flags(shot, SpellRuntime.ProjectilesScript.F_RETURN):
		manager.set_return(shot)
	var linger: float = field.behaviour(ModifierBase.Behaviour.LINGER)
	if linger > 0.0:
		manager.set_linger(shot, linger)
	var sticky: float = field.behaviour(ModifierBase.Behaviour.STICKY)
	if sticky > manager.get_sticky_of(shot):
		manager.set_sticky(shot, sticky)
	var shield: int = roundi(field.behaviour(ModifierBase.Behaviour.SHIELD))
	if shield > manager.get_shield_of(shot):
		manager.set_shield(shot, shield)
	if field.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0 and not manager.is_deflecting(shot):
		manager.set_deflect(shot, true)


## True when `hit` has an element with a status to give (what a shot takes of a field's infusions:
## mend, which has none, it does not take, as through a portal).
static func _gives_status(hit: HitProfile) -> bool:
	if hit == null or hit.element_ids.is_empty():
		return false
	if hit.status_id != &"":
		return true
	for id: StringName in hit.later_status_ids:
		if id != &"":
			return true
	return false


## A moment of the field's at `at` (a cue): a shot taken in.
func _shown(cue: StringName, at: Vector2, way: Vector2, size: float, field_slot: int) -> void:
	if kit.events == null:
		return
	var field: CompiledSpell = kit.spell_of(kit.projectiles.get_tag_of(field_slot))
	var tint: Color = field.tint if field != null else Color.WHITE
	kit.events.cue_shown.emit(SpellTag.caster_of(kit.projectiles.get_tag_of(field_slot)), cue, at, way.normalized() if not way.is_zero_approx() else Vector2.RIGHT, size, tint, 0)


# --- Its end -------------------------------------------------------------------------------------

## Every field gone at once (`Spells.clear`): their shots go with the manager's.
func clear() -> void:
	_fd_slot.resize(0)
	_fd_seq.resize(0)
	_fd_spell.clear()
	_fd_at.resize(0)
	_fd_radius.resize(0)
	_fd_held.resize(0)
	_fd_bursting.resize(0)
	_hd_slot.resize(0)
	_hd_seq.resize(0)
	_hd_field.resize(0)
	_hd_way.resize(0)


# --- For the looks and the tests --------------------------------------------------------------

## The fields of the runtime `spells` (its bound `field` carrier), for what reads its own getters.
static func of(spells: SpellRuntime) -> CarrierField:
	return spells.carrier(&"field") as CarrierField


## How many fields are open now (a bursting one counts until it has let all its shots go), and how
## many shots they hold.
func field_count() -> int:
	return _fd_slot.size()


func held_count() -> int:
	return _hd_slot.size()


## The slot of open field `n` (in the order they were cast).
func field_slot(n: int) -> int:
	return _fd_slot[n]
