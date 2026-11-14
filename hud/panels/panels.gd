extends CanvasLayer
## The corner panels of all players: the autoload "Hud". P1 is top left, P2 top
## right, P3 bottom left and P4 bottom right (nodes Root/Panel1 to Root/Panel4).
##
## A panel is shown for a joined player once a room has been entered, and hidden
## when the player leaves. A run starting or ending hides all panels and clears
## their numbers, so none stays over the menu. Numbers come only from `player_stats_changed`; the
## "MENU" word follows `UIFocus.opened` and `closed` for that player. Nothing is
## polled and nothing here takes input, so a player in their builder never makes
## another panel wait.
##
## Menus open only while a room is active, and close when the run starts or ends, so none is
## ever left open over the main menu. The pause menu's "Main menu" (`main_menu_requested`) clears
## them all and makes the main menu the current scene again (`main_menu`).
##
## Under each panel's mana bar, one row per staff with cards (owner, 2026-10-27): its cast
## sequence comes from `staff_changed` (the plain `Spells.staff_view`, icons asked of `Spells`
## once per plan), and its next cast and delay are read each frame from `Spells.cast_index` and
## `Spells.cooldown_left`, plain numbers that allocate nothing (`step_staffs`).
##
## A panel is always the player's own wizard (owner, 2026-10-28): its numbers and staff rows
## (`player_stats_changed`, `staff_changed` and the timing of `Spells.home_of_seat`) stay the
## wizard's while the seat drives another actor (possess, actors G9) and while an enemy's AI drives
## the wizard, so a player always sees their wizard taking hits. The possession itself is drawn
## in the world, over the possessed actor (`PossessedLook`).
##
## The loading screen (`loading/`, node Root/Loading, over everything) shows from
## `loading_started` to `loading_finished`, while flow compiles the shaders before the first room.
##
## A red vignette (`vignette/`, node Root/Vignette, behind the panels) glows when a
## wizard's health falls, strongest toward that wizard's corner and fading in under
## half a second. It is read from `player_stats_changed` alone (a drop in health),
## never from a node, and it takes no input.
##
## The buttons that open menus are read here, from the press counters of `core/input` (a tap
## released within a frame is not lost); each menu then takes its input through
## `core/ui_focus` (owner, 2026-10-26):
## - `back` (B; Tab or E on the keyboard) opens that player's radial spell builder
##   (`hud/builder/radial_builder.gd`, nodes Root/Radial1 to Root/Radial4, made here; owner,
##   2026-10-26) when they have no menu open, are not down and the pause menu is not open. It
##   never pauses the game; it is the full builder at any time, waves included (staffs A6a).
##   Inside a menu `back` is that menu's own (UIFocus `cancelled`), so a press only opens the
##   builder when the player had no menu open at the poll before it too. (The older list
##   builder is gone, owner 2026-11-11.) The pause menu's Sandbox page sets the radial's ring (its
##   layout, or a ring style from `builder/rings/`) and full-slot choice
##   (`builder_options_changed`). The same page switches where every corner panel's staff rows
##   show a staff's delay, on the button glyph (the default) or on the next cast
##   (`reload_style_changed`; owner, 2026-10-27).
## - `pause` (Start; Escape) closes the menu its player has open (the builder, or the pause menu
##   they opened); with none open it opens the pause menu (`hud/menus/pause/`, node
##   Root/PauseMenu), which stops the game for everyone and is worked by the player who opened
##   it. Another player's `pause` does nothing while it is open.
## - The pad line (`hud/widgets/pad_line.gd`, node Root/PadLine, made here; owner, 2026-11-13):
##   while the game waits for a seat's unplugged gamepad (`pad_wait_changed`), whose controller is
##   gone and how to go on. A waiting seat's open pause menu closes, and the pause menu another
##   player opens offers "Leave game" for this machine's waiting seats.
## - The online line (`hud/widgets/online_line.gd`, node Root/OnlineLine, made here; netcode spike
##   S4): what playing with other machines has to say, at the top middle (`online_changed`'s
##   reason and the line of `online_line_changed`, worded by `hud/widgets/online_words.gd`).
## - A seat played on another machine says so on its corner panel (online-lobby L5c): while this
##   machine plays with others (`online_changed`), a joined seat with no real device of this
##   machine on it (`core/input`) shows ONLINE (`PlayerPanel.set_online`, `poll`).
## - The stone line (`hud/widgets/stone_line.gd`, node Root/StoneLine, made here; online-lobby L1):
##   in the hub, how many wizards stand on the teleporter stone, or that A starts the run, at the
##   top middle under the online line (`start_stone_changed`). While the stone is lit, a player's
##   `accept` (A, Enter) with no menu open sends the command `run_requested` (`poll`).
## - The item hints (`item_hints.gd`, node Root/ItemHints, made here; items I6): over the item in
##   reach of each player's driven body (`item_near_changed`), its name and the A glyph, a staff's
##   numbers and cards under it, shaking red when a take is refused (`item_refused`). A with no menu
##   open and no lit stone takes it (`item_take_requested`); the altar's A comes after.
## - The frame rate readout (`hud/widgets/fps_counter.gd`, node Root/FpsCounter, made here; owner,
##   2026-11-02): "60 FPS" at the bottom middle, over everything, shown while the pause menu's
##   "Show FPS" switch is on (read after the menu is bound, then `show_fps_changed`).

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const PauseMenuScript := preload("res://hud/menus/pause/pause_menu.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const RingZoomScript := preload("res://hud/builder/rings/ring_zoom.gd")
const RingKindsScript := preload("res://hud/builder/rings/ring_kinds.gd")
const PlayerPanelScript := preload("res://hud/panels/player_panel/player_panel.gd")
const StaffRowScript := preload("res://hud/panels/player_panel/staff_row.gd")
const VignetteScript := preload("res://hud/panels/vignette/vignette.gd")
const LoadingScript := preload("res://hud/panels/loading/loading_screen.gd")
const HammerIconScript := preload("res://hud/widgets/hammer_icon.gd")
const FpsCounterScript := preload("res://hud/widgets/fps_counter.gd")
const OnlineLineScript := preload("res://hud/widgets/online_line.gd")
const StoneLineScript := preload("res://hud/widgets/stone_line.gd")
const PadLineScript := preload("res://hud/widgets/pad_line.gd")
const ItemHintsScript := preload("res://hud/panels/item_hints.gd")

const PLAYER_COUNT: int = 4
const PAUSE_ACTION: StringName = &"pause"
const BUILDER_ACTION: StringName = &"back"
## A on the hub's lit stone starts the run (`run_requested`; online-lobby L1); else it takes the
## item in reach (`item_take_requested`; items I6), else it opens the altar's room.
const START_ACTION: StringName = &"accept"
## Space between the screen edge and a panel.
const EDGE_MARGIN: float = 4.0
## How far below the online line the stone line sits, in pixels.
const STONE_LINE_DROP: float = 12.0
## How far below the top the pad line sits: under the stone line.
const PAD_LINE_DROP: float = 26.0
## The "Wave N" line and the build break line (hammer and "Build 12") sit side by side in one
## strip in the middle of the view.
const WAVE_LABEL_WIDTH: float = 80.0
const WAVE_LABEL_FONT_SIZE: int = 12
const WAVE_LABEL_OUTLINE: int = 3
const BREAK_FONT_SIZE: int = 12
const STRIP_SEPARATION: int = 6

## The event bus, the UI focus service, the input manager and the spell runtime (the
## radials ask it for names and icons). Only tests set these, before adding the
## node; otherwise the "Events", "UIFocus", "PlayerInput" and "Spells" autoloads.
var events: EventsScript = null
var ui_focus: UIFocusScript = null
var input: InputManagerScript = null
var spells: SpellsScript = null
## The save that keeps the menu's settings; the default one (`user://save.cfg`) when null.
var save: SaveFile = null
## The main menu shown on `main_menu_requested`; null: the game's own (its main scene,
## `hud/menus/main_menu/`). Tests give their own.
var main_menu: PackedScene = null

var _panels: Array[PlayerPanelScript] = []
var _radials: Array[RadialScript] = []
var _pause_menu: PauseMenuScript = null
## Per player: the `pause` and `back` press counts at the last poll, and whether a menu of
## theirs was open then.
var _seen_pause: Array[int] = [0, 0, 0, 0]
var _seen_back: Array[int] = [0, 0, 0, 0]
var _seen_start: Array[int] = [0, 0, 0, 0]
## True while the hub's teleporter stone is lit (`start_stone_changed`).
var _stone_lit: bool = false
## The seats whose wizards stand on the hub's multiplayer altar (`altar_changed`), a bit each.
var _altar_seats: int = 0
## Whether this machine plays with others now (`online_changed`): only then is a seat marked.
var _online: bool = false
var _had_menu: Array[bool] = [false, false, false, false]
## A wave is in progress (the wave line shows).
var _wave_active: bool = false
## Each seat's staffs' mana and what their sustained cards hold (`staff_mana_changed`,
## `mana_reserved`), by seat * STAFF_COUNT + staff: what a press could pay, for the staff rows.
var _staff_mana: PackedFloat32Array = PackedFloat32Array()
var _staff_reserved: PackedFloat32Array = PackedFloat32Array()
var _joined: Array[bool] = [false, false, false, false]
var _in_room: bool = false
var _vignette: VignetteScript = null
var _loading: LoadingScript = null
## The strip in the middle of the view that holds the wave line and the break line.
var _strip: HBoxContainer = null
var _wave_label: Label = null
## The build break line: a row (hidden outside a break) with the hammer and the countdown.
var _break_row: PanelContainer = null
var _break_label: Label = null
## Seconds of the break left; counted down here from `build_break_started`, display only.
var _break_left: float = 0.0
## The frame rate readout (see the top).
var _fps: FpsCounterScript = null
var _online_line: OnlineLineScript = null
var _stone_line: StoneLineScript = null
## Every player's hint over the item in reach (items I6).
var _item_hints: ItemHintsScript = null
var _pad_line: PadLineScript = null


func _ready() -> void:
	_staff_mana.resize(PLAYER_COUNT * PlayerPanelScript.STAFF_COUNT)
	_staff_mana.fill(INF)
	_staff_reserved.resize(PLAYER_COUNT * PlayerPanelScript.STAFF_COUNT)
	# The pause menu is worked while the game is paused, so the HUD runs then too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Behind the panels: the first child of Root.
	_vignette = VignetteScript.new()
	_vignette.name = "Vignette"
	var root_control: Control = get_node("Root") as Control
	root_control.add_child(_vignette)
	root_control.move_child(_vignette, 0)
	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.visible = false
	_wave_label.add_theme_font_size_override("font_size", WAVE_LABEL_FONT_SIZE)
	_wave_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_wave_label.add_theme_constant_override("outline_size", WAVE_LABEL_OUTLINE)
	var wave_backing := StyleBoxFlat.new()
	wave_backing.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	_wave_label.add_theme_stylebox_override("normal", wave_backing)
	_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.custom_minimum_size = Vector2(WAVE_LABEL_WIDTH, 0.0)
	_wave_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip = HBoxContainer.new()
	_strip.name = "Strip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_strip.add_theme_constant_override("separation", STRIP_SEPARATION)
	_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_strip.grow_vertical = Control.GROW_DIRECTION_BOTH
	_strip.add_child(_wave_label)
	# Above the vignette, below the panels and the builders (it sits in the gap between them).
	root_control.add_child(_strip)
	root_control.move_child(_strip, 1)
	_break_row = PanelContainer.new()
	_break_row.name = "BreakRow"
	_break_row.visible = false
	_break_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	backing.content_margin_left = 2.0
	backing.content_margin_right = 2.0
	_break_row.add_theme_stylebox_override("panel", backing)
	var box := HBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_break_row.add_child(box)
	var hammer: Control = HammerIconScript.new()
	hammer.name = "Hammer"
	box.add_child(hammer)
	_break_label = Label.new()
	_break_label.name = "BreakLabel"
	_break_label.add_theme_font_size_override("font_size", BREAK_FONT_SIZE)
	_break_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_break_label)
	_break_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip.add_child(_break_row)
	for player in PLAYER_COUNT:
		var panel := get_node("Root/Panel%d" % (player + 1)) as PlayerPanelScript
		panel.visible = false
		_panels.append(panel)
	_pause_menu = get_node("Root/PauseMenu") as PauseMenuScript
	for player in PLAYER_COUNT:
		var radial := RadialScript.new()
		radial.name = "Radial%d" % (player + 1)
		radial.index = player
		root_control.add_child(radial)
		# Under the corner panels (its shade leaves their band free but never dims them).
		root_control.move_child(radial, _panels[0].get_index())
		_radials.append(radial)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if ui_focus == null:
		ui_focus = get_node_or_null("/root/UIFocus") as UIFocusScript
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
	if spells == null:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	# Over everything: the loading screen before the first room.
	_loading = LoadingScript.new()
	_loading.events = events
	root_control.add_child(_loading)
	if input != null:
		for player in PLAYER_COUNT:
			_seen_pause[player] = input.get_press_count(player, PAUSE_ACTION)
			_seen_back[player] = input.get_press_count(player, BUILDER_ACTION)
			_seen_start[player] = input.get_press_count(player, START_ACTION)
	_pause_menu.save = save
	_pause_menu.bind(events, ui_focus)
	for radial in _radials:
		radial.bind(events, ui_focus, spells, input)
	_pause_menu.builder_options_changed.connect(_on_builder_options_changed)
	_pause_menu.reload_style_changed.connect(_on_reload_style_changed)
	# The frame rate readout: over everything, at the bottom middle.
	_fps = FpsCounterScript.new()
	_fps.name = "FpsCounter"
	root_control.add_child(_fps)
	_fps.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN))
	_fps.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fps.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fps.visible = _pause_menu.show_fps
	_pause_menu.show_fps_changed.connect(_on_show_fps_changed)
	# The online line: at the top middle, while a run is played with another machine.
	_online_line = OnlineLineScript.new()
	_online_line.name = "OnlineLine"
	root_control.add_child(_online_line)
	_online_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN))
	_online_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_online_line.bind(events)
	# The stone line: under the online line, while the party is in the hub.
	_stone_line = StoneLineScript.new()
	_stone_line.name = "StoneLine"
	root_control.add_child(_stone_line)
	_stone_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN + STONE_LINE_DROP))
	_stone_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stone_line.bind(events)
	# The pad line: under those, while the game waits for a seat's unplugged gamepad.
	_pad_line = PadLineScript.new()
	_pad_line.name = "PadLine"
	root_control.add_child(_pad_line)
	_pad_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN + PAD_LINE_DROP))
	_pad_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pad_line.bind(events)
	# The item hints: in the world's picture, under the panels and the builders.
	_item_hints = ItemHintsScript.new()
	_item_hints.name = "ItemHints"
	root_control.add_child(_item_hints)
	root_control.move_child(_item_hints, 1)
	_item_hints.bind(events, input, spells)
	if events != null:
		events.pad_wait_changed.connect(_on_pad_wait_changed)
		events.player_joined.connect(_on_player_joined)
		events.player_left.connect(_on_player_left)
		events.player_stats_changed.connect(_on_stats_changed)
		events.room_entered.connect(_on_room_entered)
		events.start_stone_changed.connect(_on_start_stone_changed)
		events.altar_changed.connect(func(seats: int) -> void: _altar_seats = seats)
		events.online_changed.connect(_on_online_changed)
		events.wave_started.connect(_on_wave_started)
		events.room_cleared.connect(_on_room_cleared)
		events.build_break_started.connect(_on_build_break_started)
		events.staff_changed.connect(_on_staff_changed)
		events.staff_mana_changed.connect(_on_staff_mana_changed)
		events.mana_reserved.connect(_on_mana_reserved)
		events.cast_fizzled.connect(_on_cast_fizzled)
		events.run_started.connect(_on_run_started)
		events.run_ended.connect(_on_run_ended)
		events.main_menu_requested.connect(_on_main_menu_requested)
	if ui_focus != null:
		ui_focus.opened.connect(_on_menu_opened)
		ui_focus.closed.connect(_on_menu_closed)


