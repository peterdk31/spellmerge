extends "res://tests/support/suite.gd"
## Tests for gameplay/player (move and dash) on the wizard actor (actors G7), one behaviour per
## test: the scene and its kit, walking at the Mover's speed, the dash a dash card asks for (staffs
## A6a: `caster_move_requested`, no invulnerability, `caster_move_finished` where it ends), a
## captured player, and two players (and all four) at once without touching each other.
##
## The scene tests instantiate the wizard scene alone (not in the tree); the others get a fresh
## world each (wizard_fixture.gd: wizards from the real scene in the tree, the stand-in spell
## runtime, input through the world's own input manager's virtual devices), stepped by fixed
## deltas. The step and the timings are binary fractions, so the timers add up exactly.

const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")

const STEP: float = WizardFixture.STEP
## A dash as the dash card asks for it: 55 px over a quarter of a second.
const DASH_DISTANCE: float = 55.0
const DASH_TIME: float = 0.25
const DASH_SPEED: float = DASH_DISTANCE / DASH_TIME

var _world: WizardFixture
var _players: Array[Actor] = []


func before_each() -> void:
	_world = WizardFixture.new(root, true)
	_players.clear()


func after_each() -> void:
	_world.free_all()


## `count` wizards (seats 0 to count-1) 100 px apart, in the tree. Returns the first.
func _wizards(count: int) -> Actor:
	for index in count:
		_players.append(_world.wizard(index, Vector2(100.0 * index, 0.0)))
	return _players[0]


## The wizard scene alone, freed after the test.
func _scene() -> Actor:
	return own(WizardScene.instantiate()) as Actor


func _hold(player: int, action: StringName) -> void:
	_world.hold(player, action)


func _release(player: int, action: StringName) -> void:
	_world.release(player, action)


## A dash card's request for `player`: `distance` pixels along `way` over `seconds` (the card
## says its way, rules R4 F1). The Mover acts only on a card of its own actor (the tag names the
## wizard's id).
func _dash(player: int, way: Vector2 = Vector2.RIGHT, distance: float = DASH_DISTANCE, seconds: float = DASH_TIME) -> void:
	_world.bus.caster_move_requested.emit(player, &"dash", way * distance, seconds, _tag(_players[player]))


func _tag(wizard: Actor) -> int:
	return SpellTag.make(wizard.id, 0, 0, 0)


## Step every player `count` times.
func _run(count: int) -> void:
	_world.run(count)


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001


# --- The scene ---------------------------------------------------------------------------------


func test_the_wizard_scenes_root_is_an_actor() -> void:
	var wizard: Node = own(WizardScene.instantiate()) as Node
	check(wizard is Actor, "the wizard scene's root is an Actor")


func test_the_wizard_is_in_the_wizards_group_only() -> void:
	var wizard: Actor = _scene()
	check(wizard.is_in_group(&"wizards"), "the wizard is in the wizards group")
	check(not wizard.is_in_group(&"players"), "the players group is gone (actors G8)")


func test_the_wizard_scene_carries_the_kit() -> void:
	var wizard: Actor = _scene()
	check(wizard.get_node_or_null("Health") is Health, "the wizard scene has a Health")
	check(wizard.get_node_or_null("Hurtbox") is Hurtbox, "the wizard scene has the kit's Hurtbox")
	check(wizard.get_node_or_null("Mover") is Mover, "the wizard scene has the kit's Mover")
	check(wizard.get_node_or_null("Caster") is Caster, "the wizard scene has a Caster")
	check(wizard.get_node_or_null("Downed") is Downed, "the wizard scene has a Downed")
	check(wizard.get_node_or_null("PlayerController") is PlayerController, "the wizard scene has a PlayerController")
	check(wizard.get_node_or_null("Sprite") is Sprite2D, "the wizard scene has a Sprite node")
	check(wizard.get_node_or_null("StaffLook") is StaffLook, "the wizard scene has a StaffLook")
	check(wizard.get_node_or_null("Face") is Face, "the wizard scene wears a Face")


func test_wizards_are_no_physics_bodies() -> void:
	# online-ready N6
	var wizard: Actor = _scene()
	check(wizard.get_class() == "Node2D" and wizard.get_node_or_null("CollisionShape2D") == null, "wizards are no physics bodies")


func test_wizards_walk_against_the_walls_as_circles_of_their_footprint() -> void:
	# props W4
	var footprint: Footprint = _scene().get_node_or_null("Footprint") as Footprint
	check(footprint != null and footprint.radius > 0.0, "the wizard has a footprint with a radius")


func test_the_wizard_sprite_is_drawn_with_filtering_off() -> void:
	check_equal(_scene().get_node("Sprite").texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "the sprite is drawn with filtering off")


func test_the_wizard_has_four_staffs() -> void:
	check_equal((_scene().get_node("Caster") as Caster).staff_count, 4, "the wizard has four staffs")


