extends "res://tests/support/suite.gd"
## The Decoy card (content/spells/forms/decoy/, staffs C): a copy of the wizard, an actor that aims
## itself (enemies chase it when it is nearest). The engine side is tested in `tests/core/test_spells_payload_carriers.gd` and
## `tests/gameplay/ai/test_entities.gd`; here the card's data, the entity it asks for and its body:
## a regular actor (owner, 2026-11-06) with a barrier for its shield, a deflect as it appears, and
## a payload's left-over cards landing on it.
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


## Casts `cards` once while an enemy past the aim shoots bolts at the wizard all along (when an
## enemy bolt is within `press_within` pixels of the wizard's hand; at the first step for 0), and
## counts the blocks of a barrier on a body other than the wizard's (its decoy) by the cast's first
## card (its node), the shots the wizard turned with it, the payloads fired and the decoy's health
## lost.
func _guarded(cards: Array[StringName], press_within: float = 0.0) -> Dictionary:
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
	var got: Dictionary = {"blocked": 0, "deflected": 0, "fired": 0, "barrier": 0, "lost": 0.0}
	var me: int = wizard.caster_number()
	world.bus.shield_blocked.connect(func(actor: int, _at: Vector2, tag: int) -> void:
		if actor != me and SpellTag.caster_of(tag) == me and SpellTag.node_of(tag) == 0:
			got["blocked"] += 1)
	world.bus.shot_deflected.connect(func(caster: int, _at: Vector2, tag: int, _shot: int) -> void:
		if caster == me and SpellTag.node_of(tag) == 0:
			got["deflected"] += 1)
	world.bus.wizard_shield_requested.connect(func(actor: int, charges: int, _seconds: float, tag: int) -> void:
		if actor != me and SpellTag.caster_of(tag) == me:
			got["barrier"] += charges)
	world.bus.damage_dealt.connect(func(_by: int, target: Node, amount: float, _at: Vector2) -> void:
		if target is Actor and target != wizard and (target as Actor).belongs_to == me:
			got["lost"] += amount)
	if press_within > 0.0:
		world.press_when_shot_within(press_within)
	else:
		world.press()
	world.run(2.0, 2.0)
	got["fired"] = world.spells.fires_made
	world.free_all()
	return got


func test_a_shielded_decoy_has_a_barrier_that_blocks_hits() -> void:
	# Owner, 2026-11-06: the decoy is a regular actor; its shield is a barrier on it, as on a caster.
	var plain: Dictionary = _guarded([&"decoy"])
	check_equal(plain["blocked"], 0, "a plain decoy blocks nothing")
	check_equal(plain["barrier"], 0, "and has no barrier")
	check(plain["lost"] > 0.0, "the enemy's bolts hurt it (%s)" % plain["lost"])
	var shield: ModifierBase = load("res://content/spells/modifiers/shield/shield.tres") as ModifierBase
	var got: Dictionary = _guarded([&"shield", &"decoy"])
	check_equal(got["barrier"], roundi(shield.behaviour_strength), "a shielded one gets a barrier of its charges")
	check_equal(got["blocked"], roundi(shield.behaviour_strength), "which blocks as many hits")


func test_a_deflecting_decoy_turns_the_shots_round_it_once_as_it_appears() -> void:
	# Owner, 2026-11-06: the caster's rule. Cast as an enemy bolt comes near, it turns that one; the
	# later ones reach it.
	var near: Dictionary = _guarded([&"deflect", &"decoy"], 32.0)
	check(near["deflected"] >= 1, "it turns the shot near it as it appears (%d)" % near["deflected"])
	check(near["lost"] > 0.0, "and no more: the later bolts hurt it (%s)" % near["lost"])
	check_equal(near["blocked"], 0, "it stops none")
	var early: Dictionary = _guarded([&"deflect", &"decoy"])
	check_equal(early["deflected"], 0, "cast with no shot near, it turns none later (%d)" % early["deflected"])


func test_on_block_fires_from_a_decoys_barrier() -> void:
	var got: Dictionary = _guarded([&"on_block", &"shield", &"decoy", &"bolt"])
	check(got["blocked"] > 0, "its barrier blocks")
	check_equal(got["fired"], got["blocked"], "and each block fires its payload")


