extends "res://tests/support/screenshot.gd"
## The portal's mote rift (the owner's pick, 2026-11-09; gameplay/feel/portal_look.gd: the lens the card's shader, the lips real motes) with one, two
## and four infusions: three wizards in a column, fire; fire and frost; frost, void, fire and
## lightning (the dev staff, for five cards), each casting a portal to the right. `portal_rifts` open (a lip an infusion, the motes in
## turn), `portal_rifts_opening` a tenth of a second after they open (tall, not yet wide), both at
## 2x, and `portal_rifts_close` the four infusions' mouth at 5x.

const STAFF := preload("res://content/wizard/staffs/dev/dev.tres")
const INFUSIONS: Array = [[&"fire"], [&"fire", &"frost"], [&"frost", &"void", &"fire", &"lightning"]]
## Pixels between the wizards' rows.
const ROW: float = 44.0

var _input: Node = null
var _spells: Node = null
var _shots: Node = null
var _row: Array[Actor] = []
var _start: Vector2 = Vector2.ZERO


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Spells", "Feel", "Projectiles"]):
		return
	_input = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	_spells = root.get_node("Spells")
	_shots = root.get_node("Projectiles")
	root.get_node("Feel").set("drive_engine", false)
	for p in 3:
		_input.call("add_virtual_device", p)
	flow.call("start_run", 0)
	await settle(30)
	for p in 3:
		var wizard: Actor = flow.call("get_wizard", p) as Actor
		if wizard == null:
			fail("there is no wizard for player %d" % (p + 1))
			return
		_row.append(wizard)
	_start = _row[0].global_position + Vector2(-60.0, -ROW - 30.0)
	await _cast(50)
	var image: Image = await grab()
	save_crop(image, on_screen(_start + Vector2(100.0, ROW)), "portal_rifts", Vector2i(130, 84), 2)
	var mouth: Vector2 = _row[2].global_position + Vector2(22.0, 4.0)
	save_crop(image, on_screen(mouth), "portal_rifts_close", Vector2i(30, 24), 5)
	await _cast(6)
	await snap(_start + Vector2(100.0, ROW), "portal_rifts_opening", Vector2i(130, 84), 2)


## Clear the shots, put the wizards in a column, give each a staff of its infusions and a portal,
## cast it to the right and wait `frames` frames.
func _cast(frames: int) -> void:
	_shots.call("clear")
	for p in 3:
		_row[p].global_position = _start + Vector2(0.0, ROW * p)
		_input.call("send_virtual_aim", p, Vector2.RIGHT)
		var cards: Array[StringName] = []
		cards.assign(INFUSIONS[p])
		cards.append(&"portal")
		_spells.call("install_staff", _row[p].id, 3, _spells.call("compile_staff", cards, STAFF))
	await settle(20)
	for p in 3:
		_row[p].global_position = _start + Vector2(0.0, ROW * p)
		_spells.call("cast_staff", _row[p].id, 3, _row[p].global_position, Vector2.RIGHT, 100.0)
	for frame in frames:
		await physics_frame
