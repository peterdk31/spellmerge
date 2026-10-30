extends "res://tests/support/suite.gd"
## Tests for gameplay/horde, the horde director (docs/milestones/horde.md, H3), on a fixture of
## its own (horde_fixture.gd): spawning (outside the view, inside the walls, the cap, the per-step
## limit), kills, gems, levels, offers and picks, the build break, the end, a restart and the
## missing-enemy warning. Time moves by fixed steps through `step()`; nothing waits.
##
## godot --headless --path . --script res://tests/gameplay/horde/test_horde.gd

const Fixture := preload("res://tests/gameplay/horde/horde_fixture.gd")
const HordeScript := preload("res://gameplay/horde/horde.gd")

var _run: Fixture = null


func after_each() -> void:
	if _run != null:
		_run.free_all()
	_run = null


func _make(seats: Array[int] = [0]) -> Fixture:
	_run = Fixture.new(root, seats)
	return _run


# --- Spawning -----------------------------------------------------------------------------------

func test_spawns_land_outside_the_view_and_inside_the_walls() -> void:
	var run: Fixture = _make([0, 1])
	run.director.curve = Fixture.curve([[0.0, 30.0, 200]], {Fixture.ENEMY_A: 1.0})
	run.start()
	run.run(4.0)
	var view: Rect2 = run.director.view_rect()
	var floor_rect := Rect2(Vector2(Fixture.WALL, Fixture.WALL), Fixture.ROOM - Vector2(Fixture.WALL, Fixture.WALL) * 2.0)
	var list: Array[Node2D] = run.enemies()
	check(list.size() >= 50, "enemies appeared (got %d)" % list.size())
	for enemy: Node2D in list:
		check(not view.has_point(enemy.position), "an enemy appeared in view at %s" % enemy.position)
		check(floor_rect.has_point(enemy.position), "an enemy appeared in a wall or outside at %s" % enemy.position)
		for seat: int in [0, 1]:
			check(enemy.position.distance_to(run.wizards[seat].position) >= HordeScript.SPAWN_MIN_DISTANCE, "an enemy appeared beside a wizard")


func test_spawns_follow_the_view_when_the_camera_moves() -> void:
	var run: Fixture = _make()
	run.director.curve = Fixture.curve([[0.0, 30.0, 200]], {Fixture.ENEMY_A: 1.0})
	run.wizards[0].position = Vector2(300.0, 200.0)
	run.camera.position = Vector2(320.0, 180.0)
	run.start()
	run.run(2.0)
	var view: Rect2 = run.director.view_rect()
	for enemy: Node2D in run.enemies():
		check(not view.has_point(enemy.position), "an enemy appeared in the moved view at %s" % enemy.position)
		check(run.director.arena().has_point(enemy.position), "an enemy appeared off the floor at %s" % enemy.position)


func test_the_cap_holds() -> void:
	var run: Fixture = _make()
	run.director.curve = Fixture.curve([[0.0, 500.0, 12]], {Fixture.ENEMY_A: 1.0})
	run.start()
	run.run(3.0)
	check_equal(run.enemies().size(), 12, "no more enemies than the cap")
	check_equal(run.director.alive, 12, "the alive count is the enemies")


func test_a_kill_makes_room_under_the_cap() -> void:
	var run: Fixture = _make()
	run.director.curve = Fixture.curve([[0.0, 500.0, 12]], {Fixture.ENEMY_A: 1.0})
	run.start()
	run.run(1.0)
	run.kill(run.enemies()[0], Vector2(100.0, 100.0))
	check_equal(run.director.alive, 11, "a kill takes one off")
	run.run(0.5)
	check_equal(run.enemies().size(), 12, "a new enemy took its place")


func test_at_most_spawn_per_frame_in_one_step() -> void:
	var run: Fixture = _make()
	run.director.curve = Fixture.curve([[0.0, 1000.0, 500]], {Fixture.ENEMY_A: 1.0})
	run.start()
	run.director.step(0.5)
	check_equal(run.enemies().size(), HordeScript.SPAWN_PER_FRAME, "a long step spawns at most SPAWN_PER_FRAME")
	run.director.step(0.5)
	check_equal(run.enemies().size(), HordeScript.SPAWN_PER_FRAME * 2, "and the next step as many again")


