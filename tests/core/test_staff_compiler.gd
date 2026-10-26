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
	_form(&"rain", 3, 1).motion = FormBase.Motion.RAIN
	_element(&"fire", &"burn", 1.5)
	_element(&"frost", &"chill", 1.0)
	_modifier(&"split").shot_mult = 3
	var homing: ModifierBase = _modifier(&"homing")
	homing.behaviour = ModifierBase.Behaviour.HOMING
	homing.behaviour_strength = 4.0
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


func test_a_trigger_in_the_last_slot_wraps_and_is_wasted() -> void:
	var staff: CompiledStaff = _compile("bolt on_hit")
	check_equal(staff.casts.size(), 2, "two casts")
	check_equal(_forms(staff.casts[1].group), [&"bolt"] as Array[StringName], "cast 2 wraps to the bolt")
	check(staff.casts[1].wrapped, "cast 2 wrapped")
	check(staff.wasted.has(1), "the trigger is wasted")


func test_a_counter_dash_reads_in_slot_order() -> void:
	_form(&"dash", 1, 1).motion = FormBase.Motion.DASH
	_trigger(&"on_block", TriggerBase.Event.BLOCK)
	var staff: CompiledStaff = _compile("shield on_block dash nova")
	var dash: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(dash.form_id, &"dash", "a dash")
	check_equal(dash.behaviour(ModifierBase.Behaviour.SHIELD), 1.0, "with one shield")
	check_equal(dash.trigger_event, TriggerBase.Event.BLOCK, "that fires on a block")
	check_equal(_forms(dash.payload), [&"nova"] as Array[StringName], "a nova")


# --- More rules ---------------------------------------------------------------

func test_a_steering_modifier_on_the_caster_is_wasted() -> void:
	var staff: CompiledStaff = _compile("homing fire")
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	check_equal(spell.fallback, CompiledSpell.FALLBACK_CASTER, "fire lands on the caster")
	check(not spell.modifier_ids.has(&"homing"), "homing does not")
	check(staff.wasted.has(0), "homing is wasted with a reason")


func test_a_shield_means_nothing_at_a_payload_origin() -> void:
	var staff: CompiledStaff = _compile("on_hit bolt shield")
	check(staff.casts[0].group.spells[0].payload == null, "nothing lands there")
	check(staff.wasted.has(2), "the shield is wasted")


func test_several_infusions_ride_one_shot_first_one_first() -> void:
	var spell: CompiledSpell = _compile("fire frost bolt").casts[0].group.spells[0]
	check_equal(spell.element_ids, [&"fire", &"frost"] as Array[StringName], "both elements, in order")
	check_equal(spell.element_id, &"fire", "the first sets the status and the look")
	check_equal(spell.hit.element_ids, [&"fire", &"frost"] as Array[StringName], "the hit carries both")


func test_a_second_trigger_before_one_carrier_is_wasted() -> void:
	var staff: CompiledStaff = _compile("on_hit on_expire bolt nova")
	check_equal(staff.casts[0].group.spells[0].trigger_event, TriggerBase.Event.HIT, "the first trigger counts")
	check(staff.wasted.has(1), "the second is wasted")


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
	_form(&"beam", 3, 1).ray_length = 200.0
	check_equal((_compile("beam").casts[0].group.spells[0] as CompiledSpell).hit.kind, &"ray", "a beam")
	check_equal((_compile("bolt").casts[0].group.spells[0] as CompiledSpell).hit.kind, &"shot", "a bolt")


func test_the_builder_view_counts_a_casts_damage() -> void:
	# A bolt hits for 5 once, a nova for 4 with 8 shots: 5 + 32, the on-hit payload left out.
	var ids: Array[StringName] = [&"double", &"bolt", &"nova"]
	var view: Dictionary = _spells.call("staff_view", ids, _staff)
	check_equal(int((view["casts"] as Array)[0]["damage"]), 37, "a bolt and a nova together")
	var payload: Dictionary = _spells.call("staff_view", [&"on_hit", &"bolt", &"nova"] as Array[StringName], _staff)
	check_equal(int((payload["casts"] as Array)[0]["damage"]), 5, "a payload is not counted: it depends on what is hit")
