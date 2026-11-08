class_name StaffCompiler
extends RefCounted
## Reads a staff's cards into its cycle (staffs A4; the rules are docs/milestones/M2-staffs.md,
## "Reading a staff"). `Spells.compile_staff` is the one caller; it hands in a lookup from card
## id to card, so this script needs no registry.
##
## In short: a cast reads one group from the cursor. Modifiers and infusions wait for the next
## carrier; a multicast card makes the group want more carriers (or fire again); a trigger waits
## for the next carrier, whose payload is the group read right after it (with more triggers, each
## takes the next group in turn). Reading wraps past the
## last slot, and a card already read in this cast ends the group. Cards left with no carrier
## land on a fallback carrier (`Carriers.fallback`): the caster (the cast's own group), or for a
## payload what fired it (a body or a shot, as its carrier and trigger say: `Carrier.payload_cast_by`)
## or else the point it began at, by the same rules as any carrier. Nothing is refused: a card that
## does nothing is listed as wasted (`wasted`); the builder shows it.


const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
## `CompiledCast.targets` value for a card that landed on the caster, on a payload's origin, and on
## the body or shot that fired a payload.
const TARGET_CASTER: int = -1
const TARGET_POINT: int = -2
const TARGET_BEARER: int = -3


## How the description says when a trigger fires, by `TriggerBase.Event`.
const WHEN: Array[String] = ["on hit", "when it ends", "every %s s", "when its shield blocks", "on a kill", "at once", "on a wall", "when you are hurt", "on a reaction", "when its staff is pressed again"]

## Test only (tests/core/test_card_rules.gd): true keeps every card the waste table would drop on
## its carrier (a behaviour, numbers, an infusion, a trigger that "never fires"), so the runtime
## alone decides what it does and the test can see whether a W cell really changes nothing.
static var keep_wasted: bool = false

## Not state: services, caches and scratch, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_lookup", &"keep_wasted"]

## id -> SpellComponent (or null for an unknown id).
var _lookup: Callable

# Per compile.
var _out: CompiledStaff = null
var _cards: Array[SpellComponent] = []
var _count: int = 0
# Per cast.
var _cast: CompiledCast = null
var _used: PackedByteArray = PackedByteArray()
var _pos: int = 0
## True once a reading tried to go past the last slot: the staff's cycle ends with this cast.
var _reached_end: bool = false
## True while a payload's group is read: its carriers and multicast cards add no wind-down.
var _in_payload: bool = false
## Slots that did something in some cast, so they are not listed as wasted for the staff.
var _useful: Dictionary = {}


func _init(lookup: Callable) -> void:
	_lookup = lookup


## The cycle of `cards` (ids by slot, `&""` for empty) in `staff`. Cards past `staff.slots`
## are ignored; an unknown id is wasted.
func compile(cards: Array[StringName], staff: StaffBase) -> CompiledStaff:
	_out = CompiledStaff.new()
	_out.staff = staff
	_out.cards = cards.duplicate()
	_count = mini(cards.size(), staff.slots if staff != null else cards.size())
	_cards.clear()
	_useful.clear()
	var unknown: Dictionary = {}
	for slot in _count:
		var card: SpellComponent = null
		if cards[slot] != &"":
			card = _lookup.call(cards[slot]) as SpellComponent
			if card == null:
				unknown[slot] = true
		_cards.append(card)
	var cursor: int = 0
	while _has_card_from(cursor) and _out.casts.size() < _count + 1:
		var cast: CompiledCast = _read_cast(cursor, staff)
		_out.casts.append(cast)
		if cast.ends_cycle:
			break
		cursor = _pos
	for cast in _out.casts:
		for slot: int in cast.wasted:
			if not _useful.has(slot):
				_out.wasted[slot] = true
	_out.wasted.merge(unknown)
	return _out


