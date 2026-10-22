extends "res://tests/support/suite.gd"
## Tests for the spell builder in hud/builder (M2 part 16): opened from the overlay, driven
## only by its owner's device through core/ui_focus, showing the slot chain and the bag from
## events, and asking for changes with `build_change_requested`. The wizards are real (on the
## real registry and spell runtime), so a request is checked and answered as in the game.
## Four builders open at once is the point of several tests.
##
## godot --headless --path . --script res://tests/hud/test_builder.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const BuilderScript := preload("res://hud/builder/builder.gd")
const PreviewScript := preload("res://hud/builder/spell_preview.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

const STEP: float = 0.0625
const BOLT_FIRE: Dictionary = {"form": &"bolt", "element": &"fire"}
const BOLT: Dictionary = {"form": &"bolt"}

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
## Every build_refused as [player, reason].
var _refused: Array = []


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
	_refused.clear()
	_bus.build_change_requested.connect(func(player: int, path: PackedInt32Array, slot: int, id: StringName) -> void: _requests.append([player, path, slot, id]))
	_bus.build_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))
	# The HUD first, as in the game (the autoload exists before any wizard appears).
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
	_bus.room_entered.emit(&"test_room")


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


## Open player's builder the way a person does: the overlay, then "Build".
func _open(player: int) -> void:
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


## Focus `control` and press cast on it.
func _press(player: int, control: Control) -> void:
	check(_focus_on(player, control), "player %d can reach %s" % [player + 1, control.name])
	_tap(player, &"cast")
	_frame()


func _row_named(builder: BuilderScript, display_name: String) -> Button:
	for row in builder.shown_rows():
		if row.text.trim_prefix(BuilderScript.FOCUS_MARK).begins_with(display_name):
			return row
	return null


## Choose `display_name` in the bag for slot `slot` of `player`'s builder.
func _choose(player: int, slot: int, display_name: String) -> void:
	var builder: BuilderScript = _builder(player)
	_press(player, builder.slot_button(slot))
	var row: Button = _row_named(builder, display_name)
	check(row != null, "the bag shows %s for slot %d" % [display_name, slot])
	if row != null:
		_press(player, row)


# --- Opening ----------------------------------------------------------------

func test_the_builder_opens_from_the_overlay() -> void:
	_start(1)
	check(not _builder(0).is_open() and not _builder(0).visible, "the builder starts closed and hidden")
	_open(0)
	check(_builder(0).is_open() and _builder(0).visible, "Build opens it")
	check(_focus.is_open(0) and _input.is_captured(0), "it holds the owner's focus and input")
	check(not _hud.get_overlay(0).is_open(), "in place of the overlay")
	check_equal(_hud.get_panel(0).status_text(), "MENU", "the corner panel says MENU")


func test_the_overlay_action_closes_the_builder() -> void:
	_start(1)
	_open(0)
	_tap(0, &"overlay")
	_frame()
	check(not _builder(0).is_open() and not _builder(0).visible, "the builder is closed")
	check(not _focus.is_open(0) and not _input.is_captured(0), "the owner is free again")


func test_close_and_cancel_close_the_builder() -> void:
	_start(2)
	_open(0)
	_press(0, _builder(0).close_button())
	check(not _builder(0).is_open(), "the Close entry closes it")
	_open(1)
	_tap(1, &"dodge")
	_frame()
	check(not _builder(1).is_open(), "cancel on a control that is not a bag row closes it")


func test_cancel_on_a_bag_row_goes_back_to_its_slot() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(BuilderScript.SLOT_ELEMENT))
	check(builder.shown_rows().has(_focus.focused(0)), "choosing a slot moves focus to its bag")
	_tap(0, &"dodge")
	_frame()
	check(builder.is_open(), "cancel on a bag row keeps the builder open")
	check_equal(_focus.focused(0), builder.slot_button(BuilderScript.SLOT_ELEMENT), "and focuses the slot again")


