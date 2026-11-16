extends "res://tests/support/suite.gd"
## The Old Broom v0 (boss OB3, docs/milestones/boss-old-broom.md): the first boss, as data. Its data
## is sound, the registry finds it under bosses, it fights in the crypt, its line of lore keeps the
## story's rules, every staff of both phases casts and wastes no card, and phase 2 ("Spring
## cleaning") brings the double Sweep, its burning look and its own profile under 55% health. Its
## body is layered (boss plan OB8): a head, its handle and its binding, which carries the face; in
## phase 2 the head burns and gives off sparks that follow it. Its look (boss plan OB9): its own
## face (an old staff's eyes and brows, angrier in phase 2), drawn frames for its extreme poses on
## both heads, and an impatient tap standing. Its Big Sweep (boss plan OB14): a long Sweep it runs up
## to a wall's foot for, about every 20 s, not its first move but phase 2's; phase 1 locks its aim as
## its wind-up starts, phase 2 for its last 0.25 s, and both turn to the player swept longest ago.
## Its sounds (boss plan OB15): every sound id of the plan's sound sheet named in its cue or data,
## its wind-ups' scrapes held with their lanes, its swish held while it sweeps, its burning held for
## phase 2, and its music two stacked layers, phase 2 one step up.
##
## This test is the broom's own: deleting its folder deletes it (decision 28).
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
	check_equal(BROOM.staffs.size(), 4, "phase 1: the Sweep, the dust flick, the swat and the Big Sweep")
	check(BROOM.staffs[0].cards.has(&"dash") and BROOM.staffs[0].cards.has(&"lumber"), "the Sweep is a long, heavy charge (Lumber, OB4)")
	check(BROOM.staffs[0].cards.has(&"plow"), "that carries what it meets and pins it to the walls (Plow, OB11)")
	check_equal(BROOM.staffs[0].cards, [&"on_wall", &"bigger", &"lumber", &"plow", &"dash", &"pulse"] as Array[StringName], "a wall that stops it sets off its dust ring (OB12)")
	check(is_equal_approx(BROOM.staffs[0].staff.wind_up, 0.8), "winding up 0.8 s in phase 1")
	check(BROOM.contact_damage > 0, "touching it hurts")


func test_the_big_sweep() -> void:
	# Boss plan OB14, "The broom's data": on wall · reach · reach · bigger · bigger · lumber · plow ·
	# dash · pulse, about 610 px long, every 20-25 s, first when phase 2 starts.
	var big: StaffCards = BROOM.staffs[3]
	check_equal(big.cards, [&"on_wall", &"reach", &"reach", &"bigger", &"bigger", &"lumber", &"plow", &"dash", &"pulse"] as Array[StringName], "the Sweep, twice as far and wider")
	check(big.staff.cooldown >= 18.0 and big.staff.cooldown <= 25.0, "its long cooldown gives its pace (%s s)" % big.staff.cooldown)
	check(big.staff.first_wait > 0.0, "not its first move as it enters (%s s)" % big.staff.first_wait)
	check(big.staff.wind_up >= BROOM.staffs[0].staff.wind_up, "winding up no quicker than the Sweep")
	check(BROOM.phases[0].staffs.has(big), "it stays in phase 2")
	var fx := Fixture.new(root)
	fx.players[0].position = Vector2(200.0, 0.0)
	var body: Actor = fx.enemy(BROOM.scene, BROOM, Vector2.ZERO)
	var sense: CastSense = body.caster.next_cast_sense(3)
	check(sense != null and sense.moves_along and sense.harms(), "a move along its line that hurts: what the run-up is for")
	check(sense.move_reach > 560.0 and sense.move_reach < 660.0, "about 610 px long (%s)" % sense.move_reach)
	check(not body.caster.cast_ready(0.0, 3), "it waits as the fight starts")
	fx.combat.hit(fx.players[0].id, body, BROOM.max_health * 0.5)
	fx.run(body, 1)
	check_equal(body.phases.current, 0, "spring cleaning")
	check(body.caster.cast_ready(0.0, 3), "the Big Sweep is ready as phase 2 starts: its first move")
	fx.free_all()


