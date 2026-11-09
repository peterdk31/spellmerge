extends "res://tests/support/suite.gd"
## What a shot is drawn as and told as (`Projectiles.set_form`): every shot a card fired carries the
## card's id, so its impacts and its end are told as that card (`impact_form`, its card's impact
## look), and the body (`impact_body`) goes with them. A still shot may ask for a card's own body
## (a shader `register_body` numbered with the mesh it draws: a wall's stone, quads), drawn by that
## shader's pair of batches; it is still a rune to the world. A flying shot may ask for one too (a
## bolt's head, MESH_HEAD). A shot whose motion is not written as its body's mesh draws plain, and
## a body's nodes keep the first batches' draw order. The manager is stepped by hand.
## (docs/milestones/card-looks.md, phase 1.)
##
## godot --headless --path . --script res://tests/core/test_projectile_bodies.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const WarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const STONE: Shader = preload("res://content/spells/forms/wall/stone.gdshader")
const POOL: Shader = preload("res://content/spells/forms/pool/pool.gdshader")
const BOLT: Shader = preload("res://content/spells/forms/bolt/bolt.gdshader")

const DT: float = 1.0 / 60.0

var bus: EventsScript
var mgr: ManagerScript
## The manager's [impact_form, impact_body] as each impact or expiry was sent.
var told: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	told.clear()
	bus.projectile_impact.connect(func(_caster: int, _target: Node, _position: Vector2, _direction: Vector2) -> void:
		told.append([mgr.impact_form, mgr.impact_body]))
	bus.projectile_expired.connect(func(_caster: int, _position: Vector2, _tag: int, _shot: int) -> void:
		told.append([mgr.impact_form, mgr.impact_body]))


func test_a_card_shader_is_numbered_once_and_given_a_pair_of_batches() -> void:
	check_equal(mgr.register_body(null), 0, "no shader is no body")
	var stone: int = mgr.register_body(STONE)
	check_equal(stone, 1, "the first shader is body 1")
	check_equal(mgr.register_body(STONE), stone, "asked again, the same body")
	check_equal(mgr.register_body(POOL), 2, "another is the next")
	check(mgr.body_shader(stone) == STONE, "a body knows its shader")
	check(WarmupScript._wanted.has(STONE) and WarmupScript._wanted.has(POOL), "both are warmed before the first room")
	check(ManagerScript.batch_on_enemy_layer(ManagerScript.body_batch(stone, true)) and not ManagerScript.batch_on_enemy_layer(ManagerScript.body_batch(stone, false)), "its pair: the hat ramps', then the enemy ramp's a layer up")
	check_equal(mgr.batch_mesh(ManagerScript.body_batch(stone, false)), ManagerScript.MESH_QUAD, "one quad a shot, as a rune")
	check_equal(mgr.batch_count(), ManagerScript.BATCH_BODY_FIRST + 4, "two bodies: the first five batches and two pairs")


func test_there_is_no_fixed_number_of_bodies() -> void:
	var grown: Array[int] = []
	mgr.batches_grown.connect(func(count: int) -> void: grown.append(count))
	for n in 20:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\n// body %d\n" % n
		check_equal(mgr.register_body(shader), n + 1, "body %d is numbered" % (n + 1))
	check_equal(mgr.batch_count(), ManagerScript.BATCH_BODY_FIRST + 40, "each with its own pair of batches")
	check_equal(grown.size(), 20, "each told (batches_grown)")
	check_equal(grown[19], mgr.batch_count(), "with the count in all")


func test_a_still_shot_of_a_card_body_draws_in_its_batch() -> void:
	var stone: int = mgr.register_body(STONE)
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(mgr._batch_of(slot), ManagerScript.BATCH_ENEMY_STILL, "a still shot of no actor is a rune of the enemy ramp")
	check(mgr.set_form(slot, &"wall", stone), "a card may name its body")
	check_equal(mgr._batch_of(slot), ManagerScript.body_batch(stone, true), "and it draws in that body's batch")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_RUNE, "still a rune to the world")


func test_a_flying_shot_of_a_quad_body_draws_plain() -> void:
	var stone: int = mgr.register_body(STONE)
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2(50, 0), 1.0)
	mgr.set_form(slot, &"swap", stone)
	check_equal(mgr._batch_of(slot), ManagerScript.BATCH_ENEMY, "a quad body draws no head: the shot draws in its motion's batch")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_BOLT, "a bolt's body")


