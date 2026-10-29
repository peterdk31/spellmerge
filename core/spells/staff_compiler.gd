class_name StaffCompiler
extends RefCounted
## Reads a staff's cards into its cycle (staffs A4; the rules are docs/milestones/M2-staffs.md,
## "Reading a staff"). `Spells.compile_staff` is the one caller; it hands in a lookup from card
## id to card, so this script needs no registry.
##
## In short: a cast reads one group from the cursor. Modifiers and infusions wait for the next
## carrier; a multicast card makes the group want more carriers (or fire again); a trigger waits
## for the next carrier, whose payload is the group read right after it. Reading wraps past the
## last slot, and a card already read in this cast ends the group. Cards left with no carrier
## land on the caster (the cast's own group) or on the payload's origin (a payload). Nothing is
## refused: a card that does nothing is listed as wasted, with the reason.

## The behaviours whose strength is a factor: more cards multiply it (`stacked`).
const MULTIPLIED: Array[int] = [ModifierBase.Behaviour.HEAVY, ModifierBase.Behaviour.GROWTH]

## `CompiledCast.targets` value for a card that landed on the caster, and on a payload's origin.
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const TARGET_CASTER: int = -1
const TARGET_POINT: int = -2

## Behaviours that only mean something on a shot in flight, so they are wasted on a fallback.
const TRAVEL_ONLY: Array[int] = [
	ModifierBase.Behaviour.HOMING, ModifierBase.Behaviour.CHAIN, ModifierBase.Behaviour.BOUNCE,
	ModifierBase.Behaviour.LINGER, ModifierBase.Behaviour.STICKY, ModifierBase.Behaviour.GHOST,
	ModifierBase.Behaviour.SPIRAL, ModifierBase.Behaviour.MIRROR, ModifierBase.Behaviour.GROWTH,
	ModifierBase.Behaviour.RELAY, ModifierBase.Behaviour.RETURN, ModifierBase.Behaviour.ARC,
	ModifierBase.Behaviour.POSSESS, ModifierBase.Behaviour.MAGNET, ModifierBase.Behaviour.DEFLECT,
]

## How the description says when a trigger fires, by `TriggerBase.Event`.
const WHEN: Array[String] = ["on hit", "when it ends", "every %s s", "when its shield blocks", "on a kill", "at once", "on a wall", "when you are hurt", "on a reaction"]

## Test only (tests/core/test_card_rules.gd): true keeps every card the waste table would drop on
## its carrier (a behaviour, numbers, an infusion, a trigger that "never fires"), so the runtime
## alone decides what it does and the test can see whether a W cell really changes nothing.
static var keep_wasted: bool = false

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
## True once a reading tried to go past the last slot: the staff recharges after this cast.
var _reached_end: bool = false
## Slots that did something in some cast, so they are not listed as wasted for the staff.
var _useful: Dictionary = {}


var _namer: SpellNamer = null


func _init(lookup: Callable) -> void:
	_lookup = lookup
	_namer = SpellNamer.new(lookup)


## The cycle of `cards` (ids by slot, `&""` for empty) in `staff`. Cards past `staff.slots`
## are ignored; an unknown id is wasted with its reason.
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
				unknown[slot] = "Unknown card '%s'." % cards[slot]
		_cards.append(card)
	var cursor: int = 0
	while _has_card_from(cursor) and _out.casts.size() < _count + 1:
		var cast: CompiledCast = _read_cast(cursor, staff)
		_out.casts.append(cast)
		if cast.recharges:
			break
		cursor = _pos
	for cast in _out.casts:
		for slot: int in cast.wasted:
			if not _useful.has(slot):
				_out.wasted[slot] = cast.wasted[slot]
	_out.wasted.merge(unknown)
	return _out


func _read_cast(start: int, staff: StaffBase) -> CompiledCast:
	_cast = CompiledCast.new()
	_used = PackedByteArray()
	_used.resize(_count)
	_pos = start
	_reached_end = false
	_cast.group = _read_group(staff.draw if staff != null else 1, false)
	_cast.recharges = _reached_end or not _has_card_from(_pos)
	_cast.delay += staff.cast_delay if staff != null else 0.0
	if _cast.recharges and staff != null:
		_cast.delay += staff.recharge
	_cast.spell_name = _namer.name_cast(_cast, _out.cards)
	_cast.description = "%s. %s mana, %s s%s." % [_group_text(_cast.group), _number(_cast.mana), _number(_cast.delay), ", then recharge" if _cast.recharges else ""]
	return _cast


