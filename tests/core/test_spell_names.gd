extends "res://tests/support/suite.gd"
## Spell names (staffs E1): a name for every cast, built from its cards by `SpellNamer`. Cards
## with known words sit behind a stand-in registry, so the exact names can be checked; the last
## test reads the real registry and wants words on every card.
##
## godot --headless --path . --script res://tests/core/test_spell_names.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


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
	_card(FormBase.new(), &"bolt", ["Bolt"])
	_card(FormBase.new(), &"beam", ["Beam", "Lance"])
	_card(FormBase.new(), &"nova", ["Nova"])
	_card(FormBase.new(), &"fox", ["Fox"])
	_card(FormBase.new(), &"fly", ["Fly"])
	_card(ElementBase.new(), &"fire", ["Fire"])
	_card(ElementBase.new(), &"frost", ["Frost"])
	_card(ModifierBase.new(), &"homing", ["Seeking", "Nosy"])
	_card(ModifierBase.new(), &"slow", ["Lazy"])
	_card(ModifierBase.new(), &"bigger", ["Hefty"])
	_card(ModifierBase.new(), &"faster", ["Zippy"])
	_card(TriggerBase.new(), &"on_hit", ["Sudden"])
	_card(MulticastBase.new(), &"double", ["Twice"])
	_card(MulticastBase.new(), &"triple", ["Thrice"])
	(_fake.items[&"triple"] as MulticastBase).extra_draws = 2
	(_fake.items[&"homing"] as ModifierBase).behaviour = ModifierBase.Behaviour.HOMING
	(_fake.items[&"homing"] as ModifierBase).behaviour_strength = 4.0
	(_fake.items[&"homing"] as ModifierBase).behaviour_reach = 160.0


func _card(card: SpellComponent, id: StringName, words: Array[String]) -> void:
	card.id = id
	card.display_name = String(id).capitalize()
	card.name_words = PackedStringArray(words)
	_fake.items[id] = card


func _names(cards: String) -> PackedStringArray:
	var ids: Array[StringName] = []
	for word in cards.split(" ", false):
		ids.append(&"" if word == "-" else StringName(word))
	var view: Dictionary = _spells.call("staff_view", ids, _staff)
	var out := PackedStringArray()
	for cast: Dictionary in view["casts"]:
		out.append(String(cast["name"]))
	return out


func _name(cards: String) -> String:
	var names: PackedStringArray = _names(cards)
	return names[0] if not names.is_empty() else ""


func test_a_plain_carrier_has_a_plain_name() -> void:
	check_equal(_name("bolt"), "Bolt", "a plain bolt is Bolt")
	check_equal(_name("nova"), "Nova", "a plain nova is Nova")


func test_infusions_fuse_into_one_word() -> void:
	check_equal(_name("fire bolt"), "Fire Bolt", "one infusion, one word before the noun")
	check_equal(_name("fire frost nova"), "Firefrost Nova", "two infusions fuse")


func test_modifiers_are_adjectives_and_only_three_are_said() -> void:
	var said: String = _name("slow bigger faster slow bolt")
	check(said.ends_with("Bolt"), "it ends in the noun: %s" % said)
	check_equal(said.split(" ").size(), 4, "three adjectives and the noun: %s" % said)


func test_a_trigger_names_its_payload_in_the_plural() -> void:
	var said: String = _name("on_hit bolt nova")
	check_equal(said, "Bolt of Sudden Novas", "the trigger's word and the payload's plural")
	check_equal(_name("on_hit fox fox"), "Fox of Sudden Foxes", "x takes -es")
	check_equal(_name("on_hit fly fly"), "Fly of Sudden Flies", "consonant + y takes -ies")


func test_a_multicast_is_a_hyphenated_prefix() -> void:
	check_equal(_name("double bolt bolt"), "Twice-Bolt and Bolt", "the first carrier takes the prefix")
	check_equal(_name("double triple bolt bolt bolt bolt"), "Twice-Thrice-Bolt and Bolt and Bolt and more", "prefixes chain, three carriers are said")


