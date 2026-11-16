extends "res://tests/support/suite.gd"
## The hub's grass (ground cover GC8, content/cover/hub_grass, docs/milestones/ground-cover.md decision
## 2): it fills the hub by itself; fire lights it, catching then burning (1.2 s in all), burning its
## standers and spreading fire, then it smoulders, goes to ash and grows back after 30 s; frost and
## water put it out, its flames going out; its fire gives off embers and smoke; its sheet holds every
## frame its states draw, and every change plays through frames, each tuft its own.
##
## godot --headless --path . --script res://content/cover/hub_grass/test_hub_grass.gd

const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const GRASS: CoverKind = preload("res://content/cover/hub_grass/hub_grass.tres")

var _kit: Kit


func before_each() -> void:
	_kit = Kit.new(root, GRASS)


func after_each() -> void:
	_kit.free_all()


## The grass with no spread: one lit cell's own story.
func _still() -> CoverKind:
	var still := GRASS.duplicate(true) as CoverKind
	for state_id: StringName in [&"catching", &"burning"]:
		var lit: CoverState = still.states[still.state_at(state_id)]
		lit.spreads = &""
		lit.spread_chance = 0.0
	return still


## The seconds after which `state` moves on by itself (0 for never).
static func _after(state: CoverState) -> float:
	for row in state.triggers:
		if row.when == CoverTrigger.When.AFTER:
			return row.seconds
	return 0.0


func test_it_is_sound_and_fills_the_hub() -> void:
	check_equal(_kit.problems(), PackedStringArray(), "its data")
	check(GRASS.fills(&"hub"), "the hub's biome")
	check(not GRASS.fills(&"crypt"), "not the crypt's")
	check_equal(GRASS.frame_count(), 194, "six tufts at rest, two trampled, then each tuft's own strip of each stage of its fire: catching, burning, smouldering, ash, growing back, going out as it catches and as it burns")
	var rest: CoverState = GRASS.states[0]
	check_equal(rest.state_id, &"rest", "it starts at rest")
	check_equal(rest.frames, PackedInt32Array([0, 1, 2, 3, 4, 5]), "six tufts at rest, curved and leaning, so the grass is never a row of straight blades")
	check(not rest.trampled_frames.is_empty(), "it draws trampled frames (GC4)")
	for state: CoverState in GRASS.states:
		check_equal(state.frames.size(), rest.frames.size(), "%s draws a frame for each tuft at rest, in their order, so a tuft keeps its blades through every change (a tuft picks the same place in each list: CoverTufts.frame)" % state.state_id)
	for state_id: StringName in [&"catching", &"burning", &"smouldering", &"growing", &"doused", &"quenched", &"burning_doused", &"burning_quenched"]:
		var change: CoverState = GRASS.states[GRASS.state_at(state_id)]
		check(change.animation_frames >= 3 and not change.animation_loops, "%s plays its change through, a frame at a time (the owner, 2026-11-16: everything should look smooth)" % state_id)
		var lasts: float = float(change.animation_frames) / float(change.animation_fps)
		check(lasts <= _after(change) + 0.05, "%s's frames play out within its %.1f s (%.2f s)" % [state_id, _after(change), lasts])
	check(GRASS.trample_hold >= 4.0, "a trail through it stays flat a good while after the last body left (the owner, 2026-11-16: it sprang back far too soon), got %.1f s" % GRASS.trample_hold)
	check(GRASS.trample_spring >= 2.0, "and grows back slowly, not at once, got %.1f s" % GRASS.trample_spring)
	check(GRASS.tufts_per_cell >= 5, "dense: at least five tufts a cell (the owner, 2026-11-16)")
	check(rest.status == &"", "grass at rest harms nobody")


func test_fire_lights_it_and_it_burns_to_ash_then_grows_back() -> void:
	_kit.free_all()
	_kit = Kit.new(root, _still())
	var cell: int = _kit.cell(4, 4)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"catching", "lit: it catches first, flames at its blades' feet (the owner, 2026-11-16: the change to fire was not seen)")
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"burning", "then the blades burn")
	_kit.wait(0.6)
	check_equal(_kit.state_of(cell), &"burning", "still burning a second on")
	_kit.wait(0.3)
	check_equal(_kit.state_of(cell), &"smouldering", "then it smoulders, charred, harming nobody")
	check(GRASS.states[GRASS.state_at(&"smouldering")].status == &"", "smouldering grass burns nobody")
	_kit.wait(1.0)
	check_equal(_kit.state_of(cell), &"ash", "then ash")
	_kit.wait(29.0)
	check_equal(_kit.state_of(cell), &"ash", "ash for most of 30 s")
	_kit.wait(1.5)
	check_equal(_kit.state_of(cell), &"growing", "then the hub's grass grows back out of the ash")
	_kit.wait(1.5)
	check_equal(_kit.state_of(cell), &"rest", "to the grass at rest")


