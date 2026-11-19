extends Control
## A seat's reward menu (connected biomes CB10, decisions 16 and 17; DESIGN rules 3 and 4; the cards
## by the owner's redesign of 2026-11-19): the oldest of the seat's offers not yet picked
## (`rewards_waiting_changed`), "Pick 1 of 2" over a row of cards, one a choice (`reward_card.gd`:
## its icon, its name and what it does, as the Rewards area's view says), side by side as
## `reward_layout.gd` lays them out in the room it is given (`room`: its seat's quarter of the view
## while several play, the whole view for one), so 1 to 4 or more choices stay readable in a quarter
## of the screen (past what fits, the row scrolls). Left and right (and up and down) move the focus
## along the row, wrapping round (UIFocus); `accept` on a card sends the command
## `reward_pick_requested(seat, offer, choice)` and closes it; `back` closes it with nothing sent,
## the offer left unspent. `hud/panels/panels.gd` opens it for its seat (nodes Root/Reward1 to
## Root/Reward4): by itself as an offer is rolled for a seat whose wizard was in the room
## (`reward_rolled`'s `here`: `wants_open`), and on the seat's A with no menu open and nothing else
## for A while it has one waiting (the unspent icon on its corner panel says so). It is that seat's
## alone and pauses nothing (pillar 2). It closes by itself when the offer it shows is gone. A pick
## the Rewards area refuses (`reward_refused`: no room in the bag, a heal while down) opens it again
## on that offer, its title saying so. Display and intent only: what a pick gives is the Rewards
## area's, told back by `rewards_waiting_changed`. **X** (`alternate`) on it sends the command
## `reward_reroll_requested(seat, offer)` (a reward reroll spent, the owner's of 2026-11-19); the
## new choices (`reward_rerolled`) are turned over onto its cards, and a refusal
## (`reward_reroll_refused`: none held) shows in its title (NO_REROLL_TEXT), nothing else changing.
##
## Smooth (docs/STYLE.md): it unrolls from its top over OPEN_FRAMES frames as it opens and rolls up
## as it closes; the focused card stands up LIFT pixels, one a frame (the one left sinks back alike),
## the gold rim slides from card to card over MOVE_FRAMES frames and a scrolled row slides along;
## everything by whole pixels, one step a drawn frame (`step`, called by `panels.gd` each frame).
## A reroll rolls it up over OPEN_FRAMES frames, turns the cards over to the new
## choices there and unrolls it again, never in one jump (a reroll of another count of choices closes
## it and opens it again on the new ones).

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const LayoutScript := preload("res://hud/menus/reward/reward_layout.gd")
const CardScript := preload("res://hud/menus/reward/reward_card.gd")

const TITLE_TEXT: String = "Pick 1 of %d"
## Its title after a pick was refused (`reward_refused`: a full bag, a heal while down).
const REFUSED_TEXT: String = "Can't take that now"
## Its title after X with no reward reroll held (`reward_reroll_refused`).
const NO_REROLL_TEXT: String = "No reward rerolls"
const FONT_SIZE: int = CardScript.FONT_SIZE
## The title's line, under the menu's top edge.
const TITLE_HEIGHT: float = 12.0
## Frames to unroll (or roll up), to slide the rim to the next card, and to slide the row.
const OPEN_FRAMES: int = 4
const MOVE_FRAMES: int = 4
const SCROLL_FRAMES: int = 4

const OUTLINE: Color = Color("#14121f")
const BACK: Color = Color("#2b2840")
const GOLD: Color = Color("#f2c230")
const ARROW: Color = Color("#d4d0e0")
const PLAYER_COLORS: Array[Color] = [Color("#3b73c9"), Color("#d9477a"), Color("#3f8f4f"), Color("#8a4fc4")]
const PLAYER_LIGHTS: Array[Color] = [Color("#7fc0f0"), Color("#f59ab8"), Color("#8fd46a"), Color("#c99af0")]

