extends SceneTree
## Tests for gameplay/player (move and dash) on the wizard actor (actors G7): the scene, the
## speeds, the dash a dash card asks for (staffs A6a: `caster_move_requested`, no
## invulnerability, `caster_move_finished` where it ends), a captured player, and two players
## (and all four) at once without touching each other. Wizards are made from the real scene by
## the wizard fixture; input goes through the real input manager's virtual devices; time moves by
## fixed deltas. The step and the timings are binary fractions, so the timers add up exactly.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_move.gd

const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")

const STEP: float = WizardFixture.STEP
## The wizard's walking speed (the scene's Mover).
const MOVE_SPEED: float = 90.0
## A dash as the dash card asks for it: 55 px over a quarter of a second (220 px/s).
const DASH_DISTANCE: float = 55.0
const DASH_TIME: float = 0.25
const DASH_SPEED: float = 220.0

var _failures: Array[String] = []
var _world: WizardFixture = null
var _players: Array[Actor] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_wizard_scene()
	_test_stands_still()
	_test_walks_at_move_speed()
	_test_diagonal_is_not_faster()
	_test_dash_runs_at_the_card_speed_without_invulnerability()
	_test_dash_without_direction_uses_the_aim()
	_test_dash_direction_is_locked()
	_test_dash_end_is_reported_where_it_stopped()
	_test_dash_for_another_player_is_ignored()
	_test_captured_player_cannot_move()
	_test_capture_during_dash_ends_it()
	_test_two_players_at_once()
	_test_four_players_at_once()
	_test_no_input()
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


## `count` wizards (seats 0 to count-1), in the tree, on the stand-in spell runtime.
func _setup(count: int) -> void:
	_teardown()
	_world = WizardFixture.new(root, true)
	for index in count:
		_players.append(_world.wizard(index, Vector2(100.0 * index, 0.0)))


func _teardown() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	_players.clear()


func _hold(player: int, action: StringName) -> void:
	_world.hold(player, action)


func _release(player: int, action: StringName) -> void:
	_world.release(player, action)


## A dash card's request for `player`: `distance` pixels over `seconds`. The Mover acts only on a
## card of its own actor (the tag names the wizard's id).
func _dash(player: int, distance: float = DASH_DISTANCE, seconds: float = DASH_TIME) -> void:
	var wizard: Actor = _players[player]
	_world.bus.caster_move_requested.emit(player, &"dash", wizard.muzzle_position() + Vector2(distance, 0.0), seconds, _tag(wizard))


func _tag(wizard: Actor) -> int:
	return SpellTag.make(wizard.id, 0, 0, 0)


## Step every player `count` times.
func _run(count: int) -> void:
	_world.run(count)


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001


# --- Tests ------------------------------------------------------------------