func _read_cast(start: int, staff: StaffBase) -> CompiledCast:
	_cast = CompiledCast.new()
	_used = PackedByteArray()
	_used.resize(_count)
	_pos = start
	_reached_end = false
	_in_payload = false
	_cast.group = _read_group(staff.draw if staff != null else 1, false, Carrier.BY_BODY)
	_cast.ends_cycle = _reached_end or not _has_card_from(_pos)
	_cast.wind_up = _cast.group.wind_up + (staff.wind_up if staff != null else 0.0)
	_cast.delay = _cast.wind_down
	if _cast.ends_cycle and staff != null:
		_cast.delay += staff.cooldown
	_cast.description = "%s. %s mana, %s%s s%s." % [_group_text(_cast.group), _number(_cast.mana), ("%s s wind-up, " % _number(_cast.wind_up)) if _cast.wind_up > 0.0 else "", _number(_cast.wind_down), (", then %s s cooldown" % _number(staff.cooldown)) if _cast.ends_cycle and staff != null and staff.cooldown > 0.0 else ""]
	_cast.sense = CastSense.of(_cast)
	return _cast


## Reads one group that wants `want` carriers. `payload` is true for a trigger's (or a payload
## carrier's) group, whose fallback is what fired it or its origin instead of the caster; `by` says
## who may cast the group (`Carrier.BY_*` bits: the caster's body for the cast's own), for the
## fallback and for what its carriers' payloads are cast by in turn (`Carrier.payload_cast_by`).
func _read_group(want: int, payload: bool, by: int, wind_up: float = 0.0) -> CompiledGroup:
	var outer_payload: bool = _in_payload
	_in_payload = payload
	var group := CompiledGroup.new()
	# A trigger's own wind-up starts its payload's (`wind_up`); no card changes it (a staff or a
	# relic may, later: docs/milestones/cast-timing.md, T9).
	group.wind_up = maxf(wind_up, 0.0)
	var elements: Array[ElementBase] = []
	var modifiers: Array[ModifierBase] = []
	var kept: PackedInt32Array = PackedInt32Array()
	# The triggers kept for the next carrier, in slot order; each takes its own payload.
	var triggers: Array[TriggerBase] = []
	var trigger_slots: PackedInt32Array = PackedInt32Array()
	# The multicast cards read, in slot order; whether each did anything is known at the end.
	var multicasts: PackedInt32Array = PackedInt32Array()
	# The carriers the group asked for before any multicast, and the ones it found.
	var asked: int = want
	var found: int = 0
	while want > 0:
		var slot: int = _next_slot()
		if slot < 0:
			break
		var card: SpellComponent = _cards[slot]
		if card is ElementBase:
			elements.append(card as ElementBase)
			kept.append(slot)
		elif card is ModifierBase:
			modifiers.append(card as ModifierBase)
			kept.append(slot)
		elif card is MulticastBase:
			multicasts.append(slot)
			want += (card as MulticastBase).extra_draws
		elif card is TriggerBase:
			triggers.append(card as TriggerBase)
			trigger_slots.append(slot)
		elif card is FormBase:
			var form := card as FormBase
			var on: Carrier = Carriers.of(form.carrier)
			var kept_modifiers: Array[ModifierBase] = _modifiers_on(on, modifiers, payload, form.wind_up)
			var kept_elements: Array[ElementBase] = _elements_on(on, elements, kept_modifiers)
			var spell: CompiledSpell = _build(form, on, kept_elements, kept_modifiers, CompiledSpell.FALLBACK_NONE)
			spell.slot = slot
			_useful[slot] = true
			_land(spell, kept, kept_modifiers, kept_elements, slot)
			spell.card_slots.append(slot)
			if form.carries_payload():
				# A payload a carrier drops itself (a rain's) falls at a point.
				spell.own_payload = _read_group(1, true, Carrier.BY_POINT)
			for t in triggers.size():
				_read_trigger(spell, triggers[t], trigger_slots[t], form, kept_elements, kept_modifiers, on.payload_cast_by(triggers[t].event, spell, by))
			group.spells.append(spell)
			group.wind_up += spell.wind_up
			elements = []
			modifiers = []
			kept = PackedInt32Array()
			triggers = []
			trigger_slots = PackedInt32Array()
			want -= 1
			found += 1
	# Triggers with no carrier after them are wasted.
	for at: int in trigger_slots:
		_waste(at)
	# The fallback carrier is one the group drew too: a multicast that kept it reading pulled the
	# cards that landed there into this cast (`triple · bolt · fire`: the fire lands on you now).
	var landed: int = 0
	if not elements.is_empty() or not modifiers.is_empty():
		var fallback: CompiledSpell = _fallback(elements, modifiers, kept, payload, by)
		if fallback != null:
			group.spells.append(fallback)
			group.wind_up += fallback.wind_up
			landed = 1
	_take_multicasts(group, multicasts, maxi(found + landed - asked, 0), found)
	_in_payload = outer_payload
	return group