func test_the_builder_closes_when_its_owner_goes_down_or_the_run_ends() -> void:
	_start(2)
	_open(0)
	_open(1)
	_bus.player_stats_changed.emit(0, 0, 100, 50.0, 50.0)
	check(not _builder(0).is_open(), "going down closes it")
	check(_builder(1).is_open(), "a teammate's builder stays open")
	_bus.run_ended.emit(false)
	check(not _builder(1).is_open() and not _focus.is_open(1), "the end of the run closes it")


func test_the_builder_never_pauses_the_game() -> void:
	_start(1)
	_open(0)
	check(not paused, "the tree is not paused while a builder is open")


func test_the_focused_control_is_marked_with_text() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	var focused: Button = _focus.focused(0) as Button
	check(focused != null and focused.text.begins_with(BuilderScript.FOCUS_MARK), "the focused control starts with the mark, got %s and text '%s'" % [focused, focused.text if focused != null else ""])
	var marked: int = 0
	for control in builder.controls():
		if (control as Button).text.begins_with(BuilderScript.FOCUS_MARK):
			marked += 1
	check_equal(marked, 1, "only one control is marked")
	check(builder.slot_button(BuilderScript.SLOT_FORM).text.contains("["), "the selected slot is shown in brackets")


# --- What it shows ----------------------------------------------------------

func test_the_chain_shows_the_recipe_by_name() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check(builder.slot_button(BuilderScript.SLOT_FORM).text.contains("Bolt"), "the form slot names the form")
	check(builder.slot_button(BuilderScript.SLOT_ELEMENT).text.contains("Fire"), "the element slot names the element")
	check(builder.slot_button(BuilderScript.SLOT_TRIGGER).text.contains(BuilderScript.EMPTY_SLOT_TEXT), "an empty slot is shown as empty")


func test_a_slot_offers_only_components_that_fit_it() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	for slot in BuilderScript.SLOT_COUNT:
		if builder.slot_button(slot).disabled:
			continue
		_press(0, builder.slot_button(slot))
		var ids: Array[StringName] = builder.row_ids()
		check(not ids.is_empty(), "slot %d offers something" % slot)
		for id in ids:
			if id == &"":
				continue
			var component := _registry.get_resource(&"spells", id) as SpellComponent
			check_equal(component.kind(), BuilderScript.SLOT_KINDS[slot], "%s fits slot %d" % [id, slot])


func test_a_filled_slot_offers_none_and_marks_the_current_component() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(BuilderScript.SLOT_ELEMENT))
	check_equal(builder.row_ids()[0], &"", "None comes first for a filled element slot")
	check(_row_named(builder, "Fire").text.ends_with(BuilderScript.CURRENT_MARK), "the current element is marked")
	_press(0, builder.slot_button(BuilderScript.SLOT_FORM))
	check(not builder.row_ids().has(&""), "the form slot cannot be emptied")


func test_modifiers_fill_in_order() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check(not builder.slot_button(BuilderScript.SLOT_FIRST_MODIFIER).disabled, "the first free modifier slot can be used")
	check(builder.slot_button(BuilderScript.SLOT_FIRST_MODIFIER + 1).disabled, "the one after it waits")
	_choose(0, BuilderScript.SLOT_FIRST_MODIFIER, "Split")
	check(not builder.slot_button(BuilderScript.SLOT_FIRST_MODIFIER + 1).disabled, "filling one opens the next")


func test_the_bag_comes_from_the_player_not_the_registry() -> void:
	_start(1)
	_bus.bag_changed.emit(0, [&"bolt", &"fire"] as Array[StringName])
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(BuilderScript.SLOT_FORM))
	check_equal(builder.row_ids(), [&"bolt"] as Array[StringName], "only the bolt is offered for the form slot")


# --- What it asks for -------------------------------------------------------

func test_choosing_a_component_sends_a_request_and_the_player_applies_it() -> void:
	_start(1)
	_open(0)
	_choose(0, BuilderScript.SLOT_ELEMENT, "Frost")
	check_equal(_requests.size(), 1, "one request")
	check_equal(_requests[0][0], 0, "it names its owner")
	check_equal(_requests[0][1], PackedInt32Array([0]), "for spell A")
	check_equal(_requests[0][2], BuilderScript.SLOT_ELEMENT, "for the element slot")
	check_equal(_requests[0][3], &"frost", "with the component id")
	check_equal(_players[0].recipe_of(0).get("element"), &"frost", "the player applied it")
	check(_builder(0).slot_button(BuilderScript.SLOT_ELEMENT).text.contains("Frost"), "the chain shows the new element")
	check(_builder(0).is_open(), "the builder stays open")


