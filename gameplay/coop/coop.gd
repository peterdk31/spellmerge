extends Node
## Co-op (autoload `Coop`): joining and leaving mid-run and revives. Up to four players; nobody ever waits for another player,
## but for a seat whose gamepad is unplugged (owner, 2026-11-13: the game stops until it is back).
##
## Joining and leaving: `core/input` turns a button press (or a bot's virtual device) into `device_joined` / `device_left`, and the frames
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
## The camera is not Coop's: each machine frames its own seats' wizards as it draws (Feel's party
## camera, gameplay/feel/party_camera.gd), so nothing here knows a view or a room's size.
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
const FRESH_BECAUSE: String = "the seats' joins are the session's; room_entered sets the run's wizards and revives"
## The reasons the pause menu stops the game (`Sim.stop`), one a seat: a seat's open menu stops it
## for everyone, and only that seat's closing, or the seat leaving, lets it go. A seat that leaves
## with its menu open (a machine gone back to the main menu, or lost, online: its closing never
## comes) must not leave everyone else stopped; and online two machines' menus may be open at
## once, each its own reason.
const MENU_OF: Array[StringName] = [&"menu_0", &"menu_1", &"menu_2", &"menu_3"]
## The reasons a seat's unplugged gamepad stops the game, one a seat (owner, 2026-11-13: the seat
## keeps its wizard and everyone waits for the controller): let go when the seat has a gamepad
## again, or leaves.
const PAD_OF: Array[StringName] = [&"pad_0", &"pad_1", &"pad_2", &"pad_3"]

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null

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
	events.room_entered.connect(_on_room_entered)
	# A command, heard at the tick's start (core/events, online-ready N2).
	events.listen(&"pause_requested", _on_pause_requested)
	events.listen(&"pad_wait_requested", _on_pad_wait_requested)


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


## Seat `player`'s gamepad was unplugged (`on` 1) or the seat has one again (`on` 0) (a command, at
## a tick's start): the game stops for everyone while a seat that plays waits for its gamepad. A
## seat that has left meanwhile stops nothing.
func _on_pad_wait_requested(player: int, on: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	var game: Sim = Sim.found(self)
	if on == 0:
		game.go(PAD_OF[player])
	elif _joined[player]:
		game.stop(PAD_OF[player])
	_send_pad_wait(game)


## The seats `game` stands stopped for because their gamepad is unplugged, a bit each.
static func pad_waits(game: Sim) -> int:
	var seats: int = 0
	for seat in PLAYER_SLOTS:
		if game.stopped_for(PAD_OF[seat]):
			seats |= 1 << seat
	return seats


func _send_pad_wait(game: Sim) -> void:
	if events != null:
		events.pad_wait_changed.emit(pad_waits(game))


## True while some seat's pause menu stops `game`.
static func menu_stops(game: Sim) -> bool:
	for reason in MENU_OF:
		if game.stopped_for(reason):
			return true
	return false


## Coop's rules, once a tick (core/sim/tick.gd): the revives.
func step_rules(delta: float) -> void:
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
		# Nobody waits for the gamepad of a seat that left.
		if game.stopped_for(PAD_OF[player]):
			game.go(PAD_OF[player])
			_send_pad_wait(game)
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


## A new world is up: its wizards and revives are new.
func _on_room_entered(_room_id: StringName) -> void:
	refresh_wizards()
	_clear_revives()