func _process(delta: float) -> void:
	poll()
	step_hints(delta)
	_vignette.step(delta)
	step_break(delta)
	step_staffs()


## Put every player's item hint over its item as the camera shows it now (none outside a room,
## and none for a player with a menu open). Called every frame; tests call it directly.
func step_hints(delta: float) -> void:
	var menus: Array[bool] = [false, false, false, false]
	for player in PLAYER_COUNT:
		menus[player] = not _in_room or _has_menu(player) or (_pause_menu != null and _pause_menu.is_open())
	var viewport: Viewport = get_viewport()
	var to_screen: Transform2D = viewport.get_canvas_transform() if viewport != null else Transform2D.IDENTITY
	_item_hints.step(delta, menus, transform.affine_inverse() * to_screen)


## The item hints (for tests and screenshots).
func get_item_hints() -> ItemHintsScript:
	return _item_hints


## Count the break line down by `delta` seconds. It only draws; Flow decides when the wave
## starts, so a drift here never moves the wave. Called every frame; tests call it directly.
func step_break(delta: float) -> void:
	if not _break_row.visible:
		return
	_break_left = maxf(_break_left - delta, 0.0)
	_show_break_seconds()


func _show_break_seconds() -> void:
	_break_label.text = "Build %d" % ceili(_break_left)