## The seat it belongs to (0-3), set before it enters the tree.
var index: int = 0
## The room it lays its cards out in and is centred on (view pixels; `panels.gd` sets it before
## opening it). With no area, the viewport's.
var room: Rect2 = Rect2()

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _layout: LayoutScript = LayoutScript.new()
## Clips the row to the cards in view; the row holds the cards and slides inside it.
var _strip: Control = null
var _row: Control = null
var _cursor: Control = null
var _cards: Array[CardScript] = []
var _title: String = ""
var _focused: int = -1
var _open: bool = false
## The seat's offers waiting, oldest first (`rewards_waiting_changed`), and the one shown (-1: none).
var _offers: Array[Dictionary] = []
var _shown: int = -1
## An offer was rolled while the seat's wizard was there: the panels open it when they may.
var _wants_open: bool = false
## The offer whose pick was refused, shown with REFUSED_TEXT the next time it opens (-1: none).
var _refused: int = -1
## The new choices of the offer shown, rerolled and not yet turned over onto the cards (empty: none).
var _rerolled: Array[Dictionary] = []
## Rolled up for a reroll: it unrolls again once the cards are turned over.
var _rerolling: bool = false
## X sent and not yet answered (`reward_rerolled` or `reward_reroll_refused`): A and X wait, so a
## pick never takes a choice not yet shown and a double press never spends two.
var _reroll_pending: bool = false
## Its whole height, and how far it has unrolled: 0 (rolled up) to OPEN_FRAMES.
var _full_height: float = 0.0
var _unrolled: int = 0
## The rim's slide: from, to and the frames taken of MOVE_FRAMES.
var _rim_from: Rect2 = Rect2()
var _rim_to: Rect2 = Rect2()
var _rim_frame: int = MOVE_FRAMES
## The row's slide (its x in the strip): from, to and the frames taken of SCROLL_FRAMES.
var _first: int = 0
var _row_from: float = 0.0
var _row_to: float = 0.0
var _row_frame: int = SCROLL_FRAMES


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visible = false
	_strip = Control.new()
	_strip.name = "Strip"
	_strip.clip_contents = true
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_row = Control.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_row)
	_cursor = Control.new()
	_cursor.name = "Rim"
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.draw.connect(_draw_rim)
	_row.add_child(_cursor)


## Connect to the event bus and the focus service (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript) -> void:
	_events = events
	_ui_focus = ui_focus
	if _events != null:
		_events.rewards_waiting_changed.connect(_on_rewards_waiting_changed)
		_events.reward_rolled.connect(_on_reward_rolled)
		_events.reward_refused.connect(_on_reward_refused)
		_events.reward_rerolled.connect(_on_reward_rerolled)
		_events.reward_reroll_refused.connect(_on_reward_reroll_refused)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.focus_changed.connect(_on_focus_changed)
		_ui_focus.alternate.connect(_on_alternate)


func is_open() -> bool:
	return _open


## How many of the seat's offers wait (the unspent count).
func waiting() -> int:
	return _offers.size()


## True once an offer was rolled with the seat's wizard there and the menu has not opened since.
func wants_open() -> bool:
	return _wants_open and not _offers.is_empty()


## Open it for its seat on its oldest offer (closing any other panel of theirs), laid out in `room`.
## False with none waiting, already open, or the seat has no device.
func open_menu() -> bool:
	if visible and not _open and not _offers.is_empty():
		# Still rolling up: it opens again once rolled up (the panels ask each frame), never by a jump.
		_wants_open = true
		return false
	_wants_open = false
	if _open or _ui_focus == null or _offers.is_empty():
		return false
	_ui_focus.close(index)
	_fill(_offers[0])
	visible = true
	var controls: Array[Control] = []
	for card: CardScript in _cards:
		controls.append(card)
	if not _ui_focus.open(index, controls):
		visible = false
		_shown = -1
		return false
	_refused = -1
	_rerolled = []
	_rerolling = false
	_reroll_pending = false
	_open = true
	_unrolled = 0
	_lay_out()
	_ui_focus.focus(index, _cards[0])
	_focused = maxi(_ui_focus.focus_index(index), 0)
	_settle()
	return true


