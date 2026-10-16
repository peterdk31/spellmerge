extends SceneTree
## Tests for core/events: the autoload is registered, every event exists with
## the player index first where it has one, and signals reach listeners for all
## four player indices.
##
## godot --headless --path . --script res://tests/core/test_events.gd

const EventsScript := preload("res://core/events/events.gd")

## Events that carry a player index first.
const PER_PLAYER: Array[StringName] = [
	&"play_requested", &"build_change_requested", &"reward_pick_requested",
	&"door_vote_requested", &"pause_requested", &"spell_cast", &"projectile_hit",
	&"damage_dealt", &"status_applied", &"enemy_died", &"player_downed",
	&"player_revived", &"player_joined", &"player_left", &"door_voted", &"reward_taken",
]

## Events about the run, a room or the account, with no player index.
const NOT_PER_PLAYER: Array[StringName] = [
	&"run_started", &"run_ended", &"room_entered", &"room_cleared",
	&"difficulty_changed", &"reward_rolled", &"unlock_gained", &"currency_changed",
]

var _failures: Array[String] = []
var _received: Array[int] = []


func _initialize() -> void:
	_test_autoload_registered()
	_test_signals_exist()
	_test_play_requested_all_players()
	_test_player_events_all_players()
	if _failures.is_empty():
		print("TEST OK: core/events")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _on_player(player: int) -> void:
	_received.append(player)


func _test_autoload_registered() -> void:
	var path := str(ProjectSettings.get_setting("autoload/Events", ""))
	_check(path == "*res://core/events/events.gd", "autoload Events is registered, got '%s'" % path)


func _test_signals_exist() -> void:
	var bus: Node = EventsScript.new()
	var signals: Dictionary = {}
	for info: Dictionary in bus.get_signal_list():
		signals[StringName(info["name"])] = info["args"]
	for event in PER_PLAYER:
		_check(signals.has(event), "signal %s exists" % event)
		if not signals.has(event):
			continue
		var args: Array = signals[event]
		_check(not args.is_empty() and args[0]["name"] == "player" and args[0]["type"] == TYPE_INT,
			"%s takes the player index (an int) first" % event)
	for event in NOT_PER_PLAYER:
		_check(signals.has(event), "signal %s exists" % event)
	bus.free()


func _test_play_requested_all_players() -> void:
	var bus: Node = EventsScript.new()
	_received.clear()
	bus.play_requested.connect(_on_player)
	for player in 4:
		bus.play_requested.emit(player)
	_check(_received == [0, 1, 2, 3], "play_requested reaches the listener for players 0-3, got %s" % [_received])
	bus.free()


func _test_player_events_all_players() -> void:
	var bus: Node = EventsScript.new()
	_received.clear()
	bus.player_downed.connect(_on_player)
	bus.player_joined.connect(_on_player)
	for player in 4:
		bus.player_downed.emit(player)
		bus.player_joined.emit(player)
	_check(_received == [0, 0, 1, 1, 2, 2, 3, 3], "player events keep the player index, got %s" % [_received])
	bus.free()
