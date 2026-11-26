extends "res://tests/support/suite.gd"
## The floor's look (docs/milestones/floor-look.md; gameplay/feel/cover_flat.gd, cover_lights.gd):
## the floor's states name their surfaces, glows and marks; a flat look keeps each cell's state, the one
## before and when it changed (the shader's blue and green); live water's and steam's glow are written
## as the floor's lights, a patch of cells a row, eased in and out, none from still water; a renewal
## restarts nothing; the effects' Low row gives off none of the floor's motes and holds its shimmer;
## and a frame of the lights allocates nothing.

const CoverFlatScript := preload("res://gameplay/feel/cover_flat.gd")
const CoverLightsScript := preload("res://gameplay/feel/cover_lights.gd")
const CoverMotesScript := preload("res://gameplay/feel/cover_motes.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const FLOOR: CoverKind = preload("res://content/cover/floor/floor.tres")


func _state(id: StringName) -> int:
	for at in FLOOR.states.size():
		if FLOOR.states[at].state_id == id:
			return at
	return -1


func _layout(columns: int = 8, rows: int = 6) -> CoverLayout:
	var laid := CoverLayout.new()
	laid.origin = Vector2(64.0, 32.0)
	laid.columns = columns
	laid.rows = rows
	laid.size = Vector2(columns * CoverLayout.CELL, rows * CoverLayout.CELL)
	laid.kinds = [FLOOR] as Array[CoverKind]
	laid.cells = PackedByteArray()
	laid.cells.resize(columns * rows)
	laid.cells.fill(1)
	return laid


func _flat(laid: CoverLayout) -> CoverFlatScript:
	var flat: CoverFlatScript = own(CoverFlatScript.new()) as CoverFlatScript
	flat.lay(laid, 0, 0.0)
	return flat


func test_the_states_name_their_looks() -> void:
	check(FLOOR.problems().is_empty(), "the floor is sound: %s" % [FLOOR.problems()])
	for id: StringName in [&"wetting", &"wet", &"drying", &"live", &"spent"]:
		check_equal(FLOOR.states[_state(id)].flat_surface, CoverState.FlatSurface.WATER, "%s is water" % id)
	for id: StringName in [&"freezing", &"ice", &"thawing"]:
		check_equal(FLOOR.states[_state(id)].flat_surface, CoverState.FlatSurface.ICE, "%s is ice" % id)
	check_equal(FLOOR.states[_state(&"steam")].flat_surface, CoverState.FlatSurface.STEAM, "steam is steam")
	check_equal(FLOOR.states[_state(&"live")].flat_glow, &"arc", "live water glows Arc")
	check(FLOOR.states[_state(&"steam")].flat_glow != &"", "steam glows")
	check_equal(FLOOR.states[_state(&"wet")].flat_glow, &"", "still water gives no light")
	check(FLOOR.states[_state(&"steam")].flat_trace != &"", "steam leaves a scorch")
	check(FLOOR.states[_state(&"drying")].flat_trace != &"", "a puddle leaves its damp")


func test_a_glow_named_badly_is_a_problem() -> void:
	var kind := FLOOR.duplicate(true) as CoverKind
	kind.states[_state(&"live")].flat_glow = &"no_such"
	kind.states[_state(&"steam")].flat_trace = &"no_such"
	var found: String = "\n".join(kind.problems())
	check(found.contains("glows in 'no_such'"), "a glow of no material is named: %s" % found)
	check(found.contains("mark of 'no_such'"), "a mark of no material is named")


func test_a_cell_keeps_the_state_before() -> void:
	var laid := _layout()
	var flat := _flat(laid)
	flat.show_cell(9, laid.columns, _state(&"wet"), 1.0)
	flat.show_cell(9, laid.columns, _state(&"steam"), 2.0)
	flat.show_cell(9, laid.columns, _state(&"dry"), 2.5)
	check_equal(flat.shown_cell(9, laid.columns), _state(&"dry"), "dry now")
	check_equal(flat.shown_before(9), _state(&"steam"), "steam before (its scorch is drawn)")


func test_live_water_lights_and_eases() -> void:
	var laid := _layout()
	var flat := _flat(laid)
	var lights: CoverLightsScript = CoverLightsScript.new()
	for cell: int in [0, 1, 8, 9, 20]:
		flat.show_cell(cell, laid.columns, _state(&"wet"), 0.5)
	lights.begin()
	flat.write_lights(lights, 1.0)
	check_equal(lights.count, 0, "still water lights nothing")
	for cell: int in [0, 1, 8, 9, 20]:
		flat.show_cell(cell, laid.columns, _state(&"live"), 1.0)
	lights.begin()
	flat.write_lights(lights, 1.0)
	check_equal(lights.count, 0, "a cell just gone live has no light yet (it eases in)")
	lights.begin()
	flat.write_lights(lights, 1.0 + CoverLightsScript.EASE_SECONDS * 1.01)
	check_equal(lights.count, 2, "a patch a row: the 2x2 block and the lone cell")
	var strength_at: int = SpellLightScript.SPOT_ROW_STRENGTH
	var whole: float = lights.rows[strength_at]
	var lone: float = lights.rows[SpellLightScript.STRIDE + strength_at]
	check(absf(whole - FLOOR.states[_state(&"live")].flat_glow_strength) < 0.001, "a full patch at its glow")
	check(absf(lone - whole * 0.5) < 0.001, "a lone cell at half")
	var middle := Vector2(lights.rows[SpellLightScript.ROW_X], lights.rows[SpellLightScript.ROW_Y])
	check(absf(middle.distance_to(laid.origin + Vector2(16.0, 16.0)) - 0.0) < 0.01, "at its cells' middle")
	# Spent: the glow eases out, then the cells leave the list.
	for cell: int in [0, 1, 8, 9, 20]:
		flat.show_cell(cell, laid.columns, _state(&"spent"), 2.0)
	lights.begin()
	flat.write_lights(lights, 2.0 + CoverLightsScript.EASE_SECONDS * 0.5)
	check_equal(lights.count, 2, "easing out")
	check(lights.rows[strength_at] < whole, "dimmer as it eases out")
	lights.begin()
	flat.write_lights(lights, 2.0 + CoverLightsScript.EASE_SECONDS * 1.01)
	check_equal(lights.count, 0, "out")
	check_equal(flat.glowing_count(), 0, "and no cell kept")


func test_a_renewal_restarts_nothing() -> void:
	var laid := _layout()
	var flat := _flat(laid)
	var lights: CoverLightsScript = CoverLightsScript.new()
	flat.show_cell(3, laid.columns, _state(&"live"), 1.0)
	flat.show_cell(3, laid.columns, _state(&"live"), 1.1)
	lights.begin()
	flat.write_lights(lights, 1.0 + CoverLightsScript.EASE_SECONDS * 1.01)
	check_equal(lights.count, 1, "lit from its first change, not the renewal")


func test_the_lights_have_a_limit() -> void:
	var laid := _layout(40, 30)
	var flat := _flat(laid)
	var lights: CoverLightsScript = CoverLightsScript.new()
	for cell in laid.columns * laid.rows:
		flat.show_cell(cell, laid.columns, _state(&"live"), 0.0)
	lights.begin()
	flat.write_lights(lights, 1.0)
	check_equal(lights.count, CoverLightsScript.MOST, "a lake past the limit lights MOST patches")


func test_low_effects_hold_the_floor_still() -> void:
	var low: EffectsQualityScript = EffectsQualityScript.new(EffectsQualityScript.Level.LOW)
	var high: EffectsQualityScript = EffectsQualityScript.new(EffectsQualityScript.Level.HIGH)
	check_equal(low.floor_motes, 0.0, "Low: none of the floor's motes")
	check(not low.floor_shimmer, "Low: no shimmer")
	check_equal(high.floor_motes, 1.0, "High: every mote")
	check(high.floor_shimmer, "High: shimmer")
	var laid := _layout()
	var flat := _flat(laid)
	flat.set_shimmer(false)
	check_equal((flat.material as ShaderMaterial).get_shader_parameter(&"shimmer"), false, "the shader told")
	check_equal((flat.material as ShaderMaterial).get_shader_parameter(&"art_detail"), ArtDetail.DETAIL, "drawn at the 64-px detail")


func test_the_floor_motes_follow_the_share() -> void:
	var laid := _layout()
	var motes: CoverMotesScript = CoverMotesScript.new()
	motes.lay(laid)
	motes.flat_share = 0.0
	motes.show(4, _state(&"live"))
	check_equal(motes.cells_giving_off(&"floor", _state(&"live")), 1, "the cell is kept")
	# With no pool nothing is thrown, and with a zero share nothing is owed: a frame rolls none.
	motes.give_off(0.0, null)
	motes.give_off(0.1, null)
	check_equal(motes.given, 0, "none given off")


func test_a_frame_of_lights_allocates_nothing() -> void:
	var laid := _layout(20, 12)
	var flat := _flat(laid)
	var lights: CoverLightsScript = CoverLightsScript.new()
	for cell in 60:
		flat.show_cell(cell, laid.columns, _state(&"live"), 0.0)
	lights.begin()
	flat.write_lights(lights, 0.5)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		lights.begin()
		flat.write_lights(lights, 0.5 + frame * 0.001)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "no object made")


func test_a_cell_knows_its_drawn_neighbours() -> void:
	var laid := _layout()
	var flat := _flat(laid)
	check_equal(flat.neighbours_drawn(9), 0, "dry round it")
	flat.show_cell(0, laid.columns, _state(&"wet"), 1.0)
	flat.show_cell(10, laid.columns, _state(&"ice"), 1.0)
	# Cell 9 is (1, 1): 0 is its up-left (bit 4), 10 its right (bit 1).
	check_equal(flat.neighbours_drawn(9), 16 | 2, "its up-left and right neighbours drawn")
	flat.show_cell(10, laid.columns, _state(&"dry"), 2.0)
	check_equal(flat.neighbours_drawn(9), 16, "a neighbour dried is no longer drawn")
	flat.show_cell(9, laid.columns, _state(&"wet"), 2.0)
	check_equal(flat.neighbours_drawn(0), 128, "and it is the down-right of cell 0")
