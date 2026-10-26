extends "res://tests/support/suite.gd"
## Statuses in gameplay/combat (M2 part 7): the four elements' burn, chill and freeze, shock
## and hex, read from `Spells.hit_profile`, with several players at once. Hits arrive as
## `projectile_hit` on a test bus, with the tag of a real compiled spell built from the real
## element resources; time moves by `Combat.step` with a fixed binary-fraction delta.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_statuses.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const STEP: float = 0.0625
const ELEMENTS: Array[StringName] = [&"fire", &"frost", &"storm", &"void", &"lightning"]


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _bus: EventsScript
var _projectiles: ManagerScript
var _combat: CombatScript
var _spells: SpellsScript
var _fake: FakeRegistry
## Each status_applied as [player, target, id].
var _applied: Array = []
## Each damage_dealt as [player, target, amount].
var _damage: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_projectiles, _bus)
	_combat.spells = _spells
	_combat._ready()
	_applied.clear()
	_damage.clear()
	_bus.status_applied.connect(func(player: int, target: Node, id: StringName) -> void: _applied.append([player, target, id]))
	_bus.damage_dealt.connect(func(player: int, target: Node, amount: int, _at: Vector2) -> void: _damage.append([player, target, amount]))
	var bolt := FormBase.new()
	bolt.id = &"bolt"
	bolt.base_damage = 4
	bolt.speed = 200.0
	bolt.lifetime = 1.0
	_fake.items[&"bolt"] = bolt
	for element in ELEMENTS:
		_fake.items[element] = load("res://content/spells/elements/%s/%s.tres" % [element, element])


func _enemy(at: Vector2 = Vector2.ZERO, health: int = 100) -> Node2D:
	var enemy := own(Node2D.new()) as Node2D
	enemy.position = at
	# Only nodes in the tree are on the manager's target grid.
	root.add_child(enemy)
	_combat.register_enemy(enemy, health, 10.0)
	return enemy


## The tag of a bolt of `element` (&"" for none) built into slot A of `player`.
func _tag(player: int, element: StringName) -> int:
	var recipe: Dictionary = {"form": &"bolt"}
	if element != &"":
		recipe["element"] = element
	return _spells.install(player, 0, _spells.compile(recipe))


## A shot of `tag` from `player` hits `enemy` from the left.
func _hit(player: int, enemy: Node2D, tag: int) -> void:
	# The manager's target grid is rebuilt in its step, which neighbour searches read.
	_projectiles.step(STEP)
	_bus.projectile_hit.emit(player, enemy, enemy.position + Vector2(-8.0, 0.0), tag)


func _run(seconds: float) -> void:
	for i in int(seconds / STEP):
		_combat.step(STEP)


func _damage_to(enemy: Node2D) -> int:
	var total: int = 0
	for row: Array in _damage:
		if row[1] == enemy:
			total += row[2] as int
	return total


func test_a_spell_hit_deals_the_profile_damage_and_its_status() -> void:
	var enemy := _enemy()
	_hit(0, enemy, _tag(0, &"fire"))
	check_equal(_combat.get_health(enemy), 96, "the compiled spell's damage was dealt")
	check(_combat.has_status(enemy, &"burn"), "the fire hit set the enemy burning")
	check_equal(_applied, [[0, enemy, &"burn"]], "status_applied named the player, the enemy and burn")


func test_each_element_puts_its_own_status_on() -> void:
	var wanted: Array[StringName] = [&"burn", &"chill", &"shock", &"hex", &"static"]
	for i in ELEMENTS.size():
		var player: int = i % 4
		var enemy := _enemy()
		_hit(player, enemy, _tag(player, ELEMENTS[i]))
		check(_combat.has_status(enemy, wanted[i]), "%s puts on %s" % [ELEMENTS[i], wanted[i]])
		check_equal(_applied[_applied.size() - 1], [player, enemy, wanted[i]], "player %d is named" % player)


func test_a_hit_without_an_element_puts_nothing_on() -> void:
	var enemy := _enemy()
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.get_health(enemy), 96, "plain damage was dealt")
	check(_applied.is_empty(), "no status_applied")


func test_a_killing_hit_puts_no_status_on() -> void:
	var enemy := _enemy(Vector2.ZERO, 3)
	_hit(0, enemy, _tag(0, &"fire"))
	check_equal(_combat.get_enemy_count(), 0, "the enemy died")
	check(_applied.is_empty(), "no status on a dead enemy")


