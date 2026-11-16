extends "res://tests/support/screenshot.gd"
## The boss intro's filmstrip (docs/milestones/boss-intro.md, step BI4): for every boss with an intro
## (`EnemyBase.boss_intro`) played in a room of its biome that hosts bosses (a pinned run of that
## room), with one wizard, the run's rule on (`SessionRules.boss_intros`, off for automation): the
## silhouette (`boss_intro_<id>_1_silhouette`), its eyes lit (`_2_eyes`), the reveal (`_3_reveal`),
## each page written out (`_4_line1`, ...; with no lines, "Fight"), and the overlay leaving
## (`_9_closing`). With no boss of the game's with an intro, the tests' stand-in boss
## (tests/support/intro_boss.gd) plays in a copy of the crypt arena, so the overlay is always shown.
## Each picture is grabbed as it is drawn (no settling: the timeline is real time).
##
## godot --path . --script res://tests/screenshots/shot_boss_intro.gd

const BossIntroScript := preload("res://hud/panels/boss/boss_intro.gd")
const IntroBoss := preload("res://tests/support/intro_boss.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
## Frames to wait for the intro to open, and for each of its moments.
const OPEN_FRAMES: int = 60 * 5
const MOMENT_FRAMES: int = 60 * 8

var _registry: Node = null
var _flow: Node = null
var _events: Node = null


func _init() -> void:
	# The run is pinned here, in the boss's room.
	pin_room = false


func take() -> void:
	if not need(["Registry", "Flow", "PlayerInput", "Events", "Hud"]):
		return
	_registry = root.get_node("Registry")
	_flow = root.get_node("Flow")
	_events = root.get_node("Events")
	root.get_node("PlayerInput").call("add_virtual_device", 0)
	var bosses: Array[EnemyBase] = []
	for id: StringName in _registry.call("get_ids", &"bosses"):
		var data: EnemyBase = _registry.call("get_resource", &"bosses", id) as EnemyBase
		if data != null and data.boss_intro != null:
			bosses.append(data)
	var stand_in: bool = bosses.is_empty()
	if stand_in:
		print("No boss of the game's has an intro: the tests' stand-in shows it.")
		var made: EnemyBase = IntroBoss.make(_registry)
		IntroBoss.register(_registry, made)
		bosses.append(made)
	for data in bosses:
		var room: RoomBase = ARENA if stand_in else _boss_room(data)
		if room == null:
			print("SKIP: no room hosts the boss '%s'" % data.id)
			continue
		if not await _film(data, room, data.biomes[0] if stand_in else room.biome):
			return


## The filmstrip of `data`'s intro in a run of `room` in `biome`. False when it failed.
func _film(data: EnemyBase, room: RoomBase, biome: StringName) -> bool:
	# Automation turns the intros off (rule 4): this run has them on.
	SessionRules.machine().boss_intros = 1
	_flow.set("run_id_to_play", PinnedRun.pin(_registry, room, biome, RoomKind.FILL_BOSS))
	_flow.call("start_run", 0)
	var intro: BossIntroScript = root.get_node("Hud").call("get_boss_intro") as BossIntroScript
	if not await wait_for(func() -> bool: return intro.is_open(), OPEN_FRAMES):
		fail("the intro of '%s' did not open" % data.id)
		return false
	var prefix: String = "boss_intro_%s" % data.id
	if not await _at(intro, BossIntro.SLASH_AT + (BossIntro.DARK_AT - BossIntro.SLASH_AT) * 0.9, prefix + "_1_silhouette"):
		return false
	if not await _at(intro, BossIntro.DARK_AT + 0.4, prefix + "_2_eyes"):
		return false
	if not await _at(intro, intro.name_done_at() + BossIntroScript.GLINT_TIME * 0.5, prefix + "_3_reveal"):
		return false
	for page in data.boss_intro.pages():
		if not await wait_for(func() -> bool: return intro.shown_page() == page and intro.time() >= BossIntro.LINES_AT and intro.is_line_written(), MOMENT_FRAMES):
			fail("page %d of '%s' was not written out" % [page, data.id])
			return false
		await process_frame
		save(await grab(), "%s_4_line%d" % [prefix, page + 1])
		# A seat's A on the page written out (the HUD sends it for a seat of this machine; the
		# shot's seat is a virtual device, so it is sent here).
		_events.emit_signal("boss_intro_next_requested", 0, page)
	if not await wait_for(func() -> bool: return intro.is_showing() and not intro.is_open() and intro.bars_in() <= 0.6, MOMENT_FRAMES):
		fail("the intro of '%s' did not close" % data.id)
		return false
	save(await grab(), prefix + "_9_closing")
	_flow.call("stop_run")
	await settle(4)
	return true


## Wait for `intro`'s clock to pass `time`, then save the picture `shot_name`.
func _at(intro: BossIntroScript, time: float, shot_name: String) -> bool:
	if not await wait_for(func() -> bool: return intro.time() >= time, MOMENT_FRAMES):
		fail("the intro did not reach %.2f s for %s" % [time, shot_name])
		return false
	save(await grab(), shot_name)
	return true


## A room of `data`'s biomes that hosts a boss kind, or null.
func _boss_room(data: EnemyBase) -> RoomBase:
	var kinds: Array[StringName] = []
	for kind: Resource in _registry.call("get_all", &"room_kinds"):
		if kind is RoomKind and (kind as RoomKind).fill == RoomKind.FILL_BOSS:
			kinds.append((kind as RoomKind).id)
	for room: Resource in _registry.call("get_all", &"rooms"):
		var template := room as RoomBase
		if template == null or not data.biomes.has(template.biome) or String(template.id).begins_with(PinnedRun.PREFIX):
			continue
		for kind: StringName in kinds:
			if template.hosts(kind):
				return template
	return null
