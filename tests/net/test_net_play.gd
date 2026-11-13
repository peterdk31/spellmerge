extends "res://tests/support/suite.gd"
## Host and Join (netcode spike S4, docs/milestones/netcode-spike.md; net/net_play.gd, the autoload
## "NetPlay"): two machines in one process, each a scripted fight with its own bus, frames service
## and input layer and its own NetPlay, on a stepped clock, their codes swapped through a stand-in
## handshake (tests/net/loop_handshake.gd; the real one is tests/net/test_net_rtc.gd's). The
## requests the main menu sends walk both through their phases into one run, the same at every
## tick; each machine's devices sit on its own seat; a refused code or a failed handshake says why
## and leaves the machine as it was; a hash check that fails is said once and the run saved; and
## the other machine leaving ends it for the one that stays, whose game plays on.

const NetPlayScript := preload("res://net/net_play.gd")
const LoopHandshake := preload("res://tests/net/loop_handshake.gd")
const RoomHandshake := preload("res://tests/net/room_handshake.gd")
const ContentFight := preload("res://tests/core/content_fight.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

const CARD: StringName = &"bolt"
## Steps enough for the client's pings to tell the host it is ready.
const WARM_UP: int = 120
const KEYBOARD: int = InputManagerScript.KEYBOARD


## One machine: a fight, its NetPlay, and what its bus said.
class Machine:
	extends RefCounted
	var fight: ContentFight
	var play: NetPlayScript
	var handshake: LoopHandshake = null
	var room: RoomHandshake = null
	## Every seat that joined (seat + 1) or left (-seat - 1) on this machine.
	var seats: Array[int] = []
	## Every `online_changed`, as [phase, code, reason], and every line: its facts, and its counters.
	var changes: Array[Array] = []
	var lines: Array[Dictionary] = []
	var counters: PackedStringArray = PackedStringArray()
	## What was said that the bus does not allow: a reason that is no name of `OnlineWhy`, or a
	## fact that is not a number, a yes or no, a name or a room's code.
	var strays: PackedStringArray = PackedStringArray()
	## Its state after every tick of the online run, by tick.
	var run: Desync = Desync.new()
	var ticks: int = 0

	func _init(root: Node, card: SpellComponent, table: Dictionary) -> void:
		fight = ContentFight.new(root, ContentFight.CARD, card)
		play = NetPlayScript.new()
		play.events = fight.fight.bus
		play.frames = fight.frames
		play.input = fight.input
		play.areas = fight.areas
		play.handshake_maker = func() -> NetHandshake:
			handshake = LoopHandshake.new(table)
			return handshake
		play.room_handshake_maker = func() -> NetHandshake:
			room = RoomHandshake.new(table)
			return room
		root.add_child(play)
		play.set_physics_process(false)
		fight.fight.bus.online_changed.connect(_on_changed)
		fight.fight.bus.online_line_changed.connect(func(facts: Dictionary, line: String) -> void:
			lines.append(facts)
			counters.append(line)
			for key: Variant in facts:
				var fact: Variant = facts[key]
				var is_room: bool = key == OnlineWhy.LINE_ROOM and fact is String and NetSignal.is_room_code(fact)
				# The areas only on the host, whose names are its own.
				var is_areas: bool = key == OnlineWhy.LINE_PARTED_AREAS and fact is PackedStringArray and play.is_hosting()
				if not (fact is int or fact is bool or is_room or is_areas):
					strays.append("the line's fact %s: %s" % [key, fact]))
		fight.fight.bus.seat_joined.connect(func(seat: int) -> void: seats.append(seat + 1))
		fight.fight.bus.seat_left.connect(func(seat: int) -> void: seats.append(-seat - 1))

	func _on_changed(phase: StringName, code: String, reason: StringName, facts: Dictionary) -> void:
		changes.append([phase, code, reason])
		if reason != &"" and not OnlineWhy.ALL.has(reason):
			strays.append("the reason %s" % reason)
		if reason == &"" and not facts.is_empty():
			strays.append("facts with no reason: %s" % facts)
		for key: Variant in facts:
			var fact: Variant = facts[key]
			var is_room: bool = key == OnlineWhy.ROOM and fact is String and NetSignal.is_room_code(fact)
			if not (key is StringName) or not (fact is int or fact is bool or fact is StringName or is_room):
				strays.append("the fact %s of %s: %s" % [key, reason, fact])

	func phases() -> Array[StringName]:
		var out: Array[StringName] = []
		for change in changes:
			out.append(change[0])
		return out

	## One physics step: NetPlay's, then the game's once the run plays (before it the game is the
	## menu's: nothing steps).
	func step() -> void:
		play.step()
		if play.phase == NetPlayScript.PLAYING or play.phase == NetPlayScript.ENDED:
			fight.physics_step(_after_tick)

	func _after_tick() -> void:
		var online: bool = play.session != null and (play.is_hosting() or (play.session as NetClient).is_playing())
		play.after_tick()
		if online:
			ticks += 1
			run.capture(fight.areas())

	func free_all() -> void:
		if play.session is NetHost:
			(play.session as NetHost).stop()
		fight.frames.stop_playing()
		play.free()
		fight.free_all()


var _registry: RegistryScript
var _host: Machine
var _client: Machine
## A third machine, made by the tests that need one.
var _third: Machine = null
var _card: SpellComponent = null
var _table: Dictionary = {}


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	var card: SpellComponent = null
	for found: Resource in _registry.get_all(&"spells"):
		if found is SpellComponent and (found as SpellComponent).id == CARD:
			card = found as SpellComponent
	_card = card
	_table = {}
	_third = null
	_host = Machine.new(root, card, _table)
	_client = Machine.new(root, card, _table)


func after_each() -> void:
	# Whatever a test did: nothing left net/ for the screen but names and their facts.
	for machine: Machine in [_host, _client, _third]:
		if machine != null:
			check_equal(machine.strays, PackedStringArray(), "every reason said is a name of OnlineWhy, and every fact a number, a yes or no, a name or a room's code")
	_host.free_all()
	_client.free_all()
	if _third != null:
		_third.free_all()
	for name: String in ["online_host_parted", "online_client_parted"]:
		DirAccess.remove_absolute(Replay.FOLDER + name + Replay.EXTENSION)


## The scripted players stand in for each machine's own device, as in tests/net/net_pair.gd: the
## host's seat 0 and the client's seat 1 are joined (virtual devices), and on the client seat 0 is
## the replay's.
func _seat_scripted_players() -> void:
	_host.fight.input.add_virtual_device(0)
	_client.fight.input.add_virtual_device(NetHost.SEAT)
	_client.fight.frames.set_source(0, null)


func _steps(count: int) -> void:
	for i in count:
		_host.step()
		_client.step()
		if _third != null:
			_third.step()


## Host and Join pressed and the codes swapped as two players would; both step until `phase`.
func _link_up(until: StringName = NetPlayScript.PLAYING) -> void:
	_host.fight.fight.bus.online_host_requested.emit(0)
	_steps(4)
	_client.fight.fight.bus.online_join_requested.emit(0, _host.play.code)
	_steps(4)
	_host.fight.fight.bus.online_answer_requested.emit(0, _client.play.code)
	for i in WARM_UP + 20:
		if _host.play.phase == until and _client.play.phase == until:
			return
		_steps(1)


func test_host_and_join_walk_into_one_run_the_same_on_both_machines() -> void:
	_seat_scripted_players()
	_host.fight.fight.bus.online_host_requested.emit(0)
	check_equal(_host.phases(), [NetPlayScript.MAKING] as Array[StringName], "Host: its code is being made")
	_steps(4)
	check_equal(_host.changes.back(), [NetPlayScript.CODE, LoopHandshake.HOST_CODE, &""], "then shown, for the other player")
	_client.fight.fight.bus.online_join_requested.emit(0, _host.play.code)
	_steps(4)
	check_equal(_client.changes.back(), [NetPlayScript.CODE, LoopHandshake.JOIN_CODE, &""], "Join with the host's code: the client's own is shown")
	check(_host.play.session == null and _client.play.session == null, "no session before the link")
	_host.fight.fight.bus.online_answer_requested.emit(0, _client.play.code)
	check_equal(_host.play.phase, NetPlayScript.LINKING, "the host given the code that came back: linking")
	_steps(2)
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.LINKED, NetPlayScript.LINKED], "both linked")
	check(_host.play.session is NetHost and _client.play.session is NetClient, "the host holds a host's session, the client a client's")
	check_equal(_host.fight.frames.is_recording(), false, "the run does not start at once: the client measures its ping first")
	_steps(WARM_UP + 5)
	check_equal(_host.phases(), [NetPlayScript.MAKING, NetPlayScript.CODE, NetPlayScript.LINKING, NetPlayScript.LINKED, NetPlayScript.PLAYING] as Array[StringName], "the host's phases, each said once")
	check_equal(_client.phases(), [NetPlayScript.MAKING, NetPlayScript.CODE, NetPlayScript.LINKED, NetPlayScript.PLAYING] as Array[StringName], "the client's")
	check(_host.fight.frames.is_recording() and _client.fight.frames.is_live(), "the host records its run, the client plays it live")
	check_equal((_host.play.session as NetHost).replay.start, NetPlayScript.START, "started as a sandbox")
	check((_client.play.session as NetClient).stats.pings >= 2, "the client measured its ping before the run (%d pings)" % (_client.play.session as NetClient).stats.pings)
	_steps(200)
	check(_host.ticks >= 200 and _client.ticks >= _host.ticks - 10, "both play (%d and %d ticks)" % [_host.ticks, _client.ticks])
	var first: int = -1
	for tick in mini(_host.run.hashes.size(), _client.run.hashes.size()):
		if _host.run.hashes[tick] != _client.run.hashes[tick]:
			first = tick
			break
	check_equal(first, -1, "the same state at every tick both ran")
	check((_host.play.session as NetHost).totals().checks >= 2 and (_host.play.session as NetHost).totals().mismatches == 0, "the checks were made after the ticks, and passed (%d)" % (_host.play.session as NetHost).totals().checks)
	check(_host.fight.wizard_casts > 0 and (_client.play.session as NetClient).stats.presses > 0, "the fights fought, the client's presses in the host's ticks")
	check(_host.counters.size() >= 3 and _host.counters[0].begins_with("host:") and _client.counters.size() >= 3 and _client.counters[0].begins_with("client:"), "each sends its counters' line about once a second")
	check_equal([_host.lines[0], _client.lines[-1]], [{}, {}], "with nothing else to say of a run of two that goes well")
	# A request while a run plays changes nothing.
	_host.fight.fight.bus.online_host_requested.emit(0)
	_host.fight.fight.bus.online_leave_requested.emit(0)
	_steps(2)
	check_equal(_host.play.phase, NetPlayScript.PLAYING, "Host or Cancel during the run is not heard")


