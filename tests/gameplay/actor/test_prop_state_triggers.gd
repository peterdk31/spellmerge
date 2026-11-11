extends "res://tests/support/suite.gd"
## A prop's states and their triggers (props W6, docs/milestones/props.md, "Triggers" and "The exploding barrel,
## written out"): the `PropStateTriggers` component on a body made by `PropBody.make`, with real Spells,
## Combat and cards. The exploding barrel (`fixtures/exploding_barrel.tres`, the plan's exploding barrel as data: a fuse staff of
## `fire · blast` that winds up 1 s and a blast staff with none) in all its paths: lit and blown, shot
## while lit, shot apart, possessed and pressed; a chain of three; several triggers on one hit; a
## `gone` state; an invincible prop; the triggers one by one; its state in the hash and a snapshot.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_prop_state_triggers.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const EXPLODING_BARREL: PropBase = preload("res://tests/gameplay/actor/fixtures/exploding_barrel.tres")

## The fuse (staff 1, by number 0) and the blast (staff 2, by number 1).
const FUSE: int = 0
const BLAST: int = 1
## Steps the fuse takes to burn (1 s), and a few more.
const FUSE_STEPS: int = 20

var _world: Fixture
## [actor id, state id] of every `prop_state_changed`.
var _changes: Array = []
## [caster, staff] of every `cast_left`.
var _left: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_changes.clear()
	_left.clear()
	_world.bus.prop_state_changed.connect(func(actor: int, state: StringName) -> void: _changes.append([actor, state]))
	_world.bus.cast_left.connect(func(caster: int, staff: int) -> void: _left.append([caster, staff]))


func after_each() -> void:
	_world.free_all()


## A body of `data` at `at`.
func _prop(data: PropBase, at: Vector2 = Vector2.ZERO) -> Actor:
	return _world.add(PropBody.make(data), at)


func _state(body: Actor) -> StringName:
	return body.state_triggers.state_id()


## A dummy of the enemies' team at `at` that only stands and is hurt (its health tells a blast's hit).
func _dummy(at: Vector2) -> Actor:
	var body: Actor = _world.actor(at, [&"health", &"hurtbox"], Fixture.Scripted.new())
	body.health.max_health = 1000.0
	body.health.reset(1000.0)
	return body


## Light `body` with a fire hit (a fire bolt from a shooter beside it, aimed at it), and run until
## it lands.
func _light(body: Actor) -> void:
	var aim: Vector2 = Vector2.RIGHT
	var shooter: Actor = _world.actor(body.global_position - aim * 40.0 + body.body_offset, [&"caster"], Fixture.Scripted.new(), [[&"fire", &"bolt"]])
	shooter.aim = aim
	var hits: Array[StringName] = []
	var heard := func(_by: int, _amount: float, element: StringName) -> void: hits.append(element)
	body.damaged.connect(heard)
	check(shooter.caster.cast(0), "the fire bolt leaves")
	for i in 30:
		_world.run(1)
		if not hits.is_empty():
			break
	check_equal(hits, [&"fire"] as Array[StringName], "a fire hit landed")
	body.damaged.disconnect(heard)
	# Its work done, the shooter leaves (its burn on the body stays).
	_world.actors.erase(shooter)
	shooter.free()


## The exploding barrel's casts of staff `staff` that left.
func _blasts(body: Actor, staff: int) -> int:
	var count: int = 0
	for entry: Array in _left:
		if entry[0] == body.caster_number() and entry[1] == staff:
			count += 1
	return count


func _known() -> Dictionary:
	return PropNames.known(_world.registry)


# --- The data -----------------------------------------------------------------

func test_the_exploding_barrel_is_sound() -> void:
	check_equal(EXPLODING_BARREL.problems(_known()), PackedStringArray(), "the exploding barrel's data is sound")


