extends "res://tests/support/suite.gd"
## The line of fire minds a prop's whole body (2026-11-18: enemies fired into a pillar a wizard hid
## behind). A shot is spent on a world hit shape, and a crypt pillar's is its tall body (22 × 52 round
## 28 px above its feet), far bigger than its ground (26 × 12): a wizard standing level with the
## pillar's middle, just behind it, is hidden from a shot although the feet-to-feet line is clear.
## The real pillar and imp, in the AI fixture's world.
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const PILLAR: PropBase = preload("res://content/props/crypt_pillar/crypt_pillar.tres")
const ROOM := Rect2(0.0, 0.0, 640.0, 400.0)
## Where the pillar stands (its feet).
const PILLAR_AT := Vector2(300.0, 200.0)

var fx: Fixture
var pillar: Actor


func before_each() -> void:
	fx = Fixture.new(root)
	fx.projectiles.set_bounds(ROOM)
	pillar = PropBody.make(PILLAR)
	pillar.position = PILLAR_AT
	fx.wire(pillar)
	root.add_child(pillar)
	pillar.ticking = false
	fx.projectiles.step(Fixture.STEP)


func after_each() -> void:
	if is_instance_valid(pillar):
		pillar.free()
	fx.free_all()


func test_a_pillars_body_stops_the_line_its_ground_does_not() -> void:
	# Level with the pillar's middle, above its ground: the feet line misses the ground.
	var from := Vector2(200.0, 172.0)
	var to := Vector2(400.0, 172.0)
	check(AISight.ground_clear(fx.projectiles, from, to), "no ground on the line")
	check(AISight.line_clear(fx.projectiles, from, to), "no wall on it")
	check(not fx.projectiles.props_clear(from, to), "but the pillar's body is")
	check(not AISight.fire_clear(fx.projectiles, from, to), "so a shot along it would not get through")
	check(AISight.fire_clear(fx.projectiles, Vector2(200.0, 120.0), Vector2(400.0, 120.0)), "a line over its top is clear")
	check(not fx.projectiles.props_clear(Vector2(200.0, 140.0), Vector2(400.0, 140.0), 8.0), "a wide shot grazing its top is not")


func test_only_the_worlds_bodies_count() -> void:
	# A wizard on the line is a foe's body, not cover: the line minds props only.
	fx.players[0].position = Vector2(300.0, 100.0)
	fx.projectiles.step(Fixture.STEP)
	check(fx.projectiles.props_clear(Vector2(200.0, 88.0), Vector2(400.0, 88.0)), "a body of a team is no prop")
	check(fx.projectiles.props_clear(Vector2(200.0, 172.0), Vector2(250.0, 172.0)), "a line that stops short of the pillar is clear")


func test_the_flank_way_ends_where_the_shot_is_clear() -> void:
	var eye := Vector2(0.0, -12.0)
	var from := Vector2(270.0, 178.0)
	var aim := Vector2(340.0, 166.0)
	check(not AISight.fire_clear(fx.projectiles, from + eye, aim), "the pillar is between")
	var way: Vector2 = AISight.flank(fx.projectiles, from, aim - eye, aim, eye, 40.0)
	check(way != Vector2.ZERO, "a way out is found")
	check(AISight.walk_clear(fx.projectiles, from, from + way * 40.0), "it can be walked")
	check(AISight.fire_clear(fx.projectiles, from + way * 40.0 + eye, aim) or AISight.fire_clear(fx.projectiles, from + way * 80.0 + eye, aim), "and from its end, a probe or two out, the shot is clear")
	check(AISight.flank(null, from, aim - eye, aim, eye, 40.0) == Vector2.ZERO, "no manager, no flank")


func test_a_wizard_hugging_a_pillar_is_hit_from_its_open_side() -> void:
	# Review: the line was asked out to the wizard's centre, so a wizard whose body overlaps the
	# pillar's (standing just in front of it) or stands within a shot's width of its side was hidden
	# from every side. The shot meets the wizard first from its open side.
	var front := Vector2(300.0, 194.0)  # body just south of the pillar's box bottom, inside its reach
	check(AISight.fire_clear(fx.projectiles, Vector2(300.0, 300.0), front, 4.0, 12.0), "from the south the shot meets the wizard first")
	check(not AISight.fire_clear(fx.projectiles, Vector2(300.0, 60.0), front, 4.0, 12.0), "from the north the pillar is between")
	var side := Vector2(318.0, 172.0)  # body 7 px off the box's right edge
	check(AISight.fire_clear(fx.projectiles, Vector2(420.0, 172.0), side, 8.0, 16.0), "from the right a wide shot meets it first")
	check(not AISight.fire_clear(fx.projectiles, Vector2(180.0, 172.0), side, 8.0, 16.0), "from the left the pillar is between")


func test_an_imp_shoots_a_wizard_standing_in_front_of_a_pillar() -> void:
	fx.players[0].position = Vector2(300.0, 208.0)
	var imp: Actor = fx.imp(Vector2(300.0, 290.0))
	var brain: AIBrain = Fixture.ai(imp).brain
	fx.run(imp, 2)
	check(brain.line_clear, "the wizard in front of the pillar is in its line of fire")


func test_an_imp_does_not_fire_into_the_pillar_a_wizard_hides_behind() -> void:
	# The wizard stands just behind the pillar's body, level with the imp: their feet line passes
	# over the pillar's ground, their bodies' line through its body.
	fx.players[0].position = Vector2(340.0, 178.0)
	var imp: Actor = fx.imp(Vector2(260.0, 178.0))
	var brain: AIBrain = Fixture.ai(imp).brain
	fx.run(imp, 2)
	check(brain.ground_clear, "nothing on the feet line")
	check(not brain.line_clear, "it sees the pillar's body in its line of fire")
	var full: float = pillar.health.health
	var wizard_full: float = fx.players[0].health.health
	for i in 240:
		fx.run(imp, 1)
		if fx.players[0].health.health < wizard_full:
			break
	check_equal(pillar.health.health, full, "no shot of it hit the pillar")
	check(fx.players[0].health.health < wizard_full, "it went round and hit the wizard")
