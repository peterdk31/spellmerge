extends "res://tests/support/suite.gd"
## Possess (actors G9, docs/milestones/M2-actors.md, "Possess (a card)"; owner, 2026-10-29): every
## actor the card's carriers hit is possessed by the caster's controller; it drives the oldest
## (its staff on the seat's buttons) and puppets copy its intent on the others; the caster's body
## stands and can be hurt, and its being down or dead ends nothing; a possession ends when the
## time is up, when the target dies or is down, and when another driver's newer possession of the
## target starts; the controller then moves to its next oldest body, else home, else waits behind
## whoever possesses its home; an enemy's controller possesses a wizard the same way (a scripted
## controller stands in for the AI), and goes on after its body dies; and `Actor.drive` never
## leaves a controller on two bodies. The HUD stays the player's (owner, 2026-10-28): the seat's numbers, its corner panel
## (a real Hud) and its builder are its own wizard's, live, while it drives an imp and while an AI
## drives the wizard; the PossessedLook draws bars and the timer over a seat-driven imp, only the
## timer over an AI-driven wizard. Real wizard scene, real Spells and registry (the `possess` card).
##
## godot --headless --path . --script res://tests/gameplay/actor/test_possess.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")
const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScript := preload("res://hud/panels/panels.gd")
## Loaded, not preloaded: the scene is also the "Hud" autoload (tests/README.md).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

## The card's seconds (content/spells/modifiers/possess/possess.tres).
const SECONDS: float = 3.0

var _world: Fixture
## Every possess_started / possess_ended as [caster, actor].
var _started: Array = []
var _ended: Array = []
## Every player_stats_changed as [player, health, max_health].
var _stats: Array = []
var _staff_casts: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_started.clear()
	_ended.clear()
	_stats.clear()
	_staff_casts.clear()
	var bus := _world.bus
	bus.possess_started.connect(func(c: int, a: int) -> void: _started.append([c, a]))
	bus.possess_ended.connect(func(c: int, a: int) -> void: _ended.append([c, a]))
	bus.player_stats_changed.connect(func(p: int, h: int, mh: int, _m: float, _mm: float) -> void: _stats.append([p, h, mh]))
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
	check(not _stats.has([0, 50, 50]), "seat 0's numbers never become the imp's: %s" % [_stats])
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
	check_equal(_stats, [[0, 90, 100]], "which are seat 0's numbers still (the HUD is the player's own wizard)")
	_stats.clear()
	_world.hurt(imp, 5)
	check(_stats.is_empty(), "a hit on the imp is not: %s" % [_stats])
	check(imp.controller == seat, "a hit on the body does not end it")
	check(_look(imp) != null, "the possession is drawn over the imp")


func test_every_actor_a_cast_hits_is_possessed_and_the_seat_drives_the_first() -> void:
	var wizard := _possessor([&"possess", &"chain", &"bolt"])
	var first := _imp(Vector2(0.0, 60.0))
	var second := _imp(Vector2(30.0, 90.0))
	var seat := _seat(wizard)
	_tap(0, &"staff_1")
	_world.run(12)
	check(first.controller == seat, "the first imp hit is driven by the seat")
	check(second.health.health < 50, "the chain jumps on and hurts the second")
	check(second.controller is PuppetController, "and possesses it too, as a puppet")
	check_equal(_started.size(), 2, "two possessions: %s" % [_started])
	check_equal(seat.possessions.size(), 2, "the seat holds both, oldest first")
	check(seat.possessions[0].target == first, "the first imp is the oldest")
	check_equal(_world.table.actor_of_seat(0), first.id, "the seat is on the first imp only")
	check_equal(_world.table.team_of(second.id), ActorsScript.TEAM_WIZARDS, "the puppet is on the seat's team")
	check_equal(_world.table.seat_of(second.id), ActorsScript.NONE, "and is no seat")


func test_a_split_bolt_possesses_both_imps_it_hits() -> void:
	var wizard := _possessor([&"possess", &"split", &"bolt"])
	var left := _imp(Vector2(-14.0, 70.0))
	var right := _imp(Vector2(14.0, 70.0))
	_tap(0, &"staff_1")
	_world.run(12)
	check(left.possessed_by != null and right.possessed_by != null, "both imps are possessed: %s" % [_started])
	check_equal(_seat(wizard).possessions.size(), 2, "by seat 0")