func test_a_body_is_made_from_its_data() -> void:
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	check_equal(exploding_barrel.team(), ActorsScript.TEAM_WORLD, "the world's")
	check(exploding_barrel.is_still(), "still: no controller, no Mover")
	check_equal(exploding_barrel.health.max_health, 10.0, "its health")
	check_equal(exploding_barrel.hurtbox.radius, 7.0, "its hurt circle")
	check_equal(exploding_barrel.footprint.size, Vector2(14.0, 8.0), "its ground")
	check_equal(exploding_barrel.caster.staff_count, 2, "its two staffs")
	check_equal(_state(exploding_barrel), &"idle", "in its first state")
	check(exploding_barrel.downable, "its 0 health is its own")
	check(exploding_barrel.rest_leaf() != null, "a fresh prop rests (props W2)")


# --- The exploding barrel -----------------------------------------------------------------

func test_fire_lights_the_fuse_and_a_second_later_it_blows() -> void:
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	var near: Actor = _dummy(Vector2(24.0, 0.0))
	_light(exploding_barrel)
	check_equal(_state(exploding_barrel), &"fusing", "fire lights it")
	check(exploding_barrel.caster.is_winding(FUSE), "its fuse burns")
	check_equal(_changes, [[exploding_barrel.id, &"fusing"]], "the bus is told")
	_world.run(FUSE_STEPS)
	check_equal(_state(exploding_barrel), &"broken", "the fuse burnt out: it blew")
	check_equal(_blasts(exploding_barrel, FUSE), 1, "once")
	check(near.health.health < near.health.max_health, "the blast hurt what stood near")
	check(not exploding_barrel.hurtbox.registered, "rubble cannot be hit")
	check(not exploding_barrel.footprint.solid, "nor blocks")
	check(not exploding_barrel.is_dying(), "it stays, as rubble")


func test_a_lit_exploding_barrel_shot_blows_at_once_and_its_fuse_no_more() -> void:
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	var near: Actor = _dummy(Vector2(24.0, 0.0))
	_light(exploding_barrel)
	check_equal(_state(exploding_barrel), &"fusing", "lit")
	_world.combat.hit(ActorsScript.NONE, exploding_barrel, 100.0)
	check_equal(_state(exploding_barrel), &"broken", "shot while lit: it blows now")
	check_equal(_blasts(exploding_barrel, BLAST), 1, "with its blast")
	check(not exploding_barrel.caster.is_winding(FUSE), "its fuse is out")
	_world.run(2)
	check(near.health.health < near.health.max_health, "the blast hurt what stood near")
	_world.run(FUSE_STEPS)
	check_equal(_blasts(exploding_barrel, FUSE), 0, "the fuse never goes off")
	check_equal(_blasts(exploding_barrel, BLAST), 1, "nothing blows twice")


func test_an_exploding_barrel_shot_apart_blows_at_once() -> void:
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	var near: Actor = _dummy(Vector2(24.0, 0.0))
	_world.combat.hit(ActorsScript.NONE, exploding_barrel, 100.0)
	check_equal(_state(exploding_barrel), &"broken", "shot apart")
	check_equal(_blasts(exploding_barrel, BLAST), 1, "it blew")
	_world.run(2)
	check(near.health.health < near.health.max_health, "and hurt what stood near")
	check_equal(_changes, [[exploding_barrel.id, &"broken"]], "one change of state")


func test_a_possessed_exploding_barrel_pressing_two_blows_and_one_lights_its_fuse() -> void:
	var driver := Fixture.Scripted.new()
	var wizard: Actor = _world.actor(Vector2(-80.0, 0.0), [&"health", &"hurtbox"], driver)
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	check(Possession.begin(wizard, exploding_barrel, 30.0) != null, "possessed")
	driver.presses.append(BLAST)
	_world.run(1)
	check_equal(_state(exploding_barrel), &"broken", "pressing 2 blows it")
	var other: Actor = _prop(EXPLODING_BARREL, Vector2(0.0, 80.0))
	check(Possession.begin(wizard, other, 30.0) != null, "the next one possessed")
	driver.presses.append(FUSE)
	_world.run(1)
	check_equal(_state(other), &"idle", "pressing 1 lights its fuse the long way (its idle state hears the fuse leave)")
	check(other.caster.is_winding(FUSE), "the fuse burns")
	_world.run(FUSE_STEPS)
	check_equal(_state(other), &"broken", "and it blows")