## Reads one group that wants `want` carriers. `payload` is true for a trigger's (or a payload
## carrier's) group, whose fallback is the payload's origin instead of the caster.
func _read_group(want: int, payload: bool) -> CompiledGroup:
	var group := CompiledGroup.new()
	var elements: Array[ElementBase] = []
	var modifiers: Array[ModifierBase] = []
	var kept: PackedInt32Array = PackedInt32Array()
	var trigger: TriggerBase = null
	var trigger_slot: int = -1
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
			var multicast := card as MulticastBase
			group.multicast_ids.append(multicast.id)
			_useful[slot] = true
			_cast.mana += multicast.mana_cost
			_cast.delay += multicast.cooldown
			want += multicast.extra_draws
			match multicast.mode:
				MulticastBase.Mode.SCATTER:
					group.scatter = true
				MulticastBase.Mode.BURST:
					group.repeats *= maxi(multicast.repeats, 1)
					group.repeat_interval = maxf(group.repeat_interval, multicast.repeat_interval)
		elif card is TriggerBase:
			if trigger != null:
				_waste(slot, "A second trigger before the same carrier does nothing.")
			else:
				trigger = card as TriggerBase
				trigger_slot = slot
		elif card is FormBase:
			var form := card as FormBase
			# A behaviour its form cannot run (homing on a rune, return on a beam) is wasted, and
			# changes nothing else either.
			var kept_modifiers: Array[ModifierBase] = []
			var deflects: bool = false
			var blasts: bool = false
			for modifier in modifiers:
				deflects = deflects or (modifier.behaviour == ModifierBase.Behaviour.DEFLECT and behaviour_runs(modifier.behaviour, form.motion))
				blasts = blasts or (modifier.behaviour == ModifierBase.Behaviour.BLAST and behaviour_runs(modifier.behaviour, form.motion))
			var life: float = _life_of(form, modifiers)
			var why_not: Dictionary = {}
			for modifier in modifiers:
				var why: String = "deflect turns every shot that touches it first" if deflects and _shield_outrun(modifier, form.motion) else behaviour_waste(modifier.behaviour, form.motion, blasts)
				if why.is_empty():
					why = _numbers_waste(modifier, form.motion, blasts)
				if why.is_empty() and modifier.behaviour == ModifierBase.Behaviour.ARC and life <= 1.0 / _strength_of(modifiers, ModifierBase.Behaviour.ARC):
					why = "it ends before its first zap (%.2f s)" % life
				if why.is_empty() or keep_wasted:
					kept_modifiers.append(modifier)
				else:
					why_not[modifier] = why
			# An infusion is a hit's element: on a carrier that hits nothing itself, only a blast carries it.
			var kept_elements: Array[ElementBase] = []
			if hits(form.motion) or blasts or keep_wasted:
				kept_elements = elements
			var spell: CompiledSpell = _build(form, kept_elements, kept_modifiers, trigger, CompiledSpell.FALLBACK_NONE)
			spell.slot = slot
			_useful[slot] = true
			for at: int in kept:
				var modifier := _cards[at] as ModifierBase
				if modifier != null and not kept_modifiers.has(modifier):
					_waste(at, "%s does nothing on a %s: %s." % [_name(modifier), _name(form), why_not[modifier]])
				elif _cards[at] is ElementBase and kept_elements.is_empty():
					_waste(at, "%s does nothing on a %s: %s, and it has no blast to carry it." % [_name(_cards[at]), _name(form), _hits_nothing(form.motion)])
				else:
					_attach(at, slot)
			if form.carries_payload():
				spell.own_payload = _read_group(1, true)
			if trigger != null:
				# A trigger whose event never happens on this carrier still reads its payload, so the
				# cards after it are read in the same order whether it fires or not; the payload is
				# then wasted with it (rules R2b).
				var never: String = "" if keep_wasted else _trigger_never(trigger, form, kept_elements, kept_modifiers, life)
				var first: int = _cast.slots.size()
				var mana: float = _cast.mana
				var delay: float = _cast.delay
				var useful: Dictionary = _useful.duplicate() if not never.is_empty() else {}
				var held: CompiledGroup = _read_group(1, true)
				if held.is_empty():
					_waste(trigger_slot, "Nothing is left after its carrier for it to fire.")
					spell.trigger_id = &""
				elif not never.is_empty():
					_waste(trigger_slot, never)
					spell.trigger_id = &""
					_cast.mana = mana
					_cast.delay = delay
					for at: int in _cast.slots.slice(first):
						_cast.targets.erase(at)
						if not useful.has(at):
							_useful.erase(at)
						if not _cast.wasted.has(at):
							_waste(at, "Nothing casts it: %s before it never fires on a %s." % [_name(trigger), _name(form)])
				else:
					_attach(trigger_slot, slot)
					spell.payload = held
			group.spells.append(spell)
			elements = []
			modifiers = []
			kept = PackedInt32Array()
			trigger = null
			want -= 1
	if trigger != null:
		_waste(trigger_slot, "No carrier comes after it.")
	if not elements.is_empty() or not modifiers.is_empty():
		var fallback: CompiledSpell = _fallback(elements, modifiers, kept, payload)
		if fallback != null:
			group.spells.append(fallback)
	return group


