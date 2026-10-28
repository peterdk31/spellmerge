extends "res://tests/support/suite.gd"
## Possess (actors G9, docs/milestones/M2-actors.md, "Possess (a card)"): the card's carrier hands
## its caster's controller to the first actor it hits; the seat then drives that actor (its staff
## on the seat's buttons, its numbers on the seat's panel, the builder on its staffs, restored
## after); the caster's body stands and can be hurt; it ends when the time is up, when the target
## or the caster's body dies or is down, and when a newer possession of the target starts; nested
## possessions unwind in order; an enemy's controller possesses a wizard the same way (a scripted
## controller stands in for the AI); and `Actor.drive` never leaves a controller on two bodies.
## Real wizard scene, real Spells and registry (the `possess` card itself).
##
## godot --headless --path . --script res://tests/gameplay/actor/test_possess.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

## The card's seconds (content/spells/modifiers/possess/possess.tres).
const SECONDS: float = 3.0

var _world: Fixture
## Every possess_started / possess_ended as [caster, actor].
var _started: Array = []
var _ended: Array = []
## Every player_possessed as [player, seconds], and player_stats_changed as [player, max_health].
var _possessed: Array = []
var _stats: Array = []
var _staff_casts: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_started.clear()
	_ended.clear()
	_possessed.clear()
	_stats.clear()
	_staff_casts.clear()
	var bus := _world.bus
	bus.possess_started.connect(func(c: int, a: int) -> void: _started.append([c, a]))
	bus.possess_ended.connect(func(c: int, a: int) -> void: _ended.append([c, a]))
	bus.player_possessed.connect(func(p: int, s: float) -> void: _possessed.append([p, s]))
	bus.player_stats_changed.connect(func(p: int, _h: int, mh: int, _m: float, _mm: float) -> void: _stats.append([p, mh]))
	bus.staff_cast.connect(func(p: int, s: int, _o: Vector2, _d: Vector2) -> void: _staff_casts.append([p, s]))


func after_each() -> void:
	_world.free_all()


## A creature of the kit standing in for an enemy (until G6): Health 50, a hurtbox, a Mover, a
## Caster with `cards` (one row per staff) and a scripted controller (team enemies, no seat).
func _imp(at: Vector2, cards: Array = [[&"bolt"]]) -> Actor:
	var body := Actor.new()
	body.name = "Imp"
	var health := Health.new()
	health.max_health = 50
	body.add_child(health)
	body.add_child(Hurtbox.new())
	body.add_child(Mover.new())
	var caster := Caster.new()
	caster.staff_count = cards.size()
	caster.start_cards = cards
	body.add_child(caster)
	body.add_child(ActorFixture.Scripted.new())
	body.position = at
	return _world.add(body)


func _brain(body: Actor) -> ActorFixture.Scripted:
	return body.home_controller as ActorFixture.Scripted


func _seat(body: Actor) -> PlayerController:
	return Fixture.controller(body)


func _tap(seat: int, action: StringName) -> void:
	_world.hold(seat, action)
	_world.release(seat, action)


