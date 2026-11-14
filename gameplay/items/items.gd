extends Node
## The Items area (autoload `Items`; items I6, docs/milestones/items.md, "The ground" and "Picking
## up"): what lies on the ground, and taking it. A row an item (`GroundItem`: its number, where it
## lies and its stack), state like any area's, the same on every machine, saved and restored with
## everything else. An item is not a body: nothing hits, pushes or is blocked by it. It belongs to
## the room it lies in: a run's start (one room a run) clears the ground.
##
## - **Laid:** the room's placements (`room_items_placed`, from flow: each `ItemStandIn`'s data, one
##   copy each, `ItemKinds.stack_of`), and a drop (`item_drop_requested`, from an actor's Inventory:
##   a card given back to a full bag), which lands a step from the body at the first free spot of
##   DIRECTIONS (no wall, no standing body's ground, no wall between: `ProjectileManager`'s grid),
##   tried from the side away from the item the body would take next, the same on every machine.
## - **In reach:** each tick (its step, `Tick.STEPS` "Items", after the bodies moved) it finds, for
##   the body each seat drives, the item in reach (`PickupRule.nearest`; none for a body with no
##   Inventory or down) and says so when it changes (`item_near_changed`).
## - **Taken:** `take(actor, item)` gives the item to the actor's Inventory as the pickup rule says,
##   if it still lies in reach and there is room (`PickupRule.take`); keyed by actor, so a seat's
##   request (`item_take_requested`, a command at the tick's start: seats in order, so the first of
##   two takes it) is one caller and an AI (I9) another. No room is `item_refused` for the seat.
## - **Said:** `ground_item_changed` as each item is laid and goes, with its view (`view_of`: plain
##   values for Feel's look and the HUD's hint). After a snapshot is restored it says everything
##   again (`rebuild_derived`), for the looks of the machine it was restored on.
##
## It knows nothing of the HUD, the AI or `net/`, and calls no other area: it hears events, reads
## the actor table and asks the projectile manager's wall grid.

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const SEATS: int = 4
## No item (`item_near_changed`'s and `nearest`'s none).
const NONE: int = -1
## What a take came to (`take`).
enum Take { TAKEN, GONE, NO_HOLDER, OUT_OF_REACH, NO_ROOM }
## How far from the feet a drop lands, then nearer if every way is blocked, in pixels; past both,
## at the feet.
const DROP_STEPS: PackedFloat32Array = [18.0, 9.0]
## The room an item takes on the ground: a drop's spot is free of walls this far round.
const DROP_RADIUS: float = 4.0
## The ways a drop may land, clockwise from below (towards the camera); tried in order of how far
## each points away from the item the body would take next, this order on a tie.
const DIRECTIONS: Array[Vector2] = [
	Vector2(0.0, 1.0), Vector2(-0.70710678, 0.70710678), Vector2(-1.0, 0.0), Vector2(-0.70710678, -0.70710678),
	Vector2(0.0, -1.0), Vector2(0.70710678, -0.70710678), Vector2(1.0, 0.0), Vector2(0.70710678, 0.70710678),
]
## The card folder the views name cards from.
const CARDS_FOLDER: StringName = &"spells"

## Not state: services, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"events", &"actors", &"projectiles", &"registry"]

## The services. Only tests set these, before adding the node; otherwise the autoloads.
var events: EventsScript = null
var actors: ActorsScript = null
var projectiles: ProjectilesScript = null
var registry: RegistryScript = null

## What lies on the ground, in the order it was laid (numbers rising).
var _rows: Array[GroundItem] = []
## The number the next item laid gets.
var _next_number: int = 0
## By seat: the item last said in reach (`item_near_changed`), NONE for none.
var _near: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])


func _ready() -> void:
	# The tick steps it (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Items").steps(&"Items", step).renewed_by(begin_run)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if actors == null:
		actors = get_node_or_null("/root/Actors") as ActorsScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectilesScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if events == null:
		push_warning("Items: the Events autoload is missing, so nothing lies on the ground.")
		return
	events.room_items_placed.connect(_on_room_items_placed)
	events.item_drop_requested.connect(_on_item_drop_requested)
	# A command, heard at the tick's start (core/events, online-ready N2).
	events.listen(&"item_take_requested", _on_item_take_requested)


