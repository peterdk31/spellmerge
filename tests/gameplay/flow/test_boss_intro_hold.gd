extends "res://tests/support/suite.gd"
## A boss's intro as the game's (docs/milestones/boss-intro.md, rule 2, step BI2), on the real
## autoloads: a test boss made here (the imp's body, with an intro), the boss of a run of copies of the
## crypt arena pinned to a biome of its own (tests/support/pinned_run.gd). The game stops on the
## room's tick with the boss's id open, by both ways into a room, only for a boss with an intro and the
## run's rule on; any seat turns a page, a stale page is ignored, the last page lets the game go; it
## stacks with the pause menu and a waited-for pad; none in the sandbox or for adds; it closes when the
## last seat leaves and when the run ends; a staff pressed during it casts nothing as the fight starts;
## a snapshot mid-intro restores its page and tells it open, not fresh; a recording of it plays back
## the same.

const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CoopScript := preload("res://gameplay/coop/coop.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
## The plain boss's rooms are copies of another arena: a pinned room's id is its template's.
const PLAIN_ARENA: RoomBase = preload("res://content/rooms/crypt/arena_02.tres")
const BOSS_ID: StringName = &"test_intro_boss"
const PLAIN_ID: StringName = &"test_intro_plain_boss"
const ADD_ID: StringName = &"test_intro_add_boss"
const LAIR: StringName = &"test_intro_lair"
const PLAIN_LAIR: StringName = &"test_intro_plain_lair"
const LINES: Array[String] = ["The first line.", "The second line."]
const DT: float = 1.0 / 60.0

var flow: FlowScript
var tick: TickScript
var input: Node
var events: Node
var frames: Node
var registry: Node
## Each intro event heard: [kind, args...].
var heard: Array[Array] = []
## The casts of each actor id heard (`actor_cast`).
var casts: Dictionary = {}


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	frames = root.get_node("Frames")
	registry = root.get_node("Registry")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	heard.clear()
	casts.clear()
	events.connect("boss_intro_opened", _on_opened)
	events.connect("boss_intro_paged", _on_paged)
	events.connect("boss_intro_closed", _on_closed)
	events.connect("actor_cast", _on_cast)
	_register()
	SessionRules.machine().boss_intros = 1


func after_each() -> void:
	events.disconnect("boss_intro_opened", _on_opened)
	events.disconnect("boss_intro_paged", _on_paged)
	events.disconnect("boss_intro_closed", _on_closed)
	events.disconnect("actor_cast", _on_cast)
	frames.call("stop_recording")
	frames.call("stop_playing")
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	for seat in 4:
		input.leave(seat)
	await commands_applied()
	tick.begin_run()


func _on_opened(actor: int, boss_name: String, lore: String, intro: BossIntro, page: int, fresh: bool) -> void:
	heard.append([&"opened", actor, boss_name, lore, intro, page, fresh])


func _on_paged(page: int) -> void:
	heard.append([&"paged", page])


func _on_closed(actor: int) -> void:
	heard.append([&"closed", actor])


func _on_cast(caster: int, _actor: Node) -> void:
	casts[caster] = int(casts.get(caster, 0)) + 1


func _of(kind: StringName) -> Array[Array]:
	var found: Array[Array] = []
	for row: Array in heard:
		if row[0] == kind:
			found.append(row)
	return found


## The imp as a boss of its own biome, with an intro of LINES (or none), standing still and casting
## nothing (its staffs taken), so the fight changes nothing a test reads.
func _make_boss(id: StringName, biome: StringName, with_intro: bool) -> EnemyBase:
	var data: EnemyBase = (registry.call("get_resource", &"enemies", &"ember_imp") as EnemyBase).duplicate() as EnemyBase
	data.id = id
	data.display_name = "The Intro Boss"
	data.lore = "It was made for this test."
	data.boss = true
	data.biomes = [biome] as Array[StringName]
	data.max_health = 1000.0
	data.staffs = [] as Array[StaffCards]
	data.phases = [] as Array[EnemyPhase]
	data.boss_intro = _make_intro() if with_intro else null
	return data


static func _make_intro() -> BossIntro:
	var intro := BossIntro.new()
	intro.portrait = ImageTexture.create_from_image(Image.create(BossIntro.FRAME * BossIntro.FRAMES, BossIntro.FRAME, false, Image.FORMAT_RGBA8))
	intro.lines = LINES.duplicate()
	intro.accent = &"spark"
	return intro


func _register() -> void:
	if registry.call("get_resource", &"bosses", BOSS_ID) != null:
		return
	registry.call("add", &"bosses", _make_boss(BOSS_ID, LAIR, true))
	# A boss with no intro, whose phase calls a boss with one as its add.
	var plain: EnemyBase = _make_boss(PLAIN_ID, PLAIN_LAIR, false)
	var called := EnemyAdds.new()
	called.enemy = ADD_ID
	called.count = 1
	var phase := EnemyPhase.new()
	phase.health_below = 0.5
	phase.transition = 0.0
	phase.adds = [called] as Array[EnemyAdds]
	plain.phases = [phase] as Array[EnemyPhase]
	registry.call("add", &"bosses", plain)
	registry.call("add", &"bosses", _make_boss(ADD_ID, &"test_intro_nowhere", true))


## A run of `depth` boss rooms of `lair`'s, with `players` seats.
func _play(players: int = 1, depth: int = 1, lair: StringName = LAIR) -> void:
	flow.run_id_to_play = PinnedRun.pin(registry, PLAIN_ARENA if lair == PLAIN_LAIR else ARENA, lair, RoomKind.FILL_BOSS, 16, depth)
	for seat in players:
		input.add_virtual_device(seat)
	events.emit_signal("play_requested", 0)


func _boss() -> Actor:
	for enemy: Node in flow.get(&"_enemies"):
		var actor := enemy as Actor
		if actor != null and actor.data != null and actor.data.boss:
			return actor
	return null


func _stopped() -> bool:
	return tick.sim.stopped_for(BossIntroHold.STOP)


## A seat's A on page `page`, applied at the next tick's start.
func _next(seat: int, page: int) -> void:
	events.emit_signal("boss_intro_next_requested", seat, page)
	await commands_applied()


func test_the_game_stops_on_the_rooms_tick_with_the_boss_open() -> void:
	_play()
	var boss: Actor = _boss()
	check(boss != null, "the boss stands")
	if boss == null:
		return
	check(_stopped(), "stopped for the intro as the room starts, on its tick")
	check_equal(_of(&"opened").size(), 1, "opened once")
	var opened: Array = _of(&"opened")[0]
	check(boss.id != ActorsScript.NONE, "the boss's id is open")
	check_equal(opened[1], boss.id, "for the boss, by its id")
	check_equal(opened[2], "The Intro Boss", "its shown name")
	check_equal(opened[3], "It was made for this test.", "its lore")
	check(opened[4] == boss.data.boss_intro, "its intro")
	check_equal(opened[5], 0, "on the first page")
	check_equal(opened[6], true, "fresh")
	var at: Vector2 = boss.position
	var health: float = boss.health.health
	for i in 5:
		await physics_frame
	check(_stopped(), "still stopped: nobody pressed A")
	check(boss.position == at and boss.health.health == health, "the world stands still under it")


func test_the_next_room_opens_its_own() -> void:
	_play(1, 2)
	check(_stopped(), "the first room's intro")
	await _next(0, 0)
	await _next(0, 1)
	check(not _stopped(), "closed")
	var first: Actor = _boss()
	for enemy: Node in flow.get(&"_enemies").duplicate():
		events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO, -1)
	heard.clear()
	# Into the lit exit (one of the arena's two leads on).
	var entered: int = flow.get(&"_enemies").size()
	for exit: Actor in ExitRules.exits_in(flow.contents):
		if flow.get(&"_enemies").size() != entered:
			break
		flow.get_wizard(0).position = HubRules.area_at(exit.prop, exit.position).get_center()
		flow.step(DT)
	var boss: Actor = _boss()
	check(boss != null and boss != first, "the next room's boss stands")
	check(_stopped(), "the next room stops for its own intro")
	check_equal(_of(&"opened").size(), 1, "opened once more")
	if boss != null and not _of(&"opened").is_empty():
		check_equal(_of(&"opened")[0][1], boss.id, "for the next room's boss, its id open")