## The multicast cards of `group` (`slots`, in slot order) after it was read: `extra` carriers came
## beyond what the group asked for (its fallback carrier counts), `found` of a form card's. Those
## carriers go to the cards in slot order, each up to its `extra_draws`. A card works when it got one of them, or for what else it does: a
## burst repeats a group that fires anything, a scatter turns the carriers it has. Any other is
## wasted (owner, 2026-11-06: one that adds no carrier at all; one that adds fewer than it asks for
## still works) and costs nothing. A card that works joins the group: its cost, its mode.
func _take_multicasts(group: CompiledGroup, slots: PackedInt32Array, extra: int, found: int) -> void:
	for slot: int in slots:
		var multicast := _cards[slot] as MulticastBase
		var got: int = mini(multicast.extra_draws, extra)
		extra -= got
		var works: bool = got > 0
		match multicast.mode:
			MulticastBase.Mode.BURST:
				works = works or (multicast.repeats > 1 and not group.is_empty())
			MulticastBase.Mode.SCATTER:
				works = works or found > 0
		if not works and not keep_wasted:
			_waste(slot)
			continue
		group.multicast_ids.append(multicast.id)
		group.multicast_slots.append(slot)
		_useful[slot] = true
		_cast.mana += multicast.mana_cost
		if not _in_payload:
			_cast.wind_down += multicast.wind_down
		match multicast.mode:
			MulticastBase.Mode.SCATTER:
				group.scatter = true
			MulticastBase.Mode.BURST:
				group.repeats *= maxi(multicast.repeats, 1)
				group.repeat_interval = maxf(group.repeat_interval, multicast.repeat_interval)


## Reads the payload of `trigger` (in `trigger_slot`) on the carrier `spell` (in `form`): the group
## read next. A trigger whose event never happens on this carrier still reads its payload, so the
## cards after it are read in the same order whether it fires or not; the payload is then wasted
## with it (rules R2b). One with nothing to fire is wasted too. Every trigger of a carrier is read
## the same way, in slot order, so each takes the next group (owner, 2026-10-31). `by` is who may
## cast the payload (`Carrier.payload_cast_by`).
func _read_trigger(spell: CompiledSpell, trigger: TriggerBase, trigger_slot: int, form: FormBase, elements: Array[ElementBase], modifiers: Array[ModifierBase], by: int) -> void:
	var never: bool = not keep_wasted and not _trigger_fires(trigger, form, elements, modifiers)
	var first: int = _cast.slots.size()
	var mana: float = _cast.mana
	var wind_down: float = _cast.wind_down
	var useful: Dictionary = _useful.duplicate() if never else {}
	var held: CompiledGroup = _read_group(1, true, by, trigger.wind_up)
	if held.is_empty():
		_waste(trigger_slot)
	elif never:
		_waste(trigger_slot)
		_cast.mana = mana
		_cast.wind_down = wind_down
		for at: int in _cast.slots.slice(first):
			_cast.targets.erase(at)
			if not useful.has(at):
				_useful.erase(at)
			if not _cast.wasted.has(at):
				_waste(at)
	else:
		_attach(trigger_slot, spell.slot)
		var fires := CompiledSpell.Trigger.new()
		fires.id = trigger.id
		fires.event = trigger.event
		# A timer's tick is its payload's whole wind-up (cast timing T8).
		fires.interval = held.wind_up if trigger.event == TriggerBase.Event.TIMER else 0.0
		fires.payload = held
		fires.slot = trigger_slot
		spell.triggers.append(fires)


