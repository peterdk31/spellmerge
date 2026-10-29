extends "res://tests/support/suite.gd"
## Staff codes (staffs D2): `StaffCode` turns a staff's cards into one line of text and back,
## accepting only known card ids; `Spells.parse_staff_code` checks them against the registry.
##
## godot --headless --path . --script res://tests/core/test_staff_code.gd

const SpellsScript := preload("res://core/spells/spells.gd")

const KNOWN: Array[StringName] = [&"fire", &"bolt", &"double", &"nova", &"on_hit"]


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


func _known(id: StringName) -> bool:
	return KNOWN.has(id)


func _cards(ids: Array) -> Array[StringName]:
	var cards: Array[StringName] = []
	for id: Variant in ids:
		cards.append(StringName(id))
	return cards


func test_encode_lists_the_cards_and_leaves_off_trailing_empty_slots() -> void:
	check_equal(StaffCode.encode(_cards(["double", "fire", "bolt"])), "sm1:double,fire,bolt", "plain cards")
	check_equal(StaffCode.encode(_cards(["fire", "", "bolt", "", ""])), "sm1:fire,-,bolt", "a gap is a dash, the empty tail is left off")
	check_equal(StaffCode.encode(_cards(["", ""])), "sm1:", "an empty staff is only the tag")


func test_a_code_reads_back_to_the_same_cards() -> void:
	var cards: Array[StringName] = _cards(["double", "fire", "", "bolt", "on_hit", "nova"])
	var read: Dictionary = StaffCode.parse(StaffCode.encode(cards), _known)
	check(bool(read["ok"]), "it reads: %s" % read["error"])
	check_equal(read["cards"], cards, "the same cards")


func test_parse_pads_to_the_slot_count() -> void:
	var read: Dictionary = StaffCode.parse("sm1:fire,bolt", _known, 4)
	check_equal(read["cards"], _cards(["fire", "bolt", "", ""]), "four slots")
	read = StaffCode.parse("sm1:", _known, 3)
	check(bool(read["ok"]) and (read["cards"] as Array).size() == 3, "an empty code is an empty staff")


func test_parse_ignores_spaces_and_the_case_of_the_tag() -> void:
	var read: Dictionary = StaffCode.parse("  SM1: fire , bolt\n", _known)
	check(bool(read["ok"]), "spaces and a capital tag are fine: %s" % read["error"])
	check_equal(read["cards"], _cards(["fire", "bolt"]), "the cards")


func test_parse_refuses_what_is_not_a_code() -> void:
	for text: String in ["", "fire,bolt", "sm2:fire", "hello world", "sm1:fire;bolt"]:
		var read: Dictionary = StaffCode.parse(text, _known)
		check(not bool(read["ok"]), "'%s' is refused" % text)
		check((read["cards"] as Array).is_empty(), "'%s' gives no cards" % text)
		check(str(read["error"]) != "", "'%s' says why" % text)


func test_parse_refuses_unknown_cards_and_anything_but_names() -> void:
	var read: Dictionary = StaffCode.parse("sm1:fire,nope", _known)
	check(not bool(read["ok"]) and "nope" in str(read["error"]), "an unknown card is named: %s" % read["error"])
	for bad: String in ["sm1:res://x.gd", "sm1:fire,Bolt", "sm1:../fire", "sm1:fire,$(ls)", "sm1:fire,,bolt", "sm1:fire bolt"]:
		check(not bool(StaffCode.parse(bad, _known)["ok"]), "'%s' is refused" % bad)


func test_parse_refuses_codes_that_are_too_big() -> void:
	check(not bool(StaffCode.parse("sm1:" + "-,".repeat(StaffCode.MAX_SLOTS) + "-", _known)["ok"]), "too many cards")
	check(not bool(StaffCode.parse("sm1:" + "a".repeat(StaffCode.MAX_LENGTH), _known)["ok"]), "too long")
	check(not bool(StaffCode.parse("sm1:fire,bolt,nova", _known, 2)["ok"]), "more cards than the staff has slots")


func test_the_registry_decides_which_cards_are_known() -> void:
	var fake: FakeRegistry = own(FakeRegistry.new()) as FakeRegistry
	fake.items[&"bolt"] = FormBase.new()
	var spells: Node = own(SpellsScript.new())
	spells.set("registry", fake)
	check(bool(spells.call("parse_staff_code", "sm1:bolt")["ok"]), "a card the registry has")
	check(not bool(spells.call("parse_staff_code", "sm1:bolt,fire")["ok"]), "a card it has not")