## Close it if it is open (the offer stays unspent); it rolls up over OPEN_FRAMES frames.
func close_menu() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## One frame of its looks: unrolling or rolling up, the cards standing up or sinking, the rim and
## the row sliding (`panels.gd` calls it every frame; tests call it directly). It is laid out as it
## opens: a seat joining or leaving while it is open moves it the next time it opens.
func step() -> void:
	if not visible:
		return
	if _open and not _rerolled.is_empty():
		_rerolling = true
	var target: int = OPEN_FRAMES if _open and not _rerolling else 0
	if _unrolled != target:
		_unrolled += signi(target - _unrolled)
		_apply_height()
	if _open and _rerolling and _unrolled == 0:
		# Rolled up for a reroll: the cards turn over to the new choices, and it unrolls again.
		_turn_over()
		return
	if not _open and _unrolled == 0:
		# Rolled up (or closed before it unrolled at all): it hides.
		visible = false
		return
	for at in _cards.size():
		var card: CardScript = _cards[at]
		var lift: int = clampi(card.lift + (1 if at == _focused else -1), 0, CardScript.LIFT)
		if lift != card.lift:
			card.lift = lift
			card.queue_redraw()
	if _rim_frame < MOVE_FRAMES:
		_rim_frame += 1
		_cursor.queue_redraw()
	if _row_frame < SCROLL_FRAMES:
		_row_frame += 1
		_row.position.x = _row_x()


## True while any of its looks is still changing (for tests and screenshots).
func is_moving() -> bool:
	if not visible:
		return false
	if not _open or _rerolling or not _rerolled.is_empty() or _unrolled != OPEN_FRAMES or _rim_frame < MOVE_FRAMES or _row_frame < SCROLL_FRAMES:
		return true
	for at in _cards.size():
		if _cards[at].lift != (CardScript.LIFT if at == _focused else 0):
			return true
	return false


## Its cards, in order (for tests and screenshots).
func cards() -> Array[CardScript]:
	return _cards.duplicate()


## The card focused (-1: none), and the first in view of a scrolling row.
func focused_card() -> int:
	return _focused


func first_in_view() -> int:
	return _first


## Its title as shown.
func title_text() -> String:
	return _title


## Its layout (for tests).
func layout() -> LayoutScript:
	return _layout


## The gold rim's rect now (in the row's space, for tests).
func rim_rect() -> Rect2:
	return _rim_now()


## The number of the offer it shows (-1 for none).
func shown_offer() -> int:
	return _shown


## The height it has when fully unrolled.
func full_height() -> float:
	return _full_height


## One card a choice of `offer`.
func _fill(offer: Dictionary) -> void:
	for card: CardScript in _cards:
		_row.remove_child(card)
		card.queue_free()
	_cards.clear()
	_shown = int(offer.get("offer", -1))
	var choices: Array = offer.get("choices", [])
	_title = REFUSED_TEXT if _shown == _refused else TITLE_TEXT % choices.size()
	for choice in choices.size():
		var made: CardScript = CardScript.new()
		made.name = "Choice%d" % choice
		made.show_choice(choices[choice] as Dictionary)
		_row.add_child(made)
		_cards.append(made)
	_row.move_child(_cursor, -1)
	_focused = -1
	_first = 0


## The cards turned over to the rerolled choices (`_rerolled`), laid out again, the focus kept on
## the card it was on.
func _turn_over() -> void:
	var choices: Array[Dictionary] = _rerolled
	_rerolled = []
	_rerolling = false
	if choices.size() != _cards.size():
		# Another count of choices: closed and opened again on the new ones (from the waiting list).
		close_menu()
		_wants_open = true
		return
	for at in choices.size():
		_cards[at].show_choice(choices[at])
	_title = TITLE_TEXT % choices.size()
	_lay_out()
	_settle()