func test_shots_with_no_spell_still_use_the_hit_table() -> void:
	var enemy := _enemy()
	_combat.set_hit_profile(1234, 7, 0.0)
	_hit(0, enemy, 1234)
	check_equal(_combat.get_health(enemy), 93, "the table's damage")
	check(_applied.is_empty(), "and no status")


func test_burn_deals_its_damage_over_time_to_the_player_who_set_it() -> void:
	var enemy := _enemy()
	_hit(2, enemy, _tag(2, &"fire"))
	var before: int = _combat.get_health(enemy)
	_run(1.0)
	check_equal(before - _combat.get_health(enemy), 2, "2 damage per second")
	_run(5.0)
	check_equal(_combat.get_health(enemy), 100 - 4 - 6, "6 damage over its 3 seconds in all, then it stops")
	check(not _combat.has_status(enemy, &"burn"), "the burn ended")


func test_burn_can_kill_and_credits_the_killer() -> void:
	var enemy := _enemy(Vector2.ZERO, 5)
	var deaths: Array = []
	_bus.enemy_died.connect(func(player: int, _enemy: Node, _at: Vector2) -> void: deaths.append(player))
	_combat.apply_status(3, enemy, &"burn", 10.0, 4.0)
	_run(2.0)
	check_equal(deaths, [3], "player 3 got the kill")
	check_equal(_combat.get_enemy_count(), 0, "the enemy is gone")


func test_burning_again_refreshes_without_adding_up() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"burn", 2.0, 2.0)
	_run(1.0)
	_combat.apply_status(0, enemy, &"burn", 2.0, 1.0)
	check(_combat.status_left(enemy, &"burn") > 1.9, "the time was refreshed")
	var before: int = _combat.get_health(enemy)
	_run(1.0)
	check_equal(before - _combat.get_health(enemy), 2, "the stronger burn kept its rate")


func test_chill_slows_and_runs_out() -> void:
	var enemy := _enemy()
	check_equal(_combat.speed_factor(enemy), 1.0, "a free enemy keeps its pace")
	_hit(0, enemy, _tag(0, &"frost"))
	check(is_equal_approx(_combat.speed_factor(enemy), 0.6), "40% slower")
	_run(3.5)
	check_equal(_combat.speed_factor(enemy), 1.0, "the chill wore off")
	check_equal(_combat.chill_stacks(enemy), 0, "and its stacks")


func test_the_third_chill_freezes_then_thaws() -> void:
	var enemy := _enemy()
	var tag: int = _tag(1, &"frost")
	_hit(1, enemy, tag)
	_hit(1, enemy, tag)
	check_equal(_combat.chill_stacks(enemy), 2, "two stacks")
	check(_combat.speed_factor(enemy) > 0.0, "not frozen yet")
	_hit(1, enemy, tag)
	check_equal(_combat.speed_factor(enemy), 0.0, "frozen at the third")
	check(_combat.has_status(enemy, &"freeze") and not _combat.has_status(enemy, &"chill"), "freeze replaced chill")
	check_equal(_applied[_applied.size() - 1], [1, enemy, &"freeze"], "status_applied says freeze")
	_hit(1, enemy, tag)
	check_equal(_combat.chill_stacks(enemy), 0, "a frozen enemy takes no chill")
	_run(_combat.FREEZE_TIME + STEP)
	check_equal(_combat.speed_factor(enemy), 1.0, "it thawed and walks at full speed")


func test_shock_makes_the_next_hit_jump_to_the_nearest_neighbour() -> void:
	var enemy := _enemy(Vector2(0.0, 0.0))
	var near := _enemy(Vector2(30.0, 0.0))
	var far := _enemy(Vector2(50.0, 40.0))
	_hit(0, enemy, _tag(0, &"storm"))
	check_equal(_combat.get_health(near), 100, "the shocking hit itself does not jump")
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.get_health(near), 100 - 3, "the next hit jumped to the nearest enemy")
	check_equal(_combat.get_health(far), 100, "and only to one")
	check(not _combat.has_status(enemy, &"shock"), "the shock is used up")
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.get_health(near), 100 - 3, "no second jump without a new shock")


func test_a_shock_jump_does_not_reach_past_its_range() -> void:
	var enemy := _enemy(Vector2(0.0, 0.0))
	var distant := _enemy(Vector2(200.0, 0.0))
	_combat.apply_status(0, enemy, &"shock", 4.0, 75.0)
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.get_health(distant), 100, "out of range is left alone")


