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
const ELEMENTS: Array[StringName] = [&"fire", &"frost", &"storm", &"void"]


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
	var wanted: Array[StringName] = [&"burn", &"chill", &"shock", &"hex"]
	for i in ELEMENTS.size():
		var enemy := _enemy()
		_hit(i, enemy, _tag(i, ELEMENTS[i]))
		check(_combat.has_status(enemy, wanted[i]), "%s puts on %s" % [ELEMENTS[i], wanted[i]])
		check_equal(_applied[_applied.size() - 1], [i, enemy, wanted[i]], "player %d is named" % i)


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
	_damage.clear()
	_run(1.0)
	check_equal(_damage_to(enemy), 2, "2 damage per second")
	check_equal(_damage[0][0], 2, "credited to player 2")
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
	_damage.clear()
	_run(1.0)
	check_equal(_damage_to(enemy), 2, "the stronger burn kept its rate")


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
	_damage.clear()
	_run(1.0)
	check_equal(_damage_to(second), 2, "the burn kept ticking on the right enemy")


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