func test_none_with_the_rule_off_or_for_a_boss_with_no_intro() -> void:
	SessionRules.machine().boss_intros = 0
	_play()
	check(_boss() != null, "the boss stands")
	check(not _stopped() and heard.is_empty(), "the rule off: no intro")
	flow.stop_run()
	SessionRules.machine().boss_intros = 1
	_play(1, 1, PLAIN_LAIR)
	check(_boss() != null, "the plain boss stands")
	check(not _stopped() and heard.is_empty(), "a boss with no intro: none")


func test_any_seat_turns_a_page_and_the_last_lets_the_game_go() -> void:
	_play(2)
	var boss: Actor = _boss()
	await _next(1, 0)
	check_equal(_of(&"paged"), [[&"paged", 1]] as Array[Array], "seat 1's A turns the page for everyone")
	check(_stopped(), "a page to go: still stopped")
	await _next(0, 1)
	check_equal(_of(&"closed"), [[&"closed", boss.id]] as Array[Array], "seat 0's A on the last page closes it")
	check(not tick.sim.is_stopped(), "the game goes on")
	check_equal(flow.boss_intro.page, 0, "no page open")
	await _next(0, 0)
	check_equal(_of(&"opened").size(), 1, "never twice in a room")
	check(not _stopped(), "a late A changes nothing")