## A load takes each machine its own time, and the run must start on the same tick on both: each
## loads once linked (the bus's loading events are Flow's and the loading service's in the game),
## the other hears nothing of it meanwhile, and the host starts only when both are ready.
func test_the_run_starts_only_when_both_machines_have_loaded() -> void:
	_seat_scripted_players()
	var asked: Array[String] = []
	_host.fight.fight.bus.play_load_requested.connect(func() -> void:
		asked.append("host")
		_host.fight.fight.bus.loading_started.emit())
	_client.fight.fight.bus.play_load_requested.connect(func() -> void:
		asked.append("client")
		_client.fight.fight.bus.loading_started.emit())
	_link_up(NetPlayScript.LINKED)
	check_equal(asked, ["host", "client"], "once linked, each machine is asked to load what a room needs, once")
	_steps(WARM_UP)
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.LINKED, NetPlayScript.LINKED], "while both load, no run starts")
	check_equal([(_host.play.session as NetHost).totals().sent, (_client.play.session as NetClient).stats.sent], [0, 0], "and neither says anything to the other")
	_host.fight.fight.bus.loading_finished.emit()
	_steps(WARM_UP)
	check_equal(_host.play.phase, NetPlayScript.LINKED, "the host loaded, the client still loading: the host waits for it")
	check(not _host.fight.frames.is_recording(), "nothing is recorded yet")
	_client.fight.fight.bus.loading_finished.emit()
	_steps(WARM_UP)
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "both loaded: the run starts")
	check((_client.play.session as NetClient).stats.pings >= 2, "the client measured its ping after its load (%d pings)" % (_client.play.session as NetClient).stats.pings)
	# The host the slower one: the client's pings wait for it.
	_host.free_all()
	_client.free_all()
	if _third != null:
		_third.free_all()
	before_each()
	_seat_scripted_players()
	_host.fight.fight.bus.play_load_requested.connect(func() -> void: _host.fight.fight.bus.loading_started.emit())
	_link_up(NetPlayScript.LINKED)
	_steps(WARM_UP)
	check_equal(_host.play.phase, NetPlayScript.LINKED, "the host still loading does not start, whatever the client sent")
	_host.fight.fight.bus.loading_finished.emit()
	_steps(10)
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "loaded, it starts")


