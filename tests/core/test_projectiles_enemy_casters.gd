extends "res://tests/support/suite.gd"
## Enemy casters in core/projectiles (staffs F4, docs/milestones/M2-staffs.md, "Enemy staffs"):
## shots owned by an enemy caster row (FIRST_ENEMY_CASTER and up) are the enemies' side. Events
## name them NO_PLAYER; they skip their own enemy's body, hit wizards and decoys, and hit the
## other enemies too (actors G3c); they share NO_PLAYER's drop bucket at the cap; they orbit
## their own anchor; shields and homing work by side; and they are drawn by the shot shader in
## the enemy ramp, above the players' shots. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_enemy_casters.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const SpellTagScript := preload("res://core/spells/spell_tag.gd")

const DT: float = 1.0 / 60.0
## The first and the last enemy caster.
const IMP: int = ManagerScript.FIRST_ENEMY_CASTER
const LAST: int = ManagerScript.CASTERS - 1

var mgr: ManagerScript
var bus: EventsScript
## Every projectile_hit as [player, target, tag].
var hits: Array = []
## Every projectile_expired and projectile_impact's player.
var expired: Array[int] = []
var impacts: Array[int] = []
## Every shot_blocked as [player, tag].
var blocked: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	root.add_child(mgr)
	hits.clear()
	expired.clear()
	impacts.clear()
	blocked.clear()
	bus.projectile_hit.connect(func(player: int, target: Node, _at: Vector2, tag: int) -> void: hits.append([player, target, tag]))
	bus.projectile_expired.connect(func(player: int, _at: Vector2, _tag: int) -> void: expired.append(player))
	bus.projectile_impact.connect(func(player: int, _target: Node, _at: Vector2, _dir: Vector2) -> void: impacts.append(player))
	bus.shot_blocked.connect(func(player: int, _at: Vector2, tag: int) -> void: blocked.append([player, tag]))


