extends "res://tests/support/suite.gd"
## Cues in gameplay/feel (`play_cue`, `cue_shown`): a cue is a `CueBase` file in `content/cues/`
## that says a moment's flashes and weight. Blast's (the owner's picks, 2026-10-29) is the ragged
## shell, fragments and rubble flung past the radius, a scorch under the bodies, a shake and a
## punch away from the caster; the rising fireball is a barrel's; the quake is a ground strike.
## A cue made in the test checks each key on its own.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")


## The real cues, and one more made in the test.
class CuesRegistry:
	extends RegistryScript
	var extra: CueBase = null

	func get_resource(folder: StringName, id: StringName) -> Resource:
		if extra != null and folder == &"cues" and id == extra.id:
			return extra
		return super(folder, id)


var bus: EventsScript
var feel: FeelScript
var registry: CuesRegistry


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	feel.events = bus
	feel.actors = own(ActorSeats.table(4)) as ActorSeats.ActorsScript
	feel.drive_engine = false
	feel.preset = FeelPresetScript.new()
	registry = own(CuesRegistry.new()) as CuesRegistry
	registry.scan()
	feel.registry = registry
	root.add_child(feel)


func _cue(id: StringName, at: Vector2 = Vector2(100.0, 50.0), size: float = 40.0) -> void:
	bus.cue_shown.emit(0, id, at, Vector2.ZERO, size, Color.WHITE, 0)


func _made(parts: Array[Dictionary]) -> CueBase:
	var cue := CueBase.new()
	cue.id = &"test_cue"
	cue.parts = parts
	registry.extra = cue
	return cue


## Its fragments and rubble are motes and its scorch a floor mark since S3 (test_motes.gd,
## test_marks.gd): the cue's flash is the shell alone.
func test_a_blast_is_the_ragged_shell() -> void:
	_cue(&"blast")
	check_equal(feel.flashes_of(&"shell"), 1, "the ragged shell")
	check_equal(feel.live_flashes(), 1, "and no other flash")
	check_equal(feel.flashes_of(&"fireball"), 0, "no fireball")
	check_equal(feel.flash_info(&"shell").get("zoom"), 20, "its radius is the zoom x 2")


func test_the_shell_is_over_the_bodies() -> void:
	_cue(&"blast")
	feel.step(0.02)
	check_equal(feel._blast_node.multimesh.visible_instance_count, 1, "the shell in the blast batch")
	check(feel._blast_node.z_index > 40, "over the enemies (entities.gd DRAW_Z 40)")
	check_equal(feel._flash_node.multimesh.visible_instance_count, 0, "nothing in the flares' batch")


func test_each_part_lasts_its_own_seconds() -> void:
	_cue(&"blast")
	feel.step(feel.flash_kind(&"shell").seconds + 0.01)
	check_equal(feel.flashes_of(&"shell"), 0, "the shell is gone after its seconds")


func test_a_blast_shakes_and_punches_away_from_its_caster() -> void:
	var body := Node2D.new()
	root.add_child(body)
	own(body)
	body.global_position = Vector2(0.0, 50.0)
	feel.actors.set_node(0, body)
	_cue(&"blast")
	check(is_equal_approx(feel.trauma(), feel.cue_of(&"blast").shake), "a shake")
	check(feel.kick().x > 0.0 and is_zero_approx(feel.kick().y), "a punch away from the caster: %s" % [feel.kick()])


func test_away_with_no_body_to_push_from_punches_down() -> void:
	bus.cue_shown.emit(-1, &"blast", Vector2(10.0, 10.0), Vector2.ZERO, 40.0, Color.WHITE, 0)
	check(feel.kick().y > 0.0 and is_zero_approx(feel.kick().x), "down the screen")


func test_the_shake_setting_turns_its_weight_off() -> void:
	feel.shake_enabled = false
	_cue(&"blast")
	check_equal(feel.trauma(), 0.0, "no shake")
	check_equal(feel.kick(), Vector2.ZERO, "no punch")
	check_equal(feel.flashes_of(&"shell"), 1, "the explosion still shows")


func test_the_rising_fireball_is_a_cue_of_its_own() -> void:
	_cue(&"fireball")
	check_equal(feel.flashes_of(&"fireball"), 1, "the rising fireball")
	check_equal(feel.flashes_of(&"shell"), 0, "not the shell")


