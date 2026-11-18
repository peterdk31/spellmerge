extends "res://tests/support/suite.gd"
## A spawn style's mark as an art strip (spawn styles AS4, docs/milestones/spawn-styles.md): the look
## lays a strip's frame instead of the ring, its frames in order over the mark stage, the last held,
## then the close's frames backwards to the first (`SpawnStyle.strip_frame`, docs/STYLE.md, "Smooth");
## drawn at whole pixels centred on the body's feet at a whole-number scale of the footprint; from the
## body's state alone (a fresh look draws the same frame); and a frame of it allocates nothing. The
## frames' numbers and the checks are tests/core/test_spawn_style.gd's.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const MarkStrips := preload("res://tests/support/mark_strips.gd")

var _world: Fixture
var _look: SpawnLook
var _strip: ImageTexture = MarkStrips.strip(16, 4)
var _style: SpawnStyle = MarkStrips.style(&"rooted", _strip)


func before_each() -> void:
	_world = Fixture.new(root)
	_look = _new_look()


func after_each() -> void:
	_look.free()
	_world.free_all()


## A look whose lookup finds the strip's style (and `rise`'s numbers for any other id).
func _new_look() -> SpawnLook:
	var look := SpawnLook.new()
	root.add_child(look)
	var style: SpawnStyle = _style
	look.style_of = func(id: StringName) -> SpawnStyle: return style if id == style.id else null
	return look


## An enemy at `at` (a hurt circle) spawning `share` of the way through in `style_id`.
func _spawning(at: Vector2, share: float, style_id: StringName = &"rooted") -> Actor:
	var body := Actor.new()
	body.add_child(Hurtbox.new())
	body.spawn(_style.seconds, style_id)
	_world.add(body, at)
	_set_share(body, share)
	return body


func _set_share(body: Actor, share: float) -> void:
	body.spawn_left = _style.seconds * (1.0 - share)


func _frame(look: SpawnLook) -> void:
	look.step(_world.table, 0.016)
	look.cut()


func test_its_frames_play_hold_and_close_backwards() -> void:
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.0)
	var seen: Array = []
	for n in 400:
		_set_share(body, float(n) / 400.0)
		_frame(_look)
		var frame: int = _look.mark_frame(0) if _look.marks() > 0 else -9
		if seen.is_empty() or seen[-1] != frame:
			seen.append(frame)
	check_equal(seen, [0, 1, 2, 3, 2, 1, 0], "each frame in order, the last held, three back down to the first")
	_set_share(body, 0.6)
	_frame(_look)
	check_equal(_look.mark_strip(0), _strip, "the style's strip")
	check_equal(_look.mark_frame(0), 3, "held through the motion")
	body.spawn_left = 0.0
	_frame(_look)
	check_equal(_look.marks(), 0, "none once it stands")


func test_it_is_drawn_at_whole_pixels_centred_on_the_feet() -> void:
	_spawning(Vector2(200.5, 140.25), 0.2)
	_frame(_look)
	check_equal(_look.marks(), 1, "one mark")
	var at := Vector2(_look.mark(0).x, _look.mark(0).y)
	check_equal(at, Vector2(201.0, 140.0), "on whole pixels at its feet")
	var scale: int = _look.mark_scale(0)
	check(scale >= 1 and scale <= SpawnStyle.MAX_STRIP_SCALE, "a whole-number scale: %d" % scale)
	var corner: Vector2 = SpawnLook.strip_corner(at, 16, scale)
	check_equal(corner, corner.round(), "its corner on whole pixels")
	check_equal(corner + Vector2(8.0, 8.0) * float(scale), at, "its centre on the feet")
	check_equal(int(_look.mark(0).z), 8 * scale, "as wide as half its drawn side")
	check_equal(SpawnLook.strip_corner(Vector2(10.0, 10.0), 15, 1), Vector2(3.0, 3.0), "an odd side: half of it, rounded down, up and left")


func test_its_scale_follows_the_footprint() -> void:
	var small: Actor = _spawning(Vector2(100.0, 100.0), 0.2)
	var big: Actor = _spawning(Vector2(200.0, 100.0), 0.2)
	big.set_size(3.0)
	_frame(_look)
	check_equal(_look.marks(), 2, "a mark each")
	check_equal(_look.mark_scale(0), SpawnStyle.strip_scale(16, small.wall_radius()), "the small one's by its footprint")
	check_equal(_look.mark_scale(1), SpawnStyle.strip_scale(16, big.wall_radius()), "the big one's by its")
	check(_look.mark_scale(1) > _look.mark_scale(0), "a bigger body, a bigger mark: %d, %d" % [_look.mark_scale(0), _look.mark_scale(1)])


func test_a_fresh_look_draws_the_same_frame() -> void:
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.0)
	for share: float in [0.05, 0.15, 0.3, 0.6, 0.93, 0.97, 0.99]:
		_set_share(body, share)
		_frame(_look)
		var fresh: SpawnLook = _new_look()
		_frame(fresh)
		check_equal([fresh.mark_frame(0), fresh.mark_scale(0), fresh.mark(0)], [_look.mark_frame(0), _look.mark_scale(0), _look.mark(0)], "at %.2f, from its state alone" % share)
		fresh.free()
		_frame(_look)


func test_a_style_with_no_strip_draws_the_ring() -> void:
	_spawning(Vector2(100.0, 100.0), 0.2, &"rise")
	var rooted: Actor = _spawning(Vector2(200.0, 100.0), 0.3)
	_frame(_look)
	check_equal(_look.marks(), 2, "a mark each")
	check_equal(_look.mark_frame(0), -1, "rise's is the ring")
	check(_look.mark_strip(0) == null, "with no strip")
	check_equal(_look.mark_frame(1), SpawnStyle.strip_frame(4, rooted.spawn_share(), _style), "the strip's style's is its frame")
	check_equal(_look.mark_frame(1), 3, "at 0.3 of rise's numbers, its last")


func test_a_frame_of_strips_allocates_nothing() -> void:
	var bodies: Array[Actor] = []
	for n in 12:
		bodies.append(_spawning(Vector2(60.0 + 40.0 * (n % 6), 100.0 + 60.0 * (n / 6)), float(n) / 12.0, &"rooted" if n % 2 == 0 else &"rise"))
	_frame(_look)
	_frame(_look)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		for body in bodies:
			_set_share(body, fmod(body.spawn_share() + 0.005, 0.99))
		_frame(_look)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of twelve bodies, strips and rings, make no object")
