class_name CastSense
extends RefCounted
## What one cast of a staff does, in numbers and yes/no answers, for an AI that plays whatever
## staffs it holds (docs/milestones/M2-enemy-ai.md, "What the AI knows of a cast"). Made once per
## compiled cast by `StaffCompiler` (`CompiledCast.sense`; compiled staffs are cached for every
## caster, so it costs nothing per actor or per frame) and read with `Spells.next_cast_sense` and
## `Caster.next_cast_sense`. It names no card: an AI knows a card only by what it does (owner,
## 2026-11-01; a test fails on any card or carrier id in the AI's code). Read-only.
##
## It reads the cast's own group: its carriers (a Pulse's ring among them). What its triggers
## fire later is not part of the cast's summary.

## Made whole by the staff compiler (`CastSense.of`) and never changed after: the state walk
## hashes it once (core/sim/README.md).
const FROZEN: bool = true

## How far it goes along the aim (the carriers' `reach_of`, as the telegraph shows it); 0 when it
## is not aimed (a nova, an orbit, a decoy) or does nothing.
var reach: float = 0.0
## How near the target must be for a cast that is not aimed to touch it (a nova's ring, an orbit,
## a swing or slam's length); for an aimed cast its `reach`.
var close_reach: float = 0.0
## The hit width of its first carrier (pixels).
var radius: float = 0.0
## What the whole cast may deal: every carrier's hit times its shots, times the group's repeats;
## 0 when it hurts nobody.
var damage: float = 0.0
## The widest explosion at a carrier's end (`blast`): closer than this its caster is hurt too.
var blast: float = 0.0
## True when a blast of it goes off where it was cast, on its caster, wherever its target is: a
## carrier that goes out all round its cast point (`AOE`, a Pulse's ring) blasts at its centre.
var blast_on_caster: bool = false
## True when it hits round a point or round its caster rather than along a line (a nova, a ring,
## an orbit, a fall from the sky, a rune).
var area: bool = false
## Shot speed of its first aimed carrier (pixels a second), for leading a moving target; 0 for
## one that is there at once (a beam, a swing) or not aimed.
var speed: float = 0.0
## True when it steers itself to a target (homing).
var homing: bool = false
## True when it moves its caster (a dash, a teleport), and how far.
var moves_caster: bool = false
var move_reach: float = 0.0
## True when it stops other actors' shots: a carrier that blocks (a wall), or a shield or deflect
## on the caster or on its carriers.
var blocks: bool = false
## True when it makes a body of its own that stays (a decoy, a familiar).
var spawns: bool = false
## True when it opens a way through the world that shots and bodies take (a portal).
var opens: bool = false
## True when its hits heal.
var heals: bool = false
## True when its hits apply a status.
var status: bool = false
## True when it stays on until the button is pressed again (`hold`).
var sustained: bool = false
## True when holding the button keeps it going or casts it anew (a beam, a swing): worth
## holding as one long cast. (A held button casts any staff again when it is ready.)
var repeats_held: bool = false
## Its cost and its delay (`CompiledCast.mana`, `delay`).
var mana: float = 0.0
var delay: float = 0.0
## Seconds it winds up before it leaves (`CompiledCast.wind_up`: its staff's and its cards'; an
## enemy's telegraph, docs/milestones/cast-timing.md).
var wind_up: float = 0.0
## The longest life of its carriers (seconds): how long a held cast lasts once.
var lasts: float = 0.0
## True when the cast fires nothing at all (only wasted cards).
var empty: bool = true


## True when the cast can hurt someone: it deals damage, or explodes.
func harms() -> bool:
	return damage > 0.0 or blast > 0.0


## The summary of `cast`.
static func of(cast: CompiledCast) -> CastSense:
	var sense := CastSense.new()
	sense.mana = cast.mana
	sense.delay = cast.delay
	sense.wind_up = cast.wind_up
	sense._read_group(cast.group)
	return sense


## How far what `group` casts reaches from where it is cast, along its aim or all round (the larger;
## 0 for nothing): how near a foe must be for `on near` to fire it (props W9b).
static func reach_of(group: CompiledGroup) -> float:
	var sense := CastSense.new()
	sense._read_group(group)
	return maxf(sense.reach, sense.close_reach)


