extends "res://tests/support/suite.gd"
## What a cast does, for an AI (`CastSense`, docs/milestones/M2-enemy-ai.md, AI2): the summary the
## compiler makes of every cast, read with `Spells.next_cast_sense`. Real cards from the registry.
##
## godot --headless --path . --script res://tests/core/test_cast_sense.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


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
	var sense: CastSense = _sense(["nova"])
	check_equal(sense.reach, 0.0, "a nova is not aimed")
	check(sense.area, "it hits round its caster")
	check(sense.close_reach > 20.0, "within its ring: %s" % sense.close_reach)
	check(sense.damage > 0.0, "and hurts")


func test_moves_blocks_spawns_heals() -> void:
	check(_sense(["dash"]).moves_caster, "a dash moves its caster")
	check(_sense(["teleport"]).moves_caster, "a teleport too")
	check(_sense(["wall"]).blocks, "a wall blocks shots")
	check(_sense(["shield"]).blocks, "a shield on the caster blocks")
	check(_sense(["decoy"]).spawns, "a decoy is a body of its own")
	check(_sense(["familiar"]).spawns, "a familiar too")
	var mend: CastSense = _sense(["mend", "bolt"])
	check(mend.heals, "a mend bolt heals")
	check_equal(mend.damage, 0.0, "and hurts nobody")


func test_held_and_sustained() -> void:
	check(_sense(["beam"]).repeats_held, "a beam goes on while held")
	check(_sense(["rain"]).repeats_held, "a rain falls again while held")
	var hold: CastSense = _sense(["hold", "orbit"])
	check(hold.sustained, "a held orbit stays until pressed again")
	check(not _sense(["bolt"]).sustained, "a bolt does not")


func test_a_blast_is_known() -> void:
	var sense: CastSense = _sense(["blast", "bolt"])
	check(sense.blast > 0.0, "a blast bolt explodes: %s" % sense.blast)
	check(sense.harms(), "and harms")


func test_a_rain_hurts_with_what_it_drops() -> void:
	var sense: CastSense = _sense(["rain", "nova"])
	check(sense.area, "a rain falls on a point")
	check(sense.damage > 0.0, "and hurts with its payload")


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
