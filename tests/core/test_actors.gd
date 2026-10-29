extends "res://tests/support/suite.gd"
## `core/actors` (the `Actors` autoload; actors G2, docs/milestones/M2-actors.md, "Core: the
## actor table and one caster number"): ids handed out lowest free first and freed again, a full
## table, team, ramp and seat, a seat held by one actor at a time, the budget of seated and
## unseated actors, a node lookup that forgets freed nodes, safe answers for bad ids, and the
## spell runtime leaving the table to the bodies (actors G3b: Spells opens no actor; it asks the
## table for a seat's own body), and a seat's home body, kept while another actor holds the seat. Each test makes its own table.
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


func test_a_seat_keeps_its_home_body_while_another_actor_holds_the_seat() -> void:
	var wizard: int = _actors.open(ActorsScript.TEAM_WIZARDS, 1, 1)
	var imp: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_actors.set_home(wizard, 1)
	check_equal(_actors.home_of_seat(1), wizard, "the wizard is seat 1's own body")
	_actors.set_driver(wizard, ActorsScript.TEAM_WIZARDS, ActorsScript.NONE)
	_actors.set_driver(imp, ActorsScript.TEAM_WIZARDS, 1)
	check_equal(_actors.actor_of_seat(1), imp, "seat 1 drives the imp")
	check_equal(_actors.home_of_seat(1), wizard, "and its home body is still the wizard")
	var other: int = _actors.open(ActorsScript.TEAM_WIZARDS, 1)
	_actors.set_home(other, 1)
	check_equal(_actors.home_of_seat(1), other, "a new home body takes the seat's home")
	_actors.set_home(wizard, 1)
	_actors.close(wizard)
	check_equal(_actors.home_of_seat(1), ActorsScript.NONE, "closing the home body frees it")
	_actors.set_home(other, 7)
	check_equal(_actors.home_of_seat(7), ActorsScript.NONE, "a bad seat is no home")
	check_equal(_actors.home_of_seat(-1), ActorsScript.NONE, "nor seat -1")
	_actors.set_home(other, 2)
	_actors.clear()
	check_equal(_actors.home_of_seat(2), ActorsScript.NONE, "clear forgets the homes")


func test_spells_opens_no_actors_and_finds_seats_in_the_table() -> void:
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.actors = _actors
	var imp: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	var wizard: int = _actors.open(ActorsScript.TEAM_WIZARDS, 2, 2)
	check(spells.open_caster(imp) and spells.open_caster(wizard), "the bodies' ids open as casters")
	check_equal(_actors.open_count(), 2, "opening a caster opens no actor")
	_actors.set_home(wizard, 2)
	check_equal(spells.home_of_seat(2), wizard, "Spells finds a seat's own body in the table")
	check_equal(spells.home_of_seat(0), ActorsScript.NONE, "and none for an empty seat")
	spells.close_caster(imp)
	check(_actors.is_open(imp), "closing a caster leaves its actor to its body")
	spells.clear()
	check_equal(_actors.open_count(), 2, "nor does clear close any")


func test_hold_needs_an_open_actor_and_some_seconds() -> void:
	var id: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	check(not _actors.hold(id + 1, 0.5), "a closed actor cannot be held")
	check(not _actors.hold(ActorsScript.NONE, 0.5), "nor no actor")
	check(not _actors.hold(id, 0.0), "no seconds is no hold")
	check_equal(_actors.held_count, 0, "nothing is held")
	check(_actors.hold(id, 0.5), "an open actor is held")
	check_equal(_actors.held_count, 1, "one held")
	check_equal(_actors.held_left(id), 0.5, "for its seconds")


func test_the_longer_hold_wins_and_counts_once() -> void:
	var id: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_actors.hold(id, 0.5)
	_actors.hold(id, 0.25)
	check_equal(_actors.held_left(id), 0.5, "a shorter hold does not cut it")
	_actors.hold(id, 1.0)
	check_equal(_actors.held_left(id), 1.0, "a longer one lengthens it")
	check_equal(_actors.held_count, 1, "still one actor held")


func test_spend_hold_over_a_partial_an_exact_and_a_long_step() -> void:
	var id: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	check_equal(_actors.spend_hold(id, 0.25), 0.25, "a free actor runs the whole step")
	_actors.hold(id, 0.75)
	check_equal(_actors.spend_hold(id, 0.5), 0.0, "a hold longer than the step covers it")
	check_equal(_actors.held_left(id), 0.25, "and keeps what is left")
	check_equal(_actors.spend_hold(id, 0.25), 0.0, "a hold equal to the step covers it")
	check_equal(_actors.held_count, 0, "and ends")
	_actors.hold(id, 0.25)
	check_equal(_actors.spend_hold(id, 0.75), 0.5, "a hold shorter than the step runs the rest")
	check_equal(_actors.held_count, 0, "and ends")
	check_equal(_actors.spend_hold(99999, 0.25), 0.25, "a bad id is never held")


func test_a_hold_ends_when_the_actor_closes_opens_again_or_the_table_clears() -> void:
	var id: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_actors.hold(id, 1.0)
	_actors.close(id)
	check_equal(_actors.held_count, 0, "closing drops the hold")
	check_equal(_actors.held_left(id), 0.0, "and the seconds")
	var again: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	check_equal(again, id, "the id is reused")
	check_equal(_actors.held_left(again), 0.0, "a reused id starts free")
	_actors.hold(again, 1.0)
	var other: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_actors.hold(other, 1.0)
	check_equal(_actors.held_count, 2, "two held")
	_actors.clear()
	check_equal(_actors.held_count, 0, "clear releases every hold")
	check_equal(_actors.held_left(again), 0.0, "and the seconds")
