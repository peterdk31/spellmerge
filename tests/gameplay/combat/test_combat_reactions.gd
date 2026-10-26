extends "res://tests/support/suite.gd"
## Element reactions in gameplay/combat (M2 part 8): the six reactions of
## `content/spells/reactions.tres` and the four effect kinds, both ways round for each pair,
## with several players at once. Hits arrive as `projectile_hit` with the tag of a real
## compiled spell built from the real element resources; time moves by `Combat.step`.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_reactions.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const STEP: float = 0.0625
const ELEMENTS: Array[StringName] = [&"fire", &"frost", &"storm", &"void"]
## The bolt's damage in these tests.
const BOLT: int = 4


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
## Each reaction_triggered as [player, id, position].
var _reacted: Array = []
## Each status_applied as [player, target, id].
var _applied: Array = []


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
	_reacted.clear()
	_applied.clear()
	_bus.reaction_triggered.connect(func(player: int, id: StringName, at: Vector2) -> void: _reacted.append([player, id, at]))
	_bus.status_applied.connect(func(player: int, target: Node, id: StringName) -> void: _applied.append([player, target, id]))
	var bolt := FormBase.new()
	bolt.id = &"bolt"
	bolt.base_damage = BOLT
	bolt.speed = 200.0
	bolt.lifetime = 1.0
	_fake.items[&"bolt"] = bolt
	for element in ELEMENTS + [&"lightning"]:
		_fake.items[element] = load("res://content/spells/elements/%s/%s.tres" % [element, element])


func _enemy(at: Vector2 = Vector2.ZERO, health: int = 100) -> Node2D:
	var enemy := own(Node2D.new()) as Node2D
	enemy.position = at
	root.add_child(enemy)
	_combat.register_enemy(enemy, health, 10.0)
	return enemy


func _tag(player: int, element: StringName) -> int:
	return _spells.install(player, 0, _spells.compile({"form": &"bolt", "element": element}))


## A shot of `element` from `player` hits `enemy` from the left.
func _hit(player: int, enemy: Node2D, element: StringName) -> void:
	var tag: int = _tag(player, element)
	_projectiles.step(STEP)
	_bus.projectile_hit.emit(player, enemy, enemy.position + Vector2(-8.0, 0.0), tag)


func _run(seconds: float) -> void:
	for i in int(seconds / STEP):
		_combat.step(STEP)


func _ids() -> Array:
	var ids: Array = []
	for row: Array in _reacted:
		ids.append(row[1])
	return ids


# --- the table ---


func test_every_pair_of_the_four_first_elements_reacts_both_ways_under_one_of_six_names() -> void:
	var table: ReactionTable = load("res://content/spells/reactions.tres") as ReactionTable
	var names: Dictionary = {}
	for a in ELEMENTS:
		for b in ELEMENTS:
			if a == b:
				continue
			var found: bool = false
			for row in table.rows:
				var status_element: StringName = {&"burn": &"fire", &"chill": &"frost", &"shock": &"storm", &"hex": &"void"}.get(row.status_id, &"")
				if status_element == a and row.element_id == b:
					found = true
					names[row.reaction_id] = true
			check(found, "%s on %s reacts" % [b, a])
	check_equal(names.size(), 6, "six reactions in all")


# --- Shatter: frost and storm, consume ---


func test_shatter_eats_chill_for_bonus_damage() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_hit(0, enemy, &"storm")
	check_equal(_ids(), [&"shatter"], "shatter fired")
	check_equal(_combat.get_health(enemy), 100 - BOLT - 6, "the hit plus the bonus")
	check(not _combat.has_status(enemy, &"chill"), "the chill is gone")
	check(not _combat.has_status(enemy, &"shock"), "storm put no shock on: the reaction ran instead")


func test_shatter_doubles_on_a_frozen_enemy_and_ends_the_freeze() -> void:
	var enemy := _enemy()
	for i in 3:
		_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	check(_combat.has_status(enemy, &"freeze"), "frozen to start with")
	_hit(0, enemy, &"storm")
	check_equal(_combat.get_health(enemy), 100 - BOLT - 12, "twice the bonus")
	check(not _combat.has_status(enemy, &"freeze"), "the freeze is broken")
	check_equal(_combat.speed_factor(enemy), 1.0, "the enemy moves again")