func test_each_machine_seats_its_own_device_on_its_own_seat() -> void:
	# Nobody has joined: the menus were worked with the mouse.
	_host.fight.fight.bus.online_host_requested.emit(0)
	check_equal([_host.fight.input.device_of(0), _host.fight.input.is_keyboard_provisional()], [KEYBOARD, true], "the host's keyboard is seat 0, until a gamepad wants it")
	check_equal([_host.fight.input.own_first_seat(), _host.fight.input.own_seat_count()], [0, 4], "and the host machine's players take seats as ever: the lowest free")
	_steps(4)
	_client.fight.fight.bus.online_join_requested.emit(0, _host.play.code)
	check_equal(_client.fight.input.joined_count(), 0, "the client's devices are not seated before the host says where")
	_steps(4)
	_host.fight.fight.bus.online_answer_requested.emit(0, _client.play.code)
	_steps(WARM_UP + 10)
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "both play")
	check(InputManagerScript.is_virtual(_host.fight.input.device_of(NetHost.SEAT)), "on the host the client's seat is a virtual device")
	check(InputManagerScript.is_virtual(_client.fight.input.device_of(0)), "on the client the host's seat is")
	check_equal(_client.fight.input.device_of(NetHost.SEAT), KEYBOARD, "and the client's keyboard kept its seat through the run's start")
	_steps(30)
	# The host's HUD never captures the client's seat (its frames would be emptied): nothing
	# presses that seat's virtual device.
	check(not _host.fight.input.is_captured(NetHost.SEAT), "the client's seat is not captured on the host")
	for action: StringName in InputManagerScript.ACTIONS:
		check_equal(_host.fight.input.get_press_count(NetHost.SEAT, action), 0, "no %s was pressed on the host for the client's seat" % action)


func test_a_gamepad_that_joined_before_join_was_pressed_is_the_clients_seat() -> void:
	var press := InputEventJoypadButton.new()
	press.device = 3
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	_client.fight.input.handle_event(press)
	check_equal(_client.fight.input.device_of(0), 3, "a gamepad joined the menu as seat 0")
	_host.fight.fight.bus.online_host_requested.emit(0)
	_steps(4)
	_client.fight.fight.bus.online_join_requested.emit(0, _host.play.code)
	check_equal(_client.fight.input.device_of(0), 3, "it stays where it is until the machines are linked")
	_steps(4)
	_host.fight.fight.bus.online_answer_requested.emit(0, _client.play.code)
	_steps(WARM_UP + 10)
	check_equal(_client.play.phase, NetPlayScript.PLAYING, "the run plays")
	check_equal([_client.fight.input.device_of(NetHost.SEAT), InputManagerScript.is_virtual(_client.fight.input.device_of(0))], [3, true], "the host seated it on the seat it gave; seat 0 is the host's")
	check_equal(_client.fight.input.player_of(KEYBOARD), InputManagerScript.NO_PLAYER, "and the keyboard stays out")


func test_a_refused_code_says_why_and_another_may_be_given() -> void:
	_seat_scripted_players()
	_client.fight.fight.bus.online_join_requested.emit(0, NetCode.PREFIX + "bm90")
	check_equal(_client.play.phase, NetPlayScript.FAILED, "Join with what is no host's code fails")
	check_equal(_client.changes.back(), [NetPlayScript.FAILED, "", OnlineWhy.JOINERS_CODE], "and says why, by the name the handshake gave")
	check_equal([_client.fight.input.own_first_seat(), _client.fight.input.own_seat_count()], [0, 4], "the machine's seats are as they were")
	_host.fight.fight.bus.online_host_requested.emit(0)
	_host.fight.fight.bus.online_answer_requested.emit(0, LoopHandshake.JOIN_CODE)
	check_equal(_host.play.phase, NetPlayScript.MAKING, "an answer before the host's own code is made is not heard")
	_steps(4)
	_host.fight.fight.bus.online_answer_requested.emit(0, "nonsense")
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.CODE, LoopHandshake.HOST_CODE], "the host given nonsense keeps showing its code")
	check_equal(_host.play.reason, OnlineWhy.HOSTS_CODE, "and says why, by name")
	_client.fight.fight.bus.online_join_requested.emit(0, _host.play.code)
	_steps(4)
	_host.fight.fight.bus.online_answer_requested.emit(0, _client.play.code)
	_steps(WARM_UP + 10)
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "with the right codes they play")


func test_an_answer_the_handshake_breaks_on_fails_at_once() -> void:
	_host.fight.fight.bus.online_host_requested.emit(0)
	_steps(4)
	_host.fight.fight.bus.online_answer_requested.emit(0, LoopHandshake.BROKEN_CODE)
	check_equal(_host.changes.back(), [NetPlayScript.FAILED, "", OnlineWhy.BAD_CODE], "failed, said once: the host's own code is spent, so it is not shown as if it still worked")
	check_equal(_host.phases().count(NetPlayScript.CODE), 1, "and no word of pasting another")


func test_a_linked_machine_that_is_never_ready_is_let_go() -> void:
	_seat_scripted_players()
	check(_host.play.ready_steps >= 60 * Engine.physics_ticks_per_second, "the limit is far longer than any load (%d steps)" % _host.play.ready_steps)
	_host.play.ready_steps = 60
	_link_up(NetPlayScript.LINKED)
	# The host loads: nothing is counted, of anyone.
	_host.fight.fight.bus.loading_started.emit()
	for i in 100:
		_host.step()
	_host.fight.fight.bus.loading_finished.emit()
	# The client says nothing (it never steps): the host waits its time, and no longer.
	for i in 40:
		_host.step()
	check_equal(_host.play.phase, NetPlayScript.LINKED, "the host waits for the other machine's pings, a load of its own not counted")
	for i in 30:
		_host.step()
	check_equal([_host.play.phase, _host.play.reason, _host.play.facts], [NetPlayScript.FAILED, OnlineWhy.NOT_READY, {OnlineWhy.SECONDS: NetPlayScript.READY_S}], "past the limit it gives up, and says how long it waited")
	check(_host.play.session == null and not _host.fight.frames.is_recording(), "holding nothing")


func test_a_joining_machine_the_host_never_starts_gives_up() -> void:
	_seat_scripted_players()
	_client.play.ready_steps = 60
	_link_up(NetPlayScript.LINKED)
	# The host stands still: its link stays open, and no run ever begins.
	for i in 40:
		_client.step()
	check_equal(_client.play.phase, NetPlayScript.LINKED, "the joining machine waits for the host's run")
	for i in 30:
		_client.step()
	check_equal([_client.play.phase, _client.play.reason], [NetPlayScript.FAILED, OnlineWhy.NOT_READY], "past the limit it gives up, by name")
	check_equal(_client.fight.input.own_seat_count(), 4, "its seats its own again")