func _cards(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(&"" if word == "-" else StringName(word))
	return out


## Seat 0's wizard at the origin (aiming down), its first staff `possess · bolt`.
func _possessor(row: Array = [&"possess", &"bolt"]) -> Actor:
	return _world.wizard(0, Vector2.ZERO, [row, [], [], []])


# --- The card ------------------------------------------------------------------------------

func test_a_wizard_possesses_the_imp_its_bolt_hits_and_casts_its_staff_from_the_seat() -> void:
	var wizard := _possessor()
	var imp := _imp(Vector2(0.0, 60.0))
	var seat := _seat(wizard)
	var table: ActorsScript = _world.table
	_tap(0, &"staff_1")
	_world.run(8)
	check_equal(_started, [[wizard.id, imp.id]], "possess_started names the caster's body and the imp")
	check(imp.controller == seat, "the seat drives the imp")
	check(wizard.controller == null, "the wizard's body has no controller")
	check(seat.driving == imp and seat.driven() == imp, "the seat's controller drives only the imp")
	check_equal(table.actor_of_seat(0), imp.id, "the actor table has seat 0 on the imp")
	check_equal(table.team_of(imp.id), ActorsScript.TEAM_WIZARDS, "the imp is on the seat's team")
	check_equal(table.seat_of(wizard.id), ActorsScript.NONE, "the body has no seat")
	check_equal(table.team_of(wizard.id), ActorsScript.TEAM_WIZARDS, "and keeps its home team")
	check(imp.possessed_by != null and is_equal_approx(imp.possessed_by.seconds, SECONDS), "for the card's %s s" % SECONDS)
	check(not _stats.is_empty() and _stats.back() == [0, 50], "seat 0's panel shows the imp's numbers: %s" % [_stats])
	# The seat's first button casts the imp's staff, with the imp's mana.
	_staff_casts.clear()
	var mana: float = imp.caster.mana
	_tap(0, &"staff_1")
	_world.run(1)
	check_equal(_staff_casts, [[0, 0]], "seat 0's button casts the imp's staff")
	check(imp.caster.mana < mana, "with the imp's mana")
	# The seat's stick walks the imp; the wizard's body stands and can be hurt.
	_world.hold(0, &"move_right")
	_world.run(1)
	check(imp.velocity.x > 0.0, "seat 0's stick walks the imp: %s" % imp.velocity)
	check_equal(wizard.velocity, Vector2.ZERO, "the wizard's body stands")
	_world.release(0, &"move_right")
	_stats.clear()
	_world.hurt(wizard, 10)
	check_equal(wizard.health.health, 90, "the standing body takes hits")
	check(_stats.is_empty(), "which are not seat 0's numbers now: %s" % [_stats])
	check(imp.controller == seat, "a hit on the body does not end it")
	var ring: bool = false
	for child in imp.get_children():
		ring = ring or child is PossessedLook
	check(ring, "a ring is drawn round the possessed imp")


func test_one_possession_per_cast() -> void:
	var wizard := _possessor([&"possess", &"chain", &"bolt"])
	var first := _imp(Vector2(0.0, 60.0))
	var second := _imp(Vector2(30.0, 90.0))
	_tap(0, &"staff_1")
	_world.run(12)
	check(first.controller == _seat(wizard), "the first imp hit is possessed")
	check(second.health.health < 50, "the chain jumps on and hurts the second")
	check(second.controller == _brain(second), "but does not possess it")
	check_equal(_started.size(), 1, "one possession")


# --- How it ends ---------------------------------------------------------------------------

func test_it_ends_when_the_time_is_up_and_each_controller_goes_home() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	var brain := _brain(imp)
	var seat := _seat(wizard)
	check(Possession.begin(wizard, imp, 1.0) != null, "it starts")
	check_equal(brain.stopped_count, 1, "the imp's controller is put aside")
	_world.run(15)
	check(imp.controller == seat, "still on before the time is up")
	_stats.clear()
	_world.run(2)
	check(imp.controller == brain, "the imp's own controller is back")
	check_equal(brain.started_count, 2, "and starts over (an AI's fresh target and windup)")
	check(wizard.controller == seat and seat.driving == wizard, "the seat is home")
	check_equal(_world.table.actor_of_seat(0), wizard.id, "seat 0 on the wizard again")
	check_equal(_world.table.team_of(imp.id), ActorsScript.TEAM_ENEMIES, "the imp's team is its own again")
	check(not _stats.is_empty() and _stats.back() == [0, 100], "the panel shows the wizard again: %s" % [_stats])
	check_equal(_ended, [[wizard.id, imp.id]], "possess_ended")
	check(imp.possessed_by == null and wizard.possessions_cast.is_empty(), "nothing is left of it")
	# The ring is gone (freed at the end of the frame).
	var ring: bool = false
	for child in imp.get_children():
		ring = ring or (child is PossessedLook and not child.is_queued_for_deletion())
	check(not ring, "the ring is taken off")


func test_it_ends_when_the_possessed_actor_dies() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	Possession.begin(wizard, imp, SECONDS)
	imp.health.take(500, 0)
	check(imp.is_dying(), "the imp dies")
	check(wizard.controller == _seat(wizard), "the seat is home at once")
	check_equal(_ended.size(), 1, "possess_ended")


func test_it_ends_when_a_possessed_wizard_is_downed_and_the_seat_comes_back_to_it() -> void:
	var caster := _world.wizard(0)
	var target := _world.wizard(1, Vector2(0.0, 60.0))
	var seat_one := _seat(target)
	Possession.begin(caster, target, SECONDS)
	check(target.controller == _seat(caster), "seat 0 drives wizard 1")
	check_equal(_possessed, [[1, SECONDS]], "seat 1 is told it is possessed, with the time")
	check(seat_one.is_set_aside() and seat_one.driving == null, "seat 1 drives nothing")
	_world.hurt(target, 100)
	check(target.is_down(), "wizard 1 is down")
	_world.run(1)
	check(target.controller == seat_one, "seat 1 is back on its downed wizard")
	check(caster.controller == _seat(caster), "seat 0 is home")
	check(_possessed.back() == [1, 0.0], "seat 1 is told it drives again: %s" % [_possessed])


func test_it_ends_when_the_casters_body_is_downed() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	Possession.begin(wizard, imp, SECONDS)
	_world.hurt(wizard, 100)
	check(wizard.is_down(), "the standing body is downed")
	_world.run(1)
	check(wizard.controller == _seat(wizard), "the seat goes home to its downed wizard")
	check(imp.controller == _brain(imp), "the imp's own controller is back")


func test_it_ends_when_the_casters_body_dies() -> void:
	var imp := _imp(Vector2(0.0, 60.0))
	var wizard := _world.wizard(0)
	Possession.begin(imp, wizard, SECONDS)
	imp.die(-1)
	check(wizard.controller == _seat(wizard), "the wizard's seat is back at once")
	check_equal(_ended, [[imp.id, wizard.id]], "possess_ended")


func test_a_newer_possession_of_an_actor_ends_the_older_first() -> void:
	var first := _world.wizard(0)
	var second := _world.wizard(1, Vector2(40.0, 0.0))
	var imp := _imp(Vector2(0.0, 60.0))
	Possession.begin(first, imp, SECONDS)
	Possession.begin(second, imp, SECONDS)
	check_equal(_ended, [[first.id, imp.id]], "the older ended")
	check(first.controller == _seat(first), "seat 0 is home")
	check(imp.controller == _seat(second), "seat 1 drives the imp")
	check(imp.possessed_by.put_aside == _brain(imp), "with the imp's own controller put aside")
	_world.run(int(SECONDS / Fixture.STEP) + 1)
	check(imp.controller == _brain(imp), "which comes back at the end")
	check(second.controller == _seat(second), "and seat 1 is home")


# --- Nested --------------------------------------------------------------------------------

func test_a_possession_from_a_possessed_body_moves_on_and_they_unwind_in_order() -> void:
	var wizard := _possessor()
	var near := _imp(Vector2(0.0, 60.0), [[&"possess", &"bolt"]])
	var far := _imp(Vector2(0.0, 120.0))
	var seat := _seat(wizard)
	_tap(0, &"staff_1")
	_world.run(8)
	check(near.controller == seat, "the seat drives the near imp")
	# From the near imp (aiming down) the seat possesses the far one.
	_tap(0, &"staff_1")
	_world.run(8)
	check(far.controller == seat, "the seat moved on to the far imp")
	check(near.controller == null, "the near imp stands with no controller")
	check(wizard.controller == null, "and the wizard's body still stands")
	check_equal(_world.table.actor_of_seat(0), far.id, "seat 0 is on the far imp only")
	# The far one dies: the seat goes back to the near imp, whose possession goes on.
	far.health.take(500, 0)
	check(near.controller == seat, "the seat is back on the near imp")
	check(wizard.controller == null, "not yet home")
	_world.run(int(SECONDS / Fixture.STEP) + 1)
	check(wizard.controller == seat, "then home")
	check(near.controller == _brain(near), "and the near imp has its own controller")


func test_ending_the_older_possession_unwinds_the_newer_first() -> void:
	var wizard := _world.wizard(0)
	var near := _imp(Vector2(0.0, 60.0))
	var far := _imp(Vector2(0.0, 120.0))
	var outer := Possession.begin(wizard, near, SECONDS)
	Possession.begin(near, far, SECONDS)
	check(far.controller == _seat(wizard) and near.controller == null, "nested")
	outer.end()
	check_equal(_ended, [[near.id, far.id], [wizard.id, near.id]], "the newer ends first")
	check(far.controller == _brain(far) and near.controller == _brain(near), "both imps have their own controllers")
	check(wizard.controller == _seat(wizard), "the seat is home")


# --- An enemy possesses a wizard -------------------------------------------------------------

func test_an_enemy_possesses_a_wizard_and_its_controller_drives_it() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 80.0), [[&"possess", &"bolt"]])
	var brain := _brain(imp)
	brain.aim = Vector2.UP
	brain.presses = [0]
	_world.run(8)
	check(wizard.controller == brain, "the imp's controller drives the wizard")
	check(imp.controller == null, "the imp stands")
	check_equal(_possessed, [[0, SECONDS]], "seat 0's panel is marked possessed with the time")
	check_equal(_world.table.actor_of_seat(0), ActorsScript.NONE, "seat 0 drives nothing")
	check_equal(_world.table.team_of(wizard.id), ActorsScript.TEAM_ENEMIES, "the wizard aims at the enemies' targets")
	brain.move = Vector2.RIGHT
	_world.hold(0, &"move_left")
	_world.run(1)
	check(wizard.velocity.x > 0.0, "the imp's controller walks the wizard, not seat 0: %s" % wizard.velocity)
	_world.release(0, &"move_left")
	brain.move = Vector2.ZERO
	_world.run(int(SECONDS / Fixture.STEP))
	check(wizard.controller == _seat(wizard), "the seat comes back at the end")
	check(imp.controller == brain, "the imp's controller goes home")
	check(_possessed.back() == [0, 0.0], "and the mark goes")


