extends RefCounted
## The scripted scenes the determinism tests play (online-ready N1): each is built fresh, stepped by
## hand one tick at a time, and hands its areas by name for `SimHash`, `Desync` and `StateWalk`.
##
## - `fight`: three staffed enemies with brains (fire bolts and frost novas, the enemy tests'
##   exact profile) against two wizards, on the enemy tests' world (tests/gameplay/ai/ai_fixture.gd).
## - `storm`: a frost nova split, a fire chain and a homing lightning bolt (aimed away, so it picks a
##   target and keeps it: by key since N5) cast on three imps, on the clip stage
##   (tests/clips/stage.gd): the spell runtime, the projectile manager, Combat and Feel.
## - `horde`: a horde wave of made-up swarmers round one wizard (tests/gameplay/horde/horde_fixture.gd).
##
##     var scene := SimScenes.new(root, &"fight")
##     for i in 60:
##         scene.step()
##         desync.capture(scene.areas())
##     scene.free_all()

const AIFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const StageScript := preload("res://tests/clips/stage.gd")
const HordeFixture := preload("res://tests/gameplay/horde/horde_fixture.gd")

const NAMES: Array[StringName] = [&"fight", &"storm", &"horde"]
## The fight's staffs (card ids by slot, one row a staff).
const FIGHT_STAFFS: Array = [["fire", "bolt"], ["frost", "nova"]]
const STORM: Dictionary = {
	"id": "sim_storm",
	"casts": [
		{"player": 0, "staff": 0, "cards": ["split", "frost", "nova"], "at": 0.0, "origin": Vector2(-80.0, 0.0), "aim": Vector2.RIGHT},
		{"player": 1, "staff": 0, "cards": ["chain", "fire", "bolt"], "at": 0.5, "origin": Vector2(-80.0, 40.0), "aim": Vector2.RIGHT},
		{"player": 2, "staff": 0, "cards": ["homing", "lightning", "bolt"], "at": 0.2, "origin": Vector2(-60.0, -60.0), "aim": Vector2.UP},
	],
	"imps": [Vector2(40.0, -20.0), Vector2(60.0, 20.0), Vector2(90.0, 0.0)],
}

var name: StringName
var _fight: AIFixture = null
var _stage: StageScript = null
var _horde: HordeFixture = null


func _init(root: Node, scene: StringName) -> void:
	name = scene
	match scene:
		&"fight":
			_fight = AIFixture.new(root, 2)
			for i in 3:
				_fight.staffed_enemy(FIGHT_STAFFS, Vector2(160.0 + 40.0 * i, 60.0 * i))
		&"storm":
			_stage = StageScript.new(root, root.get_node_or_null("Registry"))
			if not _stage.start(STORM):
				push_error("SimScenes: the storm's staffs cast nothing")
		&"horde":
			_horde = HordeFixture.new(root, [0] as Array[int])
			root.add_child(_horde.world)
			_horde.start()
		_:
			push_error("SimScenes: no scene %s" % scene)


## One tick of the scene.
func step() -> void:
	if _fight != null:
		_fight.run_all(1)
	elif _stage != null:
		_stage.tick()
	elif _horde != null:
		_horde.director.step(1.0 / 60.0)


## The scene's areas, by name: its services and every actor's body by actor id.
func areas() -> Dictionary:
	if _fight != null:
		var out: Dictionary = {"actors": _fight.actors, "projectiles": _fight.projectiles, "spells": _fight.spells, "combat": _fight.combat, "board": _fight.board}
		var bodies: Array[Actor] = []
		for body in _fight.players + _fight.enemies:
			if is_instance_valid(body):
				bodies.append(body)
		bodies.sort_custom(func(a: Actor, b: Actor) -> bool: return a.id < b.id)
		for body in bodies:
			out["actor %d" % body.id] = body
		return out
	if _stage != null:
		return {"actors": _stage.actors, "projectiles": _stage.projectiles, "spells": _stage.spells, "combat": _stage.combat}
	if _horde != null:
		return {"actors": _horde.actors, "horde": _horde.director, "gems": _horde.director.gems()}
	return {}


func free_all() -> void:
	if _fight != null:
		_fight.free_all()
	if _stage != null:
		_stage.free_all()
	if _horde != null:
		_horde.free_all()
	_fight = null
	_stage = null
	_horde = null