func test_a_handshake_that_fails_or_is_given_up_leaves_the_machine_as_it_was() -> void:
	_host.fight.fight.bus.online_host_requested.emit(0)
	_host.fight.fight.bus.online_host_requested.emit(0)
	check_equal(_host.phases(), [NetPlayScript.MAKING] as Array[StringName], "Host pressed twice begins once")
	_steps(4)
	_host.handshake.fails_with = NetWhy.new(OnlineWhy.NO_LINK, "the two machines could not reach each other", {OnlineWhy.CAUSE: OnlineWhy.CAUSE_RELAY, OnlineWhy.MINE_RELAY: 1})
	_steps(1)
	check_equal(_host.changes.back(), [NetPlayScript.FAILED, "", OnlineWhy.NO_LINK], "the handshake failed: said, by its name, the code gone")
	check_equal(_host.play.facts, {OnlineWhy.CAUSE: OnlineWhy.CAUSE_RELAY, OnlineWhy.MINE_RELAY: 1}, "with the facts the handshake gave, as they were")
	check_equal([_host.fight.input.own_first_seat(), _host.fight.input.own_seat_count(), _host.fight.input.device_of(0)], [0, 4, KEYBOARD], "the machine's seats are its own again")
	# Hosting again after a failure, then giving up.
	_host.fight.fight.bus.online_host_requested.emit(0)
	_steps(4)
	check_equal(_host.play.phase, NetPlayScript.CODE, "Host again works")
	var given_up: LoopHandshake = _host.handshake
	_host.fight.fight.bus.online_leave_requested.emit(0)
	check_equal(_host.changes.back(), [NetPlayScript.OFF, "", &""], "Cancel: off")
	check(given_up.link() == null and _host.fight.input.own_seat_count() == 4, "the handshake is closed, the seats the machine's own")
	_steps(3)
	check_equal(_host.play.phase, NetPlayScript.OFF, "and nothing more happens")


func test_a_machine_that_leaves_before_the_run_fails_the_other() -> void:
	_seat_scripted_players()
	_link_up(NetPlayScript.LINKED)
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.LINKED, NetPlayScript.LINKED], "linked")
	_host.fight.fight.bus.online_leave_requested.emit(0)
	_steps(2)
	check_equal(_host.play.phase, NetPlayScript.OFF, "the host gave up")
	check_equal([_client.play.phase, _client.play.reason], [NetPlayScript.FAILED, OnlineWhy.TURNED_AWAY], "the client is told")
	check(_client.play.session == null and not _client.fight.frames.is_live(), "and holds no session and plays nothing")


func test_the_client_gone_the_hosts_run_plays_on_without_its_seat() -> void:
	_seat_scripted_players()
	_link_up()
	_steps(60)
	var ticks_before: int = _host.fight.ticks
	(_client.play.session as NetClient).link.close()
	_steps(5)
	check_equal(_host.play.phase, NetPlayScript.ENDED, "the host sees the client gone")
	check_equal([_host.play.reason, _host.play.facts], [OnlineWhy.GUEST_LEFT, {}], "and says so: its link just closed, so nothing of why")
	check_equal([_host.lines[-1], _host.counters[-1]], [{}, ""], "the counters of the run that is over are cleared")
	check(_host.play.session == null and not _host.fight.frames.is_recording(), "its session and its recording ended")
	check(not _host.fight.input.is_joined(NetHost.SEAT), "the client's seat left the host's game")
	check_equal(_host.fight.input.own_seat_count(), 4, "the host machine's seats are all its own again")
	check_equal(_host.fight.ticks, ticks_before + 5, "and its game played on, a tick every step")
	_steps(30)
	check_equal(_host.phases().count(NetPlayScript.ENDED), 1, "said once")


## The machine that stays keeps playing on the seat it has: its device neither leaves nor joins
## again when the seats become its own again (its wizard would be made anew).
func test_the_machine_that_stays_keeps_its_device_on_its_seat() -> void:
	# Real devices this time: each machine's keyboard, seated by Host and Join.
	_link_up()
	check_equal([_host.fight.input.device_of(0), _client.fight.input.device_of(NetHost.SEAT)], [KEYBOARD, KEYBOARD], "each machine's keyboard plays")
	_steps(30)
	var moves: Array[String] = []
	_host.fight.fight.bus.device_left.connect(func(seat: int, device: int) -> void: moves.append("host left %d %d" % [seat, device]))
	_host.fight.fight.bus.device_joined.connect(func(seat: int, device: int) -> void: moves.append("host joined %d %d" % [seat, device]))
	_client.fight.fight.bus.device_left.connect(func(seat: int, device: int) -> void: moves.append("client left %d %d" % [seat, device]))
	_client.fight.fight.bus.device_joined.connect(func(seat: int, device: int) -> void: moves.append("client joined %d %d" % [seat, device]))
	(_client.play.session as NetClient).link.close()
	_steps(5)
	check_equal(_host.play.phase, NetPlayScript.ENDED, "the client gone")
	var host_moves: Array[String] = moves.filter(func(move: String) -> bool: return move.begins_with("host"))
	check_equal(host_moves, ["host left %d %d" % [NetHost.SEAT, InputManagerScript.virtual_device_id(NetHost.SEAT)]], "only the client's virtual device left the host; the host's keyboard was not touched")
	check_equal([_host.fight.input.device_of(0), _host.fight.input.own_seat_count()], [KEYBOARD, 4], "it plays on as seat 0, and a second player may join again")
	moves.clear()
	for i in 60:
		_client.step()
	check_equal(_client.play.phase, NetPlayScript.ENDED, "the client sees its link gone")
	check_equal([_client.fight.input.device_of(NetHost.SEAT), _client.fight.input.own_seat_count()], [KEYBOARD, 4], "the client's keyboard stays on its seat, with all four seats the machine's again")
	for move in moves:
		check(not move.contains(" %d" % KEYBOARD), "the client's keyboard neither left nor joined (%s)" % move)
	# After a run that ended nothing more is heard: that run may still play.
	_host.fight.fight.bus.online_host_requested.emit(0)
	_host.fight.fight.bus.online_leave_requested.emit(0)
	check_equal(_host.play.phase, NetPlayScript.ENDED, "Host or Cancel after the run ended is not heard")


