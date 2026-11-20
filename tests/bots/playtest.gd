extends "res://tests/support/screenshot.gd"
## A playtest run: 1-4 fighter bots play a whole crypt biome, fight after fight to the boss, and
## the script prints what went wrong on the way (a playtest report; gates nothing, runs in no build).
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/bots/playtest.gd -- --players=4 --seed=11
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --fixed-fps 60 --path . --script res://tests/bots/playtest.gd -- --players=2 --seed=3 --split=equal --shots
##
## Lines (`PLAYTEST <game seconds>: ...`): each room entered and fight cleared, each down and revive,
## `stuck` (a standing bot out of a fight that moved under STUCK_MOVE pixels in STUCK_TICKS ticks),
## `long fight` (over LONG_FIGHT seconds); at the end `PLAYTEST RESULT`, the world's sounds started
## (`sounds`, and `doubled sound`: one id started twice at one place in one frame), `one body hit
## twice in a frame by one caster's card`, and every error logged; `PLAYTEST downs` the downs by
## bot. The arguments are in tests/README.md (`bots/`). The bots start in the hub (the owner,
## 2026-11-20, after #886), as players do: each plays its hub errand (tests/bots/bot_hub.gd), drawing
## its build from the hub's dice (tests/bots/bot_builds.gd: a fighter's strong staff and a dash, and
## with two or more P2's mend, dash and the rack's Wild star rebuilt as an attack), and all walk onto
## the teleporter stone, where P1 starts the run; `PLAYTEST heals` says what each bot's heals gave to
## teammates and to foes. `--plain` plays the starter staffs instead and `--build` the smoke test's
## old random staffs (set as the run starts); with either the bots only walk to the stone. With `--shots` (on a display) it saves screenshots as `playtest_<seed>_<players>_<what>`
## in the hub as the rack's staff is taken and as the party stands on the lit stone, at the first
## room of each kind, the first reward offer, the boss's intro, every stuck spot and long fight, and
## with `--every=S` one every S game seconds.
##
## The bots page a boss's intro on as a player's A would (`boss_intro_next_requested`, seat 0), and
## `--sturdy` heals the standing wizards every half second: a playtest looks for rough edges on the way
## to the boss, not at the balance (the seed sweep's, tests/smoke/four_bot_sweep.gd).