## A run's start (one room a run): the ground is cleared, every item said gone, and the area is a
## fresh one's.
func begin_run() -> void:
	clear()
	SimFresh.renew(self)


## Nothing lies on the ground any more, and no seat has an item in reach (each said).
func clear() -> void:
	var gone: Array[GroundItem] = _rows.duplicate()
	_rows.clear()
	for row: GroundItem in gone:
		_say_gone(row)
	for seat in SEATS:
		_set_near(seat, NONE)


## The tick's step: the item in reach of each seat's driven body, said when it changed.
func step(_delta: float) -> void:
	for seat in SEATS:
		var found: int = NONE
		var body: Actor = _holder(actors.actor_of_seat(seat)) if actors != null else null
		if body != null and not body.is_down():
			var at: int = PickupRule.nearest(_rows, body.global_position)
			if at >= 0:
				found = _rows[at].number
		_set_near(seat, found)


# --- Laying and taking -----------------------------------------------------------------

## Lay `stack` (a copy of it) at `at`, shown as `title` (empty: its content's name). Returns its
## number.
func lay(stack: ItemStack, at: Vector2, title: String = "") -> int:
	var row := GroundItem.make(_next_number, at, stack.copy(), title)
	_next_number += 1
	_rows.append(row)
	if events != null:
		events.ground_item_changed.emit(row.number, row.at, view_of(row))
	return row.number


## Give the item `item` to the actor `actor` (its Inventory), as the pickup rule says: it must
## still lie there and in reach of the actor's feet, and the rule must find room. Returns what it
## came to; only TAKEN changes anything.
func take(actor: int, item: int) -> Take:
	var at: int = _index_of(item)
	if at < 0:
		return Take.GONE
	var body: Actor = _holder(actor)
	if body == null or body.is_down():
		return Take.NO_HOLDER
	var row: GroundItem = _rows[at]
	if not PickupRule.in_reach(body.global_position, row.at):
		return Take.OUT_OF_REACH
	if not PickupRule.take(body.inventory, row.stack):
		return Take.NO_ROOM
	_rows.remove_at(at)
	_say_gone(row)
	return Take.TAKEN


## Where a drop from feet at `feet` lands: a step away (DROP_STEPS), the first free way of
## DIRECTIONS taken from the side away from `away` (the item the body would take next; none: from
## below), at the feet when every way is blocked.
func drop_spot(feet: Vector2, away: Vector2 = Vector2.INF) -> Vector2:
	var order: Array[int] = _ways_from(feet, away)
	for distance in DROP_STEPS:
		for way: int in order:
			var spot: Vector2 = feet + DIRECTIONS[way] * distance
			if _free(feet, spot):
				return spot
	return feet


## What lies on the ground: a copy of each row, in the order laid.
func lying() -> Array[GroundItem]:
	var out: Array[GroundItem] = []
	for row: GroundItem in _rows:
		out.append(GroundItem.make(row.number, row.at, row.stack.copy(), row.title))
	return out


## The item in reach of seat `seat`'s driven body as last said, NONE for none.
func near_of(seat: int) -> int:
	return _near[seat] if seat >= 0 and seat < SEATS else NONE


## The plain view of `row` for the looks (`ground_item_changed` says what is in it).
func view_of(row: GroundItem) -> Dictionary:
	var stack: ItemStack = row.stack
	var view: Dictionary = {"kind": stack.kind, "id": stack.id, "name": row.title, "icon": null}
	if stack.staff != null:
		var base: StaffBase = stack.staff
		if row.title == "":
			view["name"] = base.display_name
		view["head"] = base.head
		view["slots"] = base.slots
		view["cooldown"] = base.cooldown
		view["max_mana"] = base.max_mana
		view["mana_regen"] = base.mana_regen
		view["cards"] = stack.cards.duplicate()
		return view
	var content: Resource = registry.get_resource(CARDS_FOLDER, stack.id) if registry != null and stack.kind == ItemKinds.CARD else null
	if content is SpellComponent:
		if row.title == "":
			view["name"] = (content as SpellComponent).display_name
		view["icon"] = (content as SpellComponent).icon
	if String(view["name"]) == "":
		view["name"] = String(stack.id)
	return view


