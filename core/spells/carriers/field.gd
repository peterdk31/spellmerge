class_name CarrierField
extends Carrier
## A field (`&"field"`; docs/milestones/field.md): a circle on the floor `ray_length` ahead (short of a
## wall) that hits nothing and stops nothing; every shot that comes into it takes its cards (the
## owner, 2026-11-26), anyone's: a teammate's, an enemy's, its caster's own (the owner's answer of
## 2026-11-25, one rule). Its numbers shape it (Bigger, Reach, Slow, Growth); its infusions and its
## behaviours are what it gives.
##
## It is a still shot of the projectile manager (as a rune and a pool are), marked a field
## (`set_field`), so its life, Hold, Split, Orbit, its triggers and its end are the shots' own. Each
## step the manager's field pass (`shots_into_fields`, natively `ShotKernel.field_pass`) hands back the
## shots whose middle came into a field's circle, and this carrier gives them its cards: "at least the
## field's", so taking the same field again changes nothing, and fields of other cards stack. Its
## Linger is the dam: a shot that comes in is held where it is (a local stop, its life waiting) until
## the field ends, and let go at once if the field ends early.

## How far short of a wall a field cast at one lies (pixels).
const WALL_GAP: float = 2.0

## Not state: scratch, refilled before every use (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_fields_now"]

## The live fields: each one's slot and its shot's birth (`ProjectileManager.get_seq_of`), in the order
## they were cast. A row whose slot ended, or holds another shot, is dropped at the next step.
var _fd_slot: PackedInt32Array = PackedInt32Array()
var _fd_seq: PackedInt64Array = PackedInt64Array()
## The shots a field holds (its Linger): each one's slot and birth, and the birth of the field's shot.
var _hd_slot: PackedInt32Array = PackedInt32Array()
var _hd_seq: PackedInt64Array = PackedInt64Array()
var _hd_field: PackedInt64Array = PackedInt64Array()

var _fields_now: PackedInt32Array = PackedInt32Array()


func id() -> StringName:
	return &"field"


## What draws its look: its shot stands still, one quad (its card's `look_shader`).
func look_drawer() -> int:
	return LOOK_STILL


## It stays where it is cast for its life (Slow keeps it longer), Reach puts it further, Split makes
## more of them, fanned; it hits nothing, does not travel and meets no shot itself. What it gives
## (GIVES) is what a behaviour's need names it for (`ModifierBase.RULES`).
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


## What comes into it takes its infusion (as through a portal), so an infusion counts on it
## although it hits nothing.
func takes_infusion(_blasts: bool) -> bool:
	return true


## What comes into it takes an infusion's element and status, not its heal: an infusion with no
## status (mend) counts only when a blast carries it.
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
	_fd_slot.append(slot)
	_fd_seq.append(seq)
	if kit.events != null:
		var lies: Vector2 = kit.projectiles.get_position_of(slot)
		kit.set_cue_tag(tag)
		kit.events.carrier_shown.emit(actor, spell.carrier_card_id, lies, heading, spell.radius, spell.tint, spell.look)
		kit.set_cue_tag(0)
	return made


