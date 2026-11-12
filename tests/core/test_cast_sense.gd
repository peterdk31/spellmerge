extends "res://tests/support/suite.gd"
## What a cast does, for an AI (`CastSense`, docs/milestones/M2-enemy-ai.md, AI2): the summary the
## compiler makes of every cast, read with `Spells.next_cast_sense`. Real cards from the registry.
##
## godot --headless --path . --script res://tests/core/test_cast_sense.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _spell(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	arena.free_all()
	return staff.casts[0].group.spells[0]


func _sense(cards: Array, cast: int = 0) -> CastSense:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	arena.free_all()
	check(staff != null and cast < staff.casts.size(), "%s compiles to cast %d" % [cards, cast])
	if staff == null or cast >= staff.casts.size():
		return CastSense.new()
	return staff.casts[cast].sense


func test_every_cast_has_a_summary() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["fire", "bolt", "dash"])
	arena.free_all()
	for cast: CompiledCast in staff.casts:
		check(cast.sense != null, "every cast is summed up")
		check_equal(cast.sense.mana, cast.mana, "with its mana")
		check_equal(cast.sense.delay, cast.delay, "and its delay")


func test_a_bolt_is_an_aimed_shot() -> void:
	var sense: CastSense = _sense(["fire", "bolt"])
	check(sense.reach > 100.0, "a bolt reaches far: %s" % sense.reach)
	check(sense.speed > 0.0, "it flies, so it can be led")
	check(sense.harms() and sense.damage > 0.0, "it hurts")
	check(sense.status, "fire burns")
	check(not sense.area and not sense.moves_caster and not sense.blocks and not sense.spawns and not sense.heals, "and does nothing else")
	check(not sense.empty, "it is not empty")


func test_a_nova_hits_round_its_caster() -> void:
	var sense: CastSense = _sense(["nova", "bolt"])
	check_equal(sense.reach, 0.0, "a nova is not aimed")
	check(sense.area, "it hits round its caster")
	check(sense.close_reach > 20.0, "within its ring: %s" % sense.close_reach)
	check(sense.damage > 0.0, "and hurts")
	var bolt: CastSense = _sense(["bolt"])
	check(is_equal_approx(sense.close_reach, bolt.reach), "each copy flies as far as a bolt: %s vs %s" % [sense.close_reach, bolt.reach])
	check(sense.damage > bolt.damage * 4.0, "eight copies count eight times: %s vs %s" % [sense.damage, bolt.damage])


func test_a_circling_cast_is_an_area_round_its_caster() -> void:
	# Orbit (docs/milestones/carrier-modifiers.md Part 5): it goes round its caster, not out along
	# the aim, so it is not aimed and reaches as far as its circle and its size.
	var sense: CastSense = _sense(["orbit", "bolt"])
	var spell: CompiledSpell = _spell(["orbit", "bolt"])
	check_equal(sense.reach, 0.0, "a circling bolt is not aimed")
	check(sense.area, "it hits round its caster")
	check(is_equal_approx(sense.close_reach, spell.orbit_radius + spell.radius), "within its circle: %s vs %s + %s" % [sense.close_reach, spell.orbit_radius, spell.radius])
	check(sense.close_reach < _sense(["bolt"]).reach, "much nearer than a bolt flies")
	check(sense.damage > 0.0, "and hurts")
	var beam: CastSense = _sense(["orbit", "beam"])
	check_equal(beam.reach, 0.0, "a sweeping beam is not aimed either")
	check(beam.area, "it sweeps round its caster")
	# A rune, a pool or a wall circles too (5B): the same, an area as wide as its circle.
	for still: String in ["rune", "pool", "wall"]:
		var circling: CastSense = _sense(["orbit", still])
		var placed: CompiledSpell = _spell(["orbit", still])
		check(circling.reach == 0.0 and circling.area, "a circling %s is an area round its caster" % still)
		check(is_equal_approx(circling.close_reach, placed.orbit_radius + placed.radius), "as near as its circle: %s" % circling.close_reach)


func test_moves_blocks_spawns_heals() -> void:
	check(_sense(["dash"]).moves_caster, "a dash moves its caster")
	check(_sense(["dash"]).move_reach > 30.0, "its distance: %s" % _sense(["dash"]).move_reach)
	check(_sense(["teleport"]).move_reach > 30.0, "and a teleport's: %s" % _sense(["teleport"]).move_reach)
	check(_sense(["teleport"]).moves_caster, "a teleport too")
	check(_sense(["wall"]).blocks, "a wall blocks shots")
	check(_sense(["shield", "pulse"]).blocks, "a shield Pulse on the caster blocks")
	check(_sense(["decoy"]).spawns, "a decoy is a body of its own")
	check(_sense(["familiar"]).spawns, "a familiar too")
	var mend: CastSense = _sense(["mend", "bolt"])
	check(mend.heals, "a mend bolt heals")
	check_equal(mend.damage, 0.0, "and hurts nobody")
	check(not _sense(["frost", "mend", "bolt"]).status, "nor puts its frost on: a heal does nothing else (owner 2026-11-12)")
	check(_sense(["frost", "bolt"]).status, "a frost bolt does")
	var alone: CastSense = _sense(["mend"])
	check(not alone.heals and alone.empty, "a mend with no carrier casts nothing (props W9a)")
	check(_sense(["mend", "pulse"]).heals, "a mend Pulse heals those near its caster")


func test_held_and_sustained() -> void:
	check(_sense(["beam"]).repeats_held, "a beam goes on while held")
	check(_sense(["swing"]).repeats_held, "a swing sweeps again while held")
	var hold: CastSense = _sense(["hold", "rune"])
	check(hold.sustained, "a held rune stays until pressed again")
	check(not _sense(["bolt"]).sustained, "a bolt does not")


func test_a_blast_is_known() -> void:
	var sense: CastSense = _sense(["blast", "bolt"])
	check(sense.blast > 0.0, "a blast bolt explodes: %s" % sense.blast)
	check(sense.harms(), "and harms")


func test_a_fall_from_the_sky_is_an_area_that_hurts() -> void:
	var sense: CastSense = _sense(["skyfall", "bolt"])
	check(sense.area, "a bolt from the sky falls on a spot")
	check(sense.damage > 0.0, "and hurts with its own hit")


func test_multicast_adds_up() -> void:
	var one: CastSense = _sense(["bolt"])
	var three: CastSense = _sense(["triple", "bolt", "bolt", "bolt"])
	check(three.damage > one.damage * 2.5, "a triple bolt deals about three bolts: %s vs %s" % [three.damage, one.damage])


func test_spells_reads_the_next_cast() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["bolt", "dash"])
	var first: CastSense = arena.spells.next_cast_sense(0, 0)
	check(first != null and not first.moves_caster, "the first cast is the bolt")
	arena.spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 1000.0)
	var second: CastSense = arena.spells.next_cast_sense(0, 0)
	check(second != null and second.moves_caster, "then the dash")
	check(arena.spells.next_cast_sense(0, 3) == null, "an empty staff has none")
	check(arena.spells.next_cast_sense(-1, 0) == null, "nor a caster out of range")
	arena.free_all()


func test_a_rings_blast_goes_off_on_its_caster() -> void:
	# A Pulse's blast is at its centre, where it was cast: the AI's fight never casts it at a target.
	check(_sense(["blast", "pulse"]).blast_on_caster, "a blast Pulse blasts on its caster")
	check(not _sense(["blast", "bolt"]).blast_on_caster, "a blast bolt where it ends")
	check(not _sense(["fire", "pulse"]).blast_on_caster, "a Pulse with no blast")

