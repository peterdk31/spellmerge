extends "res://tests/support/suite.gd"
## Statuses in gameplay/combat (M2 part 7): the four elements' burn, chill and freeze, shock
## and hex, read from `Spells.hit_profile`, with several players at once. Hits arrive as
## `projectile_hit` on a test bus, with the tag of a real compiled spell built from the real
## element resources; time moves by `Combat.step` with a fixed binary-fraction delta.
## The players are actors 0-3 of the test's actor table, seated 0-3 (actors G3b: hits name actor
## ids). Enemies are plain bodies Combat opens an actor for (the enemies' team); `_foe` makes a
## body of the wizards' team, for the rules that aim by team (shock jumps, static discharges).
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_statuses.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const TeamBody := preload("res://tests/gameplay/combat/team_body.gd")

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
var _actors: ActorSeats.ActorsScript
var _fake: FakeRegistry
## Each status_applied as [player, target, id].
var _applied: Array = []
## Each damage_dealt as [player, target, amount].
var _damage: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	_actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_projectiles.actors = _actors
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
	_combat.register_actor(enemy, health, 10.0)
	return enemy


## A body of the wizards' team (an unseated actor of the test table) at `at`.
func _foe(at: Vector2, health: int = 100) -> Node2D:
	var body := own(TeamBody.new()) as TeamBody
	body.actor_id = _actors.open(ActorSeats.ActorsScript.TEAM_WIZARDS, 0)
	body.position = at
	root.add_child(body)
	_combat.register_actor(body, health, 10.0)
	return body


## The tag of a bolt of `element` (&"" for none) built into slot A of `player`.
func _tag(player: int, element: StringName) -> int:
	var recipe: Dictionary = {"form": &"bolt"}
	if element != &"":
		recipe["element"] = element
	return StaffKit.build(_spells, player, 0, StaffKit.cards(recipe))


## A shot of `tag` from `player` hits `enemy` from the left.
func _hit(player: int, enemy: Node2D, tag: int) -> void:
	# The manager's target grid is rebuilt in its step, which neighbour searches read.
	_projectiles.step(STEP)
	_bus.projectile_hit.emit(player, enemy, enemy.position + Vector2(-8.0, 0.0), tag, -1)


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
	check_equal(_combat.health_of(enemy), 96, "the compiled spell's damage was dealt")
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
	check_equal(_combat.health_of(enemy), 96, "plain damage was dealt")
	check(_applied.is_empty(), "no status_applied")


func test_a_killing_hit_puts_no_status_on() -> void:
	var enemy := _enemy(Vector2.ZERO, 3)
	_hit(0, enemy, _tag(0, &"fire"))
	check_equal(_combat.actor_count(), 0, "the enemy died")
	check(_applied.is_empty(), "no status on a dead enemy")


func test_a_shot_with_no_spell_does_nothing() -> void:
	var enemy := _enemy()
	_hit(0, enemy, 1234)
	check_equal(_combat.health_of(enemy), 100, "no profile, no damage (staffs F9b: Combat's table is gone)")
	check(_applied.is_empty(), "and no status")


func test_burn_deals_its_damage_over_time_to_the_player_who_set_it() -> void:
	var enemy := _enemy()
	_hit(2, enemy, _tag(2, &"fire"))
	var before: int = _combat.health_of(enemy)
	_run(1.0)
	check_equal(before - _combat.health_of(enemy), 2, "2 damage per second")
	_run(5.0)
	check_equal(_combat.health_of(enemy), 100 - 4 - 6, "6 damage over its 3 seconds in all, then it stops")
	check(not _combat.has_status(enemy, &"burn"), "the burn ended")


func test_burn_can_kill_and_credits_the_killer() -> void:
	var enemy := _enemy(Vector2.ZERO, 5)
	var deaths: Array = []
	_bus.enemy_died.connect(func(player: int, _enemy: Node, _at: Vector2, _shot: int) -> void: deaths.append(player))
	_combat.apply_status(3, enemy, &"burn", 10.0, 4.0)
	_run(2.0)
	check_equal(deaths, [3], "player 3 got the kill")
	check_equal(_combat.actor_count(), 0, "the enemy is gone")