func test_the_rate_follows_the_curve() -> void:
	var run: Fixture = _make()
	run.director.curve = Fixture.curve([[0.0, 2.0, 500]], {Fixture.ENEMY_A: 1.0})
	run.start()
	run.run(5.0)
	var count: int = run.enemies().size()
	check(count >= 9 and count <= 11, "2 a second for 5 seconds is about 10 (got %d)" % count)


func test_the_weights_choose_the_enemy() -> void:
	var run: Fixture = _make()
	run.director.curve = Fixture.curve([[0.0, 30.0, 500]], {Fixture.ENEMY_A: 0.0, Fixture.ENEMY_B: 1.0})
	run.start()
	run.run(1.0)
	check(not run.enemies().is_empty(), "enemies appeared")
	for enemy: Node2D in run.enemies():
		check_equal(enemy.get_meta(&"kind", &""), Fixture.ENEMY_B, "only the weighted enemy appears")


func test_missing_enemy_ids_are_skipped_with_one_warning() -> void:
	var run: Fixture = _make()
	run.director.curve = Fixture.curve([[0.0, 30.0, 500]], {Fixture.ENEMY_A: 1.0, &"no_such_enemy": 5.0, &"nor_this": 1.0})
	run.start()
	run.run(1.0)
	check(run.enemies().size() >= 25, "the known enemy still appears at the full rate (got %d)" % run.enemies().size())
	run.start()
	run.run(0.5)
	check_equal(run.director.missing_warnings, 1, "one warning, however many ids and starts")


# --- The curve ----------------------------------------------------------------------------------

func test_the_curve_interpolates_and_holds_its_ends() -> void:
	var curve: HordeCurve = Fixture.curve([[10.0, 1.0, 30], [20.0, 3.0, 50]], {&"a": 1.0})
	curve.points[1].weights[&"a"] = 3.0
	curve.prepare()
	check_equal(curve.rate_at(0.0), 1.0, "before the first point it holds")
	check_equal(curve.rate_at(15.0), 2.0, "halfway it is halfway")
	check_equal(curve.cap_at(15.0), 40, "the cap too")
	check_equal(curve.weight_at(15.0, curve.ids.find(&"a")), 2.0, "and the weights")
	check_equal(curve.cap_at(999.0), 50, "after the last point it holds")


func test_the_shipped_curve_grows_and_names_real_staff_enemies() -> void:
	var curve: HordeCurve = load("res://gameplay/horde/horde_curve.tres") as HordeCurve
	check(curve != null and curve.points.size() >= 2, "the curve loads with points")
	if curve == null:
		return
	curve.prepare()
	check(curve.cap_at(600.0) > curve.cap_at(0.0), "the horde grows")
	var registry: Node = root.get_node_or_null("Registry")
	var found: int = 0
	for id: StringName in curve.ids:
		if registry != null and registry.call("get_resource", &"enemies", id) != null:
			found += 1
	check(found >= 3, "the curve names enemies the game has (found %d)" % found)


# --- Kills, gems and levels ---------------------------------------------------------------------

func test_a_horde_kill_counts_and_drops_a_gem() -> void:
	var run: Fixture = _make()
	run.start()
	run.run(1.0)
	var before: int = run.director.alive
	run.kill(run.enemies()[0], Vector2(100.0, 100.0))
	check_equal(run.director.kills, 1, "the kill counts")
	check_equal(run.director.alive, before - 1, "one fewer alive")
	check_equal(run.director.gems().count, 1, "a gem lies there")
	check_equal(run.director.gems().gem_position(0), Vector2(100.0, 100.0), "where it died")


func test_a_death_outside_the_horde_does_not_count() -> void:
	var run: Fixture = _make()
	run.start()
	var stranger := Node2D.new()
	run.world.add_child(stranger)
	run.bus.enemy_died.emit(0, stranger, Vector2.ZERO, -1)
	check_equal(run.director.kills, 0, "an enemy not under the Horde node is not the director's")
	check_equal(run.director.gems().count, 0, "and drops no gem")


