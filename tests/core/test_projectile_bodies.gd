extends "res://tests/support/suite.gd"
## What a shot is drawn as and told as (`Projectiles.set_carrier_card`): every shot a card fired carries the
## card's id, so its impacts and its end are told as that card (`impact_carrier_card`, its card's impact
## look), and the body (`impact_body`) goes with them. A still shot may ask for a card's own body
## (a shader `register_body` numbered with the mesh it draws: a wall's stone, quads), drawn by that
## shader's pair of batches; it is still a rune to the world. A flying shot may ask for one too (a
## bolt's head, MESH_HEAD). A shot whose motion is not written as its body's mesh draws plain, and
## a body's nodes keep the first batches' draw order. The manager is stepped by hand.
## (docs/milestones/card-looks.md, phase 1.)
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/core/test_projectile_bodies.gd
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const WarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const STONE: Shader = preload("res://content/spells/carriers/wall/stone.gdshader")
const POOL: Shader = preload("res://content/spells/carriers/pool/pool.gdshader")
const BOLT: Shader = preload("res://content/spells/carriers/bolt/bolt.gdshader")

const DT: float = 1.0 / 60.0

var bus: EventsScript
var mgr: ManagerScript
## The manager's [impact_carrier_card, impact_body] as each impact or expiry was sent.
var told: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	told.clear()
	bus.projectile_impact.connect(func(_caster: int, _target: Node, _position: Vector2, _direction: Vector2) -> void:
		told.append([mgr.impact_carrier_card, mgr.impact_body]))
	bus.projectile_expired.connect(func(_caster: int, _position: Vector2, _tag: int, _shot: int) -> void:
		told.append([mgr.impact_carrier_card, mgr.impact_body]))


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
	check(mgr.set_carrier_card(slot, &"wall", stone), "a card may name its body")
	check_equal(mgr._batch_of(slot), ManagerScript.body_batch(stone, true), "and it draws in that body's batch")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_RUNE, "still a rune to the world")


