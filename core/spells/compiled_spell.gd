class_name CompiledSpell
extends RefCounted
## One carrier of a staff turned into final numbers (`StaffCompiler`, docs/milestones/
## M2-staffs.md): what it fires, with the infusions, modifiers and triggers that attached to it,
## and the payload each trigger fires (`triggers`). A fallback (cards that landed on the caster or on a
## payload's origin) is one too, with `fallback` set and a fallback carrier (docs/CARRIERS.md). It is read-only data for the spell runtime;
## nothing but `core/spells/` reads it (the builder gets plain values from `Spells.staff_view`).

## Made whole by the staff compiler and never changed after: the state walk hashes it once
## (core/sim/README.md).
const FROZEN: bool = true

## Not state (core/sim/README.md): `plain_hit`'s answer, worked out from the spell's own numbers the
## first time a hit asks. A compiled staff outlives a run (the compile cache), so it would carry
## from one run into the next (online-ready N3b).
const DERIVED: Array[StringName] = [&"_plain_hit"]

var form_id: StringName = &""
var element_id: StringName = &""
## Display names taken while compiling, so a description needs no second look-up.
var form_name: String = ""
var element_name: String = ""
var modifier_ids: Array[StringName] = []
## The id of its first trigger, `&""` for none (for its name; the runtime reads `triggers`).
var trigger_id: StringName:
	get:
		return triggers[0].id if not triggers.is_empty() else &""

## Damage of one hit; may be below 1 (health is decimal: an atom's speck takes 0.3).
var damage: float = 1.0
var mana_cost: float = 0.0
## Seconds its staff is busy after it leaves (`FormBase.wind_down` times the modifiers').
var wind_down: float = 0.5
var speed: float = 0.0
var lifetime: float = 1.0
var radius: float = 4.0
## Shots one cast of this carrier makes, after split and the form's own count.
var shots: int = 1
## Degrees the shots fan over.
var spread: float = 0.0
## The id of its carrier (`FormBase.carrier`, `Carriers.of`); a fallback's is a fallback carrier's
## (`Carriers.ON_CASTER`, `ON_BEARER`, `AT_POINT`), which no form card fires.
## Setting it reads the carrier's `traits` and `look_drawer` once.
var carrier: StringName = &"":
	set(value):
		carrier = value
		traits = Carriers.of(value).traits()
		look_drawer = Carriers.of(value).look_drawer()
## Its carrier's yes/no answers (`Carrier.traits`, `CarrierTraits`), kept here so the runtime asks
## them per shot with no lookup (`has_trait`).
var traits: int = 0
## What draws its carrier's look (`Carrier.look_drawer`, LOOK_*), kept with the traits.
var look_drawer: int = Carrier.LOOK_NONE
var pierce: int = 0
var orbit_radius: float = 0.0
var ray_length: float = 0.0
## SWING: degrees its sweep hits over (`FormBase.arc`). `wind_up`: the seconds its cast winds up
## before it leaves, its form card's plus its modifiers' `wind_up_add`, times their `wind_up_mult`
## (docs/milestones/cast-timing.md).
var arc: float = 0.0
var wind_up: float = 0.0
## The carrier's staff animation (`FormBase.packed_pose`, shared, never written).
var staff_pose: PackedFloat32Array = PackedFloat32Array()
## The shots the cards asked for (the same as `shots`; kept for the description).
var shots_requested: int = 1

## Element: the status a hit applies (`&""` for plain arcane damage) and the shot tint.
var status_id: StringName = &""
var status_duration: float = 0.0
var status_strength: float = 0.0
var tint: Color = Color.WHITE
## The shot's look, packed by `core/projectiles`' `pack_look`: the `look_layer` of every
## infusion and modifier on it, combined (0 none).
var look: int = 0
## The shader its carrier's look is drawn by (`FormBase.look_shader`; null for the plain one of
## whatever draws it): for shots, a body the projectile manager numbers (`register_body`, by
## `look_drawer`'s mesh); its card's id goes with every shot (`Projectiles.set_looks`), for its looks.
var look_shader: Shader = null
## How bright and how far its carrier lights the room, times the light's own
## (`FormBase.look_light_intensity`, `look_light_reach`; 1 for a plain one).
var look_light_intensity: float = 1.0
var look_light_reach: float = 1.0

