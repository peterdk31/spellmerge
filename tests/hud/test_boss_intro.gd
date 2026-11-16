extends "res://tests/support/suite.gd"
## The boss intro's overlay and its sounds (docs/milestones/boss-intro.md, step BI4): the HUD's
## `hud/panels/boss/boss_intro.gd` on a Hud of the test's own bus, driven by the three events alone
## (the hold that sends them is tested in tests/gameplay/flow/test_boss_intro_hold.gd), and Feel's
## `gameplay/feel/boss_intro_sound.gd`. The timeline's moments at fixed deltas; A ignored before the
## reveal is over and under the pause menu; a typing line written out here alone; the command sent with
## the page shown, for this machine's seats only; an open not fresh shows its page revealed; the bar
## and the banner kept back for a boss with an intro (the bar until the close, the banner unless no
## intro played); the builder and the inventory kept shut; Feel's cues at their moments while the tree
## is paused. The boss is the test's own (tests/support/intro_boss.gd), with a stand-in portrait.
##
## godot --headless --path . --script res://tests/hud/test_boss_intro.gd

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const BossIntroScript := preload("res://hud/panels/boss/boss_intro.gd")
const BossIntroSoundScript := preload("res://gameplay/feel/boss_intro_sound.gd")
const IntroBoss := preload("res://tests/support/intro_boss.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
## Loaded when needed, not preloaded: the scene is also the "Hud" autoload (see test_panels.gd).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const NO_SAVE: String = "user://test_no_save.cfg"
const BOSS: int = 7
const DT: float = 1.0 / 60.0


## A frames service that says which seats this machine plays.
class Here:
	extends Node
	var mask: int = 1

	func seats_here() -> int:
		return mask


## A registry that knows the test's cues, each with a sound of its own name, and a silent stream for
## each.
class CueRegistry:
	extends Node
	var cues: Dictionary = {}
	var stream: AudioStreamWAV = AudioStreamWAV.new()

	func know(id: StringName) -> void:
		var cue := CueBase.new()
		cue.id = id
		cue.sound = id
		cues[id] = cue

	func get_resource(folder: StringName, id: StringName) -> Resource:
		return cues.get(id) as Resource if folder == &"cues" else null

	func get_sound(id: StringName) -> AudioStream:
		return stream if cues.has(id) else null


var hud: HudScript
var bus: EventsScript
var input: InputManagerScript
var focus: UIFocusScript
var here: Here
var intro: BossIntroScript
## Every `boss_intro_next_requested` sent: [seat, page].
var asked: Array[Array] = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	input = own(InputManagerScript.new()) as InputManagerScript
	root.add_child(input)
	focus = own(UIFocusScript.new()) as UIFocusScript
	focus.input = input
	focus.events = bus
	here = own(Here.new()) as Here
	hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	hud.events = bus
	hud.save = SaveFile.new(NO_SAVE)
	hud.ui_focus = focus
	hud.input = input
	root.add_child(hud)
	intro = hud.get_boss_intro()
	intro.frames = here
	asked.clear()
	bus.boss_intro_next_requested.connect(func(seat: int, page: int) -> void: asked.append([seat, page]))


func after_each() -> void:
	hud.free()
	for seat in 4:
		input.leave(seat)


func _open(lines: Array[String] = IntroBoss.LINES, fresh: bool = true, page: int = 0) -> BossIntro:
	var data: BossIntro = IntroBoss.intro(lines)
	bus.boss_intro_opened.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, data, page, fresh)
	return data


## Step the overlay to `time` seconds since it opened, a frame of DT at a time.
func _to(time: float) -> void:
	while intro.time() + DT * 0.5 < time:
		intro.step(DT)


func test_it_is_over_the_world_and_the_panels_and_under_the_menus() -> void:
	var root_control: Control = hud.get_node("Root") as Control
	check(hud.get_node_or_null("Root/BossIntro") == intro, "the node Root/BossIntro")
	check(intro.get_index() > hud.get_panel(3).get_index(), "over the corner panels")
	check(intro.get_index() > hud.get_boss_bar().get_index(), "over the boss bar")
	check(intro.get_index() < hud.get_pause_menu().get_index(), "under the pause menu and its shade")
	check(not intro.visible and not intro.is_open(), "shut with no intro")
	check(root_control.get_child_count() > 0, "the root holds it")


