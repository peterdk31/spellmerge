extends "res://tests/support/suite.gd"
## Tests for the radial builder in hud/builder (owner, 2026-10-26): opened with B when the pause
## menu's Sandbox page picked it, the right stick picks a card on the ring (with a rumble), RT
## puts it in the marked slot (pushing the rest right, or replacing), LT takes a card out (an
## undo past the last card; held, it clears the staff), LB and RB switch staffs, the left stick
## moves the marker, the d-pad flips the kind with the one-kind ring, the numbers show the mana
## share and what RT would change, and one layout for every quarter (bars, card info, the corner
## panel hidden while it is open). The wizards are real (the real registry and spell
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
const TreeViewScript := preload("res://hud/builder/tree_view.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
## A save no test writes, so a Hud never reads the real `user://save.cfg`.
const NO_SAVE: String = "user://test_no_save.cfg"

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
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = _spells
	root.add_child(_hud)
	# The pause menu's Sandbox page picked the radial builder, every card on the ring, push.
	_hud.call("_on_builder_options_changed", true, 0, true)


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


## Hysteresis: a wobble just past the border between two cards keeps the card pointed (no
## flicker, no second rumble); the neighbour's middle picks the neighbour, and it holds the same way.
func test_a_wobble_past_the_border_keeps_the_card() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var entries: Array[Dictionary] = radial.ring_entries()
	var first: StringName = entries[0]["id"]
	var second: StringName = entries[1]["id"]
	check_equal(entries[1]["kind"], entries[0]["kind"], "two neighbours of one kind, no gap between")
	var a: float = radial.direction_to(first).angle()
	var b: float = radial.direction_to(second).angle()
	var border: float = a + angle_difference(a, b) * 0.5
	var nudge: float = signf(angle_difference(a, b)) * 0.02
	_point(0, first)
	_input.send_virtual_aim(0, Vector2.from_angle(border + nudge))
	_frame()
	check_equal(radial.pointed_id(), first, "a wobble just past the border keeps %s" % first)
	check_equal(_rumbles.size(), 1, "and does not rumble again")
	_point(0, second)
	check_equal(radial.pointed_id(), second, "the neighbour's middle picks %s" % second)
	_input.send_virtual_aim(0, Vector2.from_angle(border - nudge))
	_frame()
	check_equal(radial.pointed_id(), second, "and it holds the same way back")


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


func test_holding_lt_clears_the_staff_once() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	radial.mark_slot(0)
	_input.send_virtual(0, &"staff_4", 1.0)
	_frame()
	check_equal(radial.cards_of(1).slice(0, 2), _ids("bolt -"), "the press takes the marked card out at once")
	for _i in ceili(RadialScript.CLEAR_HOLD / STEP) + 1:
		_frame()
	check(radial.cards_of(1).all(func(id: StringName) -> bool: return id == &""), "held long enough, the rest is cleared")
	check_equal(radial.marked_slot(), 0, "the marker goes back to the start")
	var asked: int = _whole.size()
	for _i in 20:
		_frame()
	check_equal(_whole.size(), asked, "one clear per hold")
	_input.send_virtual(0, &"staff_4", 0.0)
	_frame()


func test_y_no_longer_clears() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_input.send_virtual(0, &"extra", 1.0)
	for _i in ceili(RadialScript.CLEAR_HOLD / STEP) + 2:
		_frame()
	_input.send_virtual(0, &"extra", 0.0)
	_frame()
	check_equal(radial.cards_of(1).slice(0, 2), _ids("fire bolt"), "holding Y leaves the staff")


func test_a_quick_lt_tap_takes_one_card_and_never_clears() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	radial.mark_slot(0)
	_tap(0, &"staff_4")
	for _i in ceili(RadialScript.CLEAR_HOLD / STEP) + 2:
		_frame()
	check_equal(radial.cards_of(1).slice(0, 2), _ids("bolt -"), "only the marked card came out")


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


func test_x_and_a_do_nothing_in_the_builder() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var before: Array[StringName] = radial.cards_of(1)
	_tap(0, &"alternate")
	_tap(0, &"accept")
	_frame()
	check_equal(radial.cards_of(1), before, "no staff code is copied or pasted: the staff is unchanged")
	check_equal(_whole.size(), 0, "nothing was asked for")
	check_equal(radial.note_text(), "", "and nothing is said")
	check(radial.is_open(), "the builder stays open")


func test_the_corner_panel_hides_while_the_radial_is_open() -> void:
	_start(2)
	check(_hud.get_panel(0).visible and _hud.get_panel(1).visible, "both corner panels show in the room")
	_open(0)
	check(not _hud.get_panel(0).visible, "player 1's corner panel is hidden while their radial is open")
	check(_hud.get_panel(1).visible, "player 2's stays")
	_tap(0, &"back")
	_frame()
	check(not _radial(0).is_open(), "B closed it")
	check(_hud.get_panel(0).visible, "and the corner panel is back")


func test_the_bars_follow_the_players_stats() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_bus.player_stats_changed.emit(0, 30.0, 120.0, 25.0, 100.0)
	check(radial.bar_shares().is_equal_approx(Vector2(0.25, 0.25)), "health and mana as shares: %s" % radial.bar_shares())
	_bus.player_stats_changed.emit(1, 0.0, 120.0, 0.0, 100.0)
	check(radial.bar_shares().is_equal_approx(Vector2(0.25, 0.25)), "another player's stats change nothing")


func test_the_card_info_shows_the_marked_card() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	radial.mark_slot(1)
	var info: Dictionary = radial.card_info()
	check_equal(info["id"], &"bolt", "the bolt is under the marker")
	check_equal(info["name"], _spells.component_name(&"bolt"), "its name")
	check_equal(info["kind"], "Carrier", "its kind")
	check(not (info["lines"] as PackedStringArray).is_empty(), "its lore line")
	check_equal(info["stats"], _spells.component_stats(&"bolt"), "its numbers")
	_point(0, &"nova")
	check_equal(radial.card_info()["id"], &"bolt", "pointing at a card on the ring does not change it")
	_let_go(0)
	radial.mark_slot(5)
	check_equal(radial.card_info()["name"], RadialScript.EMPTY_SLOT_TEXT, "an empty slot says so")
	_bus.staff_cards_requested.emit(0, 1, _ids("on_hit bolt nova"))
	radial.mark_slot(0)
	check_equal(radial.card_info()["kind"], "Trigger", "a trigger")
	check((radial.card_info()["stats"] as PackedStringArray).is_empty(), "shows no numbers")


func test_four_quarters_are_laid_out_alike_and_fit_the_view() -> void:
	_start(4)
	for player in 4:
		_open(player)
	var view := Rect2(Vector2.ZERO, _radial(0).get_viewport_rect().size)
	check_equal(view.size, Vector2(640.0, 360.0), "the game's view")
	var all: Array[Dictionary] = []
	for player in 4:
		all.append(_radial(player).layout_parts())
	for player in 4:
		var parts: Dictionary = all[player]
		var quarter: Rect2 = parts["quarter"]
		for key: String in ["column", "bars", "slots", "info", "ring", "hints"]:
			check(quarter.encloses(parts[key] as Rect2), "player %d's %s is inside its quarter: %s in %s" % [player + 1, key, parts[key], quarter])
		check((parts["column"] as Rect2).position - quarter.position == (all[0]["column"] as Rect2).position - (all[0]["quarter"] as Rect2).position, "player %d's column sits where player 1's does" % (player + 1))
		check((parts["ring"] as Rect2).position.x > (parts["column"] as Rect2).end.x, "player %d's ring is right of the column" % (player + 1))
		check(not (parts["ring"] as Rect2).intersects(parts["column"] as Rect2), "player %d's ring and column do not touch" % (player + 1))
		check(not (parts["hints"] as Rect2).intersects(parts["ring"] as Rect2), "player %d's hints are under the ring" % (player + 1))
		check((parts["info"] as Rect2).size.x >= 100.0 and (parts["info"] as Rect2).size.y >= 70.0, "player %d's card info has room: %s" % [player + 1, parts["info"]])


# --- The tree view (docs/milestones/M2-builder-tree.md, part T5) --------------------------------

func test_y_swaps_the_ring_for_the_tree_and_back() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	check(not radial.is_tree_open(), "the ring shows first")
	check_equal(radial.hint_verbs()[2], RadialScript.TREE_VERB, "Y says Tree")
	_tap(0, &"extra")
	_frame()
	check(radial.is_tree_open() and radial.tree_view().visible, "Y opens the tree")
	check_equal(radial.hint_verbs()[2], RadialScript.RING_VERB, "and then says Ring")
	_tap(0, &"extra")
	_frame()
	check(not radial.is_tree_open() and not radial.tree_view().visible, "Y again shows the ring")
	_tap(0, &"extra")
	_frame()
	_tap(0, &"back")
	_frame()
	_frame()
	check(not radial.is_open(), "B closed it")
	_open(0)
	check(radial.is_open() and not radial.is_tree_open(), "it opens on the ring again")


func test_the_tree_rows_come_from_the_staffs_plan() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_bus.staff_cards_requested.emit(0, 1, _ids("on_hit on_expire bolt fire nova frost nova"))
	_tap(0, &"extra")
	_frame()
	var rows: Array[Dictionary] = radial.tree_view().rows()
	check_equal(rows.size(), 3, "the bolt and a row for each trigger")
	if rows.size() == 3:
		check_equal(rows[0]["name"], _spells.component_name(&"bolt"), "the carrier row")
		check(bool(rows[0]["first"]) and int(rows[0]["cast"]) == 0, "the cast's first row")
		check_equal([int(rows[1]["depth"]), int(rows[1]["trigger"]), rows[1]["name"]], [1, 0, _spells.component_name(&"on_hit")], "on hit, one level in")
		check_equal([int(rows[2]["depth"]), int(rows[2]["trigger"]), rows[2]["name"]], [1, 1, _spells.component_name(&"on_expire")], "on expire beside it")
	# An edit while the tree is open shows at once.
	_bus.staff_cards_requested.emit(0, 1, _ids("bolt nova"))
	check_equal(radial.tree_view().rows().size(), 2, "two casts, a row each")


func test_the_marked_card_is_marked_in_the_tree_and_a_tile_marks_its_slot() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_bus.staff_cards_requested.emit(0, 1, _ids("on_hit on_expire bolt fire nova frost nova"))
	_tap(0, &"extra")
	_frame()
	var tree: TreeViewScript = radial.tree_view()
	radial.mark_slot(4)
	_frame()
	check_equal(Array(tree.marked_rows()), [1], "the fire nova's row is marked for the nova")
	radial.mark_slot(1)
	_frame()
	check_equal(Array(tree.marked_rows()), [2], "on expire's own row for its trigger card")
	var at: Vector2 = tree.tile_center(6)
	check(at.x >= 0.0, "the last nova has a tile")
	check_equal(tree.slot_at(at), 6, "the tile under a point is found, as P1's click finds it")
	check_equal(tree.slot_at(tree.position - Vector2(5.0, 5.0)), -1, "outside the tree is no tile")


func test_rt_puts_nothing_in_from_the_tree() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_point(0, &"nova")
	_tap(0, &"extra")
	_frame()
	check_equal(radial.pointed_id(), &"", "the tree has no pointed card")
	var before: Array[StringName] = radial.cards_of(1)
	_tap(0, &"staff_2")
	_frame()
	check_equal(radial.cards_of(1), before, "RT changes nothing")
	check_equal(_whole.size() + _single.size(), 0, "nothing was asked for")
	_let_go(0)


func test_a_tall_tree_scrolls_and_follows_the_marker() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	var many: Array[StringName] = []
	for _at in 20:
		many.append(&"bolt")
	_bus.staff_cards_requested.emit(0, 1, many)
	_tap(0, &"extra")
	_frame()
	var tree: TreeViewScript = radial.tree_view()
	check_equal(tree.rows().size(), 20, "a cast a bolt")
	check(tree.max_scroll() > 0.0, "taller than its space")
	radial.mark_slot(0)
	_frame()
	check_equal(tree.scroll(), 0.0, "the first row shows at the top")
	_input.send_virtual_aim(0, Vector2.DOWN)
	for _i in 4:
		_frame()
	check(tree.scroll() > 0.0, "the right stick scrolls down: %s" % tree.scroll())
	_input.send_virtual_aim(0, Vector2.ZERO)
	_frame()
	tree.wheel(-100)
	check_equal(tree.scroll(), 0.0, "the wheel scrolls back up, no further than the top")
	radial.mark_slot(19)
	_frame()
	check(is_equal_approx(tree.scroll(), tree.max_scroll()), "the marker on the last bolt scrolls its row into view")


func test_the_replay_steps_through_the_rows_and_loops() -> void:
	_start(1)
	var radial: RadialScript = _open(0)
	_bus.staff_cards_requested.emit(0, 1, _ids("on_hit bolt nova"))
	_tap(0, &"extra")
	_frame()
	var tree: TreeViewScript = radial.tree_view()
	check_equal(tree.rows().size(), 2, "the bolt and its on hit")
	var seen: Array[int] = [tree.replay_row()]
	for _beat in 3:
		tree.step(TreeViewScript.TREE_BEAT, 0.0)
		seen.append(tree.replay_row())
	check_equal(seen, [0, 1, 0, 1], "a row a beat, round and round")
