extends "res://tests/support/suite.gd"
## Tests for the wizard on staffs (staffs A6a): four staffs on four buttons, the start cards and
## the bag, `staff_change_requested` and `card_move_requested` applied and announced
## (`staff_changed`) or refused (`build_refused`), casting through `Spells.cast_staff`, a
## sustained (`hold`) card switched off only by a new press, mana held by sustained cards, the
## orbit anchor, and four players building at once. It runs the real `Spells`, projectile manager
## and event bus, with cards built in code behind a stand-in registry.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_build.gd

const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const STEP: float = 0.0625
const START: Array = [[&"dash"], [&"fire", &"bolt"], [], []]


## A registry that knows only the cards a test puts in it.
class FakeRegistry:
	extends RegistryScript
	var items: Dictionary = {}

	func get_ids(folder: StringName) -> Array[StringName]:
		var ids: Array[StringName] = []
		if folder == &"spells":
			for id: StringName in items:
				ids.append(id)
		return ids

	func get_resource(folder: StringName, id: StringName) -> Resource:
		return items.get(id) if folder == &"spells" else null


var _registry: FakeRegistry
var _bus: EventsScript
var _input: InputManagerScript
var _mgr: ManagerScript
var _spells: SpellsScript
var _staff: StaffBase
var _players: Array[PlayerScript] = []
## Every staff_changed as [player, staff, plan].
var _changed: Array = []
## Every build_refused as [player, reason].
var _refused: Array = []
## Every staff_cast as [player, staff], and every spell_cast's form.
var _staff_casts: Array = []
var _cast_forms: Array[StringName] = []


func before_each() -> void:
	_registry = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 6
	_staff.cast_delay = 0.0
	_staff.recharge = 0.0
	_players.clear()
	_changed.clear()
	_refused.clear()
	_staff_casts.clear()
	_cast_forms.clear()
	_bus.staff_changed.connect(func(player: int, staff: int, plan: Dictionary) -> void: _changed.append([player, staff, plan]))
	_bus.build_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))
	_bus.staff_cast.connect(func(player: int, staff: int, _o: Vector2, _d: Vector2) -> void: _staff_casts.append([player, staff]))
	_bus.spell_cast.connect(func(_p: int, form: StringName, _o: Vector2, _d: Vector2) -> void: _cast_forms.append(form))
	var bolt := _card(FormBase.new(), &"bolt") as FormBase
	bolt.cooldown = 0.25
	var orbit := _card(FormBase.new(), &"orbit") as FormBase
	orbit.motion = FormBase.Motion.ORBIT
	orbit.orbit_radius = 30.0
	orbit.lifetime = 5.0
	orbit.pierce = 16
	var dash := _card(FormBase.new(), &"dash") as FormBase
	dash.motion = FormBase.Motion.DASH
	dash.speed = 220.0
	dash.lifetime = 0.25
	dash.mana_cost = 0.0
	var fire := _card(ElementBase.new(), &"fire") as ElementBase
	fire.status_id = &"burn"
	fire.status_duration = 3.0
	var hold := _card(ModifierBase.new(), &"hold") as ModifierBase
	hold.behaviour = ModifierBase.Behaviour.HOLD
	hold.behaviour_strength = 1.0


func _card(card: SpellComponent, id: StringName) -> SpellComponent:
	card.id = id
	card.display_name = String(id).capitalize()
	if card is FormBase:
		(card as FormBase).mana_cost = 5.0
		(card as FormBase).speed = 200.0
	_registry.items[id] = card
	return card


## A wizard outside the tree for player `index`, with the start cards and a real device.
func _wizard(index: int, start: Array = START) -> PlayerScript:
	_input.add_virtual_device(index)
	var player := own(PlayerScript.new()) as PlayerScript
	player.index = index
	player.input = _input
	player.events = _bus
	player.registry = _registry
	player.projectiles = _mgr
	player.spells = _spells
	player.staff = _staff
	player.start_cards = start
	player._ready()
	_players.append(player)
	return player