func test_the_host_gone_the_clients_run_ends_and_its_game_goes_on() -> void:
	_seat_scripted_players()
	_link_up()
	_steps(60)
	(_host.play.session as NetHost).guests[0].link.close()
	for i in 60:
		_client.step()
	check_equal(_client.play.phase, NetPlayScript.ENDED, "the client sees the host gone")
	check_equal([_client.play.reason, _client.play.facts], [OnlineWhy.HOST_LEFT, {}], "and says so")
	check_equal([_client.lines[-1], _client.counters[-1]], [{}, ""], "its counters cleared")
	check(_client.play.session == null and not _client.fight.frames.is_playing(), "its session is gone and the replay ended, played out")
	check_equal(_client.fight.input.device_of(NetHost.SEAT), InputManagerScript.virtual_device_id(NetHost.SEAT), "its own seat stays where it was")
	check(not _client.fight.input.is_joined(0), "the host's seat left its game")
	var ticks_before: int = _client.fight.ticks
	for i in 10:
		_client.step()
	check_equal(_client.fight.ticks, ticks_before + 10, "and its game plays on alone")


## The host closed without a word (the owner's try of 2026-11-11): its link stays open, nothing
## comes, and the joining machine must not stand still for good.
func test_a_host_that_went_silent_ends_the_clients_run_and_its_game_goes_on() -> void:
	_seat_scripted_players()
	_link_up()
	_steps(60)
	var now: Array[float] = [0.0]
	(_client.play.session as NetClient).clock = func() -> float: return now[0]
	# Only the client steps from here: the host is gone, its link still open.
	for i in NetSession.SILENT_MS * 60 / 1000 + 120:
		now[0] += 1000.0 / 60.0
		_client.step()
	check_equal(_client.play.phase, NetPlayScript.ENDED, "the client takes the host for gone")
	check_equal([_client.play.reason, _client.play.facts], [OnlineWhy.HOST_LEFT, {OnlineWhy.AFTER: OnlineWhy.SILENT, OnlineWhy.SECONDS: NetSession.SILENT_MS / 1000}], "and says so: the host left, after a silence of that many seconds")
	check(_client.play.session == null and not _client.fight.frames.is_playing(), "its session is gone and the replay ended")
	check_equal(_client.fight.input.device_of(NetHost.SEAT), InputManagerScript.virtual_device_id(NetHost.SEAT), "its own seat stays where it was")
	var ticks_before: int = _client.fight.ticks
	for i in 10:
		_client.step()
	check_equal(_client.fight.ticks, ticks_before + 10, "and its game plays on alone")


func test_a_failed_check_is_said_once_and_the_run_saved() -> void:
	_seat_scripted_players()
	_link_up()
	_steps(30)
	# The client's world is changed behind the game's back: its own wizard moved.
	(_client.fight.fight.players[1] as Actor).position += Vector2(40.0, -25.0)
	_steps(3 * NetChecks.EVERY + 30)
	check((_host.play.session as NetHost).parted_tick >= 0 and (_client.play.session as NetClient).parted_tick == (_host.play.session as NetHost).parted_tick, "both know the tick they parted at (%d)" % (_host.play.session as NetHost).parted_tick)
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "the run plays on (the spike does not mend it)")
	check_equal(_host.lines[-1].get(OnlineWhy.LINE_PARTED_TICK), (_host.play.session as NetHost).parted_tick, "the host's line says so (%s)" % _host.lines[-1])
	check(not (_host.lines[-1].get(OnlineWhy.LINE_PARTED_AREAS) as PackedStringArray).is_empty(), "and in which areas")
	check_equal(_client.lines[-1].get(OnlineWhy.LINE_PARTED_TICK), _host.play.session.parted_at(), "and the client's")
	check(not _client.lines[-1].has(OnlineWhy.LINE_PARTED_AREAS), "without the names the host sent it: text off the wire is for its log, not its screen")
	var host_run: Replay = Replay.open("online_host_parted")
	var client_run: Replay = Replay.open("online_client_parted")
	check(host_run != null and client_run != null, "each side saved its run as a replay")
	if host_run != null and client_run != null:
		check(host_run.tick_count() > (_host.play.session as NetHost).parted_tick and client_run.tick_count() > 0, "with the ticks up to the parting (%d, %d)" % [host_run.tick_count(), client_run.tick_count()])
		check_equal(client_run.run_seed, host_run.run_seed, "of the same run")


# --- A room: the hub's altar and Join online (online lobby L2) -------------------

## The host's party stands in the hub and a wizard of its presses A on the altar.
func _open_room() -> void:
	_seat_scripted_players()
	_host.fight.fight.bus.hub_changed.emit(true)
	_host.fight.fight.bus.online_open_requested.emit(0)
	_steps(4)


func _join_room(machine: Machine, typed: String = RoomHandshake.ROOM) -> void:
	machine.fight.fight.bus.online_join_requested.emit(0, typed)
	for i in WARM_UP + 20:
		_host.step()
		_client.step()
		if _third != null:
			_third.step()


func test_the_altar_opens_a_room_and_says_its_code() -> void:
	_seat_scripted_players()
	_host.fight.fight.bus.hub_changed.emit(true)
	_host.fight.fight.bus.online_open_requested.emit(0)
	check_equal(_host.phases(), [NetPlayScript.MAKING] as Array[StringName], "A on the altar: the room is being made")
	_steps(4)
	check_equal(_host.changes.back(), [NetPlayScript.CODE, RoomHandshake.ROOM, &""], "then its code is said")
	check_equal(_host.lines, [{OnlineWhy.LINE_ROOM: RoomHandshake.ROOM}] as Array[Dictionary], "and given for the HUD's line: an open room nobody joined yet")
	check(_host.play.session == null and not _host.fight.frames.is_recording(), "the party plays on as it was: nothing is recorded, nobody is linked")
	check_equal(_host.fight.input.joined_count(), 1, "and nobody's seat changed")


