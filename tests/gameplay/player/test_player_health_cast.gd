extends "res://tests/support/suite.gd"
## Tests for gameplay/player (health, mana, downed, revive and cast), one behaviour per test, with
## two players (and four) at once: a hit, downing and reviving one never touches the other; the
## cast goes through `Spells.cast_staff(caster, staff, ...)` (staff A, button `staff_1`, here) and
## sends spell_cast; a tap just before a spell is ready is buffered; a missing cast sound is
## silent. The wizard is the actor of content/wizard/base/wizard.tscn (actors G7): its Health,
## Caster and Downed, its seat the PlayerController.
##
## Each test gets a fresh world (wizard_fixture.gd) on the stand-in spell runtime
## (fixtures/fake_spells.gd), so only the wizard is under test; it records the caster number (the
## wizard's actor id) of every cast. The registry is never scanned: it knows no sounds. Input goes
## through virtual devices; time moves by fixed binary-fraction deltas. Health's own clamping and
## protection are tested on a bare actor in tests/gameplay/actor/test_actor_health.gd.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/gameplay/player/test_player_health_cast.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

## Any staff the stand-in builds.
const CARDS: Array[StringName] = [&"bolt"]

var _world: Fixture
var _fake: Fixture.FakeSpells
var _players: Array[Actor] = []
var _downed: Array[int] = []
var _revived: Array[Vector2i] = []
var _casts: Array[int] = []
var _cast_ids: Array[StringName] = []


func before_each() -> void:
	_world = Fixture.new(root, true)
	_fake = _world.fake
	_players.clear()
	_downed.clear()
	_revived.clear()
	_casts.clear()
	_cast_ids.clear()
	_world.bus.player_downed.connect(func(p: int) -> void: _downed.append(p))
	_world.bus.player_revived.connect(func(p: int, r: int) -> void: _revived.append(Vector2i(p, r)))
	_world.bus.spell_cast.connect(func(p: int, id: StringName, _o: Vector2, _d: Vector2) -> void:
		_casts.append(p)
		_cast_ids.append(id))


func after_each() -> void:
	_world.free_all()


## `count` wizards, seats 0 up, side by side. Returns the first.
func _wizards(count: int) -> Actor:
	for index in count:
		_players.append(_world.wizard(index, Vector2(40.0 * index, 0.0)))
	return _players[0]


## Set what the next casts cost and how long they cool down, and give `player` a staff A.
func _arm(player: Actor, cost: float, cooldown: float) -> void:
	_fake.cost = cost
	_fake.cooldown_time = cooldown
	player.caster.set_staff(0, CARDS)


func _hit(target: Actor, amount: int) -> void:
	_world.hurt(target, amount, 0)


func _run(count: int) -> void:
	# The runtime ticks its cooldowns before the wizards act.
	_world.run(count)


func _revive(player: Actor, reviver: int) -> bool:
	return Fixture.downed(player).revive(reviver)


func _tap(seat: int) -> void:
	_world.hold(seat, &"staff_1")
	_world.release(seat, &"staff_1")


func _fired() -> int:
	return _fake.fired_players.size()


## The caster numbers (actor ids) of `players`, as the stand-in records them.
func _ids(players: Array[Actor]) -> Array[int]:
	var out: Array[int] = []
	for player in players:
		out.append(player.id)
	return out


# --- A fresh wizard ----------------------------------------------------------------------------


func test_a_wizard_starts_with_full_health() -> void:
	var wizard: Actor = _wizards(1)
	check_equal(wizard.health.health, wizard.health.max_health, "a wizard starts with full health")


func test_a_wizard_starts_with_full_mana() -> void:
	var wizard: Actor = _wizards(1)
	check_equal(wizard.caster.mana_of(0), wizard.caster.max_mana_of(0), "a wizard starts with full mana")


func test_a_wizard_does_not_start_downed() -> void:
	check(not _wizards(1).is_down(), "a wizard does not start downed")


# --- Hits --------------------------------------------------------------------------------------