func test_burning_again_refreshes_without_adding_up() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"burn", 2.0, 2.0)
	_run(1.0)
	_combat.apply_status(0, enemy, &"burn", 2.0, 1.0)
	check(_combat.status_left(enemy, &"burn") > 1.9, "the time was refreshed")
	var before: int = _combat.health_of(enemy)
	_run(1.0)
	check_equal(before - _combat.health_of(enemy), 2, "the stronger burn kept its rate")


func test_chill_slows_and_runs_out() -> void:
	var enemy := _enemy()
	check_equal(_combat.pace(enemy), 1.0, "a free enemy keeps its pace")
	_hit(0, enemy, _tag(0, &"frost"))
	check(is_equal_approx(_combat.pace(enemy), 0.6), "40% slower")
	_run(3.5)
	check_equal(_combat.pace(enemy), 1.0, "the chill wore off")
	check_equal(_combat.chill_stacks(enemy), 0, "and its stacks")


func test_the_third_chill_freezes_then_thaws() -> void:
	var enemy := _enemy()
	var tag: int = _tag(1, &"frost")
	_hit(1, enemy, tag)
	_hit(1, enemy, tag)
	check_equal(_combat.chill_stacks(enemy), 2, "two stacks")
	check(_combat.pace(enemy) > 0.0, "not frozen yet")
	_hit(1, enemy, tag)
	check_equal(_combat.pace(enemy), 0.0, "frozen at the third")
	check(_combat.has_status(enemy, &"freeze") and not _combat.has_status(enemy, &"chill"), "freeze replaced chill")
	check_equal(_applied[_applied.size() - 1], [1, enemy, &"freeze"], "status_applied says freeze")
	_hit(1, enemy, tag)
	check_equal(_combat.chill_stacks(enemy), 0, "a frozen enemy takes no chill")
	_run(_combat.FREEZE_TIME + STEP)
	check_equal(_combat.pace(enemy), 1.0, "it thawed and walks at full speed")


func test_shock_makes_the_next_hit_jump_to_the_nearest_neighbour() -> void:
	var enemy := _enemy(Vector2(0.0, 0.0))
	var near := _enemy(Vector2(30.0, 0.0))
	var far := _enemy(Vector2(50.0, 40.0))
	_hit(0, enemy, _tag(0, &"storm"))
	check_equal(_combat.health_of(near), 100, "the shocking hit itself does not jump")
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.health_of(near), 100 - 3, "the next hit jumped to the nearest enemy")
	check_equal(_combat.health_of(far), 100, "and only to one")
	check(not _combat.has_status(enemy, &"shock"), "the shock is used up")
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.health_of(near), 100 - 3, "no second jump without a new shock")


func test_a_shock_jumps_to_the_victims_own_team_only() -> void:
	var enemy := _enemy(Vector2(0.0, 0.0))
	var foe := _foe(Vector2(20.0, 0.0))
	var kin := _enemy(Vector2(50.0, 0.0))
	_combat.apply_status(0, enemy, &"shock", 4.0, 75.0)
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.health_of(foe), 100, "the nearer actor of another team is passed over")
	check_equal(_combat.health_of(kin), 100 - 3, "the jump goes to the nearest of the enemy's own team")


func test_a_shock_jump_does_not_reach_past_its_range() -> void:
	var enemy := _enemy(Vector2(0.0, 0.0))
	var distant := _enemy(Vector2(200.0, 0.0))
	_combat.apply_status(0, enemy, &"shock", 4.0, 75.0)
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.health_of(distant), 100, "out of range is left alone")


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
	check_equal(_combat.actor_count(), 1, "the shocked enemy died")
	check_equal(_combat.health_of(near), 96, "its neighbour still took the jump")


func test_hex_adds_damage_taken() -> void:
	var enemy := _enemy()
	_hit(0, enemy, _tag(0, &"void"))
	check_equal(_combat.health_of(enemy), 96, "the hexing hit is not amplified")
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.health_of(enemy), 96 - 5, "4 plus 25% rounds to 5")
	_run(5.0)
	_hit(0, enemy, _tag(0, &""))
	check_equal(_combat.health_of(enemy), 96 - 5 - 4, "after the hex wore off, plain damage")