## The cards left without a carrier, on the caster or on the payload's origin. Elements always
## mean something there; a modifier that only steers a shot in flight is wasted.
func _fallback(elements: Array[ElementBase], modifiers: Array[ModifierBase], kept: PackedInt32Array, payload: bool) -> CompiledSpell:
	var target: int = TARGET_POINT if payload else TARGET_CASTER
	var where: String = "where the payload starts" if payload else "on the caster"
	var kept_modifiers: Array[ModifierBase] = []
	var kept_slots: PackedInt32Array = PackedInt32Array()
	for at: int in kept:
		var card: SpellComponent = _cards[at]
		if card is ElementBase:
			kept_slots.append(at)
			continue
		var modifier := card as ModifierBase
		if _means_something_there(modifier, payload):
			kept_modifiers.append(modifier)
			kept_slots.append(at)
		else:
			_waste(at, "%s does nothing %s." % [_name(modifier), where])
	if elements.is_empty() and kept_modifiers.is_empty():
		return null
	var kind: int = CompiledSpell.FALLBACK_POINT if payload else CompiledSpell.FALLBACK_CASTER
	var spell: CompiledSpell = _build(null, elements, kept_modifiers, null, kind)
	for at: int in kept_slots:
		_attach(at, target)
	return spell


func _means_something_there(modifier: ModifierBase, payload: bool) -> bool:
	if TRAVEL_ONLY.has(modifier.behaviour):
		return false
	if modifier.behaviour == ModifierBase.Behaviour.SHIELD:
		return not payload
	if modifier.behaviour != ModifierBase.Behaviour.NONE:
		return true
	# A modifier of numbers only: it scales a hit (damage, size) or does nothing here.
	return not is_equal_approx(modifier.damage_mult, 1.0) or not is_equal_approx(modifier.radius_mult, 1.0)


## Why `trigger` never fires on `form` with these infusions and kept modifiers, as the wasted
## reason; "" when it can. First the carrier (`trigger_runs`), then the cards the event needs on
## it: a block needs a shield or deflect, a reaction an infusion (or relay), and a kill or reaction
## on a carrier that hits nothing itself needs a blast, whose area hit carries the carrier's tag.
## A ghost shot never meets a wall.
func _trigger_never(trigger: TriggerBase, form: FormBase, elements: Array[ElementBase], modifiers: Array[ModifierBase], life: float) -> String:
	var head: String = "%s does nothing on a %s" % [_name(trigger), _name(form)]
	var why: String = trigger_why_not(trigger.event, form.motion)
	if not why.is_empty():
		return "%s: %s." % [head, why]
	var has: Dictionary = {}
	for modifier in modifiers:
		has[modifier.behaviour] = true
	match trigger.event:
		TriggerBase.Event.BLOCK:
			if not has.has(ModifierBase.Behaviour.SHIELD) and not has.has(ModifierBase.Behaviour.DEFLECT):
				return "%s without a shield or deflect: nothing else on it blocks." % head
		TriggerBase.Event.KILL, TriggerBase.Event.REACTION:
			if not hits(form.motion) and not has.has(ModifierBase.Behaviour.BLAST):
				return "%s without a blast: %s." % [head, _hits_nothing(form.motion)]
			if trigger.event == TriggerBase.Event.REACTION and elements.is_empty() and not has.has(ModifierBase.Behaviour.RELAY):
				return "%s without an infusion: a hit with no element sets off no reaction." % head
		TriggerBase.Event.TIMER:
			if life <= trigger.interval:
				return "%s: it ends before its first tick (%.2f s, every %.2f s)." % [head, life, trigger.interval]
		TriggerBase.Event.WALL:
			if has.has(ModifierBase.Behaviour.GHOST) and flies(form.motion):
				return "%s with ghost: a ghost shot passes through walls." % head
	return ""