## Read every joined player's `pause`, `back` and `accept` presses since the last poll (several
## presses in one frame count once) and open or close menus as the top of this file says; `accept`
## with no menu open while the hub's stone is lit sends `run_requested`, else with an item in reach
## `item_take_requested`, else on the altar `online_open_requested`. Presses outside a room are
## dropped. Called every frame by _process; tests call it directly. One player's press never
## touches another player's menus.
func poll() -> void:
	if input == null:
		return
	for player in PLAYER_COUNT:
		var pause_count: int = input.get_press_count(player, PAUSE_ACTION)
		var paused_now: bool = pause_count > _seen_pause[player]
		_seen_pause[player] = pause_count
		var back_count: int = input.get_press_count(player, BUILDER_ACTION)
		var back_now: bool = back_count > _seen_back[player]
		_seen_back[player] = back_count
		var start_count: int = input.get_press_count(player, START_ACTION)
		var start_now: bool = start_count > _seen_start[player]
		_seen_start[player] = start_count
		var had_menu: bool = _had_menu[player]
		if input.is_joined(player):
			if start_now and not had_menu and not _has_menu(player) and not _pause_menu.is_open() and events != null:
				if _stone_lit:
					events.run_requested.emit(player)
				elif _item_hints.item_of(player) >= 0:
					events.item_take_requested.emit(player, _item_hints.item_of(player))
				elif _altar_seats & (1 << player) != 0:
					events.online_open_requested.emit(player)
			if paused_now:
				_on_pause_pressed(player)
			elif back_now and not had_menu and not _has_menu(player) and _in_room \
					and not _pause_menu.is_open() and not _panels[player].is_downed():
				_radials[player].open_builder()
		_had_menu[player] = _has_menu(player)
		# A seat in the game with no device of this machine on it is played on another one. Asked
		# of the input layer each frame: a device handed over or mirrored sends no event.
		_panels[player].set_online(_online and _joined[player] and not _plays_here(player))


