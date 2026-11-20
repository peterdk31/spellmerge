extends "res://tests/support/suite.gd"
## Tests for the bots' starting builds (tests/bots/bot_builds.gd) and the mend bot (tests/bots/bot.gd,
## `build_drawn`, `foe_in_line`): every build of the table is valid by the card rules on the starter
## staffs (no card wasted, one cast a staff, the attack hurts, the dash moves its caster, the mend
## heals and hurts nobody), the bag builds each, the draw is the run's dice (the same seed the same
## builds), only P2 of a team of two or more mends, and in a run the mend bot heals a hurt teammate
## and holds its heal while a foe stands in its line of fire.

const BotScript := preload("res://tests/bots/bot.gd")
const BuildsScript := preload("res://tests/bots/bot_builds.gd")

## The starter staffs of Play by number (Flow.STARTER_HEADS: RB's, RT's).
const STAFF_IDS: Array[StringName] = [&"curl", &"star"]
## Physics frames the mend bot is given to heal (its staff ready, a bolt's flight).
const HEAL_FRAMES: int = 150

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
	_flow.set(&"play_bag", _bag_had)
	for index in 4:
		_input.call("leave", index)
	await commands_applied()


## The compiled staff of `cards` on the starter staff `number`.
func _compiled(cards: Array[StringName], number: int) -> CompiledStaff:
	var staff := root.get_node("Registry").call("get_resource", &"wizard", STAFF_IDS[number]) as StaffBase
	return root.get_node("Spells").call("compile_staff", cards, staff) as CompiledStaff


# --- The table ---------------------------------------------------------------------------------


func test_every_build_is_valid_by_the_card_rules() -> void:
	for build: Dictionary in BuildsScript.all():
		var staffs: Array = build["staffs"]
		check_equal(staffs.size(), STAFF_IDS.size(), "%s: a staff for RB and one for RT" % build["name"])
		for number in staffs.size():
			var cards: Array[StringName] = BuildsScript.cards_of(build, number)
			var compiled: CompiledStaff = _compiled(cards, number)
			check(cards.size() <= 6, "%s staff %d fits the starter staff's 6 slots" % [build["name"], number])
			check(compiled != null and not compiled.is_empty(), "%s staff %d casts" % [build["name"], number])
			if compiled == null:
				continue
			check(compiled.wasted.is_empty(), "%s staff %d wastes no card: %s" % [build["name"], number, compiled.wasted])
			check_equal(compiled.casts.size(), 1, "%s staff %d is one cast" % [build["name"], number])


## What the brain reads of each build: the fighters dash on RB and hurt on RT; the mender heals on
## RB, hurting nobody, and hurts on RT.
func test_each_build_has_the_staffs_its_bot_plays() -> void:
	for build: Dictionary in BuildsScript.all():
		var first: CastSense = _compiled(BuildsScript.cards_of(build, 0), 0).casts[0].sense
		var second: CastSense = _compiled(BuildsScript.cards_of(build, 1), 1).casts[0].sense
		if build == BuildsScript.MENDER:
			check(first.heals and not first.harms(), "the mender's RB heals and hurts nobody")
			check(first.reach > 0.0, "and is aimed (it reaches a teammate along a line)")
		else:
			check(first.moves_caster, "%s: RB dashes" % build["name"])
		check(second.harms() and not second.heals, "%s: RT hurts" % build["name"])


func test_the_bag_builds_every_build() -> void:
	var bag: Array[StringName] = BuildsScript.bag()
	for build: Dictionary in BuildsScript.all():
		var left: Array[StringName] = bag.duplicate()
		for number in (build["staffs"] as Array).size():
			for id: StringName in BuildsScript.cards_of(build, number):
				check(left.has(id), "%s: the bag holds its %s" % [build["name"], id])
				left.erase(id)


# --- The draw ----------------------------------------------------------------------------------


func test_the_same_run_seed_draws_the_same_builds() -> void:
	for run_seed: int in [1, 11, 12345, 987654321]:
		for seat in 4:
			check(BuildsScript.pick(Sim.seeded(run_seed), seat, 3) == BuildsScript.pick(Sim.seeded(run_seed), seat, 3), "seed %d seat %d: the same build" % [run_seed, seat])


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
	_events.emit_signal("play_requested", 0)
	await process_frame
	var first := _flow.call("get_wizard", 0) as Actor
	var mender := _flow.call("get_wizard", 1) as Actor
	if first == null or mender == null or _bots.size() < 2:
		check(false, "the run started with two bots' wizards")
		return []
	for bot in _bots:
		check(bot.build_drawn(2), "P%d draws its build" % (bot.player + 1))
	await commands_applied()
	await physics_frame
	return [first, mender]


func test_a_drawn_build_is_on_the_staffs() -> void:
	var pair: Array = await _built_pair()
	if pair.is_empty():
		return
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
	for i in HEAL_FRAMES:
		first.global_position = mender.global_position + Vector2(60.0, 0.0)
		await physics_frame
	_events.disconnect("hit_landed", on_hit)
	check(healed[0] > 0.0, "the mend bot's heals landed on its teammate (%.0f health)" % healed[0])
	check(first.health.health > before, "its teammate has more health (%.0f, was %.0f)" % [first.health.health, before])
	check_equal(foes[0], 0.0, "and no foe was healed")


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
	foe.queue_free()


## The line test itself: ahead, within the clearance, nearer than the reach.
func test_a_point_near_the_line_is_in_it() -> void:
	check(BotScript._near_line(Vector2.ZERO, Vector2.RIGHT, Vector2(100.0, 10.0), 200.0, BotScript.FOE_CLEAR), "ahead and near the line")
	check(not BotScript._near_line(Vector2.ZERO, Vector2.RIGHT, Vector2(100.0, 40.0), 200.0, BotScript.FOE_CLEAR), "too far aside")
	check(not BotScript._near_line(Vector2.ZERO, Vector2.RIGHT, Vector2(-30.0, 0.0), 200.0, BotScript.FOE_CLEAR), "behind")
	check(not BotScript._near_line(Vector2.ZERO, Vector2.RIGHT, Vector2(300.0, 0.0), 200.0, BotScript.FOE_CLEAR), "past the reach")
