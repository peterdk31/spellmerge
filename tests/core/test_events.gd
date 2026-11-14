extends SceneTree
## Tests for core/events: the autoload is registered, every event exists with
## its seat (`player`) or actor id (`caster`, `actor`, `killer`) first where it
## has one, and signals reach listeners for all four player indices.
##
## godot --headless --path . --script res://tests/core/test_events.gd

const EventsScript := preload("res://core/events/events.gd")

## Every event with its arguments in order, as [name, type]. A new signal in
## events.gd must be added here, or the test fails.
const EVENTS: Dictionary = {
	# Player intent from the HUD.
	&"play_requested": [["player", TYPE_INT]],
	&"staff_change_requested": [["player", TYPE_INT], ["staff", TYPE_INT], ["slot", TYPE_INT], ["card_id", TYPE_STRING_NAME]],
	&"staff_cards_requested": [["player", TYPE_INT], ["staff", TYPE_INT], ["cards", TYPE_ARRAY]],
	&"reward_pick_requested": [["player", TYPE_INT], ["choice", TYPE_INT]],
	&"door_vote_requested": [["player", TYPE_INT], ["door", TYPE_INT]],
	&"pause_requested": [["player", TYPE_INT], ["on", TYPE_INT]],
	&"sandbox_requested": [["player", TYPE_INT]],
	&"hub_requested": [["player", TYPE_INT]],
	&"main_menu_requested": [["player", TYPE_INT]],
	&"seat_leave_requested": [["player", TYPE_INT]],
	&"run_requested": [["player", TYPE_INT]],
	&"effect_slots_changed": [["slots", TYPE_INT]],
	&"screen_shake_changed": [["enabled", TYPE_BOOL]],
	&"damage_numbers_changed": [["on", TYPE_BOOL]],
	&"projectile_cap_changed": [["cap", TYPE_INT]],
	&"shot_cap_requested": [["player", TYPE_INT], ["cap", TYPE_INT]],
	&"mote_cap_changed": [["cap", TYPE_INT]],
	&"mote_density_changed": [["density", TYPE_FLOAT]],
	&"floor_marks_changed": [["on", TYPE_BOOL]],
	&"spell_light_changed": [["on", TYPE_BOOL]],
	&"tailless_motes_changed": [["pool", TYPE_INT]],
	&"sandbox_action_requested": [["player", TYPE_INT], ["action", TYPE_STRING_NAME]],
	&"sandbox_spawn_requested": [["player", TYPE_INT], ["enemy_id", TYPE_STRING_NAME], ["count", TYPE_INT]],
	&"ai_view_changed": [["on", TYPE_BOOL]],
	# Playing online.
	&"online_host_requested": [["player", TYPE_INT]],
	&"online_join_requested": [["player", TYPE_INT], ["code", TYPE_STRING]],
	&"online_answer_requested": [["player", TYPE_INT], ["code", TYPE_STRING]],
	&"online_leave_requested": [["player", TYPE_INT]],
	&"online_open_requested": [["player", TYPE_INT]],
	&"play_load_requested": [],
	&"online_changed": [["phase", TYPE_STRING_NAME], ["code", TYPE_STRING], ["reason", TYPE_STRING_NAME], ["facts", TYPE_DICTIONARY]],
	&"online_line_changed": [["facts", TYPE_DICTIONARY], ["counters", TYPE_STRING]],
	# Devices.
	&"device_joined": [["player", TYPE_INT], ["device", TYPE_INT]],
	&"device_left": [["player", TYPE_INT], ["device", TYPE_INT]],
	# Seats.
	&"seat_joined": [["player", TYPE_INT]],
	&"seat_left": [["player", TYPE_INT]],
	# Spells and combat.
	&"actor_cast": [["caster", TYPE_INT], ["actor", TYPE_OBJECT]],
	&"staff_shown": [["caster", TYPE_INT], ["actor", TYPE_OBJECT], ["staff", TYPE_INT]],
	&"spell_cast": [["player", TYPE_INT], ["spell_id", TYPE_STRING_NAME], ["origin", TYPE_VECTOR2], ["direction", TYPE_VECTOR2]],
	&"projectile_hit": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["position", TYPE_VECTOR2], ["tag", TYPE_INT], ["shot", TYPE_INT]],
	&"projectile_impact": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["position", TYPE_VECTOR2], ["direction", TYPE_VECTOR2]],
	&"projectile_expired": [["caster", TYPE_INT], ["position", TYPE_VECTOR2], ["tag", TYPE_INT], ["shot", TYPE_INT]],
	&"carrier_shown": [["caster", TYPE_INT], ["carrier_card", TYPE_STRING_NAME], ["origin", TYPE_VECTOR2], ["direction", TYPE_VECTOR2], ["length", TYPE_FLOAT], ["tint", TYPE_COLOR], ["look", TYPE_INT]],
	&"carrier_ended": [["caster", TYPE_INT], ["carrier_card", TYPE_STRING_NAME], ["at", TYPE_VECTOR2], ["direction", TYPE_VECTOR2], ["size", TYPE_FLOAT], ["tint", TYPE_COLOR], ["look", TYPE_INT]],
	&"cue_shown": [["caster", TYPE_INT], ["cue", TYPE_STRING_NAME], ["at", TYPE_VECTOR2], ["direction", TYPE_VECTOR2], ["size", TYPE_FLOAT], ["tint", TYPE_COLOR], ["look", TYPE_INT]],
	&"build_refused": [["player", TYPE_INT], ["reason", TYPE_STRING]],
	&"bag_changed": [["player", TYPE_INT], ["bag", TYPE_STRING_NAME], ["ids", TYPE_ARRAY], ["counts", TYPE_PACKED_INT32_ARRAY], ["capacity", TYPE_INT]],
	&"owned_staff_changed": [["player", TYPE_INT], ["staff", TYPE_INT], ["plan", TYPE_DICTIONARY]],
	&"hands_changed": [["player", TYPE_INT], ["hands", TYPE_PACKED_INT32_ARRAY]],
	&"reaction_triggered": [["caster", TYPE_INT], ["reaction_id", TYPE_STRING_NAME], ["position", TYPE_VECTOR2], ["shot", TYPE_INT]],
	&"discharge_arc": [["caster", TYPE_INT], ["from", TYPE_VECTOR2], ["to", TYPE_VECTOR2]],
	&"damage_dealt": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["amount", TYPE_FLOAT], ["position", TYPE_VECTOR2]],
	&"status_applied": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["status_id", TYPE_STRING_NAME]],
	&"prop_state_changed": [["actor", TYPE_INT], ["state", TYPE_STRING_NAME]],
	&"prop_state_requested": [["actor", TYPE_INT], ["state", TYPE_STRING_NAME]],
	&"status_requested": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["status_id", TYPE_STRING_NAME], ["duration", TYPE_FLOAT], ["strength", TYPE_FLOAT]],
	&"enemy_died": [["killer", TYPE_INT], ["enemy", TYPE_OBJECT], ["position", TYPE_VECTOR2], ["shot", TYPE_INT]],
	# Staffs (docs/milestones/M2-staffs.md, "Events").
	&"staff_changed": [["player", TYPE_INT], ["staff", TYPE_INT], ["plan", TYPE_DICTIONARY]],
	&"staff_cast": [["player", TYPE_INT], ["staff", TYPE_INT], ["origin", TYPE_VECTOR2], ["direction", TYPE_VECTOR2]],
	&"caster_move_requested": [["caster", TYPE_INT], ["mode", TYPE_STRING_NAME], ["move", TYPE_VECTOR2], ["seconds", TYPE_FLOAT], ["tag", TYPE_INT]],
	&"caster_move_finished": [["caster", TYPE_INT], ["mode", TYPE_STRING_NAME], ["position", TYPE_VECTOR2], ["tag", TYPE_INT]],
	&"target_move_requested": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["to", TYPE_VECTOR2]],
	&"entity_spawn_requested": [["caster", TYPE_INT], ["kind", TYPE_STRING_NAME], ["position", TYPE_VECTOR2], ["seconds", TYPE_FLOAT], ["tag", TYPE_INT], ["anchor", TYPE_INT]],
	&"entity_end_requested": [["caster", TYPE_INT], ["tag", TYPE_INT]],
	&"entity_ended": [["caster", TYPE_INT], ["kind", TYPE_STRING_NAME], ["position", TYPE_VECTOR2], ["tag", TYPE_INT]],
	&"mana_refund_requested": [["caster", TYPE_INT], ["staff", TYPE_INT], ["amount", TYPE_FLOAT]],
	&"mana_spend_requested": [["caster", TYPE_INT], ["staff", TYPE_INT], ["amount", TYPE_FLOAT]],
	&"cast_fizzled": [["caster", TYPE_INT], ["staff", TYPE_INT]],
	&"cast_winding": [["caster", TYPE_INT], ["staff", TYPE_INT], ["carrier_card", TYPE_STRING_NAME], ["origin", TYPE_VECTOR2], ["direction", TYPE_VECTOR2], ["seconds", TYPE_FLOAT], ["tint", TYPE_COLOR], ["look", TYPE_INT], ["tag", TYPE_INT], ["cue", TYPE_STRING_NAME]],
	&"cast_left": [["caster", TYPE_INT], ["staff", TYPE_INT]],
	&"mana_reserved": [["player", TYPE_INT], ["staff", TYPE_INT], ["amount", TYPE_FLOAT]],
	&"shot_blocked": [["caster", TYPE_INT], ["position", TYPE_VECTOR2], ["tag", TYPE_INT], ["shot", TYPE_INT]],
	&"shot_deflected": [["caster", TYPE_INT], ["position", TYPE_VECTOR2], ["tag", TYPE_INT], ["shot", TYPE_INT]],
	&"shield_blocked": [["actor", TYPE_INT], ["position", TYPE_VECTOR2], ["tag", TYPE_INT]],
	&"barrier_changed": [["actor", TYPE_INT], ["charges", TYPE_INT], ["seconds", TYPE_FLOAT], ["tag", TYPE_INT], ["way", TYPE_VECTOR2], ["radius", TYPE_FLOAT]],
	&"kill_landed": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["position", TYPE_VECTOR2], ["tag", TYPE_INT], ["shot", TYPE_INT]],
	&"actor_hurt": [["actor", TYPE_INT], ["amount", TYPE_FLOAT], ["position", TYPE_VECTOR2], ["tag", TYPE_INT], ["kind", TYPE_STRING_NAME]],
	&"reaction_landed": [["caster", TYPE_INT], ["reaction_id", TYPE_STRING_NAME], ["target", TYPE_OBJECT], ["position", TYPE_VECTOR2], ["tag", TYPE_INT], ["shot", TYPE_INT]],
	&"wizard_shield_requested": [["caster", TYPE_INT], ["charges", TYPE_INT], ["seconds", TYPE_FLOAT], ["tag", TYPE_INT]],
	&"pull_requested": [["caster", TYPE_INT], ["position", TYPE_VECTOR2], ["radius", TYPE_FLOAT], ["strength", TYPE_FLOAT], ["tag", TYPE_INT], ["to", TYPE_VECTOR2]],
	&"possess_requested": [["caster", TYPE_INT], ["target", TYPE_INT], ["seconds", TYPE_FLOAT], ["tag", TYPE_INT]],
	&"possess_started": [["caster", TYPE_INT], ["actor", TYPE_INT]],
	&"possess_ended": [["caster", TYPE_INT], ["actor", TYPE_INT]],
	&"hit_landed": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["amount", TYPE_FLOAT], ["position", TYPE_VECTOR2], ["kind", TYPE_STRING_NAME], ["shot", TYPE_INT]],
	&"heal_dealt": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["amount", TYPE_FLOAT], ["position", TYPE_VECTOR2]],
	&"damage_number_shown": [["actor", TYPE_INT], ["position", TYPE_VECTOR2], ["amount", TYPE_FLOAT], ["element", TYPE_STRING_NAME], ["kind", TYPE_STRING_NAME], ["rise", TYPE_FLOAT], ["seconds", TYPE_FLOAT], ["size", TYPE_FLOAT]],
	# Players.
	&"player_downed": [["player", TYPE_INT]],
	&"player_revived": [["player", TYPE_INT], ["reviver", TYPE_INT]],
	&"revive_progress": [["player", TYPE_INT], ["progress", TYPE_FLOAT]],
	&"player_stats_changed": [["player", TYPE_INT], ["health", TYPE_FLOAT], ["max_health", TYPE_FLOAT], ["mana", TYPE_FLOAT], ["max_mana", TYPE_FLOAT]],
	&"staff_mana_changed": [["player", TYPE_INT], ["staff", TYPE_INT], ["mana", TYPE_FLOAT], ["max_mana", TYPE_FLOAT]],
	&"player_joined": [["player", TYPE_INT]],
	&"player_left": [["player", TYPE_INT]],
	# Run and rooms.
	&"run_started": [["player_count", TYPE_INT]],
	&"run_ended": [["victory", TYPE_BOOL]],
	&"room_entered": [["room_id", TYPE_STRING_NAME]],
	&"room_cleared": [["room_id", TYPE_STRING_NAME]],
	&"loading_started": [],
	&"loading_progressed": [["done", TYPE_INT], ["total", TYPE_INT]],
	&"loading_finished": [],
	&"start_stone_changed": [["standing", TYPE_INT], ["wizards", TYPE_INT], ["lit", TYPE_BOOL]],
	&"altar_changed": [["seats", TYPE_INT]],
	&"altar_placed": [["standing", TYPE_BOOL], ["at", TYPE_VECTOR2]],
	&"hub_changed": [["in_hub", TYPE_BOOL]],
	&"wave_started": [["wave", TYPE_INT]],
	&"sandbox_changed": [["on", TYPE_BOOL]],
	&"build_break_started": [["seconds", TYPE_FLOAT]],
	&"door_voted": [["player", TYPE_INT], ["door", TYPE_INT]],
	&"difficulty_changed": [["level", TYPE_FLOAT]],
	# Rewards and progression.
	&"reward_rolled": [["reward_ids", TYPE_ARRAY]],
	&"reward_taken": [["player", TYPE_INT], ["reward_id", TYPE_STRING_NAME]],
	&"unlock_gained": [["unlock_id", TYPE_STRING_NAME]],
	&"currency_changed": [["currency_id", TYPE_STRING_NAME], ["amount", TYPE_INT]],
}