func test_a_hit_takes_the_wizards_health() -> void:
	_wizards(2)
	_hit(_players[1], 30)
	check_equal(_players[1].health.health, _players[1].health.max_health - 30, "a hit on a wizard takes its health")


func test_a_hit_leaves_the_other_wizard_unhurt() -> void:
	_wizards(2)
	_hit(_players[1], 30)
	check_equal(_players[0].health.health, _players[0].health.max_health, "the other wizard is not hurt")


func test_a_hit_of_zero_changes_nothing() -> void:
	var wizard: Actor = _wizards(1)
	_hit(wizard, 30)
	_hit(wizard, 0)
	check_equal(wizard.health.health, wizard.health.max_health - 30, "zero damage changes nothing")


func test_a_protected_wizard_takes_no_damage() -> void:
	var wizard: Actor = _wizards(1)
	Fixture.downed(wizard).protect(1.0)
	_world.step_one(wizard)
	check(wizard.health.is_protected(), "protect makes the wizard invulnerable")
	_hit(wizard, 40)
	check_equal(wizard.health.health, wizard.health.max_health, "no damage while invulnerable")


# --- Downed ------------------------------------------------------------------------------------


func test_one_health_left_is_not_downed() -> void:
	var wizard: Actor = _wizards(1)
	_hit(wizard, wizard.health.max_health - 1)
	check(not wizard.is_down() and _downed.is_empty(), "1 health left is not downed")


func test_zero_health_downs_the_wizard() -> void:
	var wizard: Actor = _wizards(1)
	_hit(wizard, 500)
	check_equal(wizard.health.health, 0, "health stops at 0")
	check(wizard.is_down(), "0 health downs the wizard")


func test_player_downed_is_sent_once_for_the_downed_player() -> void:
	_wizards(2)
	_hit(_players[0], 500)
	check_equal(_downed, [0] as Array[int], "player_downed is sent once, for player 0")


func test_a_downed_wizard_is_not_downed_again() -> void:
	var wizard: Actor = _wizards(1)
	_hit(wizard, 500)
	_hit(wizard, 10)
	check_equal(_downed, [0] as Array[int], "a downed wizard is not downed again")


func test_a_downed_wizard_leaves_the_other_standing() -> void:
	_wizards(2)
	_hit(_players[0], 500)
	check(not _players[1].is_down(), "the other wizard stays up")


func test_a_downed_wizard_does_not_die() -> void:
	var wizard: Actor = _wizards(1)
	_hit(wizard, 500)
	check(is_instance_valid(wizard) and not wizard.is_dying(), "a downed wizard does not die")


## Two wizards, the first armed and downed; both hold right (and the first its staff) for 4 steps.
func _downed_one_holding() -> void:
	_wizards(2)
	_arm(_players[0], 1.0, 0.0)
	_hit(_players[0], 1000)
	_world.hold(0, &"move_right")
	_world.hold(0, &"staff_1")
	_world.hold(1, &"move_right")
	_run(4)


func test_a_downed_wizard_does_not_move() -> void:
	_downed_one_holding()
	check_equal(_players[0].velocity, Vector2.ZERO, "a downed wizard does not move")


func test_a_downed_wizard_holding_its_staff_does_not_cast() -> void:
	_downed_one_holding()
	check(_fake.fired_players.is_empty() and _casts.is_empty(), "a downed wizard does not cast")


func test_cast_on_a_downed_wizard_is_refused() -> void:
	_downed_one_holding()
	check(not _players[0].caster.cast(0), "cast() on a downed wizard returns false")


func test_the_other_wizard_still_walks_while_one_is_down() -> void:
	_downed_one_holding()
	check_equal(_players[1].velocity, Vector2(_players[1].mover.speed, 0.0), "the other wizard still walks")


func test_a_downed_wizard_does_not_regenerate_mana() -> void:
	var wizard: Actor = _wizards(1)
	_arm(wizard, 10.0, 1.0)
	check(wizard.caster.cast(0), "a cast fires before the hit")
	_hit(wizard, wizard.health.max_health)
	var mana: float = wizard.caster.mana_of(0)
	_run(16)
	check_equal(wizard.caster.mana_of(0), mana, "a downed wizard does not regenerate mana")


