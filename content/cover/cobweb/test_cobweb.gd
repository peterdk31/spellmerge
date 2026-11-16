extends "res://tests/support/suite.gd"
## The crypt's cobwebs (ground cover GC8, content/cover/cobweb, decision 3): they fill the crypt
## sparsely, one web a cell; whoever walks through them is chilled (slowed) while in them, and never
## frozen by them alone; fire burns them away fast, for good (the crypt's cover never grows back),
## with embers as they go; frost on a burning web puts it out.
const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const WEB: CoverKind = preload("res://content/cover/cobweb/cobweb.tres")

var _kit: Kit


func before_each() -> void:
	_kit = Kit.new(root, WEB)


func after_each() -> void:
	_kit.free_all()


## The webs with no spread: one lit cell's own story.
func _still() -> CoverKind:
	var still := WEB.duplicate(true) as CoverKind
	var burning: CoverState = still.states[still.state_at(&"burning")]
	burning.spreads = &""
	burning.spread_chance = 0.0
	return still


func test_it_is_sound_and_fills_the_crypt_one_web_a_cell() -> void:
	check_equal(_kit.problems(), PackedStringArray(), "its data")
	check(WEB.fills(&"crypt"), "the crypt's biome")
	check_equal(WEB.tufts_per_cell, 1, "a web a cell")
	check_equal(WEB.clump_size, 0, "no clumps: a web alone")
	check_equal(WEB.states[0].status, &"chill", "at rest it chills")
	check_equal(WEB.states[0].bend, 0.0, "a web does not bend, so it is never trampled")


func test_it_chills_whoever_stands_in_it_and_never_freezes_them() -> void:
	var cell: int = _kit.cell(5, 5)
	var body: Actor = _kit.world.actor(_kit.middle(cell), [&"health", &"hurtbox"])
	_kit.steps(1)
	check(_kit.has_status(body, &"chill"), "chilled at once")
	var frozen: bool = false
	for i in roundi(5.0 / Kit.DT):
		_kit.steps(1)
		frozen = frozen or _kit.has_status(body, &"freeze")
	check(not frozen, "five seconds in the webs: never frozen by them alone")
	check(_kit.asked.size() >= 9, "chilled again every half second")
	body.position = _kit.middle(_kit.cell(18, 8)) + Vector2(16.0, 16.0)
	_kit.wait(1.0)
	check(not _kit.has_status(body, &"chill"), "out of them, the chill wears off")


## Regression (GC8's review): walking in and out of webs asked a chill at each step in, so three
## within a chill's time froze the walker.
func test_walking_in_and_out_of_it_never_freezes() -> void:
	var cell: int = _kit.cell(5, 5)
	var body: Actor = _kit.world.actor(_kit.middle(cell), [&"health", &"hurtbox"])
	var frozen: bool = false
	for i in roundi(5.0 / Kit.DT):
		body.position = _kit.middle(cell) if (i / 12) % 2 == 0 else _kit.middle(_kit.cell(18, 8)) + Vector2(16.0, 16.0)
		_kit.steps(1)
		frozen = frozen or _kit.has_status(body, &"freeze")
	check(not frozen, "five seconds of 0.2 s in, 0.2 s out: never frozen")
	check(_kit.asked.size() >= 5, "while chilled again and again (%d)" % _kit.asked.size())


func test_fire_burns_it_away_for_good() -> void:
	_kit.free_all()
	_kit = Kit.new(root, _still())
	var cell: int = _kit.cell(4, 4)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"burning", "lit")
	check(_kit.look.motes.cells_giving_off(WEB.id, WEB.state_at(&"burning")) == 1, "its embers rise")
	_kit.wait(0.6)
	check_equal(_kit.state_of(cell), &"gone", "burnt away within a second")
	_kit.wait(60.0)
	check_equal(_kit.state_of(cell), &"gone", "and never back")
	var body: Actor = _kit.world.actor(_kit.middle(cell), [&"health", &"hurtbox"])
	_kit.steps(2)
	check(not _kit.has_status(body, &"chill"), "a burnt web chills nobody")


func test_frost_puts_a_burning_web_out() -> void:
	var cell: int = _kit.cell(8, 4)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	_kit.touch(&"frost", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"rest", "back to a web")


func test_water_puts_a_burning_web_out() -> void:
	var cell: int = _kit.cell(10, 4)
	_kit.touch(&"fire", _kit.middle(cell))
	_kit.steps(1)
	_kit.touch(&"water", _kit.middle(cell))
	_kit.steps(1)
	check_equal(_kit.state_of(cell), &"rest", "back to a web")