# --- The builder on a possessed actor -------------------------------------------------------

func test_the_builder_edits_the_possessed_actor_and_its_staff_comes_back_after() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0), [[&"possess", &"bolt"]])
	var twin := _imp(Vector2(60.0, 60.0), [[&"possess", &"bolt"]])
	var before: float = twin.caster.next_cast_mana(0)
	var row: Array[StringName] = imp.caster.cards_of(0)
	Possession.begin(wizard, imp, 1.0)
	_world.bus.staff_cards_requested.emit(0, 0, _cards("bolt"))
	check_equal(imp.caster.cards_of(0)[0], &"bolt", "seat 0's builder builds the imp's staff")
	check(imp.caster.next_cast_mana(0) < before, "which is cheaper now")
	check_equal(twin.caster.next_cast_mana(0), before, "an imp of the same staff keeps its own")
	check_equal(twin.caster.cards_of(0), row, "and its cards")
	check_equal(wizard.caster.cards_of(0), _cards("- - - -"), "the wizard's staffs are untouched")
	_world.run(int(1.0 / Fixture.STEP) + 1)
	check_equal(imp.caster.cards_of(0), row, "the imp's own staff comes back after")
	check_equal(imp.caster.next_cast_mana(0), before, "with its cost")


# --- drive ---------------------------------------------------------------------------------