## How long a carrier of `form` with `modifiers` lives: its lifetime times their `lifetime_mult`,
## or for ever with a hold that runs on it (it is on until switched off).
static func _life_of(form: FormBase, modifiers: Array[ModifierBase]) -> float:
	var life: float = form.lifetime
	for modifier in modifiers:
		if modifier.behaviour == ModifierBase.Behaviour.HOLD and behaviour_runs(modifier.behaviour, form.motion):
			return INF
		life *= modifier.lifetime_mult
	return life


## The summed strength of the `behaviour` cards among `modifiers`.
static func _strength_of(modifiers: Array[ModifierBase], behaviour: int) -> float:
	var sum: float = 0.0
	for modifier in modifiers:
		if modifier.behaviour == behaviour:
			sum += modifier.behaviour_strength
	return maxf(sum, 0.001)


## Why a modifier's numbers do nothing on a carrier of `motion`, or "" when one of them counts. Its
## costs (more mana, a slower cast, less damage) are no effect; an effect counts where the carrier
## uses that number: damage where it hits (or blasts), speed and lifetime where it moves or lasts,
## shots, spread and pierce where it fires shots that use them. A behaviour card is judged by its
## behaviour (`behaviour_waste`), its numbers ride with it.
static func _numbers_waste(modifier: ModifierBase, motion: FormBase.Motion, blasts: bool) -> String:
	if modifier.behaviour != ModifierBase.Behaviour.NONE:
		return ""
	var any: bool = false
	if modifier.cooldown_mult < 1.0 or not is_equal_approx(modifier.radius_mult, 1.0):
		return ""
	if modifier.damage_mult > 1.0:
		any = true
		if hits(motion) or blasts:
			return ""
	if not is_equal_approx(modifier.speed_mult, 1.0) or not is_equal_approx(modifier.lifetime_mult, 1.0):
		any = true
		if motion != FormBase.Motion.FISSURE and motion != FormBase.Motion.TELEPORT:
			return ""
	if modifier.shot_mult != 1:
		any = true
		if motion != FormBase.Motion.DASH and motion != FormBase.Motion.TELEPORT:
			return ""
	if not is_equal_approx(modifier.spread_mult, 1.0):
		any = true
		match motion:
			FormBase.Motion.STRAIGHT, FormBase.Motion.RAY, FormBase.Motion.FISSURE, FormBase.Motion.HOOK, FormBase.Motion.SWAP, FormBase.Motion.SWING, FormBase.Motion.SLAM:
				return ""
	if modifier.extra_pierce != 0:
		any = true
		if stays(motion) or motion == FormBase.Motion.RAY:
			return ""
	if not any:
		return ""
	return "none of its numbers count here: %s" % _what(motion)