func test_a_kill_after_the_end_does_not_count() -> void:
	var run: Fixture = _make()
	run.start()
	run.run(1.0)
	run.bus.player_downed.emit(0)
	check(run.director.over, "everyone down: over")
	run.kill(run.enemies()[0], Vector2(100.0, 100.0))
	check_equal(run.director.kills, 0, "the summary's kills stand")
	check_equal(run.director.gems().count, 0, "and no gem drops")


func test_a_wizard_pulls_in_a_near_gem_for_the_party() -> void:
	var run: Fixture = _make([0, 1])
	run.start()
	run.kill_beside(1, 1)
	var far := Vector2(200.0, 200.0)
	run.director.gems().add(far, 1)
	run.run(0.5)
	check_equal(run.director.xp, 1, "the near gem was picked up for the party")
	check_equal(run.director.gems().count, 1, "the far gem still lies there")


func test_a_downed_wizard_pulls_no_gem() -> void:
	var run: Fixture = _make([0, 1])
	run.start()
	run.bus.player_downed.emit(1)
	run.kill_beside(1, 1)
	run.run(0.5)
	check_equal(run.director.xp, 0, "nobody standing near it, so it lies there")


func test_enough_experience_is_a_level() -> void:
	var run: Fixture = _make()
	run.start()
	run.level_up()
	check_equal(run.director.level, 2, "a level-up")
	check_equal(run.director.xp, 0, "the experience starts over")
	check(HordeScript.xp_next(2) > HordeScript.xp_next(1), "the next level needs more")


# --- Offers and picks ---------------------------------------------------------------------------

func test_offers_are_per_seat_and_exclude_owned_cards() -> void:
	var run: Fixture = _make([0, 2])
	run.start()
	run.level_up()
	check_equal(run.offers.size(), 2, "one offer for each joined seat")
	var seats: Array[int] = []
	for offer: Array in run.offers:
		seats.append(offer[0])
		var ids: Array[StringName] = offer[1]
		check_equal(ids.size(), HordeScript.OFFER_SIZE, "three cards")
		for id: StringName in ids:
			check(not HordeScript.START_BAG.has(id), "an owned card was offered: %s" % id)
			check(id != Fixture.NOT_A_CARD, "only spell cards are offered")
			check_equal(ids.count(id), 1, "no card twice in one offer")
	seats.sort()
	var expected: Array[int] = [0, 2]
	check_equal(seats, expected, "seats 0 and 2")


func test_a_pick_sets_the_bag_and_is_announced() -> void:
	var run: Fixture = _make([0, 1])
	run.start()
	run.level_up()
	var card: StringName = run.director.offer_of(1)[2]
	run.bags.clear()
	run.bus.horde_pick_requested.emit(1, 2)
	check_equal(run.bags.size(), 1, "one bag set")
	check_equal(run.bags[0][0], 1, "for seat 1")
	var bag: Array[StringName] = run.bags[0][1]
	check(bag.has(card) and bag.has(&"dash"), "the bag is the start cards and the pick")
	check_equal(run.taken, [[1, card]], "the pick is announced")
	check(run.director.offer_of(1).is_empty(), "seat 1's offer is closed")
	check_equal(run.director.offer_of(0).size(), 3, "seat 0's is still open")


func test_a_picked_card_is_never_offered_again() -> void:
	var run: Fixture = _make()
	run.start()
	for round_number in 3:
		run.level_up()
		var offer: Array[StringName] = run.director.offer_of(0)
		check_equal(offer.size(), HordeScript.OFFER_SIZE, "an offer in round %d" % round_number)
		for id: StringName in offer:
			check(not run.director.bag_of(0).has(id), "an owned card came back: %s" % id)
		run.bus.horde_pick_requested.emit(0, 0)
		check(run.director.bag_of(0).has(offer[0]), "the pick is in the bag")
		run.run(HordeScript.BUILD_BREAK + 0.1)


func test_a_level_up_while_an_offer_is_open_waits_behind_it() -> void:
	var run: Fixture = _make()
	run.start()
	run.level_up()
	run.level_up()
	check_equal(run.offers.size(), 1, "only one offer open at a time")
	check_equal(run.director.queued_of(0), 1, "the second waits")
	run.bus.horde_pick_requested.emit(0, 0)
	check_equal(run.offers.size(), 2, "after the pick the next offer comes")
	check_equal(run.director.queued_of(0), 0, "and nothing waits any more")


