extends "res://tests/support/suite.gd"
## The Teleport card (content/spells/carriers/teleport/, staffs C): a carrier that blinks the caster a
## fixed distance the way its body walks (along the aim standing). The engine side is tested in `tests/core/test_spells_moves.gd`
## and `tests/gameplay/player/test_player_caster.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://content/spells/carriers/teleport/test_teleport.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["teleport_away", "teleport_and_fire", "shield_teleport"]


func _card() -> FormBase:
	return load("res://content/spells/carriers/teleport/teleport.tres") as FormBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `cards` from `seat` and returns the moves asked of the caster as [actor, mode, to, seconds].
func _moves(cards: Array, seat: int = 0) -> Array:
	var arena := ArenaScript.new(root)
	var moves: Array = []
	arena.bus.caster_move_requested.connect(func(actor: int, mode: StringName, to: Vector2, seconds: float, _tag: int) -> void:
		moves.append([actor, mode, to, seconds]))
	arena.place_caster(seat, Vector2.ZERO)
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	arena.run(0.5)
	arena.free_all()
	return moves


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "teleport.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"teleport", "its id is its folder")
	check_equal(card.kind(), &"form", "a carrier card")
	check_equal(card.carrier, &"teleport", "it is a teleport")
	check(card.ray_length > 0.0, "it has a distance")
	check_equal(card.speed, 0.0, "speed is a placeholder: the distance is ray_length alone")
	check(card.mana_cost > 0.0, "it costs mana, which a dash does not")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_exist() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_a_cast_blinks_the_caster_the_card_s_distance() -> void:
	var card: FormBase = _card()
	var moves: Array = _moves(["teleport"])
	check_equal(moves.size(), 1, "one move is asked")
	if moves.is_empty() or card == null:
		return
	check_equal(moves[0][1], &"teleport", "a teleport")
	check_equal(moves[0][3], 0.0, "at once")
	var away: float = Vector2.ZERO.distance_to(moves[0][2] as Vector2)
	check(absf(away - card.ray_length) < 0.5, "the card's distance away (%s of %s)" % [away, card.ray_length])


func test_a_cast_without_the_card_asks_for_no_move() -> void:
	check(_moves(["fire", "bolt"]).is_empty(), "a bolt moves nobody")


func test_four_players_blink_each() -> void:
	for seat in 4:
		var moves: Array = _moves(["teleport"], seat)
		check_equal(moves.size(), 1, "player %d blinks once" % seat)
		if not moves.is_empty():
			check_equal(moves[0][1], &"teleport", "player %d: a teleport" % seat)


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/carriers/teleport/teleport.tres") as FormBase
	check_equal(card.shown_cue, &"vanish", "its shown plays vanish")
	check_equal(card.end_cue, &"appear", "its end plays appear")


# --- Homing: a flicker strike (owner, 2026-11-06) -------------------------------------------------