func test_shatter_works_the_other_way_round_on_shock() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"shock", 4.0, 0.0001)
	_hit(0, enemy, &"frost")
	check_equal(_ids(), [&"shatter"], "frost on a shocked enemy shatters")
	check_equal(_combat.get_health(enemy), 100 - BOLT - 6, "the hit plus the bonus")
	check(not _combat.has_status(enemy, &"shock"), "the shock is gone")
	check(not _combat.has_status(enemy, &"chill"), "and frost put no chill on")


# --- Thaw: fire and frost, consume then a burst ---


func test_thaw_bursts_around_a_burning_enemy_hit_by_frost() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(30.0, 0.0))
	var far := _enemy(Vector2(120.0, 0.0))
	_combat.apply_status(0, enemy, &"burn", 3.0, 2.0)
	_hit(0, enemy, &"frost")
	check_equal(_ids(), [&"thaw"], "thaw fired")
	check_equal(_combat.get_health(enemy), 100 - BOLT - 3, "the struck enemy is in the burst")
	check_equal(_combat.get_health(near), 97, "the neighbour takes the burst")
	check_equal(_combat.get_health(far), 100, "far away is left alone")
	check(not _combat.has_status(enemy, &"burn"), "the burn is used up")
	check(not _combat.has_status(enemy, &"chill"), "no chill: the reaction ran instead")


func test_thaw_on_a_chilled_enemy_hit_by_fire() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(0.0, 30.0))
	_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_hit(0, enemy, &"fire")
	check_equal(_ids(), [&"thaw"], "fire on chill thaws")
	check_equal(_combat.get_health(near), 97, "the steam reaches the neighbour")
	check(not _combat.has_status(enemy, &"chill"), "the chill is gone")
	check(not _combat.has_status(enemy, &"burn"), "and no burn went on")


func test_thaw_melts_a_freeze() -> void:
	var enemy := _enemy()
	for i in 3:
		_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_hit(0, enemy, &"fire")
	check_equal(_ids(), [&"thaw"], "fire on a frozen enemy thaws")
	check(not _combat.has_status(enemy, &"freeze"), "no longer frozen")


# --- Flare: fire and storm, a wide weak burst ---


func test_flare_is_wider_and_weaker_than_thaw() -> void:
	var enemy := _enemy()
	var wide := _enemy(Vector2(50.0, 0.0))
	var outside := _enemy(Vector2(100.0, 0.0))
	_combat.apply_status(0, enemy, &"burn", 3.0, 2.0)
	_hit(0, enemy, &"storm")
	check_equal(_ids(), [&"flare"], "flare fired")
	check_equal(_combat.get_health(wide), 98, "a target 50 px away is hit for 2")
	check_equal(_combat.get_health(outside), 100, "100 px is out of reach")
	check(_combat.has_status(enemy, &"burn"), "flare leaves the burn alone")


func test_flare_on_a_shocked_enemy_hit_by_fire() -> void:
	var enemy := _enemy()
	var wide := _enemy(Vector2(0.0, 50.0))
	_combat.apply_status(0, enemy, &"shock", 4.0, 0.0001)
	_hit(0, enemy, &"fire")
	check(_ids().has(&"flare"), "fire on shock flares")
	check_equal(_combat.get_health(wide), 98 - 1, "the burst plus the shock's one-point jump (the jump is at least 1)")


# --- Kindle: fire and void, spread ---


func test_kindle_spreads_burn_to_neighbours_only() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(40.0, 0.0))
	var far := _enemy(Vector2(150.0, 0.0))
	_combat.apply_status(0, enemy, &"burn", 3.0, 2.0)
	_hit(1, enemy, &"void")
	check_equal(_ids(), [&"kindle"], "kindle fired")
	check(_combat.has_status(near, &"burn"), "the neighbour burns")
	check(not _combat.has_status(far, &"burn"), "the far enemy does not")
	check(_combat.has_status(enemy, &"burn"), "the source keeps burning")
	check(not _combat.has_status(enemy, &"hex"), "void's own hex did not go on")
	check(_applied.has([1, near, &"burn"]), "status_applied named the player and the neighbour")


func test_kindle_the_other_way_spreads_hex() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(40.0, 0.0))
	_combat.apply_status(0, enemy, &"hex", 4.0, 25.0)
	_hit(0, enemy, &"fire")
	check_equal(_ids(), [&"kindle"], "fire on hex kindles")
	check(_combat.has_status(near, &"hex"), "the neighbour is hexed")
	check(not _combat.has_status(enemy, &"burn"), "and fire's burn did not go on")