func _target(at: Vector2, layer: int, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	mgr.add_target(node, 8.0, layer, owner)
	return node


## An enemy at `at` whose body belongs to `caster` (as the AI registers it, then names its row).
func _enemy(at: Vector2, caster: int) -> Node2D:
	var node: Node2D = _target(at, ManagerScript.LAYER_ENEMY)
	check(mgr.set_target_owner(node, caster), "the enemy's body takes its caster row")
	return node


func _run(steps: int) -> void:
	for _i in steps:
		mgr.step(DT)


func _hit_targets() -> Array[Node]:
	var out: Array[Node] = []
	for hit: Array in hits:
		out.append(hit[1] as Node)
	return out


func test_constants_match_the_spell_tags() -> void:
	check_equal(ManagerScript.ENEMY_CASTERS, SpellTagScript.ROW_MASK + 1, "one enemy caster per enemy row of a tag")
	check_equal(ManagerScript.FIRST_ENEMY_CASTER, SpellTagScript.FIRST_ENEMY_CASTER, "numbered after the players, as SpellTag.caster_of counts")
	check(ManagerScript.is_caster(LAST) and not ManagerScript.is_caster(ManagerScript.CASTERS), "the last row is a caster, the one after is not")
	for caster in [EventsScript.NO_PLAYER, IMP, LAST]:
		check_equal(ManagerScript.event_player(caster), EventsScript.NO_PLAYER, "caster %d is named NO_PLAYER in events" % caster)
	for player in 4:
		check_equal(ManagerScript.event_player(player), player, "a player is named as itself")


func test_an_enemy_casters_shot_hits_a_wizard_and_names_no_player() -> void:
	var tag: int = SpellTagScript.make_enemy(0, 0, 1, 0)
	var imp: Node2D = _enemy(Vector2(100.0, 100.0), IMP)
	var wizard: Node2D = _target(Vector2(200.0, 100.0), ManagerScript.LAYER_PLAYER, 0)
	var slot: int = mgr.spawn(IMP, Vector2(100.0, 100.0), Vector2(300.0, 0.0), 2.0, 4.0, ManagerScript.LAYER_PLAYER, 0, tag)
	check(slot >= 0, "an enemy caster may spawn")
	_run(30)
	check_equal(hits.size(), 1, "one hit")
	check(hits.size() == 1 and hits[0][1] == wizard and hits[0][0] == EventsScript.NO_PLAYER and hits[0][2] == tag, "on the wizard, as NO_PLAYER, with its tag")
	check(not _hit_targets().has(imp), "never its own enemy")
	check(not impacts.is_empty() and impacts.all(func(p: int) -> bool: return p == EventsScript.NO_PLAYER), "its impacts name NO_PLAYER too")
	mgr.spawn(LAST, Vector2(300.0, 300.0), Vector2(10.0, 0.0), 0.1, 4.0, ManagerScript.LAYER_PLAYER)
	_run(10)
	check_equal(expired, [EventsScript.NO_PLAYER] as Array[int], "and so does the last row's expiry")


## Enemies always hurt each other (actors G3c): an enemy's spell hits the other enemies, never its
## own body; a NO_PLAYER shot hits enemies too.
func test_an_enemys_spell_hits_the_others_but_never_itself() -> void:
	var imp: Node2D = _enemy(Vector2(100.0, 100.0), IMP)
	var other: Node2D = _enemy(Vector2(200.0, 100.0), IMP + 1)
	mgr.spawn(IMP, Vector2(100.0, 100.0), Vector2(300.0, 0.0), 2.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(EventsScript.NO_PLAYER, Vector2(200.0, 160.0), Vector2(0.0, -300.0), 2.0, 4.0, ManagerScript.LAYER_PLAYER)
	_run(40)
	check_equal(_hit_targets(), [other, other] as Array[Node], "an enemy's shot and a NO_PLAYER one each hit the other enemy, never the caster")
	check(not _hit_targets().has(imp), "never its own body")
	hits.clear()
	mgr.ray(IMP, Vector2(100.0, 100.0), Vector2.RIGHT, 200.0, 0, ManagerScript.LAYER_PLAYER)
	check_equal(_hit_targets(), [other] as Array[Node], "an enemy's beam hits the other enemy too")


func test_enemy_casters_share_the_enemies_drop_bucket() -> void:
	mgr.set_cap(64)
	for i in 8:
		mgr.spawn(0, Vector2(20.0 + i, 20.0), Vector2.ZERO, 30.0)
	for i in 56:
		mgr.spawn(IMP + i % 40, Vector2(20.0 + i, 60.0), Vector2.ZERO, 30.0, 4.0, ManagerScript.LAYER_PLAYER)
	check_equal(mgr.get_count_for(IMP), mgr.get_count_for(EventsScript.NO_PLAYER), "every enemy caster counts as the enemies")
	check_equal(mgr.get_count_for(EventsScript.NO_PLAYER), 56, "56 enemy shots")
	for i in 16:
		mgr.spawn(IMP + 3, Vector2(100.0 + i, 100.0), Vector2.ZERO, 30.0, 4.0, ManagerScript.LAYER_PLAYER)
	check_equal(mgr.get_count_for(0), 8, "a crowd of enemy casters never drops a player's shot")
	check_equal(mgr.dropped, 16, "it drops the enemies' own oldest")


func test_an_enemy_orbit_follows_its_own_anchor_and_ends_with_it() -> void:
	check_equal(mgr.spawn_orbit(LAST, 20.0, 0.0, 1.0, 5.0), -1, "no anchor, no orbit")
	mgr.set_anchor(LAST, Vector2(300.0, 200.0))
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	var slot: int = mgr.spawn_orbit(LAST, 20.0, 0.0, 0.0, 5.0, 4.0, ManagerScript.LAYER_PLAYER)
	check(slot >= 0, "an enemy caster's orbit spawns round its anchor")
	check_equal(mgr.get_anchor(LAST), Vector2(300.0, 200.0), "which the manager keeps")
	mgr.set_anchor(LAST, Vector2(340.0, 200.0))
	_run(1)
	check(mgr.get_position_of(slot).is_equal_approx(Vector2(360.0, 200.0)), "and follows it (%s)" % mgr.get_position_of(slot))
	mgr.clear_anchor(LAST)
	_run(2)
	check(not mgr.is_alive(slot), "clearing the anchor ends it")
	check(expired.is_empty(), "quietly")
	check_equal(mgr.get_anchor(0), Vector2(100.0, 100.0), "a player's anchor is untouched")
	check_equal(mgr.spawn_orbit(EventsScript.NO_PLAYER, 20.0, 0.0, 1.0, 5.0, 4.0, ManagerScript.LAYER_PLAYER, 0, 0, Vector2(50.0, 50.0)), -1, "NO_PLAYER still has no orbit")


func test_shields_block_the_other_side_only() -> void:
	var guard: int = mgr.spawn(IMP, Vector2(200.0, 100.0), Vector2.ZERO, 3.0, 6.0, ManagerScript.LAYER_PLAYER, 0, 7)
	check(mgr.set_shield(guard, 1), "an enemy caster's shot can have a shield")
	var friend: int = mgr.spawn(IMP + 1, Vector2(150.0, 100.0), Vector2(200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER)
	var bolt: int = mgr.spawn(0, Vector2(250.0, 100.0), Vector2(-200.0, 0.0), 3.0, 3.0)
	_run(30)
	check(mgr.is_alive(friend), "another enemy's shot is not blocked")
	check(not mgr.is_alive(bolt), "a player's bolt is stopped")
	check(blocked.size() == 1 and blocked[0][0] == EventsScript.NO_PLAYER and blocked[0][1] == 7, "shot_blocked names NO_PLAYER and the shield's tag")
	mgr.clear()
	blocked.clear()
	var ward: int = mgr.spawn(1, Vector2(200.0, 200.0), Vector2.ZERO, 3.0, 6.0, ManagerScript.LAYER_ENEMY, 0, 9)
	mgr.set_shield(ward, 2)
	var spell: int = mgr.spawn(IMP, Vector2(260.0, 200.0), Vector2(-200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER)
	_run(30)
	check(not mgr.is_alive(spell), "a player's shield stops an enemy caster's spell")
	check(blocked.size() == 1 and blocked[0][0] == 1, "and says so for that player")


func test_an_enemy_casters_homing_picks_wizards_and_a_players_never_does() -> void:
	var wizard: Node2D = _target(Vector2(200.0, 60.0), ManagerScript.LAYER_PLAYER, 0)
	var imp: Node2D = _enemy(Vector2(200.0, 140.0), IMP)
	var point: Vector2 = mgr.homing_point(IMP, Vector2(100.0, 100.0), Vector2.RIGHT, PI, ManagerScript.LAYER_PLAYER | ManagerScript.LAYER_ENEMY, 300.0, 0, 1)
	check_equal(point, wizard.global_position, "an enemy's homing finds the wizard, never an enemy")
	point = mgr.homing_point(0, Vector2(100.0, 100.0), Vector2.RIGHT, PI, ManagerScript.LAYER_PLAYER | ManagerScript.LAYER_ENEMY, 300.0, 0, 1)
	check_equal(point, imp.global_position, "a player's finds the enemy, never a wizard")


func test_enemy_casters_are_drawn_by_the_shader_above_the_players() -> void:
	mgr.set_anchor(IMP, Vector2(300.0, 200.0))
	var bolt: int = mgr.spawn(IMP, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 2.0, 5.0, ManagerScript.LAYER_PLAYER)
	mgr.set_look(bolt, ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS])))
	mgr.spawn(IMP, Vector2(150.0, 100.0), Vector2.ZERO, 2.0, 14.0, ManagerScript.LAYER_PLAYER, 0, 0, ManagerScript.MOTION_STILL)
	mgr.spawn_orbit(IMP, 20.0, 0.0, 1.0, 2.0, 5.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(EventsScript.NO_PLAYER, Vector2(200.0, 100.0), Vector2(100.0, 0.0), 2.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(2, Vector2(250.0, 100.0), Vector2(100.0, 0.0), 2.0, 5.0)
	mgr.update_draw(1.0)
	check_equal(mgr.drawn_enemy, 4, "three enemy caster shots and the NO_PLAYER shot in their batch")
	check_equal(mgr.drawn, 5, "and the player's bolt in its own")
	var node: MultiMeshInstance2D = mgr._enemy_node
	check(node.material is ShaderMaterial, "drawn by the shot shader")
	check_equal(node.z_index, mgr._draw_node.z_index + 1, "one layer above the players' shots")
	var kinds: Array[int] = []
	for i in 3:
		var buffer: PackedFloat32Array = node.multimesh.buffer
		var at: int = i * ManagerScript.DRAW_STRIDE
		var kind: int = roundi((1.0 - buffer[at + 15]) * ManagerScript.KIND_STEPS)
		# A shot in flight is drawn as its trail; an orbit shot's is flagged so.
		if kind == ManagerScript.KIND_BOLT and (roundi(buffer[at + 5]) & ManagerScript.TRAIL_ORBIT) != 0:
			kind = ManagerScript.KIND_ORBIT
		kinds.append(kind)
		var red: int = roundi(buffer[at + 8] * 255.0)
		var bits: int = roundi(buffer[at + 9] * 255.0) | (roundi(buffer[at + 10] * 255.0) << 8) | (roundi(buffer[at + 11] * 255.0) << 16)
		check(red % 4 == 0 and (bits & ManagerScript.LOOK_ENEMY_RAMP) != 0, "shot %d is in the enemy ramp" % i)
		if kind == ManagerScript.KIND_BOLT:
			check_equal(bits & ~ManagerScript.LOOK_ENEMY_RAMP, ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS])), "with its cards' look")
	kinds.sort()
	check_equal(kinds, [ManagerScript.KIND_BOLT, ManagerScript.KIND_RUNE, ManagerScript.KIND_ORBIT] as Array[int], "a bolt, a rune and an orbit shot, each its own body")
	check(mgr.tint_of(IMP).is_equal_approx(mgr.tint_of(EventsScript.NO_PLAYER)), "an enemy caster's tint is the enemies'")
	check(mgr.tint_of(LAST).is_equal_approx(mgr.tint_of(EventsScript.NO_PLAYER)), "the last row's too, never a player's")
