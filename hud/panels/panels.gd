extends CanvasLayer
## The corner panels of all players: the autoload "Hud". P1 is top left, P2 top
## right, P3 bottom left and P4 bottom right (nodes Root/Panel1 to Root/Panel4).
##
## A panel is shown for a joined player once a room has been entered, and hidden
## when the player leaves. A run starting or ending hides all panels and clears
## their numbers, so none stays over the menu. Numbers come only from `player_stats_changed`; the
## "MENU" word follows `UIFocus.opened` and `closed` for that player. Nothing is
## polled and nothing here takes input, so a player in their overlay never makes
## another panel wait.
##
## An overlay opens only while a room is active and its owner is not down, and
## it closes when the run starts or ends or when its owner goes down, so none is
## ever left open over the menu. Each overlay sits just under (P1, P2) or over
## (P3, P4) its own corner panel, placed from that panel's height.
##
## A red vignette (`vignette/`, node Root/Vignette, behind the panels) glows when a
## wizard's health falls, strongest toward that wizard's corner and fading in under
## half a second. It is read from `player_stats_changed` alone (a drop in health),
## never from a node, and it takes no input.
##
## The overlays (`overlay/`, nodes Root/Overlay1 to Root/Overlay4) open and close
## with the owner's `overlay` action. The toggle is read here, from the press
## counter of `core/input` (a tap released within a frame is not lost); each
## overlay then takes its input through `core/ui_focus`. Nothing is paused. The
## overlay's "Build" opens that player's spell builder (`hud/builder/`, nodes
## Root/Builder1 to Root/Builder4), which sits beside the corner panel toward the
## middle of the screen and takes the player's focus over from the overlay; the
## `overlay` action closes an open builder. The only event the HUD sends from here
## is `build_change_requested`, by a builder.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const OverlayScript := preload("res://hud/panels/overlay/overlay.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const BuilderScript := preload("res://hud/builder/builder.gd")
const PlayerPanelScript := preload("res://hud/panels/player_panel/player_panel.gd")
const VignetteScript := preload("res://hud/panels/vignette/vignette.gd")
const HammerIconScript := preload("res://hud/widgets/hammer_icon.gd")

const PLAYER_COUNT: int = 4
const OVERLAY_ACTION: StringName = &"overlay"
const SWAP_ACTION: StringName = &"swap"
## Swap presses turned into requests in one poll at most (a stuck button never floods the bus).
const MAX_SWAPS_PER_POLL: int = 2
## Space between the screen edge and a panel, and between a panel and its overlay.
const EDGE_MARGIN: float = 4.0
const OVERLAY_GAP: float = 2.0
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
var _overlays: Array[OverlayScript] = []
var _builders: Array[BuilderScript] = []
## Per player: the `overlay` press count at the last poll.
var _seen_overlay: Array[int] = [0, 0, 0, 0]
## Per player: the `swap` press count at the last poll.
var _seen_swap: Array[int] = [0, 0, 0, 0]
## A wave is in progress: the builders show their quick view.
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
		_overlays.append(get_node("Root/Overlay%d" % (player + 1)) as OverlayScript)
		_builders.append(get_node("Root/Builder%d" % (player + 1)) as BuilderScript)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if ui_focus == null:
		ui_focus = get_node_or_null("/root/UIFocus") as UIFocusScript
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
	if spells == null:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	for player in PLAYER_COUNT:
		_panels[player].minimum_size_changed.connect(_place_overlay.bind(player))
		_panels[player].minimum_size_changed.connect(_place_builder.bind(player))
		_place_overlay(player)
		_place_builder(player)
	if input != null:
		for player in PLAYER_COUNT:
			_seen_overlay[player] = input.get_press_count(player, OVERLAY_ACTION)
			_seen_swap[player] = input.get_press_count(player, SWAP_ACTION)
	for overlay in _overlays:
		overlay.bind(events, ui_focus, spells)
		overlay.build_pressed.connect(_on_build_pressed)
	for builder in _builders:
		builder.bind(events, ui_focus, spells)
	if events != null:
		events.player_joined.connect(_on_player_joined)
		events.player_left.connect(_on_player_left)
		events.player_stats_changed.connect(_on_stats_changed)
		events.room_entered.connect(_on_room_entered)
		events.wave_started.connect(_on_wave_started)
		events.room_cleared.connect(_on_room_cleared)
		events.build_break_started.connect(_on_build_break_started)
		events.active_spell_changed.connect(_on_active_spell_changed)
		events.run_started.connect(_on_run_started)
		events.run_ended.connect(_on_run_ended)
	if ui_focus != null:
		ui_focus.opened.connect(_on_overlay_opened)
		ui_focus.closed.connect(_on_overlay_closed)


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


