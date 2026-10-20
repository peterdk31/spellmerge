extends "res://tests/support/suite.gd"
## The ember imp's art is wired so the game can use it (content/enemies/ember_imp): every strip
## is a row of whole 32 px frames that the sprite's `hframes` matches, and the scene has the
## parts the AI drives. How the imp looks is free to change; these checks do not look at it.

const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")
const FRAME: int = 32

var imp: Node


func before_each() -> void:
	imp = own(ImpData.scene.instantiate()) as Node


func test_idle_strip_matches_the_sprite_frames() -> void:
	var sprite: Sprite2D = imp.get_node("Sprite")
	check_equal(sprite.texture.get_height(), FRAME, "idle strip height")
	check_equal(sprite.texture.get_width(), FRAME * sprite.hframes, "idle strip width is hframes whole frames")
	check(sprite.hframes >= 2, "the idle strip has at least two frames to animate")


func test_windup_strip_is_whole_frames_with_at_least_two() -> void:
	var texture: Texture2D = imp.get("windup_texture")
	check(texture != null, "the imp has a windup strip")
	if texture != null:
		check_equal(texture.get_height(), FRAME, "windup strip height")
		check(texture.get_width() % FRAME == 0 and texture.get_width() / FRAME >= 2, "the windup strip has two or more whole frames")


func test_hurt_pose_is_one_frame() -> void:
	var texture: Texture2D = imp.get("hurt_texture")
	check(texture != null, "the imp has a hurt pose")
	if texture != null:
		check_equal(texture.get_size(), Vector2(FRAME, FRAME), "hurt pose size")


func test_poses_are_different_art() -> void:
	var sprite: Sprite2D = imp.get_node("Sprite")
	check(imp.get("windup_texture") != sprite.texture, "the windup is not the idle strip")
	check(imp.get("hurt_texture") != sprite.texture, "the hurt pose is not the idle strip")


func test_scene_has_the_telegraph_parts() -> void:
	check(imp.get_node_or_null("Telegraph") is Line2D, "a Telegraph line")
	check(imp.get_node_or_null("Telegraph/Lane") is Polygon2D, "a Lane under it")
	check(imp.get_node_or_null("Telegraph/Tip") is Polygon2D, "a Tip under it")
	check(imp.get_node_or_null("AnimationPlayer") is AnimationPlayer, "an AnimationPlayer for the idle")


func test_telegraph_is_hidden_until_the_windup() -> void:
	check(not (imp.get_node("Telegraph") as Line2D).visible, "the telegraph starts hidden")


func test_sprite_is_not_filtered() -> void:
	check_equal((imp.get_node("Sprite") as Sprite2D).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "pixel art needs nearest filtering")
