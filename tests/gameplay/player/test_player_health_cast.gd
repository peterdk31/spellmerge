extends SceneTree
## Tests for gameplay/player (health, mana, downed, revive and cast), with two
## players (and four) at once: a hit, downing and reviving one never touches the
## other; the cast goes through `Spells.cast_staff(player, staff, ...)` (staff A, button `cast_a`,
## here) and sends spell_cast;
## a missing cast sound is silent. The spell runtime is a stand-in (fixtures/fake_spells.gd),
## so only the wizard is under test. Input goes through virtual devices; time moves
## by fixed binary-fraction deltas.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_health_cast.gd

const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FakeSpells := preload("res://tests/gameplay/player/fixtures/fake_spells.gd")

const STEP: float = 0.0625
## Any staff the stand-in builds.
const CARDS: Array[StringName] = [&"bolt"]

var _failures: Array[String] = []
var _bus: Node
var _input: Node
var _registry: Node
var _fake: FakeSpells
var _players: Array[PlayerScript] = []
var _downed: Array[int] = []
var _revived: Array[Vector2i] = []
var _casts: Array[int] = []
var _cast_ids: Array[StringName] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_starts_full()
	_test_damage_event_hurts_only_the_target()
	_test_invulnerable_ignores_damage()
	_test_downed_after_zero_health()
	_test_downed_cannot_move_or_cast()
	_test_revive()
	_test_revive_of_standing_player_does_nothing()
	_test_mana_regenerates_up_to_max()
	_test_cast_spends_mana_and_sends_event()
	_test_cast_origin_stops_at_a_wall()
	_test_cast_cooldown()
	_test_cast_tap_just_before_ready_is_buffered()
	_test_cast_needs_mana()
	_test_no_spell_no_cast()
	_test_missing_sound_is_silent()
	_test_missing_sound_in_tree_is_silent()
	_test_downed_mana_freezes()
	_test_two_players_cast_and_down_independently()
	_test_four_players()
	_test_captured_player_does_not_cast()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: gameplay/player (health, mana, downed and cast)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(count: int) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_registry = RegistryScript.new()  # never scanned: knows no sounds
	_fake = FakeSpells.new()
	_bus.player_downed.connect(func(p: int) -> void: _downed.append(p))
	_bus.player_revived.connect(func(p: int, r: int) -> void: _revived.append(Vector2i(p, r)))
	_bus.spell_cast.connect(func(p: int, id: StringName, _o: Vector2, _d: Vector2) -> void:
		_casts.append(p)
		_cast_ids.append(id))
	for index in count:
		_input.add_virtual_device(index)
		var player := PlayerScript.new()
		player.index = index
		player.input = _input
		player.events = _bus
		player.registry = _registry
		player.spells = _fake
		player._ready()
		_players.append(player)


func _teardown() -> void:
	for player in _players:
		player.free()
	_players.clear()
	for node: Node in [_input, _registry, _bus, _fake]:
		if node != null:
			node.free()
	_input = null
	_registry = null
	_bus = null
	_fake = null
	_downed.clear()
	_revived.clear()
	_casts.clear()
	_cast_ids.clear()


## Set what the next casts cost and how long they cool down, and give `player` a staff A.
func _arm(player: PlayerScript, cost: float, cooldown: float) -> void:
	_fake.cost = cost
	_fake.cooldown_time = cooldown
	player.set_staff(0, CARDS)


func _hit(target: PlayerScript, amount: int) -> void:
	_bus.damage_dealt.emit(0, target, amount, Vector2.ZERO)


func _run(count: int) -> void:
	for i in count:
		_fake.step(STEP)  # the runtime ticks its cooldowns before the wizards act
		for player in _players:
			player.step(STEP)


# --- Tests ------------------------------------------------------------------

func _test_starts_full() -> void:
	_setup(1)
	_check(_players[0].health == PlayerScript.MAX_HEALTH, "a wizard starts with full health")
	_check(_players[0].mana == PlayerScript.MAX_MANA, "a wizard starts with full mana")
	_check(not _players[0].is_downed(), "a wizard does not start downed")


func _test_damage_event_hurts_only_the_target() -> void:
	_setup(2)
	_hit(_players[1], 30)
	_check(_players[1].health == PlayerScript.MAX_HEALTH - 30, "damage_dealt on a wizard takes its health")
	_check(_players[0].health == PlayerScript.MAX_HEALTH, "the other wizard is not hurt")
	_hit(_players[1], 0)
	_check(_players[1].health == PlayerScript.MAX_HEALTH - 30, "zero damage changes nothing")