func test_none_empties_a_slot() -> void:
	_start(1)
	_open(0)
	_choose(0, BuilderScript.SLOT_ELEMENT, "None")
	check_equal(_requests[0][3], &"", "the request carries an empty id")
	check(not _players[0].recipe_of(0).has("element"), "the player emptied the slot")
	check(_builder(0).slot_button(BuilderScript.SLOT_ELEMENT).text.contains(BuilderScript.EMPTY_SLOT_TEXT), "the chain shows it empty")


func test_a_refused_change_leaves_the_chain_alone() -> void:
	_start(1)
	_open(0)
	var before: Dictionary = _builder(0).recipe_of(0)
	# A trigger needs a held spell with a form to be useful, but a held spell with only an
	# element is refused by the compiler: the chain must not show it.
	_choose(0, BuilderScript.SLOT_TRIGGER, "On Hit")
	var builder: BuilderScript = _builder(0)
	_press(0, builder.held_button())
	check_equal(builder.level(), 1, "the held level is shown")
	_choose(0, BuilderScript.SLOT_ELEMENT, "Frost")
	check(not _refused.is_empty(), "the player refused a held spell with no form")
	check(not _players[0].recipe_of(0).has("held"), "so nothing was built")
	check_equal(_builder(0).recipe_of(0).has("held"), false, "and the builder did not pretend it was")
	check(before != _builder(0).recipe_of(0), "only the trigger changed")


func test_the_spell_b_tab_builds_spell_b() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.tab_button(1))
	check_equal(builder.viewed_spell(), 1, "spell B is shown")
	check(builder.slot_button(BuilderScript.SLOT_ELEMENT).text.contains(BuilderScript.EMPTY_SLOT_TEXT), "B has no element")
	_choose(0, BuilderScript.SLOT_ELEMENT, "Storm")
	check_equal(_requests[0][1], PackedInt32Array([1]), "the path is [1]")
	check_equal(_players[0].recipe_of(1).get("element"), &"storm", "spell B got the element")
	check_equal(_players[0].recipe_of(0).get("element"), &"fire", "spell A did not change")


func test_a_held_spell_is_built_one_level_down() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check(builder.held_button().disabled, "without a trigger there is nothing to open")
	_choose(0, BuilderScript.SLOT_TRIGGER, "On Hit")
	check(not builder.held_button().disabled, "with a trigger the held spell can be opened")
	_press(0, builder.held_button())
	check(not builder.up_button().disabled, "and you can go back up")
	_choose(0, BuilderScript.SLOT_FORM, "Nova")
	var held_request: Array = _requests[_requests.size() - 1]
	check_equal(held_request[1], PackedInt32Array([0, 0]), "the path of the held spell is [0, 0]")
	check_equal((_players[0].recipe_of(0).get("held") as Dictionary).get("form"), &"nova", "the held spell has the form")
	_press(0, builder.up_button())
	check_equal(builder.level(), 0, "Up goes back to the spell")
	check_equal(builder.spell_path(), PackedInt32Array([0]), "and its path")


func test_held_spells_go_two_levels_deep_and_no_further() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_choose(0, BuilderScript.SLOT_TRIGGER, "On Hit")
	_press(0, builder.held_button())
	_choose(0, BuilderScript.SLOT_FORM, "Bolt")
	_choose(0, BuilderScript.SLOT_TRIGGER, "On Hit")
	_press(0, builder.held_button())
	check_equal(builder.level(), 2, "two levels down")
	_choose(0, BuilderScript.SLOT_FORM, "Bolt")
	check(builder.slot_button(BuilderScript.SLOT_TRIGGER).disabled, "the deepest level has no trigger slot")
	check(builder.held_button().disabled, "there is no third level to open")
	check_equal(builder.spell_path(), PackedInt32Array([0, 0, 0]), "the path has one 0 per level")


