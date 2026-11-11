extends "res://tests/support/suite.gd"
## The imp's telegraph and poses (gameplay/ai's CreatureLook, reading its AIController;
## content/enemies/ember_imp, the Cinder Rod): the warning comes before the shot for as long as
## its staff winds up (docs/milestones/cast-timing.md), the aim follows the target, the line, lane and arrowhead show where the shot goes and how close it is, and the
## windup and hurt poses never change when damage lands. The strays' faces carry their mood
## (living staffs H5), so no stray has pose strips; the poses are tested on strips made in code.
## Enemies telegraph, allies don't (owner, 2026-11-01): the same AI on the players' team casts the
## step its staff is ready, with no telegraph and no furious face.

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const EventsScript := preload("res://core/events/events.gd")

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root, 1)


func after_each() -> void:
	fx.free_all()


## A plain strip of `frames` 32 px frames.
func _strip(frames: int) -> Texture2D:
	return ImageTexture.create_from_image(Image.create(32 * frames, 32, false, Image.FORMAT_RGBA8))


## An imp facing the player, its look given a two-frame windup strip and a one-frame hurt pose.
func _posed_imp() -> Actor:
	var imp: Actor = fx.imp_facing_player()
	Fixture.look(imp).windup_texture = _strip(2)
	Fixture.look(imp).hurt_texture = _strip(1)
	return imp


func test_windup_starts_in_range_without_a_shot() -> void:
	var imp: Actor = fx.imp_facing_player()
	check(not Fixture.ai(imp).is_telegraphing() and Fixture.ai(imp).telegraph_progress() == 0.0, "not telegraphing before it sees a player")
	imp.step(Fixture.STEP)
	check(Fixture.ai(imp).is_telegraphing(), "in range, the windup starts")
	check_equal(fx.projectiles.get_count(), 0, "no shot at the start of the windup")


func test_shot_leaves_exactly_when_the_telegraph_ends() -> void:
	var imp: Actor = fx.imp_facing_player()
	imp.step(Fixture.STEP)
	var steps: int = int(Fixture.ai(imp).windup_time / Fixture.STEP)
	fx.run(imp, steps - 2)
	check(Fixture.ai(imp).is_telegraphing() and fx.projectiles.get_count() == 0, "still telegraphing, still no shot, just before the end")
	check(Fixture.ai(imp).telegraph_progress() > 0.7 and Fixture.ai(imp).telegraph_progress() < 1.0, "progress is near the end")
	var guard: int = 0
	while Fixture.ai(imp).is_telegraphing() and guard < 10:
		check_equal(fx.projectiles.get_count(), 0, "no shot while it telegraphs")
		fx.run(imp, 1)
		guard += 1
	check(not Fixture.ai(imp).is_telegraphing(), "the telegraph ended")
	check_equal(fx.projectiles.get_count(), 1, "exactly one shot left as it ended")


func test_imp_stands_still_and_its_aim_follows() -> void:
	# docs/milestones/cast-timing.md (owner, 2026-11-06): the AI aims through its wind-up, as a
	# player's aim follows the stick.
	var imp: Actor = fx.imp_facing_player(60.0)
	imp.step(Fixture.STEP)
	check(imp.aim.is_equal_approx(Vector2.RIGHT), "the aim points at the player")
	var at: Vector2 = imp.position
	fx.players[0].position = Vector2(0.0, 60.0)
	fx.run(imp, 4)
	check(imp.position == at and imp.velocity == Vector2.ZERO, "the imp stands still")
	check(imp.aim.dot(Vector2.DOWN) > 0.9, "the aim follows the player: %s" % imp.aim)


func test_a_wizard_who_steps_aside_once_the_shot_left_is_not_hit() -> void:
	var imp: Actor = fx.imp_facing_player(60.0)
	imp.step(Fixture.STEP)
	while Fixture.ai(imp).is_telegraphing():
		fx.run(imp, 1)
	fx.players[0].position = Vector2(60.0, 40.0)
	fx.run(imp, 20)
	check_equal(fx.players[0].health.health, fx.players[0].health.max_health, "the shot missed")


