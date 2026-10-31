extends "res://tests/support/suite.gd"
## An echo, a zap, a relay and a chain jump hit with the carrier's whole hit (phase R, R1a,
## docs/milestones/M2-rules.md, rule 2: nothing takes a card away): heal, slam, every status and
## the kind stay; only the strength is scaled. An echoed mend bolt heals a teammate, a relay mend
## bolt still heals, an echoed beam's chain jumps hit at the echo's half on every tick.
##
## godot --headless --path . --script res://tests/core/test_spells_whole_hit.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

const ALLY_HURT: int = 40
const BIG: int = 100000


## Health a BIG imp has lost.
func _lost_big(arena: ArenaScript, imp: Node2D) -> int:
	return BIG - arena.combat.health_of(imp)


func _spell(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


## Casts `cards` from seat 0 at a hurt teammate (seat 1) at 60 px with an imp at 110 px; returns
## [health the teammate got back, health the imp lost, health the teammate still lacks].
func _party(cards: Array) -> Array[int]:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(110.0, 0.0))
	var ally: Node2D = arena.add_guard(1, Vector2(60.0, 0.0))
	arena.hurt(ally, ALLY_HURT)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(1.5)
	var out: Array[int] = [arena.healed(), arena.lost(imp), arena.lost(ally)]
	arena.free_all()
	return out


func test_an_echo_hit_is_the_whole_hit_at_half() -> void:
	var spell: CompiledSpell = _spell(["fire", "frost", "heavy", "mend", "echo", "bolt"])
	var hit: HitProfile = spell.hit
	var echo: HitProfile = spell.echo_hit
	check(echo != null, "the carrier has an echo hit")
	if echo == null:
		return
	check(hit.heal > 0 and hit.slam > 0, "the carrier heals and slams")
	check_equal(echo.damage, hit.damage * SpellLimits.ECHO_DAMAGE, "half the damage, not rounded")
	check_equal(echo.heal, roundi(hit.heal * SpellLimits.ECHO_DAMAGE), "half the heal")
	check_equal(echo.slam, roundi(hit.slam * SpellLimits.ECHO_DAMAGE), "half the slam")
	check(echo.heal > 0 and echo.slam > 0, "an echo still heals and slams")
	check_equal(echo.knockback, hit.knockback, "the heavy knockback")
	check_equal(echo.element_ids, hit.element_ids, "every element")
	check_equal(echo.status_id, hit.status_id, "the first status")
	check_equal(echo.later_status_ids, hit.later_status_ids, "the later statuses")
	check(not echo.later_status_ids.is_empty(), "the second infusion's status is there")
	check_equal(echo.kind, hit.kind, "the kind")
	check(echo != hit and echo.element_ids != null, "its own profile")


func test_an_echoed_beam_hits_as_a_ray() -> void:
	var spell: CompiledSpell = _spell(["echo", "beam"])
	check_equal(spell.echo_hit.kind if spell.echo_hit != null else &"", &"ray", "a beam's echo is a ray hit")


func test_an_echoed_mend_bolt_heals_the_teammate_and_never_hurts_it() -> void:
	var plain: Array[int] = _party(["mend", "pierce", "bolt"])
	var echoed: Array[int] = _party(["echo", "mend", "pierce", "bolt"])
	check(plain[0] > 0, "a mend bolt heals (%d)" % plain[0])
	check_equal(echoed[0], plain[0] + roundi(plain[0] * SpellLimits.ECHO_DAMAGE), "the echo heals half again")
	check_equal(echoed[2], ALLY_HURT - echoed[0], "the teammate was never hurt")
	check_equal(echoed[1], plain[1] + floori(plain[1] * SpellLimits.ECHO_DAMAGE), "the imp takes half the enemy share again (1.5: 1 whole point)")