func test_a_machine_joins_the_room_by_its_code_and_plays_the_hosts_run() -> void:
	_open_room()
	_join_room(_client, " kq7rm ")
	check_equal([_host.play.phase, _client.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "both play")
	check_equal(_client.phases(), [NetPlayScript.MAKING, NetPlayScript.LINKED, NetPlayScript.PLAYING] as Array[StringName], "the joining machine shows no code of its own")
	check(_host.fight.frames.is_recording() and _client.fight.frames.is_live(), "the host records its hub, the joining machine plays it live")
	check_equal((_host.play.session as NetHost).replay.start, NetPlayScript.ROOM_START, "begun as the hub")
	check_equal((_host.play.session as NetHost).guest_seats(), 1 << 1, "the joining machine's player has the lowest free seat")
	check(InputManagerScript.is_virtual(_host.fight.input.device_of(1)) and _client.fight.input.is_joined(1), "a virtual device on the host, the machine's own device on it there")
	check(_host.room != null and _host.room.problem() == null and _host.play.code == RoomHandshake.ROOM, "the room stays open under the run")
	_steps(200)
	check(_host.ticks >= 200 and _client.ticks >= _host.ticks - 10, "both play (%d and %d ticks)" % [_host.ticks, _client.ticks])
	var first: int = -1
	for tick in mini(_host.run.hashes.size(), _client.run.hashes.size()):
		if _host.run.hashes[tick] != _client.run.hashes[tick]:
			first = tick
			break
	check_equal(first, -1, "the same state at every tick both ran")
	var totals: NetStats = (_host.play.session as NetHost).totals()
	check(totals.checks >= 2 and totals.mismatches == 0, "the checks passed (%d)" % totals.checks)
	check(_client.play.session.counters().presses > 0, "the joining machine's presses are in the host's ticks")
	check_equal(_host.lines[-1], {OnlineWhy.LINE_ROOM: RoomHandshake.ROOM, OnlineWhy.LINE_JOINED: 1}, "the host's line keeps the room's code and says who is in")


func test_the_room_stays_open_when_the_machine_leaves_and_another_joins() -> void:
	_open_room()
	_join_room(_client)
	_steps(60)
	(_client.play.session as NetClient).link.close()
	_steps(6)
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.CODE, RoomHandshake.ROOM], "the machine gone: the room is open as before")
	check_equal(_host.play.reason, OnlineWhy.PARTY_LEFT_OPEN, "and the host is told")
	check_equal(_host.lines[-1], {OnlineWhy.LINE_ROOM: RoomHandshake.ROOM}, "its line the open room's again")
	check(_host.play.session == null and not _host.fight.frames.is_recording(), "the recording ended with it")
	check(not _host.fight.input.is_joined(1), "and its seat left, as an unplugged pad's")
	check_equal(_client.play.phase, NetPlayScript.ENDED, "the machine that left plays on alone")
	# Another machine joins the same room, into a hub begun anew.
	_third = Machine.new(root, _card, _table)
	_third.fight.input.add_virtual_device(NetHost.SEAT)
	_third.fight.frames.set_source(0, null)
	_host.fight.fight.bus.hub_changed.emit(true)
	_join_room(_third)
	check_equal([_host.play.phase, _third.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "the next machine plays")
	check((_host.play.session as NetHost).replay.tick_count() < WARM_UP + 60, "in a recording begun for it")


func test_a_machine_that_comes_while_the_party_is_out_of_the_hub_is_turned_away() -> void:
	_open_room()
	# The party left the hub (a run from the stone).
	_host.fight.fight.bus.hub_changed.emit(false)
	_host.seats.clear()
	_join_room(_client)
	check_equal(_client.play.phase, NetPlayScript.FAILED, "it does not get in")
	check_equal(_client.play.reason, OnlineWhy.TURNED_AWAY, "and is told so")
	check_equal(_host.seats, [] as Array[int], "no wizard of its ever stood in the host's run, even for a moment")
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.CODE, RoomHandshake.ROOM], "the room stays open")
	check_equal(_host.play.reason, OnlineWhy.OUT_OF_HUB, "and the host is told what happened")
	check(not _host.fight.frames.is_recording() and not _host.fight.input.is_joined(1), "nothing was recorded and nobody seated")
	check_equal(_client.fight.input.device_of(NetHost.SEAT), InputManagerScript.virtual_device_id(NetHost.SEAT), "the machine's player sits where it sat")


func test_a_machine_in_the_room_that_is_never_ready_is_turned_away() -> void:
	_open_room()
	_host.play.ready_steps = 30
	_client.fight.fight.bus.online_join_requested.emit(0, RoomHandshake.ROOM)
	_steps(4)
	check(_host.play.session != null and (_host.play.session as NetHost).guests.size() == 1, "a machine came through the room")
	# It says nothing more.
	for i in 40:
		_host.step()
	check_equal([_host.play.phase, _host.play.code, _host.play.reason], [NetPlayScript.CODE, RoomHandshake.ROOM, OnlineWhy.NOT_READY], "it is let go, the room open for the next, and the host is told why")
	check(_host.play.session == null and not _host.fight.input.is_joined(1), "it holds no place and no seat")
	_third = Machine.new(root, _card, _table)
	_third.fight.input.add_virtual_device(NetHost.SEAT)
	_third.fight.frames.set_source(0, null)
	_host.play.ready_steps = NetPlayScript.READY_S * 60
	_join_room(_third)
	check_equal([_host.play.phase, _third.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "and the next machine joins")


func test_a_wrong_room_code_fails_and_says_so() -> void:
	_open_room()
	_client.fight.fight.bus.online_join_requested.emit(0, "KQ7R")
	check_equal(_client.play.phase, NetPlayScript.FAILED, "what is no room's code fails at once")
	check_equal([_client.play.reason, _client.play.facts], [OnlineWhy.BAD_ROOM_CODE, {OnlineWhy.LENGTH: 5}], "and says what a code is")
	_table[&"open"] = false
	_steps(2)
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.FAILED, ""], "the room closed (the server's doing): the host is told")
	check_equal(_host.play.reason, OnlineWhy.ROOM_CLOSED, "by name")
	check_equal([_host.lines[-1], _host.counters[-1]], [{}, ""], "and the HUD's line with the code is cleared")
	_client.fight.fight.bus.online_join_requested.emit(0, RoomHandshake.ROOM)
	_steps(4)
	check_equal(_client.play.phase, NetPlayScript.FAILED, "a room that is closed is none")
	check_equal([_client.play.reason, _client.play.facts], [OnlineWhy.NO_ROOM, {OnlineWhy.ROOM: RoomHandshake.ROOM}], "and it says so, with the code that was typed")
	_host.fight.fight.bus.online_open_requested.emit(0)
	_steps(4)
	check_equal(_host.play.phase, NetPlayScript.CODE, "the host may open a room again")


func test_the_altar_asked_again_says_the_code_again_and_closes_nothing() -> void:
	_open_room()
	var said: int = _host.changes.size()
	var first: RoomHandshake = _host.room
	_host.fight.fight.bus.online_open_requested.emit(0)
	_host.fight.fight.bus.online_open_requested.emit(0)
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.CODE, RoomHandshake.ROOM], "A on the altar again (it is also the dash): the room stays open")
	check(_host.room == first and _table.get(&"open", false), "the same room")
	check(_host.changes.size() > said and _host.lines[-1] == {OnlineWhy.LINE_ROOM: RoomHandshake.ROOM}, "and its code is said again")
	_join_room(_client)
	check_equal(_client.play.phase, NetPlayScript.PLAYING, "a machine still joins it")
	_host.fight.fight.bus.online_open_requested.emit(0)
	check_equal(_host.play.phase, NetPlayScript.PLAYING, "A on the altar under the run changes nothing")