## The barrier charges (Combat's) on the wizard's oldest decoy in `world`, -1 with none.
func _decoy_barrier(world: World, wizard: Actor) -> int:
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	return world.combat.shield(decoy.id) if decoy != null and decoy.is_inside_tree() else -1


func test_a_decoy_placed_again_starts_with_its_own_barrier_only() -> void:
	# A decoy's actor is kept by its row and placed again: the barrier goes with the decoy, not the row.
	var quick: FormBase = _card().duplicate() as FormBase
	quick.cooldown = 0.0
	quick.lifetime = 0.25
	var made: Array = _world([&"shield", &"decoy", &"decoy"], Vector2(400.0, 300.0), {&"decoy": quick})
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.run(World.STEP, World.STEP)
	check_equal(_decoy_barrier(world, wizard), 1, "the shielded decoy has its barrier at once (Combat knows its body)")
	world.run(0.5, 0.5)
	check_equal(world.entities.count(&"decoy", wizard.id), 0, "it is gone")
	world.brain.presses = [0]
	world.run(World.STEP, World.STEP)
	check_equal(world.entities.count(&"decoy", wizard.id), 1, "the plain one stands")
	check_equal(_decoy_barrier(world, wizard), 0, "with no barrier from the one before")
	world.free_all()


func test_a_timer_on_a_decoy_shields_the_decoy() -> void:
	# The wider rule (owner, 2026-11-06): a payload's left-over cards land on the body that fired it.
	var made: Array = _world([&"timer", &"decoy", &"shield"], Vector2(400.0, 300.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	var compiled: CompiledStaff = world.spells.compile_staff([&"timer", &"decoy", &"shield"] as Array[StringName], _plain(3))
	check(not compiled.wasted.has(2), "the shield is not wasted: it lands on the decoy")
	world.run(0.125, 0.125)
	check_equal(_decoy_barrier(world, wizard), 0, "no barrier before the first tick")
	world.run(0.5, 0.5)
	check(_decoy_barrier(world, wizard) >= 1, "a barrier after it (%d)" % _decoy_barrier(world, wizard))
	check_equal(world.combat.shield(wizard.id), 0, "on the decoy, not the wizard")
	world.free_all()


func test_a_decoys_payload_waiting_for_its_turn_still_lands_on_the_decoy() -> void:
	# The body is carried through a delayed fire (`PendingLaunch.caster`), as a shot caster is:
	# an echo of the landing, and a fire past the step's budget, which waits for the next step.
	var made: Array = _world([&"timer", &"mirror", &"decoy", &"echo", &"shield"], Vector2(400.0, 300.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.spells.fire_shots_per_step = 0
	var shielded: Dictionary = {}
	world.bus.wizard_shield_requested.connect(func(actor: int, _charges: int, _seconds: float, _tag: int) -> void:
		shielded[actor] = int(shielded.get(actor, 0)) + 1)
	world.run(1.0, 1.0)
	check_equal(world.entities.count(&"decoy", wizard.id), 2, "two decoys (a mirror's)")
	check(world.spells.fires_waited > 0, "a tick waited for the next step (%d)" % world.spells.fires_waited)
	check(not shielded.has(wizard.id), "no barrier on the wizard: %s" % [shielded])
	check_equal(shielded.size(), 2, "a barrier on each decoy: %s" % [shielded])
	for actor: int in shielded:
		check(int(shielded[actor]) >= 2, "each by its tick and its echo: %s" % [shielded])
	world.free_all()


func test_an_on_hurt_payload_that_hurts_its_decoy_does_not_fire_itself_again() -> void:
	# Regression: the strike of what lands on a decoy hurt it, which fired its `on hurt` again inside
	# itself, for ever (a stack overflow).
	var made: Array = _world([&"on_hurt", &"decoy", &"fire"], Vector2(400.0, 300.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.run(0.25, 0.25)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null, "a decoy")
	if decoy == null:
		world.free_all()
		return
	var before: int = world.spells.fires_made
	var by: int = world.table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	world.combat.hit(by, decoy, 1)
	check_equal(world.spells.fires_made, before + 1, "one hurt, one payload, though its fire hurt the decoy too")
	world.free_all()


# --- The decoy's body casts its payloads (owner, 2026-11-06) ----------------------------------

## A world with the wizard casting `cards` at once and a still enemy at `enemy_at`, run until the
## decoy stands: [world, wizard, decoy, where the decoy stands, where the wizard stands].
func _decoy_world(cards: Array[StringName], enemy_at: Vector2) -> Array:
	var made: Array = _world(cards, enemy_at)
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.run(0.25, 0.25)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null, "%s: a decoy" % [cards])
	return [world, wizard, decoy, decoy.global_position if decoy != null else Vector2.INF, wizard.global_position]


func test_a_decoys_timer_dash_moves_the_decoy_not_the_wizard() -> void:
	var made: Array = _decoy_world([&"timer", &"decoy", &"dash"], Vector2(240.0, 0.0))
	var world: World = made[0]
	var decoy: Actor = made[2]
	if decoy != null:
		world.run(0.5, 0.5)
		check(decoy.global_position.distance_to(made[3]) > 40.0, "the decoy dashed (%s to %s)" % [made[3], decoy.global_position])
		check(decoy.global_position.x > (made[3] as Vector2).x, "toward its foe, the way it aims")
		check((made[1] as Actor).global_position.is_equal_approx(made[4]), "the wizard stayed (%s)" % (made[1] as Actor).global_position)
	world.free_all()


func test_a_decoys_timer_teleport_moves_the_decoy() -> void:
	var made: Array = _decoy_world([&"timer", &"decoy", &"teleport"], Vector2(240.0, 0.0))
	var world: World = made[0]
	var decoy: Actor = made[2]
	if decoy != null:
		world.run(0.5, 0.5)
		check(decoy.global_position.distance_to(made[3]) > 60.0, "the decoy teleported (%s to %s)" % [made[3], decoy.global_position])
		check((made[1] as Actor).global_position.is_equal_approx(made[4]), "the wizard stayed (%s)" % (made[1] as Actor).global_position)
	world.free_all()


func test_a_decoys_timer_pull_and_swap_move_the_decoy() -> void:
	for raw: Array in [[&"timer", &"decoy", &"pull", &"bolt"], [&"timer", &"decoy", &"swap"]]:
		var cards: Array[StringName] = []
		cards.assign(raw)
		var made: Array = _decoy_world(cards, Vector2(120.0, 0.0))
		var world: World = made[0]
		var decoy: Actor = made[2]
		if decoy != null:
			world.run(1.0, 1.0)
			check(decoy.global_position.x > (made[3] as Vector2).x + 40.0, "%s: the decoy went toward what its shot hit (%s to %s)" % [cards, made[3], decoy.global_position])
			check((made[1] as Actor).global_position.is_equal_approx(made[4]), "%s: the wizard stayed (%s)" % [cards, (made[1] as Actor).global_position])
		world.free_all()


func test_a_decoys_timer_recoil_pushes_the_decoy() -> void:
	var made: Array = _decoy_world([&"timer", &"decoy", &"recoil", &"bolt"], Vector2(240.0, 0.0))
	var world: World = made[0]
	var decoy: Actor = made[2]
	if decoy != null:
		world.run(0.6, 0.6)
		check(decoy.global_position.x < (made[3] as Vector2).x - 10.0, "pushed back from its bolt (%s to %s)" % [made[3], decoy.global_position])
		check((made[1] as Actor).global_position.is_equal_approx(made[4]), "the wizard stayed")
	world.free_all()


func test_a_decoy_that_ends_mid_dash_is_placed_again_standing() -> void:
	# A decoy's actor is kept by its row: the dash its payload asked of it ends with it.
	var quick: FormBase = _card().duplicate() as FormBase
	quick.cooldown = 0.0
	quick.lifetime = 0.3
	var made: Array = _world([&"timer", &"decoy", &"dash", &"decoy"], Vector2(240.0, 0.0), {&"decoy": quick})
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.run(0.5, 0.5)
	check_equal(world.entities.count(&"decoy", wizard.id), 0, "the first ended mid-dash")
	for wait in 240:
		if world.spells.cooldown_left(wizard.id, 0) <= 0.0:
			break
		world.run(World.STEP, World.STEP)
	world.brain.presses = [0]
	world.run(World.STEP * 2.0, World.STEP * 2.0)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null, "the second stands")
	if decoy != null:
		var at: Vector2 = decoy.global_position
		world.run(0.2, 0.2)
		check(decoy.global_position.distance_to(at) < 1.0, "and keeps no move of the one before (%s to %s)" % [at, decoy.global_position])
	world.free_all()


## Every pull asked while `world` runs `seconds`, as the actor it moves.
func _pulls(world: World, seconds: float) -> Array[int]:
	var pulled: Array[int] = []
	var listen: Callable = func(actor: int, mode: StringName, _move: Vector2, _seconds: float, _tag: int) -> void:
		if mode == &"pull":
			pulled.append(actor)
	world.bus.caster_move_requested.connect(listen)
	world.run(seconds, seconds)
	world.bus.caster_move_requested.disconnect(listen)
	return pulled


func test_a_decoys_beam_pulls_the_decoy_on_its_later_hits_too() -> void:
	# A beam hits again in its own steps, after its cast: it still hits as the decoy that cast it
	# (`CarrierKit.cast_as`), so its pull moves the decoy, never the wizard.
	var made: Array = _decoy_world([&"timer", &"decoy", &"pull", &"beam"], Vector2(120.0, 0.0))
	var world: World = made[0]
	var decoy: Actor = made[2]
	if decoy != null:
		var pulled: Array[int] = _pulls(world, 0.6)
		check(pulled.size() >= 2, "the beam hit and pulled more than once (%s)" % [pulled])
		check(pulled.count(decoy.id) == pulled.size(), "every pull moves the decoy (%s, the decoy %d)" % [pulled, decoy.id])
		check((made[1] as Actor).global_position.is_equal_approx(made[4]), "the wizard stayed")
	world.free_all()


func test_a_decoys_swap_trades_the_decoy_also_by_its_zaps() -> void:
	# A swap is a shot, so its own hits know their caster; its zaps are hits of no shot that come in
	# the shots' later steps: they hit as the shot's caster too, and trade the decoy, not the wizard.
	var made: Array = _world([&"timer", &"decoy", &"zap", &"swap"], Vector2(160.0, 0.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	# One more foe beside its path, which only its zaps reach.
	world.add_enemy(&"B", Vector2(110.0, 40.0))
	var swaps: Array[int] = []
	world.bus.caster_move_requested.connect(func(actor: int, mode: StringName, _move: Vector2, _seconds: float, _tag: int) -> void:
		if mode == &"swap":
			swaps.append(actor))
	world.run(2.0, 2.0)
	check(swaps.size() >= 3, "its swaps traded more than its direct hits (%s)" % [swaps])
	check(not swaps.has(wizard.id), "none moved the wizard (%s, the wizard %d)" % [swaps, wizard.id])
	world.free_all()


func test_a_decoys_chain_jump_pulls_the_decoy() -> void:
	# A chain jump belongs to the shot it jumped from: it is cast by what cast that shot (the decoy),
	# so the jump's hit pulls the decoy, never the wizard.
	var made: Array = _decoy_world([&"timer", &"decoy", &"pull", &"chain", &"bolt"], Vector2(120.0, 0.0))
	var world: World = made[0]
	var decoy: Actor = made[2]
	world.add_enemy(&"B", Vector2(140.0, 50.0))
	if decoy != null:
		var pulled: Array[int] = _pulls(world, 0.8)
		check(pulled.size() >= 2, "the bolt and its jump both pulled (%s)" % [pulled])
		check(pulled.count(decoy.id) == pulled.size(), "every pull moves the decoy (%s, the decoy %d)" % [pulled, decoy.id])
		check((made[1] as Actor).global_position.is_equal_approx(made[4]), "the wizard stayed")
	world.free_all()


func test_a_decoys_chain_jumps_return_to_the_decoy() -> void:
	var made: Array = _decoy_world([&"timer", &"decoy", &"return", &"chain", &"bolt"], Vector2(120.0, 0.0))
	var world: World = made[0]
	var decoy: Actor = made[2]
	world.add_enemy(&"B", Vector2(140.0, 50.0))
	if decoy != null:
		var bolts: Dictionary = {}
		var astray: int = 0
		for step in 60:
			world.run(World.STEP, World.STEP)
			for slot in world.projectiles.get_cap():
				if not world.projectiles.is_alive(slot):
					continue
				var spell: CompiledSpell = world.spells.profile(world.projectiles.get_tag_of(slot))
				if spell == null or spell.form_id != &"bolt":
					continue
				bolts[world.projectiles.get_seq_of(slot)] = true
				if world.projectiles.get_caster_of(slot).distance_to(world.projectiles.get_anchor(decoy.id)) > 1.0:
					astray += 1
		check(bolts.size() >= 2, "a bolt and a jump of it flew (%d)" % bolts.size())
		check_equal(astray, 0, "every bolt and jump comes back to the decoy, none to the wizard")
	world.free_all()


func test_your_own_chain_jump_still_pulls_you() -> void:
	var made: Array = _world([&"pull", &"chain", &"bolt"], Vector2(120.0, 0.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.add_enemy(&"B", Vector2(140.0, 50.0))
	# Another body that casts stands far off, so a pull sent to the wrong body would show.
	world.add_enemy(&"F", Vector2(-300.0, -300.0), World.HEALTH, [&"atom"], Vector2.UP)
	var pulled: Array[int] = _pulls(world, 0.8)
	check(pulled.size() >= 2, "the bolt and its jump both pulled (%s)" % [pulled])
	check(pulled.count(wizard.id) == pulled.size(), "every pull moves the wizard (%s, the wizard %d)" % [pulled, wizard.id])
	world.free_all()


func test_the_wizards_own_held_beam_still_pulls_the_wizard_on_its_later_hits() -> void:
	var made: Array = _world([&"hold", &"pull", &"beam"], Vector2(120.0, 0.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	# Another body that casts stands far off, so a pull sent to the wrong body would show.
	world.add_enemy(&"F", Vector2(-300.0, -300.0), World.HEALTH, [&"atom"], Vector2.UP)
	var pulled: Array[int] = _pulls(world, 0.6)
	check(pulled.size() >= 2, "the held beam hit and pulled more than once (%s)" % [pulled])
	check(pulled.count(wizard.id) == pulled.size(), "every pull moves the wizard (%s, the wizard %d)" % [pulled, wizard.id])
	world.free_all()


## The distance of every live orbit shot from `centre`.
func _orbits_from(world: World, centre: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for slot in world.projectiles.get_cap():
		if not world.projectiles.is_alive(slot):
			continue
		var spell: CompiledSpell = world.spells.profile(world.projectiles.get_tag_of(slot))
		if spell != null and spell.carrier == &"orbit":
			out.append(world.projectiles.get_position_of(slot).distance_to(centre))
	return out


func test_a_decoys_timer_orbit_circles_the_decoy_and_follows_it() -> void:
	var orbit: FormBase = load("res://content/spells/forms/orbit/orbit.tres") as FormBase
	var made: Array = _decoy_world([&"timer", &"homing", &"decoy", &"orbit"], Vector2(140.0, 0.0))
	var world: World = made[0]
	var decoy: Actor = made[2]
	if decoy != null:
		for seconds: float in [0.35, 1.0]:
			world.run(seconds, seconds)
			var around: PackedFloat32Array = _orbits_from(world, world.projectiles.get_anchor(decoy.id))
			check(not around.is_empty(), "orbs fly")
			for distance in around:
				check(absf(distance - orbit.orbit_radius) < 3.0, "every orb circles the decoy at its radius (%s)" % around)
		check(decoy.global_position.distance_to(made[3]) > 15.0, "and the decoy crept on meanwhile (%s to %s)" % [made[3], decoy.global_position])
	world.free_all()


func test_an_orbit_in_a_dashs_timer_circles_the_wizard() -> void:
	var orbit: FormBase = load("res://content/spells/forms/orbit/orbit.tres") as FormBase
	var made: Array = _world([&"timer", &"dash", &"orbit"], Vector2(400.0, 300.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	var start: Vector2 = wizard.global_position
	world.run(0.6, 0.6)
	check(wizard.global_position.distance_to(start) > 40.0, "the wizard dashed")
	var around: PackedFloat32Array = _orbits_from(world, world.projectiles.get_anchor(wizard.id))
	check(not around.is_empty(), "an orbit flies")
	for distance in around:
		check(absf(distance - orbit.orbit_radius) < 3.0, "it circles the wizard, not a spot on its way (%s)" % around)
	world.free_all()


## A staff of `slots` with no delay of its own.
func _plain(slots: int) -> StaffBase:
	var staff := StaffBase.new()
	staff.id = &"decoy_plain"
	staff.slots = slots
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	return staff


func test_on_hurt_on_a_decoy_turns_the_shots_round_it() -> void:
	# The wider rule (owner, 2026-11-06): the deflect left in the payload lands on the decoy's body.
	var made: Array = _world([&"on_hurt", &"decoy", &"deflect"], Vector2(400.0, 300.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.add_enemy(&"S", Vector2(140.0, 0.0), World.HEALTH, [&"bolt"], Vector2.LEFT, true)
	var turned: Array[int] = [0]
	world.bus.shot_deflected.connect(func(caster: int, _at: Vector2, _tag: int, _shot: int) -> void:
		if caster == wizard.id:
			turned[0] += 1)
	world.run(World.STEP, World.STEP)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null, "a decoy")
	if decoy == null:
		world.free_all()
		return
	var centre: Vector2 = decoy.global_position + decoy.body_offset
	for step in 120:
		if world.projectiles.shots_on_segment(wizard.id, centre, centre, 16.0) > 0:
			break
		world.run(World.STEP, World.STEP)
	check_equal(turned[0], 0, "nothing turned before it is hurt")
	var by: int = world.table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	world.combat.hit(by, decoy, 1)
	world.run(World.STEP, World.STEP)
	check(turned[0] >= 1, "hurt, it turns the bolt coming at it (%d)" % turned[0])
	world.free_all()


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


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/forms/decoy/decoy.tres") as FormBase
	check_equal(card.shown_cue, &"conjure", "its shown plays conjure")
	check_equal(card.end_cue, &"dismiss", "its end plays dismiss")
	check_equal(card.cast_cue, &"cast", "its cast plays cast")


## Cards that only guard strike nothing (owner, 2026-11-06): a decoy whose timer gives it a barrier
## every tick keeps its health for its whole life, and a wizard's lone Shield or Deflect costs it
## none; a lone infusion still strikes its caster (self-harm is on).
func test_guard_cards_landing_on_a_body_cost_it_no_health() -> void:
	var made: Array = _world([&"timer", &"decoy", &"shield"], Vector2(4000.0, 3000.0))
	var world: World = made[0]
	var wizard: Actor = made[1]
	world.run(2.5, 2.5)
	var decoy: Actor = world.entities.decoy_of(wizard.id)
	check(decoy != null and decoy.is_inside_tree(), "the decoy lives on past its fourth tick")
	if decoy != null and decoy.is_inside_tree():
		check_equal(decoy.health.health, decoy.health.max_health, "at full health")
	world.free_all()
	for cards: Array[StringName] in [[&"shield"] as Array[StringName], [&"deflect"] as Array[StringName], [&"fire"] as Array[StringName]]:
		var alone: Array = _world(cards, Vector2(4000.0, 3000.0))
		var w: World = alone[0]
		var caster: Actor = alone[1]
		w.run(0.5, 0.5)
		if cards[0] == &"fire":
			check(caster.health.health < caster.health.max_health, "a lone infusion still strikes its caster")
		else:
			check_equal(caster.health.health, caster.health.max_health, "a lone %s costs its caster no health" % cards[0])
		w.free_all()
