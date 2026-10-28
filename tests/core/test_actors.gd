extends "res://tests/support/suite.gd"
## `core/actors` (the `Actors` autoload; actors G2, docs/milestones/M2-actors.md, "Core: the
## actor table and one caster number"): ids handed out lowest free first and freed again, a full
## table, team, ramp and seat, a seat held by one actor at a time, the budget of seated and
## unseated actors, a node lookup that forgets freed nodes, safe answers for bad ids, and the
## spell runtime opening and closing an actor under each enemy caster row. Each test makes its
## own table.
##
## godot --headless --path . --script res://tests/core/test_actors.gd

const ActorsScript := preload("res://core/actors/actors.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

var _actors: ActorsScript


func before_each() -> void:
	_actors = own(ActorsScript.new()) as ActorsScript


func _open_enemies(count: int) -> Array[int]:
	var ids: Array[int] = []
	for i in count:
		ids.append(_actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY))
	return ids


func test_ids_are_handed_out_lowest_first() -> void:
	check_equal(_open_enemies(4), [0, 1, 2, 3] as Array[int], "0, 1, 2, 3 in order")
	check_equal(_actors.open_count(), 4, "four open")
	check(_actors.is_open(2) and not _actors.is_open(4), "the opened ids are open, the next is not")


func test_a_closed_id_is_free_again_lowest_first() -> void:
	_open_enemies(6)
	_actors.close(4)
	_actors.close(1)
	check(not _actors.is_open(1), "a closed id is closed")
	check_equal(_actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY), 1, "the lowest free id comes back first")
	check_equal(_actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY), 4, "then the next free one")
	check_equal(_actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY), 6, "then a new one")
	check_equal(_actors.open_count(), 7, "seven open")


func test_closing_twice_or_a_bad_id_changes_nothing() -> void:
	_open_enemies(2)
	_actors.close(1)
	_actors.close(1)
	_actors.close(-1)
	_actors.close(ActorsScript.ACTORS)
	check_equal(_actors.open_count(), 1, "only the one close counted")


func test_a_full_table_opens_none_until_one_closes() -> void:
	var ids: Array[int] = _open_enemies(ActorsScript.ACTORS)
	check_equal(ids[-1], ActorsScript.ACTORS - 1, "every id is used")
	check_equal(_actors.open(ActorsScript.TEAM_WIZARDS, 0, 0), ActorsScript.NONE, "a full table opens none")
	check_equal(_actors.actor_of_seat(0), ActorsScript.NONE, "and seats nothing")
	_actors.close(300)
	check_equal(_actors.open(ActorsScript.TEAM_WIZARDS, 0), 300, "a closed id is free again")


func test_an_actor_keeps_its_team_ramp_and_seat() -> void:
	_open_enemies(5)
	var wizard: int = _actors.open(ActorsScript.TEAM_WIZARDS, 2, 2)
	check_equal(wizard, 5, "a wizard need not have the id of its seat")
	check_equal(_actors.team_of(wizard), ActorsScript.TEAM_WIZARDS, "its team")
	check_equal(_actors.ramp_of(wizard), 2, "its ramp")
	check_equal(_actors.seat_of(wizard), 2, "its seat")
	check_equal(_actors.actor_of_seat(2), wizard, "the seat drives it")
	check_equal(_actors.team_of(0), ActorsScript.TEAM_ENEMIES, "an enemy's team")
	check_equal(_actors.ramp_of(0), ActorsScript.RAMP_ENEMY, "an enemy's ramp")
	check_equal(_actors.seat_of(0), ActorsScript.NONE, "an enemy has no seat")


func test_budget_is_the_seat_or_shared() -> void:
	var imp: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	for seat in ActorsScript.SEATS:
		var wizard: int = _actors.open(ActorsScript.TEAM_WIZARDS, seat, seat)
		check_equal(_actors.budget_of(wizard), seat, "seat %d spends its own budget" % seat)
	check_equal(_actors.budget_of(imp), ActorsScript.SHARED, "an unseated actor spends the shared one")
	check_equal(ActorsScript.SHARED, ActorsScript.SEATS, "the shared budget follows the seats'")
	check_equal(_actors.budget_of(ActorsScript.ACTORS - 1), ActorsScript.SHARED, "no actor: shared")


func test_set_driver_moves_team_seat_and_budget() -> void:
	var wizard: int = _actors.open(ActorsScript.TEAM_WIZARDS, 1, 1)
	var imp: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	# The wizard's seat drives the imp; the wizard's body has no driver.
	_actors.set_driver(wizard, ActorsScript.NONE, ActorsScript.NONE)
	_actors.set_driver(imp, ActorsScript.TEAM_WIZARDS, 1)
	check_equal(_actors.actor_of_seat(1), imp, "the seat drives the imp")
	check_equal(_actors.team_of(imp), ActorsScript.TEAM_WIZARDS, "the imp aims at enemies")
	check_equal(_actors.budget_of(imp), 1, "and spends the seat's budget")
	check_equal(_actors.ramp_of(imp), ActorsScript.RAMP_ENEMY, "its spells keep its own colours")
	check_equal(_actors.budget_of(wizard), ActorsScript.SHARED, "the wizard's body is unseated")
	# The controllers go home.
	_actors.set_driver(imp, ActorsScript.TEAM_ENEMIES, ActorsScript.NONE)
	_actors.set_driver(wizard, ActorsScript.TEAM_WIZARDS, 1)
	check_equal(_actors.actor_of_seat(1), wizard, "the seat is back on the wizard")
	check_equal(_actors.seat_of(imp), ActorsScript.NONE, "the imp has no seat")
	check_equal(_actors.team_of(imp), ActorsScript.TEAM_ENEMIES, "and its team again")


