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
## ever left open over the main menu.
##
## A red vignette (`vignette/`, node Root/Vignette, behind the panels) glows when a
## wizard's health falls, strongest toward that wizard's corner and fading in under
## half a second. It is read from `player_stats_changed` alone (a drop in health),
## never from a node, and it takes no input.
##
## The buttons that open menus are read here, from the press counters of `core/input` (a tap
## released within a frame is not lost); each menu then takes its input through
## `core/ui_focus` (owner, 2026-10-26):
## - `back` (B; Tab or E on the keyboard) opens that player's spell builder (`hud/builder/`,
##   nodes Root/Builder1 to Root/Builder4) when they have no menu open, are not down and the
##   game is not paused. It sits beside the corner panel toward the middle of the screen and
##   never pauses the game; it is the full builder at any time, waves included (staffs A6a).
##   Inside a menu `back` is that menu's own (UIFocus `cancelled`), so a press only opens the
##   builder when the player had no menu open at the poll before it too.
##   The pause menu's Sandbox page can swap it for the radial builder (`builder/radial_builder.gd`,
##   nodes Root/Radial1 to Root/Radial4, made here; owner, 2026-10-26): `back` then opens that one,
##   with the ring layout and full-slot choice from the same page (`builder_options_changed`).
## - `pause` (Start; Escape) closes the menu its player has open (the builder, or the pause menu
##   they opened); with none open it opens the pause menu (`hud/menus/pause/`, node
##   Root/PauseMenu), which stops the game for everyone and is worked by the player who opened
##   it. Another player's `pause` does nothing while it is open.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const PauseMenuScript := preload("res://hud/menus/pause/pause_menu.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const BuilderScript := preload("res://hud/builder/builder.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const PlayerPanelScript := preload("res://hud/panels/player_panel/player_panel.gd")
const VignetteScript := preload("res://hud/panels/vignette/vignette.gd")
const HammerIconScript := preload("res://hud/widgets/hammer_icon.gd")

const PLAYER_COUNT: int = 4
const PAUSE_ACTION: StringName = &"pause"
const BUILDER_ACTION: StringName = &"back"
## Space between the screen edge and a panel.
const EDGE_MARGIN: float = 4.0
## Space between a corner panel and its builder, which sits beside it.
const BUILDER_GAP: float = 2.0
## The "Wave N" line and the build break line (hammer and "Build 12") sit side by side in one
## strip in the middle of the view: the free gap between the top builders and the bottom ones.
## The builders fill the width between the info panels, so the top middle is taken once four
## are open.
const WAVE_LABEL_WIDTH: float = 80.0
const WAVE_LABEL_FONT_SIZE: int = 12
const WAVE_LABEL_OUTLINE: int = 3
const BREAK_FONT_SIZE: int = 12
const STRIP_SEPARATION: int = 6

## The event bus, the UI focus service, the input manager and the spell runtime (the
## builders ask it for names and icons). Only tests set these, before adding the
## node; otherwise the "Events", "UIFocus", "PlayerInput" and "Spells" autoloads.
var events: EventsScript = null
var ui_focus: UIFocusScript = null
var input: InputManagerScript = null
var spells: SpellsScript = null

var _panels: Array[PlayerPanelScript] = []
var _builders: Array[BuilderScript] = []
var _radials: Array[RadialScript] = []
## `back` opens the radial builders instead of the list ones (the pause menu's Sandbox page).
var _use_radial: bool = false
var _pause_menu: PauseMenuScript = null
## Per player: the `pause` and `back` press counts at the last poll, and whether a menu of
## theirs was open then.
var _seen_pause: Array[int] = [0, 0, 0, 0]
var _seen_back: Array[int] = [0, 0, 0, 0]
var _had_menu: Array[bool] = [false, false, false, false]
## A wave is in progress (the wave line shows).
var _wave_active: bool = false
var _joined: Array[bool] = [false, false, false, false]
var _in_room: bool = false
var _vignette: VignetteScript = null
## The strip in the middle of the view that holds the wave line and the break line.
var _strip: HBoxContainer = null
var _wave_label: Label = null
## The build break line: a row (hidden outside a break) with the hammer and the countdown.
var _break_row: PanelContainer = null
var _break_label: Label = null
## Seconds of the break left; counted down here from `build_break_started`, display only.
var _break_left: float = 0.0


func _ready() -> void:
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
		_builders.append(get_node("Root/Builder%d" % (player + 1)) as BuilderScript)
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
	for player in PLAYER_COUNT:
		_panels[player].minimum_size_changed.connect(_place_builder.bind(player))
		_place_builder(player)
	if input != null:
		for player in PLAYER_COUNT:
			_seen_pause[player] = input.get_press_count(player, PAUSE_ACTION)
			_seen_back[player] = input.get_press_count(player, BUILDER_ACTION)
	_pause_menu.bind(events, ui_focus)
	for builder in _builders:
		builder.bind(events, ui_focus, spells, input)
	for radial in _radials:
		radial.bind(events, ui_focus, spells, input)
	_pause_menu.builder_options_changed.connect(_on_builder_options_changed)
	if events != null:
		events.player_joined.connect(_on_player_joined)
		events.player_left.connect(_on_player_left)
		events.player_stats_changed.connect(_on_stats_changed)
		events.room_entered.connect(_on_room_entered)
		events.wave_started.connect(_on_wave_started)
		events.room_cleared.connect(_on_room_cleared)
		events.build_break_started.connect(_on_build_break_started)
		events.staff_cast.connect(_on_staff_cast)
		events.run_started.connect(_on_run_started)
		events.run_ended.connect(_on_run_ended)
	if ui_focus != null:
		ui_focus.opened.connect(_on_menu_opened)
		ui_focus.closed.connect(_on_menu_closed)