func test_a_pick_without_an_offer_or_out_of_range_does_nothing() -> void:
	var run: Fixture = _make()
	run.start()
	run.bags.clear()
	run.bus.horde_pick_requested.emit(0, 0)
	run.level_up()
	run.bus.horde_pick_requested.emit(0, 5)
	check(run.bags.is_empty() and run.taken.is_empty(), "nothing set or announced")
	check_equal(run.director.offer_of(0).size(), 3, "the offer stays open")


func test_with_every_card_owned_there_is_no_offer() -> void:
	var run: Fixture = _make()
	run.registry.folders[&"spells"] = {&"dash": SpellComponent.new(), &"fire": SpellComponent.new()}
	run.start()
	run.level_up()
	check(run.offers.is_empty(), "no card left, no offer")


# --- Bags and seats -----------------------------------------------------------------------------

func test_every_wizard_gets_the_start_bag() -> void:
	var run: Fixture = _make([0, 3])
	run.start()
	check_equal(run.bags.size(), 2, "one bag per wizard")
	for entry: Array in run.bags:
		check([0, 3].has(entry[0]), "for a seat with a wizard")
		check_equal(entry[1], HordeScript.START_BAG, "the start cards")


func test_a_joiner_gets_the_start_bag_and_offers() -> void:
	var run: Fixture = _make([0])
	run.start()
	run.add_wizard(run.world, 1, Vector2(200.0, 200.0))
	run.bags.clear()
	run.bus.player_joined.emit(1)
	check(run.bags.is_empty(), "not yet: Flow may add its wizard after this")
	run.director.step(1.0 / 60.0)
	check_equal(run.bags, [[1, HordeScript.START_BAG]], "the joiner's bag is set on the next step")
	run.level_up()
	check_equal(run.offers.size(), 2, "and it is offered cards at the next level")


func test_a_leaver_drops_its_offer() -> void:
	var run: Fixture = _make([0, 1])
	run.start()
	run.level_up()
	run.bus.player_left.emit(1)
	check(run.taken.has([1, &""]), "the dropped offer is announced")
	check(run.director.offer_of(1).is_empty(), "and gone")


# --- The build break ----------------------------------------------------------------------------

func test_a_level_up_starts_a_build_break_that_freezes_the_horde() -> void:
	var run: Fixture = _make()
	run.start()
	run.run(1.0)
	var clears: int = run.projectiles.clears
	run.level_up()
	var expected: Array[float] = [HordeScript.BUILD_BREAK]
	check_equal(run.breaks, expected, "the break is announced")
	check_equal(run.director.horde_node().process_mode, Node.PROCESS_MODE_DISABLED, "the horde stands frozen")
	check_equal(run.projectiles.clears - clears, 1, "the shots in flight are cleared")


func test_the_build_break_blocks_spawns_and_ends_on_time() -> void:
	var run: Fixture = _make()
	run.start()
	run.level_up()
	var count: int = run.enemies().size()
	var clock: float = run.director.seconds
	run.run(HordeScript.BUILD_BREAK - 0.5)
	check_equal(run.enemies().size(), count, "nothing appears in the break")
	check_equal(run.director.seconds, clock, "the clock stands still")
	check_equal(run.breaks.size(), 1, "still in the break")
	run.run(0.6)
	var expected: Array[float] = [HordeScript.BUILD_BREAK, 0.0]
	check_equal(run.breaks, expected, "it ended on time, whoever is picking")
	check_equal(run.director.horde_node().process_mode, Node.PROCESS_MODE_INHERIT, "the horde moves again")
	run.run(1.0)
	check(run.enemies().size() > count, "and spawns again")


func test_a_level_up_in_a_break_does_not_lengthen_it() -> void:
	var run: Fixture = _make()
	run.start()
	run.level_up()
	run.run(4.0)
	run.level_up()
	check_equal(run.breaks.size(), 1, "no second break")
	run.run(HordeScript.BUILD_BREAK - 4.0 + 0.1)
	check_equal(run.breaks.back(), 0.0, "the break ended on its first time")


# --- Status, the end and restarts ---------------------------------------------------------------

