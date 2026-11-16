extends "res://tests/support/suite.gd"
## Tests for the `player_stats_changed` event of gameplay/player (what the HUD shows), one
## behaviour per test: sent when a wizard appears, on a health change (hit, down, revive), when
## mana is spent and when regenerating mana crosses a whole number, and not when nothing changed.
## Four wizards at once keep their own numbers. Every staff reports its own pool by
## `staff_mana_changed`. The seat (the wizard's PlayerController) sends it for the wizard it drives
## (actors G7). Each test gets a fresh world (wizard_fixture.gd, the stand-in spell runtime) and
## the events it heard.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/gameplay/player/test_player_stats.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

var _world: Fixture
var _players: Array[Actor] = []
## Every event as [player, health, max_health, mana, max_mana].
var _stats: Array[Array] = []
## Every staff_mana_changed as [player, staff, mana, max_mana].
var _staff_mana: Array[Array] = []


func before_each() -> void:
	_world = Fixture.new(root, true)
	_players.clear()
	_stats.clear()
	_staff_mana.clear()
	_world.bus.player_stats_changed.connect(func(p: int, h: float, mh: float, m: float, mm: float) -> void:
		_stats.append([p, h, mh, m, mm]))
	_world.bus.staff_mana_changed.connect(func(p: int, at: int, m: float, mm: float) -> void:
		_staff_mana.append([p, at, m, mm]))


func after_each() -> void:
	_world.free_all()


## `count` wizards, seats 0 up, side by side.
func _wizards(count: int) -> void:
	for index in count:
		_players.append(_world.wizard(index, Vector2(40.0 * index, 0.0)))


## One wizard whose staff 1 (`staff`) holds a card costing 25 mana, the events heard so far cleared.
func _wizard_with_a_costly_card(staff: int = 0) -> Actor:
	_wizards(1)
	_world.fake.cost = 25.0
	_players[0].caster.set_staff(staff, [&"bolt"] as Array[StringName])
	_stats.clear()
	_staff_mana.clear()
	return _players[0]


func test_one_event_is_sent_when_the_wizard_appears() -> void:
	_wizards(1)
	check_equal(_stats.size(), 1, "one event when the wizard appears")


func test_the_first_event_carries_full_health_and_mana() -> void:
	_wizards(1)
	var wizard: Actor = _players[0]
	check(not _stats.is_empty() and _stats[0] == [0, wizard.health.max_health, wizard.health.max_health, wizard.caster.max_mana_of(0), wizard.caster.max_mana_of(0)],
		"the first event carries full health and mana, got %s" % [_stats])


func test_a_hit_sends_the_health_left() -> void:
	_wizards(1)
	_stats.clear()
	_world.combat.hit(-1, _players[0], 30)
	check(_stats.size() == 1 and _stats[0][1] == 70, "a hit of 30 sends health 70, got %s" % [_stats])


func test_being_downed_sends_health_zero() -> void:
	_wizards(1)
	_world.combat.hit(-1, _players[0], 100)
	check(_players[0].is_down(), "the wizard is down")
	check(not _stats.is_empty() and _stats.back()[1] == 0, "being downed sends health 0, got %s" % [_stats])


func test_a_revive_sends_the_revive_health() -> void:
	_wizards(1)
	_world.combat.hit(-1, _players[0], 100)
	_stats.clear()
	Fixture.downed(_players[0]).revive(1)
	check(_stats.size() == 1 and _stats[0][1] == Downed.REVIVE_HEALTH, "a revive sends the revive health, got %s" % [_stats])


func test_a_step_at_full_mana_sends_nothing() -> void:
	_wizards(1)
	_stats.clear()
	_players[0].step(0.01)
	check(_stats.is_empty(), "no event when nothing changed, got %d" % _stats.size())


func test_a_hit_of_zero_sends_nothing() -> void:
	_wizards(1)
	_stats.clear()
	_players[0].health.take(0)
	check(_stats.is_empty(), "a hit of 0 sends nothing, got %s" % [_stats])


func test_spending_mana_sends_the_mana_left() -> void:
	var wizard: Actor = _wizard_with_a_costly_card()
	check(wizard.caster.cast(0), "the cast fires")
	check(_stats.size() == 1 and _stats[0][3] == 75.0, "spending 25 mana sends mana 75, got %s" % [_stats])


