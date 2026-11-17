extends "res://tests/support/suite.gd"
## The look of an enemy arriving (enemy arrivals EA2, docs/milestones/enemy-arrivals.md, "The look"):
## a mark grows on the floor in at least 3 frames, the body rises out of it by whole pixels in at
## least 3, and the mark closes in at least 3 as it lands, each stage ending where the next begins
## (docs/STYLE.md, "Smooth"); it is drawn from the body's state alone (a body set mid-arrival by hand,
## as a restored snapshot is, is drawn where it is), cut at its feet while it rises and given its own
## drawing back once it stands; its rise plays the cue `enemy_arrive` once, its sound at most every
## `SOUND_EVERY`; a frame of it allocates nothing; and the game's Feel steps it.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

var _world: Fixture
var _look: ArriveLook
## Every cue the look played, as [at, weighted].
var _cues: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_look = ArriveLook.new()
	root.add_child(_look)
	_cues.clear()
	_look.play_cue = func(at: Vector2, weighted: bool) -> void: _cues.append([at, weighted])


func after_each() -> void:
	_look.free()
	_world.free_all()


## An enemy at `at` (a hurt circle 12 high), arriving `share` of the way through (set by hand).
func _arriving(at: Vector2, share: float) -> Actor:
	var body := Actor.new()
	body.add_child(Hurtbox.new())
	body.arrive(Actor.ARRIVE_SECONDS)
	_world.add(body, at)
	_set_share(body, share)
	return body


func _set_share(body: Actor, share: float) -> void:
	body.arrive_left = Actor.ARRIVE_SECONDS * (1.0 - share)


## The distinct values `value(share)` takes over the shares `from` to `to` in 200 steps, in order.
func _frames(value: Callable, from: float, to: float) -> Array:
	var seen: Array = []
	for n in 201:
		var v: Variant = value.call(lerpf(from, to, float(n) / 200.0))
		if seen.is_empty() or seen[-1] != v:
			seen.append(v)
	return seen


func test_the_mark_grows_in_four_frames_from_a_dot_and_closes_in_three() -> void:
	var grow: Array = _frames(func(share: float) -> int: return ArriveLook.mark_radius(7.0, share), 0.0, ArriveLook.MARK_END - 0.001)
	check_equal(grow, [1, 3, 5, 7], "from a dot to the footprint's width, by whole pixels")
	check_equal(ArriveLook.mark_radius(7.0, ArriveLook.MARK_END), 7, "held as the rise begins: the mark ends where the rise starts")
	var close: Array = _frames(func(share: float) -> int: return ArriveLook.mark_radius(7.0, share), ArriveLook.CLOSE_FROM - 0.01, 0.999)
	check_equal(close, [7, 5, 3, 1], "closing in three frames, down to a dot")
	check_equal(ArriveLook.mark_radius(7.0, 1.0), 0, "none once it stands")
	check(ArriveLook.MARK_FRAMES >= 3 and ArriveLook.CLOSE_FRAMES >= 3, "at least 3 frames a stage")


func test_the_body_rises_by_whole_pixels_from_its_height_to_its_feet() -> void:
	var height: float = 26.0
	check_equal(ArriveLook.rise_shift(height, 0.0), height, "all under the floor through the mark")
	check_equal(ArriveLook.rise_shift(height, ArriveLook.MARK_END), height, "the rise starts where the mark left it")
	var rise: Array = _frames(func(share: float) -> float: return ArriveLook.rise_shift(height, share), ArriveLook.MARK_END, 1.0)
	check(rise.size() >= 5, "at least 5 frames: %d" % rise.size())
	for n in rise.size():
		check_equal(rise[n], roundf(rise[n]), "whole pixels")
		if n > 0:
			check(rise[n] < rise[n - 1] and rise[n - 1] - rise[n] <= 1.0, "up a pixel at a time")
	check_equal(rise[-1], 0.0, "standing at the end")
	check(ArriveLook.rise_shift(4.0, 0.7) <= 4.0, "a small body too")