func test_removing_the_trigger_below_closes_the_held_level() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_choose(0, BuilderScript.SLOT_TRIGGER, "On Hit")
	_press(0, builder.held_button())
	# The player's recipe changes from elsewhere (a quick action): the held level is gone.
	_players[0].set_recipe(0, BOLT_FIRE)
	check_equal(builder.level(), 0, "the builder is back at the spell")
	check(builder.held_button().disabled, "and the held spell cannot be opened")


# --- Focus and layout details -----------------------------------------------

func test_focus_stays_on_the_chosen_component_when_rows_shift() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	# An empty modifier slot gains a "None" row at the top once filled.
	_choose(0, BuilderScript.SLOT_FIRST_MODIFIER, "Split")
	var focused: Button = _focus.focused(0) as Button
	check(focused != null and focused.text.contains("Split"), "focus is still on Split after the rows shifted")
	# Emptying the slot removes the "None" row; focus goes to the first row left.
	_press(0, _row_named(builder, "None"))
	focused = _focus.focused(0) as Button
	check(focused != null and builder.shown_rows().has(focused), "focus stays in the bag after emptying a slot")


func test_the_longest_slot_text_fits_when_selected_and_focused() -> void:
	_start(1)
	_open(0)
	var button: Button = _builder(0).slot_button(BuilderScript.SLOT_TRIGGER)
	var font: Font = button.get_theme_font(&"font")
	var size: int = button.get_theme_font_size(&"font_size")
	var room: float = BuilderScript.LEFT_WIDTH - button.get_theme_stylebox(&"normal").get_minimum_size().x
	var longest: String = ""
	for id in _registry.get_ids(&"spells"):
		var component := _registry.get_resource(&"spells", id) as SpellComponent
		if component != null and component.display_name.length() > longest.length():
			longest = component.display_name
	for slot_name in BuilderScript.SLOT_NAMES:
		var text: String = "%s[%s: %s]" % [BuilderScript.FOCUS_MARK, slot_name, longest]
		var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		check(wide <= room, "'%s' is %.0f px wide, the column has %.0f" % [text, wide, room])


func test_the_builder_follows_a_bag_that_grows_while_open() -> void:
	_start(1)
	_bus.bag_changed.emit(0, [&"bolt", &"fire"] as Array[StringName])
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(BuilderScript.SLOT_FORM))
	_bus.bag_changed.emit(0, [&"bolt", &"beam", &"nova", &"rune", &"fire"] as Array[StringName])
	check_equal(builder.row_ids().size(), 4, "four forms are listed")
	check(_focus.is_open(0) and builder.is_open(), "the builder is still open")
	check(_focus_on(0, builder.shown_rows()[3]), "the owner can reach the new last row")
	_tap(0, &"cast")
	_frame()
	check_equal(_requests[_requests.size() - 1][3], &"rune", "and choose it")


# --- Four players -----------------------------------------------------------

func test_four_builders_open_at_once_each_for_its_owner() -> void:
	_start(4)
	for player in 4:
		_open(player)
	for player in 4:
		check(_builder(player).is_open(), "builder %d is open" % (player + 1))
		check(_focus.is_open(player), "player %d holds a focus panel" % (player + 1))
	# Each player picks a different element in their own builder.
	var elements: Array[String] = ["Frost", "Storm", "Void", "Fire"]
	var ids: Array[StringName] = [&"frost", &"storm", &"void", &"fire"]
	for player in 4:
		_choose(player, BuilderScript.SLOT_ELEMENT, elements[player])
	for player in 4:
		check_equal(_players[player].recipe_of(0).get("element"), ids[player], "player %d got their own element" % (player + 1))
	var senders: Array[int] = []
	for request in _requests:
		senders.append(request[0] as int)
	senders.sort()
	check_equal(senders, [0, 1, 2, 3] as Array[int], "each request came from its own player, once")


