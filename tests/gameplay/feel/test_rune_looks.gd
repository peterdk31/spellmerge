extends "res://tests/support/suite.gd"
## A biome's secret runes as the view draws them (the owner, 2026-11-20; gameplay/feel/rune_looks.gd),
## driven by their event alone (`secret_rune_shown`): hidden, a faint crack in its element's tint and
## nothing in the secret room; found, the rune draws itself in round the crack a stage a frame (at
## least 3), keeping what each stage drew, and the rune leading back comes in by the same stages; -1
## forgets them, and after a restore what is told is drawn as it stands.

const LooksScript := preload("res://gameplay/feel/rune_looks.gd")
const LockLooksScript := preload("res://gameplay/feel/lock_looks.gd")
const EventsScript := preload("res://core/events/events.gd")

const AT: Vector2 = Vector2(200.0, 120.0)
const BACK: Vector2 = Vector2(900.0, 80.0)

var _bus: EventsScript = null
var _looks: LooksScript = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_looks = LooksScript.new()
	_looks.registry = root.get_node("Registry")
	root.add_child(own(_looks))
	_looks.set_process(false)
	_looks.bind(_bus)


func test_a_hidden_rune_is_a_faint_crack_in_its_elements_tint() -> void:
	_bus.secret_rune_shown.emit(0, AT, BACK, &"fire", false)
	check_equal(_looks.runes(), 1, "the rune is drawn")
	check_equal(_looks.frame_of(0), 0, "hidden: its crack alone")
	check(not _looks.is_moving(), "nothing moves while it is hidden")
	var card: ElementBase = root.get_node("Registry").call(&"get_resource", &"spells", &"fire") as ElementBase
	check(card != null and _looks.tint_of(0) == Palette.shades_of(LockLooksScript.nearest_material(card.tint)), "in the palette material nearest its element's tint")


func test_a_found_rune_draws_itself_in_by_stages() -> void:
	_bus.secret_rune_shown.emit(0, AT, BACK, &"frost", false)
	_bus.secret_rune_shown.emit(0, AT, BACK, &"frost", true)
	var frames: Array[int] = []
	while _looks.is_moving() and frames.size() < 30:
		_looks.advance()
		frames.append(_looks.frame_of(0))
	var expected: Array[int] = []
	for frame in LooksScript.FOUND_FRAMES:
		expected.append(frame + 1)
	check_equal(frames, expected, "a stage a frame")
	check(LooksScript.FOUND_FRAMES >= 3, "at least 3 stages between hidden and found (Smooth)")
	# Each stage keeps the crack and the ring drawn before it: the ring grows in order.
	var ring: PackedVector2Array = LooksScript.ring_pixels()
	check(ring.size() >= 24, "a ring of whole pixels: %d" % ring.size())
	var seen: Dictionary = {}
	for pixel: Vector2 in ring:
		check(not seen.has(pixel), "each ring pixel once")
		seen[pixel] = true
		check(pixel == pixel.round(), "whole pixels")
	check(LooksScript.crack_pixels().size() >= 5, "its crack is a stroke of pixels")


## ART3: the rune is drawn in art pixels at the same size in the world: its ring RING world pixels
## round, its crack CRACK each way, two art pixels across its middle, a lip under it, and its notches
## inside the ring, every pixel once.
func test_a_rune_is_drawn_at_the_arts_detail() -> void:
	var d: int = LooksScript.DETAIL
	check_equal(d, ArtDetail.DETAIL, "the art's detail")
	for pixel: Vector2 in LooksScript.ring_pixels():
		check(absf(pixel.length() / float(d) - float(LooksScript.RING)) < 0.5 / float(d), "the ring at RING world pixels: %s" % pixel)
	var crack: PackedVector2Array = LooksScript.crack_pixels()
	var widest: float = 0.0
	var seen: Dictionary = {}
	for pixel: Vector2 in crack:
		check(not seen.has(pixel), "each crack pixel once")
		seen[pixel] = true
		widest = maxf(widest, absf(pixel.x))
	check_equal(int(widest), LooksScript.CRACK * d, "the crack CRACK world pixels each way")
	check(crack.has(Vector2.ZERO) and crack.has(Vector2.RIGHT), "two art pixels across its middle")
	for pixel: Vector2 in LooksScript.lip_pixels(crack):
		check(not crack.has(pixel) and crack.has(pixel + Vector2.UP), "the lip lies just under the crack")
	var inside: float = float(LooksScript.RING * d - 1)
	var notches: PackedVector2Array = LooksScript.notch_pixels()
	check_equal(notches.size(), 4 * LooksScript.NOTCH, "four notches")
	for pixel: Vector2 in notches:
		check(pixel.length() < inside - 0.5, "a notch inside the ring's lit row: %s" % pixel)
		check(notches.count(pixel) == 1, "each notch pixel once")


func test_a_rune_first_told_found_is_drawn_as_it_stands_and_forgotten_by_minus_one() -> void:
	_bus.secret_rune_shown.emit(0, AT, BACK, &"fire", true)
	check_equal(_looks.frame_of(0), LooksScript.FOUND_FRAMES, "told found before it was drawn hidden: drawn found")
	_bus.secret_rune_shown.emit(-1, Vector2.ZERO, Vector2.ZERO, &"", true)
	check_equal(_looks.runes(), 0, "-1 forgets every rune")
	_bus.secret_rune_shown.emit(0, AT, BACK, &"fire", true)
	check_equal(_looks.frame_of(0), LooksScript.FOUND_FRAMES, "after a restore, drawn as it stands")