## The cards left without a carrier land on a fallback carrier (`Carriers.fallback`): the caster's
## for the cast's own group; for a payload, what fired it when a body or a shot may have (`by`),
## else its origin. Which of them do something there is the same rule as on any carrier (its yes/no
## answers and what each card needs); when none does, nothing lands and every one is wasted.
func _fallback(elements: Array[ElementBase], modifiers: Array[ModifierBase], kept: PackedInt32Array, payload: bool, by: int) -> CompiledSpell:
	var on: Carrier = Carriers.fallback(payload, by)
	var kept_modifiers: Array[ModifierBase] = _modifiers_on(on, modifiers, payload)
	var kept_elements: Array[ElementBase] = _elements_on(on, elements, kept_modifiers)
	if kept_modifiers.is_empty() and kept_elements.is_empty():
		for at: int in kept:
			_waste(at)
		return null
	var kind: int = CompiledSpell.FALLBACK_CASTER
	var target: int = TARGET_CASTER
	if on.id() == Carriers.ON_BEARER:
		kind = CompiledSpell.FALLBACK_BEARER
		target = TARGET_BEARER
	elif on.id() == Carriers.AT_POINT:
		kind = CompiledSpell.FALLBACK_POINT
		target = TARGET_POINT
	var spell: CompiledSpell = _build(null, on, kept_elements, kept_modifiers, kind)
	spell.strikes = CarrierFallback.uses_strike(kept_modifiers, kept_elements)
	_land(spell, kept, kept_modifiers, kept_elements, target)
	return spell


## The modifiers of `modifiers` that do something on the carrier `on`, in order (every one with
## `keep_wasted`): a behaviour it runs (`Carrier.works`; homing on a rune, return on a beam do
## nothing, and change nothing else either) and numbers it uses (`_numbers_count`). The one rule for
## a form's carrier and a fallback alike. `payload`: the carrier is a payload's, which adds no
## wind-down to a staff. `wind_up`: its form card's wind-up (0 for a fallback carrier); with a
## charge kept on it the carrier winds up too, so a shorter wind-up counts there.
static func _modifiers_on(on: Carrier, modifiers: Array[ModifierBase], payload: bool, wind_up: float = 0.0) -> Array[ModifierBase]:
	var deflects: bool = false
	var blasts: bool = false
	for modifier in modifiers:
		deflects = deflects or (modifier.behaviour == ModifierBase.Behaviour.DEFLECT and on.works(modifier.behaviour))
		blasts = blasts or (modifier.behaviour == ModifierBase.Behaviour.BLAST and on.works(modifier.behaviour))
	var winds_up: bool = wind_up > 0.0
	for modifier in modifiers:
		# A charge's wind-up is a cost: it is there when the charge is kept for what else it does.
		winds_up = winds_up or (modifier.wind_up_add > 0.0 and on.works(modifier.behaviour, blasts) and _numbers_count(modifier, on, blasts, payload, false))
	var out: Array[ModifierBase] = []
	for modifier in modifiers:
		# A deflect turns every shot that touches it first, so a shield with it never blocks.
		var works: bool = not (deflects and _shield_outrun(modifier, on)) and on.works(modifier.behaviour, blasts) and _numbers_count(modifier, on, blasts, payload, winds_up)
		if works or keep_wasted:
			out.append(modifier)
	return out


## The infusions of `elements` that count on the carrier `on` with `modifiers` on it (every one with
## `keep_wasted`): an infusion is a hit's element, so on a carrier that hits nothing itself only a
## blast carries it (`Carrier.takes_element`).
static func _elements_on(on: Carrier, elements: Array[ElementBase], modifiers: Array[ModifierBase]) -> Array[ElementBase]:
	var blasts: bool = false
	for modifier in modifiers:
		blasts = blasts or (modifier.behaviour == ModifierBase.Behaviour.BLAST and on.works(modifier.behaviour))
	var out: Array[ElementBase] = []
	for element in elements:
		if on.takes_element(element, blasts) or keep_wasted:
			out.append(element)
	return out


## Each card of `kept` (slots, in order) on `spell`: attached to `target` (its carrier's slot, or
## TARGET_CASTER / TARGET_BEARER / TARGET_POINT) when it is in `modifiers` or `elements`, the cards
## that work there,
## else wasted.
func _land(spell: CompiledSpell, kept: PackedInt32Array, modifiers: Array[ModifierBase], elements: Array[ElementBase], target: int) -> void:
	for at: int in kept:
		var card: SpellComponent = _cards[at]
		if (card is ModifierBase and not modifiers.has(card)) or (card is ElementBase and not elements.has(card)):
			_waste(at)
		else:
			_attach(at, target)
			spell.card_slots.append(at)


