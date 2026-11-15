extends "res://tests/support/suite.gd"
## The Old Broom v0 (boss OB3, docs/milestones/boss-old-broom.md): the first boss, as data. Its data
## is sound, the registry finds it under bosses, it fights in the crypt, its line of lore keeps the
## story's rules, every staff of both phases casts and wastes no card, and phase 2 ("Spring
## cleaning") brings the double Sweep, its burning look and its own profile under 55% health. Its
## body is layered (boss plan OB8): a head, its handle and its binding, which carries the face; in
## phase 2 the head burns and gives off sparks that follow it. Its look (boss plan OB9): its own
## face (an old staff's eyes and brows, angrier in phase 2), drawn frames for its extreme poses on
## both heads, and an impatient tap standing.
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
	check(BROOM.staffs[0].cards.has(&"plow"), "that carries what it meets and pins it to the walls (Plow, OB11)")
	check_equal(BROOM.staffs[0].cards, [&"on_wall", &"bigger", &"lumber", &"plow", &"dash", &"pulse"] as Array[StringName], "a wall that stops it sets off its dust ring (OB12)")
	check(is_equal_approx(BROOM.staffs[0].staff.wind_up, 0.8), "winding up 0.8 s in phase 1")
	check(BROOM.contact_damage > 0, "touching it hurts")


func test_the_dust_flick_goes_where_its_lane_shows() -> void:
	# Decision 34 (OB10): three slow bolts aimed at the player, a little spread, not scattered.
	var flick: StaffCards = BROOM.staffs[1]
	check(not flick.cards.has(&"scatter"), "no scatter: it ignored the aim")
	check(flick.cards.has(&"triple") and flick.cards.count(&"bolt") == 3 and flick.cards.count(&"slow") == 3, "a Triple of slow bolts")
	check(flick.staff.spread > 0.0 and flick.staff.spread <= 15.0, "a small spread between them (%s degrees)" % flick.staff.spread)
	var fx := Fixture.new(root)
	fx.players[0].position = Vector2(200.0, 0.0)
	var body: Actor = fx.enemy(BROOM.scene, BROOM, Vector2.ZERO)
	body.aim = Vector2.RIGHT
	check(body.caster.cast(1), "it flicks")
	# Its shots of staff 1 once they leave (its wind-up first; its AI may cast its other staffs).
	var shots: Array[Vector2] = []
	for i in 60:
		fx.run(body, 1)
		shots.clear()
		for slot in fx.projectiles.get_cap():
			if fx.projectiles.is_alive(slot) and fx.projectiles.get_actor_of(slot) == body.id and SpellTag.staff_of(fx.projectiles.get_tag_of(slot)) == 1:
				shots.append(fx.projectiles.get_velocity_of(slot))
		if not shots.is_empty():
			break
	check_equal(shots.size(), 3, "three bolts")
	for shot: Vector2 in shots:
		var angle: float = rad_to_deg(absf(shot.angle()))
		check(angle <= flick.staff.spread + 0.01, "each along the aim, within its spread (%.1f degrees)" % angle)
	fx.free_all()


func test_spring_cleaning() -> void:
	check_equal(BROOM.phases.size(), 1, "a second phase")
	var phase: EnemyPhase = BROOM.phases[0]
	check(is_equal_approx(phase.health_below, 0.55), "under 55% health")
	check(phase.transition > 0.0, "a transition it stands through")
	check(phase.profile != null and phase.profile != BROOM.profile, "its own profile")
	check(phase.look != null and phase.look.parts.get(&"Head") is Texture2D, "its burning head (boss plan OB8)")
	check(phase.look.motes != null and phase.look.motes_on == &"Head", "giving off sparks from the head")
	check_equal(phase.look.motes.problems(false), PackedStringArray(), "the sparks' data")
	var sweep: StaffCards = phase.staffs[0]
	check(is_equal_approx(sweep.staff.wind_up, 0.6), "winding up 0.6 s")
	check_equal(sweep.cards.count(&"dash"), 2, "two Sweeps, each with its own wind-up")
	check_equal(sweep.cards.count(&"fire"), 2, "each leaving a burning trail")
	check_equal(sweep.cards.count(&"lumber"), 2, "each a Lumber charge")
	check_equal(sweep.cards.count(&"plow"), 2, "each carrying and pinning (Plow, OB11)")
	check_equal(sweep.cards.count(&"on_wall"), 2, "each ringing out at a wall (OB12)")
	check_equal(sweep.cards.count(&"pulse"), 2, "its dust ring")
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


