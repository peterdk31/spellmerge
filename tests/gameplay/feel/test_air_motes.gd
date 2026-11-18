extends "res://tests/support/suite.gd"
## The room's air (docs/milestones/atmosphere.md, B: lit dust in the air): a room names what
## drifts in its air (`RoomBase.air`, a `MoteSource`; none by default), Feel gives it off over the
## part of the room in view at its rate for every `RoomBase.AIR_AREA` (gameplay/feel/air_motes.gd),
## never more than its share of the motes' ring, in rows of the ramp table it asks for again when
## they are overwritten, and only while spell light and the particles are on; a lit-only kind
## (`MoteKind.lit_only`) is drawn by reading the spell light's buffer, which the spectacle hands the
## motes with the light's steps (none with spell light off: not drawn), stepping a shade at a time
## and gone only from its shadow shade (Smooth); a frame allocates nothing. How it looks is checked
## by eye (tests/screenshots/shot_atmosphere_dust.gd): headless runs draw nothing.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const AirMotesScript := preload("res://gameplay/feel/air_motes.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ARENA := preload("res://content/rooms/crypt/arena_01.tres")

## One frame of Feel's clock (s).
const FRAME: float = 1.0 / 60.0
## The crypt's rooms, every one with dust in its air.
const CRYPT_ROOMS: Array[StringName] = [&"arena_01", &"arena_02", &"arena_03", &"arena_04", &"boss_broom"]

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


## A lit-only kind of dust made here.
func _dust(id: StringName = &"dust_here") -> MoteKind:
	var kind := MoteKind.new()
	kind.id = id
	kind.lit_only = true
	kind.gravity = 0.0
	kind.drag = 0.3
	kind.glow = 0.0
	kind.speed = Vector2(1.0, 4.0)
	kind.up = Vector2(0.0, 1.0)
	kind.life = Vector2(3.0, 3.0)
	return kind


## Air of `kind` at `rate`, in bone.
func _air(kind: StringName = &"dust_here", rate: float = 5.0) -> MoteSource:
	var air := MoteSource.new()
	air.kind = kind
	air.rate = rate
	air.spread = 360.0
	air.reach = 0.0
	air.colours = [&"bone"] as Array[StringName]
	return air


func _pool(cap: int, kinds: Array[MoteKind]) -> MotesScript:
	var motes: MotesScript = own(MotesScript.new(cap, 0, kinds)) as MotesScript
	root.add_child(motes)
	return motes


## A Feel with its own bus and a projectile manager in the tree. Returns [bus, feel].
func _feel() -> Array:
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
	return [bus, feel]


# --- The data -------------------------------------------------------------------------------------

func test_a_kind_is_lit_only_by_its_data() -> void:
	var plain := MoteKind.new()
	check(not plain.lit_only, "a kind is drawn as it is by default")
	var dust: MoteKind = _dust()
	check_equal(dust.problems(), PackedStringArray(), "a lit-only kind with no glow is fine")
	dust.glow = 0.5
	check(" ".join(dust.problems()).contains("does not glow"), "a lit-only kind does not glow: the light is its glow")
	dust.glow = 0.0
	dust.gravity = 100.0
	dust.settles = &"speck"
	check(" ".join(dust.problems()).contains("leaves no mark"), "a lit-only kind does not settle: a mark would show in the dark")


func test_a_room_has_no_air_by_default_and_its_air_is_checked() -> void:
	var room := RoomBase.new()
	room.id = &"test_room"
	check(room.air == null, "a room has no air by default: it is as it was")
	check_equal(room.air_problems(), PackedStringArray(), "no air, no problem")
	room.air = _air(&"")
	check(" ".join(room.template_problems([] as Array[StringName])).contains("test_room's air"), "air with a problem is a problem of the room's")
	room.air = _air()
	room.air.stand = true
	check(" ".join(room.air_problems()).contains("never standing"), "the air's motes are given off, never standing")
	room.air = _air()
	room.air.from = MoteSource.From.AREA
	room.air.size = Vector2.ZERO
	room.air.way = Vector2.ZERO
	room.air.band_length = 12.0
	check_equal(room.air_problems(), PackedStringArray(), "where a source leaves from is neither read nor checked for the air")