func test_every_seats_wizard_shows_a_head() -> void:
	for index in 4:
		var wizard: Actor = _world.wizard(index)
		_run(1)
		check((wizard.get_node("Sprite") as Sprite2D).texture != null, "wizard %d shows a head" % index)


func test_each_seat_shows_its_own_row_of_the_head_sheet() -> void:
	# The player colour is on the head.
	for index in 4:
		var wizard: Actor = _world.wizard(index)
		_run(1)
		check_equal((wizard.get_node("Sprite") as Sprite2D).frame_coords.y, index, "wizard %d shows its ramp's row of the head sheet" % index)


# --- Walking -----------------------------------------------------------------------------------


func test_no_input_no_movement() -> void:
	var wizard: Actor = _wizards(1)
	_run(2)
	check_equal(wizard.velocity, Vector2.ZERO, "no input, no movement")


func test_a_wizard_at_rest_is_not_dashing() -> void:
	var wizard: Actor = _wizards(1)
	_run(2)
	check(not wizard.mover.is_moving() and not wizard.health.is_protected(), "not dashing at rest")


func test_the_wizard_walks_at_its_movers_speed() -> void:
	var wizard: Actor = _wizards(1)
	_hold(0, &"move_right")
	_run(1)
	check(_near(wizard.velocity, Vector2(wizard.mover.speed, 0.0)), "walks right at the Mover's speed, got %s" % wizard.velocity)


func test_the_wizard_stops_when_the_key_is_released() -> void:
	var wizard: Actor = _wizards(1)
	_hold(0, &"move_right")
	_run(1)
	_release(0, &"move_right")
	_run(1)
	check_equal(wizard.velocity, Vector2.ZERO, "stops when the key is released")


func test_a_stopped_wizard_keeps_aiming_the_way_it_walked() -> void:
	# There is no `facing` any more: with no aim input the wizard aims the way it walked, and
	# keeps that aim when it stops.
	var wizard: Actor = _wizards(1)
	_hold(0, &"move_right")
	_run(1)
	_release(0, &"move_right")
	_run(1)
	check(_near(wizard.aim, Vector2.RIGHT), "keeps aiming the way it walked: %s" % wizard.aim)


func test_a_diagonal_is_not_faster() -> void:
	var wizard: Actor = _wizards(1)
	_hold(0, &"move_up")
	_hold(0, &"move_left")
	_run(1)
	check(is_equal_approx(wizard.velocity.length(), wizard.mover.speed), "a diagonal is not faster, got %f" % wizard.velocity.length())


func test_a_captured_player_does_not_walk() -> void:
	var wizard: Actor = _wizards(1)
	_world.input.set_captured(0, true)
	_hold(0, &"move_right")
	_run(1)
	check_equal(wizard.velocity, Vector2.ZERO, "a player in their overlay does not walk")


## A bare wizard script with no input manager no longer exists: a wizard whose controller has no
## input stands still (and a held key on its seat does nothing).
func test_a_wizard_whose_controller_has_no_input_stands_still() -> void:
	var wizard: Actor = _wizards(1)
	WizardFixture.controller(wizard).frames = null
	_hold(0, &"move_right")
	_run(1)
	check_equal(wizard.velocity, Vector2.ZERO, "a wizard whose controller has no input stands still")


# --- The dash ----------------------------------------------------------------------------------


## A wizard walking left that was asked to dash left, one step into the dash.
func _dashing_left() -> Actor:
	var wizard: Actor = _wizards(1)
	_hold(0, &"move_left")
	_run(1)
	_dash(0, Vector2.LEFT)
	_run(1)
	return wizard


func test_the_request_starts_a_dash() -> void:
	check(_dashing_left().mover.is_moving(), "the request starts a dash")


func test_a_dash_gives_no_invulnerability() -> void:
	check(not _dashing_left().health.is_protected(), "a dash gives no invulnerability")


func test_the_dash_goes_as_fast_as_asked() -> void:
	var wizard: Actor = _dashing_left()
	check(_near(wizard.velocity, Vector2(-DASH_SPEED, 0.0)), "the dash goes as fast as asked, got %s" % wizard.velocity)


func test_the_dash_ends_after_the_time_asked() -> void:
	var wizard: Actor = _dashing_left()
	_run(int(DASH_TIME / STEP))
	check(not wizard.mover.is_moving(), "the dash ends after the time asked")


func test_after_the_dash_the_wizard_walks_again() -> void:
	var wizard: Actor = _dashing_left()
	_run(int(DASH_TIME / STEP))
	check(_near(wizard.velocity, Vector2(-wizard.mover.speed, 0.0)), "then the wizard walks again, got %s" % wizard.velocity)