func test_the_cooldown_runs_while_downed() -> void:
	var wizard: Actor = _wizards(1)
	_arm(wizard, 10.0, 1.0)
	wizard.caster.cast(0)
	_hit(wizard, wizard.health.max_health)
	_run(16)
	_revive(wizard, 1)
	check(wizard.caster.cast(0), "the cooldown ran in the runtime meanwhile, so the revived wizard casts")


# --- Revive ------------------------------------------------------------------------------------


## Two wizards, the first armed, downed with its staff pressed for 2 steps, then let go.
func _downed_one_pressed() -> Actor:
	_wizards(2)
	_arm(_players[0], 1.0, 0.0)
	_hit(_players[0], 1000)
	_world.hold(0, &"staff_1")
	_run(2)
	_world.release(0, &"staff_1")
	return _players[0]


func test_reviving_a_downed_wizard_succeeds() -> void:
	check(_revive(_downed_one_pressed(), 1), "revive returns true for a downed wizard")


func test_player_revived_names_the_player_and_the_reviver() -> void:
	_revive(_downed_one_pressed(), 1)
	check_equal(_revived, [Vector2i(0, 1)] as Array[Vector2i], "player_revived carries the player and the reviver")


func test_a_revive_gives_revive_health() -> void:
	var wizard: Actor = _downed_one_pressed()
	_revive(wizard, 1)
	check_equal(wizard.health.health, Downed.REVIVE_HEALTH, "a revive gives REVIVE_HEALTH")


func test_a_revived_wizard_is_up() -> void:
	var wizard: Actor = _downed_one_pressed()
	_revive(wizard, 1)
	check(not wizard.is_down(), "a revived wizard is up")


func test_a_revived_wizard_walks_again() -> void:
	var wizard: Actor = _downed_one_pressed()
	_revive(wizard, 1)
	_world.hold(0, &"move_down")
	_run(1)
	check_equal(wizard.velocity, Vector2(0.0, wizard.mover.speed), "a revived wizard walks again")


func test_a_cast_pressed_while_downed_is_not_saved_for_the_revive() -> void:
	var wizard: Actor = _downed_one_pressed()
	_revive(wizard, 1)
	_run(1)
	check(_fake.fired_players.is_empty(), "a cast pressed while downed is not saved")


func test_a_revived_wizard_can_be_hurt_again() -> void:
	var wizard: Actor = _downed_one_pressed()
	_revive(wizard, 1)
	# Combat takes the revived wizard as hurtable again from its next step (a hit between the
	# revive and that step is refused), so one step runs first.
	_run(1)
	_hit(wizard, 10)
	check_equal(wizard.health.health, Downed.REVIVE_HEALTH - 10, "a revived wizard can be hurt again")


func test_reviving_a_standing_wizard_is_refused() -> void:
	var wizard: Actor = _wizards(2)
	_hit(wizard, 10)
	check(not _revive(wizard, 1), "reviving a standing wizard returns false")


func test_reviving_a_standing_wizard_changes_nothing() -> void:
	var wizard: Actor = _wizards(2)
	_hit(wizard, 10)
	_revive(wizard, 1)
	check(wizard.health.health == wizard.health.max_health - 10 and _revived.is_empty(), "the health and the events are unchanged")


# --- Mana --------------------------------------------------------------------------------------


func test_a_cast_takes_the_spells_cost() -> void:
	var wizard: Actor = _wizards(1)
	_arm(wizard, 40.0, 0.0)
	check(wizard.caster.cast(0), "a cast with full mana fires")
	check_equal(wizard.caster.mana_of(0), wizard.caster.max_mana_of(0) - 40.0, "a cast takes the spell's cost")


func test_mana_regenerates_per_second() -> void:
	var caster: Caster = _wizards(1).caster
	_arm(_players[0], 40.0, 0.0)
	caster.cast(0)
	_run(16)  # one second
	check_equal(caster.mana_of(0), caster.max_mana_of(0) - 40.0 + caster.staff_of(0).mana_regen, "mana regenerates per second")