## True when `trigger` can fire on `form` with these infusions and kept modifiers: all the trigger
## needs (`TriggerBase.NEEDS`, `Carrier.fires_with`), the one rule for the compiler and `card_works`.
func _trigger_fires(trigger: TriggerBase, form: FormBase, elements: Array[ElementBase], modifiers: Array[ModifierBase]) -> bool:
	var has: Dictionary = {}
	for modifier in modifiers:
		has[modifier.behaviour] = true
	return Carriers.of(form.carrier).fires_with(trigger.event, has, not elements.is_empty())


## True when `card` does something on the carrier `carrier` when it is the only other card there:
## what the builder, a reward screen or a bot asks before a card is placed. The same rules as a
## compile of `[card, carrier]` (a trigger with a payload after it); a form or a multicast always.
static func card_works(card: SpellComponent, carrier: StringName) -> bool:
	var on: Carrier = Carriers.of(carrier)
	if card is ModifierBase:
		var modifier := card as ModifierBase
		return on.works(modifier.behaviour) and _numbers_count(modifier, on, false, false, false)
	if card is ElementBase:
		return on.takes_element(card as ElementBase, false)
	if card is TriggerBase:
		return on.fires_with((card as TriggerBase).event, {}, false)
	return true


## True when one of a modifier's numbers counts on the carrier `on` (or it has a behaviour). Its
## costs (more mana, a slower cast, less damage) are no effect; an effect counts where the carrier
## uses that number: a shorter wind-down where it adds one to its staff (`Carrier.has_wind_down`:
## not a fallback carrier, and not a payload's carrier, `payload`), a shorter wind-up where the
## carrier winds up (`winds_up`), damage where it hits (or blasts), speed where it travels and lifetime where it moves or lasts,
## shots, spread and pierce where it fires shots that use them. A behaviour card is judged by its
## behaviour (`Carrier.works`), its numbers ride with it.
static func _numbers_count(modifier: ModifierBase, on: Carrier, blasts: bool, payload: bool, winds_up: bool) -> bool:
	if modifier.behaviour != ModifierBase.Behaviour.NONE:
		return true
	var any: bool = false
	if not is_equal_approx(modifier.radius_mult, 1.0):
		return true
	if modifier.wind_up_mult < 1.0:
		any = true
		if winds_up:
			return true
	if modifier.wind_down_mult < 1.0:
		any = true
		if on.has_wind_down() and not payload:
			return true
	if modifier.damage_mult > 1.0:
		any = true
		if on.hits() or blasts:
			return true
	if not is_equal_approx(modifier.speed_mult, 1.0):
		any = true
		if on.has(Carrier.SPEED):
			return true
	if not is_equal_approx(modifier.lifetime_mult, 1.0):
		any = true
		if on.has(Carrier.SPEED) or on.has(Carrier.LASTS):
			return true
	if modifier.shot_mult != 1:
		any = true
		if on.has(Carrier.SHOTS):
			return true
	if not is_equal_approx(modifier.speed_start, 1.0) or not is_equal_approx(modifier.speed_end, 1.0):
		any = true
		if on.flies():
			return true
	if not is_equal_approx(modifier.reach_mult, 1.0):
		any = true
		if on.reaches():
			return true
	if not is_equal_approx(modifier.spread_mult, 1.0):
		any = true
		# A placed carrier (rune, decoy, familiar) appears along its aim, so its spread moves it (rules R4 F3).
		if on.has(Carrier.SPREAD):
			return true
	if modifier.extra_pierce != 0:
		any = true
		# A wall stands through every hit (rules R4 F6).
		if on.has(Carrier.PIERCE):
			return true
	return not any