func test_a_puppet_copies_the_seats_walk_aim_and_casts() -> void:
	var wizard := _world.wizard(0)
	var driven := _imp(Vector2(0.0, 60.0))
	var puppet := _imp(Vector2(40.0, 60.0))
	var seat := _seat(wizard)
	Possession.begin(wizard, driven, SECONDS)
	Possession.begin(wizard, puppet, SECONDS)
	check(driven.controller == seat and puppet.controller is PuppetController, "the seat drives the first, a puppet the second")
	_world.hold(0, &"move_right")
	_world.run(2)
	check(driven.velocity.x > 0.0 and puppet.velocity.x > 0.0, "both walk right: %s %s" % [driven.velocity, puppet.velocity])
	check_equal(wizard.velocity, Vector2.ZERO, "the wizard's body stands")
	_world.release(0, &"move_right")
	var mana: float = puppet.caster.mana
	_tap(0, &"staff_1")
	_world.run(2)
	check(puppet.caster.mana < mana, "the seat's button casts the puppet's staff too")
	check(puppet.aim.is_equal_approx(driven.aim), "in the same direction: %s %s" % [puppet.aim, driven.aim])


func test_a_hit_on_a_body_already_possessed_does_nothing() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	var possession := Possession.begin(wizard, imp, SECONDS)
	_world.run(8)
	check(Possession.begin(wizard, imp, SECONDS) == null, "from the wizard")
	check(Possession.begin(imp, imp, SECONDS) == null, "or from the imp itself")
	check(imp.possessed_by == possession and possession.left < SECONDS, "the first goes on, not refreshed")
	check_equal(_started.size(), 1, "one possession")


func test_a_puppet_casting_possess_adds_to_the_seats_bodies() -> void:
	var wizard := _world.wizard(0)
	var driven := _imp(Vector2(0.0, 60.0))
	var puppet := _imp(Vector2(40.0, 60.0))
	var far := _imp(Vector2(40.0, 120.0))
	var seat := _seat(wizard)
	Possession.begin(wizard, driven, SECONDS)
	Possession.begin(wizard, puppet, SECONDS)
	check(Possession.begin(puppet, far, SECONDS) != null, "a puppet's hit possesses")
	check(seat.possessions.size() == 3 and seat.possessions[2].target == far, "for the seat, newest last")
	check(far.controller is PuppetController, "as a puppet")
	check(driven.controller == seat, "the seat stays in the oldest")
	check(Possession.begin(puppet, wizard, SECONDS) == null, "the seat's own wizard is never possessed by it")


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
	check(not _stats.is_empty() and _stats.back() == [0, 100, 100], "the wizard's numbers are sent again on coming home: %s" % [_stats])
	check_equal(_ended, [[wizard.id, imp.id]], "possess_ended")
	check(imp.possessed_by == null and seat.possessions.is_empty(), "nothing is left of it")
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
	check(seat_one.is_set_aside() and seat_one.driving == null, "seat 1 is set aside and drives nothing")
	_world.hurt(target, 100)
	check(target.is_down(), "wizard 1 is down")
	_world.run(1)
	check(target.controller == seat_one, "seat 1 is back on its downed wizard")
	check(caster.controller == _seat(caster), "seat 0 is home")
	check(not seat_one.is_set_aside(), "and is no longer set aside")


func test_the_casters_body_downed_ends_nothing_and_the_seat_comes_home_to_it_after() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	Possession.begin(wizard, imp, 1.0)
	_world.hurt(wizard, 100)
	check(wizard.is_down(), "the standing body is downed")
	_world.run(1)
	check(imp.controller == _seat(wizard), "the seat still drives the imp")
	_world.run(int(1.0 / Fixture.STEP) + 1)
	check(wizard.controller == _seat(wizard), "then goes home to its downed wizard")
	check(imp.controller == _brain(imp), "and the imp's own controller is back")


func test_an_enemy_that_dies_goes_on_driving_the_wizard_until_the_time_is_up() -> void:
	var imp := _imp(Vector2(0.0, 60.0))
	var brain := _brain(imp)
	var wizard := _world.wizard(0)
	Possession.begin(imp, wizard, 1.0)
	imp.die(-1)
	check(wizard.controller == brain, "the dead imp's controller still drives the wizard")
	check(is_instance_valid(brain) and brain.get_parent() != imp, "it left the body before it was freed")
	check(_ended.is_empty(), "nothing ended")
	_world.run(int(1.0 / Fixture.STEP) + 1)
	check(wizard.controller == _seat(wizard), "the wizard's seat is back at the end")
	check_equal(_ended, [[imp.id, wizard.id]], "possess_ended")
	await process_frame
	check(not is_instance_valid(brain), "the homeless controller is freed")


