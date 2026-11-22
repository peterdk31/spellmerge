extends "res://tests/support/suite.gd"
## Tests for the bots' hub errand (bench/bots/bot_hub.gd; the owner, 2026-11-20, after #886: the
## bots' runs start in the hub, where each takes a staff from the rack as a player would): two bots
## started in the hub (the hub recorded, as the runners start it) draw their builds there, the mender
## walks to the rack's Firebolt and takes it with A, both walk onto the teleporter stone and P1
## starts the run with A, and the run's wizards carry the builds in (the rack staff on the mender's
## LB, its cards as they lay). The same replay seed plays the same errand, tick for tick. A bot with
## no build only walks to the stone.

const BotScript := preload("res://bench/bots/bot.gd")
const BuildsScript := preload("res://bench/bots/bot_builds.gd")
const HubScript := preload("res://bench/bots/bot_hub.gd")

## The replay seed the hub is recorded with (the builds and the run's seed follow from it).
const REPLAY_SEED: int = 11
## Physics frames the bots are given to start the run from the hub (a few game seconds' walk).
const HUB_FRAMES: int = 900

var _input: Node
var _flow: Node
var _events: Node
var _items: Node
var _bots: Array[BotScript] = []
var _bag_had: Array[StringName] = []


func before_each() -> void:
	_input = root.get_node("PlayerInput")
	_flow = root.get_node("Flow")
	_events = root.get_node("Events")
	_items = root.get_node("Items")
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


## What a hub errand of `teams` (each bot's team for its build: 0 none) came to: the frame the run
## started on (-1: never), whether the mender held its rack staff while still in the hub, and each
## bot's build name and whether its wizard holds the build as the run starts.
func _play_hub(teams: Array[int]) -> Dictionary:
	for index in teams.size():
		var bot := BotScript.new()
		if bot.join(index, BotScript.Mode.FIGHTER, _input, _flow):
			bot.plan_hub(teams[index], index == 0)
			_bots.append(bot)
	check_equal(_bots.size(), teams.size(), "every bot joined")
	root.get_node("Frames").call("record", &"hub_requested", 0, REPLAY_SEED)
	var out: Dictionary = {"started": -1, "rack_in_hub": false, "taken_from_ground": false}
	var rack: StaffItem = BuildsScript.RACK_STAFF
	var lay_count: int = -1
	for frame in HUB_FRAMES:
		await physics_frame
		if _flow.get(&"mode") == _flow.get(&"MODE_RUN") and _flow.get(&"world") != null and _flow.call("get_wizard", 0) != null:
			out["started"] = frame
			break
		if _flow.get(&"mode") != _flow.get(&"MODE_HUB"):
			continue
		var lying: int = 0
		for row: GroundItem in _items.call("lying"):
			if HubScript.is_rack_staff(row.stack, rack):
				lying += 1
		if lay_count > 0 and lying == 0:
			out["taken_from_ground"] = true
		lay_count = lying
		if teams.size() > BuildsScript.MEND_SEAT and HubScript.holds_rack_staff(_flow.call("get_wizard", BuildsScript.MEND_SEAT) as Actor, rack):
			out["rack_in_hub"] = true
	await physics_frame
	for bot in _bots:
		var wizard := _flow.call("get_wizard", bot.player) as Actor
		out["build %d" % bot.player] = bot.build.get("name", "")
		out["holds %d" % bot.player] = bot.holds_build(wizard)
		out["at %d" % bot.player] = wizard.global_position if wizard != null else Vector2.INF
	out["run seed"] = int((root.get_node("Tick").get(&"sim") as Sim).run_seed)
	return out


