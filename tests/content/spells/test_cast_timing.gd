extends "res://tests/support/suite.gd"
## The numbers of cast timing (docs/milestones/cast-timing.md, part T4): no card locks its staff
## for long (a big card costs mana instead), the starter staffs share one cooldown, and a held
## beam on a starter staff stays on with no gap.
##
## godot --headless --path . --script res://tests/content/spells/test_cast_timing.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const STARTERS: Array[StaffBase] = [preload("res://content/wizard/staffs/crystal/crystal.tres"), preload("res://content/wizard/staffs/curl/curl.tres"), preload("res://content/wizard/staffs/moon/moon.tres"), preload("res://content/wizard/staffs/star/star.tres")]
## The longest wind-down a card may have: a lockout past it is a mana cost (the retune's rule).
const LONGEST_WIND_DOWN: float = 1.0
const STARTER_COOLDOWN: float = 0.15

var arena: ArenaScript


func before_each() -> void:
	arena = ArenaScript.new(root)


func after_each() -> void:
	arena.free_all()


func _forms() -> Array[CarrierCard]:
	var out: Array[CarrierCard] = []
	for id: StringName in arena.registry.call("get_ids", &"spells"):
		var card: Resource = arena.registry.call("get_resource", &"spells", id)
		if card is CarrierCard:
			out.append(card as CarrierCard)
	return out


func _form(id: StringName) -> CarrierCard:
	return arena.registry.call("get_resource", &"spells", id) as CarrierCard


func test_no_card_locks_its_staff_for_long() -> void:
	for form in _forms():
		check(form.wind_down <= LONGEST_WIND_DOWN, "%s winds down %s s, at most %s: a longer lockout is a mana cost" % [form.id, form.wind_down, LONGEST_WIND_DOWN])


func test_the_big_cards_cost_mana_instead() -> void:
	# Each was a lockout of 2 s or more before the retune.
	for id: StringName in [&"dash", &"teleport", &"swap", &"decoy", &"familiar"]:
		check(_form(id).mana_cost >= 20.0, "%s costs %s mana" % [id, _form(id).mana_cost])
	check(_form(&"familiar").mana_cost > _form(&"bolt").mana_cost * 5.0, "a familiar costs many bolts")


func test_the_starter_staffs_share_one_cooldown() -> void:
	for staff in STARTERS:
		check(is_equal_approx(staff.cooldown, STARTER_COOLDOWN), "%s cools down %s s" % [staff.id, staff.cooldown])
		check_equal(staff.wind_up, 0.0, "%s adds no wind-up: only enemies telegraph" % staff.id)


func test_a_held_beam_outlives_its_wind_down_and_the_starter_cooldown() -> void:
	var beam: CarrierCard = _form(&"beam")
	check(beam.lifetime > beam.wind_down + STARTER_COOLDOWN, "a beam lives %s s, past its %s s wind-down and the %s s cooldown, so held fire has no gap" % [beam.lifetime, beam.wind_down, STARTER_COOLDOWN])
