extends "res://tests/support/suite.gd"
## Tests for core/events: the autoload is registered; every event exists, with the arguments
## listed below, and no signal is left out of the list; an event has its seat (`player`) or actor
## id (`caster`, `actor`, `killer`) first exactly when it is per-player or per-actor; NO_PLAYER is
## outside the seats; and signals reach listeners for all four player indices (on a bus of its
## own, freed after each test).

const EventsScript := preload("res://core/events/events.gd")

## Every event with its arguments in order, as [name, type]. A new signal in
## events.gd must be added here, or the test fails.
const EVENTS: Dictionary = {
	# Player intent from the HUD.
	&"play_requested": [["player", TYPE_INT]],
	&"staff_change_requested": [["player", TYPE_INT], ["staff", TYPE_INT], ["slot", TYPE_INT], ["card_id", TYPE_STRING_NAME], ["body", TYPE_INT]],
	&"staff_cards_requested": [["player", TYPE_INT], ["staff", TYPE_INT], ["cards", TYPE_ARRAY], ["body", TYPE_INT]],
	&"reward_pick_requested": [["player", TYPE_INT], ["offer", TYPE_INT], ["choice", TYPE_INT]],
	&"door_vote_requested": [["player", TYPE_INT], ["door", TYPE_INT]],
	&"pause_requested": [["player", TYPE_INT], ["on", TYPE_INT]],
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
	&"shadows_changed": [["on", TYPE_BOOL]],
	&"ambient_particles_changed": [["on", TYPE_BOOL]],
	&"fog_changed": [["on", TYPE_BOOL]],
	&"environment_interaction_changed": [["on", TYPE_BOOL]],
	&"ambience_volume_changed": [["percent", TYPE_INT]],
	&"music_volume_changed": [["percent", TYPE_INT]],
	&"sound_volume_changed": [["percent", TYPE_INT]],
	&"ui_volume_changed": [["percent", TYPE_INT]],
	&"ui_sound_requested": [["id", TYPE_STRING_NAME]],
	&"tailless_motes_changed": [["pool", TYPE_INT]],
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
	&"pad_wait_requested": [["player", TYPE_INT], ["on", TYPE_INT]],
	# Items on the ground (items I6).
	&"item_take_requested": [["player", TYPE_INT], ["item", TYPE_INT]],
	&"boss_intro_next_requested": [["player", TYPE_INT], ["page", TYPE_INT]],
	&"all_cards_requested": [["player", TYPE_INT]],
	&"room_items_placed": [["room_id", TYPE_STRING_NAME], ["room", TYPE_INT], ["items", TYPE_ARRAY], ["at", TYPE_PACKED_VECTOR2_ARRAY]],
	&"item_drop_requested": [["actor", TYPE_INT], ["stack", TYPE_OBJECT]],
	&"ground_looked": [["actor", TYPE_INT], ["feet", TYPE_VECTOR2], ["reach", TYPE_FLOAT], ["sight", TYPE_OBJECT]],
	&"cover_danger_looked": [["actor", TYPE_INT], ["at", TYPE_VECTOR2], ["reach", TYPE_FLOAT], ["sight", TYPE_OBJECT]],
	&"hit_room_asked": [["target", TYPE_OBJECT], ["room", TYPE_OBJECT]],
	&"hit_damage_asked": [["tag", TYPE_INT], ["shot", TYPE_INT], ["answer", TYPE_OBJECT]],
	&"actor_take_requested": [["actor", TYPE_INT], ["item", TYPE_INT]],
	&"ground_item_changed": [["item", TYPE_INT], ["at", TYPE_VECTOR2], ["view", TYPE_DICTIONARY]],
	&"item_near_changed": [["player", TYPE_INT], ["item", TYPE_INT], ["at", TYPE_VECTOR2], ["view", TYPE_DICTIONARY]],
	&"item_refused": [["player", TYPE_INT], ["item", TYPE_INT]],
	# The inventory menu (items I7).
	&"staff_hand_requested": [["player", TYPE_INT], ["staff", TYPE_INT], ["hand", TYPE_INT], ["body", TYPE_INT]],
	&"bag_drop_requested": [["player", TYPE_INT], ["bag", TYPE_STRING_NAME], ["id", TYPE_STRING_NAME], ["staff", TYPE_INT], ["body", TYPE_INT]],
	&"inventory_refused": [["player", TYPE_INT], ["reason", TYPE_STRING]],
	&"inventory_announced": [["player", TYPE_INT], ["body", TYPE_INT]],
	&"pad_wait_changed": [["seats", TYPE_INT]],
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
	&"body_fell": [["actor", TYPE_INT]],
	&"body_returned": [["actor", TYPE_INT], ["at", TYPE_VECTOR2]],
	&"enemy_standing": [["enemy", TYPE_OBJECT]],
	&"adds_requested": [["actor", TYPE_INT], ["adds", TYPE_OBJECT], ["key", TYPE_INT], ["wave", TYPE_BOOL]],
	&"crumble_requested": [["actor", TYPE_INT]],
	# Staffs (docs/milestones/M2-staffs.md, "Events").
	&"staff_changed": [["player", TYPE_INT], ["staff", TYPE_INT], ["plan", TYPE_DICTIONARY]],
	&"staff_cast": [["player", TYPE_INT], ["staff", TYPE_INT], ["origin", TYPE_VECTOR2], ["direction", TYPE_VECTOR2]],
	&"caster_move_requested": [["caster", TYPE_INT], ["mode", TYPE_STRING_NAME], ["move", TYPE_VECTOR2], ["seconds", TYPE_FLOAT], ["tag", TYPE_INT]],
	&"caster_move_finished": [["caster", TYPE_INT], ["mode", TYPE_STRING_NAME], ["position", TYPE_VECTOR2], ["tag", TYPE_INT], ["walled", TYPE_BOOL]],
	&"target_move_requested": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["to", TYPE_VECTOR2]],
	&"entity_spawn_requested": [["caster", TYPE_INT], ["kind", TYPE_STRING_NAME], ["position", TYPE_VECTOR2], ["seconds", TYPE_FLOAT], ["tag", TYPE_INT], ["anchor", TYPE_INT]],
	&"entity_end_requested": [["caster", TYPE_INT], ["tag", TYPE_INT]],
	&"entity_ended": [["caster", TYPE_INT], ["kind", TYPE_STRING_NAME], ["position", TYPE_VECTOR2], ["tag", TYPE_INT]],
	&"mana_refund_requested": [["caster", TYPE_INT], ["staff", TYPE_INT], ["amount", TYPE_FLOAT]],
	&"mana_spend_requested": [["caster", TYPE_INT], ["staff", TYPE_INT], ["amount", TYPE_FLOAT]],
	&"cast_fizzled": [["caster", TYPE_INT], ["staff", TYPE_INT]],
	&"cast_winding": [["caster", TYPE_INT], ["staff", TYPE_INT], ["carrier_card", TYPE_STRING_NAME], ["origin", TYPE_VECTOR2], ["direction", TYPE_VECTOR2], ["seconds", TYPE_FLOAT], ["tint", TYPE_COLOR], ["look", TYPE_INT], ["tag", TYPE_INT], ["cue", TYPE_STRING_NAME]],
	&"aim_locked": [["caster", TYPE_INT], ["staff", TYPE_INT]],
	&"boss_shown": [["actor", TYPE_INT], ["boss_name", TYPE_STRING], ["lore", TYPE_STRING], ["marks", TYPE_PACKED_FLOAT32_ARRAY], ["has_intro", TYPE_BOOL]],
	&"boss_intro_opened": [["actor", TYPE_INT], ["boss_name", TYPE_STRING], ["lore", TYPE_STRING], ["intro", TYPE_OBJECT], ["page", TYPE_INT], ["fresh", TYPE_BOOL]],
	&"boss_intro_paged": [["page", TYPE_INT]],
	&"boss_intro_closed": [["actor", TYPE_INT]],
	&"boss_health_changed": [["actor", TYPE_INT], ["health", TYPE_FLOAT], ["max_health", TYPE_FLOAT]],
	&"boss_hidden": [["actor", TYPE_INT]],
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
	&"carry_ended": [["caster", TYPE_INT], ["target", TYPE_OBJECT], ["carrier", TYPE_INT], ["way", TYPE_VECTOR2], ["pinned", TYPE_BOOL], ["tag", TYPE_INT]],
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
	&"run_begun": [["run_id", TYPE_STRING_NAME], ["players", TYPE_INT]],
	&"run_room_filled": [["room", TYPE_INT], ["enemies", TYPE_ARRAY], ["scale", TYPE_FLOAT], ["group", TYPE_INT], ["refill_at", TYPE_INT], ["stagger", TYPE_FLOAT]],
	&"run_biome_chosen": [["map", TYPE_OBJECT]],
	&"run_room_scaled": [["scale", TYPE_FLOAT]],
	&"room_left": [["room", TYPE_INT]],
	&"room_entered": [["room_id", TYPE_STRING_NAME], ["room", TYPE_INT]],
	&"room_built": [["room_id", TYPE_STRING_NAME], ["room", TYPE_INT], ["layout_root", TYPE_OBJECT]],
	&"floor_touched": [["caster", TYPE_INT], ["element", TYPE_STRING_NAME], ["at", TYPE_VECTOR2], ["radius", TYPE_FLOAT]],
	&"cover_changed": [["room", TYPE_INT], ["cells", TYPE_PACKED_INT32_ARRAY], ["states", TYPE_PACKED_INT32_ARRAY]],
	&"room_cleared": [["room_id", TYPE_STRING_NAME], ["room", TYPE_INT]],
	&"loading_started": [],
	&"loading_progressed": [["done", TYPE_INT], ["total", TYPE_INT]],
	&"loading_finished": [],
	&"start_stone_changed": [["standing", TYPE_INT], ["wizards", TYPE_INT], ["lit", TYPE_BOOL]],
	&"altar_changed": [["seats", TYPE_INT]],
	&"altar_placed": [["standing", TYPE_BOOL], ["at", TYPE_VECTOR2]],
	&"gather_door_shown": [["door", TYPE_INT], ["rule", TYPE_STRING_NAME], ["area", TYPE_RECT2], ["gathered", TYPE_INT], ["standing", TYPE_INT], ["held", TYPE_BOOL], ["open", TYPE_BOOL]],
	&"key_door_shown": [["door", TYPE_INT], ["area", TYPE_RECT2], ["open", TYPE_BOOL]],
	&"secret_rock_shown": [["rock", TYPE_INT], ["area", TYPE_RECT2], ["element", TYPE_STRING_NAME], ["broken", TYPE_BOOL]],
	&"hub_changed": [["in_hub", TYPE_BOOL]],
	&"door_voted": [["player", TYPE_INT], ["door", TYPE_INT]],
	&"difficulty_changed": [["level", TYPE_FLOAT]],
	# Rewards and progression.
	&"reward_rolled": [["player", TYPE_INT], ["offer", TYPE_INT], ["choices", TYPE_ARRAY], ["here", TYPE_BOOL]],
	&"reward_taken": [["player", TYPE_INT], ["offer", TYPE_INT], ["choice", TYPE_INT], ["reward", TYPE_DICTIONARY]],
	&"reward_refused": [["player", TYPE_INT], ["offer", TYPE_INT]],
	&"rewards_waiting_changed": [["player", TYPE_INT], ["offers", TYPE_ARRAY]],
	&"coin_changed": [["coin", TYPE_INT], ["at", TYPE_VECTOR2], ["lying", TYPE_BOOL]],
	&"wallet_changed": [["player", TYPE_INT], ["coins", TYPE_INT]],
	&"run_stats_ruled": [["changes", TYPE_ARRAY]],
	&"health_gift_requested": [["actor", TYPE_INT], ["heal", TYPE_FLOAT], ["more_most", TYPE_FLOAT]],
	&"unlock_gained": [["unlock_id", TYPE_STRING_NAME]],
	&"currency_changed": [["currency_id", TYPE_STRING_NAME], ["amount", TYPE_INT]],
}