func test_a_wizard_who_stays_is_hit() -> void:
	var imp: Actor = fx.imp_facing_player(60.0)
	imp.step(Fixture.STEP)
	fx.run(imp, int(Fixture.ai(imp).windup_time / Fixture.STEP) + 20)
	check(fx.players[0].health.health < fx.players[0].health.max_health, "the shot hit")


## The lane of an imp (Feel's `lane` cue part, the card's `wind_cue`; docs/milestones/cast-timing.md,
## T6b), or null while it shows none.
func _lane(imp: Actor) -> Sprite2D:
	return fx.lanes().call("sprite_of", imp.id) as Sprite2D


func test_line_is_hidden_outside_the_windup() -> void:
	var imp: Actor = fx.imp_facing_player()
	fx.with_feel()
	check(_lane(imp) == null, "no lane before the windup")
	fx.run(imp, 1)
	check(_lane(imp) != null and _lane(imp).visible, "a lane while it winds up")
	while Fixture.ai(imp).is_telegraphing():
		fx.run(imp, 1)
	fx.run(imp, 1)
	check(_lane(imp) == null, "gone once the shot left")
	check(imp.get_node("Sprite").modulate == Color.WHITE, "the sprite is white again after the shot")


func test_line_is_as_long_as_the_shot_flies() -> void:
	var imp: Actor = fx.imp_facing_player()
	fx.with_feel()
	fx.run(imp, 1)
	var bolt: FormBase = fx.registry.call("get_resource", &"spells", &"bolt") as FormBase
	var reach: float = bolt.speed * bolt.lifetime
	check(is_equal_approx(float(fx.lanes().call("reach_of", imp.id)), reach), "the far end is the real reach of its bolt (%.1f)" % float(fx.lanes().call("reach_of", imp.id)))
	var line: Sprite2D = _lane(imp)
	check(line.offset.x + line.region_rect.size.x == reach, "the lane and its arrowhead end where the bolt ends")
	var material: ShaderMaterial = line.material as ShaderMaterial
	check(float(material.get_shader_parameter(&"telegraph_lane")) >= bolt.radius, "the lane is at least as wide as the bolt")


func test_line_follows_the_aim() -> void:
	var imp: Actor = fx.imp_facing_player(60.0)
	fx.with_feel()
	fx.run(imp, 1)
	check(is_equal_approx(_lane(imp).rotation, imp.aim.angle()), "the lane shows, turned to the aim")
	fx.players[0].position = Vector2(0.0, 60.0)
	fx.run(imp, 3)
	check(is_equal_approx(_lane(imp).rotation, imp.aim.angle()) and imp.aim.dot(Vector2.DOWN) > 0.9, "and turns as the aim follows the player")


func test_its_gathering_ring_stays_on_the_staff_tip_as_the_aim_turns() -> void:
	# Regression: the wind cue's ring sat where the staff tip was at the press, moved only with the
	# body, so as the aim followed the player it stayed behind while the tip and the lane turned.
	var imp: Actor = fx.imp_facing_player(60.0)
	# A staff with a length, so its tip swings round the hand as the aim turns.
	imp.staff_reach = 10.0
	var feel: Node = fx.with_feel()
	fx.run(imp, 1)
	var ring: Dictionary = feel.call("flash_info", &"ring_in")
	check(not ring.is_empty(), "a ring gathers as it winds up")
	var pressed: Vector2 = fx.spells.call("aim_origin_of", imp.id)
	fx.players[0].position = Vector2(0.0, 60.0)
	fx.run(imp, 3)
	var tip: Vector2 = fx.spells.call("aim_origin_of", imp.id)
	ring = feel.call("flash_info", &"ring_in")
	check(not tip.is_equal_approx(pressed), "the staff tip moved as the aim turned: %s to %s" % [pressed, tip])
	check(not ring.is_empty() and (ring["at"] as Vector2).distance_to(tip) <= 1.0, "the ring is on the tip as it is now: %s, the tip %s" % [ring.get("at"), tip])