func _test_wizard_scene() -> void:
	var wizard := WizardScene.instantiate() as Actor
	_check(wizard != null, "the wizard scene's root is an Actor")
	if wizard == null:
		return
	_check(wizard.is_in_group(&"wizards") and not wizard.is_in_group(&"players"), "the wizard is in the wizards group (the players group is gone, actors G8)")
	_check(wizard.get_node_or_null("CollisionShape2D") is CollisionShape2D, "the wizard scene has a collision shape")
	_check(wizard.get_node_or_null("Health") is Health, "the wizard scene has a Health")
	_check(wizard.get_node_or_null("Hurtbox") is Hurtbox, "the wizard scene has the kit's Hurtbox")
	_check(wizard.get_node_or_null("Mover") is Mover, "the wizard scene has the kit's Mover")
	_check(wizard.get_node_or_null("Caster") is Caster, "the wizard scene has a Caster")
	_check(wizard.get_node_or_null("Downed") is Downed, "the wizard scene has a Downed")
	_check(wizard.get_node_or_null("PlayerController") is PlayerController, "the wizard scene has a PlayerController")
	_check(wizard.get_node_or_null("Sprite") is Sprite2D, "the wizard scene has a Sprite node")
	_check(wizard.get_node_or_null("StaffLook") is StaffLook, "the wizard scene has a StaffLook")
	_check(wizard.get_node_or_null("Face") is Face, "the wizard scene wears a Face")
	_check(wizard.collision_mask == Actor.LAYER_WALLS and wizard.collision_mask == 1, "wizards collide only with walls")
	_check(wizard.collision_layer == 0, "wizards are on no body layer")
	_check(wizard.get_node("Sprite").texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "the sprite is drawn with filtering off")
	var caster := wizard.get_node("Caster") as Caster
	_check(caster.staff_count == 4, "the wizard has four staffs")
	wizard.free()
	# Each seat shows its own row of the head sheet: the player colour is on the head.
	_teardown()
	_world = WizardFixture.new(root, true)
	for index in 4:
		var instance: Actor = _world.wizard(index)
		_run(1)
		var sprite: Sprite2D = instance.get_node("Sprite") as Sprite2D
		_check(sprite.texture != null, "wizard %d shows a head" % index)
		_check(sprite.frame_coords.y == index, "wizard %d shows its ramp's row of the head sheet" % index)
	_teardown()


func _test_stands_still() -> void:
	_setup(1)
	_run(2)
	_check(_players[0].velocity == Vector2.ZERO, "no input, no movement")
	_check(not _players[0].mover.is_moving() and not _players[0].health.is_protected(), "not dashing at rest")


func _test_walks_at_move_speed() -> void:
	_setup(1)
	_check(is_equal_approx(_players[0].mover.speed, MOVE_SPEED), "the wizard walks at %f px/s" % MOVE_SPEED)
	_hold(0, &"move_right")
	_run(1)
	_check(_near(_players[0].velocity, Vector2(MOVE_SPEED, 0.0)), "walks right at MOVE_SPEED, got %s" % _players[0].velocity)
	_release(0, &"move_right")
	_run(1)
	_check(_players[0].velocity == Vector2.ZERO, "stops when the key is released")
	# There is no `facing` any more: with no aim input the wizard aims the way it walked, and
	# keeps that aim when it stops.
	_check(_near(_players[0].aim, Vector2.RIGHT), "keeps aiming the way it walked")


func _test_diagonal_is_not_faster() -> void:
	_setup(1)
	_hold(0, &"move_up")
	_hold(0, &"move_left")
	_run(1)
	_check(is_equal_approx(_players[0].velocity.length(), MOVE_SPEED), "a diagonal is not faster, got %f" % _players[0].velocity.length())


func _test_dash_runs_at_the_card_speed_without_invulnerability() -> void:
	_setup(1)
	var player: Actor = _players[0]
	_hold(0, &"move_left")
	_run(1)
	_dash(0)
	_run(1)
	_check(player.mover.is_moving(), "the request starts a dash")
	_check(not player.health.is_protected(), "a dash gives no invulnerability")
	_check(_near(player.velocity, Vector2(-DASH_SPEED, 0.0)), "the dash goes the way the wizard walks, as fast as asked, got %s" % player.velocity)
	_run(int(DASH_TIME / STEP))
	_check(not player.mover.is_moving(), "the dash ends after the time asked")
	_check(_near(player.velocity, Vector2(-MOVE_SPEED, 0.0)), "then the wizard walks again")


## Changed in actors G7 (owner-approved): a standing wizard dashes the way it aims, not the way
## it last walked. A fresh wizard aims down; one that aims up with the stick dashes up.
func _test_dash_without_direction_uses_the_aim() -> void:
	_setup(1)
	var player: Actor = _players[0]
	_dash(0)
	_run(1)
	_check(_near(player.velocity, Vector2(0.0, DASH_SPEED)), "a fresh standing wizard dashes the way it aims (down), got %s" % player.velocity)
	_setup(1)
	player = _players[0]
	_hold(0, &"move_left")
	_run(1)
	_release(0, &"move_left")
	_world.input.send_virtual_aim(0, Vector2.UP)
	_run(1)
	_dash(0)
	_run(1)
	_check(_near(player.velocity, Vector2(0.0, -DASH_SPEED)), "a standing wizard dashes the way it aims, not the way it last walked, got %s" % player.velocity)