func test_the_crypt_and_the_hub_have_lit_air_of_a_kind_there_is() -> void:
	var rooms: Array[StringName] = CRYPT_ROOMS.duplicate()
	rooms.append(&"hub")
	for id in rooms:
		var room := registry.get_resource(&"rooms", id) as RoomBase
		check(room != null and room.air != null, "%s has air" % id)
		if room == null or room.air == null:
			continue
		check_equal(room.air_problems(), PackedStringArray(), "%s's air is sound" % id)
		var kind := registry.get_resource(&"motes", room.air.kind) as MoteKind
		check(kind != null and kind.lit_only and kind.problems().is_empty(), "%s's air is a sound lit-only kind (%s)" % [id, room.air.kind])
	var crypt_air: MoteSource = (registry.get_resource(&"rooms", &"arena_01") as RoomBase).air
	for id in CRYPT_ROOMS:
		check((registry.get_resource(&"rooms", id) as RoomBase).air == crypt_air, "%s shares the crypt's air" % id)


# --- Drawn by the light ------------------------------------------------------------------------

func test_a_lit_only_kind_tells_the_shader_and_reads_the_light_it_is_handed() -> void:
	var plain := _dust(&"plain_here")
	plain.lit_only = false
	var motes: MotesScript = _pool(1024, [plain, _dust()])
	check_equal(motes.kind_numbers(0)[3], Vector4(0.0, 0.0, 0.0, 0.0), "a plain kind is drawn as it is")
	check_equal(motes.kind_numbers(1)[3], Vector4(1.0, 0.0, 0.0, 0.0), "a lit-only kind, in its row's light texel")
	check(motes.light() == null and motes.shader_parameter(&"light_on") != true, "no light buffer until one is handed: lit-only motes are not drawn")
	var light: SpellLightScript = own(SpellLightScript.new(null, 0)) as SpellLightScript
	root.add_child(light)
	motes.set_light(light.buffer(), SpellLightScript.lit_steps())
	check(motes.light() == light.buffer() and motes.shader_parameter(&"light_buffer") == light.buffer(), "the spell light's buffer, handed to the shader")
	check(motes.shader_parameter(&"lit_steps") == SpellLightScript.lit_steps(), "with the light's steps")
	check(motes.shader_parameter(&"light_on") == true, "and lit-only motes drawn by it")
	check(light.buffer() == light.viewport.get_texture(), "the buffer is the light viewport's own texture")
	motes.set_light(null)
	check(motes.shader_parameter(&"light_on") != true, "none again: not drawn")
	var code: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	check(code.contains("uniform sampler2D light_buffer") and code.contains("textureLod(light_buffer, SCREEN_UV, 0.0)"), "the shader reads the light under each lit-only pixel")
	check(code.contains("texelFetch(kind_table, ivec2(3, k), 0)"), "and knows a lit-only kind by its row's light texel")


func test_feel_hands_the_motes_the_spell_lights_buffer_and_takes_it_back() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	check(feel.light() != null and feel.motes().light() == feel.light().buffer(), "spell light on: the motes read its buffer")
	bus.spell_light_changed.emit(false)
	check(feel.motes().light() == null, "off: none (lit-only motes are not drawn)")
	bus.spell_light_changed.emit(true)
	check(feel.motes().light() == feel.light().buffer(), "on again: the new light's buffer")
	bus.mote_cap_changed.emit(MoteCap.STOPS[1])
	check(feel.motes().light() == feel.light().buffer(), "a new ring of motes reads it too")
	check(feel.motes().lit_steps == SpellLightScript.lit_steps(), "by the light's steps")


## The dust's steps come from the same numbers the apply rect lights the floor by: faint just inside
## where the floor is lit, then at its lit and bright steps; the shader's and Motes' defaults match.
func test_the_dusts_steps_are_the_floors() -> void:
	var steps: Vector4 = SpellLightScript.lit_steps()
	check(steps.x < SpellLightScript.LIT_FROM and steps.x >= SpellLightScript.LIT_FROM * 0.5, "a faint first step just under where the floor is lit")
	check(is_equal_approx(steps.y, SpellLightScript.LIT_FROM) and is_equal_approx(steps.w, SpellLightScript.BRIGHT_FROM), "then the floor's lit and bright steps")
	check(steps.y < steps.z and steps.z < steps.w, "rising")
	check(MotesScript.DEFAULT_LIT_STEPS.is_equal_approx(steps), "Motes' default is the light's")
	var code: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	var found: RegExMatch = RegEx.create_from_string("uniform vec4 lit_steps = vec4\\(([^)]*)\\);").search(code)
	var numbers: PackedFloat64Array = PackedFloat64Array()
	if found != null:
		for number in found.get_string(1).split(","):
			numbers.append(float(number))
	check(numbers.size() == 4 and Vector4(numbers[0], numbers[1], numbers[2], numbers[3]).is_equal_approx(steps), "and the shader's (%s)" % [numbers])
	var light: SpellLightScript = own(SpellLightScript.new(null, 0)) as SpellLightScript
	var apply := light.apply.material as ShaderMaterial
	check(is_equal_approx(float(apply.get_shader_parameter(&"lit_from")), SpellLightScript.LIT_FROM) and is_equal_approx(float(apply.get_shader_parameter(&"bright_from")), SpellLightScript.BRIGHT_FROM), "the apply rect is set from the same numbers")


