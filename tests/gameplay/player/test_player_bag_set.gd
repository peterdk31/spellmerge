extends "res://tests/support/suite.gd"
## Tests for the set bag (horde H2, docs/milestones/horde.md): `bag_set_requested` for a seat makes
## that seat's bag exactly the list and sends `bag_changed`; other seats keep theirs; a bag set
## before the wizard first drives survives the first fill (and is announced when it binds); a
## bag set after the fill replaces it, and the builder then refuses a card no longer in it.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_bag_set.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")


## A registry that knows only the cards a test puts in it.
class FakeRegistry:
	extends RegistryScript
	var items: Dictionary = {}

	func get_ids(folder: StringName) -> Array[StringName]:
		var ids: Array[StringName] = []
		if folder == &"spells":
			for id: StringName in items:
				ids.append(id)
		return ids

	func get_resource(folder: StringName, id: StringName) -> Resource:
		return items.get(id) if folder == &"spells" else null


var _world: Fixture
var _registry: FakeRegistry
## Every bag_changed as [player, bag].
var _bags: Array = []
## Every build_refused's player.
var _refused: Array[int] = []


func before_each() -> void:
	_world = Fixture.new(root, true)
	_registry = FakeRegistry.new()
	for id: StringName in [&"dash", &"fire", &"bolt", &"orbit", &"split"]:
		var card := SpellComponent.new()
		card.id = id
		_registry.items[id] = card
	_bags.clear()
	_refused.clear()
	_world.bus.bag_changed.connect(func(player: int, bag: Array[StringName]) -> void: _bags.append([player, bag]))
	_world.bus.build_refused.connect(func(player: int, _reason: String) -> void: _refused.append(player))


func after_each() -> void:
	_world.free_all()
	_registry.free()


## The wizard of `seat`, reading the cards of `_registry`; in the tree unless `ready` is false.
func _wizard(seat: int, ready: bool = true) -> Actor:
	var body: Actor = _world.wizard(seat, Vector2(40.0 * seat, 0.0), Fixture.NO_CARDS, null, false)
	Fixture.controller(body).registry = _registry
	if ready:
		_world.add(body)
	return body


func _ids(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(StringName(word))
	return out


func test_without_a_set_bag_it_fills_with_every_card() -> void:
	var body := _wizard(0)
	check_equal(Fixture.controller(body).bag.size(), 5, "the bag has every card of the registry")


func test_a_set_bag_replaces_the_filled_one_and_is_announced() -> void:
	var body := _wizard(0)
	_bags.clear()
	_world.bus.bag_set_requested.emit(0, _ids("dash fire bolt"))
	check_equal(Fixture.controller(body).bag, _ids("dash fire bolt"), "the bag is exactly the list")
	check_equal(_bags.size(), 1, "bag_changed is sent once")
	check_equal(_bags[0], [0, _ids("dash fire bolt")], "for that seat, with the new bag")


func test_only_the_named_seat_takes_it() -> void:
	var first := _wizard(0)
	var second := _wizard(1)
	_bags.clear()
	_world.bus.bag_set_requested.emit(1, _ids("bolt"))
	check_equal(Fixture.controller(first).bag.size(), 5, "seat 0 keeps its bag")
	check_equal(Fixture.controller(second).bag, _ids("bolt"), "seat 1 has the set bag")
	check_equal(_bags.size(), 1, "only seat 1 announces")


func test_a_bag_set_before_the_first_drive_survives_the_first_fill() -> void:
	var body := _wizard(2, false)
	Fixture.controller(body).set_bag(_ids("dash fire"))
	check(_bags.is_empty(), "nothing is announced before the wizard drives")
	_world.add(body)
	check_equal(Fixture.controller(body).bag, _ids("dash fire"), "the first fill does not overwrite it")
	check_equal(_bags, [[2, _ids("dash fire")]], "binding the wizard announces the set bag")


func test_the_set_bag_is_a_copy() -> void:
	var body := _wizard(0)
	var cards: Array[StringName] = _ids("dash bolt")
	_world.bus.bag_set_requested.emit(0, cards)
	cards.append(&"orbit")
	check_equal(Fixture.controller(body).bag, _ids("dash bolt"), "changing the sent list later changes nothing")


func test_the_builder_refuses_a_card_outside_the_set_bag() -> void:
	var body := _wizard(0)
	_world.bus.bag_set_requested.emit(0, _ids("dash"))
	_world.bus.staff_change_requested.emit(0, 0, 0, &"orbit")
	check_equal(_refused, [0] as Array[int], "a card no longer in the bag is refused")
	check(body.caster.cards_of(0).is_empty() or body.caster.cards_of(0)[0] == &"", "and the staff is unchanged")


func test_an_empty_set_bag_is_kept_empty() -> void:
	var body := _wizard(3)
	_world.bus.bag_set_requested.emit(3, [] as Array[StringName])
	check(Fixture.controller(body).bag.is_empty(), "an empty list empties the bag")