func test_a_blown_exploding_barrel_ends_its_possession() -> void:
	var driver := Fixture.Scripted.new()
	var wizard: Actor = _world.actor(Vector2(-80.0, 0.0), [&"health", &"hurtbox"], driver)
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	check(Possession.begin(wizard, exploding_barrel, 30.0) != null, "possessed")
	_world.combat.hit(ActorsScript.NONE, exploding_barrel, 100.0)
	check(exploding_barrel.possessed_by == null, "its death ends the possession")
	check(wizard.controller == driver, "the driver is home")
	check_equal(_world.table.team_of(exploding_barrel.id), ActorsScript.TEAM_WORLD, "the rubble is the world's")


## Regression (review of W6): a change of driver ended every wind-up, so possessing a lit exploding barrel
## put its fuse out for good and it never blew.
func test_a_lit_exploding_barrel_possessed_still_blows() -> void:
	var driver := Fixture.Scripted.new()
	var wizard: Actor = _world.actor(Vector2(-80.0, 0.0), [&"health", &"hurtbox"], driver)
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	_light(exploding_barrel)
	check(exploding_barrel.caster.is_winding(FUSE), "lit")
	check(Possession.begin(wizard, exploding_barrel, 0.25) != null, "possessed")
	check(exploding_barrel.caster.is_winding(FUSE), "the fuse is the exploding barrel's own: a new driver does not put it out")
	_world.run(FUSE_STEPS)
	check(exploding_barrel.possessed_by == null, "the possession ran out")
	check_equal(_state(exploding_barrel), &"broken", "and the fuse blew")


func test_a_possessors_own_wind_up_ends_with_its_possession() -> void:
	var driver := Fixture.Scripted.new()
	var wizard: Actor = _world.actor(Vector2(-80.0, 0.0), [&"health", &"hurtbox"], driver)
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	var possession: Possession = Possession.begin(wizard, exploding_barrel, 30.0)
	driver.presses.append(FUSE)
	_world.run(1)
	check(exploding_barrel.caster.is_winding(FUSE), "the driver lit the fuse")
	possession.end()
	check(not exploding_barrel.caster.is_winding(FUSE), "its cast was the driver's: it ends with the driver (cast timing)")


## Regression (review of W6): a `cast` row that casts the staff it hears cast it again before the
## first cast was counted, sixteen deep.
func test_a_cast_row_does_not_cast_the_staff_that_is_leaving() -> void:
	var again: PropTrigger = PropTrigger.make(PropTrigger.When.CAST, 2)
	again.staff = 2
	var rows: Array[PropTrigger] = [PropTrigger.make(PropTrigger.When.DEATH, 2), again]
	var body: Actor = _prop(_made([PropState.make(&"idle", rows)]))
	_world.combat.hit(ActorsScript.NONE, body, 100.0)
	check_equal(_blasts(body, BLAST), 1, "one blast, not one a moment deep")


## Regression (review of W6): Combat told the body its reaction before the reaction's effect, so a
## prop that stops being hittable on it left the effect undone.
func test_a_prop_that_breaks_on_a_reaction_still_takes_it() -> void:
	var row: ReactionRow = null
	for candidate: ReactionRow in CombatScript.REACTIONS.rows:
		if candidate.effect == ReactionRow.Effect.CONSUME and candidate.damage > 0:
			row = candidate
			break
	check(row != null, "a reaction that deals damage")
	if row == null:
		return
	var breaks: PropTrigger = PropTrigger.make(PropTrigger.When.REACTION, 0, &"broken")
	breaks.reaction = row.reaction_id
	var data: PropBase = _made([PropState.make(&"idle", [breaks] as Array[PropTrigger]), PropState.make(&"broken", [] as Array[PropTrigger], false, false)], 1000.0)
	var body: Actor = _prop(data)
	check(_world.combat.apply_status(ActorsScript.NONE, body, row.status_id, 3.0, 50.0), "its status")
	var taken: Array[float] = []
	body.damaged.connect(func(_by: int, amount: float, _element: StringName) -> void: taken.append(amount))
	var shooter: Actor = _world.actor(body.global_position + Vector2(-40.0, -8.0), [&"caster"], Fixture.Scripted.new(), [[row.element_id, &"bolt"]])
	shooter.aim = Vector2.RIGHT
	check(shooter.caster.cast(0), "a bolt of the element that reacts with it")
	_world.run(20)
	check_equal(_state(body), &"broken", "it broke on %s" % row.reaction_id)
	check(taken.size() >= 2, "the bolt's hit and then the reaction's own damage: %s" % [taken])


