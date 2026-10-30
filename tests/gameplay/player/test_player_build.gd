extends "res://tests/support/suite.gd"
## Tests for the wizard on staffs (staffs A6a; the wizard actor and its seat since actors G7):
## four staffs on four buttons, the start cards and the bag, `staff_change_requested`,
## `staff_cards_requested` and `card_move_requested` applied and announced (`staff_changed`) or
## refused (`build_refused`), casting through `Spells.cast_staff`, a sustained (`hold`) card
## switched off only by a new press, mana held by sustained cards, the orbit anchor, and four
## players building at once. And the seat (the PlayerController) on an actor that is not its
## wizard: its input and casts follow the actor it drives, while its HUD numbers and builder stay
## its own wizard's (owner, 2026-10-28), also while no controller drives the wizard; `release`
## gives it back. It runs the real `Spells`, projectile
## manager and event bus, with cards built in code behind a stand-in registry, and the real
## wizard scene.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_build.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

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


var _world: Fixture
var _registry: FakeRegistry
var _spells: SpellsScript
var _staff: StaffBase
var _players: Array[Actor] = []
## Every staff_changed as [player, staff, plan].
var _changed: Array = []
## Every build_refused as [player, reason].
var _refused: Array = []
## Every staff_cast as [player, staff], and every spell_cast's form.
var _staff_casts: Array = []
var _cast_forms: Array[StringName] = []
## Every player_stats_changed as [player, health, max_health, mana, max_mana].
var _stats: Array = []


func before_each() -> void:
	# The wizard world, with the real Spells reading the cards made here instead of the stand-in.
	_world = Fixture.new(root, true)
	_world.fake.bind(null, null)
	_world.fake.free()
	_world.fake = null
	_world.registry.free()
	_registry = FakeRegistry.new()
	_world.registry = _registry
	_spells = SpellsScript.new()
	_spells.registry = _registry
	_spells.actors = _world.table
	_spells.bind(_world.projectiles, _world.bus)
	_world.spells = _spells
	_world.combat.spells = _spells
	_world.projectiles.set_cap(512)
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
	_stats.clear()
	var bus := _world.bus
	bus.staff_changed.connect(func(player: int, staff: int, plan: Dictionary) -> void: _changed.append([player, staff, plan]))
	bus.build_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))
	bus.staff_cast.connect(func(player: int, staff: int, _o: Vector2, _d: Vector2) -> void: _staff_casts.append([player, staff]))
	bus.spell_cast.connect(func(_p: int, form: StringName, _o: Vector2, _d: Vector2) -> void: _cast_forms.append(form))
	bus.player_stats_changed.connect(func(p: int, h: int, mh: int, m: float, mm: float) -> void: _stats.append([p, h, mh, m, mm]))
	var bolt := _card(FormBase.new(), &"bolt") as FormBase
	bolt.cooldown = 0.25
	var orbit := _card(FormBase.new(), &"orbit") as FormBase
	orbit.carrier = &"orbit"
	orbit.orbit_radius = 30.0
	orbit.lifetime = 5.0
	orbit.pierce = 16
	var dash := _card(FormBase.new(), &"dash") as FormBase
	dash.carrier = &"dash"
	dash.speed = 220.0
	dash.lifetime = 0.25
	dash.mana_cost = 0.0
	var fire := _card(ElementBase.new(), &"fire") as ElementBase
	fire.status_id = &"burn"
	fire.status_duration = 3.0
	var hold := _card(ModifierBase.new(), &"hold") as ModifierBase
	hold.behaviour = ModifierBase.Behaviour.HOLD
	hold.behaviour_strength = 1.0


func after_each() -> void:
	_world.free_all()


func _card(card: SpellComponent, id: StringName) -> SpellComponent:
	card.id = id
	card.display_name = String(id).capitalize()
	if card is FormBase:
		(card as FormBase).mana_cost = 5.0
		(card as FormBase).speed = 200.0
	_registry.items[id] = card
	return card


