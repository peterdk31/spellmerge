extends "res://tests/support/suite.gd"
## Spells' state by caster, hashed caster by caster (props W3, core/sim/README.md, "The hash"):
## Spells' PARTED tables (builds, spells by tag, node counts, live counts, last infusion) are walked
## as one part a caster (`state_part`, "Spells 7"), never with the rest of Spells. A caster with
## nothing of its builds alive is its builds as installed; one with shots in the air is its
## generations too, and an older build's spells. The live count by caster (`_caster_live`) is the
## sum of the generations' at every step, which is what lets a resting caster skip its tables. A
## desync report names the caster whose part differs.
##
## godot --headless --path . --script res://tests/core/test_spells_parts.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const SpellsScript := preload("res://core/spells/spells.gd")


func test_a_resting_caster_is_its_builds() -> void:
	var arena := ArenaScript.new(root)
	var spells: SpellsScript = arena.spells
	check_equal(spells.state_parts(), 0, "no build, no parts")
	var bolt: CompiledStaff = arena.install_cards(1, 0, [&"bolt"])
	var fire: CompiledStaff = arena.install_cards(1, 2, [&"fire", &"bolt"])
	check_equal(spells.state_parts(), 2, "ids 0 and 1: one past the highest with a build")
	check_equal(spells.state_part(0), [], "caster 0 has nothing")
	check_equal(spells.state_part(1), [bolt, null, fire, null, null], "caster 1: its four staffs and its last infusion")
	arena.free_all()


func test_an_older_build_in_the_air_joins_the_part() -> void:
	var arena := ArenaScript.new(root)
	var spells: SpellsScript = arena.spells
	arena.install_cards(0, 0, [&"bolt"])
	check(arena.cast(0, 0), "cast")
	arena.run(0.05)
	var flying: Array = spells.state_part(0).duplicate()
	check(flying.size() > 5, "a shot in the air: its generation and live shots join the part: %s" % [flying])
	var old: CompiledSpell = spells.profile(spells.current_tag(0, 0))
	var rebuilt: CompiledStaff = arena.install_cards(0, 0, [&"bolt"])
	var part: Array = spells.state_part(0)
	check(part.has(old) and part[0] == rebuilt, "the older build's spell is in it while its shot flies, the new build installed")
	arena.run(3.0)
	check_equal(arena.projectiles.get_count(), 0, "the shot is gone")
	check_equal(spells.state_part(0), [rebuilt, null, null, null, null], "at rest again: the build only")
	arena.free_all()


## After a busy fight (casts, triggers that fire payloads, echoes that wait, rebuilds and a closed
## caster while shots fly), each caster's live count is the sum of its generations', and one with
## none holds its current generations only, whose spells are its installed builds' nodes.
func test_the_live_count_by_caster_stays_the_sum() -> void:
	var arena := ArenaScript.new(root)
	var spells: SpellsScript = arena.spells
	arena.add_imp(Vector2(80, 0))
	arena.add_imp(Vector2(140, 10))
	var peak: int = 0
	var older: int = 0
	var builds: Array = [[&"bolt"], [&"split", &"bolt"], [&"on_hit", &"bolt", &"nova", &"bolt"], [&"echo", &"fire", &"bolt"], [&"timer", &"bolt", &"blast", &"bolt"]]
	for step in 40:
		var caster: int = step % 4
		if step % 3 == 0:
			arena.install_cards(caster, step % 2, builds[step % builds.size()])
		arena.cast(caster, step % 2)
		if step == 25:
			spells.close_caster(3)
		arena.run(0.05)
		_check_sums(spells, "step %d" % step)
		for actor in 4:
			peak = maxi(peak, spells._caster_live[actor])
			older = maxi(older, spells.generations_held(actor, 0) - 1)
	check(peak > 3 and older > 0, "the fight had shots alive (most %d by one caster) and older builds held (%d)" % [peak, older])
	arena.run(4.0)
	_check_sums(spells, "after")
	for actor in 4:
		check_equal(spells._caster_live[actor], 0, "caster %d: nothing alive at the end" % actor)
	arena.free_all()


func test_a_change_moves_its_casters_part_only() -> void:
	var arena := ArenaScript.new(root)
	var spells: SpellsScript = arena.spells
	arena.install_cards(0, 0, [&"bolt"])
	arena.install_cards(1, 0, [&"bolt"])
	var before: Dictionary[String, int] = SimHash.areas({"Spells": spells})
	check(before.has("Spells") and before.has("Spells 0") and before.has("Spells 1"), "Spells and a part a caster: %s" % [before.keys()])
	spells._last_infused[1] = spells.profile(spells.current_tag(0, 0))
	var after: Dictionary[String, int] = SimHash.areas({"Spells": spells})
	check_equal(after["Spells 1"] != before["Spells 1"], true, "caster 1's part changes")
	check_equal(after["Spells 0"], before["Spells 0"], "caster 0's does not")
	check_equal(after["Spells"], before["Spells"], "nor the rest of Spells")
	# Hashed whole (a lone area, `SimHash.of`), the PARTED tables count too.
	var whole: int = SimHash.of(spells)
	spells._last_infused[1] = null
	check(SimHash.of(spells) != whole, "the whole hash sees a PARTED table")
	arena.free_all()


## Two runs whose caster 1 parts (another build): the desync report names Spells' part of caster
## 1, and caster 0's and the rest of Spells' agree.
func test_a_desync_names_the_caster() -> void:
	var a := ArenaScript.new(root)
	var b := ArenaScript.new(root)
	for arena: ArenaScript in [a, b]:
		arena.install_cards(0, 0, [&"bolt"])
		arena.install_cards(1, 0, [&"bolt"])
	b.spells._last_infused[1] = b.spells.profile(b.spells.current_tag(0, 0))
	var first := Desync.new(0)
	var second := Desync.new(0)
	first.capture({"Spells": a.spells})
	second.capture({"Spells": b.spells})
	var report: String = Desync.compare(first, second)
	check(report.contains("in Spells 1\n"), "the report names caster 1's part only: %s" % report)
	check(report.contains("Spells 1[4]"), "and the member that differs, by its place in the part: %s" % report)
	a.free_all()
	b.free_all()


func _check_sums(spells: SpellsScript, when: String) -> void:
	var sums: Dictionary[int, int] = {}
	for key: int in spells._generation_live:
		var actor: int = SpellTag.caster_of(key)
		sums[actor] = sums.get(actor, 0) + int(spells._generation_live[key])
	for actor in 4:
		check_equal(spells._caster_live[actor], sums.get(actor, 0), "%s: caster %d's live count" % [when, actor])
	for key: int in spells._node_counts:
		var actor: int = SpellTag.caster_of(key)
		var staff: int = SpellTag.staff_of(key)
		var generation: int = SpellTag.generation_of(key)
		var current: bool = spells.current_tag(actor, staff) != 0 and SpellTag.generation_of(spells.current_tag(actor, staff)) == generation
		if spells._caster_live[actor] == 0:
			check(current, "%s: caster %d at rest holds only its current generations (staff %d holds %d)" % [when, actor, staff, generation])
		if current:
			var build: CompiledStaff = spells._installed[actor * SpellLimits.STAFFS + staff]
			check_equal(int(spells._node_counts[key]), build.nodes.size(), "%s: a current generation's nodes are its build's" % when)
			for spell in build.nodes:
				check(spells.profile(SpellTag.make(actor, staff, spell.node, generation)) == spell, "%s: a current generation's spells are its build's nodes" % when)