## Toggle the overlay of every joined player who pressed `overlay` since the
## last poll (several presses in one frame toggle once). Presses outside a room
## are dropped, and a downed player's overlay is not opened. Called every frame by
## _process; tests call it directly. One player's press never touches another.
func poll() -> void:
	if input == null:
		return
	for player in PLAYER_COUNT:
		_poll_swap(player)
		var count: int = input.get_press_count(player, OVERLAY_ACTION)
		var presses: int = count - _seen_overlay[player]
		_seen_overlay[player] = count
		if presses <= 0 or not input.is_joined(player):
			continue
		if _builders[player].is_open():
			_builders[player].close_builder()
		elif _overlays[player].is_open():
			_overlays[player].close_overlay()
		elif _in_room and not _panels[player].is_downed():
			_overlays[player].open_overlay()


## A `swap` press of `player` becomes `spell_swap_requested(player)`, the player's wizard
## decides. Not while the player works a menu (`swap` is captured there too), outside a room,
## for a player who is not joined or is down. Presses in those states are dropped, not kept.
func _poll_swap(player: int) -> void:
	var count: int = input.get_press_count(player, SWAP_ACTION)
	var presses: int = count - _seen_swap[player]
	_seen_swap[player] = count
	if presses <= 0 or events == null or not _in_room or not input.is_joined(player):
		return
	if _panels[player].is_downed() or (ui_focus != null and ui_focus.is_open(player)):
		return
	for _press in mini(presses, MAX_SWAPS_PER_POLL):
		events.spell_swap_requested.emit(player)


## The overlay of `player`, or null for a bad index.
func get_overlay(player: int) -> OverlayScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _overlays[player]


## The spell builder of `player`, or null for a bad index.
func get_builder(player: int) -> BuilderScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _builders[player]


## The red vignette (for tests).
func get_vignette() -> VignetteScript:
	return _vignette


## The panel of `player`, or null for a bad index.
func get_panel(player: int) -> PlayerPanelScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _panels[player]


## Put the overlay of `player` clear of that player's panel: under it in the top
## corners, over it in the bottom ones, from the panel's height, not a fixed number.
func _place_overlay(player: int) -> void:
	var offset: float = EDGE_MARGIN + _panels[player].get_combined_minimum_size().y + OVERLAY_GAP
	var y: float = offset if player < 2 else -offset
	_overlays[player].offset_top = y
	_overlays[player].offset_bottom = y


## Put the builder of `player` beside that player's panel, toward the middle of the
## screen (right of the left panels, left of the right ones), from the panel's width.
func _place_builder(player: int) -> void:
	var offset: float = EDGE_MARGIN + _panels[player].get_combined_minimum_size().x + BUILDER_GAP
	var x: float = offset if player % 2 == 0 else -offset
	_builders[player].offset_left = x
	_builders[player].offset_right = x


## The overlay's "Build" was activated: the builder takes the owner's focus over.
func _on_build_pressed(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_builders[player].open_builder()


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
	for player in PLAYER_COUNT:
		_refresh(player)


func _on_wave_started(wave: int) -> void:
	_wave_label.text = "Wave %d" % wave
	_wave_label.visible = true
	_break_row.visible = false
	_set_quick(true)


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


## The wave is cleared: the builders unfold into the full view for the break.
func _on_room_cleared(_room_id: StringName) -> void:
	_set_quick(false)


## Whether a wave is in progress, so the builders show their quick view (for tests).
func is_wave_active() -> bool:
	return _wave_active


func _set_quick(quick: bool) -> void:
	_wave_active = quick
	for builder in _builders:
		builder.set_quick(quick)


func _on_active_spell_changed(player: int, slot: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_active_spell(slot)


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
	_set_quick(false)
	_wave_label.visible = false
	_break_row.visible = false
	_vignette.clear()
	for player in PLAYER_COUNT:
		_overlays[player].close_overlay()
		_builders[player].close_builder()
		_panels[player].reset()
		_refresh(player)


func _on_stats_changed(player: int, health: int, max_health: int, mana: float, max_mana: float) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		var before: int = _panels[player].health()
		_panels[player].set_stats(health, max_health, mana, max_mana)
		if _in_room and before >= 0 and health < before:
			_vignette.flash_hit(player, float(before - health) / float(maxi(max_health, 1)), _joined.count(true))
		if health <= 0:
			_overlays[player].close_overlay()
			_builders[player].close_builder()


func _on_overlay_opened(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(true)


func _on_overlay_closed(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(false)