## Whether seat `player` is played on this machine: a real device sits on it (another machine's
## seat is a virtual device here, as a bot's is; `core/input`).
func _plays_here(player: int) -> bool:
	return input.is_joined(player) and not InputManagerScript.is_virtual(input.device_of(player))


## Playing with other machines began or ended (`online_changed`): the seats are marked only while
## it lasts (a room open or a run played), so offline a bot's or a recording's seat is not called
## online.
func _on_online_changed(phase: StringName, _code: String, _reason: StringName, _facts: Dictionary) -> void:
	_online = phase == EventsScript.ONLINE_CODE or phase == EventsScript.ONLINE_LINKED or phase == EventsScript.ONLINE_PLAYING


## Whether `player` has a menu open: their builder, or the pause menu they work.
func _has_menu(player: int) -> bool:
	return _radials[player].is_open() or _pause_menu.owner_player == player


## `pause`: close the player's open menu, or open the pause menu for them.
func _on_pause_pressed(player: int) -> void:
	if _radials[player].is_open():
		_radials[player].close_builder()
	elif _pause_menu.is_open():
		if _pause_menu.owner_player == player:
			_pause_menu.close_menu()
	elif _in_room:
		_pause_menu.open_menu(player)


## The seats the game waits for (their gamepad is unplugged; `pad_wait_changed`). A waiting seat
## cannot work a menu, so whatever it had open closes (its builder, or the pause menu, which another
## player may then open), as when a device left; the pause menu offers "Leave game" for the waiting
## seats of this machine (another machine's are its own to let go).
func _on_pad_wait_changed(seats: int) -> void:
	var here: int = 0
	for player in PLAYER_COUNT:
		if seats & (1 << player) == 0:
			continue
		if ui_focus != null:
			ui_focus.close(player)
		if input != null and input.is_waiting(player):
			here |= 1 << player
	_pause_menu.set_waiting_seats(here)