func test_the_timeline_plays_its_moments() -> void:
	_open()
	check(intro.visible and intro.is_open(), "it shows as it opens")
	check_equal(intro.bars_in(), 0.0, "the room shows a moment first")
	_to(BossIntro.LEAD + (BossIntro.SLASH_AT - BossIntro.LEAD) * 0.5)
	check(intro.bars_in() > 0.0 and intro.bars_in() < 1.0, "the bars slide in")
	_to(BossIntro.SLASH_AT - DT)
	check(not intro.get_node("Stage/Portrait").visible, "no portrait before the slash")
	_to(BossIntro.SLASH_AT + DT)
	check_equal(intro.bars_in(), 1.0, "in by the slash")
	_to(BossIntro.SLASH_AT + 0.2)
	check(intro.get_node("Stage/Portrait").visible, "the portrait comes in on the slash")
	check(not intro.is_revealed(), "black")
	check_equal(intro.eyes_glow(), 0.0, "its eyes dark before the silhouette holds")
	_to(BossIntro.DARK_AT + 0.3)
	check(intro.eyes_glow() > 0.0, "its eyes light in the dark")
	check_equal(intro.letters_shown(), 0, "no name before the reveal")
	_to(BossIntro.REVEAL_AT - DT)
	check(not intro.is_revealed() and not intro.is_flashing(), "not yet")
	var flashed: int = 0
	var shook: bool = false
	for i in BossIntro.FLASH_FRAMES + 3:
		intro.step(DT)
		flashed += 1 if intro.is_flashing() else 0
		shook = shook or intro.shake_offset() != Vector2.ZERO
	check(intro.is_revealed(), "revealed")
	check_equal(flashed, BossIntro.FLASH_FRAMES, "a white flash for its frames")
	check(shook, "the overlay shakes")
	check_equal(intro.eyes_glow(), 0.0, "the mean pose has its own eyes")
	check(intro.letters_shown() >= 1, "the name's letters slam in")
	check(intro.letters_shown() < IntroBoss.NAME.length(), "letter by letter")
	_to(BossIntro.REVEAL_AT + BossIntro.SHAKE_TIME + DT)
	check_equal(intro.shake_offset(), Vector2.ZERO, "settled within its time")
	_to(intro.name_done_at())
	check_equal(intro.letters_shown(), IntroBoss.NAME.length(), "the whole name")
	for i in IntroBoss.NAME.length():
		check_equal(intro.letter_size(i), 32, "letter %d at its 2x" % i)
	check(not intro.get_node("Stage/Line").visible, "no line before LINES_AT")
	_to(BossIntro.LINES_AT + DT)
	check(intro.get_node("Stage/Line").visible, "the dialog shows")
	check_equal(intro.shown_line(), IntroBoss.LINES[0], "the first line")
	_to(BossIntro.LINES_AT + 0.5)
	check_equal(intro.typed_line(), IntroBoss.LINES[0].left(int((intro.time() - BossIntro.LINES_AT) * BossIntro.TYPE_RATE)), "typing out at its rate")
	check(intro.typed_line().length() >= int(0.5 * BossIntro.TYPE_RATE) - 1, "about half a second's")
	check_equal(intro.typed_lore(), IntroBoss.LORE, "the lore line typed out under the name")


func test_a_letter_slams_from_4x_to_2x_in_whole_steps() -> void:
	_open()
	_to(BossIntro.REVEAL_AT)
	var sizes: Array[int] = []
	for i in 12:
		var font_size: int = intro.letter_size(0)
		if font_size > 0 and (sizes.is_empty() or sizes[-1] != font_size):
			sizes.append(font_size)
		intro.step(DT)
	check_equal(sizes, [64, 48, 32] as Array[int], "4x, 3x, then its 2x")
	check_equal(intro.letter_size(1) > 0, true, "the next letter follows")


func test_with_no_lines_a_and_fight_show_under_the_name() -> void:
	_open([] as Array[String])
	_to(BossIntro.LINES_AT + DT)
	check(intro.is_fight_shown(), "Fight under the name")
	check(not intro.get_node("Stage/Line").visible, "no dialog box")
	check(intro.is_line_written(), "nothing to type")


