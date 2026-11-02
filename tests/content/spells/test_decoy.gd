extends "res://tests/support/suite.gd"
## The Decoy card (content/spells/forms/decoy/, staffs C): a still copy of the wizard that
## enemies target. The engine side is tested in `tests/core/test_spells_payload_carriers.gd` and
## `tests/gameplay/ai/test_entities.gd`; here the card's data and the entity it asks for. The
## combo arena has no `ai`, so its combos only check what the wizard's other staffs do beside it.
##
## godot --headless --path . --script res://tests/content/spells/test_decoy.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")
const World := preload("res://tests/support/card_rules_world.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const COMBOS: Array[String] = ["decoy_and_fire", "decoy_frost_cover"]


func _card() -> FormBase:
	return load("res://content/spells/forms/decoy/decoy.tres") as FormBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `cards` from `seat` and returns every entity asked for as [actor, kind, position, seconds].
func _spawns(cards: Array, seat: int = 0) -> Array:
	var arena := ArenaScript.new(root)
	var spawns: Array = []
	arena.bus.entity_spawn_requested.connect(func(actor: int, kind: StringName, at: Vector2, seconds: float, _tag: int, _caster: int) -> void:
		spawns.append([actor, kind, at, seconds]))
	arena.place_caster(seat, Vector2(40, 20))
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	arena.run(0.5)
	arena.free_all()
	return spawns


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "decoy.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"decoy", "its id is its folder")
	check_equal(card.kind(), &"form", "a carrier card")
	check_equal(card.carrier, &"decoy", "it is a decoy")
	check(card.lifetime > 0.0, "it lasts a while")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_exist() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_a_cast_asks_for_one_decoy_a_step_ahead_of_the_caster() -> void:
	var spawns: Array = _spawns(["decoy"])
	check_equal(spawns.size(), 1, "one decoy")
	if spawns.is_empty():
		return
	check_equal(spawns[0][1], &"decoy", "a decoy, not a familiar")
	var at: Vector2 = spawns[0][2]
	# Rules R4 F3: what a caster places appears twice its size ahead along the aim (+x here).
	check(at.distance_to(Vector2(40.0 + _card().radius * 2.0, 20)) < 1.0, "a step ahead of the caster (%s)" % [at])
	check_equal(spawns[0][3], _card().lifetime, "for the card's lifetime")


func test_a_cast_without_the_card_asks_for_none() -> void:
	check(_spawns(["fire", "bolt"]).is_empty(), "a bolt leaves no decoy")


func test_four_players_leave_their_own() -> void:
	for seat in 4:
		var spawns: Array = _spawns(["decoy"], seat)
		check_equal(spawns.size(), 1, "player %d leaves one decoy" % seat)
		if not spawns.is_empty():
			check_equal(spawns[0][0], seat, "player %d: the decoy is theirs" % seat)


## Casts `cards` once while an enemy past the aim shoots bolts at the wizard all along, and counts
## the wizard's blocks and deflects by the decoy's card (its node), and the payloads fired.
func _guarded(cards: Array[StringName]) -> Dictionary:
	var registry: Node = own(RegistryScript.new()) as Node
	registry.call("scan")
	var shelf := own(World.Shelf.new()) as World.Shelf
	shelf.base = registry
	var staff := StaffBase.new()
	staff.id = &"decoy_guard"
	staff.slots = 16
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	var world := World.new(root, shelf, staff)
	var wizard: Actor = world.add_wizard(cards)
	world.add_enemy(&"E", Vector2(140.0, 0.0), World.HEALTH, [&"bolt"], Vector2.LEFT, true)
	var got: Dictionary = {"blocked": 0, "deflected": 0, "fired": 0}
	var me: int = wizard.caster_number()
	world.bus.shot_blocked.connect(func(caster: int, _at: Vector2, tag: int, _shot: int) -> void:
		if caster == me and SpellTag.node_of(tag) == 0:
			got["blocked"] += 1)
	world.bus.shot_deflected.connect(func(caster: int, _at: Vector2, tag: int, _shot: int) -> void:
		if caster == me and SpellTag.node_of(tag) == 0:
			got["deflected"] += 1)
	world.press()
	world.run(2.0, 2.0)
	got["fired"] = world.spells.fires_made
	world.free_all()
	return got


func test_a_shielded_decoy_blocks_shots_that_touch_it() -> void:
	# Rules R4g: a shield on a decoy stops the other teams' shots at it, one charge each.
	check_equal(_guarded([&"decoy"])["blocked"], 0, "a plain decoy blocks nothing")
	var shield: ModifierBase = load("res://content/spells/modifiers/shield/shield.tres") as ModifierBase
	var got: Dictionary = _guarded([&"shield", &"decoy"])
	check_equal(got["blocked"], roundi(shield.behaviour_strength), "a shielded one blocks as many as its charges")


func test_a_deflecting_decoy_turns_shots_away() -> void:
	var got: Dictionary = _guarded([&"deflect", &"decoy"])
	check(got["deflected"] > 1, "it turns every shot that reaches it (%d)" % got["deflected"])
	check_equal(got["blocked"], 0, "and stops none")


func test_on_block_fires_from_a_decoy() -> void:
	var got: Dictionary = _guarded([&"on_block", &"shield", &"decoy", &"bolt"])
	check(got["blocked"] > 0, "it blocks")
	check_equal(got["fired"], got["blocked"], "and each block fires its payload")


## A world with the wizard's staff `cards` (cast once at the first step) and a still enemy whose hurt
## circle is at `enemy_at`.
func _world(cards: Array[StringName], enemy_at: Vector2) -> Array:
	var registry: Node = own(RegistryScript.new()) as Node
	registry.call("scan")
	var shelf := own(World.Shelf.new()) as World.Shelf
	shelf.base = registry
	var staff := StaffBase.new()
	staff.id = &"decoy_aim"
	staff.slots = 16
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	var world := World.new(root, shelf, staff)
	var wizard: Actor = world.add_wizard(cards)
	var enemy: Node2D = world.add_enemy(&"E", enemy_at)
	world.press()
	return [world, wizard, enemy]


## The decoy aims itself (owner, 2026-11-02): a payload fired from an actor's body goes along that
## actor's aim, and a decoy aims at the nearest foe. The wizard aims along +x; the enemy stands
## well off that line, so only an aimed bolt finds it.
func test_a_decoys_timer_fires_at_the_nearest_foe_not_the_way_it_was_cast() -> void:
	var made: Array = _world([&"timer", &"decoy", &"bolt"], Vector2(40.0, 140.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	var enemy: Node2D = made[2]
	world.run(0.25)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null and decoy.is_inside_tree(), "the decoy is an actor in the world")
	if decoy != null:
		var to_enemy: Vector2 = (enemy.global_position - decoy.global_position).normalized()
		check(decoy.aim.dot(to_enemy) > 0.95, "it aims at the enemy (%s, the enemy %s)" % [decoy.aim, to_enemy])
		check_equal(world.table.team_of(decoy.id), world.table.team_of(wizard.id), "on its wizard's team")
	world.run(2.0, 2.0)
	check(world.combat.health_of(enemy) < World.HEALTH, "its timer's bolts hit the enemy off the cast's line (health %s)" % world.combat.health_of(enemy))
	world.free_all()


## The wizard's own shots pass its decoy, as they pass the wizard (it belongs to the wizard).
func test_the_wizards_own_shots_pass_its_decoy() -> void:
	var made: Array = _world([&"decoy"], Vector2(400.0, 0.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.run(0.25)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null, "a decoy")
	if decoy != null:
		check_equal(world.projectiles.target_owner_of(decoy), wizard.id, "its hurt circle is owned by the wizard")
	world.free_all()


## Homing on a decoy makes it creep toward its target at SpellLimits.HOMING_DRIFT, as a homing rune
## does (owner, 2026-11-02); without homing it stands.
func test_a_homing_decoy_creeps_toward_its_target_and_a_plain_one_stands() -> void:
	for homing: bool in [false, true]:
		var cards: Array[StringName] = [&"decoy"]
		if homing:
			cards.push_front(&"homing")
		var made: Array = _world(cards, Vector2(120.0, 0.0))
		var world: World = made[0]
		var wizard: Actor = made[1]
		world.run(0.125)
		var decoy: Actor = world.entities.decoy_of(wizard.id)
		check(decoy != null, "a decoy (homing %s)" % homing)
		if decoy == null:
			world.free_all()
			continue
		var start: Vector2 = decoy.global_position
		world.run(1.0, 1.0)
		var moved: Vector2 = decoy.global_position - start
		if homing:
			check(moved.x > SpellLimits.HOMING_DRIFT * 0.9 and moved.x < SpellLimits.HOMING_DRIFT * 1.1, "a homing decoy creeps toward the enemy at HOMING_DRIFT (%s)" % moved)
		else:
			check(moved.is_zero_approx(), "a plain decoy stands (%s)" % moved)
		world.free_all()