func test_kindled_burn_is_credited_to_the_player_who_spread_it() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(40.0, 0.0), 2)
	_combat.apply_status(0, enemy, &"burn", 3.0, 2.0)
	var killers: Array[int] = []
	_bus.enemy_died.connect(func(player: int, who: Node, _at: Vector2) -> void:
		if who == near:
			killers.append(player))
	_hit(2, enemy, &"void")
	_run(2.0)
	check_equal(killers, [2], "player 2 gets the kill")


# --- Stillness: frost and void, extend ---


func test_stillness_freezes_a_chilled_enemy_for_two_seconds() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_hit(0, enemy, &"void")
	check_equal(_ids(), [&"stillness"], "stillness fired")
	check(_combat.has_status(enemy, &"freeze"), "frozen")
	check_equal(_combat.status_left(enemy, &"freeze"), 2.0, "for 2 seconds")
	check(not _combat.has_status(enemy, &"hex"), "void's hex did not go on")
	check_equal(_applied[_applied.size() - 1], [0, enemy, &"freeze"], "status_applied said freeze")


func test_stillness_makes_a_freeze_last_longer() -> void:
	var enemy := _enemy()
	for i in 3:
		_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_hit(0, enemy, &"void")
	check_equal(_combat.status_left(enemy, &"freeze"), 3.0, "1 s of freeze plus 2 s")


func test_stillness_the_other_way_lengthens_and_strengthens_hex() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"hex", 4.0, 25.0)
	_hit(0, enemy, &"frost")
	check_equal(_ids(), [&"stillness"], "frost on hex")
	check_equal(_combat.status_left(enemy, &"hex"), 6.0, "two seconds longer")
	check(not _combat.has_status(enemy, &"chill"), "and no chill went on")
	var before: int = _combat.get_health(enemy)
	_combat.hit(0, enemy, 20)
	check_equal(before - _combat.get_health(enemy), 20 + 10, "hex now adds 50 per cent (25 plus 25)")


# --- Rift: storm and void, a burst that pulls ---


func test_rift_bursts_and_pulls_toward_the_centre() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(30.0, 0.0))
	var outside := _enemy(Vector2(100.0, 0.0))
	_combat.apply_status(0, enemy, &"shock", 4.0, 0.0001)
	_hit(0, enemy, &"void")
	check_equal(_ids(), [&"rift"], "rift fired")
	# The burst's 2, and the shock's own jump of at least 1 to the nearest enemy (the hit
	# spends the shock before the reaction runs, so rift only adds the burst).
	check_equal(_combat.get_health(near), 100 - 2 - 1, "the neighbour takes the burst and the jump")
	check(_combat.get_knockback(near).x < 0.0, "and is pulled toward the centre")
	check_equal(_combat.get_health(outside), 100, "out of reach is untouched")


func test_rift_on_a_hexed_enemy_hit_by_storm() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(0.0, -30.0))
	_combat.apply_status(0, enemy, &"hex", 4.0, 25.0)
	_hit(0, enemy, &"storm")
	check_equal(_ids(), [&"rift"], "storm on hex")
	check(_combat.get_knockback(near).y > 0.0, "the neighbour is pulled in")
	check(not _combat.has_status(enemy, &"shock"), "no shock went on")


# --- the rest of the contract ---


func test_the_same_element_does_not_react() -> void:
	var own_status: Dictionary = {&"fire": &"burn", &"frost": &"chill", &"storm": &"shock", &"void": &"hex"}
	for element in ELEMENTS:
		var enemy := _enemy(Vector2(200.0 * ELEMENTS.find(element), 0.0))
		_combat.apply_status(0, enemy, own_status[element], 3.0, 10.0)
		_hit(0, enemy, element)
	check(_reacted.is_empty(), "an element on its own status only refreshes it")


func test_a_hit_with_no_element_does_not_react() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_bus.projectile_hit.emit(0, enemy, enemy.position + Vector2(-8.0, 0.0), _spells.install(0, 0, _spells.compile({"form": &"bolt"})))
	check(_reacted.is_empty(), "plain damage reacts with nothing")
	check(_combat.has_status(enemy, &"chill"), "and leaves the chill")


func test_the_event_names_the_player_and_the_place() -> void:
	var enemy := _enemy(Vector2(40.0, 24.0))
	_combat.apply_status(3, enemy, &"chill", 3.0, 40.0)
	_hit(3, enemy, &"storm")
	check_equal(_reacted.size(), 1, "one event")
	check_equal(_reacted[0][0], 3, "the player who landed the hit")
	check_equal(_reacted[0][2], enemy.position, "at the enemy")


