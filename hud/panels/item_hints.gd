extends Control
## Every player's item hint (items I6; one `hud/widgets/item_hint.gd` a player, node Root/ItemHints,
## made by `panels.gd`): it hears which item is in reach of each player's driven body
## (`item_near_changed`) and a refused take (`item_refused`), and each frame puts each hint over its
## item as the camera shows it now, those of players sharing an item stacked. A player's hint hides
## while that player has a menu open (`step`'s `menus`). `item_of(player)` is the item A would take
## (the panels send `item_take_requested`). Display only: it reads no input.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ItemHintScript := preload("res://hud/widgets/item_hint.gd")

const PLAYER_COUNT: int = 4

var _hints: Array[ItemHintScript] = []
## By player: where its item lies (room pixels).
var _at: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at.resize(PLAYER_COUNT)
	for player in PLAYER_COUNT:
		var hint := ItemHintScript.new()
		hint.name = "ItemHint%d" % (player + 1)
		add_child(hint)
		_hints.append(hint)


func bind(events: EventsScript, input: InputManagerScript, spells: SpellsScript) -> void:
	for hint in _hints:
		hint.bind(input, spells)
	if events != null:
		events.item_near_changed.connect(_on_item_near_changed)
		events.item_refused.connect(_on_item_refused)


## The item `player`'s A takes now (shown, and no menu of theirs open), -1 for none.
func item_of(player: int) -> int:
	if player < 0 or player >= PLAYER_COUNT or not _hints[player].visible:
		return -1
	return _hints[player].item()


## Player `player`'s hint (for tests).
func hint_of(player: int) -> ItemHintScript:
	return _hints[player]


## Every hint hidden (a run ended).
func clear() -> void:
	for player in PLAYER_COUNT:
		_hints[player].show_item(player, -1, {})


## A frame: `menus` holds, by player, whether they have a menu open; `to_screen` turns room pixels
## into this layer's (the camera now). Real time for the shakes.
func step(delta: float, menus: Array[bool], to_screen: Transform2D) -> void:
	for player in PLAYER_COUNT:
		var hint: ItemHintScript = _hints[player]
		hint.visible = hint.item() >= 0 and not menus[player]
		if not hint.visible:
			continue
		var below: int = 0
		for other in player:
			if _hints[other].visible and _hints[other].item() == hint.item():
				below += 1
		hint.place_over(to_screen * _at[player], below)
		hint.step(delta)


func _on_item_near_changed(player: int, item: int, at: Vector2, view: Dictionary) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_at[player] = at
	_hints[player].show_item(player, item, view)


func _on_item_refused(player: int, item: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_hints[player].refuse(item)