func test_a_newer_possession_of_an_actor_ends_the_other_drivers_older_first() -> void:
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


# --- Moving on ----------------------------------------------------------------------------

func test_a_possession_from_the_driven_body_adds_a_puppet_and_the_seat_moves_on_when_it_ends() -> void:
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
	check(far.controller is PuppetController, "the far imp is a puppet")
	check(near.controller == seat, "the seat stays in the oldest, the near imp")
	check(wizard.controller == null, "and the wizard's body still stands")
	# The near one dies: the seat moves on to the far imp, not home.
	near.health.take(500, 0)
	check(far.controller == seat, "the seat moves on to the far imp")
	check(wizard.controller == null, "not yet home")
	check_equal(_world.table.actor_of_seat(0), far.id, "seat 0 is on the far imp")
	_world.run(int(SECONDS / Fixture.STEP) + 1)
	check(wizard.controller == seat, "then home")
	check(far.controller == _brain(far), "and the far imp has its own controller")


func test_when_the_driven_body_is_stolen_the_seat_moves_on() -> void:
	var first := _world.wizard(0)
	var second := _world.wizard(1, Vector2(80.0, 0.0))
	var near := _imp(Vector2(0.0, 60.0))
	var far := _imp(Vector2(0.0, 120.0))
	Possession.begin(first, near, SECONDS)
	Possession.begin(first, far, SECONDS)
	Possession.begin(second, near, SECONDS)
	check(near.controller == _seat(second), "seat 1 took the near imp")
	check(far.controller == _seat(first), "seat 0 moved on to the far one")
	check(first.controller == null, "seat 0's wizard still stands")
	Possession.begin(second, far, SECONDS)
	check(far.controller is PuppetController and (far.controller as PuppetController).leader_controller == _seat(second),
		"seat 1 steals the far one too, as its puppet")
	check(first.controller == _seat(first), "and seat 0, with nothing left, is home")


func test_a_seat_with_nothing_left_waits_behind_whoever_possesses_its_wizard() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	var other := _imp(Vector2(60.0, 0.0))
	var seat := _seat(wizard)
	Possession.begin(wizard, imp, 1.0)
	check(Possession.begin(other, wizard, 2.0) != null, "an imp possesses the empty wizard")
	check(wizard.controller == _brain(other), "the imp's controller drives it")
	_world.run(int(1.0 / Fixture.STEP) + 1)
	check(imp.controller == _brain(imp), "seat 0's possession of the imp is over")
	check(seat.driving == null and seat.is_set_aside(), "seat 0 waits: it drives nothing")
	check(wizard.controller == _brain(other), "while the imp's controller goes on")
	_world.run(int(1.0 / Fixture.STEP) + 1)
	check(wizard.controller == seat, "then seat 0 is home")
	check(other.controller == _brain(other), "and the other imp's controller too")


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
	check(_seat(wizard).is_set_aside(), "seat 0 is set aside")
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
	check(not _seat(wizard).is_set_aside(), "and seat 0 drives again")


# --- The builder during a possession ----------------------------------------------------

func test_the_builder_edits_the_home_wizard_while_the_seat_drives_an_imp() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0), [[&"possess", &"bolt"]])
	var row: Array[StringName] = imp.caster.cards_of(0)
	var changed: Array = []
	_world.bus.staff_changed.connect(func(p: int, at: int, plan: Dictionary) -> void: changed.append([p, at, plan.get("cards")]))
	Possession.begin(wizard, imp, 1.0)
	check(changed.is_empty(), "driving the imp announces none of its staffs: %s" % [changed])
	_world.bus.staff_cards_requested.emit(0, 0, _cards("bolt"))
	check_equal(wizard.caster.cards_of(0)[0], &"bolt", "seat 0's builder builds the wizard's staff")
	check_equal(imp.caster.cards_of(0), row, "not the imp's")
	check(changed.size() == 1 and changed[0][0] == 0 and changed[0][1] == 0 and changed[0][2] == _cards("bolt - - -"),
		"the panel and builder hear the wizard's new staff: %s" % [changed])
	_world.bus.staff_cards_requested.emit(0, 3, _cards("bolt"))
	check(wizard.caster.has_staff(3), "a staff the imp does not have is the wizard's to build")
	_world.run(int(1.0 / Fixture.STEP) + 1)
	check(wizard.controller == _seat(wizard), "after the possession")
	check_equal(wizard.caster.cards_of(0)[0], &"bolt", "the wizard keeps what was built")
	check_equal(imp.caster.cards_of(0), row, "and the imp its own")


