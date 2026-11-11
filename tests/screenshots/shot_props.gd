extends "res://tests/support/screenshot.gd"
## Every prop in every state (props W7, docs/milestones/props.md, "W7: the look"): in the arena, a
## row a prop (the registry's `props`, by id, then the test exploding barrel,
## tests/gameplay/actor/fixtures/exploding_barrel.tres), a column a state, each body made by
## `PropBody.make` and put into its state as a trigger would, its look's art, motes and light
## showing. `props` is the whole sheet a moment later (the motes given off), `props_4x` the first
## row close up.

const TEST_BARREL: PropBase = preload("res://tests/gameplay/actor/fixtures/exploding_barrel.tres")
## The gap between two props, either way (px).
const GAP: Vector2 = Vector2(40.0, 44.0)


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	for i in 4:
		await settle()
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	if wizard == null:
		fail("no wizard in the arena")
		return
	var props: Array[PropBase] = []
	for resource: Resource in registry.call("get_all", &"props"):
		if resource is PropBase:
			props.append(resource as PropBase)
	props.append(TEST_BARREL)
	var columns: int = 1
	for data in props:
		columns = maxi(columns, data.states.list.size() if data.states != null else 1)
	# The open floor between the arena's pillars and the spawns; the wizard aside.
	var centre: Vector2 = Vector2(320.0, 280.0)
	wizard.global_position = Vector2(500.0, 320.0)
	var corner: Vector2 = centre - Vector2(GAP.x * float(columns - 1), GAP.y * float(props.size() - 1)) * 0.5 + Vector2(0.0, 12.0)
	for row in props.size():
		var data: PropBase = props[row]
		for column in (data.states.list.size() if data.states != null else 1):
			var body: Actor = PropBody.make(data)
			if body == null:
				continue
			wizard.get_parent().add_child(body)
			body.global_position = (corner + GAP * Vector2(column, row)).round()
			if column > 0:
				_put_in(body, data.states.list[column].state_id)
	for i in 40:
		await physics_frame
		await process_frame
	var half := Vector2i(int(GAP.x * float(columns)) / 2 + 8, int(GAP.y * float(props.size())) / 2 + 8)
	await snap(centre, "props", half, 2)
	await snap(corner + Vector2(GAP.x * float(columns - 1) * 0.5, -12.0), "props_4x", Vector2i(int(GAP.x * float(columns)) / 2 + 4, 20), 4)
	flow.call("stop_run")
	await create_timer(0.3).timeout


## `body` in its state `state_id`, entered as a trigger enters it (its look follows, its cue plays).
func _put_in(body: Actor, state_id: StringName) -> void:
	if body.state_triggers != null:
		body.state_triggers.enter(state_id)
