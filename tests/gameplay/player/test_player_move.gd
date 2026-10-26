extends SceneTree
## Tests for gameplay/player (move and dash): the speeds, the dash a dash card asks for (staffs
## A6a: `caster_move_requested`, no invulnerability, `caster_move_finished` where it ends), a
## captured player, and two players (and all four) at once without touching each other. Input goes through the real
## input manager's virtual devices; time moves by fixed deltas. The step and the
## timings are binary fractions, so the timers add up exactly.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_move.gd

const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")

const STEP: float = 0.0625
## A dash as the dash card asks for it: 55 px over a quarter of a second (220 px/s).
const DASH_DISTANCE: float = 55.0
const DASH_TIME: float = 0.25
const DASH_SPEED: float = 220.0

var _failures: Array[String] = []
var _bus: Node
var _input: Node
var _players: Array[PlayerScript] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_wizard_scene()
	_test_stands_still()
	_test_walks_at_move_speed()
	_test_diagonal_is_not_faster()
	_test_dash_runs_at_the_card_speed_without_invulnerability()
	_test_dash_without_direction_uses_facing()
	_test_dash_direction_is_locked()
	_test_dash_end_is_reported_where_it_stopped()
	_test_dash_for_another_player_is_ignored()
	_test_captured_player_cannot_move()
	_test_capture_during_dash_ends_it()
	_test_two_players_at_once()
	_test_four_players_at_once()
	_test_no_input_manager()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: gameplay/player (move and dash)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(count: int) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	for index in count:
		_input.add_virtual_device(index)
		var player := PlayerScript.new()
		player.index = index
		player.input = _input
		player.events = _bus
		player._ready()
		_players.append(player)


func _teardown() -> void:
	for player in _players:
		player.free()
	_players.clear()
	for node: Node in [_input, _bus]:
		if node != null:
			node.free()
	_input = null
	_bus = null


func _hold(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 1.0)


func _release(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 0.0)


## A dash card's request for `player`: `distance` pixels over `seconds`.
func _dash(player: int, distance: float = DASH_DISTANCE, seconds: float = DASH_TIME) -> void:
	_bus.caster_move_requested.emit(player, &"dash", _players[player].muzzle_position() + Vector2(distance, 0.0), seconds, 77)


## Step every player `count` times.
func _run(count: int) -> void:
	for i in count:
		for player in _players:
			player.step(STEP)


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001


# --- Tests ------------------------------------------------------------------

func _test_wizard_scene() -> void:
	var wizard := WizardScene.instantiate() as PlayerScript
	_check(wizard != null, "the wizard scene's root runs gameplay/player/player.gd")
	if wizard == null:
		return
	_check(wizard.get_node_or_null("CollisionShape2D") != null, "the wizard scene has a collision shape")
	_check(wizard.get_node_or_null("Sprite") is Sprite2D, "the wizard scene has a Sprite node")
	_check(wizard.collision_mask == PlayerScript.LAYER_WALLS, "players collide only with walls")
	_check(wizard.get_node("Sprite").texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "the sprite is drawn with filtering off")
	wizard.free()
	# Each index shows a body strip of 32x32 frames (the same for all, with no player colour)
	# under its own hat, whose most common colour (the outline apart) differs per player.
	var hats: Array[Color] = []
	for index in 4:
		var instance := WizardScene.instantiate() as PlayerScript
		_check(instance.textures.size() == 4 and instance.hat_textures.size() == 4, "the wizard scene lists four strips and four hats")
		instance.index = index
		instance.apply_texture()  # no tree and no _ready() needed to look at the sprite
		var sprite: Sprite2D = instance.get_node("Sprite") as Sprite2D
		var texture: Texture2D = sprite.texture
		_check(texture != null, "wizard %d shows a sprite" % index)
		if texture != null:
			_check(texture.get_height() == 32 and texture.get_width() % 32 == 0, "wizard %d sprite is a strip of 32x32 frames" % index)
		var hat: Sprite2D = sprite.get_node_or_null("Hat") as Sprite2D
		_check(hat != null and hat.texture != null, "wizard %d shows a hat" % index)
		if hat != null and hat.texture != null:
			var colour_count: Dictionary = {}
			var image := hat.texture.get_image()
			for y in image.get_height():
				for x in image.get_width():
					var pixel := image.get_pixel(x, y)
					if pixel.a > 0.0:
						colour_count[pixel] = int(colour_count.get(pixel, 0)) + 1
			var main := Color.BLACK
			var best := 0
			for pixel: Color in colour_count:
				if pixel.is_equal_approx(Color("#14121f")):
					continue
				if int(colour_count[pixel]) > best:
					best = int(colour_count[pixel])
					main = pixel
			_check(best > 0, "wizard %d has a hat colour" % index)
			for other in hats:
				_check(not other.is_equal_approx(main), "wizard %d hat colour differs from the others" % index)
			hats.append(main)
		instance.free()


func _test_stands_still() -> void:
	_setup(1)
	_run(2)
	_check(_players[0].velocity == Vector2.ZERO, "no input, no movement")
	_check(not _players[0].is_dashing() and not _players[0].is_invulnerable(), "not dashing at rest")


