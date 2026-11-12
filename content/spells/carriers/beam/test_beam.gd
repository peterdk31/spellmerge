extends "res://tests/support/card_rig.gd"
## The Beam card (content/spells/carriers/beam/, M2 part 10): a ray that hits along its line up to its reach, at once and every tick of its life; held, it stays on.
##
## godot --headless --path . --script res://content/spells/carriers/beam/test_beam.gd

const ShaderSource := preload("res://tests/support/shader_source.gd")


func test_the_card_is_a_beam() -> void:
	_check_card(&"beam", 2)
	check_equal(_form(&"beam").carrier, &"beam", "beam is a ray")
	check(_form(&"beam").ray_length > 0.0, "a beam has a reach")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"beam"], false)
	for player in 4:
		check_equal(_mgr.get_count_for(player), 0, "a ray holds no shot")


func test_the_beam_hits_along_a_line_up_to_its_reach_at_once() -> void:
	var near := _target(Vector2(60.0, 0.0))
	var second := _target(Vector2(120.0, 0.0))
	var third := _target(Vector2(180.0, 0.0))
	var beside := _target(Vector2(120.0, 50.0))
	_cast_form(&"beam", 0, Vector2.ZERO)
	check_equal(_form(&"beam").pierce, 0, "a beam pierces only with pierce cards")
	check_equal(_hit_targets(), [near] as Array, "a bare beam hits the nearest on the line and stops there")
	check(not _hit_targets().has(second) and not _hit_targets().has(third) and not _hit_targets().has(beside), "not the ones behind it nor the one beside it")
	check_equal(_mgr.get_count(), 0, "a beam holds no shot")


func test_one_beam_hits_at_once_and_every_tick_of_its_life() -> void:
	_target(Vector2(60.0, 0.0))
	var spell: CompiledSpell = StaffKit.first(_spells, [&"beam"] as Array[StringName])
	_cast_form(&"beam", 0, Vector2.ZERO)
	check_equal(_hits.size(), 1, "a hit at once")
	check_equal(CarrierBeam.of(_spells).beam_count(), 1, "and the beam stays on")
	_tick(60)
	var hits: int = Carriers.of(&"beam").hits_per_target(spell.lifetime)
	check_equal(_hits.size(), hits, "then one hit every %s s of its %s s life" % [SpellLimits.BEAM_TICK, spell.lifetime])
	check_equal(CarrierBeam.of(_spells).beam_count(), 0, "then it is gone")
	check_equal(spell.damage, 2, "a hit does 2 damage")


func test_a_held_beam_stays_on_and_drains_mana_steadily() -> void:
	_target(Vector2(60.0, 0.0))
	# A starter staff (the curl): the beam's life covers a whole cast cycle, so held fire leaves no gap.
	var staff: StaffBase = load("res://content/wizard/staffs/curl/curl.tres") as StaffBase
	_spells.install_staff(0, 0, _spells.compile_staff([&"beam"] as Array[StringName], staff))
	var spell: CompiledSpell = StaffKit.first(_spells, [&"beam"] as Array[StringName])
	var mana: float = 100.0
	var casts: int = 0
	var dark: int = 0
	# Fire is held for 2 seconds: the player casts whenever the staff allows.
	for i in 120:
		var taken: float = _spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, mana)
		if taken != SpellsScript.REFUSED:
			mana -= taken
			casts += 1
		if CarrierBeam.of(_spells).beam_count() == 0:
			dark += 1
		_tick(1)
	check_equal(dark, 0, "a beam is on in every step")
	check_equal(spell.mana_cost, 4.0, "a cast costs 4 mana")
	check(absf(100.0 - mana - 4.0 * casts) < 0.01, "each cast takes 4 mana (%f)" % mana)
	check(absi(_hits.size() - roundi(2.0 / SpellLimits.BEAM_TICK)) <= 3, "the enemy is hit about every %s s: %d hits" % [SpellLimits.BEAM_TICK, _hits.size()])


func test_the_beam_does_not_reach_past_its_length() -> void:
	_target(Vector2(_form(&"beam").ray_length + 40.0, 0.0))
	_cast_form(&"beam", 0, Vector2.ZERO)
	check_equal(_hits.size(), 0, "a target beyond the reach is safe")


func test_its_own_look_takes_every_uniform_feel_gives_a_beam() -> void:
	# The beam's look is its own (a white-hot core banded out through its ramp; void a dark rift;
	# the owner, 2026-11-08), no longer the plain beam's include: Feel sets the plain beam's
	# uniforms on it (`Feel._on_form_shown`), so it keeps declaring every one, or a setting falls
	# on nothing and the beam draws stale.
	var plain: String = ShaderSource.of(load("res://core/projectiles/shot_beam.gdshader") as Shader)
	var own_look: String = ShaderSource.of(_form(&"beam").look_shader)
	check(not _form(&"beam").look_shader.code.contains("#include \"res://core/projectiles/shot_beam.gdshaderinc\""), "the beam draws a look of its own")
	var count: int = 0
	for line: String in plain.split("\n"):
		if line.begins_with("uniform "):
			count += 1
			check(own_look.contains(line), "the beam's look keeps `%s`" % line)
	check(count > 10, "the plain beam's uniforms were read (%d)" % count)
	check(own_look.contains("uniform vec4 beam_infusions[8];") and own_look.contains("uniform int beam_infusion_count"), "it is handed every infusion on the beam")
	check(own_look.contains("rift = kind == L_PULL ? 1.0 : 0.0;"), "a beam whose first infusion gives off a dark heart (void) is a dark rift")



func test_it_hands_its_look_every_infusion_on_it_in_slot_order() -> void:
	# The beam's look shows every infusion from what it is handed (a strand each but the first),
	# so a new or changed infusion card needs nothing in the beam: its tint and its look kind go
	# with the beam.
	var frost: ElementBase = _registry.call("get_resource", &"spells", &"frost")
	var fire: ElementBase = _registry.call("get_resource", &"spells", &"fire")
	_cast_with(&"beam", [&"frost", &"fire", &"frost"], 0, Vector2.ZERO)
	var beams: CarrierBeam = CarrierBeam.of(_spells)
	var at: int = -1
	for i in beams.beam_slots():
		if beams.beam_on(i):
			at = i
	check(at >= 0, "the beam is on")
	if at < 0:
		return
	var looks: PackedColorArray = beams.beam_infusions(at)
	check_equal(looks.size(), 2, "each different infusion once")
	check_equal(Color(looks[0].r, looks[0].g, looks[0].b), frost.tint, "the first first, in its tint")
	check_equal(int(roundf(looks[0].a * 255.0)), frost.look_layer, "with its look kind")
	check_equal(Color(looks[1].r, looks[1].g, looks[1].b), fire.tint, "then the next")
	check_equal(int(roundf(looks[1].a * 255.0)), fire.look_layer, "with its look kind")