## Lay its cards out in its room and centre it there.
func _lay_out() -> void:
	var space: Rect2 = room
	if not space.has_area():
		space = get_viewport_rect() if is_inside_tree() else Rect2(Vector2.ZERO, Vector2(640.0, 360.0))
	# Too tall for the room: fewer cards in view, each wider, so their words take fewer lines.
	var most: int = _cards.size()
	var card_height: float = 0.0
	while true:
		_layout.fit(_cards.size(), space.size.x, most)
		card_height = 0.0
		for card: CardScript in _cards:
			card_height = maxf(card_height, card.fit_width(_layout.card_width))
		if LayoutScript.EDGE * 2.0 + TITLE_HEIGHT + card_height <= space.size.y - 2.0 * LayoutScript.MARGIN or _layout.shown <= 1 or _layout.card_width >= LayoutScript.CARD_MAX:
			break
		most = _layout.shown - 1
	for at in _cards.size():
		var card: CardScript = _cards[at]
		card.position = Vector2(float(at) * _layout.pitch(), 0.0)
		card.size = Vector2(_layout.card_width, card_height)
		card.lift = 0
	_cursor.position = Vector2.ZERO
	_cursor.size = Vector2(maxf(float(_cards.size()) * _layout.pitch(), 1.0), card_height)
	var top: float = LayoutScript.EDGE + TITLE_HEIGHT
	_strip.position = Vector2(_layout.row_left(), top)
	_strip.size = Vector2(_layout.row_width(), card_height)
	_row.size = _cursor.size
	_full_height = top + card_height + LayoutScript.EDGE
	var width: float = _layout.menu_width()
	var at: Vector2 = (space.get_center() - Vector2(width, _full_height) * 0.5).round()
	# Kept inside its room (its top left first, should it be bigger than the room).
	at = at.min(space.end - Vector2(width, _full_height)).max(space.position)
	position = at
	size = Vector2(width, 0.0)
	_apply_height()


## Put the rim, the row and the focused card where they rest now (no slide: it is opening).
func _settle() -> void:
	_rim_to = _card_rect(maxi(_focused, 0))
	_rim_from = _rim_to
	_rim_frame = MOVE_FRAMES
	_row_to = -float(_first) * _layout.pitch()
	_row_from = _row_to
	_row_frame = SCROLL_FRAMES
	_row.position.x = _row_to
	for at in _cards.size():
		_cards[at].lift = CardScript.LIFT if at == _focused else 0
	_cursor.queue_redraw()


func _apply_height() -> void:
	size = Vector2(size.x, roundf(_full_height * float(_unrolled) / float(OPEN_FRAMES)))
	queue_redraw()


## Card `at`'s frame standing up, in the row's space.
func _card_rect(at: int) -> Rect2:
	if at < 0 or at >= _cards.size():
		return Rect2()
	var card: CardScript = _cards[at]
	return Rect2(card.position, Vector2(card.size.x, card.size.y - float(CardScript.LIFT)))


func _rim_now() -> Rect2:
	var t: float = float(_rim_frame) / float(MOVE_FRAMES)
	var at: Vector2 = _rim_from.position.lerp(_rim_to.position, t).round()
	var wide: Vector2 = _rim_from.size.lerp(_rim_to.size, t).round()
	return Rect2(at, wide)


func _row_x() -> float:
	return roundf(lerpf(_row_from, _row_to, float(_row_frame) / float(SCROLL_FRAMES)))


func _focus_on(at: int) -> void:
	if at == _focused:
		return
	var was: int = _focused
	_focused = at
	if was < 0 or not _open:
		_settle()
		return
	_rim_from = _rim_now()
	_rim_to = _card_rect(at)
	_rim_frame = 0
	var first: int = _layout.first_for(at, _first)
	if first != _first:
		_first = first
		_row_from = _row.position.x
		_row_to = -float(_first) * _layout.pitch()
		_row_frame = 0
	_cursor.queue_redraw()


