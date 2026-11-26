extends "res://tests/support/screenshot.gd"
## Sigils (docs/milestones/staff-language.md, L4) in the hub: player 1's RT staff (a fire bolt) gets Cast when
## Hurt and Cast when Close, the wizard is hurt below half, and its staff casts by itself
## (`staff_sigils_play`: the corner panel's row with the two sigil icons, glowing); then the inventory
## open on the Sigils bag (`staff_sigils_bag`), and the builder's hub saying what the staff does by
## itself (`staff_sigils_builder`).

const DevHub := preload("res://tests/support/dev_hub.gd")
const SIGILS: Array[StringName] = [&"cast_when_hurt", &"cast_when_close"]

var _input: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_hud = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	_input.call("add_virtual_device", 0)
	if not DevHub.start(flow, root.get_node("Registry")):
		fail("the hub did not start")
		return
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 0) != null):
		fail("the hub did not start with a wizard")
		return
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	var number: int = wizard.inventory.hands()[1]
	for id: StringName in SIGILS:
		wizard.inventory.add(ItemStack.of(ItemKinds.SIGIL, id, 2))
		wizard.inventory.put_sigil(number, id)
	wizard.health.take(wizard.health.max_health * 0.6)
	await settle(40)
	await shot("staff_sigils_play")
	var inventory: Node = _hud.call("get_inventory", 0)
	inventory.call("open_inventory")
	await settle(4)
	inventory.call("point_at", inventory.call("entry_of", "bag", &"sigils"))
	inventory.call("enter_pointed")
	await settle(4)
	inventory.call("point_at", 0)
	await settle(8)
	await shot("staff_sigils_bag")
	inventory.call("close_inventory")
	await settle(4)
	_hud.call("_on_builder_options_changed", 0, true)
	tap(0, &"back")
	if not await wait_for(func() -> bool: return _hud.call("get_radial", 0).call("is_open")):
		fail("the radial builder did not open")
		return
	await settle(8)
	await shot("staff_sigils_builder")
	tap(0, &"back")
	await settle(8)
	flow.call("stop_run")
	await create_timer(0.3).timeout
