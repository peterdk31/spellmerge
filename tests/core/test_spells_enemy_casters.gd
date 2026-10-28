extends "res://tests/support/suite.gd"
## Enemy casters in core/spells (staffs F5, docs/milestones/M2-staffs.md, "Enemy staffs"): an
## enemy opens a caster row, installs and casts a staff like a player, and its spells hit wizards
## (never enemies), with payloads and chains; events name it NO_PLAYER and its tags name its row;
## all enemies share one per-step fire count and a capped share of the live beams and the waiting
## launches, so they never take a player's; closing a row ends what it holds while its shots in
## the air fly on; a four-player staff is unchanged. A real projectile manager and event bus,
## stepped by hand, with cards built in code and a stand-in registry.
##
## godot --headless --path . --script res://tests/core/test_spells_enemy_casters.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _fake: FakeRegistry
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every projectile_hit as [player, target, tag].
var _hits: Array = []
## Every caster_move_requested and area_hit_requested as [player, tag].
var _moves: Array = []
var _areas: Array = []
var _refunds: int = 0


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(1024)
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_hits.clear()
	_moves.clear()
	_areas.clear()
	_refunds = 0
	_bus.projectile_hit.connect(func(player: int, target: Node, _at: Vector2, tag: int) -> void: _hits.append([player, target, tag]))
	_bus.caster_move_requested.connect(func(player: int, _mode: StringName, _to: Vector2, _seconds: float, tag: int) -> void: _moves.append([player, tag]))
	_bus.area_hit_requested.connect(func(player: int, _at: Vector2, _radius: float, tag: int) -> void: _areas.append([player, tag]))
	_bus.mana_refund_requested.connect(func(_player: int, _amount: float) -> void: _refunds += 1)
	_form(&"bolt", 300.0, 1.0)
	_form(&"slow", 30.0, 5.0)
	var beam: FormBase = _form(&"beam", 0.0, 5.0)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 200.0
	var dash: FormBase = _form(&"dash", 400.0, 0.2)
	dash.motion = FormBase.Motion.DASH
	dash.ray_length = 80.0
	var orb: FormBase = _form(&"orb", 0.0, 5.0)
	orb.motion = FormBase.Motion.ORBIT
	orb.orbit_radius = 30.0
	var chain: ModifierBase = ModifierBase.new()
	chain.behaviour = ModifierBase.Behaviour.CHAIN
	chain.behaviour_strength = 1.0
	_put(chain, &"chain")
	var echo: ModifierBase = ModifierBase.new()
	echo.behaviour = ModifierBase.Behaviour.ECHO
	echo.behaviour_strength = 1.0
	_put(echo, &"echo")
	var siphon: ModifierBase = ModifierBase.new()
	siphon.behaviour = ModifierBase.Behaviour.SIPHON
	siphon.behaviour_strength = 2.0
	_put(siphon, &"siphon")
	var blast: ModifierBase = ModifierBase.new()
	blast.behaviour = ModifierBase.Behaviour.BLAST
	blast.behaviour_strength = 24.0
	_put(blast, &"blast")
	var on_hit := TriggerBase.new()
	on_hit.event = TriggerBase.Event.HIT
	on_hit.max_fires = 1
	_put(on_hit, &"on_hit")
	var timer := TriggerBase.new()
	timer.event = TriggerBase.Event.TIMER
	timer.max_fires = 1
	timer.interval = 0.5
	_put(timer, &"timer")


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


func _form(id: StringName, speed: float, lifetime: float) -> FormBase:
	var form := FormBase.new()
	form.base_damage = 5
	form.speed = speed
	form.lifetime = lifetime
	form.mana_cost = 2.0
	_put(form, id)
	return form


func _build(caster: int, cards: Array[StringName]) -> int:
	return StaffKit.build(_spells, caster, 0, cards)


