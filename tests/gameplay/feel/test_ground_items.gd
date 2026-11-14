extends "res://tests/support/suite.gd"
## The items on the ground's look (items I6; gameplay/feel/ground_items.gd): it draws each item
## Items says lies somewhere, by the view it was given, and draws it no more once it is gone; Feel
## has one, bound to its bus.

const GroundItemsScript := preload("res://gameplay/feel/ground_items.gd")
const EventsScript := preload("res://core/events/events.gd")
const WILD_STAR: StaffItem = preload("res://content/items/staffs/wild_star/wild_star.tres")

var _bus: EventsScript = null
var _look: GroundItemsScript = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_look = GroundItemsScript.new()
	root.add_child(own(_look))
	_look.bind(_bus)


func test_it_draws_what_lies_there_until_it_goes() -> void:
	check_equal(_look.count(), 0, "nothing said, nothing drawn")
	var staff: Dictionary = {"kind": ItemKinds.STAFF, "id": &"star", "name": "Wild star", "icon": null, "head": WILD_STAR.staff.head}
	_bus.ground_item_changed.emit(0, Vector2(40, 40), staff)
	_bus.ground_item_changed.emit(1, Vector2(80, 40), {"kind": ItemKinds.CARD, "id": &"bolt", "name": "Bolt", "icon": null})
	check_equal(_look.count(), 2, "both drawn")
	check(_look.view_of(0)["head"] == WILD_STAR.staff.head, "the staff by its head")
	_look._process(0.5)
	_bus.ground_item_changed.emit(0, Vector2(40, 40), {})
	check_equal(_look.count(), 1, "the one gone is drawn no more")
	check(_look.view_of(0).is_empty(), "nothing of it")


func test_feel_has_one() -> void:
	var feel: Node = root.get_node("Feel")
	check(feel.call("ground_items") is GroundItemsScript, "Feel draws the items on the ground")