## A compiled spell of the carrier `on` from its form card (none for a fallback carrier, whose
## numbers are SpellLimits.FALLBACK_*) and the cards that attach to it.
func _build(form: FormBase, on: Carrier, elements: Array[ElementBase], modifiers: Array[ModifierBase], fallback: int) -> CompiledSpell:
	var spell := CompiledSpell.new()
	spell.node = _out.nodes.size()
	_out.nodes.append(spell)
	spell.fallback = fallback
	spell.behaviours.resize(ModifierBase.Behaviour.size())
	var damage: float = SpellLimits.FALLBACK_DAMAGE
	var mana: float = 0.0
	var wind_down: float = 0.0
	var speed: float = 0.0
	var radius: float = SpellLimits.FALLBACK_RADIUS
	var shots: int = 1
	var pierce: int = 0
	var homing_reach: float = 0.0
	var heals: bool = false
	var later_ids: Array[StringName] = []
	# Every `wind_up_mult` on the carrier, applied to its whole wind-up once all are read.
	var wind_up_mult: float = 1.0
	var later_durations: PackedFloat32Array = PackedFloat32Array()
	var later_strengths: PackedFloat32Array = PackedFloat32Array()
	spell.lifetime = SpellLimits.MIN_LIFETIME
	var carrier: Carrier = on
	spell.carrier = on.id()
	# A fallback carrier's own animation; a form card's carrier takes its card's below.
	spell.staff_pose = on.staff_pose()
	if form != null:
		spell.form_id = form.id
		spell.form_name = _name(form)
		spell.lifetime = form.lifetime
		spell.orbit_radius = form.orbit_radius
		spell.ray_length = form.ray_length
		spell.arc = form.arc
		spell.wind_up = maxf(form.wind_up, 0.0)
		spell.staff_pose = form.packed_pose()
		spell.spread = form.spread
		spell.look_shader = form.look_shader
		damage = form.base_damage
		mana = form.mana_cost
		wind_down = form.wind_down
		speed = form.speed
		radius = form.radius
		shots = form.shots
		pierce = form.pierce
	for element in elements:
		if spell.element_ids.is_empty():
			spell.element_id = element.id
			spell.element_name = _name(element)
			spell.status_id = element.status_id
			spell.status_duration = element.status_duration
			spell.status_strength = element.status_strength
			spell.tint = element.tint
		else:
			later_ids.append(element.status_id)
			later_durations.append(element.status_duration)
			later_strengths.append(element.status_strength)
		spell.element_ids.append(element.id)
		damage *= element.damage_scale
		heals = heals or element.heals
	for modifier in modifiers:
		spell.modifier_ids.append(modifier.id)
		damage *= modifier.damage_mult
		mana *= modifier.mana_mult
		wind_down *= modifier.wind_down_mult
		spell.wind_up += maxf(modifier.wind_up_add, 0.0)
		wind_up_mult *= maxf(modifier.wind_up_mult, 0.0)
		speed *= modifier.speed_mult
		radius *= modifier.radius_mult
		shots *= modifier.shot_mult
		pierce += modifier.extra_pierce
		spell.spread_mult *= modifier.spread_mult
		spell.speed_start *= modifier.speed_start
		spell.speed_end *= modifier.speed_end
		spell.speed_ease *= modifier.speed_ease
		spell.lifetime *= modifier.lifetime_mult
		if carrier.flies():
			spell.lifetime *= modifier.reach_mult
		else:
			spell.ray_length *= modifier.reach_mult
		if modifier.behaviour == ModifierBase.Behaviour.ZAP:
			spell.zap_reach = maxf(spell.zap_reach, modifier.behaviour_reach)
		spell.behaviours[modifier.behaviour] = stacked(modifier.behaviour, spell.behaviours[modifier.behaviour], modifier.behaviour_strength)
		if modifier.cue != &"" and not spell.behaviour_cues.has(modifier.behaviour):
			spell.behaviour_cues[modifier.behaviour] = modifier.cue
		match modifier.behaviour:
			ModifierBase.Behaviour.HOMING:
				# Homing stacks by multiplying: the tightest card's curve, / HOMING_STACK for each
				# more (owner, 2026-10-27); an instant carrier's bend follows from it.
				homing_reach = maxf(homing_reach, modifier.behaviour_reach)
				if spell.homing_curve <= 0.0:
					spell.homing_curve = modifier.behaviour_strength
				else:
					spell.homing_curve = minf(spell.homing_curve, modifier.behaviour_strength) / SpellLimits.HOMING_STACK
			ModifierBase.Behaviour.CHAIN:
				spell.chain_jumps += int(modifier.behaviour_strength)
	spell.look = _look_of(elements, modifiers)
	spell.damage = maxf(damage, SpellLimits.MIN_DAMAGE)
	spell.mana_cost = mana
	spell.wind_down = maxf(wind_down, 0.0)
	spell.wind_up *= wind_up_mult
	spell.speed = speed
	spell.radius = radius
	spell.shots = shots
	spell.shots_requested = shots
	spell.pierce = pierce
	if spell.shots > 1 and spell.spread <= 0.0 and not carrier.has(Carrier.RING):
		spell.spread = SpellLimits.SPLIT_SPREAD
	spell.hit = HitProfile.new()
	spell.hit.damage = spell.damage
	spell.hit.knockback = form.knockback if form != null and form.knockback > 0.0 else SpellLimits.KNOCKBACK
	spell.hit.element_id = spell.element_id
	spell.hit.element_ids = spell.element_ids
	spell.hit.status_id = spell.status_id
	spell.hit.status_duration = spell.status_duration
	spell.hit.status_strength = spell.status_strength
	spell.hit.later_status_ids = later_ids
	spell.hit.later_status_durations = later_durations
	spell.hit.later_status_strengths = later_strengths
	# A swing's sweep, a slam's shockwave (`burst`), a beam's or a rain's ray.
	if carrier.hit_kind() != &"":
		spell.hit.kind = carrier.hit_kind()
	if spell.homing_curve > 0.0:
		spell.homing_range = carrier.homing_range(spell.ray_length, homing_reach)
		# Past 180 degrees it would be bending back the other way: that is all the way round.
		spell.homing_angle = minf(rad_to_deg(SpellLimits.INSTANT_HOMING_REACH / spell.homing_curve), 180.0)
	if heals:
		spell.hit.heal = maxi(roundi(spell.damage), 1)
		spell.hit.damage = maxf(spell.damage * SpellLimits.HEAL_ENEMY_SHARE, 1.0)
	var heavy: float = spell.behaviour(ModifierBase.Behaviour.HEAVY)
	if heavy > 0.0:
		spell.hit.knockback *= heavy
		spell.hit.slam = roundi(spell.damage * SpellLimits.SLAM_SHARE)
	if spell.behaviour(ModifierBase.Behaviour.ECHO) > 0.0:
		spell.echo_hit = spell.hit.scaled(SpellLimits.ECHO_DAMAGE, 1.0)
	if spell.behaviour(ModifierBase.Behaviour.BLAST) > 0.0:
		spell.blast_hit = blast_hit(spell.hit)
		if spell.echo_hit != null:
			spell.echo_blast_hit = blast_hit(spell.echo_hit)
	var zap: float = spell.behaviour(ModifierBase.Behaviour.ZAP)
	if zap > 0.0:
		# The chance each body the shot passes is zapped, once (zap cards combine as chances,
		# `stacked`); a zap hits like a ray, at ZAP_DAMAGE of the shot.
		spell.zap_chance = zap
		spell.zap_hit = zap_hit(spell.hit)
		if spell.echo_hit != null:
			spell.echo_zap_hit = zap_hit(spell.echo_hit)
	_cast.mana += spell.mana_cost
	if not _in_payload:
		_cast.wind_down += spell.wind_down
	return spell