## Its still shot `ray_length` ahead of `origin` along `heading`, short of a wall, hitting nothing
## (no hit layers) and never spent.
func spawn_row(spell: CompiledSpell, _tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, lifetime: float) -> int:
	var to: Vector2 = origin + heading * spell.ray_length
	var clipped: Vector2 = kit.projectiles.grid().clip_to_walls(origin, to)
	if not clipped.is_equal_approx(to):
		# Short of the wall, never on it (a shot in a wall ends).
		clipped -= heading * minf(WALL_GAP, origin.distance_to(clipped))
	var at: Vector2 = kit.on_floor(spell, clipped)
	var slot: int = kit.projectiles.spawn(actor, at, Vector2.ZERO, lifetime, spell.radius, 0, SpellRuntime.PIERCE_ALL, _tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	kit.projectiles.set_facing(slot, heading)
	return slot


# --- Each step ---------------------------------------------------------------------------------

## The fields that ended are dropped (their held shots let go); every shot that came into a field in
## the manager's last step takes its cards.
func step(_delta: float) -> void:
	if _fd_slot.is_empty():
		return
	_drop_ended()
	if _fd_slot.is_empty():
		return
	# The rows as the pass reads them (a field given to below may not end one, but stay safe).
	_fields_now.resize(_fd_slot.size())
	for n in _fd_slot.size():
		_fields_now[n] = _fd_slot[n]
	var found: int = kit.projectiles.shots_into_fields(_fields_now, _fields_now.size())
	for i in found:
		var row: int = kit.projectiles.field_of(i)
		_give(kit.projectiles.field_shot(i), _fields_now[row], _fd_seq[row])


## Every row whose field ended (its slot dead or holding another shot) goes, and the shots it held
## are let go.
func _drop_ended() -> void:
	var i: int = 0
	while i < _fd_slot.size():
		var slot: int = _fd_slot[i]
		if kit.projectiles.is_alive(slot) and kit.projectiles.get_seq_of(slot) == _fd_seq[i]:
			i += 1
			continue
		_let_go(_fd_seq[i])
		_fd_slot.remove_at(i)
		_fd_seq.remove_at(i)


## The shots the field born `field_seq` holds are let go (a local stop ended early).
func _let_go(field_seq: int) -> void:
	var i: int = 0
	while i < _hd_slot.size():
		if _hd_field[i] != field_seq:
			i += 1
			continue
		var shot: int = _hd_slot[i]
		var seq: int = _hd_seq[i]
		_hd_slot.remove_at(i)
		_hd_seq.remove_at(i)
		_hd_field.remove_at(i)
		if kit.projectiles.is_alive(shot) and kit.projectiles.get_seq_of(shot) == seq:
			kit.projectiles.release_shot(shot)
			# Another dam that holds it still does, for its own life left.
			var left: float = _held_by_another(shot, seq)
			if left > 0.0:
				kit.projectiles.freeze_shot(shot, left)


## The longest life left of a live field that holds the shot `shot` (born `seq`), 0 for none.
func _held_by_another(shot: int, seq: int) -> float:
	var left: float = 0.0
	for h in _hd_slot.size():
		if _hd_slot[h] != shot or _hd_seq[h] != seq:
			continue
		var row: int = _fd_seq.find(_hd_field[h])
		if row < 0:
			continue
		var field: int = _fd_slot[row]
		if kit.projectiles.is_alive(field) and kit.projectiles.get_seq_of(field) == _hd_field[h]:
			left = maxf(left, kit.projectiles.get_life_of(field))
	return left


## The shot in `shot` came into the field in `field_slot` (born `field_seq`): it takes the field's
## cards, at least the field's of each (what it has of one already stays), and shows it.
func _give(shot: int, field_slot: int, field_seq: int) -> void:
	var manager := kit.projectiles
	if not manager.is_alive(shot):
		return
	var field: CompiledSpell = kit.spell_of(manager.get_tag_of(field_slot))
	if field == null:
		return
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
	var sticky: float = field.behaviour(ModifierBase.Behaviour.STICKY)
	if sticky > manager.get_sticky_of(shot):
		manager.set_sticky(shot, sticky)
	var shield: int = roundi(field.behaviour(ModifierBase.Behaviour.SHIELD))
	if shield > manager.get_shield_of(shot):
		manager.set_shield(shot, shield)
	if field.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0 and not manager.is_deflecting(shot):
		manager.set_deflect(shot, true)
	if field.behaviour(ModifierBase.Behaviour.LINGER) > 0.0:
		_hold(shot, field_slot, field_seq)
	_shown(shot, field_slot, field)


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


## The dam: the shot in `shot` is held where it is until the field ends (its life left; let go
## earlier if the field ends early: `_drop_ended`).
func _hold(shot: int, field_slot: int, field_seq: int) -> void:
	var left: float = kit.projectiles.get_life_of(field_slot)
	if not (left > 0.0) or not kit.projectiles.freeze_shot(shot, left):
		return
	_hd_slot.append(shot)
	_hd_seq.append(kit.projectiles.get_seq_of(shot))
	_hd_field.append(field_seq)


## A shot took the field: its look where it is (`field_through`, a cue).
func _shown(shot: int, field_slot: int, field: CompiledSpell) -> void:
	if kit.events == null:
		return
	var way: Vector2 = kit.projectiles.get_velocity_of(shot)
	kit.events.cue_shown.emit(SpellTag.caster_of(kit.projectiles.get_tag_of(field_slot)), &"field_through", kit.projectiles.get_position_of(shot), way.normalized() if not way.is_zero_approx() else Vector2.RIGHT, kit.projectiles.get_radius_of(shot), field.tint, 0)


# --- Its end -------------------------------------------------------------------------------------

## Every field gone at once (`Spells.clear`): their shots go with the manager's.
func clear() -> void:
	_fd_slot.resize(0)
	_fd_seq.resize(0)
	_hd_slot.resize(0)
	_hd_seq.resize(0)
	_hd_field.resize(0)


# --- For the looks and the tests --------------------------------------------------------------

## The fields of the runtime `spells` (its bound `field` carrier), for what reads its own getters.
static func of(spells: SpellRuntime) -> CarrierField:
	return spells.carrier(&"field") as CarrierField


## How many fields are open now, and how many shots they hold.
func field_count() -> int:
	return _fd_slot.size()


func held_count() -> int:
	return _hd_slot.size()


## The slot of open field `n` (in the order they were cast).
func field_slot(n: int) -> int:
	return _fd_slot[n]
