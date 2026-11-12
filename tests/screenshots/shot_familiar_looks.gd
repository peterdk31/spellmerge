extends "res://tests/support/screenshot.gd"
## The familiar's own look (content/spells/carriers/familiar/familiar.gdshader; the owner, 2026-11-08:
## rework the carriers' looks): each of four wizards with two familiars circling it, in their
## owners' ramps (`familiar_looks`, the four at 3x), and one wizard's at 6x
## (`familiar_looks_6x`), so the orb's eyes, glint and wisp can be judged. Asked for with
## `entity_spawn_requested`, as core/spells asks for them.

const TAG: int = 1 << 21


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Events", "Entities"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	var entities: Node = root.get_node("Entities")
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	for i in 4:
		await settle()
	var centre: Vector2 = Vector2.ZERO
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		wizard.global_position = Vector2(230.0 + 60.0 * float(index), 270.0)
		centre += wizard.global_position / 4.0
	await settle()
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		var at: Vector2 = wizard.global_position
		# Entities are owned by actor id: the actor this wizard opened (actors G3b).
		var caster: int = int(wizard.get("id"))
		events.call("emit_signal", "entity_spawn_requested", caster, &"familiar", at + Vector2(20.0, -6.0), 30.0, TAG + index, -1)
		events.call("emit_signal", "entity_spawn_requested", caster, &"familiar", at + Vector2(-20.0, 6.0), 30.0, TAG + index, -1)
	# Past the wave's banner.
	for i in 6:
		await settle()
	if int(entities.call("count")) != 8:
		fail("there are %d familiars, not 8, in familiar_looks" % int(entities.call("count")))
		return
	await snap(centre, "familiar_looks", Vector2i(220, 70), 3)
	var first: Node2D = flow.call("get_wizard", 0) as Node2D
	await snap(first.global_position, "familiar_looks_6x", Vector2i(60, 50), 6)
	flow.call("stop_run")
	await create_timer(0.3).timeout
