extends "res://tests/support/suite.gd"
## Spells' state by caster, hashed caster by caster (props W3, core/sim/README.md, "The hash"):
## Spells' BY_ACTOR tables (builds, spells by tag, node counts, live counts, last infusion) are walked
## as one part a caster (`actor_part`, "Spells 7"), never with the rest of Spells. A caster with
## nothing of its builds alive is its builds as installed; one with shots in the air is its
## generations too, and an older build's spells. What lets a resting caster skip its tables is
## checked by `actor_part_problems`, here through fights and a wrap of the generations, and at every walk
## of every card (tests/core/test_state_walked.gd). Every change to a BY_ACTOR table either changes
## its caster's part or is named by `actor_part_problems`; a table with no case here fails. A desync
## report names the caster.
##
## godot --headless --path . --script res://tests/core/test_spells_parts.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const SpellsScript := preload("res://core/spells/spells.gd")


func test_a_resting_caster_is_its_builds() -> void:
	var arena := ArenaScript.new(root)
	var spells: SpellsScript = arena.spells
	check_equal(spells.actor_parts(), 0, "no build, no parts")
	arena.install_cards(1, 0, [&"bolt"])
	check_equal(spells.actor_parts(), 2, "ids 0 and 1: one past the highest with a build")
	check_equal(spells.actor_part(0), [], "caster 0 has nothing: an empty share")
	var before: Dictionary[String, int] = SimHash.areas({"Spells": spells})
	check(before.has("Spells 1") and not before.has("Spells 0"), "an empty share is no area: %s" % [before.keys()])
	arena.install_cards(1, 2, [&"fire", &"bolt"])
	var after: Dictionary[String, int] = SimHash.areas({"Spells": spells})
	check(after["Spells 1"] != before["Spells 1"], "another build changes the caster's part")
	check_equal(spells.actor_part_problems(), PackedStringArray(), "nothing wrong")
	arena.free_all()


## While an older build's shot flies, its generation is in its caster's part; once it is gone the
## part hashes as that of a caster that never cast (a resting caster is its builds).
func test_an_older_build_in_the_air_joins_the_part() -> void:
	var arena := ArenaScript.new(root)
	var spells: SpellsScript = arena.spells
	arena.install_cards(0, 0, [&"bolt"])
	var resting: int = SimHash.areas({"Spells": spells})["Spells 0"]
	check(arena.cast(0, 0), "cast")
	arena.run(0.05)
	arena.install_cards(0, 0, [&"bolt"])
	check(arena.projectiles.get_count() > 0 and spells.generations_held(0, 0) == 2, "the older build's shot flies")
	check(SimHash.areas({"Spells": spells})["Spells 0"] != resting, "the older generation is in the part")
	check_equal(spells.actor_part_problems(), PackedStringArray(), "nothing wrong while it flies")
	arena.run(3.0)
	check_equal(arena.projectiles.get_count(), 0, "the shot is gone")
	check_equal(SimHash.areas({"Spells": spells})["Spells 0"], resting, "at rest again: its builds only, as before it cast")
	arena.free_all()


## After a busy fight (casts, triggers that fire payloads, echoes that wait, rebuilds and a closed
## caster while shots fly), the parts still stand at every step.
func test_the_parts_stand_through_a_fight() -> void:
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
		check_equal(spells.actor_part_problems(), PackedStringArray(), "step %d" % step)
		peak = maxi(peak, arena.projectiles.get_count())
		for actor in 4:
			older = maxi(older, spells.generations_held(actor, 0) - 1)
	check(peak > 3 and older > 0, "the fight had shots alive (most %d) and older builds held (%d)" % [peak, older])
	arena.run(4.0)
	check_equal(arena.projectiles.get_count(), 0, "nothing alive at the end")
	check_equal(spells.actor_part_problems(), PackedStringArray(), "after")
	arena.free_all()


## One staff rebuilt round the whole ring of generations while slow shots of every build fly: the
## oldest generation is revoked with its shots alive (`begin_generation` takes all of it at once).
func test_the_parts_stand_when_the_generations_wrap() -> void:
	var arena := ArenaScript.new(root)
	var spells: SpellsScript = arena.spells
	var revoked: int = 0
	for build in SpellLimits.GENERATIONS + 3:
		arena.install_cards(0, 0, [&"slow", &"bolt"])
		revoked += spells.revoked_tags.size()
		check(arena.cast(0, 0), "build %d casts (past the wind-down)" % build)
		# 0.4 s a build: past the bolt's wind-down, and a slow bolt (3.6 s) of the first build still
		# flies when the eighth build takes its generation.
		arena.run(0.4)
		check_equal(spells.actor_part_problems(), PackedStringArray(), "build %d" % build)
	check(revoked > 0, "a generation was revoked with its shots in the air")
	check(arena.projectiles.get_count() > 0, "shots still fly")
	arena.run(10.0)
	check_equal(spells.actor_part_problems(), PackedStringArray(), "after")
	arena.free_all()