## A compiled spell from a carrier (or none, for a fallback) and the cards that attach to it.
func _build(form: FormBase, elements: Array[ElementBase], modifiers: Array[ModifierBase], trigger: TriggerBase, fallback: int) -> CompiledSpell:
	var spell := CompiledSpell.new()
	spell.node = _out.nodes.size()
	_out.nodes.append(spell)
	spell.fallback = fallback
	spell.behaviours.resize(ModifierBase.Behaviour.size())
	var damage: float = SpellLimits.FALLBACK_DAMAGE
	var mana: float = 0.0
	var cooldown: float = 0.0
	var speed: float = 0.0
	var radius: float = SpellLimits.FALLBACK_RADIUS
	var shots: int = 1
	var pierce: int = 0
	var homing_reach: float = 0.0
	var heals: bool = false
	var later_ids: Array[StringName] = []
	var later_durations: PackedFloat32Array = PackedFloat32Array()
	var later_strengths: PackedFloat32Array = PackedFloat32Array()
	spell.motion = FormBase.Motion.STILL
	spell.lifetime = SpellLimits.MIN_LIFETIME
	if form != null:
		spell.form_id = form.id
		spell.form_name = _name(form)
		spell.motion = form.motion
		spell.lifetime = form.lifetime
		spell.orbit_radius = form.orbit_radius
		spell.ray_length = form.ray_length
		spell.arc = form.arc
		spell.wind_up = form.wind_up
		spell.staff_pose = form.packed_pose()
		spell.spread = form.spread
		damage = form.base_damage
		mana = form.mana_cost
		cooldown = form.cooldown
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
		cooldown *= modifier.cooldown_mult
		speed *= modifier.speed_mult
		radius *= modifier.radius_mult
		shots *= modifier.shot_mult
		pierce += modifier.extra_pierce
		spell.spread_mult *= modifier.spread_mult
		spell.lifetime *= modifier.lifetime_mult
		if modifier.behaviour == ModifierBase.Behaviour.ARC:
			spell.arc_reach = maxf(spell.arc_reach, modifier.behaviour_reach)
		spell.behaviours[modifier.behaviour] = stacked(modifier.behaviour, spell.behaviours[modifier.behaviour], modifier.behaviour_strength)
		if modifier.cue != &"" and not spell.behaviour_cues.has(modifier.behaviour):
			spell.behaviour_cues[modifier.behaviour] = modifier.cue
		match modifier.behaviour:
			ModifierBase.Behaviour.HOMING:
				# Homing stacks by multiplying: the strongest card's turn rate, x HOMING_STACK for
				# each more (owner, 2026-10-27); an instant carrier's bend follows from it.
				homing_reach = maxf(homing_reach, modifier.behaviour_reach)
				if spell.homing_turn <= 0.0:
					spell.homing_turn = modifier.behaviour_strength
				else:
					spell.homing_turn = maxf(spell.homing_turn, modifier.behaviour_strength) * SpellLimits.HOMING_STACK
			ModifierBase.Behaviour.CHAIN:
				spell.chain_jumps += int(modifier.behaviour_strength)
	spell.look = _look_of(elements, modifiers)
	spell.damage = maxi(roundi(damage), 1)
	spell.mana_cost = mana
	spell.cooldown = maxf(cooldown, 0.0)
	spell.speed = speed
	spell.radius = radius
	spell.shots = shots
	spell.shots_requested = shots
	spell.pierce = pierce
	if spell.shots > 1 and spell.spread <= 0.0 and spell.motion != FormBase.Motion.ORBIT:
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
	if spell.motion == FormBase.Motion.SWING:
		spell.hit.kind = &"swing"
	elif spell.motion == FormBase.Motion.SLAM:
		# A shockwave on an area: the hit kind of an area hit.
		spell.hit.kind = &"burst"
	elif spell.ray_length > 0.0 and spell.motion != FormBase.Motion.DASH and spell.motion != FormBase.Motion.TELEPORT:
		spell.hit.kind = &"ray"
	if spell.homing_turn > 0.0:
		spell.homing_range = homing_range(spell.motion, spell.ray_length, homing_reach)
		# Past 180 degrees it would be bending back the other way: that is all the way round.
		spell.homing_angle = minf(rad_to_deg(spell.homing_turn * SpellLimits.INSTANT_HOMING_SECONDS), 180.0)
	if heals:
		spell.hit.heal = spell.damage
		spell.hit.damage = maxi(roundi(float(spell.damage) * SpellLimits.HEAL_ENEMY_SHARE), 1)
	var heavy: float = spell.behaviour(ModifierBase.Behaviour.HEAVY)
	if heavy > 0.0:
		spell.hit.knockback *= heavy
		spell.hit.slam = roundi(float(spell.damage) * SpellLimits.SLAM_SHARE)
	if spell.behaviour(ModifierBase.Behaviour.ECHO) > 0.0:
		spell.echo_hit = spell.hit.scaled(SpellLimits.ECHO_DAMAGE, 1.0)
	var arc: float = spell.behaviour(ModifierBase.Behaviour.ARC)
	if arc > 0.0:
		# Zaps per second add up over arc cards (a shot zaps at most once a physics step); a zap
		# hits like a ray, at ARC_DAMAGE of the shot.
		spell.arc_interval = 1.0 / arc
		spell.arc_hit = zap_hit(spell.hit)
		if spell.echo_hit != null:
			spell.echo_arc_hit = zap_hit(spell.echo_hit)
	if trigger != null:
		spell.trigger_id = trigger.id
		spell.trigger_event = trigger.event
		spell.trigger_interval = trigger.interval
	_cast.mana += spell.mana_cost
	_cast.delay += spell.cooldown
	return spell


## What a zap (`arc`) of a shot that hits with `hit` does: the same hit, ray kind, at ARC_DAMAGE of
## its strength and knockback. Spells asks it again for a shot whose hit changed (`relay`).
static func zap_hit(hit: HitProfile) -> HitProfile:
	var zap: HitProfile = hit.scaled(SpellLimits.ARC_DAMAGE, SpellLimits.ARC_DAMAGE)
	zap.kind = &"ray"
	return zap


## The strength of `behaviour` after one more card of `strength` on top of `before` (0 for none):
## counts add (bounces, shields, seconds, pixels) and multipliers multiply (heavy's knockback,
## growth's factor; rule 3, docs/milestones/M2-rules.md R1c), so two heavy cards are 4 x 4, not 4 + 4.
## Homing multiplies too, by its own rule (HOMING_STACK).
static func stacked(behaviour: int, before: float, strength: float) -> float:
	if before > 0.0 and MULTIPLIED.has(behaviour):
		return before * strength
	return before + strength