## What a zap (`arc`) of a shot that hits with `hit` does: the same hit, ray kind, at ZAP_DAMAGE of
## its strength and knockback. Spells asks it again for a shot whose hit changed (`relay`).
static func zap_hit(hit: HitProfile) -> HitProfile:
	var zap: HitProfile = hit.scaled(SpellLimits.ZAP_DAMAGE, SpellLimits.ZAP_DAMAGE)
	zap.kind = &"ray"
	return zap


## What a blast's strike of a carrier that hits with `hit` does: the same hit, kind `burst` (its
## hit-stop, shake and sound, "downed by your own Blast"): what it strikes is the carrier's hit
## (rules R4 F2), and it feels like an explosion. Spells asks it again for a hit that changed (`relay`).
static func blast_hit(hit: HitProfile) -> HitProfile:
	var blast: HitProfile = hit.copy()
	blast.kind = &"burst"
	return blast


## The strength of `behaviour` after one more card of `strength` on top of `before` (0 for none), by its
## `ModifierBase.RULES` "stacks": counts add (bounces, shields, seconds, pixels) and multipliers multiply (heavy's knockback,
## growth's factor; rule 3, docs/milestones/M2-rules.md R1c), so two heavy cards are 4 x 4, not 4 + 4.
## Homing multiplies too, by its own rule (HOMING_STACK). Chances (zap's) combine as chances do:
## two 50% cards are 75%, never past 100%.
static func stacked(behaviour: int, before: float, strength: float) -> float:
	var stack: ModifierBase.Stack = ModifierBase.stacks(behaviour)
	if before > 0.0 and stack == ModifierBase.Stack.MULTIPLY:
		return before * strength
	if stack == ModifierBase.Stack.CHANCE:
		return 1.0 - (1.0 - clampf(before, 0.0, 1.0)) * (1.0 - clampf(strength, 0.0, 1.0))
	return before + strength