func _test_dash_direction_is_locked() -> void:
	_setup(1)
	var player: Actor = _players[0]
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
	var player: Actor = _players[0]
	var ends: Array = []
	_world.bus.caster_move_finished.connect(func(p: int, mode: StringName, at: Vector2, tag: int) -> void: ends.append([p, mode, at, tag]))
	_dash(0)
	_run(int(DASH_TIME / STEP) + 1)
	_check(ends.size() == 1, "the end is reported once, got %s" % [ends])
	if ends.size() == 1:
		# The event's caster is the wizard's caster number (its actor id), not the seat.
		_check(ends[0][0] == player.caster_number() and ends[0][1] == &"dash" and ends[0][3] == _tag(player), "for this wizard, the dash and its card's tag")
		_check(_near(ends[0][2], player.global_position), "where the wizard stopped")


func _test_dash_for_another_player_is_ignored() -> void:
	_setup(2)
	_dash(1)
	_run(1)
	_check(not _players[0].mover.is_moving(), "player 1 does not dash for player 2's card")
	_check(_players[1].mover.is_moving(), "player 2 does")


func _test_captured_player_cannot_move() -> void:
	_setup(1)
	var player: Actor = _players[0]
	_world.input.set_captured(0, true)
	_hold(0, &"move_right")
	_run(1)
	_check(player.velocity == Vector2.ZERO, "a player in their overlay does not walk")


func _test_capture_during_dash_ends_it() -> void:
	_setup(1)
	var player: Actor = _players[0]
	_hold(0, &"move_right")
	_run(1)
	_dash(0)
	_run(1)
	_check(player.mover.is_moving(), "the dash started")
	_world.input.set_captured(0, true)
	_run(1)
	_check(not player.mover.is_moving(), "an overlay opening ends the dash")
	_check(player.velocity == Vector2.ZERO, "the captured wizard stands still")


func _test_two_players_at_once() -> void:
	_setup(2)
	_hold(0, &"move_right")
	_hold(1, &"move_left")
	_run(1)
	_dash(1)
	_run(1)
	_check(_near(_players[0].velocity, Vector2(MOVE_SPEED, 0.0)), "player 0 walks right")
	_check(not _players[0].mover.is_moving(), "player 1's dash does not touch player 0")
	_check(_near(_players[1].velocity, Vector2(-DASH_SPEED, 0.0)), "player 1 dashes left")
	_dash(0)
	_run(1)
	_check(_players[0].mover.is_moving() and _players[1].mover.is_moving(), "both dash at once")


func _test_four_players_at_once() -> void:
	_setup(4)
	for index in 4:
		_hold(index, &"move_down")
	_run(1)
	_dash(2)
	_run(1)
	for index in 4:
		var dashing: bool = index == 2
		_check(_players[index].mover.is_moving() == dashing, "only player 2 dashes (player %d)" % index)
		var speed: float = DASH_SPEED if dashing else MOVE_SPEED
		_check(_near(_players[index].velocity, Vector2(0.0, speed)), "player %d moves down at the right speed" % index)


## A bare wizard script with no input manager no longer exists: a wizard whose controller has no
## input stands still (and a held key on its seat does nothing).
func _test_no_input() -> void:
	_setup(1)
	var player: Actor = _players[0]
	WizardFixture.controller(player).input = null
	_hold(0, &"move_right")
	_run(1)
	_check(player.velocity == Vector2.ZERO, "a wizard whose controller has no input stands still")