func _target(at: Vector2, layer: int, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	_mgr.add_target(node, 10.0, layer, owner)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _cast(caster: int, origin: Vector2 = Vector2.ZERO, direction: Vector2 = Vector2.RIGHT) -> float:
	return _spells.cast_staff(caster, 0, origin, direction, 100.0)


func _hit_targets() -> Array[Node]:
	var out: Array[Node] = []
	for hit: Array in _hits:
		out.append(hit[1] as Node)
	return out


func test_rows_open_close_and_are_handed_out_oldest_closed_first() -> void:
	check_equal(SpellLimits.ENEMY_CASTERS, ManagerScript.ENEMY_CASTERS, "the runtime has the manager's enemy rows")
	check_equal(SpellLimits.FIRST_ENEMY_CASTER, SpellTag.FIRST_ENEMY_CASTER, "numbered as the tags number them")
	check_equal(_build(SpellLimits.FIRST_ENEMY_CASTER, [&"bolt"]), 0, "a row that is not open takes no build")
	var rows: Array[int] = []
	for i in SpellLimits.ENEMY_CASTERS:
		rows.append(_spells.open_enemy_caster())
	check_equal(rows[0], SpellLimits.FIRST_ENEMY_CASTER, "the first row follows the players")
	check_equal(rows[-1], SpellLimits.CASTERS - 1, "the last is the last caster")
	check_equal(_spells.open_enemy_caster(), -1, "with every row open there is none left")
	check_equal(_spells.enemy_casters_open(), SpellLimits.ENEMY_CASTERS, "all open")
	_spells.close_enemy_caster(rows[5])
	_spells.close_enemy_caster(rows[2])
	check(not _spells.is_enemy_caster_open(rows[5]), "a closed row is closed")
	check_equal(_spells.open_enemy_caster(), rows[5], "the row closed first comes back first")
	check_equal(_spells.open_enemy_caster(), rows[2], "then the next")
	_spells.close_enemy_caster(0)
	_spells.close_enemy_caster(SpellLimits.CASTERS)
	check_equal(_spells.enemy_casters_open(), SpellLimits.ENEMY_CASTERS, "a player or a bad number closes nothing")


## Enemies always hurt each other (actors G3c): an enemy's bolt stops on the first actor in its
## way, an enemy or a wizard.
func test_an_enemys_bolt_hits_the_first_in_its_way_an_enemy_too() -> void:
	var imp: int = _spells.open_enemy_caster()
	var tag: int = _build(imp, [&"bolt"])
	check(SpellTag.is_enemy_tag(tag) and SpellTag.caster_of(tag) == imp, "its tags name its row")
	var other: Node2D = _target(Vector2(60.0, 0.0), ManagerScript.LAYER_ENEMY)
	var wizard: Node2D = _target(Vector2(140.0, 0.0), ManagerScript.LAYER_PLAYER, 0)
	check(_cast(imp) >= 0.0, "an enemy casts its staff")
	_tick(40)
	check_equal(_hit_targets(), [other] as Array[Node], "it stops on the other enemy in its way")
	check(not _hit_targets().has(wizard), "so the wizard behind it is safe")
	check(_hits.size() == 1 and _hits[0][0] == EventsScript.NO_PLAYER and _hits[0][2] == tag, "the hit names NO_PLAYER and its tag")
	check(_spells.hit_profile(tag) != null, "combat can read its numbers")


func test_an_enemys_payload_and_chain_go_to_wizards() -> void:
	var imp: int = _spells.open_enemy_caster()
	_build(imp, [&"chain", &"on_hit", &"bolt", &"bolt"])
	var first: Node2D = _target(Vector2(100.0, 0.0), ManagerScript.LAYER_PLAYER, 0)
	var second: Node2D = _target(Vector2(160.0, 60.0), ManagerScript.LAYER_PLAYER, 1)
	_target(Vector2(100.0, 40.0), ManagerScript.LAYER_ENEMY)
	_cast(imp)
	_tick(60)
	check(_hit_targets().has(first), "the bolt hits the first wizard")
	check(_hit_targets().has(second), "its chain or payload goes on to the second")
	for hit: Array in _hits:
		check(SpellTag.caster_of(hit[2]) == imp and hit[0] == EventsScript.NO_PLAYER, "every hit is the enemy's")
		check(hit[1] == first or hit[1] == second, "and on a wizard")


func test_a_four_player_staff_is_unchanged() -> void:
	var tags: Array[int] = []
	for player in SpellLimits.PLAYERS:
		tags.append(_build(player, [&"bolt"]))
		check_equal(tags[player], SpellTag.make(player, 0, 0, 0), "player %d's first tag is as before" % player)
	var imp: int = _spells.open_enemy_caster()
	var enemy_tag: int = _build(imp, [&"bolt"])
	check(not tags.has(enemy_tag), "the enemy's tag is none of theirs")
	var targets: Array[Node2D] = []
	for player in SpellLimits.PLAYERS:
		targets.append(_target(Vector2(60.0 * player, 100.0), ManagerScript.LAYER_ENEMY))
		_cast(player, Vector2(60.0 * player, 0.0), Vector2.DOWN)
	_tick(30)
	check_equal(_hits.size(), 4, "four players still hit enemies")
	for hit: Array in _hits:
		check(hit[1] == targets[hit[0]] and hit[0] == SpellTag.player_of(hit[2]), "each as itself")


func test_enemies_share_a_capped_part_of_the_beams() -> void:
	_build(0, [&"beam"])
	_spells.set_aim(0, Vector2(0.0, 300.0), Vector2.RIGHT)
	_cast(0, Vector2(0.0, 300.0))
	var imps: Array[int] = []
	for i in SpellLimits.ENEMY_BEAMS + 4:
		var imp: int = _spells.open_enemy_caster()
		imps.append(imp)
		_build(imp, [&"beam"])
		_spells.set_aim(imp, Vector2(0.0, 10.0 * i), Vector2.RIGHT)
		_cast(imp, Vector2(0.0, 10.0 * i))
	check_equal(_spells.beam_count(), SpellLimits.ENEMY_BEAMS + 1, "the enemies hold their share and no more")
	var players: int = 0
	var enemies: int = 0
	for at in _spells.beam_slots():
		if _spells.beam_on(at):
			if _spells.beam_player(at) == 0:
				players += 1
			elif _spells.beam_player(at) == EventsScript.NO_PLAYER:
				enemies += 1
	check_equal(players, 1, "the player's beam was never ended by an enemy's")
	check_equal(enemies, SpellLimits.ENEMY_BEAMS, "an enemy's beam is named NO_PLAYER for its look")
	_spells.close_enemy_caster(imps[-1])
	check_equal(_spells.beam_count(), SpellLimits.ENEMY_BEAMS, "closing a row ends its beam")


func test_enemies_share_a_capped_part_of_the_waiting_launches() -> void:
	for i in SpellLimits.ENEMY_PENDING + 8:
		var imp: int = _spells.open_enemy_caster()
		_build(imp, [&"echo", &"slow"])
		_cast(imp, Vector2(0.0, 4.0 * i))
	check_equal(_spells.delayed_dropped, 8, "past their share the enemies' echoes are dropped")
	_build(0, [&"echo", &"slow"])
	_cast(0, Vector2(0.0, 200.0))
	check_equal(_spells.delayed_dropped, 8, "a player's echo still waits its turn")


func test_enemies_share_one_fire_count_a_step() -> void:
	var count: int = SpellLimits.MAX_FIRES_PER_STEP + 8
	for i in count:
		var imp: int = _spells.open_enemy_caster()
		_build(imp, [&"timer", &"slow", &"bolt"])
		_cast(imp, Vector2(0.0, 4.0 * i), Vector2.DOWN)
	var player_payload: int = 0
	_build(0, [&"timer", &"slow", &"bolt"])
	_cast(0, Vector2(300.0, 0.0), Vector2.DOWN)
	player_payload = _spells.current_tag(0, 0, 1)
	_tick(31)
	check_equal(_spells.fires_dropped, 8, "every enemy together fires one player's worth of payloads a step")
	check(_spells.live_shots(player_payload) > 0, "and the player's timer fires anyway")


func test_closing_a_row_lets_its_shots_fly_on_with_their_numbers() -> void:
	var imp: int = _spells.open_enemy_caster()
	var tag: int = _build(imp, [&"slow"])
	_cast(imp)
	_tick(5)
	_spells.close_enemy_caster(imp)
	check_equal(_spells.live_shots(tag), 1, "the shot flies on")
	check(_spells.hit_profile(tag) != null, "with its numbers")
	check_equal(_spells.cast_staff(imp, 0, Vector2.ZERO, Vector2.RIGHT, 100.0), SpellsScript.REFUSED, "a closed row casts nothing")
	_tick(400)
	check_equal(_spells.live_shots(tag), 0, "until it ends")
	check(_spells.hit_profile(tag) == null, "then its numbers are forgotten")
	_spells.open_enemy_caster()
	_spells.clear()
	check_equal(_spells.enemy_casters_open(), 0, "clear closes every row")
	check_equal(_spells.open_enemy_caster(), SpellLimits.FIRST_ENEMY_CASTER, "and frees them in order")


func test_a_reopened_row_goes_on_round_the_ring() -> void:
	var imp: int = _spells.open_enemy_caster()
	var old: int = _build(imp, [&"slow"])
	_cast(imp)
	_spells.close_enemy_caster(imp)
	for row in SpellLimits.ENEMY_CASTERS - 1:
		_spells.open_enemy_caster()
	check_equal(_spells.open_enemy_caster(), imp, "the last free row is the dead enemy's")
	var fresh: int = _build(imp, [&"bolt"])
	check(fresh != old, "a new generation, not the old one's")
	check_equal(_spells.live_shots(old), 1, "the old shot is still counted")
	check(_spells.profile(old) != null and _spells.profile(old) != _spells.profile(fresh), "with its old numbers")


func test_next_cast_mana_and_siphon_refunds_for_an_ai() -> void:
	var imp: int = _spells.open_enemy_caster()
	check_equal(_spells.next_cast_mana(imp, 0), SpellsScript.REFUSED, "nothing built, nothing to cast")
	_build(imp, [&"siphon", &"bolt"])
	var cost: float = _spells.next_cast_mana(imp, 0)
	check(cost > 0.0, "the next cast's mana (%.2f)" % cost)
	check_equal(_spells.cast_staff(imp, 0, Vector2.ZERO, Vector2.RIGHT, cost * 0.5), SpellsScript.REFUSED, "less than that is refused")
	_target(Vector2(80.0, 0.0), ManagerScript.LAYER_PLAYER, 0)
	check_equal(_spells.cast_staff(imp, 0, Vector2.ZERO, Vector2.RIGHT, cost), cost, "enough casts and spends it")
	_tick(30)
	check(is_equal_approx(_spells.take_refund(imp), 2.0), "the siphon's refund waits for the AI")
	check_equal(_spells.take_refund(imp), 0.0, "once")
	check_equal(_refunds, 0, "no player is refunded for it")
	check_equal(_spells.take_refund(0), 0.0, "a player's comes as an event instead")


func test_an_enemys_dash_is_asked_for_by_tag_and_ends_with_its_blast() -> void:
	var imp: int = _spells.open_enemy_caster()
	var tag: int = _build(imp, [&"blast", &"dash"])
	_cast(imp, Vector2(50.0, 50.0))
	check(_moves.size() == 1 and _moves[0][0] == EventsScript.NO_PLAYER and SpellTag.caster_of(_moves[0][1]) == imp, "the move is asked for as NO_PLAYER with the enemy's tag")
	_bus.caster_move_finished.emit(EventsScript.NO_PLAYER, &"dash", Vector2(130.0, 50.0), tag)
	check(_areas.size() == 1 and _areas[0][0] == EventsScript.NO_PLAYER and _areas[0][1] == tag, "where it ends, its blast")
	_bus.caster_move_finished.emit(1, &"dash", Vector2(130.0, 50.0), tag)
	check_equal(_areas.size(), 1, "a player's answer for an enemy's tag is ignored")


func test_an_enemys_orbit_circles_its_own_anchor() -> void:
	var imp: int = _spells.open_enemy_caster()
	_build(imp, [&"orb"])
	check_equal(_cast(imp, Vector2(200.0, 200.0)), SpellsScript.REFUSED, "with no anchor, no orbit")
	_mgr.set_anchor(imp, Vector2(200.0, 200.0))
	check(_cast(imp, Vector2(200.0, 200.0)) >= 0.0, "with its anchor it casts")
	check_equal(_mgr.get_count_for(EventsScript.NO_PLAYER), 1, "one enemy shot round it")


func test_next_cast_reach_for_a_telegraph() -> void:
	var imp: int = _spells.open_enemy_caster()
	check_equal(_spells.next_cast_reach(imp, 0), 0.0, "no build, no reach")
	_build(imp, [&"bolt"])
	check(is_equal_approx(_spells.next_cast_reach(imp, 0), 300.0), "a bolt reaches its speed times its life")
	_build(imp, [&"beam"])
	check(is_equal_approx(_spells.next_cast_reach(imp, 0), 200.0), "a beam its length")
	_build(imp, [&"orb"])
	check_equal(_spells.next_cast_reach(imp, 0), 0.0, "an orbit is not aimed")