func _ids(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(&"" if word == "-" else StringName(word))
	return out


func _run(count: int) -> void:
	for i in count:
		_mgr.step(STEP)
		_spells.step(STEP)
		for player in _players:
			player.step(STEP)


func _tap(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 1.0)
	_input.send_virtual(player, action, 0.0)


func test_the_bag_holds_every_card_in_the_registry() -> void:
	var player := _wizard(0)
	check_equal(player.bag.size(), _registry.items.size(), "the bag has every card")


func test_the_start_cards_are_built_and_announced() -> void:
	var player := _wizard(1)
	check(player.has_staff(0) and player.has_staff(1), "the dash and the fire bolt staffs are built")
	check(not player.has_staff(2) and not player.has_staff(3), "the empty staffs have no build")
	check_equal(player.cards_of(1), _ids("fire bolt - - - -"), "staff X holds the fire bolt, as many slots as the staff")
	check_equal(_changed.size(), 4, "every staff is announced once")
	var plan: Dictionary = _changed[1][2]
	check_equal(plan.get("cards"), _ids("fire bolt - - - -"), "the plan carries the cards")
	check(not (plan.get("casts", []) as Array).is_empty(), "and the casts")


func test_each_button_casts_its_own_staff() -> void:
	var player := _wizard(0, [[&"bolt"], [&"fire", &"bolt"], [], []])
	_input.send_virtual(0, &"cast_x", 1.0)
	_run(1)
	check_equal(_staff_casts, [[0, 1]], "cast_x casts staff X")
	check_equal(_cast_forms, [&"bolt"] as Array[StringName], "spell_cast names the carrier")
	_input.send_virtual(0, &"cast_a", 1.0)
	_run(1)
	check(_staff_casts.has([0, 0]), "cast_a casts staff A, with X still held")
	check(player.mana < PlayerScript.MAX_MANA, "the casts took mana")


func test_a_tap_just_before_the_staff_is_ready_still_casts() -> void:
	_wizard(0, [[], [&"bolt"], [], []])
	_tap(0, &"cast_x")
	_run(1)
	check_equal(_staff_casts.size(), 1, "the first tap casts")
	_run(2)
	_tap(0, &"cast_x")
	_run(3)
	check_equal(_staff_casts.size(), 2, "a tap within INPUT_BUFFER of the end of the delay casts once ready")


func test_a_dash_card_dashes_the_wizard() -> void:
	var player := _wizard(0)
	_input.send_virtual(0, &"move_right", 1.0)
	_run(1)
	_tap(0, &"cast_a")
	_run(2)
	check(player.is_dashing(), "the A staff's dash card dashes")
	check(not player.is_invulnerable(), "without invulnerability")
	check(player.velocity.x > PlayerScript.MOVE_SPEED, "faster than walking, the way the wizard walks")


func test_a_held_button_does_not_switch_a_hold_off_but_a_new_press_does() -> void:
	var player := _wizard(0, [[], [], [&"hold", &"orbit"], []])
	_input.send_virtual(0, &"cast_y", 1.0)
	_run(1)
	check(_spells.is_holding(0, 2), "the press switches the orbit on")
	check_equal(player.free_mana(), player.mana - 5.0, "its mana is held")
	_run(20)
	check(_spells.is_holding(0, 2), "holding the button does not switch it off")
	_input.send_virtual(0, &"cast_y", 0.0)
	_tap(0, &"cast_y")
	_run(1)
	check(not _spells.is_holding(0, 2), "a new press switches it off")
	check_equal(player.free_mana(), player.mana, "and frees its mana")


func test_a_change_request_builds_the_staff_and_is_announced() -> void:
	var player := _wizard(2)
	_changed.clear()
	_bus.staff_change_requested.emit(2, 3, 0, &"bolt")
	check_equal(player.cards_of(3)[0], &"bolt", "the card is in the slot")
	check(player.has_staff(3), "the staff can cast now")
	check_equal(_changed.size(), 1, "the change is announced")
	check_equal([_changed[0][0], _changed[0][1]], [2, 3], "for this player and staff")
	_bus.staff_change_requested.emit(2, 3, 0, &"")
	check(not player.has_staff(3), "emptying the slot leaves nothing to cast")


func test_a_wrong_request_is_refused_and_changes_nothing() -> void:
	var player := _wizard(0)
	var before: Array[StringName] = player.cards_of(1)
	_bus.staff_change_requested.emit(0, 1, 9, &"bolt")
	_bus.staff_change_requested.emit(0, 4, 0, &"bolt")
	_bus.staff_change_requested.emit(0, 1, 0, &"no_such_card")
	check_equal(_refused.size(), 3, "three refusals")
	check_equal(player.cards_of(1), before, "the staff is as it was")


func test_a_request_for_another_player_is_ignored() -> void:
	var first := _wizard(0)
	var second := _wizard(1)
	_bus.staff_change_requested.emit(1, 2, 0, &"bolt")
	check(not first.has_staff(2), "player 1's staff Y is untouched")
	check(second.has_staff(2), "player 2's is built")


func test_cards_move_and_swap_between_slots_staffs_and_the_bag() -> void:
	var player := _wizard(0)
	_bus.card_move_requested.emit(0, 1, 0, 1, 1)
	check_equal(player.cards_of(1).slice(0, 2), _ids("bolt fire"), "two slots of one staff swap")
	_bus.card_move_requested.emit(0, 1, 0, 2, 3)
	check_equal(player.cards_of(2)[3], &"bolt", "a card moves to another staff")
	check_equal(player.cards_of(1)[0], &"", "and leaves its slot")
	_bus.card_move_requested.emit(0, PlayerScript.BAG, player.bag.find(&"orbit"), 3, 0)
	check_equal(player.cards_of(3)[0], &"orbit", "a card comes from the bag")
	_bus.card_move_requested.emit(0, 3, 0, PlayerScript.BAG, 0)
	check_equal(player.cards_of(3)[0], &"", "and goes back")


func test_four_players_build_different_staffs_at_once() -> void:
	for index in 4:
		_wizard(index, [[], [], [], []])
	var cards: Array[StringName] = [&"bolt", &"orbit", &"dash", &"fire"]
	for index in 4:
		_bus.staff_change_requested.emit(index, index, 0, cards[index])
	for index in 4:
		check_equal(_players[index].cards_of(index)[0], cards[index], "player %d built its own staff" % index)
		for other in 4:
			if other != index:
				check_equal(_players[index].cards_of(other)[0], &"", "player %d's other staffs are empty" % index)


func test_the_orbit_anchor_follows_the_wizard_and_goes_when_it_falls() -> void:
	var player := _wizard(0, [[], [&"orbit"], [], []])
	player.global_position = Vector2(100, 50)
	_input.send_virtual(0, &"cast_x", 1.0)
	_run(1)
	check(_mgr.get_count() > 0, "the orbit shot flies")
	check(_mgr.get_anchor(0).is_finite(), "the anchor is set")
	player.take_damage(1000)
	_run(1)
	check(not _mgr.get_anchor(0).is_finite(), "a downed wizard clears its anchor")


func test_a_wizard_put_back_in_the_tree_hears_requests_again() -> void:
	var player := _wizard(0)
	root.add_child(player)
	root.remove_child(player)
	root.add_child(player)
	_bus.staff_change_requested.emit(0, 2, 0, &"bolt")
	check(player.has_staff(2), "it still listens")
	root.remove_child(player)