func test_a_does_nothing_before_the_reveal_is_over() -> void:
	_open()
	_to(BossIntro.REVEAL_AT + 0.1)
	check(not intro.press(0), "a press during the reveal sends nothing")
	check(asked.is_empty(), "no command")
	check_equal(intro.typed_line(), "", "and writes nothing out")


func test_a_on_a_typing_line_writes_it_out_here_alone() -> void:
	_open()
	_to(BossIntro.LINES_AT + 0.1)
	check(not intro.is_line_written(), "still typing")
	check(not intro.press(0), "the first press sends nothing")
	check(asked.is_empty(), "no command: the other machines keep typing theirs")
	check(intro.is_line_written(), "written out")
	check_equal(intro.typed_line(), IntroBoss.LINES[0], "the whole line")
	check(intro.press(0), "the next press asks for the next page")
	check_equal(asked, [[0, 0]] as Array[Array], "with the page shown")


func test_the_command_carries_the_page_and_only_this_machines_seats_send_it() -> void:
	here.mask = 0b0010
	_open()
	_to(BossIntro.LINES_AT + 3.0)
	check(not intro.press(0), "seat 0 is another machine's")
	check(intro.press(1), "seat 1 is this machine's")
	check_equal(asked, [[1, 0]] as Array[Array], "page 0, from seat 1")
	bus.boss_intro_paged.emit(1)
	check_equal(intro.shown_page(), 1, "the next page")
	check_equal(intro.shown_line(), IntroBoss.LINES[1], "its line")
	check(not intro.is_line_written(), "typing from its start")
	intro.step(3.0)
	check(intro.press(1), "written out: the next page")
	check_equal(asked[-1], [1, 1], "page 1 this time")


func test_a_is_the_pause_menus_while_it_is_open() -> void:
	input.add_virtual_device(0)
	bus.player_joined.emit(0)
	bus.room_entered.emit(&"test_room")
	_open()
	_to(BossIntro.LINES_AT + 3.0)
	hud.get_pause_menu().open_menu(0)
	check(hud.get_pause_menu().is_open(), "the pause menu opens over it")
	check(not intro.press(0), "A under the pause menu is the menu's")
	_tap(0, &"accept")
	hud.poll()
	check(asked.is_empty(), "nor through the panels")
	hud.get_pause_menu().close_menu()
	hud.poll()
	_tap(0, &"accept")
	hud.poll()
	check_equal(asked, [[0, 0]] as Array[Array], "the menu shut, the panels hand A to it")


func test_the_builder_and_the_inventory_stay_shut_while_it_is_open() -> void:
	input.add_virtual_device(0)
	bus.player_joined.emit(0)
	bus.room_entered.emit(&"test_room")
	hud.poll()
	_tap(0, &"back")
	hud.poll()
	check(hud.get_radial(0).is_open(), "the builder opens with no intro")
	_open()
	check(not hud.get_radial(0).is_open(), "and closes as the intro opens")
	hud.poll()
	hud.poll()
	_tap(0, &"back")
	hud.poll()
	check(not hud.get_radial(0).is_open(), "the builder is refused while it is open")
	_tap(0, &"inventory")
	hud.poll()
	check(not hud.get_inventory(0).is_open(), "the inventory too")
	_tap(0, &"pause")
	hud.poll()
	check(hud.get_pause_menu().is_open(), "the pause menu still opens")


func test_an_open_not_fresh_shows_its_page_revealed() -> void:
	var data: BossIntro = _open(IntroBoss.LINES, false, 1)
	check(intro.is_open() and intro.is_revealed(), "revealed at once")
	check_equal(intro.shown_page(), 1, "on its page")
	check_equal(intro.typed_line(), IntroBoss.LINES[1], "its line written out")
	check_equal(intro.letters_shown(), IntroBoss.NAME.length(), "the whole name")
	check(not intro.is_flashing(), "no flash")
	intro.step(DT)
	check(intro.press(0), "A asks for the next page at once")
	var before: float = intro.time()
	bus.boss_intro_opened.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, data, 1, true)
	check_equal(intro.time(), before, "an open of the boss and page shown changes nothing")


