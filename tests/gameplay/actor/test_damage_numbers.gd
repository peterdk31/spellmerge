extends "res://tests/support/suite.gd"
## Damage numbers on every actor (props W5, docs/milestones/props.md): every actor has one
## `DamageNumbers` look (its scene's own, else one the actor adds; never two), and it tells each of
## its actor's hits on the bus (`damage_number_shown`): where it starts (above its hurt shape, a
## circle's or a box's), the amount, the hit's element, its kind (`hit`, `heal`, `spared` for an
## invincible actor) and the look's own numbers. Feel's drawer is tested in
## tests/gameplay/feel/test_damage_number_drawer.gd.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_damage_numbers.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ActorScript := preload("res://gameplay/actor/actor.gd")
## The folders whose scenes are actors (an actor scene is found there by its root, so a new one is
## checked too).
const ACTOR_FOLDERS: Array[String] = ["res://content"]

var _world: Fixture
## Every `damage_number_shown` sent, as its arguments.
var _shown: Array[Array] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_shown.clear()
	_world.bus.damage_number_shown.connect(_on_shown)


func after_each() -> void:
	_world.free_all()


func _on_shown(actor: int, position: Vector2, amount: float, element: StringName, kind: StringName, rise: float, seconds: float, size: float) -> void:
	_shown.append([actor, position, amount, element, kind, rise, seconds, size])


func _numbers_in(body: Node) -> int:
	var count: int = 0
	for child in body.get_children():
		if child is DamageNumbers:
			count += 1
	return count


func test_every_actor_has_one_added_when_its_scene_has_none() -> void:
	var body: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox"])
	check(body.damage_numbers != null, "the actor added one")
	check_equal(_numbers_in(body), 1, "one")
	check(body.damage_numbers.actor == body, "set up for it")


func test_a_scenes_own_is_used_not_doubled() -> void:
	var body := Actor.new()
	body.add_child(Health.new())
	body.add_child(Hurtbox.new())
	var own_numbers := DamageNumbers.new()
	own_numbers.text_size = 2.0
	own_numbers.rise = 30.0
	body.add_child(own_numbers)
	_world.add(body, Vector2.ZERO)
	check(body.damage_numbers == own_numbers, "its own")
	check_equal(_numbers_in(body), 1, "and no second")
	_world.combat.hit(0, body, 5.0)
	check_equal(_shown.size(), 1, "a hit shows a number")
	check_equal(_shown[0][5], 30.0, "its rise")
	check_equal(_shown[0][7], 2.0, "its size")


func test_a_hit_is_told_from_above_the_hurt_circle() -> void:
	var body: Actor = _world.actor(Vector2(40.0, 60.0), [&"health", &"hurtbox"])
	_world.combat.hit(3, body, 7.5)
	check_equal(_shown.size(), 1, "one number")
	var row: Array = _shown[0]
	check_equal(row[0], body.id, "of this actor")
	var top: float = body.hurtbox.offset.y - body.hurtbox.radius - body.damage_numbers.lift
	check_equal(row[1], Vector2(40.0, 60.0 + top), "above the top of its hurt circle")
	check_equal(row[2], 7.5, "the amount")
	check_equal(row[3], &"", "a plain hit")
	check_equal(row[4], Fixture.EventsScript.NUMBER_HIT, "a hit")
	check_equal(row[6], body.damage_numbers.seconds, "the look's seconds")


func test_a_box_starts_above_its_top() -> void:
	var body := Fixture.prop_body()
	var box: Hurtbox = null
	for child in body.get_children():
		if child is Hurtbox:
			box = child as Hurtbox
	box.size = Vector2(40.0, 24.0)
	box.offset = Vector2(0.0, -12.0)
	_world.add(body, Vector2(100.0, 100.0))
	_world.combat.hit(0, body, 4.0)
	check_equal(_shown.size(), 1, "the prop shows its hit, though nothing steps it")
	check_equal(_shown[0][1], Vector2(100.0, 100.0 - 12.0 - 12.0 - body.damage_numbers.lift), "above the box")