func test_mana_stops_at_the_maximum() -> void:
	var caster: Caster = _wizards(1).caster
	_arm(_players[0], 40.0, 0.0)
	caster.cast(0)
	_run(16 * 21)
	check_equal(caster.mana_of(0), caster.max_mana_of(0), "mana stops at the maximum")


func test_a_cast_without_enough_mana_is_refused() -> void:
	var caster: Caster = _wizards(1).caster
	_arm(_players[0], 60.0, 0.0)
	check(caster.cast(0), "first cast fires")
	check(not caster.cast(0), "a second cast without enough mana is refused")


func test_a_refused_cast_sends_nothing() -> void:
	var caster: Caster = _wizards(1).caster
	_arm(_players[0], 60.0, 0.0)
	caster.cast(0)
	caster.cast(0)
	check(_fired() == 1 and _casts.size() == 1, "a refused cast sends nothing")


func test_a_refused_cast_takes_no_mana() -> void:
	var caster: Caster = _wizards(1).caster
	_arm(_players[0], 60.0, 0.0)
	caster.cast(0)
	caster.cast(0)
	check_equal(caster.mana_of(0), caster.max_mana_of(0) - 60.0, "a refused cast takes no mana")


# --- Casting -----------------------------------------------------------------------------------


## Two wizards; the second, armed, holds its staff for one step of its own.
func _second_holds_its_staff() -> void:
	_wizards(2)
	_arm(_players[1], 10.0, 0.0)
	_world.hold(1, &"staff_1")
	_world.step_one(_players[1])


func test_holding_a_staff_casts_it_for_the_wizards_own_caster() -> void:
	_second_holds_its_staff()
	check_equal(_fake.fired_players, [_players[1].id], "holding cast calls the runtime for this wizard's caster number")
	check_equal(_fake.fired_slots, [0], "and for the active slot")


func test_spell_cast_names_the_player_and_the_carrier() -> void:
	_second_holds_its_staff()
	check(_casts == [1] and _cast_ids == [&"bolt"], "spell_cast is sent with the player and the carrier card id: %s %s" % [_casts, _cast_ids])


func test_a_cast_takes_only_its_own_wizards_mana() -> void:
	_second_holds_its_staff()
	check(_players[1].caster.mana_of(0) < _players[1].caster.max_mana_of(0), "the cast took mana")
	check_equal(_players[0].caster.mana_of(0), _players[0].caster.max_mana_of(0), "the other wizard's mana is untouched")


## A wizard against the left side of a wall from x = 96 to 128, armed; the origins of its casts.
func _against_a_wall(origins: Array[Vector2]) -> Actor:
	var wizard: Actor = _wizards(1)
	var wall: Array[Rect2] = [Rect2(96.0, 0.0, 32.0, 360.0)]
	_world.projectiles.set_walls(wall)
	wizard.global_position = Vector2(94.0, 200.0)
	wizard.aim = Vector2.RIGHT
	_world.bus.spell_cast.connect(func(_p: int, _id: StringName, origin: Vector2, _d: Vector2) -> void: origins.append(origin))
	_arm(wizard, 1.0, 0.0)
	return wizard


func test_a_wizard_against_a_wall_still_casts() -> void:
	var origins: Array[Vector2] = []
	var wizard: Actor = _against_a_wall(origins)
	check(wizard.muzzle_position().x > 96.0, "the staff tip is behind the wall (%s)" % wizard.muzzle_position())
	check(wizard.caster.cast(0), "a wizard against a wall still casts")


func test_a_shot_aimed_into_a_wall_starts_in_front_of_it() -> void:
	var origins: Array[Vector2] = []
	_against_a_wall(origins).caster.cast(0)
	check(origins.size() == 1 and origins[0].x <= 96.01, "the shot starts in front of the wall (%s)" % [origins])