func test_a_shock_jump_puts_no_status_on_the_neighbour() -> void:
	var enemy := _enemy(Vector2(0.0, 0.0))
	var near := _enemy(Vector2(30.0, 0.0))
	_combat.apply_status(0, enemy, &"shock", 4.0, 100.0)
	_hit(0, enemy, _tag(0, &"fire"))
	check(not _combat.has_status(near, &"burn") and not _combat.has_status(near, &"shock"), "the jump carries damage only")


func test_a_shock_jump_still_happens_when_the_hit_kills() -> void:
	var enemy := _enemy(Vector2(0.0, 0.0), 2)
	var near := _enemy(Vector2(30.0, 0.0))
	_combat.apply_status(0, enemy, &"shock", 4.0, 100.0)
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.get_enemy_count(), 1, "the shocked enemy died")
	check_equal(_combat.get_health(near), 96, "its neighbour still took the jump")


func test_hex_adds_damage_taken() -> void:
	var enemy := _enemy()
	_hit(0, enemy, _tag(0, &"void"))
	check_equal(_combat.get_health(enemy), 96, "the hexing hit is not amplified")
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.get_health(enemy), 96 - 5, "4 plus 25% rounds to 5")
	_run(5.0)
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.get_health(enemy), 96 - 5 - 4, "after the hex wore off, plain damage")


func test_hex_pulls_toward_the_hit_instead_of_pushing_away() -> void:
	var plain := _enemy(Vector2(0.0, 0.0))
	var hexed := _enemy(Vector2(0.0, 100.0))
	_combat.apply_status(0, hexed, &"hex", 4.0, 25.0)
	var tag: int = _tag(0, &"")
	_hit(0, plain, tag)
	_hit(0, hexed, tag)
	check(_combat.get_knockback(plain).x > 0.0, "a plain enemy is pushed away from a hit on its left")
	check(_combat.get_knockback(hexed).x < 0.0, "a hexed one is pulled toward it")
	check(absf(_combat.get_knockback(hexed).x) < absf(_combat.get_knockback(plain).x), "and more lightly")


func test_statuses_stay_with_their_own_enemy_when_another_dies() -> void:
	var first := _enemy(Vector2(0.0, 0.0), 3)
	var second := _enemy(Vector2(500.0, 0.0))
	_combat.apply_status(0, second, &"hex", 4.0, 25.0)
	_combat.apply_status(0, second, &"burn", 4.0, 2.0)
	_combat.hit(0, first, 3)
	check(_combat.has_status(second, &"hex") and _combat.has_status(second, &"burn"), "the survivor keeps both")
	check(not _combat.has_status(first, &"hex"), "the dead enemy has none")
	var before: int = _combat.get_health(second)
	_run(1.0)
	check_equal(before - _combat.get_health(second), 2, "the burn kept ticking on the right enemy")


func test_burn_ticks_send_no_damage_event_but_the_killing_one_does() -> void:
	var crowd: Array[Node2D] = []
	for i in 12:
		var enemy := _enemy(Vector2(float(i) * 100.0, 0.0), 6)
		_combat.apply_status(i % 4, enemy, &"burn", 10.0, 2.0)
		crowd.append(enemy)
	_damage.clear()
	_run(2.0)
	check_equal(_damage.size(), 0, "burning hurt them all without one impact event")
	check_equal(_combat.get_health(crowd[0]), 2, "but the health went down")
	_run(1.0)
	check_equal(_damage.size(), 12, "each death sent its damage once")
	check_equal(_combat.get_enemy_count(), 0, "and they all died")


func test_a_frozen_enemy_still_hurts_on_contact() -> void:
	var wizard := own(Node2D.new()) as Node2D
	root.add_child(wizard)
	_combat.register_player(0, wizard, 8.0)
	var enemy := own(Node2D.new()) as Node2D
	root.add_child(enemy)
	_combat.register_enemy(enemy, 50, 10.0, 1)
	for i in 3:
		_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	check(_combat.has_status(enemy, &"freeze"), "frozen")
	_damage.clear()
	_combat.step(STEP)
	check_equal(_damage.size(), 1, "standing still does not make its touch harmless")


func test_registering_again_clears_statuses() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"burn", 4.0, 2.0)
	_combat.apply_status(0, enemy, &"hex", 4.0, 25.0)
	_combat.register_enemy(enemy, 50, 10.0)
	check(not _combat.has_status(enemy, &"burn") and not _combat.has_status(enemy, &"hex"), "a fresh enemy has no status")


