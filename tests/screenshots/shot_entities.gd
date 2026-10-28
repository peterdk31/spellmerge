extends "res://tests/support/screenshot.gd"
## Screenshots of the entity kit (staffs B5): each of four wizards with a decoy beside it and two
## familiars circling it (`entities_four_players`), and the same crop at 4x (`entities_4x`). The
## entities are asked for with `entity_spawn_requested`, as core/spells asks for them.

const TAG: int = 1 << 20


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
		wizard.global_position = Vector2(220.0 + 60.0 * float(index), 190.0)
		centre += wizard.global_position / 4.0
	await settle()
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		var at: Vector2 = wizard.global_position
		# Entities are owned by actor id: the actor this wizard opened (actors G3b).
		var caster: int = int(wizard.get("actor_id"))
		events.call("emit_signal", "entity_spawn_requested", caster, &"decoy", at + Vector2(0.0, 40.0), 30.0, TAG + index, -1)
		events.call("emit_signal", "entity_spawn_requested", caster, &"familiar", at + Vector2(20.0, -14.0), 30.0, TAG + index, -1)
		events.call("emit_signal", "entity_spawn_requested", caster, &"familiar", at + Vector2(-20.0, -14.0), 30.0, TAG + index, -1)
	await settle()
	if int(entities.call("count")) != 12:
		fail("there are %d entities, not 12, in entities_four_players" % int(entities.call("count")))
		return
	await snap(centre + Vector2(0.0, 10.0), "entities_four_players", Vector2i(160, 60), 1)
	await snap(centre + Vector2(-60.0, 10.0), "entities_4x", Vector2i(40, 40), 4)
	flow.call("stop_run")
	await create_timer(0.3).timeout
