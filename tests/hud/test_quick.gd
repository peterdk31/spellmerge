extends "res://tests/support/suite.gd"
## Tests for the quick view and the quick actions (M2 part 18): the active spell on the corner
## panel, a `swap` press turned into `spell_swap_requested`, the builder folding into the quick
## view when a wave starts (and back when it is cleared), and "Bag" in the quick view
## and the overlay. The wizards are real (real registry and spell runtime), so a request is
## checked and answered as in the game. Several players at once is the point of some tests.
##
## godot --headless --path . --script res://tests/hud/test_quick.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const BuilderScript := preload("res://hud/builder/builder.gd")
const OverlayScript := preload("res://hud/panels/overlay/overlay.gd")
const DropChoicesScript := preload("res://hud/widgets/drop_choices.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

const STEP: float = 0.0625
const BOLT_FIRE: Dictionary = {"form": &"bolt", "element": &"fire"}
const BOLT: Dictionary = {"form": &"bolt"}
const ROOM: StringName = &"test_room"

var _registry: RegistryScript
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _mgr: ManagerScript
var _spells: SpellsScript
var _hud: HudScript
var _players: Array[PlayerScript] = []
## Every build_change_requested as [player, path, slot, id].
var _requests: Array = []
## Every spell_swap_requested player.
var _swaps: Array[int] = []


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_players.clear()
	_requests.clear()
	_swaps.clear()
	_bus.build_change_requested.connect(func(player: int, path: PackedInt32Array, slot: int, id: StringName) -> void: _requests.append([player, path, slot, id]))
	_bus.spell_swap_requested.connect(func(player: int) -> void: _swaps.append(player))
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = _spells
	root.add_child(_hud)


## `count` players with a device and a wizard (spell A bolt + fire, B bolt), joined, in a room.
func _start(count: int) -> void:
	for index in count:
		_input.add_virtual_device(index)
		var player := own(PlayerScript.new()) as PlayerScript
		player.index = index
		player.input = _input
		player.events = _bus
		player.registry = _registry
		player.projectiles = _mgr
		player.spells = _spells
		player.start_recipe_a = BOLT_FIRE
		player.start_recipe_b = BOLT
		player._ready()
		_players.append(player)
		_bus.player_joined.emit(index)
	_bus.room_entered.emit(ROOM)


func _tap(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 1.0)
	_input.send_virtual(player, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()
	for player in _players:
		player.step(STEP)


func _builder(player: int) -> BuilderScript:
	return _hud.get_builder(player)


func _overlay(player: int) -> OverlayScript:
	return _hud.get_overlay(player)


func _wave_start(wave: int = 1) -> void:
	_bus.wave_started.emit(wave)


func _wave_end() -> void:
	_bus.room_cleared.emit(ROOM)


## Open the builder the way a person does: the overlay, then "Build".
func _open_builder(player: int) -> void:
	_tap(player, &"overlay")
	_frame()
	_tap(player, &"move_down")
	_frame()
	_tap(player, &"cast")
	_frame()


## Press move_down for `player` until `control` is focused. False if it never was.
func _focus_on(player: int, control: Control) -> bool:
	for _attempt in 40:
		if _focus.focused(player) == control:
			return true
		_tap(player, &"move_down")
		_frame()
	return _focus.focused(player) == control


func _press(player: int, control: Control) -> void:
	check(_focus_on(player, control), "player %d can reach %s" % [player + 1, control.name])
	_tap(player, &"cast")
	_frame()


func _row_named(rows: Array[Button], display_name: String) -> Button:
	for row in rows:
		if row.text.trim_prefix(BuilderScript.FOCUS_MARK).begins_with(display_name):
			return row
	return null


# --- The corner panel and swap ------------------------------------------------

func test_the_corner_panel_shows_the_active_spell() -> void:
	_start(2)
	check_equal(_hud.get_panel(0).spell_text().strip_edges(), "Spell A", "a wizard starts on spell A")
	_bus.active_spell_changed.emit(1, 1)
	check_equal(_hud.get_panel(1).spell_text().strip_edges(), "Spell B", "player 2 swapped to B")
	check_equal(_hud.get_panel(0).spell_text().strip_edges(), "Spell A", "player 1 is not affected")
	_bus.run_ended.emit(false)
	check_equal(_hud.get_panel(1).spell_text().strip_edges(), "Spell A", "a run's end clears it back to A")


func test_a_wizard_that_starts_on_b_says_so() -> void:
	var player := own(PlayerScript.new()) as PlayerScript
	player.index = 2
	player.events = _bus
	player.registry = _registry
	player.projectiles = _mgr
	player.spells = _spells
	player.start_recipe_b = BOLT
	player._ready()
	check_equal(_hud.get_panel(2).active_spell(), 1, "the panel follows the wizard's first announcement")


func test_the_panel_ignores_a_bad_slot() -> void:
	_start(1)
	_bus.active_spell_changed.emit(0, 5)
	check_equal(_hud.get_panel(0).active_spell(), 0, "slot 5 is not a spell")


func test_a_swap_press_becomes_a_request_and_the_wizard_swaps() -> void:
	_start(1)
	_tap(0, &"swap")
	_frame()
	check_equal(_swaps, [0] as Array[int], "one press sent one request for player 1")
	check_equal(_players[0].active_slot, 1, "the wizard swapped to B")
	check_equal(_hud.get_panel(0).spell_text().strip_edges(), "Spell B", "and the panel says so")
	_tap(0, &"swap")
	_frame()
	check_equal(_hud.get_panel(0).spell_text().strip_edges(), "Spell A", "a second press goes back to A")


func test_each_player_swaps_alone() -> void:
	_start(4)
	_tap(2, &"swap")
	_frame()
	check_equal(_swaps, [2] as Array[int], "only player 3's press sent a request")
	for player in 4:
		check_equal(_players[player].active_slot, 1 if player == 2 else 0, "player %d active slot" % (player + 1))
		check_equal(_hud.get_panel(player).active_spell(), 1 if player == 2 else 0, "panel %d" % (player + 1))
	for player in 4:
		_tap(player, &"swap")
	_frame()
	check_equal(_swaps.size(), 5, "four more presses, four more requests")
	for player in 4:
		check_equal(_players[player].active_slot, 0 if player == 2 else 1, "everyone has swapped once more")


func test_no_swap_request_in_a_menu_outside_a_room_or_when_down() -> void:
	_start(3)
	_tap(0, &"overlay")
	_frame()
	_tap(0, &"swap")
	_frame()
	check(_swaps.is_empty(), "swap in the overlay asks for nothing (it is captured like cast)")
	_bus.player_stats_changed.emit(1, 0, 100, 50.0, 50.0)
	_tap(1, &"swap")
	_frame()
	check(_swaps.is_empty(), "a downed player asks for nothing")
	_bus.run_started.emit(3)
	_tap(2, &"swap")
	_frame()
	check(_swaps.is_empty(), "outside a room nothing is asked")
	_bus.room_entered.emit(ROOM)
	_frame()
	check(_swaps.is_empty(), "and the press is not kept for later")


func test_a_player_without_a_device_cannot_swap() -> void:
	_start(1)
	_tap(3, &"swap")
	_frame()
	check(_swaps.is_empty(), "player 4 has no device")


func test_the_hud_sends_swap_requests_only() -> void:
	var source: String = FileAccess.get_file_as_string("res://hud/panels/panels.gd")
	check(source.contains("spell_swap_requested.emit"), "the panels send the request")
	for other in ["active_spell_changed.emit", "recipe_changed.emit", "build_refused.emit"]:
		check(not source.contains(other), "the panels never send %s" % other)


# --- The quick view -----------------------------------------------------------

func test_a_wave_folds_an_open_builder_into_the_quick_view() -> void:
	_start(1)
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	check(not builder.is_quick(), "a builder opened in a break is the full one")
	check(builder.tab_button(0).is_visible_in_tree() and builder.up_button().is_visible_in_tree(), "which has tabs and held levels")
	_wave_start()
	check(builder.is_quick() and builder.is_open(), "the wave folds it, still open")
	check(not builder.tab_button(0).is_visible_in_tree() and not builder.tab_button(1).is_visible_in_tree(), "the tabs are gone")
	check(not builder.up_button().is_visible_in_tree() and not builder.held_button().is_visible_in_tree(), "so are the held levels")
	check(not builder.info_panel().is_visible_in_tree(), "and the info panel")
	check(builder.drop_button().is_visible_in_tree(), "\"Bag\" is there")
	check(builder.close_button().is_visible_in_tree(), "and Close")
	check(builder.slot_button(BuilderScript.SLOT_FORM).text.contains("Bolt"), "the chain is still shown")
	check(builder.slot_button(BuilderScript.SLOT_ELEMENT).disabled, "but read only")
	var reachable: Array[Control] = []
	for control in builder.controls():
		if control.is_visible_in_tree():
			reachable.append(control)
	check_equal(reachable, [builder.drop_button(), builder.close_button()] as Array[Control], "the controls that can be reached are Drop and Close")
	check(_focus.focused(0) == builder.drop_button(), "focus is on \"Bag\"")
	check(builder.drop_button().text.begins_with(BuilderScript.FOCUS_MARK), "marked by text")
	check(_focus.is_open(0) and _input.is_captured(0), "the owner still holds focus and stands still")
	check(not paused, "the wave is never paused")


func test_the_quick_view_shows_a_hint_for_the_focused_control() -> void:
	_start(1)
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	var label: Label = builder.find_child("QuickHint", true, false) as Label
	check(label != null and not label.is_visible_in_tree(), "the full builder has the hint in its info panel instead")
	_wave_start()
	check(label.is_visible_in_tree(), "the quick view shows a hint line")
	check_equal(label.text, BuilderScript.HINT_DROP, "on Bag it says what Cast does")
	_focus_on(0, builder.close_button())
	check_equal(label.text, BuilderScript.HINT_CLOSE, "on Close it follows the focus")
	_wave_end()
	check(not label.is_visible_in_tree(), "the hint line goes with the quick view")
	_wave_start(2)
	_tap(0, &"dodge")
	_frame()
	_open_builder(0)
	check_equal(label.text, BuilderScript.HINT_DROP, "a builder opened in a wave has the hint at once")


## The focus mark ("> ") is on one control only: folding must not leave it on a slot that the
## quick view shows read only (it showed "> [F: Bolt]" beside "> Bag").
func _marked(builder: BuilderScript) -> Array[Button]:
	var marked: Array[Button] = []
	for slot in BuilderScript.SLOT_COUNT:
		var button: Button = builder.slot_button(slot)
		if button.text.begins_with(BuilderScript.FOCUS_MARK):
			marked.append(button)
	if builder.drop_button().text.begins_with(BuilderScript.FOCUS_MARK):
		marked.append(builder.drop_button())
	return marked


func test_folding_leaves_one_focus_mark_and_unfolding_too() -> void:
	_start(1)
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	check_equal(_marked(builder), [builder.slot_button(BuilderScript.SLOT_FORM)] as Array[Button], "the full builder opens marked on the form slot")
	_wave_start()
	check_equal(_marked(builder), [builder.drop_button()] as Array[Button], "folded: only \"Bag\" is marked")
	_wave_end()
	check_equal(_marked(builder), [builder.slot_button(BuilderScript.SLOT_FORM)] as Array[Button], "unfolded: back on the form slot, no mark left on Drop")
	check(_focus.focused(0) == builder.slot_button(BuilderScript.SLOT_FORM), "and focus is there")


func test_folding_with_nothing_to_drop_puts_focus_on_close() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	for name_to_drop in ["Split", "Pierce", "Bigger"]:
		_press(0, _row_named(builder.shown_rows(), name_to_drop))
	_wave_end()
	_wave_start(2)
	check(builder.is_quick() and builder.drop_button().disabled, "a full spell folds with \"Bag\" greyed")
	check(_focus.focused(0) == builder.close_button(), "focus is on Close, not on a greyed button")
	check_equal(_marked(builder), [] as Array[Button], "no read-only slot is marked")


func test_the_quick_view_unfolds_when_the_wave_is_cleared_and_keeps_the_choices() -> void:
	_start(1)
	_open_builder(0)
	_wave_start()
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	_press(0, _row_named(builder.shown_rows(), "Split"))
	check_equal(_players[0].recipe_of(0).get("modifiers"), [&"split"], "a component dropped during the wave")
	_wave_end()
	check(not builder.is_quick() and builder.is_open(), "the cleared wave unfolds it, still open")
	check(builder.tab_button(0).is_visible_in_tree() and builder.info_panel().is_visible_in_tree(), "the full view is back")
	check(builder.slot_button(BuilderScript.SLOT_FIRST_MODIFIER).text.contains("Split"), "with the choice kept")
	check(not builder.slot_button(BuilderScript.SLOT_ELEMENT).disabled, "and the slots work again")
	check(not builder.drop_button().visible, "\"Bag\" is only the quick view's")
	check(builder.controls().has(builder.tab_button(0)), "the tabs are controls again")
	check(builder.controls().size() > 4, "UIFocus has the full list")


func test_a_builder_opened_during_a_wave_is_the_quick_view_of_the_active_spell() -> void:
	_start(1)
	_tap(0, &"swap")
	_frame()
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	check(builder.is_open() and builder.is_quick(), "opened quick")
	check_equal(builder.viewed_spell(), 1, "it shows the active spell, B")
	check(builder.slot_button(BuilderScript.SLOT_FORM).text.contains("Bolt"), "the chain of B")
	check(not builder.slot_button(BuilderScript.SLOT_ELEMENT).text.contains("Fire"), "which has no element")


func test_a_swap_while_in_the_quick_view_follows_the_active_spell() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	check(builder.is_dropping(), "the list is open")
	_bus.spell_swap_requested.emit(0)
	check_equal(builder.viewed_spell(), 1, "the quick view moved to B")
	check(not builder.is_dropping(), "and the drop list closed, since it was for A")
	check(builder.is_open(), "still open")


func test_the_builder_state_resets_with_the_run() -> void:
	_start(1)
	_wave_start()
	check(_hud.is_wave_active() and _builder(0).is_quick(), "a wave is on")
	_bus.run_ended.emit(false)
	check(not _hud.is_wave_active() and not _builder(0).is_quick(), "the run's end clears it")


# --- Bag in the quick view -----------------------------------------

func test_drop_component_lists_what_fits_a_free_slot() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	check(builder.is_dropping(), "activating it shows the list")
	var ids: Array[StringName] = builder.row_ids()
	check(not ids.has(&"fire") and not ids.has(&"frost"), "spell A has an element already, so no element is offered")
	check(not ids.has(&"nova") and not ids.has(&"on_hit"), "forms and triggers are not offered")
	for id in [&"split", &"pierce", &"homing", &"chain", &"bigger", &"faster"]:
		check(ids.has(id), "the modifier %s is offered" % id)
	for slot in builder.row_slots():
		check_equal(slot, BuilderScript.SLOT_FIRST_MODIFIER, "into the first free modifier slot")
	check(builder.shown_rows().has(_focus.focused(0)), "focus moved to the first component")


func test_dropping_a_component_sends_one_request_for_the_active_spell() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	_press(0, _row_named(builder.shown_rows(), "Pierce"))
	check_equal(_requests.size(), 1, "one request")
	check_equal(_requests[0], [0, PackedInt32Array([0]), BuilderScript.SLOT_FIRST_MODIFIER, &"pierce"], "player 1, spell A, the first modifier slot, pierce")
	check_equal(_players[0].recipe_of(0).get("modifiers"), [&"pierce"], "the wizard built it")
	check(builder.slot_button(BuilderScript.SLOT_FIRST_MODIFIER).text.contains("Pierce"), "the chain shows it")


func test_the_next_drop_goes_to_the_next_free_slot_until_all_are_full() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	_press(0, _row_named(builder.shown_rows(), "Split"))
	check(builder.is_dropping(), "the list stays open for the next one")
	check_equal(builder.row_slots()[0], BuilderScript.SLOT_FIRST_MODIFIER + 1, "the second modifier slot is next")
	_press(0, _row_named(builder.shown_rows(), "Pierce"))
	_press(0, _row_named(builder.shown_rows(), "Bigger"))
	check_equal(_players[0].recipe_of(0).get("modifiers"), [&"split", &"pierce", &"bigger"], "three modifiers in order")
	check(not builder.is_dropping(), "with every slot full the list is over")
	check(builder.drop_button().disabled, "\"Bag\" is greyed")
	check(_focus.focused(0) == builder.close_button(), "and focus is on Close")
	check_equal(_requests.size(), 3, "three requests, no more")


func test_spell_b_offers_an_element_and_modifiers() -> void:
	_start(1)
	_tap(0, &"swap")
	_frame()
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	var ids: Array[StringName] = builder.row_ids()
	check(ids.has(&"frost") and ids.has(&"split"), "B has no element yet: an element and modifiers are offered")
	_press(0, _row_named(builder.shown_rows(), "Frost"))
	check_equal(_requests[0][1], PackedInt32Array([1]), "the request names spell B")
	check_equal(_requests[0][2], BuilderScript.SLOT_ELEMENT, "the element slot")
	check_equal(_players[0].recipe_of(1).get("element"), &"frost", "B got its element")
	check(not builder.row_ids().has(&"storm"), "elements are no longer offered")
	check_equal(_players[0].recipe_of(0), BOLT_FIRE, "spell A is untouched")


func test_cancel_goes_back_from_the_list_then_closes() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	_tap(0, &"dodge")
	_frame()
	check(builder.is_open() and not builder.is_dropping(), "cancel on a component leaves the list, the builder stays")
	check(_focus.focused(0) == builder.drop_button(), "focus is on \"Bag\" again")
	_tap(0, &"dodge")
	_frame()
	check(not builder.is_open(), "cancel there closes it")


func test_the_list_offers_only_what_the_player_owns() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_bus.bag_changed.emit(0, [&"split", &"bolt"] as Array[StringName])
	_press(0, builder.drop_button())
	check_equal(builder.row_ids(), [&"split"] as Array[StringName], "only the owned modifier is offered")


func test_a_bag_that_shrinks_ends_the_list() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.drop_button())
	_bus.bag_changed.emit(0, [&"bolt", &"fire"] as Array[StringName])
	check(not builder.is_dropping(), "nothing fits any more: the list is over")
	check(builder.drop_button().disabled, "and the button is greyed")
	check(builder.is_open(), "the builder stays open")


func test_four_quick_views_work_at_once_each_for_its_owner() -> void:
	_start(4)
	_wave_start()
	for player in 4:
		_open_builder(player)
	for player in 4:
		check(_builder(player).is_open() and _builder(player).is_quick(), "builder %d is a quick view" % (player + 1))
	var names: Array[String] = ["Split", "Pierce", "Homing", "Chain"]
	for player in 4:
		var builder: BuilderScript = _builder(player)
		_press(player, builder.drop_button())
		_press(player, _row_named(builder.shown_rows(), names[player]))
	var expected: Array = [&"split", &"pierce", &"homing", &"chain"]
	for player in 4:
		check_equal(_players[player].recipe_of(0).get("modifiers"), [expected[player]], "player %d got their own" % (player + 1))
	var senders: Array[int] = []
	for request in _requests:
		senders.append(request[0] as int)
	senders.sort()
	check_equal(senders, [0, 1, 2, 3] as Array[int], "one request from each player")


## Spell B has no element, so its list is the longest: every element and every modifier.
func test_four_quick_views_with_their_longest_lists_fit_the_screen() -> void:
	_start(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_tap(player, &"swap")
	_frame()
	_wave_start()
	for player in 4:
		_open_builder(player)
		_press(player, _builder(player).drop_button())
	check_equal(_builder(0).row_ids().size(), 10, "the longest list has ten components")
	await process_frame
	await process_frame
	var screen := Rect2(0, 0, 640, 360)
	var rects: Array[Rect2] = []
	var names: Array[String] = []
	for player in 4:
		rects.append(_hud.get_panel(player).get_global_rect())
		names.append("panel %d" % (player + 1))
		rects.append(_builder(player).get_global_rect())
		names.append("builder %d" % (player + 1))
	for i in rects.size():
		check(screen.encloses(rects[i]), "%s is inside the 640x360 view, got %s" % [names[i], rects[i]])
		for j in range(i + 1, rects.size()):
			check(not rects[i].intersects(rects[j]), "%s and %s do not overlap, got %s and %s" % [names[i], names[j], rects[i], rects[j]])


func test_four_overlays_with_their_longest_lists_fit_the_screen() -> void:
	_start(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_tap(player, &"swap")
		_tap(player, &"overlay")
	_frame()
	for player in 4:
		_press(player, _overlay(player).drop_button())
	check_equal(_overlay(0).row_ids().size(), 10, "the longest list has ten components")
	await process_frame
	await process_frame
	var screen := Rect2(0, 0, 640, 360)
	var rects: Array[Rect2] = []
	var names: Array[String] = []
	for player in 4:
		rects.append(_hud.get_panel(player).get_global_rect())
		names.append("panel %d" % (player + 1))
		rects.append(_overlay(player).get_global_rect())
		names.append("overlay %d" % (player + 1))
	for i in rects.size():
		check(screen.encloses(rects[i]), "%s is inside the 640x360 view, got %s" % [names[i], rects[i]])
		for j in range(i + 1, rects.size()):
			check(not rects[i].intersects(rects[j]), "%s and %s do not overlap, got %s and %s" % [names[i], names[j], rects[i], rects[j]])


func test_the_quick_view_is_narrower_than_the_full_builder() -> void:
	_start(1)
	_open_builder(0)
	await process_frame
	var full: float = _builder(0).size.x
	_wave_start()
	await process_frame
	var quick: float = _builder(0).size.x
	check(quick < full, "the quick view (%s) is narrower than the full builder (%s)" % [quick, full])
	_wave_end()
	await process_frame
	check_equal(_builder(0).size.x, full, "and the full width is back")


# --- Bag in the overlay --------------------------------------------

func test_the_overlay_drops_a_component_during_a_wave() -> void:
	_start(1)
	_wave_start()
	_tap(0, &"overlay")
	_frame()
	var overlay: OverlayScript = _overlay(0)
	check(overlay.is_open(), "the overlay opens in a wave")
	_press(0, overlay.drop_button())
	check(overlay.is_dropping() and not overlay.shown_rows().is_empty(), "\"Bag\" lists the components")
	check(not overlay.row_ids().has(&"fire"), "no element for A, which has one")
	_press(0, _row_named(overlay.shown_rows(), "Homing"))
	check_equal(_requests.size(), 1, "one request")
	check_equal(_requests[0], [0, PackedInt32Array([0]), BuilderScript.SLOT_FIRST_MODIFIER, &"homing"], "for spell A, first modifier slot")
	check_equal(_players[0].recipe_of(0).get("modifiers"), [&"homing"], "built")
	check(overlay.is_open() and overlay.is_dropping(), "the overlay stays open on the shorter list")
	check_equal(overlay.row_slots()[0], BuilderScript.SLOT_FIRST_MODIFIER + 1, "the next one goes to the next slot")


func test_the_overlay_drop_follows_the_active_spell() -> void:
	_start(1)
	_tap(0, &"swap")
	_frame()
	_tap(0, &"overlay")
	_frame()
	var overlay: OverlayScript = _overlay(0)
	_press(0, overlay.drop_button())
	check(overlay.row_ids().has(&"fire"), "B has no element: elements are offered")
	_press(0, _row_named(overlay.shown_rows(), "Storm"))
	check_equal(_requests[0][1], PackedInt32Array([1]), "the request names spell B")
	check_equal(_players[0].recipe_of(1).get("element"), &"storm", "B has it")


func test_the_overlay_cancel_leaves_the_list_then_closes() -> void:
	_start(1)
	_tap(0, &"overlay")
	_frame()
	var overlay: OverlayScript = _overlay(0)
	_press(0, overlay.drop_button())
	_tap(0, &"dodge")
	_frame()
	check(overlay.is_open() and not overlay.is_dropping(), "cancel on a component leaves the list")
	check(_focus.focused(0) == overlay.drop_button(), "focus is back on the button")
	_tap(0, &"dodge")
	_frame()
	check(not overlay.is_open(), "and cancel there closes the overlay")


func test_a_full_spell_greys_out_the_overlay_drop() -> void:
	_start(1)
	_players[0].set_recipe(1, {"form": &"bolt", "element": &"frost", "modifiers": [&"split", &"pierce", &"bigger"]})
	_tap(0, &"swap")
	_frame()
	_tap(0, &"overlay")
	_frame()
	check(_overlay(0).drop_button().disabled, "nothing fits a free slot: the button is disabled")
	check(_focus.focused(0) != _overlay(0).drop_button(), "focus skips it")


func test_four_overlays_drop_at_once() -> void:
	_start(4)
	for player in 4:
		_tap(player, &"overlay")
	_frame()
	for player in 4:
		_press(player, _overlay(player).drop_button())
	for player in 4:
		_press(player, _overlay(player).shown_rows()[player])
	var senders: Array[int] = []
	for request in _requests:
		senders.append(request[0] as int)
	senders.sort()
	check_equal(senders, [0, 1, 2, 3] as Array[int], "one request from each player")
	for request in _requests:
		check_equal(request[1], PackedInt32Array([0]), "all for spell A")


func test_the_action_is_called_bag_and_its_list_says_drop() -> void:
	_start(1)
	_wave_start()
	_tap(0, &"overlay")
	_frame()
	var overlay: OverlayScript = _overlay(0)
	check(overlay.drop_button().text.ends_with("Bag"), "the overlay action is \"Bag\"")
	check_equal(overlay.get_node("%Title").text, "P1 MENU", "the menu is titled MENU")
	_press(0, overlay.drop_button())
	check_equal(overlay.get_node("%Title").text, "P1 Drop", "the open list is titled Drop")
	_tap(0, &"dodge")
	_frame()
	check_equal(overlay.get_node("%Title").text, "P1 MENU", "back from the list it is MENU again")
	_tap(0, &"dodge")
	_frame()
	_open_builder(0)
	var builder: BuilderScript = _builder(0)
	check(builder.is_quick() and builder.drop_button().text.ends_with("Bag"), "the quick view action is \"Bag\"")
	_press(0, builder.drop_button())
	check_equal((builder.find_child("Title", true, false) as Label).text, "P1 Drop", "the quick view's open list is titled Drop")


func test_bag_opens_in_combat_for_one_player() -> void:
	_bag_opens(1, true)


func test_bag_opens_in_combat_for_four_players() -> void:
	_bag_opens(4, true)


func test_bag_opens_in_a_room_for_one_player() -> void:
	_bag_opens(1, false)


func test_bag_opens_in_a_room_for_four_players() -> void:
	_bag_opens(4, false)


func _bag_opens(players: int, in_wave: bool) -> void:
	_start(players)
	if in_wave:
		_wave_start()
	for player in players:
		_tap(player, &"overlay")
	_frame()
	for player in players:
		var overlay: OverlayScript = _overlay(player)
		check(overlay.is_open(), "%d players: overlay %d opens (wave: %s)" % [players, player, in_wave])
		_press(player, overlay.drop_button())
		check(overlay.is_dropping() and not overlay.shown_rows().is_empty(), "%d players: the Bag list of player %d opens (wave: %s)" % [players, player, in_wave])
		_press(player, overlay.shown_rows()[0])
	var senders: Array[int] = []
	for request in _requests:
		senders.append(request[0] as int)
	senders.sort()
	var expected: Array[int] = []
	for player in players:
		expected.append(player)
	check_equal(senders, expected, "%d players: one drop request from each" % players)


func test_build_from_the_overlay_in_a_wave_opens_the_quick_view() -> void:
	_start(1)
	_wave_start()
	_open_builder(0)
	check(_builder(0).is_open() and _builder(0).is_quick(), "Build during a wave gives the quick view")
	check(not _overlay(0).is_open(), "in place of the overlay")


# --- The helper ---------------------------------------------------------------

func test_drop_choices_pick_the_free_slot_by_kind() -> void:
	check_equal(DropChoicesScript.free_slot_for({}, &"element"), 1, "an empty element slot")
	check_equal(DropChoicesScript.free_slot_for({"element": &"fire"}, &"element"), -1, "a filled one")
	check_equal(DropChoicesScript.free_slot_for({}, &"modifier"), 2, "the first modifier slot")
	check_equal(DropChoicesScript.free_slot_for({"modifiers": [&"a", &"b"]}, &"modifier"), 4, "the third after two")
	check_equal(DropChoicesScript.free_slot_for({"modifiers": [&"a", &"b", &"c"]}, &"modifier"), -1, "none after three")
	check_equal(DropChoicesScript.free_slot_for({}, &"form"), -1, "forms are not dropped")
	check_equal(DropChoicesScript.free_slot_for({}, &"trigger"), -1, "nor triggers")


func test_drop_choices_match_the_wizards_slots() -> void:
	check_equal(DropChoicesScript.SLOT_ELEMENT, PlayerScript.SLOT_ELEMENT, "element slot")
	check_equal(DropChoicesScript.SLOT_FIRST_MODIFIER, PlayerScript.SLOT_FIRST_MODIFIER, "first modifier slot")
	check_equal(DropChoicesScript.MAX_MODIFIERS, SpellLimits.MAX_MODIFIERS, "the modifier limit")


func test_the_quick_actions_send_only_build_change_requested() -> void:
	for path in ["res://hud/panels/overlay/overlay.gd", "res://hud/widgets/drop_choices.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		for other in ["spell_swap_requested.emit", "recipe_changed.emit", "bag_changed.emit", "spell_changed.emit"]:
			check(not source.contains(other), "%s never sends %s" % [path, other])
		check(not source.contains("res://gameplay"), "%s never loads anything from gameplay" % path)