## Whether homing can steer a carrier of `motion`: what it moves turns toward a target as it
## goes, at the turn rate (a shot in flight, a dash, whether it carries the wizard or a shot),
## a still shot (a rune) creeps toward one at SpellLimits.HOMING_DRIFT, what is over at once
## bends its way toward one, up to `homing_angle` (a beam, a teleport), and what is placed ahead
## of its caster is placed on one near that point (a wall, a rain; rules R4i). On any other form
## a homing card is wasted. A new motion that should home goes here, and the homing test of
## every form card (tests/content/spells/test_homing_forms.gd) checks it reaches.
static func homing_steers(motion: FormBase.Motion) -> bool:
	match motion:
		FormBase.Motion.STRAIGHT, FormBase.Motion.STILL, FormBase.Motion.HOOK, FormBase.Motion.SWAP, FormBase.Motion.RAY, FormBase.Motion.DASH, FormBase.Motion.TELEPORT, FormBase.Motion.WALL, FormBase.Motion.RAIN:
			return true
	return false


## True when a carrier of `motion` can run `behaviour` (`behaviour_waste` gives no reason). A
## card whose behaviour cannot run is wasted.
static func behaviour_runs(behaviour: int, motion: FormBase.Motion, blasts: bool = false) -> bool:
	return behaviour_waste(behaviour, motion, blasts).is_empty()


## Why a carrier of `motion` cannot run `behaviour`, for the wasted card's reason, or "" when it
## runs it: the one table of behaviour x carrier (rule 1, docs/milestones/M2-rules.md R2a). It says
## what the runtime really does: a behaviour that does nothing on a carrier is listed here, never
## left silent, and a wasted card changes nothing else either (its numbers too). When the runtime
## learns a behaviour on a new carrier, the carrier comes off its list here in the same change;
## tests/core/test_card_rules.gd plays every card on every carrier and fails on a silent one.
## `blasts` is true when the carrier also has a blast: its area hit carries heavy's knockback and
## slam even on a carrier that hits nothing itself (it sends no shot hit, so no chain or siphon).
static func behaviour_waste(behaviour: int, motion: FormBase.Motion, blasts: bool = false) -> String:
	match behaviour:
		ModifierBase.Behaviour.HOMING:
			return "" if homing_steers(motion) else "it has nothing to aim, and %s" % _what(motion)
		ModifierBase.Behaviour.RETURN:
			return "" if flies(motion) else "it does not fly out"
		ModifierBase.Behaviour.ARC:
			return "" if stays(motion) else "it is not a shot that stays in the air"
		ModifierBase.Behaviour.DEFLECT:
			return "" if guards(motion) or motion == FormBase.Motion.HOOK or motion == FormBase.Motion.SWAP else "it touches no shots"
		ModifierBase.Behaviour.GROWTH:
			return "" if stays(motion) else "it grows a shot in the world, and %s" % _what(motion)
		ModifierBase.Behaviour.SPIRAL, ModifierBase.Behaviour.LINGER, ModifierBase.Behaviour.STICKY:
			if flies(motion) or motion == FormBase.Motion.ORBIT:
				return ""
			return "it does not move" if stays(motion) else "it only changes a moving shot, and %s" % _what(motion)
		ModifierBase.Behaviour.GHOST:
			if motion == FormBase.Motion.ORBIT:
				return "an orbit already passes walls"
			return "" if flies(motion) else "it only takes a flying shot through walls, and %s" % _what(motion)
		ModifierBase.Behaviour.BOUNCE:
			if flies(motion) or motion == FormBase.Motion.RAY or motion == FormBase.Motion.FISSURE:
				return ""
			return "it turns a shot or a beam at walls, and %s" % _what(motion)
		ModifierBase.Behaviour.HEAVY:
			return "" if hits(motion) or blasts else "it acts on what the carrier hits, and %s (a blast would carry it)" % _what(motion)
		ModifierBase.Behaviour.CHAIN, ModifierBase.Behaviour.SIPHON, ModifierBase.Behaviour.POSSESS:
			return "" if hits(motion) else "it acts on what the carrier hits, and %s" % _what(motion)
		ModifierBase.Behaviour.MAGNET, ModifierBase.Behaviour.RELAY:
			return "" if stays(motion) else "it needs a shot that stays in the world, and %s" % _what(motion)
		ModifierBase.Behaviour.SHIELD:
			match motion:
				FormBase.Motion.RAIN, FormBase.Motion.DECOY, FormBase.Motion.FAMILIAR:
					return "it blocks shots that touch the carrier or guards the caster on a move, and %s" % _what(motion)
		ModifierBase.Behaviour.MIRROR:
			match motion:
				FormBase.Motion.STRAIGHT, FormBase.Motion.RAY, FormBase.Motion.FISSURE, FormBase.Motion.SWING, FormBase.Motion.SLAM:
					return ""
			return "only a straight shot, a beam, a fissure, a swing and a slam fire backwards"
		ModifierBase.Behaviour.HOLD:
			match motion:
				FormBase.Motion.DASH, FormBase.Motion.TELEPORT, FormBase.Motion.RAIN, FormBase.Motion.FISSURE, FormBase.Motion.SWING, FormBase.Motion.SLAM:
					return "nothing keeps it on: %s" % _what(motion)
		ModifierBase.Behaviour.RECOIL:
			match motion:
				FormBase.Motion.DASH, FormBase.Motion.TELEPORT:
					return "it moves the wizard itself"
	return ""


