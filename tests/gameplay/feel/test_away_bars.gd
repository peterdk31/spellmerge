extends "res://tests/support/suite.gd"
## The health bar over a wizard whose seat is away (gameplay/feel/away_bars.gd, items I8): while a
## seat drives another body its own wizard shows its health over its head, live; none while it
## drives its wizard, none over a wizard an enemy's AI drives (its panel shows it), and higher over
## a wizard that is itself possessed meanwhile (over that timer). Real wizard scene and actor table.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const AwayBarsScript := preload("res://gameplay/feel/away_bars.gd")

var _world: Fixture
var _bars: AwayBarsScript


func before_each() -> void:
	_world = Fixture.new(root)
	_bars = own(AwayBarsScript.new()) as AwayBarsScript
	root.add_child(_bars)


func after_each() -> void:
	_world.free_all()


## A creature with Health 50 and a scripted controller (no seat).
func _imp(at: Vector2) -> Actor:
	var body := Actor.new()
	body.name = "Imp"
	var health := Health.new()
	health.max_health = 50
	body.add_child(health)
	body.add_child(Hurtbox.new())
	body.add_child(Mover.new())
	body.add_child(ActorFixture.Scripted.new())
	body.position = at
	return _world.add(body)


func test_a_wizard_whose_seat_drives_another_body_shows_its_health_over_its_head() -> void:
	var wizard := _world.wizard(0, Vector2(40.0, 80.0))
	var imp := _imp(Vector2(40.0, 140.0))
	_bars.step(_world.table)
	check_equal(_bars.count, 0, "no bar while the seat drives its wizard")
	Possession.begin(wizard, imp, 3.0)
	_bars.step(_world.table)
	check_equal(_bars.count, 1, "one bar while the seat drives the imp")
	if _bars.count != 1:
		return
	check_equal(_bars.seat_of(0), 0, "seat 0's")
	check_equal(_bars.position_of(0), Vector2(40.0, 80.0 + AwayBarsScript.TOP), "just over the wizard's head")
	check_equal(_bars.filled_of(0), AwayBarsScript.BAR_WIDTH, "full")
	_world.hurt(wizard, 50)
	_bars.step(_world.table)
	check_equal(_bars.filled_of(0), AwayBarsScript.BAR_WIDTH / 2, "a hit on the wizard shows at once")
	_world.hurt(wizard, 49)
	_bars.step(_world.table)
	check_equal(_bars.filled_of(0), 1, "a hurt wizard shows at least a pixel")
	imp.possessed_by.end()
	_bars.step(_world.table)
	check_equal(_bars.count, 0, "home again: no bar")


func test_a_wizard_an_enemy_drives_shows_no_bar() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	Possession.begin(imp, wizard, 3.0)
	_bars.step(_world.table)
	check_equal(_bars.count, 0, "its seat drives nothing, so its panel shows the wizard")


func test_the_bar_sits_over_the_timer_of_a_wizard_possessed_meanwhile() -> void:
	var wizard := _world.wizard(0, Vector2(40.0, 80.0))
	var mine := _imp(Vector2(40.0, 140.0))
	var other := _imp(Vector2(90.0, 80.0))
	Possession.begin(wizard, mine, 3.0)
	Possession.begin(other, wizard, 3.0)
	_bars.step(_world.table)
	check_equal(_bars.count, 1, "the seat still drives its imp")
	if _bars.count == 1:
		check_equal(_bars.position_of(0), Vector2(40.0, 80.0 + AwayBarsScript.TOP - AwayBarsScript.OVER_RING), "over the possession's ring")