func _process(delta: float) -> void:
	poll()
	_vignette.step(delta)
	step_break(delta)


## Count the break line down by `delta` seconds. It only draws; Flow decides when the wave
## starts, so a drift here never moves the wave. Called every frame; tests call it directly.
func step_break(delta: float) -> void:
	if not _break_row.visible:
		return
	_break_left = maxf(_break_left - delta, 0.0)
	_show_break_seconds()


func _show_break_seconds() -> void:
	_break_label.text = "Build %d" % ceili(_break_left)


## Read every joined player's `pause` and `back` presses since the last poll (several presses in
## one frame count once) and open or close menus as the top of this file says. Presses outside a
## room are dropped. Called every frame by _process; tests call it directly. One player's press
## never touches another player's menus.
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
		var had_menu: bool = _had_menu[player]
		if input.is_joined(player):
			if paused_now:
				_on_pause_pressed(player)
			elif back_now and not had_menu and not _has_menu(player) and _in_room \
					and not _pause_menu.is_open() and not _panels[player].is_downed():
				if _use_radial:
					_radials[player].open_builder()
				else:
					_builders[player].open_builder()
		_had_menu[player] = _has_menu(player)


## Whether `player` has a menu open: their builder, or the pause menu they work.
func _has_menu(player: int) -> bool:
	return _builders[player].is_open() or _radials[player].is_open() or _pause_menu.owner_player == player


## `pause`: close the player's open menu, or open the pause menu for them.
func _on_pause_pressed(player: int) -> void:
	if _builders[player].is_open():
		_builders[player].close_builder()
	elif _radials[player].is_open():
		_radials[player].close_builder()
	elif _pause_menu.is_open():
		if _pause_menu.owner_player == player:
			_pause_menu.close_menu()
	elif _in_room:
		_pause_menu.open_menu(player)


## The pause menu (for tests and screenshots).
func get_pause_menu() -> PauseMenuScript:
	return _pause_menu


## The spell builder of `player`, or null for a bad index.
func get_builder(player: int) -> BuilderScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _builders[player]


## The radial builder of `player`, or null for a bad index.
func get_radial(player: int) -> RadialScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _radials[player]


## Whether `back` opens the radial builders.
func uses_radial() -> bool:
	return _use_radial


## The pause menu's builder switches: which builder `back` opens, and the radial's options.
func _on_builder_options_changed(radial: bool, ring_by_kind: bool, push: bool) -> void:
	_use_radial = radial
	for builder in _radials:
		builder.layout = RadialScript.Layout.KIND if ring_by_kind else RadialScript.Layout.ALL
		builder.put = RadialScript.Put.PUSH if push else RadialScript.Put.REPLACE


## The red vignette (for tests).
func get_vignette() -> VignetteScript:
	return _vignette


## The panel of `player`, or null for a bad index.
func get_panel(player: int) -> PlayerPanelScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _panels[player]


## Put the builder of `player` beside that player's panel, toward the middle of the
## screen (right of the left panels, left of the right ones), from the panel's width.
func _place_builder(player: int) -> void:
	var offset: float = EDGE_MARGIN + _panels[player].get_combined_minimum_size().x + BUILDER_GAP
	var x: float = offset if player % 2 == 0 else -offset
	_builders[player].offset_left = x
	_builders[player].offset_right = x


func _refresh(player: int) -> void:
	_panels[player].visible = _in_room and _joined[player]


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
	_refresh(player)


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


func _on_staff_cast(player: int, staff: int, _origin: Vector2, _direction: Vector2) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_active_staff(staff)


## The "Wave N" line, or null before the script's `_ready`.
func get_wave_label() -> Label:
	return _wave_label


## A new run starts with no room entered yet: panels wait for `room_entered`.
func _on_run_started(_player_count: int) -> void:
	_reset_all()


## A run is over: no panels over the menu, and the next run starts clean.
func _on_run_ended(_victory: bool) -> void:
	_reset_all()


func _reset_all() -> void:
	_in_room = false
	_wave_active = false
	_wave_label.visible = false
	_break_row.visible = false
	_vignette.clear()
	_pause_menu.close_menu()
	for player in PLAYER_COUNT:
		_builders[player].close_builder()
		_radials[player].close_builder()
		_panels[player].reset()
		_refresh(player)


func _on_stats_changed(player: int, health: int, max_health: int, mana: float, max_mana: float) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		var before: int = _panels[player].health()
		_panels[player].set_stats(health, max_health, mana, max_mana)
		if _in_room and before >= 0 and health < before:
			_vignette.flash_hit(player, float(before - health) / float(maxi(max_health, 1)), _joined.count(true))
		if health <= 0:
			_builders[player].close_builder()
			_radials[player].close_builder()


func _on_menu_opened(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(true)


func _on_menu_closed(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(false)