func test_the_quake_strikes_the_ground() -> void:
	_cue(&"quake", Vector2(20.0, 0.0), 16.0)
	check_equal(feel.flashes_of(&"quake"), 1, "a mark on the floor")
	check_equal(feel.flash_info(&"quake").get("zoom"), roundi(16.0 * 1.5 / feel.flash_kind(&"quake").step), "out past its reach")
	check(feel.kick().y > 0.0, "a punch down the screen")


func test_an_unknown_cue_shows_nothing() -> void:
	_cue(&"no_such_cue")
	check_equal(feel.live_flashes(), 0, "nothing")
	check_equal(feel.trauma(), 0.0, "no shake")


func test_a_new_cue_is_data_alone() -> void:
	_made([{"flash": &"fireball", "reach": 1.0}])
	_cue(&"test_cue")
	check_equal(feel.flashes_of(&"fireball"), 1, "the part it names")
	check_equal(feel.live_flashes(), 1, "only that")
	check_equal(feel.trauma(), 0.0, "no weight it does not ask for")


func test_a_part_sizes_by_zoom_or_by_the_cues_size() -> void:
	_made([{"flash": &"burst", "zoom": 3}, {"flash": &"ring_out", "reach": 1.0}])
	_cue(&"test_cue", Vector2.ZERO, 30.0)
	check_equal(feel.flash_info(&"burst").get("zoom"), 3, "a fixed zoom")
	check_equal(feel.flash_info(&"ring_out").get("zoom"), 3, "a ring of 30 px: 10 px a step")


func test_a_part_can_take_an_exact_colour_or_be_plain() -> void:
	_made([{"flash": &"burst", "color": Color.RED}, {"flash": &"ring_out", "plain": true}])
	bus.cue_shown.emit(1, &"test_cue", Vector2.ZERO, Vector2.ZERO, 0.0, Color.BLUE, 5)
	check_equal(feel.flash_dress(&"burst"), [Color.RED, FeelScript.EXACT], "its own colour, exactly")
	check_equal(feel.flash_dress(&"ring_out"), [Color.WHITE, 0], "white, no cards")


func test_a_part_faces_the_way_it_says() -> void:
	_made([{"flash": &"burst"}, {"flash": &"spray", "way": &"back"}, {"flash": &"puff", "way": &"up"}])
	bus.cue_shown.emit(0, &"test_cue", Vector2.ZERO, Vector2.LEFT, 0.0, Color.WHITE, 0)
	check_equal(feel.flash_info(&"burst").get("dir"), Vector2.LEFT, "the cue's way")
	check_equal(feel.flash_info(&"spray").get("dir"), Vector2.RIGHT, "against it")
	check_equal(feel.flash_info(&"puff").get("dir"), Vector2.UP, "up the screen")


func test_a_part_can_last_the_cues_size_in_seconds() -> void:
	_made([{"flash": &"ring_in", "zoom": 2, "lasts_size": true}, {"flash": &"burst"}])
	_cue(&"test_cue", Vector2.ZERO, 0.6)
	check(is_equal_approx(feel.flash_info(&"ring_in")["seconds"], 0.6), "as long as the cue is big")
	check_equal(feel.flash_info(&"ring_in").get("zoom"), 2, "its zoom still its own")
	check(is_equal_approx(feel.flash_info(&"burst")["seconds"], feel.flash_kind(&"burst").seconds), "the other parts keep theirs")
	feel.step(feel.flash_kind(&"burst").seconds + 0.4)
	_cue(&"test_cue", Vector2.ZERO, 0.0)
	check_equal(feel.flashes_of(&"ring_in"), 0, "left out when the cue's size is 0")
	check_equal(feel.flashes_of(&"burst"), 1, "the rest still shows")


func test_the_telegraph_closes_on_its_point_for_its_seconds() -> void:
	_cue(&"telegraph", Vector2(40.0, 40.0), 0.6)
	check_equal(feel.flashes_of(&"ring_in"), 1, "a ring closing")
	check_equal(feel.flash_info(&"ring_in").get("zoom"), 2, "2 steps across")
	check_equal(feel.flash_info(&"ring_in").get("dir"), Vector2.RIGHT, "upright")
	feel.step(0.5)
	check_equal(feel.flashes_of(&"ring_in"), 1, "still there just before")
	feel.step(0.2)
	check_equal(feel.flashes_of(&"ring_in"), 0, "gone when the wait is over")