const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const BuildsScript := preload("res://tests/bots/bot_builds.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const STUCK_TICKS: int = 600
const STUCK_MOVE: float = 24.0
const LONG_FIGHT: float = 90.0
const DEFAULT_LIMIT: float = 1500.0
## Game seconds the bots are given in the hub to start the run.
const HUB_LIMIT: float = 60.0

var _players: int = 4
var _seed: int = 11
var _limit: float = DEFAULT_LIMIT
var _shots: bool = false
var _sturdy: bool = false
var _build: bool = false
var _plain: bool = false
var _bag_had: Array[StringName] = []
var _built: bool = false
var _split: int = SplitScreenSetting.DYNAMIC
var _bots: Array[BotScript] = []
var _flow: Node
var _events: Node
var _log: Logger = ErrorLogScript.new()
var _ticks: int = 0
var _ended: int = -1
var _last_at: Array[Vector2] = []
var _last_tick: PackedInt32Array = PackedInt32Array()
var _stuck_said: Array[Vector2] = []
var _started_at: Dictionary = {}
var _long_said: Dictionary = {}
var _kinds_shot: Dictionary = {}
var _reward_shot: bool = false
var _intro_page: int = -1
var _intro_wait: int = 0
var _cleared: int = 0
var _boss_cleared: bool = false
var _fights: int = 0
var _downs: int = 0
## True once the run from the stone entered its start room, and the tick it did.
var _run_started: bool = false
var _run_tick: int = 0
var _downs_by: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _shot_queue: Array[String] = []
var _every: int = 0
var _audio: Node
var _sounds_seen: int = 0
var _doubles: Dictionary = {}
var _sound_counts: Dictionary = {}
var _hits_now: Dictionary = {}
## The tick a hit was last counted on (a frame a tick: `--fixed-fps 60`).
var _hits_tick: int = -1
var _hit_twice: Dictionary = {}
## The heals the bots' spells landed: by seat, health given to a teammate (itself too), to the
## world's bodies (a prop: `Actors.TEAM_WORLD`) and to a foe, and how many heals each.
var _healed_mates: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _healed_foes: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _healed_world: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _heals: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


func _init() -> void:
	pin_room = false


func take() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="):
			_players = clampi(arg.trim_prefix("--players=").to_int(), 1, 4)
		elif arg.begins_with("--seed="):
			_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--limit="):
			_limit = arg.trim_prefix("--limit=").to_float()
		elif arg == "--shots":
			_shots = DisplayServer.get_name() != "headless"
		elif arg.begins_with("--every="):
			_every = arg.trim_prefix("--every=").to_int() * 60
		elif arg == "--sturdy":
			_sturdy = true
		elif arg == "--build":
			_build = true
		elif arg == "--plain":
			_plain = true
		elif arg == "--split=equal":
			_split = SplitScreenSetting.EQUAL
	_flow = root.get_node("Flow")
	_events = root.get_node("Events")
	var input: Node = root.get_node("PlayerInput")
	var feel: Node = root.get_node_or_null("Feel")
	if feel != null:
		feel.call("set_split_mode", _split)
	OS.add_logger(_log)
	_audio = root.get_node_or_null("Audio")
	for index in _players:
		var bot := BotScript.new()
		if not bot.join(index, BotScript.Mode.FIGHTER, input, _flow):
			fail("bot %d could not join" % (index + 1))
			return
		# The hub's errand: a drawn build for the whole team (none with `--plain` or `--build`); P1 starts.
		bot.plan_hub(0 if _plain or _build else _players, index == 0)
		_bots.append(bot)
		_last_at.append(Vector2.INF)
		_last_tick.append(0)
	_events.connect("room_entered", _on_room_entered)
	_events.connect("room_cleared", _on_room_cleared)
	_events.connect("player_downed", func(p: int) -> void: _downs += 1; _downs_by[clampi(p, 0, 3)] += 1; _say("downed P%d" % (p + 1)))
	_events.connect("player_revived", func(p: int, r: int) -> void: _say("revived P%d by P%d" % [p + 1, r + 1]))
	_events.connect("run_ended", func(victory: bool) -> void: _say("run ended, victory %s" % victory); _ended = 1 if victory else 0)
	_events.connect("rewards_waiting_changed", _on_rewards)
	_events.connect("hit_landed", _on_hit_landed)
	_events.connect("boss_intro_opened", func(_a: int, _n: String, _l: String, _i: Resource, page: int, _f: bool) -> void: _intro_page = page; _intro_wait = 150; _queue_shot("boss_intro"))
	_events.connect("boss_intro_paged", func(page: int) -> void: _intro_page = page; _intro_wait = 90)
	_events.connect("boss_intro_closed", func(_a: int) -> void: _intro_page = -1)
	if not _plain and not _build:
		_bag_had = BuildsScript.stock(_flow)
	var frames: Node = root.get_node("Frames")
	frames.call("record", &"hub_requested", 0, _seed)
	var tick: Node = root.get_node("Tick")
	print("PLAYTEST start in the hub: %d players, replay seed %d, split %d" % [_players, _seed, _split])
	var rack_shot: bool = false
	while not _run_started and float(_ticks) / 60.0 < HUB_LIMIT:
		await process_frame
		_ticks += 1
		# In the hub: a shot as the rack's staff is taken and one as the party stands on the stone.
		for bot in _bots:
			var wizard := _flow.call("get_wizard", bot.player) as Actor
			var rack: StaffItem = BuildsScript.rack_of(bot.build)
			if not rack_shot and rack != null and BotScript.HubScript.holds_rack_staff(wizard, rack):
				rack_shot = true
				_say("P%d took the rack's %s" % [bot.player + 1, rack.id])
				_queue_shot("hub_rack")
		if bool(_flow.call("is_stone_lit")) and not _kinds_shot.has(&"hub_stone"):
			_kinds_shot[&"hub_stone"] = true
			_say("the party stands on the lit stone")
			_queue_shot("hub_stone")
		while not _shot_queue.is_empty():
			var what: String = _shot_queue.pop_front()
			save(await grab(), "playtest_%d_%d%s_%s" % [_seed, _players, "e" if _split == SplitScreenSetting.EQUAL else "", what])
	if not _run_started:
		_say("the run never started from the hub's stone")
		_ended = 0
	else:
		_say("the run started from the hub's stone, run seed %d" % int(tick.get("sim").get("run_seed")))
	# `--limit` counts the run's time, not the hub's.
	while _ended < 0 and float(_ticks - _run_tick) / 60.0 < _limit:
		await process_frame
		_ticks += 1
		if _flow.get("mode") != _flow.get("MODE_RUN"):
			_say("back in the hub")
			_ended = 1 if _boss_cleared else 0
			break
		_watch()
		_listen()
		if _sturdy and _ticks % 30 == 0:
			for index in _bots.size():
				var wizard := _flow.call("get_wizard", index) as Actor
				if wizard != null and not wizard.is_down() and wizard.health != null:
					wizard.health.heal(wizard.health.max_health)
		if _intro_page >= 0:
			_intro_wait -= 1
			if _intro_wait == 0:
				_events.emit_signal("boss_intro_next_requested", 0, _intro_page)
				_intro_wait = 90
		if _shots and _every > 0 and _ticks % _every == 0:
			_queue_shot("t%04d" % (_ticks / 60))
		while not _shot_queue.is_empty():
			var what: String = _shot_queue.pop_front()
			save(await grab(), "playtest_%d_%d%s_%s" % [_seed, _players, "e" if _split == SplitScreenSetting.EQUAL else "", what])
	var world: BiomeWorld = _flow.get("biome") as BiomeWorld
	var map: BiomeMap = world.map if world != null else null
	print("PLAYTEST RESULT: %s, %d players, seed %d: %d of %d fights cleared, %d downs, %.0f game s, errors %d" % [
		"WON" if _ended == 1 else ("LOST" if _ended == 0 else "TIMEOUT"), _players, _seed, _cleared, _fights, _downs, float(_ticks) / 60.0, _log.call("get_lines").size()])
	var counts: Array = []
	for id: StringName in _sound_counts:
		counts.append("%s %d" % [id, _sound_counts[id]])
	print("PLAYTEST sounds: " + ", ".join(counts))
	var by: Array[String] = []
	for seat in _bots.size():
		by.append("P%d %d" % [seat + 1, _downs_by[seat]])
	print("PLAYTEST downs: " + ", ".join(by))
	for what: String in _hit_twice:
		print("PLAYTEST one body hit twice in a frame by one caster's card: %s, %d times" % [what, _hit_twice[what]])
	for id: StringName in _doubles:
		print("PLAYTEST doubled sound: %s, %d times two or more at one place in one frame" % [id, _doubles[id]])
	for seat in _bots.size():
		if _heals[seat] > 0:
			print("PLAYTEST heals: P%d healed %d times, %.0f health to teammates, %.0f to props, %.0f to foes" % [seat + 1, _heals[seat], _healed_mates[seat], _healed_world[seat], _healed_foes[seat]])
	for line: String in _log.call("get_lines"):
		print("PLAYTEST error: " + line)
	if _ended < 0 and map != null:
		var life: RoomLife = _flow.get("life") as RoomLife
		for room in map.rooms():
			print("PLAYTEST left: room %d %s %s flags %d" % [room, map.room_templates[room], map.room_kinds[room], life.flags[room] if room < life.flags.size() else -1])
	OS.remove_logger(_log)
	for bot in _bots:
		bot.leave()
	if not _plain and not _build:
		_flow.set(&"play_bag", _bag_had)


## A report line, with the game time.
func _say(text: String) -> void:
	print("PLAYTEST %.1f: %s" % [float(_ticks) / 60.0, text])


## A screenshot `what` saved after this frame (with `--shots`).
func _queue_shot(what: String) -> void:
	if _shots:
		_shot_queue.append(what)


func _on_room_entered(_room_id: StringName, room: int) -> void:
	var biome: BiomeWorld = _flow.get("biome") as BiomeWorld
	var map: BiomeMap = biome.map if biome != null and _flow.get("mode") == _flow.get("MODE_RUN") else null
	if map == null or room < 0 or room >= map.rooms():
		return
	var kind: StringName = map.room_kinds[room]
	var life: RoomLife = _flow.get("life") as RoomLife
	if life.fights[room].has_enemies():
		_fights = 0
		for r in map.rooms():
			if life.fights[r].has_enemies():
				_fights += 1
	if room == 0 and not _run_started:
		_run_started = true
		_run_tick = _ticks
	_say("entered room %d (%s, %s)" % [room, map.room_templates[room], kind])
	if room == 0 and not _plain and not _built:
		_built = true
		for index in _bots.size():
			if _build:
				_bots[index].build_random(2026 + index)
				_say("P%d built %s" % [index + 1, _bots[index].built_cards])
			else:
				# Built in the hub: it carried its build in (or says it did not).
				var bot: BotScript = _bots[index]
				var carried: bool = bot.holds_build(_flow.call("get_wizard", index) as Actor)
				_say("P%d carried %s %s%s" % [index + 1, bot.build.get("name", "none"), bot.build.get("staffs", []), "" if carried else " NOT on its staffs"])
	_started_at[room] = _ticks
	if not _kinds_shot.has(kind):
		_kinds_shot[kind] = true
		_queue_shot("room_%s_%s" % [kind, map.room_templates[room]])


func _on_room_cleared(_room_id: StringName, room: int) -> void:
	var life: RoomLife = _flow.get("life") as RoomLife
	if _flow.get("mode") != _flow.get("MODE_RUN") or life == null or room < 0 or room >= life.fights.size() or not life.fights[room].has_enemies():
		return
	_cleared += 1
	var map: BiomeMap = (_flow.get("biome") as BiomeWorld).map
	if map != null and map.room_kinds[room] == &"boss":
		_boss_cleared = true
		_ended = 1
	_say("cleared room %d after %.1f s" % [room, float(_ticks - int(_started_at.get(room, _ticks))) / 60.0])


func _on_rewards(_seat: int, offers: Array[Dictionary]) -> void:
	if not offers.is_empty() and not _reward_shot:
		_reward_shot = true
		_queue_shot("reward")


## A fight running past LONG_FIGHT, and a standing bot out of a fight that has not moved.
func _watch() -> void:
	var life: RoomLife = _flow.get("life") as RoomLife
	var map: BiomeMap = (_flow.get("biome") as BiomeWorld).map
	if map == null:
		return
	for room: int in _started_at:
		if room < life.rooms() and life.has(room, RoomLife.STARTED) and not life.has(room, RoomLife.CLEARED) and not _long_said.has(room):
			if float(_ticks - int(_started_at[room])) / 60.0 > LONG_FIGHT:
				_long_said[room] = true
				_say("long fight in room %d (%s): over %d s" % [room, map.room_templates[room], int(LONG_FIGHT)])
				_queue_shot("long_fight_%d" % room)
	for index in _bots.size():
		var wizard := _flow.call("get_wizard", index) as Actor
		if wizard == null or wizard.is_down():
			_last_at[index] = Vector2.INF
			continue
		var here: Vector2 = wizard.global_position
		var in_fight: bool = wizard.room >= 0 and wizard.room < life.rooms() and life.has(wizard.room, RoomLife.STARTED) and not life.has(wizard.room, RoomLife.CLEARED)
		if in_fight or _last_at[index] == Vector2.INF or here.distance_to(_last_at[index]) > STUCK_MOVE:
			_last_at[index] = here
			_last_tick[index] = _ticks
			continue
		if _ticks - _last_tick[index] >= STUCK_TICKS:
			_last_tick[index] = _ticks
			var said: bool = false
			for spot in _stuck_said:
				if spot.distance_to(here) < 48.0:
					said = true
			var where: String = ("room %d %s" % [wizard.room, map.room_templates[wizard.room]]) if wizard.room >= 0 and wizard.room < map.rooms() else ("bridge %d %s" % [wizard.room - map.rooms(), map.bridge_templates[wizard.room - map.rooms()] if wizard.room - map.rooms() < map.bridges() else "?"])
			if not said:
				_stuck_said.append(here)
				_say("stuck P%d at %s in %s" % [index + 1, here, where])
				_queue_shot("stuck_p%d_%d" % [index + 1, _ticks])


## The world's one-shots started this frame (Voices' own members, read by name: a playtest tool):
## counted by id, and an id started twice or more at one place (within 12 px) in one frame noted as
## doubled.
func _listen() -> void:
	if _audio == null:
		return
	var voices: Node = _audio.get("voices")
	if voices == null:
		return
	var started: int = int(voices.get("started"))
	if started == _sounds_seen:
		return
	var fresh: int = started - _sounds_seen
	_sounds_seen = started
	var got_ids: Variant = voices.get("_voice_id")
	var got_from: Variant = voices.get("_from")
	var got_placed: Variant = voices.get("_placed")
	if not (got_ids is Array and got_from is PackedFloat64Array and got_placed is Array) or (got_placed as Array).size() != (got_ids as Array).size():
		# Voices' members changed (this reads them by name), or its voices are flat (no place).
		return
	var ids: Array = got_ids
	var from: PackedFloat64Array = got_from
	var placed: Array = got_placed
	var clock: float = float(voices.get("_clock"))
	var now: Array[int] = []
	for i in ids.size():
		if from[i] == clock and ids[i] != &"":
			now.append(i)
	for i in now:
		_sound_counts[ids[i]] = int(_sound_counts.get(ids[i], 0)) + 1
	if fresh < 2:
		return
	var said: Dictionary = {}
	for a in now.size():
		for b in range(a + 1, now.size()):
			var i: int = now[a]
			var j: int = now[b]
			if ids[i] == ids[j] and not said.has(ids[i]) and (placed[i] as Node2D).global_position.distance_to((placed[j] as Node2D).global_position) < 12.0:
				said[ids[i]] = true
				_doubles[ids[i]] = int(_doubles.get(ids[i], 0)) + 1


## A body hit twice in one frame by one caster's card of one kind (a step's hits of one spell on one
## body are one hit: the owner, 2026-11-17; two casts of one card are two spells).
func _on_hit_landed(caster: int, target: Node, amount: float, _at: Vector2, kind: StringName, _shot: int, card: StringName) -> void:
	if kind == &"heal":
		_count_heal(caster, target, amount)
		return
	if kind == &"status":
		return
	if _hits_tick != _ticks:
		_hits_tick = _ticks
		_hits_now.clear()
	var key: String = "%d %d %s %s" % [caster, target.get_instance_id(), kind, card]
	if _hits_now.has(key):
		var what: String = "%s %s" % [kind, card]
		_hit_twice[what] = int(_hit_twice.get(what, 0)) + 1
	_hits_now[key] = true


## A heal of the actor `caster` on `target`: counted for the bot whose wizard cast it, as given to a
## teammate (its own team), to a prop (the world's team) or to a foe.
func _count_heal(caster: int, target: Node, amount: float) -> void:
	for seat in _bots.size():
		var wizard := _flow.call("get_wizard", seat) as Actor
		if wizard == null or wizard.id != caster:
			continue
		var body := target as Actor
		_heals[seat] += 1
		if body == null:
			# A body that is no actor (none heals today): counted as a prop's, never a foe's.
			_healed_world[seat] += amount
		elif body.team() == wizard.team():
			_healed_mates[seat] += amount
		elif body.team() == ActorsScript.TEAM_WORLD:
			_healed_world[seat] += amount
		else:
			_healed_foes[seat] += amount
		return
