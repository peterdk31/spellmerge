extends Control
## Every player's item hint (items I6; one `hud/widgets/item_hint.gd` a player, node Root/ItemHints,
## made by `panels.gd`): it hears which item is in reach of each player's driven body
## (`item_near_changed`) and a refused take (`item_refused`), and each frame puts each hint over its
## item as the camera shows it now, those of players sharing an item stacked. A player's hint hides
## while that player has a menu open (`step`'s `menus`). `item_of(player)` is the item A would take
## (the panels send `item_take_requested`). A shop's item in reach (`shelf_near_changed`, connected
## biomes CB11's follow-up) is shown the same way, "Buy" and its price, when no ground item is in
## reach; `shelf_of(player)` is the one A would buy (`shelf_buy_requested`), and a refused buy
## (`shelf_refused`) shakes it. A seat whose body stands at a shut key door with no key of its own
## (`key_needed_shown`, the owner's of 2026-11-19) is shown "Needs a key" over the door, words alone,
## when neither is in reach. Display only: it reads no input.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ItemHintScript := preload("res://hud/widgets/item_hint.gd")

const PLAYER_COUNT: int = 4

var _hints: Array[ItemHintScript] = []
## By player: where its shown item lies (room pixels).
var _at: PackedVector2Array = PackedVector2Array()
## By player: the ground item in reach and the shop item in reach (-1: none), each with its place and view.
var _ground: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _ground_at: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _ground_view: Array[Dictionary] = [{}, {}, {}, {}]
var _shelf: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _shelf_at: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _shelf_view: Array[Dictionary] = [{}, {}, {}, {}]
## By player: true while its body is at a shut key door with no key, and the door's mouth.
var _needs_key: Array[bool] = [false, false, false, false]
var _door_at: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


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
		events.shelf_near_changed.connect(_on_shelf_near_changed)
		events.shelf_refused.connect(_on_shelf_refused)
		events.key_needed_shown.connect(_on_key_needed_shown)


## The item `player`'s A takes now (shown, and no menu of theirs open), -1 for none.
func item_of(player: int) -> int:
	if player < 0 or player >= PLAYER_COUNT or not _hints[player].visible or _ground[player] < 0:
		return -1
	return _hints[player].item()


## The shop item `player`'s A buys now (shown, no ground item in reach and no menu open), -1 for none.
func shelf_of(player: int) -> int:
	if player < 0 or player >= PLAYER_COUNT or not _hints[player].visible or _ground[player] >= 0 or _shelf[player] < 0:
		return -1
	return _hints[player].item()


## Player `player`'s hint (for tests).
func hint_of(player: int) -> ItemHintScript:
	return _hints[player]


## Every hint hidden (a run ended).
func clear() -> void:
	for player in PLAYER_COUNT:
		_ground[player] = -1
		_shelf[player] = -1
		_needs_key[player] = false
		_hints[player].show_item(player, -1, {})


## A frame: `menus` holds, by player, whether they have a menu open; `to_screen` turns room pixels
## into this layer's (the camera now). While the screen is split (`views`, connected biomes CB6)
## each player's hint is put where that player's own view shows the item instead (another
## machine's player's, where any view shows it) (`layer` turns the
## screen's pixels into this layer's), and hides while the item is outside that view's cell. Real
## time for the shakes.
func step(delta: float, menus: Array[bool], to_screen: Transform2D, views: ScreenViews = null, layer: Transform2D = Transform2D.IDENTITY) -> void:
	var split: bool = views != null and views.is_split()
	for player in PLAYER_COUNT:
		var hint: ItemHintScript = _hints[player]
		hint.visible = hint.item() >= 0 and not menus[player]
		if not hint.visible:
			continue
		var place: Vector2 = to_screen * _at[player]
		if split:
			# The player's own view; a player of another machine's, the view that shows the item.
			var view: int = views.view_of_seat(player)
			if view < 0:
				view = views.view_showing(_at[player])
			var on_screen: Vector2 = views.to_screen[view] * _at[player] if view >= 0 else Vector2.INF
			hint.visible = view >= 0 and views.cell_holds(view, on_screen, 0.0)
			if not hint.visible:
				continue
			place = layer * on_screen
		var below: int = 0
		for other in player:
			if _hints[other].visible and _hints[other].item() == hint.item() and _at[other] == _at[player]:
				below += 1
		hint.place_over(place, below)
		hint.step(delta)


func _on_item_near_changed(player: int, item: int, at: Vector2, view: Dictionary) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_ground[player] = item if not view.is_empty() else -1
	_ground_at[player] = at
	_ground_view[player] = view
	_show(player)


func _on_shelf_near_changed(player: int, item: int, at: Vector2, view: Dictionary) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_shelf[player] = item if not view.is_empty() else -1
	_shelf_at[player] = at
	_shelf_view[player] = view
	if _ground[player] < 0:
		# A ground item shown stays as it is (its refused shake too).
		_show(player)


func _on_key_needed_shown(player: int, at: Vector2, needed: bool) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_needs_key[player] = needed
	_door_at[player] = at
	if _ground[player] < 0 and _shelf[player] < 0:
		_show(player)


## Player `player`'s hint shows its ground item in reach, else its shop item, else a shut key door's
## "Needs a key", else nothing.
func _show(player: int) -> void:
	if _ground[player] >= 0:
		_at[player] = _ground_at[player]
		_hints[player].show_item(player, _ground[player], _ground_view[player])
	elif _shelf[player] >= 0:
		_at[player] = _shelf_at[player]
		_hints[player].show_item(player, _shelf[player], _shelf_view[player], ItemHintScript.BUY)
	elif _needs_key[player]:
		_at[player] = _door_at[player]
		_hints[player].show_note(player, ItemHintScript.NEEDS_KEY)
	else:
		_hints[player].show_item(player, -1, {})


func _on_item_refused(player: int, item: int) -> void:
	if player >= 0 and player < PLAYER_COUNT and _ground[player] >= 0:
		_hints[player].refuse(item)


func _on_shelf_refused(player: int, item: int) -> void:
	if player >= 0 and player < PLAYER_COUNT and _ground[player] < 0:
		_hints[player].refuse(item)