func test_status_is_sent_four_times_a_second() -> void:
	var run: Fixture = _make()
	run.start()
	run.statuses = 0
	run.run(2.0)
	check(run.statuses >= 7 and run.statuses <= 9, "about 8 in two seconds (got %d)" % run.statuses)


func test_horde_over_when_every_wizard_is_down() -> void:
	var run: Fixture = _make([0, 1])
	run.start()
	run.bus.player_downed.emit(0)
	check_equal(run.overs, 0, "one still stands")
	run.bus.player_revived.emit(0, 1)
	run.bus.player_downed.emit(1)
	check_equal(run.overs, 0, "a revive counts")
	run.bus.player_downed.emit(0)
	check_equal(run.overs, 1, "everyone down: over")
	run.bus.player_downed.emit(1)
	check_equal(run.overs, 1, "only once")
	run.bus.player_revived.emit(0, 1)
	check(run.director.over, "a revive after the end changes nothing")
	var count: int = run.enemies().size()
	run.run(2.0)
	check_equal(run.enemies().size(), count, "nothing spawns after the end")


func test_the_last_standing_leaving_ends_it() -> void:
	var run: Fixture = _make([0, 1])
	run.start()
	run.bus.player_downed.emit(0)
	run.bus.player_left.emit(1)
	check_equal(run.overs, 1, "the one left is down")


func test_a_second_start_forgets_the_old_world() -> void:
	var run: Fixture = _make()
	run.start()
	run.run(1.0)
	var old_world: Node2D = run.world
	var old_enemy: Node2D = run.enemies()[0]
	var old_horde: Node2D = run.director.horde_node()
	run.world = run.make_world([0])
	run.start()
	check(run.director.world == run.world, "the director runs the new world")
	check(old_horde.get_parent() == null, "the old horde left the old world")
	check_equal(run.director.kills, 0, "the counts start over")
	check_equal(run.director.alive, 0, "nothing alive yet")
	run.bus.enemy_died.emit(0, old_enemy, Vector2.ZERO, -1)
	check_equal(run.director.kills, 0, "an old enemy's death is not counted")
	run.run(1.0)
	check(not run.enemies().is_empty(), "the new world fills")
	old_world.free()


func test_horde_ended_stops_the_director() -> void:
	var run: Fixture = _make()
	run.start()
	run.level_up()
	run.bus.horde_ended.emit()
	check(not run.director.is_running(), "it stopped")
	check(run.taken.has([0, &""]), "the open offer was dropped")
	check_equal(run.breaks.back(), 0.0, "the break ended")


func test_a_real_enemy_is_an_actor_with_its_data() -> void:
	var run: Fixture = _make()
	var registry: Node = root.get_node_or_null("Registry")
	check(registry != null, "the Registry autoload exists")
	if registry == null:
		return
	run.director.registry = registry
	run.director.curve = Fixture.curve([[0.0, 30.0, 10]], {&"ember_imp": 1.0})
	run.start()
	run.director.step(0.2)
	var list: Array[Node2D] = run.enemies()
	check(not list.is_empty(), "an imp appeared")
	for enemy: Node2D in list:
		var actor := enemy as Actor
		check(actor != null and actor.data != null and actor.data.id == &"ember_imp", "an actor with the imp's data")


func test_the_floor_is_the_walls_box_a_body_in() -> void:
	var run: Fixture = _make()
	run.start()
	var inner := Rect2(Vector2(Fixture.WALL, Fixture.WALL), Fixture.ROOM - Vector2(Fixture.WALL, Fixture.WALL) * 2.0)
	check(inner.encloses(run.director.arena()), "the floor is inside the walls")
	check(run.director.arena().grow(HordeScript.WALL_MARGIN).is_equal_approx(Rect2(Vector2.ZERO, Fixture.ROOM)), "the walls' box, WALL_MARGIN in")


func test_without_walls_the_camera_limits_are_the_room() -> void:
	var run: Fixture = _make()
	run.world.get_child(0).free()
	run.start()
	check(run.director.arena().grow(HordeScript.WALL_MARGIN).is_equal_approx(Rect2(Vector2.ZERO, Fixture.ROOM)), "the camera's limits, WALL_MARGIN in")
