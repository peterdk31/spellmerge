extends "res://tests/support/suite.gd"
## Tests for the staff compiler (staffs A4): every example of docs/milestones/M2-staffs.md,
## "Reading a staff", as slots in and casts out, plus the numbers of a cast, fallbacks, wasted
## cards and the builder view. Cards are built in code behind a stand-in registry.
##
## godot --headless --path . --script res://tests/core/test_staff_compiler.gd

const SpellsScript := preload("res://core/spells/spells.gd")


## A registry stand-in with the same question as the real one.
class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _spells: Node
var _fake: FakeRegistry
var _staff: StaffBase


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_spells = own(SpellsScript.new())
	_spells.set("registry", _fake)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 20
	_staff.cast_delay = 0.1
	_staff.recharge = 0.5
	var bolt: FormBase = _form(&"bolt", 5, 1)
	bolt.cooldown = 0.2
	var nova: FormBase = _form(&"nova", 4, 8)
	nova.spread = 360.0
	nova.cooldown = 0.4
	_form(&"rain", 3, 1).carrier = &"rain"
	_element(&"fire", &"burn", 1.5)
	_element(&"frost", &"chill", 1.0)
	_modifier(&"split").shot_mult = 3
	var homing: ModifierBase = _modifier(&"homing")
	homing.behaviour = ModifierBase.Behaviour.HOMING
	homing.behaviour_strength = 4.0
	homing.behaviour_reach = 160.0
	var bigger: ModifierBase = _modifier(&"bigger")
	bigger.radius_mult = 2.0
	bigger.damage_mult = 2.0
	_modifier(&"faster").speed_mult = 2.0
	var blast: ModifierBase = _modifier(&"blast")
	blast.behaviour = ModifierBase.Behaviour.BLAST
	blast.behaviour_strength = 24.0
	var shield: ModifierBase = _modifier(&"shield")
	shield.behaviour = ModifierBase.Behaviour.SHIELD
	shield.behaviour_strength = 1.0
	_trigger(&"on_hit", TriggerBase.Event.HIT)
	_trigger(&"on_expire", TriggerBase.Event.EXPIRE)
	_multicast(&"double", 1, MulticastBase.Mode.TOGETHER)
	_multicast(&"scatter", 2, MulticastBase.Mode.SCATTER)
	var burst: MulticastBase = _multicast(&"burst", 0, MulticastBase.Mode.BURST)
	burst.repeats = 3
	burst.repeat_interval = 0.08


func _put(card: SpellComponent, id: StringName) -> void:
	card.id = id
	card.display_name = String(id).capitalize()
	_fake.items[id] = card


func _form(id: StringName, damage: int, shots: int) -> FormBase:
	var form := FormBase.new()
	form.base_damage = damage
	form.shots = shots
	form.speed = 300.0
	form.mana_cost = 2.0
	_put(form, id)
	return form


func _element(id: StringName, status: StringName, scale: float) -> ElementBase:
	var element := ElementBase.new()
	element.status_id = status
	element.status_duration = 2.0
	element.damage_scale = scale
	_put(element, id)
	return element


func _modifier(id: StringName) -> ModifierBase:
	var modifier := ModifierBase.new()
	_put(modifier, id)
	return modifier


func _trigger(id: StringName, event: TriggerBase.Event) -> TriggerBase:
	var trigger := TriggerBase.new()
	trigger.event = event
	_put(trigger, id)
	return trigger


func _multicast(id: StringName, extra: int, mode: MulticastBase.Mode) -> MulticastBase:
	var multicast := MulticastBase.new()
	multicast.extra_draws = extra
	multicast.mode = mode
	_put(multicast, id)
	return multicast


## Compiles a staff from card ids written as one string, slots separated by spaces ("-" is an
## empty slot), as the design writes them with dots.
func _compile(cards: String) -> CompiledStaff:
	var ids: Array[StringName] = []
	for word in cards.split(" ", false):
		ids.append(&"" if word == "-" else StringName(word))
	return _spells.call("compile_staff", ids, _staff) as CompiledStaff


func _forms(group: CompiledGroup) -> Array[StringName]:
	var out: Array[StringName] = []
	for spell in group.spells:
		out.append(spell.form_id)
	return out