func _test_walks_at_move_speed() -> void:
	_setup(1)
	_hold(0, &"move_right")
	_run(1)
	_check(_near(_players[0].velocity, Vector2(PlayerScript.MOVE_SPEED, 0.0)), "walks right at MOVE_SPEED, got %s" % _players[0].velocity)
	_release(0, &"move_right")
	_run(1)
	_check(_players[0].velocity == Vector2.ZERO, "stops when the key is released")
	_check(_players[0].facing == Vector2.RIGHT, "keeps facing the way it walked")


func _test_diagonal_is_not_faster() -> void:
	_setup(1)
	_hold(0, &"move_up")
	_hold(0, &"move_left")
	_run(1)
	_check(is_equal_approx(_players[0].velocity.length(), PlayerScript.MOVE_SPEED), "a diagonal is not faster, got %f" % _players[0].velocity.length())


func _test_dash_runs_at_the_card_speed_without_invulnerability() -> void:
	_setup(1)
	var player: PlayerScript = _players[0]
	_hold(0, &"move_left")
	_run(1)
	_dash(0)
	_run(1)
	_check(player.is_dashing(), "the request starts a dash")
	_check(not player.is_invulnerable(), "a dash gives no invulnerability")
	_check(_near(player.velocity, Vector2(-DASH_SPEED, 0.0)), "the dash goes the way the wizard walks, as fast as asked, got %s" % player.velocity)
	_run(int(DASH_TIME / STEP))
	_check(not player.is_dashing(), "the dash ends after the time asked")
	_check(_near(player.velocity, Vector2(-PlayerScript.MOVE_SPEED, 0.0)), "then the wizard walks again")


func _test_dash_without_direction_uses_facing() -> void:
	_setup(1)
	var player: PlayerScript = _players[0]
	_dash(0)
	_run(1)
	_check(_near(player.velocity, Vector2(0.0, DASH_SPEED)), "a standing dash goes the way the wizard faces, got %s" % player.velocity)


func _test_dash_direction_is_locked() -> void:
	_setup(1)
	var player: PlayerScript = _players[0]
	_hold(0, &"move_right")
	_run(1)
	_dash(0)
	_run(1)
	_release(0, &"move_right")
	_hold(0, &"move_up")
	_run(1)
	_check(_near(player.velocity, Vector2(DASH_SPEED, 0.0)), "steering does not bend a dash, got %s" % player.velocity)


func _test_dash_end_is_reported_where_it_stopped() -> void:
	_setup(1)
	var player: PlayerScript = _players[0]
	var ends: Array = []
	_bus.caster_move_finished.connect(func(p: int, mode: StringName, at: Vector2, tag: int) -> void: ends.append([p, mode, at, tag]))
	_dash(0)
	_run(int(DASH_TIME / STEP) + 1)
	_check(ends.size() == 1, "the end is reported once, got %s" % [ends])
	if ends.size() == 1:
		_check(ends[0][0] == 0 and ends[0][1] == &"dash" and ends[0][3] == 77, "for this player, the dash and its card's tag")
		_check(_near(ends[0][2], player.global_position), "where the wizard stopped")


func _test_dash_for_another_player_is_ignored() -> void:
	_setup(2)
	_dash(1)
	_run(1)
	_check(not _players[0].is_dashing(), "player 1 does not dash for player 2's card")
	_check(_players[1].is_dashing(), "player 2 does")


func _test_captured_player_cannot_move() -> void:
	_setup(1)
	var player: PlayerScript = _players[0]
	_input.set_captured(0, true)
	_hold(0, &"move_right")
	_run(1)
	_check(player.velocity == Vector2.ZERO, "a player in their overlay does not walk")


func _test_capture_during_dash_ends_it() -> void:
	_setup(1)
	var player: PlayerScript = _players[0]
	_hold(0, &"move_right")
	_run(1)
	_dash(0)
	_run(1)
	_check(player.is_dashing(), "the dash started")
	_input.set_captured(0, true)
	_run(1)
	_check(not player.is_dashing(), "an overlay opening ends the dash")
	_check(player.velocity == Vector2.ZERO, "the captured wizard stands still")


func _test_two_players_at_once() -> void:
	_setup(2)
	_hold(0, &"move_right")
	_hold(1, &"move_left")
	_run(1)
	_dash(1)
	_run(1)
	_check(_near(_players[0].velocity, Vector2(PlayerScript.MOVE_SPEED, 0.0)), "player 0 walks right")
	_check(not _players[0].is_dashing(), "player 1's dash does not touch player 0")
	_check(_near(_players[1].velocity, Vector2(-DASH_SPEED, 0.0)), "player 1 dashes left")
	_dash(0)
	_run(1)
	_check(_players[0].is_dashing() and _players[1].is_dashing(), "both dash at once")


func _test_four_players_at_once() -> void:
	_setup(4)
	for index in 4:
		_hold(index, &"move_down")
	_run(1)
	_dash(2)
	_run(1)
	for index in 4:
		var dashing: bool = index == 2
		_check(_players[index].is_dashing() == dashing, "only player 2 dashes (player %d)" % index)
		var speed: float = DASH_SPEED if dashing else PlayerScript.MOVE_SPEED
		_check(_near(_players[index].velocity, Vector2(0.0, speed)), "player %d moves down at the right speed" % index)


func _test_no_input_manager() -> void:
	var player := PlayerScript.new()
	player.step(STEP)
	_check(player.velocity == Vector2.ZERO, "a wizard with no input manager stands still")
	player.free()
