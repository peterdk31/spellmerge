extends "res://tests/support/suite.gd"
## The projectile manager's hit table (`HitTable`, perf plan H1): every `projectile_hit` it sends is
## a row of the table, written in the order the hits are sent, and handed to the table's applier
## after the event's listeners heard it (`sending` names the row meanwhile). A hit a listener sends
## is a row of its own, applied inside. The table is emptied when a step begins and grows past its
## first size keeping its rows. The manager is stepped by hand; the applier is the test's.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0

var bus: EventsScript
var mgr: ManagerScript
## What happened, in order: "hit <row being sent>" for each `projectile_hit`, "apply <row>" for each
## row applied.
var order: Array[String] = []
## Each `projectile_hit` as [caster, target, at, tag, shot, impact_count].
var heard: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	order.clear()
	heard.clear()
	mgr.hit_table.applier = _apply
	bus.projectile_hit.connect(func(caster: int, target: Node, at: Vector2, tag: int, shot: int) -> void:
		order.append("hit %d" % mgr.hit_table.sending)
		heard.append([caster, target, at, tag, shot, mgr.impact_count]))


func _apply(table: HitTable, row: int) -> void:
	check(table == mgr.hit_table, "the applier is handed the manager's table")
	check(table.sending != row, "a row is applied once its send is over")
	order.append("apply %d" % row)


func _target(at: Vector2) -> Node2D:
	var body := own(Node2D.new()) as Node2D
	root.add_child(body)
	body.global_position = at
	mgr.add_target(body, 8.0, ManagerScript.LAYER_ENEMY)
	return body


func test_each_hit_is_a_row_applied_after_its_listeners() -> void:
	var a: Node2D = _target(Vector2(100.0, 100.0))
	var b: Node2D = _target(Vector2(300.0, 100.0))
	check(mgr.strike(1, a, Vector2(100.0, 100.0), Vector2.RIGHT, 7, &"swing"), "the first strike was sent")
	check(mgr.strike(2, b, Vector2(300.0, 100.0), Vector2.LEFT, 9, &"swing"), "the second strike was sent")
	check_equal(order, ["hit 0", "apply 0", "hit 1", "apply 1"] as Array[String], "each row's hit heard, then the row applied")
	var table: HitTable = mgr.hit_table
	check_equal(table.rows, 2, "two rows")
	for row in table.rows:
		var event: Array = heard[row]
		check_equal([table.caster[row], table.target[row], table.at[row], table.tag[row], table.shot[row], table.count[row]], event, "row %d says what its event said" % row)
	check_equal(table.card[0], &"swing", "a row keeps its carrier card")
	check(table.heading[1].is_equal_approx(Vector2.LEFT), "and its heading")


func test_merged_hits_are_one_row_counting_them() -> void:
	var body: Node2D = _target(Vector2(200.0, 100.0))
	for i in 3:
		mgr.spawn(4, Vector2(150.0, 100.0 + float(i)), Vector2(600.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 5)
	var rows: int = 0
	for _i in 10:
		mgr.step(DT)
		rows = maxi(rows, mgr.hit_table.rows)
	check_equal(heard.size(), 1, "three shots of one spell on one body in one pass: one hit sent")
	if heard.is_empty():
		return
	check_equal(heard[0][5], 3, "standing for three hits")
	check_equal(rows, 1, "one row")
	check_equal(order, ["hit 0", "apply 0"] as Array[String], "applied after it was heard")
	check(heard[0][1] == body, "on the body")


func test_a_hit_a_listener_sends_is_a_row_applied_inside() -> void:
	var a: Node2D = _target(Vector2(100.0, 100.0))
	var b: Node2D = _target(Vector2(300.0, 100.0))
	var once: Array[bool] = [false]
	bus.projectile_hit.connect(func(_c: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
		if target == a and not once[0]:
			once[0] = true
			mgr.strike(3, b, Vector2(300.0, 100.0), Vector2.RIGHT, 8, &"swing"))
	mgr.strike(1, a, Vector2(100.0, 100.0), Vector2.RIGHT, 7, &"swing")
	check_equal(order, ["hit 0", "hit 1", "apply 1", "apply 0"] as Array[String], "the inner row is heard and applied inside the outer row's send")


func test_a_step_empties_the_table() -> void:
	var a: Node2D = _target(Vector2(100.0, 100.0))
	mgr.strike(1, a, Vector2(100.0, 100.0), Vector2.RIGHT, 7, &"swing")
	check_equal(mgr.hit_table.rows, 1, "a row")
	mgr.step(DT)
	check_equal(mgr.hit_table.rows, 0, "the step began with an empty table")


func test_the_table_grows_keeping_its_rows() -> void:
	var table := HitTable.new()
	var node := own(Node2D.new()) as Node2D
	var n: int = HitTable.FIRST_ROWS * 2 + 3
	for i in n:
		check_equal(table.write(i, node, Vector2(i, 0.0), Vector2.RIGHT, i * 10, i, 1, &"bolt", 0, Color.WHITE, i), i, "rows numbered in order")
	check_equal(table.rows, n, "every row kept")
	var right: bool = true
	for i in n:
		right = right and table.caster[i] == i and table.tag[i] == i * 10 and table.look[i] == i and table.at[i] == Vector2(i, 0.0)
	check(right, "every row's columns kept through the growth")
	table.empty()
	check_equal(table.rows, 0, "emptied")


func test_with_no_applier_the_hits_are_still_sent() -> void:
	mgr.hit_table.applier = Callable()
	var a: Node2D = _target(Vector2(100.0, 100.0))
	check(mgr.strike(1, a, Vector2(100.0, 100.0), Vector2.RIGHT, 7, &"swing"), "sent")
	check_equal(order, ["hit 0"] as Array[String], "heard, nothing applied")
