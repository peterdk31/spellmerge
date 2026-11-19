extends RefCounted
## Where a reward menu's cards sit in the room it has (hud/menus/reward, the owner's redesign of
## 2026-11-19): one row, the cards side by side, as wide as the room lets them be between CARD_MIN
## and CARD_MAX, so 1, 2, 3, 4 or more offers lay out evenly at full screen and in a quarter of it.
## When even CARD_MIN is too wide for all of them the row shows as many as fit (`shown`) and
## scrolls (`scrolls`, an arrow's room each side; `first_for` keeps the focused card in view).
## Plain numbers by whole pixels, no nodes: `reward_menu.gd` reads it, the tests check it alone.

## Air between two cards, and the menu's own border and air inside it (each side).
const GAP: float = 4.0
const EDGE: float = 4.0
## The narrowest and widest a card is.
const CARD_MIN: float = 60.0
const CARD_MAX: float = 96.0
## Each side of the row while it scrolls, for its arrow.
const ARROW_ROOM: float = 6.0
## Air kept between the menu and its room's edge.
const MARGIN: float = 4.0

## The cards in the row, how many show at once, how wide each is, and whether the row scrolls.
var count: int = 0
var shown: int = 0
var card_width: float = 0.0
var scrolls: bool = false


## Lay out `of_count` cards in a room `room_width` pixels wide.
func fit(of_count: int, room_width: float) -> void:
	count = maxi(of_count, 0)
	shown = count
	scrolls = false
	var inner: float = floorf(room_width - 2.0 * (MARGIN + EDGE))
	if count > 0 and _width_for(count, inner) < CARD_MIN:
		scrolls = true
		inner -= 2.0 * ARROW_ROOM
		shown = clampi(floori((inner + GAP) / (CARD_MIN + GAP)), 1, count)
	card_width = maxf(floorf(minf(_width_for(shown, inner), CARD_MAX)), 1.0) if shown > 0 else 0.0


## The step from one card to the next (a card and a gap).
func pitch() -> float:
	return card_width + GAP


## How wide the row in view is (the cards shown and their gaps).
func row_width() -> float:
	return maxf(float(shown) * card_width + float(shown - 1) * GAP, 0.0)


## Where the row in view starts, from the menu's left edge (past an arrow's room while it scrolls).
func row_left() -> float:
	return EDGE + (ARROW_ROOM if scrolls else 0.0)


## How wide the whole menu is.
func menu_width() -> float:
	return row_left() * 2.0 + row_width()


## The first card in view so that card `focused` shows, from `first` (the one in view before),
## moving the row as little as it can.
func first_for(focused: int, first: int) -> int:
	var at: int = first
	if focused < at:
		at = focused
	elif focused >= at + shown:
		at = focused - shown + 1
	return clampi(at, 0, maxi(count - shown, 0))


func _width_for(cards: int, inner: float) -> float:
	return (inner - float(cards - 1) * GAP) / float(cards)
