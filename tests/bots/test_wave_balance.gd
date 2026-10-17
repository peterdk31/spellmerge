extends SceneTree
## Balance probe for checkpoint C1: fighter bots play the fixed wave with 1, 2, 3 and
## 4 players, one run after the other, and print a `BALANCE:` line per run (game
## seconds to clear, health lost, wizards downed, casts). The wave is sized for four
## players (docs/milestones/M1-core-loop.md), so this is how "alone" and "with four"
## are compared from data.
##
## Gates, deliberately loose (the numbers are for people to read, not to pass):
##  - every run clears the room within TIME_LIMIT game seconds, or a wizard is
##    downed (a lost room restarts by itself, which is not a clear).
## Who gets downed is only reported: the bots play in real (scaled) time, so the health
## lost varies from run to run and a gate on it could break the daily build.
## The numbers are in docs/LOG.md.
##
## godot --headless --path . --script res://tests/bots/test_wave_balance.gd

const BotScript := preload("res://tests/bots/bot.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")

const COUNTS: Array[int] = [1, 2, 3, 4]
const TIME_LIMIT: float = 120.0
const TIME_SCALE: float = 2.0

var _failures: Array[String] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var events: Node = root.get_node_or_null("Events")
	var flow: Node = root.get_node_or_null("Flow")
	var input: Node = root.get_node_or_null("PlayerInput")
	if events == null or flow == null or input == null:
		printerr("TEST FAILED: the Events, Flow and PlayerInput autoloads must exist")
		quit(1)
		return
	for count in COUNTS:
		await _run(count, events, flow, input)
	if _failures.is_empty():
		print("TEST OK: wave balance (1-4 fighter bots; see the BALANCE lines)")
		quit(0)
	else:
		for reason in _failures:
			printerr("TEST FAILED: " + reason)
		quit(1)


func _run(count: int, events: Node, flow: Node, input: Node) -> void:
	var bots: Array[BotScript] = []
	var joined: bool = true
	for index in count:
		var bot := BotScript.new()
		if not bot.join(index, BotScript.Mode.FIGHTER, input, flow):
			_failures.append("bot %d could not take its virtual device" % (index + 1))
			joined = false
			break
		bots.append(bot)
	if not joined:
		for bot in bots:
			bot.leave()
		return
	var tally: Dictionary = {"cleared": false, "downed": 0, "casts": 0}
	var on_cleared := func(_room: StringName) -> void: tally["cleared"] = true
	var on_downed := func(_player: int) -> void: tally["downed"] = int(tally["downed"]) + 1
	var on_cast := func(_player: int, _spell: StringName, _origin: Vector2, _direction: Vector2) -> void:
		tally["casts"] = int(tally["casts"]) + 1
	events.connect("room_cleared", on_cleared)
	events.connect("player_downed", on_downed)
	events.connect("spell_cast", on_cast)
	Engine.time_scale = TIME_SCALE
	events.emit_signal("play_requested", 0)
	var elapsed: float = 0.0
	var wizards: Array[Node] = []
	for index in count:
		wizards.append(flow.call("get_wizard", index) as Node)
	# Health is sampled every frame, so a restart that frees the wizards cannot undercount.
	var lowest: Array[int] = []
	lowest.resize(count)
	lowest.fill(PlayerScript.MAX_HEALTH)
	var last: int = Time.get_ticks_usec()
	while elapsed < TIME_LIMIT and not bool(tally["cleared"]) and int(tally["downed"]) < count:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var delta: float = float(now - last) / 1000000.0 * TIME_SCALE
		last = now
		elapsed += delta
		for index in count:
			if is_instance_valid(wizards[index]):
				lowest[index] = mini(lowest[index], int(wizards[index].get("health")))
		for bot in bots:
			bot.step(delta)
	Engine.time_scale = 1.0
	events.disconnect("room_cleared", on_cleared)
	events.disconnect("player_downed", on_downed)
	events.disconnect("spell_cast", on_cast)
	for bot in bots:
		bot.leave()
	flow.call("stop_run")
	var lost: int = 0
	for health in lowest:
		lost += PlayerScript.MAX_HEALTH - health
	var cleared: bool = bool(tally["cleared"])
	print("BALANCE: %d player(s): %s in %.1f game seconds, %d health lost, %d downed, %d casts" % [
		count, "cleared" if cleared else "NOT cleared", elapsed, lost, int(tally["downed"]), int(tally["casts"])])
	if not cleared and int(tally["downed"]) == 0:
		_failures.append("%d player(s): the room was neither cleared nor lost in %d game seconds" % [count, int(TIME_LIMIT)])
	await process_frame