## The pad line (for tests and screenshots).
func get_pad_line() -> PadLineScript:
	return _pad_line


## The pause menu (for tests and screenshots).
func get_pause_menu() -> PauseMenuScript:
	return _pause_menu


## The radial builder of `player`, or null for a bad index.
func get_radial(player: int) -> RadialScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _radials[player]


## The pause menu's builder switches: the radial's ring and what a full slot does.
func _on_builder_options_changed(ring: PauseMenuScript.Ring, push: bool) -> void:
	for builder in _radials:
		builder.layout = RadialScript.Layout.KIND if ring == PauseMenuScript.Ring.ONE_KIND else RadialScript.Layout.ALL
		builder.put = RadialScript.Put.PUSH if push else RadialScript.Put.REPLACE
		# Each radial its own style object: they keep per-player state.
		match ring:
			PauseMenuScript.Ring.ZOOM:
				builder.ring_picker = RingZoomScript.new()
			PauseMenuScript.Ring.KINDS_HOLD:
				builder.ring_picker = RingKindsScript.new(RingKindsScript.Enter.HOLD)
			PauseMenuScript.Ring.KINDS_DEPTH:
				builder.ring_picker = RingKindsScript.new(RingKindsScript.Enter.DEPTH)
			_:
				builder.ring_picker = null