func test_the_altar_opens_nothing_under_a_replay() -> void:
	_seat_scripted_players()
	var replay: Replay = _host.fight.frames.record(&"sandbox_requested", 0, 5)
	for i in 4:
		_host.fight.frames.tick(ContentFight.DT)
	_host.fight.frames.stop_recording()
	check(_host.fight.frames.play(replay), "a replay plays")
	_host.fight.fight.bus.online_open_requested.emit(0)
	check_equal([_host.play.phase, _host.room == null], [NetPlayScript.OFF, true], "A on the altar in a replay opens no room")


func test_the_host_waits_for_the_joining_machines_pings_not_for_any_messages() -> void:
	_open_room()
	# A second player on the joining machine: two asks for seats reach the host beside its pings.
	_client.fight.input.add_virtual_device(2)
	_client.fight.fight.bus.online_join_requested.emit(0, RoomHandshake.ROOM)
	var pings_at_start: int = -1
	for i in WARM_UP + 20:
		_steps(1)
		if _host.play.phase == NetPlayScript.PLAYING:
			pings_at_start = (_host.play.session as NetHost).guests[0].pings_heard
			break
	check(pings_at_start >= NetPlayScript.READY_PINGS, "the run began only once the machine's pings said it was ready (%d heard)" % pings_at_start)


## A party of several machines (online lobby L3 through the room): a second machine joins while
## the first plays, catches up on what was recorded, and each leaves on its own.
func test_a_second_machine_joins_the_party_while_the_first_plays() -> void:
	_open_room()
	_join_room(_client)
	_steps(90)
	check_equal(_host.play.phase, NetPlayScript.PLAYING, "the first machine plays")
	var recording: Replay = (_host.play.session as NetHost).replay
	_third = Machine.new(root, _card, _table)
	_third.fight.input.add_virtual_device(NetHost.SEAT)
	_third.fight.frames.set_source(0, null)
	_host.seats.clear()
	_join_room(_third)
	check_equal([_host.play.phase, _client.play.phase, _third.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING, NetPlayScript.PLAYING], "all three play")
	var host: NetHost = _host.play.session as NetHost
	check(host.replay == recording, "in the recording the first machine plays: it did not begin anew under it")
	check_equal([host.guests.size(), host.guest_seats()], [2, 0b0110], "two guest machines, a seat each: the lowest free")
	check_equal(_host.seats, [3], "the second machine's player was seated once, in the run")
	check(_host.changes.back()[0] == NetPlayScript.PLAYING and _host.phases().count(NetPlayScript.PLAYING) == 1, "the host went on playing: no phase was said again")
	# However slow this machine is under the test's own captures: a step's time is never short.
	(_third.play.session as NetClient).burst_usec = 1 << 40
	_steps(200)
	for machine: Machine in [_client, _third]:
		var first: int = -1
		for tick in mini(_host.run.hashes.size(), machine.run.hashes.size()):
			if _host.run.hashes[tick] != machine.run.hashes[tick]:
				first = tick
				break
		check_equal(first, -1, "the same state at every tick the host and a guest ran")
	check(_third.ticks >= _host.ticks - 12, "the machine that came later caught up (%d of %d ticks)" % [_third.ticks, _host.ticks])
	var totals: NetStats = host.totals()
	check(totals.checks >= 4 and totals.mismatches == 0, "both machines' checks passed (%d)" % totals.checks)
	check_equal(_host.lines[-1].get(OnlineWhy.LINE_JOINED), 2, "the host's line says who is in (%s)" % _host.lines[-1])
	# The first machine leaves: the second plays on with the host.
	(_client.play.session as NetClient).link.close()
	_steps(6)
	check_equal([_host.play.phase, host.guests.size(), _third.play.phase], [NetPlayScript.PLAYING, 1, NetPlayScript.PLAYING], "one machine gone, the other plays on")
	check(not _host.fight.input.is_joined(1) and _host.fight.input.is_joined(2), "its seat left; the other's stays")
	check(_host.fight.frames.is_recording(), "the recording goes on")
	(_third.play.session as NetClient).link.close()
	_steps(6)
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.CODE, RoomHandshake.ROOM], "the last one gone: the room is open as before")
	check(_host.play.session == null and not _host.fight.frames.is_recording(), "and the recording ended")


func test_a_fourth_guest_machine_is_not_taken() -> void:
	_open_room()
	_host.fight.fight.bus.hub_changed.emit(true)
	var links: Array[NetLink] = []
	for i in NetHost.GUESTS + 1:
		var joiner := RoomHandshake.new(_table)
		check_equal(joiner.take(RoomHandshake.ROOM), null, "machine %d names the room" % (i + 2))
		joiner.poll()
		links.append(joiner.link())
		_steps(2)
	check_equal((_host.play.session as NetHost).guests.size(), NetHost.GUESTS, "three guest machines are taken")
	check(links[0].is_open() and links[1].is_open() and links[2].is_open(), "their links are open")
	check(not links[3].is_open(), "the fourth's is closed: the host takes three")


func test_a_machine_too_far_behind_a_run_begun_anew_is_let_go_and_the_host_knows_why() -> void:
	_open_room()
	_join_room(_client)
	_steps(NetHost.MAX_FLUSH + 200)
	# A machine joins a long recording, and the party is back in its hub before it caught up.
	_third = Machine.new(root, _card, _table)
	_third.fight.input.add_virtual_device(NetHost.SEAT)
	_third.fight.frames.set_source(0, null)
	_third.fight.fight.bus.online_join_requested.emit(0, RoomHandshake.ROOM)
	var host: NetHost = _host.play.session as NetHost
	for i in WARM_UP + 20:
		if host.guests.size() == 2 and host.guests[1].admitted:
			break
		_steps(1)
	check(host.guests.size() == 2 and host.guests[1].admitted and host.replay.tick_count() - host.guests[1].sent_ticks > NetHost.MAX_FLUSH, "the late machine is in the run, far behind it")
	_host.fight.frames.restart(NetPlayScript.ROOM_START, 0)
	_steps(3)
	check_equal(host.guests.size(), 1, "the run begun anew: it is let go")
	check_equal([_host.play.phase, _host.play.reason], [NetPlayScript.PLAYING, OnlineWhy.FELL_BEHIND], "the others play on, and the host knows why it went")