## Smooth (docs/STYLE.md): the shader's pick, mirrored (`Motes.lit_shade`, `lit_life_shade`), moves
## a lit-only mote at most a shade a step as the light or its life changes, and it is only ever
## gone from its shadow shade, never from a brighter one.
func test_a_lit_only_mote_never_pops() -> void:
	var steps: Vector4 = SpellLightScript.lit_steps()
	for shade_from in 4:
		var lives: Array[int] = []
		for i in 401:
			lives.append(MotesScript.lit_life_shade(3.0 * float(i) / 400.0, 3.0, shade_from))
		check(lives[0] == 3 and lives[-1] == 3, "from %d: born and gone in its shadow shade" % shade_from)
		check(lives.min() == shade_from, "from %d: its first shade at its brightest" % shade_from)
		for life_shade in range(shade_from, 4):
			var last: int = MotesScript.NOT_DRAWN
			for i in 1001:
				var shade: int = MotesScript.lit_shade(0.6 * float(i) / 1000.0, life_shade, steps)
				check(absi(shade - last) <= 1, "light rising: a shade at a time (%d to %d)" % [last, shade])
				last = shade
		for i in 1001:
			var most: float = 0.6 * float(i) / 1000.0
			var last: int = MotesScript.lit_shade(most, lives[0], steps)
			for j in range(1, lives.size(), 7):
				var shade: int = MotesScript.lit_shade(most, lives[j], steps)
				check(absi(shade - last) <= 1, "its life: a shade at a time")
				check(shade != MotesScript.NOT_DRAWN or last == MotesScript.NOT_DRAWN or last == 3, "gone only from its shadow shade")
				last = shade
	check_equal(MotesScript.lit_shade(steps.x * 0.99, 0, steps), MotesScript.NOT_DRAWN, "not drawn in the dark")
	check_equal(MotesScript.lit_shade(steps.w, 0, steps), 0, "white-hot in the brightest light")
	check_equal(MotesScript.lit_shade(steps.w, 2, steps), 2, "no brighter than its life allows")
	var code: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	check(code.contains("const float RISE_SPEED = %s;" % MotesScript.RISE_SPEED), "the shader rises as Motes does")


# --- Given off ------------------------------------------------------------------------------------

func test_the_air_is_given_off_over_the_room_in_view_at_its_rate() -> void:
	var motes: MotesScript = _pool(8192, [_dust()])
	var air := AirMotesScript.new(RampTableScript.new())
	air.use(_air(&"dust_here", 5.0))
	check(air.look != null and air.sources.size() == 1, "the air in its one colour")
	# 200 x 100 px is 2 AIR_AREA: 10 a second.
	var bounds := Rect2(0.0, 0.0, 200.0, 100.0)
	var clock: float = 0.0
	for frame in 121:
		air.give_off(clock, motes, Rect2(), bounds)
		motes.step(clock)
		clock += FRAME
	check(air.given >= 19 and air.given <= 21, "about 20 in two seconds over two AIR_AREA, got %d" % air.given)
	var given: int = air.given
	for frame in 60:
		air.give_off(clock, null, Rect2(), bounds)
		clock += FRAME
	check_equal(air.given, given, "none with no pool (the particles or the light are off)")
	air.use(null)
	for frame in 60:
		air.give_off(clock, motes, Rect2(), bounds)
		clock += FRAME
	check_equal(air.given, given, "none with no air")


func test_the_air_is_given_off_only_near_the_view_and_inside_the_room() -> void:
	var view := Rect2(100.0, 100.0, 64.0, 36.0)
	var near: Rect2 = view.grow(AirMotesScript.VIEW_MARGIN)
	check(AirMotesScript.area_of(view, Rect2(0.0, 0.0, 2000.0, 2000.0)).is_equal_approx(near), "a little past the view, in a big room")
	check(AirMotesScript.area_of(view, Rect2(0.0, 0.0, 120.0, 120.0)).is_equal_approx(Rect2(near.position, Vector2(120.0, 120.0) - near.position)), "never past the room's bounds")
	check(AirMotesScript.area_of(Rect2(), Rect2(0.0, 0.0, 50.0, 50.0)).is_equal_approx(Rect2(0.0, 0.0, 50.0, 50.0)), "the whole room with no view")
	check(not AirMotesScript.area_of(view, Rect2(1000.0, 1000.0, 50.0, 50.0)).has_area(), "nothing where the room is out of view")


