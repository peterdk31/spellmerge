extends "res://tests/support/suite.gd"
## Shadows (docs/milestones/atmosphere.md, C): light blocked by a room's standing walls and the props
## that block light (gameplay/feel/light_blockers.gd, handed to the spell light, `light.gdshader`'s
## blockers, whose pick `LightBlockers.shade_between` mirrors), easing out as a pillar crumbles; and
## the bodies' short hard shadows cast away from the light near them (gameplay/feel/body_shadows.gd),
## easing as lights move, in whole pixels, taking the drawn shadows' place. Only while spell light is
## on; a frame allocates nothing. How it looks is checked by eye
## (tests/screenshots/shot_atmosphere_shadows.gd): headless runs draw nothing.

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const LightBlockersScript := preload("res://gameplay/feel/light_blockers.gd")
const BodyShadowsScript := preload("res://gameplay/feel/body_shadows.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const CarriedLightsScript := preload("res://gameplay/feel/carried_lights.gd")
const PILLAR: PropBase = preload("res://content/props/crypt_pillar/crypt_pillar.tres")
const CRACKED_PILLAR: PropBase = preload("res://content/props/cracked_pillar/cracked_pillar.tres")

## One frame of Feel's clock (s).
const FRAME: float = 1.0 / 60.0
## The crypt's rooms.
const CRYPT_ROOMS: Array[StringName] = [&"arena_01", &"arena_02", &"arena_03", &"arena_04", &"boss_broom"]

var _world: Fixture
var _clock: float = 0.0


func before_each() -> void:
	_world = Fixture.new(root)
	_clock = 0.0


func after_each() -> void:
	_world.free_all()


## A crypt pillar standing with its feet at `at`.
func _pillar(at: Vector2) -> Actor:
	return _world.add(PropBody.make(PILLAR), at)


## A body that walks, its feet at `at`.
func _walker(at: Vector2) -> Actor:
	return _world.actor(at, [&"mover"])


## A spot row buffer of the lights `lights` ([where, reach, strength] each).
static func _rows(lights: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	rows.resize(lights.size() * SpellLightScript.STRIDE)
	for at in lights.size():
		var light: Array = lights[at]
		SpellLightScript.write_spot_row(rows, at, light[0], light[1], Color.WHITE, light[2], 0.0, 0.0)
	return rows


# --- What blocks light ----------------------------------------------------------------------------

func test_only_walls_standing_inside_the_room_block() -> void:
	var rects: Array[Rect2] = [
		Rect2(0.0, 0.0, 400.0, 16.0), # the north edge
		Rect2(0.0, 16.0, 16.0, 284.0), # the west edge, joined to it
		Rect2(16.0, 60.0, 30.0, 20.0), # a jut joined to the west edge
		Rect2(384.0, 290.0, 16.0, 10.0), # the box round them all ends here: an edge too
		Rect2(120.0, 120.0, 64.0, 32.0), # a sarcophagus in the middle
		Rect2(200.0, 200.0, 32.0, 32.0), # a pillar wall
	]
	var standing: Array[Rect2] = LightBlockersScript.standing(rects)
	check_equal(standing, [rects[4], rects[5]] as Array[Rect2], "the walls joined to the room's edge are not blockers")
	check_equal(LightBlockersScript.standing([] as Array[Rect2]), [] as Array[Rect2], "no walls: none")


func test_every_crypt_rooms_own_walls_block_and_all_fit() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	for id in CRYPT_ROOMS:
		var room := registry.get_resource(&"rooms", id) as RoomBase
		var layout: Node = room.build()
		var standing: Array[Rect2] = LightBlockersScript.standing(RoomPlaces.wall_rects(layout))
		var own_walls: int = 0
		var walls := layout.get_node_or_null(^"Walls")
		if walls != null:
			for child in walls.get_children():
				if child is CollisionShape2D:
					own_walls += 1
		check_equal(standing.size(), own_walls, "%s: its own walls (not its ground's edge) block light" % id)
		var pillars: int = 0
		for node: Node in layout.find_children("*", "", true, false):
			var data: Variant = node.get(&"prop")
			if data is PropBase and (data as PropBase).blocks_light:
				pillars += 1
		check(standing.size() + pillars <= LightBlockersScript.MAX, "%s: its %d walls and %d pillars fit the %d boxes" % [id, standing.size(), pillars, LightBlockersScript.MAX])
		layout.free()


func test_the_pillars_block_light_and_other_props_do_not() -> void:
	check(PILLAR.blocks_light and CRACKED_PILLAR.blocks_light, "the crypt's pillars block light")
	check(not PropBase.new().blocks_light, "a prop lets light pass by default")


func test_a_pillar_blocks_by_its_ground_with_its_shaft_over_it() -> void:
	var pillar: Actor = _pillar(Vector2(100.0, 100.0))
	_walker(Vector2(200.0, 100.0))
	var blockers := LightBlockersScript.new()
	# The room's edge (two walls round it) and a wall standing inside it.
	blockers.use_walls([Rect2(0.0, 0.0, 400.0, 8.0), Rect2(0.0, 292.0, 400.0, 8.0), Rect2(300.0, 40.0, 32.0, 16.0)] as Array[Rect2])
	check(blockers.step(_world.table, _clock), "the boxes are new")
	check_equal(blockers.count, 2, "a standing wall and the pillar; the walker blocks nothing")
	check_equal(blockers.boxes[0], Vector4(300.0, 40.0, 332.0, 56.0), "the wall first")
	check_equal(blockers.bodies[0].w, 1.0, "at full strength")
	var ground: Rect2 = pillar.footprint.rect_at(pillar.global_position)
	check_equal(blockers.boxes[1], Vector4(ground.position.x, ground.position.y, ground.end.x, ground.end.y), "the pillar blocks by its ground")
	var top: float = pillar.global_position.y + PILLAR.shaft_offset.y - PILLAR.shaft_size.y * 0.5
	check_equal(top, 100.0 - 61.0, "its shaft reaches its capital (its art's top, not its hurt box's)")
	check_equal(blockers.bodies[1], Vector4(100.0 - PILLAR.shaft_size.x * 0.5, top, 100.0 + PILLAR.shaft_size.x * 0.5, 1.0), "its shaft is its art's box, at full strength as it comes")
	_clock += FRAME
	check(not blockers.step(_world.table, _clock), "nothing changed: nothing to hand over")


func test_a_crumbling_pillar_eases_its_shadow_out() -> void:
	var pillar: Actor = _pillar(Vector2(100.0, 100.0))
	var blockers := LightBlockersScript.new()
	blockers.step(_world.table, _clock)
	var shaft: Vector4 = blockers.bodies[0]
	pillar.health.empty()
	_world.run(1)
	check(not pillar.footprint.solid, "its rubble blocks no walking")
	var strengths: Array[float] = []
	var tops: Array[float] = []
	for frame in ceili(LightBlockersScript.FADE_SECONDS / FRAME) + 2:
		_clock += FRAME
		blockers.step(_world.table, _clock)
		strengths.append(blockers.bodies[0].w if blockers.count > 0 else 0.0)
		tops.append(blockers.bodies[0].y if blockers.count > 0 else blockers.boxes[0].y)
	check_equal(blockers.count, 0, "gone once eased out")
	var steps: int = 0
	for at in strengths.size():
		var before: float = 1.0 if at == 0 else strengths[at - 1]
		check(strengths[at] <= before, "it only fades")
		check(before - strengths[at] <= FRAME / LightBlockersScript.FADE_SECONDS + 0.0001, "never more than a frame's share at once")
		if strengths[at] < before:
			steps += 1
	check(steps >= 3, "the light comes back over at least 3 frames (Smooth), took %d" % steps)
	check(tops[2] > shaft.y and tops[2] < shaft.y + 52.0, "its shaft comes down with it")


func test_the_pick_blocks_only_what_stands_between() -> void:
	var boxes := PackedVector4Array([Vector4(90.0, 88.0, 110.0, 100.0)])
	var bodies := PackedVector4Array([Vector4(90.0, 40.0, 110.0, 1.0)])
	var shade := LightBlockersScript.shade_between
	check_equal(shade.call(Vector2(100.0, 140.0), Vector2(100.0, 20.0), boxes, bodies, 1), 1.0, "a light behind the box: the floor before it is dark")
	check_equal(shade.call(Vector2(60.0, 94.0), Vector2(140.0, 94.0), boxes, bodies, 1), 1.0, "a light beside it: the far side is dark")
	check_equal(shade.call(Vector2(60.0, 120.0), Vector2(140.0, 120.0), boxes, bodies, 1), 0.0, "a way past it: lit")
	check_equal(shade.call(Vector2(100.0, 94.0), Vector2(140.0, 94.0), boxes, bodies, 1), 0.0, "a pixel on the box itself is lit (its own face)")
	check_equal(shade.call(Vector2(60.0, 94.0), Vector2(100.0, 94.0), boxes, bodies, 1), 0.0, "a light standing in the box lights round it")
	check_equal(shade.call(Vector2(100.0, 60.0), Vector2(100.0, 140.0), boxes, bodies, 1), 0.0, "the shaft's face is lit from before it")
	check_equal(shade.call(Vector2(100.0, 60.0), Vector2(60.0, 94.0), boxes, bodies, 1), 0.0, "and from beside it")
	check_equal(shade.call(Vector2(100.0, 60.0), Vector2(100.0, 20.0), boxes, bodies, 1), 1.0, "not from behind it")
	check_equal(LightBlockersScript.lit_as(Vector2(95.0, 50.0), boxes, bodies, 1), Vector2(95.0, 100.5), "a light on the shaft lights from before its base")
	bodies[0] = Vector4(90.0, 40.0, 110.0, 0.25)
	check_equal(shade.call(Vector2(60.0, 94.0), Vector2(140.0, 94.0), boxes, bodies, 1), 0.25, "a fading box blocks by its strength")


func test_the_shader_has_the_picks_numbers() -> void:
	var code: String = (load("res://gameplay/feel/light.gdshader") as Shader).code
	check(code.contains("const int MAX_BLOCKERS = %d;" % LightBlockersScript.MAX), "the shader's MAX_BLOCKERS is the blockers' MAX")
	check(code.contains("uniform vec4 blocker_box[%d];" % LightBlockersScript.MAX), "and its arrays that long")
	check_equal(SpellLightScript.MAX_BLOCKERS, LightBlockersScript.MAX, "the spell light hands over as many")
	# The pick's tests, by their text (headless runs draw nothing): each line the GDScript mirrors.
	for line: String in [
			"if (body.w > 0.0 && body.y < box.y && p.x >= body.x && p.x <= body.z && p.y >= body.y && p.y <= box.w) {",
			"return k >= 0 ? vec2(p.x, blocker_box[k].w + 0.5) : p;",
			"at = vec2(p.x, blocker_box[own].w + 0.5);",
			"if (l.y < blocker_box[own].y) {",
			"if (strength <= shade || holds(box, at) || holds(box, l)) {",
			"if (crosses(at, l, box)) {",
			"COLOR = vec4(lamp * f * f * open, 1.0);"]:
		check(code.contains(line), "the shader's pick has `%s`, as light_blockers.gd's" % line)


func test_the_spell_light_hands_its_lights_the_boxes_but_not_its_shots() -> void:
	var light := SpellLightScript.new(null, 0)
	root.add_child(own(light))
	var boxes := PackedVector4Array([Vector4(0.0, 0.0, 10.0, 10.0), Vector4(20.0, 0.0, 30.0, 10.0)])
	var bodies := PackedVector4Array([Vector4(0.0, 0.0, 10.0, 1.0), Vector4(20.0, -20.0, 30.0, 0.5)])
	light.set_blockers(boxes, bodies, 2)
	check_equal(light.blocker_count(), 2, "two boxes")
	for node: MultiMeshInstance2D in [light.spots, light.carried, light.cue_lights, light.flashes[0]]:
		var material := node.material as ShaderMaterial
		check_equal(material.get_shader_parameter(&"blocker_count"), 2, "%s draws with them" % node.name)
		check_equal(material.get_shader_parameter(&"blocker_body"), bodies, "and their columns")
	for node: MultiMeshInstance2D in light.batches:
		var shot_count: Variant = (node.material as ShaderMaterial).get_shader_parameter(&"blocker_count")
		check(SpellLightScript.SHOTS_BLOCKED or shot_count == null or shot_count == 0, "a shot's light is not blocked (SHOTS_BLOCKED)")
	light.set_blockers(boxes, bodies, 99)
	check_equal(light.blocker_count(), 2, "never more than it was handed")


# --- The bodies' shadows --------------------------------------------------------------------------

func _shadows() -> BodyShadowsScript:
	var made := BodyShadowsScript.new(0)
	root.add_child(own(made))
	return made


## `frames` frames of the shadows lit by `rows` (spot rows, `count` of them).
func _shade_frames(shadows: BodyShadowsScript, rows: PackedFloat32Array, frames: int, blockers: LightBlockersScript = null) -> void:
	for frame in frames:
		shadows.begin_lights()
		shadows.add_lights(rows, rows.size() / SpellLightScript.STRIDE, SpellLightScript.SPOT_ROW_STRENGTH, PackedInt32Array())
		shadows.step(_world.table, _clock, Rect2(), blockers)
		_clock += FRAME


func test_a_body_casts_its_shadow_away_from_the_light() -> void:
	var walker: Actor = _walker(Vector2(100.0, 100.0))
	var shadows: BodyShadowsScript = _shadows()
	_shade_frames(shadows, _rows([]), 1)
	check_equal(shadows.count, 1, "a body that walks stands on a shadow")
	check_equal(shadows.cast[walker.id], Vector2.ZERO, "no light near: it lies under it")
	_shade_frames(shadows, _rows([[Vector2(80.0, 102.0), 48.0, 0.7]]), 1)
	_shade_frames(shadows, _rows([[Vector2(80.0, 102.0), 48.0, 0.7]]), 30)
	var cast: Vector2 = shadows.cast[walker.id]
	check(cast.x > 0.0 and absf(cast.y) < 0.01, "a light to its west casts it east, got %s" % cast)
	check(cast.length() <= BodyShadowsScript.LENGTH + 0.001, "at most LENGTH px")
	_shade_frames(shadows, _rows([[Vector2(100.0, 140.0), 48.0, 0.7]]), 60)
	cast = shadows.cast[walker.id]
	check(cast.y < 0.0 and absf(cast.x) < 0.01, "a light to its south casts it north, got %s" % cast)
	_shade_frames(shadows, _rows([[Vector2(60.0, 102.0), 48.0, 0.7], [Vector2(140.0, 102.0), 48.0, 0.7]]), 60)
	check(shadows.cast[walker.id].length() < 0.01, "two lights either side: they share it, no flip")
	_shade_frames(shadows, _rows([[Vector2(200.0, 100.0), 48.0, 0.7]]), 60)
	check(shadows.cast[walker.id].length() < 0.01, "a light out of reach casts nothing")


func test_its_own_light_casts_no_shadow() -> void:
	var walker: Actor = _walker(Vector2(100.0, 100.0))
	var shadows: BodyShadowsScript = _shadows()
	var rows: PackedFloat32Array = _rows([[Vector2(100.0, 80.0), 52.0, 0.4]])
	for frame in 30:
		shadows.begin_lights()
		shadows.add_lights(rows, 1, SpellLightScript.SPOT_ROW_STRENGTH, PackedInt32Array([walker.id]))
		shadows.step(_world.table, _clock, Rect2(), null)
		_clock += FRAME
	check_equal(shadows.cast[walker.id], Vector2.ZERO, "the light over its own head")


func test_a_light_the_pillar_hides_casts_no_shadow() -> void:
	_pillar(Vector2(100.0, 100.0))
	var hidden: Actor = _walker(Vector2(100.0, 70.0))
	var blockers := LightBlockersScript.new()
	blockers.step(_world.table, _clock)
	var shadows: BodyShadowsScript = _shadows()
	_shade_frames(shadows, _rows([[Vector2(100.0, 115.0), 64.0, 1.0]]), 30, blockers)
	check_equal(shadows.cast[hidden.id], Vector2.ZERO, "behind the pillar from the light: no shadow from it")
	_shade_frames(shadows, _rows([[Vector2(100.0, 115.0), 64.0, 1.0]]), 30, null)
	check(shadows.cast[hidden.id].y < -1.0, "nothing blocking: cast away from it")


func test_the_shadow_eases_a_pixel_at_a_time() -> void:
	var walker: Actor = _walker(Vector2(100.0, 100.0))
	var shadows: BodyShadowsScript = _shadows()
	var west: PackedFloat32Array = _rows([[Vector2(80.0, 102.0), 48.0, 0.7]])
	var east: PackedFloat32Array = _rows([[Vector2(120.0, 102.0), 48.0, 0.7]])
	_shade_frames(shadows, west, 2)
	check(shadows.cast[walker.id].x > 2.0, "a body that comes takes its cast at once")
	var drawn: Array[float] = []
	var last: Vector2 = shadows.cast[walker.id]
	for frame in 60:
		_shade_frames(shadows, east, 1)
		var now: Vector2 = shadows.cast[walker.id]
		check(now.distance_to(last) <= BodyShadowsScript.LENGTH * FRAME / BodyShadowsScript.EASE_SECONDS + 0.001, "never more than a frame's share")
		last = now
		var i: int = 0 * BodyShadowsScript.STRIDE
		var by: float = shadows.multimesh.buffer[i + 12]
		check_equal(by, roundf(by), "drawn in whole pixels")
		if drawn.is_empty() or drawn[-1] != by:
			drawn.append(by)
	check(shadows.cast[walker.id].x < -2.0, "it swung over to the other side")
	for at in range(1, drawn.size()):
		check(absf(drawn[at] - drawn[at - 1]) <= 1.0, "a pixel at a time: %s" % [drawn])
	check(drawn.size() >= 5, "through every pixel between, got %s" % [drawn])


func test_a_falling_body_s_shadow_shrinks_and_props_have_none() -> void:
	var walker: Actor = _walker(Vector2(100.0, 100.0))
	_pillar(Vector2(200.0, 100.0))
	var shadows: BodyShadowsScript = _shadows()
	_shade_frames(shadows, _rows([]), 1)
	check_equal(shadows.count, 1, "the pillar has no body shadow (it blocks light instead)")
	var radius: float = shadows.multimesh.buffer[14]
	check_equal(radius, walker.footprint.radius + BodyShadowsScript.RADIUS_PAD, "the drawn shadow's size")
	walker.fall_left = HoleRules.FALL_SECONDS * 0.5
	_shade_frames(shadows, _rows([]), 1)
	check(shadows.multimesh.buffer[14] < radius, "smaller as it falls")


func test_it_takes_the_drawn_shadows_place() -> void:
	var drawn := Node2D.new()
	drawn.add_to_group(LightSpot.DRAWN_SHADOW)
	root.add_child(own(drawn))
	var shadows: BodyShadowsScript = _shadows()
	check(not drawn.visible, "hidden while the cast shadows are drawn")
	var later := Node2D.new()
	later.add_to_group(LightSpot.DRAWN_SHADOW)
	root.add_child(own(later))
	check(not later.visible, "one that comes later too")
	root.remove_child(shadows)
	check(drawn.visible and later.visible, "shown again when they go")


func test_a_frame_allocates_nothing() -> void:
	var pillar: Actor = _pillar(Vector2(100.0, 100.0))
	for at in 20:
		_walker(Vector2(40.0 + 12.0 * at, 140.0))
	var blockers := LightBlockersScript.new()
	var shadows: BodyShadowsScript = _shadows()
	var rows: PackedFloat32Array = _rows([[Vector2(80.0, 120.0), 64.0, 0.8], [Vector2(160.0, 150.0), 48.0, 0.7]])
	var owners := PackedInt32Array()
	for frame in 10:
		blockers.step(_world.table, _clock)
		shadows.begin_lights()
		shadows.add_lights(rows, 2, SpellLightScript.SPOT_ROW_STRENGTH, owners)
		shadows.step(_world.table, _clock, Rect2(0.0, 0.0, 640.0, 360.0), blockers)
		_clock += FRAME
	pillar.footprint.set_solid(false)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		blockers.step(_world.table, _clock)
		shadows.begin_lights()
		shadows.add_lights(rows, 2, SpellLightScript.SPOT_ROW_STRENGTH, owners)
		shadows.step(_world.table, _clock, Rect2(0.0, 0.0, 640.0, 360.0), blockers)
		_clock += FRAME
	check_equal(shadows.count, 20, "every walker's shadow drawn")
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames (a pillar easing out among them) make no object")


# --- In Feel --------------------------------------------------------------------------------------

func test_feel_blocks_light_by_the_room_and_draws_shadows_only_with_spell_light() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var table: Node = own(ActorSeats.table()) as Node
	var manager: ProjectilesScript = own(ProjectilesScript.new()) as ProjectilesScript
	manager.events = bus
	manager.actors = table
	root.add_child(manager)
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = table
	feel.projectiles = manager
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	check(ShaderWarmupScript.shaders().has(BodyShadowsScript.SHADER), "the shadows' shader is compiled before play")
	bus.spell_light_changed.emit(true)
	var spectacle: Node = feel.spectacle()
	check(spectacle.get("shadows") != null, "spell light on: the bodies' shadows are drawn")
	var room := registry.get_resource(&"rooms", &"arena_03") as RoomBase
	var layout: Node = room.build()
	bus.room_built.emit(room.id, layout)
	layout.free()
	feel._process(FRAME)
	var light: SpellLightScript = spectacle.get("light")
	check_equal(light.blocker_count(), 4, "the ossuary court's four bone walls block its light")
	bus.spell_light_changed.emit(false)
	check(spectacle.get("shadows") == null, "spell light off: no shadows node")
	bus.spell_light_changed.emit(true)
	feel._process(FRAME)
	check_equal((spectacle.get("light") as SpellLightScript).blocker_count(), 4, "a light made again is handed the boxes")


func test_a_new_pillar_under_an_old_id_comes_as_it_stands() -> void:
	var pillar: Actor = _pillar(Vector2(100.0, 100.0))
	var id: int = pillar.id
	var blockers := LightBlockersScript.new()
	blockers.step(_world.table, _clock)
	pillar.footprint.set_solid(false)
	for frame in 60:
		_clock += FRAME
		blockers.step(_world.table, _clock)
	check_equal(blockers.count, 0, "crumbled and eased out")
	_world.actors.erase(pillar)
	pillar.free()
	_clock += FRAME
	blockers.step(_world.table, _clock)
	var again: Actor = _pillar(Vector2(100.0, 100.0))
	check_equal(again.id, id, "the next body takes the id")
	_clock += FRAME
	blockers.step(_world.table, _clock)
	check_equal(blockers.count, 1, "the new pillar blocks")
	check_equal(blockers.bodies[0].w, 1.0, "at full strength at once, not easing in from the rubble's 0")


func test_a_light_made_anew_takes_the_boxes_as_they_stand() -> void:
	var pillar: Actor = _pillar(Vector2(100.0, 100.0))
	var blockers := LightBlockersScript.new()
	blockers.step(_world.table, _clock)
	# Crumbled while spell light was off (no steps), then the light comes back.
	pillar.footprint.set_solid(false)
	blockers.refresh()
	_clock += FRAME
	check(blockers.step(_world.table, _clock), "handed over again")
	check_equal(blockers.count, 0, "rubble already: no shadow fading over it")


func test_a_room_built_forgets_the_last_rooms_props() -> void:
	var pillar: Actor = _pillar(Vector2(100.0, 100.0))
	var blockers := LightBlockersScript.new()
	blockers.step(_world.table, _clock)
	pillar.footprint.set_solid(false)
	_clock += FRAME
	blockers.step(_world.table, _clock)
	check(blockers.strength[pillar.id] > 0.0 and blockers.strength[pillar.id] < 1.0, "easing out")
	blockers.use_walls([] as Array[Rect2])
	check_equal(blockers.strength[pillar.id], -1.0, "a new room: its props come as new")


func test_a_wizard_behind_a_pillar_lights_round_itself() -> void:
	# A pillar's base and shaft, a wizard standing behind it: its staff tip is on the shaft's screen
	# box, its feet behind the base. Its light is blocked by where it stands (its feet), never moved in
	# front of the pillar.
	var boxes := PackedVector4Array([Vector4(87.0, 88.0, 113.0, 100.0)])
	var bodies := PackedVector4Array([Vector4(84.0, 39.0, 116.0, 1.0)])
	var feet := Vector2(100.0, 76.0)
	var shade := LightBlockersScript.shade_between
	check_equal(shade.call(Vector2(80.0, 70.0), feet, boxes, bodies, 1), 0.0, "the floor beside it, behind the pillar, is lit")
	check_equal(shade.call(Vector2(100.0, 130.0), feet, boxes, bodies, 1), 1.0, "the floor in front of the pillar is not")
	var wizard: Actor = _walker(feet)
	var lights := CarriedLightsScript.new()
	_world.table.set_home(wizard.id, 0)
	for frame in 3:
		lights.step(_world.table, _clock)
		_clock += FRAME
	var rows: PackedFloat32Array = lights.rows
	var tip := Vector2(rows[SpellLightScript.ROW_X], rows[SpellLightScript.ROW_Y])
	var ground := Vector2(rows[SpellLightScript.SPOT_ROW_GROUND], rows[SpellLightScript.SPOT_ROW_GROUND + 1])
	check_equal(tip + ground, wizard.global_position, "a carried light stands on its body's feet")
	var code: String = (load("res://gameplay/feel/light.gdshader") as Shader).code
	check(code.contains("lamp_at = rows == ROWS_SPOT ? centre + ground : lit_as(centre);"), "the shader lights a spot row from where it stands, only a flash or a cue moved off a shaft")


func test_a_staff_tip_over_a_wall_does_not_open_it() -> void:
	# A low wall; a wizard standing just south of it, its staff tip over the wall's box.
	var boxes := PackedVector4Array([Vector4(0.0, 0.0, 128.0, 32.0)])
	var bodies := PackedVector4Array([Vector4(0.0, 0.0, 128.0, 1.0)])
	var feet := Vector2(64.0, 40.0)
	var tip := Vector2(64.0, 20.0)
	var shade := LightBlockersScript.shade_between
	check_equal(shade.call(Vector2(64.0, -10.0), tip, boxes, bodies, 1), 0.0, "lit from the tip, the wall would let it through")
	check_equal(shade.call(Vector2(64.0, -10.0), feet, boxes, bodies, 1), 1.0, "lit from where it stands, the wall blocks the far side")


func test_a_spawning_body_s_shadow_rises_with_it() -> void:
	var walker: Actor = _walker(Vector2(100.0, 100.0))
	walker.spawn_seconds = 1.0
	walker.spawn_left = 0.9
	var shadows: BodyShadowsScript = _shadows()
	_shade_frames(shadows, _rows([]), 1)
	check_equal(shadows.count, 0, "under its spawn mark: no shadow")
	walker.spawn_left = 0.3
	_shade_frames(shadows, _rows([]), 1)
	var full: float = walker.footprint.radius + BodyShadowsScript.RADIUS_PAD
	check(shadows.count == 1 and shadows.multimesh.buffer[14] < full, "rising: part of it")
	walker.spawn_left = 0.0
	_shade_frames(shadows, _rows([]), 1)
	check_equal(shadows.multimesh.buffer[14], full, "landed: all of it")


## Each spawn style's own mark: a style whose mark lasts longer (`SpawnStyle.mark_end`) keeps the
## shadow back longer (spawn styles; the lookup is the registry's, handed in as `style_of`).
func test_a_spawning_body_s_shadow_waits_for_its_own_style_s_mark() -> void:
	check_equal(BodyShadowsScript.rise_share(0.5, 0.4), (0.5 - 0.4) / 0.6, "past the default mark: partly")
	check_equal(BodyShadowsScript.rise_share(0.5, 0.7), 0.0, "a longer mark: none yet")
	check_equal(BodyShadowsScript.rise_share(1.0, 0.7), 1.0, "standing: all")
	var long_mark := SpawnStyle.from_default()
	long_mark.id = &"test_long_mark"
	long_mark.mark_end = 0.7
	var walker: Actor = _walker(Vector2(100.0, 100.0))
	walker.spawn_style = long_mark.id
	walker.spawn_seconds = 1.0
	walker.spawn_left = 0.5
	var shadows: BodyShadowsScript = _shadows()
	shadows.style_of = func(id: StringName) -> SpawnStyle: return long_mark if id == long_mark.id else null
	_shade_frames(shadows, _rows([]), 1)
	check_equal(shadows.count, 0, "half way through a style whose mark lasts to 0.7: no shadow yet")
	walker.spawn_style = &"no_such_style"
	_shade_frames(shadows, _rows([]), 1)
	check_equal(shadows.count, 1, "an unknown style takes the default's mark (0.4): showing")


func test_a_gone_body_s_shadow_shrinks_away_where_it_was() -> void:
	var walker: Actor = _walker(Vector2(100.0, 100.0))
	var shadows: BodyShadowsScript = _shadows()
	_shade_frames(shadows, _rows([]), 2)
	walker.visible = false
	var sizes: Array[float] = []
	for frame in 12:
		_shade_frames(shadows, _rows([]), 1)
		sizes.append(shadows.multimesh.buffer[14] if shadows.count > 0 else 0.0)
		if shadows.count > 0:
			check_equal(Vector2(shadows.multimesh.buffer[3], shadows.multimesh.buffer[7]), Vector2(100.0, 102.0), "where it was")
	check_equal(sizes[-1], 0.0, "gone in the end")
	var shown: int = 0
	for size in sizes:
		if size > 0.0:
			shown += 1
	check(shown >= 3, "over at least 3 frames, got %s" % [sizes])
