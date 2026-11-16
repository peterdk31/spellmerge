class_name CarrierSpray
extends Carrier
## A spray (`&"spray"`; the owner, 2026-11-16: the jet's own carrier, "a held hose"): a jet of the
## spell poured out of the staff, striking every body in a narrow cone along its heading out to its
## `ray_length` (a wall hides what is behind it), pushed outward from the hand. Over at once, and
## cast again each time the staff is ready while its button is held (the caster's hold), so held
## it pours on, paying its mana as it goes. Where its cone ends (short of a wall) is its end point:
## its `blast` and `on expire` payload go off there (a pool there paints the floor where it is
## pointed). Its look is told for Feel (`carrier_shown` with its card's id, from the hand along its
## heading as far as it reaches: its card's `shown_cue`, a jet).
##
## Its cone's width is its card's `arc` (degrees across, centred on its heading). It keeps no rows:
## everything it does is done as it is cast.

## Not state: the bodies one cast has struck, emptied at its start and done with as it ends
## (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_struck"]

var _struck: Array = []


func id() -> StringName:
	return &"spray"


## What draws its look: no shot of its own (its jet is a cue, `carrier_shown`).
func look_drawer() -> int:
	return LOOK_NONE


## It hits, reach lengthens it, it is held by the hand that casts it (never hitting that body), and
## a launch's shots fan out and turn by the staff's spread.
func traits() -> int:
	return HITS | REACHES | MELEE | SHOTS | SPREAD


func required_fields() -> Dictionary:
	return {
		"ray_length": "A spray needs a `ray_length` (how far it reaches) above 0.",
		"arc": "A spray needs an `arc` (degrees its cone spans) above 0.",
	}


## One jet of the launch along `heading`: its cone struck from `origin` at once, its end point's
## blast and `on expire` payload, and its look told.
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, _lifetime: float, chain: int, prev: int) -> int:
	if not origin.is_finite() or not heading.is_finite() or heading.is_zero_approx():
		return 0
	var reach: float = spell.ray_length
	var end: Vector2 = kit.projectiles.clip_to_walls(origin, origin + heading * reach)
	var got: float = origin.distance_to(end)
	if kit.events != null:
		kit.events.carrier_shown.emit(actor, spell.carrier_card_id, origin, heading, got, spell.tint, spell.look)
	# Its build is kept while it pours (what its hits set off may read it).
	kit.shot_started(tag)
	var half: float = deg_to_rad(spell.arc) * 0.5
	var spare: Node = kit.spared(spell, source if is_instance_valid(source) else null)
	var found: int = kit.projectiles.sweep(actor, origin, heading, 1, -half, half, reach, SpellRuntime.HITS, spare)
	_struck.clear()
	if found > 0:
		kit.strike(spell, tag, actor, found, _struck, origin, chain, prev, spell.echo_hit if kit.is_echo(spell) else null)
	_struck.clear()
	kit.blast(spell, tag, actor, end)
	if spell.fires_on(TriggerBase.Event.EXPIRE):
		kit.fire_payloads(spell, TriggerBase.Event.EXPIRE, tag, actor, end, heading, null)
	kit.shot_ended(tag)
	return 1


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length