func test_it_closes_the_way_it_came_then_hides() -> void:
	_open()
	_to(BossIntro.LINES_AT + 1.0)
	bus.boss_intro_closed.emit(BOSS + 1)
	check(intro.is_open(), "another boss's close is not its")
	bus.boss_intro_closed.emit(BOSS)
	check(intro.is_showing() and not intro.is_open(), "leaving")
	check(not intro.press(0), "A is no more its")
	intro.step(BossIntroScript.CLOSE_TIME * 0.5)
	check(intro.bars_in() > 0.0 and intro.bars_in() < 1.0, "the bars slide out")
	intro.step(BossIntroScript.CLOSE_TIME)
	check(not intro.visible and not intro.is_showing(), "gone")
	_open()
	bus.boss_intro_closed.emit(-1)
	check(not intro.is_open(), "a close of no actor closes whatever shows")


func test_the_bar_waits_for_the_close_and_fades_in() -> void:
	var bar: Control = hud.get_boss_bar()
	bus.boss_shown.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, PackedFloat32Array(), true)
	bus.boss_health_changed.emit(BOSS, 500.0, 1000.0)
	_open()
	hud.get_boss_bar().step(DT)
	(hud as Node).call("_process", DT)
	check(not bar.visible, "no bar under the intro")
	check(not hud.get_boss_banner().visible, "no banner for a boss with an intro")
	bus.boss_intro_closed.emit(BOSS)
	check(bar.visible, "the bar comes as it closes")
	check_equal(bar.modulate.a, 0.0, "fading in")
	check_equal(hud.get_boss_bar().shown_share(), 0.5, "with the health told meanwhile")
	hud.get_boss_bar().step(1.0)
	check_equal(bar.modulate.a, 1.0, "in")
	check(not hud.get_boss_banner().visible, "still no banner: the overlay was its entrance")


func test_with_no_intro_opened_the_bar_and_banner_show_at_the_frames_end() -> void:
	# The run's rule off (automation): no intro opens for it.
	bus.boss_shown.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, PackedFloat32Array(), true)
	check(not hud.get_boss_bar().visible, "kept back on the frame it shows")
	(hud as Node).call("_process", DT)
	check(hud.get_boss_bar().visible, "the bar at the frame's end")
	check(hud.get_boss_banner().visible, "and the banner, as for a boss with no intro")
	check_equal(hud.get_boss_banner().shown_name(), IntroBoss.NAME, "its name")


func test_the_intro_opened_before_it_was_shown_still_keeps_them_back() -> void:
	_open()
	bus.boss_shown.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, PackedFloat32Array(), true)
	(hud as Node).call("_process", DT)
	check(not hud.get_boss_bar().visible and not hud.get_boss_banner().visible, "either order: kept back")
	bus.boss_intro_closed.emit(BOSS)
	check(hud.get_boss_bar().visible, "the bar after the close")


func test_a_run_ending_clears_it() -> void:
	_open()
	bus.run_ended.emit(false)
	check(not intro.visible and not intro.is_showing(), "nothing over the menu")


func test_feels_cues_play_at_their_moments_while_the_tree_is_paused() -> void:
	var registry: CueRegistry = own(CueRegistry.new()) as CueRegistry
	registry.know(&"test_dark")
	registry.know(&"test_reveal")
	var sound: BossIntroSoundScript = own(BossIntroSoundScript.new()) as BossIntroSoundScript
	sound.registry = registry
	root.add_child(sound)
	sound.bind(bus)
	var data: BossIntro = IntroBoss.intro()
	data.dark_cue = &"test_dark"
	data.reveal_cue = &"test_reveal"
	bus.boss_intro_opened.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, data, 0, false)
	sound.step(BossIntro.REVEAL_AT + 1.0)
	check(sound.played.is_empty(), "a restored intro plays nothing: its moments are past")
	paused = true
	bus.boss_intro_opened.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, data, 0, true)
	var frames_waited: int = 0
	while sound.played.size() < 2 and frames_waited < 600:
		await process_frame
		frames_waited += 1
	paused = false
	check_equal(sound.played, [&"test_dark", &"test_reveal"] as Array[StringName], "the dark cue, then the reveal's, with the tree paused")
	sound.stop()
	bus.boss_intro_opened.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, data, 0, true)
	sound.step(BossIntro.DARK_AT - 0.01)
	check(sound.played.is_empty(), "nothing before DARK_AT")
	sound.step(0.02)
	check_equal(sound.played, [&"test_dark"] as Array[StringName], "the dark cue at DARK_AT")
	sound.step(BossIntro.REVEAL_AT - BossIntro.DARK_AT - 0.02)
	check_equal(sound.played.size(), 1, "the reveal's not yet")
	sound.step(0.02)
	check_equal(sound.played[-1], &"test_reveal", "the reveal's at REVEAL_AT")
	sound.stop()
	sound.played.clear()
	data.reveal_cue = &""
	bus.boss_intro_opened.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, data, 0, true)
	sound.step(BossIntro.DARK_AT + 0.01)
	bus.boss_intro_closed.emit(BOSS)
	sound.step(BossIntro.REVEAL_AT)
	check_equal(sound.played, [&"test_dark"] as Array[StringName], "closed: nothing more plays")
	bus.boss_intro_opened.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, data, 0, true)
	sound.step(BossIntro.REVEAL_AT + 0.01)
	check_equal(sound.played[-1], BossIntro.SHARED_REVEAL_CUE, "no reveal cue of its own: the shared one")