## True for the carriers that are a shot flying out on its own (a bolt, a hook, a swap).
static func flies(motion: FormBase.Motion) -> bool:
	return motion == FormBase.Motion.STRAIGHT or motion == FormBase.Motion.HOOK or motion == FormBase.Motion.SWAP


## True for the carriers that are shots staying in the world for a while (a bolt, a rune, an orbit,
## a wall, a hook, a swap): what rides on a live shot (arc, magnet, relay) runs on them.
static func stays(motion: FormBase.Motion) -> bool:
	match motion:
		FormBase.Motion.STRAIGHT, FormBase.Motion.STILL, FormBase.Motion.ORBIT, FormBase.Motion.HOOK, FormBase.Motion.SWAP, FormBase.Motion.WALL:
			return true
	return false


## True for the carriers that hit under their own tag (a shot, a beam, a fissure, a swing, a slam):
## a rain's payload, a dash, a teleport, a decoy and a familiar hit nothing themselves.
static func hits(motion: FormBase.Motion) -> bool:
	return stays(motion) or motion == FormBase.Motion.RAY or motion == FormBase.Motion.FISSURE or motion == FormBase.Motion.SWING or motion == FormBase.Motion.SLAM


## What a carrier of `motion` is, for a wasted card's reason.
static func _what(motion: FormBase.Motion) -> String:
	match motion:
		FormBase.Motion.STRAIGHT:
			return "a bolt flies on its own"
		FormBase.Motion.STILL:
			return "a rune stays where it is"
		FormBase.Motion.ORBIT:
			return "an orbit is held on its circle"
		FormBase.Motion.RAY:
			return "a beam is a line, not a shot"
		FormBase.Motion.DASH:
			return "a dash moves the wizard and hits nothing"
		FormBase.Motion.TELEPORT:
			return "a teleport moves the wizard and hits nothing"
		FormBase.Motion.WALL:
			return "a wall stands still"
		FormBase.Motion.RAIN:
			return "a rain only drops its payload"
		FormBase.Motion.FISSURE:
			return "a fissure is a crack that is over at once"
		FormBase.Motion.DECOY:
			return "a decoy is a body that hits nothing"
		FormBase.Motion.FAMILIAR:
			return "a familiar is a body that hits nothing"
		FormBase.Motion.SWING:
			return "a swing is a sweep that is over at once"
		FormBase.Motion.SLAM:
			return "a slam is a strike that is over at once"
	return "this carrier cannot run it"


## True for the carriers whose shield only stops shots that touch them (a shot, a beam's line, a
## swing's sweep): on these a deflect turns every such shot first (owner, 2026-10-29), so a shield
## with it never blocks. A hook's shield also guards its caster on the pull, a dash's and a
## teleport's is a barrier on the caster: those keep it.
static func guards(motion: FormBase.Motion) -> bool:
	match motion:
		FormBase.Motion.STRAIGHT, FormBase.Motion.STILL, FormBase.Motion.ORBIT, FormBase.Motion.WALL, FormBase.Motion.RAY, FormBase.Motion.FISSURE, FormBase.Motion.SWING, FormBase.Motion.SLAM:
			return true
	return false


## True when `modifier` is a shield that a deflect on a carrier of `motion` leaves with nothing to do.
static func _shield_outrun(modifier: ModifierBase, motion: FormBase.Motion) -> bool:
	return modifier.behaviour == ModifierBase.Behaviour.SHIELD and guards(motion)