func test_telegraph_grows_brighter_and_bigger() -> void:
	var imp: Actor = fx.imp_facing_player()
	fx.with_feel()
	fx.run(imp, 1)
	var material: ShaderMaterial = _lane(imp).material as ShaderMaterial
	var early: float = material.get_shader_parameter(&"telegraph_progress")
	fx.run(imp, int(Fixture.ai(imp).windup_time / Fixture.STEP) - 4)
	check(float(material.get_shader_parameter(&"telegraph_progress")) > early + 0.5, "the shader is told the shot is near: dashes on, arrowhead bigger, brighter")
	check_equal(material.shader.resource_path, "res://gameplay/feel/telegraph.gdshader", "drawn by the telegraph's own shader, not the shot shader (its cost in a crowd)")
	var base: Color = material.get_shader_parameter(&"ramp_base")
	check(base.r > base.b, "in the cast's colour: the imp's fire bolt is warm (%s)" % base)


func test_windup_pose_has_two_frames_and_idle_returns() -> void:
	var imp: Actor = _posed_imp()
	var sprite: Sprite2D = imp.get_node("Sprite")
	var idle_texture: Texture2D = sprite.texture
	check(Fixture.look(imp).windup_texture != null and Fixture.look(imp).windup_texture != idle_texture, "the windup is its own art")
	fx.run(imp, 1)
	check(sprite.texture == Fixture.look(imp).windup_texture and sprite.hframes == 2, "the windup pose shows two frames")
	fx.run(imp, int(Fixture.ai(imp).windup_time / Fixture.STEP) + 2)
	check(sprite.texture == idle_texture, "after the shot the idle strip is back")


func test_windup_frames_flip_faster_toward_the_shot() -> void:
	var imp: Actor = _posed_imp()
	var sprite: Sprite2D = imp.get_node("Sprite")
	fx.run(imp, 1)
	var flips: Array[int] = []
	var last: int = sprite.frame
	for i in int(Fixture.ai(imp).windup_time / Fixture.STEP) - 1:
		fx.run(imp, 1)
		if sprite.frame != last:
			flips.append(i)
			last = sprite.frame
	check(flips.size() >= 3, "the frame flips several times (%d)" % flips.size())
	if flips.size() >= 3:
		check(flips[flips.size() - 1] - flips[flips.size() - 2] < flips[0] + 1, "the flips speed up")
	check_equal(sprite.frame, sprite.hframes - 1, "the bright frame is held for the last part")


func test_sprite_is_brighter_in_the_last_part_of_the_windup() -> void:
	var imp: Actor = fx.imp_facing_player()
	var sprite: Sprite2D = imp.get_node("Sprite")
	fx.run(imp, 1)
	var early: Color = sprite.modulate
	fx.run(imp, int(Fixture.ai(imp).windup_time / Fixture.STEP) - 2)
	check(sprite.modulate != early and sprite.modulate.v > early.v, "the sprite is brighter near the shot")


func test_hit_on_another_enemy_does_not_hurt_this_one() -> void:
	var imp: Actor = fx.imp_facing_player()
	var other: Actor = fx.imp(Vector2(500.0, 0.0))
	fx.run(imp, 3)
	other.damaged.emit(0, 1, &"")
	check(not Fixture.look(imp).is_hurt(), "only a hit on this imp shows its hurt pose")


func test_hit_shows_the_hurt_pose_at_once_and_it_ends() -> void:
	var imp: Actor = _posed_imp()
	var sprite: Sprite2D = imp.get_node("Sprite")
	fx.run(imp, 3)
	imp.damaged.emit(0, 1, &"")
	check(Fixture.look(imp).is_hurt() and sprite.texture == Fixture.look(imp).hurt_texture and sprite.hframes == 1, "the hurt pose shows at once")
	fx.run(imp, int(CreatureLook.HURT_TIME / Fixture.STEP) + 1)
	check(not Fixture.look(imp).is_hurt() and sprite.texture == Fixture.look(imp).windup_texture, "the windup pose comes back")


func test_hit_does_not_cancel_the_windup_or_delay_the_shot() -> void:
	var imp: Actor = fx.imp_facing_player()
	fx.run(imp, 3)
	imp.damaged.emit(0, 1, &"")
	fx.run(imp, 1)
	check(Fixture.ai(imp).is_telegraphing(), "still winding up, still telegraphing")
	# Four frames have run; the shot leaves the frame the windup ends, before it can reach anyone.
	fx.run(imp, int(Fixture.ai(imp).windup_time / Fixture.STEP) - 3)
	check_equal(fx.projectiles.get_count(), 1, "the shot still came on time")