func test_a_stale_page_is_ignored() -> void:
	_play(2)
	# Both seats press A on the first page on one tick: one page turns, not two.
	events.emit_signal("boss_intro_next_requested", 0, 0)
	events.emit_signal("boss_intro_next_requested", 1, 0)
	await commands_applied()
	check_equal(_of(&"paged"), [[&"paged", 1]] as Array[Array], "one page turned")
	check(_stopped(), "still open on the last page")
	check(_of(&"closed").is_empty(), "not closed")


func test_it_stacks_with_the_pause_menu_and_a_waited_for_pad() -> void:
	_play(2)
	events.emit_signal("pause_requested", 0, 1)
	await commands_applied()
	await _next(1, 0)
	await _next(1, 1)
	check(not _stopped() and _of(&"closed").size() == 1, "the intro closed")
	check(tick.sim.is_stopped(), "the open menu still stops the game")
	events.emit_signal("pause_requested", 0, 0)
	await commands_applied()
	check(not tick.sim.is_stopped(), "the game goes once the menu shuts")
	flow.stop_run()
	heard.clear()
	_play(2)
	events.emit_signal("pad_wait_requested", 1, 1)
	await commands_applied()
	await _next(0, 0)
	await _next(0, 1)
	check(not _stopped(), "the intro closed")
	check(tick.sim.stopped_for(CoopScript.PAD_OF[1]), "the waited-for pad still stops the game")
	events.emit_signal("pad_wait_requested", 1, 0)
	await commands_applied()
	check(not tick.sim.is_stopped(), "the game goes once the pad is back")


func test_none_in_the_sandbox_or_for_adds() -> void:
	flow.mode = FlowScript.MODE_SANDBOX
	input.add_virtual_device(0)
	events.emit_signal("sandbox_requested", 0)
	check_equal(flow.spawn_in_sandbox(BOSS_ID, 1), 1, "the boss with an intro spawns in the sandbox")
	await commands_applied()
	check(not _stopped() and heard.is_empty(), "the sandbox's spawns open none")
	flow.stop_run()
	flow.mode = FlowScript.MODE_RUN
	_play(1, 1, PLAIN_LAIR)
	var plain: Actor = _boss()
	plain.phases.begin(0)
	var added: bool = false
	for enemy: Node in flow.get(&"_enemies"):
		added = added or (enemy as Actor).data.id == ADD_ID
	check(added, "the plain boss called a boss with an intro as its add")
	check(not _stopped() and heard.is_empty(), "an add opens none")


func test_it_closes_when_the_last_seat_leaves() -> void:
	_play(2)
	var boss: Actor = _boss()
	input.leave(1)
	await commands_applied()
	check(_stopped(), "a seat left, one is still there to press A")
	input.leave(0)
	await commands_applied()
	check(not _stopped(), "the last seat left: closed")
	check_equal(_of(&"closed"), [[&"closed", boss.id]] as Array[Array], "told closed")


func test_it_closes_when_the_run_ends() -> void:
	_play()
	var id: int = _boss().id
	flow.stop_run()
	check(not _stopped(), "the run's end lets the intro's stop go")
	check_equal(_of(&"closed"), [[&"closed", id]] as Array[Array], "told closed")
	check(not flow.boss_intro.opened and not flow.boss_intro.done, "cleared with the run")


func test_it_closes_when_its_boss_leaves_the_tree() -> void:
	_play()
	var boss: Actor = _boss()
	boss.get_parent().remove_child(boss)
	await physics_frame
	await physics_frame
	check(not _stopped(), "its boss went: closed by Flow's step through its stop")
	check_equal(_of(&"closed").size(), 1, "told closed")
	boss.free()


func test_a_staff_pressed_during_it_casts_nothing_on_the_first_tick() -> void:
	_play()
	var wizard: Actor = flow.get_wizard(0) as Actor
	await physics_frame
	# The dash on RB (staff 0), tapped while the game stands stopped.
	input.send_virtual(0, &"staff_1", 1.0)
	await physics_frame
	input.send_virtual(0, &"staff_1", 0.0)
	await physics_frame
	await _next(0, 0)
	# The last A, and a tap on the same frame: the tick it closes on.
	events.emit_signal("boss_intro_next_requested", 0, 1)
	input.send_virtual(0, &"staff_1", 1.0)
	input.send_virtual(0, &"staff_1", 0.0)
	await commands_applied()
	check(not tick.sim.is_stopped(), "the fight goes on")
	for i in 3:
		await physics_frame
	check_equal(int(casts.get(wizard.id, 0)), 0, "no cast from the presses made during the intro")
	# The same tap now the fight goes: it casts, so the test sees a cast when there is one.
	input.send_virtual(0, &"staff_1", 1.0)
	await physics_frame
	input.send_virtual(0, &"staff_1", 0.0)
	for i in 3:
		await physics_frame
	check(int(casts.get(wizard.id, 0)) > 0, "a tap in the fight casts")