## What a hit does, for `Spells.hit_profile`; set by the compiler.
var hit: HitProfile = null
## What an echo's second firing does: the whole hit at ECHO_DAMAGE (heal, slam, every status
## and the kind kept). Null without an `echo` modifier.
var echo_hit: HitProfile = null
## What a `blast`'s strikes do: the carrier's hit (and its echo's), as `burst` (`StaffCompiler.blast_hit`),
## so an explosion feels like one whatever set it off. Null without a blast.
var blast_hit: HitProfile = null
var echo_blast_hit: HitProfile = null

## The radius in pixels of the tightest curve a homing carrier turns on toward a target, at any
## speed (whatever moves turns its speed / this radians a second); 0 means no homing.
var homing_curve: float = 0.0
## Degrees off its aim a homing beam or teleport still bends to a target: what that curve turns
## over SpellLimits.INSTANT_HOMING_REACH pixels, up to all the way round (0 without homing).
var homing_angle: float = 0.0
## Pixels away a homing spell looks for its target (`Carrier.homing_range`); 0 when it does
## not home, or its form cannot be steered (its homing cards are then listed as wasted).
var homing_range: float = 0.0
## Times a hit jumps on to another target; 0 means no chain.
var chain_jumps: int = 0
## Factor on the staff's `spread` for this carrier's shots (its modifiers' `spread_mult`,
## multiplied); 1 means the staff's own spread.
var spread_mult: float = 1.0
## Speed over life (`ProjectileManager.set_speed_curve`): every shot's default motion, the
## SpellLimits.SHOT_SPEED_* curve, times its modifiers' `speed_start`, `speed_end` and
## `speed_ease`, each multiplied. All 1 would be a shot that keeps its speed.
var speed_start: float = SpellLimits.SHOT_SPEED_START
var speed_end: float = SpellLimits.SHOT_SPEED_END
var speed_ease: float = SpellLimits.SHOT_SPEED_EASE


## True when the spell's shots change speed over their life (every spell's, unless its cards
## cancel the default curve out).
func has_speed_curve() -> bool:
	return speed_start != 1.0 or speed_end != 1.0
## `zap`: the chance (0 to 1; 0 for none) that each body coming within `zap_reach` of a shot is
## zapped (rolled again `SpellLimits.ZAP_AGAIN` after it was zapped or lost), and what a zap hits with.
var zap_chance: float = 0.0
var zap_reach: float = 0.0
var zap_hit: HitProfile = null
## An echoed shot's zap: `zap_hit` at ECHO_DAMAGE. Null without both `zap` and `echo`.
var echo_zap_hit: HitProfile = null

## `fallback` values: a carrier's spell, the cards that landed on the caster, on a payload's
## origin, or on the body or shot that fired a payload (docs/CARRIERS.md, "The fallback carriers").
const FALLBACK_NONE: int = 0
const FALLBACK_CASTER: int = 1
const FALLBACK_POINT: int = 2
const FALLBACK_BEARER: int = 3
var fallback: int = FALLBACK_NONE
## A fallback carrier's: whether a card that landed on it uses its strike (`CarrierFallback.uses_strike`:
## cards that only guard, a shield or a deflect, strike nothing). True for any other carrier.
var strikes: bool = true
## Every infusion on the shot, in slot order; `element_id` is the first.
var element_ids: Array[StringName] = []
## The stacked `behaviour_strength` of the modifiers, indexed by `ModifierBase.Behaviour`
## (`StaffCompiler.stacked`: three shields give 3 at SHIELD, two heavy cards 16 at HEAVY).
var behaviours: PackedFloat32Array = PackedFloat32Array()
## The cue each behaviour goes off with (`ModifierBase.cue`), by `ModifierBase.Behaviour`: the
## first card of that behaviour in slot order that names one. Only the named ones are kept.
var behaviour_cues: Dictionary = {}
## Every trigger on the carrier that fires, in slot order, each with its own payload: the
## triggers before a carrier take the groups read after it in turn (owner, 2026-10-31,
## docs/milestones/M2-staffs.md, "Reading a staff"). A trigger that never fires or found nothing
## to fire is not here (it is wasted).
var triggers: Array[Trigger] = []
## The first trigger's payload, or null without a trigger (for a reader that follows one chain,
## such as `chain_length`; the runtime fires every one of `triggers`).
var payload: CompiledGroup:
	get:
		return triggers[0].payload if not triggers.is_empty() else null
