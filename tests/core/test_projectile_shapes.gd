extends "res://tests/support/suite.gd"
## The element shapes of core/projectiles (#244): a shot with a shape is drawn with its kind in
## the custom data (the shader builds the silhouette and the animation from it), a straight
## player bolt with a shape gets trail marks in a batch of their own, and the number of marks
## is bounded whatever the shot count is. The manager is stepped and drawn by hand.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ELEMENTS: Array[String] = [
	"res://content/spells/elements/fire/fire.tres",
	"res://content/spells/elements/frost/frost.tres",
	"res://content/spells/elements/storm/storm.tres",
	"res://content/spells/elements/void/void.tres",
]

var mgr: ManagerScript


func before_each() -> void:
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	mgr.set_cap(600)
	root.add_child(mgr)


## The kind written in the custom data of instance `i` of a node's buffer.
func kind_at(node: MultiMeshInstance2D, i: int) -> int:
	var buffer: PackedFloat32Array = node.multimesh.buffer
	return roundi((1.0 - buffer[i * ManagerScript.DRAW_STRIDE + 15]) * 10.0)


func test_set_shape_takes_a_live_shot_in_range_only() -> void:
	var slot: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 1.0)
	check(mgr.set_shape(slot, ManagerScript.SHAPE_RING), "a live shot takes a shape")
	check_equal(mgr.get_shape_of(slot), ManagerScript.SHAPE_RING, "and keeps it")
	check(not mgr.set_shape(slot, ManagerScript.SHAPE_COUNT), "a shape past the last is refused")
	check(not mgr.set_shape(slot, -1), "a negative shape is refused")
	check(not mgr.set_shape(-1, 1) and not mgr.set_shape(999999, 1), "a slot out of range is refused")
	check_equal(mgr.get_shape_of(slot), ManagerScript.SHAPE_RING, "a refused shape changes nothing")


func test_a_shaped_bolt_is_drawn_with_its_kind_and_two_trail_marks() -> void:
	var plain: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 1.0)
	var kinds: Array[int] = []
	for shape in range(1, ManagerScript.SHAPE_COUNT):
		var slot: int = mgr.spawn(1, Vector2(50.0, 60.0 + shape * 20.0), Vector2(100.0, 0.0), 1.0)
		mgr.set_shape(slot, shape)
		kinds.append(shape)
	mgr.update_draw(1.0)
	check(plain >= 0, "the plain bolt exists")
	check_equal(mgr.drawn, 5, "five bolts drawn")
	check_equal(mgr.drawn_trails, 8, "two marks behind each of the four shaped bolts, none behind the plain one")
	var seen: Array[int] = []
	for i in 5:
		seen.append(kind_at(mgr._draw_node, i))
	seen.sort()
	check_equal(seen, [0, 1, 2, 3, 4] as Array[int], "each shape writes its own kind, the plain bolt 0")
	var marks: Array[int] = []
	for i in 8:
		marks.append(kind_at(mgr._trail_node, i))
	marks.sort()
	check_equal(marks, [5, 5, 6, 6, 7, 7, 8, 8] as Array[int], "each mark is its shape's kind plus four")


func test_the_trail_lies_behind_the_bolt() -> void:
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 1.0)
	mgr.set_shape(slot, ManagerScript.SHAPE_FLAME)
	mgr.update_draw(1.0)
	var buffer: PackedFloat32Array = mgr._trail_node.multimesh.buffer
	for i in 2:
		var x: float = buffer[i * ManagerScript.DRAW_STRIDE + 3]
		check(x < 100.0, "mark %d is behind a bolt flying right (x %.1f)" % [i, x])
	check(buffer[3] > buffer[ManagerScript.DRAW_STRIDE + 3], "the marks run back from the bolt, nearest first")


