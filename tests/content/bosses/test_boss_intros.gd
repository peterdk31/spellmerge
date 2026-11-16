extends "res://tests/support/suite.gd"
## Every boss's intro (docs/milestones/boss-intro.md, rule 1; `BossIntro.problems`): a portrait of
## three 96×96 frames, at most three lines, an accent that is a palette ramp and cues the game has
## (content/cues); and each kind of mistake named. Its lines' words are the story check's
## (tests/content/story/test_lore.gd).
##
## godot --headless --path . --script res://tests/content/bosses/test_boss_intros.gd

const RegistryScript := preload("res://core/registry/registry.gd")


func _registry() -> RegistryScript:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	return registry


static func _known_by(registry: RegistryScript) -> Callable:
	return func(cue: StringName) -> bool: return registry.get_resource(&"cues", cue) != null


static func _sheet(width: int, height: int) -> Texture2D:
	return ImageTexture.create_from_image(Image.create(width, height, false, Image.FORMAT_RGBA8))


static func _intro() -> BossIntro:
	var intro := BossIntro.new()
	intro.portrait = _sheet(BossIntro.FRAME * BossIntro.FRAMES, BossIntro.FRAME)
	intro.lines = ["What an awful smell of The Wizard.", "I must clean it up."] as Array[String]
	intro.accent = &"spark"
	return intro


func test_every_boss_intro_has_no_problem() -> void:
	var registry: RegistryScript = _registry()
	var known: Callable = _known_by(registry)
	for res: Resource in registry.get_all(&"bosses"):
		var data := res as EnemyBase
		if data == null or data.boss_intro == null:
			continue
		check_equal(data.boss_intro.problems(String(data.id), known), PackedStringArray(), "%s's intro" % data.id)
		check(data.boss, "%s: an intro is a boss's" % data.id)


func test_a_good_intro_has_no_problem() -> void:
	check_equal(_intro().problems("test", _known_by(_registry())), PackedStringArray(), "a sheet of three frames, two lines, a ramp, the shared reveal cue")
	check_equal(_intro().pages(), 2, "a page a line")
	var quiet := BossIntro.new()
	check_equal(quiet.pages(), 1, "no lines: one page (\"Fight\")")
	check_equal(quiet.reveal_cue_or_shared(), BossIntro.SHARED_REVEAL_CUE, "no reveal cue of its own: the shared one")


func test_each_mistake_is_named() -> void:
	var known: Callable = _known_by(_registry())
	var intro: BossIntro = _intro()
	intro.portrait = null
	check_equal(intro.problems("test").size(), 1, "no portrait")
	intro.portrait = _sheet(BossIntro.FRAME * 2, BossIntro.FRAME)
	check_equal(intro.problems("test").size(), 1, "two frames, not three")
	intro.portrait = _sheet(BossIntro.FRAME * BossIntro.FRAMES, BossIntro.FRAME + 1)
	check_equal(intro.problems("test").size(), 1, "a frame too high")
	intro = _intro()
	intro.lines = ["One.", "Two.", "Three.", "Four."] as Array[String]
	check_equal(intro.problems("test").size(), 1, "more than three lines")
	intro = _intro()
	intro.accent = &"pink"
	check_equal(intro.problems("test").size(), 1, "an accent that is no palette ramp")
	intro = _intro()
	intro.dark_cue = &"no_such_cue"
	check_equal(intro.problems("test", known).size(), 1, "a dark cue the game does not have")
	check_equal(intro.problems("test").size(), 0, "with nobody to ask, the cues are not checked")
	intro = _intro()
	intro.reveal_cue = &"no_such_cue"
	check_equal(intro.problems("test", known).size(), 1, "a reveal cue the game does not have")


func test_an_intro_is_among_its_bosss_problems() -> void:
	var data := EnemyBase.new()
	data.id = &"test_boss"
	data.boss = true
	data.boss_intro = BossIntro.new()
	check(data.problems().size() >= 2, "no portrait and no accent: its data's problems say so")
