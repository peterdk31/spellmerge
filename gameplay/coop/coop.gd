extends Node
## Co-op (autoload `Coop`): joining and leaving mid-run, the party's shared view and revives. Up to four players; nobody ever waits for another player.
##
## Joining and leaving: `core/input` turns a button press (or an unplugged
## gamepad, or a bot's virtual device) into `device_joined` / `device_left`, and the frames
## service (core/sim) into the simulation's `seat_joined` / `seat_left` (offline as the device
## does; while a replay plays, as its frames say). Coop hears only those, never a device, and
## turns them into `player_joined(player)` / `player_left(player)`, once each
## per change, in any order and in any slots. `flow` hears them and adds or
## removes the wizard, `difficulty` counts the players. Coop knows the wizards only as the
## actors in the `wizards` group (the wizard scene puts its root there; actors G7) and their
## Downed component, so the run simply goes on.
##
## Friendly fire is no option any more (actors G3c): a player's shots always hit the other
## players, and the shooter too once a shot has left them (owner, 2026-11-06; `Spells._launch`),
## and `combat` turns the hits into damage as for any wizard.
##
## The party's shared view, on the tick (`step_rules`): the part of the room that holds every
## wizard (downed ones too, so a body can still be found) with CAMERA_MARGIN pixels to spare, zoomed
## out no further than MIN_ZOOM and never past the room (`room_laid_out`: the view stops zooming out
## where it would be bigger than the room, and is pushed in from the edge instead). A wizard whose
## seat drives another actor (possess, actors G9) counts twice: its own standing body and the actor
## its seat drives (`ActorController.driving` of its home controller), so both stay in view. It is
## sent as `view_fitted` when it changes. The view is VIEW_SIZE,
## the game's own, never the window's, so it is the same on every machine (online-ready N9). The
## camera that shows it is drawing only: Feel's party camera (gameplay/feel/party_camera.gd) eases
## towards it on real time; nothing here reads a camera.
##
## Revive: a standing wizard within REVIVE_RANGE of a downed one holds the revive.
## After REVIVE_HOLD_TIME the downed wizard comes back (`Downed.revive(reviver)`,
## the reviver being the seat of the nearest standing wizard) and is protected for
## REVIVE_PROTECTION seconds. Out of reach the progress drains at twice the speed
## it fills, so a step away costs a little, not everything. Each downed wizard has
## its own progress (by the wizard's seat, `Downed.seat`), so any number of revives run at
## once, for any seats 0-3, and
## nobody waits for another. `revive_progress(player, progress)` is sent when the
## progress changes, for the ring the downed wizard draws. Reasoning: DECISIONS.md.
##
## Nothing here allocates per tick. Timing runs in `step_rules(delta)`, so tests drive it with
## fixed deltas.

const EventsScript := preload("res://core/events/events.gd")
const DownedScript := preload("res://gameplay/player/downed.gd")

const PLAYER_SLOTS: int = 4
## The group every wizard actor is in (its scene puts it there).
const WIZARDS_GROUP: StringName = &"wizards"
## The game's view in pixels at zoom 1: the project's viewport (display/window/size), which the
## window only scales (stretch mode "viewport"), so it is the same on every machine. A test checks
## the two agree.
const VIEW_SIZE: Vector2 = Vector2(640.0, 360.0)
## Space kept between the outermost wizards and the edge of the view, in pixels.
const CAMERA_MARGIN: float = 48.0
## The view never zooms in past 1 or out past 0.5 (Camera2D zoom: smaller sees more).
const MAX_ZOOM: float = 1.0
const MIN_ZOOM: float = 0.5

## Seconds a standing wizard must stay near a downed one to revive it.
const REVIVE_HOLD_TIME: float = 2.0
## How close (centre to centre, pixels) a standing wizard must be: about one body
## and a half, so it must really be beside the body, not just on screen.
const REVIVE_RANGE: float = 48.0
## The progress drains this many times faster than it fills when nobody is near.
const REVIVE_DRAIN_FACTOR: float = 2.0
## Seconds a revived wizard cannot be hurt, enough to step away from what downed it.
const REVIVE_PROTECTION: float = 1.5

## Not state: services, caches and scratch, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"events"]
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_wizards", &"_downs"]

## Why Coop needs no renewing at a run's start (core/sim/sim_area.gd, `fresh_because`).
const FRESH_BECAUSE: String = "the seats' joins are the session's; room_laid_out and room_entered set the run's room, view, wizards and revives"
## The reasons the pause menu stops the game (`Sim.stop`), one a seat: a seat's open menu stops it
## for everyone, and only that seat's closing, or the seat leaving, lets it go. A seat that leaves
## with its menu open (a machine gone back to the main menu, or lost, online: its closing never
## comes) must not leave everyone else stopped; and online two machines' menus may be open at
## once, each its own reason.
const MENU_OF: Array[StringName] = [&"menu_0", &"menu_1", &"menu_2", &"menu_3"]

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null