func test_phase_2_opens_with_a_run_up_and_the_big_sweep() -> void:
	# A room the arena's size (832 × 512, walls round it); the broom in its middle, a wizard near.
	var fx := Fixture.new(root)
	fx.projectiles.set_bounds(Rect2(0.0, 0.0, 832.0, 512.0))
	fx.projectiles.set_walls([
		Rect2(0.0, 0.0, 832.0, 32.0), Rect2(0.0, 480.0, 832.0, 32.0),
		Rect2(0.0, 0.0, 32.0, 512.0), Rect2(800.0, 0.0, 32.0, 512.0)] as Array[Rect2])
	fx.players[0].position = Vector2(470.0, 300.0)
	var body: Actor = fx.enemy(BROOM.scene, BROOM, Vector2(416.0, 200.0))
	fx.run(body, 1)
	fx.combat.hit(fx.players[0].id, body, BROOM.max_health * 0.5)
	var swept_from: Vector2 = Vector2.INF
	var other: bool = false
	for i in int(20.0 / Fixture.STEP):
		body.step(Fixture.STEP)
		body.move(Fixture.STEP)
		fx.combat.step(Fixture.STEP)
		fx.projectiles.step(Fixture.STEP)
		fx.spells.call("step", Fixture.STEP)
		fx.players[0].position = Vector2(470.0, 300.0)
		for at in 3:
			other = other or body.caster.is_winding(at)
		if body.caster.is_winding(3):
			swept_from = body.global_position
			break
	check(swept_from != Vector2.INF, "it winds up the Big Sweep")
	check(not other, "before anything else")
	var brain: AIBrain = Fixture.ai(body).brain
	var sense: CastSense = body.caster.next_cast_sense(3)
	if swept_from != Vector2.INF:
		check(brain.run_here(sense) >= sense.move_reach * 0.8, "from where its line is long: %s of %s px from %s" % [brain.run_here(sense), sense.move_reach, swept_from])
	fx.free_all()


func test_its_aim_locks_and_turns() -> void:
	# Decision 26: phase 1 locks at the wind-up's start, phase 2 for its last 0.25 s.
	var longest: float = 0.0
	for entry: StaffCards in BROOM.staffs:
		longest = maxf(longest, entry.staff.wind_up)
	check(BROOM.profile.aim_lock >= longest, "phase 1 goes where its lane first showed (%s s)" % BROOM.profile.aim_lock)
	check(is_equal_approx(BROOM.phases[0].profile.aim_lock, 0.25), "phase 2 follows, then commits for 0.25 s")
	check(BROOM.profile.turns > 0.0 and BROOM.phases[0].profile.turns > 0.0, "its Sweeps go round the party")


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
	# Its mites (OB13): 4 + 2 a player at once, 2 + 1 a player every 10 s, at most 6 + 2 a player.
	check_equal(phase.adds.size(), 1, "mites pour out")
	var mites: EnemyAdds = phase.adds[0]
	check_equal(mites.enemy, &"crypt_mite", "crypt mites")
	check_equal([mites.burst_for(1), mites.burst_for(4)], [4, 10], "4 + 2 a player at once")
	check_equal([mites.wave_for(1), mites.wave_for(4)], [2, 5], "2 + 1 a player a wave")
	check(is_equal_approx(mites.every, 10.0), "every 10 s")
	check_equal([mites.cap_for(1), mites.cap_for(4)], [6, 12], "at most 6 + 2 a player alive")
	check_equal(mites.at, EnemyAdds.At.RING, "out of the broom, round it")
	for cast: Dictionary in casts:
		check(float(cast.get("wind_up", 0.0)) >= sweep.staff.wind_up, "each winds up on its own: %s" % cast.get("wind_up"))


func test_its_health_by_players() -> void:
	check(is_equal_approx(BROOM.health_per_player, 0.7), "0.7 of its health more for each player after the first")
	check(is_equal_approx(BROOM.health_for(4), BROOM.max_health * 3.1), "four players: 3.1 times")


func test_it_enters_play_and_changes_phase() -> void:
	var fx := Fixture.new(root)
	fx.players[0].position = Vector2(200.0, 0.0)
	var body: Actor = fx.enemy(BROOM.scene, BROOM, Vector2.ZERO)
	check(body.caster != null and body.caster.staff_count == 4, "it holds its four staffs")
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


