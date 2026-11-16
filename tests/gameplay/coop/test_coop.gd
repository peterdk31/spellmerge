extends "res://tests/support/suite.gd"
## gameplay/coop on the real autoloads (the real wiring of Flow, PlayerInput, Coop, Feel's party
## camera, Combat and the projectiles is the point): every join order of 1-4 players (the first is in
## when Play is pressed, the rest join mid-run), every leave order, no duplicate events, Feel's party
## camera keeps every wizard on this machine in the picture (zooms out as the players spread, never
## past the room, eases instead of jumping), the revive, a wizard's bolt hits a teammate (friendly
## fire is always on), not the shooter it leaves, and the stops a seat's pause menu or unplugged
## gamepad put on the game. Each test joins the players it needs by virtual devices and starts its
## own run of arena_01 (pinned, so its spawns are known); `after_each` stops it, frees the devices
## and drops the test's listeners. The order tests walk the 24 orders of all four players: every
## shorter order is the start of one of them, and is checked at each step. Those nine tests take
## about a second each, so the runner plays the file in processes side by side
## (tests/support/suite.gd, "shards"):
# unit-test-shards: 2

const CoopScript := preload("res://gameplay/coop/coop.gd")
const FlowScript := preload("res://gameplay/flow/flow.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
## The room every run here plays (its spawns are named below): the crypt run picks among several.
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")

const VIEW: Vector2 = Vector2(640.0, 360.0)
const BOLT_TAG: int = 1
const SHOT_DAMAGE: int = 10

var events: Node
var coop: CoopScript
var flow: FlowScript
var input: InputManagerScript
var combat: Node
var projectiles: ProjectileManagerScript
var party: PartyCameraScript
var actors: ActorsScript
var feel: Node
var joined_events: Array = []
var left_events: Array = []
## [signal, callable] of every listener the test connected to the game's bus.
var _listening: Array[Array] = []


func before_each() -> void:
	events = root.get_node("Events")
	coop = root.get_node("Coop") as CoopScript
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput") as InputManagerScript
	combat = root.get_node("Combat")
	projectiles = root.get_node("Projectiles") as ProjectileManagerScript
	actors = root.get_node("Actors") as ActorsScript
	feel = root.get_node("Feel")
	party = feel.get("party_camera") as PartyCameraScript
	# A run of arena_01 alone, so the spawns and limits checked below are its (run generation RG3b:
	# the crypt run's first room is any of its fight rooms).
	flow.run_id_to_play = PinnedRun.pin(root.get_node("Registry"), ARENA)
	joined_events.clear()
	left_events.clear()
	_listen("player_joined", func(player: int) -> void: joined_events.append(player))
	_listen("player_left", func(player: int) -> void: left_events.append(player))


func after_each() -> void:
	_stop()
	# No menu or gamepad wait a test opened stands (the game's sim is cleared for the next test too).
	for seat in InputManagerScript.MAX_PLAYERS:
		_command(&"pause_requested", [seat, 0])
		_command(&"pad_wait_requested", [seat, 0])
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	(root.get_node("Frames") as Node).call("stop_playing")
	(root.get_node("Spells") as Node).get("_profiles").erase(BOLT_TAG)
	for row: Array in _listening:
		if events.is_connected(row[0], row[1]):
			events.disconnect(row[0], row[1])
	_listening.clear()


## Connects `callable` to the game's bus's `signal_name` for this test.
func _listen(signal_name: StringName, callable: Callable) -> void:
	events.connect(signal_name, callable)
	_listening.append([signal_name, callable])


func _stop() -> void:
	flow.stop_run()
	for index in InputManagerScript.MAX_PLAYERS:
		input.leave(index)
	joined_events.clear()
	left_events.clear()


## The wizard actor of player `index` (actors G7), or null.
func _wizard(index: int) -> Actor:
	return flow.get_wizard(index) as Actor


## The seat of a wizard: its PlayerController's.
func _seat(wizard: Actor) -> int:
	var seat: PlayerController = PlayerController.of(wizard)
	return seat.seat if seat != null else -1


## The health of player `index`'s wizard.
func _health(index: int) -> float:
	return _wizard(index).health.health


## A hit of `amount` on player `index`'s wizard; true if it was taken.
func _hurt(index: int, amount: int) -> bool:
	return _wizard(index).health.take(amount)


func _down(slot: int) -> void:
	_wizard(slot).health.take(_wizard(slot).health.max_health)


## True if `point` is one of arena_01's four player spawns.
func _is_player_spawn(point: Vector2) -> bool:
	for slot in InputManagerScript.MAX_PLAYERS:
		if point == Vector2(224.0 + 64.0 * slot, 320.0):
			return true
	return false


func _wizard_count() -> int:
	var count: int = 0
	for index in InputManagerScript.MAX_PLAYERS:
		if _wizard(index) != null:
			count += 1
	return count


## Every order of the four slots 0-3 (24 of them).
func _orders() -> Array[Array]:
	var out: Array[Array] = []
	_extend([], out)
	return out


func _extend(prefix: Array, out: Array[Array]) -> void:
	if prefix.size() == InputManagerScript.MAX_PLAYERS:
		out.append(prefix)
		return
	for slot in InputManagerScript.MAX_PLAYERS:
		if not prefix.has(slot):
			var next: Array = prefix.duplicate()
			next.append(slot)
			_extend(next, out)


## `first` joins and asks for a run (the keyboard stays out); its first tick's view puts the party
## camera on the new room's.
func _start_with(first: int) -> void:
	input.add_virtual_device(first)
	events.emit_signal("play_requested", first)
	_fit_and_snap()


## A run with `first` in, the others of `order` joined one after another mid-run; `each` is called
## after each joiner with the joiner's slot and how many are in.
func _join_in_order(order: Array, each: Callable) -> void:
	_stop()
	_start_with(order[0] as int)
	for position in range(1, order.size()):
		input.add_virtual_device(order[position] as int)
		each.call(order[position] as int, position + 1)


## A run of all four, which then leave in `order`; `each` is called after each leaver with the slots
## gone so far.
func _leave_in_order(order: Array, each: Callable) -> void:
	_stop()
	_start_with(0)
	for slot in range(1, InputManagerScript.MAX_PLAYERS):
		input.add_virtual_device(slot)
	check_equal(_wizard_count(), 4, "four wizards before leaving")
	left_events.clear()
	var gone: Array = []
	for slot: int in order:
		input.leave(slot)
		gone.append(slot)
		each.call(gone.duplicate())


## True if the wizard is inside what the camera really shows: its position and zoom with the camera
## limits applied (`visible_rect`).
func _in_view(wizard: Node2D) -> bool:
	return party.visible_rect().grow(0.01).has_point(wizard.global_position)


## The party found where it stands now (every seat's: the test's players are virtual devices, so
## none is "this machine's"), then the camera put on its view at once. Feel does the same every
## drawn frame; the tests draw none, so the world's camera is handed over here.
func _fit_and_snap() -> void:
	party.follow(root.get_camera_2d())
	party.look(actors, 0)
	party.snap()


## One drawn frame of `delta` seconds: the party found again, the camera eased.
func _frame(delta: float) -> void:
	party.follow(root.get_camera_2d())
	party.look(actors, 0)
	party.step(delta)


## The party camera, its room's bounds taken off it, to test the zoom alone; null (a failure) if
## there is none.
func _open_camera() -> Camera2D:
	var camera: Camera2D = party.camera
	check(camera != null, "the camera was found after room_entered")
	if camera != null:
		camera.limit_left = -10000000
		camera.limit_top = -10000000
		camera.limit_right = 10000000
		camera.limit_bottom = 10000000
	return camera


func _everyone_in_view() -> bool:
	if party.camera == null:
		return false
	for index in InputManagerScript.MAX_PLAYERS:
		var wizard: Actor = _wizard(index)
		if wizard != null and not _in_view(wizard):
			return false
	return true


func test_nobody_is_joined_at_the_start() -> void:
	check_equal(coop.joined_count(), 0, "nobody is joined at the start")


# --- Join and leave orders -------------------------------------------------------------------

func test_every_join_order_announces_each_player_once_in_order() -> void:
	for order: Array in _orders():
		_join_in_order(order, func(_slot: int, count: int) -> void:
			check_equal(joined_events, order.slice(0, count), "join order %s: player_joined came in order" % [order])
			check_equal(coop.joined_count(), count, "join order %s: %d players joined" % [order, count]))


func test_whoever_comes_first_starts_the_run_announced_once() -> void:
	for first in InputManagerScript.MAX_PLAYERS:
		_stop()
		_start_with(first)
		check_equal(flow.state, FlowScript.State.RUNNING, "first %d: the run started" % first)
		check_equal(joined_events, [first], "first %d: the starter was announced once" % first)


func test_every_join_order_gives_each_joiner_a_wizard_on_a_player_spawn_mid_run() -> void:
	for order: Array in _orders():
		_join_in_order(order, func(slot: int, count: int) -> void:
			check(_wizard(slot) != null, "join order %s: slot %d got a wizard mid-run" % [order, slot])
			# A joiner takes the free spawn farthest from enemies and wizards (DECISIONS.md), not
			# necessarily the one numbered like its slot.
			check(_wizard(slot) != null and _is_player_spawn(_wizard(slot).position), "join order %s: slot %d stands on a player spawn" % [order, slot])
			check_equal(_wizard_count(), count, "join order %s: %d wizards" % [order, count]))


func test_every_join_order_goes_on_running_while_someone_joins() -> void:
	for order: Array in _orders():
		_join_in_order(order, func(slot: int, _count: int) -> void:
			check(flow.state == FlowScript.State.RUNNING and not flow.is_restarting(), "join order %s: the run went on while slot %d joined" % [order, slot]))


func test_every_join_order_keeps_everyone_in_the_picture() -> void:
	for order: Array in _orders():
		_join_in_order(order, func(slot: int, _count: int) -> void:
			_fit_and_snap()
			check(_everyone_in_view(), "join order %s: everyone is in view after slot %d joined" % [order, slot]))


func test_every_join_order_gives_each_wizard_its_own_seat_and_colour() -> void:
	for order: Array in _orders():
		_join_in_order(order, func(_slot: int, count: int) -> void:
			for slot: int in order.slice(0, count):
				check(_wizard(slot) != null and _seat(_wizard(slot)) == slot and _wizard(slot).ramp == slot, "join order %s: wizard %d has its own seat and colour" % [order, slot]))


func test_every_leave_order_announces_each_leaver_in_order() -> void:
	for order: Array in _orders():
		_leave_in_order(order, func(gone: Array) -> void:
			check_equal(left_events, gone, "leave order %s: player_left came in order" % [order])
			check_equal(coop.joined_count(), 4 - gone.size(), "leave order %s: %d players remain" % [order, 4 - gone.size()]))


func test_every_leave_order_takes_only_the_leavers_wizard() -> void:
	for order: Array in _orders():
		_leave_in_order(order, func(gone: Array) -> void:
			for other in InputManagerScript.MAX_PLAYERS:
				check((_wizard(other) == null) == gone.has(other), "leave order %s: after %s left, slot %d %s its wizard" % [order, gone, other, "lost" if gone.has(other) else "kept"])
			check_equal(_wizard_count(), 4 - gone.size(), "leave order %s: %d wizards remain" % [order, 4 - gone.size()]))


## The run goes on, and waits quietly once everyone is gone (nobody is down, so nothing restarts).
func test_every_leave_order_goes_on_running_quietly() -> void:
	for order: Array in _orders():
		_leave_in_order(order, func(gone: Array) -> void:
			check(flow.state == FlowScript.State.RUNNING and not flow.is_restarting(), "leave order %s: the run goes on after %s left" % [order, gone]))


func test_every_leave_order_keeps_the_rest_in_the_picture() -> void:
	for order: Array in _orders():
		_leave_in_order(order, func(gone: Array) -> void:
			_frame(0.1)
			check(_everyone_in_view() or _wizard_count() == 0, "leave order %s: the rest are in view after %s left" % [order, gone]))


# --- Joining in the menu ---------------------------------------------------------------------

const MENU_ORDERS: Array[Array] = [[0, 1, 2, 3], [3, 2, 1, 0], [2, 0, 3, 1]]


## All four join in the menu, before Play, in `order`.
func _join_in_the_menu(order: Array) -> void:
	_stop()
	for slot: int in order:
		input.add_virtual_device(slot)


func test_players_joined_in_the_menu_are_announced_in_order() -> void:
	for order: Array in MENU_ORDERS:
		_join_in_the_menu(order)
		check_equal(joined_events, order, "menu join order %s was announced in order" % [order])


func test_joining_in_the_menu_starts_nothing() -> void:
	_join_in_the_menu(MENU_ORDERS[0])
	check(flow.state == FlowScript.State.IDLE and _wizard_count() == 0, "joining in the menu starts nothing")


func test_play_after_menu_joins_plays_all_four_without_announcing_them_again() -> void:
	for order: Array in MENU_ORDERS:
		_join_in_the_menu(order)
		events.emit_signal("play_requested", order[0])
		check_equal(_wizard_count(), 4, "menu join order %s: four wizards after Play" % [order])
		check_equal(joined_events, order, "Play does not announce the players again")


func test_four_joined_in_the_menu_are_in_view_at_the_start() -> void:
	for order: Array in MENU_ORDERS:
		_join_in_the_menu(order)
		events.emit_signal("play_requested", order[0])
		_fit_and_snap()
		check(_everyone_in_view(), "menu join order %s: everyone in view at the start" % [order])


# --- Device events ---------------------------------------------------------------------------

func test_a_second_device_for_a_taken_slot_joins_nobody() -> void:
	_start_with(0)
	joined_events.clear()
	events.emit_signal("device_joined", 0, 77)
	check(joined_events.is_empty(), "a second device_joined for a taken slot sends no player_joined")
	check_equal(coop.joined_count(), 1, "the count did not move")


func test_a_device_for_a_slot_outside_0_to_3_is_ignored() -> void:
	_start_with(0)
	joined_events.clear()
	events.emit_signal("device_joined", 4, 78)
	events.emit_signal("device_joined", -1, 79)
	check(joined_events.is_empty(), "a device_joined for a slot outside 0-3 is ignored")
	check_equal(coop.joined_count(), 1, "the count did not move")


func test_a_device_leaving_a_slot_nobody_holds_sends_no_player_left() -> void:
	_start_with(0)
	events.emit_signal("device_left", 2, 80)
	check(left_events.is_empty(), "device_left for a slot nobody holds sends no player_left")
	check_equal(coop.joined_count(), 1, "the count did not move")


## Coop hears the simulation's seats (the frames service's `seat_joined` and `seat_left`), never a
## device (netcode spike S1): while a replay plays, a pad joining here seats nobody and adds no
## wizard; once the replay ends its seat is seated. The frames service, playing.
func _playing_a_replay() -> Node:
	var frames: Node = root.get_node("Frames")
	var replay := Replay.new()
	replay.build = Replay.build_of()
	replay.content = Replay.content_of(root.get_node("Registry"))
	replay.seats = 0b0001
	var frame_list: Array[InputFrame] = []
	for seat in 4:
		var frame := InputFrame.new()
		frame.seat = seat
		frame_list.append(frame)
	replay.add_tick(frame_list, 0b0001)
	check(bool(frames.call("play", replay)), "the replay plays")
	check_equal(joined_events, [0], "the replay's seat joins")
	return frames


func test_a_device_joining_during_a_replay_joins_nobody() -> void:
	_playing_a_replay()
	var wizards: int = _wizard_count()
	input.add_virtual_device(2)
	check_equal(joined_events, [0], "a device joining while it plays joins nobody")
	check(not coop.is_joined(2) and _wizard_count() == wizards, "no seat, no wizard")


func test_a_device_that_joined_during_a_replay_is_seated_once_it_ends() -> void:
	var frames: Node = _playing_a_replay()
	input.add_virtual_device(2)
	frames.call("stop_playing")
	check_equal(joined_events, [0, 2], "once it ends the device's seat joins")
	check(coop.is_joined(2), "seated")


func test_a_player_who_rejoins_gets_a_fresh_wizard_at_full_health() -> void:
	_start_with(0)
	input.add_virtual_device(1)
	input.leave(1)
	check(_wizard(1) == null and _wizard_count() == 1, "slot 2 left: only P1 plays")
	input.add_virtual_device(1)
	check(_wizard(1) != null and _wizard_count() == 2, "slot 2 rejoined with a fresh wizard")
	check(_wizard(1) != null and _health(1) == _wizard(1).health.max_health, "the rejoined wizard is at full health")


func test_leaving_and_rejoining_announces_each_change() -> void:
	_start_with(0)
	input.add_virtual_device(1)
	input.leave(1)
	input.add_virtual_device(1)
	check(joined_events == [0, 1, 1] and left_events == [1], "events: joined 0, 1, 1 and left 1, got %s and %s" % [joined_events, left_events])


## Coop keeps its wizards by actor id, not by the tree's order (online-ready N3c: a game rebuilt
## from a snapshot need not add them in the same order), so revives go the same way.
func test_the_wizards_go_by_actor_id_whatever_the_trees_order() -> void:
	_start_with(0)
	input.add_virtual_device(1)
	input.add_virtual_device(2)
	var first: Actor = _wizard(0)
	first.get_parent().move_child(first, -1)
	coop.refresh_wizards()
	var ids: Array[int] = []
	for body: Node2D in coop._wizards:
		ids.append((body as Actor).id)
	var sorted: Array[int] = ids.duplicate()
	sorted.sort()
	check(ids.size() == 3 and ids == sorted, "the wizards go by actor id whatever the tree's order: %s" % [ids])


# --- Leaving and joining while down ----------------------------------------------------------

## Two players, the first down: one wizard still stands, so nothing restarts.
func _one_down_of_two() -> void:
	_start_with(0)
	input.add_virtual_device(1)
	_down(0)
	check(not flow.is_restarting(), "one wizard still stands: no restart")


## When the only wizard standing leaves and the rest are down, the room restarts as usual.
func test_the_last_standing_wizard_leaving_restarts_the_room() -> void:
	_one_down_of_two()
	input.leave(1)
	check(flow.is_restarting(), "the last standing wizard left and the rest are down: the room restarts")


## A player who joins while everyone is down gives the party a standing wizard.
func test_a_player_joining_while_all_are_down_cancels_the_restart() -> void:
	_one_down_of_two()
	input.leave(1)
	input.add_virtual_device(2)
	check(not flow.is_restarting(), "a player joining while all were down cancels the restart")


## A mid-run joiner is protected for a moment and does not land on an enemy. The joiner (an enemy
## stood on slot 1's spawn first) and that spawn.
func _joiner_beside_an_enemy() -> Array:
	_start_with(0)
	var spawns: PackedVector2Array = flow._room.places().player_spawns
	var enemy: Node2D = flow._enemies[0] as Node2D
	enemy.position = spawns[1]
	input.add_virtual_device(1)
	var joiner: Actor = _wizard(1)
	check(joiner != null, "the joiner has a wizard")
	return [joiner, spawns[1]]


func test_a_mid_run_joiner_cannot_be_hurt_at_first() -> void:
	var joiner: Actor = _joiner_beside_an_enemy()[0]
	if joiner == null:
		return
	check(joiner.health.is_protected(), "the joiner is protected")
	check(not joiner.health.take(SHOT_DAMAGE) and joiner.health.health == joiner.health.max_health, "a hit on the new joiner does nothing")


func test_a_mid_run_joiner_lands_clear_of_enemies_and_wizards() -> void:
	var made: Array = _joiner_beside_an_enemy()
	var joiner: Actor = made[0]
	if joiner == null:
		return
	check(joiner.position.distance_to(made[1] as Vector2) > 1.0, "the joiner is not put under the enemy")
	check(joiner.position.distance_to(_wizard(0).position) > 1.0, "the joiner does not stand on another wizard")


# --- The party camera ------------------------------------------------------------------------

func test_one_player_is_framed_without_zoom() -> void:
	_start_with(0)
	var camera: Camera2D = _open_camera()
	if camera == null:
		return
	# The limits changed, so the target moved: snap again to see the zoom alone.
	_fit_and_snap()
	check(is_equal_approx(camera.zoom.x, PartyCameraScript.MAX_ZOOM), "one player: no zoom out, got %f" % camera.zoom.x)
	check(camera.position.is_equal_approx(_wizard(0).global_position), "one player: the camera is on the player: %s vs %s" % [camera.position, _wizard(0).global_position])


## Four wizards spread to the corners of a wide area, the camera on them; the corners.
func _four_spread() -> Array[Vector2]:
	_start_with(0)
	_open_camera()
	for slot in range(1, 4):
		input.add_virtual_device(slot)
	var corners: Array[Vector2] = [Vector2(40.0, 40.0), Vector2(600.0, 40.0), Vector2(40.0, 340.0), Vector2(600.0, 340.0)]
	for slot in 4:
		_wizard(slot).global_position = corners[slot]
	coop.refresh_wizards()
	_fit_and_snap()
	return corners


func test_four_spread_players_are_zoomed_out_to_fit() -> void:
	_four_spread()
	var camera: Camera2D = party.camera
	check(camera.zoom.x < PartyCameraScript.MAX_ZOOM, "four spread players: the camera zoomed out, got %f" % camera.zoom.x)
	check(camera.zoom.x >= PartyCameraScript.MIN_ZOOM, "the zoom stays above the minimum")
	check(_everyone_in_view(), "four spread players: everyone is in view")


func test_spread_players_keep_the_margin_from_the_views_edge() -> void:
	var corners: Array[Vector2] = _four_spread()
	var camera: Camera2D = party.camera
	for slot in 4:
		var offset: Vector2 = (corners[slot] - camera.position) * camera.zoom.x
		check(absf(offset.x) <= VIEW.x * 0.5 - PartyCameraScript.CAMERA_MARGIN * camera.zoom.x + 0.01 or absf(offset.y) <= VIEW.y * 0.5 - PartyCameraScript.CAMERA_MARGIN * camera.zoom.x + 0.01, "slot %d keeps the margin from the view's edge on one axis" % slot)


func test_players_too_far_apart_stop_the_zoom_at_the_minimum() -> void:
	_four_spread()
	_wizard(0).global_position = Vector2(-1000.0, 0.0)
	_wizard(1).global_position = Vector2(2000.0, 0.0)
	_fit_and_snap()
	check(is_equal_approx(party.camera.zoom.x, PartyCameraScript.MIN_ZOOM), "far apart: the zoom stops at the minimum")


func test_players_back_together_zoom_back_in() -> void:
	_four_spread()
	for slot in 4:
		_wizard(slot).global_position = Vector2(300.0 + 4.0 * slot, 200.0)
	_fit_and_snap()
	check(is_equal_approx(party.camera.zoom.x, PartyCameraScript.MAX_ZOOM), "together again: the zoom is back to 1, got %f" % party.camera.zoom.x)


func test_a_downed_wizard_stays_in_the_picture() -> void:
	_four_spread()
	_down(3)
	_wizard(3).global_position = Vector2(600.0, 340.0)
	_wizard(0).global_position = Vector2(40.0, 40.0)
	_fit_and_snap()
	check(_in_view(_wizard(3)) and _in_view(_wizard(0)), "a downed wizard stays in the picture")


## Two wizards, the camera snapped on them far apart, then the second walked near the first.
func _target_moved() -> Camera2D:
	_start_with(0)
	input.add_virtual_device(1)
	var camera: Camera2D = _open_camera()
	if camera == null:
		return null
	_wizard(0).global_position = Vector2(100.0, 100.0)
	_wizard(1).global_position = Vector2(500.0, 300.0)
	_fit_and_snap()
	_wizard(1).global_position = Vector2(200.0, 100.0)
	return camera


func test_one_frame_moves_the_camera_part_of_the_way() -> void:
	var camera: Camera2D = _target_moved()
	if camera == null:
		return
	var before: Vector2 = camera.position
	_frame(0.016)
	var moved: float = camera.position.distance_to(before)
	var total: float = before.distance_to(party.target_position)
	check(moved > 0.0 and moved < total, "one frame moves the camera part of the way (%f of %f)" % [moved, total])


func test_the_camera_arrives_at_its_target() -> void:
	var camera: Camera2D = _target_moved()
	if camera == null:
		return
	for i in 200:
		_frame(0.1)
	check(camera.position.distance_to(party.target_position) < 0.01, "the camera arrives at its target")
	check(absf(camera.zoom.x - party.target_zoom) < 0.001, "the zoom arrives at its target")


func test_a_zero_or_negative_step_does_not_move_the_camera() -> void:
	var camera: Camera2D = _target_moved()
	if camera == null:
		return
	var at: Vector2 = camera.position
	_frame(0.0)
	_frame(-1.0)
	check_equal(camera.position, at, "a zero or negative step does not move the camera")


## A far-off joiner: while the camera eases, nobody is outside the view.
func test_nobody_leaves_the_view_while_the_camera_eases_out() -> void:
	_start_with(0)
	input.add_virtual_device(1)
	if _open_camera() == null:
		return
	_wizard(0).global_position = Vector2(60.0, 200.0)
	_wizard(1).global_position = Vector2(70.0, 200.0)
	_fit_and_snap()
	_wizard(1).global_position = Vector2(560.0, 200.0)
	var out: int = 0
	for i in 120:
		_frame(0.016)
		if not _everyone_in_view():
			out += 1
	check_equal(out, 0, "frames of the ease out with someone out of view")


## The room's limits and the zoom agree: four wizards in the corners of arena_01, the camera's room.
func _four_in_the_rooms_corners() -> Rect2:
	_start_with(0)
	for slot in range(1, 4):
		input.add_virtual_device(slot)
	var camera: Camera2D = party.camera
	check(camera != null, "the camera exists for the limits test")
	if camera == null:
		return Rect2()
	var room := Rect2(Vector2(camera.limit_left, camera.limit_top), Vector2(camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top))
	var corners: Array[Vector2] = [Vector2(20.0, 20.0), Vector2(room.end.x - 20.0, 20.0), Vector2(20.0, room.end.y - 20.0), room.end - Vector2(20.0, 20.0)]
	for slot in 4:
		_wizard(slot).global_position = corners[slot]
	coop.refresh_wizards()
	return room


func test_wizards_in_the_rooms_corners_are_in_a_view_inside_the_room() -> void:
	var room: Rect2 = _four_in_the_rooms_corners()
	if not room.has_area():
		return
	_fit_and_snap()
	check(room.grow(0.01).encloses(party.visible_rect()), "snapped: the view stays inside the room, got %s" % party.visible_rect())
	for slot in 4:
		check(_in_view(_wizard(slot)), "snapped: the wizard in corner %d is in the view" % slot)


func test_easing_out_to_the_rooms_corners_never_shows_past_the_room_or_loses_anyone() -> void:
	var room: Rect2 = _four_in_the_rooms_corners()
	if not room.has_area():
		return
	var camera: Camera2D = party.camera
	# Start from the middle and ease out to the corners: nobody is ever outside.
	camera.position = room.get_center()
	camera.zoom = Vector2.ONE
	for i in 60:
		_frame(0.016)
		check(room.grow(0.01).encloses(party.visible_rect()), "easing %d: the view stays inside the room" % i)
		check(_everyone_in_view(), "easing %d: everyone is in view" % i)


## Machines playing together each frame their own seats (owner, 2026-11-13). Two wizards far apart,
## the camera's room bounds taken off.
func _two_far_apart() -> Camera2D:
	_start_with(0)
	input.add_virtual_device(1)
	var camera: Camera2D = _open_camera()
	if camera != null:
		_wizard(0).global_position = Vector2(100.0, 100.0)
		_wizard(1).global_position = Vector2(900.0, 500.0)
	return camera


func test_with_one_seat_played_here_the_camera_holds_its_wizard_alone() -> void:
	var camera: Camera2D = _two_far_apart()
	if camera == null:
		return
	party.look(actors, 0b0001)
	party.snap()
	check(camera.position.is_equal_approx(_wizard(0).global_position) and is_equal_approx(camera.zoom.x, PartyCameraScript.MAX_ZOOM), "seat 0 alone plays here: the camera is on its wizard, not zoomed out (%s, %f)" % [camera.position, camera.zoom.x])
	check(not _in_view(_wizard(1)), "the wizard played on another machine may be out of the picture")


func test_with_both_seats_played_here_the_camera_holds_both() -> void:
	if _two_far_apart() == null:
		return
	party.look(actors, 0b0011)
	party.snap()
	check(_everyone_in_view(), "both play here: both are in the picture")


## The wiring, through Feel's own step: a real device's seat is this machine's (`Frames.seats_here`),
## a virtual device's is not (another machine's player, as the host seats a guest). A run started by
## a virtual device in seat 1, the keyboard joined in seat 0 mid-run, the two far apart and Feel
## stepped; false (a failure) if any of it is missing.
func _keyboard_and_a_guest() -> bool:
	_start_with(1)
	var seat: int = input.join_as(InputManagerScript.KEYBOARD, 0)
	check(seat == 0 and _wizard(0) != null, "the keyboard joined seat 0 mid-run (%d)" % seat)
	# Feel finds the world's camera itself.
	feel.call("step", 0.016)
	if party.camera == null or _wizard(0) == null:
		check(false, "the camera and the keyboard's wizard exist for the wiring test")
		return false
	_open_camera()
	_wizard(0).global_position = Vector2(100.0, 100.0)
	_wizard(1).global_position = Vector2(900.0, 500.0)
	feel.call("step", 0.016)
	return true


func test_feels_camera_heads_for_the_wizard_played_here_alone() -> void:
	if not _keyboard_and_a_guest():
		return
	check(party.target_position.is_equal_approx(_wizard(0).global_position) and is_equal_approx(party.target_zoom, PartyCameraScript.MAX_ZOOM), "Feel's step heads the camera for the keyboard's wizard alone (%s, %f)" % [party.target_position, party.target_zoom])


## The wizard played elsewhere is out of the picture: Feel marks it at the picture's edge.
func test_feel_marks_the_teammate_out_of_the_picture_at_its_edge() -> void:
	if not _keyboard_and_a_guest():
		return
	feel.call("step", 0.016)
	var markers: Node = feel.call("teammate_markers") as Node
	check(markers != null and int(markers.get("count")) == 1 and int(markers.call("seat_of", 0)) == 1, "Feel marks the teammate out of the picture, and nobody else")
	if markers != null and int(markers.get("count")) == 1:
		check(party.visible_rect().has_point(markers.call("position_of", 0) as Vector2), "the marker is in the picture")


func test_with_no_seat_played_here_feels_camera_holds_whoever_is_left() -> void:
	if not _keyboard_and_a_guest():
		return
	input.leave(0)
	feel.call("step", 0.016)
	check(party.target_position.is_equal_approx(_wizard(1).global_position), "with no seat played here, the camera holds whoever is left (%s)" % party.target_position)


## The room restart builds a new world and camera; the party camera follows the new one.
func test_the_party_camera_follows_the_new_worlds_camera_after_a_restart() -> void:
	_start_with(0)
	var old_camera: Camera2D = party.camera
	_down(0)
	flow.step(FlowScript.RESTART_DELAY)
	check_equal(flow.state, FlowScript.State.RUNNING, "the room restarted")
	_fit_and_snap()
	check(party.camera != null and party.camera != old_camera and party.camera.is_inside_tree(), "the party camera picked up the new world's camera")
	check(_everyone_in_view(), "the player is in view after the restart")


func test_stepping_the_camera_with_its_world_gone_is_safe() -> void:
	_start_with(0)
	_down(0)
	flow.step(FlowScript.RESTART_DELAY)
	# A step with the old camera gone must not fail.
	_frame(0.1)
	_stop()
	_frame(0.1)
	check_equal(_wizard_count(), 0, "stepping with no wizards is safe")


# --- Revive ----------------------------------------------------------------------------------

## Put a run with `count` players (slots 0 to count-1) up, far apart.
func _run_with(count: int) -> void:
	_start_with(0)
	for slot in range(1, count):
		input.add_virtual_device(slot)
	for slot in count:
		# A joiner is protected for a while; let that run out so it can be hurt.
		_wizard(slot).step(Downed.JOIN_PROTECTION + 0.1)
		_wizard(slot).position = Vector2(100.0 + 150.0 * slot, 100.0)
	coop.refresh_wizards()


## Advance the revive by `seconds`, in steps of 0.1.
func _hold(seconds: float) -> void:
	for i in roundi(seconds / 0.1):
		coop.step_revive(0.1)


## Places wizard `slot` `distance` px to the right of wizard `of`.
func _beside(slot: int, of: int, distance: float) -> void:
	_wizard(slot).position = _wizard(of).position + Vector2(distance, 0.0)


## Two players, wizard 0 down; the revive_progress events heard, each [player, progress].
func _one_down() -> Array:
	_run_with(2)
	var progress: Array = []
	_listen("revive_progress", func(p: int, f: float) -> void: progress.append([p, f]))
	_down(0)
	check(_wizard(0).is_down(), "wizard 0 is down")
	return progress


## `_one_down`, then wizard 1 beside it for the full hold; the player_revived events heard, each
## [player, reviver].
func _revived() -> Array:
	_one_down()
	var revived: Array = []
	_listen("player_revived", func(p: int, r: int) -> void: revived.append([p, r]))
	_beside(1, 0, 20.0)
	_hold(CoopScript.REVIVE_HOLD_TIME + 0.2)
	check(not _wizard(0).is_down(), "wizard 0 is back up")
	return revived


func test_nobody_near_fills_no_revive() -> void:
	var progress: Array = _one_down()
	_hold(1.0)
	check(coop.revive_progress_of(0) == 0.0 and progress.is_empty(), "nobody near, no progress")


func test_just_outside_the_range_fills_no_revive() -> void:
	_one_down()
	_beside(1, 0, CoopScript.REVIVE_RANGE + 1.0)
	_hold(1.0)
	check_equal(coop.revive_progress_of(0), 0.0, "just outside the range does not count")


func test_half_the_hold_beside_the_body_is_half_the_revive() -> void:
	_one_down()
	_beside(1, 0, CoopScript.REVIVE_RANGE - 4.0)
	_hold(CoopScript.REVIVE_HOLD_TIME * 0.5)
	check(absf(coop.revive_progress_of(0) - 0.5) < 0.01, "half the time, half the progress, got %f" % coop.revive_progress_of(0))
	check(absf(Downed.of(_wizard(0)).revive_progress() - 0.5) < 0.01, "the downed wizard knows its progress (for the ring)")
	check(_wizard(0).is_down(), "still down at half the time")


func test_revive_progress_names_the_downed_player() -> void:
	var progress: Array = _one_down()
	_beside(1, 0, CoopScript.REVIVE_RANGE - 4.0)
	_hold(CoopScript.REVIVE_HOLD_TIME * 0.5)
	check(not progress.is_empty() and progress[0][0] == 0, "revive_progress names the downed player")


## Stepping away drains at twice the speed: 0.2 s away undoes 0.2 of the hold (the same 0.2 s
## beside the body would have filled 0.1).
func test_stepping_away_drains_the_revive_twice_as_fast_as_it_fills() -> void:
	_one_down()
	_beside(1, 0, CoopScript.REVIVE_RANGE - 4.0)
	_hold(CoopScript.REVIVE_HOLD_TIME * 0.5)
	_beside(1, 0, 300.0)
	_hold(0.2)
	check(absf(coop.revive_progress_of(0) - 0.3) < 0.01, "progress drains twice as fast as it fills, got %f" % coop.revive_progress_of(0))


func test_a_revive_left_alone_drains_to_nothing() -> void:
	_one_down()
	_beside(1, 0, CoopScript.REVIVE_RANGE - 4.0)
	_hold(CoopScript.REVIVE_HOLD_TIME * 0.5)
	_beside(1, 0, 300.0)
	_hold(CoopScript.REVIVE_HOLD_TIME)
	check(coop.revive_progress_of(0) == 0.0 and Downed.of(_wizard(0)).revive_progress() == 0.0, "the progress drains to nothing")


func test_the_full_hold_beside_the_body_revives() -> void:
	_one_down()
	_beside(1, 0, 20.0)
	_hold(CoopScript.REVIVE_HOLD_TIME - 0.2)
	check(_wizard(0).is_down(), "not yet shortly before the end")
	_hold(0.4)
	check(not _wizard(0).is_down(), "back up after the hold time")


func test_player_revived_names_the_player_and_the_reviver() -> void:
	check_equal(_revived(), [[0, 1]], "player_revived carries the player and the reviver")


func test_the_revive_cue_plays_on_the_revived_actor() -> void:
	var cues: Array = []
	_listen("cue_shown", func(p: int, id: StringName, at: Vector2, _d: Vector2, _s: float, _t: Color, _l: int) -> void:
		if id == Downed.REVIVE_CUE:
			cues.append([p, at]))
	_revived()
	check(cues.size() == 1 and cues[0][0] == _wizard(0).id and cues[0][1] == _wizard(0).global_position, "the cue revive plays on the revived actor (S6), got %s" % [cues])


func test_a_revived_wizard_stands_at_the_revive_health() -> void:
	_revived()
	check_equal(_health(0), Downed.REVIVE_HEALTH, "the revive health")


func test_the_revive_ring_is_cleared_after_the_revive() -> void:
	var progress: Array = _one_down()
	_beside(1, 0, 20.0)
	_hold(CoopScript.REVIVE_HOLD_TIME + 0.2)
	check(coop.revive_progress_of(0) == 0.0 and Downed.of(_wizard(0)).revive_progress() == 0.0, "the ring is cleared")
	check(not progress.is_empty() and progress.back()[1] == 0.0, "the last progress sent is 0")


func test_a_revived_wizard_is_protected_for_revive_protection() -> void:
	_revived()
	check(_wizard(0).health.is_protected(), "protected after the revive")
	check(not _hurt(0, SHOT_DAMAGE) and _health(0) == Downed.REVIVE_HEALTH, "a hit right after does nothing")
	for i in roundi(CoopScript.REVIVE_PROTECTION / 0.1) + 2:
		_wizard(0).step(0.1)
	check(not _wizard(0).health.is_protected(), "the protection ends after REVIVE_PROTECTION")
	check(_hurt(0, SHOT_DAMAGE), "hurt normally afterwards")


func test_the_reviver_is_unharmed() -> void:
	_revived()
	check(_health(1) == _wizard(1).health.max_health and not _wizard(1).is_down(), "the reviver is unharmed")


func test_with_four_players_each_slot_is_revived_by_the_next() -> void:
	for fallen in InputManagerScript.MAX_PLAYERS:
		_stop()
		_run_with(4)
		_down(fallen)
		_beside((fallen + 1) % 4, fallen, 24.0)
		_hold(CoopScript.REVIVE_HOLD_TIME + 0.2)
		check(not _wizard(fallen).is_down(), "slot %d is back up" % fallen)
		check(_wizard(fallen).health.is_protected(), "slot %d is protected" % fallen)


## Three of four fall at once. Slot 2 stands beside slot 0 only; downed slots 1 and 3 stand together.
func _three_down() -> void:
	_run_with(4)
	_down(0)
	_down(1)
	_down(3)
	_beside(2, 0, 20.0)
	_beside(3, 1, 20.0)
	_hold(CoopScript.REVIVE_HOLD_TIME + 0.2)


func test_a_standing_wizard_revives_the_downed_one_beside_it() -> void:
	_three_down()
	check(not _wizard(0).is_down(), "slot 0 revived by slot 2")


func test_downed_wizards_do_not_revive_each_other() -> void:
	_three_down()
	check(_wizard(1).is_down() and _wizard(3).is_down(), "downed wizards do not revive each other")


## Slot 0 walks over to the two still down: both are revived at once, each by the nearest standing
## wizard.
func test_one_wizard_revives_two_downed_beside_it_at_once() -> void:
	_three_down()
	_beside(0, 1, 10.0)
	_wizard(2).position = Vector2(900.0, 900.0)
	var revived: Array = []
	_listen("player_revived", func(p: int, r: int) -> void: revived.append([p, r]))
	_hold(CoopScript.REVIVE_HOLD_TIME + 0.2)
	check(not _wizard(1).is_down() and not _wizard(3).is_down(), "slots 1 and 3 are back up together")
	check(revived.has([1, 0]) and revived.has([3, 0]), "slot 0 is the reviver of both, got %s" % [revived])


## Three players, wizard 0 down and wizard 1 reviving it for a second.
func _revive_under_way() -> void:
	_run_with(3)
	_down(0)
	_beside(1, 0, 20.0)
	_hold(1.0)
	check(coop.revive_progress_of(0) > 0.0, "progress under way")


func test_a_reviver_who_leaves_stops_the_revive() -> void:
	_revive_under_way()
	input.leave(1)
	_hold(CoopScript.REVIVE_HOLD_TIME * 2.0)
	check(_wizard(0).is_down() and coop.revive_progress_of(0) == 0.0, "the reviver left, the progress drained away")


func test_a_downed_leavers_revive_is_cleared() -> void:
	_revive_under_way()
	input.leave(0)
	check_equal(coop.revive_progress_of(0), 0.0, "a leaver's progress is cleared")


# --- Friendly fire ---------------------------------------------------------------------------

## Friendly fire is always on (actors G3c): three wizards (all in before Play: a mid-run joiner is
## invulnerable for 2 s) with no enemy in the way, the test shots' hit profile under BOLT_TAG in
## Spells (Combat reads only those; set after the start, which resets Spells), and wizard 0's bolt
## fired at wizard 1, through the real projectile manager and Combat.
func _bolt_at_a_teammate() -> void:
	var hit := HitProfile.new()
	hit.damage = SHOT_DAMAGE
	var spell := CompiledSpell.new()
	spell.hit = hit
	input.add_virtual_device(1)
	input.add_virtual_device(2)
	_start_with(0)
	for enemy: Node in flow._enemies.duplicate():
		combat.call("unregister_actor", enemy)
	(root.get_node("Spells") as Node).get("_profiles")[BOLT_TAG] = spell
	_wizard(0).global_position = Vector2(100.0, 100.0)
	_wizard(1).global_position = Vector2(140.0, 100.0)
	_wizard(2).global_position = Vector2(100.0, 300.0)
	projectiles.clear()
	# The shot is cast by wizard 0's actor (actors G3b: the caster is the actor id the wizard opened).
	# It starts on the shooter, and spares them until it has left them, as Spells has every launch.
	projectiles.exclude(projectiles.spawn(_wizard(0).id, Vector2(100.0, 100.0), Vector2(400.0, 0.0), 1.0, 4.0, ProjectileManagerScript.LAYER_ENEMY, 0, BOLT_TAG), _wizard(0))
	projectiles.step(0.1)


func test_a_wizards_bolt_hurts_the_teammate_in_its_way() -> void:
	_bolt_at_a_teammate()
	check_equal(_health(1), _wizard(1).health.max_health - SHOT_DAMAGE, "the teammate is hurt")
	check_equal(projectiles.get_count(), 0, "the shot ended on the hit")


func test_a_wizard_is_not_hit_by_its_own_bolt_leaving_it() -> void:
	_bolt_at_a_teammate()
	check_equal(_health(0), _wizard(0).health.max_health, "the shooter is not hit by the shot leaving them")


func test_a_wizard_off_the_line_of_fire_is_untouched() -> void:
	_bolt_at_a_teammate()
	check_equal(_health(2), _wizard(2).health.max_health, "a wizard off the line of fire is untouched")


func test_an_enemy_shot_still_hurts_a_wizard() -> void:
	_bolt_at_a_teammate()
	projectiles.clear()
	projectiles.spawn(-1, Vector2(100.0, 296.0), Vector2(0.0, 100.0), 0.2, 4.0, ProjectileManagerScript.LAYER_PLAYER, 0, BOLT_TAG)
	projectiles.step(0.05)
	check_equal(_health(2), _wizard(2).health.max_health - SHOT_DAMAGE, "an enemy shot still hurts a wizard")


# --- What stops the game ---------------------------------------------------------------------
# The pause menu stops the game one reason a seat (`Coop.MENU_OF`): another seat's closing does not
# let it go, and the seat leaving with its menu open does (online, a machine gone back to the main
# menu or lost never sends its closing; everyone else stood stopped for good before).

func _command(command: StringName, args: Array) -> void:
	events.call("apply_command", command, args)


func test_a_seats_menu_stops_the_game() -> void:
	_command(&"pause_requested", [1, 1])
	check(CoopScript.menu_stops(Sim.found(coop)), "seat 1's menu stops the game")


func test_another_seats_closing_does_not_let_a_menus_stop_go() -> void:
	_command(&"pause_requested", [1, 1])
	_command(&"pause_requested", [2, 1])
	_command(&"pause_requested", [2, 0])
	check(CoopScript.menu_stops(Sim.found(coop)), "seat 2's closing does not let seat 1's stop go")


func test_a_seat_that_leaves_with_its_menu_open_lets_the_game_go() -> void:
	var game: Sim = Sim.found(coop)
	_command(&"pause_requested", [1, 1])
	events.emit_signal("seat_left", 1)
	check(not CoopScript.menu_stops(game) and not game.is_stopped(), "seat 1 leaving lets the game go")


func test_a_menu_of_a_seat_out_of_range_stops_nothing() -> void:
	_command(&"pause_requested", [5, 1])
	check(not Sim.found(coop).is_stopped(), "a seat out of range stops nothing")


## The owner, 2026-11-13: a seat whose gamepad is unplugged keeps playing (its wizard stays) and the
## game stops for everyone, one reason a seat (`Coop.PAD_OF`), until that seat has a gamepad again or
## leaves. Before, the input layer made the seat leave. A run of three seats; the pad_wait_changed
## events heard (the seats waited for, as bits).
func _three_seats() -> Array[int]:
	var waits: Array[int] = []
	_listen("pad_wait_changed", func(seats: int) -> void: waits.append(seats))
	_start_with(0)
	input.add_virtual_device(1)
	input.add_virtual_device(2)
	return waits


func test_an_unplugged_pad_stops_the_game_for_its_seat() -> void:
	var waits: Array[int] = _three_seats()
	var game: Sim = Sim.found(coop)
	_command(&"pad_wait_requested", [1, 1])
	check(game.stopped_for(CoopScript.PAD_OF[1]) and CoopScript.pad_waits(game) == 2, "seat 1's missing gamepad stops the game")
	check_equal(waits, [2] as Array[int], "the waiting seat is said")


func test_a_seat_with_an_unplugged_pad_keeps_its_wizard() -> void:
	_three_seats()
	_command(&"pad_wait_requested", [1, 1])
	check(coop.is_joined(1) and _wizard(1) != null, "the seat and its wizard stay")


func test_one_seats_pad_back_does_not_let_anothers_stop_go() -> void:
	var waits: Array[int] = _three_seats()
	var game: Sim = Sim.found(coop)
	_command(&"pad_wait_requested", [1, 1])
	_command(&"pad_wait_requested", [2, 1])
	_command(&"pad_wait_requested", [1, 0])
	check(game.is_stopped() and CoopScript.pad_waits(game) == 4, "seat 1's gamepad back does not let seat 2's stop go")
	check_equal(waits, [2, 6, 4] as Array[int], "each change is said")


## The waiting seat leaves (the pause menu's "Leave game"): nobody waits for it.
func test_the_waiting_seat_leaving_lets_the_game_go() -> void:
	var waits: Array[int] = _three_seats()
	_command(&"pad_wait_requested", [2, 1])
	input.leave(2)
	check(not Sim.found(coop).is_stopped() and waits[-1] == 0, "the waiting seat leaving lets the game go: %s" % [waits])


func test_a_pad_wait_of_a_seat_that_left_or_out_of_range_stops_nothing() -> void:
	_three_seats()
	input.leave(2)
	_command(&"pad_wait_requested", [2, 1])
	check(not Sim.found(coop).is_stopped(), "a seat that has left stops nothing")
	_command(&"pad_wait_requested", [7, 1])
	check(not Sim.found(coop).is_stopped(), "a seat out of range stops nothing")


func test_the_pause_menus_stop_stands_apart_from_a_pad_wait() -> void:
	_three_seats()
	var game: Sim = Sim.found(coop)
	_command(&"pad_wait_requested", [1, 1])
	_command(&"pause_requested", [0, 1])
	_command(&"pad_wait_requested", [1, 0])
	check(game.is_stopped() and CoopScript.pad_waits(game) == 0, "the gamepad back leaves the pause menu's stop")
	_command(&"pause_requested", [0, 0])
	check(not game.is_stopped(), "the menu closing lets the game go")
