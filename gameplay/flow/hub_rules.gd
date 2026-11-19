class_name HubRules
extends RefCounted
## The hub's rules (online lobby L1/L2, props W8c, docs/milestones/props.md, "W8c: a room
## foundation"): who stands on the teleporter stone and on the multiplayer altar, read from the props
## standing in the room by what they are (`PropBase.role`: ROLE_RUN_START, ROLE_PARTY_ALTAR), each
## stood on where its own area is (`PropBase.area_rect`), never by a content id; the stone lit while
## every wizard of the hub stands on one, asked of each stone by the bus (`prop_state_requested`:
## LIT, UNLIT, the states a `run_start` prop has). It tells the party where it is (`hub_changed`),
## the HUD who stands on the altar (`altar_changed`), the view where the altar is (`altar_placed`)
## and the stone's count (`start_stone_changed`). A on the lit stone starts the party's departure
## (`depart`): the run starts DEPART_TICKS later (`departure_due`), so the loading screen is up
## before the biome is built, which takes the game a second or more in one tick; the departure is
## told as it begins and ends (`run_departure_changed`). (The lectern of run generation RG7 and its start
## depth went with the row map, connected biomes CB8: a biome's run starts in its start room.)
## Flow's state (it holds one), counted by Flow each tick and as a wizard joins or leaves.

const EventsScript := preload("res://core/events/events.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")

## What a prop is to these rules (`PropBase.role`), and the states a `run_start` prop has.
const ROLE_RUN_START: StringName = &"run_start"
const ROLE_PARTY_ALTAR: StringName = &"party_altar"
const LIT: StringName = &"lit"
const UNLIT: StringName = &"unlit"
const SEATS: int = 4
## Ticks from A on the lit stone to the run's start (a fifth of a second): longer than the loading
## screen takes to come down (hud/panels/loading/, COVER_FRAMES), so it covers the hub before the
## tick that builds the biome. Ticks, not real time: the run starts on the same tick everywhere.
const DEPART_TICKS: int = 12

## Not state: what was last told, only drawn or heard outside the simulation, so a game whose state
## a snapshot replaced tells it again (DERIVED).
const DERIVED: Array[StringName] = [&"_stone_sent", &"_altar_sent", &"_hub_sent", &"_place_sent", &"_place_stands", &"_departure_sent"]

## The wizards on a stone and in the hub at the last count (none out of the hub).
var standing: int = 0
var wizards: int = 0
var _stone_sent: Vector2i = Vector2i(-1, -1)
var _altar_sent: int = -1
var _hub_sent: bool = false
var _place_stands: bool = false
var _place_sent: Vector2 = Vector2.ZERO
## The seat whose A started the departure (-1: none), and the ticks left until the run starts.
var departing_seat: int = -1
var _depart_left: int = 0
var _departure_sent: bool = false


## True while every wizard of the hub stands on a stone, and there is one.
func is_lit() -> bool:
	return wizards > 0 and standing == wizards


## True while the party is departing: A was pressed on the lit stone and the run has not started.
func is_departing() -> bool:
	return departing_seat >= 0


## Seat `seat` pressed A on the lit stone: the run starts DEPART_TICKS from now, whoever steps
## off the stone or joins meanwhile (the press is the party's choice). False, and nothing changes,
## while a departure is already under way.
func depart(seat: int) -> bool:
	if is_departing():
		return false
	departing_seat = seat
	_depart_left = DEPART_TICKS
	return true


## One tick of the departure: the seat that started it on the tick the run is due (the departure
## is over then), else -1.
func departure_due() -> int:
	if not is_departing():
		return -1
	_depart_left -= 1
	if _depart_left > 0:
		return -1
	var seat: int = departing_seat
	departing_seat = -1
	_depart_left = 0
	return seat


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
	if not in_hub:
		# Out of the hub (the run started, the main menu, the hub gone) nothing departs.
		departing_seat = -1
		_depart_left = 0
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
	# The loading screen covers the hub while the party departs (the HUD's).
	if is_departing() != _departure_sent:
		_departure_sent = is_departing()
		events.run_departure_changed.emit(_departure_sent)
	# Where the party is, for whoever lets other machines join it (net/): told as it changes.
	if in_hub != _hub_sent:
		_hub_sent = in_hub
		events.hub_changed.emit(in_hub)
	# Who stands on the altar is told to the HUD only (A there opens the room, net/'s to do).
	if at_altar != _altar_sent:
		_altar_sent = at_altar
		events.altar_changed.emit(at_altar)
	# Where the first altar is, for what the view draws over it (the room's code).
	var stands: bool = not altars.is_empty()
	var place: Vector2 = Vector2.ZERO
	if stands:
		var area: Rect2 = area_at(altars[0].prop, altars[0].position)
		place = Vector2(area.get_center().x, area.position.y)
	if stands != _place_stands or place != _place_sent:
		_place_stands = stands
		_place_sent = place
		events.altar_placed.emit(stands, place)
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
