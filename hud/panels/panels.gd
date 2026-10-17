extends CanvasLayer
## The corner panels of all players: the autoload "Hud". P1 is top left, P2 top
## right, P3 bottom left and P4 bottom right (nodes Root/Panel1 to Root/Panel4).
##
## A panel is shown for a joined player once a room has been entered, and hidden
## when the player leaves. A run starting or ending hides all panels and clears
## their numbers, so none stays over the menu. Numbers come only from `player_stats_changed`; the
## "MENU" word follows `UIFocus.opened` and `closed` for that player. Nothing is
## polled and nothing here takes input, so a player in their overlay never makes
## another panel wait. The HUD sends no events from here.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const PlayerPanelScript := preload("res://hud/panels/player_panel/player_panel.gd")

const PLAYER_COUNT: int = 4

## The event bus and the UI focus service. Only tests set these, before adding
## the node; otherwise the "Events" and "UIFocus" autoloads.
var events: EventsScript = null
var ui_focus: UIFocusScript = null

var _panels: Array[PlayerPanelScript] = []
var _joined: Array[bool] = [false, false, false, false]
var _in_room: bool = false


func _ready() -> void:
	for player in PLAYER_COUNT:
		var panel := get_node("Root/Panel%d" % (player + 1)) as PlayerPanelScript
		panel.visible = false
		_panels.append(panel)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if ui_focus == null:
		ui_focus = get_node_or_null("/root/UIFocus") as UIFocusScript
	if events != null:
		events.player_joined.connect(_on_player_joined)
		events.player_left.connect(_on_player_left)
		events.player_stats_changed.connect(_on_stats_changed)
		events.room_entered.connect(_on_room_entered)
		events.run_started.connect(_on_run_started)
		events.run_ended.connect(_on_run_ended)
	if ui_focus != null:
		ui_focus.opened.connect(_on_overlay_opened)
		ui_focus.closed.connect(_on_overlay_closed)


## The panel of `player`, or null for a bad index.
func get_panel(player: int) -> PlayerPanelScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _panels[player]


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


## A new run starts with no room entered yet: panels wait for `room_entered`.
func _on_run_started(_player_count: int) -> void:
	_reset_all()


## A run is over: no panels over the menu, and the next run starts clean.
func _on_run_ended(_victory: bool) -> void:
	_reset_all()


func _reset_all() -> void:
	_in_room = false
	for player in PLAYER_COUNT:
		_panels[player].reset()
		_refresh(player)


func _on_stats_changed(player: int, health: int, max_health: int, mana: float, max_mana: float) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_stats(health, max_health, mana, max_mana)


func _on_overlay_opened(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(true)


func _on_overlay_closed(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(false)