func test_two_props_on_one_set_of_states_react_apart() -> void:
	# The states are a file of their own (`exploding_barrel_states.tres`), which a big exploding barrel may share.
	var big := EXPLODING_BARREL.duplicate() as PropBase
	big.max_health = 40.0
	check(big.states == EXPLODING_BARREL.states, "one set of states")
	var small: Actor = _prop(EXPLODING_BARREL)
	var other: Actor = _prop(big, Vector2(200.0, 0.0))
	_world.combat.hit(ActorsScript.NONE, small, 100.0)
	check_equal([_state(small), _state(other)], [&"broken", &"idle"], "each body keeps its own state")


func test_three_exploding_barrels_set_each_other_off() -> void:
	var first: Actor = _prop(EXPLODING_BARREL)
	var second: Actor = _prop(EXPLODING_BARREL, Vector2(20.0, 0.0))
	var third: Actor = _prop(EXPLODING_BARREL, Vector2(40.0, 0.0))
	var far: Actor = _prop(EXPLODING_BARREL, Vector2(300.0, 0.0))
	_world.combat.hit(ActorsScript.NONE, first, 100.0)
	_world.run(FUSE_STEPS * 2)
	check_equal([_state(first), _state(second), _state(third)], [&"broken", &"broken", &"broken"], "the blasts ran down the row")
	check_equal(_state(far), &"idle", "an exploding barrel out of reach stands")


# --- The rule ---------------------------------------------------------------------

## A prop of `states` (code-made) with the exploding barrel's staffs and `health`.
func _made(states: Array[PropState], health: float = 10.0, invincible: bool = false) -> PropBase:
	var data := PropBase.new()
	data.id = &"made"
	data.scene = EXPLODING_BARREL.scene
	data.max_health = health
	data.invincible = invincible
	data.staffs = EXPLODING_BARREL.staffs.duplicate()
	data.states = PropStates.make(states)
	return data


## A row heard on a fire hit of at least `at_least`.
func _on_fire(at_least: float, cast: int, then: StringName = &"") -> PropTrigger:
	var row: PropTrigger = PropTrigger.make(PropTrigger.When.ELEMENT_HIT, cast, then)
	row.element = &"fire"
	row.at_least = at_least
	return row


func test_one_hit_fires_every_trigger_that_hears_it_and_the_first_then_wins() -> void:
	var rows: Array[PropTrigger] = [_on_fire(0.0, 0, &"lit"), _on_fire(1.0, 1, &"cracked"), _on_fire(1000.0, 2, &"never")]
	var data: PropBase = _made([PropState.make(&"idle", rows), PropState.make(&"lit"), PropState.make(&"cracked"), PropState.make(&"never")], 1000.0)
	var body: Actor = _prop(data)
	_light(body)
	check_equal(_state(body), &"lit", "the first then sets the state")
	check(body.caster.is_winding(FUSE), "the second row cast its staff too, and entering the state keeps its wind-up")
	check_equal(_blasts(body, BLAST), 0, "a row the hit is too weak for fires not")
	check_equal(_changes.size(), 1, "the state changed once")


func test_leaving_a_state_ends_the_wind_ups_it_cast() -> void:
	var rows: Array[PropTrigger] = [_on_fire(0.0, 1), PropTrigger.make(PropTrigger.When.DEATH, 0, &"out")]
	var data: PropBase = _made([PropState.make(&"idle", rows), PropState.make(&"out")])
	var body: Actor = _prop(data)
	_light(body)
	check(body.caster.is_winding(FUSE), "its fire row lit the fuse")
	_world.combat.hit(ActorsScript.NONE, body, 100.0)
	check_equal(_state(body), &"out", "its death moved it on")
	check(not body.caster.is_winding(FUSE), "and the fuse of the state it left is out")