## The room the view stays inside, in world pixels (`room_laid_out`); Rect2() for no bounds.
var room: Rect2 = Rect2()

## The party's view, the part of the world that holds every wizard, worked out on the tick (`step_rules`) and
## sent as `view_fitted` when it changes; Rect2() before the first fit of a room.
var fitted_view: Rect2 = Rect2()
## The box round the party inside it (every wizard and the bodies they drive), sent with it.
var fitted_party: Rect2 = Rect2()

var _joined: Array[bool] = [false, false, false, false]
var _joined_count: int = 0
var _wizards: Array[Node2D] = []
## The Downed component of each of `_wizards` (null for a body without one), found once.
var _downs: Array[DownedScript] = []
## Per player index: how far the revive has got (0 to 1), and what was last sent.
var _revive: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _revive_sent: Array[float] = [0.0, 0.0, 0.0, 0.0]


func _ready() -> void:
	# The tick steps it (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Coop").steps(&"Coop", step_rules).fresh_because(FRESH_BECAUSE)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if events == null:
		push_warning("Coop: the Events autoload is missing, so nobody can join.")
		return
	events.seat_joined.connect(_on_seat_joined)
	events.seat_left.connect(_on_seat_left)
	events.room_laid_out.connect(_on_room_laid_out)
	events.room_entered.connect(_on_room_entered)
	# A command, heard at the tick's start (core/events, online-ready N2).
	events.listen(&"pause_requested", _on_pause_requested)