func test_a_relay_mend_bolt_still_heals_after_it_takes_on_frost() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(110.0, 0.0))
	var ally: Node2D = arena.add_guard(1, Vector2(60.0, 0.0))
	arena.hurt(ally, ALLY_HURT)
	arena.install_cards(1, 0, ["frost", "bolt"])
	arena.install_cards(0, 0, ["relay", "mend", "pierce", "bolt"])
	check(arena.cast(1, 0, Vector2.DOWN), "the teammate casts frost")
	arena.run(0.1)
	check(arena.cast(0, 0), "the relay mend bolt is cast")
	arena.run(1.5)
	check(arena.healed() > 0, "the teammate is healed")
	check_equal(arena.lost(ally), ALLY_HURT - arena.healed(), "and never hurt")
	check(arena.was_given(imp, &"chill"), "the bolt took on the frost")
	arena.free_all()


func test_relay_keeps_each_new_elements_status() -> void:
	# A relay bolt that takes on frost and lightning from a teammate: both statuses ride on.
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(110.0, 0.0), BIG)
	arena.add_guard(1, Vector2(60.0, 0.0))
	arena.install_cards(1, 0, ["frost", "lightning", "bolt"])
	arena.install_cards(0, 0, ["relay", "pierce", "bolt"])
	check(arena.cast(1, 0, Vector2.DOWN), "the teammate casts frost and lightning")
	arena.run(0.1)
	check(arena.cast(0, 0), "the relay bolt is cast")
	arena.run(1.5)
	# Every two statuses react: the first one alone would not.
	check(arena.was_given(imp, &"chill"), "the first element's status")
	check(not arena.reaction_ids().is_empty(), "the second one's status reacts with it")
	arena.free_all()


func test_an_echoed_beams_jumps_hit_at_half_on_every_tick() -> void:
	var arena := ArenaScript.new(root)
	var first: Node2D = arena.add_imp(Vector2(60.0, 0.0), BIG)
	var second: Node2D = arena.add_imp(Vector2(60.0, 40.0), BIG)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["echo", "chain", "beam"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	# [seconds, target, damage] of every hit.
	var hits: Array = []
	arena.bus.projectile_hit.connect(func(_actor: int, target: Node, _at: Vector2, tag: int, _shot: int) -> void:
		var profile: HitProfile = arena.spells.hit_profile(tag)
		hits.append([arena.time, target, profile.damage if profile != null else -1]))
	check(arena.cast(0, 0), "the beam is cast")
	arena.run(0.9)
	var full: float = spell.hit.damage
	var half: float = spell.echo_hit.damage
	check(half < full, "the echo is weaker (%.2f < %.2f)" % [half, full])
	# The beam lives 0.3 s and its echo comes 0.3 s after it; each hits every 0.15 s.
	var later_jumps: int = 0
	for row: Array in hits:
		var at: float = row[0]
		if at < 0.29:
			check_equal(row[2], full, "the beam hits at full damage at %.2f s" % at)
		else:
			check_equal(row[2], half, "the echo hits at half at %.2f s" % at)
			if row[1] == second and at > 0.31:
				later_jumps += 1
	check(later_jumps > 0, "the echo's jumps hit after its first tick (%d)" % later_jumps)
	check(_lost_big(arena, first) > 0 and _lost_big(arena, second) > 0, "both imps are hit")
	arena.free_all()


func test_an_echoed_shots_zaps_hit_at_the_echos_share() -> void:
	var spell: CompiledSpell = _spell(["echo", "zap", "rune"])
	check(spell.echo_zap_hit != null, "an echoed shot has its own zap")
	if spell.echo_zap_hit == null:
		return
	check(is_equal_approx(spell.echo_zap_hit.damage, spell.echo_hit.damage * SpellLimits.ZAP_DAMAGE), "the echo's damage at the zap's share")
	check_equal(spell.echo_zap_hit.kind, &"ray", "a zap is a ray hit")
	# (How often a rune zaps is the card's chance, tests/content/spells/test_zap.gd: one roll a body.)


func test_a_zap_keeps_slam_and_heal() -> void:
	var spell: CompiledSpell = _spell(["heavy", "mend", "zap", "bolt"])
	check(spell.zap_hit.slam > 0, "a heavy shot's zap slams")
	check(spell.zap_hit.heal > 0, "a mend shot's zap heals")
	check_equal(spell.zap_hit.knockback, spell.hit.knockback * SpellLimits.ZAP_DAMAGE, "at the zap's share of knockback")