func test_a_gone_state_frees_the_body_after_its_entered_triggers() -> void:
	var rows: Array[PropTrigger] = [PropTrigger.make(PropTrigger.When.DEATH, 0, &"gone")]
	var entered: Array[PropTrigger] = [PropTrigger.make(PropTrigger.When.ENTERED, 2)]
	var data: PropBase = _made([PropState.make(&"idle", rows), PropState.make(&"gone", entered, false, false, true)])
	var body: Actor = _prop(data)
	_world.combat.hit(ActorsScript.NONE, body, 100.0)
	check_equal(_blasts(body, BLAST), 1, "its entered trigger cast first")
	check(body.is_dying(), "then it is gone")


func test_death_with_no_death_trigger_leaves_it_standing() -> void:
	var data: PropBase = _made([PropState.make(&"idle")])
	var body: Actor = _prop(data)
	_world.combat.hit(ActorsScript.NONE, body, 100.0)
	check_equal(body.health.health, 0.0, "its health is empty")
	check(not body.is_dying(), "and it stands")
	check(body.is_inside_tree(), "in the room")


func test_an_invincible_prop_reacts_and_keeps_its_health() -> void:
	var rows: Array[PropTrigger] = [_on_fire(0.0, 0, &"lit")]
	var lit: Array[PropTrigger] = [PropTrigger.make(PropTrigger.When.DEATH, 0, &"idle")]
	var data: PropBase = _made([PropState.make(&"idle", rows), PropState.make(&"lit", lit)], 5.0, true)
	var body: Actor = _prop(data)
	_light(body)
	check_equal(_state(body), &"lit", "its hits still land: fire lights it")
	_world.combat.hit(ActorsScript.NONE, body, 100.0)
	check_equal(body.health.health, 5.0, "no hit takes its health")
	check_equal(_state(body), &"lit", "so it never dies")


func test_health_below_fires_on_the_hit_that_crosses_it() -> void:
	var row: PropTrigger = PropTrigger.make(PropTrigger.When.HEALTH_BELOW, 2)
	row.share = 0.5
	var data: PropBase = _made([PropState.make(&"idle", [row] as Array[PropTrigger])], 10.0)
	var body: Actor = _prop(data)
	_world.combat.hit(ActorsScript.NONE, body, 4.0)
	check_equal(_blasts(body, BLAST), 0, "above half: nothing")
	_world.combat.hit(ActorsScript.NONE, body, 2.0)
	check_equal(_blasts(body, BLAST), 1, "the hit that took it below half")
	_world.combat.hit(ActorsScript.NONE, body, 1.0)
	check_equal(_blasts(body, BLAST), 1, "only that one")


func test_a_status_put_on_it_is_a_moment() -> void:
	var burn: PropTrigger = PropTrigger.make(PropTrigger.When.STATUS, 0, &"burning")
	burn.status = &"burn"
	var data: PropBase = _made([PropState.make(&"idle", [burn] as Array[PropTrigger]), PropState.make(&"burning")], 1000.0)
	var body: Actor = _prop(data)
	check(_world.combat.apply_status(ActorsScript.NONE, body, &"chill", 3.0, 10.0), "chilled")
	check_equal(_state(body), &"idle", "another status: nothing")
	check(_world.combat.apply_status(ActorsScript.NONE, body, &"burn", 3.0, 1.0), "burnt")
	check_equal(_state(body), &"burning", "its status")


func test_a_reaction_between_statuses_on_it_is_a_moment() -> void:
	var row: ReactionRow = CombatScript.REACTIONS.rows[0]
	var reacted: PropTrigger = PropTrigger.make(PropTrigger.When.REACTION, 0, &"reacted")
	reacted.reaction = row.reaction_id
	var body: Actor = _prop(_made([PropState.make(&"idle", [reacted] as Array[PropTrigger]), PropState.make(&"reacted")], 1000.0))
	check(_world.combat.apply_status(ActorsScript.NONE, body, row.status_id, 3.0, 50.0), "its status")
	var shooter: Actor = _world.actor(body.global_position + Vector2(-40.0, -8.0), [&"caster"], Fixture.Scripted.new(), [[row.element_id, &"bolt"]])
	shooter.aim = Vector2.RIGHT
	check(shooter.caster.cast(0), "a bolt of the element that reacts with it")
	_world.run(20)
	check_equal(_state(body), &"reacted", "Combat's %s on it" % row.reaction_id)


