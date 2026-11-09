class_name Skyfall
extends RefCounted
## Skyfall, the falling modifier (owner, 2026-11-09; docs/milestones/carrier-modifiers.md Part 2): a
## hole opens a little up the screen from where it is cast and, after a moment, the carrier is cast from
## it straight down the screen, onto the floor line through the spot. Its shots are in the air until
## they near that line (`Projectiles.set_floor`: they touch nothing up there) and end at it; a placed
## carrier (a rune, a pool, a wall, a decoy...) lands on the line after a streak from the sky; and
## whatever a falling shot casts falls to the same line.
##
## All of the modifier is here. The runtime calls it at the places marked "Skyfall": `_cast_once`
## and `_penta` (a cast that falls opens its hole instead of leaving), `_run_pending` (the hole has
## opened: it falls), `_land_shots` (every shot a carrier makes) and `_placed_at` with the kit's
## `on_floor` (every carrier that is placed); `_drop_pending` lets go of a fall that never falls. Taking it out again is this file, the card folder, those
## calls, and `set_floor` in the projectile manager.

## Not state: the runtime's kit, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_kit"]

var _kit: CarrierKit = null
## The fall being cast now: its floor line's y (INF between casts) and its actor (set only by `begin`).
var _floor: float = INF
var _actor: int = -1


func _init(kit: CarrierKit) -> void:
	_kit = kit


## True when `spell` falls: it has the card, and the card does something on its carrier.
func falls(spell: CompiledSpell) -> bool:
	return Skyfall.falls_on(spell, _kit.carrier_of(spell))


## `falls` for a spell on `carrier` (CastSense asks it with no runtime).
static func falls_on(spell: CompiledSpell, carrier: Carrier) -> bool:
	return spell.behaviour(ModifierBase.Behaviour.SKYFALL) > 0.0 and carrier.works(ModifierBase.Behaviour.SKYFALL)


## The spot a cast from `origin` falls onto: where what casts it is now (owner, 2026-11-09: "It
## should just open up on the spot it is cast from, like over the player, or above a projectile with
## on_hit skyfall"). No card moves it: homing steers the falling carrier, as on any carrier.
func spot_of(actor: int, origin: Vector2) -> Vector2:
	return _kit.caster_place(actor, origin)


## Opens the hole over `spot` (its look, the card's `shown_cue`) and queues the fall, cast by the hole
## (a point) after SpellLimits.SKYFALL_SECONDS. A point spares no body: whoever stands under it when
## it lands is hit, its caster too (owner: "This is just following the general rule"). While it
## waits it counts as a live shot of `tag`, as an entity asked for does, so it is a carrier like any
## other: a `hold` on it starts at the cast (its mana kept, the next press calls it off), and when
## it falls what it makes carries the hold on by its own rule (`Spells._run_pending`). Returns 1:
## the cast has gone.
func open(spell: CompiledSpell, tag: int, actor: int, spot: Vector2) -> int:
	var hole: Vector2 = spot + Vector2.UP * SpellLimits.SKYFALL_HEIGHT
	var cue: StringName = spell.cue_of(ModifierBase.Behaviour.SKYFALL)
	if _kit.events != null and cue != &"":
		_kit.set_cue_tag(tag)
		_kit.events.cue_shown.emit(actor, cue, hole, Vector2.DOWN, SpellLimits.SKYFALL_SECONDS, spell.tint, spell.look)
		_kit.set_cue_tag(0)
	_kit.cast_as(SpellRuntime.CASTER_POINT, 0)
	var launch: SpellRuntime.PendingLaunch = _kit.delay(SpellLimits.SKYFALL_SECONDS, null, spell, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), hole, Vector2.DOWN, null, false)
	_kit.cast_done()
	launch.echoed = _kit.is_echo(spell)
	launch.fall_floor = spot.y
	_kit.shot_started(tag)
	return 1


## The fall's cast begins (`Spells._run_pending`): what `actor` makes now knows the floor line `floor_y`.
func begin(floor_y: float, actor: int) -> void:
	_floor = floor_y
	_actor = actor


## The fall's cast is over.
func end() -> void:
	_floor = INF
	_actor = -1


## The floor line now: the fall being cast, else that of the falling shot casting a payload (what an
## airborne shot casts falls too, owner); INF for none.
func floor_now() -> float:
	if is_finite(_floor):
		return _floor
	var shot: int = _kit.caster_shot()
	return _kit.projectiles.get_floor_of(shot) if shot >= 0 else INF


## Every shot of a launch made while something falls falls onto its floor line.
func land_shots(slots: PackedInt32Array, count: int) -> void:
	var floor_y: float = floor_now()
	if not is_finite(floor_y):
		return
	for n in count:
		if slots[n] >= 0:
			_kit.projectiles.set_floor(slots[n], floor_y)


## Whose fall it is: the fall being cast, else the falling shot casting a payload.
func _falling_actor() -> int:
	if is_finite(_floor):
		return _actor
	var shot: int = _kit.caster_shot()
	return _kit.projectiles.get_actor_of(shot) if shot >= 0 else -1


## Where a carrier placed at `point` goes: there, or, while something falls, on the floor line below
## it, after a streak from the sky down to it (a look only, the chain jump's ray).
func on_floor(spell: CompiledSpell, point: Vector2) -> Vector2:
	var floor_y: float = floor_now()
	if not is_finite(floor_y) or not point.is_finite():
		return point
	var actor: int = _falling_actor()
	var at := Vector2(point.x, floor_y)
	var from: Vector2 = at + Vector2.UP * maxf(SpellLimits.SKYFALL_HEIGHT, floor_y - point.y)
	if _kit.events != null:
		_kit.events.form_shown.emit(actor, SpellRuntime.RAY_FORM, from, Vector2.DOWN, at.y - from.y, spell.tint, spell.look)
	return at