func test_the_nova_is_a_ring_120_px_across_for_a_quarter_second() -> void:
	_cue(&"nova", Vector2(50.0, 60.0), 0.0)
	check_equal(feel.flashes_of(&"ring_out"), 1, "a ring flashes out")
	check_equal(feel.flash_info(&"ring_out").get("zoom"), 6, "6 steps of 20 px across")
	check(is_equal_approx(feel.flash_info(&"ring_out")["seconds"], 0.25), "a quarter second")
	check_equal(feel.trauma(), 0.0, "no weight")


func test_the_slam_is_a_star_and_the_ground_struck() -> void:
	_cue(&"slam", Vector2(20.0, 0.0), 16.0)
	check_equal(feel.flashes_of(&"burst"), 1, "a white-hot star")
	check_equal(feel.flash_info(&"burst").get("zoom"), 3, "3 steps big")
	check_equal(feel.flashes_of(&"quake"), 1, "cracks in the floor")
	check_equal(feel.flash_info(&"quake").get("zoom"), roundi(16.0 * 1.5 / feel.flash_kind(&"quake").step), "out past its reach")
	var quake: CueBase = feel.cue_of(&"quake")
	var slam: CueBase = feel.cue_of(&"slam")
	# A slam hits harder than the ground merely shaking (the owner, 2026-11-08: "it should really
	# look like it hits hard"): at least the quake's weight, punched the same way.
	check(slam.shake >= quake.shake and slam.kick >= quake.kick and slam.hold >= quake.hold and slam.kick_way == quake.kick_way, "at least the quake's weight")


func test_a_flash_part_on_the_floor_is_drawn_under_the_bodies() -> void:
	# A cue part's `floor` (a ground strike's flash): the floor batch, under the bodies, while the
	# same kind with no `floor` (every other cue's burst) stays over everything.
	var cue: CueBase = _made([{"flash": &"burst", "zoom": 2, "floor": true}, {"flash": &"burst", "zoom": 2}])
	check(cue.problems().is_empty(), "`floor` is a flash part's key: %s" % [cue.problems()])
	_cue(&"test_cue")
	feel.step(0.01)
	check_equal(feel._floor_node.multimesh.visible_instance_count, 1, "the one with `floor` on the floor")
	check_equal(feel._flash_node.multimesh.visible_instance_count, 1, "the other over everything")
	check(feel._floor_node.z_index < feel._flash_node.z_index, "the floor under the flashes")


func test_particles_off_leaves_out_the_parts_that_say_so() -> void:
	feel.particles_enabled = false
	_cue(&"appear")
	check_equal(feel.flashes_of(&"spray"), 0, "no spray")
	check_equal(feel.flashes_of(&"fall"), 1, "the column still shows")


## A cue's holds and game stop are the game's (`HitStop`, online-ready N4): Feel plays the cue and
## holds nobody.
func test_feel_plays_a_cues_holds_as_nothing() -> void:
	var cue: CueBase = _made([])
	cue.hold = 0.05
	cue.hold_target = 0.07
	cue.stop_game = 0.1
	feel.play_cue(&"test_cue", 0, Vector2.ZERO, Vector2.ZERO, 0.0, Color.WHITE, 0, 2)
	check_equal(feel.actors.held_count, 0, "nobody held by Feel")


func test_kick_ways() -> void:
	var cue: CueBase = _made([])
	cue.kick = 2.0
	for row: Array in [[&"down", Vector2.DOWN], [&"back", Vector2.RIGHT], [&"aim", Vector2.LEFT]]:
		cue.kick_way = row[0]
		feel.shake_enabled = false
		feel.shake_enabled = true
		bus.cue_shown.emit(0, &"test_cue", Vector2.ZERO, Vector2.LEFT, 0.0, Color.WHITE, 0)
		check(feel.kick().normalized().is_equal_approx(row[1]), "%s: %s" % [row[0], feel.kick()])


func test_a_big_cue_draws_bigger_and_a_small_one_smaller() -> void:
	_cue(&"blast", Vector2.ZERO, 100.0)
	check_equal(feel.flash_info(&"shell").get("zoom"), 50, "100 px: zoom 50")
	feel.step(feel.flash_kind(&"shell").seconds + 0.1)
	_cue(&"blast", Vector2.ZERO, 1.0)
	check_equal(feel.flash_info(&"shell").get("zoom"), 1, "the smallest is zoom 1")


