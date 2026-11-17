class_name CarrierSpray
extends Carrier
## A spray (`&"spray"`; the owner, 2026-11-16: the jet's own carrier, "a held hose"): a jet of the
## spell poured out of the staff, striking every body in a narrow cone along its heading out to its
## `ray_length` past the staff tip (a wall hides what is behind it), pushed outward from the hand.
## Over at once, and cast again each time the staff is ready while its button is held (the
## caster's hold; an enemy's AI holds it too), so held it pours on, paying its mana as it goes.
## With `hold` it is switched on by one press and pours on by itself, its cast's mana reserved, until
## pressed again (as a beam is; the owner, 2026-11-16): cast anew every `wind_up` + `lifetime`
## (`REPEATS_HELD`, as a held swing sweeps back). Where its jet ends (short of a wall) is its end point: its `blast` and `on expire`
## payload go off there (a pool there paints the floor where it is pointed). Its look is told for
## Feel (`carrier_shown` with its card's id, from the staff tip along its heading as far as it
## reaches, as its spell's cue tag: its card's `shown_cue`, a jet of its cards' motes).
##
## Its cone spans its card's `arc` (degrees, centred on its heading), widened by its hit `radius`
## at its reach either side (Bigger widens it). A wizard's own cast is struck from its hand (the
## aim's pivot, as a swing and a slam are), so a body between hand and staff tip is not missed; a
## payload's from where it is cast. It keeps no rows: everything it does is done as it is cast.

## Not state: the bodies one cast has struck, emptied at its start and done with as it ends
## (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_struck"]

var _struck: Array = []


func id() -> StringName:
	return &"spray"


## Held on, it pours: only its first cast of a press winds up its staff (an enemy telegraphs once,
## then pours while it holds; the Spitter, content/enemies/spitter/).
func pours_held() -> bool:
	return true


## What draws its look: no shot of its own (its jet is a cue, `carrier_shown`).
func look_drawer() -> int:
	return LOOK_NONE


## It hits, reach lengthens it, it is held by the hand that casts it (never hitting that body), a
## launch's shots fan out and turn by the staff's spread, and held it is cast anew (`hold` keeps it
## on; an enemy's AI holds it, `ai_holds`).
func traits() -> int:
	return HITS | REACHES | MELEE | SHOTS | SPREAD | REPEATS_HELD


func required_fields() -> Dictionary:
	return {
		"ray_length": "A spray needs a `ray_length` (how far it reaches) above 0.",
		"arc": "A spray needs an `arc` (degrees its cone spans) above 0.",
	}


## Half its cone's angle (radians): its `arc`'s half, widened by its hit radius at its reach.
static func half_angle(spell: CompiledSpell) -> float:
	return deg_to_rad(spell.arc) * 0.5 + DMath.atan2(spell.radius, maxf(spell.ray_length, 1.0))


## How wide its cone is either side of its heading at its reach (pixels): its lane, for an enemy's
## AI (`CastSense.radius`).
func lane_radius(spell: CompiledSpell) -> float:
	return spell.ray_length * DMath.tan(half_angle(spell))


## One jet of the launch along `heading`: its cone struck at once, its end point's blast and
## `on expire` payload, and its look told.
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, _lifetime: float, chain: int, prev: int) -> int:
	if not origin.is_finite() or not heading.is_finite() or heading.is_zero_approx():
		return 0
	var end: Vector2 = kit.projectiles.grid().clip_to_walls(origin, origin + heading * spell.ray_length)
	var got: float = origin.distance_to(end)
	if kit.events != null:
		# Its cue throws its spell's cards' motes (`Spells.cue_tag`).
		kit.set_cue_tag(tag)
		kit.events.carrier_shown.emit(actor, spell.carrier_card_id, origin, heading, got, spell.tint, spell.look)
		kit.set_cue_tag(0)
	# Its build is kept while it pours (what its hits set off may read it).
	kit.shot_started(tag)
	# A wizard's own cast is struck from its hand, as far as the staff tip and its reach past it.
	var from: Vector2 = origin
	var holder: int = SpellRuntime.body_of(kit.caster(), actor)
	if holder == actor and actor >= 0 and actor < SpellRuntime.ACTORS and kit.aim_pivot(actor).is_finite():
		from = kit.aim_pivot(actor)
	var half: float = half_angle(spell)
	var spare: Node = kit.spared(spell, source if is_instance_valid(source) else null)
	var found: int = kit.projectiles.sweep(actor, from, heading, 1, -half, half, from.distance_to(origin) + got, SpellRuntime.HITS, spare)
	_struck.clear()
	if found > 0:
		kit.strike(spell, tag, actor, found, _struck, from, chain, prev, spell.echo_hit if kit.is_echo(spell) else null)
	_struck.clear()
	kit.blast(spell, tag, actor, end)
	if spell.fires_on(TriggerBase.Event.EXPIRE):
		kit.fire_payloads(spell, TriggerBase.Event.EXPIRE, tag, actor, end, heading, null)
	kit.shot_ended(tag)
	return 1


## A bigger caster's spray reaches further (its size is its reach, as a swing's).
func scale_size(spell: CompiledSpell, factor: float) -> void:
	super.scale_size(spell, factor)
	spell.ray_length *= factor


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length