## The wizard of seat `index`, in the tree, with the start cards and a real device.
func _wizard(index: int, start: Array = START) -> Actor:
	var player: Actor = _world.wizard(index, Vector2(40.0 * index, 0.0), start, _staff)
	_players.append(player)
	return player


## A bare actor of the kit (not a wizard, no controller of its own) with Health (40), a Mover and
## a Caster of two staffs (a bolt and an empty one) and 50 mana, in the tree.
func _creature(at: Vector2) -> Actor:
	var body := Actor.new()
	body.name = "Creature"
	var health := Health.new()
	health.max_health = 40
	body.add_child(health)
	# A hurtbox, so Combat can hit it (actors G5: hits reach Health only through Combat).
	body.add_child(Hurtbox.new())
	body.add_child(Mover.new())
	var caster := Caster.new()
	caster.staff_count = 2
	caster.staff = _staff
	caster.start_cards = [[&"bolt"], []]
	caster.max_mana = 50.0
	body.add_child(caster)
	body.position = at
	return _world.add(body)


func _seat(player: Actor) -> PlayerController:
	return Fixture.controller(player)


func _ids(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(&"" if word == "-" else StringName(word))
	return out


func _run(count: int) -> void:
	_world.run(count)


func _tap(player: int, action: StringName) -> void:
	_world.hold(player, action)
	_world.release(player, action)


func test_the_bag_holds_every_card_in_the_registry() -> void:
	var player := _wizard(0)
	check_equal(_seat(player).bag.size(), _registry.items.size(), "the bag has every card")


func test_the_start_cards_are_built_and_announced() -> void:
	var player := _wizard(1)
	var caster: Caster = player.caster
	check(caster.has_staff(0) and caster.has_staff(1), "the dash and the fire bolt staffs are built")
	check(not caster.has_staff(2) and not caster.has_staff(3), "the empty staffs have no build")
	check_equal(caster.cards_of(1), _ids("fire bolt - - - -"), "staff X holds the fire bolt, as many slots as the staff")
	check_equal(_changed.size(), 4, "every staff is announced once")
	var plan: Dictionary = _changed[1][2]
	check_equal(plan.get("cards"), _ids("fire bolt - - - -"), "the plan carries the cards")
	check(not (plan.get("casts", []) as Array).is_empty(), "and the casts")


func test_each_button_casts_its_own_staff() -> void:
	var player := _wizard(0, [[&"bolt"], [&"fire", &"bolt"], [], []])
	_world.hold(0, &"staff_2")
	_run(1)
	check_equal(_staff_casts, [[0, 1]], "staff_2 casts staff 2")
	check_equal(_cast_forms, [&"bolt"] as Array[StringName], "spell_cast names the carrier")
	_world.hold(0, &"staff_1")
	_run(1)
	check(_staff_casts.has([0, 0]), "staff_1 casts staff 1, with staff 2 still held")
	check(player.caster.mana < player.caster.max_mana, "the casts took mana")


func test_a_tap_just_before_the_staff_is_ready_still_casts() -> void:
	_wizard(0, [[], [&"bolt"], [], []])
	_tap(0, &"staff_2")
	_run(1)
	check_equal(_staff_casts.size(), 1, "the first tap casts")
	_run(2)
	_tap(0, &"staff_2")
	_run(3)
	check_equal(_staff_casts.size(), 2, "a tap within INPUT_BUFFER of the end of the delay casts once ready")


func test_a_dash_card_dashes_the_wizard() -> void:
	var player := _wizard(0)
	_world.hold(0, &"move_right")
	_run(1)
	_tap(0, &"staff_1")
	_run(2)
	check(player.mover.is_moving(), "the A staff's dash card dashes")
	check(not player.health.is_protected(), "without invulnerability")
	check(player.velocity.x > player.mover.speed, "faster than walking, the way the wizard walks")


func test_a_held_button_does_not_switch_a_hold_off_but_a_new_press_does() -> void:
	var player := _wizard(0, [[], [], [&"hold", &"orbit"], []])
	var caster: Caster = player.caster
	_world.hold(0, &"staff_3")
	_run(1)
	check(_spells.is_holding(player.id, 2), "the press switches the orbit on")
	check_equal(caster.free_mana(), caster.mana - 5.0, "its mana is held")
	_run(20)
	check(_spells.is_holding(player.id, 2), "holding the button does not switch it off")
	_world.release(0, &"staff_3")
	_tap(0, &"staff_3")
	_run(1)
	check(not _spells.is_holding(player.id, 2), "a new press switches it off")
	check_equal(caster.free_mana(), caster.mana, "and frees its mana")


func test_a_change_request_builds_the_staff_and_is_announced() -> void:
	var player := _wizard(2)
	_changed.clear()
	_world.bus.staff_change_requested.emit(2, 3, 0, &"bolt")
	check_equal(player.caster.cards_of(3)[0], &"bolt", "the card is in the slot")
	check(player.caster.has_staff(3), "the staff can cast now")
	check_equal(_changed.size(), 1, "the change is announced")
	check_equal([_changed[0][0], _changed[0][1]], [2, 3], "for this player and staff")
	_world.bus.staff_change_requested.emit(2, 3, 0, &"")
	check(not player.caster.has_staff(3), "emptying the slot leaves nothing to cast")


func test_a_wrong_request_is_refused_and_changes_nothing() -> void:
	var player := _wizard(0)
	var before: Array[StringName] = player.caster.cards_of(1)
	_world.bus.staff_change_requested.emit(0, 1, 9, &"bolt")
	_world.bus.staff_change_requested.emit(0, 4, 0, &"bolt")
	_world.bus.staff_change_requested.emit(0, 1, 0, &"no_such_card")
	check_equal(_refused.size(), 3, "three refusals")
	check_equal(player.caster.cards_of(1), before, "the staff is as it was")


func test_a_request_for_another_player_is_ignored() -> void:
	var first := _wizard(0)
	var second := _wizard(1)
	_world.bus.staff_change_requested.emit(1, 2, 0, &"bolt")
	check(not first.caster.has_staff(2), "player 1's staff Y is untouched")
	check(second.caster.has_staff(2), "player 2's is built")


func test_cards_move_and_swap_between_slots_staffs_and_the_bag() -> void:
	var player := _wizard(0)
	var caster: Caster = player.caster
	var bus := _world.bus
	bus.card_move_requested.emit(0, 1, 0, 1, 1)
	check_equal(caster.cards_of(1).slice(0, 2), _ids("bolt fire"), "two slots of one staff swap")
	bus.card_move_requested.emit(0, 1, 0, 2, 3)
	check_equal(caster.cards_of(2)[3], &"bolt", "a card moves to another staff")
	check_equal(caster.cards_of(1)[0], &"", "and leaves its slot")
	bus.card_move_requested.emit(0, PlayerController.BAG, _seat(player).bag.find(&"orbit"), 3, 0)
	check_equal(caster.cards_of(3)[0], &"orbit", "a card comes from the bag")
	bus.card_move_requested.emit(0, 3, 0, PlayerController.BAG, 0)
	check_equal(caster.cards_of(3)[0], &"", "and goes back")


func test_a_whole_staff_request_sets_every_slot_in_one_change() -> void:
	var player := _wizard(1)
	var caster: Caster = player.caster
	_changed.clear()
	_world.bus.staff_cards_requested.emit(1, 2, _ids("fire bolt orbit"))
	check_equal(caster.cards_of(2).slice(0, 4), _ids("fire bolt orbit -"), "the cards fill the first slots, the rest is empty")
	check_equal(caster.cards_of(2).size(), caster.slot_count(), "the row keeps the staff's slots")
	check_equal(_changed.size(), 1, "one change, announced once")
	_world.bus.staff_cards_requested.emit(1, 2, [] as Array[StringName])
	check(not caster.has_staff(2), "an empty list clears the staff")


func test_a_wrong_whole_staff_request_is_refused_and_changes_nothing() -> void:
	var player := _wizard(0)
	var caster: Caster = player.caster
	var before: Array[StringName] = caster.cards_of(1)
	var too_many: Array[StringName] = []
	for _slot in caster.slot_count() + 1:
		too_many.append(&"bolt")
	_world.bus.staff_cards_requested.emit(0, 1, too_many)
	_world.bus.staff_cards_requested.emit(0, 4, _ids("bolt"))
	_world.bus.staff_cards_requested.emit(0, 1, _ids("bolt no_such_card"))
	check_equal(_refused.size(), 3, "three refusals")
	check_equal(caster.cards_of(1), before, "the staff is as it was")
	_world.bus.staff_cards_requested.emit(1, 1, _ids("orbit"))
	check_equal(caster.cards_of(1), before, "another player's request is not this wizard's")


func test_four_players_build_different_staffs_at_once() -> void:
	for index in 4:
		_wizard(index, [[], [], [], []])
	var cards: Array[StringName] = [&"bolt", &"orbit", &"dash", &"fire"]
	for index in 4:
		_world.bus.staff_change_requested.emit(index, index, 0, cards[index])
	for index in 4:
		check_equal(_players[index].caster.cards_of(index)[0], cards[index], "player %d built its own staff" % index)
		for other in 4:
			if other != index:
				check_equal(_players[index].caster.cards_of(other)[0], &"", "player %d's other staffs are empty" % index)


func test_the_orbit_anchor_follows_the_wizard_and_goes_when_it_falls() -> void:
	var player := _wizard(0, [[], [&"orbit"], [], []])
	player.global_position = Vector2(100, 50)
	_world.hold(0, &"staff_2")
	_run(1)
	check(_world.projectiles.get_count() > 0, "the orbit shot flies")
	check(_world.projectiles.get_anchor(player.id).is_finite(), "the anchor is set")
	_world.hurt(player, 1000)
	_run(1)
	check(not _world.projectiles.get_anchor(player.id).is_finite(), "a downed wizard clears its anchor")


func test_a_wizard_put_back_in_the_tree_hears_requests_again() -> void:
	var player := _wizard(0)
	root.remove_child(player)
	root.add_child(player)
	_world.bus.staff_change_requested.emit(0, 2, 0, &"bolt")
	check(player.caster.has_staff(2), "it still listens")


# --- The seat on another actor (actors G7) ----------------------------------

func test_a_seat_drives_another_actor_and_release_gives_it_back() -> void:
	var wizard := _wizard(0)
	var creature := _creature(Vector2(200.0, 0.0))
	var seat: PlayerController = _seat(wizard)
	var table: ActorsScript = _world.table
	check_equal(table.actor_of_seat(0), wizard.id, "seat 0 drives its wizard at first")
	check(seat.home() == wizard, "its home body is the wizard")
	_changed.clear()
	_stats.clear()
	# A possession as G9 does it: the wizard's body is left without a controller, the seat drives
	# the creature.
	wizard.drive(null)
	creature.drive(seat)
	check(seat.driven() == creature and seat.home() == wizard, "the seat drives the creature, its home is the wizard")
	check_equal(table.actor_of_seat(0), creature.id, "the actor table has seat 0 on the creature")
	check_equal(table.home_of_seat(0), wizard.id, "and seat 0's home body is still the wizard")
	check_equal(table.seat_of(creature.id), 0, "the creature's seat is 0")
	check_equal(table.seat_of(wizard.id), ActorsScript.NONE, "the wizard's body has no seat")
	check_equal(creature.team(), ActorsScript.TEAM_WIZARDS, "the creature is on the seat's team")
	check(_stats.is_empty(), "the seat's numbers do not become the creature's: %s" % [_stats])
	check(_changed.is_empty(), "nor its staffs: %s" % [_changed])
	# The seat's input moves and casts the creature, not the wizard.
	_world.hold(0, &"move_right")
	_run(1)
	check(is_equal_approx(creature.velocity.x, creature.mover.speed), "seat 0's stick walks the creature: %s" % creature.velocity)
	check_equal(wizard.velocity, Vector2.ZERO, "the wizard's body stands")
	_world.release(0, &"move_right")
	_staff_casts.clear()
	_tap(0, &"staff_1")
	_run(1)
	check_equal(_staff_casts, [[0, 0]], "seat 0's button casts the creature's staff, sent for seat 0")
	check(creature.caster.mana < creature.caster.max_mana, "with the creature's mana")
	check_equal(wizard.caster.mana, wizard.caster.max_mana, "not the wizard's")
	# Its numbers are the wizard's.
	_stats.clear()
	_world.hurt(creature, 10)
	check(_stats.is_empty(), "a hit on the creature is not seat 0's health: %s" % [_stats])
	_world.hurt(wizard, 10)
	check(not _stats.is_empty() and _stats.back()[0] == 0 and _stats.back()[1] == 90 and _stats.back()[2] == 100,
		"a hit on the standing wizard is: %s" % [_stats])
	# The builder builds the wizard's staffs.
	_changed.clear()
	var creature_row: Array[StringName] = creature.caster.cards_of(1)
	_world.bus.staff_cards_requested.emit(0, 1, _ids("fire bolt"))
	check_equal(wizard.caster.cards_of(1), _ids("fire bolt - - - -"), "seat 0's builder builds the wizard's staff")
	check_equal(creature.caster.cards_of(1), creature_row, "not the creature's")
	check_equal(_changed.size(), 1, "the change is announced once")
	if _changed.size() == 1:
		check_equal([_changed[0][0], _changed[0][1]], [0, 1], "for seat 0, staff 1")
		check_equal(_changed[0][2].get("cards"), _ids("fire bolt - - - -"), "with the wizard's new cards")
	_world.bus.staff_cards_requested.emit(0, 3, _ids("bolt"))
	check(_refused.is_empty() and wizard.caster.has_staff(3), "a staff the creature lacks is the wizard's to build")
	# Release: the creature stands again and the seat is its wizard's.
	_stats.clear()
	_changed.clear()
	creature.release()
	wizard.release()
	check(seat.driven() == wizard, "the seat drives its wizard again")
	check_equal(table.actor_of_seat(0), wizard.id, "the actor table has seat 0 on the wizard")
	check_equal(table.seat_of(creature.id), ActorsScript.NONE, "the creature has no seat")
	check_equal(creature.team(), ActorsScript.NONE, "nor the seat's team")
	check(not _stats.is_empty() and _stats.back()[1] == 90, "the wizard's numbers are sent again: %s" % [_stats])
	check_equal(_changed.size(), 4, "the wizard's four staffs are announced again")
	_world.hold(0, &"move_right")
	_run(1)
	check(is_equal_approx(wizard.velocity.x, wizard.mover.speed), "seat 0's stick walks the wizard again: %s" % wizard.velocity)
	check_equal(creature.velocity, Vector2.ZERO, "the creature stands")


func test_a_wizard_no_controller_drives_is_still_its_seats_panel_and_builder() -> void:
	var wizard := _wizard(0, [[&"bolt"], [], [], []])
	var seat: PlayerController = _seat(wizard)
	wizard.drive(null)
	_stats.clear()
	_changed.clear()
	_refused.clear()
	_staff_casts.clear()
	_world.hurt(wizard, 30)
	check(not _stats.is_empty() and _stats.back()[1] == 70, "its hit is seat 0's numbers: %s" % [_stats])
	check(wizard.caster.cast(0), "it can still be made to cast")
	_run(1)
	check(_stats.back()[3] < 100.0, "its mana spent shows: %s" % [_stats.back()])
	_run(16)
	check(wizard.caster.mana > wizard.caster.max_mana - 5.0, "it gets mana back")
	check_equal(_stats.back()[3], float(floori(wizard.caster.mana)), "which shows too, with no controller on it")
	check(_staff_casts.is_empty(), "a cast no seat pressed is no staff_cast")
	_world.bus.staff_cards_requested.emit(0, 1, _ids("orbit"))
	check_equal(wizard.caster.cards_of(1)[0], &"orbit", "seat 0's builder builds it")
	check(not _changed.is_empty() and _changed.back()[1] == 1, "and announces it")
	check(seat.driven() == null, "while the seat drives nothing")