func test_a_seat_drives_one_actor_and_the_newer_takes_it() -> void:
	var first: int = _actors.open(ActorsScript.TEAM_WIZARDS, 0, 0)
	var second: int = _actors.open(ActorsScript.TEAM_WIZARDS, 0, 0)
	check_equal(_actors.actor_of_seat(0), second, "the newer actor holds the seat")
	check_equal(_actors.seat_of(first), ActorsScript.NONE, "the older one lost it")
	_actors.set_driver(first, ActorsScript.TEAM_WIZARDS, 0)
	check_equal(_actors.actor_of_seat(0), first, "set_driver takes it back")
	check_equal(_actors.seat_of(second), ActorsScript.NONE, "from the other")


func test_closing_a_seated_actor_frees_its_seat() -> void:
	var wizard: int = _actors.open(ActorsScript.TEAM_WIZARDS, 3, 3)
	_actors.close(wizard)
	check_equal(_actors.actor_of_seat(3), ActorsScript.NONE, "no actor in the seat")
	var next: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	check_equal(next, wizard, "the id is reused")
	check_equal(_actors.seat_of(next), ActorsScript.NONE, "without the old seat")


func test_a_bad_seat_is_no_seat() -> void:
	var actor: int = _actors.open(ActorsScript.TEAM_WIZARDS, 0, ActorsScript.SEATS)
	check_equal(_actors.seat_of(actor), ActorsScript.NONE, "seat 4 is no seat")
	check_equal(_actors.actor_of_seat(ActorsScript.SEATS), ActorsScript.NONE, "nothing in seat 4")
	check_equal(_actors.actor_of_seat(-1), ActorsScript.NONE, "nothing in seat -1")


func test_bad_ids_answer_none() -> void:
	for id in [-1, 7, ActorsScript.ACTORS, ActorsScript.ACTORS + 10]:
		check(not _actors.is_open(id), "%d is not open" % id)
		check_equal(_actors.team_of(id), ActorsScript.NONE, "no team for %d" % id)
		check_equal(_actors.ramp_of(id), ActorsScript.NONE, "no ramp for %d" % id)
		check_equal(_actors.seat_of(id), ActorsScript.NONE, "no seat for %d" % id)
		check(_actors.node_of(id) == null, "no node for %d" % id)
		_actors.set_driver(id, ActorsScript.TEAM_WIZARDS, 0)
		_actors.set_node(id, _actors)
	check_equal(_actors.actor_of_seat(0), ActorsScript.NONE, "set_driver on a bad id seats nothing")
	check_equal(_actors.open_count(), 0, "nothing opened")


func test_node_of_forgets_a_freed_node() -> void:
	var id: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	check(_actors.node_of(id) == null, "no node yet")
	var body := Node2D.new()
	_actors.set_node(id, body)
	check(_actors.node_of(id) == body, "the node is found")
	body.free()
	check(_actors.node_of(id) == null, "a freed node is null")
	var other := own(Node2D.new()) as Node2D
	_actors.set_node(id, other)
	_actors.close(id)
	check(_actors.node_of(id) == null, "a closed actor has no node")
	_actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	check(_actors.node_of(id) == null, "nor does the next actor with its id")


func test_clear_closes_everything() -> void:
	_open_enemies(10)
	_actors.open(ActorsScript.TEAM_WIZARDS, 0, 0)
	_actors.clear()
	check_equal(_actors.open_count(), 0, "nothing open")
	check_equal(_actors.actor_of_seat(0), ActorsScript.NONE, "no seat held")
	check_equal(_actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY), 0, "ids start again at 0")


func test_enemy_caster_rows_open_and_close_actors() -> void:
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.actors = _actors
	var first: int = spells.open_enemy_caster()
	var second: int = spells.open_enemy_caster()
	check_equal(first, SpellLimits.FIRST_ENEMY_CASTER, "the caster numbers are as before")
	var actor: int = spells.actor_of_caster(second)
	check(_actors.is_open(actor), "the row opened an actor")
	check_equal(_actors.team_of(actor), ActorsScript.TEAM_ENEMIES, "on the enemies' team")
	check_equal(_actors.ramp_of(actor), ActorsScript.RAMP_ENEMY, "in the enemy ramp")
	check_equal(_actors.budget_of(actor), ActorsScript.SHARED, "spending the shared budget")
	check_equal(spells.actor_of_caster(0), ActorsScript.NONE, "a player has no actor from Spells yet")
	spells.close_enemy_caster(second)
	check(not _actors.is_open(actor), "closing the row closes the actor")
	check_equal(spells.actor_of_caster(second), ActorsScript.NONE, "a closed row has none")
	spells.clear()
	check_equal(_actors.open_count(), 0, "clear closes the rest")


func test_a_freed_runtime_closes_its_actors() -> void:
	var spells: SpellsScript = SpellsScript.new()
	spells.actors = _actors
	for i in 3:
		spells.open_enemy_caster()
	check_equal(_actors.open_count(), 3, "three rows, three actors")
	spells.free()
	check_equal(_actors.open_count(), 0, "none left open in the table")


func test_a_full_table_leaves_the_row_working() -> void:
	_open_enemies(ActorsScript.ACTORS)
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.actors = _actors
	var caster: int = spells.open_enemy_caster()
	check_equal(caster, SpellLimits.FIRST_ENEMY_CASTER, "the row still opens")
	check_equal(spells.actor_of_caster(caster), ActorsScript.NONE, "without an actor")
	spells.close_enemy_caster(caster)
	check_equal(_actors.open_count(), ActorsScript.ACTORS, "and closing it closes none of the others")
