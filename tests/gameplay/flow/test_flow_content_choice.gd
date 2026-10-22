extends "res://tests/support/suite.gd"
## A run is made of the content flow is told to use (by registry id), not of fixed names, so a new
## room, enemy, start spell or wizard scene needs no edit in `flow.gd`. Uses the real autoloads.

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
	flow.start_recipe_a = FlowScript.DEFAULT_START_RECIPE_A.duplicate(true)
	flow.start_recipe_b = FlowScript.DEFAULT_START_RECIPE_B.duplicate(true)
	flow.wizard_scene = FlowScript.DefaultWizardScene
	input.leave(0)


func test_the_defaults_are_the_m1_content() -> void:
	check_equal(flow.room_id_to_play, &"arena_01", "default room")
	check_equal(flow.enemy_id_to_play, &"ember_imp", "default enemy")
	check_equal(flow.start_recipe_a, {"form": &"bolt", "element": &"fire"}, "default spell A")
	check_equal(flow.start_recipe_b, {"form": &"bolt"}, "default spell B")


func test_an_unknown_room_starts_no_run() -> void:
	flow.room_id_to_play = &"no_such_room"
	check(not flow.start_run(0), "a missing room must not start a run")
	check_equal(flow.state, FlowScript.State.IDLE, "flow stays idle")


func test_an_unknown_enemy_starts_no_run() -> void:
	flow.enemy_id_to_play = &"no_such_enemy"
	check(not flow.start_run(0), "a missing enemy must not start a run")


func test_an_unknown_component_starts_no_run() -> void:
	flow.start_recipe_a = {"form": &"no_such_form"}
	check(not flow.start_run(0), "a start spell with a missing component must not start a run")
	check_equal(flow.state, FlowScript.State.IDLE, "flow stays idle")


func test_a_start_spell_without_a_form_starts_no_run() -> void:
	flow.start_recipe_b = {"element": &"fire"}
	check(not flow.start_run(0), "a start spell that does not compile must not start a run")


func test_other_start_recipes_reach_the_wizards() -> void:
	flow.start_recipe_a = {"form": &"nova"}
	check(flow.start_run(0), "the run starts with another start spell")
	var wizard: Node = flow.get_wizard(0)
	check_equal(wizard.call("recipe_of", 0), {"form": &"nova"}, "spell A is the chosen recipe")
	check_equal(wizard.call("recipe_of", 1), {"form": &"bolt"}, "spell B is the default")


func test_the_chosen_wizard_scene_is_the_one_spawned() -> void:
	var stand_in := PackedScene.new()
	var holder: Node = own(FlowScript.DefaultWizardScene.instantiate()) as Node
	holder.name = "SwappedWizard"
	check_equal(stand_in.pack(holder), OK, "the stand-in scene packs")
	flow.wizard_scene = stand_in
	check(flow.start_run(0), "the run starts with the swapped scene")
	var wizard: Node = flow.get_wizard(0)
	check(wizard != null and wizard.name == &"SwappedWizard", "the player got the swapped wizard scene")
	check_equal(wizard.get("index"), 0, "the swapped wizard is player 0")
	check(wizard.call("has_spell") as bool, "the swapped wizard holds a spell")


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