## The pause menu's reload switch: every panel's staff rows show the delay on the button glyph,
## or on the next cast.
func _on_reload_style_changed(on_button: bool) -> void:
	var style: StaffRowScript.Style = StaffRowScript.Style.BUTTON if on_button else StaffRowScript.Style.NEXT_CAST
	for panel in _panels:
		panel.set_reload_style(style)


func _on_show_fps_changed(on: bool) -> void:
	_fps.visible = on
	if on:
		_fps.refresh()


## The frame rate readout (for tests and screenshots).
func get_fps_counter() -> FpsCounterScript:
	return _fps


## The red vignette (for tests).
func get_vignette() -> VignetteScript:
	return _vignette


## The panel of `player`, or null for a bad index.
func get_panel(player: int) -> PlayerPanelScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _panels[player]


## A corner panel shows while its player is in a room, except while their radial builder is open:
## the radial shows the bars itself, so its column can sit where the panel was (owner,
## 2026-10-31, docs/milestones/M2-builder-tree.md). The radial is shown before its menu opens and
## hidden before it closes, so `visible` is already right when UIFocus says so.
func _refresh(player: int) -> void:
	_panels[player].visible = _in_room and _joined[player] and not _radials[player].visible


func _on_player_joined(player: int) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_joined[player] = true
	_refresh(player)


func _on_player_left(player: int) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_joined[player] = false
	_panels[player].reset()
	_panels[player].clear_staffs()
	_refresh(player)


## The hub's stone lit or out: while lit, a seat's `accept` with no menu open starts the run.
func _on_start_stone_changed(_standing: int, _wizards: int, lit: bool) -> void:
	_stone_lit = lit


func _on_room_entered(_room_id: StringName) -> void:
	_in_room = true
	_wave_label.visible = false  # stop_run sends no event; Flow sends wave_started right after
	for player in PLAYER_COUNT:
		_refresh(player)


func _on_wave_started(wave: int) -> void:
	_wave_label.text = "Wave %d" % wave
	_wave_label.visible = true
	_break_row.visible = false
	_wave_active = true


## The build break began: the hammer and a countdown of `seconds` show until the next wave.
func _on_build_break_started(seconds: float) -> void:
	_break_left = maxf(seconds, 0.0)
	_show_break_seconds()
	_break_row.visible = true


## The build break line (hammer and countdown), or null before `_ready`.
func get_break_row() -> PanelContainer:
	return _break_row


## The countdown text of the build break line.
func get_break_label() -> Label:
	return _break_label


## The wave is cleared: the wave line goes (it shows only while a wave is on; nothing sends
## `run_ended` yet).
func _on_room_cleared(_room_id: StringName) -> void:
	_wave_active = false
	_wave_label.visible = false


## Whether a wave is in progress (for tests).
func is_wave_active() -> bool:
	return _wave_active


## A staff was built or changed: its row shows the plan's cast sequence, with each card's icon
## asked of `Spells` once here (never per frame).
func _on_staff_changed(player: int, staff: int, plan: Dictionary) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	var icons: Array[Texture2D] = []
	for id: Variant in plan.get("cards", []):
		var card: StringName = StringName(id)
		icons.append(spells.component_icon(card) if spells != null and card != &"" else null)
	_panels[player].set_staff_plan(staff, plan, icons)