func _test_invulnerable_ignores_damage() -> void:
	_setup(1)
	_players[0].protect(1.0)
	_players[0].step(STEP)
	_check(_players[0].is_invulnerable(), "protect makes the wizard invulnerable")
	_hit(_players[0], 40)
	_check(_players[0].health == PlayerScript.MAX_HEALTH, "no damage while invulnerable")


func _test_downed_after_zero_health() -> void:
	_setup(2)
	_hit(_players[0], PlayerScript.MAX_HEALTH - 1)
	_check(not _players[0].is_downed() and _downed.is_empty(), "1 health left is not downed")
	_hit(_players[0], 500)
	_check(_players[0].health == 0, "health stops at 0")
	_check(_players[0].is_downed(), "0 health downs the wizard")
	_check(_downed == [0], "player_downed is sent once, for player 0")
	_hit(_players[0], 10)
	_check(_downed == [0], "a downed wizard is not downed again")
	_check(not _players[1].is_downed(), "the other wizard stays up")


func _test_downed_cannot_move_or_cast() -> void:
	_setup(2)
	_arm(_players[0], 1.0, 0.0)
	_hit(_players[0], 1000)
	_input.send_virtual(0, &"move_right", 1.0)
	_input.send_virtual(0, &"cast_a", 1.0)
	_input.send_virtual(1, &"move_right", 1.0)
	_run(4)
	_check(_players[0].velocity == Vector2.ZERO, "a downed wizard does not move")
	_check(_fake.fired_players.is_empty() and _casts.is_empty(), "a downed wizard does not cast")
	_check(not _players[0].cast_staff(0), "cast() on a downed wizard returns false")
	_check(_players[1].velocity == Vector2(PlayerScript.MOVE_SPEED, 0.0), "the other wizard still walks")


func _test_revive() -> void:
	_setup(2)
	_arm(_players[0], 1.0, 0.0)
	_hit(_players[0], 1000)
	_input.send_virtual(0, &"cast_a", 1.0)  # pressed while downed
	_run(2)
	_input.send_virtual(0, &"cast_a", 0.0)
	_check(_players[0].revive(1), "revive returns true for a downed wizard")
	_check(_revived == [Vector2i(0, 1)], "player_revived carries the player and the reviver")
	_check(_players[0].health == PlayerScript.REVIVE_HEALTH, "a revive gives REVIVE_HEALTH")
	_check(not _players[0].is_downed(), "a revived wizard is up")
	_input.send_virtual(0, &"move_down", 1.0)
	_run(1)
	_check(_players[0].velocity == Vector2(0.0, PlayerScript.MOVE_SPEED), "a revived wizard walks again")
	_check(_fake.fired_players.is_empty(), "a cast pressed while downed is not saved")
	_hit(_players[0], 10)
	_check(_players[0].health == PlayerScript.REVIVE_HEALTH - 10, "a revived wizard can be hurt again")


func _test_revive_of_standing_player_does_nothing() -> void:
	_setup(2)
	_hit(_players[0], 10)
	_check(not _players[0].revive(1), "reviving a standing wizard returns false")
	_check(_players[0].health == PlayerScript.MAX_HEALTH - 10 and _revived.is_empty(), "and changes nothing")


func _test_mana_regenerates_up_to_max() -> void:
	_setup(1)
	_arm(_players[0], 40.0, 0.0)
	_check(_players[0].cast_staff(0), "a cast with full mana fires")
	_check(_players[0].mana == PlayerScript.MAX_MANA - 40.0, "a cast takes the spell's cost")
	_run(16)  # one second
	_check(_players[0].mana == PlayerScript.MAX_MANA - 40.0 + PlayerScript.MANA_REGEN, "mana regenerates per second")
	_run(16 * 20)
	_check(_players[0].mana == PlayerScript.MAX_MANA, "mana stops at the maximum")


func _test_cast_spends_mana_and_sends_event() -> void:
	_setup(2)
	_arm(_players[1], 10.0, 0.0)
	_input.send_virtual(1, &"cast_a", 1.0)
	_players[1].step(STEP)
	_check(_fake.fired_players == [1], "holding cast calls the runtime for this player")
	_check(_fake.fired_slots == [0], "and for the active slot")
	_check(_casts == [1] and _cast_ids == [&"bolt"], "spell_cast is sent with the player and the form id")
	_check(_players[1].mana < PlayerScript.MAX_MANA, "the cast took mana")
	_check(_players[0].mana == PlayerScript.MAX_MANA, "the other wizard's mana is untouched")