## The group a rain carries (its payload), or null.
var own_payload: CompiledGroup = null
## Index in `CompiledStaff.nodes`; the tag of this spell's shots carries it.
var node: int = -1
## The carrier's slot in the staff, -1 for a fallback.
var slot: int = -1
## The slots of its own cards, in the order they were read: the infusions and modifiers attached
## to it, then its carrier (a fallback: the cards that landed there). Set where the compiler
## attaches them; its triggers are in `triggers` and a group's multicasts in the group. For the
## builder's tree (docs/milestones/M2-builder-tree.md, part T3).
var card_slots: PackedInt32Array = PackedInt32Array()
## The behaviours that make a hit not plain (`plain_hit`), and its answer once worked out (-1 not yet).
const PLAIN_HIT_BEHAVIOURS: Array[int] = [ModifierBase.Behaviour.SIPHON, ModifierBase.Behaviour.POSSESS, ModifierBase.Behaviour.PULL, ModifierBase.Behaviour.BLAST]
var _plain_hit: int = -1


## The stacked strength of `behaviour` (a `ModifierBase.Behaviour`) on this spell, 0 for none.
func behaviour(kind: int) -> float:
	return behaviours[kind] if kind >= 0 and kind < behaviours.size() else 0.0


## The cue `behaviour` (a `ModifierBase.Behaviour`) goes off with on this spell, `&""` for none.
func cue_of(kind: int) -> StringName:
	return behaviour_cues.get(kind, &"") as StringName


## How many spells there are in this chain of payloads, this one included (following the first
## spell of each payload).
func chain_length() -> int:
	if payload == null or payload.is_empty():
		return 1
	return 1 + payload.spells[0].chain_length()


## True when its hit does nothing of its own besides its payload and chain: no siphon, possess,
## pull or blast (`Spells._on_hit_effects`). Worked out once (performance, 2026-11-02: every hit
## asks); the compiler is done with a spell before it is fired, and nothing changes it after.
func plain_hit() -> bool:
	if _plain_hit < 0:
		_plain_hit = 1
		for kind: int in PLAIN_HIT_BEHAVIOURS:
			if behaviour(kind) > 0.0:
				_plain_hit = 0
	return _plain_hit == 1


## True when one of its triggers goes off on `event` (a `TriggerBase.Event`).
func fires_on(event: int) -> bool:
	for trigger in triggers:
		if trigger.event == event:
			return true
	return false


## True when it has a trigger its carrier fires while it lives (`TriggerBase.LIVE`): it is listed
## as a live carrier (`CarrierKit.live_join`).
func fires_live() -> bool:
	for trigger in triggers:
		if TriggerBase.LIVE.has(trigger.event):
			return true
	return false


## True when its carrier answers yes to `flag` (a `CarrierTraits` flag).
func has_trait(flag: int) -> bool:
	return traits & flag != 0


## One trigger of a carrier and the group it fires.
class Trigger:
	extends RefCounted
	var id: StringName = &""
	## A `TriggerBase.Event` value.
	var event: int = TriggerBase.Event.HIT
	## Seconds between fires, for a timer: its payload's whole wind-up (the timer card's and the
	## payload's cards'; docs/milestones/cast-timing.md, T8), which the tick then fires without.
	var interval: float = 0.0
	var payload: CompiledGroup = null
	## The trigger card's slot in the staff.
	var slot: int = -1
