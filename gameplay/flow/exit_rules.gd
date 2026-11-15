class_name ExitRules
extends RefCounted
## The exits of a run's room (run generation RG4, docs/milestones/run-generation.md, "Exits and the
## way on"): the props standing in it of the role `RoomBase.EXIT_ROLE`, read by what they are, never
## by a content id, each stood on where its own area is (`PropBase.area_rect`). The room leads to the
## rooms of the next row of the run's map its `ways` name (their kinds, left to right, as the map
## holds its links). Dark while the room is under way; once it is cleared (`open`), the ways spread
## over its exits left to right (`exit_of`) and each of those is lit, asked of the prop by the bus
## (`prop_state_requested`: LIT, DARK, the states a `room_exit` has), the rest stay dark. When every
## wizard standing (not down) stands in one lit exit (where its own body is: a seat driving another
## body holds the party until it comes back), `count` names its way: the party goes on, with
## no button (owner, 2026-11-15: "Just everyone stepping into it"). Stepping in is position only, so
## it is the simulation's own and needs no command.
##
## The view is told where the lit exits are and the kind of room behind each (`room_exits_shown`),
## as it changes. Flow's state (it holds one), counted by Flow each tick in a run's room.

const EventsScript := preload("res://core/events/events.gd")

## The states a `room_exit` prop has: dark (its first) and lit.
const DARK: StringName = &"dark"
const LIT: StringName = &"lit"
## No way taken.
const NONE: int = -1

## Not state: what the view was last told, only drawn outside the simulation, so a game whose state
## a snapshot replaced tells it again.
const DERIVED: Array[StringName] = [&"_shown_at", &"_shown_kinds"]

## The kinds of the rooms the room in play leads to, left to right (the run's map's links); none for
## the run's last room, and out of a run of rooms.
var ways: Array[StringName] = []
## True once the room is cleared: its exits with a way are lit.
var open: bool = false
var _shown_at: PackedVector2Array = PackedVector2Array()
var _shown_kinds: Array[StringName] = []


## A room of the run is entered: it leads to `room_ways` (kinds, left to right), every exit dark.
func enter(room_ways: Array[StringName]) -> void:
	ways = room_ways.duplicate()
	open = false


## No room of a run is in play (the hub, the sandbox, the run over): no way, every exit dark.
func leave() -> void:
	ways.clear()
	open = false


## The exit (0 = the leftmost of `exits`) that way `way` of `count` leads through: the ways spread
## evenly over the exits, in order (one way of two exits: the right one; of three: the middle one).
## Whole numbers only, so it is the same on every machine.
static func exit_of(way: int, count: int, exits: int) -> int:
	return (way * 2 + 1) * exits / (count * 2)


## The exits standing in `contents`, left to right (then top to bottom; then in the room's order).
static func exits_in(contents: RoomContents) -> Array[Actor]:
	var found: Array[Actor] = contents.with_role(RoomBase.EXIT_ROLE)
	# An insertion sort: stable, so exits at one place keep the room's order on every machine.
	for i in range(1, found.size()):
		var exit: Actor = found[i]
		var j: int = i - 1
		while j >= 0 and _before(exit.position, found[j].position):
			found[j + 1] = found[j]
			j -= 1
		found[j + 1] = exit
	return found


## For each exit of `exits` (left to right), the way it leads by, or NONE for an exit kept dark. Ways
## past the exits there are lead nowhere (a template is never picked for a room with more links than
## it has exits: the run generator's `_pick_templates`).
func way_of_each(exits: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	found.resize(exits)
	found.fill(NONE)
	if not open:
		return found
	var count: int = mini(ways.size(), exits)
	for way in count:
		found[exit_of(way, count, exits)] = way
	return found


## Count `party` (the wizards) in the lit exits of `contents`, ask every exit to be lit or dark as
## its way says, tell the view what changed, and return the way every standing wizard stands in
## (NONE while none is so: a wizard elsewhere holds the party, nobody picks for anyone).
func count(party: Array[Node2D], contents: RoomContents, events: EventsScript) -> int:
	var exits: Array[Actor] = exits_in(contents)
	var way_of: PackedInt32Array = way_of_each(exits.size())
	var at := PackedVector2Array()
	var kinds: Array[StringName] = []
	var taken: int = NONE
	for i in exits.size():
		var exit: Actor = exits[i]
		var want: StringName = LIT if way_of[i] != NONE else DARK
		if events != null and exit.state_triggers != null and exit.state_triggers.state_id() != want:
			events.prop_state_requested.emit(exit.id, want)
		if way_of[i] == NONE:
			continue
		var area: Rect2 = HubRules.area_at(exit.prop, exit.position)
		at.append(Vector2(area.get_center().x, area.position.y))
		kinds.append(ways[way_of[i]])
		if taken == NONE and _everyone_in(party, area):
			taken = way_of[i]
	if events != null and (at != _shown_at or kinds != _shown_kinds):
		_shown_at = at
		_shown_kinds = kinds
		events.room_exits_shown.emit(at.duplicate(), kinds.duplicate())
	return taken


## True when at least one wizard of `party` stands (is not down) and every one standing is in `area`.
static func _everyone_in(party: Array[Node2D], area: Rect2) -> bool:
	var standing: int = 0
	for wizard: Node2D in party:
		if not is_instance_valid(wizard) or (wizard is Actor and (wizard as Actor).is_down()):
			continue
		standing += 1
		if not area.has_point(wizard.position):
			return false
	return standing > 0


static func _before(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
