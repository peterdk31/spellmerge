extends "res://tests/support/suite.gd"
## The floor's own cover (the floor's first slice, docs/milestones/floor.md, content/cover/floor):
## every open cell no other kind took is floor, dry at rest and drawing nothing. Water wets it (it
## soaks who stands in it, and dries in a while; more water keeps it wet); lightning makes a puddle
## live, runs through the water joined to it and no further, strikes who stands in it as its
## lighter's, and leaves it spent for a moment (a lake is live once); frost freezes it (ice chills,
## never freezes a body by itself) and fire thaws ice to water; fire on water is steam, then dry.
const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const FLOOR: CoverKind = preload("res://content/cover/floor/floor.tres")

var _kit: Kit


func before_each() -> void:
	_kit = Kit.new(root, FLOOR)


func after_each() -> void:
	_kit.free_all()


## `element` on the cells (x, y) to (x + w - 1, y + h - 1), one touch a cell.
func _touch_block(element: StringName, x: int, y: int, w: int, h: int) -> void:
	for cy in range(y, y + h):
		for cx in range(x, x + w):
			_kit.touch(element, _kit.middle(_kit.cell(cx, cy)))


func _wet_block(x: int, y: int, w: int, h: int) -> void:
	_touch_block(&"water", x, y, w, h)
	_kit.wait(0.4)


func test_it_is_sound_flat_and_fills_the_floor() -> void:
	check_equal(_kit.problems(), PackedStringArray(), "its data")
	check(FLOOR.fills_floor, "it takes the floor's cells")
	check_equal(FLOOR.look, CoverKind.Look.FLAT, "drawn flat")
	check(not FLOOR.states[0].gives(), "dry floor gives nothing")
	check_equal(FLOOR.states[0].flat_material, &"", "and draws nothing")
	check(_kit.look.flat_of(FLOOR.id) != null, "Feel lays its flat look")
	check(_kit.look.batch_of(FLOOR.id) == null, "and no tufts")


func test_water_wets_it_and_it_soaks_who_stands_in_it() -> void:
	var cell: int = _kit.cell(4, 4)
	_kit.touch(&"water", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"wetting", "the water spreads in")
	_kit.wait(0.3)
	check_equal(_kit.state_of(cell), &"wet", "wet")
	check_equal(_kit.look.shown_state(cell), FLOOR.state_at(&"wet"), "shown wet")
	var body: Actor = _kit.world.actor(_kit.middle(cell), [&"health", &"hurtbox"])
	_kit.steps(1)
	check(_kit.has_status(body, &"soak"), "soaked")


func test_a_puddle_dries_and_more_water_keeps_it_wet() -> void:
	var kept: int = _kit.cell(2, 2)
	var left: int = _kit.cell(6, 2)
	_kit.touch(&"water", _kit.middle(kept))
	_kit.touch(&"water", _kit.middle(left))
	_kit.wait(10.0)
	_kit.touch(&"water", _kit.middle(kept))
	_kit.wait(2.5)
	check_equal(_kit.state_of(kept), &"wet", "watered again: still wet")
	check_equal(_kit.state_of(left), &"drying", "left alone it dries after 12 s")
	_kit.wait(0.6)
	check_equal(_kit.state_of(left), &"dry", "and is dry floor again")
	_kit.wait(10.0)
	check_equal(_kit.state_of(kept), &"dry", "the other dries in its turn")


func test_lightning_runs_through_the_lake_and_no_further() -> void:
	_wet_block(2, 2, 6, 4)
	var apart: int = _kit.cell(12, 3)
	_kit.touch(&"water", _kit.middle(apart))
	_kit.wait(0.4)
	_kit.touch(&"lightning", _kit.middle(_kit.cell(2, 2)))
	_kit.wait(0.4)
	check_equal(_kit.count_in(&"live") + _kit.count_in(&"spent"), 24, "the whole lake went live within 0.4 s")
	check_equal(_kit.state_of(apart), &"wet", "a puddle apart stays wet")
	check_equal(_kit.state_of(_kit.cell(8, 3)), &"dry", "dry floor beside it stays dry")
	check(_kit.cover.rolls() > 0, "spread by the run's chance")
	_kit.wait(1.0)
	check_equal(_kit.count_in(&"spent"), 24, "then spent")
	_kit.touch(&"lightning", _kit.middle(_kit.cell(4, 3)))
	_kit.steps(2)
	check_equal(_kit.count_in(&"live"), 0, "lightning does not light a spent lake: live once")
	_kit.wait(1.6)
	check_equal(_kit.count_in(&"wet"), 25, "then wet again, the puddle apart too")