## The sound sheet (boss plan OB15, "Sound"): each moment's cue or data names its sound id. Silent
## until the audio pass adds the files.
func test_its_sounds() -> void:
	var registry: Node = root.get_node("Registry")
	var sweep: StaffBase = BROOM.staffs[0].staff
	var swat: StaffBase = BROOM.staffs[2].staff
	var big: StaffBase = BROOM.staffs[3].staff
	var double: StaffBase = BROOM.phases[0].staffs[0].staff
	var cues: Dictionary = {}
	for id: StringName in [sweep.wind_cue, big.wind_cue, sweep.move_cue, sweep.wall_cue, swat.cast_cue, BROOM.phases[0].look.cue]:
		var cue: CueBase = registry.get_resource(&"cues", id) as CueBase
		check(cue != null, "its cue %s exists in content/cues" % id)
		if cue != null:
			check_equal(cue.problems(), PackedStringArray(), "%s is sound" % id)
			cues[id] = cue
	check_equal(_held_of(cues.get(sweep.wind_cue)), &"broom_scrape", "the Sweep winds up with a held scrape")
	check_equal(_held_of(cues.get(big.wind_cue)), &"broom_big_scrape", "the Big Sweep with its own, louder one")
	check(float(_part_of(cues.get(big.wind_cue), &"held").get("volume", 0.0)) > float(_part_of(cues.get(sweep.wind_cue), &"held").get("volume", 0.0)), "known without looking: louder")
	for id: StringName in [sweep.wind_cue, big.wind_cue]:
		check(not _part_of(cues.get(id), &"lane").is_empty(), "%s keeps the telegraph's lane" % id)
	for staff: StaffBase in [sweep, big, double]:
		check_equal(staff.move_cue, sweep.move_cue, "%s swishes as it sweeps" % staff.display_name)
		check_equal(staff.wall_cue, sweep.wall_cue, "%s crunches into a wall" % staff.display_name)
	check_equal(double.wind_cue, sweep.wind_cue, "the double Sweep scrapes as the Sweep does")
	check_equal(_held_of(cues.get(sweep.move_cue)), &"broom_swish", "the swish is held while it moves")
	check_equal((cues.get(sweep.wall_cue) as CueBase).sound, &"broom_crunch", "the wall hit's crunch")
	check_equal((cues.get(swat.cast_cue) as CueBase).sound, &"broom_swat", "the swat")
	check_equal((cues.get(BROOM.phases[0].look.cue) as CueBase).sound, &"broom_ignite", "the phase change's ignition")
	check_equal(BROOM.phases[0].look.sound, &"broom_burning", "the bristles burn, held through phase 2")
	check_equal(BROOM.death_sound, &"broom_splinter", "it dies splintering, in place of the boss death's own")
	var layers: Array[StringName] = [&"boss_broom", &"boss_broom_fire"]
	check(BROOM.music != null and BROOM.music.layers == layers, "its music: its track and a fiercer layer")
	check(BROOM.music != null and BROOM.music.stacked, "stacked: phase 2 adds the second over the first")
	check_equal(BROOM.phases[0].intensity, 0, "phase 2 is one step up")
	for prop: StringName in [&"cracked_pillar", &"dust_heap"]:
		check(registry.get_resource(&"props", prop) != null, "the arena's %s is there" % prop)


## Its intro (boss intro BI5): the owner's two lines (2026-11-16), the Spark ramp, a portrait of its
## own in its folder whose eyes frame lights only where its silhouette's eyes are, and its own cues,
## sound only (the world stands still under the overlay, so a flash or a mote would not move).
func test_its_intro() -> void:
	var intro: BossIntro = BROOM.boss_intro
	check(intro != null, "it has an intro")
	if intro == null:
		return
	var registry: Node = root.get_node("Registry")
	check_equal(intro.problems(String(BROOM.id), func(cue: StringName) -> bool: return registry.get_resource(&"cues", cue) != null), PackedStringArray(), "its intro")
	var lines: Array[String] = ["What an awful smell of The Wizard.", "I must clean it up."]
	check_equal(intro.lines, lines, "the owner's two lines")
	check_equal(intro.pages(), 2, "two pages")
	check_equal(intro.accent, &"spark", "the Spark ramp")
	check(intro.portrait != null and intro.portrait.resource_path.begins_with("res://content/bosses/old_broom/"), "its portrait is in its folder")
	for pair: Array in [[intro.dark_cue, &"broom_creak"], [intro.reveal_cue, &"broom_intro_reveal"]]:
		var id: StringName = pair[0]
		check(String(id).begins_with("broom_"), "%s is its own cue" % id)
		var cue: CueBase = registry.get_resource(&"cues", id) as CueBase
		check(cue != null, "its cue %s exists in content/cues" % id)
		if cue != null:
			check_equal(cue.problems(), PackedStringArray(), "%s is sound" % id)
			check_equal(cue.sound, pair[1], "%s plays its sound" % id)
			check(cue.parts.is_empty(), "%s is its sound only" % id)
	if intro.portrait == null:
		return
	var sheet: Image = intro.portrait.get_image()
	var lit: int = 0
	var size: int = BossIntro.FRAME
	for y: int in size:
		for x: int in size:
			if sheet.get_pixel(BossIntro.EYES * size + x, y).a > 0.0:
				lit += 1
				check(sheet.get_pixel(BossIntro.REST * size + x, y).a > 0.0, "an eye lit at (%d, %d) is on the silhouette" % [x, y])
	check(lit > 0, "its eyes light up in the dark")
	check(_height(sheet, BossIntro.MEAN) > _height(sheet, BossIntro.REST), "it rears up for the reveal: the mean pose stands taller than the hunched rest")


## How many rows from the top of `frame` of `sheet` the art starts, from its bottom: its height.
static func _height(sheet: Image, frame: int) -> int:
	var size: int = BossIntro.FRAME
	for y: int in size:
		for x: int in size:
			if sheet.get_pixel(frame * size + x, y).a > 0.0:
				return size - y
	return 0


static func _part_of(cue: Variant, type: StringName) -> Dictionary:
	if cue is CueBase:
		for part: Dictionary in (cue as CueBase).parts:
			if StringName(part.get("part", "flash")) == type:
				return part
	return {}


static func _held_of(cue: Variant) -> StringName:
	return StringName(_part_of(cue, &"held").get("sound", ""))
