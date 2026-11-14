extends "res://tests/support/suite.gd"
## Tests for the inventory menu (items I7, hud/menus/inventory/): Select (Tab) opens it on the ring
## of the four bags with how full each is, and closes it again (so do B on the first ring and
## Start); A enters a bag, B goes back out; on the staffs ring a hand's button puts the staff
## pointed at on that hand or, on its own hand, takes it off, and X drops it; on the cards ring the
## kinds, then a kind's cards with their counts, and X drops one; the hands column's arrows compare
## every hand's staff with the one pointed at; a refusal shows its words; the left stick steps
## round the ring; nothing is asked for with nothing pointed at; and what an earlier wizard held is
## forgotten when the seat's wizard is said anew (the builder's too). The wizard is real (the real
## registry and spell runtime), so every request is answered as in the game.
##
## godot --headless --path . --script res://tests/hud/test_inventory_menu.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const InventoryScript := preload("res://hud/menus/inventory/inventory_menu.gd")
const MirrorScript := preload("res://hud/widgets/inventory_mirror.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const NO_SAVE: String = "user://test_no_save.cfg"

const STEP: float = 0.0625
const STAFFS: StringName = &"staffs"
const CARDS: StringName = &"cards"

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
var _world: WizardFixture
var _wizard: Actor
## The staffs: RB's, RT's and one in the bag.
var _short: StaffBase
var _long: StaffBase
var _bagged: StaffBase
## Every staff_hand_requested [player, staff, hand] and bag_drop_requested [player, bag, id, staff].
var _hand_asks: Array = []
var _drop_asks: Array = []
var _dropped: Array[ItemStack] = []


func before_each() -> void:
	_world = WizardFixture.new(root)
	own(_world.registry)
	_bus = own(_world.bus) as EventsScript
	_input = own(_world.input) as InputManagerScript
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	own(_world.projectiles)
	own(_world.spells)
	own(_world.combat)
	own(_world.table)
	own(_world.frames)
	_hand_asks.clear()
	_drop_asks.clear()
	_dropped.clear()
	_bus.staff_hand_requested.connect(func(player: int, staff: int, hand: int) -> void: _hand_asks.append([player, staff, hand]))
	_bus.bag_drop_requested.connect(func(player: int, bag: StringName, id: StringName, staff: int) -> void: _drop_asks.append([player, bag, id, staff]))
	_bus.item_drop_requested.connect(func(_actor: int, stack: ItemStack) -> void: _dropped.append(stack))
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = _world.spells
	root.add_child(_hud)
	_short = _staff(&"short", 4, 0.5, 100.0)
	_long = _staff(&"long", 6, 0.8, 100.0)
	_bagged = _staff(&"bagged", 8, 0.2, 60.0)


func _staff(id: StringName, slots: int, cooldown: float, mana: float) -> StaffBase:
	var made := StaffBase.new()
	made.id = id
	made.slots = slots
	made.cooldown = cooldown
	made.max_mana = mana
	return made


## Player 0's wizard: `_short` on RB with a bolt, `_long` on RT, `_bagged` as staff 4 in the bag,
## the dev bag of cards; in a room.
func _start() -> void:
	_input.add_virtual_device(0)
	_wizard = own(_world.wizard(0, Vector2.ZERO, [[&"bolt"], [], [], []], null, true, [_short, _long, null, null] as Array[StaffBase])) as Actor
	check(_wizard.inventory.add(ItemStack.of_staff(_bagged)), "a staff in the bag")
	_bus.player_joined.emit(0)
	_bus.room_entered.emit(&"test_room")


func _tap(action: StringName) -> void:
	_input.send_virtual(0, action, 1.0)
	_input.send_virtual(0, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()
	for player in 4:
		_inventory(player).step(STEP)
	_world.step_one(_wizard)


func _inventory(player: int = 0) -> InventoryScript:
	return _hud.get_inventory(player)


func _open() -> InventoryScript:
	_tap(&"inventory")
	_frame()
	return _inventory()


## Point the right stick at the entry whose `key` is `value`, and keep holding it there.
func _point(key: String, value: Variant) -> void:
	var entry: int = _inventory().entry_of(key, value)
	check(entry != InventoryScript.NONE, "%s %s is on the ring" % [key, value])
	_input.send_virtual_aim(0, _inventory().menu().direction_to(entry))
	_frame()


func _enter(bag: StringName) -> void:
	_point("bag", bag)
	_tap(&"accept")
	_frame()
	_input.send_virtual_aim(0, Vector2.ZERO)
	_frame()


func test_select_opens_the_bags_and_closes_them_again() -> void:
	_start()
	var inventory: InventoryScript = _open()
	check(inventory.is_open(), "Select opens it")
	check(_input.is_captured(0), "the wizard stands still meanwhile")
	check(not _hud.get_panel(0).visible, "the corner panel hides while it is open")
	check_equal(inventory.layer(), InventoryScript.Layer.BAGS, "on the ring of bags")
	var bags: Array = []
	for entry: Dictionary in inventory.entries():
		bags.append(entry["bag"])
	check_equal(bags, ItemKinds.BAGS, "the four bags, in order")
	check_equal(inventory.mirror().fill_text(STAFFS), "1/∞", "the staff bag: one staff off a hand, no limit")
	check_equal(inventory.mirror().fill_text(&"relics"), "0/∞", "an empty bag")
	_tap(&"inventory")
	_frame()
	check(not inventory.is_open(), "Select again closes it")
	check(_hud.get_panel(0).visible, "and the corner panel is back")
	_frame()
	check(not inventory.is_open(), "the press that closed it opens nothing")
	_open()
	_tap(&"back")
	_frame()
	check(not inventory.is_open(), "B on the first ring closes it")
	_frame()
	_open()
	check(inventory.is_open(), "open again")
	_tap(&"pause")
	_frame()
	check(not inventory.is_open(), "so does Start")
	check(not _hud.get_pause_menu().is_open(), "with no pause menu over it")


func test_it_does_not_open_over_another_menu() -> void:
	_start()
	_tap(&"back")
	_frame()
	check(_hud.get_radial(0).is_open(), "the builder is open")
	_tap(&"inventory")
	_frame()
	check(not _inventory().is_open(), "Select does nothing in the builder")


func test_a_enters_a_bag_and_b_goes_back_out() -> void:
	_start()
	var inventory: InventoryScript = _open()
	_enter(STAFFS)
	check_equal(inventory.layer(), InventoryScript.Layer.STAFFS, "in the staff bag")
	var numbers: Array = []
	for entry: Dictionary in inventory.entries():
		numbers.append(entry["staff"])
	check_equal(numbers, [0, 1, 4], "every staff owned: the hands' first, then the bag's")
	_tap(&"back")
	_frame()
	check_equal(inventory.layer(), InventoryScript.Layer.BAGS, "B goes back to the bags")
	check(inventory.is_open(), "and does not close it")
	check_equal(inventory.pointed().get("bag"), STAFFS, "pointing at the bag it came out of")
	_enter(&"relics")
	check_equal(inventory.layer(), InventoryScript.Layer.EMPTY, "relics: nothing there yet")
	check(inventory.entries().is_empty(), "an empty ring")
	check(inventory.hub_lines().has("Empty"), "which says so")


func test_a_hands_button_puts_the_staff_on_that_hand_and_off_again() -> void:
	_start()
	var inventory: InventoryScript = _open()
	_enter(STAFFS)
	_point("staff", 4)
	_tap(&"staff_3")
	_frame()
	check_equal(_hand_asks, [[0, 4, 2]], "LB asked for")
	check_equal(_wizard.inventory.hands(), PackedInt32Array([0, 1, 4, Inventory.NO_STAFF]), "the bag's staff is on LB")
	check(_wizard.caster.holds(2), "the Caster's LB holds it")
	check_equal(inventory.pointed().get("staff"), 4, "still pointed at as the ring is laid out again")
	_tap(&"staff_3")
	_frame()
	check_equal(_hand_asks.back(), [0, 4, -1], "its own hand's button takes it off")
	check_equal(_wizard.inventory.hand_of(4), -1, "back in the bag")
	_point("staff", 0)
	_tap(&"staff_2")
	_frame()
	check_equal(_wizard.inventory.hands(), PackedInt32Array([1, 0, Inventory.NO_STAFF, Inventory.NO_STAFF]), "RB's staff onto RT: the two changed places")


func test_x_drops_the_staff_pointed_at() -> void:
	_start()
	var inventory: InventoryScript = _open()
	_enter(STAFFS)
	_point("staff", 4)
	_tap(&"alternate")
	_frame()
	check_equal(_drop_asks, [[0, STAFFS, &"bagged", 4]], "the staff asked dropped, by its number")
	check_equal(_dropped.size(), 1, "it went to the ground")
	check_equal(inventory.entry_of("staff", 4), InventoryScript.NONE, "and off the ring")
	check(inventory.pointed().get("staff", -1) != 4, "it is pointed at no more")


func test_the_cards_are_by_kind_then_counted_and_x_drops_one() -> void:
	_start()
	var inventory: InventoryScript = _open()
	_enter(CARDS)
	check_equal(inventory.layer(), InventoryScript.Layer.KINDS, "the kinds first")
	check(inventory.entry_of("kind", &"carrier") != InventoryScript.NONE, "the carriers are there")
	_point("kind", &"carrier")
	_tap(&"accept")
	_frame()
	_input.send_virtual_aim(0, Vector2.ZERO)
	_frame()
	check_equal(inventory.layer(), InventoryScript.Layer.CARDS, "then the carriers")
	for entry: Dictionary in inventory.entries():
		check_equal(_world.spells.component_kind(entry["card"]), &"carrier", "%s is a carrier" % entry["card"])
		check_equal(int(entry["count"]), _wizard.inventory.count_of(CARDS, entry["card"]), "%s: its copies" % entry["card"])
	var before: int = _wizard.inventory.count_of(CARDS, &"bolt")
	_point("card", &"bolt")
	_tap(&"alternate")
	_frame()
	check_equal(_drop_asks, [[0, CARDS, &"bolt", -1]], "one bolt asked dropped")
	check_equal(_wizard.inventory.count_of(CARDS, &"bolt"), before - 1, "one copy fewer")
	check_equal(int(inventory.pointed().get("count", 0)), before - 1, "and the ring says so")
	_tap(&"back")
	_frame()
	check_equal(inventory.layer(), InventoryScript.Layer.KINDS, "B: back to the kinds")


func test_the_arrows_compare_every_hand_with_the_staff_pointed_at() -> void:
	_start()
	var inventory: InventoryScript = _open()
	check_equal(inventory.hand_arrows(0), PackedInt32Array([0, 0, 0]), "no arrows with nothing pointed at")
	_enter(STAFFS)
	_point("staff", 4)
	# Bagged against short: 8 slots to 4 (better), 0.2 s to 0.5 (better), 60 mana to 100 (worse).
	check_equal(inventory.hand_arrows(0), PackedInt32Array([1, 1, -1]), "RB: more slots, a shorter delay, less mana")
	check_equal(inventory.hand_arrows(1), PackedInt32Array([1, 1, -1]), "RT the same")
	check_equal(inventory.hand_arrows(2), PackedInt32Array([0, 0, 0]), "an empty hand: none")
	_point("staff", 1)
	check_equal(inventory.hand_arrows(1), PackedInt32Array([0, 0, 0]), "a staff against itself: none")
	check_equal(inventory.hand_arrows(0), PackedInt32Array([1, -1, 0]), "long against short: more slots, a longer delay, the same mana")


func test_a_refusal_shows_its_words() -> void:
	_start()
	var inventory: InventoryScript = _open()
	_wizard.inventory.set_capacity(STAFFS, 1)
	_enter(STAFFS)
	_point("staff", 0)
	_tap(&"staff_1")
	_frame()
	check_equal(_hand_asks, [[0, 0, -1]], "RB's staff asked off its hand")
	check_equal(_wizard.inventory.hand_of(0), 0, "refused: the staff bag is full")
	check_equal(inventory.note_text(), PlayerController.NO_ROOM, "and the note says why")
	for _at in 30:
		_frame()
	check_equal(inventory.note_text(), "", "the note fades")


func test_nothing_is_asked_with_nothing_pointed_at_or_on_the_wrong_ring() -> void:
	_start()
	_open()
	_tap(&"alternate")
	_tap(&"staff_1")
	_frame()
	check(_hand_asks.is_empty() and _drop_asks.is_empty(), "the bags ring asks for nothing")
	_enter(STAFFS)
	_tap(&"alternate")
	_tap(&"staff_2")
	_frame()
	check(_hand_asks.is_empty() and _drop_asks.is_empty(), "nor the staffs ring with nothing pointed at")
	check_equal(_inventory().hint_verbs(), ["Open", "Drop", "Back", "Close"] as Array[String], "the hints")


func test_the_left_stick_steps_round_the_ring() -> void:
	_start()
	var inventory: InventoryScript = _open()
	_input.send_virtual(0, &"move_right", 1.0)
	_frame()
	check_equal(inventory.pointed().get("bag"), ItemKinds.BAGS[0], "the first bag")
	_input.send_virtual(0, &"move_right", 0.0)
	_frame()
	check_equal(inventory.pointed().get("bag"), ItemKinds.BAGS[0], "stays pointed at once let go")
	_input.send_virtual(0, &"move_left", 1.0)
	_frame()
	_input.send_virtual(0, &"move_left", 0.0)
	_frame()
	check_equal(inventory.pointed().get("bag"), ItemKinds.BAGS[ItemKinds.BAGS.size() - 1], "round to the last")


## Regression: a wizard said anew (back in the hub from a run) leaves nothing of the one before in
## the inventory or the builder: a staff only the earlier one owned is forgotten.
func test_a_wizard_said_anew_forgets_the_earlier_ones_staffs() -> void:
	_start()
	var inventory: InventoryScript = _open()
	check(inventory.mirror().staffs().has(4), "the bag's staff is known")
	check(_hud.get_radial(0).strip().has(4), "to the builder too")
	_bus.inventory_announced.emit(0)
	for number in [0, 1]:
		_bus.owned_staff_changed.emit(0, number, _wizard.inventory.plan_of(number))
	_bus.hands_changed.emit(0, PackedInt32Array([0, 1, -1, -1]))
	check_equal(inventory.mirror().staffs(), PackedInt32Array([0, 1]), "only what was said anew")
	check_equal(_hud.get_radial(0).strip(), PackedInt32Array([0, 1]), "the builder's strip too")


func test_the_mirror() -> void:
	var mirror := MirrorScript.new()
	mirror.hear_bag(CARDS, [&"bolt", &"fire"] as Array[StringName], PackedInt32Array([3, 1]), 10)
	check_equal(mirror.copies(CARDS), 4, "four copies")
	check_equal(mirror.fill_text(CARDS), "4/10", "of ten")
	check_equal(mirror.count_of(CARDS, &"bolt"), 3, "three bolts")
	check_equal(mirror.fill_text(STAFFS), "0/∞", "a bag never said: empty, no limit")
	mirror.hear_staff(5, {"staff": _short, "cards": [&"bolt"]})
	mirror.hear_staff(4, {"staff": _long, "cards": []})
	mirror.hear_staff(2, {"staff": _bagged, "cards": []})
	mirror.hear_hands(PackedInt32Array([-1, 5, -1, -1]))
	check_equal(mirror.staffs(), PackedInt32Array([5, 2, 4]), "the hands' first, then by number")
	check_equal(mirror.hand_of(5), 1, "on RT")
	check_equal(mirror.base_of(4), _long, "its staff")
	mirror.hear_staff(4, {})
	check_equal(mirror.staffs(), PackedInt32Array([5, 2]), "an empty plan: gone")


func test_the_columns_numbers_are_short() -> void:
	check_equal(InventoryScript.number_text(0.15, true), "0.15s", "a delay")
	check_equal(InventoryScript.number_text(0.5, true), "0.5s", "no trailing zero")
	check_equal(InventoryScript.number_text(0.0, true), "0s", "none")
	check_equal(InventoryScript.number_text(100.0, false), "100", "mana")
	check_equal(InventoryScript.number_text(12000.0, false), "12k", "thousands")
	check_equal(InventoryScript.number_text(1000000.0, false), "1M", "the dev staff's million")


## Review: Space is both `accept` and `staff_1` on the keyboard; the press that enters the staff bag
## puts nothing on a hand.
func test_the_press_that_enters_the_staffs_puts_nothing_on_a_hand() -> void:
	_start()
	var inventory: InventoryScript = _open()
	_point("bag", STAFFS)
	_tap(&"accept")
	_tap(&"staff_1")
	_frame()
	check_equal(inventory.layer(), InventoryScript.Layer.STAFFS, "in the staff bag")
	check(_hand_asks.is_empty(), "and nothing asked of a hand")


## Items I8: the menus are the driven body's. A possession closes an open inventory (it would name a
## staff of the body shown before), and what it shows is the possessed imp's: its staff, its empty
## card bag; when the possession ends, the wizard's again.
func test_a_possession_closes_the_menus_and_they_show_the_body_the_seat_drives() -> void:
	_start()
	var imp_data: EnemyBase = load("res://content/enemies/ember_imp/ember_imp.tres") as EnemyBase
	var imp := imp_data.scene.instantiate() as Actor
	imp.data = imp_data
	imp.position = Vector2(0.0, 60.0)
	own(_world.add(imp))
	var inventory: InventoryScript = _open()
	check(inventory.is_open(), "the inventory is open")
	Possession.begin(_wizard, imp, 1.0)
	check(not inventory.is_open(), "a possession closes it")
	check_equal(inventory.mirror().staffs(), PackedInt32Array([0]), "it shows the imp's one staff")
	check_equal(inventory.mirror().base_of(0).id, &"ember_imp", "the imp's own")
	check_equal(inventory.mirror().fill_text(CARDS), "0/∞", "and its empty card bag")
	_frame()
	_open()
	check(inventory.is_open(), "it opens again on the imp's things")
	imp.possessed_by.end()
	check(not inventory.is_open(), "the possession's end closes it")
	check_equal(inventory.mirror().staffs(), PackedInt32Array([0, 1, 4]), "and it shows the wizard's staffs again")