## Events about the run, a room or the account, with no seat and no actor.
const NOT_PER_PLAYER: Array[StringName] = [
	&"run_started", &"run_ended", &"run_begun", &"run_room_filled", &"run_biome_chosen", &"run_room_scaled", &"run_stats_ruled", &"coin_changed", &"room_left", &"gather_door_shown", &"key_door_shown", &"secret_rock_shown", &"room_entered", &"room_built", &"cover_changed", &"room_cleared", &"start_stone_changed", &"altar_changed", &"altar_placed", &"hub_changed", &"pad_wait_changed",
	&"room_items_placed", &"ground_item_changed", &"enemy_standing", &"boss_intro_paged",
	&"hit_room_asked", &"hit_damage_asked",
	&"loading_started", &"loading_progressed", &"loading_finished",
	&"play_load_requested", &"online_changed", &"online_line_changed", &"effect_slots_changed", &"screen_shake_changed", &"damage_numbers_changed", &"projectile_cap_changed", &"mote_cap_changed", &"mote_density_changed", &"floor_marks_changed", &"spell_light_changed", &"shadows_changed", &"ambient_particles_changed", &"fog_changed", &"environment_interaction_changed", &"ambience_volume_changed", &"music_volume_changed", &"sound_volume_changed", &"ui_volume_changed", &"ui_sound_requested", &"tailless_motes_changed", &"difficulty_changed", &"unlock_gained", &"currency_changed",
]