func test_the_hits_element_is_told() -> void:
	var target: Actor = _world.actor(Vector2(80.0, 0.0), [&"health", &"hurtbox"])
	var brain := Fixture.Scripted.new()
	brain.team = ActorsScript.TEAM_WIZARDS
	brain.aim = Vector2.RIGHT
	var shooter: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"caster"], brain, [[&"fire", &"bolt"]])
	_world.run(1)
	check(shooter.caster.cast(0), "cast")
	_world.run(16)
	var hits: Array = _shown.filter(func(row: Array) -> bool: return row[0] == target.id)
	check(not hits.is_empty(), "the target shows its hit")
	if not hits.is_empty():
		check_equal(hits[0][3], &"fire", "in fire")


func test_a_heal_is_told_as_one_and_only_what_it_gave() -> void:
	var brain := Fixture.Scripted.new()
	brain.team = ActorsScript.TEAM_WIZARDS
	var friend: Actor = _world.actor(Vector2(80.0, 0.0), [&"health", &"hurtbox"], brain)
	_world.combat.hit(0, friend, 2.0)
	_shown.clear()
	var healer_brain := Fixture.Scripted.new()
	healer_brain.team = ActorsScript.TEAM_WIZARDS
	healer_brain.aim = Vector2.RIGHT
	var healer: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"caster"], healer_brain, [[&"mend", &"bolt"]])
	_world.run(1)
	check(healer.caster.cast(0), "cast")
	_world.run(16)
	var heals: Array = _shown.filter(func(row: Array) -> bool: return row[0] == friend.id)
	check_equal(heals.size(), 1, "one number")
	if heals.size() == 1:
		check_equal(heals[0][4], Fixture.EventsScript.NUMBER_HEAL, "a heal")
		check_equal(heals[0][2], 2.0, "what it gave: the 2 it lacked")


func test_heals_can_be_left_out() -> void:
	var body: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox"])
	body.damage_numbers.heals = false
	body.health.take(5.0)
	body.healed.emit(0, 5.0)
	check(_shown.is_empty(), "no heal shown")
	body.damage_numbers.heals = true
	body.healed.emit(0, 5.0)
	check_equal(_shown.size(), 1, "shown again when on")


func test_an_invincible_actors_hit_is_spared() -> void:
	var body: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox"])
	body.health.invincible = true
	_world.combat.hit(0, body, 9.0)
	check_equal(body.health.health, body.health.max_health, "it took nothing")
	check_equal(_shown.size(), 1, "but its number shows")
	if _shown.size() == 1:
		check_equal(_shown[0][4], Fixture.EventsScript.NUMBER_SPARED, "as spared")
		check_equal(_shown[0][2], 9.0, "with what it would have taken")


## Every actor scene in the content folders (found by folder) has exactly one once set up.
func test_every_actor_scene_has_one() -> void:
	var scenes: PackedStringArray = PackedStringArray()
	for folder in ACTOR_FOLDERS:
		_scenes_in(folder, scenes)
	var actors: int = 0
	for path in scenes:
		var scene := load(path) as PackedScene
		if scene == null or not _is_actor_scene(scene):
			continue
		actors += 1
		var body: Actor = _world.add(scene.instantiate() as Actor, Vector2.ZERO)
		check(body.damage_numbers != null and body.damage_numbers.actor == body, "%s has its numbers" % path)
		check_equal(_numbers_in(body), 1, "%s has one" % path)
	check(actors >= 5, "the actor scenes were found: %d" % actors)


## Whether the scene's root runs the actor script (or one made from it).
static func _is_actor_scene(scene: PackedScene) -> bool:
	var state: SceneState = scene.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) != &"script":
			continue
		var script := state.get_node_property_value(0, i) as Script
		while script != null:
			if script == ActorScript:
				return true
			script = script.get_base_script()
	return false


func _scenes_in(folder: String, into: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".tscn"):
			into.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		_scenes_in(folder.path_join(sub), into)
