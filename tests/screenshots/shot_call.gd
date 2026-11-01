extends "res://tests/support/screenshot.gd"
## The call (enemy AI L4, docs/milestones/M2-enemy-ai.md): two strays (Cinder Rods), one above
## the other, to the right of player 1's wizard in the sandbox. Before its windup one glances at the
## other, its brows raised, and the other joins in: furious, its telegraph up. `call_6x` is the two
## of them enlarged mid-call, `call_1x` the same moment as a player sees it.

const IMP_SCENE := preload("res://content/enemies/ember_imp/ember_imp.tscn")
const IMP_DATA := preload("res://content/enemies/ember_imp/ember_imp.tres")
## How far the strays stand from the wizard (inside a fire bolt's range band) and apart.
const AWAY: float = 130.0
const APART: float = 30.0


func take() -> void:
	if not need(["PlayerInput", "Flow", "Events"]):
		return
	var flow: Node = root.get_node("Flow")
	root.get_node("PlayerInput").call("add_virtual_device", 0)
	root.get_node("Events").emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return flow.get("sandbox") and flow.call("get_wizard", 0) != null):
		fail("the sandbox did not start")
		return
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	await settle(10)
	var keen: AIProfile = IMP_DATA.profile_or_fallback().duplicate() as AIProfile
	# Always calls when it may (the shot waits for one), and never dodges off the spot.
	keen.teamwork = 1.0
	keen.dodge = 0.0
	keen.randomness = 0.0
	var strays: Array[Actor] = []
	for side: float in [-1.0, 1.0]:
		strays.append(_stray(wizard.global_position + Vector2(AWAY, side * APART * 0.5), keen))
	var calling: Array[AIBrain] = [null]
	var called: bool = await wait_for(func() -> bool:
		for body in strays:
			var brain: AIBrain = (body.get_node(^"AIController") as AIController).brain
			if brain.state == AIBrain.State.CALL:
				calling[0] = brain
				return true
		return false, 300)
	if not called:
		fail("neither stray called")
		return
	# A few frames in: the other stray has heard it and winds up.
	await settle(6)
	if calling[0].state != AIBrain.State.CALL:
		fail("the call was over before the shot")
		return
	var middle: Vector2 = (strays[0].global_position + strays[1].global_position) * 0.5 + Vector2(0.0, -20.0)
	var image: Image = await grab()
	save_crop(image, on_screen(middle), "call_6x", Vector2i(24, 36), 6)
	save_crop(image, on_screen(middle - Vector2(AWAY * 0.5, 0.0)), "call_1x", Vector2i(160, 90), 1)


## A Cinder Rod at `at` in the sandbox room, playing by `profile`.
func _stray(at: Vector2, profile: AIProfile) -> Actor:
	var body := IMP_SCENE.instantiate() as Actor
	body.data = IMP_DATA
	(body.get_node(^"AIController") as AIController).profile = profile
	root.add_child(body)
	body.global_position = at
	return body