## True when `modifier` is a shield that a deflect on the carrier `on` leaves with nothing to do: on
## a carrier whose shield only stops shots that touch it (`Carrier.GUARDS`) a deflect turns every
## such shot first (owner, 2026-10-29), so a shield with it never blocks.
static func _shield_outrun(modifier: ModifierBase, on: Carrier) -> bool:
	return modifier.behaviour == ModifierBase.Behaviour.SHIELD and on.guards()


## The look of a carrier's shots (docs/milestones/M2-staffs.md, "The look of a shot"): the
## looks of every infusion and modifier on it, combined.
static func _look_of(elements: Array, modifiers: Array) -> int:
	var kinds := PackedInt32Array()
	for cards: Array in [elements, modifiers]:
		for card: SpellComponent in cards:
			kinds.append(int(card.get(&"look_layer")))
	return ProjectilesScript.pack_look(kinds)


## The next card slot to read, or -1 when the group must end: no card is left, or the next
## card was already read in this cast (which is what keeps wrap-around finite).
func _next_slot() -> int:
	var steps: int = 0
	var crossed: bool = false
	while steps <= _count:
		if _pos >= _count:
			_pos = 0
			_reached_end = true
			crossed = true
		var slot: int = _pos
		if _cards[slot] == null:
			_pos += 1
			steps += 1
			continue
		if _used[slot] != 0:
			return -1
		_used[slot] = 1
		_pos += 1
		_cast.slots.append(slot)
		if crossed:
			_cast.wrapped = true
		return slot
	return -1


## True when a card sits in a slot at `from` or after it.
func _has_card_from(from: int) -> bool:
	for slot in range(maxi(from, 0), _count):
		if _cards[slot] != null:
			return true
	return false


func _attach(slot: int, target: int) -> void:
	_cast.targets[slot] = target
	_useful[slot] = true


func _waste(slot: int) -> void:
	_cast.wasted[slot] = true


func _group_text(group: CompiledGroup) -> String:
	if group == null or group.is_empty():
		return "Nothing"
	var parts: PackedStringArray = PackedStringArray()
	for spell in group.spells:
		parts.append(_spell_text(spell))
	var text: String = " and ".join(parts)
	if group.scatter:
		text += ", scattered"
	if group.repeats > 1:
		text += ", %d times" % group.repeats
	return text


func _spell_text(spell: CompiledSpell) -> String:
	var names: PackedStringArray = PackedStringArray()
	for id in spell.element_ids:
		names.append(_name(_lookup.call(id) as SpellComponent))
	var text: String
	match spell.fallback:
		CompiledSpell.FALLBACK_CASTER:
			text = "on you: %s" % ", ".join(names + _modifier_names(spell))
		CompiledSpell.FALLBACK_POINT:
			text = "right there: %s" % ", ".join(names + _modifier_names(spell))
		CompiledSpell.FALLBACK_BEARER:
			text = "on what fired it: %s" % ", ".join(names + _modifier_names(spell))
		_:
			names.append(spell.form_name)
			text = " ".join(names)
			var modifiers: PackedStringArray = _modifier_names(spell)
			if not modifiers.is_empty():
				text += " (%s)" % ", ".join(modifiers)
	if spell.own_payload != null and not spell.own_payload.is_empty():
		text += " carrying %s" % _group_text(spell.own_payload)
	for trigger in spell.triggers:
		var when: String = WHEN[trigger.event] if trigger.event < WHEN.size() else "then"
		if trigger.event == TriggerBase.Event.TIMER:
			when = when % _number(trigger.interval)
		text += "; %s: %s" % [when, _group_text(trigger.payload)]
	return text


func _modifier_names(spell: CompiledSpell) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for id in spell.modifier_ids:
		names.append(_name(_lookup.call(id) as SpellComponent))
	return names


func _name(card: SpellComponent) -> String:
	if card == null:
		return "?"
	return card.display_name if not card.display_name.is_empty() else String(card.id)


func _number(value: float) -> String:
	return String.num(value, 2)
