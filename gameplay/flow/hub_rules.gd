class_name HubRules
extends RefCounted
## The hub's rules (online lobby L1/L2, props W8c, docs/milestones/props.md, "W8c: a room
## foundation"): who stands on the teleporter stone and on the multiplayer altar, read from the props
## standing in the room by what they are (`PropBase.role`: ROLE_RUN_START, ROLE_PARTY_ALTAR), each
## stood on where its own area is (`PropBase.area_rect`), never by a content id; the stone lit while
## every wizard of the hub stands on one, asked of each stone by the bus (`prop_state_requested`:
## LIT, UNLIT, the states a `run_start` prop has). It tells the party where it is (`hub_changed`),
## the HUD who stands on the altar (`altar_changed`), the view where the altar is (`altar_placed`)
## and the stone's count (`start_stone_changed`).
##
## The trial gate (boss OB2, docs/milestones/boss-old-broom.md, decision 27): each seat's pick of a
## room to try (`picks`, by seat, set by the command `trial_picked` through Flow, which checks the
## room is one the lectern offers), kept while that seat's wizard is in the hub and forgotten as it
## leaves it (a joiner has none); who stands at the lectern (ROLE_TRIAL_LECTERN, told to the HUD by
## `lectern_changed`: A there opens that seat's room menu); and the gate (ROLE_TRIAL_GATE), lit only
## while every wizard of the hub stands in one and every one of them picked the same room
## (`agreed_pick`), asked of each gate as the stone is (LIT, UNLIT) and told by
## `trial_gate_changed`; the picks are drawn over the first gate (`trial_picks_changed`, view only).
## Flow's state (it holds one), counted by Flow each tick and as a wizard joins or leaves.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")

## What a prop is to these rules (`PropBase.role`), and the states a `run_start` prop has.
const ROLE_RUN_START: StringName = &"run_start"
const ROLE_PARTY_ALTAR: StringName = &"party_altar"
## The trial gate (lit as the stone is: LIT, UNLIT) and the lectern beside it (boss OB2).
const ROLE_TRIAL_GATE: StringName = &"trial_gate"
const ROLE_TRIAL_LECTERN: StringName = &"trial_lectern"
## The registry folder the picked rooms are found in (as Flow's).
const ROOM_FOLDER: StringName = &"rooms"
## Every role these rules read (a prop of another role is a mistake: tests/content/props).
const ROLES: Array[StringName] = [ROLE_RUN_START, ROLE_PARTY_ALTAR, ROLE_TRIAL_GATE, ROLE_TRIAL_LECTERN]
## The roles lit and put out (LIT, UNLIT states).
const LIT_ROLES: Array[StringName] = [ROLE_RUN_START, ROLE_TRIAL_GATE]
const LIT: StringName = &"lit"
const UNLIT: StringName = &"unlit"
const SEATS: int = 4

## Not state: what was last told, only drawn or heard outside the simulation, so a game whose state
## a snapshot replaced tells it again (DERIVED).
const DERIVED: Array[StringName] = [&"_stone_sent", &"_altar_sent", &"_hub_sent", &"_place_sent", &"_place_stands",
	&"_gate_sent", &"_lectern_sent", &"_picks_sent", &"_gate_place_sent", &"_gate_stands",
	&"_stones", &"_altars", &"_gates", &"_lecterns"]

## The wizards on a stone and in the hub at the last count (none out of the hub).
var standing: int = 0
var wizards: int = 0
## The wizards in a trial gate at the last count, and each seat's pick (`&""`: none).
var in_gate: int = 0
var picks: Array[StringName] = [&"", &"", &"", &""]
## The seats with a wizard in the hub at the last count, a bit each.
var _present: int = 0
var _stone_sent: Vector2i = Vector2i(-1, -1)
var _altar_sent: int = -1
var _hub_sent: bool = false
var _place_stands: bool = false
var _place_sent: Vector2 = Vector2.ZERO
var _gate_sent: Vector3i = Vector3i(-1, -1, -1)
var _lectern_sent: int = -1
var _picks_sent: Array[StringName] = []
var _gate_stands: bool = false
var _gate_place_sent: Vector2 = Vector2.ZERO
## The props of each role standing at the last count (scratch, filled again each count).
var _stones: Array[Actor] = []
var _altars: Array[Actor] = []
var _gates: Array[Actor] = []
var _lecterns: Array[Actor] = []


## True while every wizard of the hub stands on a stone, and there is one.
func is_lit() -> bool:
	return wizards > 0 and standing == wizards


## The room every wizard of the hub picked, or `&""` while one picked none or another (or none is
## there).
func agreed_pick() -> StringName:
	if wizards <= 0:
		return &""
	var agreed: StringName = &""
	var seen: bool = false
	for seat in SEATS:
		if _present & (1 << seat) == 0:
			continue
		if not seen:
			agreed = picks[seat]
			seen = true
		elif picks[seat] != agreed:
			return &""
	return agreed