## Changed in rules R4 F1 (owner, 2026-10-30): the request carries its way, so the wizard dashes
## the way its card asks, not the way it walks or aims.
func test_the_dash_goes_the_way_its_card_asks() -> void:
	var wizard: Actor = _wizards(1)
	_hold(0, &"move_left")
	_world.input.send_virtual_aim(0, Vector2.DOWN)
	_run(1)
	_dash(0, Vector2.UP)
	_run(1)
	check(_near(wizard.velocity, Vector2(0.0, -DASH_SPEED)), "a wizard walking left and aiming down dashes up as asked, got %s" % wizard.velocity)


func test_steering_does_not_bend_a_dash() -> void:
	var wizard: Actor = _wizards(1)
	_hold(0, &"move_right")
	_run(1)
	_dash(0)
	_run(1)
	_release(0, &"move_right")
	_hold(0, &"move_up")
	_run(1)
	check(_near(wizard.velocity, Vector2(DASH_SPEED, 0.0)), "steering does not bend a dash, got %s" % wizard.velocity)


## Every caster_move_finished of one wizard's dash, run to its end, as
## [caster, mode, position, tag].
func _dash_ends() -> Array:
	_wizards(1)
	var ends: Array = []
	_world.bus.caster_move_finished.connect(func(p: int, mode: StringName, at: Vector2, tag: int, _walled: bool) -> void: ends.append([p, mode, at, tag]))
	_dash(0)
	_run(int(DASH_TIME / STEP) + 1)
	return ends


func test_the_dash_end_is_reported_once() -> void:
	check_equal(_dash_ends().size(), 1, "the end is reported once")


func test_the_dash_end_names_the_wizard_the_dash_and_its_cards_tag() -> void:
	# The event's caster is the wizard's caster number (its actor id), not the seat.
	var ends: Array = _dash_ends()
	var wizard: Actor = _players[0]
	check(ends.size() == 1 and ends[0][0] == wizard.caster_number() and ends[0][1] == &"dash" and ends[0][3] == _tag(wizard), "for this wizard, the dash and its card's tag: %s" % [ends])


func test_the_dash_end_is_reported_where_the_wizard_stopped() -> void:
	var ends: Array = _dash_ends()
	check(ends.size() == 1 and _near(ends[0][2], _players[0].global_position), "where the wizard stopped: %s" % [ends])


func test_a_dash_for_another_player_is_ignored() -> void:
	_wizards(2)
	_dash(1)
	_run(1)
	check(not _players[0].mover.is_moving(), "player 1 does not dash for player 2's card")
	check(_players[1].mover.is_moving(), "player 2 does")


## A wizard walking right, one step into a dash, then captured for a step.
func _captured_mid_dash() -> Actor:
	var wizard: Actor = _wizards(1)
	_hold(0, &"move_right")
	_run(1)
	_dash(0)
	_run(1)
	check(wizard.mover.is_moving(), "the dash started")
	_world.input.set_captured(0, true)
	_run(1)
	return wizard


func test_an_overlay_opening_ends_the_dash() -> void:
	check(not _captured_mid_dash().mover.is_moving(), "an overlay opening ends the dash")


func test_a_wizard_captured_mid_dash_stands_still() -> void:
	check_equal(_captured_mid_dash().velocity, Vector2.ZERO, "the captured wizard stands still")


# --- Several players ---------------------------------------------------------------------------


## Player 0 walking right, player 1 walking left and one step into a dash left.
func _two_one_dashing() -> void:
	_wizards(2)
	_hold(0, &"move_right")
	_hold(1, &"move_left")
	_run(1)
	_dash(1, Vector2.LEFT)
	_run(1)


func test_one_players_dash_leaves_the_other_walking() -> void:
	_two_one_dashing()
	check(_near(_players[0].velocity, Vector2(_players[0].mover.speed, 0.0)), "player 0 walks right")
	check(not _players[0].mover.is_moving(), "player 1's dash does not touch player 0")


func test_the_dashing_player_dashes_its_own_way() -> void:
	_two_one_dashing()
	check(_near(_players[1].velocity, Vector2(-DASH_SPEED, 0.0)), "player 1 dashes left")


func test_two_players_dash_at_once() -> void:
	_two_one_dashing()
	_dash(0)
	_run(1)
	check(_players[0].mover.is_moving() and _players[1].mover.is_moving(), "both dash at once")


## Four players walking down, player 2 one step into a dash down.
func _four_one_dashing() -> void:
	_wizards(4)
	for index in 4:
		_hold(index, &"move_down")
	_run(1)
	_dash(2, Vector2.DOWN)
	_run(1)


func test_of_four_players_only_the_one_asked_dashes() -> void:
	_four_one_dashing()
	for index in 4:
		check(_players[index].mover.is_moving() == (index == 2), "only player 2 dashes (player %d)" % index)


func test_of_four_players_each_moves_at_its_own_speed() -> void:
	_four_one_dashing()
	for index in 4:
		var speed: float = DASH_SPEED if index == 2 else _players[index].mover.speed
		check(_near(_players[index].velocity, Vector2(0.0, speed)), "player %d moves down at the right speed" % index)