## Events about the run, a room or the account, with no seat and no actor.
const NOT_PER_PLAYER: Array[StringName] = [
	&"run_started", &"run_ended", &"room_entered", &"room_cleared", &"wave_started", &"start_stone_changed", &"altar_changed", &"altar_placed", &"hub_changed",
	&"loading_started", &"loading_progressed", &"loading_finished",
	&"play_load_requested", &"online_changed", &"online_line_changed", &"sandbox_changed", &"ai_view_changed", &"effect_slots_changed", &"screen_shake_changed", &"damage_numbers_changed", &"projectile_cap_changed", &"mote_cap_changed", &"mote_density_changed", &"floor_marks_changed", &"spell_light_changed", &"tailless_motes_changed", &"build_break_started", &"difficulty_changed", &"reward_rolled", &"unlock_gained", &"currency_changed",
]

## The names of a first argument that is a seat (`player`) or an actor id (the rest).
const FIRST_KEYS: Array[String] = ["player", "caster", "actor", "killer"]

var _failures: Array[String] = []
var _received: Array[int] = []


func _initialize() -> void:
	_test_autoload_registered()
	_test_signals_exist()
	_test_no_player_value()
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
	var signals: Dictionary = {}
	var script: Script = EventsScript
	for info: Dictionary in script.get_script_signal_list():
		signals[StringName(info["name"])] = info["args"]
	for event: StringName in EVENTS:
		_check(signals.has(event), "signal %s exists" % event)
		if not signals.has(event):
			continue
		var expected: Array = EVENTS[event]
		var args: Array = signals[event]
		_check(args.size() == expected.size(), "%s takes %d arguments, got %d" % [event, expected.size(), args.size()])
		for i in mini(args.size(), expected.size()):
			_check(args[i]["name"] == expected[i][0] and args[i]["type"] == expected[i][1],
				"%s argument %d is %s (type %d), got %s (type %d)" % [event, i, expected[i][0], expected[i][1], args[i]["name"], args[i]["type"]])
		var has_player: bool = not NOT_PER_PLAYER.has(event)
		var first: String = "" if expected.is_empty() else expected[0][0]
		_check(has_player == FIRST_KEYS.has(first),
			"%s has a seat or an actor id first exactly when it is per-player or per-actor" % event)
	for event: StringName in signals:
		_check(EVENTS.has(event), "signal %s in events.gd is covered by this test" % event)


func _test_no_player_value() -> void:
	_check(EventsScript.NO_PLAYER == -1, "NO_PLAYER is -1, outside the seats and the actor ids")


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
