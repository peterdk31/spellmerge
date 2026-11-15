extends "res://tests/support/suite.gd"
## The lectern beside the hub's trial gate (boss OB2, content/props/trial_lectern): a book on a stand
## that nobody bumps into and no hit lands on, in one state. Standing at it is the hub's rules'
## (`HubRules.ROLE_TRIAL_LECTERN`: A there opens that seat's room menu); its area reaches past its
## art, so a wizard standing beside the book counts.
##
## godot --headless --path . --script res://content/props/trial_lectern/test_trial_lectern.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const LECTERN: PropBase = preload("res://content/props/trial_lectern/trial_lectern.tres")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func test_it_is_the_hubs_lectern_walked_up_to_and_never_hit() -> void:
	check_equal(LECTERN.role, HubRules.ROLE_TRIAL_LECTERN, "the hub's rules know it as the lectern")
	var body: Actor = _world.add(PropBody.make(LECTERN), Vector2(200, 200))
	check(body.is_still(), "it stands still, never stepped")
	check(not body.hurtbox.is_on(), "no hit lands on it")
	check(not body.footprint.solid, "nobody bumps into it")
	check(body.health.invincible, "invincible all the same")
	check_equal(LECTERN.states.list.size(), 1, "one state")
	var sprite := body.get_node("Sprite") as Sprite2D
	check_equal(sprite.texture, LECTERN.looks[0].layers[0].texture, "its stand drawn")
	check_equal(sprite.z_index, RoomBase.FLOOR_Z, "on the floor")


func test_its_area_holds_its_art() -> void:
	var area: Rect2 = LECTERN.area_rect()
	check_equal(area, Rect2(-32, -32, 64, 64), "a 64 px box round its feet")
	var layer: PropLayer = LECTERN.looks[0].layers[0]
	var size := Vector2(layer.frame_size())
	check(area.encloses(Rect2(layer.drawn_at() - size * 0.5, size)), "its art inside the area")