func test_a_shot_aimed_away_from_a_wall_starts_at_the_staff_tip() -> void:
	var origins: Array[Vector2] = []
	var wizard: Actor = _against_a_wall(origins)
	wizard.aim = Vector2.LEFT
	wizard.caster.cast(0)
	check(origins.size() == 1 and absf(origins[0].x - wizard.muzzle_position().x) < 0.01, "away from the wall the muzzle is where the staff points (%s)" % [origins])


func test_a_held_cast_fires_once_per_cooldown() -> void:
	_arm(_wizards(1), 1.0, 0.25)
	_world.hold(0, &"staff_1")
	_run(8)  # 0.5 s held: fires at 0 s and again once the 0.25 s cooldown is over
	check_equal(_fired(), 2, "a held cast fires once per cooldown")


func test_every_cast_sends_one_spell_cast() -> void:
	_arm(_wizards(1), 1.0, 0.25)
	_world.hold(0, &"staff_1")
	_run(8)
	check_equal(_casts.size(), _fired(), "one spell_cast per cast")
	check_equal(_casts.size(), 2, "two casts were sent")


func test_without_a_spell_nothing_is_cast() -> void:
	var wizard: Actor = _wizards(1)
	_world.hold(0, &"staff_1")
	_run(2)
	check(_casts.is_empty() and not wizard.caster.cast(0), "without a spell nothing is cast")


func test_a_wizard_with_empty_staffs_has_no_build() -> void:
	check(not _wizards(1).caster.has_staff(0), "a wizard with empty staffs has no build")


func test_a_player_with_an_overlay_open_does_not_cast() -> void:
	_wizards(2)
	_arm(_players[0], 1.0, 0.0)
	_arm(_players[1], 1.0, 0.0)
	_world.hold(0, &"staff_1")
	_world.hold(1, &"staff_1")
	_world.input.set_captured(0, true)
	_run(1)
	check_equal(_fake.fired_players, [_players[1].id], "a player with an overlay open does not cast; the other does")


# --- The input buffer --------------------------------------------------------------------------
# A tap of `cast` within INPUT_BUFFER of the spell being ready fires when it is; an earlier tap and
# a tap made in an overlay do not carry over.


## A wizard that cast a spell of `cooldown` and stepped twice since (0.125 s).
func _cooling(cooldown: float) -> Actor:
	var wizard: Actor = _wizards(1)
	_arm(wizard, 1.0, cooldown)
	check(wizard.caster.cast(0), "the first cast fires")
	_run(2)
	return wizard


func test_a_tap_is_not_used_while_the_spell_cools_down() -> void:
	_cooling(0.25)
	_tap(0)
	_run(1)
	check_equal(_fired(), 1, "the tap is not used while the spell cools down")


func test_a_tap_just_before_the_spell_is_ready_fires_when_it_is() -> void:
	_cooling(0.25)
	_tap(0)
	_run(2)
	check_equal(_fired(), 2, "a tap just before the spell is ready fires when it is")


func test_a_buffered_tap_fires_once() -> void:
	_cooling(0.25)
	_tap(0)
	_run(10)
	check_equal(_fired(), 2, "a buffered tap fires once")


func test_a_tap_longer_ago_than_the_buffer_is_dropped() -> void:
	_cooling(0.5)  # 0.375 s left
	_tap(0)
	_run(8)
	check_equal(_fired(), 1, "a tap longer ago than INPUT_BUFFER is dropped")


func test_a_tap_made_in_an_overlay_is_not_buffered() -> void:
	_cooling(0.25)
	_world.input.set_captured(0, true)
	_tap(0)
	_run(1)
	_world.input.set_captured(0, false)
	_run(3)
	check_equal(_fired(), 1, "a tap made in an overlay is not buffered")


func test_a_press_that_fired_while_held_leaves_no_buffered_cast() -> void:
	_cooling(0.25)
	_world.hold(0, &"staff_1")  # held until the spell is ready
	_run(2)
	_world.release(0, &"staff_1")
	var fired: int = _fired()
	_run(1)
	check_equal(_fired(), fired, "a tap that fired while held leaves no buffered cast")