func _read_group(group: CompiledGroup) -> void:
	if group == null or group.is_empty():
		return
	empty = false
	var repeats: float = float(maxi(group.repeats, 1))
	# The aimed numbers (`radius`, `speed`) are the first aimed carrier's: one that acts all round
	# its caster (`AOE`) is not aimed.
	var first_carrier: bool = true
	for spell: CompiledSpell in group.spells:
		_read_spell(spell, repeats, first_carrier)
		if not spell.has_trait(CarrierTraits.AOE):
			first_carrier = false
	if close_reach <= 0.0:
		close_reach = reach


func _read_spell(spell: CompiledSpell, repeats: float, first: bool) -> void:
	var shield: bool = spell.behaviour(ModifierBase.Behaviour.SHIELD) > 0.0 or spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	var carrier: Carrier = Carriers.of(spell.carrier)
	var spell_reach: float = carrier.reach_of(spell)
	# A nova casts it every way at once: not aimed, an area as far out as each copy goes.
	var ways: int = spell.nova_ways()
	# Skyfall: it falls where it is cast, an area round there, not aimed.
	var falls: bool = Skyfall.falls_on(spell, carrier)
	if falls:
		spell_reach = 0.0
	var carried: float = spell.radius if falls else spell_reach
	# Orbit: it circles its caster, an area as wide as its circle, not aimed.
	var circles: bool = Orbit.orbits_on(spell, carrier)
	if circles:
		spell_reach = 0.0
		carried = spell.orbit_radius + spell.radius
	# A ring that goes out all round its cast point (a Pulse): an area as far as it grows, not aimed.
	if ways > 1 or spell.has_trait(CarrierTraits.AOE):
		spell_reach = 0.0
	if first:
		radius = spell.radius
		speed = spell.speed if spell_reach > 0.0 and spell.speed > 0.0 and spell.has_trait(CarrierTraits.FLIES) else 0.0
	reach = maxf(reach, spell_reach)
	lasts = maxf(lasts, spell.lifetime)
	# A blast strikes with the carrier's hit (`StaffCompiler.blast_hit`): a mend's blast only heals,
	# so it is no harm (owner 2026-11-12: a heal does nothing else).
	if spell.hit == null or spell.hit.heal <= 0:
		blast = maxf(blast, spell.behaviour(ModifierBase.Behaviour.BLAST))
		if spell.behaviour(ModifierBase.Behaviour.BLAST) > 0.0 and spell.has_trait(CarrierTraits.AOE):
			blast_on_caster = true
	if spell.homing_range > 0.0:
		homing = true
	if spell.has_trait(CarrierTraits.MOVES_CASTER):
		moves_caster = true
		# A dash runs its `ray_length` (or its flight), a teleport jumps it.
		move_reach = maxf(move_reach, maxf(spell_reach, maxf(spell.ray_length, spell.speed * spell.lifetime)))
	if spell.has_trait(CarrierTraits.BLOCKS) or (shield and spell.has_trait(CarrierTraits.GUARDS)):
		blocks = true
	if spell.has_trait(CarrierTraits.SPAWNS):
		spawns = true
	if spell.has_trait(CarrierTraits.GATES):
		opens = true
	if spell.behaviour(ModifierBase.Behaviour.HOLD) > 0.0:
		sustained = true
	if spell.has_trait(CarrierTraits.REPEATS_HELD) or spell.has_trait(CarrierTraits.LINE):
		repeats_held = true
	var ring: bool = spell.has_trait(CarrierTraits.AOE) or falls or circles or ways > 1 or spell.spread >= 360.0 or spell.has_trait(CarrierTraits.OUTWARD)
	if ring:
		area = true
	# How near a cast that is not aimed must be: a ring's flight, an orbit's circle, a melee arc.
	var near: float = 0.0
	if circles:
		# Its circle is where it goes, whatever it would have flown or been placed.
		near = carried
	elif spell_reach <= 0.0:
		if ring and spell.speed > 0.0:
			near = spell.speed * spell.lifetime
		near = maxf(near, spell.radius)
		near = maxf(near, spell.ray_length)
		near = maxf(near, carried)
	close_reach = maxf(close_reach, near if spell_reach <= 0.0 else spell_reach)
	var hit: HitProfile = spell.hit
	var shots: float = float(maxi(spell.shots, 1) * ways)
	if hit != null:
		if hit.heal > 0:
			# A heal does nothing else (owner 2026-11-12): no damage, and its infusions' statuses never land.
			heals = true
		else:
			if spell.has_trait(CarrierTraits.HITS):
				damage += hit.damage * shots * repeats
			if hit.status_id != &"":
				status = true