const World := preload("res://tests/support/card_rules_world.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
## The enemies of the flicker scene: all within a homing teleport's reach of the wizard's body.
const FOES: Array[Vector2] = [Vector2(70.0, 30.0), Vector2(120.0, -60.0), Vector2(-40.0, 90.0)]


## A world with the wizard's first staff `cards`, pressed once at the first step, and an enemy at
## each of `foes`: [world, wizard, enemies].
func _flicker_world(cards: Array[StringName], foes: Array[Vector2] = FOES) -> Array:
	var registry: Node = own(RegistryScript.new()) as Node
	registry.call("scan")
	var shelf := own(World.Shelf.new()) as World.Shelf
	shelf.base = registry
	var staff := StaffBase.new()
	staff.id = &"flicker"
	staff.slots = 16
	staff.cooldown = 0.0
	var world := World.new(root, shelf, staff)
	var wizard: Actor = world.add_wizard(cards)
	var enemies: Array[Node2D] = []
	for at in foes:
		enemies.append(world.add_enemy(&"E", at))
	world.press()
	return [world, wizard, enemies]


## How many of `enemies` lost health.
static func _hurt(world: World, enemies: Array[Node2D]) -> int:
	var hurt: int = 0
	for enemy in enemies:
		if world.combat.health_of(enemy) < World.HEALTH:
			hurt += 1
	return hurt


func test_a_homing_teleport_lands_on_a_target_in_reach_and_strikes_it() -> void:
	# Before: it blinked its card's distance toward the farther target and its strike missed.
	var made: Array = _flicker_world([&"homing", &"teleport"], [Vector2(120.0, -60.0)])
	var world: World = made[0]
	var wizard: Actor = made[1]
	var enemy: Node2D = (made[2] as Array[Node2D])[0]
	# A staff that reaches ahead of the hand, as a wizard's does: the cast leaves from its tip.
	wizard.staff_reach = 14.0
	# Where the wizard's body (its centre) landed from the enemy's hurt circle, as it lands.
	var gap: Array[float] = [-1.0]
	world.bus.caster_move_finished.connect(func(_actor: int, _mode: StringName, _at: Vector2, _tag: int) -> void:
		gap[0] = (wizard.global_position + wizard.body_offset).distance_to(enemy.global_position + (enemy as Actor).body_offset))
	world.run(0.5, 0.5)
	check(world.combat.health_of(enemy) < World.HEALTH, "its landing strike hit the target (health %s)" % world.combat.health_of(enemy))
	# Measured from the body it moves, not the staff tip it is cast from: the body's centre lands at
	# the target's edge, LAND_CLEARANCE short of it.
	var hurtbox := Hurtbox.new()
	var want: float = hurtbox.radius + SpellLimits.LAND_CLEARANCE
	hurtbox.free()
	check(absf(gap[0] - want) < 1.0, "the wizard's body lands at the target's edge: %s px from its centre, want %s" % [gap[0], want])
	world.free_all()


## Owner, 2026-11-06: with no target in reach a homing teleport teleports in place: the wizard stays
## where it is, but the cast happens and the teleport lands there, so what it carries goes off.
func test_a_homing_teleport_with_no_target_in_reach_teleports_in_place() -> void:
	var made: Array = _flicker_world([&"on_expire", &"homing", &"teleport", &"swing"], [Vector2(600.0, 0.0)])
	var world: World = made[0]
	var wizard: Actor = made[1]
	var start: Vector2 = wizard.global_position
	var landed: Array[int] = [0]
	var swung: Array[int] = [0]
	world.bus.caster_move_finished.connect(func(actor: int, mode: StringName, _at: Vector2, _tag: int) -> void:
		if mode == &"teleport" and actor == wizard.id:
			landed[0] += 1)
	# The swing its landing casts: a live sweep of the wizard's, seen as the world steps.
	var swings: CarrierSwing = world.spells.carrier(&"swing") as CarrierSwing
	for i in 8:
		world.run(0.0625, 0.0625)
		for at in swings.swing_slots():
			if swings.swing_on(at) and swings.swing_actor(at) == wizard.id:
				swung[0] += 1
	check(wizard.global_position.is_equal_approx(start), "it stays where it is: %s" % wizard.global_position)
	check(landed[0] >= 1, "but it teleported, in place")
	check(swung[0] >= 1, "and its landing's payload went off there (the swing)")
	world.free_all()


func test_a_plain_teleport_still_blinks_its_distance_along_the_aim() -> void:
	var made: Array = _flicker_world([&"teleport"])
	var world: World = made[0]
	var wizard: Actor = made[1]
	var start: Vector2 = wizard.global_position
	world.run(0.5, 0.5)
	var moved: Vector2 = wizard.global_position - start
	check(is_equal_approx(moved.length(), _card().ray_length) and absf(moved.angle()) < 0.01, "its card's distance along +x: %s" % moved)
	world.free_all()


func test_the_flicker_strike_hops_from_enemy_to_enemy() -> void:
	# Each landing hit fires the next blink (`on hit`), cast by the wizard's body where it landed.
	var made: Array = _flicker_world([&"on_hit", &"homing", &"teleport", &"on_hit", &"homing", &"teleport", &"homing", &"teleport", &"swing"])
	var world: World = made[0]
	var wizard: Actor = made[1]
	var blinks: Array[int] = [0]
	world.bus.caster_move_requested.connect(func(actor: int, mode: StringName, _move: Vector2, _seconds: float, _tag: int) -> void:
		if mode == &"teleport" and actor == wizard.id:
			blinks[0] += 1)
	world.run(0.5, 0.5)
	check_equal(blinks[0], 3, "one press, three blinks: each landing hit fires the next")
	check(_hurt(world, made[2]) >= 2, "it struck more than one enemy (%d)" % _hurt(world, made[2]))
	world.free_all()


func test_homing_picks_spread_over_the_enemies_across_casts() -> void:
	# A fresh random pick each time, any way round: over a few casts every enemy in reach is picked.
	var made: Array = _flicker_world([&"homing", &"teleport"])
	var world: World = made[0]
	world.press(true)
	world.run(8.0, 8.0)
	check_equal(_hurt(world, made[2]), FOES.size(), "every enemy in reach was struck, the one behind too")
	world.free_all()


func test_a_payload_of_its_landing_hit_is_cast_by_the_wizards_body() -> void:
	# What a move moves casts its hits' payloads (`Carrier.hit_caster`): a shield left over in the
	# payload is a barrier on the wizard, not a card wasted on a point.
	var made: Array = _flicker_world([&"on_hit", &"homing", &"teleport", &"shield", &"pulse"], [Vector2(70.0, 30.0)])
	var world: World = made[0]
	var wizard: Actor = made[1]
	var compiled: CompiledStaff = world.spells.compile_staff([&"on_hit", &"homing", &"teleport", &"shield", &"pulse"] as Array[StringName], _staff_of(5))
	check(not compiled.wasted.has(3), "the shield is not wasted")
	world.run(0.1, 0.1)
	check(world.combat.shield(wizard.id) > 0, "the wizard has a barrier from its landing hit")
	world.free_all()


## A plain staff of `slots` slots.
func _staff_of(slots: int) -> StaffBase:
	var staff := StaffBase.new()
	staff.slots = slots
	return staff