func test_the_builder_edits_the_wizard_an_ai_drives_and_the_change_stays() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	Possession.begin(imp, wizard, 1.0)
	check(wizard.controller == _brain(imp), "the imp's controller drives the wizard")
	_world.bus.staff_cards_requested.emit(0, 1, _cards("fire bolt"))
	check_equal(wizard.caster.cards_of(1), _cards("fire bolt - -"), "seat 0's builder builds its own wizard")
	_world.run(int(1.0 / Fixture.STEP) + 1)
	check(wizard.controller == _seat(wizard), "after the possession")
	check_equal(wizard.caster.cards_of(1), _cards("fire bolt - -"), "nothing undoes the player's change")


# --- The HUD stays the player's ---------------------------------------------------------

## A real Hud on the world's bus and spell runtime, with seat 0 joined and a room entered.
func _hud() -> HudScript:
	var hud := (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	hud.events = _world.bus
	hud.ui_focus = own(UIFocusScript.new()) as UIFocusScript
	hud.spells = _world.spells
	root.add_child(hud)
	own(hud)
	_world.bus.player_joined.emit(0)
	_world.bus.room_entered.emit(&"arena_01")
	return hud


func test_the_panel_shows_the_home_wizards_live_health_while_the_seat_drives_an_imp() -> void:
	var hud := _hud()
	var wizard := _world.wizard(0, Vector2.ZERO, [[&"bolt"], [], [], []])
	var imp := _imp(Vector2(0.0, 60.0), [[&"bolt"], [&"bolt"]])
	var panel := hud.get_panel(0)
	check_equal(panel.health(), 100, "the panel starts with the wizard's health")
	Possession.begin(wizard, imp, SECONDS)
	_world.run(2)
	check(imp.controller == _seat(wizard), "seat 0 drives the imp")
	check_equal(panel.health(), 100, "the panel still shows the wizard, not the imp's 50")
	_world.hurt(wizard, 30)
	check_equal(panel.health(), 70, "a hit on the standing wizard shows on its player's panel at once")
	_world.hurt(imp, 10)
	check_equal(panel.health(), 70, "a hit on the imp does not")
	check_equal(panel.shown_rows(), 1, "the rows are the wizard's one staff, not the imp's two")
	# The rows' timing is read by the wizard's actor id, not the imp's the seat drives.
	check_equal(_world.spells.home_of_seat(0), wizard.id, "Spells finds seat 0's own wizard for the rows' timing")
	check_equal(_world.table.actor_of_seat(0), imp.id, "while the seat drives the imp")
	_tap(0, &"staff_1")
	_world.run(1)
	hud.step_staffs()
	check(imp.caster.mana < imp.caster.max_mana, "seat 0's button casts the imp's staff")
	check_equal(wizard.caster.mana, wizard.caster.max_mana, "not the wizard's")


func test_the_panel_keeps_the_players_live_stats_while_an_ai_drives_the_wizard() -> void:
	var hud := _hud()
	var wizard := _world.wizard(0, Vector2.ZERO, [[&"bolt"], [], [], []])
	var imp := _imp(Vector2(0.0, 80.0), [[&"possess", &"bolt"]])
	var brain := _brain(imp)
	var panel := hud.get_panel(0)
	Possession.begin(imp, wizard, SECONDS)
	check(wizard.controller == brain, "the imp's controller drives the wizard")
	_world.hurt(wizard, 25, imp.id)
	check_equal(panel.health(), 75, "the wizard's hit shows on its player's panel while the AI drives it")
	# The AI casts the wizard's staff: its mana drops, and the panel's mana follows.
	_stats.clear()
	brain.presses = [0]
	_world.run(1)
	check(wizard.caster.mana < wizard.caster.max_mana, "the AI cast the wizard's staff")
	var mana_label := panel.find_child("ManaValue", true, false) as Label
	check_equal(mana_label.text, str(floori(wizard.caster.mana)), "the panel's mana is the wizard's, live")
	var before: int = floori(wizard.caster.mana)
	_world.run(16)
	check(floori(wizard.caster.mana) > before and mana_label.text == str(floori(wizard.caster.mana)),
		"and its regen too, with no seat driving it: %s" % mana_label.text)
	check_equal(panel.status_text(), "", "no possessed word on the panel")
	check(not _stats.is_empty() and _stats.back()[0] == 0, "sent for seat 0")


# --- The look over a possessed actor ----------------------------------------------------

func _look(body: Actor) -> PossessedLook:
	for child in body.get_children():
		if child is PossessedLook and not child.is_queued_for_deletion():
			return child as PossessedLook
	return null


func test_the_look_draws_bars_and_timer_over_a_seat_driven_imp() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	check(_look(imp) == null, "nothing is drawn over an imp nobody possesses")
	Possession.begin(wizard, imp, 2.0)
	var look := _look(imp)
	check(look != null and look.shows_bars(), "a seat-driven imp gets the bars")
	imp.step(Fixture.STEP)
	check(look.draws_bars(), "which are drawn")
	check_equal(look.health_pixels(), PossessedLook.BAR_WIDTH, "a full health bar")
	check_equal(look.mana_pixels(), PossessedLook.BAR_WIDTH, "a full mana bar")
	_world.hurt(imp, 25, wizard.id)
	check_equal(look.health_pixels(), PossessedLook.BAR_WIDTH / 2, "half health, half the bar")
	var steps: int = look.drawn_steps()
	check(steps > 0 and steps <= PossessedLook.ARC_STEPS, "the timer is drawn: %d" % steps)
	_world.run(int(1.0 / Fixture.STEP))
	imp.step(0.0)
	check(look.drawn_steps() < steps and look.drawn_steps() > 0, "the timer runs down: %d" % look.drawn_steps())
	_world.run(int(1.0 / Fixture.STEP) + 1)
	check(_look(imp) == null, "the look goes when the possession ends")


func test_the_look_draws_only_a_timer_over_an_ai_driven_wizard() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	check(_look(wizard) == null, "nothing over a wizard nobody possesses")
	Possession.begin(imp, wizard, 2.0)
	var look := _look(wizard)
	check(look != null, "a look over the possessed wizard")
	wizard.step(Fixture.STEP)
	check(not look.shows_bars() and not look.draws_bars(), "with no bars (its numbers are on its panel)")
	check(look.drawn_steps() > 0, "only the timer")
	check(_look(imp) == null, "and nothing over the imp's standing body")


# --- drive ---------------------------------------------------------------------------------

func test_drive_never_leaves_a_controller_on_two_bodies() -> void:
	var wizard := _world.wizard(0)
	var imp := _imp(Vector2(0.0, 60.0))
	var seat := _seat(wizard)
	imp.drive(seat)
	check(wizard.controller == null, "taken off the wizard")
	check(seat.driving == imp, "it drives the imp")
	check(not wizard.caster.cast_done.is_connected(seat._on_cast_done), "the wizard's casts are not bound to it")
	check(wizard.health.changed.is_connected(seat._on_health_changed), "its health stays bound (the panel is the wizard's)")
	check(imp.caster.cast_done.is_connected(seat._on_cast_done), "the imp's is")
	check_equal(_world.table.seat_of(wizard.id), ActorsScript.NONE, "the wizard has no seat in the table")
	wizard.drive(seat)
	check(imp.controller == null and wizard.controller == seat, "and back, never on both")
	check(not imp.caster.cast_done.is_connected(seat._on_cast_done), "the imp's caster is let go")
	_stats.clear()
	_world.hurt(imp, 5)
	check(_stats.is_empty(), "the imp's hits are not the seat's: %s" % [_stats])
	_world.hurt(wizard, 5)
	check(not _stats.is_empty() and _stats.back() == [0, 95, 100], "the wizard's are, once each")
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
	check(_seat(wizard).is_set_aside(), "seat 0 is set aside")
	var look: PossessedLook = _look(wizard)
	check(look != null and not look.shows_bars(), "only the timer is drawn over the wizard")
	check_equal(_world.table.actor_of_seat(0), ActorsScript.NONE, "seat 0 drives nothing")
	_world.run(int(SECONDS / Fixture.STEP) + 1)
	check(wizard.controller == _seat(wizard), "the seat comes back at the end")
	check(imp.controller == mind, "and the AI goes home")