## No cue is capped in size (the owner, 2026-11-09): a flash is drawn as big as its cue asks, past
## the 63 the look's red byte holds (an explosion was capped at 126 px round, a table flash at zoom
## 15, an arc at 252 px), and the shaders read its size from its row's transform, which says so.
func test_a_huge_cue_is_drawn_whole() -> void:
	_cue(&"blast", Vector2.ZERO, 400.0)
	check_equal(feel.flash_info(&"shell").get("zoom"), 200, "a 400 px blast: zoom 200")
	feel.step(0.001)
	var blast: PackedFloat32Array = feel._blast_node.multimesh.buffer
	var side: float = Vector2(blast[1], blast[5]).length()
	check_equal(roundi(side / (4.0 * FeelScript.BLAST_SPAN)), 200, "its square tells the shader zoom 200: %s px" % side)
	feel.step(feel.flash_kind(&"shell").seconds + 0.1)

	var ring: FlashKind = feel.flash_kind(&"ring_out")
	_made([{"flash": &"ring_out", "reach": 1.0}])
	_cue(&"test_cue", Vector2.ZERO, 1000.0)
	var zoom: int = roundi(1000.0 / ring.step)
	check(zoom > 15, "a zoom past the old 15: %d" % zoom)
	check_equal(feel.flash_info(&"ring_out").get("zoom"), zoom, "a 1000 px ring at its zoom")
	feel.step(0.001)
	var flash: PackedFloat32Array = feel._flash_node.multimesh.buffer
	side = Vector2(flash[1], flash[5]).length()
	check_equal(roundi(side / FeelScript.FLASH_GRID), zoom, "its square tells the shader so: %s px" % side)
	feel.step(ring.seconds + 0.1)

	feel.show_flash(&"arc", Vector2.ZERO, Vector2.RIGHT, Color.WHITE, 0, 0, 1, 0.5, 600.0)
	check_equal(feel.flash_info(&"arc").get("zoom"), 150, "a 600 px arc: 150 steps of 4")
	feel.step(0.001)
	var arc: PackedFloat32Array = feel._arc_node.multimesh.buffer
	var along: float = Vector2(arc[0], arc[4]).length() - 2.0 * FeelScript.ARC_MARGIN
	check(is_equal_approx(along, 600.0), "its quad is 600 px long past its margins: %s" % along)


## Every flash kind of the content is one Feel draws: a code and a row for a cue's part each.
func test_every_flash_kind_is_drawn() -> void:
	var rows: Dictionary = feel.get("_flash_rows") as Dictionary
	for found: Resource in registry.get_all(&"flashes"):
		var kind: FlashKind = found as FlashKind
		check(rows.has(kind.id), "%s is drawn" % kind.id)
	check(rows.size() >= 14, "every kind (%d)" % rows.size())


func test_a_death_plays_its_cue() -> void:
	var cue: CueBase = feel.cue_of(&"enemy_death")
	bus.enemy_died.emit(0, null, Vector2(30.0, 30.0), -1)
	check_equal(feel.flash_dress(&"ring_out"), [cue.parts[0]["color"], FeelScript.EXACT], "the white-hot ring, exactly its colour")
	check_equal(feel.flash_info(&"ring_out").get("zoom"), cue.parts[0]["zoom"], "as big as the cue says")
	check(is_equal_approx(feel.trauma(), cue.shake), "a shake")
	check_equal(feel.flashes_of(&"puff"), 1, "and its puff")


func test_a_downed_wizard_plays_its_cue() -> void:
	var cue: CueBase = feel.cue_of(&"player_downed")
	bus.player_downed.emit(1)
	check(is_equal_approx(feel.trauma(), cue.shake), "a shake")
	check_equal(feel.live_flashes(), 0, "nothing drawn: the event names no position")
	check_equal(feel.actors.held_count, 0, "nobody held")


func test_a_heal_plays_its_cue() -> void:
	var cue: CueBase = feel.cue_of(&"heal")
	bus.heal_dealt.emit(0, null, 5, Vector2(10.0, 10.0))
	check_equal(feel.flash_dress(&"ring_out"), [cue.parts[0]["color"], FeelScript.EXACT], "a ring in exactly its colour")
	check_equal(feel.flash_info(&"ring_out").get("zoom"), cue.parts[0]["zoom"], "as big as the cue says")
	check_equal(feel.trauma(), 0.0, "no shake")