## Say everything again (a snapshot restored: the looks of this machine know nothing of it).
func rebuild_derived() -> void:
	if events == null:
		return
	for row: GroundItem in _rows:
		events.ground_item_changed.emit(row.number, row.at, view_of(row))
	for seat in SEATS:
		var item: int = _near[seat]
		var at: int = _index_of(item)
		if at >= 0:
			events.item_near_changed.emit(seat, item, _rows[at].at, view_of(_rows[at]))
		else:
			events.item_near_changed.emit(seat, NONE, Vector2.ZERO, {})


# --- Heard ------------------------------------------------------------------------------

## The run's room was stood: lay what its scene places, one copy each, in its order.
func _on_room_items_placed(items: Array[Resource], at: PackedVector2Array) -> void:
	for i in mini(items.size(), at.size()):
		var stack: ItemStack = ItemKinds.stack_of(items[i])
		if stack == null:
			push_warning("Items: %s is no item, so nothing lies at %s." % [items[i], at[i]])
			continue
		stack.count = 1
		lay(stack, at[i], (items[i] as StaffItem).shown_name() if items[i] is StaffItem else "")


## An actor's Inventory let `stack` go: it lands beside the actor (`drop_spot`), away from the item
## it would take next. An actor with no body lays nothing.
func _on_item_drop_requested(actor: int, stack: ItemStack) -> void:
	var body := actors.node_of(actor) as Node2D if actors != null else null
	if body == null or stack == null:
		return
	var feet: Vector2 = body.global_position
	var next: int = PickupRule.nearest(_rows, feet)
	lay(stack, drop_spot(feet, _rows[next].at if next >= 0 else Vector2.INF))


## Seat `player` asked for `item` (a command): taken as `take` says for the body it drives; no
## room is said (`item_refused`), anything else is silent.
func _on_item_take_requested(player: int, item: int) -> void:
	if player < 0 or player >= SEATS or actors == null:
		return
	if take(actors.actor_of_seat(player), item) == Take.NO_ROOM and events != null:
		events.item_refused.emit(player, item)


# --- Inside -----------------------------------------------------------------------------

## The body of actor `actor` if it can hold things (it has an Inventory), else null.
func _holder(actor: int) -> Actor:
	if actors == null or actor == ActorsScript.NONE:
		return null
	var body := actors.node_of(actor) as Actor
	return body if body != null and body.inventory != null else null


func _index_of(item: int) -> int:
	if item == NONE:
		return -1
	for at in _rows.size():
		if _rows[at].number == item:
			return at
	return -1


func _set_near(seat: int, item: int) -> void:
	if _near[seat] == item:
		return
	_near[seat] = item
	if events == null:
		return
	var at: int = _index_of(item)
	if at >= 0:
		events.item_near_changed.emit(seat, item, _rows[at].at, view_of(_rows[at]))
	else:
		events.item_near_changed.emit(seat, NONE, Vector2.ZERO, {})


func _say_gone(row: GroundItem) -> void:
	if events != null:
		events.ground_item_changed.emit(row.number, row.at, {})


## DIRECTIONS' indices, the way pointing furthest from `away` first (as seen from `feet`), the
## table's order on a tie; the table's order with no `away` or one at the feet.
func _ways_from(feet: Vector2, away: Vector2) -> Array[int]:
	var order: Array[int] = []
	for way in DIRECTIONS.size():
		order.append(way)
	if away == Vector2.INF or away == feet:
		return order
	var from: Vector2 = feet - away
	var score: Array[float] = []
	for way in DIRECTIONS.size():
		score.append(DIRECTIONS[way].dot(from))
	# A stable insertion sort, highest score first: eight entries.
	for i in range(1, order.size()):
		var way: int = order[i]
		var j: int = i - 1
		while j >= 0 and score[order[j]] < score[way]:
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = way
	return order


## True when an item may lie at `spot`, dropped from `feet`: no wall or standing ground round it and
## none between.
func _free(feet: Vector2, spot: Vector2) -> bool:
	if projectiles == null:
		return true
	return not projectiles.circle_blocked(spot, DROP_RADIUS) and projectiles.line_clear(feet, spot)