## A wizard who spent 25 mana, then regenerated for two steps: 0.0625 s * 10 mana/s = 0.625 a
## step, so 1.25 mana, one whole number crossed. The events heard so far are cleared.
func _wizard_who_regenerated_two_steps() -> Actor:
	var wizard: Actor = _wizard_with_a_costly_card()
	wizard.caster.cast(0)
	_stats.clear()
	_world.step_one(wizard)
	_world.step_one(wizard)
	return wizard


func test_regenerated_mana_is_not_announced_in_the_step_it_crosses_a_whole_number() -> void:
	# The seat looks at the mana when it thinks, before the Caster regenerates, so the crossing
	# is announced the step after it (actors G7: one step later than the old wizard).
	_wizard_who_regenerated_two_steps()
	check(_stats.is_empty(), "the crossing is not announced in the step it happens, got %s" % [_stats])


func test_regenerated_mana_is_announced_once_per_whole_number_crossed() -> void:
	var wizard: Actor = _wizard_who_regenerated_two_steps()
	_world.step_one(wizard)
	check_equal(_stats.size(), 1, "regenerating 1.25 mana crosses one whole number once")
	check(_stats.size() == 1 and _stats[0][3] == 76.0, "regenerated mana is whole numbers, got %s" % [_stats])


func test_a_hit_on_one_of_four_wizards_is_reported_by_that_wizard_alone() -> void:
	_wizards(4)
	_stats.clear()
	_world.combat.hit(-1, _players[2], 40)
	check(_stats.size() == 1 and _stats[0][0] == 2 and _stats[0][1] == 60, "only player 2 reports its hit, got %s" % [_stats])
	_stats.clear()
	_world.combat.hit(-1, _players[3], 10)
	check(_stats.size() == 1 and _stats[0][0] == 3 and _stats[0][1] == 90, "only player 3 reports its hit, got %s" % [_stats])


func test_a_hit_on_one_of_four_wizards_leaves_the_others_untouched() -> void:
	_wizards(4)
	_world.combat.hit(-1, _players[2], 40)
	_world.combat.hit(-1, _players[3], 10)
	check(_players[0].health.health == _players[0].health.max_health and _players[1].health.health == _players[1].health.max_health,
		"players 0 and 1 are untouched")


## Every staff has its own pool (owner, 2026-11-01): each reports its own mana by
## `staff_mana_changed`, and `player_stats_changed` carries the pool of the staff on show.
func test_every_staff_reports_its_pool_when_the_wizard_appears() -> void:
	_wizards(1)
	var wizard: Actor = _players[0]
	var seen: Array[int] = []
	for row: Array in _staff_mana:
		seen.append(int(row[1]))
	check(seen.size() == wizard.caster.staff_count and seen.has(0) and seen.has(wizard.caster.staff_count - 1), "every staff reports its pool when the wizard appears, got %s" % [_staff_mana])


func test_a_cast_reports_only_the_pool_of_the_staff_it_spent() -> void:
	var wizard: Actor = _wizard_with_a_costly_card(1)
	check(wizard.caster.cast(1), "staff 2 casts")
	PlayerController.of(wizard).announce_stats()
	check(_staff_mana.size() == 1 and _staff_mana[0][1] == 1 and _staff_mana[0][2] == wizard.caster.max_mana_of(1) - 25.0,
		"only staff 2's pool changed, got %s" % [_staff_mana])
	check(wizard.caster.mana_of(0) == wizard.caster.max_mana_of(0), "staff 1's pool is untouched")


func test_the_stats_event_carries_the_mana_of_the_staff_on_show() -> void:
	var wizard: Actor = _wizard_with_a_costly_card(1)
	wizard.caster.cast(1)
	PlayerController.of(wizard).announce_stats()
	wizard.caster.current = 1
	PlayerController.of(wizard).announce_stats()
	check(not _stats.is_empty() and _stats.back()[3] == wizard.caster.max_mana_of(1) - 25.0, "the panel's mana is the staff on show, got %s" % [_stats])
