extends "res://tests/support/suite.gd"
## Death From Every Sky (content/items/staffs/death_from_every_sky): on the hub's rack, a premade staff with one of the crazy
## builds, on the sandbox staff (its 20 slots hold the build, and it never runs dry): sixteen big meteors fall in a ring round the wizard; each bursts into eight lightning atoms, which
## overload whatever burns.
## Its data is sound, every card it names is a card, its build wastes none of them and reads in one
## cast, and its triggers fire at the payload depths the build is made of.
##
## godot --headless --path . --script res://content/items/staffs/death_from_every_sky/test_death_from_every_sky.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const ITEM: StaffItem = preload("res://content/items/staffs/death_from_every_sky/death_from_every_sky.tres")
## The tree's trigger rows, in order: [payload depth, the trigger's name], one a trigger that fires.
const TRIGGERS: Array = [[1, "On Expire"]]


func test_it_is_sound() -> void:
	check_equal(ITEM.problems(), PackedStringArray(), "its data")
	check_equal(ITEM.id, &"death_from_every_sky", "its id is its folder's")
	check_equal(ITEM.shown_name(), "Death From Every Sky", "its name")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"items", &"death_from_every_sky") == ITEM, "the registry finds it under items")


func test_every_card_is_a_card_and_none_is_wasted() -> void:
	var registry: Node = root.get_node("Registry")
	for id: StringName in ITEM.cards:
		check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s is a card" % id)
	var view: Dictionary = _view()
	check(not bool(view.get("empty", true)), "it casts")
	check_equal(view.get("wasted"), {}, "no card is wasted (slot: wasted)")


func test_it_reads_as_its_build() -> void:
	var casts: Array = _view()["casts"]
	check_equal(casts.size(), 1, "one cast")
	if casts.is_empty():
		return
	var read: Dictionary = {}
	var fired: Array = []
	for row: Dictionary in casts[0]["tree"]:
		for slot: int in row["slots"]:
			read[slot] = true
		if int(row["trigger"]) >= 0:
			read[int(row["trigger"])] = true
			fired.append([int(row["depth"]), String(row["name"])])
	check_equal(read.size(), ITEM.cards.size(), "the cast reads every card")
	check_equal(fired, TRIGGERS, "its triggers fire where the build means them to")


func _view() -> Dictionary:
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = root.get_node("Registry")
	return spells.staff_view(ITEM.cards, ITEM.staff)
