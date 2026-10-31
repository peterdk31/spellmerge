extends "res://tests/support/suite.gd"
## Combat's step with a crowd of bodies (Horde swarm S5, "Cheaper targets",
## docs/milestones/horde-swarm.md): the step made cheaper (every team read once a step, each
## victim's place once, a crowd passed by the box round the victims, only running counts written)
## must touch exactly as before. A scripted crowd of plain bodies (the swarm's) round a few
## wizards, and round many (the grid path), sends the very hits it sent before the change: the
## fingerprints below were recorded on Combat before S5. And the edges: a touch at exactly the
## reach still lands, and a team changed by a death earlier in the step counts for that step's
## touch.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_crowd.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const STEP: float = 0.0625
const ROOM: Vector2 = Vector2(640.0, 360.0)
## The crowds' touches with Combat before S5 (count and hash of every hit in order): four
## wizards, then twenty.
const RECORDED_FEW: Array[int] = [46, 368545434]
const RECORDED_MANY: Array[int] = [174, 3358639731]

var _bus: EventsScript
var _combat: CombatScript
var _projectiles: ProjectileManagerScript
var _actors: ActorsScript
var _holder: Node2D
var _bodies: Array[Node2D] = []
var _index_of: Dictionary = {}
var _hits: int = 0
var _hash: int = 0
var _step_no: int = 0


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_actors = own(ActorsScript.new()) as ActorsScript
	_projectiles = own(ProjectileManagerScript.new()) as ProjectileManagerScript
	_projectiles.actors = _actors
	_projectiles.set_bounds(Rect2(Vector2.ZERO, ROOM))
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.actors = _actors
	_combat.projectiles = _projectiles
	_combat.setup()
	_holder = own(Node2D.new()) as Node2D
	_holder.position = Vector2(2.0, 1.0)
	root.add_child(_holder)
	_bodies.clear()
	_index_of.clear()
	_hits = 0
	_hash = 0
	_step_no = 0
	_bus.hit_landed.connect(_on_hit)


func _on_hit(by: int, target: Node, amount: int, where: Vector2, kind: StringName, _shot: int) -> void:
	_hits += 1
	_hash = hash([_hash, _step_no, by, _index_of.get(target.get_instance_id(), -99), amount, where, kind])


## A plain body at `at` (a swarmer: `contact` > 0; a wizard: on the wizards' team).
func _body(at: Vector2, health: int, radius: float, contact: int, wizard: bool) -> Node2D:
	var body := Node2D.new()
	body.position = at
	_holder.add_child(body)
	var row: int = _combat.register_actor(body, health, radius, contact, Vector2(0.0, -4.0))
	if wizard:
		_actors.set_driver(row, ActorsScript.TEAM_WIZARDS, ActorsScript.NONE)
	_index_of[body.get_instance_id()] = _bodies.size()
	_bodies.append(body)
	return body


## `wizards` wizards in a ring in the middle and 300 swarmers walking through them back and forth
## (no trigonometry), some burning so a few die on the way; returns [hits, hash].
func _crowd(wizards: int) -> Array[int]:
	for w in wizards:
		var spot: Vector2 = ROOM * 0.5 + Vector2(float(w % 5) * 26.0 - 52.0, float(w / 5) * 26.0 - 40.0)
		_body(spot, 1 << 20, 8.0, 0, true)
	var first: int = _bodies.size()
	for i in 300:
		var home: Vector2 = Vector2(fmod(float(i) * 97.31, ROOM.x - 40.0) + 20.0, fmod(float(i) * 53.77, ROOM.y - 40.0) + 20.0)
		_body(home, 3 + i % 4, 5.0 + float(i % 3), 1 + i % 3, false)
	for i in range(0, 300, 11):
		_combat.apply_status(ActorsScript.NONE, _bodies[first + i], CombatScript.BURN, 2.0, 2.0)
	for s in 120:
		for i in 300:
			var held: Variant = _bodies[first + i]
			if not is_instance_valid(held):
				continue
			var home: Vector2 = Vector2(fmod(float(i) * 97.31, ROOM.x - 40.0) + 20.0, fmod(float(i) * 53.77, ROOM.y - 40.0) + 20.0)
			var toward: Vector2 = ROOM * 0.5 - home
			var swing: float = absf(fmod(float(s + i * 3), 60.0) - 30.0) / 30.0
			(held as Node2D).position = home + toward * swing
		_projectiles.step(1.0 / 60.0)
		_combat.step(STEP)
		_step_no += 1
	print("crowd of %d wizards: %d hits, hash %d" % [wizards, _hits, _hash])
	return [_hits, _hash]


func test_a_crowd_round_a_few_wizards_touches_as_before() -> void:
	var got: Array[int] = _crowd(4)
	check(got[0] > 30, "the crowd touches a lot (%d hits)" % got[0])
	check_equal(got, RECORDED_FEW, "the same touches and burns, in the same order, as before")


func test_a_crowd_round_many_wizards_touches_as_before() -> void:
	var got: Array[int] = _crowd(20)
	check(got[0] > 30, "the crowd touches a lot (%d hits)" % got[0])
	check_equal(got, RECORDED_MANY, "the same touches and burns, in the same order, as before")


func test_a_touch_at_exactly_the_reach_lands() -> void:
	var wizard: Node2D = _body(Vector2(200.0, 200.0), 100, 8.0, 0, true)
	_body(Vector2(216.0, 200.0), 10, 8.0, 2, false)
	_body(Vector2(200.0, 216.5), 10, 8.0, 3, false)
	_combat.step(STEP)
	check_equal(_hits, 1, "only the one at exactly 16 px (8 + 8) touches")
	check_equal(_combat.health_of(wizard), 98, "its damage")


func test_a_team_changed_earlier_in_the_step_counts_for_its_touch() -> void:
	var wizard: Node2D = _body(Vector2(200.0, 200.0), 100, 8.0, 0, true)
	var toucher: Node2D = _body(Vector2(205.0, 200.0), 10, 8.0, 2, false)
	var burning: Node2D = _body(Vector2(400.0, 200.0), 1, 8.0, 0, false)
	# The burning body dies of its burn in this step (before contact is counted), and its death
	# turns the toucher to the wizards' side: it touches no wizard in this step.
	_combat.apply_status(ActorsScript.NONE, burning, CombatScript.BURN, 1.0, 100.0)
	var toucher_id: int = _combat.actor_of(toucher)
	_bus.enemy_died.connect(func(_by: int, _who: Node, _at: Vector2, _shot: int) -> void:
		_actors.set_driver(toucher_id, ActorsScript.TEAM_WIZARDS, ActorsScript.NONE))
	_combat.step(STEP)
	check_equal(_combat.health_of(wizard), 100, "the turned toucher did not hurt a wizard")