## Cue parts are played by type from a table (docs/milestones/spell-spectacle-2.md, S1): a part
## type added at run time plays with the cue's context, and a part of a type nothing plays is
## skipped and counted.
func test_a_part_type_added_at_run_time_plays() -> void:
	var played: Array = []
	feel.add_cue_part(&"test_part", func(part: Dictionary, cue: RefCounted) -> void:
		played.append([part.get("size_x", 0), cue.get(&"at"), cue.get(&"size"), cue.get(&"ramp"), cue.get(&"surface")]))
	_made([{"part": &"test_part", "size_x": 3}, {"flash": &"burst"}])
	feel.play_cue(&"test_cue", 1, Vector2(10.0, 20.0), Vector2.UP, 30.0, Color.WHITE, 0, -1, -1, 7)
	check_equal(played.size(), 1, "played once")
	check_equal(played[0], [3, Vector2(10.0, 20.0), 30.0, feel._ramp_of(1), 7], "with the part and the cue's context, what broke too")
	check_equal(feel.flashes_of(&"burst"), 1, "and the cue's other parts as before")
	check(feel.has_cue_part(&"flash") and feel.has_cue_part(&"motes") and feel.has_cue_part(&"mark"), "Feel's flashes and the spectacle's motes and marks are in the table")


func test_a_part_nothing_plays_is_skipped_and_counted() -> void:
	_made([{"part": &"nobody_plays_this"}, {"flash": &"burst"}])
	_cue(&"test_cue")
	check_equal(feel.unknown_cue_parts, 1, "counted")
	check_equal(feel.flashes_of(&"burst"), 1, "the rest still plays")


## One context per depth is kept and filled for every cue: playing cues allocates none.
func test_a_cue_reuses_its_context() -> void:
	_made([{"flash": &"burst"}])
	_cue(&"test_cue")
	var made: int = feel._cue_contexts.size()
	for i in 20:
		_cue(&"test_cue", Vector2(float(i), 0.0))
	check_equal(feel._cue_contexts.size(), made, "no new context")
	check_equal(feel._cue_depth, 0, "and none left in use")


## A cue played from inside a part gets a context of its own; the outer one is left as it was.
func test_a_cue_inside_a_part_has_its_own_context() -> void:
	var seen: Array = []
	feel.add_cue_part(&"inner", func(_part: Dictionary, cue: RefCounted) -> void:
		seen.append(cue.get(&"at")))
	feel.add_cue_part(&"outer", func(_part: Dictionary, cue: RefCounted) -> void:
		feel.play_cue(&"test_cue_inner", 0, Vector2(5.0, 5.0))
		seen.append(cue.get(&"at")))
	var inner := CueBase.new()
	inner.id = &"test_cue_inner"
	inner.parts = [{"part": &"inner"}]
	feel._cue_cache[&"test_cue_inner"] = inner
	_made([{"part": &"outer"}])
	_cue(&"test_cue", Vector2(100.0, 50.0))
	check_equal(seen, [Vector2(5.0, 5.0), Vector2(100.0, 50.0)], "the inner cue's point, then the outer's still")


## A part's way: along the cue, against it, right or up.
func test_a_parts_way_comes_from_the_cue() -> void:
	var cue := FeelScript.CueContextScript.new()
	cue.aim = Vector2.DOWN
	check_equal(cue.way_of({}), Vector2.DOWN, "along the cue by default")
	check_equal(cue.way_of({"way": &"back"}), Vector2.UP, "back")
	check_equal(cue.way_of({"way": &"right"}), Vector2.RIGHT, "right")
	check_equal(cue.way_of({"way": &"up"}), Vector2.UP, "up")


