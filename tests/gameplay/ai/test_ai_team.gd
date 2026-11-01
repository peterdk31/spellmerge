extends "res://tests/support/suite.gd"
## Working together (enemy AI L2-L4, docs/milestones/M2-enemy-ai.md, "What is left"): the team
## board's reports and a healer that heals its hurt teammates, never a wizard; attackers spreading
## round their target; the call before a group attack. Real cards from the registry, enemies from the imp's scene with staffs made
## here, stepped by hand.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_team.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

var fx: Fixture
## Heals landed, by the node healed (`hit_landed` of kind heal).
var healed: Dictionary = {}


func before_each() -> void:
	fx = Fixture.new(root)
	healed = {}
	fx.bus.hit_landed.connect(_on_hit_landed)


func after_each() -> void:
	fx.free_all()


func _on_hit_landed(_caster: int, target: Node, _amount: float, _at: Vector2, kind: StringName, _shot: int) -> void:
	if kind == CombatScript.KIND_HEAL:
		healed[target.get_instance_id()] = int(healed.get(target.get_instance_id(), 0)) + 1


## A teammate standing at `at` (no staff, no walk), with `share` of its health left.
func _hurt_mate(at: Vector2, share: float) -> Actor:
	var data: EnemyBase = Fixture.staffed([])
	data.max_health = 100.0
	data.move_speed = 0.0
	var body: Actor = fx.imp(at, data)
	body.health.reset(100.0 * share)
	return body


func test_the_board_keeps_reports() -> void:
	var board := TeamBoard.new()
	var slot: int = board.report(1, 7, Vector2(10.0, 0.0), 0.5)
	check_equal(board.mate(1, slot), 7, "a report takes a slot")
	check_equal(board.mate_place(1, slot), Vector2(10.0, 0.0), "where it stands")
	check_equal(board.mate_health(1, slot), 0.5, "and how hurt it is")
	check_equal(board.report(1, 7, Vector2.ZERO, 0.4), slot, "the next report of the same actor keeps its slot")
	check_equal(board.mate(2, slot), -1, "another team's row is empty")
	board.step(TeamBoard.REPORT_LIFE + 0.1)
	check_equal(board.mate(1, slot), -1, "an old report no longer counts")


func test_a_crowd_keeps_its_hurt_on_the_board() -> void:
	var board := TeamBoard.new()
	board.report(1, 100, Vector2.ZERO, 0.2)
	for i in TeamBoard.PLACES * 3:
		board.step(0.01)
		board.report(1, i, Vector2.ZERO, 1.0)
	var kept: bool = false
	for slot in TeamBoard.PLACES:
		kept = kept or board.mate(1, slot) == 100
	check(kept, "teammates that are not hurt make way first, so a hurt one stays for a healer")


func test_it_heals_a_hurt_teammate_never_a_wizard() -> void:
	# The wizard is hurt too, and as near: a heal is only ever for its own team.
	fx.players[0].position = Vector2(-90.0, 0.0)
	fx.players[0].health.reset(fx.players[0].health.max_health * 0.5)
	var wizard_health: float = fx.players[0].health.health
	var healer: Actor = fx.staffed_enemy([["mend", "bolt"]])
	var mate: Actor = _hurt_mate(Vector2(0.0, 70.0), 0.3)
	var brain: AIBrain = Fixture.ai(healer).brain
	var healing: bool = false
	for i in 64:
		fx.run_all(1)
		if brain.behaviour != null and brain.behaviour.name() == "heal ally":
			healing = true
			check(brain.plan_target == mate, "it aims its heal at the teammate")
		check(fx.players[0].health.health <= wizard_health, "the wizard is never healed")
	check(healing, "a hurt teammate in reach makes it heal")
	check(int(healed.get(mate.get_instance_id(), 0)) > 0, "the teammate is healed: %s" % healed)
	check(AIBrain.health_of(mate) > 0.3, "its health goes up: %.2f" % AIBrain.health_of(mate))
	check_equal(int(healed.get(fx.players[0].get_instance_id(), 0)), 0, "no heal lands on the wizard")


func test_it_leaves_a_teammate_that_is_well() -> void:
	fx.players[0].position = Vector2(300.0, 0.0)
	var healer: Actor = fx.staffed_enemy([["mend", "bolt"]])
	_hurt_mate(Vector2(0.0, 70.0), 0.9)
	var brain: AIBrain = Fixture.ai(healer).brain
	for i in 32:
		fx.run_all(1)
		check(brain.behaviour == null or brain.behaviour.name() != "heal ally", "nobody to heal")
	check(healed.is_empty(), "no heal cast: %s" % healed)


