extends SceneTree
## Tests for gameplay/coop, on the real autoloads: every join order of 1-4 players
## (the first is in when Play is pressed, the rest join mid-run), every leave
## order, no duplicate events, the camera keeps everyone in view (zooms out as the
## players spread, never past its limits, eases instead of jumping), and friendly
## fire (off by default, never hits the shooter, switches back off).
##
## godot --headless --path . --script res://tests/gameplay/coop/test_coop.gd

const CoopScript := preload("res://gameplay/coop/coop.gd")
const FlowScript := preload("res://gameplay/flow/flow.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const VIEW: Vector2 = Vector2(640.0, 360.0)
const BOLT_TAG: int = 1
const SHOT_DAMAGE: int = 10

var _failures: Array[String] = []
var _events: Node
var _coop: CoopScript
var _flow: FlowScript
var _input: InputManagerScript
var _combat: Node
var _projectiles: ProjectileManagerScript
var _joined_events: Array = []
var _left_events: Array = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_events = root.get_node_or_null("Events")
	_coop = root.get_node_or_null("Coop") as CoopScript
	_flow = root.get_node_or_null("Flow") as FlowScript
	_input = root.get_node_or_null("PlayerInput") as InputManagerScript
	_combat = root.get_node_or_null("Combat")
	_projectiles = root.get_node_or_null("Projectiles") as ProjectileManagerScript
	if _events == null or _coop == null or _flow == null or _input == null or _combat == null or _projectiles == null:
		printerr("TEST FAILED: the Events, PlayerInput, Projectiles, Combat, Flow and Coop autoloads must exist")
		quit(1)
		return
	_events.connect("player_joined", func(player: int) -> void: _joined_events.append(player))
	_events.connect("player_left", func(player: int) -> void: _left_events.append(player))
	_coop.view_size = VIEW
	_test_defaults()
	_test_every_join_order()
	_test_every_leave_order()
	_test_join_before_play()
	_test_duplicate_device_events()
	_test_leave_and_rejoin_same_slot()
	_test_last_standing_leaves_restarts_the_room()
	_test_camera_zooms_out_to_fit()
	_test_camera_eases()
	_test_camera_respects_room_limits()
	_test_nobody_leaves_the_view_while_easing()
	_test_joiner_is_protected()
	_test_camera_survives_a_restart()
	_test_revive_two_players()
	_test_revive_four_players()
	_test_revive_edges()
	_test_friendly_fire()
	_stop()
	if _failures.is_empty():
		print("TEST OK: gameplay/coop (join orders, leave orders, camera, friendly fire)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _stop() -> void:
	_flow.stop_run()
	for index in InputManagerScript.MAX_PLAYERS:
		_input.leave(index)
	_coop.set_friendly_fire(false)
	_joined_events.clear()
	_left_events.clear()


func _wizard(index: int) -> PlayerScript:
	return _flow.get_wizard(index) as PlayerScript


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


## Every ordered selection of 1 to 4 different slots out of 0-3 (64 of them).
func _sequences() -> Array[Array]:
	var out: Array[Array] = []
	_extend([], out)
	return out


func _extend(prefix: Array, out: Array[Array]) -> void:
	for slot in InputManagerScript.MAX_PLAYERS:
		if prefix.has(slot):
			continue
		var next: Array = prefix.duplicate()
		next.append(slot)
		out.append(next)
		_extend(next, out)


## Start a run with `first` already in; the keyboard stays out.
func _start_with(first: int) -> void:
	_input.add_virtual_device(first)
	_events.emit_signal("play_requested", first)


## True if the wizard is inside what the camera really shows: its position and
## zoom with the camera limits applied (`visible_rect`).
func _in_view(wizard: Node2D, _camera: Camera2D) -> bool:
	return _coop.visible_rect().grow(0.01).has_point(wizard.global_position)


## Take the room's limits off the camera, to test the zoom alone.
func _open_limits(camera: Camera2D) -> void:
	camera.limit_left = -10000000
	camera.limit_top = -10000000
	camera.limit_right = 10000000
	camera.limit_bottom = 10000000


func _everyone_in_view() -> bool:
	var camera: Camera2D = _coop.camera
	if camera == null:
		return false
	for index in InputManagerScript.MAX_PLAYERS:
		var wizard: PlayerScript = _wizard(index)
		if wizard != null and not _in_view(wizard, camera):
			return false
	return true


func _test_defaults() -> void:
	_check(not _coop.friendly_fire and not _projectiles.friendly_fire, "friendly fire is off by default")
	_check(_coop.joined_count() == 0, "nobody is joined at the start")


func _test_every_join_order() -> void:
	var sequences: Array[Array] = _sequences()
	_check(sequences.size() == 64, "there are 64 join orders of 1-4 players, got %d" % sequences.size())
	for sequence: Array in sequences:
		var label: String = "join order %s" % [sequence]
		_stop()
		_start_with(sequence[0] as int)
		_check(_flow.state == FlowScript.State.RUNNING, label + ": the run started")
		_check(_joined_events == [sequence[0]], label + ": the starter was announced once, got %s" % [_joined_events])
		for position in range(1, sequence.size()):
			var slot: int = sequence[position]
			_input.add_virtual_device(slot)
			var expected: Array = []
			for i in position + 1:
				expected.append(sequence[i] as int)
			_check(_joined_events == expected, label + ": player_joined came in order, got %s" % [_joined_events])
			_check(_wizard(slot) != null, label + ": slot %d got a wizard mid-run" % slot)
			# A joiner takes the free spawn farthest from enemies and wizards (DECISIONS.md), not
			# necessarily the one numbered like its slot.
			_check(_wizard(slot) != null and _is_player_spawn(_wizard(slot).position), label + ": slot %d stands on a player spawn" % slot)
			_check(_coop.joined_count() == position + 1, label + ": %d players joined" % (position + 1))
			_check(_wizard_count() == position + 1, label + ": %d wizards" % (position + 1))
			_check(_flow.state == FlowScript.State.RUNNING and not _flow.is_restarting(), label + ": the run went on while someone joined")
			_coop.snap()
			_check(_everyone_in_view(), label + ": everyone is in view after slot %d joined" % slot)
		for slot: int in sequence:
			_check(_wizard(slot) != null and (_wizard(slot) as PlayerScript).index == slot, label + ": wizard %d has its own index" % slot)
	_stop()


func _test_every_leave_order() -> void:
	for sequence: Array in _sequences():
		var label: String = "leave order %s" % [sequence]
		_stop()
		_start_with(0)
		for slot in range(1, InputManagerScript.MAX_PLAYERS):
			_input.add_virtual_device(slot)
		_check(_wizard_count() == 4, label + ": four wizards before leaving")
		_left_events.clear()
		var left: Array = []
		for slot: int in sequence:
			_input.leave(slot)
			left.append(slot)
			_check(_left_events == left, label + ": player_left came in order, got %s" % [_left_events])
			_check(_wizard(slot) == null, label + ": slot %d lost its wizard" % slot)
			_check(_wizard_count() == 4 - left.size(), label + ": %d wizards remain" % (4 - left.size()))
			_check(_coop.joined_count() == 4 - left.size(), label + ": %d players remain" % (4 - left.size()))
			for other in InputManagerScript.MAX_PLAYERS:
				_check(left.has(other) or _wizard(other) != null, label + ": slot %d kept its wizard" % other)
			_coop.step(0.1)
			_check(_everyone_in_view() or _wizard_count() == 0, label + ": the rest are in view")
		# The order may name only some slots: the rest are still playing. When everyone is
		# gone, the run waits quietly (nobody is down, so nothing restarts).
		_check(_wizard_count() == 4 - sequence.size() and _flow.state == FlowScript.State.RUNNING and not _flow.is_restarting(), label + ": the run goes on, and waits quietly once everyone is gone (nobody is down)")
	_stop()


## All four join in the menu, before Play: each is announced once and all four play.
func _test_join_before_play() -> void:
	for order: Array in [[0, 1, 2, 3], [3, 2, 1, 0], [2, 0, 3, 1]]:
		_stop()
		for slot: int in order:
			_input.add_virtual_device(slot)
		_check(_joined_events == order, "menu join order %s was announced in order, got %s" % [order, _joined_events])
		_check(_flow.state == FlowScript.State.IDLE and _wizard_count() == 0, "joining in the menu starts nothing")
		_events.emit_signal("play_requested", order[0])
		_check(_wizard_count() == 4, "menu join order %s: four wizards after Play" % [order])
		_check(_joined_events == order, "Play does not announce the players again, got %s" % [_joined_events])
		_check(_everyone_in_view(), "menu join order %s: everyone in view at the start" % [order])
	_stop()


func _test_duplicate_device_events() -> void:
	_stop()
	_start_with(0)
	_joined_events.clear()
	_events.emit_signal("device_joined", 0, 77)
	_check(_joined_events.is_empty(), "a second device_joined for a taken slot sends no player_joined")
	_events.emit_signal("device_joined", 4, 78)
	_events.emit_signal("device_joined", -1, 79)
	_check(_joined_events.is_empty(), "a device_joined for a slot outside 0-3 is ignored")
	_events.emit_signal("device_left", 2, 80)
	_check(_left_events.is_empty(), "device_left for a slot nobody holds sends no player_left")
	_check(_coop.joined_count() == 1, "the count did not move")
	_stop()


func _test_leave_and_rejoin_same_slot() -> void:
	_stop()
	_start_with(0)
	_input.add_virtual_device(1)
	_input.leave(1)
	_check(_wizard(1) == null and _wizard_count() == 1, "slot 2 left: only P1 plays")
	_input.add_virtual_device(1)
	_check(_wizard(1) != null and _wizard_count() == 2, "slot 2 rejoined with a fresh wizard")
	_check((_wizard(1) as PlayerScript).health == PlayerScript.MAX_HEALTH, "the rejoined wizard is at full health")
	_check(_joined_events == [0, 1, 1] and _left_events == [1], "events: joined 0, 1, 1 and left 1, got %s and %s" % [_joined_events, _left_events])
	_stop()


## When the only wizard standing leaves and the rest are down, the room restarts as usual;
## and a player who joins while everyone is down gives the party a standing wizard.
func _test_last_standing_leaves_restarts_the_room() -> void:
	_stop()
	_start_with(0)
	_input.add_virtual_device(1)
	(_wizard(0) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
	_check(not _flow.is_restarting(), "one wizard still stands: no restart")
	_input.leave(1)
	_check(_flow.is_restarting(), "the last standing wizard left and the rest are down: the room restarts")
	_input.add_virtual_device(2)
	_check(not _flow.is_restarting(), "a player joining while all were down cancels the restart")
	_stop()


func _test_camera_zooms_out_to_fit() -> void:
	_stop()
	_start_with(0)
	_coop.snap()
	var camera: Camera2D = _coop.camera
	_check(camera != null, "the camera was found after room_entered")
	if camera == null:
		return
	_open_limits(camera)
	# The limits changed, so the target moved: snap again to see the zoom alone.
	_coop.snap()
	_check(is_equal_approx(camera.zoom.x, CoopScript.MAX_ZOOM), "one player: no zoom out, got %f" % camera.zoom.x)
	_check(camera.position.is_equal_approx(_wizard(0).global_position), "one player: the camera is on the player: %s vs %s" % [camera.position, _wizard(0).global_position])
	for slot in range(1, 4):
		_input.add_virtual_device(slot)
	# Spread the four wizards to the corners of a wide area.
	var corners: Array[Vector2] = [Vector2(40.0, 40.0), Vector2(600.0, 40.0), Vector2(40.0, 340.0), Vector2(600.0, 340.0)]
	for slot in 4:
		_wizard(slot).global_position = corners[slot]
	_coop.refresh_wizards()
	_coop.snap()
	_check(camera.zoom.x < CoopScript.MAX_ZOOM, "four spread players: the camera zoomed out, got %f" % camera.zoom.x)
	_check(camera.zoom.x >= CoopScript.MIN_ZOOM, "the zoom stays above the minimum")
	_check(_everyone_in_view(), "four spread players: everyone is in view")
	for slot in 4:
		var offset: Vector2 = (corners[slot] - camera.position) * camera.zoom.x
		_check(absf(offset.x) <= VIEW.x * 0.5 - CoopScript.CAMERA_MARGIN * camera.zoom.x + 0.01 or absf(offset.y) <= VIEW.y * 0.5 - CoopScript.CAMERA_MARGIN * camera.zoom.x + 0.01, "slot %d keeps the margin from the view's edge on one axis" % slot)
	# Pushed apart beyond what fits: the zoom stops at the minimum.
	_wizard(0).global_position = Vector2(-1000.0, 0.0)
	_wizard(1).global_position = Vector2(2000.0, 0.0)
	_coop.snap()
	_check(is_equal_approx(camera.zoom.x, CoopScript.MIN_ZOOM), "far apart: the zoom stops at the minimum")
	# Back together: it zooms in again.
	for slot in 4:
		_wizard(slot).global_position = Vector2(300.0 + 4.0 * slot, 200.0)
	_coop.snap()
	_check(is_equal_approx(camera.zoom.x, CoopScript.MAX_ZOOM), "together again: the zoom is back to 1, got %f" % camera.zoom.x)
	# The downed are still in view.
	(_wizard(3) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
	_wizard(3).global_position = Vector2(600.0, 340.0)
	_wizard(0).global_position = Vector2(40.0, 40.0)
	_coop.snap()
	_check(_in_view(_wizard(3), camera) and _in_view(_wizard(0), camera), "a downed wizard stays in the shared view")
	_stop()


func _test_camera_eases() -> void:
	_stop()
	_start_with(0)
	_input.add_virtual_device(1)
	var camera: Camera2D = _coop.camera
	if camera == null:
		_check(false, "the camera exists for the easing test")
		return
	_open_limits(camera)
	_wizard(0).global_position = Vector2(100.0, 100.0)
	_wizard(1).global_position = Vector2(500.0, 300.0)
	_coop.snap()
	_wizard(1).global_position = Vector2(200.0, 100.0)
	var before: Vector2 = camera.position
	_coop.step(0.016)
	var moved: float = camera.position.distance_to(before)
	var total: float = before.distance_to(_coop.target_position)
	_check(moved > 0.0 and moved < total, "one frame moves the camera part of the way (%f of %f)" % [moved, total])
	for i in 200:
		_coop.step(0.1)
	_check(camera.position.distance_to(_coop.target_position) < 0.01, "the camera arrives at its target")
	_check(absf(camera.zoom.x - _coop.target_zoom) < 0.001, "the zoom arrives at its target")
	# A zero or negative step moves nothing.
	var at: Vector2 = camera.position
	_coop.step(0.0)
	_coop.step(-1.0)
	_check(camera.position == at, "a zero or negative step does not move the camera")
	_stop()


## The room's limits and the zoom agree: wizards in opposite corners of arena_01
## are all in the real view, and the view never shows beyond the room.
func _test_camera_respects_room_limits() -> void:
	_stop()
	_start_with(0)
	for slot in range(1, 4):
		_input.add_virtual_device(slot)
	var camera: Camera2D = _coop.camera
	if camera == null:
		_check(false, "the camera exists for the limits test")
		return
	var room := Rect2(Vector2(camera.limit_left, camera.limit_top), Vector2(camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top))
	var corners: Array[Vector2] = [Vector2(20.0, 20.0), Vector2(room.end.x - 20.0, 20.0), Vector2(20.0, room.end.y - 20.0), room.end - Vector2(20.0, 20.0)]
	for slot in 4:
		_wizard(slot).global_position = corners[slot]
	_coop.refresh_wizards()
	_coop.snap()
	_check(room.grow(0.01).encloses(_coop.visible_rect()), "snapped: the view stays inside the room, got %s" % _coop.visible_rect())
	for slot in 4:
		_check(_in_view(_wizard(slot), camera), "snapped: the wizard in corner %d is in the view" % slot)
	# Start from the middle and ease out to the corners: nobody is ever outside.
	camera.position = room.get_center()
	camera.zoom = Vector2.ONE
	for i in 60:
		_coop.step(0.016)
		_check(room.grow(0.01).encloses(_coop.visible_rect()), "easing %d: the view stays inside the room" % i)
		_check(_everyone_in_view(), "easing %d: everyone is in view" % i)
	_stop()


## A far-off joiner: while the camera eases, nobody is outside the view.
func _test_nobody_leaves_the_view_while_easing() -> void:
	_stop()
	_start_with(0)
	_input.add_virtual_device(1)
	var camera: Camera2D = _coop.camera
	if camera == null:
		_check(false, "the camera exists for the ease-out test")
		return
	_open_limits(camera)
	_wizard(0).global_position = Vector2(60.0, 200.0)
	_wizard(1).global_position = Vector2(70.0, 200.0)
	_coop.snap()
	_wizard(1).global_position = Vector2(560.0, 200.0)
	for i in 120:
		_coop.step(0.016)
		_check(_everyone_in_view(), "ease-out frame %d: everyone is in view" % i)
	_stop()


## A mid-run joiner is protected for a moment and does not land on an enemy.
func _test_joiner_is_protected() -> void:
	_stop()
	_start_with(0)
	var spawns: PackedVector2Array = _flow._room.player_spawns
	# An enemy stands on slot 1's spawn.
	var enemy: Node2D = _flow._enemies[0] as Node2D
	enemy.position = spawns[1]
	_input.add_virtual_device(1)
	var joiner: PlayerScript = _wizard(1)
	_check(joiner != null, "the joiner has a wizard")
	if joiner == null:
		return
	_check(joiner.is_invulnerable(), "the joiner cannot be hurt at first")
	_check(not joiner.take_damage(SHOT_DAMAGE) and joiner.health == PlayerScript.MAX_HEALTH, "a hit on the new joiner does nothing")
	_check(joiner.position.distance_to(spawns[1]) > 1.0, "the joiner is not put under the enemy")
	_check(joiner.position.distance_to(_wizard(0).position) > 1.0, "the joiner does not stand on another wizard")
	_stop()


## Put a run with `count` players (slots 0 to count-1) up, far apart.
func _run_with(count: int) -> void:
	_stop()
	_start_with(0)
	for slot in range(1, count):
		_input.add_virtual_device(slot)
	for slot in count:
		# A joiner is protected for a while; let that run out so it can be hurt.
		_wizard(slot).step(PlayerScript.JOIN_PROTECTION + 0.1)
		_wizard(slot).position = Vector2(100.0 + 150.0 * slot, 100.0)
	_coop.refresh_wizards()


func _down(slot: int) -> void:
	_wizard(slot).take_damage(PlayerScript.MAX_HEALTH)


## Advance the revive by `seconds`, in steps of 0.1.
func _hold(seconds: float) -> void:
	for i in roundi(seconds / 0.1):
		_coop.step_revive(0.1)


func _test_revive_two_players() -> void:
	_run_with(2)
	var progress: Array = []
	var on_progress: Callable = func(p: int, f: float) -> void: progress.append([p, f])
	_events.connect("revive_progress", on_progress)
	var revived: Array = []
	var on_revived: Callable = func(p: int, r: int) -> void: revived.append([p, r])
	_events.connect("player_revived", on_revived)
	_down(0)
	_check(_wizard(0).is_downed(), "revive: wizard 0 is down")
	# Far away: nothing fills.
	_hold(1.0)
	_check(_coop.revive_progress_of(0) == 0.0 and progress.is_empty(), "revive: nobody near, no progress")
	# Just outside the range: still nothing.
	_wizard(1).position = _wizard(0).position + Vector2(CoopScript.REVIVE_RANGE + 1.0, 0.0)
	_hold(1.0)
	_check(_coop.revive_progress_of(0) == 0.0, "revive: just outside the range does not count")
	# Inside: half the hold time is half the progress, and the downed wizard hears it.
	_wizard(1).position = _wizard(0).position + Vector2(CoopScript.REVIVE_RANGE - 4.0, 0.0)
	_hold(CoopScript.REVIVE_HOLD_TIME * 0.5)
	_check(absf(_coop.revive_progress_of(0) - 0.5) < 0.01, "revive: half the time, half the progress, got %f" % _coop.revive_progress_of(0))
	_check(absf(_wizard(0).revive_progress() - 0.5) < 0.01, "revive: the downed wizard knows its progress (for the ring)")
	_check(not progress.is_empty() and progress[0][0] == 0, "revive: revive_progress names the downed player")
	_check(_wizard(0).is_downed(), "revive: still down at half the time")
	# Stepping away drains at twice the speed: 0.2 s away undoes 0.2 of the hold
	# (the same 0.2 s beside the body would have filled 0.1).
	_wizard(1).position = _wizard(0).position + Vector2(300.0, 0.0)
	_hold(0.2)
	_check(absf(_coop.revive_progress_of(0) - 0.3) < 0.01, "revive: progress drains twice as fast as it fills, got %f" % _coop.revive_progress_of(0))
	_hold(CoopScript.REVIVE_HOLD_TIME)
	_check(_coop.revive_progress_of(0) == 0.0 and _wizard(0).revive_progress() == 0.0, "revive: the progress drains to nothing")
	# Back beside the body: the full hold revives.
	_wizard(1).position = _wizard(0).position + Vector2(20.0, 0.0)
	_hold(CoopScript.REVIVE_HOLD_TIME - 0.2)
	_check(_wizard(0).is_downed(), "revive: not yet shortly before the end")
	_hold(0.4)
	_check(not _wizard(0).is_downed(), "revive: back up after the hold time")
	_check(revived == [[0, 1]], "revive: player_revived carries the player and the reviver, got %s" % [revived])
	_check(_wizard(0).health == PlayerScript.REVIVE_HEALTH, "revive: the revive health")
	_check(_coop.revive_progress_of(0) == 0.0 and _wizard(0).revive_progress() == 0.0, "revive: the ring is cleared")
	_check(progress.back()[1] == 0.0, "revive: the last progress sent is 0")
	# The protection window.
	_check(_wizard(0).is_invulnerable(), "revive: protected after the revive")
	_check(not _wizard(0).take_damage(SHOT_DAMAGE) and _wizard(0).health == PlayerScript.REVIVE_HEALTH, "revive: a hit right after does nothing")
	for i in roundi(CoopScript.REVIVE_PROTECTION / 0.1) + 2:
		_wizard(0).step(0.1)
	_check(not _wizard(0).is_invulnerable(), "revive: the protection ends after REVIVE_PROTECTION")
	_check(_wizard(0).take_damage(SHOT_DAMAGE), "revive: hurt normally afterwards")
	_check(_wizard(1).health == PlayerScript.MAX_HEALTH and not _wizard(1).is_downed(), "revive: the reviver is unharmed")
	_events.disconnect("revive_progress", on_progress)
	_events.disconnect("player_revived", on_revived)
	_stop()


func _test_revive_four_players() -> void:
	# Each slot in turn is the one who falls, and the next slot revives it.
	for fallen in InputManagerScript.MAX_PLAYERS:
		_run_with(4)
		_down(fallen)
		_wizard((fallen + 1) % 4).position = _wizard(fallen).position + Vector2(24.0, 0.0)
		_hold(CoopScript.REVIVE_HOLD_TIME + 0.2)
		_check(not _wizard(fallen).is_downed(), "revive x4: slot %d is back up" % fallen)
		_check(_wizard(fallen).is_invulnerable(), "revive x4: slot %d is protected" % fallen)
	# Three fall at once. Slot 2 stands beside slot 0 only; downed slots 1 and 3
	# stand together but cannot revive each other.
	_run_with(4)
	_down(0)
	_down(1)
	_down(3)
	_wizard(2).position = _wizard(0).position + Vector2(20.0, 0.0)
	_wizard(3).position = _wizard(1).position + Vector2(20.0, 0.0)
	_hold(CoopScript.REVIVE_HOLD_TIME + 0.2)
	_check(not _wizard(0).is_downed(), "revive x4: slot 0 revived by slot 2")
	_check(_wizard(1).is_downed() and _wizard(3).is_downed(), "revive x4: downed wizards do not revive each other")
	# Slot 0 walks over: both are revived at once, each by the nearest standing wizard.
	_wizard(0).position = _wizard(1).position + Vector2(10.0, 0.0)
	_wizard(2).position = Vector2(900.0, 900.0)
	var revived: Array = []
	var on_revived: Callable = func(p: int, r: int) -> void: revived.append([p, r])
	_events.connect("player_revived", on_revived)
	_hold(CoopScript.REVIVE_HOLD_TIME + 0.2)
	_check(not _wizard(1).is_downed() and not _wizard(3).is_downed(), "revive x4: slots 1 and 3 are back up together")
	_check(revived.has([1, 0]) and revived.has([3, 0]), "revive x4: slot 0 is the reviver of both, got %s" % [revived])
	_events.disconnect("player_revived", on_revived)
	_stop()


## A reviver who leaves stops the revive; a downed leaver's progress is cleared.
func _test_revive_edges() -> void:
	_run_with(3)
	_down(0)
	_wizard(1).position = _wizard(0).position + Vector2(20.0, 0.0)
	_hold(1.0)
	_check(_coop.revive_progress_of(0) > 0.0, "revive edges: progress under way")
	_input.leave(1)
	_hold(CoopScript.REVIVE_HOLD_TIME * 2.0)
	_check(_wizard(0).is_downed() and _coop.revive_progress_of(0) == 0.0, "revive edges: the reviver left, the progress drained away")
	_hold(1.0)
	_input.leave(0)
	_check(_coop.revive_progress_of(0) == 0.0, "revive edges: a leaver's progress is cleared")
	_stop()


## The room restart builds a new world and camera; Coop follows the new one.
func _test_camera_survives_a_restart() -> void:
	_stop()
	_start_with(0)
	var old_camera: Camera2D = _coop.camera
	(_wizard(0) as PlayerScript).take_damage(PlayerScript.MAX_HEALTH)
	_flow.step(FlowScript.RESTART_DELAY)
	_check(_flow.state == FlowScript.State.RUNNING, "the room restarted")
	_check(_coop.camera != null and _coop.camera != old_camera and _coop.camera.is_inside_tree(), "Coop picked up the new world's camera")
	_check(_everyone_in_view(), "the player is in view after the restart")
	# A step with the old camera gone must not fail.
	_coop.step(0.1)
	_stop()
	_coop.step(0.1)
	_check(true, "stepping with no wizards is safe")


func _test_friendly_fire() -> void:
	for enabled: bool in [false, true]:
		_stop()
		# All three are in before Play: a mid-run joiner is invulnerable for 2 s.
		_input.add_virtual_device(1)
		_input.add_virtual_device(2)
		_start_with(0)
		# No enemy gets in the way of the test shots.
		for enemy: Node in _flow._enemies.duplicate():
			_combat.call("unregister_enemy", enemy)
		_combat.call("set_hit_profile", BOLT_TAG, SHOT_DAMAGE, 0.0)
		_coop.set_friendly_fire(enabled)
		_check(_projectiles.friendly_fire == enabled, "Coop sets the projectile manager's flag (%s)" % enabled)
		_wizard(0).global_position = Vector2(100.0, 100.0)
		_wizard(1).global_position = Vector2(140.0, 100.0)
		_wizard(2).global_position = Vector2(100.0, 300.0)
		_projectiles.clear()
		_projectiles.spawn(0, Vector2(100.0, 100.0), Vector2(400.0, 0.0), 1.0, 4.0, ProjectileManagerScript.LAYER_ENEMY, 0, BOLT_TAG)
		_projectiles.step(0.1)
		var label: String = "friendly fire %s" % ("on" if enabled else "off")
		_check((_wizard(0) as PlayerScript).health == PlayerScript.MAX_HEALTH, label + ": the shooter is never hit by its own shot")
		_check((_wizard(2) as PlayerScript).health == PlayerScript.MAX_HEALTH, label + ": a wizard off the line of fire is untouched")
		var expected: int = PlayerScript.MAX_HEALTH - SHOT_DAMAGE if enabled else PlayerScript.MAX_HEALTH
		_check((_wizard(1) as PlayerScript).health == expected, label + ": the teammate's health is %d, got %d" % [expected, (_wizard(1) as PlayerScript).health])
		_check(_projectiles.get_count() == (0 if enabled else 1), label + ": the shot %s" % ("ended on the hit" if enabled else "flew on"))
		# An enemy shot hurts players either way.
		_projectiles.clear()
		_projectiles.spawn(-1, Vector2(100.0, 296.0), Vector2(0.0, 100.0), 0.2, 4.0, ProjectileManagerScript.LAYER_PLAYER, 0, BOLT_TAG)
		_projectiles.step(0.05)
		_check((_wizard(2) as PlayerScript).health == PlayerScript.MAX_HEALTH - SHOT_DAMAGE, label + ": an enemy shot still hurts a wizard")
	# Turned off again, the flag does not stay on.
	_coop.set_friendly_fire(true)
	_coop.set_friendly_fire(false)
	_check(not _projectiles.friendly_fire and not _coop.friendly_fire, "friendly fire switches back off")
	_stop()