func test_a_card_with_several_words_gives_the_first_when_plain_and_one_of_them_otherwise() -> void:
	check_equal(_name("beam"), "Beam", "plain: the first word")
	var said: String = _name("fire beam")
	check(said == "Fire Beam" or said == "Fire Lance", "one of its words: %s" % said)


func test_the_name_grows_with_the_build() -> void:
	var small: String = _name("bolt")
	var middle: String = _name("fire bolt")
	var large: String = _name("double homing fire frost on_hit bolt nova")
	check(small.length() < middle.length() and middle.length() < large.length(), "%s < %s < %s" % [small, middle, large])
	check(large.contains("Twice-") and large.contains("Firefrost") and large.contains("of Sudden Novas"), "it says every part: %s" % large)


func test_the_same_cards_always_give_the_same_name() -> void:
	var first: String = _name("double homing fire frost on_hit bolt nova")
	for i in 5:
		check_equal(_name("double homing fire frost on_hit bolt nova"), first, "name %d is the same" % i)
	# A new staff object and a new namer read the same.
	var other := own(SpellsScript.new())
	other.set("registry", _fake)
	var ids: Array[StringName] = [&"double", &"homing", &"fire", &"frost", &"on_hit", &"bolt", &"nova"]
	var view: Dictionary = other.call("staff_view", ids, _staff)
	check_equal(String((view["casts"] as Array)[0]["name"]), first, "another runtime gives the same name")


func test_cards_with_no_carrier_are_named_for_where_they_land() -> void:
	check_equal(_name("fire"), "Fire Aura", "an infusion alone lands on the caster")
	check_equal(_name("on_hit bolt fire"), "Bolt of Sudden Fire Flares", "an infusion alone in a payload lands on its origin")


func test_a_card_keeps_its_word_when_other_cards_change() -> void:
	var word: String = _name("homing bolt").split(" ")[0]
	for extra in ["fire", "slow", "bigger", "double"]:
		var said: String = _name("%s homing bolt" % extra)
		check(said.contains(word), "'%s' stays in '%s'" % [word, said])


func test_a_multi_word_head_is_pluralized_on_its_last_word() -> void:
	(_fake.items[&"fox"] as SpellComponent).name_words = PackedStringArray(["Seeking Fox"])
	check_equal(_name("on_hit bolt fox"), "Bolt of Sudden Seeking Foxes", "the last word takes the plural")


func test_a_worst_case_build_has_a_short_name() -> void:
	var cards: String = "double triple slow bigger faster homing fire frost on_hit bolt "
	cards += "on_hit nova on_hit fox on_hit fly bolt nova fox fly bolt nova fox fly"
	var said: String = _name(cards)
	check(said != "", "it has a name")
	check(said.length() <= SpellNamer.MAX_LENGTH, "%d characters: %s" % [said.length(), said])
	var many: String = _name("double triple bolt bolt bolt bolt bolt bolt")
	check(many.ends_with("and more"), "more carriers than said ends 'and more': %s" % many)


func test_every_cast_of_the_cycle_has_a_name() -> void:
	var names: PackedStringArray = _names("fire bolt frost nova")
	check_equal(names.size(), 2, "two casts")
	check_equal(names[0], "Fire Bolt", "first")
	check_equal(names[1], "Frost Nova", "second")


func test_a_card_without_words_says_its_display_name() -> void:
	(_fake.items[&"bolt"] as SpellComponent).name_words = PackedStringArray()
	check_equal(_name("bolt"), "Bolt", "the display name stands in")


func test_every_real_card_has_name_words() -> void:
	var arena := ArenaScript.new(root)
	var ids: Array[StringName] = arena.registry.call("get_ids", &"spells")
	check(ids.size() > 0, "the registry finds cards")
	for id in ids:
		var card := arena.registry.call("get_resource", &"spells", id) as SpellComponent
		if card == null:
			continue
		check(not card.name_words.is_empty(), "%s: set `name_words` in its .tres (see SpellComponent)" % id)
		for word in card.name_words:
			check(word.strip_edges() != "" and word == word.strip_edges(), "%s: a name word has no blank edges ('%s')" % [id, word])
	arena.free_all()