# --- The examples of "Reading a staff" ----------------------------------------

func test_two_casts_then_recharge() -> void:
	var staff: CompiledStaff = _compile("fire bolt frost nova")
	check_equal(staff.casts.size(), 2, "two casts")
	var first: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal([first.form_id, first.element_id], [&"bolt", &"fire"], "cast 1 is a fire bolt")
	var second: CompiledSpell = staff.casts[1].group.spells[0]
	check_equal([second.form_id, second.element_id], [&"nova", &"frost"], "cast 2 is a frost nova")
	check(not staff.casts[0].recharges, "cast 1 does not recharge")
	check(staff.casts[1].recharges, "cast 2 recharges")


func test_a_trailing_modifier_wraps_onto_the_first_carrier() -> void:
	var staff: CompiledStaff = _compile("blast bolt blast")
	check_equal(staff.casts.size(), 2, "two casts")
	check_equal(staff.casts[0].group.spells[0].modifier_ids, [&"blast"] as Array[StringName], "cast 1: a bolt with one blast")
	var second: CompiledSpell = staff.casts[1].group.spells[0]
	check_equal(second.form_id, &"bolt", "cast 2 wraps to the bolt")
	check_equal(second.modifier_ids, [&"blast", &"blast"] as Array[StringName], "cast 2: a bolt with two blasts")
	check(staff.casts[1].wrapped, "cast 2 wrapped")
	check(staff.casts[1].recharges, "a wrapped cast recharges")


func test_a_lone_blast_explodes_on_the_caster() -> void:
	var staff: CompiledStaff = _compile("blast")
	check_equal(staff.casts.size(), 1, "one cast")
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(spell.fallback, CompiledSpell.FALLBACK_CASTER, "it lands on the caster")
	check(spell.behaviour(ModifierBase.Behaviour.BLAST) > 0.0, "it blasts")
	check_equal(staff.casts[0].targets[0], StaffCompiler.TARGET_CASTER, "the plan links it to the caster")
	check(staff.casts[0].recharges, "and the staff recharges")


func test_double_with_a_payload_on_the_second_bolt() -> void:
	var staff: CompiledStaff = _compile("double fire bolt on_hit bolt frost nova")
	check_equal(staff.casts.size(), 1, "one cast")
	var group: CompiledGroup = staff.casts[0].group
	check_equal(_forms(group), [&"bolt", &"bolt"] as Array[StringName], "two bolts together")
	check_equal(group.spells[0].element_id, &"fire", "the first is a fire bolt")
	check(group.spells[0].payload == null, "the first holds nothing")
	check_equal(group.spells[1].element_id, &"", "the second is plain")
	var payload: CompiledGroup = group.spells[1].payload
	check(payload != null, "the second has a payload")
	if payload != null:
		check_equal([payload.spells[0].form_id, payload.spells[0].element_id], [&"nova", &"frost"], "a frost nova on hit")


func test_a_group_resumes_after_its_payload() -> void:
	var staff: CompiledStaff = _compile("double on_hit bolt nova bolt")
	check_equal(staff.casts.size(), 1, "one cast")
	var group: CompiledGroup = staff.casts[0].group
	check_equal(_forms(group), [&"bolt", &"bolt"] as Array[StringName], "the last bolt joins the cast")
	check_equal(_forms(group.spells[0].payload), [&"nova"] as Array[StringName], "the first fires a nova on hit")
	check(group.spells[1].payload == null, "the last bolt holds nothing")
	check(staff.casts[0].recharges, "then recharge")


func test_a_lone_modifier_in_a_payload_lands_on_its_origin() -> void:
	var staff: CompiledStaff = _compile("on_hit bolt blast")
	var bolt: CompiledSpell = staff.casts[0].group.spells[0]
	check(bolt.payload != null, "the bolt has a payload")
	if bolt.payload != null:
		check_equal(bolt.payload.spells[0].fallback, CompiledSpell.FALLBACK_POINT, "the blast lands where the bolt hits, not on the caster")
	check_equal(staff.casts[0].targets[2], StaffCompiler.TARGET_POINT, "the plan links it to the payload's origin")