## True when a trigger of `event` (`TriggerBase.Event`) can fire on a carrier of `motion`: the
## carrier makes that event under its own tag at runtime (core/spells/spells.gd), with the right
## cards on it (`_trigger_never` checks those). Where it cannot, the trigger and its payload are
## wasted (rules R2b, docs/milestones/M2-rules.md). The table is what the runtime does today:
## - on expire and on cast: every carrier (each has an end point; each is cast).
## - on kill and on reaction: every carrier, by its hits, or by its blast's area hit on one
##   that hits nothing itself (dash, teleport, rain, decoy, familiar).
## - on hit: the carriers that hit (`hits`).
## - timer and on hurt: only shots the projectile manager holds (`_register` keeps their clock
##   and their hurt slot); a beam, fissure, swing, move, rain or entity has none (R4).
## - on block: a shot, beam, fissure or swing with a shield or deflect, and a dash's or
##   teleport's barrier; a rain, decoy or familiar has nothing that blocks.
## - on wall: a flying shot (bolt, hook, swap) at a wall it bounces off or ends on, and a beam
##   or fissure at a wall it turns at or ends on.
static func trigger_runs(event: int, motion: FormBase.Motion) -> bool:
	return trigger_why_not(event, motion).is_empty()


## Why a trigger of `event` never fires on a carrier of `motion` (`trigger_runs`), in words a
## player reads after "On Hit does nothing on a Rain: "; "" when it can fire.
static func trigger_why_not(event: int, motion: FormBase.Motion) -> String:
	match event:
		TriggerBase.Event.HIT:
			if not hits(motion):
				return _hits_nothing(motion)
		TriggerBase.Event.TIMER, TriggerBase.Event.HURT:
			if not stays(motion):
				var what: String = "keeps a timer" if event == TriggerBase.Event.TIMER else "hears you get hurt"
				return "only a shot that flies or stays %s for now" % what
		TriggerBase.Event.BLOCK:
			if not (stays(motion) or hits(motion) or motion == FormBase.Motion.DASH or motion == FormBase.Motion.TELEPORT):
				return "nothing on it can block a shot"
		TriggerBase.Event.WALL:
			if not (flies(motion) or motion == FormBase.Motion.RAY or motion == FormBase.Motion.FISSURE):
				match motion:
					FormBase.Motion.STILL, FormBase.Motion.WALL:
						return "it stays where it is and never meets a wall"
					FormBase.Motion.ORBIT:
						return "an orbit passes through walls"
					FormBase.Motion.SWING:
						return "a swing's sweep never meets a wall"
					FormBase.Motion.SLAM:
						return "a slam strikes short of a wall and its ring never meets one"
					FormBase.Motion.DASH, FormBase.Motion.TELEPORT:
						return "it stops before walls"
				return _hits_nothing(motion)
	return ""


## Why a carrier that hits nothing under its own tag sets off no hit, for a reason.
static func _hits_nothing(motion: FormBase.Motion) -> String:
	match motion:
		FormBase.Motion.DASH:
			return "a dash moves you and hits nothing"
		FormBase.Motion.TELEPORT:
			return "a teleport moves you and hits nothing"
		FormBase.Motion.RAIN:
			return "a rain hits nothing itself, only what it drops does"
		FormBase.Motion.DECOY:
			return "a decoy hits nothing"
		FormBase.Motion.FAMILIAR:
			return "a familiar hits nothing itself, only what it casts does"
	return "it hits nothing"


## How far a homing carrier looks for its target, the one rule for every form: as far as its
## homing cards reach (`ModifierBase.behaviour_reach`, the largest), and one that is over at
## once (a beam, a teleport) at least as far as it goes, so its far end homes too (a card that
## reaches further bends it toward targets past its end). 0 where homing cannot steer.
static func homing_range(motion: FormBase.Motion, ray_length: float, reach: float) -> float:
	if not homing_steers(motion):
		return 0.0
	if motion == FormBase.Motion.RAY or motion == FormBase.Motion.TELEPORT:
		return maxf(reach, ray_length)
	return reach


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


func _waste(slot: int, reason: String) -> void:
	_cast.wasted[slot] = reason


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
		_:
			names.append(spell.form_name)
			text = " ".join(names)
			var modifiers: PackedStringArray = _modifier_names(spell)
			if not modifiers.is_empty():
				text += " (%s)" % ", ".join(modifiers)
	if spell.own_payload != null and not spell.own_payload.is_empty():
		text += " carrying %s" % _group_text(spell.own_payload)
	if spell.payload != null:
		var when: String = WHEN[spell.trigger_event] if spell.trigger_event < WHEN.size() else "then"
		if spell.trigger_event == TriggerBase.Event.TIMER:
			when = when % _number(spell.trigger_interval)
		text += "; %s: %s" % [when, _group_text(spell.payload)]
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
