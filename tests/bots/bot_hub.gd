extends RefCounted
## A bot's errand in the hub (the owner, 2026-11-20, after #886: the bots' runs start in the hub,
## where each bot takes a staff from the hub's rack as a player would, and the run starts through the
## hub's own run start, so what it carries in is its loadout). Bot code, never the game's: it reads
## what a person reads off the screen (where the rack's staffs lie, `Items.lying`; which one is in
## reach, `Items.near_of`, the hint; where the teleporter stone stands, the room's props by role, and
## whether it is lit, `Flow.is_stone_lit`), and the bot (tests/bots/bot.gd) plays it through its seat's
## input only: the walk, and A as the gamepad's (`take` for the item in reach, `accept` on the lit
## stone, which the HUD's panels turn into the commands `item_take_requested` and `run_requested`).
##
## The stages, in order (`stage`):
## - RACK: with a rack staff in its build (`BuildsScript.rack_of`), walk to where it lies and press
##   `take` once it is the item in reach (again every RETRY ticks while it is not taken yet). Taken
##   (one of its hands holds it), or no longer lying there (taken by another): on to BUILD.
## - BUILD: the bot sets its build (`bot.gd`, `send_build`: each staff as one `staff_cards_requested`,
##   as the builder does), then STONE. A bot with no build (an idler, a playtest's `--plain`) has
##   nothing to set.
## - STONE: walk onto the stone, to its own spot there (`spot_on`: the four seats' spots apart, so
##   nobody shoves another off), then WAIT.
## - WAIT: stand there. The starter (one bot of the party, `starter`) presses `accept` while the stone
##   is lit (every wizard of the hub on it), again every RETRY ticks until the party departs.
## - DONE: the party left the hub (a run started; `left_hub`). A later hub (the run's end) is
##   played as a bot plays a room with no fight: the runners are over by then.
##
## Nothing is allocated per step once it found its rack staff (`lying` is read until then).

enum Stage { RACK, BUILD, STONE, WAIT, DONE }