func test_its_stats() -> void:
	# Boss plan OB7, "The broom's data": its numbers live in its own data, never in general code.
	var stats: ActorStats = BROOM.stats
	check(stats != null, "it has stats")
	check(is_equal_approx(stats.power, 2.0), "power 2 in phase 1")
	check(stats.mass > 1.0 and stats.spell_scale > 1.0, "heavier and bigger-spelled than a wizard")
	check(is_equal_approx(stats.resist_chill, 0.6) and is_equal_approx(stats.resist_burn, 0.3) and is_equal_approx(stats.resist_possess, 0.7), "its resists")
	var phase_2: ActorStats = BROOM.phases[0].stats
	check(phase_2 != null and is_equal_approx(phase_2.power, 2.5), "power 2.5 in phase 2")
	var fx := Fixture.new(root)
	var body: Actor = fx.enemy(BROOM.scene, BROOM, Vector2.ZERO)
	check(is_equal_approx(body.stats.power, 2.0), "the body takes its stats")
	fx.combat.hit(fx.players[0].id, body, BROOM.max_health * 0.5)
	fx.run(body, 1)
	check(is_equal_approx(body.stats.power, 2.5), "and phase 2's")
	fx.free_all()


func test_its_layered_body() -> void:
	# Boss plan OB8: the broom's look is its own data (its scene and phase look), never general code.
	var fx := Fixture.new(root)
	var body: Actor = fx.enemy(BROOM.scene, BROOM, Vector2.ZERO)
	var look := body.get_node("CreatureLook") as CreatureLook
	var names: Array[StringName] = []
	for part in look.parts():
		names.append(StringName(part.name))
	check_equal(names, [&"Head", &"Handle", &"Binding"] as Array[StringName], "its parts")
	var head := body.get_node("Sprite/Head") as BodyPart
	var binding := body.get_node("Sprite/Head/Binding") as BodyPart
	check(binding.carries_face, "the face rides the binding")
	check(head.fling > 1.0 and binding.fling > 1.0, "the bound head flies off when it dies")
	var art: Texture2D = head.texture
	fx.combat.hit(fx.players[0].id, body, BROOM.max_health * 0.5)
	fx.run(body, 1)
	check(head.texture != art and head.texture == BROOM.phases[0].look.parts[&"Head"], "phase 2 sets the head on fire")
	var sparks: Node2D = look.phase_motes()
	check(sparks != null and sparks.get_parent() == head, "its sparks come off the head")
	check(MoteSource.follows(sparks), "and follow it")
	fx.free_all()


func test_its_own_face_and_drawn_poses() -> void:
	# Boss plan OB9, decision 14: its own face, not a stray's, and a few drawn frames for the extreme
	# poses; the numbers are its scene's.
	var fx := Fixture.new(root)
	var body: Actor = fx.enemy(BROOM.scene, BROOM, Vector2.ZERO)
	var face := body.get_node("Face") as Face
	check(face.art != null and face.art.eyes != null and face.art.brows != null, "a face of its own")
	check(face.art.eyes.resource_path.begins_with("res://content/bosses/old_broom/"), "drawn in its folder")
	check_equal(face.art.eyes.get_width(), face.art.frame.x * 10, "ten looks a row (nine and the blink)")
	check_equal(face.art.brows.get_width(), face.art.frame.x * Face.Mood.size(), "a brow a mood")
	check_equal(face.art.eyes.get_height(), face.art.frame.y * 2, "its own eyes and phase 2's")
	check_equal(face.art.brows.get_height(), face.art.frame.y * 2, "its own brows and phase 2's")
	check_equal(BROOM.phases[0].look.face_row, 1, "phase 2 shows the angrier row")
	var head := body.get_node("Sprite/Head") as BodyPart
	var burning: Texture2D = BROOM.phases[0].look.parts[&"Head"]
	check_equal(head.texture.get_width(), head.hframes * 88, "the head's frames, 88 px each")
	check_equal(burning.get_width(), head.texture.get_width(), "the burning head has the same frames")
	check_equal(burning.get_height(), head.texture.get_height(), "of the same height")
	var frames: Dictionary = {}
	for pose in BodyPose.Pose.values():
		frames[pose] = head.frame_for(pose)
	check_equal(frames[BodyPose.Pose.IDLE], 0, "at rest: the first frame")
	check_equal(frames[BodyPose.Pose.MOVE], 0, "sweeping too (the game swishes and squashes it)")
	var drawn: Array = [frames[BodyPose.Pose.WINDUP], frames[BodyPose.Pose.WALL], frames[BodyPose.Pose.CAST], frames[BodyPose.Pose.TRANSITION]]
	check_equal(drawn, [1, 2, 3, 4], "drawn frames for the wind-up, the wall hit, the swat and the phase change")
	check(head.tap > 0.0, "it taps the floor standing")
	fx.free_all()