func test_the_mender_takes_its_rack_staff_in_the_hub_and_carries_it_into_the_run() -> void:
	var got: Dictionary = await _play_hub([2, 2] as Array[int])
	check(int(got["started"]) >= 0, "the bots started the run from the hub's stone")
	check(bool(got["rack_in_hub"]), "the mender held the rack's staff in the hub")
	check(bool(got["taken_from_ground"]), "taken off the ground (with A, as a player takes it), not given")
	check_equal(got["build 1"], "mender", "P2 drew the mender's build")
	check(bool(got["holds 0"]), "P1 carried its build into the run (%s)" % got["build 0"])
	check(bool(got["holds 1"]), "P2 carried its three staffs into the run")
	var mender := _flow.call("get_wizard", 1) as Actor
	if mender == null:
		return
	var hands: PackedInt32Array = mender.inventory.hands()
	check(hands.size() > 2 and hands[2] != Inventory.NO_STAFF, "the rack staff is on the mender's LB")
	if hands.size() > 2 and hands[2] != Inventory.NO_STAFF:
		check(HubScript.is_rack_staff(mender.inventory.staff(hands[2]), BuildsScript.RACK_STAFF), "the Firebolt, its cards as they lay on the rack")


func test_the_same_replay_seed_plays_the_same_errand() -> void:
	var first: Dictionary = await _play_hub([2, 2] as Array[int])
	await after_each()
	before_each()
	var second: Dictionary = await _play_hub([2, 2] as Array[int])
	check(int(first["started"]) >= 0, "the first errand started the run")
	for key: String in first:
		check_equal(second.get(key), first[key], "the second errand's %s" % key)


func test_a_bot_with_no_build_only_walks_to_the_stone() -> void:
	var got: Dictionary = await _play_hub([0, 0] as Array[int])
	check(int(got["started"]) >= 0, "the bots started the run from the stone")
	check(not bool(got["taken_from_ground"]), "no bot took the rack's staff")
	check_equal(got["build 1"], "", "and P2 drew no build")
	var wizard := _flow.call("get_wizard", 1) as Actor
	check(wizard != null and not HubScript.holds_rack_staff(wizard, BuildsScript.RACK_STAFF), "P2 holds no rack staff")


func test_the_seats_stand_apart_on_the_stone() -> void:
	var stone := Rect2(Vector2(752.0, 496.0), Vector2(96.0, 96.0))
	var spots: Array[Vector2] = []
	for seat in 4:
		var spot: Vector2 = HubScript.spot_on(stone, seat)
		check(stone.grow(-HubScript.SPOT_REACH).has_point(spot), "seat %d's spot is on the stone" % seat)
		for other in spots:
			check(spot.distance_to(other) >= HubScript.SPOT_APART, "seat %d's spot is apart from the others" % seat)
		spots.append(spot)


func test_only_the_firebolt_is_the_menders_rack_staff() -> void:
	var rack: StaffItem = BuildsScript.RACK_STAFF
	check(HubScript.is_rack_staff(rack.stack(), rack), "the Firebolt is")
	var wild: StaffItem = load("res://content/items/staffs/wild_star/wild_star.tres") as StaffItem
	check(not HubScript.is_rack_staff(wild.stack(), rack), "the Wild star is not")
	var same_staff_other_cards: ItemStack = ItemStack.of_staff(rack.staff, [&"bolt"] as Array[StringName])
	check(not HubScript.is_rack_staff(same_staff_other_cards, rack), "its staff with other cards is not")
	var sentry: StaffItem = load("res://content/items/staffs/patient_sentry/patient_sentry.tres") as StaffItem
	check(not HubScript.is_rack_staff(sentry.stack(), rack), "another premade staff is not")


## Regression (the review of 2026-11-20): the stone lights once every wizard is in its area, so a bot
## still walking to its corner departs with the party; its errand is done all the same, never begun
## again in a later hub.
func test_leaving_the_hub_from_any_stage_ends_the_errand() -> void:
	for stage: HubScript.Stage in [HubScript.Stage.RACK, HubScript.Stage.BUILD, HubScript.Stage.STONE, HubScript.Stage.WAIT]:
		var errand := HubScript.new()
		errand.stage = stage
		errand.left_hub()
		check_equal(errand.stage, HubScript.Stage.DONE, "left from %s" % HubScript.Stage.keys()[stage])


## A bot whose errand has not begun (Flow still idle before the hub starts) is not done by it.
func test_an_errand_not_begun_is_not_ended_by_an_idle_flow() -> void:
	var bot := BotScript.new()
	bot.use_flow(_flow)
	bot.plan_hub(2, true)
	_flow.call("stop_run")
	bot.step(1.0 / 60.0)
	check_equal(bot.hub.stage, HubScript.Stage.RACK, "the errand waits for the hub")