## S6 2: a cue is read once for playing (`CuePlan`): each part prepared once by its type's
## `prepare`, then played from that; a new part player reads the cues again.
func test_a_cues_parts_are_prepared_once() -> void:
	var prepared: Array[int] = [0]
	var played: Array = []
	feel.add_cue_part(&"test_part", func(made: Variant, _cue: RefCounted) -> void: played.append(made),
		func(part: Dictionary) -> Variant:
			prepared[0] += 1
			return int(part["size_x"]) * 10)
	_made([{"part": &"test_part", "size_x": 3}, {"flash": &"burst", "zoom": 2}])
	for i in 3:
		_cue(&"test_cue")
	check_equal(prepared[0], 1, "prepared once")
	check_equal(played, [30, 30, 30], "and played from what it made")
	check_equal(feel.flashes_of(&"burst"), 3, "a flash part is prepared too, and plays")
	check_equal(feel.flash_info(&"burst").get("zoom"), 2, "with its keys")
	feel.add_cue_part(&"test_part", func(made: Variant, _cue: RefCounted) -> void: played.append(-1),
		func(_part: Dictionary) -> Variant: return 0)
	_cue(&"test_cue")
	check_equal(played.back(), -1, "a new player reads the cue again")


func test_a_flash_part_is_read_into_typed_fields() -> void:
	var flash: FeelScript.CuePlanScript.Flash = FeelScript.CuePlanScript.flash_of({"flash": &"ring_out", "zoom": 3, "way": &"up", "no_cards": true, "if_layer": 5}, feel.get("_flash_rows") as Dictionary)
	check_equal(flash.kind, int((feel.get("_flash_codes") as Dictionary)[&"ring_out"]), "its flash")
	check_equal(flash.zoom, 3.0, "its zoom")
	check_equal(flash.way, FeelScript.CuePlanScript.WAY_UP, "its way")
	check_equal(flash.paint, FeelScript.CuePlanScript.PAINT_NO_CARDS, "its colours")
	check(flash.gated and flash.if_layer == 5, "and its gate")
	check(FeelScript.CuePlanScript.flash_of({"flash": &"nothing"}, feel.get("_flash_rows") as Dictionary) == null, "a flash Feel has not: none")


## A cue with an `every` plays at most that often for one actor, parts and weight (S6, item 13: a
## moment that may come hundreds of times a second); another actor's play is its own.
func test_a_cue_with_every_plays_at_most_that_often_per_actor() -> void:
	var cue: CueBase = _made([{"flash": &"burst", "zoom": 1, "seconds": 2.0}])
	cue.every = 0.5
	cue.shake = 0.2
	check(cue.problems().is_empty(), "a valid cue: %s" % [cue.problems()])
	bus.cue_shown.emit(0, &"test_cue", Vector2(10.0, 0.0), Vector2.ZERO, 0.0, Color.WHITE, 0)
	var trauma: float = feel._trauma
	bus.cue_shown.emit(0, &"test_cue", Vector2(20.0, 0.0), Vector2.ZERO, 0.0, Color.WHITE, 0)
	check_equal(feel.flashes_of(&"burst"), 1, "played once for actor 0")
	check_equal(feel._trauma, trauma, "and its weight once")
	bus.cue_shown.emit(1, &"test_cue", Vector2(30.0, 0.0), Vector2.ZERO, 0.0, Color.WHITE, 0)
	check_equal(feel.flashes_of(&"burst"), 2, "actor 1's is its own")
	feel.step(0.25)
	bus.cue_shown.emit(0, &"test_cue", Vector2(40.0, 0.0), Vector2.ZERO, 0.0, Color.WHITE, 0)
	check_equal(feel.flashes_of(&"burst"), 2, "not again within its every")
	feel.step(0.26)
	bus.cue_shown.emit(0, &"test_cue", Vector2(50.0, 0.0), Vector2.ZERO, 0.0, Color.WHITE, 0)
	check_equal(feel.flashes_of(&"burst"), 3, "again once its every is over")
	cue.every = -1.0
	check(not cue.problems().is_empty(), "an every below 0 is a problem")


## The moments that had no look (S6, item 13) each have a cue file, played by name from their area.
func test_the_new_moments_have_cues() -> void:
	for id: StringName in [&"revive", &"shield_block", &"pull", &"wave_start"]:
		var cue: CueBase = feel.cue_of(id)
		check(cue != null, "%s is a cue file" % id)
		if cue != null:
			check(not cue.parts.is_empty(), "%s shows something" % id)
	check(feel.cue_of(&"pull").every > 0.0, "a pull is throttled")