func test_a_trigger_with_nothing_after_it_is_wasted() -> void:
	var staff: CompiledStaff = _compile("on_hit bolt")
	check_equal(staff.casts.size(), 1, "one cast")
	check(staff.casts[0].group.spells[0].payload == null, "no payload")
	check(staff.wasted.has(0), "the trigger is wasted: %s" % staff.wasted)
	check(staff.casts[0].recharges, "it wrapped, so it recharges")


func test_magnet_on_a_payload_fired_from_a_point_is_wasted() -> void:
	var magnet: ModifierBase = _modifier(&"magnet")
	magnet.behaviour = ModifierBase.Behaviour.MAGNET
	magnet.behaviour_strength = 70.0
	var staff: CompiledStaff = _compile("magnet bolt")
	check(not staff.wasted.has(0), "on a bolt it counts")
	staff = _compile("on_hit bolt magnet")
	check(staff.wasted.has(2), "in a payload from a point it is wasted: %s" % staff.wasted)


func test_a_trigger_in_the_last_slot_wraps_and_is_wasted() -> void:
	var staff: CompiledStaff = _compile("bolt on_hit")
	check_equal(staff.casts.size(), 2, "two casts")
	check_equal(_forms(staff.casts[1].group), [&"bolt"] as Array[StringName], "cast 2 wraps to the bolt")
	check(staff.casts[1].wrapped, "cast 2 wrapped")
	check(staff.wasted.has(1), "the trigger is wasted")


func test_a_counter_dash_reads_in_slot_order() -> void:
	_form(&"dash", 1, 1).carrier = &"dash"
	_trigger(&"on_block", TriggerBase.Event.BLOCK)
	var staff: CompiledStaff = _compile("shield on_block dash nova")
	var dash: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(dash.form_id, &"dash", "a dash")
	check_equal(dash.behaviour(ModifierBase.Behaviour.SHIELD), 1.0, "with one shield")
	check(dash.fires_on(TriggerBase.Event.BLOCK), "that fires on a block")
	check_equal(_forms(dash.payload), [&"nova"] as Array[StringName], "a nova")


# --- More rules ---------------------------------------------------------------

func test_a_steering_modifier_on_the_caster_is_wasted() -> void:
	var staff: CompiledStaff = _compile("homing fire")
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(spell.fallback, CompiledSpell.FALLBACK_CASTER, "fire lands on the caster")
	check(not spell.modifier_ids.has(&"homing"), "homing does not")
	check(staff.wasted.has(0), "homing is wasted with a reason")


func test_how_far_homing_looks_comes_from_the_card_and_a_beam_s_length() -> void:
	var far: ModifierBase = _modifier(&"far_homing")
	far.behaviour = ModifierBase.Behaviour.HOMING
	far.behaviour_strength = 2.0
	far.behaviour_reach = 240.0
	var beam: FormBase = _form(&"beam", 3, 1)
	beam.carrier = &"beam"
	beam.ray_length = 300.0
	var rune: FormBase = _form(&"rune", 3, 1)
	rune.carrier = &"rune"
	var orbit: FormBase = _form(&"orbit", 3, 1)
	orbit.carrier = &"orbit"
	check_equal((_compile("homing bolt").casts[0].group.spells[0] as CompiledSpell).homing_range, 160.0, "a bolt looks as far as its card reaches")
	check_equal((_compile("far_homing bolt").casts[0].group.spells[0] as CompiledSpell).homing_range, 240.0, "a card that reaches further looks further, with no change to core")
	check_equal((_compile("homing far_homing bolt").casts[0].group.spells[0] as CompiledSpell).homing_range, 240.0, "two cards look as far as the further one")
	check_equal((_compile("homing beam").casts[0].group.spells[0] as CompiledSpell).homing_range, 300.0, "a beam looks at least as far as it is long")
	beam.ray_length = 200.0
	check_equal((_compile("far_homing beam").casts[0].group.spells[0] as CompiledSpell).homing_range, 240.0, "and as far as its card reaches, past its end")
	check_equal((_compile("bolt").casts[0].group.spells[0] as CompiledSpell).homing_range, 0.0, "no homing card, no homing")
	check_equal((_compile("homing rune").casts[0].group.spells[0] as CompiledSpell).homing_range, 160.0, "a rune homes as far as its card reaches (it creeps, rules R4i)")
	var staff: CompiledStaff = _compile("homing orbit")
	check_equal((staff.casts[0].group.spells[0] as CompiledSpell).homing_range, 0.0, "an orbit has nothing to aim")
	check(staff.wasted.has(0) and not (staff.casts[0].group.spells[0] as CompiledSpell).modifier_ids.has(&"homing"), "so homing on it is wasted and left off it")