func _draw() -> void:
	var whole := Rect2(Vector2.ZERO, Vector2(size.x, _full_height))
	draw_rect(whole, OUTLINE)
	draw_rect(whole.grow(-1.0), PLAYER_COLORS[index % PLAYER_COLORS.size()])
	draw_rect(whole.grow(-2.0), BACK)
	var font: Font = get_theme_default_font()
	var x: float = floorf((size.x - font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x) * 0.5)
	draw_string(font, Vector2(x, LayoutScript.EDGE + 1.0 + font.get_ascent(FONT_SIZE)).round(), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, PLAYER_LIGHTS[index % PLAYER_LIGHTS.size()])
	if _layout.scrolls:
		var middle: float = _strip.position.y + floorf(_strip.size.y * 0.5)
		_draw_arrow(Vector2(LayoutScript.EDGE + 1.0, middle), -1)
		_draw_arrow(Vector2(size.x - LayoutScript.EDGE - 2.0, middle), 1)


## A small arrow, 3 px deep, its point at `tip` toward `way` (-1 left, 1 right).
func _draw_arrow(tip: Vector2, way: int) -> void:
	for depth in 3:
		var column: float = tip.x - float(way * depth)
		draw_rect(Rect2(Vector2(column, tip.y - float(depth)), Vector2(1.0, float(depth * 2 + 1))), ARROW)


func _draw_rim() -> void:
	if _focused < 0:
		return
	var rim: Rect2 = _rim_now()
	_cursor.draw_rect(rim, GOLD, false, 1.0)
	_cursor.draw_rect(rim.grow(-1.0), GOLD, false, 1.0)


func _on_rewards_waiting_changed(player: int, offers: Array[Dictionary]) -> void:
	if player != index:
		return
	_offers = offers.duplicate()
	if _offers.is_empty():
		_wants_open = false
	if _open and (_offers.is_empty() or int(_offers[0].get("offer", -1)) != _shown):
		# The offer it showed was picked or went (a run's start): the menu goes with it.
		close_menu()


func _on_reward_rolled(player: int, _offer: int, _choices: Array[Dictionary], here: bool) -> void:
	if player == index and here:
		_wants_open = true


func _on_reward_refused(player: int, offer: int) -> void:
	if player == index:
		_refused = offer
		_wants_open = true


func _on_reward_rerolled(player: int, offer: int, choices: Array[Dictionary]) -> void:
	if player == index and _open and offer == _shown:
		_rerolled = choices.duplicate()
		_reroll_pending = false


func _on_reward_reroll_refused(player: int, offer: int) -> void:
	if player == index and _open and offer == _shown:
		_reroll_pending = false
		_title = NO_REROLL_TEXT
		queue_redraw()


## X: spend a reward reroll on the offer shown (the class doc).
func _on_alternate(player: int, _control: Control) -> void:
	if player != index or not _open or _busy() or _events == null:
		return
	_reroll_pending = true
	UiSounds.send(_events, UiSounds.CHOOSE)
	_events.reward_reroll_requested.emit(index, _shown)


## True while a reroll is asked, or its cards still turn over: A and X wait.
func _busy() -> bool:
	return _reroll_pending or _rerolling or not _rerolled.is_empty()


func _on_closed(player: int) -> void:
	if player != index or not _open:
		return
	# It rolls up (`step`) and hides once rolled up; nothing in it can be focused meanwhile.
	_open = false
	_shown = -1


func _on_focus_changed(player: int, control: Control) -> void:
	if player == index and _open:
		_focus_on(_cards.find(control as CardScript))


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	var choice: int = _cards.find(control as CardScript)
	if choice < 0 or _busy():
		return
	UiSounds.send(_events, UiSounds.CHOOSE)
	if _events != null:
		_events.reward_pick_requested.emit(index, _shown, choice)
	close_menu()


func _on_cancelled(player: int) -> void:
	if player == index and _open:
		close_menu()
