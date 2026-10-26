extends SceneTree
## Screenshots of the radial builder (owner, 2026-10-26), for people and for Claude to look at
## (not a test: it only checks that each staged state happened). Needs a display, so it runs only
## through `ci/build/build.sh --quick --screenshots`; each shot is saved as
## user://screenshots/<name>.png and copied to build/screenshots/.
##
## Shots, in the sandbox with the radial builder picked: one player pointing at a nova (the hub
## shows its numbers, the marked slot its ghost, the numbers what RT would change), then after
## two cards were put in, the one-kind ring on the modifiers, a clear held half way, and all four
## players with their radials open at once.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20

var _input: Node = null
var _hud: Node = null


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	_input = root.get_node_or_null("PlayerInput")
	_hud = root.get_node_or_null("Hud")
	var flow: Node = root.get_node_or_null("Flow")
	var events: Node = root.get_node_or_null("Events")
	if _input == null or _hud == null or flow == null or events == null:
		_fail("the PlayerInput, Hud, Flow and Events autoloads must exist")
		return
	for index in 4:
		_input.call("add_virtual_device", index)
	events.emit_signal("sandbox_requested", 0)
	for i in 4:
		await _settle()
	_hud.call("_on_builder_options_changed", true, false, true)
	await _open(0)
	var radial: Node = _hud.call("get_radial", 0)
	if not radial.call("is_open"):
		_fail("the radial builder of player 1 is not open")
		return
	await _point(0, &"nova", false)
	await _shot("radial_pointing")
	_tap(0, &"staff_2")
	await _point(0, &"split", false)
	_tap(0, &"staff_2")
	await _point(0, &"homing", true)
	await _shot("radial_built")
	_hud.call("_on_builder_options_changed", true, true, true)
	_tap(0, &"kind_next")
	await _settle()
	await _point(0, &"pierce", true)
	await _shot("radial_one_kind")
	_input.call("send_virtual", 0, &"extra", 1.0)
	await create_timer(0.3).timeout
	await _shot("radial_clearing")
	_input.call("send_virtual", 0, &"extra", 0.0)
	_hud.call("_on_builder_options_changed", true, false, true)
	for index in range(1, 4):
		await _open(index)
	var cards: Array[StringName] = [&"bolt", &"frost", &"orbit", &"chain"]
	for index in 4:
		if not _hud.call("get_radial", index).call("is_open"):
			_fail("the radial builder of player %d is not open" % (index + 1))
			return
		await _point(index, cards[index], true)
	await _shot("radial_four_players")
	for index in 4:
		_tap(index, &"back")
	await _settle()
	flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


func _tap(player: int, action: StringName) -> void:
	_input.call("send_virtual", player, action, 1.0)
	_input.call("send_virtual", player, action, 0.0)


func _open(player: int) -> void:
	_tap(player, &"back")
	await _settle()


## Point `player`'s right stick at `id`, held (the pointer line shows) or let go again.
func _point(player: int, id: StringName, hold: bool) -> void:
	var direction: Vector2 = _hud.call("get_radial", player).call("direction_to", id)
	_input.call("send_virtual_aim", player, direction)
	await _settle()
	if not hold:
		_input.call("send_virtual_aim", player, Vector2.ZERO)
		await _settle()


func _fail(message: String) -> void:
	printerr("SHOT FAILED: " + message)
	quit(1)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame


func _shot(shot_name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [SHOTS_DIR, shot_name]
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		return
	print("SHOT: %s (%dx%d)" % [shot_name, image.get_width(), image.get_height()])
