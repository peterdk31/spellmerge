extends "res://tests/support/suite.gd"
## The deflect's and the parry's looks (melee I5; docs/milestones/M2-staffs.md, "The look"): a
## deflected shot flashes big and white where it turned, in its new caster's colours, bigger than
## a hit's; a swing's block (a parry) shows a big four-point star in Spark gold and holds the
## parrying actor alone for a moment; another carrier's block shows neither.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel_deflect.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

var _world: Fixture
var _feel: FeelScript


func before_each() -> void:
	_world = Fixture.new(root)
	_feel = own(FeelScript.new()) as FeelScript
	_feel.events = _world.bus
	_feel.projectiles = _world.projectiles
	_feel.actors = _world.table
	_feel.combat = _world.combat
	_feel.drive_engine = false
	var preset: FeelPresetScript = FeelPresetScript.new()
	preset.hit_sound = &""
	_feel.preset = preset
	root.add_child(_feel)


func after_each() -> void:
	_world.free_all()


func _body(at: Vector2) -> Actor:
	return _world.actor(at, [&"health", &"hurtbox"] as Array[StringName])


## A shot of `caster` at `at` flying left at 100 px/s.
func _shot(caster: int, at: Vector2) -> int:
	return _world.projectiles.spawn(caster, at, Vector2(-100.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER | ManagerScript.LAYER_ENEMY)


func test_a_deflected_shot_flashes_big_and_white_in_its_new_casters_colours() -> void:
	var batter: Actor = _body(Vector2.ZERO)
	var shooter: Actor = _body(Vector2(200.0, 0.0))
	var slot: int = _shot(shooter.id, Vector2(20.0, 0.0))
	check(_world.projectiles.deflect_shot(slot, batter.id, Vector2.RIGHT, 7), "the shot is deflected")
	var flash: Dictionary = _feel.effect_info(FeelScript.KIND_BURST)
	check(not flash.is_empty(), "a white-hot burst shows")
	if flash.is_empty():
		return
	check_equal(flash["ramp"], _world.table.ramp_of(batter.id), "in the deflecting actor's colours")
	check_equal(flash["core"], Color.WHITE, "white: the ramp's own white-hot core")
	check_equal(flash["zoom"], _feel.cue_of(&"deflect").parts[0]["zoom"], "as big as the cue says")
	# A hit's spray and a shot's landing flare are 1 to 3; a deflect's flash is bigger.
	check(int(flash["zoom"]) > 3, "bigger than a hit's (%d)" % int(flash["zoom"]))
	check((flash["at"] as Vector2).distance_to(Vector2(20.0, 0.0)) <= 1.0, "where it turned")
	check((flash["dir"] as Vector2).x > 0.9, "aimed the way it leaves: %s" % flash["dir"])
	check_equal(_world.table.held_left(batter.id), 0.0, "a deflect holds nobody (only a parry does)")


func test_a_swing_block_is_a_parry_a_gold_star_and_a_local_stop() -> void:
	var parrier: Actor = _body(Vector2.ZERO)
	var shooter: Actor = _body(Vector2(200.0, 0.0))
	var other: Actor = _body(Vector2(0.0, 200.0))
	var slot: int = _shot(shooter.id, Vector2(20.0, 0.0))
	check(_world.projectiles.block_shot(slot, parrier.id, 7, &"swing"), "the swing's shield stops the shot")
	var star: Dictionary = _feel.effect_info(FeelScript.KIND_BURST)
	check(not star.is_empty(), "a four-point star shows")
	if not star.is_empty():
		check_equal(star["core"], Color("f2c230"), "in Spark gold")
		check((int(star["look"]) & FeelScript.EXACT) != 0, "exactly that colour, whoever parried")
		check_equal(star["zoom"], _feel.cue_of(&"parry").parts[0]["zoom"], "as big as the cue says")
		check(int(star["zoom"]) > 3, "big, bigger than a hit's")
	check(_world.table.held_left(parrier.id) >= _feel.cue_of(&"parry").hold - 0.0001, "the parrying actor is held for the parry")
	check(is_equal_approx(_feel.cue_of(&"parry").hold, 0.06), "the playground's 0.06 s")
	check_equal(_world.table.held_left(other.id), 0.0, "another actor is not")
	check_equal(_world.table.held_left(shooter.id), 0.0, "nor the shooter")
	check_equal(_feel.stop_left, 0.0, "the game runs on")
	check_equal(_world.projectiles.impact_form, &"", "the form is only told while the block is sent")


func test_other_blocks_show_no_parry() -> void:
	var guard: Actor = _body(Vector2.ZERO)
	var shooter: Actor = _body(Vector2(200.0, 0.0))
	check(_world.projectiles.block_shot(_shot(shooter.id, Vector2(20.0, 0.0)), guard.id, 7, &"beam"), "a beam's shield stops a shot")
	check(_world.projectiles.block_shot(_shot(shooter.id, Vector2(20.0, 10.0)), guard.id, 7), "so does a block with no form")
	check_equal(_feel.effects_of(FeelScript.KIND_BURST), 0, "no star")
	check_equal(_world.table.held_left(guard.id), 0.0, "and no stop")


func test_a_real_shielded_swing_parries() -> void:
	# The whole flow with the real cards (the combo arena): the swing's guard blocks with its form,
	# and a Feel listening to that arena sees a parry.
	var arena := ArenaScript.new(root)
	var feel := own(FeelScript.new()) as FeelScript
	feel.events = arena.bus
	feel.projectiles = arena.projectiles
	feel.actors = arena.projectiles.actors
	feel.drive_engine = false
	feel.preset = _feel.preset
	root.add_child(feel)
	arena.projectiles.spawn(ActorSeats.enemy(arena.projectiles.actors), Vector2(60.0, 0.0), Vector2(-200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER)
	arena.install_cards(0, 0, ["shield", "swing"])
	arena.cast(0, 0)
	arena.run(0.3)
	check_equal(arena.blocks, [0], "the swing's shield stopped the shot")
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "the parry's star shows")
	check(arena.projectiles.actors.held_left(0) > 0.0, "the parrier is held")
	arena.free_all()