## A light part's keys are checked like any part's (S6, item 4).
func test_a_light_part_is_checked() -> void:
	var cue: CueBase = _made([{"part": &"light", "radius": 30.0, "strength": 1.0, "seconds": 0.3, "bare": true}])
	check(cue.problems().is_empty(), "a valid light part: %s" % [cue.problems()])
	check(cue.lights(), "it lights")
	for bad: Dictionary in [{"part": &"light", "strength": 3.0}, {"part": &"light", "seconds": 0.0}, {"part": &"light", "radius": -1.0}, {"part": &"light", "bare": true, "plain": true}, {"part": &"light", "zoom": 2}]:
		var wrong := CueBase.new()
		wrong.id = &"wrong"
		wrong.parts = [bad]
		check(not wrong.problems().is_empty(), "%s is a problem" % [bad])
	check(not feel.cue_of(&"blast").lights(), "a cue with no light part lights by its flashes")
	check(feel.has_cue_part(&"light"), "a light part has a player")


## A hit's look is not played when it would show nothing (most of a crowd's hits): its flashes past
## the frame's share of hit flashes and its parts that need a spray on a hit whose motes do not spray.
## `probe` needs a spray, `steady` plays whatever the hit (as a mark does); each counts its plays.
func _probe_parts(played: Array[StringName]) -> void:
	feel.add_cue_part(&"probe", func(_part: Dictionary, _cue: RefCounted) -> void: played.append(&"probe"),
		Callable(), func(_part: Dictionary) -> bool: return true)
	feel.add_cue_part(&"steady", func(_part: Dictionary, _cue: RefCounted) -> void: played.append(&"steady"))


## Plays `test_cue` as the look of a hit: past the frame's share of hit flashes or not (`full`), its
## motes sprayed or not (`sprayed`; a framed hit, as Feel's impact and damage frame theirs).
func _play_as_hit(full: bool, sprayed: bool, hit: bool = true) -> void:
	feel._flashes_shown = feel.effect_slots if full else 0
	feel.spectacle().hold_hit(0, 0, sprayed)
	feel._hit_flash = hit
	feel.play_cue(&"test_cue", 0, Vector2(100.0, 50.0), Vector2.RIGHT, 20.0)
	feel._hit_flash = false
	feel.spectacle().end_hit()


func test_a_hit_look_that_shows_nothing_is_not_played() -> void:
	var played: Array[StringName] = []
	_probe_parts(played)
	_made([{"flash": &"spray", "reach": 1.0}, {"part": &"probe"}] as Array[Dictionary])
	_play_as_hit(true, false)
	check_equal(played, [] as Array[StringName], "past the share and not sprayed: none of its parts played")
	check_equal(feel.live_flashes(), 0, "and no flash shown")
	_play_as_hit(false, false)
	check_equal(feel.flashes_of(&"spray"), 1, "under the share its flash is shown")
	check_equal(played, [&"probe"] as Array[StringName], "and the cue played")


func test_a_sprayed_hit_plays_its_look_past_the_flash_share() -> void:
	if feel.motes() == null:
		return
	var played: Array[StringName] = []
	_probe_parts(played)
	_made([{"flash": &"spray", "reach": 1.0}, {"part": &"probe"}] as Array[Dictionary])
	_play_as_hit(true, true)
	check_equal(played, [&"probe"] as Array[StringName], "a sprayed hit past the share plays its parts")
	check_equal(feel.live_flashes(), 0, "but not its flash")


func test_a_part_that_plays_whatever_the_hit_keeps_its_cue() -> void:
	var played: Array[StringName] = []
	_probe_parts(played)
	_made([{"flash": &"spray", "reach": 1.0}, {"part": &"probe"}, {"part": &"steady"}] as Array[Dictionary])
	_play_as_hit(true, false)
	check(played.has(&"steady"), "a part with no spray gate (a mark, a light) plays for a hidden hit: %s" % [played])


func test_a_weighted_cue_or_one_not_of_a_hit_is_played() -> void:
	var played: Array[StringName] = []
	_probe_parts(played)
	var cue: CueBase = _made([{"part": &"probe"}] as Array[Dictionary])
	_play_as_hit(true, false, false)
	check_equal(played, [&"probe"] as Array[StringName], "a cue played as no hit's look is played")
	played.clear()
	cue.shake = 0.2
	feel.forget_cues()
	_play_as_hit(true, false)
	check_equal(played, [&"probe"] as Array[StringName], "a cue with weight (its shake) is played for a hidden hit")