func test_a_killing_hit_sets_off_no_reaction() -> void:
	var enemy := _enemy(Vector2.ZERO, 3)
	_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_hit(0, enemy, &"storm")
	check_equal(_combat.get_enemy_count(), 0, "the enemy died")
	check(_reacted.is_empty(), "nothing is left to react")


func test_a_reaction_can_kill_and_credits_the_player() -> void:
	var enemy := _enemy(Vector2.ZERO, BOLT + 3)
	_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	var killers: Array[int] = []
	_bus.enemy_died.connect(func(player: int, _who: Node, _at: Vector2) -> void: killers.append(player))
	_hit(2, enemy, &"storm")
	check_equal(killers, [2], "player 2's shatter finished it")


func test_four_players_react_on_four_enemies_at_once() -> void:
	var enemies: Array[Node2D] = []
	var statuses: Array[StringName] = [&"burn", &"chill", &"shock", &"hex"]
	for player in 4:
		var enemy := _enemy(Vector2(200.0 * player, 0.0))
		enemies.append(enemy)
		_combat.apply_status(player, enemy, statuses[player], 3.0, 10.0)
	# fire on burn: none; frost on chill: none; so pick a different element for each.
	var elements: Array[StringName] = [&"frost", &"storm", &"void", &"storm"]
	for player in 4:
		_hit(player, enemies[player], elements[player])
	check_equal(_ids(), [&"thaw", &"shatter", &"rift", &"rift"], "each hit reacted by its own pair")
	var players: Array[int] = []
	for row: Array in _reacted:
		players.append(row[0] as int)
	check_equal(players, [0, 1, 2, 3], "each reaction names its own player")


func test_reactions_do_not_chain_into_each_other() -> void:
	# A burst's damage is not a projectile hit, so it sets off nothing on the neighbours.
	var enemy := _enemy()
	var near := _enemy(Vector2(30.0, 0.0))
	_combat.apply_status(0, near, &"chill", 3.0, 40.0)
	_combat.apply_status(0, enemy, &"burn", 3.0, 2.0)
	_hit(0, enemy, &"storm")
	check_equal(_ids(), [&"flare"], "only the struck enemy reacted")
	check(_combat.has_status(near, &"chill"), "the neighbour keeps its chill")


func test_a_busy_reaction_leaves_nothing_behind() -> void:
	var crowd: Array[Node2D] = []
	for i in 40:
		crowd.append(_enemy(Vector2(float(i % 8) * 14.0, float(i / 8) * 14.0)))
	_combat.apply_status(0, crowd[0], &"burn", 3.0, 2.0)
	_hit(0, crowd[0], &"storm")
	_run(1.0)
	check_equal(_reacted.size(), 1, "one reaction for one hit")
	check(_combat._near.is_empty(), "the scratch list is empty again")


# --- limits: a reaction cannot be repeated for ever ---


func test_an_enemy_reacts_once_per_wait_and_the_next_hit_does_its_own_status() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"shock", 5.0, 50.0)
	_hit(0, enemy, &"fire")
	_hit(0, enemy, &"fire")
	check_equal(_ids(), [&"flare"], "the second hit inside the wait did not react")
	check(_combat.has_status(enemy, &"burn"), "it burned the enemy instead")
	_run(CombatScript.REACTION_WAIT + STEP)
	_combat.apply_status(0, enemy, &"shock", 5.0, 50.0)
	_hit(0, enemy, &"fire")
	check_equal(_ids(), [&"flare", &"flare"], "after the wait it reacts again")


func test_twenty_stillness_hits_freeze_for_no_more_than_the_limit() -> void:
	var enemy := _enemy(Vector2.ZERO, 1000)
	_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	for i in 20:
		_hit(0, enemy, &"void")
		check(_combat.status_left(enemy, &"freeze") <= CombatScript.MAX_FREEZE, "frozen no longer than the cap")
		_run(CombatScript.REACTION_WAIT + STEP)
	check(_combat.has_status(enemy, &"freeze"), "still frozen: the cap is a ceiling")


func test_twenty_stillness_hits_on_hex_stay_under_the_caps() -> void:
	var enemy := _enemy(Vector2.ZERO, 100000)
	_combat.apply_status(0, enemy, &"hex", 4.0, 25.0)
	for i in 20:
		_hit(0, enemy, &"frost")
		_run(CombatScript.REACTION_WAIT + STEP)
	check(_combat.status_left(enemy, &"hex") <= CombatScript.MAX_EXTENDED_TIME, "hex time under its cap")
	var before: int = _combat.get_health(enemy)
	_combat.hit(0, enemy, 100)
	check(before - _combat.get_health(enemy) <= 100 + 100, "hex adds at most 100 per cent")