## The party is back in its hub after a run (Flow asks the frames service for the hub's start):
## the host's recording begins anew there, and every guest machine goes on in the new one.
func test_the_run_begun_anew_goes_on_in_a_new_recording_on_every_machine() -> void:
	_open_room()
	_join_room(_client)
	_third = Machine.new(root, _card, _table)
	_third.fight.input.add_virtual_device(NetHost.SEAT)
	_third.fight.frames.set_source(0, null)
	_join_room(_third)
	(_third.play.session as NetClient).burst_usec = 1 << 40
	_steps(100)
	var host: NetHost = _host.play.session as NetHost
	var first: Replay = host.replay
	check(first.tick_count() > 100, "three machines play the first recording")
	_host.fight.frames.restart(NetPlayScript.ROOM_START, 0)
	_steps(120)
	var second: Replay = host.replay
	check(second != first and _host.fight.frames.recorded() == second, "the host records into a new recording, and its session sends that one")
	check(second.tick_count() >= 110 and second.tick_count() < first.tick_count(), "which counts its ticks from the first (%d)" % second.tick_count())
	check_equal(second.seats, 0b0111, "with every machine's seats in its header")
	check_equal([_host.play.phase, _client.play.phase, _third.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING, NetPlayScript.PLAYING], "everyone plays on")
	for machine: Machine in [_client, _third]:
		var replay: Replay = (machine.play.session as NetClient).replay
		check_equal([replay.run_seed, replay.start], [second.run_seed, second.start], "a guest machine plays the new recording")
		check(machine.ticks >= _host.ticks - 12, "and is where the host is (%d of %d ticks)" % [machine.ticks, _host.ticks])
		var parting: int = -1
		for tick in mini(_host.run.hashes.size(), machine.run.hashes.size()):
			if _host.run.hashes[tick] != machine.run.hashes[tick]:
				parting = tick
				break
		check_equal(parting, -1, "the same state at every tick, through the one recording and into the next")
	check(_client.play.session.counters().presses > 0, "a guest's presses are in the host's ticks of the new recording too")
	check_equal([host.guests[0].plays_run, host.guests[1].plays_run], [2, 2], "each said when it played the new one")
	check_equal(host.totals().mismatches, 0, "no check differed")
	check(host.guests[0].stats.checks >= 1 and host.guests[1].stats.checks >= 1, "and the new recording's checks were made")
	check_equal([host.guests[0].problem, host.guests[1].problem], ["", ""], "what was on its way from the recording before closed no link")


func test_a_machine_still_waiting_to_be_joined_is_not_let_go_when_the_last_one_playing_leaves() -> void:
	_open_room()
	_join_room(_client)
	_steps(30)
	# Another machine links and has not said it is ready yet (no ping of its heard).
	var waiting := RoomHandshake.new(_table)
	waiting.take(RoomHandshake.ROOM)
	waiting.poll()
	var link: NetLink = waiting.link()
	_steps(2)
	var host: NetHost = _host.play.session as NetHost
	check_equal(host.guests.size(), 2, "two guest machines: one plays, one waits")
	(_client.play.session as NetClient).link.close()
	_steps(6)
	check(link.is_open(), "the one that plays leaves: the one that waits keeps its link")
	check(_host.play.session == host and host.guests.size() == 1 and _host.fight.frames.is_recording(), "the party's session and its recording go on for it")
	check_equal(_host.play.phase, NetPlayScript.PLAYING, "and the host says nothing of a room left empty")
	link.close()
	_steps(4)
	check_equal([_host.play.phase, _host.play.session == null], [NetPlayScript.CODE, true], "with that one gone too, the room is open as before")



# --- Back to the main menu (the pause menu's "Main menu", `main_menu_requested`) ---------------

## A guest machine that goes back to the menu leaves the party at once: its link closes, so the
## host lets its seats go in a step or two, not after a silence (NetSession.SILENT_MS).
func test_a_guest_back_to_the_menu_leaves_the_party_at_once() -> void:
	_open_room()
	_join_room(_client)
	_steps(60)
	_client.fight.fight.bus.main_menu_requested.emit(0)
	check_equal([_client.play.phase, _client.play.code], [NetPlayScript.OFF, ""], "the machine that left is off")
	check(_client.play.session == null and not _client.fight.frames.is_playing(), "it holds no session and plays nothing")
	check_equal([_client.lines[-1], _client.counters[-1]], [{}, ""], "and the HUD's online line is cleared")
	_steps(3)
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.CODE, RoomHandshake.ROOM], "the host plays on with its room open")
	check(not _host.fight.input.is_joined(1), "and the guest's seat left its game")


## The owner's case (online lobby, L2 leftovers): a machine whose host left goes back to the menu
## and joins another room, with no restart of the game.
func test_a_machine_whose_host_left_goes_back_to_the_menu_and_joins_another_room() -> void:
	_open_room()
	_join_room(_client)
	_steps(60)
	_host.fight.fight.bus.main_menu_requested.emit(0)
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.OFF, ""], "the host back in the menu is off")
	check(_host.play.session == null and not _host.fight.frames.is_recording(), "it holds no session and records nothing")
	check(not _table.get(&"open", true), "and its room is closed")
	for i in 30:
		_client.step()
	check_equal(_client.play.phase, NetPlayScript.ENDED, "the guest sees its host gone at once")
	_client.fight.fight.bus.main_menu_requested.emit(0)
	check_equal(_client.play.phase, NetPlayScript.OFF, "back in the menu it is off")
	check_equal(_client.fight.input.own_seat_count(), 4, "with every seat its machine's again")
	# Another machine opens a room; the one that was left alone joins it.
	_third = Machine.new(root, _card, _table)
	_third.fight.input.add_virtual_device(0)
	_third.fight.fight.bus.hub_changed.emit(true)
	_third.fight.fight.bus.online_open_requested.emit(0)
	_client.fight.fight.bus.online_join_requested.emit(0, RoomHandshake.ROOM)
	for i in WARM_UP + 20:
		_third.step()
		_client.step()
	check_equal([_third.play.phase, _client.play.phase], [NetPlayScript.PLAYING, NetPlayScript.PLAYING], "it plays in the new room")
	check(_client.fight.frames.is_live() and (_third.play.session as NetHost).guest_seats() != 0, "the new host's recording, live, with a seat of its own")


## Back to the menu before anything linked gives up, as Cancel does.
func test_back_to_the_menu_while_the_room_is_being_made_gives_it_up() -> void:
	_seat_scripted_players()
	_host.fight.fight.bus.hub_changed.emit(true)
	_host.fight.fight.bus.online_open_requested.emit(0)
	_host.fight.fight.bus.main_menu_requested.emit(0)
	check_equal([_host.play.phase, _host.play.code], [NetPlayScript.OFF, ""], "off")
	check(not _table.get(&"open", true), "the room it was making is closed")
	_steps(4)
	check_equal(_host.play.phase, NetPlayScript.OFF, "and stays off")