func test_a_flying_shot_of_a_quad_body_draws_plain() -> void:
	var stone: int = mgr.register_body(STONE)
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2(50, 0), 1.0)
	mgr.set_carrier_card(slot, &"swap", stone)
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
	mgr.set_carrier_card(slot, &"bolt", head)
	check_equal(mgr._batch_of(slot), ManagerScript.body_batch(head, true), "a flying shot of a head body draws in its pair")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_BOLT, "still a bolt to the world")
	var still: int = mgr.spawn(0, Vector2(140, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_carrier_card(still, &"bolt", head)
	check_equal(mgr._batch_of(still), ManagerScript.BATCH_ENEMY_STILL, "a still shot of a head body draws plain: routing never disagrees with writing")


func test_an_orbit_shot_deflected_keeps_its_head_body() -> void:
	var head: int = mgr.register_body(BOLT, ManagerScript.MESH_HEAD)
	# A bolt of 60 px/s set circling a point 30 px out: it turns 2 rad/s (orbit as a modifier, 5A).
	var slot: int = mgr.spawn(0, Vector2(130, 100), Vector2(60, 0), 1.0, 5.0)
	check(mgr.set_orbit(slot, 30.0, 0.0, 0.0, Vector2(100, 100)) and mgr._motion[slot] == ManagerScript.MOTION_ORBIT, "an orbit shot round a point")
	if slot < 0:
		return
	mgr.set_carrier_card(slot, &"bolt", head)
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
	mgr.set_carrier_card(slot, &"wall", stone)
	for _i in 10:
		mgr.step(DT)
	var again: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(again, slot, "the same slot is taken again")
	check_equal(mgr._batch_of(again), ManagerScript.BATCH_ENEMY_STILL, "a rune again, not the stone before")
	check_equal(mgr._carrier_card_of(again), &"rune", "told by its body again")


func test_an_impact_is_told_as_the_card_with_its_body() -> void:
	mgr.set_walls([Rect2(150.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2(240, 0), 5.0)
	mgr.set_carrier_card(slot, &"atom")
	for _i in 30:
		mgr.step(DT)
	check_equal(told.size(), 2, "it ended on the wall: its impact, then its end")
	for each: Array in told:
		check_equal(each[0], &"atom", "told as the atom it is, not a bolt")
		check_equal(each[1], ManagerScript.KIND_BOLT, "with its bolt's body")
	check_equal(mgr.impact_carrier_card, &"", "nothing told outside the event")
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


func test_set_carrier_card_refuses_an_empty_slot() -> void:
	check(not mgr.set_carrier_card(-1, &"bolt"), "no slot -1")
	check(not mgr.set_carrier_card(3, &"bolt"), "nor a slot with no shot")


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
	mgr.set_carrier_card(slot, &"pool", body)
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


func test_a_body_on_the_floor_draws_under_the_bodies() -> void:
	# The pool was drawn over everyone, at the shots' z (the owner, 2026-11-16: "it should be drawn
	# on the floor").
	var early: int = mgr.register_body(POOL)
	mgr.set_body_ground(early, true, false)
	root.add_child(mgr)
	var stone: int = mgr.register_body(STONE)
	for enemy: bool in [false, true]:
		check_equal(mgr._nodes[ManagerScript.body_batch(early, enemy)].z_index, ManagerScript.FLOOR_DRAW_Z, "a body said to lie on the floor before its batches were made draws there")
		check_equal(mgr._nodes[ManagerScript.body_batch(stone, enemy)].z_index, ManagerScript.DRAW_Z + (1 if enemy else 0), "any other as a shot")
	check(ManagerScript.FLOOR_DRAW_Z > RoomBase.FLOOR_Z and ManagerScript.FLOOR_DRAW_Z <= 0, "over the room's floor, never over a body (z 0)")
	mgr.set_body_ground(stone, true, false)
	check_equal(mgr._nodes[ManagerScript.body_batch(stone, false)].z_index, ManagerScript.FLOOR_DRAW_Z, "and one whose batches are made moves down")
	mgr.set_body_ground(stone, false, false)
	check_equal(mgr._nodes[ManagerScript.body_batch(stone, false)].z_index, ManagerScript.DRAW_Z, "and back")
	check(mgr.body_on_floor(early) and not mgr.body_merges(early) and not mgr.body_on_floor(stone), "it says how each lies")


func test_a_merging_body_tells_its_shader_of_every_shot() -> void:
	root.add_child(mgr)
	var pool: int = mgr.register_body(POOL)
	var stone: int = mgr.register_body(STONE)
	mgr.set_body_ground(pool, true, true)
	_drawn_still(pool, Vector2(120.0, 90.0))
	_drawn_still(pool, Vector2(150.0, 96.0))
	_drawn_still(stone, Vector2(300.0, 90.0))
	mgr.update_draw(1.0)
	for enemy: bool in [false, true]:
		var material := mgr._nodes[ManagerScript.body_batch(pool, enemy)].material as ShaderMaterial
		check_equal(material.get_shader_parameter(&"merge_count"), 2, "both pools, not the stone, told to both batches")
		check_equal(material.get_shader_parameter(&"merge_first"), 0, "no hat ramp's pools: the enemy ramp's start the list")
		var places: PackedVector4Array = material.get_shader_parameter(&"merge_place")
		check_equal(places.size(), StillMerge.MOST, "a list of the shader's size")
		var found: Array = [Vector2(places[0].x, places[0].y), Vector2(places[1].x, places[1].y)]
		check(found.has(Vector2(120.0, 90.0)) and found.has(Vector2(150.0, 96.0)), "where each is drawn (%s)" % [found])
		check(is_equal_approx(places[0].z, ManagerScript.look_size(14.0) * ManagerScript.STILL_HIT), "its hit size as drawn (%f)" % places[0].z)
		check(places[0].w - roundf(places[0].w) > 0.0, "its still clock's code: just placed")
	var stone_material := mgr._nodes[ManagerScript.body_batch(stone, true)].material as ShaderMaterial
	check_equal(stone_material.get_shader_parameter(&"merge_count"), null, "a body that does not merge is told nothing")
	mgr.set_body_ground(pool, true, false)
	var stopped := mgr._nodes[ManagerScript.body_batch(pool, true)].material as ShaderMaterial
	check_equal(stopped.get_shader_parameter(&"merge_count"), 0, "a body that stops merging is told of none")


func test_both_batches_are_told_one_list_in_one_order() -> void:
	# Each batch listing its own first let the two disagree on which pool draws a pixel (review,
	# 2026-11-16): one list, the hat ramps' then the enemy ramp's, and each told where its own start.
	var hats := PackedFloat32Array()
	hats.resize(ManagerScript.DRAW_STRIDE * 2)
	var foes := PackedFloat32Array()
	foes.resize(ManagerScript.DRAW_STRIDE)
	mgr._write_quad(hats, 0, Vector2.RIGHT, 96.0, Vector2(10.0, 20.0), Color.WHITE, Color.WHITE, 1, 0.0, 0.1)
	mgr._write_quad(hats, ManagerScript.DRAW_STRIDE, Vector2.RIGHT, 96.0, Vector2(30.0, 20.0), Color.WHITE, Color.WHITE, 1, 0.0, -0.1)
	mgr._write_quad(foes, 0, Vector2.RIGHT, 48.0, Vector2(50.0, 60.0), Color.WHITE, Color.WHITE, 1)
	var merge := StillMerge.new()
	merge.fill(hats, 2, foes, 1)
	var places: PackedVector4Array = merge.places()
	check_equal(merge.count, 3, "the hat ramps' two and the enemy ramp's one")
	check_equal(Vector2(places[0].x, places[0].y), Vector2(10.0, 20.0), "the hat ramps' first, in row order")
	check_equal(Vector2(places[1].x, places[1].y), Vector2(30.0, 20.0), "")
	check_equal(Vector2(places[2].x, places[2].y), Vector2(50.0, 60.0), "then the enemy ramp's")
	check(is_equal_approx(places[2].z, 48.0 * ManagerScript.STILL_HIT), "each its hit size as drawn")
	check(absf(places[0].w - 0.1) < 0.001 and absf(places[1].w + 0.1) < 0.001, "and its clock's code (facing +x: step 0)")
	var hat_material := ShaderMaterial.new()
	var foe_material := ShaderMaterial.new()
	hat_material.shader = POOL
	foe_material.shader = POOL
	merge.hand_to(hat_material, false)
	merge.hand_to(foe_material, true)
	check_equal(hat_material.get_shader_parameter(&"merge_first"), 0, "the hat ramps' batch finds its shots from the start")
	check_equal(foe_material.get_shader_parameter(&"merge_first"), 2, "the enemy ramp's after the hat ramps'")
	check(hat_material.get_shader_parameter(&"merge_place") == foe_material.get_shader_parameter(&"merge_place"), "one list for both")
	var many := PackedFloat32Array()
	many.resize(ManagerScript.DRAW_STRIDE * (StillMerge.MOST + 5))
	merge.fill(many, StillMerge.MOST + 5, foes, 1)
	check_equal(merge.count, StillMerge.MOST, "never past the shader's list: the rest are drawn alone")
	check_equal(merge.enemy_first, StillMerge.MOST, "and the enemy ramp's past it")


func test_a_merge_fills_its_lists_in_turn() -> void:
	# A list a material holds is copied if written (an allocation a frame): the next frame fills
	# the other.
	var rows := PackedFloat32Array()
	rows.resize(ManagerScript.DRAW_STRIDE)
	mgr._write_quad(rows, 0, Vector2.RIGHT, 96.0, Vector2(10.0, 20.0), Color.WHITE, Color.WHITE, 1)
	var merge := StillMerge.new()
	merge.fill(rows, 1, PackedFloat32Array(), 0)
	var first: PackedVector4Array = merge.places()
	mgr._write_quad(rows, 0, Vector2.RIGHT, 96.0, Vector2(70.0, 20.0), Color.WHITE, Color.WHITE, 1)
	merge.fill(rows, 1, PackedFloat32Array(), 0)
	check_equal(first[0].x, 10.0, "the list handed out last frame is left as it was")
	check_equal(merge.places()[0].x, 70.0, "the frame's own is the other")


func test_the_merge_list_is_the_shaders_size() -> void:
	var code: String = POOL.code
	check(code.contains("const int MERGE_MOST = %d;" % StillMerge.MOST), "pool.gdshader's MERGE_MOST is StillMerge.MOST")
	check(code.contains("const float FACING_STEPS = %d.0;" % StillMerge.FACING_STEPS), "and its FACING_STEPS StillMerge's")


func test_a_still_shot_thrown_one_way_turns_its_quad_that_way() -> void:
	root.add_child(mgr)
	var pool: int = mgr.register_body(POOL)
	var slot: int = _drawn_still(pool, Vector2(120.0, 90.0))
	var down := Vector2(0.0, 1.0)
	check(mgr.set_facing(slot, down * 3.0), "a still shot takes a facing")
	check(mgr.get_facing_of(slot).is_equal_approx(down), "made a unit vector")
	var flying: int = mgr.spawn(0, Vector2(10, 10), Vector2(50, 0), 1.0)
	check(not mgr.set_facing(flying, down), "a flying shot never: it faces where it flies")
	check(not mgr.set_facing(slot, Vector2.ZERO), "nor no direction")
	mgr.set_body_ground(pool, true, true)
	var across: Array = []
	mgr.still_shots_drawn.connect(func(view: StillShotView) -> void:
		across.append(view.across(0)))
	mgr.watch_body(pool, true)
	mgr.update_draw(1.0)
	check(across.size() == 1 and (across[0] as Vector2).is_equal_approx(down), "its quad turns the way it was thrown (%s)" % [across])
	var material := mgr._nodes[ManagerScript.body_batch(pool, true)].material as ShaderMaterial
	var w: float = (material.get_shader_parameter(&"merge_place") as PackedVector4Array)[0].w
	check_equal(roundi(w), StillMerge.FACING_STEPS / 4, "and its shader is told so, a quarter turn")
	check(absf(w - roundf(w) - mgr.still_code(mgr.sim_time - mgr._born[slot], mgr._life[slot])) < 0.001, "beside its clock's code")
	var again: int = _drawn_still(pool, Vector2(200.0, 90.0))
	check_equal(mgr.get_facing_of(again), Vector2.ZERO, "a new still shot faces nowhere until told")


func test_the_projectile_manager_is_before_the_world_and_the_areas_that_draw_over_the_floor() -> void:
	# FLOOR_DRAW_Z is the bodies' z 0, a tie the manager loses by being an earlier autoload than the
	# areas drawing at 0 (Feel's lying remnants and ground items) and than the world (added after
	# every autoload).
	var lines: PackedStringArray = FileAccess.get_file_as_string("res://project.godot").split("\n")
	var at: Dictionary = {}
	for n in lines.size():
		var name: String = lines[n].get_slice("=", 0)
		if name in ["Projectiles", "Feel", "Entities"]:
			at[name] = n
	check(at.size() == 3, "the three autoloads are listed (%s)" % [at])
	if at.size() == 3:
		check(at["Projectiles"] < at["Feel"] and at["Projectiles"] < at["Entities"], "the manager comes first, so a pool draws under them at one z")