func test_frost_puts_it_out() -> void:
	_kit.free_all()
	_kit = Kit.new(root, _still())
	var cell: int = _kit.cell(6, 4)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	_kit.touch(&"frost", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"doused", "catching, its flames go out")
	check(GRASS.states[GRASS.state_at(&"doused")].status == &"", "and burn nobody")
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"rest", "back at rest")
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.wait(0.4)
	_kit.touch(&"frost", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"burning_doused", "burning, out too, from its burnt-down flames (its own frames, so it does not pop back to full grass)")
	check(GRASS.states[GRASS.state_at(&"burning_doused")].status == &"", "burning nobody")
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"rest", "and back at rest")


func test_a_fire_spreads_through_it() -> void:
	_kit.touch(&"fire", _kit.middle(_kit.cell(9, 4)))
	_kit.wait(4.0)
	check(_kit.count_in(&"catching") + _kit.count_in(&"burning") + _kit.count_in(&"smouldering") + _kit.count_in(&"ash") > 5, "the fire spread beyond the cell it was lit in")


func test_it_burns_whoever_stands_in_it() -> void:
	_kit.free_all()
	_kit = Kit.new(root, _still())
	var cell: int = _kit.cell(5, 5)
	var body: Actor = _kit.world.actor(_kit.middle(cell), [&"health", &"hurtbox"])
	_kit.steps(5)
	check(_kit.asked.is_empty(), "at rest it asks nothing")
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.asked.size(), 1, "lit: a status asked at once")
	check_equal(_kit.asked[0][1], &"burn", "a burn")
	check(_kit.has_status(body, &"burn"), "Combat put it on")


func test_burning_it_gives_off_embers_and_smoke() -> void:
	var burning: CoverState = GRASS.states[GRASS.state_at(&"burning")]
	var kinds: Array[StringName] = []
	for look: MoteSource in burning.motes:
		check_equal(_kit.look.motes.stream_problems(look), PackedStringArray(), "%s is a sound cover stream" % look.kind)
		kinds.append(look.kind)
	check_equal(kinds, [&"ember", &"smoke"] as Array[StringName], "embers and smoke")
	var cell: int = _kit.cell(3, 3)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check(_kit.look.motes.cells_giving_off(GRASS.id, GRASS.state_at(&"catching")) >= 1, "Feel gives off the catching cell's embers")
	_kit.wait(0.4)
	check(_kit.look.motes.cells_giving_off(GRASS.id, GRASS.state_at(&"burning")) >= 1, "and the burning cell's")
	check_equal(_kit.look.motes.cells_giving_off(GRASS.id, 0), 0, "and none from the grass at rest")


func test_water_wets_it_puts_its_fire_out_and_wet_grass_does_not_light() -> void:
	_kit.free_all()
	_kit = Kit.new(root, _still())
	var cell: int = _kit.cell(4, 6)
	_kit.touch(&"water", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"wet", "water wets it")
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"wet", "wet grass does not catch fire")
	_kit.wait(8.5)
	check_equal(_kit.state_of(cell), &"rest", "it dries in 8 s")
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"catching", "dry, it lights again")
	_kit.touch(&"water", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"quenched", "and water puts the fire out as it catches, its flames going out")
	check_equal(GRASS.states[GRASS.state_at(&"quenched")].status, &"soak", "soaking whoever stands in it already")
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"wet", "then it is wet")
	_kit.wait(8.5)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"burning", "lit again and burning")
	_kit.touch(&"water", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"burning_quenched", "water puts a burning cell out too, from its burnt-down flames")
	check_equal(GRASS.states[GRASS.state_at(&"burning_quenched")].status, &"soak", "soaking already")
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"wet", "then it is wet")


func test_wet_grass_soaks_whoever_stands_in_it() -> void:
	var wet: CoverState = GRASS.states[GRASS.state_at(&"wet")]
	check_equal(wet.status, &"soak", "a body standing in wet grass is soaked")
	check(wet.status_every > 0.0 and wet.status_duration > wet.status_every, "for as long as it stands in it")
	check(not wet.motes.is_empty(), "it glints with water while wet")