# --- The cast sound ----------------------------------------------------------------------------


func test_a_cast_with_no_cast_sound_is_still_sent() -> void:
	var wizard: Actor = _wizards(1)
	check(_world.registry.get_sound(PlayerController.CAST_SOUND_ID) == null, "the test registry has no cast sound")
	_arm(wizard, 1.0, 0.0)
	check(wizard.caster.cast(0), "a cast with no sound still fires")
	check_equal(_casts.size(), 1, "the seat still sends it")


func test_a_cast_with_no_registry_is_still_sent() -> void:
	var wizard: Actor = _wizards(1)
	_arm(wizard, 1.0, 0.0)
	Fixture.controller(wizard).registry = null
	check(wizard.caster.cast(0), "a cast without a registry still fires")
	check_equal(_casts.size(), 1, "the seat still sends it")


func test_inside_the_tree_the_seat_has_a_sound_player() -> void:
	# The fixture's wizards are in the tree.
	check(Fixture.controller(_wizards(1))._sound_player != null, "inside the tree the seat has a sound player")


func test_a_missing_cast_sound_plays_nothing() -> void:
	var wizard: Actor = _wizards(1)
	var seat: PlayerController = Fixture.controller(wizard)
	_arm(wizard, 1.0, 0.0)
	check(wizard.caster.cast(0), "a cast with the sound player but no sound fires")
	check(seat._sound_player != null and not seat._sound_player.playing, "and plays nothing")


# --- Several players ---------------------------------------------------------------------------


## Two armed wizards both holding their staff, the first downed before the first step.
func _two_casting_one_downed() -> void:
	_wizards(2)
	_arm(_players[1], 10.0, 0.5)
	_arm(_players[0], 10.0, 0.5)
	_world.hold(0, &"staff_1")
	_world.hold(1, &"staff_1")
	_hit(_players[0], 1000)
	_run(1)


func test_a_downed_player_does_not_cast_while_the_other_does() -> void:
	_two_casting_one_downed()
	check_equal(_fake.fired_players, [_players[1].id], "downed player 0 does not cast; player 1 casts at the same time")


func test_a_revived_player_casts_again() -> void:
	_two_casting_one_downed()
	_revive(_players[0], 1)
	_run(1)
	check_equal(_fake.fired_players, [_players[1].id, _players[0].id], "player 0 casts again after the revive")


func test_casting_costs_mana_not_health() -> void:
	_two_casting_one_downed()
	check(_players[1].caster.mana_of(0) < _players[1].caster.max_mana_of(0), "player 1 lost mana")
	check_equal(_players[1].health.health, _players[1].health.max_health, "player 1 lost no health")


## Four armed wizards that each held their staff for one step.
func _four_casting() -> void:
	_wizards(4)
	for at in _players.size():
		_arm(_players[at], 10.0, 1.0)  # one runtime for all: cooldowns are per caster
		_world.hold(at, &"staff_1")
	_run(1)


func test_four_wizards_each_cast_once() -> void:
	_four_casting()
	check_equal(_fake.fired_players, _ids(_players), "four wizards each cast once")


func test_each_of_four_seats_sends_its_own_spell_cast() -> void:
	_four_casting()
	check_equal(_casts, [0, 1, 2, 3] as Array[int], "each seat sends its own spell_cast")


func test_downed_and_revived_events_name_the_right_players() -> void:
	_four_casting()
	_hit(_players[3], 1000)
	_hit(_players[2], 1000)
	_revive(_players[2], 0)
	check_equal(_downed, [3, 2] as Array[int], "player_downed names the downed players")
	check_equal(_revived, [Vector2i(2, 0)] as Array[Vector2i], "player_revived names the revived player and the reviver")


func test_downing_two_of_four_wizards_leaves_the_others_untouched() -> void:
	_four_casting()
	_hit(_players[3], 1000)
	_hit(_players[2], 1000)
	check(_players[0].health.health == _players[0].health.max_health and _players[1].health.health == _players[1].health.max_health,
		"players 0 and 1 are untouched")
