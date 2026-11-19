extends "res://tests/support/suite.gd"
## A seat's key count beside its corner panel's coins (the owner, 2026-11-19;
## `hud/widgets/key_count.gd`): Smooth (docs/STYLE.md), each change a play of at least 3 poses moved
## by whole pixels, the first key sliding in, one more nodding up, one spent dipping and the last
## sinking out. `panels.gd` tells each panel the keys in its seat's shown body's currency bag.
const KeyCountScript := preload("res://hud/widgets/key_count.gd")
const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"


func _count() -> KeyCountScript:
	var keys := own(KeyCountScript.new()) as KeyCountScript
	keys.full_size = Vector2(20, 9)
	return keys


## The offsets of each pose of the play running, and the count shown at each, till it rests.
func _poses(keys: KeyCountScript) -> Array:
	var out: Array = []
	var guard: int = 0
	while keys.playing() != KeyCountScript.Play.NONE and guard < 100:
		out.append([keys.offset(), keys.shown_count()])
		keys.advance(KeyCountScript.POSE_TIME)
		guard += 1
	out.append([keys.offset(), keys.shown_count()])
	return out


## Every step between two poses is a move of whole pixels, never a jump past the play's own height.
func _check_smooth(poses: Array, what: String) -> void:
	check(poses.size() >= 4, "%s: at least 3 poses before it rests (%s)" % [what, poses])
	var distinct: Dictionary = {}
	for pose: Array in poses:
		distinct[pose[0]] = true
	check(distinct.size() >= 3, "%s: at least 3 looks (%s)" % [what, poses])
	for at in range(1, poses.size()):
		if poses[at][1] == 0:
			# Out of view: nothing is drawn.
			continue
		check(absi(poses[at][0] - poses[at - 1][0]) <= 3, "%s: pose %d moves by a few pixels (%s)" % [what, at, poses])


func test_the_first_key_slides_in_and_more_nod_and_the_last_sinks_out() -> void:
	var keys: KeyCountScript = _count()
	check(not keys.visible, "no key: hidden")
	keys.set_count(1, false)
	check(keys.visible, "shown as the first key is taken")
	var appear: Array = _poses(keys)
	_check_smooth(appear, "appear")
	check(appear[0][0] > 0, "it starts below, cut by its edge (%s)" % [appear])
	check_equal(appear.back(), [0, 1], "it rests in place showing 1")
	keys.set_count(2, false)
	var gain: Array = _poses(keys)
	_check_smooth(gain, "one more")
	check(gain[1][0] < 0, "one more nods up (%s)" % [gain])
	check_equal(gain.back(), [0, 2], "then shows 2")
	keys.set_count(1, false)
	var spend: Array = _poses(keys)
	_check_smooth(spend, "one spent")
	check(spend[1][0] > 0, "one spent dips (%s)" % [spend])
	check_equal(spend.back(), [0, 1], "then shows 1")
	keys.set_count(0, false)
	check_equal(keys.shown_count(), 1, "the last key's number stays while it sinks")
	var leave: Array = _poses(keys)
	_check_smooth(leave, "the last spent")
	check_equal(leave.back()[1], 0, "and is 0 once it is out of view")
	check(not keys.visible, "then it hides")


func test_a_change_during_a_play_waits_and_a_restore_is_drawn_at_once() -> void:
	var keys: KeyCountScript = _count()
	keys.set_count(1, false)
	keys.advance(KeyCountScript.POSE_TIME)
	keys.set_count(2, false)
	check_equal(keys.playing(), KeyCountScript.Play.APPEAR, "the slide in plays on")
	for i in KeyCountScript.POSE_COUNT:
		keys.advance(KeyCountScript.POSE_TIME)
	check_equal(keys.playing(), KeyCountScript.Play.GAIN, "then the second key's play")
	check_equal(keys.shown_count(), 2, "showing 2")
	keys.set_count(3, true)
	check_equal(keys.playing(), KeyCountScript.Play.NONE, "a restore: no play")
	check_equal([keys.offset(), keys.shown_count()], [0, 3], "drawn as it stands")
	keys.set_count(0, true)
	check(not keys.visible, "none at once: hidden at once")


