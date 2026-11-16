extends RefCounted
## A boss with an intro, for the tests and the filmstrip of the boss intro (docs/milestones/boss-intro.md,
## step BI4): the imp's body as a boss, standing still and casting nothing, with an intro of its own
## whose portrait is a stand-in (`intro_boss/portrait.svg`, drawn from its grid by
## tools/pixel_grid.py). Nothing of the game's content changes; `register` adds it under its own id.
##
##     var data: EnemyBase = IntroBoss.make(registry)
##     IntroBoss.register(registry, data, biome)

const PORTRAIT: Texture2D = preload("res://tests/support/intro_boss/portrait.svg")
const ID: StringName = &"test_overlay_boss"
const NAME: String = "The Stand-in"
const LORE: String = "It was drawn for the tests."
const LINES: Array[String] = ["You will not pass this test.", "Nobody ever passes this test."]


## The boss's data: the imp of `registry` as a boss of `biome`, with `lines` (none: "Fight").
static func make(registry: Node, biome: StringName = &"test_overlay_lair", lines: Array[String] = LINES) -> EnemyBase:
	var data: EnemyBase = (registry.call("get_resource", &"enemies", &"ember_imp") as EnemyBase).duplicate() as EnemyBase
	data.id = ID
	data.display_name = NAME
	data.lore = LORE
	data.boss = true
	data.biomes = [biome] as Array[StringName]
	data.max_health = 1000.0
	data.staffs = [] as Array[StaffCards]
	data.phases = [] as Array[EnemyPhase]
	data.boss_intro = intro(lines)
	return data


## Its intro: the stand-in portrait, `lines`, the Spark ramp and the shared reveal cue.
static func intro(lines: Array[String] = LINES) -> BossIntro:
	var made := BossIntro.new()
	made.portrait = PORTRAIT
	made.lines = lines.duplicate()
	made.accent = &"spark"
	return made


## Register `data` as a boss in `registry` (once: a second call changes nothing).
static func register(registry: Node, data: EnemyBase) -> void:
	if registry.call("get_resource", &"bosses", data.id) == null:
		registry.call("add", &"bosses", data)
