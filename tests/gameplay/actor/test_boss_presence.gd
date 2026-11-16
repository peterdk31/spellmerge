extends "res://tests/support/suite.gd"
## A boss in play, told to the HUD (boss plan OB16, gameplay/actor/boss_presence.gd): a boss body
## (its data's `boss`) gets one `BossPresence` look, no other body has one; as it enters play it sends
## `boss_shown` once (its id, its name, its lore line, a mark at each phase's health share), then its
## health; each change of its health follows (a hit, a player joining); and `boss_hidden` once when it
## dies or leaves the tree, with the id it was shown under, and it is shown again as it comes back. A
## boss of the test's own; nothing here names a boss of the game. The bar and the banner are tested
## in tests/hud/test_boss_bar.gd.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_boss_presence.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")

var fx: Fixture
## What the bus said, in order: [event, args...].
var heard: Array[Array] = []


func before_each() -> void:
	fx = Fixture.new(root)
	heard.clear()
	fx.bus.boss_shown.connect(func(actor: int, boss_name: String, lore: String, marks: PackedFloat32Array) -> void: heard.append([&"shown", actor, boss_name, lore, marks]))
	fx.bus.boss_health_changed.connect(func(actor: int, health: float, most: float) -> void: heard.append([&"health", actor, health, most]))
	fx.bus.boss_hidden.connect(func(actor: int) -> void: heard.append([&"hidden", actor]))


func after_each() -> void:
	fx.free_all()


## A boss of the test's own: a phase under 0.6 of its health, one under 0.25, and one by time only.
func _boss_data() -> EnemyBase:
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.id = &"test_boss"
	data.display_name = "The Test Boss"
	data.lore = "It was made for this test."
	data.boss = true
	data.max_health = 200.0
	var late := EnemyPhase.new()
	late.health_below = 0.25
	var timed := EnemyPhase.new()
	timed.after_seconds = 1000.0
	var first := EnemyPhase.new()
	first.health_below = 0.6
	data.phases = [first, timed, late] as Array[EnemyPhase]
	return data


func _presences(body: Node) -> int:
	var count: int = 0
	for child in body.get_children():
		if child is BossPresence:
			count += 1
	return count


func _of(kind: StringName) -> Array[Array]:
	var found: Array[Array] = []
	for row in heard:
		if row[0] == kind:
			found.append(row)
	return found


func test_a_boss_is_shown_once_with_its_name_lore_and_marks_then_its_health() -> void:
	var body: Actor = fx.imp(Vector2.ZERO, _boss_data())
	check_equal(_presences(body), 1, "a boss body has one presence")
	check_equal(heard.size(), 2, "shown, then its health")
	check_equal(heard[0][0], &"shown", "shown first")
	check_equal(heard[0][1], body.id, "under its id")
	check_equal(heard[0][2], "The Test Boss", "its name")
	check_equal(heard[0][3], "It was made for this test.", "its lore")
	check_equal(heard[0][4], PackedFloat32Array([0.6, 0.25]), "a mark a phase by health, largest first; none for one by time")
	check_equal(heard[1], [&"health", body.id, 200.0, 200.0], "then its health, full")


func test_a_boss_with_no_name_is_shown_by_its_id_in_words() -> void:
	var data: EnemyBase = _boss_data()
	data.display_name = ""
	data.phases = [] as Array[EnemyPhase]
	fx.imp(Vector2.ZERO, data)
	check_equal(heard[0][2], "Test Boss", "its id in words (`EnemyBase.shown_name`)")
	check_equal(heard[0][4], PackedFloat32Array(), "no phases: no marks")


func test_another_body_has_none_and_says_nothing() -> void:
	var body: Actor = fx.imp(Vector2.ZERO)
	check_equal(_presences(body), 0, "a stray has none")
	fx.combat.hit(fx.players[0].id, body, 1.0)
	body.free()
	check(heard.is_empty(), "and nothing is told of it")


func test_its_health_follows_hits_and_the_players() -> void:
	var body: Actor = fx.imp(Vector2.ZERO, _boss_data())
	heard.clear()
	fx.combat.hit(fx.players[0].id, body, 50.0)
	check_equal(_of(&"health").back(), [&"health", body.id, 150.0, 200.0], "a hit")
	body.data.health_per_player = 0.5
	body.count_players(2)
	check_equal(_of(&"health").back(), [&"health", body.id, 225.0, 300.0], "a second player: its most and health by the same share")
	check(_of(&"shown").is_empty(), "never shown again meanwhile")


func test_its_death_hides_it_once() -> void:
	var body: Actor = fx.imp(Vector2.ZERO, _boss_data())
	var id: int = body.id
	heard.clear()
	fx.combat.hit(fx.players[0].id, body, 500.0)
	check_equal(_of(&"hidden"), [[&"hidden", id]] as Array[Array], "hidden as it dies")
	body.free()
	check_equal(_of(&"hidden").size(), 1, "once, though its body then leaves")


func test_leaving_the_tree_hides_it_and_coming_back_shows_it_again() -> void:
	var body: Actor = fx.imp(Vector2.ZERO, _boss_data())
	var id: int = body.id
	var parent: Node = body.get_parent()
	heard.clear()
	parent.remove_child(body)
	check_equal(heard, [[&"hidden", id]] as Array[Array], "hidden under the id it was shown under (its body's is closed)")
	heard.clear()
	parent.add_child(body)
	check_equal(_of(&"shown").size(), 1, "shown again as it comes back")
	check_equal(_of(&"shown")[0][1], body.id, "under its id now")
	check_equal(_of(&"health").size(), 1, "with its health")


func test_after_a_snapshot_its_health_is_told_again_not_its_entrance() -> void:
	var body: Actor = fx.imp(Vector2.ZERO, _boss_data())
	fx.combat.hit(fx.players[0].id, body, 20.0)
	heard.clear()
	body.rebuild_derived()
	check_equal(heard, [[&"health", body.id, 180.0, 200.0]] as Array[Array], "its health only")