func test_live_water_strikes_who_stands_in_it_as_its_lighters() -> void:
	_wet_block(2, 2, 3, 3)
	var body: Actor = _kit.world.actor(_kit.middle(_kit.cell(3, 3)), [&"health", &"hurtbox"])
	var dry: Actor = _kit.world.actor(_kit.middle(_kit.cell(12, 6)), [&"health", &"hurtbox"])
	var struck: Array = []
	_kit.world.bus.floor_strike_requested.connect(func(caster: int, target: Node, element: StringName, damage: float, tag: int) -> void: struck.append([caster, target, element, damage, tag]))
	var reactions: Array = []
	_kit.world.bus.reaction_landed.connect(func(_c: int, reaction: StringName, _t: Node, _p: Vector2, tag: int, _s: int) -> void: reactions.append([reaction, tag]))
	_kit.steps(2)
	check(_kit.has_status(body, &"soak"), "soaked by the puddle")
	var before: float = _kit.world.combat.health_of(body)
	var tag: int = SpellTag.make(3, 1, 0, 0)
	_kit.world.bus.floor_touched.emit(3, &"lightning", _kit.middle(_kit.cell(2, 2)), 0.0, tag)
	_kit.wait(0.6)
	check(not struck.is_empty(), "struck")
	check_equal(struck[0][1], body, "the body in the water")
	check_equal(struck[0][0], 3, "as the hit of who lit it")
	check_equal(struck[0][4], tag, "with its spell's tag")
	check_equal(struck[0][2], &"lightning", "by lightning")
	check(_kit.world.combat.health_of(body) < before, "it hurt (%s from %s)" % [_kit.world.combat.health_of(body), before])
	check(reactions.size() > 0 and reactions[0][0] == &"current", "a soaked body sets off Current (%s)" % [reactions])
	check_equal(_kit.cover.room().actor_at(_kit.cell(4, 4)), 3, "a cell the spread lit is its lighter's too")
	check_equal(_kit.cover.room().tag_at(_kit.cell(4, 4)), tag, "and its spell's")
	for heard: Array in struck:
		check(heard[1] != dry, "nobody on dry floor is struck")


func test_frost_freezes_it_ice_chills_and_never_freezes_a_body() -> void:
	_wet_block(2, 2, 3, 3)
	var cell: int = _kit.cell(3, 3)
	_kit.touch(&"frost", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"freezing", "it freezes over")
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"ice", "ice")
	check_equal(_kit.state_of(_kit.cell(2, 2)), &"wet", "frost freezes only where it lands")
	var body: Actor = _kit.world.actor(_kit.middle(cell), [&"health", &"hurtbox"])
	var frozen: bool = false
	var chilled: bool = false
	for i in roundi(5.0 / Kit.DT):
		_kit.steps(1)
		chilled = chilled or _kit.has_status(body, &"chill")
		frozen = frozen or _kit.has_status(body, &"freeze")
	check(chilled, "whoever stands on ice is chilled")
	check(not frozen, "five seconds on ice: never frozen by it alone")
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"thawing", "fire thaws it")
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"wet", "to water again, for the lake")


func test_fire_on_water_is_steam_then_dry_floor() -> void:
	_wet_block(2, 2, 1, 1)
	var cell: int = _kit.cell(2, 2)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"steam", "steam")
	check(_kit.look.motes.cells_giving_off(FLOOR.id, FLOOR.state_at(&"steam")) == 1, "steam rises")
	_kit.wait(0.6)
	check_equal(_kit.state_of(cell), &"dry", "and the floor is dry")
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"dry", "fire on dry floor does nothing (oil is Part 2)")


func test_the_ai_walks_through_water_and_ice_but_not_live_water() -> void:
	_wet_block(2, 2, 3, 3)
	var sight := CoverSight.new()
	_kit.cover.look(_kit.middle(_kit.cell(3, 3)), 48.0, sight)
	check(not sight.harms(_kit.middle(_kit.cell(3, 3))), "a puddle is no danger")
	_kit.touch(&"lightning", _kit.middle(_kit.cell(3, 3)))
	_kit.steps(2)
	_kit.cover.look(_kit.middle(_kit.cell(3, 3)), 48.0, sight)
	check(sight.harms(_kit.middle(_kit.cell(3, 3))), "live water is")


func test_every_change_of_look_plays_four_frames() -> void:
	for state: CoverState in FLOOR.states:
		if state.flat_motion == CoverState.FlatMotion.GROW or state.flat_motion == CoverState.FlatMotion.SHRINK or state.flat_motion == CoverState.FlatMotion.GROW_IN:
			check(state.animation_frames >= 3, "%s plays at least 3 frames (Smooth)" % state.state_id)
			var seconds: float = float(state.animation_frames) / float(state.animation_fps)
			var after: float = 0.0
			for row in state.triggers:
				if row.when == CoverTrigger.When.AFTER:
					after = row.seconds
			check(after > 0.0 and seconds <= after + 0.001, "%s plays out within its time (%s s in %s s)" % [state.state_id, seconds, after])


