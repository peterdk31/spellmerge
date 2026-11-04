extends "res://tests/support/screenshot.gd"
## The moments that had no look before S6 item 13 (docs/milestones/spell-spectacle-2.md): a horde
## level-up, a gem picked up, a revive, a barrier blocking a hit, a body caught by a pull and a
## wave starting, each its cue (content/cues), played by name in the live game as player 1's
## wizard's, in a row (`moment_cues_1x` as a player sees it, `moment_cues_4x` enlarged), a few
## frames in. Their starter looks are for the owner to tune; before item 13 they drew nothing.

## The cues, left to right.
const CUES: Array[StringName] = [&"level_up", &"gem_pickup", &"revive", &"shield_block", &"pull", &"wave_start"]
## Pixels between neighbours.
const GAP: float = 40.0


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Events"]):
		return
	# On game time, as in play (Feel ages its flashes on the real clock otherwise).
	if root.has_node("Feel"):
		root.get_node("Feel").set("drive_engine", false)
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	await settle()
	var wizard: Node2D = flow.call("get_wizard", 0) as Node2D
	if wizard == null:
		fail("there is no wizard for player 1")
		return
	var caster: int = int(wizard.get("id"))
	var centre: Vector2 = wizard.global_position + Vector2(0.0, -36.0)
	for i in CUES.size():
		var at: Vector2 = centre + Vector2((float(i) - (CUES.size() - 1) * 0.5) * GAP, 0.0)
		events.call("emit_signal", "cue_shown", caster, CUES[i], at, Vector2.LEFT, 0.0, Color.WHITE, 0)
	await settle(5)
	await snap(centre, "moment_cues_4x", Vector2i(roundi(GAP * CUES.size()), 48), 4)
	await snap(centre, "moment_cues_1x", Vector2i(roundi(GAP * CUES.size()), 48), 1)
