extends "res://tests/support/suite.gd"
## The Old Broom v0 (boss OB3, docs/milestones/boss-old-broom.md): the first boss, as data. Its data
## is sound, the registry finds it under bosses, it fights in the crypt, its line of lore keeps the
## story's rules, every staff of both phases casts and wastes no card, and phase 2 ("Spring
## cleaning") brings the double Sweep, its burning look and its own profile under 55% health.
##
## This test is the broom's own: deleting its folder deletes it (decision 28).
##
## godot --headless --path . --script res://content/bosses/old_broom/test_old_broom.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const BROOM: EnemyBase = preload("res://content/bosses/old_broom/old_broom.tres")


func _spells() -> SpellsScript:
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = root.get_node("Registry")
	return spells


func _all_staffs() -> Array[StaffCards]:
	var entries: Array[StaffCards] = BROOM.staffs.duplicate()
	for phase: EnemyPhase in BROOM.phases:
		entries.append_array(phase.staffs)
	return entries


func test_it_is_sound() -> void:
	check_equal(BROOM.problems(), PackedStringArray(), "its data")
	check_equal(BROOM.id, &"old_broom", "its id is its folder's")
	check(BROOM.boss, "a boss")
	check_equal(BROOM.shown_name(), "The Old Broom", "its name")
	var registry: Node = root.get_node("Registry")
	check(registry.call("get_resource", &"bosses", &"old_broom") == BROOM, "the registry finds it under bosses")
	check(BROOM.fights_in(&"crypt", 0), "it fights in the crypt")


func test_its_lore_is_one_short_line() -> void:
	check(BROOM.lore != "", "it has its line of lore")
	check_equal(StoryValidator.check_lore(BROOM.resource_path, BROOM.lore, BROOM.boss).size(), 0, "within the story's rules")


func test_every_staff_casts_and_wastes_no_card() -> void:
	var spells: SpellsScript = _spells()
	var registry: Node = root.get_node("Registry")
	for entry: StaffCards in _all_staffs():
		var name: String = entry.staff.display_name
		check_equal(SpellValidator.check_staff(entry.staff).size(), 0, "%s: the staff is valid" % name)
		for id: StringName in entry.cards:
			check(registry.call("get_resource", &"spells", id) is SpellComponent, "%s: %s is a card" % [name, id])
		var view: Dictionary = spells.staff_view(entry.cards, entry.staff)
		check(not bool(view.get("empty", true)), "%s casts" % name)
		check_equal(view.get("wasted"), {}, "%s wastes no card (slot: wasted)" % name)
		var cycle: float = 0.0
		for cast: Dictionary in view.get("casts", []):
			cycle += float(cast.get("mana", 0.0))
		check(cycle <= entry.staff.max_mana, "%s: a full staff casts its whole cycle (%s of %s mana)" % [name, cycle, entry.staff.max_mana])


func test_the_sweep_is_a_telegraphed_charge() -> void:
	check_equal(BROOM.staffs.size(), 3, "phase 1: the Sweep, the dust flick and the swat")
	check(BROOM.staffs[0].cards.has(&"dash") and BROOM.staffs[0].cards.has(&"lumber"), "the Sweep is a long, heavy charge (Lumber, OB4)")
	check(is_equal_approx(BROOM.staffs[0].staff.wind_up, 0.8), "winding up 0.8 s in phase 1")
	check(BROOM.contact_damage > 0, "touching it hurts")


func test_spring_cleaning() -> void:
	check_equal(BROOM.phases.size(), 1, "a second phase")
	var phase: EnemyPhase = BROOM.phases[0]
	check(is_equal_approx(phase.health_below, 0.55), "under 55% health")
	check(phase.transition > 0.0, "a transition it stands through")
	check(phase.profile != null and phase.profile != BROOM.profile, "its own profile")
	check(phase.look != null and phase.look.texture != null, "its burning look")
	var sweep: StaffCards = phase.staffs[0]
	check(is_equal_approx(sweep.staff.wind_up, 0.6), "winding up 0.6 s")
	check_equal(sweep.cards.count(&"dash"), 2, "two Sweeps, each with its own wind-up")
	check_equal(sweep.cards.count(&"fire"), 2, "each leaving a burning trail")
	check_equal(sweep.cards.count(&"lumber"), 2, "each a Lumber charge")
	var casts: Array = _spells().staff_view(sweep.cards, sweep.staff).get("casts", [])
	check_equal(casts.size(), 2, "its cycle is two casts")
	for cast: Dictionary in casts:
		check(float(cast.get("wind_up", 0.0)) >= sweep.staff.wind_up, "each winds up on its own: %s" % cast.get("wind_up"))


func test_it_enters_play_and_changes_phase() -> void:
	var fx := Fixture.new(root)
	fx.players[0].position = Vector2(200.0, 0.0)
	var body: Actor = fx.enemy(BROOM.scene, BROOM, Vector2.ZERO)
	check(body.caster != null and body.caster.staff_count == 3, "it holds its three staffs")
	check(body.caster.next_cast_sense(0).moves_caster, "staff 0, the Sweep, moves it")
	check(body.phases != null, "its phases run")
	fx.run(body, 2)
	check_equal(body.phases.current, -1, "no phase at full health")
	fx.combat.hit(fx.players[0].id, body, BROOM.max_health * 0.5)
	fx.run(body, 1)
	check_equal(body.phases.current, 0, "under 55% health, spring cleaning starts")
	check(body.caster.cards_of(0).count(&"dash") == 2, "with the double Sweep")
	fx.free_all()