## `player` opened (`on` 1) or closed (`on` 0) the pause menu (a command, at a tick's start;
## online-ready N4): the game stops while it is open (`Sim.stop`), and the Tick pauses the tree for
## the picture.
func _on_pause_requested(player: int, on: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	var game: Sim = Sim.found(self)
	if on != 0:
		game.stop(MENU_OF[player])
	else:
		game.go(MENU_OF[player])


## True while some seat's pause menu stops `game`.
static func menu_stops(game: Sim) -> bool:
	for reason in MENU_OF:
		if game.stopped_for(reason):
			return true
	return false


## Coop's rules, once a tick (core/sim/tick.gd): the party's view (`view_fitted`), then the
## revives.
func step_rules(delta: float) -> void:
	if not _all_valid():
		refresh_wizards()
	var party: Rect2 = _party_box()
	if party.size.x >= 0.0:
		var fit: Vector3 = _fit(party)
		var size: Vector2 = VIEW_SIZE / fit.z
		var view := Rect2(Vector2(fit.x, fit.y) - size * 0.5, size)
		if view != fitted_view or party != fitted_party:
			fitted_view = view
			fitted_party = party
			if events != null:
				events.view_fitted.emit(view, party)
	step_revive(delta)


## Number of players who are in right now.
func joined_count() -> int:
	return _joined_count


func is_joined(player: int) -> bool:
	return player >= 0 and player < PLAYER_SLOTS and _joined[player]


## Read the wizards in the `wizards` group again. Done by itself after a join, a
## leave and `room_entered`. They are kept by actor id (online-ready N3c: the group's order is the
## tree's, which a game rebuilt from a snapshot need not repeat), so revives go in that order.
func refresh_wizards() -> void:
	_wizards.clear()
	_downs.clear()
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(WIZARDS_GROUP):
		if node is Node2D:
			var at: int = _wizards.size()
			while at > 0 and _id_of(_wizards[at - 1]) > _id_of(node):
				at -= 1
			_wizards.insert(at, node as Node2D)
			_downs.insert(at, DownedScript.of(node))


## A wizard's actor id (the order of `_wizards`), or -1 for a body without one.
static func _id_of(body: Node) -> int:
	var id: Variant = body.get(&"id")
	return id if id is int else -1


## Where a view holding `party` with CAMERA_MARGIN to spare would be, and its zoom: (centre x,
## centre y, zoom).
func _fit(party: Rect2) -> Vector3:
	var view: Vector2 = VIEW_SIZE
	var need: Vector2 = party.size + Vector2.ONE * (CAMERA_MARGIN * 2.0)
	var floor_zoom: float = _min_zoom()
	var zoom: float = clampf(minf(view.x / need.x, view.y / need.y), floor_zoom, maxf(MAX_ZOOM, floor_zoom))
	var centre: Vector2 = _clamp_centre(party.get_center(), zoom)
	return Vector3(centre.x, centre.y, zoom)


## The box round every wizard and the bodies their seats drive now; a negative size with none.
func _party_box() -> Rect2:
	var low := Vector2.INF
	var high := -Vector2.INF
	var seen: int = 0
	for wizard: Node2D in _wizards:
		if not is_instance_valid(wizard) or not wizard.is_inside_tree():
			continue
		var at: Vector2 = wizard.global_position
		low = low.min(at)
		high = high.max(at)
		seen += 1
		var body := wizard as Actor
		if body == null or body.home_controller == null:
			continue
		if not is_instance_valid(body.home_controller.driving):
			continue
		var driven: Actor = body.home_controller.driving
		if driven != body and driven.is_inside_tree():
			low = low.min(driven.global_position)
			high = high.max(driven.global_position)
	if seen == 0:
		return Rect2(Vector2.ZERO, -Vector2.ONE)
	return Rect2(low, high - low)


## The smallest zoom allowed: MIN_ZOOM, but never so far out that the view is bigger than the
## room, which would show empty space.
func _min_zoom() -> float:
	if room.size.x <= 0.0 or room.size.y <= 0.0:
		return MIN_ZOOM
	return maxf(MIN_ZOOM, maxf(VIEW_SIZE.x / room.size.x, VIEW_SIZE.y / room.size.y))


## Move a view's centre so the view at `zoom` stays inside the room (centred on an axis the room is
## smaller than the view on).
func _clamp_centre(centre: Vector2, zoom: float) -> Vector2:
	if room.size.x <= 0.0 or room.size.y <= 0.0:
		return centre
	var half: Vector2 = VIEW_SIZE * (0.5 / zoom)
	var low: Vector2 = room.position + half
	var high: Vector2 = room.end - half
	var mid: Vector2 = room.get_center()
	var x: float = clampf(centre.x, low.x, high.x) if low.x <= high.x else mid.x
	var y: float = clampf(centre.y, low.y, high.y) if low.y <= high.y else mid.y
	return Vector2(x, y)


## Advance every revive by `delta` seconds (`step_rules` calls it). A downed wizard
## fills while any standing wizard is within REVIVE_RANGE and drains otherwise.
func step_revive(delta: float) -> void:
	if delta <= 0.0:
		return
	if not _all_valid():
		refresh_wizards()
	for at in _wizards.size():
		var body: Node2D = _wizards[at]
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var wizard: DownedScript = _downs[at]
		var player: int = wizard.seat() if wizard != null else -1
		if player < 0 or player >= PLAYER_SLOTS:
			continue
		if not wizard.is_down():
			_set_revive(player, 0.0)
			continue
		var reviver: int = _nearest_reviver(body)
		if reviver < 0:
			_set_revive(player, _revive[player] - delta * REVIVE_DRAIN_FACTOR / REVIVE_HOLD_TIME)
			continue
		var progress: float = _revive[player] + delta / REVIVE_HOLD_TIME
		if progress < 1.0:
			_set_revive(player, progress)
			continue
		_set_revive(player, 0.0)
		if wizard.revive(reviver):
			wizard.protect(REVIVE_PROTECTION)


## The seat of the standing wizard nearest to `body` within REVIVE_RANGE, or -1.
func _nearest_reviver(body: Node2D) -> int:
	var best: int = -1
	var best_distance: float = REVIVE_RANGE
	for at in _wizards.size():
		var other: Node2D = _wizards[at]
		if other == body or not is_instance_valid(other) or not other.is_inside_tree():
			continue
		var teammate: DownedScript = _downs[at]
		if teammate == null or teammate.is_down():
			continue
		var distance: float = other.global_position.distance_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = teammate.seat()
	return best


## Keep a player's progress between 0 and 1 and send it when it changed.
func _set_revive(player: int, progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	_revive[player] = progress
	if progress != _revive_sent[player]:
		_revive_sent[player] = progress
		if events != null:
			events.revive_progress.emit(player, progress)


## How far the revive of `player` has got, 0 to 1.
func revive_progress_of(player: int) -> float:
	return _revive[player] if player >= 0 and player < PLAYER_SLOTS else 0.0


func _all_valid() -> bool:
	for wizard: Node2D in _wizards:
		if not is_instance_valid(wizard):
			return false
	return true


func _on_seat_joined(player: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS or _joined[player]:
		return
	_joined[player] = true
	_joined_count += 1
	if events != null:
		events.player_joined.emit(player)
	# `flow` added the wizard while the event was going out.
	refresh_wizards()


func _on_seat_left(player: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	# A seat that leaves with its pause menu open lets the game go (heard where the frames say the
	# seat left, so on every machine at the same tick).
	var game: Sim = Sim.found(self)
	if game != null:
		game.go(MENU_OF[player])
	if not _joined[player]:
		return
	_set_revive(player, 0.0)
	_joined[player] = false
	_joined_count -= 1
	if events != null:
		events.player_left.emit(player)
	refresh_wizards()


## Forget all progress (a new world has new wizards).
func _clear_revives() -> void:
	for player in PLAYER_SLOTS:
		_set_revive(player, 0.0)


## A room is laid out (`room_laid_out`, just before `room_entered`): the view stays inside it.
func _on_room_laid_out(bounds: Rect2) -> void:
	room = bounds


## A new world is up: a new view is fitted at the next tick, and its wizards and revives are new.
func _on_room_entered(_room_id: StringName) -> void:
	fitted_view = Rect2()
	fitted_party = Rect2()
	refresh_wizards()
	_clear_revives()