func test_shatter_doubles_for_a_frozen_and_shocked_enemy() -> void:
	var enemy := _enemy()
	for i in 3:
		_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_combat.apply_status(0, enemy, &"shock", 5.0, 50.0)
	_hit(0, enemy, &"frost")
	check_equal(_ids(), [&"shatter"], "frost on shock shatters")
	check_equal(_combat.get_health(enemy), 100 - BOLT - 12, "twice the bonus, as for a frozen chill")
	check(not _combat.has_status(enemy, &"freeze"), "the freeze is broken")


func test_a_spread_row_can_use_up_the_status() -> void:
	var table := ReactionTable.new()
	var row := ReactionRow.new()
	row.reaction_id = &"test_spread"
	row.status_id = &"burn"
	row.element_id = &"storm"
	row.effect = ReactionRow.Effect.SPREAD
	row.radius = 48.0
	row.consume_status = true
	table.rows.append(row)
	_combat.reactions = table
	var enemy := _enemy()
	var near := _enemy(Vector2(30.0, 0.0))
	_combat.apply_status(0, enemy, &"burn", 3.0, 2.0)
	_hit(0, enemy, &"storm")
	check(not _combat.has_status(enemy, &"burn"), "the struck enemy lost its burn")
	check(_combat.has_status(near, &"burn"), "the neighbour caught it")


# --- Lightning (#243): Overload with fire, Superconduct with frost ---


func test_lightning_reacts_with_fire_and_frost_both_ways() -> void:
	var table: ReactionTable = load("res://content/spells/reactions.tres") as ReactionTable
	var wanted: Array = [
		[&"burn", &"lightning", &"overload"], [&"static", &"fire", &"overload"],
		[&"chill", &"lightning", &"superconduct"], [&"static", &"frost", &"superconduct"],
	]
	for want: Array in wanted:
		var row: ReactionRow = table.find(want[0], want[1])
		check(row != null and row.reaction_id == want[2], "%s on %s is %s" % [want[1], want[0], want[2]])


func test_overload_bursts_round_a_burning_enemy_hit_by_lightning() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(30.0, 0.0))
	var outside := _enemy(Vector2(100.0, 0.0))
	_combat.apply_status(0, enemy, &"burn", 3.0, 1.0)
	_hit(0, enemy, &"lightning")
	check_equal(_ids(), [&"overload"], "overload fired")
	check_equal(_combat.get_health(near), 100 - 4, "the neighbour takes the burst")
	check_equal(_combat.get_health(outside), 100, "out of reach is untouched")
	check(not _combat.has_status(enemy, &"static"), "the reaction ran instead of the charge")


func test_overload_the_other_way_fire_on_a_charged_enemy() -> void:
	var enemy := _enemy()
	var near := _enemy(Vector2(30.0, 0.0))
	_combat.apply_status(1, enemy, &"static", 5.0, 60.0)
	_hit(1, enemy, &"fire")
	check_equal(_ids(), [&"overload"], "fire on static")
	check_equal(_reacted[0][0], 1, "it names the player who hit")
	check_equal(_combat.get_health(near), 100 - 4, "the neighbour takes the burst")
	check(not _combat.has_status(enemy, &"burn"), "and fire's burn did not go on")


func test_superconduct_freezes_a_chilled_enemy_hit_by_lightning() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"chill", 3.0, 40.0)
	_hit(0, enemy, &"lightning")
	check_equal(_ids(), [&"superconduct"], "superconduct fired")
	check(_combat.has_status(enemy, &"freeze"), "frozen")
	check_equal(_combat.status_left(enemy, &"freeze"), 1.5, "for 1.5 seconds")
	check(not _combat.has_status(enemy, &"static"), "no charge went on")


func test_superconduct_the_other_way_frost_drains_a_charge_for_damage() -> void:
	var enemy := _enemy()
	_combat.apply_status(0, enemy, &"static", 5.0, 60.0)
	_hit(0, enemy, &"frost")
	check_equal(_ids(), [&"superconduct"], "frost on static")
	check_equal(_combat.get_health(enemy), 100 - BOLT - 4, "the hit plus the bonus")
	check(not _combat.has_status(enemy, &"static"), "the charge is used up")
	check(not _combat.has_status(enemy, &"chill"), "frost's chill did not go on")
