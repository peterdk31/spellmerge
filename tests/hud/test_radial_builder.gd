extends "res://tests/support/suite.gd"
## Tests for the radial builder in hud/builder (owner, 2026-10-26): opened with B when the pause
## menu's Sandbox page picked it, the right stick picks a card on the ring (with a rumble), RT
## puts it in the marked slot (pushing the rest right, or replacing), LT takes a card out (an
## undo past the last card), holding Y clears the staff, LB and RB switch staffs, the left stick
## moves the marker, the d-pad flips the kind with the one-kind ring, and the numbers show the
## mana share and what RT would change. The wizards are real (the real registry and spell
## runtime, the 20-slot dev staff), so every request is answered as in the game.
##
## godot --headless --path . --script res://tests/hud/test_radial_builder.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

const STEP: float = 0.0625
const START: Array = [[&"dash"], [&"fire", &"bolt"], [], []]

var _registry: RegistryScript
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _mgr: ManagerScript
var _spells: SpellsScript
var _hud: HudScript
## The world the wizards live in (its services are the ones below).
var _world: WizardFixture
var _players: Array[Actor] = []
## Every rumble as [device, weak, strong, seconds].
var _rumbles: Array = []
## Every staff_cards_requested as [player, staff, cards].
var _whole: Array = []
## Every staff_change_requested as [player, staff, slot, id].
var _single: Array = []


func before_each() -> void:
	# The wizard fixture's world: the real registry and spell runtime, its own bus and input.
	_world = WizardFixture.new(root)
	_registry = own(_world.registry) as RegistryScript
	_bus = own(_world.bus) as EventsScript
	_input = own(_world.input) as InputManagerScript
	_input.vibrator = func(device: int, weak: float, strong: float, seconds: float) -> void: _rumbles.append([device, weak, strong, seconds])
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_mgr = own(_world.projectiles) as ManagerScript
	_spells = own(_world.spells) as SpellsScript
	own(_world.combat)
	own(_world.table)
	_players.clear()
	_rumbles.clear()
	_whole.clear()
	_single.clear()
	_bus.staff_cards_requested.connect(func(player: int, staff: int, cards: Array[StringName]) -> void: _whole.append([player, staff, cards.duplicate()]))
	_bus.staff_change_requested.connect(func(player: int, staff: int, slot: int, id: StringName) -> void: _single.append([player, staff, slot, id]))
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = _spells
	root.add_child(_hud)
	# The pause menu's Sandbox page picked the radial builder, every card on the ring, push.
	_hud.call("_on_builder_options_changed", true, false, true)


## `count` players with a virtual device and a wizard (the start cards on the dev staff), in a room.
func _start(count: int) -> void:
	for index in count:
		_input.add_virtual_device(index)
		# A real wizard actor (actors G7), seated as flow seats it and in the tree.
		var player := own(_world.wizard(index, Vector2.ZERO, START, _registry.get_resource(&"wizard", &"dev") as StaffBase)) as Actor
		_players.append(player)
		_bus.player_joined.emit(index)
	_bus.room_entered.emit(&"test_room")


