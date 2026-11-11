extends "res://tests/support/screenshot.gd"
## Every prop in every state (props W7, docs/milestones/props.md, "W7: the look"): in the arena, a
## row a prop (the registry's `props`, by id, then the test exploding barrel,
## tests/gameplay/actor/fixtures/exploding_barrel.tres), a column a state, each body made by
## `PropBody.make` and put into its state as a trigger would, its look's art, motes and light
## showing; each prop's cells as big as its art (a barrel to the hub's 96 px stone). `props` is the
## whole sheet a moment later (the motes given off), `props_4x` the first prop close up.

const TEST_BARREL: PropBase = preload("res://tests/gameplay/actor/fixtures/exploding_barrel.tres")
## Pixels round each prop's art, and the widest a row of the sheet runs (inside the arena's walls).
const PAD: float = 12.0
const ROW_WIDTH: float = 560.0
## The arena's middle, where the sheet is centred.
const CENTRE: Vector2 = Vector2(320.0, 192.0)


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	input.call("add_virtual_device", 0)
	# Still training dummies for the wave, so nothing walks across the sheet.
	var enemy_was: StringName = flow.get("enemy_id_to_play")
	flow.set("enemy_id_to_play", &"training_dummy")
	flow.call("start_run", 0)
	flow.set("enemy_id_to_play", enemy_was)
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
	wizard.global_position = Vector2(600.0, 340.0)
	# The pillars' art and shade are drawn over a floor slab, the wave's banner over the sheet: hidden
	# here (only what is drawn).
	var layout: Node = wizard.get_parent().get_child(0)
	for node: Node in layout.find_children("Pillar*", "CanvasItem", true, false):
		(node as CanvasItem).visible = false
	var shade := layout.get_node_or_null("Shade") as CanvasItem
	if shade != null:
		shade.visible = false
	var hud: Node = root.get_node_or_null("Hud")
	if hud != null:
		hud.set("visible", false)
	# Each prop a block of its states side by side, a cell as big as its biggest art (props differ
	# from a barrel to the hub's 96 px stone); blocks run in rows across the arena.
	var cells: Array[Rect2] = []
	var x: float = 0.0
	var y: float = 0.0
	var row_height: float = 0.0
	var width: float = 0.0
	for data in props:
		var cell: Vector2 = _art_size(data) + Vector2(PAD, PAD)
		var states: int = data.states.list.size() if data.states != null else 1
		if x > 0.0 and x + cell.x * float(states) > ROW_WIDTH:
			y += row_height
			x = 0.0
			row_height = 0.0
		cells.append(Rect2(Vector2(x, y), cell))
		x += cell.x * float(states)
		width = maxf(width, x)
		row_height = maxf(row_height, cell.y)
	var sheet := Rect2(CENTRE - Vector2(width, y + row_height) * 0.5, Vector2(width, y + row_height))
	for i in props.size():
		var data: PropBase = props[i]
		for column in (data.states.list.size() if data.states != null else 1):
			var body: Actor = PropBody.make(data)
			if body == null:
				continue
			wizard.get_parent().add_child(body)
			var cell := Rect2(sheet.position + cells[i].position + Vector2(cells[i].size.x * float(column), 0.0), cells[i].size)
			# The art's bottom middle on the cell's (less its padding), the feet where its layer puts them.
			var bottom := Vector2(cell.get_center().x, cell.end.y - PAD * 0.5)
			body.global_position = (bottom - _first_offset(data)).round()
			if column > 0:
				_put_in(body, data.states.list[column].state_id)
	# The motes given off for a while (under the test barrel's 1 s fuse).
	for i in 40:
		await physics_frame
		await process_frame
	await snap(sheet.get_center(), "props", Vector2i(sheet.size * 0.5) + Vector2i(4, 4), 2)
	var first := Rect2(sheet.position + cells[0].position, Vector2(cells[0].size.x * float(props[0].states.list.size()), cells[0].size.y))
	await snap(first.get_center(), "props_4x", Vector2i(first.size * 0.5) + Vector2i(2, 2), 4 if first.size.y <= 48.0 else 2)
	if hud != null:
		hud.set("visible", true)
	flow.call("stop_run")
	await create_timer(0.3).timeout


## The biggest frame of any layer of any of its looks.
func _art_size(data: PropBase) -> Vector2:
	var most := Vector2(16.0, 16.0)
	for look in data.looks:
		for layer in look.layers:
			if layer != null:
				most = most.max(Vector2(layer.frame_size()))
	return most


## Where its first look's first layer stands from its feet (a slab's is below its middle).
func _first_offset(data: PropBase) -> Vector2:
	for look in data.looks:
		if look != null and not look.layers.is_empty() and look.layers[0] != null:
			return look.layers[0].offset
	return Vector2.ZERO


## `body` in its state `state_id`, entered as a trigger enters it (its look follows, its cue plays).
func _put_in(body: Actor, state_id: StringName) -> void:
	if body.state_triggers != null:
		body.state_triggers.enter(state_id)
