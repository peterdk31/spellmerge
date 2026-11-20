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
## when neither is in reach. A seat whose body stands at an unvisited room's doorway it may reroll
## (`room_reroll_shown`, the owner's of 2026-11-19) is shown X "Reroll room" there, when nothing
## above is shown; `reroll_of(player)` is true while it shows (the panels send
## `room_reroll_requested` on X), and a refused reroll (`room_reroll_refused`) shakes it with why.
## A shop's reroll sign in reach comes as a shop item (its view's kind `SHELF_SIGN`): "Reroll shelf"
## and its price, A buying the reroll. A seat's own reward item in reach (`reward_near_changed`, the
## owner's of 2026-11-19) is shown "Open reward" when no ground or shop item is; `reward_of(player)`
## is the offer A opens (the panels open its reward menu).
## Display only: it reads no input.

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
## By player: its own reward item in reach (its offer, -1: none) and where it lies.
var _reward: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _reward_at: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## By player: true while its body is at a shut key door with no key, and the door's mouth.
var _needs_key: Array[bool] = [false, false, false, false]
var _door_at: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## By player: true while its body is at a doorway it may reroll, the mouth's middle, and the words
## shown there (REROLL_ROOM, or why a reroll was refused).
var _reroll: Array[bool] = [false, false, false, false]
var _reroll_at: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## By player: X sent and not yet answered (no second request: a double press spends one).
var _reroll_pending: Array[bool] = [false, false, false, false]
var _reroll_words: Array[String] = [ItemHintScript.REROLL_ROOM, ItemHintScript.REROLL_ROOM, ItemHintScript.REROLL_ROOM, ItemHintScript.REROLL_ROOM]


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
		events.reward_near_changed.connect(_on_reward_near_changed)
		events.key_needed_shown.connect(_on_key_needed_shown)
		events.room_reroll_shown.connect(_on_room_reroll_shown)
		events.room_reroll_refused.connect(_on_room_reroll_refused)


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


## The reward offer whose item `player`'s A opens now (shown, no ground or shop item in reach and no
## menu open), -1 for none.
func reward_of(player: int) -> int:
	if player < 0 or player >= PLAYER_COUNT or not _hints[player].visible or _ground[player] >= 0 or _shelf[player] >= 0 or _reward[player] < 0:
		return -1
	return _reward[player]


## True while `player`'s hint shows X "Reroll room" at a doorway (shown, nothing else shown there
## and no menu open): X sends `room_reroll_requested`.
func reroll_of(player: int) -> bool:
	if player < 0 or player >= PLAYER_COUNT or not _hints[player].visible:
		return false
	return _reroll[player] and not _reroll_pending[player] and _ground[player] < 0 and _shelf[player] < 0 and _reward[player] < 0 and not _needs_key[player]


## `player`'s X asked for a reroll: no other until it is answered (`room_reroll_shown`, refused).
func reroll_asked(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_reroll_pending[player] = true


## Player `player`'s hint (for tests).
func hint_of(player: int) -> ItemHintScript:
	return _hints[player]


## Every hint hidden (a run ended).
func clear() -> void:
	for player in PLAYER_COUNT:
		_ground[player] = -1
		_shelf[player] = -1
		_reward[player] = -1
		_needs_key[player] = false
		_reroll[player] = false
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
		hint.visible = (hint.item() >= 0 or hint.is_note()) and not menus[player]
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


func _on_reward_near_changed(player: int, offer: int, at: Vector2) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_reward[player] = offer
	_reward_at[player] = at
	if _ground[player] < 0 and _shelf[player] < 0:
		_show(player)


func _on_key_needed_shown(player: int, at: Vector2, needed: bool) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_needs_key[player] = needed
	_door_at[player] = at
	if _ground[player] < 0 and _shelf[player] < 0 and _reward[player] < 0:
		_show(player)


func _on_room_reroll_shown(player: int, at: Vector2, shown: bool) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_reroll[player] = shown
	_reroll_at[player] = at
	_reroll_pending[player] = false
	_reroll_words[player] = ItemHintScript.REROLL_ROOM
	if _ground[player] < 0 and _shelf[player] < 0 and _reward[player] < 0 and not _needs_key[player]:
		_show(player)


func _on_room_reroll_refused(player: int, reason: StringName) -> void:
	if player < 0 or player >= PLAYER_COUNT or not _reroll[player]:
		return
	_reroll_pending[player] = false
	match reason:
		&"none_held":
			_reroll_words[player] = ItemHintScript.NO_ROOM_REROLLS
		&"occupied":
			_reroll_words[player] = ItemHintScript.SOMEONE_INSIDE
		_:
			_reroll_words[player] = ItemHintScript.NOTHING_FITS
	if _ground[player] < 0 and _shelf[player] < 0 and _reward[player] < 0 and not _needs_key[player]:
		_show(player)
		_hints[player].refuse(ItemHintScript.NOTE)


## Player `player`'s hint shows its ground item in reach, else its shop item (or reroll sign), else
## its own reward item, else a shut key door's "Needs a key", else X "Reroll room" at a doorway it
## may reroll, else nothing.
func _show(player: int) -> void:
	if _ground[player] >= 0:
		_at[player] = _ground_at[player]
		_hints[player].show_item(player, _ground[player], _ground_view[player])
	elif _shelf[player] >= 0:
		_at[player] = _shelf_at[player]
		var is_sign: bool = _shelf_view[player].get("kind", &"") == EventsScript.SHELF_SIGN
		_hints[player].show_item(player, _shelf[player], _shelf_view[player], "" if is_sign else ItemHintScript.BUY)
	elif _reward[player] >= 0:
		_at[player] = _reward_at[player]
		_hints[player].show_item(player, _reward[player], {"name": ItemHintScript.REWARD_NAME}, ItemHintScript.OPEN)
	elif _needs_key[player]:
		_at[player] = _door_at[player]
		_hints[player].show_note(player, ItemHintScript.NEEDS_KEY)
	elif _reroll[player]:
		_at[player] = _reroll_at[player]
		_hints[player].show_note(player, _reroll_words[player], ItemHintScript.REROLL_ACTION)
	else:
		_hints[player].show_item(player, -1, {})


func _on_item_refused(player: int, item: int) -> void:
	if player >= 0 and player < PLAYER_COUNT and _ground[player] >= 0:
		_hints[player].refuse(item)


func _on_shelf_refused(player: int, item: int) -> void:
	if player >= 0 and player < PLAYER_COUNT and _ground[player] < 0 and _shelf[player] >= 0:
		_hints[player].refuse(item)