func test_hex_pulls_toward_the_hit_instead_of_pushing_away() -> void:
	var plain := _enemy(Vector2(0.0, 0.0))
	var hexed := _enemy(Vector2(0.0, 100.0))
	_combat.apply_status(0, hexed, &"hex", 4.0, 25.0)
	var tag: int = _tag(0, &"")
	_hit(0, plain, tag)
	_hit(0, hexed, tag)
	check(_combat.knockback_of(plain).x > 0.0, "a plain enemy is pushed away from a hit on its left")
	check(_combat.knockback_of(hexed).x < 0.0, "a hexed one is pulled toward it")
	check(absf(_combat.knockback_of(hexed).x) < absf(_combat.knockback_of(plain).x), "and more lightly")


func test_statuses_stay_with_their_own_enemy_when_another_dies() -> void:
	var first := _enemy(Vector2(0.0, 0.0), 3)
	var second := _enemy(Vector2(500.0, 0.0))
	_combat.apply_status(0, second, &"hex", 4.0, 25.0)
	_combat.apply_status(0, second, &"burn", 4.0, 2.0)
	_combat.hit(0, first, 3)
	check(_combat.has_status(second, &"hex") and _combat.has_status(second, &"burn"), "the survivor keeps both")
	check(not _combat.has_status(first, &"hex"), "the dead enemy has none")
	var before: int = _combat.health_of(second)
	_run(1.0)
	check_equal(before - _combat.health_of(second), 2, "the burn kept ticking on the right enemy")


func test_burn_ticks_send_no_damage_event_but_the_killing_one_does() -> void:
	var crowd: Array[Node2D] = []
	for i in 12:
		var enemy := _enemy(Vector2(float(i) * 100.0, 0.0), 6)
		_combat.apply_status(i % 4, enemy, &"burn", 10.0, 2.0)
		crowd.append(enemy)
	_damage.clear()
	_run(2.0)
	check_equal(_damage.size(), 0, "burning hurt them all without one impact event")
	check_equal(_combat.health_of(crowd[0]), 2, "but the health went down")
	_run(1.0)
	check_equal(_damage.size(), 12, "each death sent its damage once")
	check_equal(_combat.actor_count(), 0, "and they all died")


func test_a_frozen_enemy_still_hurts_on_contact() -> void:
	_foe(Vector2.ZERO)
	var enemy := own(Node2D.new()) as Node2D
	root.add_child(enemy)
	_combat.register_actor(enemy, 50, 10.0, 1)
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
	_combat.register_actor(enemy, 50, 10.0)
	check(not _combat.has_status(enemy, &"burn") and not _combat.has_status(enemy, &"hex"), "a fresh enemy has no status")


func test_bad_applications_are_refused() -> void:
	var enemy := _enemy()
	var stranger := own(Node2D.new()) as Node2D
	check(not _combat.apply_status(0, stranger, &"burn", 3.0, 2.0), "an unregistered node")
	check(not _combat.apply_status(0, enemy, &"burn", 0.0, 2.0), "no time")
	check(not _combat.apply_status(0, enemy, &"sparkle", 3.0, 2.0), "an unknown status")
	check(_applied.is_empty(), "nothing was announced")
	check_equal(_combat.pace(stranger), 1.0, "an unknown enemy is not slowed")


func test_a_wizard_a_spell_hits_gets_its_status_too() -> void:
	# Staffs (B3): statuses on wizards exist; what reaches a wizard at all is the projectile
	# manager's rule (every shot but the caster's own, which only once out of their hitbox).
	var wizard := _foe(Vector2.ZERO)
	_hit(0, wizard, _tag(0, &"fire"))
	check_equal(_applied, [[0, wizard, &"burn"]], "the fire hit set the wizard burning")
	check(_combat.status_left(wizard, &"burn") > 0.0, "and combat keeps it for the wizard's actor")
	check_equal(_damage.size(), 1, "the damage was sent")


