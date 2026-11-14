extends "res://tests/support/suite.gd"
## A run is made of the content flow is told to use (by registry id), not of fixed names, so a new
## room, enemy, start card, staff or wizard scene needs no edit in `flow.gd`. Uses the real autoloads.

const FlowScript := preload("res://gameplay/flow/flow.gd")

var flow: FlowScript
var input: Node


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	input.add_virtual_device(0)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	flow.world_parent = null
	flow.stop_run()
	flow.room_id_to_play = FlowScript.DEFAULT_ROOM_ID
	flow.enemy_id_to_play = FlowScript.DEFAULT_ENEMY_ID
	flow.start_cards = FlowScript.DEFAULT_START_CARDS.duplicate(true)
	flow.play_bag = FlowScript.PLAY_BAG.duplicate()
	flow.mode = FlowScript.MODE_WAVES
	flow.wizard_scene = FlowScript.DefaultWizardScene
	input.leave(0)


func test_the_defaults_are_the_m1_content() -> void:
	check_equal(flow.room_id_to_play, &"arena_01", "default room")
	check_equal(flow.enemy_id_to_play, &"ember_imp", "default enemy")
	check_equal(flow.start_cards, [[&"dash"], [&"bolt"], [], []], "default start cards: dash on A, bolt on X")
	check_equal(flow.play_bag, [&"dash", &"bolt"] as Array[StringName], "Play's bag: dash and bolt")


func test_an_unknown_room_starts_no_run() -> void:
	flow.room_id_to_play = &"no_such_room"
	check(not flow.start_run(0), "a missing room must not start a run")
	check_equal(flow.state, FlowScript.State.IDLE, "flow stays idle")


func test_an_unknown_enemy_starts_no_run() -> void:
	flow.enemy_id_to_play = &"no_such_enemy"
	check(not flow.start_run(0), "a missing enemy must not start a run")


## One staff file per setup, used as it is (owner, 2026-11-01): Play and the hub hold the first two
## basic staffs on RB and RT and two empty hands (items I2), the sandbox the dev staff on every
## button, in every build channel.
func test_each_mode_gets_its_own_staffs_as_they_are() -> void:
	var registry: Node = root.get_node("Registry")
	var dev: StaffBase = registry.call("get_resource", &"wizard", FlowScript.DEV_STAFF) as StaffBase
	for mode: StringName in [FlowScript.MODE_WAVES, FlowScript.MODE_SANDBOX, FlowScript.MODE_HUB]:
		flow.mode = mode
		var staffs: Array[StaffBase] = flow.staffs_for_mode()
		check_equal(staffs.size(), 4, "%s: four hands" % mode)
		if staffs.size() != 4:
			continue
		for at in 4:
			var wanted: StaffBase = dev
			if mode != FlowScript.MODE_SANDBOX:
				# Play and the hub (items I2): two staffs, RB and RT; LB and LT empty.
				wanted = registry.call("get_resource", &"wizard", flow.STARTER_HEADS[at]) as StaffBase if at < FlowScript.START_HANDS else null
			check(staffs[at] == wanted, "%s: button %d holds %s" % [mode, at, wanted.id if wanted != null else "nothing"])
	check_equal(FlowScript.START_HANDS, 2, "players start with two staffs")
	flow.mode = FlowScript.MODE_WAVES
	var heads: Dictionary = {}
	for id in FlowScript.STARTER_HEADS:
		heads[(registry.call("get_resource", &"wizard", id) as StaffBase).head] = true
	check_equal(heads.size(), 4, "the four basic staffs have four different heads")


## Each mode's setup (owner, 2026-11-05): a new wizard's card bag is the mode's, counted (items
## I3). Play: one dash and one bolt; the sandbox and the hub (owner, 2026-11-11 and 2026-11-13):
## Inventory.DEV_COPIES of every card, a joiner's too.
func test_each_mode_gives_its_own_bag() -> void:
	var registry: Node = root.get_node("Registry")
	var every: Dictionary = {}
	for id: StringName in registry.call("get_ids", &"spells"):
		if registry.call("get_resource", &"spells", id) is SpellComponent:
			every[id] = Inventory.DEV_COPIES
	var wanted: Dictionary = {
		FlowScript.MODE_WAVES: {&"dash": 1, &"bolt": 1},
		FlowScript.MODE_SANDBOX: every,
		FlowScript.MODE_HUB: every,
	}
	for mode: StringName in wanted:
		flow.mode = mode
		check_equal(flow.bag_for_mode(), wanted[mode], "%s: bag_for_mode" % mode)
		check(flow.start_run(0), "%s: a run starts" % mode)
		var wizard := flow.get_wizard(0) as Actor
		check(wizard != null, "%s: a wizard" % mode)
		if wizard != null:
			check_equal(_card_counts(wizard), wanted[mode], "%s: the wizard's bag" % mode)
		flow._on_player_joined(1)
		var joiner := flow.get_wizard(1) as Actor
		check(joiner != null, "%s: a joiner's wizard" % mode)
		if joiner != null:
			check_equal(_card_counts(joiner), wanted[mode], "%s: the joiner's bag" % mode)
		flow.stop_run()


## A mode's start cards are all in its bag, so taking one out can be undone.
func test_play_start_cards_are_in_its_bag() -> void:
	for pair: Array in [[FlowScript.DEFAULT_START_CARDS, FlowScript.PLAY_BAG]]:
		for staff: Array in pair[0]:
			for id: Variant in staff:
				check((pair[1] as Array).has(StringName(str(id))), "%s is in the bag %s" % [id, pair[1]])


