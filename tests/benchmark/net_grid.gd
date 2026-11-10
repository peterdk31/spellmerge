extends SceneTree
## The netcode spike's grid (S2 and S5, docs/milestones/netcode-spike.md): two scripted fights
## linked by the sessions over the loopback (tests/net/net_pair.gd) at each round trip and loss of
## the grid, on a stepped clock, and the counters of each run: the input delay the client took,
## how long its presses took to come back, the host's ticks that stood a late frame in, the
## client's waits, the bytes a second each way, and the time the sessions spent on the link and on
## the hash checks a tick. Not run in the build (about a minute).
##
## The fights are small (a card's content fight), so the hash time here is a small world's; the
## bytes and the delays are the link's and the sessions', and do not depend on the world.
##
## `--guests=N` (online lobby L3): N guest machines of one seat each (1 to 3), every one on a link
## of the grid's; the host's columns are then its whole cost (every guest's bytes and link time,
## one hashing), the client's the first guest's.
##
## Prints `BENCH: net grid` lines and `NET GRID OK`.
##
## godot --headless --path . --script res://tests/benchmark/net_grid.gd [-- --ticks=N --card=ID --delay=D --guests=N]

const NetPair := preload("res://tests/net/net_pair.gd")
const ContentFight := preload("res://tests/core/content_fight.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## The round trips of the grid, in milliseconds.
const ROUND_TRIPS: Array[float] = [0.0, 50.0, 100.0, 150.0, 200.0]
## (jitter each way in milliseconds, loss each way)
const LINKS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 0.01), Vector2(20.0, 0.05)]


func _initialize() -> void:
	var ticks: int = 1800
	var card_id: StringName = &"bolt"
	var delay: int = -1
	var guests: int = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			ticks = maxi(arg.substr(8).to_int(), 120)
		elif arg.begins_with("--card="):
			card_id = StringName(arg.substr(7))
		elif arg.begins_with("--delay="):
			delay = arg.substr(8).to_int()
		elif arg.begins_with("--guests="):
			guests = clampi(arg.substr(9).to_int(), 1, NetHost.GUESTS)
	await process_frame
	var registry := RegistryScript.new()
	registry.scan()
	var card: SpellComponent = null
	for found: Resource in registry.get_all(&"spells"):
		if found is SpellComponent and (found as SpellComponent).id == card_id:
			card = found as SpellComponent
	if card == null:
		printerr("net_grid: no card %s" % card_id)
		registry.free()
		quit(1)
		return
	print("BENCH: net grid: %d ticks of %s a run, %d guest machine(s); rtt and jitter in ms, loss each way; delay in ticks at the end (and how often the ping moved it); press = the client's press to its tick, mean / worst ms; stood = host ticks with a late frame stood in; waited = client steps with no tick; B/s to the client / to the host; us/tick on the link (host / client) and hashing (host / client)" % [ticks, card_id, guests])
	var failed: bool = false
	for link in LINKS:
		for rtt in ROUND_TRIPS:
			failed = _run(card, ticks, rtt, link.x, link.y, delay, guests) or failed
	registry.free()
	if failed:
		printerr("net_grid: a run parted or did not finish")
		quit(1)
		return
	print("NET GRID OK")
	quit(0)


## One run of the grid; true when it failed (the machines parted, or the client did not finish).
func _run(card: SpellComponent, ticks: int, rtt_ms: float, jitter_ms: float, loss: float, delay: int, guests: int) -> bool:
	var seats: Array[int] = []
	for g in guests:
		seats.append(1 << (g + 1))
	var pair := NetPair.new(root, ContentFight.CARD, card, rtt_ms, jitter_ms, loss, delay, 1, [], seats)
	# The sessions' own checks say whether the machines agree; the per-tick capture is the tests'.
	pair.captures = false
	var failed: bool = not pair.start()
	pair.run(ticks)
	failed = not pair.let_client_catch_up() or failed
	pair.step(true, false)
	var host: NetStats = pair.host.totals()
	var client: NetStats = pair.client.stats
	failed = failed or host.mismatches > 0 or host.checks == 0 or pair.first_parting() >= 0
	for g in guests:
		failed = failed or pair.host.guests[g].problem != "" or pair.clients[g].problem != ""
	var seconds: float = float(ticks) / 60.0
	print("BENCH: net grid: rtt %3d jitter %2d loss %2d%%: delay %2d (moved %d), press %3d / %3d ms (%d), stood %4d, late %4d, waited %4d, most ahead %2d, %5d / %5d B/s, link %4.1f / %4.1f us/tick, hash %5.1f / %5.1f us/tick, checks %d ok%s" % [
		roundi(rtt_ms), roundi(jitter_ms), roundi(loss * 100.0),
		client.delay, client.retunes, roundi(client.press_ms()), roundi(client.press_steps_worst * NetStats.TICK_MS), client.presses,
		host.stood_in, host.late_frames, client.steps_waited, client.most_ahead,
		roundi(host.sent_bytes / seconds), roundi(client.sent_bytes / seconds),
		float(host.net_usec) / ticks, float(client.net_usec) / ticks,
		float(host.hash_usec) / ticks, float(client.hash_usec) / ticks,
		host.checks, " FAILED" if failed else "",
	])
	pair.free_all()
	return failed
