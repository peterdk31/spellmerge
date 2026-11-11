class_name HubRules
extends RefCounted
## The hub's rules (online lobby L1/L2, props W8c, docs/milestones/props.md, "W8c: a room
## foundation"): who stands on the teleporter stone and on the multiplayer altar, read from the props
## standing in the room by what they are (`PropBase.role`: ROLE_RUN_START, ROLE_PARTY_ALTAR), each
## stood on where its own area is (`PropBase.area_rect`), never by a content id; the stone lit while
## every wizard of the hub stands on one, asked of each stone by the bus (`prop_state_requested`:
## LIT, UNLIT, the states a `run_start` prop has). It tells the party where it is (`hub_changed`),
## the HUD who stands on the altar (`altar_changed`) and the stone's count (`start_stone_changed`).
## Flow's state (it holds one), counted by Flow each tick and as a wizard joins or leaves.

const EventsScript := preload("res://core/events/events.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")

## What a prop is to these rules (`PropBase.role`), and the states a `run_start` prop has.
const ROLE_RUN_START: StringName = &"run_start"
const ROLE_PARTY_ALTAR: StringName = &"party_altar"
const LIT: StringName = &"lit"
const UNLIT: StringName = &"unlit"
const SEATS: int = 4

## Not state: what was last told, only drawn or heard outside the simulation, so a game whose state
## a snapshot replaced tells it again (DERIVED).
const DERIVED: Array[StringName] = [&"_stone_sent", &"_altar_sent", &"_hub_sent"]

## The wizards on a stone and in the hub at the last count (none out of the hub).
var standing: int = 0
var wizards: int = 0
var _stone_sent: Vector2i = Vector2i(-1, -1)
var _altar_sent: int = -1
var _hub_sent: bool = false


## True while every wizard of the hub stands on a stone, and there is one.
func is_lit() -> bool:
	return wizards > 0 and standing == wizards


## Where standing on a prop of `data` whose feet are at `at` counts, in room pixels (empty: none).
static func area_at(data: PropBase, at: Vector2) -> Rect2:
	var area: Rect2 = data.area_rect() if data != null else Rect2()
	return Rect2(area.position + at, area.size) if area.has_area() else Rect2()


## Where standing on the first prop of `role` a room places counts (`RoomPlaces`; tests and tools).
static func area_of(places: RoomPlaces, role: StringName) -> Rect2:
	for i in places.placed.size():
		var data := places.placed[i] as PropBase
		if data != null and data.role == role:
			return area_at(data, places.placed_at[i])
	return Rect2()


## Count `party` (the wizards, by seat through their controller) on the props of `contents` while
## `in_hub`, ask the stones to light or go out when that changes, and tell what changed.
func count(in_hub: bool, party: Array[Node2D], contents: RoomContents, events: EventsScript) -> void:
	standing = 0
	wizards = 0
	var at_altar: int = 0
	var stones: Array[Actor] = []
	var altars: Array[Actor] = []
	if in_hub:
		stones = contents.with_role(ROLE_RUN_START)
		altars = contents.with_role(ROLE_PARTY_ALTAR)
		for wizard: Node2D in party:
			if not is_instance_valid(wizard):
				continue
			wizards += 1
			if _on_any(stones, wizard.position):
				standing += 1
			var controller: PlayerScript = PlayerScript.of(wizard)
			var seat: int = controller.seat if controller != null else -1
			if seat >= 0 and seat < SEATS and _on_any(altars, wizard.position):
				at_altar |= 1 << seat
	if events == null:
		return
	# Where the party is, for whoever lets other machines join it (net/): told as it changes.
	if in_hub != _hub_sent:
		_hub_sent = in_hub
		events.hub_changed.emit(in_hub)
	# Who stands on the altar is told to the HUD only (A there opens the room, net/'s to do).
	if at_altar != _altar_sent:
		_altar_sent = at_altar
		events.altar_changed.emit(at_altar)
	var lit: bool = is_lit()
	# Asked whenever a stone is not in the state wanted (a stone stood again, or one that left it
	# by its own triggers, follows at once).
	var want: StringName = LIT if lit else UNLIT
	for stone in stones:
		if stone.state_triggers != null and stone.state_triggers.state_id() != want:
			events.prop_state_requested.emit(stone.id, want)
	var now := Vector2i(standing, wizards)
	if now != _stone_sent:
		_stone_sent = now
		events.start_stone_changed.emit(standing, wizards, lit)


static func _on_any(props: Array[Actor], point: Vector2) -> bool:
	for prop in props:
		if area_at(prop.prop, prop.position).has_point(point):
			return true
	return false