## The review's: its room on the row grows and shrinks by whole pixels, never in one jump, so the
## row's height and the coins beside it move in steps.
func test_its_room_on_the_row_grows_and_shrinks_in_steps() -> void:
	var keys: KeyCountScript = _count()
	check_equal(keys.custom_minimum_size, Vector2.ZERO, "no key: no room taken")
	keys.set_count(1, false)
	var rooms: Array[Vector2] = [keys.custom_minimum_size]
	while keys.playing() != KeyCountScript.Play.NONE:
		keys.advance(KeyCountScript.POSE_TIME)
		rooms.append(keys.custom_minimum_size)
	check_equal(rooms.back(), Vector2(20, 9), "all of it at rest")
	for at in rooms.size():
		check(rooms[at] == rooms[at].round(), "whole pixels (%s)" % [rooms])
		if at > 0:
			check(rooms[at].y - rooms[at - 1].y <= 3.0 and rooms[at].y >= rooms[at - 1].y, "grows by steps of a few pixels (%s)" % [rooms])
	check(rooms[0].y > 0.0 and rooms[0].y < 9.0, "starting part way (%s)" % [rooms])
	keys.set_count(0, false)
	var last: float = keys.custom_minimum_size.y
	while keys.playing() != KeyCountScript.Play.NONE:
		keys.advance(KeyCountScript.POSE_TIME)
		check(keys.custom_minimum_size.y <= last and last - keys.custom_minimum_size.y <= 3.0, "shrinks by steps")
		last = keys.custom_minimum_size.y
	check_equal(keys.custom_minimum_size, Vector2.ZERO, "none once it is out of view")


## The review's: a biome laid as the last biome's keys sink out says 0 at once after 0 played: the
## sinking plays on.
func test_the_same_count_at_once_lets_a_play_run() -> void:
	var keys: KeyCountScript = _count()
	keys.set_count(2, true)
	keys.set_count(0, false)
	keys.set_count(0, true)
	check_equal(keys.playing(), KeyCountScript.Play.LEAVE, "still sinking")
	check(keys.visible, "and drawn")


func test_each_panel_shows_its_own_bodys_keys() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var input := own(InputManagerScript.new()) as InputManagerScript
	input.events = bus
	var focus := own(UIFocusScript.new()) as UIFocusScript
	focus.input = input
	focus.events = bus
	focus._ready()
	var hud := (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	hud.events = bus
	hud.ui_focus = focus
	hud.input = input
	hud.save = SaveFile.new("user://test_key_count_save.cfg")
	root.add_child(hud)
	own(hud)
	var ids: Array[StringName] = [CoinBase.ID, KeyBase.ID]
	bus.bag_changed.emit(0, &"currency", ids, PackedInt32Array([5, 2]), -1)
	check_equal(hud.get_panel(0).key_count().shown_count(), 2, "panel 0 shows its body's 2 keys")
	check_equal(hud.get_panel(0).purse_text(), "5 coins", "beside its coins, from the same bag")
	for seat in [1, 2, 3]:
		check_equal(hud.get_panel(seat).key_count().shown_count(), 0, "panel %d shows its own body's: none" % seat)
	bus.bag_changed.emit(1, &"currency", [KeyBase.ID] as Array[StringName], PackedInt32Array([1]), -1)
	check_equal(hud.get_panel(1).key_count().shown_count(), 1, "seat 1's one key, on its own panel")
	check_equal(hud.get_panel(0).key_count().shown_count(), 2, "seat 0's unchanged")
	bus.bag_changed.emit(0, &"potions", [] as Array[StringName], PackedInt32Array(), -1)
	check_equal(hud.get_panel(0).key_count().shown_count(), 2, "another bag says nothing of keys")
	# A body shown anew (a possession): the count plays from the last body's to the new one's.
	hud.get_panel(0).key_count().advance(1.0)
	bus.inventory_announced.emit(0, 99)
	check_equal(hud.get_panel(0).key_count().playing(), KeyCountScript.Play.NONE, "the announcement alone changes nothing: the new body's bag follows")
	bus.bag_changed.emit(0, &"currency", [CoinBase.ID] as Array[StringName], PackedInt32Array([3]), -1)
	check_equal(hud.get_panel(0).key_count().playing(), KeyCountScript.Play.LEAVE, "a body with none: the keys sink out, never one jump")
	await process_frame
	check(hud.get_panel(0).key_count().is_processing(), "and steps itself each frame while it plays")
	var keys: KeyCountScript = hud.get_panel(0).key_count()
	check_equal(keys.get_index(), 0, "first on the purse row: its left edge never moves")