func test_feel_plays_no_entrance_cue_for_a_boss_whose_intro_plays() -> void:
	var wait := BossIntroWait.new()
	var released: Array[Array] = []
	wait.released.connect(func(actor: int, played: bool) -> void: released.append([actor, played]))
	wait.bind(bus)
	bus.boss_shown.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, PackedFloat32Array(), true)
	_open()
	wait.settle()
	check(released.is_empty(), "its intro opened: it waits for the close")
	bus.boss_intro_closed.emit(BOSS)
	check_equal(released, [[BOSS, true]] as Array[Array], "released as played: no banner, no entrance cue")
	bus.boss_shown.emit(BOSS + 1, "", "", PackedFloat32Array(), true)
	wait.settle()
	check_equal(released[-1], [BOSS + 1, false], "none opened by the frame's end: released unplayed")
	bus.boss_shown.emit(BOSS + 2, "", "", PackedFloat32Array(), true)
	bus.boss_hidden.emit(BOSS + 2)
	wait.settle()
	check_equal(released.size(), 2, "a boss gone meanwhile is never released")


func _tap(seat: int, action: StringName) -> void:
	input.send_virtual(seat, action, 1.0)
	input.send_virtual(seat, action, 0.0)


func test_a_second_boss_with_an_intro_waits_for_the_first_ones_close() -> void:
	# Review of BI4: the hold opens only the first boss's intro; the other's bar must not show under it.
	bus.boss_shown.emit(BOSS, IntroBoss.NAME, IntroBoss.LORE, PackedFloat32Array(), true)
	bus.boss_shown.emit(BOSS + 1, "The Other", "", PackedFloat32Array(), true)
	_open()
	(hud as Node).call("_process", DT)
	check(not hud.get_boss_bar().visible, "no bar under the open intro, for either boss")
	check(not hud.get_boss_banner().visible, "nor a banner")
	bus.boss_intro_closed.emit(BOSS)
	check_equal(hud.get_boss_bar().shown_boss(), BOSS, "the first boss's bar as it closes")
	(hud as Node).call("_process", DT)
	check(hud.get_boss_bar().is_held(BOSS + 1) == false, "the other released at that frame's end")
	check(hud.get_boss_banner().visible and hud.get_boss_banner().shown_name() == "The Other", "its banner then: no intro played for it")


func test_the_dialog_box_keeps_clear_of_the_portrait_on_a_narrow_view() -> void:
	_open()
	_to(BossIntro.LINES_AT + DT)
	check_equal(intro.box_rect().size.x, BossIntroScript.BOX_SIZE.x, "its full width at 640")
	intro.size = Vector2(480.0, 360.0)
	var portrait_left: float = 480.0 - BossIntroScript.PORTRAIT_RIGHT - BossIntro.FRAME * BossIntroScript.SCALE
	check(intro.box_rect().end.x <= portrait_left, "narrower, ending before the portrait")


func test_the_fight_glyph_is_not_lit_before_fight_shows() -> void:
	_open([] as Array[String])
	for i in 30:
		intro.step(DT)
		check(not intro.is_glyph_lit(), "no glyph before LINES_AT")