func test_a_shield_means_nothing_at_a_payload_origin() -> void:
	var staff: CompiledStaff = _compile("on_hit bolt shield")
	check(staff.casts[0].group.spells[0].payload == null, "nothing lands there")
	check(staff.wasted.has(2), "the shield is wasted")


func test_several_infusions_ride_one_shot_first_one_first() -> void:
	var spell: CompiledSpell = _compile("fire frost bolt").casts[0].group.spells[0]
	check_equal(spell.element_ids, [&"fire", &"frost"] as Array[StringName], "both elements, in order")
	check_equal(spell.element_id, &"fire", "the first sets the status and the look")
	check_equal(spell.hit.element_ids, [&"fire", &"frost"] as Array[StringName], "the hit carries both")


func test_each_trigger_takes_its_own_payload_in_order() -> void:
	var staff: CompiledStaff = _compile("on_hit on_expire bolt nova fire bolt")
	check_equal(staff.casts.size(), 1, "one cast reads both payloads")
	check(staff.wasted.is_empty(), "nothing is wasted: %s" % staff.wasted)
	var bolt: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(bolt.triggers.size(), 2, "two triggers")
	if bolt.triggers.size() == 2:
		check_equal(bolt.triggers[0].event, TriggerBase.Event.HIT, "the first is on hit")
		check_equal(_forms(bolt.triggers[0].payload), [&"nova"] as Array[StringName], "and fires the nova")
		check_equal(bolt.triggers[1].event, TriggerBase.Event.EXPIRE, "the second is on expire")
		check_equal(_forms(bolt.triggers[1].payload), [&"bolt"] as Array[StringName], "and fires the next group, the fire bolt")
		check_equal(bolt.triggers[1].payload.spells[0].element_id, &"fire", "with its fire")
	check_equal(staff.casts[0].targets.get(0, -1), 2, "on hit goes on the bolt")
	check_equal(staff.casts[0].targets.get(1, -1), 2, "on expire goes on the bolt")
	check(staff.casts[0].recharges, "no card is left: recharge")


func test_the_same_trigger_twice_fires_two_payloads() -> void:
	var bolt: CompiledSpell = _compile("on_hit on_hit bolt nova bolt").casts[0].group.spells[0]
	check_equal(bolt.triggers.size(), 2, "both count")
	if bolt.triggers.size() == 2:
		check_equal(_forms(bolt.triggers[0].payload), [&"nova"] as Array[StringName], "a nova on hit")
		check_equal(_forms(bolt.triggers[1].payload), [&"bolt"] as Array[StringName], "and a bolt on hit")


func test_a_trigger_with_no_cards_left_is_wasted_and_the_others_keep_theirs() -> void:
	var staff: CompiledStaff = _compile("on_hit on_expire bolt nova")
	var bolt: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(bolt.triggers.size(), 1, "only on hit has a payload")
	check(not staff.wasted.has(0), "on hit counts")
	check(staff.wasted.has(1), "on expire finds nothing to fire (the read wraps to used cards) and is wasted: %s" % staff.wasted)


func test_payloads_nest_before_the_next_trigger_reads() -> void:
	# On hit: a bolt that, on expire, fires a nova. On expire: a fire bolt.
	var staff: CompiledStaff = _compile("on_hit on_expire bolt on_expire bolt nova fire bolt")
	var bolt: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(bolt.triggers.size(), 2, "two triggers")
	if bolt.triggers.size() == 2:
		var inner: CompiledSpell = bolt.triggers[0].payload.spells[0]
		check_equal(inner.form_id, &"bolt", "on hit fires a bolt")
		check_equal(_forms(inner.payload), [&"nova"] as Array[StringName], "whose own payload is read first")
		check_equal(bolt.triggers[1].payload.spells[0].element_id, &"fire", "then on expire takes the fire bolt")