## Every BY_ACTOR table, changed for caster 1 (resting, then with shots in the air), changes caster 1's
## part, or is named by `actor_part_problems`; caster 0's part never changes. A table BY_ACTOR lists that
## this test cannot change fails here: give it a case.
func test_every_parted_table_is_hashed_or_checked() -> void:
	for alive: bool in [false, true]:
		for member: StringName in SpellsScript.BY_ACTOR:
			var arena := ArenaScript.new(root)
			var spells: SpellsScript = arena.spells
			# Caster 0's build differs from caster 1's: what a case puts in is another spell (a FROZEN
			# spell hashes by what it holds, so an equal one would change nothing).
			arena.install_cards(0, 0, [&"split", &"bolt"])
			arena.install_cards(1, 0, [&"bolt"])
			if alive:
				arena.cast(1, 0)
				arena.run(0.05)
				arena.install_cards(1, 0, [&"bolt"])
			var before: Dictionary[String, int] = SimHash.areas({"Spells": spells})
			var changed: bool = _change(spells, member, 1)
			check(changed, "%s: a case changes it for caster 1 (alive: %s)" % [member, alive])
			var after: Dictionary[String, int] = SimHash.areas({"Spells": spells})
			var hashed: bool = after.get("Spells 1") != before.get("Spells 1")
			check(hashed or not spells.actor_part_problems().is_empty(), "%s (alive: %s): hashed in caster 1's part, or named by actor_part_problems" % [member, alive])
			if alive and member != &"_profiles" and member != &"_node_counts":
				check(hashed, "%s: with shots in the air, hashed" % member)
			check_equal(after.get("Spells 0"), before.get("Spells 0"), "%s: caster 0's part does not change" % member)
			arena.free_all()


func test_a_part_goes_with_its_body_in_the_spread_hash() -> void:
	var arena := ArenaScript.new(root)
	var spells: SpellsScript = arena.spells
	for actor in 4:
		arena.install_cards(actor, 0, [&"bolt"])
	var first: Dictionary = SimHash.slice({"Spells": spells}, 1, 2)
	var second: Dictionary = SimHash.slice({"Spells": spells}, 0, 2)
	check(first.has("Spells 1") and first.has("Spells 3") and not first.has("Spells 0"), "odd casters in part 1: %s" % [first.keys()])
	check(second.has("Spells 0") and second.has("Spells 2"), "even ones in part 0: %s" % [second.keys()])
	check_equal(int(first.has("Spells")) + int(second.has("Spells")), 1, "the rest of Spells in one part")
	arena.free_all()


## Two runs whose caster 1 parts (another infusion): the desync report names Spells' part of caster
## 1 only.
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
	a.free_all()
	b.free_all()


## Changes `member` (a BY_ACTOR table) for `actor`: an entry of its, or one added for it. False when
## there is no case for that table.
func _change(spells: SpellsScript, member: StringName, actor: int) -> bool:
	var other: CompiledSpell = spells.profile(spells.current_tag(0, 0))
	var other_build: CompiledStaff = spells._installed[0]
	match member:
		&"_installed":
			spells._installed[actor * SpellLimits.STAFFS + 1] = other_build
		&"_last_infused":
			spells._last_infused[actor] = other
		&"_profiles", &"_node_counts", &"_live", &"_generation_live":
			var table: Dictionary = spells.get(member)
			for key: int in table:
				if SpellTag.caster_of(key) == actor:
					var value: Variant = table[key]
					table[key] = other if value is CompiledSpell else int(value) + 1
					return true
			# None of its yet: one added.
			var tag: int = SpellTag.make(actor, 0, 0, SpellTag.generation_of(spells.current_tag(actor, 0)))
			var key: int = SpellTag.generation_key(tag) if member == &"_node_counts" or member == &"_generation_live" else tag
			table[key] = other if member == &"_profiles" else 1
		_:
			return false
	return true
