extends "res://tests/support/suite.gd"
## core/audio's ears (connected biomes CB12, decision 29; core/audio/ears.gd): a world sound is heard
## only where its caller says (Feel's rooms; here a test's rule), a one-shot or an accent elsewhere
## is not played and a held sound there is silent until it is heard; while the screen is split a
## sound is put where the root camera draws the pixel its own view shows it at, the view whose
## wizards stand nearest it. An Audio of the test's own on a registry of the test's own.
const AudioScript := preload("res://core/audio/audio.gd")
const EarsScript := preload("res://core/audio/ears.gd")
const HeldScript := preload("res://core/audio/held.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const SoundBook := preload("res://tests/core/audio/sound_book.gd")

var book: SoundBook
var audio: AudioScript


func before_each() -> void:
	book = own(SoundBook.new()) as SoundBook
	book.know([&"knock", &"hum"])
	audio = AudioScript.new()
	audio.registry = book
	root.add_child(audio)


func after_each() -> void:
	audio.clear_world()
	audio.free()


## Heard only west of x = 100.
static func _west(at: Vector2) -> bool:
	return at.x < 100.0


func test_with_no_rule_every_sound_is_heard_where_it_is() -> void:
	var ears := EarsScript.new()
	check(ears.hears(Vector2(5000, 5000)), "no rule: heard")
	check_equal(ears.place(Vector2(30, 40)), Vector2(30, 40), "one picture: where it is")


func test_a_one_shot_where_nobody_hears_is_not_played() -> void:
	audio.ears.heard = _west
	check(audio.play(&"knock", Vector2(40, 0)) >= 0, "heard: it plays")
	check_equal(audio.play(&"knock", Vector2(400, 0)), -1, "not heard: it does not")
	check(audio.play(&"knock") >= 0, "a sound of no place is heard")


func test_a_held_sound_is_silent_while_nobody_hears_it() -> void:
	audio.ears.heard = _west
	var body := Node2D.new()
	root.add_child(own(body))
	body.global_position = Vector2(400, 0)
	var handle: int = audio.hold(&"hum", body, Vector2.INF, INF)
	check(audio.is_held(handle), "held where nobody hears it: it keeps its slot")
	check_equal(audio.held.gain_of(handle), 0.0, "and is silent")
	body.global_position = Vector2(40, 0)
	var gains: Array[float] = []
	for i in 10:
		audio.step_world(HeldScript.FADE / 4.0)
		gains.append(audio.held.gain_of(handle))
	check(gains[0] > 0.0 and gains[0] < 1.0, "heard again, it comes up over its fade: %s" % [gains])
	check_equal(gains[gains.size() - 1], 1.0, "then is heard whole")
	check_equal(audio.held.held_at(handle), Vector2(40, 0), "where its body is")


func test_while_split_a_sound_is_heard_where_its_view_shows_it() -> void:
	var views := ScreenViewsScript.new()
	views.screen = Vector2(640, 360)
	views.count = 2
	# Two views, each showing its wizards at its anchor: one round (0, 0), one round (2000, 0).
	views.to_screen[0] = Transform2D(0.0, Vector2(160, 180))
	views.anchor[0] = Vector2(160, 180)
	views.to_screen[1] = Transform2D(0.0, Vector2(480 - 2000, 180))
	views.anchor[1] = Vector2(480, 180)
	# The root camera's picture: (1000, 0) in the screen's middle.
	var root_canvas := Transform2D(0.0, Vector2(320 - 1000, 180))
	var ears := EarsScript.new()
	ears.use(views, root_canvas)
	check_equal(ears.views(), 2, "it hears from both views")
	check_equal(ears.place(Vector2(10, 0)), Vector2(1000 - 160 + 10, 0), "a sound by the first view's wizards is put where its view draws it, left of the middle")
	check_equal(ears.place(Vector2(2010, 0)), Vector2(1000 + 160 + 10, 0), "one by the second's, right of the middle")
	ears.clear_views()
	check_equal(ears.place(Vector2(2010, 0)), Vector2(2010, 0), "one picture again: where it is")


func test_an_accent_where_nobody_hears_is_not_played() -> void:
	audio.ears.heard = _west
	check_equal(audio.play_accent(&"knock", Vector2(400, 0), 0.0, 1.0), -1, "not heard: no accent")
	check(audio.play_accent(&"knock", Vector2(40, 0), 0.0, 1.0) >= 0, "heard: it plays")


func test_refresh_hears_from_the_views_published_on_a_viewport() -> void:
	var views := ScreenViewsScript.new()
	views.count = 2
	views.to_screen[0] = Transform2D.IDENTITY
	views.to_screen[1] = Transform2D(0.0, Vector2(-1000, 0))
	var viewport: Viewport = root.get_viewport()
	ScreenViewsScript.publish(viewport, views)
	var ears := EarsScript.new()
	ears.refresh(viewport)
	check_equal(ears.views(), 2, "published views are heard from")
	ScreenViewsScript.withdraw(viewport)
	ears.refresh(viewport)
	check_equal(ears.views(), 0, "withdrawn: one picture")