func test_a_multicast_in_one_payload_counts_for_that_payload_only() -> void:
	var bolt: CompiledSpell = _compile("on_hit on_expire bolt double nova nova bolt").casts[0].group.spells[0]
	check_equal(bolt.triggers.size(), 2, "two triggers")
	if bolt.triggers.size() == 2:
		check_equal(_forms(bolt.triggers[0].payload), [&"nova", &"nova"] as Array[StringName], "the double takes two novas")
		check_equal(_forms(bolt.triggers[1].payload), [&"bolt"] as Array[StringName], "the next payload starts after them")


func test_a_trigger_that_never_fires_keeps_its_place_and_the_next_still_reads() -> void:
	_form(&"slam", 1, 1).carrier = &"slam"
	_trigger(&"timer", TriggerBase.Event.TIMER).interval = 0.5
	# A slam is over at once: its timer never fires, but it still reads the nova, so on hit gets the bolt.
	var staff: CompiledStaff = _compile("timer on_hit slam nova bolt")
	var slam: CompiledSpell = staff.casts[0].group.spells[0]
	check(staff.wasted.has(0) and staff.wasted.has(3), "the timer and its nova are wasted: %s" % staff.wasted)
	check_equal(slam.triggers.size(), 1, "only on hit is left")
	if slam.triggers.size() == 1:
		check_equal(_forms(slam.triggers[0].payload), [&"bolt"] as Array[StringName], "and it fires the bolt")


func test_triggers_with_no_carrier_are_all_wasted() -> void:
	var staff: CompiledStaff = _compile("on_hit on_expire")
	check(staff.wasted.has(0) and staff.wasted.has(1), "both are wasted: %s" % staff.wasted)


func test_scatter_and_burst_mark_the_group() -> void:
	var scattered: CompiledGroup = _compile("scatter bolt bolt bolt").casts[0].group
	check(scattered.scatter, "scatter")
	check_equal(scattered.spells.size(), 3, "three carriers")
	var burst: CompiledGroup = _compile("burst bolt").casts[0].group
	check_equal(burst.repeats, 3, "burst fires the group three times")
	check_equal(burst.spells.size(), 1, "the same one carrier")


func test_rain_carries_its_own_payload() -> void:
	var rain: CompiledSpell = _compile("rain frost nova").casts[0].group.spells[0]
	check(rain.own_payload != null, "rain reads a payload")
	if rain.own_payload != null:
		check_equal(rain.own_payload.spells[0].element_id, &"frost", "a frost nova falls")


func test_the_numbers_of_a_cast() -> void:
	var cast: CompiledCast = _compile("fire bolt").casts[0]
	check_equal(cast.mana, 2.0, "the bolt's mana")
	check(is_equal_approx(cast.delay, 0.1 + 0.2 + 0.5), "staff delay + bolt cooldown + recharge, got %s" % cast.delay)
	var split: CompiledSpell = _compile("split bolt").casts[0].group.spells[0]
	check_equal(split.shots, 3, "split triples the shots")
	var many: CompiledSpell = _compile("split split split nova").casts[0].group.spells[0]
	check_equal(many.shots, 216, "no shot limit any more")


func test_an_empty_staff_has_no_cast_and_unknown_cards_are_wasted() -> void:
	check(_compile("- - -").is_empty(), "no cards, no cast")
	var staff: CompiledStaff = _compile("nope bolt")
	check(staff.wasted.has(0), "an unknown id is wasted")
	check_equal(_forms(staff.casts[0].group), [&"bolt"] as Array[StringName], "the rest still casts")


func test_cards_past_the_staff_slots_are_ignored() -> void:
	_staff.slots = 1
	var staff: CompiledStaff = _compile("bolt nova")
	check_equal(staff.casts.size(), 1, "one slot, one cast")
	check_equal(_forms(staff.casts[0].group), [&"bolt"] as Array[StringName], "only the bolt")


func test_every_compiled_spell_has_its_own_node() -> void:
	# Cast 1 is two bolts (one with a nova on hit); cast 2 reads the blast, wraps and reads the
	# same cards again, so the cycle holds six spells.
	var staff: CompiledStaff = _compile("double on_hit bolt nova bolt blast")
	check_equal(staff.casts.size(), 2, "two casts")
	check_equal(staff.nodes.size(), 6, "three spells per cast")
	for i in staff.nodes.size():
		check_equal(staff.nodes[i].node, i, "node %d knows its index" % i)