## The owner, 2026-11-25: only fully wet floor carries lightning; a puddle still spreading in, drying,
## freezing or thawing does not (nor dry floor).
func test_only_wet_floor_carries_lightning() -> void:
	var spreading: int = _kit.cell(2, 2)
	_kit.touch(&"water", _kit.middle(spreading))
	_kit.steps(1)
	check_equal(_kit.state_of(spreading), &"wetting", "still spreading in")
	_kit.touch(&"lightning", _kit.middle(spreading))
	_kit.steps(1)
	check_equal(_kit.state_of(spreading), &"wetting", "lightning on a wetting cell: nothing")
	var dry: int = _kit.cell(8, 2)
	_kit.touch(&"lightning", _kit.middle(dry))
	_kit.steps(1)
	check_equal(_kit.state_of(dry), &"dry", "nor on dry floor")
	for state: CoverState in FLOOR.states:
		var carries: bool = state.on_element(&"lightning") != &""
		check_equal(carries, state.state_id == &"wet", "%s carries lightning only if it is wet" % state.state_id)



# --- Oil (docs/milestones/oil-spill.md) -------------------------------------------------------

func _oil_block(x: int, y: int, w: int, h: int) -> void:
	_touch_block(&"oil", x, y, w, h)
	_kit.wait(0.4)


func test_oil_coats_it_lies_long_and_soaks_in() -> void:
	var cell: int = _kit.cell(4, 4)
	_kit.touch(&"oil", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"oiling", "the oil spreads in")
	_kit.wait(0.3)
	check_equal(_kit.state_of(cell), &"oiled", "oiled")
	check(not FLOOR.states[FLOOR.state_at(&"oiled")].gives(), "oil gives nothing to who stands in it")
	_kit.wait(20.0)
	_kit.touch(&"oil", _kit.middle(cell))
	_kit.wait(20.0)
	check_equal(_kit.state_of(cell), &"oiled", "more oil keeps it oiled (its time from 0)")
	_kit.wait(10.2)
	check_equal(_kit.state_of(cell), &"soaking", "it soaks in after 30 s")
	_kit.wait(0.6)
	check_equal(_kit.state_of(cell), &"dry", "and the floor is dry")


func test_fire_lights_oil_and_runs_through_joined_oil_and_no_further() -> void:
	_oil_block(2, 2, 8, 1)
	_oil_block(12, 2, 2, 1)
	var tag: int = SpellTag.make(2, 1, 0, 0)
	_kit.world.bus.floor_touched.emit(2, &"fire", _kit.middle(_kit.cell(2, 2)), 0.0, tag)
	_kit.steps(1)
	check_equal(_kit.state_of(_kit.cell(2, 2)), &"catching", "the oil catches")
	_kit.wait(2.5)
	for x in range(2, 10):
		var state: StringName = _kit.state_of(_kit.cell(x, 2))
		check(state == &"burning" or state == &"catching", "the fire ran to cell %d (%s)" % [x, state])
	check_equal(_kit.cover.room().actor_at(_kit.cell(9, 2)), 2, "a cell the fire ran to is its lighter's")
	check_equal(_kit.cover.room().tag_at(_kit.cell(9, 2)), tag, "and its spell's")
	for x in [12, 13]:
		check_equal(_kit.state_of(_kit.cell(x, 2)), &"oiled", "oil not joined to it does not burn (%d)" % x)
	check_equal(_kit.state_of(_kit.cell(5, 4)), &"dry", "dry floor does not burn")


func test_burning_oil_harms_who_stands_in_it_as_its_lighters() -> void:
	_oil_block(2, 2, 3, 3)
	var body: Actor = _kit.world.actor(_kit.middle(_kit.cell(3, 3)), [&"health", &"hurtbox"])
	var struck: Array = []
	_kit.world.bus.floor_strike_requested.connect(func(caster: int, target: Node, element: StringName, damage: float, tag: int) -> void: struck.append([caster, target, element, damage, tag]))
	_kit.steps(2)
	check(_kit.asked.is_empty(), "oil asks nothing of who stands in it")
	var before: float = _kit.world.combat.health_of(body)
	var tag: int = SpellTag.make(1, 2, 0, 0)
	_kit.world.bus.floor_touched.emit(1, &"fire", _kit.middle(_kit.cell(3, 3)), 0.0, tag)
	_kit.wait(0.8)
	check(_kit.has_status(body, &"burn"), "it burns")
	check(not struck.is_empty(), "struck")
	check_equal(struck[0][0], 1, "as the hit of who lit it")
	check_equal(struck[0][2], &"fire", "by fire")
	check_equal(struck[0][4], tag, "with its spell's tag")
	check(_kit.world.combat.health_of(body) < before, "it hurt")
	var sight := CoverSight.new()
	_kit.cover.look(_kit.middle(_kit.cell(3, 3)), 48.0, sight)
	check(sight.harms(_kit.middle(_kit.cell(3, 3))), "burning oil is danger to the AI")