## Each shown panel's staff rows get their staff's next cast and delay left from `Spells`
## (plain numbers; nothing allocated). Called every frame by _process; tests call it directly.
func step_staffs() -> void:
	if spells == null:
		return
	for player in PLAYER_COUNT:
		var panel: PlayerPanelScript = _panels[player]
		if not panel.visible:
			continue
		# Spells keeps staffs by caster (actors G3b): the seat's own wizard, also while the seat
		# drives another actor.
		var actor: int = spells.home_of_seat(player)
		for staff in PlayerPanelScript.STAFF_COUNT:
			# The cast a press would fire with the staff's mana (one it cannot pay is skipped;
			# docs/milestones/cast-timing.md); unknown until the staff's mana was told.
			var mana: float = _staff_mana[player * PlayerPanelScript.STAFF_COUNT + staff]
			var firing: int = StaffRowScript.FIRING_UNKNOWN
			if is_finite(mana):
				firing = spells.firing_cast(actor, staff, maxf(mana - _staff_reserved[player * PlayerPanelScript.STAFF_COUNT + staff], 0.0))
			panel.set_staff_timing(staff, spells.cast_index(actor, staff), spells.cooldown_left(actor, staff), spells.is_winding(actor, staff), firing)


## The "Wave N" line, or null before the script's `_ready`.
func get_wave_label() -> Label:
	return _wave_label


## A new run starts with no room entered yet: panels wait for `room_entered`.
func _on_run_started(_player_count: int) -> void:
	_reset_all()
	_staff_mana.fill(INF)
	_staff_reserved.fill(0.0)


## A run is over: no panels over the menu, and the next run starts clean (its wizards announce
## their staffs again when they appear).
func _on_run_ended(_victory: bool) -> void:
	_reset_all()
	_item_hints.clear()
	for panel in _panels:
		panel.clear_staffs()


## This machine goes back to the main menu (`main_menu_requested`): no panel or menu stays, and
## the main menu becomes the current scene again (Flow takes the run's world away itself). Nothing
## here asks Flow or net/: each does its own part of leaving.
func _on_main_menu_requested(_player: int) -> void:
	_on_run_ended(false)
	# The run's stops went with it (Flow); a seat still waiting says so again in the next room.
	_pad_line.show_seats(0)
	_pause_menu.set_waiting_seats(0)
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var scene: PackedScene = main_menu
	if scene == null:
		scene = load("res://hud/menus/main_menu/main_menu.tscn") as PackedScene
	var menu: Node = scene.instantiate() if scene != null else null
	if menu == null:
		push_warning("Hud: the main menu could not be made.")
		return
	tree.root.add_child(menu)
	tree.current_scene = menu


func _reset_all() -> void:
	_in_room = false
	_wave_active = false
	_wave_label.visible = false
	_break_row.visible = false
	_vignette.clear()
	_pause_menu.close_menu()
	for player in PLAYER_COUNT:
		_radials[player].close_builder()
		_panels[player].reset()
		_refresh(player)


func _on_stats_changed(player: int, health: float, max_health: float, mana: float, max_mana: float) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		var before: float = _panels[player].health()
		_panels[player].set_stats(health, max_health, mana, max_mana)
		if _in_room and before >= 0.0 and health < before:
			_vignette.flash_hit(player, (before - health) / maxf(max_health, 1.0), _joined.count(true))
		if health <= 0.0:
			_radials[player].close_builder()


func _on_menu_opened(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(true)
		_refresh(player)


func _on_menu_closed(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(false)
		_refresh(player)


## A seat's staff's mana changed (the player sends whole numbers).
func _on_staff_mana_changed(player: int, staff: int, mana: float, _max_mana: float) -> void:
	if player >= 0 and player < PLAYER_COUNT and staff >= 0 and staff < PlayerPanelScript.STAFF_COUNT:
		_staff_mana[player * PlayerPanelScript.STAFF_COUNT + staff] = mana


## What a seat's staff's sustained cards hold of its mana.
func _on_mana_reserved(player: int, staff: int, amount: float) -> void:
	if player >= 0 and player < PLAYER_COUNT and staff >= 0 and staff < PlayerPanelScript.STAFF_COUNT:
		_staff_reserved[player * PlayerPanelScript.STAFF_COUNT + staff] = amount


## A press found no cast its mana pays (docs/milestones/cast-timing.md): the seat whose own wizard
## it was shows it on that staff's row.
func _on_cast_fizzled(caster: int, staff: int) -> void:
	if spells == null:
		return
	for player in PLAYER_COUNT:
		if spells.home_of_seat(player) == caster:
			_panels[player].staff_fizzled(staff)