func test_a_shader_under_each_mesh_is_two_bodies() -> void:
	var quad: int = mgr.register_body(BOLT, ManagerScript.MESH_QUAD)
	var head: int = mgr.register_body(BOLT, ManagerScript.MESH_HEAD)
	check(quad != head and quad > 0 and head > 0, "one shader, two meshes: two bodies")
	check_equal(mgr.register_body(BOLT, ManagerScript.MESH_HEAD), head, "the pair asked again is the same body")
	check_equal(mgr.body_mesh(head), ManagerScript.MESH_HEAD, "a body knows its mesh")
	check_equal(mgr.batch_mesh(ManagerScript.body_batch(head, true)), ManagerScript.MESH_HEAD, "its batches draw heads")
	check_equal(mgr.register_body(STONE), mgr.register_body(STONE, ManagerScript.MESH_QUAD), "the mesh is a quad by default, as still bodies were")


func test_a_flying_shot_of_a_head_body_draws_in_its_batch() -> void:
	var head: int = mgr.register_body(BOLT, ManagerScript.MESH_HEAD)
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2(50, 0), 1.0)
	mgr.set_form(slot, &"bolt", head)
	check_equal(mgr._batch_of(slot), ManagerScript.body_batch(head, true), "a flying shot of a head body draws in its pair")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_BOLT, "still a bolt to the world")
	var still: int = mgr.spawn(0, Vector2(140, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_form(still, &"bolt", head)
	check_equal(mgr._batch_of(still), ManagerScript.BATCH_ENEMY_STILL, "a still shot of a head body draws plain: routing never disagrees with writing")


func test_an_orbit_shot_deflected_keeps_its_head_body() -> void:
	var head: int = mgr.register_body(BOLT, ManagerScript.MESH_HEAD)
	# A bolt of 60 px/s set circling a point 30 px out: it turns 2 rad/s (orbit as a modifier, 5A).
	var slot: int = mgr.spawn(0, Vector2(130, 100), Vector2(60, 0), 1.0, 5.0)
	check(mgr.set_orbit(slot, 30.0, 0.0, 0.0, Vector2(100, 100)) and mgr._motion[slot] == ManagerScript.MOTION_ORBIT, "an orbit shot round a point")
	if slot < 0:
		return
	mgr.set_form(slot, &"bolt", head)
	check_equal(mgr._batch_of(slot), ManagerScript.body_batch(head, true), "a circling shot keeps its card's head body")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_BOLT, "and is a bolt to the world: its motion is not its body")
	mgr.step(DT)
	var tangent: Vector2 = mgr.get_velocity_of(slot)
	mgr.deflect_shot(slot, 0, Vector2.LEFT, 0)
	check_equal(mgr._batch_of(slot), ManagerScript.body_batch(head, true), "flying straight after a deflect, still a head of its body")
	check_equal(mgr._motion[slot], ManagerScript.MOTION_STRAIGHT, "it left its circle")
	var from: Vector2 = mgr.get_position_of(slot)
	mgr.step(DT)
	var went: Vector2 = mgr.get_position_of(slot) - from
	check(went.normalized().dot(tangent.normalized()) > 0.999 and absf(went.length() / DT - 60.0 * SpellLimits.DEFLECT_SPEEDUP) < 0.01, "and flies on along its tangent at its speed, sped up: %s" % (went / DT))


## Regression (5A review): a circling shot with no speed of its own (turned by its drift alone, as a
## circling rune will be) stopped dead when deflected, its curve's speed being 0. It flies on along its
## tangent at the speed it went round with, sped up, whatever its curve was.
func test_a_deflected_drift_only_orbit_flies_on() -> void:
	var slot: int = mgr.spawn(0, Vector2(130, 100), Vector2.ZERO, 2.0, 5.0)
	check(mgr.set_orbit(slot, 30.0, 0.0, 2.0, Vector2(100, 100)), "a still shot set circling by its drift")
	mgr.step(DT)
	var tangent: Vector2 = mgr.get_velocity_of(slot)
	check(absf(tangent.length() - 60.0) < 0.01, "it goes round at drift x radius: %s" % tangent)
	mgr.deflect_shot(slot, 0, Vector2.LEFT, 0)
	var from: Vector2 = mgr.get_position_of(slot)
	mgr.step(DT)
	var went: Vector2 = (mgr.get_position_of(slot) - from) / DT
	check(went.normalized().dot(tangent.normalized()) > 0.99 and absf(went.length() - 60.0 * SpellLimits.DEFLECT_SPEEDUP) < 0.01, "deflected, it flies on along its tangent, sped up: %s" % went)
	mgr.step(DT * 30.0)
	check(mgr.get_velocity_of(slot).length() > 60.0, "and keeps that speed (no curve left to slow it)")


func test_a_reused_slot_forgets_its_card() -> void:
	var stone: int = mgr.register_body(STONE)
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 0.05, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_form(slot, &"wall", stone)
	for _i in 10:
		mgr.step(DT)
	var again: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(again, slot, "the same slot is taken again")
	check_equal(mgr._batch_of(again), ManagerScript.BATCH_ENEMY_STILL, "a rune again, not the stone before")
	check_equal(mgr._form_of(again), &"rune", "told by its body again")


func test_an_impact_is_told_as_the_card_with_its_body() -> void:
	mgr.set_walls([Rect2(150.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2(240, 0), 5.0)
	mgr.set_form(slot, &"atom")
	for _i in 30:
		mgr.step(DT)
	check_equal(told.size(), 2, "it ended on the wall: its impact, then its end")
	for each: Array in told:
		check_equal(each[0], &"atom", "told as the atom it is, not a bolt")
		check_equal(each[1], ManagerScript.KIND_BOLT, "with its bolt's body")
	check_equal(mgr.impact_form, &"", "nothing told outside the event")
	check_equal(mgr.impact_body, 0, "no body outside the event")


func test_a_shot_no_card_named_is_told_by_its_body() -> void:
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 0.05, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check(slot >= 0, "spawned")
	for _i in 10:
		mgr.step(DT)
	check_equal(told.size(), 1, "its life ran out")
	if not told.is_empty():
		check_equal(told[0][0], &"rune", "told as a rune, by its body")
		check_equal(told[0][1], ManagerScript.KIND_RUNE, "with a rune's body")


func test_set_form_refuses_an_empty_slot() -> void:
	check(not mgr.set_form(-1, &"bolt"), "no slot -1")
	check(not mgr.set_form(3, &"bolt"), "nor a slot with no shot")


func test_a_body_keeps_the_first_batches_draw_order() -> void:
	# Numbered before the nodes are made (in the tree) and after: placed either way.
	var early_head: int = mgr.register_body(BOLT, ManagerScript.MESH_HEAD)
	root.add_child(mgr)
	var stone: int = mgr.register_body(STONE)
	var late_head: int = mgr.register_body(POOL, ManagerScript.MESH_HEAD)
	var at: Callable = func(batch: int) -> int: return (mgr._nodes[batch] as Node).get_index()
	for enemy: bool in [false, true]:
		var bolts: int = ManagerScript.BATCH_ENEMY if enemy else ManagerScript.BATCH_BOLT
		var runes: int = ManagerScript.BATCH_ENEMY_STILL if enemy else ManagerScript.BATCH_STILL
		var side: String = "the enemy ramp's" if enemy else "the hat ramps'"
		check(at.call(bolts) < at.call(ManagerScript.body_batch(early_head, enemy)), "%s head body draws above the plain bolts" % side)
		check(at.call(ManagerScript.body_batch(early_head, enemy)) < at.call(ManagerScript.body_batch(late_head, enemy)), "%s head bodies in the order they were numbered" % side)
		check(at.call(ManagerScript.body_batch(late_head, enemy)) < at.call(runes), "%s head bodies draw under the runes, as a plain bolt does" % side)
		check(at.call(runes) < at.call(ManagerScript.body_batch(stone, enemy)), "%s quad body draws above the plain runes" % side)
	root.remove_child(mgr)


func test_a_body_is_looked_up_without_being_numbered() -> void:
	var grown: Array[int] = []
	mgr.batches_grown.connect(func(count: int) -> void: grown.append(count))
	check_equal(mgr.body_of(STONE), 0, "a shader never numbered is no body")
	check_equal(mgr.batch_count(), ManagerScript.BATCH_BODY_FIRST, "and asking made no batches")
	check(grown.is_empty(), "nor told of any")
	var stone: int = mgr.register_body(STONE)
	check_equal(mgr.body_of(STONE), stone, "once numbered, it is found")
	check_equal(mgr.body_of(STONE, ManagerScript.MESH_HEAD), 0, "under another mesh it is another body, not numbered")
	check_equal(mgr.body_of(null), 0, "no shader is no body")


## A still shot of no actor at `at` drawn by `body` (the manager in the tree, its batches made).
func _drawn_still(body: int, at: Vector2, life: float = 5.0) -> int:
	var slot: int = mgr.spawn(0, at, Vector2.ZERO, life, 14.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_form(slot, &"pool", body)
	return slot


func test_a_watched_body_hands_out_its_still_shots_drawn() -> void:
	root.add_child(mgr)
	var pool: int = mgr.register_body(POOL)
	var stone: int = mgr.register_body(STONE)
	var views: Array = []
	mgr.still_shots_drawn.connect(func(view: StillShotView) -> void:
		views.append([view.body, view.enemy, view.count, view.at(0) if view.count > 0 else Vector2.INF, view.reach(0) if view.count > 0 else 0.0, view.clock(0).x if view.count > 0 else -1.0, view.clock(0).y if view.count > 0 else -1.0, view.ramp(0) if view.count > 0 else -1, view.look(0) if view.count > 0 else -1, view.time]))
	mgr.watch_body(pool, true)
	check(mgr.body_watched(pool) and not mgr.body_watched(stone), "only the body asked for is watched")
	mgr.update_draw(1.0)
	check(views.is_empty(), "a frame that draws none of its shots hands out nothing")
	var slot: int = _drawn_still(pool, Vector2(120.0, 90.0))
	mgr.set_look(slot, 1 << 0)
	_drawn_still(stone, Vector2(300.0, 90.0))
	for n in 30:
		mgr.step(1.0 / 60.0)
	mgr.update_draw(1.0)
	check_equal(views.size(), 1, "the watched body's batch is handed out, the other's not (%s)" % [views])
	if views.size() != 1:
		return
	var seen: Array = views[0]
	check_equal(seen[0], pool, "the view names its body")
	check(seen[1], "a shot of no actor is the enemy ramp's batch of the pair")
	check_equal(seen[2], 1, "one shot drawn")
	check(seen[3].distance_to(Vector2(120.0, 90.0)) < 0.01, "where it was drawn (%s)" % seen[3])
	check(is_equal_approx(seen[4], ManagerScript.look_size(14.0) * ManagerScript.STILL_HIT), "its hit size as drawn (%f)" % seen[4])
	check(absf(seen[5] - 0.5) < 0.02, "half a second since it was placed (%f)" % seen[5])
	check(is_equal_approx(seen[6], ManagerScript.STILL_END), "far from its end: STILL_END left (%f)" % seen[6])
	check_equal(seen[7], 0, "the enemy ramp reads as ramp 0")
	check_equal(seen[8], ManagerScript.ramp_look(-1, 1 << 0), "its look bits, the enemy ramp's flag with them")
	check(is_equal_approx(seen[9], mgr.sim_time), "drawn at the manager's clock")
	check(mgr._still_views[ManagerScript.body_batch(pool, true)].count == 0, "the view lets the rows go once it was handed out (nothing kept to copy when they are written again)")
	mgr.watch_body(pool, false)
	views.clear()
	mgr.update_draw(1.0)
	check(views.is_empty() and not mgr.body_watched(pool), "unwatched, nothing is handed out")


func test_a_head_body_is_never_watched() -> void:
	var head: int = mgr.register_body(BOLT, ManagerScript.MESH_HEAD)
	mgr.watch_body(head, true)
	check(not mgr.body_watched(head), "only still bodies' shots are read back")
	mgr.watch_body(99, true)
	check(not mgr.body_watched(99), "nor a body never numbered")


func test_a_bodys_shape_reaches_its_shader() -> void:
	root.add_child(mgr)
	var pool: int = mgr.register_body(POOL)
	for enemy: bool in [false, true]:
		var material := mgr._nodes[ManagerScript.body_batch(pool, enemy)].material as ShaderMaterial
		check_equal(material.get_shader_parameter(&"look_shape"), null, "before its card says, the shader keeps its own")
	mgr.set_body_shape(pool, Vector2(1.3, 0.75), Vector2(0.2, 0.5))
	for enemy: bool in [false, true]:
		var material := mgr._nodes[ManagerScript.body_batch(pool, enemy)].material as ShaderMaterial
		check_equal(material.get_shader_parameter(&"look_shape"), Vector2(1.3, 0.75), "its card's shape, both batches")
		check_equal(material.get_shader_parameter(&"look_clock"), Vector2(0.2, 0.5), "and its clock")
	var stone: int = mgr.register_body(STONE)
	mgr.set_body_shape(stone, Vector2(1.25, 0.6), Vector2(0.3, 0.8))
	var later := ManagerScript.new()
	own(later)
	var kept: int = later.register_body(STONE)
	later.set_body_shape(kept, Vector2(1.25, 0.6), Vector2(0.3, 0.8))
	root.add_child(later)
	var made := later._nodes[ManagerScript.body_batch(kept, false)].material as ShaderMaterial
	check_equal(made.get_shader_parameter(&"look_shape"), Vector2(1.25, 0.6), "a shape set before the batches are made reaches them when they are")