func test_one_players_buttons_do_not_work_another_builder() -> void:
	_start(4)
	for player in 4:
		_open(player)
	var focus_before: Control = _focus.focused(2)
	for player in [0, 1, 3]:
		_tap(player, &"move_down")
		_tap(player, &"cast")
		_tap(player, &"dodge")
	_frame()
	check(_builder(2).is_open(), "the others' cancel does not close player 3's builder")
	check_equal(_focus.focused(2), focus_before, "the others' movement does not move player 3's focus")
	for request in _requests:
		check(request[0] != 2, "no request names player 3")


func test_a_recipe_event_for_another_player_is_ignored() -> void:
	_start(2)
	_bus.recipe_changed.emit(1, 0, {"form": &"nova"})
	check_equal(_builder(0).recipe_of(0).get("form"), &"bolt", "builder 1 still shows its own spell")
	check_equal(_builder(1).recipe_of(0).get("form"), &"nova", "builder 2 shows the new one")


func test_four_open_builders_fit_the_screen_without_covering_anything() -> void:
	_start(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_open(player)
	# Give every builder its fullest view: a slot with the longest bag open, and a filled chain.
	for player in 4:
		_choose(player, BuilderScript.SLOT_FIRST_MODIFIER, "Split")
		_press(player, _builder(player).slot_button(BuilderScript.SLOT_FIRST_MODIFIER))
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
		check(rects[i].size.x > 0.0 and rects[i].size.y > 0.0, "%s has a size after layout" % names[i])
		check(screen.encloses(rects[i]), "%s is inside the 640x360 view, got %s" % [names[i], rects[i]])
		for j in range(i + 1, rects.size()):
			check(not rects[i].intersects(rects[j]), "%s and %s do not overlap, got %s and %s" % [names[i], names[j], rects[i], rects[j]])


func test_a_builder_stays_on_its_owners_side_of_the_screen() -> void:
	_start(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_builder(player).visible = true
	await process_frame
	await process_frame
	for player in 4:
		var rect: Rect2 = _builder(player).get_global_rect()
		var left_side: bool = player % 2 == 0
		check(rect.end.x <= 320.0 if left_side else rect.position.x >= 320.0, "builder %d stays in its half of the screen, got %s" % [player + 1, rect])
		var top_side: bool = player < 2
		check(rect.end.y <= 180.0 if top_side else rect.position.y >= 180.0, "builder %d stays in its quarter, got %s" % [player + 1, rect])


# --- The contract with the player -------------------------------------------

func test_slot_numbers_match_the_wizard() -> void:
	check_equal(BuilderScript.SLOT_FORM, PlayerScript.SLOT_FORM, "form slot")
	check_equal(BuilderScript.SLOT_ELEMENT, PlayerScript.SLOT_ELEMENT, "element slot")
	check_equal(BuilderScript.SLOT_FIRST_MODIFIER, PlayerScript.SLOT_FIRST_MODIFIER, "first modifier slot")
	check_equal(BuilderScript.SLOT_TRIGGER, PlayerScript.SLOT_TRIGGER, "trigger slot")
	check_equal(BuilderScript.SLOT_KINDS, PlayerScript.SLOT_KINDS, "the kind of every slot")
	check_equal(BuilderScript.MAX_LEVEL, SpellLimits.MAX_DEPTH, "the held depth")


func test_the_builder_sends_no_event_but_build_change_requested() -> void:
	var source: String = FileAccess.get_file_as_string("res://hud/builder/builder.gd")
	check(source.contains("build_change_requested.emit"), "it sends build_change_requested")
	for other in ["spell_swap_requested.emit", "spell_changed.emit", "recipe_changed.emit", "bag_changed.emit", "build_refused.emit"]:
		check(not source.contains(other), "it never sends %s" % other)
	check(not source.contains("res://gameplay"), "it never loads anything from gameplay")


# --- Live stats, complexity, refusal reason, preview, descriptions (part 17) ---

func test_the_complexity_bar_follows_the_whole_spell() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check_equal(builder.complexity_limit(), float(SpellLimits.MAX_COMPLEXITY), "the bar ends at the limit")
	check_equal(builder.complexity_value(), 2.0, "bolt and fire cost 2")
	check_equal(builder.complexity_text(), "Complexity 2/%d" % SpellLimits.MAX_COMPLEXITY, "and the number is in words")
	_choose(0, BuilderScript.SLOT_FIRST_MODIFIER, "Split")
	check_equal(builder.complexity_value(), 4.0, "split adds 2")
	# The held spell counts toward the whole spell, whichever level is shown.
	_choose(0, BuilderScript.SLOT_TRIGGER, "On Hit")
	check_equal(builder.complexity_value(), 5.0, "the trigger adds 1")
	_press(0, builder.held_button())
	_choose(0, BuilderScript.SLOT_FORM, "Nova")
	check_equal(builder.level(), 1, "the held level is shown")
	check_equal(builder.complexity_value(), 7.0, "a held nova adds 2 to the whole spell")
	_press(0, builder.tab_button(1))
	check_equal(builder.complexity_value(), 1.0, "spell B shows its own cost")


func test_the_stats_come_from_the_compiled_spell_shown() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	var plain: Dictionary = _spells.builder_view(builder.recipe_of(0), 0)
	check(builder.stats_text().contains("Dmg %d" % plain["damage"]), "the damage is shown, got '%s'" % builder.stats_text())
	check(builder.stats_text().contains("Shots %d" % plain["shots"]), "the shots are shown")
	check(builder.stats_text().contains("Mana"), "and the mana")
	_choose(0, BuilderScript.SLOT_FIRST_MODIFIER, "Split")
	var split: Dictionary = _spells.builder_view(builder.recipe_of(0), 0)
	check(int(split["shots"]) > int(plain["shots"]), "split makes more shots")
	check(builder.stats_text().contains("Shots %d" % split["shots"]), "the stats follow the change, got '%s'" % builder.stats_text())
	_choose(0, BuilderScript.SLOT_FORM, "Beam")
	check(builder.stats_text().contains("Ray"), "a beam is a ray, not a shot count")
	# The held level shows the held spell's own numbers.
	_choose(0, BuilderScript.SLOT_TRIGGER, "On Hit")
	_press(0, builder.held_button())
	check_equal(builder.stats_text(), BuilderScript.NO_STATS_TEXT, "an empty held spell has no stats")
	_choose(0, BuilderScript.SLOT_FORM, "Nova")
	var held: Dictionary = _spells.builder_view(builder.recipe_of(0), 1)
	check(builder.stats_text().contains("Dmg %d" % held["damage"]), "the held spell's damage is shown, got '%s'" % builder.stats_text())
	var cast: Dictionary = _spells.builder_view(builder.recipe_of(0), 0)
	check(int(held["damage"]) != int(cast["damage"]) or int(held["shots"]) != int(cast["shots"]), "and it is not the cast's numbers")


func test_a_refusal_reason_is_shown_as_text_and_cleared_by_the_next_change() -> void:
	_start(2)
	_open(0)
	_open(1)
	var builder: BuilderScript = _builder(0)
	check_equal(builder.note_text(), "", "nothing is refused at first")
	_choose(0, BuilderScript.SLOT_TRIGGER, "On Hit")
	_press(0, builder.held_button())
	_choose(0, BuilderScript.SLOT_ELEMENT, "Frost")
	check(not _refused.is_empty(), "the player refused it")
	var reason: String = _refused[0][1]
	check(reason != "", "with a reason")
	check_equal(builder.refusal_reason(), reason, "the builder keeps it")
	check_equal(builder.note_text(), BuilderScript.REFUSED_PREFIX + reason, "and shows it as words, with its label")
	check_equal(_builder(1).note_text(), "", "another player's builder shows nothing")
	_choose(0, BuilderScript.SLOT_FORM, "Bolt")
	check_equal(builder.refusal_reason(), "", "a change that works clears it")
	check_equal(builder.note_text(), "", "and the text is gone")


func test_an_over_complex_spell_is_refused_with_the_compilers_reason() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_choose(0, BuilderScript.SLOT_FORM, "Nova")
	_choose(0, BuilderScript.SLOT_FIRST_MODIFIER, "Split")
	_choose(0, BuilderScript.SLOT_FIRST_MODIFIER + 1, "Chain")
	_choose(0, BuilderScript.SLOT_FIRST_MODIFIER + 2, "Homing")
	_choose(0, BuilderScript.SLOT_TRIGGER, "Timer")
	check(_refused.is_empty(), "11 of 12 is still fine")
	_press(0, builder.held_button())
	_choose(0, BuilderScript.SLOT_FORM, "Nova")
	check(not _refused.is_empty(), "a held nova goes over the budget")
	check(builder.note_text().begins_with(BuilderScript.REFUSED_PREFIX + "Too complex"), "the reason says so, got '%s'" % builder.note_text())
	check(builder.complexity_value() <= float(SpellLimits.MAX_COMPLEXITY), "the bar still shows the last built spell")


func test_the_preview_draws_the_pattern_of_the_form() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check_equal(builder.preview_pattern(), "fan", "a bolt")
	var expected: Dictionary = {"Nova": "ring", "Beam": "ray", "Orbit": "orbit", "Rune": "rune", "Bolt": "fan"}
	for form_name: String in expected:
		_choose(0, BuilderScript.SLOT_FORM, form_name)
		check_equal(builder.preview_pattern(), expected[form_name], "the preview of %s" % form_name)


func test_the_preview_caps_the_drawn_shots() -> void:
	var preview := PreviewScript.new()
	var view: Dictionary = {"shown": true, "pattern": "ring", "shots": 99, "spread": 360.0, "tint": Color.RED, "pierce": 0}
	preview.show_view(view)
	check_equal(preview.shots(), PreviewScript.MAX_DRAWN, "99 shots are kept at the cap")
	check_equal(preview.pattern(), "ring", "the pattern is kept")
	check(preview.drawn_limit(6.0) < PreviewScript.MAX_DRAWN, "a small circle draws fewer dots than the cap")
	view["shots"] = 0
	preview.show_view(view)
	check_equal(preview.shots(), 1, "at least one shot")
	preview.show_view({})
	check_equal(preview.pattern(), "none", "no spell draws only the wizard")
	preview.free()


func test_the_description_is_empty_until_the_lore_exists() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(BuilderScript.SLOT_ELEMENT))
	check_equal(builder.note_text(), "", "nothing to say about a component yet")
	check_equal(_spells.component_description(&"fire"), "", "the runtime has no description yet")
	check_equal(_spells.component_description(&"nothing_like_it"), "", "and an unknown id has none")


func test_the_info_panels_of_four_builders_fit_the_screen_beside_everything() -> void:
	_start(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_open(player)
		_choose(player, BuilderScript.SLOT_FIRST_MODIFIER, "Split")
		_press(player, _builder(player).slot_button(BuilderScript.SLOT_FIRST_MODIFIER))
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
		rects.append(_builder(player).info_panel().get_global_rect())
		names.append("info %d" % (player + 1))
	for i in rects.size():
		check(screen.encloses(rects[i]), "%s is inside the 640x360 view, got %s" % [names[i], rects[i]])
		for j in range(i + 1, rects.size()):
			check(not rects[i].intersects(rects[j]), "%s and %s do not overlap, got %s and %s" % [names[i], names[j], rects[i], rects[j]])
	for player in 4:
		var info: Control = _builder(player).info_panel()
		check(info.is_visible_in_tree(), "info %d is shown with its builder" % (player + 1))
		check(info.get_global_rect().size.y <= BuilderScript.INFO_HEIGHT + 0.5, "info %d keeps its size, got %s" % [player + 1, info.get_global_rect()])
	_press(0, _builder(0).close_button())
	check(not _builder(0).info_panel().is_visible_in_tree(), "closing the builder hides its info")
	check(_builder(1).info_panel().is_visible_in_tree(), "another player's stays")


func test_the_info_of_each_player_shows_that_players_spell() -> void:
	_start(4)
	for player in 4:
		_open(player)
	_choose(2, BuilderScript.SLOT_FORM, "Nova")
	check_equal(_builder(2).preview_pattern(), "ring", "player 3 built a nova")
	check_equal(_builder(0).preview_pattern(), "fan", "player 1 still has a bolt")
	check_equal(_builder(3).complexity_value(), 2.0, "player 4's bar is its own")