## A keyboard's Space is A and staff 1 at once (review of BI2): a staff held down as the intro closes
## is not held for the fight until it is let go, then it casts again.
func test_a_staff_held_through_the_close_casts_nothing_until_let_go() -> void:
	_play()
	var wizard: Actor = flow.get_wizard(0) as Actor
	await _next(0, 0)
	input.send_virtual(0, &"staff_1", 1.0)
	events.emit_signal("boss_intro_next_requested", 0, 1)
	await commands_applied()
	check(not tick.sim.is_stopped(), "the fight goes on")
	for i in 20:
		await physics_frame
	check_equal(int(casts.get(wizard.id, 0)), 0, "held through the close: no cast while it stays held")
	check(tick.sim.held_through[0] != 0, "kept out of the frames as the game's state")
	input.send_virtual(0, &"staff_1", 0.0)
	await physics_frame
	await physics_frame
	check_equal(tick.sim.held_through[0], 0, "let go: no longer kept out")
	input.send_virtual(0, &"staff_1", 1.0)
	for i in 3:
		await physics_frame
	input.send_virtual(0, &"staff_1", 0.0)
	check(int(casts.get(wizard.id, 0)) > 0, "pressed again, it casts")


## A snapshot with no intro open restored over a machine showing one (a joiner's own run's, a seek):
## the intro closes and the HUD is told, with no actor (review of BI2).
func test_a_snapshot_with_none_open_closes_one_shown() -> void:
	_play()
	await _next(0, 0)
	await _next(0, 1)
	check(not _stopped(), "closed")
	var snapshot: Snapshot = Snapshot.take(tick.state_areas(), root)
	flow.stop_run()
	_play()
	check(_stopped(), "a run of its own, its intro open")
	heard.clear()
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored without problems")
	check(not flow.boss_intro.opened and not _stopped(), "closed, and the game goes")
	check_equal(_of(&"closed"), [[&"closed", ActorsScript.NONE]] as Array[Array], "the HUD told none is open")


func test_a_snapshot_mid_intro_restores_its_page_and_opens_it_not_fresh() -> void:
	_play(2)
	var boss: Actor = _boss()
	await _next(0, 0)
	var snapshot: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	await _next(0, 1)
	check(not _stopped(), "closed after the snapshot")
	heard.clear()
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored without problems")
	check(flow.boss_intro.opened, "open again")
	check_equal(flow.boss_intro.page, 1, "on its page")
	check(flow.boss_intro.boss == boss, "for its boss")
	check(_stopped(), "the game stopped for it again")
	check_equal(_of(&"opened").size(), 1, "told open")
	if not _of(&"opened").is_empty():
		check_equal(_of(&"opened")[0][5], 1, "on page 1")
		check_equal(_of(&"opened")[0][6], false, "not fresh: the HUD shows the page revealed")
	await _next(1, 1)
	check(not tick.sim.is_stopped(), "its last page lets the game go, as before")


func test_a_recording_of_an_intro_plays_back_the_same() -> void:
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA, LAIR, RoomKind.FILL_BOSS)
	input.add_virtual_device(0)
	await physics_frame
	var recorded := Desync.new()
	var replay: Replay = frames.call("record", &"play_requested", 0) as Replay
	check(_stopped(), "the recorded run stops for its intro")
	var closed_at: int = -1
	for i in 60:
		await physics_frame
		recorded.capture(tick.state_areas())
		if i == 10:
			events.emit_signal("boss_intro_next_requested", 0, 0)
		if i == 20:
			events.emit_signal("boss_intro_next_requested", 0, 1)
		if closed_at < 0 and not _of(&"closed").is_empty():
			closed_at = i
	replay = frames.call("stop_recording") as Replay
	check(closed_at > 20, "closed by the recorded A")
	check_equal(replay.rules.boss_intros, 1, "the rule in the replay's header")
	# The machine's own rule off: the replay plays by its header.
	SessionRules.machine().boss_intros = 0
	flow.stop_run()
	heard.clear()
	var played := Desync.new()
	check(bool(frames.call("play", replay)), "it plays")
	check(_stopped(), "the replay stops for its intro too")
	var replay_closed_at: int = -1
	for i in replay.tick_count():
		await physics_frame
		played.capture(tick.state_areas())
		if replay_closed_at < 0 and not _of(&"closed").is_empty():
			replay_closed_at = i
	check_equal(replay_closed_at, closed_at, "closed on the same tick")
	var parting: int = Desync.first_parting(recorded, played)
	check(parting < 0, "the same state at every tick: %s" % (Desync.compare(recorded, played) if parting >= 0 else ""))