func _tap(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 1.0)
	_input.send_virtual(player, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()
	for player in 4:
		_radial(player).step(STEP)
	for player in _players:
		player.step(STEP)


func _radial(player: int) -> RadialScript:
	return _hud.get_radial(player)


func _open(player: int) -> RadialScript:
	_tap(player, &"back")
	_frame()
	return _radial(player)


## Point `player`'s right stick at card `id` and keep holding it there (letting go lets the card go).
func _point(player: int, id: StringName) -> void:
	var direction: Vector2 = _radial(player).direction_to(id)
	check(direction != Vector2.ZERO, "%s is on the ring" % id)
	_input.send_virtual_aim(player, direction)
	_frame()


## Let go of `player`'s right stick.
func _let_go(player: int) -> void:
	_input.send_virtual_aim(player, Vector2.ZERO)
	_frame()


func _ids(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(&"" if word == "-" else StringName(word))
	return out


func test_b_opens_the_radial_on_staff_2_after_its_last_card() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	check(radial.is_open(), "B opens the radial builder")
	check(not _hud.get_builder(0).is_open(), "not the list builder")
	check_equal(radial.viewed_staff(), 1, "staff 2 (the fire bolt)")
	check_equal(radial.marked_slot(), 2, "the marker sits after the last card")
	check(_input.is_captured(0), "the wizard stands still while building")


func test_the_ring_holds_every_card_once_grouped_by_kind() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var entries: Array[Dictionary] = radial.ring_entries()
	check_equal(entries.size(), PlayerController.of(_players[0]).bag.size(), "every card of the bag")
	var last: int = 0
	for entry in entries:
		var order: int = RadialScript.KINDS.find(entry["kind"])
		check(order >= last, "%s is in kind order" % entry["id"])
		last = order
		check_equal(int(entry["count"]), 1, "one of each in a plain bag")
		check_equal(radial.direction_to(entry["id"]).is_zero_approx(), false, "%s can be pointed at" % entry["id"])


## Every real card in the registry, found by the registry's own scan (so a new card folder is
## checked with no list to edit): on the ring, picked exactly by the stick, with its name, kind
## and at least one line of numbers in the hub.
func test_every_real_card_can_be_picked_and_shows_its_numbers() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var cards: Array[StringName] = []
	for id: StringName in _registry.get_ids(&"spells"):
		if _registry.get_resource(&"spells", id) is SpellComponent:
			cards.append(id)
	check(cards.size() >= 20, "the registry found the cards (%d)" % cards.size())
	check_equal(radial.ring_entries().size(), cards.size(), "each real card has one place on the ring")
	for id in cards:
		_input.send_virtual_aim(0, radial.direction_to(id))
		_frame()
		check_equal(radial.pointed_id(), id, "the stick picks %s" % id)
		var lines: PackedStringArray = radial.hub_lines()
		check_equal(lines[0], _spells.component_name(id), "%s: its name in the hub" % id)
		check_equal(lines[1], String(RadialScript.KIND_WORDS.get(_spells.component_kind(id), "")), "%s: its kind" % id)
		check(lines.size() > 2, "%s: at least one line of its numbers" % id)
	check_equal(_rumbles.size(), cards.size(), "one rumble per card landed on")


func test_the_right_stick_picks_a_card_with_a_rumble() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_point(0, &"nova")
	check_equal(radial.pointed_id(), &"nova", "the stick picked the nova")
	check_equal(_rumbles.size(), 1, "landing on it rumbles once")
	check_equal(int(_rumbles[0][0]), InputManagerScript.virtual_device_id(0), "the player's own pad")
	check_equal(radial.hub_lines()[0], "Nova", "the hub shows its name")
	check_equal(radial.hub_lines()[1], "Carrier", "and its kind")
	check(radial.hub_lines().size() > 2 and radial.hub_lines()[2].begins_with("Dmg"), "and its numbers")
	_input.send_virtual_aim(0, radial.direction_to(&"nova"))
	_frame()
	check_equal(_rumbles.size(), 1, "staying on the same card does not rumble again")


func test_letting_go_of_the_stick_lets_the_card_go_and_shows_the_staff() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_point(0, &"nova")
	check_equal(radial.pointed_id(), &"nova", "pointed while held")
	_let_go(0)
	check_equal(radial.pointed_id(), &"", "letting go picks nothing")
	check_equal(radial.hub_lines()[0], "Staff 2", "the hub shows the staff's numbers again")
	var asked: int = _single.size() + _whole.size()
	_tap(0, &"staff_2")
	_frame()
	check_equal(_single.size() + _whole.size(), asked, "RT with nothing picked asks for nothing")


func test_rt_puts_the_card_in_and_moves_the_marker_on() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_point(0, &"nova")
	_tap(0, &"staff_2")
	_frame()
	check_equal(_single, [[0, 1, 2, &"nova"]], "an empty slot takes the card")
	check_equal(radial.cards_of(1).slice(0, 3), _ids("fire bolt nova"), "the player answered")
	check_equal(radial.marked_slot(), 3, "the marker moved on")
	check(_rumbles.size() >= 2, "putting a card in rumbles")
	_tap(0, &"staff_2")
	_frame()
	check_equal(radial.cards_of(1).slice(0, 4), _ids("fire bolt nova nova"), "a held stick keeps the card picked for the next slot")


func test_rt_on_a_card_pushes_the_rest_right_or_replaces_it() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	radial.mark_slot(1)
	_point(0, &"frost")
	_tap(0, &"staff_2")
	_frame()
	check_equal(_whole.size(), 1, "a push is one whole-staff request")
	check_equal(radial.cards_of(1).slice(0, 4), _ids("fire frost bolt -"), "the bolt moved one slot right")
	radial.put = RadialScript.Put.REPLACE
	radial.mark_slot(0)
	_point(0, &"void")
	_tap(0, &"staff_2")
	_frame()
	check_equal(radial.cards_of(1).slice(0, 3), _ids("void frost bolt"), "with replace, the card is swapped out")


func test_a_full_staff_refuses_a_push() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var full: Array[StringName] = []
	for _slot in _players[0].caster.slot_count():
		full.append(&"bolt")
	_bus.staff_cards_requested.emit(0, 1, full)
	radial.mark_slot(0)
	_point(0, &"fire")
	var asked: int = _whole.size()
	_tap(0, &"staff_2")
	_frame()
	check_equal(_whole.size(), asked, "nothing is asked")
	check_equal(radial.note_text(), RadialScript.FULL_NOTE, "the note says why")


func test_lt_takes_a_card_out_and_closes_the_gap() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	radial.mark_slot(0)
	check_equal(radial.lt_action(), RadialScript.LT_TAKE, "LT takes the fire out")
	_tap(0, &"staff_4")
	_frame()
	check_equal(radial.cards_of(1).slice(0, 2), _ids("bolt -"), "the bolt closed the gap")
	check_equal(radial.marked_slot(), 0, "the marker stays")


func test_lt_past_the_last_card_is_an_undo() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_point(0, &"nova")
	_tap(0, &"staff_2")
	_frame()
	_point(0, &"split")
	_tap(0, &"staff_2")
	_frame()
	check_equal(radial.marked_slot(), 4, "after two picks the marker is past them")
	check_equal(radial.lt_action(), RadialScript.LT_UNDO, "LT is an undo there")
	check_equal(radial.hint_verbs()[1], RadialScript.UNDO_VERB, "and the hint says so")
	_tap(0, &"staff_4")
	_frame()
	check_equal(radial.cards_of(1).slice(0, 4), _ids("fire bolt nova -"), "the last card came out")
	check_equal(radial.marked_slot(), 3, "the marker stepped back to it")
	_tap(0, &"staff_4")
	_frame()
	_tap(0, &"staff_4")
	_frame()
	_tap(0, &"staff_4")
	_frame()
	check(radial.cards_of(1).all(func(id: StringName) -> bool: return id == &""), "undo all the way empties the staff")
	check_equal(radial.lt_action(), &"", "and then LT has nothing to do")


func test_holding_y_clears_the_staff_once() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_input.send_virtual(0, &"extra", 1.0)
	_frame()
	check_equal(radial.cards_of(1).slice(0, 2), _ids("fire bolt"), "a short press does nothing yet")
	for _i in ceili(RadialScript.CLEAR_HOLD / STEP) + 1:
		_frame()
	check(radial.cards_of(1).all(func(id: StringName) -> bool: return id == &""), "held long enough, the staff is clear")
	check_equal(radial.marked_slot(), 0, "the marker goes back to the start")
	var asked: int = _whole.size()
	for _i in 20:
		_frame()
	check_equal(_whole.size(), asked, "one clear per hold")
	_input.send_virtual(0, &"extra", 0.0)


func test_lb_rb_switch_staffs_and_the_left_stick_moves_the_marker() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_tap(0, &"page_prev")
	_frame()
	check_equal(radial.viewed_staff(), 0, "LB shows staff 1")
	check_equal(radial.marked_slot(), 1, "after its dash")
	_tap(0, &"page_next")
	_frame()
	_tap(0, &"page_next")
	_frame()
	check_equal(radial.viewed_staff(), 2, "RB twice shows staff 3")
	check_equal(radial.marked_slot(), 0, "an empty staff starts at its first slot")
	_input.send_virtual(0, &"move_right", 1.0)
	_frame()
	check_equal(radial.marked_slot(), 1, "right moves one slot at once")
	for _i in ceili((RadialScript.MOVE_DELAY + RadialScript.MOVE_REPEAT) / STEP) + 1:
		_frame()
	check(radial.marked_slot() >= 3, "held, it repeats")
	_input.send_virtual(0, &"move_right", 0.0)
	_frame()
	var at: int = radial.marked_slot()
	_input.send_virtual(0, &"move_down", 1.0)
	_frame()
	_input.send_virtual(0, &"move_down", 0.0)
	check_equal(radial.marked_slot(), at + RadialScript.SLOT_COLUMNS, "down moves one row")
	check(not _players[0].caster.has_staff(2), "the move keys never walked or cast anything")


func test_the_one_kind_ring_flips_with_the_dpad() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	radial.layout = RadialScript.Layout.KIND
	check_equal(radial.shown_kind(), &"form", "carriers first")
	check(radial.ring_entries().all(func(entry: Dictionary) -> bool: return entry["kind"] == &"form"), "the ring holds only carriers")
	_tap(0, &"kind_next")
	_frame()
	check_equal(radial.shown_kind(), &"modifier", "right shows the modifiers")
	check(radial.direction_to(&"split") != Vector2.ZERO and radial.direction_to(&"bolt") == Vector2.ZERO, "only modifiers can be picked")
	_tap(0, &"kind_prev")
	_frame()
	_tap(0, &"kind_prev")
	_frame()
	check_equal(radial.shown_kind(), RadialScript.KINDS[RadialScript.KINDS.find(radial.shown_kind())], "left wraps round")
	check(radial.shown_kind() != &"form", "to the last kind")


func test_the_numbers_show_the_mana_share_and_what_rt_would_change() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var view: Dictionary = _spells.staff_view(_players[0].caster.cards_of(1), _players[0].caster.staff)
	var mana: float = 0.0
	for cast: Dictionary in view["casts"]:
		mana = maxf(mana, float(cast["mana"]))
	var share: int = roundi(mana / _players[0].caster.max_mana * 100.0)
	check_equal(radial.number_lines()[0], "Mana %d%%" % share, "the dearest cast as a share of the wizard's mana")
	check_equal(radial.hub_lines()[0], "Staff 2", "with nothing pointed at, the hub shows the staff")
	_point(0, &"nova")
	check(radial.number_lines()[1].contains(" > "), "a pointed card shows what RT would make of the damage: %s" % radial.number_lines()[1])
	var dear: Array[StringName] = _ids("split split split split split split nova")
	_bus.staff_cards_requested.emit(0, 1, dear)
	check(radial.number_lines()[0].get_slice(" > ", 0).ends_with("!"), "a cast dearer than all the mana is marked: %s" % radial.number_lines()[0])


func test_a_bag_with_several_of_a_card_counts_them() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var bag: Array[StringName] = PlayerController.of(_players[0]).bag.duplicate()
	bag.append(&"bolt")
	bag.append(&"bolt")
	_bus.bag_changed.emit(0, bag)
	var bolts: Array[Dictionary] = radial.ring_entries().filter(func(entry: Dictionary) -> bool: return entry["id"] == &"bolt")
	check_equal(bolts.size(), 1, "one place on the ring")
	check_equal(int(bolts[0]["count"]), 3, "counted three times")


func test_four_radials_open_at_once_each_for_its_own_player() -> void:
	_start(4)
	for player in 4:
		_open(player)
	for player in 4:
		check(_radial(player).is_open(), "player %d's radial is open" % (player + 1))
	_point(2, &"orbit")
	_tap(2, &"staff_2")
	_frame()
	for player in 4:
		var expected: Array[StringName] = _ids("fire bolt orbit") if player == 2 else _ids("fire bolt -")
		check_equal(_radial(player).cards_of(1).slice(0, 3), expected, "player %d's staff" % (player + 1))
		check_equal(_radial(player).pointed_id(), &"orbit" if player == 2 else &"", "player %d's pointer" % (player + 1))
	_tap(1, &"back")
	_frame()
	check(not _radial(1).is_open() and _radial(0).is_open() and _radial(3).is_open(), "B closes only its owner's")


func test_the_slots_frame_each_cast_of_the_cycle() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	# The dev staff draws one carrier a cast: fire bolt, then frost nova.
	_bus.staff_cards_requested.emit(0, 1, _ids("fire bolt frost nova"))
	var groups: PackedInt32Array = radial.slot_groups()
	check_equal(Array(groups.slice(0, 5)), [0, 0, 1, 1, -1], "two casts of two cards, and an empty slot in none")
	_bus.staff_cards_requested.emit(0, 1, _ids("fire bolt"))
	check_equal(Array(radial.slot_groups().slice(0, 3)), [0, 0, -1], "one cast after an edit")


func test_pointing_at_a_card_shows_the_casts_as_rt_would_leave_them() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	radial.mark_slot(1)
	_point(0, &"nova")
	# Pushed in after the fire: the fire now infuses the nova, and the bolt is a cast of its own.
	check_equal(Array(radial.slot_groups().slice(0, 4)), [0, 0, 1, -1], "the preview's casts while pointing")
	check_equal(radial.cards_of(1).slice(0, 3), _ids("fire bolt -"), "the staff itself is unchanged")
	_let_go(0)
	check_equal(Array(radial.slot_groups().slice(0, 3)), [0, 0, -1], "the staff's own casts again after letting go")


## A fake clipboard for `player`'s radial: a Dictionary {"text": ...} it reads and writes.
func _clipboard(player: int) -> Dictionary:
	var board: Dictionary = {"text": ""}
	var radial: RadialScript = _radial(player)
	radial.clipboard_get = func() -> String: return str(board["text"])
	radial.clipboard_set = func(text: String) -> void: board["text"] = text
	return board


func test_x_copies_the_shown_staff_as_a_code_and_says_so() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var board: Dictionary = _clipboard(0)
	_tap(0, &"alternate")
	_frame()
	check_equal(board["text"], "sm1:fire,bolt", "the staff's code is on the clipboard")
	check_equal(radial.result_text(), "Copied 2 cards", "the row says what was copied")
	_bus.staff_cards_requested.emit(0, 1, _ids("-"))
	board["text"] = "kept"
	_tap(0, &"alternate")
	_frame()
	check_equal(board["text"], "kept", "an empty staff copies nothing")
	check_equal(radial.result_text(), RadialScript.NOTHING_TO_COPY, "and says so")


func test_a_pastes_the_clipboards_code_over_the_staff() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var board: Dictionary = _clipboard(0)
	board["text"] = "sm1:double,fire,-,bolt"
	_tap(0, &"accept")
	_frame()
	check_equal(radial.cards_of(1).slice(0, 5), _ids("double fire - bolt -"), "all the slots at once")
	check_equal(radial.result_text(), "Pasted 3 cards", "the row says how many cards")
	check_equal(_whole.size(), 1, "one request for the whole staff")
	board["text"] = "sm1:fire"
	_tap(0, &"accept")
	_frame()
	check_equal(radial.result_text(), "Pasted 1 card", "one card is not plural")
	for _step in int(RadialScript.RESULT_TIME / STEP) + 2:
		_frame()
	check_equal(radial.result_text(), "", "the result goes after a few seconds")


func test_a_refused_paste_changes_nothing_and_says_why() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var board: Dictionary = _clipboard(0)
	var before: Array[StringName] = radial.cards_of(1)
	for text: String in ["hello", "sm1:fire,nosuchcard", "sm1:" + ",".join(PackedStringArray(["fire"])) + ",fire".repeat(40)]:
		board["text"] = text
		_tap(0, &"accept")
		_frame()
		check(radial.result_text() != "", "a result for %s" % text.left(12))
		check_equal(radial.cards_of(1), before, "the staff is unchanged for %s" % text.left(12))
	check_equal(_whole.size(), 0, "nothing was asked for")
	board["text"] = ""
	_tap(0, &"accept")
	_frame()
	check_equal(radial.result_text(), RadialScript.CLIPBOARD_EMPTY, "an empty clipboard is named")
	board["text"] = "sm1:fire"
	_bus.staff_cards_requested.connect(func(player: int, _staff: int, _cards: Array[StringName]) -> void: _bus.build_refused.emit(player, "You do not have that card."))
	_tap(0, &"accept")
	_frame()
	check_equal(radial.result_text(), "You do not have that card.", "the player's own refusal is the result")


func test_the_names_of_the_casts_show_for_each_cast() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_bus.staff_cards_requested.emit(0, 1, _ids("fire bolt frost nova"))
	var names: PackedStringArray = radial.cast_names()
	check_equal(names.size(), 2, "a name for each of the two casts")
	for word in names:
		check(word != "", "the name is not empty")
	_bus.staff_cards_requested.emit(0, 1, _ids("fire bolt"))
	check_equal(radial.cast_names().size(), 1, "one cast, one name")
	_bus.staff_cards_requested.emit(0, 1, _ids("-"))
	check_equal(radial.cast_names().size(), 0, "no cast, no name")


func test_a_code_with_only_gaps_clears_the_staff_and_says_so() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var board: Dictionary = _clipboard(0)
	board["text"] = "sm1:-"
	_tap(0, &"accept")
	_frame()
	check_equal(radial.cards_of(1).slice(0, 3), _ids("- - -"), "the staff is emptied")
	check_equal(radial.result_text(), RadialScript.CLEARED, "and the row says so, not 'Pasted 0 cards'")


func test_copy_and_paste_work_for_the_last_seat_and_stay_off_the_others() -> void:
	_start(4)
	var first: RadialScript = _open(0)
	var last: RadialScript = _open(3)
	var board_first: Dictionary = _clipboard(0)
	var board_last: Dictionary = _clipboard(3)
	_bus.staff_cards_requested.emit(3, 1, _ids("frost nova"))
	_tap(0, &"alternate")
	_frame()
	check_equal(board_first["text"], "sm1:fire,bolt", "X for player 1 copies player 1's staff")
	check_equal(board_last["text"], "", "and not player 4's")
	check_equal(last.result_text(), "", "player 4's row is quiet")
	_tap(3, &"alternate")
	_frame()
	check_equal(board_last["text"], "sm1:frost,nova", "X for player 4 copies player 4's staff")
	board_last["text"] = "sm1:double,fire"
	_tap(3, &"accept")
	_frame()
	check_equal(last.cards_of(1).slice(0, 3), _ids("double fire -"), "A pastes into player 4's staff")
	check_equal(last.result_text(), "Pasted 2 cards", "player 4's row says so")
	check_equal(first.cards_of(1).slice(0, 3), _ids("fire bolt -"), "player 1's staff is untouched")
	_bus.build_refused.emit(3, "You do not have that card.")
	check_equal(first.result_text(), "Copied 2 cards", "player 4's refusal does not replace player 1's row")
	check_equal(first.note_text(), "", "nor become a note there")
