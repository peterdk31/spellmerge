extends "res://tests/support/suite.gd"
## Tests for the bots' starting builds (tests/bots/bot_builds.gd) and the mend bot (tests/bots/bot.gd,
## `build_drawn`, `foe_in_line`): every build of the table is valid by the card rules on the staffs
## it goes on (the starter staffs, and the mender's rack staff: no card wasted, one cast a staff, the
## attack hurts, the dash moves its caster, the mend heals and hurts nobody), the bag builds each,
## the draw is the run's dice (the same seed the same builds), only P2 of a team of two or more
## mends, and in a run the mend bot heals a hurt teammate with its heal, dashes from a shot with its
## dash, fights with its rack staff (the Firebolt) and holds its heal while a foe stands in its line
## of fire. Its rack staff is put on its LB
## here as the hub's rack would give it (tests/bots/test_bot_hub.gd takes it from the rack).

const BotScript := preload("res://tests/bots/bot.gd")
const BuildsScript := preload("res://tests/bots/bot_builds.gd")

const FlowScript := preload("res://gameplay/flow/flow.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
## The replay seed a run of these tests is recorded with, so its run seed (and the builds drawn from
## it) are the same on every start.
const REPLAY_SEED: int = 11
## Physics frames the mend bot is given to heal (its staff ready, a bolt's flight).
const HEAL_FRAMES: int = 150
## The mender's hands (bot_builds.gd, MENDER): the heal on RB, the dash on RT, the attack on LB.
const HEAL_HAND: int = 0
const DASH_HAND: int = 1
const ATTACK_HAND: int = 2
## Physics frames the mend bot is given to dash from the shots fired at it, and how often one comes.
const DODGE_FRAMES: int = 120
const SHOT_EVERY: int = 15

var _input: Node
var _flow: Node
var _events: Node
var _bots: Array[BotScript] = []
var _bag_had: Array[StringName] = []


func before_each() -> void:
	_input = root.get_node("PlayerInput")
	_flow = root.get_node("Flow")
	_events = root.get_node("Events")
	_bots.clear()
	_bag_had = BuildsScript.stock(_flow)


func after_each() -> void:
	for bot in _bots:
		bot.leave()
	_bots.clear()
	_flow.call("stop_run")
	var frames: Node = root.get_node("Frames")
	if bool(frames.call("is_recording")):
		frames.call("stop_recording")
	_flow.set(&"play_bag", _bag_had)
	for index in 4:
		_input.call("leave", index)
	await commands_applied()


## The staff `build` sets hand `hand` of: Play's starter (Flow's STARTER_HEADS, RB's and RT's), or
## past them its rack staff's.
func _staff(build: Dictionary, hand: int) -> StaffBase:
	if hand >= FlowScript.START_HANDS:
		var rack: StaffItem = BuildsScript.rack_of(build)
		return rack.staff if rack != null else null
	return root.get_node("Registry").call("get_resource", &"wizard", FlowScript.STARTER_HEADS[hand]) as StaffBase


## The compiled staff of `build`'s hand `hand` (its rack staff's own cards past the build's list).
func _compiled(build: Dictionary, hand: int) -> CompiledStaff:
	return root.get_node("Spells").call("compile_staff", BuildsScript.cards_held(build, hand), _staff(build, hand)) as CompiledStaff


# --- The table ---------------------------------------------------------------------------------


func test_every_build_is_valid_by_the_card_rules() -> void:
	for build: Dictionary in BuildsScript.all():
		var hands: int = BuildsScript.held_hands(build)
		check_equal(BuildsScript.hands_of(build), FlowScript.START_HANDS, "%s: cards for each starter staff (RB, RT)" % build["name"])
		for number in hands:
			var cards: Array[StringName] = BuildsScript.cards_held(build, number)
			var compiled: CompiledStaff = _compiled(build, number)
			check(cards.size() <= _staff(build, number).slots, "%s staff %d fits its staff's %d slots" % [build["name"], number, _staff(build, number).slots])
			check(compiled != null and not compiled.is_empty(), "%s staff %d casts" % [build["name"], number])
			if compiled == null:
				continue
			check(compiled.wasted.is_empty(), "%s staff %d wastes no card: %s" % [build["name"], number, compiled.wasted])
			check_equal(compiled.casts.size(), 1, "%s staff %d is one cast" % [build["name"], number])


## What the brain reads of each build: the fighters dash on RB and hurt on RT; the mender heals on
## RB, hurting nobody, dashes on RT and hurts on LB with the rack's Firebolt (the owner, 2026-11-20:
## heal, dash and a fire bolt).
func test_each_build_has_the_staffs_its_bot_plays() -> void:
	for build: Dictionary in BuildsScript.all():
		var first: CastSense = _compiled(build, 0).casts[0].sense
		var second: CastSense = _compiled(build, 1).casts[0].sense
		if build == BuildsScript.MENDER:
			var third: CastSense = _compiled(build, 2).casts[0].sense
			check(first.heals and not first.harms(), "the mender's RB heals and hurts nobody")
			check(first.reach > 0.0, "and is aimed (it reaches a teammate along a line)")
			check(second.moves_caster, "the mender's RT dashes")
			check(third.harms() and not third.heals and not third.moves_caster, "the mender's LB hurts")
			continue
		check(first.moves_caster, "%s: RB dashes" % build["name"])
		check(second.harms() and not second.heals and not second.moves_caster, "%s: RT hurts" % build["name"])


func test_only_the_mender_takes_a_rack_staff_and_it_lies_in_the_hub() -> void:
	for build: Dictionary in BuildsScript.FIGHTERS:
		check(BuildsScript.rack_of(build) == null, "%s takes no rack staff" % build["name"])
	var rack: StaffItem = BuildsScript.rack_of(BuildsScript.MENDER)
	check(rack != null and rack.problems().is_empty(), "the mender's rack staff is a valid premade staff")
	# The owner, 2026-11-20, on #891: bots never take a dev staff or the Wild star.
	check(rack != null and rack.staff.cooldown > 0.0 and rack.staff.max_mana <= 100.0, "a fair staff: a starter's mana and a cooldown, never the dev staff")
	check(rack != null and rack.id != &"wild_star", "never the Wild star")
	check(rack != null and rack.id == &"firebolt", "the Firebolt (fire on a bolt)")
	var hub: Node = (load("res://content/rooms/hub/hub.tscn") as PackedScene).instantiate()
	var laid: bool = false
	for stand_in: Node in hub.get_node("Items").get_children():
		if stand_in.get(&"item") == rack:
			laid = true
	hub.free()
	check(laid, "and the hub's scene lays it on its rack")


func test_the_bag_builds_every_build() -> void:
	var bag: Array[StringName] = BuildsScript.bag()
	for build: Dictionary in BuildsScript.all():
		var left: Array[StringName] = bag.duplicate()
		for number in BuildsScript.hands_of(build):
			for id: StringName in BuildsScript.cards_of(build, number):
				check(left.has(id), "%s: the bag holds its %s" % [build["name"], id])
				left.erase(id)


# --- The draw ----------------------------------------------------------------------------------


func test_the_same_run_seed_draws_the_same_builds() -> void:
	for run_seed: int in [1, 11, 12345, 987654321]:
		for seat in 4:
			check(BuildsScript.pick(Sim.seeded(run_seed), seat, 3) == BuildsScript.pick(Sim.seeded(run_seed), seat, 3), "seed %d seat %d: the same build" % [run_seed, seat])


func test_different_seeds_draw_different_builds() -> void:
	var names: Dictionary = {}
	for run_seed in range(1, 40):
		names[BuildsScript.pick(Sim.seeded(run_seed), 0, 1)["name"]] = true
	check(names.size() > 1, "the draw follows the seed, not a fixed build")
	var seats: Dictionary = {}
	for seat: int in [0, 2, 3]:
		for run_seed in range(1, 40):
			seats["%d %s" % [seat, BuildsScript.pick(Sim.seeded(run_seed), seat, 4)["name"]]] = true
	check(seats.size() > 3, "and is keyed by the seat")


func test_the_draw_reaches_every_fighters_build() -> void:
	var seen: Dictionary = {}
	for run_seed in range(1, 200):
		seen[BuildsScript.pick(Sim.seeded(run_seed), 0, 1)["name"]] = true
	check_equal(seen.size(), BuildsScript.FIGHTERS.size(), "every fighter's build is drawn for some seed: %s" % [seen.keys()])


func test_only_p2_of_a_team_of_two_or_more_mends() -> void:
	var sim: Sim = Sim.seeded(7)
	check(BuildsScript.pick(sim, 1, 2) == BuildsScript.MENDER, "P2 of two mends")
	check(BuildsScript.pick(sim, 1, 4) == BuildsScript.MENDER, "P2 of four mends")
	check(BuildsScript.pick(sim, 1, 1) != BuildsScript.MENDER, "a bot alone fights")
	for seat: int in [0, 2, 3]:
		check(BuildsScript.pick(sim, seat, 4) != BuildsScript.MENDER, "P%d fights" % (seat + 1))


# --- In a run ----------------------------------------------------------------------------------


## Two fighters in a run with their drawn builds applied: [P1's wizard, P2's (the mender)], or empty.
func _built_pair() -> Array:
	for index in 2:
		var bot := BotScript.new()
		if bot.join(index, BotScript.Mode.FIGHTER, _input, _flow):
			_bots.append(bot)
	# Play, recorded: the replay's seed deals the run's (as the smoke test starts it).
	root.get_node("Frames").call("record", &"play_requested", 0, REPLAY_SEED)
	await process_frame
	await physics_frame
	var first := _flow.call("get_wizard", 0) as Actor
	var mender := _flow.call("get_wizard", 1) as Actor
	if first == null or mender == null or _bots.size() < 2:
		check(false, "the run started with two bots' wizards")
		return []
	# The mender's rack staff on its free hand (LB), as the hub's rack gives it (Play has no rack).
	check(mender.inventory.put_on_hand(BuildsScript.RACK_STAFF.stack(), mender.inventory.free_hand()), "the mender holds its rack staff")
	for bot in _bots:
		check(bot.build_drawn(2), "P%d draws its build" % (bot.player + 1))
	await commands_applied()
	await physics_frame
	return [first, mender]


func test_a_drawn_build_is_on_the_staffs() -> void:
	var pair: Array = await _built_pair()
	if pair.is_empty():
		return
	var sim: Sim = root.get_node("Tick").get(&"sim") as Sim
	check(sim.run_seed != 0, "the run has its seed")
	check(_bots[0].build == BuildsScript.pick(Sim.seeded(sim.run_seed), 0, 2), "P1's build is the one the run's seed draws (%s)" % _bots[0].build["name"])
	check(_bots[0].holds_build(pair[0]), "P1 holds its build (%s)" % _bots[0].build["name"])
	check(_bots[1].build == BuildsScript.MENDER and _bots[1].holds_build(pair[1]), "P2 holds the mend build")


func test_the_mend_bot_heals_a_hurt_teammate() -> void:
	var pair: Array = await _built_pair()
	if pair.is_empty():
		return
	var first: Actor = pair[0]
	var mender: Actor = pair[1]
	# The start room holds no fight: P1 stands still (an idler would too) 60 px from the mender.
	_bots[0].mode = BotScript.Mode.IDLER
	first.global_position = mender.global_position + Vector2(60.0, 0.0)
	first.health.health = first.health.max_health * 0.4
	var before: float = first.health.health
	var healed: Array[float] = [0.0]
	var foes: Array[float] = [0.0]
	var on_hit := func(caster: int, target: Node, amount: float, _at: Vector2, kind: StringName, _shot: int, _card: StringName) -> void:
		if kind == &"heal" and caster == mender.id:
			if target == first:
				healed[0] += amount
			elif target is Actor and (target as Actor).team() != mender.team():
				foes[0] += amount
	_events.connect("hit_landed", on_hit)
	var heal_presses: int = 0
	for i in HEAL_FRAMES:
		first.global_position = mender.global_position + Vector2(60.0, 0.0)
		await physics_frame
		if _bots[1].intent.pressed_bits & (1 << HEAL_HAND) != 0:
			heal_presses += 1
	_events.disconnect("hit_landed", on_hit)
	check(heal_presses > 0, "the mend bot pressed its heal (RB) for its hurt teammate")
	check(healed[0] > 0.0, "the mend bot's heals landed on its teammate (%.0f health)" % healed[0])
	check(first.health.health > before, "its teammate has more health (%.0f, was %.0f)" % [first.health.health, before])
	check_equal(foes[0], 0.0, "and no foe was healed")


## The third staff (the owner, 2026-11-20): shots flying at the mender make it get away with its
## dash (RT), the staff whose next cast moves it, and it never heals the foe that shoots.
func test_the_mend_bot_dashes_from_a_shot() -> void:
	var pair: Array = await _built_pair()
	if pair.is_empty():
		return
	var first: Actor = pair[0]
	var mender: Actor = pair[1]
	_bots[0].mode = BotScript.Mode.IDLER
	first.global_position = mender.global_position + Vector2(0.0, 90.0)
	# A foe far off to own the shots (a shot of the enemies' team is one to dodge).
	var foe := (load("res://content/enemies/crypt_mite/crypt_mite.tscn") as PackedScene).instantiate() as Actor
	(_flow.get(&"world") as Node2D).add_child(foe)
	await physics_frame
	var dashes: int = 0
	var heals: int = 0
	for i in DODGE_FRAMES:
		foe.global_position = mender.global_position + Vector2(-400.0, -200.0)
		if i % SHOT_EVERY == 0:
			mender.projectiles.spawn(foe.id, mender.global_position + mender.body_offset + Vector2(-90.0, 0.0), Vector2(260.0, 0.0), 2.0, 4.0, ProjectilesScript.ACTOR_LAYERS)
		await physics_frame
		var bits: int = _bots[1].intent.pressed_bits
		if bits & (1 << DASH_HAND) != 0:
			dashes += 1
		if bits & (1 << HEAL_HAND) != 0:
			heals += 1
	foe.queue_free()
	check(dashes > 0, "the mend bot dashed (RT) from the shots flying at it")
	check_equal(heals, 0, "and pressed no heal with nobody hurt")


## Out of reach of a hurt teammate and with no shot coming, the mend bot fights with its attack
## (LB, the rack staff), never with the heal.
func test_the_mend_bot_attacks_with_its_rack_staff() -> void:
	var pair: Array = await _built_pair()
	if pair.is_empty():
		return
	var first: Actor = pair[0]
	var mender: Actor = pair[1]
	_bots[0].mode = BotScript.Mode.IDLER
	first.global_position = mender.global_position + Vector2(0.0, 90.0)
	var foe := (load("res://content/enemies/crypt_mite/crypt_mite.tscn") as PackedScene).instantiate() as Actor
	(_flow.get(&"world") as Node2D).add_child(foe)
	var attacks: int = 0
	var heals: int = 0
	for i in HEAL_FRAMES:
		if is_instance_valid(foe) and not foe.is_down():
			foe.global_position = mender.global_position + Vector2(110.0, 0.0)
		await physics_frame
		var bits: int = _bots[1].intent.pressed_bits | _bots[1].intent.held_bits
		if bits & (1 << ATTACK_HAND) != 0:
			attacks += 1
		if bits & (1 << HEAL_HAND) != 0:
			heals += 1
	if is_instance_valid(foe):
		foe.queue_free()
	check(attacks > 0, "the mend bot fought the foe with its attack (LB)")
	check_equal(heals, 0, "and never pressed its heal at it")


## A heal heals whatever it hits: with a foe on its line of fire the mend bot holds the heal (and
## only the heal: its fighting staff still goes).
func test_the_mend_bot_holds_its_heal_with_a_foe_in_its_line() -> void:
	var pair: Array = await _built_pair()
	if pair.is_empty():
		return
	var mender: Actor = pair[1]
	var bot: BotScript = _bots[1]
	# A fresh brain reads its staffs at its first think (the build is on them now).
	bot.brain.setup(mender, BotScript.PROFILE, BotScript.SEED + 1)
	bot.brain.think(1.0 / 60.0, bot.intent)
	var heals: int = 0
	var hurts: int = 0
	for at in bot.brain.staff_count:
		var sense: CastSense = bot.brain.senses[at]
		if sense != null and not sense.empty:
			if sense.heals:
				heals |= 1 << at
			elif sense.harms():
				hurts |= 1 << at
	check(heals != 0 and hurts != 0, "the mender holds a heal and a staff that hurts")
	check_equal(bot.held_heal(heals | hurts), hurts, "a held heal keeps the staff that hurts")
	check(bot.heal_reach() > 0.0, "its heal reaches out")
	check(not bot.foe_in_line(mender, Vector2.RIGHT, bot.heal_reach()), "no foe in the start room's line")
	# A teammate is no foe: P1 straight ahead does not hold the heal.
	var first: Actor = pair[0]
	first.global_position = mender.global_position + Vector2(60.0, 0.0)
	check(not bot.foe_in_line(mender, Vector2.RIGHT, bot.heal_reach()), "a teammate ahead is no foe")
	# A foe (an enemy actor of the crypt) beyond the teammate, still within the heal's reach (a heal
	# that misses flies on): the heal is held.
	var foe := (load("res://content/enemies/crypt_mite/crypt_mite.tscn") as PackedScene).instantiate() as Actor
	(_flow.get(&"world") as Node2D).add_child(foe)
	foe.global_position = mender.global_position + Vector2(120.0, 6.0)
	await physics_frame
	foe.global_position = mender.global_position + Vector2(120.0, 6.0)
	check(bot.foe_in_line(mender, Vector2.RIGHT, bot.heal_reach()), "a foe beyond the teammate holds the heal")
	check(not bot.foe_in_line(mender, Vector2.UP, bot.heal_reach()), "a foe aside does not")
	check(not bot.foe_in_line(mender, Vector2.RIGHT, 60.0), "nor one past the reach")
	# Regression (the playtest of 2026-11-20): a foe pressed against the mender took the heal as it
	# left the staff, whichever way it was aimed.
	foe.global_position = mender.global_position + Vector2(-6.0, 2.0)
	check(bot.foe_in_line(mender, Vector2.RIGHT, bot.heal_reach()), "a foe on top of the mender holds the heal, aimed away")
	check(bot.foe_in_line(mender, Vector2.ZERO, bot.heal_reach()), "and with no aim at all")
	foe.queue_free()


## The line test itself: ahead, within the clearance, nearer than the reach.
func test_a_point_near_the_line_is_in_it() -> void:
	check(BotScript._near_line(Vector2.ZERO, Vector2.RIGHT, Vector2(100.0, 10.0), 200.0, BotScript.FOE_CLEAR), "ahead and near the line")
	check(not BotScript._near_line(Vector2.ZERO, Vector2.RIGHT, Vector2(100.0, 40.0), 200.0, BotScript.FOE_CLEAR), "too far aside")
	check(not BotScript._near_line(Vector2.ZERO, Vector2.RIGHT, Vector2(-30.0, 0.0), 200.0, BotScript.FOE_CLEAR), "behind")
	check(not BotScript._near_line(Vector2.ZERO, Vector2.RIGHT, Vector2(300.0, 0.0), 200.0, BotScript.FOE_CLEAR), "past the reach")


## End to end (the review of 2026-11-20), through the frames the bot fills with a hurt teammate in
## reach: a foe pressed against the mender (a heal any way it aims would hit it as it leaves the
## staff) and the heal staff is never pressed or held; a foe in the line past the teammate, and no
## heal lands on it. Without the gate in `step` the brain's `heal ally` presses it.
func test_the_mend_bot_never_heals_a_foe() -> void:
	var pair: Array = await _built_pair()
	if pair.is_empty():
		return
	var first: Actor = pair[0]
	var mender: Actor = pair[1]
	_bots[0].mode = BotScript.Mode.IDLER
	first.health.health = first.health.max_health * 0.4
	var foe := (load("res://content/enemies/crypt_mite/crypt_mite.tscn") as PackedScene).instantiate() as Actor
	(_flow.get(&"world") as Node2D).add_child(foe)
	var foe_healed: Array[float] = [0.0]
	var on_hit := func(caster: int, target: Node, amount: float, _at: Vector2, kind: StringName, _shot: int, _card: StringName) -> void:
		if kind == &"heal" and caster == mender.id and target == foe:
			foe_healed[0] += amount
	_events.connect("hit_landed", on_hit)
	var pressed: int = await _heal_presses(first, mender, foe, Vector2(-8.0, 0.0))
	check(is_instance_valid(foe) and not foe.is_down(), "the foe stood there the whole time")
	check_equal(pressed, 0, "the heal staff (RB) is never pressed with a foe pressed against the mender")
	await _heal_presses(first, mender, foe, Vector2(110.0, 4.0))
	_events.disconnect("hit_landed", on_hit)
	check_equal(foe_healed[0], 0.0, "no heal lands on a foe in the line past the teammate")
	foe.queue_free()


## HEAL_FRAMES physics frames with `first` (hurt) 60 px right of `mender` and `foe` at `foe_at` from
## it, kept there and alive; returns the heal staff's bit (RB's) if any frame P2's bot filled pressed
## or held it, else 0.
func _heal_presses(first: Actor, mender: Actor, foe: Actor, foe_at: Vector2) -> int:
	var frames: Node = root.get_node("Frames")
	var heal_bit: int = 1 << 0
	var pressed: int = 0
	for i in HEAL_FRAMES:
		first.global_position = mender.global_position + Vector2(60.0, 0.0)
		foe.global_position = mender.global_position + foe_at
		if foe.health != null:
			# Hurt (a heal would show) and never killed by the mender's fighting staff.
			foe.health.max_health = 10000.0
			foe.health.health = 5000.0
		await physics_frame
		var frame: InputFrame = frames.call("frame_of", 1)
		pressed |= (frame.pressed_bits | frame.held_bits) & heal_bit
	return pressed