func test_bad_applications_are_refused() -> void:
	var enemy := _enemy()
	var stranger := own(Node2D.new()) as Node2D
	check(not _combat.apply_status(0, stranger, &"burn", 3.0, 2.0), "an unregistered node")
	check(not _combat.apply_status(0, enemy, &"burn", 0.0, 2.0), "no time")
	check(not _combat.apply_status(0, enemy, &"sparkle", 3.0, 2.0), "an unknown status")
	check(_applied.is_empty(), "nothing was announced")
	check_equal(_combat.speed_factor(stranger), 1.0, "an unknown enemy is not slowed")


func test_wizards_get_no_status_from_player_spells() -> void:
	var wizard := own(Node2D.new()) as Node2D
	_combat.register_player(1, wizard, 8.0)
	_hit(0, wizard, _tag(0, &"fire"))
	check(_applied.is_empty(), "friendly fire is damage only")
	check_equal(_damage.size(), 1, "the damage was sent")


func test_a_charged_enemy_hit_again_discharges_to_every_other_charged_enemy_nearby() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var left := _enemy(Vector2(-50.0, 0.0))
	var right := _enemy(Vector2(60.0, 30.0))
	var uncharged := _enemy(Vector2(0.0, 40.0))
	for charged: Node2D in [struck, left, right]:
		_combat.apply_status(0, charged, &"static", 5.0, 60.0)
	_hit(1, struck, _tag(1, &""))
	check_equal(_combat.get_health(struck), 96, "the hit itself did its damage")
	check_equal(_combat.get_health(left), 98, "one charged neighbour took 60% of the hit")
	check_equal(_combat.get_health(right), 98, "so did the other, whichever side it is on")
	check_equal(_combat.get_health(uncharged), 100, "an enemy that is not charged is left alone")
	check(not _combat.has_status(struck, &"static"), "the struck enemy spent its charge")
	check(_combat.has_status(left, &"static") and _combat.has_status(right, &"static"), "the ones it zapped stay charged")


func test_a_discharge_is_announced_at_each_enemy_it_zaps() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var left := _enemy(Vector2(-50.0, 0.0))
	var right := _enemy(Vector2(60.0, 0.0))
	for charged: Node2D in [struck, left, right]:
		_combat.apply_status(0, charged, &"static", 5.0, 60.0)
	var seen: Array = []
	_bus.reaction_triggered.connect(func(player: int, id: StringName, at: Vector2) -> void: seen.append([player, id, at]))
	_hit(3, struck, _tag(3, &""))
	check_equal(seen.size(), 2, "one announcement for each enemy zapped, none for the struck one")
	for row: Array in seen:
		check(row[0] == 3 and row[1] == _combat.DISCHARGE, "it names the discharge and the player who hit")
	var places: Array = [seen[0][2], seen[1][2]]
	check(places.has(left.position) and places.has(right.position), "at the zapped enemies' places")


func test_a_discharge_sends_an_arc_from_the_struck_enemy_to_each_one_zapped() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var left := _enemy(Vector2(-50.0, 0.0))
	var right := _enemy(Vector2(60.0, 0.0))
	for charged: Node2D in [struck, left, right]:
		_combat.apply_status(0, charged, &"static", 5.0, 60.0)
	var arcs: Array = []
	_bus.discharge_arc.connect(func(player: int, from: Vector2, to: Vector2) -> void: arcs.append([player, from, to]))
	_hit(2, struck, _tag(2, &""))
	check_equal(arcs.size(), 2, "one arc for each enemy zapped")
	var ends: Array = []
	for arc: Array in arcs:
		check_equal(arc[0], 2, "it names the player who hit")
		check_equal(arc[1], struck.position, "it starts at the struck enemy")
		ends.append(arc[2])
	check(ends.has(left.position) and ends.has(right.position), "and ends at the zapped ones")


func test_no_arc_when_nobody_is_zapped() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	var arcs: Array = []
	_bus.discharge_arc.connect(func(player: int, from: Vector2, to: Vector2) -> void: arcs.append([player, from, to]))
	_hit(0, struck, _tag(0, &""))
	check(arcs.is_empty(), "a charged enemy alone has nothing to arc to")


func test_a_discharge_is_one_step_not_a_second_jump() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var near := _enemy(Vector2(60.0, 0.0))
	var beyond := _enemy(Vector2(150.0, 0.0))
	for charged: Node2D in [struck, near, beyond]:
		_combat.apply_status(0, charged, &"static", 5.0, 60.0)
	_hit(0, struck, _tag(0, &""))
	check_equal(_combat.get_health(near), 98, "the near one was zapped")
	check_equal(_combat.get_health(beyond), 100, "one in reach of the near one only is not: the discharge does not go on")