func test_it_heals_itself_with_a_heal_that_lands_on_it() -> void:
	fx.players[0].position = Vector2(300.0, 0.0)
	var data: EnemyBase = Fixture.staffed([["mend"]])
	data.max_health = 100.0
	var healer: Actor = fx.imp(Vector2.ZERO, data)
	healer.health.reset(30.0)
	fx.run_all(48)
	check(int(healed.get(healer.get_instance_id(), 0)) > 0, "hurt, it casts the heal that lands on it: %s" % healed)
	check(healer.health.health > 30.0, "and its health goes up: %.1f" % healer.health.health)


## An imp holding a fire bolt it cannot pay for (so the test is about where it walks, and no shot
## of it hurts a teammate into a grudge), with health to spare, at `at`, playing with `teamwork`.
func _waiting_imp(at: Vector2, teamwork: float) -> Actor:
	var profile: AIProfile = Fixture.exact().duplicate() as AIProfile
	profile.teamwork = teamwork
	var data: EnemyBase = Fixture.staffed([["fire", "bolt"]], 1.0, 0.0)
	data.max_health = 1000.0
	var body: Actor = Fixture.ImpData.scene.instantiate() as Actor
	Fixture.ai(body).profile = profile
	body.data = data
	body.position = at
	fx.wire(body)
	root.add_child(body)
	body.set_physics_process(false)
	fx.enemies.append(body)
	return body


## The smallest angle (degrees) between two of `bodies` round the origin.
func _closest_pair(bodies: Array[Actor]) -> float:
	var least: float = 360.0
	for a in bodies.size():
		for b in range(a + 1, bodies.size()):
			least = minf(least, rad_to_deg(absf(angle_difference(bodies[a].position.angle(), bodies[b].position.angle()))))
	return least


## Four imps 300 px off the wizard (at the origin), side by side within 30 degrees.
func _four_imps(teamwork: float) -> Array[Actor]:
	fx.players[0].position = Vector2.ZERO
	var bodies: Array[Actor] = []
	for i in 4:
		bodies.append(_waiting_imp(Vector2.from_angle(deg_to_rad(165.0 + 10.0 * i)) * 300.0, teamwork))
	return bodies


func test_the_board_gives_slots_round_a_target() -> void:
	var board := TeamBoard.new()
	var slots: PackedInt32Array = PackedInt32Array()
	for i in 4:
		slots.append(board.note_attack(1, 10 + i, 77, Vector2.ZERO, Vector2.from_angle(deg_to_rad(170.0 + 5.0 * i)) * 100.0))
	board.note_attack(1, 20, 88, Vector2.ZERO, Vector2(100.0, 0.0))
	check_equal(board.attackers(1, slots[0], 10), 0, "nothing is counted before the board's timer")
	board.step(TeamBoard.RECOUNT)
	var angles: Array[float] = []
	for i in 4:
		check_equal(board.attackers(1, slots[i], 10 + i), 4, "four on the one target")
		angles.append(board.slot_angle(1, slots[i]))
	for a in 4:
		for b in range(a + 1, 4):
			var apart: float = rad_to_deg(absf(angle_difference(angles[a], angles[b])))
			check(apart > 89.0, "their slots are a quarter turn apart or more: %.0f" % apart)
	check_equal(board.attackers(1, slots[0], 11), 0, "a slot answers only for its own attacker")
	board.step(TeamBoard.NOTE_LIFE + TeamBoard.RECOUNT)
	check_equal(board.attackers(1, slots[0], 10), 0, "an old note no longer counts")


func test_four_imps_spread_round_a_wizard() -> void:
	var bodies: Array[Actor] = _four_imps(1.0)
	check(_closest_pair(bodies) < 11.0, "they start side by side")
	fx.run_all(240)
	var apart: float = _closest_pair(bodies)
	check(apart >= 60.0, "they end at least 60 degrees apart round it: %.0f" % apart)
	for body in bodies:
		check(Fixture.ai(body).brain.target == fx.players[0], "all on the wizard")
	var brain: AIBrain = Fixture.ai(bodies[0]).brain
	check_equal(brain.attackers, 4, "each counts the four")
	check(brain.spread_bonus() > 0.0 and brain.spread_bonus() < AIBrain.SPREAD_BONUS, "so a fight on this target is a little less keen than alone: %.3f" % brain.spread_bonus())


func test_with_no_teamwork_they_do_not_spread() -> void:
	var bodies: Array[Actor] = _four_imps(0.0)
	fx.run_all(240)
	var apart: float = _closest_pair(bodies)
	check(apart < 30.0, "they stay side by side: %.0f" % apart)
	check_equal(Fixture.ai(bodies[0]).brain.attackers, 0, "and count nobody")