func _test_cast_origin_stops_at_a_wall() -> void:
	_setup(1)
	var manager: Node2D = ProjectileManagerScript.new()
	manager.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	# A wall from x = 96 to 128; the wizard stands against its left side.
	var wall: Array[Rect2] = [Rect2(96.0, 0.0, 32.0, 360.0)]
	manager.set_walls(wall)
	_players[0].projectiles = manager
	_players[0].global_position = Vector2(94.0, 200.0)
	_players[0].aim = Vector2.RIGHT
	var origins: Array[Vector2] = []
	_bus.spell_cast.connect(func(_p: int, _id: StringName, origin: Vector2, _d: Vector2) -> void: origins.append(origin))
	_arm(_players[0], 1.0, 0.0)
	var tip: Vector2 = _players[0].muzzle_position()
	_check(tip.x > 96.0, "the staff tip is behind the wall (%s)" % str(tip))
	_check(_players[0].cast_staff(0), "a wizard against a wall still casts")
	_check(origins.size() == 1 and origins[0].x <= 96.01, "the shot starts in front of the wall (%s)" % str(origins))
	# Aiming away from the wall is not clipped.
	_players[0].aim = Vector2.LEFT
	origins.clear()
	_players[0].cast_staff(0)
	_check(origins.size() == 1 and absf(origins[0].x - _players[0].muzzle_position().x) < 0.01, "away from the wall the muzzle is where the staff points")
	_players[0].projectiles = null
	manager.free()


func _test_cast_cooldown() -> void:
	_setup(1)
	_arm(_players[0], 1.0, 0.25)
	_input.send_virtual(0, &"cast_a", 1.0)
	_run(8)  # 0.5 s held: fires at 0 s and again once the 0.25 s cooldown is over
	_check(_fake.fired_players.size() == 2, "a held cast fires once per cooldown (got %d)" % _fake.fired_players.size())
	_check(_casts.size() == 2, "one spell_cast per cast")


## A tap of `cast` within INPUT_BUFFER of the spell being ready fires when it is;
## an earlier tap and a tap made in an overlay do not carry over.
func _test_cast_tap_just_before_ready_is_buffered() -> void:
	_setup(1)
	_arm(_players[0], 1.0, 0.25)
	_check(_players[0].cast_staff(0), "the first cast fires")
	_run(2)  # 0.125 s of the cooldown left
	_input.send_virtual(0, &"cast_a", 1.0)
	_input.send_virtual(0, &"cast_a", 0.0)
	_run(1)
	_check(_fake.fired_players.size() == 1, "the tap is not used while the spell cools down")
	_run(1)
	_check(_fake.fired_players.size() == 2, "a tap just before the spell is ready fires when it is")
	_run(8)
	_check(_fake.fired_players.size() == 2, "a buffered tap fires once")
	_setup(1)
	_arm(_players[0], 1.0, 0.5)
	_check(_players[0].cast_staff(0), "the first cast fires")
	_run(2)  # 0.375 s left
	_input.send_virtual(0, &"cast_a", 1.0)
	_input.send_virtual(0, &"cast_a", 0.0)
	_run(8)
	_check(_fake.fired_players.size() == 1, "a tap longer ago than INPUT_BUFFER is dropped")
	_setup(1)
	_arm(_players[0], 1.0, 0.25)
	_check(_players[0].cast_staff(0), "the first cast fires")
	_run(2)
	_input.set_captured(0, true)
	_input.send_virtual(0, &"cast_a", 1.0)
	_input.send_virtual(0, &"cast_a", 0.0)
	_run(1)
	_input.set_captured(0, false)
	_run(3)
	_check(_fake.fired_players.size() == 1, "a tap made in an overlay is not buffered")
	_setup(1)
	_arm(_players[0], 1.0, 0.25)
	_check(_players[0].cast_staff(0), "the first cast fires")
	_run(2)
	_input.send_virtual(0, &"cast_a", 1.0)  # held until the spell is ready
	_run(2)
	_input.send_virtual(0, &"cast_a", 0.0)
	var fired: int = _fake.fired_players.size()
	_run(1)
	_check(_fake.fired_players.size() == fired, "a tap that fired while held leaves no buffered cast")


