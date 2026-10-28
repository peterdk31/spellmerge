extends "res://tests/support/suite.gd"
## The imp's telegraph and poses (gameplay/ai, content/enemies/ember_imp): the warning comes
## before the shot, the aim is locked, the line, lane and arrowhead show where the shot goes
## and how close it is, and the windup and hurt poses never change when damage lands.

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const AiScript := preload("res://gameplay/ai/ai.gd")
const EventsScript := preload("res://core/events/events.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root, 1)


func after_each() -> void:
	fx.free_all()


func test_windup_starts_in_range_without_a_shot() -> void:
	var imp: AiScript = fx.imp_facing_player()
	check(not imp.is_telegraphing() and imp.telegraph_progress() == 0.0, "not telegraphing before it sees a player")
	imp.step(Fixture.STEP)
	check(imp.is_telegraphing(), "in range, the windup starts")
	check_equal(fx.projectiles.get_count(), 0, "no shot at the start of the windup")


func test_shot_leaves_exactly_when_the_telegraph_ends() -> void:
	var imp: AiScript = fx.imp_facing_player()
	imp.step(Fixture.STEP)
	var steps: int = int(imp.windup_time / Fixture.STEP)
	fx.run(imp, steps - 2)
	check(imp.is_telegraphing() and fx.projectiles.get_count() == 0, "still telegraphing, still no shot, just before the end")
	check(imp.telegraph_progress() > 0.8 and imp.telegraph_progress() < 1.0, "progress is near the end")
	fx.run(imp, 2)
	check(not imp.is_telegraphing(), "the telegraph ended")
	check_equal(fx.projectiles.get_count(), 1, "exactly one shot left")


func test_imp_stands_still_and_keeps_its_aim() -> void:
	var imp: AiScript = fx.imp_facing_player(60.0)
	imp.step(Fixture.STEP)
	check(imp.aim.is_equal_approx(Vector2.RIGHT), "the aim points at the player")
	var at: Vector2 = imp.position
	fx.players[0].position = Vector2(0.0, 60.0)
	fx.run(imp, 4)
	check(imp.position == at and imp.velocity == Vector2.ZERO, "the imp stands still")
	check(imp.aim.is_equal_approx(Vector2.RIGHT), "the aim stays on where the player was")


func test_a_wizard_who_steps_aside_is_not_hit() -> void:
	var imp: AiScript = fx.imp_facing_player(60.0)
	imp.step(Fixture.STEP)
	fx.players[0].position = Vector2(60.0, 40.0)
	fx.run(imp, int(imp.windup_time / Fixture.STEP) + 20)
	check_equal(fx.players[0].health, PlayerScript.MAX_HEALTH, "the shot missed")


func test_a_wizard_who_stays_is_hit() -> void:
	var imp: AiScript = fx.imp_facing_player(60.0)
	imp.step(Fixture.STEP)
	fx.run(imp, int(imp.windup_time / Fixture.STEP) + 20)
	check(fx.players[0].health < PlayerScript.MAX_HEALTH, "the shot hit")


func test_line_is_hidden_outside_the_windup() -> void:
	var imp: AiScript = fx.imp_facing_player()
	var line: Sprite2D = imp.get_node("Telegraph")
	check(not line.visible, "hidden before the windup")
	fx.run(imp, int(imp.windup_time / Fixture.STEP) + 2)
	check(not line.visible, "hidden after the shot")
	check(imp.get_node("Sprite").modulate == Color.WHITE, "the sprite is white again after the shot")


func test_line_is_as_long_as_the_shot_flies() -> void:
	var imp: AiScript = fx.imp_facing_player()
	imp.step(Fixture.STEP)
	check(is_equal_approx(imp.telegraph_reach(), imp.attack_speed * imp.attack_lifetime), "the far end is the real reach")
	var material: ShaderMaterial = (imp.get_node("Telegraph") as Sprite2D).material as ShaderMaterial
	check(is_equal_approx(material.get_shader_parameter(&"beam_length"), imp.attack_speed * imp.attack_lifetime - AiScript.TELEGRAPH_START), "the shader draws it that long")


func test_line_turns_toward_the_locked_aim() -> void:
	var imp: AiScript = fx.imp_facing_player()
	imp.step(Fixture.STEP)
	var line: Sprite2D = imp.get_node("Telegraph")
	check(line.visible and is_equal_approx(line.rotation, imp.aim.angle()), "the line shows, turned to the aim")


func test_telegraph_grows_brighter_and_bigger() -> void:
	var imp: AiScript = fx.imp_facing_player()
	imp.step(Fixture.STEP)
	var line: Sprite2D = imp.get_node("Telegraph")
	var material: ShaderMaterial = line.material as ShaderMaterial
	var early: float = material.get_shader_parameter(&"telegraph_progress")
	fx.run(imp, int(imp.windup_time / Fixture.STEP) - 4)
	check(float(material.get_shader_parameter(&"telegraph_progress")) > early + 0.5, "the shader is told the shot is near: dashes on, arrowhead bigger, brighter")
	check_equal(material.get_shader_parameter(&"beam_mode"), 3, "drawn by the shot shader's telegraph mode")
	var other: AiScript = fx.imp(Vector2(0.0, 400.0))
	check(other.get_node("Telegraph").material != line.material, "each enemy has its own telegraph material")


func test_lane_and_arrowhead_follow_the_reach() -> void:
	var imp: AiScript = fx.imp_facing_player()
	var line: Sprite2D = imp.get_node("Telegraph")
	var material: ShaderMaterial = line.material as ShaderMaterial
	check(is_equal_approx(line.offset.x + line.region_rect.size.x, imp.attack_speed * imp.attack_lifetime), "the lane and its arrowhead end where the shot ends")
	check(float(material.get_shader_parameter(&"telegraph_lane")) >= imp.attack_radius, "the lane is at least as wide as the shot")


func test_windup_pose_has_two_frames_and_idle_returns() -> void:
	var imp: AiScript = fx.imp_facing_player()
	var sprite: Sprite2D = imp.get_node("Sprite")
	var idle_texture: Texture2D = sprite.texture
	check(imp.windup_texture != null and imp.windup_texture != idle_texture, "the windup is its own art")
	fx.run(imp, 1)
	check(sprite.texture == imp.windup_texture and sprite.hframes == 2, "the windup pose shows two frames")
	fx.run(imp, int(imp.windup_time / Fixture.STEP) + 2)
	check(sprite.texture == idle_texture, "after the shot the idle strip is back")


func test_windup_frames_flip_faster_toward_the_shot() -> void:
	var imp: AiScript = fx.imp_facing_player()
	var sprite: Sprite2D = imp.get_node("Sprite")
	fx.run(imp, 1)
	var flips: Array[int] = []
	var last: int = sprite.frame
	for i in int(imp.windup_time / Fixture.STEP) - 1:
		fx.run(imp, 1)
		if sprite.frame != last:
			flips.append(i)
			last = sprite.frame
	check(flips.size() >= 3, "the frame flips several times (%d)" % flips.size())
	if flips.size() >= 3:
		check(flips[flips.size() - 1] - flips[flips.size() - 2] < flips[0] + 1, "the flips speed up")
	check_equal(sprite.frame, sprite.hframes - 1, "the bright frame is held for the last part")


func test_sprite_is_brighter_in_the_last_part_of_the_windup() -> void:
	var imp: AiScript = fx.imp_facing_player()
	var sprite: Sprite2D = imp.get_node("Sprite")
	fx.run(imp, 1)
	var early: Color = sprite.modulate
	fx.run(imp, int(imp.windup_time / Fixture.STEP) - 2)
	check(sprite.modulate != early and sprite.modulate.v > early.v, "the sprite is brighter near the shot")


func test_hit_on_another_enemy_does_not_hurt_this_one() -> void:
	var imp: AiScript = fx.imp_facing_player()
	var other: AiScript = fx.imp(Vector2(500.0, 0.0))
	fx.run(imp, 3)
	fx.bus.damage_dealt.emit(0, other, 1, Vector2.ZERO)
	check(not imp.is_hurt(), "only a hit on this imp shows its hurt pose")


func test_hit_shows_the_hurt_pose_at_once_and_it_ends() -> void:
	var imp: AiScript = fx.imp_facing_player()
	var sprite: Sprite2D = imp.get_node("Sprite")
	fx.run(imp, 3)
	fx.bus.damage_dealt.emit(0, imp, 1, Vector2.ZERO)
	check(imp.is_hurt() and sprite.texture == imp.hurt_texture and sprite.hframes == 1, "the hurt pose shows at once")
	fx.run(imp, int(AiScript.HURT_TIME / Fixture.STEP) + 1)
	check(not imp.is_hurt() and sprite.texture == imp.windup_texture, "the windup pose comes back")


func test_hit_does_not_cancel_the_windup_or_delay_the_shot() -> void:
	var imp: AiScript = fx.imp_facing_player()
	fx.run(imp, 3)
	fx.bus.damage_dealt.emit(0, imp, 1, Vector2.ZERO)
	fx.run(imp, 1)
	check(imp.state == AiScript.State.WINDUP and imp.get_node("Telegraph").visible, "still winding up, line still shown")
	fx.run(imp, int(imp.windup_time / Fixture.STEP) + 2)
	check_equal(fx.projectiles.get_count_for(EventsScript.NO_PLAYER), 1, "the shot still came on time")


func test_hurt_pose_also_shows_while_recovering() -> void:
	var imp: AiScript = fx.imp_facing_player()
	var sprite: Sprite2D = imp.get_node("Sprite")
	fx.run(imp, int(imp.windup_time / Fixture.STEP) + 2)
	fx.bus.damage_dealt.emit(0, imp, 1, Vector2.ZERO)
	fx.run(imp, 1)
	check(sprite.texture == imp.hurt_texture, "a hit while recovering shows the hurt pose")
	fx.run(imp, int(AiScript.HURT_TIME / Fixture.STEP) + 1)
	check(sprite.hframes == 2 and sprite.texture != imp.hurt_texture, "afterwards the idle strip is back")