func test_the_builder_view_is_plain_values() -> void:
	var ids: Array[StringName] = [&"homing", &"fire"]
	var view: Dictionary = _spells.call("staff_view", ids, _staff)
	check(not bool(view["empty"]), "not empty")
	var casts: Array = view["casts"]
	check_equal(casts.size(), 1, "one cast")
	var cast: Dictionary = casts[0]
	check(String(cast["text"]).contains("on you: Fire"), "it reads as fire on the caster: %s" % cast["text"])
	check_equal((cast["targets"] as Dictionary)[1], StaffCompiler.TARGET_CASTER, "fire links to the caster")
	check((view["wasted"] as Dictionary).has(0), "homing on the caster is wasted")
	check_equal(view["staff"], _staff, "the staff comes back, to preview other cards with")


func test_each_kind_of_card_has_short_lines_of_its_numbers() -> void:
	var bolt: FormBase = _fake.items[&"bolt"]
	bolt.mana_cost = 5.0
	check_equal(_spells.call("component_stats", &"bolt"), PackedStringArray(["Dmg 5", "Mana 5", "Delay 0.2s"]), "a carrier: damage, mana, delay")
	check_equal((_spells.call("component_stats", &"nova") as PackedStringArray)[0], "Dmg 4x8", "shots multiply the damage")
	(_fake.items[&"split"] as ModifierBase).damage_mult = 0.5
	check_equal(_spells.call("component_stats", &"split"), PackedStringArray(["Dmg x0.5", "Shots x3"]), "a modifier: what it changes")
	check_equal(_spells.call("component_stats", &"homing"), PackedStringArray(["Homes in"]), "a behaviour in words")
	check_equal((_spells.call("component_stats", &"fire") as PackedStringArray)[0], "Burn %ss" % SpellsScript._short((_fake.items[&"fire"] as ElementBase).status_duration), "an element: its status and time")
	check_equal(_spells.call("component_stats", &"on_hit"), PackedStringArray(["On hit"]), "a trigger: when it fires")
	check_equal(_spells.call("component_stats", &"double"), PackedStringArray(["+1 carriers"]), "a multicast: its draws")
	check_equal(_spells.call("component_stats", &"no_such_card"), PackedStringArray(), "nothing for an unknown id")
	check_equal(SpellsScript._short(0.35), "0.35", "the leading zero stays, so the dot cannot be missed")
	check_equal(SpellsScript._short(1.5), "1.5", "no trailing zero")
	check_equal(SpellsScript._short(10.0), "10", "a whole number")


# --- The hit profile combat reads (staffs B3) ----------------------------------

func test_every_element_of_a_hit_keeps_its_status_in_order() -> void:
	var staff: CompiledStaff = _compile("fire frost bolt")
	var hit: HitProfile = staff.casts[0].group.spells[0].hit
	check_equal(hit.element_ids, [&"fire", &"frost"] as Array[StringName], "both elements")
	check_equal(hit.status_id, &"burn", "the first element's status")
	check_equal(hit.later_status_ids, [&"chill"] as Array[StringName], "the second one's follows")
	check_equal(hit.later_status_durations.size(), 1, "with its time")


func test_a_heavy_hit_pushes_harder_and_slams() -> void:
	var heavy: ModifierBase = _modifier(&"heavy")
	heavy.behaviour = ModifierBase.Behaviour.HEAVY
	heavy.behaviour_strength = 3.0
	var plain: HitProfile = _compile("bolt").casts[0].group.spells[0].hit
	var hit: HitProfile = _compile("heavy bolt").casts[0].group.spells[0].hit
	check_equal(plain.slam, 0, "an ordinary hit has no slam")
	check_equal(hit.knockback, plain.knockback * 3.0, "three times the push")
	check(hit.slam >= 1, "a knock into a wall hurts")