const RouteScript := preload("res://tests/bots/bot_route.gd")
const BuildsScript := preload("res://tests/bots/bot_builds.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## How near the rack staff a bot walks before it presses `take` (pixels; inside the pickup rule's
## reach, `PickupRule.REACH`, 24 px, with a margin for the step it overshoots by).
const RACK_REACH: float = 10.0
## How near its spot on the stone a bot stops (pixels; the stone's area is 96 px across).
const SPOT_REACH: float = 6.0
## How far apart the seats' spots on the stone are from its middle (pixels, each axis).
const SPOT_APART: float = 18.0
## Ticks between two presses of one button that changed nothing yet (a take, a start).
const RETRY: int = 30
## The route's names for its two walks (`bot_route.gd`, `aim`'s `key`).
const KEY_RACK: int = -2
const KEY_STONE: int = -3
## How far a detour round a wall looks where the route has no way (`AISight.detour`).
const DETOUR_PROBE: float = 32.0

## No ground item found yet.
const NO_ITEM: int = -1

var stage: Stage = Stage.RACK
## The button to tap this step (`&""`: none), as the bot's gamepad would: `take` or `accept`.
var tap: StringName = &""
## The ground item it walks to (its number, where it lies), NO_ITEM until found.
var _item: int = NO_ITEM
var _item_at: Vector2 = Vector2.ZERO
var _route: RouteScript = RouteScript.new()
var _since_tap: int = RETRY


## Start the errand afresh (a new hub, a new wizard).
func reset() -> void:
	stage = Stage.RACK
	tap = &""
	_item = NO_ITEM
	_route.reset()
	_since_tap = RETRY


## One step of the errand for the wizard of `seat` with `build` (empty: none): the way to walk (unit
## length, or ZERO), with `tap` set to the button to tap now. `flow` is the Flow autoload, `items`
## the Items autoload; `starter` true for the bot that starts the run. BUILD is left to the bot
## (`built` moves it on).
func step(seat: int, wizard: Actor, build: Dictionary, starter: bool, flow: Node, items: Node) -> Vector2:
	tap = &""
	_since_tap += 1
	match stage:
		Stage.RACK:
			return _to_rack(seat, wizard, build, items)
		Stage.STONE:
			var stone: Rect2 = stone_area(flow)
			if not stone.has_area():
				return Vector2.ZERO
			var way: Vector2 = _walk(wizard, spot_on(stone, seat), SPOT_REACH, KEY_STONE)
			if way == Vector2.ZERO:
				stage = Stage.WAIT
			return way
		Stage.WAIT:
			if starter and bool(flow.call("is_stone_lit")) and _since_tap >= RETRY:
				_press(&"accept")
	return Vector2.ZERO


## Out of the hub: once it waited on the stone, the party departed and the errand is done (a hub
## before that, left some other way, is begun again when it is back).
func left_hub() -> void:
	if stage == Stage.WAIT:
		stage = Stage.DONE


## The bot set its build (or had none to set): on to the stone.
func built() -> void:
	if stage == Stage.BUILD:
		stage = Stage.STONE


## The walk to the rack staff of `build`, and its take.
func _to_rack(seat: int, wizard: Actor, build: Dictionary, items: Node) -> Vector2:
	var wanted: StaffItem = BuildsScript.rack_of(build)
	if wanted == null or items == null:
		stage = Stage.BUILD
		return Vector2.ZERO
	if holds_rack_staff(wizard, wanted):
		stage = Stage.BUILD
		return Vector2.ZERO
	if _item == NO_ITEM or not _still_lies(items):
		_item = NO_ITEM
		var rows: Array[GroundItem] = items.call("lying")
		if rows.is_empty():
			# The room's items are not laid yet (the hub's first tick).
			return Vector2.ZERO
		for row: GroundItem in rows:
			if is_rack_staff(row.stack, wanted):
				_item = row.number
				_item_at = row.at
				break
		if _item == NO_ITEM:
			# Not lying in the hub (another took it): the build goes on without it.
			stage = Stage.BUILD
			return Vector2.ZERO
	if int(items.call("near_of", seat)) == _item:
		if _since_tap >= RETRY:
			_press(&"take")
		return Vector2.ZERO
	return _walk(wizard, _item_at, RACK_REACH, KEY_RACK)


## True while its item still lies on the ground (read through `near_of`'s numbers would need it in
## reach; the rows are read only while it walks, a short while).
func _still_lies(items: Node) -> bool:
	for row: GroundItem in items.call("lying"):
		if row.number == _item:
			return true
	return false


func _press(button: StringName) -> void:
	tap = button
	_since_tap = 0


## The way for `wizard` to walk to within `reach` of `point` over the room's walls (the route's
## field over the whole room, `bot_route.gd`; round a wall toward it where the field has no way: a
## prop's ground, as the stone's, is no cell to stand in for the field), ZERO once there.
func _walk(wizard: Actor, point: Vector2, reach: float, key: int) -> Vector2:
	var feet: Vector2 = wizard.global_position
	if feet.distance_to(point) <= reach:
		return Vector2.ZERO
	var projectiles: ProjectilesScript = wizard.projectiles
	if projectiles == null:
		return Vector2.ZERO
	var way: Vector2 = _route.aim(projectiles, feet, projectiles.bounds(), RoomGrid.NO_PLACE, point, reach, wizard.wall_radius(), key)
	if way != Vector2.ZERO:
		return way
	return AISight.detour(projectiles, feet, point, DETOUR_PROBE)


## Where standing on the room's first teleporter stone counts (`HubRules.area_at`), empty with none.
static func stone_area(flow: Node) -> Rect2:
	var contents: RoomContents = flow.get(&"contents") as RoomContents
	if contents == null:
		return Rect2()
	for stone: Actor in contents.with_role(HubRules.ROLE_RUN_START):
		return HubRules.area_at(stone.prop, stone.position)
	return Rect2()


## Seat `seat`'s spot on the stone's area `stone`: one corner of a square round its middle each.
static func spot_on(stone: Rect2, seat: int) -> Vector2:
	var side: Vector2 = Vector2(-1.0 if seat % 2 == 0 else 1.0, -1.0 if seat < 2 else 1.0)
	return stone.get_center() + side * SPOT_APART


## True when `stack` is the rack staff `wanted` (its staff and its cards), as a person knows it by
## its look and its name.
static func is_rack_staff(stack: ItemStack, wanted: StaffItem) -> bool:
	return stack != null and wanted != null and stack.staff == wanted.staff and stack.cards == stack.fit(wanted.cards)


## True when a hand of `wizard` holds a staff of `wanted`'s staff past the start hands (the rack
## staff, taken; its cards may be rebuilt since).
static func holds_rack_staff(wizard: Actor, wanted: StaffItem) -> bool:
	if wizard == null or wizard.inventory == null or wanted == null:
		return false
	var hands: PackedInt32Array = wizard.inventory.hands()
	for hand in hands.size():
		if hand < BuildsScript.START_HANDS or hands[hand] == Inventory.NO_STAFF:
			continue
		var stack: ItemStack = wizard.inventory.staff(hands[hand])
		if stack != null and stack.staff == wanted.staff:
			return true
	return false