# --- Problems ---------------------------------------------------------------------

func test_problems_name_what_is_wrong() -> void:
	var data := PropBase.new()
	data.id = &"bad"
	var empty: String = "\n".join(data.problems())
	check(empty.contains("no scene") and empty.contains("no states"), "no scene, no states: %s" % empty)
	var stray: PropTrigger = _on_fire(0.0, 3, &"nowhere")
	stray.element = &"custard"
	var loop_a: Array[PropTrigger] = [PropTrigger.make(PropTrigger.When.ENTERED, 0, &"b")]
	var loop_b: Array[PropTrigger] = [PropTrigger.make(PropTrigger.When.ENTERED, 0, &"a")]
	data.staffs = EXPLODING_BARREL.staffs.duplicate()
	data.states = PropStates.make([PropState.make(&"idle", [stray] as Array[PropTrigger]), PropState.make(&"a", loop_a), PropState.make(&"b", loop_b), PropState.make(&"idle")])
	var found: String = "\n".join(data.problems(_known()))
	check(found.contains("staff 3"), "a staff it does not hold: %s" % found)
	check(found.contains("'nowhere'"), "a state it does not have")
	check(found.contains("custard"), "an element nobody knows")
	check(found.contains("for ever"), "entered triggers that go round")
	check(found.contains("two states are named 'idle'"), "a name twice")


# --- State ------------------------------------------------------------------------

func test_its_state_is_state() -> void:
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	var triggers: PropStateTriggers = exploding_barrel.state_triggers
	check(triggers.at_rest(), "fresh, it rests")
	_light(exploding_barrel)
	check(not triggers.at_rest(), "lit, it is walked member by member")
	check(exploding_barrel.rest_leaf() == null, "and its body too")
	var walk := StateWalk.new()
	var paths: Dictionary = {}
	walk.walk("actor", exploding_barrel, func(path: String, value: Variant) -> void: paths[path] = value)
	check(walk.problems.is_empty(), "its body can be walked: %s" % [walk.problems])
	check_equal(paths.get("actor.state_triggers.state"), 1, "its state is in its body's walk (the hash, a snapshot): %s" % [paths.keys()])


func _areas() -> Dictionary:
	var areas: Dictionary = {"Actors": _world.table, "Projectiles": _world.projectiles, "Spells": _world.spells, "Combat": _world.combat}
	for body in _world.actors:
		if is_instance_valid(body) and body.is_inside_tree() and body.id != ActorsScript.NONE:
			areas["actor %d" % body.id] = body
	return areas


func test_a_snapshot_rolls_a_prop_back_to_its_state() -> void:
	var exploding_barrel: Actor = _prop(EXPLODING_BARREL)
	_light(exploding_barrel)
	check_equal(_state(exploding_barrel), &"fusing", "lit")
	var snapshot := Snapshot.take(_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	_world.combat.hit(ActorsScript.NONE, exploding_barrel, 100.0)
	check_equal(_state(exploding_barrel), &"broken", "blown since")
	check_equal(snapshot.restore(_areas(), root, func(body: Node) -> void: _world.add(body as Actor, (body as Actor).position)), PackedStringArray(), "restored without problems")
	check(is_instance_valid(exploding_barrel), "restored in place")
	check_equal(_state(exploding_barrel), &"fusing", "lit again")
	check(exploding_barrel.hurtbox.registered and exploding_barrel.footprint.solid, "standing again: hit and blocking")
	check(exploding_barrel.caster.is_winding(FUSE), "its fuse burns again")
	_world.run(FUSE_STEPS)
	check_equal(_state(exploding_barrel), &"broken", "and it blows as it did")