func test_oil_is_no_danger_to_the_ai() -> void:
	_oil_block(2, 2, 3, 3)
	var sight := CoverSight.new()
	_kit.cover.look(_kit.middle(_kit.cell(3, 3)), 48.0, sight)
	check(not sight.harms(_kit.middle(_kit.cell(3, 3))), "the enemies walk over oil")


func test_it_burns_long_burns_down_to_scorched_then_dry() -> void:
	_oil_block(2, 2, 1, 1)
	var cell: int = _kit.cell(2, 2)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.wait(0.4)
	check_equal(_kit.state_of(cell), &"burning", "burning")
	_kit.wait(5.0)
	check_equal(_kit.state_of(cell), &"burning", "it burns long")
	_kit.wait(1.0)
	check_equal(_kit.state_of(cell), &"burning_down", "it burns down")
	_kit.wait(0.6)
	check_equal(_kit.state_of(cell), &"scorched", "scorched")
	check(not FLOOR.states[FLOOR.state_at(&"scorched")].gives(), "scorched floor gives nothing")
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"scorched", "fire does nothing to it")
	_kit.wait(10.2)
	check_equal(_kit.state_of(cell), &"dry", "then dry")


func test_new_oil_on_scorched_floor_lies_again() -> void:
	_oil_block(2, 2, 1, 1)
	var cell: int = _kit.cell(2, 2)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.wait(7.2)
	check_equal(_kit.state_of(cell), &"scorched", "scorched")
	_kit.touch(&"oil", _kit.middle(cell))
	_kit.wait(0.3)
	check_equal(_kit.state_of(cell), &"oiled", "new oil lies on it")


func test_water_and_frost_put_an_oil_fire_out_and_leave_the_oil() -> void:
	for element: StringName in [&"water", &"frost"]:
		_oil_block(2, 2, 1, 1)
		var cell: int = _kit.cell(2, 2)
		_kit.touch(&"fire", _kit.middle(cell))
		_kit.wait(0.4)
		check_equal(_kit.state_of(cell), &"burning", "burning")
		_kit.touch(element, _kit.middle(cell))
		_kit.steps(1)
		check_equal(_kit.state_of(cell), &"doused", "%s puts it out" % element)
		_kit.wait(0.4)
		check_equal(_kit.state_of(cell), &"oiled", "and leaves the oil (%s)" % element)
		_kit.touch(&"fire", _kit.middle(cell))
		_kit.steps(1)
		check_equal(_kit.state_of(cell), &"catching", "to be lit again (%s)" % element)
		_kit.wait(8.0)


func test_lightning_does_not_light_oil_and_oil_does_nothing_on_water() -> void:
	_oil_block(2, 2, 1, 1)
	_kit.touch(&"lightning", _kit.middle(_kit.cell(2, 2)))
	_kit.steps(1)
	check_equal(_kit.state_of(_kit.cell(2, 2)), &"oiled", "lightning does not light oil")
	_wet_block(6, 2, 1, 1)
	_kit.touch(&"oil", _kit.middle(_kit.cell(6, 2)))
	_kit.steps(1)
	check_equal(_kit.state_of(_kit.cell(6, 2)), &"wet", "oil on water: nothing")


func test_the_fire_touches_its_neighbours_a_puddle_beside_it_boils() -> void:
	_oil_block(2, 2, 1, 1)
	_wet_block(3, 2, 1, 1)
	_kit.touch(&"fire", _kit.middle(_kit.cell(2, 2)))
	_kit.wait(1.5)
	var boiled: StringName = _kit.state_of(_kit.cell(3, 2))
	check(boiled == &"steam" or boiled == &"dry", "the water beside the fire boiled away (%s)" % boiled)


## Regression (the oil screenshots): a cell still catching took no water, kept burning and lit the
## doused oil round it again; water and frost put a catching fire out too.
func test_water_puts_out_a_fire_still_catching() -> void:
	_oil_block(2, 2, 1, 1)
	var cell: int = _kit.cell(2, 2)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"catching", "catching")
	_kit.touch(&"water", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"doused", "put out")