func test_a_discharge_cannot_loop_forever() -> void:
	# A tight ring of charged enemies, every one in reach of every other.
	var ring: Array[Node2D] = []
	for i in 8:
		ring.append(_enemy(Vector2.from_angle(i * TAU / 8.0) * 20.0))
		_combat.apply_status(0, ring[i], &"static", 5.0, 100.0)
	# A listener that hits another charged enemy from inside the discharge: it takes its own
	# damage, but must not start a discharge of its own.
	var tag: int = _tag(0, &"")
	var reentered: Array[bool] = [false]
	_bus.damage_dealt.connect(func(_player: int, target: Node, _amount: int, _at: Vector2) -> void:
		if not reentered[0] and target == ring[1]:
			reentered[0] = true
			_bus.projectile_hit.emit(0, ring[2], ring[2].position, tag)
	)
	_hit(0, ring[0], tag)
	check(reentered[0], "the listener did hit from inside the discharge")
	check(not _combat._discharging, "the discharge finished")
	check(_damage.size() <= 8 + 1, "one hit, its discharge and the nested hit: at most one event per enemy plus one (%d)" % _damage.size())
	var third: int = 0
	for row: Array in _damage:
		if row[1] == ring[3]:
			third += 1
	check_equal(third, 1, "an enemy not hit directly was zapped once, so the nested hit started no second discharge")


func test_discharge_damage_always_names_the_player_who_hit() -> void:
	for player in 4:
		var struck := _enemy(Vector2(0.0, player * 200.0))
		var other := _enemy(Vector2(40.0, player * 200.0))
		_combat.apply_status(player, struck, &"static", 5.0, 60.0)
		_combat.apply_status(player, other, &"static", 5.0, 60.0)
		_damage.clear()
		_hit(player, struck, _tag(player, &""))
		check_equal(_damage.size(), 2, "player %d: the hit and the discharge" % player)
		for row: Array in _damage:
			check_equal(row[0], player, "player %d: every damage_dealt carries the hitter's index" % player)


func test_a_hit_with_no_player_does_not_discharge() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var other := _enemy(Vector2(40.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	_combat.apply_status(0, other, &"static", 5.0, 60.0)
	_hit(EventsScript.NO_PLAYER, struck, _tag(0, &""))
	check_equal(_combat.get_health(other), 100, "a hit that names no player discharges nothing")
	check(_combat.has_status(struck, &"static"), "and keeps its charge")
	_combat.set_hit_profile(4321, 5, 0.0)
	_hit(0, struck, 4321)
	check_equal(_combat.get_health(other), 100, "a shot that is not a spell does not discharge either")


func test_a_lone_charged_enemy_keeps_its_charge_and_lightning_charges_again() -> void:
	var enemy := _enemy()
	_hit(2, enemy, _tag(2, &"lightning"))
	check(_combat.has_status(enemy, &"static"), "lightning charges")
	check_equal(_applied[_applied.size() - 1], [2, enemy, &"static"], "status_applied names static and the player")
	_run(2.0)
	var left: float = _combat.status_left(enemy, &"static")
	_hit(2, enemy, _tag(2, &"lightning"))
	check(_combat.status_left(enemy, &"static") > left, "with nobody to zap the charge is kept and refreshed")


func test_a_lightning_hit_that_discharges_does_not_charge_the_struck_enemy_again() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var other := _enemy(Vector2(40.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	_combat.apply_status(0, other, &"static", 5.0, 60.0)
	_hit(0, struck, _tag(0, &"lightning"))
	check_equal(_combat.get_health(other), 98, "it discharged")
	check(not _combat.has_status(struck, &"static"), "the discharge replaced the charge")


func test_a_killing_hit_still_discharges() -> void:
	var struck := _enemy(Vector2(0.0, 0.0), 3)
	var other := _enemy(Vector2(40.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 100.0)
	_combat.apply_status(0, other, &"static", 5.0, 100.0)
	_hit(0, struck, _tag(0, &""))
	check_equal(_combat.get_enemy_count(), 1, "the struck enemy died")
	check_equal(_combat.get_health(other), 96, "and its charge went to the other")


func test_static_runs_out_and_registering_again_clears_it() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"static", 1.0, 60.0)
	_run(1.5)
	check(not _combat.has_status(enemy, &"static"), "the charge ran out")
	_combat.apply_status(0, enemy, &"static", 5.0, 60.0)
	_combat.register_enemy(enemy, 50, 10.0)
	check(not _combat.has_status(enemy, &"static"), "registering again cleared it")