func test_a_charged_enemy_discharges_to_every_actor_of_another_team_nearby() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var left := _foe(Vector2(-50.0, 0.0))
	var right := _foe(Vector2(60.0, 30.0))
	var kin := _enemy(Vector2(0.0, 40.0))
	var far := _foe(Vector2(200.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	_combat.apply_status(0, kin, &"static", 5.0, 60.0)
	_hit(1, struck, _tag(1, &""))
	check_equal(_combat.health_of(struck), 96, "the hit itself did its damage")
	check(is_equal_approx(_combat.health_of(left), 97.6), "an actor of another team near took 60% of the hit (2.4)")
	check(is_equal_approx(_combat.health_of(right), 97.6), "so did the other, whichever side it is on, charged or not")
	check_equal(_combat.health_of(kin), 100, "the struck enemy's own team is left alone, charged or not")
	check_equal(_combat.health_of(far), 100, "and so is anyone out of reach")
	check(not _combat.has_status(struck, &"static"), "the struck enemy spent its charge")
	check(_combat.has_status(kin, &"static"), "its kin keeps its own")


func test_a_discharge_is_announced_at_each_actor_it_zaps_in_the_charged_actors_name() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var left := _foe(Vector2(-50.0, 0.0))
	var right := _foe(Vector2(60.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	var seen: Array = []
	_bus.reaction_triggered.connect(func(player: int, id: StringName, at: Vector2, _shot: int) -> void: seen.append([player, id, at]))
	_hit(3, struck, _tag(3, &""))
	check_equal(seen.size(), 2, "one announcement for each actor zapped, none for the struck one")
	for row: Array in seen:
		check(row[0] == _combat.actor_of(struck) and row[1] == _combat.DISCHARGE, "it names the discharge and the charged actor")
	var places: Array = [seen[0][2], seen[1][2]]
	check(places.has(left.position) and places.has(right.position), "at the zapped actors' places")


func test_a_discharge_sends_an_arc_from_the_struck_actor_to_each_one_zapped() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var left := _foe(Vector2(-50.0, 0.0))
	var right := _foe(Vector2(60.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	var arcs: Array = []
	_bus.discharge_arc.connect(func(player: int, from: Vector2, to: Vector2) -> void: arcs.append([player, from, to]))
	_hit(2, struck, _tag(2, &""))
	check_equal(arcs.size(), 2, "one arc for each actor zapped")
	var ends: Array = []
	for arc: Array in arcs:
		check_equal(arc[0], _combat.actor_of(struck), "it names the charged actor")
		check_equal(arc[1], struck.position, "it starts at the struck enemy")
		ends.append(arc[2])
	check(ends.has(left.position) and ends.has(right.position), "and ends at the zapped ones")


func test_no_arc_when_nobody_of_another_team_is_near() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	_enemy(Vector2(30.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	var arcs: Array = []
	_bus.discharge_arc.connect(func(player: int, from: Vector2, to: Vector2) -> void: arcs.append([player, from, to]))
	_hit(0, struck, _tag(0, &""))
	check(arcs.is_empty(), "a charged enemy among its own kind has nothing to arc to")


func test_a_discharge_is_one_step_not_a_second_jump() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var near := _foe(Vector2(60.0, 0.0))
	var beyond := _enemy(Vector2(150.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	_combat.apply_status(0, near, &"static", 5.0, 60.0)
	_hit(0, struck, _tag(0, &""))
	check(is_equal_approx(_combat.health_of(near), 97.6), "the near one was zapped (60% of 4)")
	check(_combat.has_status(near, &"static"), "and the zap did not set its own charge off")
	check_equal(_combat.health_of(beyond), 100, "one in reach of the near one only is not: the discharge does not go on")


func test_a_discharge_cannot_loop_forever() -> void:
	# A tight ring of charged actors of both teams, every one in reach of every other.
	var ring: Array[Node2D] = []
	for i in 8:
		var at: Vector2 = Vector2.from_angle(i * TAU / 8.0) * 20.0
		ring.append(_enemy(at) if i % 2 == 0 else _foe(at))
		_combat.apply_status(0, ring[i], &"static", 5.0, 100.0)
	# A listener that hits another charged actor from inside the discharge: it takes its own
	# damage, but must not start a discharge of its own.
	var tag: int = _tag(0, &"")
	var reentered: Array[bool] = [false]
	_bus.damage_dealt.connect(func(_player: int, target: Node, _amount: int, _at: Vector2) -> void:
		if not reentered[0] and target == ring[1]:
			reentered[0] = true
			_bus.projectile_hit.emit(0, ring[2], ring[2].position, tag, -1)
	)
	_hit(0, ring[0], tag)
	check(reentered[0], "the listener did hit from inside the discharge")
	check(not _combat._discharging, "the discharge finished")
	check(_damage.size() <= 8 + 1, "one hit, its discharge and the nested hit: at most one event per actor plus one (%d)" % _damage.size())
	var third: int = 0
	for row: Array in _damage:
		if row[1] == ring[3]:
			third += 1
	check_equal(third, 1, "an actor not hit directly was zapped once, so the nested hit started no second discharge")


func test_discharge_damage_is_the_charged_actors_and_the_hit_the_hitters() -> void:
	for player in 4:
		var struck := _enemy(Vector2(0.0, player * 200.0))
		_foe(Vector2(40.0, player * 200.0))
		_combat.apply_status(player, struck, &"static", 5.0, 60.0)
		_damage.clear()
		_hit(player, struck, _tag(player, &""))
		check_equal(_damage.size(), 2, "player %d: the hit and the discharge" % player)
		check_equal(_damage[0][0], player, "player %d: the hit carries the hitter's id" % player)
		check_equal(_damage[1][0], _combat.actor_of(struck), "player %d: the discharge the charged actor's" % player)


func test_any_hit_sets_a_charge_off() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var other := _foe(Vector2(40.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 50.0)
	_hit(EventsScript.NO_PLAYER, struck, _tag(0, &""))
	check_equal(_combat.health_of(other), 98, "a spell hit that names no actor discharges")
	_combat.apply_status(0, struck, &"static", 5.0, 50.0)
	var enemy_caster: int = ActorSeats.enemy(_actors)
	_hit(enemy_caster, struck, _tag(enemy_caster, &""))
	check_equal(_combat.health_of(other), 96, "so does an enemy actor's spell")
	_combat.apply_status(0, struck, &"static", 5.0, 50.0)
	_combat.hit(EventsScript.NO_PLAYER, struck, 4)
	check_equal(_combat.health_of(other), 94, "and a plain hit (a touch, a reaction's damage)")
	_combat.apply_status(0, struck, &"static", 5.0, 50.0)
	_combat.apply_status(0, struck, &"burn", 1.0, 8.0)
	_run(0.5)
	check_equal(_combat.health_of(other), 94, "a burn tick is no hit: it sets nothing off")
	check(_combat.has_status(struck, &"static"), "and leaves the charge")


func test_a_charge_is_spent_even_with_nobody_to_zap() -> void:
	var enemy := _enemy()
	_hit(2, enemy, _tag(2, &"lightning"))
	check(_combat.has_status(enemy, &"static"), "lightning charges")
	check_equal(_applied[_applied.size() - 1], [2, enemy, &"static"], "status_applied names static and the player")
	_hit(2, enemy, _tag(2, &"lightning"))
	check(not _combat.has_status(enemy, &"static"), "the next hit spends it, and the discharge replaces the new charge")
	_hit(2, enemy, _tag(2, &"lightning"))
	check(_combat.has_status(enemy, &"static"), "the one after charges again")


func test_a_lightning_hit_that_discharges_does_not_charge_the_struck_enemy_again() -> void:
	var struck := _enemy(Vector2(0.0, 0.0))
	var other := _foe(Vector2(40.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 60.0)
	_hit(0, struck, _tag(0, &"lightning"))
	check(is_equal_approx(_combat.health_of(other), 97.6), "it discharged (60% of 4)")
	check(not _combat.has_status(struck, &"static"), "the discharge replaced the charge")


func test_a_killing_hit_still_discharges() -> void:
	var struck := _enemy(Vector2(0.0, 0.0), 3)
	var other := _foe(Vector2(40.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 100.0)
	_hit(0, struck, _tag(0, &""))
	check(not _combat.is_registered(struck), "the struck enemy died")
	check_equal(_combat.health_of(other), 96, "and its charge went to the other")


func test_a_charged_wizard_side_body_discharges_into_the_enemies() -> void:
	var struck := _foe(Vector2(0.0, 0.0))
	var enemy := _enemy(Vector2(40.0, 0.0))
	var mate := _foe(Vector2(-40.0, 0.0))
	_combat.apply_status(0, struck, &"static", 5.0, 50.0)
	var enemy_caster: int = ActorSeats.enemy(_actors)
	_hit(enemy_caster, struck, _tag(enemy_caster, &""))
	check_equal(_combat.health_of(enemy), 98, "the enemies near take the charge")
	check_equal(_combat.health_of(mate), 100, "its teammates do not")


func test_static_runs_out_and_registering_again_clears_it() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"static", 1.0, 60.0)
	_run(1.5)
	check(not _combat.has_status(enemy, &"static"), "the charge ran out")
	_combat.apply_status(0, enemy, &"static", 5.0, 60.0)
	_combat.register_actor(enemy, 50, 10.0)
	check(not _combat.has_status(enemy, &"static"), "registering again cleared it")
