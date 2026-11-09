extends "res://tests/support/screenshot.gd"
## Orbit on every carrier it circles (docs/milestones/carrier-modifiers.md Part 5, 5B step 5): three
## wizards side by side in the sandbox, fire; fire and frost; frost, void, fire and lightning (the dev staff, for six
## cards), each casting `orbit · <carrier>` to the right, pictured a moment later as it goes round.
## One sheet a carrier, at 2x: `orbit_bolt`, `orbit_atom`, `orbit_swap`, `orbit_rune` (armed and
## circling), `orbit_pool`, `orbit_wall` (its row turns with its circle) and `orbit_beam` (it sweeps,
## the whole staff turning round the hand with it).

const STAFF := preload("res://content/wizard/staffs/dev/dev.tres")
const INFUSIONS: Array = [[&"fire"], [&"fire", &"frost"], [&"frost", &"void", &"fire", &"lightning"]]
## The beam last: a live beam is not a projectile, so `clear` leaves it, and it would show on the next.
const CARRIERS: Array[StringName] = [&"bolt", &"atom", &"swap", &"rune", &"pool", &"wall", &"beam"]
## Frames after the cast for each carrier: long enough to have gone round a little (a rune arms first).
const WAIT: Dictionary = {&"rune": 80}
const DEFAULT_WAIT: int = 30
## Where each wizard stands: the sandbox room's open floor, clear of its middle pillar and its walls
## by more than a circle (walls end what circles), and the middle of the picture.
const PLACES: Array[Vector2] = [Vector2(180.0, 200.0), Vector2(420.0, 200.0), Vector2(540.0, 200.0)]
const MIDDLE := Vector2(360.0, 200.0)

var _input: Node = null
var _spells: Node = null
var _shots: Node = null
var _row: Array[Actor] = []


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
	flow.set(&"mode", &"sandbox")
	flow.call("start_run", 0)
	await settle(30)
	for p in 3:
		var wizard: Actor = flow.call("get_wizard", p) as Actor
		if wizard == null:
			fail("there is no wizard for player %d" % (p + 1))
			return
		_row.append(wizard)
	for carrier: StringName in CARRIERS:
		await _cast(carrier, int(WAIT.get(carrier, DEFAULT_WAIT)))
		await snap(MIDDLE, "orbit_%s" % carrier, Vector2i(460, 110), 2)


## Clear the shots, put the wizards side by side, give each a staff of its infusions, Orbit and
## `carrier`, cast it to the right and wait `frames` frames. The last sheet's shots are cleared and
## the staffs are ready again (as the tests do: `Spells.clear` would also forget the wizards' aims).
func _cast(carrier: StringName, frames: int) -> void:
	_shots.call("clear")
	var ready: PackedFloat32Array = _spells.get(&"_cooldown")
	ready.fill(0.0)
	_spells.set(&"_cooldown", ready)
	for p in 3:
		_row[p].global_position = PLACES[p]
		_input.call("send_virtual_aim", p, Vector2.RIGHT)
		var cards: Array[StringName] = []
		cards.assign(INFUSIONS[p])
		cards.append(&"orbit")
		cards.append(carrier)
		_spells.call("install_staff", _row[p].id, 3, _spells.call("compile_staff", cards, STAFF))
	await settle(20)
	for p in 3:
		_row[p].global_position = PLACES[p]
		_spells.call("cast_staff", _row[p].id, 3, _row[p].global_position, Vector2.RIGHT, 100.0)
	for frame in frames:
		await physics_frame