func test_hurt_pose_also_shows_while_recovering() -> void:
	var imp: Actor = _posed_imp()
	var sprite: Sprite2D = imp.get_node("Sprite")
	var idle_texture: Texture2D = sprite.texture
	fx.run(imp, int(Fixture.ai(imp).windup_time / Fixture.STEP) + 2)
	imp.damaged.emit(0, 1, &"")
	fx.run(imp, 1)
	check(sprite.texture == Fixture.look(imp).hurt_texture, "a hit while recovering shows the hurt pose")
	fx.run(imp, int(CreatureLook.HURT_TIME / Fixture.STEP) + 1)
	check(sprite.texture == idle_texture, "afterwards the idle body is back")


# --- Enemies telegraph, allies don't (owner, 2026-11-01) --------------------------------------


## An imp body holding `rows` (big pools) at `at`, its own AI (exact profile) playing for `team`;
## its casts counted in `casts`.
func _imp_of(team: int, rows: Array, at: Vector2, casts: PackedInt32Array) -> Actor:
	var body: Actor = Fixture.ImpData.scene.instantiate() as Actor
	Fixture.ai(body).team = team
	body.data = Fixture.staffed(rows)
	body.position = at
	fx.wire(body)
	root.add_child(body)
	body.ticking = false
	fx.enemies.append(body)
	body.caster.cast_done.connect(func(staff: int, _o: Vector2, _d: Vector2) -> void: casts[staff] += 1)
	return body


func _face(body: Actor) -> Face:
	for child in body.get_children():
		if child is Face:
			return child as Face
	return null


## Cast timing (docs/milestones/cast-timing.md): a cast winds up as long as its staff says, whoever
## holds it; only an enemy shows it (the telegraph, the furious face).
func test_an_ally_casts_the_step_its_staff_is_ready_with_no_warning() -> void:
	var casts := PackedInt32Array([0, 0, 0, 0])
	fx.with_feel()
	var foe: Actor = fx.imp(Vector2(80.0, 0.0), Fixture.staffed([]))
	var ally: Actor = _imp_of(Fixture.ActorsScript.TEAM_WIZARDS, [["fire", "bolt"]], Vector2.ZERO, casts)
	var mind: AIController = Fixture.ai(ally)
	var face: Face = _face(ally)
	check(face != null, "the imp has a face")
	check_equal(mind.brain.windup_for(0), Fixture.WIND_UP, "an ally's cast winds up as its staff says")
	fx.run(ally, 1)
	check(mind.target == foe, "it fights the enemy")
	check_equal(casts[0], 1, "and starts its cast the first step its staff is ready")
	var warned: bool = false
	var furious: bool = false
	for i in 30:
		fx.run(ally, 1)
		warned = warned or mind.is_telegraphing() or fx.lanes().call("sprite_of", ally.id) != null
		furious = furious or (face != null and face.mood() == Face.Mood.FURIOUS)
	check(casts[0] > 1, "it goes on casting: %s" % casts)
	check(not warned, "never a telegraph")
	check(not furious, "never a furious face")


func test_the_same_ai_on_the_enemies_team_telegraphs() -> void:
	var casts := PackedInt32Array([0, 0, 0, 0])
	fx.with_feel()
	fx.players[0].position = Vector2(80.0, 0.0)
	var enemy: Actor = _imp_of(Fixture.ActorsScript.TEAM_ENEMIES, [["fire", "bolt"]], Vector2.ZERO, casts)
	var mind: AIController = Fixture.ai(enemy)
	check_equal(mind.brain.windup_for(0), Fixture.WIND_UP, "an enemy's cast winds up as its staff says")
	fx.run(enemy, 1)
	check(mind.is_telegraphing() and fx.lanes().call("sprite_of", enemy.id) != null, "it telegraphs first, its lane shown")
	check(_face(enemy).mood() == Face.Mood.FURIOUS, "with a furious face")
	check_equal(fx.projectiles.get_count(), 0, "and nothing has left yet")
	fx.run(enemy, ceili(mind.windup_time / Fixture.STEP) + 1)
	check(fx.projectiles.get_count() > 0, "then its cast leaves")