## An imp that stands where it is (no walk) with a fire bolt and pools to spare, health to spare,
## at `at`, playing with `teamwork`.
func _standing_imp(at: Vector2, teamwork: float) -> Actor:
	var profile: AIProfile = Fixture.exact().duplicate() as AIProfile
	profile.teamwork = teamwork
	var data: EnemyBase = Fixture.staffed([["fire", "bolt"]])
	data.max_health = 1000.0
	data.move_speed = 0.0
	var body: Actor = Fixture.ImpData.scene.instantiate() as Actor
	Fixture.ai(body).profile = profile
	body.data = data
	body.position = at
	fx.wire(body)
	root.add_child(body)
	body.set_physics_process(false)
	fx.enemies.append(body)
	return body


## Two imps side by side, 60 px apart, the wizard out of their reach; once they have told the
## board where they stand, the wizard steps in front of them (neither is in the other's line).
func _two_imps(teamwork: float) -> Array[Actor]:
	fx.players[0].position = Vector2(2000.0, 0.0)
	fx.players[0].health.protect(1000.0)
	var bodies: Array[Actor] = [_standing_imp(Vector2(-120.0, -30.0), teamwork), _standing_imp(Vector2(-120.0, 30.0), teamwork)]
	fx.run_all(16)
	fx.players[0].position = Vector2.ZERO
	return bodies


func _face(body: Actor) -> Face:
	return body.get_node(^"Face") as Face


func test_a_call_makes_teammates_near_keener() -> void:
	var board := TeamBoard.new()
	board.step(TeamBoard.CALL_GAP)
	check(board.can_call(1), "a team may call")
	board.call_attack(1, 7, Vector2.ZERO)
	check(board.is_calling(1), "the call lasts")
	check(not board.can_call(1), "and the team calls no more for a while")
	check(board.beat(1, 8, 1.0, Vector2(50.0, 0.0)) > 1.0, "a teammate near the call joins in")
	check_equal(board.beat(1, 8, 1.0, Vector2(TeamBoard.CALL_REACH * 2.0, 0.0)), 1.0, "one far from it does not")
	check_equal(board.beat(1, 7, 1.0, Vector2.ZERO), 1.0, "nor the one that called")
	check_equal(board.beat(1, 8, 0.0, Vector2.ZERO), 1.0, "nor one with no teamwork")
	check_equal(board.beat(2, 8, 1.0, Vector2.ZERO), 1.0, "nor another team")
	board.step(TeamBoard.CALL_TIME)
	check(not board.is_calling(1), "the call is over after CALL_TIME")
	check_equal(board.beat(1, 8, 1.0, Vector2(50.0, 0.0)), 1.0, "and so is joining in")
	check_equal(board.nearest_mate(1, 7, Vector2.ZERO, 100.0), Vector2.INF, "with no reports there is no teammate to glance at")
	board.report(1, 8, Vector2(40.0, 0.0), 1.0)
	board.report(1, 9, Vector2(90.0, 0.0), 1.0)
	check_equal(board.nearest_mate(1, 7, Vector2.ZERO, 100.0), Vector2(40.0, 0.0), "the nearest teammate on the board")


func test_a_called_teammate_joins_within_a_beat() -> void:
	var bodies: Array[Actor] = _two_imps(1.0)
	var caller: int = -1
	var called_at: float = -1.0
	var joined_at: float = -1.0
	var glanced: bool = false
	var time: float = 0.0
	for i in 32:
		fx.run_all(1)
		time += Fixture.STEP
		for at in 2:
			var brain: AIBrain = Fixture.ai(bodies[at]).brain
			if caller < 0 and brain.state == AIBrain.State.CALL:
				caller = at
				called_at = time
			if caller >= 0 and at != caller and joined_at < 0.0 and brain.state == AIBrain.State.WINDUP:
				joined_at = time
		if caller >= 0 and Fixture.ai(bodies[caller]).brain.state == AIBrain.State.CALL:
			var face: Face = _face(bodies[caller])
			var other: Actor = bodies[1 - caller]
			glanced = glanced or (face.mood() == Face.Mood.RAISED and face.look().y == signi(int(other.position.y - bodies[caller].position.y)))
	check(caller >= 0, "one of them calls before it winds up")
	check(glanced, "glancing at the other, brows raised")
	check(joined_at >= 0.0 and joined_at - called_at <= TeamBoard.BEAT, "the other starts its windup within a beat: called %.2f, joined %.2f" % [called_at, joined_at])


func test_with_no_teamwork_nobody_calls() -> void:
	var bodies: Array[Actor] = _two_imps(0.0)
	var windups: int = 0
	for i in 48:
		fx.run_all(1)
		for body in bodies:
			var brain: AIBrain = Fixture.ai(body).brain
			check(brain.state != AIBrain.State.CALL, "nobody calls")
			if brain.state == AIBrain.State.WINDUP:
				windups += 1
	check(windups > 0, "they attack all the same")
	check(not fx.board.is_calling(1) and fx.board.called_at(1) == -INF, "the board has no call")