func test_a_mend_hit_heals_and_barely_hurts_enemies() -> void:
	(_fake.items[&"frost"] as ElementBase).heals = true
	var hit: HitProfile = _compile("frost bolt").casts[0].group.spells[0].hit
	check(hit.heal > 0, "it heals wizards")
	check(hit.damage < hit.heal, "and an enemy takes a tenth of it")
	check(hit.damage >= 1, "at least a point")


func test_a_beam_is_a_ray_hit_and_a_bolt_a_shot() -> void:
	var beam: FormBase = _form(&"beam", 3, 1)
	beam.carrier = &"beam"
	beam.ray_length = 200.0
	check_equal((_compile("beam").casts[0].group.spells[0] as CompiledSpell).hit.kind, &"ray", "a beam")
	check_equal((_compile("bolt").casts[0].group.spells[0] as CompiledSpell).hit.kind, &"shot", "a bolt")


func test_a_swing_is_a_swing_hit_though_it_has_a_reach() -> void:
	var swing: FormBase = _form(&"swing", 2, 1)
	swing.carrier = &"swing"
	swing.ray_length = 24.0
	swing.arc = 90.0
	check_equal((_compile("swing").casts[0].group.spells[0] as CompiledSpell).hit.kind, &"swing", "its own kind, for its own stop and shake")


func test_a_slam_is_an_area_hit() -> void:
	var slam: FormBase = _form(&"slam", 3, 1)
	slam.carrier = &"slam"
	slam.ray_length = 20.0
	slam.radius = 16.0
	check_equal((_compile("slam").casts[0].group.spells[0] as CompiledSpell).hit.kind, &"burst", "a shockwave hits as an area hit")


func test_the_builder_view_counts_a_casts_damage() -> void:
	# A bolt hits for 5 once, a nova for 4 with 8 shots: 5 + 32, the on-hit payload left out.
	var ids: Array[StringName] = [&"double", &"bolt", &"nova"]
	var view: Dictionary = _spells.call("staff_view", ids, _staff)
	check_equal(int((view["casts"] as Array)[0]["damage"]), 37, "a bolt and a nova together")
	var payload: Dictionary = _spells.call("staff_view", [&"on_hit", &"bolt", &"nova"] as Array[StringName], _staff)
	check_equal(int((payload["casts"] as Array)[0]["damage"]), 5, "a payload is not counted: it depends on what is hit")


func test_the_builder_view_keeps_a_specks_damage() -> void:
	# An atom hits for 0.3: the builder shows that, not 0.
	var atom: FormBase = _form(&"speck", 1, 1)
	atom.base_damage = 0.3
	var view: Dictionary = _spells.call("staff_view", [&"speck"] as Array[StringName], _staff)
	check(is_equal_approx(float((view["casts"] as Array)[0]["damage"]), 0.3), "a cast of one speck is 0.3")
	check_equal(_spells.call("component_stats", &"speck")[0], "Dmg 0.3", "and its card says so")


func test_reach_stretches_a_carriers_range_and_two_multiply() -> void:
	var reach: ModifierBase = _modifier(&"reach")
	reach.reach_mult = 1.6
	var bolt: FormBase = _form(&"far_bolt", 3, 1)
	bolt.lifetime = 1.0
	var dash: FormBase = _form(&"far_dash", 1, 1)
	dash.carrier = &"dash"
	dash.ray_length = 80.0
	var rune: FormBase = _form(&"far_rune", 3, 1)
	rune.carrier = &"rune"
	var shot: CompiledSpell = _compile("reach far_bolt").casts[0].group.spells[0]
	check(is_equal_approx(shot.lifetime, 1.6) and is_equal_approx(shot.speed, 300.0), "a flying shot lives longer at its speed: %s s" % shot.lifetime)
	var move: CompiledSpell = _compile("reach far_dash").casts[0].group.spells[0]
	check(is_equal_approx(move.ray_length, 128.0), "a dash goes 128 px: %s" % move.ray_length)
	var twice: CompiledSpell = _compile("reach reach far_dash").casts[0].group.spells[0]
	check(is_equal_approx(twice.ray_length, 80.0 * 1.6 * 1.6), "two reach cards multiply: %s" % twice.ray_length)
	var staff: CompiledStaff = _compile("reach far_rune")
	check(staff.wasted.has(0), "a rune has no range: reach is wasted")
