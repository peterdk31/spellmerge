extends "res://tests/support/screenshot.gd"
## Screenshots of the radial builder's ring styles (owner, 2026-10-30; hud/builder/rings/), in
## the sandbox: the zoom ring locked on a card (its fan spread under the stick), the kinds ring
## with Hold (resting on the modifiers, the sector filling) and the modifiers unwrapped with one
## picked, and with Depth (half a push pointing at the elements, then pushed out and open).

var _input: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_hud = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	_input.call("add_virtual_device", 0)
	root.get_node("Events").emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 0) != null):
		fail("the sandbox did not start")
		return
	# Zoom (ring 2): held still on a modifier, then turned a little inside the fan.
	_hud.call("_on_builder_options_changed", true, 2, true)
	if not await _open():
		return
	var radial: Node = _hud.call("get_radial", 0)
	var start: Vector2 = radial.call("direction_to", &"pierce")
	_input.call("send_virtual_aim", 0, start)
	await settle(20)
	_input.call("send_virtual_aim", 0, start.rotated(0.35))
	await settle(8)
	await shot("radial_zoom_locked")
	await _close()
	# Kinds: hold (ring 3): resting on the modifiers, half way, then open with a card picked.
	_hud.call("_on_builder_options_changed", true, 3, true)
	if not await _open():
		return
	var kinds: RefCounted = radial.get("ring_picker")
	var modifiers: Vector2 = kinds.call("kind_direction", radial, &"modifier")
	_input.call("send_virtual_aim", 0, modifiers)
	# Grabbed at once (shot() would settle past the hold time).
	await settle(8)
	save(await grab(), "radial_kinds_hold_resting")
	await settle(20)
	_input.call("send_virtual_aim", 0, kinds.call("card_direction", radial, &"homing"))
	await settle(8)
	await shot("radial_kinds_open")
	await _close()
	# Kinds: depth (ring 4): half a push on the elements, then pushed out.
	_hud.call("_on_builder_options_changed", true, 4, true)
	if not await _open():
		return
	kinds = radial.get("ring_picker")
	var elements: Vector2 = kinds.call("kind_direction", radial, &"element")
	_input.call("send_virtual_aim", 0, elements * 0.6)
	await settle(8)
	await shot("radial_kinds_depth_pointing")
	_input.call("send_virtual_aim", 0, elements)
	await settle(8)
	await shot("radial_kinds_depth_open")
	await _close()
	flow.call("stop_run")
	await create_timer(0.3).timeout


func _open() -> bool:
	tap(0, &"back")
	var opened: bool = await wait_for(func() -> bool: return _hud.call("get_radial", 0).call("is_open"))
	if not opened:
		fail("the radial builder did not open")
	return opened


func _close() -> void:
	_input.call("send_virtual_aim", 0, Vector2.ZERO)
	tap(0, &"back")
	await settle(8)