## The names of a first argument that is a seat (`player`) or an actor id (the rest).
const FIRST_KEYS: Array[String] = ["player", "caster", "actor", "killer"]

var received: Array[int] = []


func before_each() -> void:
	received.clear()


func _on_player(player: int) -> void:
	received.append(player)


## The signals events.gd declares, as name -> its argument list.
func _signals() -> Dictionary[StringName, Array]:
	var signals: Dictionary[StringName, Array] = {}
	var script: Script = EventsScript
	for info: Dictionary in script.get_script_signal_list():
		signals[StringName(info["name"])] = info["args"]
	return signals


func test_the_events_autoload_is_registered() -> void:
	var path: String = str(ProjectSettings.get_setting("autoload/Events", ""))
	check_equal(path, "*res://core/events/events.gd", "autoload Events is registered")


func test_every_listed_event_exists() -> void:
	var signals: Dictionary[StringName, Array] = _signals()
	for event: StringName in EVENTS:
		check(signals.has(event), "signal %s exists" % event)


func test_every_event_takes_its_listed_arguments() -> void:
	var signals: Dictionary[StringName, Array] = _signals()
	for event: StringName in EVENTS:
		if not signals.has(event):
			continue
		var expected: Array = EVENTS[event]
		var args: Array = signals[event]
		check(args.size() == expected.size(), "%s takes %d arguments, got %d" % [event, expected.size(), args.size()])
		for i in mini(args.size(), expected.size()):
			check(args[i]["name"] == expected[i][0] and args[i]["type"] == expected[i][1],
				"%s argument %d is %s (type %d), got %s (type %d)" % [event, i, expected[i][0], expected[i][1], args[i]["name"], args[i]["type"]])


