extends "res://tests/support/screenshot.gd"
## What a possession draws over the possessed actor (owner, 2026-10-28): player 1 drives an ember
## imp (its health and mana bars beside the timer, in player 1's colour), and another imp's AI
## drives player 1's standing wizard (only the timer, in the enemy ramp). The corner panel stays
## the wizard's. `possess_1x` as a player sees it, `possess_4x` the two overlays enlarged.

const IMP_SCENE := preload("res://content/enemies/ember_imp/ember_imp.tscn")
const IMP_DATA := preload("res://content/enemies/ember_imp/ember_imp.tres")
## Long enough to outlast the shots.
const SECONDS: float = 60.0


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Combat"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var combat: Node = root.get_node("Combat")
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	await settle()
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	if wizard == null:
		fail("there is no wizard for player 1")
		return
	var driven: Actor = _imp(wizard.global_position + Vector2(48.0, -8.0))
	var taker: Actor = _imp(wizard.global_position + Vector2(-48.0, 8.0))
	await settle(2)
	var mine: Possession = Possession.begin(wizard, driven, SECONDS)
	if mine == null:
		fail("player 1 could not possess the imp")
		return
	var theirs: Possession = Possession.begin(taker, wizard, SECONDS)
	if theirs == null:
		fail("the imp could not possess the wizard")
		return
	# Part way through, so the timers' arcs show the time running out.
	mine.left = SECONDS * 0.6
	theirs.left = SECONDS * 0.3
	# The driven imp has taken a hit and cast once, so both bars are part full.
	combat.call("hit", wizard.id, driven, 12)
	driven.caster.mana = driven.caster.max_mana * 0.6
	await settle(20)
	var centre: Vector2 = (driven.global_position + wizard.global_position) * 0.5 + Vector2(0.0, -20.0)
	await snap(centre, "possess_4x", Vector2i(72, 36), 4)
	await snap(centre, "possess_1x", Vector2i(160, 90), 1)


## An ember imp at `at`, in the room.
func _imp(at: Vector2) -> Actor:
	var body := IMP_SCENE.instantiate() as Actor
	body.data = IMP_DATA
	root.add_child(body)
	body.global_position = at
	return body