## True while every wizard of the hub stands in a trial gate and all of them picked the same room.
func is_gate_lit() -> bool:
	return wizards > 0 and in_gate == wizards and agreed_pick() != &""


## Seat `seat` picks the room `room_id` for the trial gate (`&""`: no pick). The caller checks the
## room is offered (`RoomBase.offered_for_trial`) and the seat has a wizard in the hub; told at the
## next count.
func pick(seat: int, room_id: StringName) -> void:
	if seat >= 0 and seat < SEATS:
		picks[seat] = room_id


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
## `in_hub`, ask the stones and gates to light or go out when that changes, and tell what changed
## (the picks' rooms by their shown names, from `registry`). A seat with no wizard in the hub
## forgets its pick.
func count(in_hub: bool, party: Array[Node2D], contents: RoomContents, events: EventsScript, registry: RegistryScript = null) -> void:
	standing = 0
	wizards = 0
	in_gate = 0
	_present = 0
	var at_altar: int = 0
	var at_lectern: int = 0
	var stones: Array[Actor] = _stones
	var altars: Array[Actor] = _altars
	var gates: Array[Actor] = _gates
	var lecterns: Array[Actor] = _lecterns
	stones.clear()
	altars.clear()
	gates.clear()
	lecterns.clear()
	if in_hub:
		contents.fill_with_role(ROLE_RUN_START, stones)
		contents.fill_with_role(ROLE_PARTY_ALTAR, altars)
		contents.fill_with_role(ROLE_TRIAL_GATE, gates)
		contents.fill_with_role(ROLE_TRIAL_LECTERN, lecterns)
		for wizard: Node2D in party:
			if not is_instance_valid(wizard):
				continue
			wizards += 1
			if _on_any(stones, wizard.position):
				standing += 1
			if _on_any(gates, wizard.position):
				in_gate += 1
			var controller: PlayerScript = PlayerScript.of(wizard)
			var seat: int = controller.seat if controller != null else -1
			if seat < 0 or seat >= SEATS:
				continue
			_present |= 1 << seat
			if _on_any(altars, wizard.position):
				at_altar |= 1 << seat
			if _on_any(lecterns, wizard.position):
				at_lectern |= 1 << seat
	for seat in SEATS:
		if _present & (1 << seat) == 0:
			picks[seat] = &""
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
	_light(stones, lit, events)
	var now := Vector2i(standing, wizards)
	if now != _stone_sent:
		_stone_sent = now
		events.start_stone_changed.emit(standing, wizards, lit)
	_tell_trial(gates, at_lectern, events, registry)


## The trial gate's part of a count: the gates lit or put out, who stands at the lectern, the gate's
## count, and the picks drawn over the first gate, each told as it changes.
func _tell_trial(gates: Array[Actor], at_lectern: int, events: EventsScript, registry: RegistryScript) -> void:
	var lit: bool = is_gate_lit()
	_light(gates, lit, events)
	var now := Vector3i(in_gate, wizards, 1 if lit else 0)
	if now != _gate_sent:
		_gate_sent = now
		events.trial_gate_changed.emit(in_gate, wizards, lit)
	if at_lectern != _lectern_sent:
		_lectern_sent = at_lectern
		events.lectern_changed.emit(at_lectern)
	var stands: bool = not gates.is_empty()
	var place: Vector2 = Vector2.ZERO
	if stands:
		var area: Rect2 = area_at(gates[0].prop, gates[0].position)
		place = Vector2(area.get_center().x, area.position.y)
	if picks != _picks_sent or stands != _gate_stands or place != _gate_place_sent:
		_picks_sent = picks.duplicate()
		_gate_stands = stands
		_gate_place_sent = place
		events.trial_picks_changed.emit(_names_of(picks, registry), stands, place)


## Each pick's room by its shown name (`RoomBase.shown_name`; its id with no registry), "" for none.
static func _names_of(chosen: Array[StringName], registry: RegistryScript) -> PackedStringArray:
	var out := PackedStringArray()
	for id: StringName in chosen:
		var room: RoomBase = null
		if id != &"" and registry != null:
			room = registry.get_resource(ROOM_FOLDER, id) as RoomBase
		out.append(room.shown_name() if room != null else String(id))
	return out


## Ask each of `props` (stones or gates) to enter LIT or UNLIT, whenever one is not in the state
## wanted (one stood again, or one that left it by its own triggers, follows at once).
static func _light(props: Array[Actor], lit: bool, events: EventsScript) -> void:
	var want: StringName = LIT if lit else UNLIT
	for prop in props:
		if prop.state_triggers != null and prop.state_triggers.state_id() != want:
			events.prop_state_requested.emit(prop.id, want)


static func _on_any(props: Array[Actor], point: Vector2) -> bool:
	for prop in props:
		if area_at(prop.prop, prop.position).has_point(point):
			return true
	return false