func test_an_event_has_a_seat_or_actor_first_exactly_when_it_is_per_player() -> void:
	for event: StringName in EVENTS:
		var expected: Array = EVENTS[event]
		var has_player: bool = not NOT_PER_PLAYER.has(event)
		var first: String = "" if expected.is_empty() else expected[0][0]
		check(has_player == FIRST_KEYS.has(first),
			"%s has a seat or an actor id first exactly when it is per-player or per-actor" % event)


func test_every_signal_in_events_is_listed_here() -> void:
	for event: StringName in _signals():
		check(EVENTS.has(event), "signal %s in events.gd is covered by this test" % event)


func test_no_player_is_outside_the_seats_and_actor_ids() -> void:
	check_equal(EventsScript.NO_PLAYER, -1, "NO_PLAYER is -1, outside the seats and the actor ids")


func test_play_requested_reaches_a_listener_for_every_seat() -> void:
	var bus: Node = own(EventsScript.new())
	bus.play_requested.connect(_on_player)
	for player in 4:
		bus.play_requested.emit(player)
	check_equal(received, [0, 1, 2, 3] as Array[int], "play_requested reaches the listener for players 0-3")


func test_player_events_keep_the_player_index() -> void:
	var bus: Node = own(EventsScript.new())
	bus.player_downed.connect(_on_player)
	bus.player_joined.connect(_on_player)
	for player in 4:
		bus.player_downed.emit(player)
		bus.player_joined.emit(player)
	check_equal(received, [0, 0, 1, 1, 2, 2, 3, 3] as Array[int], "player events keep the player index")
