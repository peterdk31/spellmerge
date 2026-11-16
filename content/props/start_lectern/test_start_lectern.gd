extends "res://tests/support/suite.gd"
## The hub's lectern (run generation RG7, content/props/start_lectern): where a seat picks the depth
## of its map the stone's run starts at. A stone stand nobody walks through and no hit lands on, in
## one state, of the role the hub's rules read (`HubRules.ROLE_START_LECTERN`); standing at it is its
## area, in front of it. The hub stands it in its zone of that name (`RoomContents`), so deleting
## this folder leaves the hub whole.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://content/props/start_lectern/test_start_lectern.gd
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const LECTERN: PropBase = preload("res://content/props/start_lectern/start_lectern.tres")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func test_it_blocks_and_is_never_hit() -> void:
	var body: Actor = _world.add(PropBody.make(LECTERN), Vector2(200, 200))
	check(body.is_still(), "it stands still, never stepped")
	check(not body.hurtbox.is_on(), "no hit lands on it")
	check(body.footprint.solid, "nobody walks through it")
	check(body.health.invincible, "invincible all the same")
	check_equal(LECTERN.role, HubRules.ROLE_START_LECTERN, "the lectern the hub's rules read")
	check_equal(LECTERN.states.list.size(), 1, "one state")
	var sprite := body.get_node("Sprite") as Sprite2D
	check_equal(sprite.texture, LECTERN.looks[0].layers[0].texture, "its stand drawn")


## Stood at in front of it: its area reaches past its ground on every side and mostly below its
## feet, where a wizard walking up to it stands, and its art stands on its ground.
func test_it_is_stood_at_in_front() -> void:
	var area: Rect2 = LECTERN.area_rect()
	var ground: Rect2 = LECTERN.ground_rect()
	check(area.has_area() and ground.has_area(), "an area and a ground of its own")
	check(area.grow(-8.0).encloses(ground), "the area reaches past its ground on every side")
	check(area.end.y - ground.end.y >= 24.0, "room in front of it to stand in")
	var layer: PropLayer = LECTERN.looks[0].layers[0]
	var size := Vector2(layer.frame_size())
	var art := Rect2(layer.offset - Vector2(size.x * 0.5, size.y), size)
	check(art.encloses(ground), "its art covers its ground")
	check(absf(art.end.y - ground.end.y) <= 2.0, "its art stands where its ground does")