func test_other_start_cards_reach_the_wizards() -> void:
	flow.start_cards = [[&"nova"], [&"frost", &"bolt"], [], []]
	check(flow.start_run(0), "the run starts with other start cards")
	var wizard: Actor = flow.get_wizard(0) as Actor
	var a: Array[StringName] = wizard.caster.cards_of(0)
	var b: Array[StringName] = wizard.caster.cards_of(1)
	check_equal(a[0], &"nova", "staff A holds the chosen card")
	check_equal(b.slice(0, 2), [&"frost", &"bolt"] as Array[StringName], "staff RT too")
	check(wizard.caster.has_staff(1), "a staff with cards is built")
	check(not wizard.caster.has_staff(2), "an empty hand has no build")


func test_the_chosen_wizard_scene_is_the_one_spawned() -> void:
	var stand_in := PackedScene.new()
	var holder: Node = own(FlowScript.DefaultWizardScene.instantiate()) as Node
	holder.name = "SwappedWizard"
	check_equal(stand_in.pack(holder), OK, "the stand-in scene packs")
	flow.wizard_scene = stand_in
	check(flow.start_run(0), "the run starts with the swapped scene")
	var wizard: Actor = flow.get_wizard(0) as Actor
	check(wizard != null and wizard.name == &"SwappedWizard", "the player got the swapped wizard scene")
	var seat: PlayerController = PlayerController.of(wizard)
	check_equal(seat.seat if seat != null else -1, 0, "the swapped wizard is player 0")
	check(wizard != null and wizard.caster.has_staff(1), "the swapped wizard holds its staffs")


func test_a_missing_wizard_scene_starts_no_run() -> void:
	flow.wizard_scene = null
	check(not flow.start_run(0), "no wizard scene must not start a run")
	check_equal(flow.state, FlowScript.State.IDLE, "flow stays idle")


func test_a_scene_without_the_player_script_starts_no_run() -> void:
	var plain := PackedScene.new()
	var holder: Node2D = own(Node2D.new()) as Node2D
	plain.pack(holder)
	flow.wizard_scene = plain
	check(not flow.start_run(0), "a scene that is not a player must not start a run")


func test_a_joiner_gets_the_wizard_scene_the_run_started_with() -> void:
	check(flow.start_run(0), "the run starts")
	var other := PackedScene.new()
	var holder: Node = own(FlowScript.DefaultWizardScene.instantiate()) as Node
	holder.name = "LaterWizard"
	other.pack(holder)
	flow.wizard_scene = other
	flow._on_player_joined(1)
	var joiner: Node = flow.get_wizard(1)
	check(joiner != null and joiner.name != &"LaterWizard", "a joiner mid-run keeps the run's wizard scene")


## `wizard`'s card bag as card id to copies.
func _card_counts(wizard: Actor) -> Dictionary:
	var out: Dictionary = {}
	for stack: ItemStack in wizard.inventory.stacks_in(ItemKinds.bag_of(ItemKinds.CARD)):
		out[stack.id] = stack.count
	return out


## A run that starts from a player loadout (items I4: the hub begun anew for a joining machine, a
## run from the stone) holds exactly it: its card bag counted as it was (no copy given twice, the
## regression of I3's review), its staffs under their numbers on their hands. A seat with no loadout
## gets the mode's.
func test_a_wizard_from_a_loadout_holds_exactly_it() -> void:
	flow.mode = FlowScript.MODE_HUB
	var loadout := PlayerLoadout.new()
	loadout.add_stack(&"cards", &"bolt", 17)
	loadout.add_stack(&"cards", &"fire", 1)
	loadout.add_staff(0, FlowScript.STARTER_HEADS[0], [&"bolt", &"bolt", &"bolt"] as Array[StringName])
	loadout.add_staff(5, FlowScript.DEV_STAFF, [&"fire"] as Array[StringName])
	loadout.set_hands(PackedInt32Array([0, PlayerLoadout.NO_STAFF, PlayerLoadout.NO_STAFF, PlayerLoadout.NO_STAFF]))
	var party := PartyLoadout.new()
	party.put(0, loadout)
	check(flow.start_run(0, party), "the hub starts with a loadout")
	var wizard := flow.get_wizard(0) as Actor
	check_equal(_card_counts(wizard), {&"bolt": 17, &"fire": 1}, "its card bag is the loadout's, no copy given twice")
	var held: PlayerLoadout = PlayerController.loadout_of(wizard)
	check(held.stack_ids(&"cards") == loadout.stack_ids(&"cards") and held.stack_counts(&"cards") == loadout.stack_counts(&"cards"), "its loadout's bags are the loadout's")
	check(held.staff_numbers() == loadout.staff_numbers() and held.hands() == loadout.hands(), "and its staffs' numbers and hands")
	for number: int in loadout.staff_numbers():
		var written: Array[StringName] = loadout.staff_cards(number)
		check(held.staff_id(number) == loadout.staff_id(number) and held.staff_cards(number).slice(0, written.size()) == written, "staff %d is the staff it was, with its cards (padded to its slots)" % number)
	check_equal(wizard.caster.cards_of(0).slice(0, 3), [&"bolt", &"bolt", &"bolt"] as Array[StringName], "RB's staff with its cards")
	check(not wizard.caster.holds(1), "RT empty, as the loadout has it")
	check_equal(wizard.inventory.hand_of(5), -1, "the dev staff in the staff bag")
	flow.stop_run()
