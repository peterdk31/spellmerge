extends RefCounted
## The scripted scenes the determinism tests play (online-ready N1): each is built fresh, stepped by
## hand one tick at a time, and hands its areas by name for `SimHash`, `Desync` and `StateWalk`.
##
## - `fight`: three staffed enemies with brains (fire bolts and frost novas, the enemy tests'
##   exact profile) against two wizards, on the enemy tests' world (tests/gameplay/ai/ai_fixture.gd).
## - `storm`: a frost nova split, a fire chain and a homing lightning bolt (aimed away, so it picks a
##   target and keeps it: by key since N5) cast on three imps, on the clip stage
##   (tests/clips/stage.gd): the spell runtime, the projectile manager, Combat and Feel.
## - `possessed`: the fight with the first enemy's controller possessing both wizards (actors G9):
##   it drives the first and a puppet added in play drives the second; every body steps.
##
##     var scene := SimScenes.new(root, &"fight")
##     for i in 60:
##         scene.step()
##         desync.capture(scene.areas())
##     scene.free_all()

const AIFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const StageScript := preload("res://tests/clips/stage.gd")

const NAMES: Array[StringName] = [&"fight", &"storm", &"possessed"]
## The fight's staffs (card ids by slot, one row a staff).
const FIGHT_STAFFS: Array = [["fire", "bolt"], ["frost", "nova", "bolt"]]
## How long the possessed scene's possessions last (past its ticks).
const POSSESSED_SECONDS: float = 60.0
const STORM: Dictionary = {
	"id": "sim_storm",
	"casts": [
		{"player": 0, "staff": 0, "cards": ["split", "frost", "nova", "bolt"], "at": 0.0, "origin": Vector2(-80.0, 0.0), "aim": Vector2.RIGHT},
		{"player": 1, "staff": 0, "cards": ["chain", "fire", "bolt"], "at": 0.5, "origin": Vector2(-80.0, 40.0), "aim": Vector2.RIGHT},
		{"player": 2, "staff": 0, "cards": ["homing", "lightning", "bolt"], "at": 0.2, "origin": Vector2(-60.0, -60.0), "aim": Vector2.UP},
	],
	"imps": [Vector2(40.0, -20.0), Vector2(60.0, 20.0), Vector2(90.0, 0.0)],
}

var name: StringName
var _root: Node
var _fight: AIFixture = null
var _stage: StageScript = null


func _init(root: Node, scene: StringName) -> void:
	name = scene
	_root = root
	match scene:
		&"fight", &"possessed":
			_fight = AIFixture.new(root, 2)
			for i in 3:
				_fight.staffed_enemy(FIGHT_STAFFS, Vector2(160.0 + 40.0 * i, 60.0 * i))
			if scene == &"possessed":
				for wizard in _fight.players:
					if Possession.begin(_fight.enemies[0], wizard, POSSESSED_SECONDS) == null:
						push_error("SimScenes: the possession did not start")
		&"storm":
			_stage = StageScript.new(root, root.get_node_or_null("Registry"))
			if not _stage.start(STORM):
				push_error("SimScenes: the storm's staffs cast nothing")
		_:
			push_error("SimScenes: no scene %s" % scene)


## One tick of the scene.
func step() -> void:
	if _fight != null and name == &"possessed":
		# The wizards step too: a possessed one is driven by the enemy's controller or its puppet.
		for wizard in _fight.players:
			if is_instance_valid(wizard) and wizard.is_inside_tree():
				wizard.step(AIFixture.STEP)
				wizard.position += wizard.velocity * AIFixture.STEP
		_fight.run_all(1)
	elif _fight != null:
		_fight.run_all(1)
	elif _stage != null:
		_stage.tick()


## The scene's areas, by name: its services and every actor's body by actor id (from the actor
## table, as `Tick.state_areas` finds them).
func areas() -> Dictionary:
	if _fight != null:
		return _fight.areas({"board": _fight.board})
	if _stage != null:
		return {"actors": _stage.actors, "projectiles": _stage.projectiles, "spells": _stage.spells, "combat": _stage.combat}
	return {}


## Makes this scene as `snapshot` says (online-ready N10): its bodies made again with the scene's
## services, and the scene's own lists of them found again. Its input goes on as `input_from`'s
## (the scene the snapshot was taken from, at that tick: the stage's casts still to come), as a
## replay's frames go on after a snapshot in the game. Returns the snapshot's problems.
func restore(snapshot: Snapshot, input_from: Object = null) -> PackedStringArray:
	if _stage != null and input_from != null and input_from.get(&"_stage") != null:
		var played: StageScript = input_from.get(&"_stage")
		_stage.time = played.time
		_stage.set(&"_pending", (played.get(&"_pending") as Array).duplicate(true))
	if _fight != null:
		var problems: PackedStringArray = snapshot.restore(areas(), _root, func(body: Node) -> void: _fight.wire(body as Actor))
		_fight.regather()
		return problems
	if _stage != null:
		return snapshot.restore(areas(), world())
	return PackedStringArray()


## A stand-in for this scene's input as it is now (the stage's clock and casts to come), for
## `restore`'s `input_from`; it holds no world.
func input_copy() -> Object:
	var copy := InputCopy.new()
	if _stage != null:
		copy._stage = StageScript.new(_root, null)
		copy._stage.time = _stage.time
		copy._stage.set(&"_pending", (_stage.get(&"_pending") as Array).duplicate(true))
	return copy


class InputCopy:
	extends RefCounted
	var _stage: Object = null


## Changes the fight's world as no snapshot says (for a restore to undo): the first enemy still
## standing dies, and an imp joins.
func disturb() -> void:
	if _fight == null:
		return
	for body in _fight.enemies:
		if is_instance_valid(body) and not body.is_dying():
			body.die(-1)
			break
	_fight.imp(Vector2(400.0, 400.0))


## The world the scene's bodies are under.
func world() -> Node:
	if _stage != null:
		return _stage.world
	return _root


func free_all() -> void:
	if _fight != null:
		_fight.free_all()
	if _stage != null:
		_stage.free_all()
	_fight = null
	_stage = null
