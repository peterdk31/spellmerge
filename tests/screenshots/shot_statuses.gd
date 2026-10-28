extends "res://tests/support/screenshot.gd"
## Screenshots of enemy statuses: one ember imp each with burning, chill, freeze, shock, hex and
## static, in a row in the live game (`statuses_1x`, as a player sees them, and `statuses_4x`),
## then a reaction bursting over the row (`status_reaction_1x`).

const IMP_SCENE := preload("res://content/enemies/ember_imp/ember_imp.tscn")
const IDS: Array[StringName] = [&"burn", &"chill", &"freeze", &"shock", &"hex", &"static"]
## Pixels between neighbours in the row.
const GAP: float = 40.0
## Status seconds, long enough to outlast the shots.
const SECONDS: float = 20.0


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Events", "Combat"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	var combat: Node = root.get_node("Combat")
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	await settle()
	var wizard: Node2D = flow.call("get_wizard", 0) as Node2D
	var centre: Vector2 = wizard.global_position + Vector2(0.0, -60.0)
	# Statuses and reactions name their caster by actor id: the actor the wizard opened (actors G3b).
	var caster: int = int(wizard.get("id"))
	var imps: Array[Node2D] = []
	for i in IDS.size():
		var imp := Node2D.new()
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = load("res://content/enemies/ember_imp/idle.svg") as Texture2D
		sprite.hframes = 2
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		imp.add_child(sprite)
		root.add_child(imp)
		imp.global_position = centre + Vector2((float(i) - 2.5) * GAP, 0.0)
		combat.call("register_actor", imp, 400, 10.0)
		imps.append(imp)
	for i in IDS.size():
		var id: StringName = IDS[i]
		if id == &"freeze":
			# Three chills in a row freeze.
			for k in 3:
				combat.call("apply_status", caster, imps[i], &"chill", SECONDS, 30.0)
		else:
			combat.call("apply_status", caster, imps[i], id, SECONDS, 5.0)
	await _snap(centre, "statuses_4x", 4)
	await _snap(centre, "statuses_1x", 1)
	events.call("emit_signal", "reaction_triggered", caster, &"shatter", centre + Vector2(GAP * 0.5, 0.0))
	await _snap(centre, "status_reaction_1x", 1)


## Let the flashes grow for a few frames, then save a crop around the world point `at`,
## `zoom` times bigger than the game draws it (1 is the real size).
func _snap(at: Vector2, name: String, zoom: int) -> void:
	await settle(3)
	await snap(at, name, Vector2i(128, 40) if zoom == 4 else Vector2i(120, 40), zoom)
