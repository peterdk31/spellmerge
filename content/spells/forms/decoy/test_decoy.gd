extends "res://tests/support/suite.gd"
## The Decoy card (content/spells/forms/decoy/, staffs C): a copy of the wizard, an actor that aims
## itself (enemies chase it when it is nearest). The engine side is tested in `tests/core/test_spells_payload_carriers.gd` and
## `tests/gameplay/ai/test_entities.gd`; here the card's data and the entity it asks for. The
## combo arena has no `ai`, so its combos only check what the wizard's other staffs do beside it.
##
## godot --headless --path . --script res://content/spells/forms/decoy/test_decoy.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")
const World := preload("res://tests/support/card_rules_world.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

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
func _world(cards: Array[StringName], enemy_at: Vector2, extra: Dictionary = {}) -> Array:
	var registry: Node = own(RegistryScript.new()) as Node
	registry.call("scan")
	var shelf := own(World.Shelf.new()) as World.Shelf
	shelf.base = registry
	shelf.extra = extra
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


## Two decoys of one staff: breaking the older takes only its own timer; the younger keeps
## ticking from its own body. Regression: the tag's last entry left (the younger's).
func test_a_broken_decoy_takes_only_its_own_timer() -> void:
	# A decoy card with no cooldown, so the staff casts a second while the first stands.
	var quick: FormBase = _card().duplicate() as FormBase
	quick.cooldown = 0.0
	var made: Array = _world([&"timer", &"decoy", &"bolt"], Vector2(400.0, 300.0), {&"decoy": quick})
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.run(0.25, 0.25)
	var older: Actor = world.entities.decoy_of(wizard.id)
	# Once the cast's delay (its bolt's cooldown) is over, a second, below the first.
	for wait in 120:
		if world.spells.cooldown_left(wizard.id, 0) <= 0.0:
			break
		world.run(World.STEP, World.STEP)
	# The second stands well below the first.
	wizard.position += Vector2(0.0, 120.0)
	world.brain.presses = [0]
	world.run(0.25, 0.25)
	check_equal(world.entities.count(&"decoy", wizard.id), 2, "two decoys")
	if older == null or world.entities.count(&"decoy", wizard.id) != 2:
		world.free_all()
		return
	var older_at: Vector2 = older.global_position + older.body_offset
	var by: int = world.table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	world.combat.hit(by, older, 1000)
	world.run(World.STEP, World.STEP)
	var younger: Actor = world.entities.decoy_of(wizard.id)
	check(younger != null and younger != older, "the younger stands")
	if younger == null:
		world.free_all()
		return
	var younger_at: Vector2 = younger.global_position + younger.body_offset
	# Over a second (two ticks), where new bolts start: a bolt within a step's flight of a body.
	var from_younger: int = 0
	var from_older: int = 0
	for step in int(1.0 / World.STEP):
		world.run(World.STEP, World.STEP)
		from_younger += _bolts_near(world, younger_at)
		from_older += _bolts_near(world, older_at)
	check(from_younger > 0, "the younger keeps its timer")
	check_equal(from_older, 0, "the broken one ticks no more")
	world.free_all()


## The bolts within 8 px of `at` (one just fired from there).
func _bolts_near(world: World, at: Vector2) -> int:
	var found: int = 0
	for slot in world.projectiles.get_cap():
		if world.projectiles.is_alive(slot) and world.projectiles.get_position_of(slot).distance_to(at) < 8.0:
			var spell: CompiledSpell = world.spells.profile(world.projectiles.get_tag_of(slot))
			if spell != null and spell.form_id == &"bolt":
				found += 1
	return found


## `on hurt` on a decoy fires when the decoy is hurt (owner, 2026-11-02), not its wizard.
func test_on_hurt_on_a_decoy_fires_when_the_decoy_is_hurt() -> void:
	var made: Array = _world([&"on_hurt", &"decoy", &"bolt"], Vector2(400.0, 300.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.run(0.25, 0.25)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null, "a decoy")
	if decoy == null:
		world.free_all()
		return
	var by: int = world.table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	var before: int = _bolts(world)
	world.combat.hit(by, wizard, 1)
	world.run(0.0625, 0.0625)
	check_equal(_bolts(world), before, "the wizard hurt: no bolt")
	world.combat.hit(by, decoy, 1)
	world.run(0.0625, 0.0625)
	check_equal(_bolts(world), before + 1, "the decoy hurt: a bolt")
	world.free_all()


func _bolts(world: World) -> int:
	var found: int = 0
	for slot in world.projectiles.get_cap():
		if world.projectiles.is_alive(slot):
			var spell: CompiledSpell = world.spells.profile(world.projectiles.get_tag_of(slot))
			if spell != null and spell.form_id == &"bolt":
				found += 1
	return found


## A decoy aims at the nearest foe it can see: one behind a wall is passed over for one farther
## off in view. A copy of a living staff (a head sheet of StaffLook.DIRECTIONS columns) turns to
## its aim.
func test_a_decoy_aims_at_a_foe_it_can_see_and_turns_to_it() -> void:
	var made: Array = _world([&"decoy"], Vector2(70.0, 0.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.add_wall(Rect2(40.0, -30.0, 8.0, 60.0))
	var seen: Node2D = world.add_enemy(&"B", Vector2(20.0, 140.0))
	world.run(0.0625, 0.0625)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null, "a decoy")
	if decoy == null:
		world.free_all()
		return
	var look: DecoyLook = decoy.get_node(^"Look") as DecoyLook
	var sheet := Image.create(16 * StaffLook.DIRECTIONS, 16 * 4, false, Image.FORMAT_RGBA8)
	look.sprite.texture = ImageTexture.create_from_image(sheet)
	look.sprite.hframes = StaffLook.DIRECTIONS
	look.sprite.vframes = 4
	look.sprite.frame_coords = Vector2i(0, 2)
	world.run(AIBrain.RETARGET_TIME + 0.125, AIBrain.RETARGET_TIME + 0.125)
	var to_seen: Vector2 = (seen.global_position - decoy.global_position).normalized()
	check(decoy.aim.dot(to_seen) > 0.95, "it aims at the foe in view (%s, that foe %s)" % [decoy.aim, to_seen])
	check_equal(look.sprite.frame_coords, Vector2i(StaffLook.direction_of(decoy.aim), 2), "its copy turns to its aim")
	world.free_all()