func test_its_height_counts_its_sprite_its_hurt_shape_and_its_size() -> void:
	var body := Actor.new()
	var hurtbox := Hurtbox.new()
	hurtbox.radius = 12.0
	hurtbox.offset = Vector2(0.0, -14.0)
	body.add_child(hurtbox)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var art := PlaceholderTexture2D.new()
	art.size = Vector2(16.0, 40.0)
	sprite.texture = art
	sprite.position = Vector2(0.0, -14.0)
	body.add_child(sprite)
	_world.add(body, Vector2(100.0, 100.0))
	check_equal(ArriveLook.body_height(body), 34.0 + ArriveLook.HEIGHT_MARGIN, "its sprite's top (14 + 20) and the margin")
	body.set_size(2.0)
	check_equal(ArriveLook.body_height(body), 68.0 + ArriveLook.HEIGHT_MARGIN, "twice as tall at twice its size")


func test_it_is_drawn_from_its_state_alone_and_put_back_once_it_stands() -> void:
	var marking: Actor = _arriving(Vector2(100.0, 100.0), 0.25)
	var rising: Actor = _arriving(Vector2(200.5, 140.0), 0.6)
	var standing := Actor.new()
	_world.add(standing, Vector2(300.0, 100.0))
	_look.step(_world.table, 0.016)
	check_equal(_look.drawn(), 2, "the two arriving bodies are drawn arriving")
	check_equal(marking.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "a body still under the floor is cut")
	check_equal(rising.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "a rising one is cut at its feet")
	check_equal(standing.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "a standing body is left alone")
	check_equal(_look.marks(), 2, "a mark under each")
	var first: Vector3 = _look.mark(0)
	var second: Vector3 = _look.mark(1)
	check_equal(Vector2(first.x, first.y), Vector2(100.0, 100.0), "at its feet")
	check_equal(int(first.z), ArriveLook.mark_radius(marking.wall_radius(), marking.arrive_share()), "as wide as its share says")
	check_equal(Vector2(second.x, second.y), Vector2(201.0, 140.0), "on whole pixels")
	check_equal(marking.global_position, Vector2(100.0, 100.0), "its place untouched")
	check_equal(_cues.size(), 1, "the rising body's cue played once")
	check_equal(_cues[0], [rising.global_position, true], "at its feet, with its sound")
	_look.step(_world.table, 0.016)
	check_equal(_cues.size(), 1, "and not again")
	_set_share(marking, 0.5)
	_look.step(_world.table, 0.2)
	check_equal(_cues.size(), 2, "the other's as it starts to rise")
	check_equal(_cues[1][1], true, "its sound too: more than 0.1 s after the first")
	rising.arrive_left = 0.0
	_look.step(_world.table, 0.016)
	check_equal(_look.drawn(), 1, "a body that stands is no longer drawn arriving")
	check_equal(rising.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "its own drawing back")
	_world.actors.erase(marking)
	marking.free()
	_look.step(_world.table, 0.016)
	check_equal(_look.drawn(), 0, "a body gone is forgotten")
	check_equal(_look.marks(), 0, "no marks")


func test_a_group_rising_together_sounds_once() -> void:
	for n in 4:
		_arriving(Vector2(100.0 + 30.0 * n, 100.0), 0.5)
	_look.step(_world.table, 0.016)
	check_equal(_cues.size(), 4, "a cue for each body's dust")
	var weighted: int = 0
	for cue: Array in _cues:
		weighted += 1 if cue[1] else 0
	check_equal(weighted, 1, "one sound for the four")


func test_a_frame_allocates_nothing() -> void:
	var bodies: Array[Actor] = []
	for n in 12:
		bodies.append(_arriving(Vector2(60.0 + 40.0 * (n % 6), 100.0 + 60.0 * (n / 6)), float(n) / 12.0))
	_look.step(_world.table, 0.016)
	_look.step(_world.table, 0.016)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		for body in bodies:
			_set_share(body, fmod(body.arrive_share() + 0.005, 0.99))
		_look.step(_world.table, 0.016)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of twelve bodies arriving make no object")


## The game's Feel holds the look and steps it, and the cue it plays is in the registry, sound named.
func test_feel_steps_it_and_its_cue_is_there() -> void:
	var feel := root.get_node_or_null("Feel")
	check(feel != null, "the game's Feel")
	if feel == null:
		return
	var look := feel.get("_arrive_look") as ArriveLook
	check(look != null and look.get_parent() == feel, "Feel holds an arrival look")
	check(look.play_cue.is_valid(), "and plays its cue")
	var cue := root.get_node("Registry").call("get_resource", &"cues", ArriveLook.CUE) as CueBase
	check(cue != null, "the cue enemy_arrive is in the registry")
	if cue != null:
		check_equal(cue.sound, &"enemy_arrive", "its soft sound")
		check_equal(cue.problems(), PackedStringArray(), "no problems")