func test_runes_enemy_shots_and_orbit_shots_get_no_trail() -> void:
	var rune: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2.ZERO, 1.0, 8.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_shape(rune, ManagerScript.SHAPE_STAR)
	var enemy: int = mgr.spawn(-1, Vector2(80.0, 50.0), Vector2(-60.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.set_shape(enemy, ManagerScript.SHAPE_FLAME)
	mgr.set_anchor(2, Vector2(200.0, 200.0))
	var orb: int = mgr.spawn_orbit(2, 20.0, 0.0, 1.0, 1.0)
	mgr.set_shape(orb, ManagerScript.SHAPE_RING)
	mgr.update_draw(1.0)
	check_equal(mgr.drawn_trails, 0, "none of them trails")
	check_equal(kind_at(mgr._hostile_node, 0), 0, "an enemy shot stays the enemy sprite, whatever its shape")


func test_runes_and_orbit_shots_are_drawn_as_their_form_whatever_the_element() -> void:
	var rune: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2.ZERO, 1.0, 8.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_anchor(2, Vector2(200.0, 200.0))
	mgr.spawn_orbit(2, 20.0, 0.0, 1.0, 1.0)
	mgr.update_draw(1.0)
	check_equal(kind_at(mgr._rune_node, 0), ManagerScript.KIND_RUNE, "a plain rune is drawn as a rune")
	check_equal(kind_at(mgr._orbit_node, 0), ManagerScript.KIND_ORBIT, "a plain orbit shot is drawn as a pair of beads")
	mgr.set_shape(rune, ManagerScript.SHAPE_STAR)
	mgr.update_draw(1.0)
	check_equal(kind_at(mgr._rune_node, 0), ManagerScript.KIND_RUNE, "an element's shape does not change a rune's body")
	check(ManagerScript.KIND_RUNE != ManagerScript.KIND_ORBIT, "so rune and orbit differ in flight")


func test_shaped_bodies_are_drawn_smaller_than_the_sprite() -> void:
	var plain: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 1.0)
	var shaped: int = mgr.spawn(0, Vector2(100.0, 200.0), Vector2(100.0, 0.0), 1.0)
	mgr.set_shape(shaped, ManagerScript.SHAPE_FLAME)
	mgr.update_draw(1.0)
	var buffer: PackedFloat32Array = mgr._draw_node.multimesh.buffer
	var sizes: Array[float] = [buffer[0], buffer[ManagerScript.DRAW_STRIDE]]
	sizes.sort()
	check(absf(sizes[0] / sizes[1] - ManagerScript.SHAPE_SCALE) < 0.01, "a shaped body is drawn at SHAPE_SCALE of the sprite")
	check(plain != shaped, "two shots")


func test_trail_marks_are_bounded() -> void:
	for i in 300:
		var slot: int = mgr.spawn(i % 4, Vector2(20.0 + i, 20.0 + (i % 10) * 10.0), Vector2(100.0, 0.0), 1.0)
		mgr.set_shape(slot, 1 + i % 4)
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, 300, "all the bolts are drawn")
	check_equal(mgr.drawn_trails, ManagerScript.TRAIL_MAX, "the marks stop at the limit")
	check(mgr._trail_node.multimesh.instance_count <= ManagerScript.TRAIL_MAX, "and so does the batch")
	mgr.clear()
	mgr.update_draw(1.0)
	check_equal(mgr.drawn_trails, 0, "the marks go with the shots")


func test_the_shape_range_matches_the_shape_count() -> void:
	var element: ElementBase = load(ELEMENTS[0]) as ElementBase
	check_equal(int((element.ranges()["shape"] as Vector2).y), ManagerScript.SHAPE_COUNT - 1, "ElementBase's top shape is the manager's last")


func test_trail_marks_stay_consistent_under_a_small_cap() -> void:
	mgr.set_cap(40)
	for i in 30:
		var slot: int = mgr.spawn(i % 4, Vector2(20.0 + i, 20.0 + (i % 10) * 10.0), Vector2(100.0, 0.0), 1.0)
		mgr.set_shape(slot, 1 + i % 4)
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, 30, "all the bolts are drawn")
	check_equal(mgr.drawn_trails, 30 * ManagerScript.TRAIL_MARKS, "every bolt gets its marks")
	check(mgr._trail_node.multimesh.instance_count >= mgr.drawn_trails, "the batch has room for every mark")
	check_equal(mgr._trail_buffer.size(), mgr._trail_node.multimesh.instance_count * ManagerScript.DRAW_STRIDE, "and the buffer is exactly the batch")


func test_shapes_animate_from_the_simulation_clock() -> void:
	var slot: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(10.0, 0.0), 1.0)
	mgr.set_shape(slot, ManagerScript.SHAPE_FLAME)
	for i in 30:
		mgr.step(1.0 / 60.0)
	mgr.update_draw(1.0)
	var drawn_time: float = float((mgr._draw_node.material as ShaderMaterial).get_shader_parameter(&"sim_time"))
	check_equal(drawn_time, mgr.sim_time, "the batch is drawn at the simulation time")
	check(absf(mgr.sim_time - 0.5) < 0.001, "which counts the stepped seconds, not the engine's clock")
	check_equal(float((mgr._trail_node.material as ShaderMaterial).get_shader_parameter(&"sim_time")), mgr.sim_time, "so is the trail")


func test_a_reused_slot_starts_plain() -> void:
	var slot: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 1.0)
	mgr.set_shape(slot, ManagerScript.SHAPE_ZIGZAG)
	mgr.clear()
	var again: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 1.0)
	check_equal(mgr.get_shape_of(again), 0, "a new shot is plain, not the last one's shape")


func test_the_four_elements_have_four_different_shapes() -> void:
	var seen: Array[int] = []
	for path in ELEMENTS:
		var element: ElementBase = load(path) as ElementBase
		check(element != null, "%s loads" % path)
		if element == null:
			continue
		check(element.shape >= 1 and element.shape < ManagerScript.SHAPE_COUNT, "%s has a shape" % element.id)
		check(not seen.has(element.shape), "%s has a shape of its own" % element.id)
		seen.append(element.shape)
		check(element.range_problems().is_empty(), "%s is in range" % element.id)