func _test_cast_needs_mana() -> void:
	_setup(1)
	_arm(_players[0], 60.0, 0.0)
	_check(_players[0].cast_staff(0), "first cast fires")
	_check(not _players[0].cast_staff(0), "a second cast without enough mana is refused")
	_check(_fake.fired_players.size() == 1 and _casts.size() == 1, "a refused cast sends nothing")
	_check(_players[0].mana == PlayerScript.MAX_MANA - 60.0, "a refused cast takes no mana")


func _test_no_spell_no_cast() -> void:
	_setup(1)
	_input.send_virtual(0, &"cast_a", 1.0)
	_run(2)
	_check(_casts.is_empty() and not _players[0].cast_staff(0), "without a spell nothing is cast")
	_check(not _players[0].has_staff(0), "a wizard with empty staffs has no build")


func _test_missing_sound_is_silent() -> void:
	_setup(1)
	_check(_registry.get_sound(PlayerScript.CAST_SOUND_ID) == null, "the test registry has no cast sound")
	_arm(_players[0], 1.0, 0.0)
	_check(_players[0].cast_staff(0), "a cast with no sound still fires")
	_players[0].registry = null
	_check(_players[0].cast_staff(0), "a cast without a registry still fires")


func _test_missing_sound_in_tree_is_silent() -> void:
	_setup(0)
	_input.add_virtual_device(0)
	var player := PlayerScript.new()
	player.index = 0
	player.input = _input
	player.events = _bus
	player.registry = _registry
	player.spells = _fake
	root.add_child(player)  # _ready() makes the AudioStreamPlayer
	_players.append(player)
	_check(player._sound_player != null, "inside the tree the wizard has a sound player")
	_arm(player, 1.0, 0.0)
	_check(player.cast_staff(0), "a cast with the sound player but no sound fires")
	_check(player._sound_player != null and not player._sound_player.playing, "and plays nothing")


func _test_downed_mana_freezes() -> void:
	_setup(1)
	_arm(_players[0], 10.0, 1.0)
	_check(_players[0].cast_staff(0), "a cast fires before the hit")
	_hit(_players[0], PlayerScript.MAX_HEALTH)
	var mana: float = _players[0].mana
	_run(16)
	_check(_players[0].mana == mana, "a downed wizard does not regenerate mana")
	_check(not _players[0].cast_staff(0), "a downed wizard cannot cast")
	_players[0].revive(1)
	_check(_players[0].cast_staff(0), "the cooldown ran in the runtime meanwhile, so the revived wizard casts")


func _test_two_players_cast_and_down_independently() -> void:
	_setup(2)
	_arm(_players[1], 10.0, 0.5)
	_arm(_players[0], 10.0, 0.5)
	_input.send_virtual(0, &"cast_a", 1.0)
	_input.send_virtual(1, &"cast_a", 1.0)
	_hit(_players[0], 1000)
	_run(1)
	_check(_fake.fired_players == [1], "downed player 0 does not cast; player 1 casts at the same time")
	_players[0].revive(1)
	_run(1)
	_check(_fake.fired_players == [1, 0], "player 0 casts again after the revive")
	_check(_players[1].mana < PlayerScript.MAX_MANA and _players[1].health == PlayerScript.MAX_HEALTH, "player 1 lost mana, not health")


func _test_four_players() -> void:
	_setup(4)
	for player in _players:
		_arm(player, 10.0, 1.0)  # one runtime for all: cooldowns are per player
		_input.send_virtual(player.index, &"cast_a", 1.0)
	_run(1)
	_check(_fake.fired_players == [0, 1, 2, 3], "four wizards each cast once")
	_hit(_players[3], 1000)
	_hit(_players[2], 1000)
	_players[2].revive(0)
	_check(_downed == [3, 2] and _revived == [Vector2i(2, 0)], "downed and revived events name the right players")
	_check(_players[0].health == PlayerScript.MAX_HEALTH and _players[1].health == PlayerScript.MAX_HEALTH, "players 0 and 1 are untouched")


func _test_captured_player_does_not_cast() -> void:
	_setup(2)
	_arm(_players[0], 1.0, 0.0)
	_arm(_players[1], 1.0, 0.0)
	_input.send_virtual(0, &"cast_a", 1.0)
	_input.send_virtual(1, &"cast_a", 1.0)
	_input.set_captured(0, true)
	_run(1)
	_check(_fake.fired_players == [1], "a player with an overlay open does not cast; the other does")