func test_the_air_never_holds_more_than_its_share_of_the_ring() -> void:
	var motes: MotesScript = _pool(1024, [_dust()])
	var air := AirMotesScript.new(RampTableScript.new())
	air.use(_air(&"dust_here", 1000.0))
	var clock: float = 0.0
	for frame in 181:
		air.give_off(clock, motes, Rect2(), Rect2(0.0, 0.0, 1000.0, 1000.0))
		motes.step(clock)
		clock += FRAME
	# A life of 3 s: 1,024 * RING_SHARE / 3 a second at most, over three seconds.
	var most: float = 1024.0 * AirMotesScript.RING_SHARE
	check(float(air.given) <= most + 1.0, "at most its share of the ring alive at once, got %d of %d" % [air.given, int(most)])
	check(float(air.given) >= most - 2.0, "and as much as that share, got %d" % air.given)


func test_the_airs_colours_follow_the_ramp_table_through_a_long_fight() -> void:
	var motes: MotesScript = _pool(8192, [_dust()])
	var table := RampTableScript.new()
	var air := AirMotesScript.new(table)
	air.use(_air(&"dust_here", 5.0))
	var bone: Color = Palette.ramp_of(&"bone")[1]
	check(table.shade(air.sources[0], 1).is_equal_approx(bone), "its row is Bone")
	# A long fight's colours take every row, the air's too.
	for i in RampTableScript.ROWS:
		table.source(PackedColorArray([Color(0.01 * i, 0.2, 0.3), Color(0.02, 0.01 * i, 0.4), Color(0.03, 0.04, 0.01 * i)]))
	check(not table.shade(air.sources[0], 1).is_equal_approx(bone), "the old row went to other colours")
	air.give_off(0.0, motes, Rect2(), Rect2(0.0, 0.0, 200.0, 100.0))
	check(table.shade(air.sources[0], 1).is_equal_approx(bone), "asked for again: Bone once more")
	var written: int = table.writes
	air.give_off(FRAME, motes, Rect2(), Rect2(0.0, 0.0, 200.0, 100.0))
	check_equal(table.writes, written, "and not again while the table writes nothing")


func test_air_naming_no_kind_there_is_gives_off_nothing() -> void:
	var motes: MotesScript = _pool(1024, [_dust()])
	var air := AirMotesScript.new(RampTableScript.new())
	air.use(_air(&"no_such_kind"))
	for frame in 30:
		air.give_off(float(frame) * FRAME, motes, Rect2(), Rect2(0.0, 0.0, 200.0, 200.0))
	check_equal(air.given, 0, "a kind the pool lacks: nothing, warned once")
	air.use(_air(&""))
	check(air.look == null, "air with a problem is not used")


func test_a_frame_allocates_nothing() -> void:
	var motes: MotesScript = _pool(1024, [_dust()])
	var air := AirMotesScript.new(RampTableScript.new())
	air.use(_air(&"dust_here", 30.0))
	var bounds := Rect2(0.0, 0.0, 300.0, 200.0)
	var view := Rect2(20.0, 20.0, 160.0, 90.0)
	var clock: float = 0.0
	# The ring's one chunk is made by the first mote.
	for frame in 30:
		air.give_off(clock, motes, view, bounds)
		motes.step(clock)
		clock += FRAME
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var given: int = air.given
	for frame in 100:
		air.give_off(clock, motes, view, bounds)
		motes.step(clock)
		clock += FRAME
	check(air.given > given, "motes were given off")
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of air make no object")


# --- In Feel --------------------------------------------------------------------------------------

func test_a_room_names_feel_its_air_given_off_only_with_spell_light() -> void:
	var still := ARENA.duplicate() as RoomBase
	still.id = &"test_still_room"
	still.air = null
	registry.add(&"rooms", still)
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var air: AirMotesScript = feel.spectacle().air
	bus.room_entered.emit(&"arena_01", 0)
	check(air.look == ARENA.air, "the crypt's air is the spectacle's")
	for frame in 60:
		feel._process(FRAME)
	check(air.given > 0, "given off while motes and spell light are on, got %d" % air.given)
	bus.spell_light_changed.emit(false)
	var given: int = air.given
	for frame in 60:
		feel._process(FRAME)
	check_equal(air.given, given, "spell light off: none given off (its lit-only dust would be unseen)")
	bus.spell_light_changed.emit(true)
	feel.spectacle().particles_enabled = false
	given = air.given
	for frame in 60:
		feel._process(FRAME)
	check_equal(air.given, given, "particles off: none given off either")
	feel.spectacle().particles_enabled = true
	bus.spell_light_changed.emit(true)
	bus.room_entered.emit(still.id, 0)
	check(air.look == null, "a room with no air: nothing drifts")