func test_drive_never_leaves_a_controller_on_two_bodies() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	var seat := _seat(wizard)
	imp.drive(seat)
	check(wizard.controller == null, "taken off the wizard")
	check(seat.driving == imp, "it drives the imp")
	check(not wizard.caster.cast_done.is_connected(seat._on_cast_done), "the wizard's caster is not bound to it")
	check(not wizard.health.changed.is_connected(seat._on_health_changed), "nor its health")
	check(imp.caster.cast_done.is_connected(seat._on_cast_done), "the imp's is")
	check_equal(_world.table.seat_of(wizard.id), ActorsScript.NONE, "the wizard has no seat in the table")
	wizard.drive(seat)
	check(imp.controller == null and wizard.controller == seat, "and back, never on both")
	check(not imp.caster.cast_done.is_connected(seat._on_cast_done), "the imp's caster is let go")
	_stats.clear()
	_world.hurt(imp, 5)
	check(_stats.is_empty(), "the imp's hits are not the seat's: %s" % [_stats])
	_world.hurt(wizard, 5)
	check(not _stats.is_empty() and _stats.back() == [0, 100], "the wizard's are, once each")
	check_equal(_stats.size(), 1, "sent once, not twice")


# --- The real enemy (G6: an Actor driven by its AIController) ----------------------------------

## An ember imp from the real scene and `data` (the real data by default), in the tree at `at`.
func _ember_imp(at: Vector2, data: EnemyBase = ImpData) -> Actor:
	var body := ImpData.scene.instantiate() as Actor
	body.data = data
	body.position = at
	return _world.add(body)


func _mind(body: Actor) -> AIController:
	return body.home_controller as AIController


func test_a_wizard_possesses_an_ember_imp_and_its_ai_starts_over_after() -> void:
	var wizard := _possessor()
	var imp := _ember_imp(Vector2(0.0, 60.0))
	var mind := _mind(imp)
	check(mind != null, "the imp is driven by its AIController")
	_tap(0, &"staff_1")
	_world.run(8)
	check(imp.controller == _seat(wizard), "the seat drives the ember imp")
	check(mind.driving == null, "its AI drives nothing meanwhile")
	check(not mind.is_telegraphing(), "and winds nothing up")
	_staff_casts.clear()
	_tap(0, &"staff_1")
	_world.run(1)
	check_equal(_staff_casts, [[0, 0]], "seat 0's button casts the imp's fire bolt")
	_world.run(int(SECONDS / Fixture.STEP) + 1)
	check(imp.controller == mind and mind.driving == imp, "the AI drives its imp again")
	check(wizard.controller == _seat(wizard), "the seat is home")


func test_an_ember_imp_with_possess_takes_a_wizard_and_its_ai_drives_it() -> void:
	var data := ImpData.duplicate() as EnemyBase
	data.cards = [&"possess", &"bolt"] as Array[StringName]
	data.max_mana = 40.0
	var wizard := _world.wizard(0)
	var imp := _ember_imp(Vector2(80.0, 0.0), data)
	var mind := _mind(imp)
	var taken: bool = false
	for i in 64:
		_world.run(1)
		if wizard.controller == mind:
			taken = true
			break
	check(taken, "the imp's AI winds up, casts and takes the wizard")
	check(imp.controller == null, "the imp stands")
	check_equal(_possessed, [[0, SECONDS]], "seat 0's panel is marked possessed with the time")
	check_equal(_world.table.actor_of_seat(0), ActorsScript.NONE, "seat 0 drives nothing")
	_world.run(int(SECONDS / Fixture.STEP) + 1)
	check(wizard.controller == _seat(wizard), "the seat comes back at the end")
	check(imp.controller == mind, "and the AI goes home")
