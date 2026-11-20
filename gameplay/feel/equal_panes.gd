extends RefCounted
## The panes of the equal split screen (the owner, 2026-11-19 and 2026-11-20;
## `SplitScreenSetting.EQUAL`): pure geometry, nothing drawn. `split_camera.gd` groups the seats as
## the Voronoi split does (wizards standing close share a view) and lays each group's view on its
## pane here (`lay`); the bisector cut (`voronoi_cells.gd`) between the panes' middles (and the
## blank's) gives exactly the panes, so the drawing and every reader of `ScreenViews` work unchanged.
##
## - **One group** (or none): the whole screen.
## - **Two groups:** the left and right halves, always (the owner, 2026-11-20), whichever seats
##   they hold: the group whose seats' corner panels are more on the left takes the left half (a tie:
##   the group of the lowest seat).
## - **Three groups of three players, or four groups:** the 2×2 grid of quarters, each group the
##   quarter that keeps most of its seats' panels where they are (`_score`). With three, the fourth
##   quarter is a blank: no view's, drawn as the void (`blank_quarter`).
## - **Three groups of four players** (a pair and two alone; the owner, 2026-11-20): the pair a half,
##   the two alone a quarter each of the other half; no void. A bisector cut cannot make that
##   layout, so the pair's view is cut as its half's top quarter (`split_camera.gd` eases its anchor to the top quarter's middle) and the bottom quarter
##   is its **twin** (`twin_quarter`, `twin_group`): a blank site whose part of the screen shows the
##   pair's own picture with no divider between, so the two read as one pane.
##
## **The HUD's corners** (`corner`): each seat's corner panel, builder, inventory and reward menu
## sit in one quarter of the screen, and a panel at that quarter's outer side (the screen's corner)
## or its inner side (toward the screen's middle line). Unsplit, a seat's is its own corner's quarter
## at its outer side (P1 top left, P2 top right, P3 bottom left, P4 bottom right). Laid on panes,
## each seat takes a spot inside its own group's pane: its own corner if that is in the pane, else
## a free spot on its own row (a quarter's outer side, then its inner side: a panel keeps its row,
## the owner, 2026-11-20), else one on the other row, so no two panels
## stand on one spot (nor on the corner of a seat with a body but no pane here, `elsewhere`: a seat
## played on another machine) and each stays inside its pane (`hud_corners_changed`; the HUD moves them,
## hud/panels/seat_corners.gd). A spot is `quarter * 2 + inner` (inner 1 for the inner side).
##
## **Two seats of a half each a quarter** (the owner, 2026-11-20): a seat's builder, inventory and
## reward menu open in its panel's quarter, so where two seats share a half (two pairs, the pair of
## four players in three groups, a pair of three players) and their panels would sit on one row of
## one quarter, the one at the inner side moves to the half's other quarter (its outer side) with
## its menus, so two players' menus never overlap (`_part`); not onto the panel of a seat played on
## another machine. A trio's half has three seats for two quarters, and two of them share one.
##
## Made once, filled by `lay`; nothing allocated after it is made.

const ActorsScript := preload("res://core/actors/actors.gd")

## Quarters (a bit each): the left half's, the right half's, all four.
const LEFT_QUARTERS: int = 0b0101
const RIGHT_QUARTERS: int = 0b1010
const ALL_QUARTERS: int = 0b1111

## By group (its lowest seat): the quarters its pane covers (a bit each; 0: no group).
var quarters: PackedInt32Array = PackedInt32Array()
## The quarter no group's (the blank with three groups of three players), or -1.
var blank_quarter: int = -1
## The pair's twin quarter with three groups of four players (its half's bottom quarter, shown with
## the pair's picture), and the pair (its lowest seat); -1: none.
var twin_quarter: int = -1
var twin_group: int = -1
## By seat: its HUD spot (`quarter * 2 + inner`); its own corner's outer side for a seat in no group.
var corner: PackedInt32Array = PackedInt32Array()
## How many groups the last `lay` had.
var groups: int = 0

## The lowest seats of the groups (`groups` of them), and a scratch of quarters taken.
var _firsts: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	quarters.resize(ActorsScript.SEATS)
	corner.resize(ActorsScript.SEATS)
	_firsts.resize(ActorsScript.SEATS)
	for seat in ActorsScript.SEATS:
		corner[seat] = home_spot(seat)


## Seat `seat`'s spot unsplit: its own corner's quarter, at its outer side.
static func home_spot(seat: int) -> int:
	return seat * 2


## Lay the panes for the groups `group_seats` (by group's lowest seat: the seats it holds, a bit a
## seat; 0 for a seat that leads no group), and each seat's HUD spot, keeping off the own corners of
## the seats `elsewhere` (a bit a seat: shown on the HUD, in no pane here).
func lay(group_seats: PackedInt32Array, elsewhere: int = 0) -> void:
	groups = 0
	blank_quarter = -1
	twin_quarter = -1
	twin_group = -1
	for seat in ActorsScript.SEATS:
		quarters[seat] = 0
		corner[seat] = home_spot(seat)
		if group_seats[seat] != 0:
			_firsts[groups] = seat
			groups += 1
	if groups == 1:
		quarters[_firsts[0]] = ALL_QUARTERS
	elif groups == 2:
		var a: int = _firsts[0]
		var b: int = _firsts[1]
		# The first group left unless the other way keeps more panels on their own side.
		var kept: int = _on_side(group_seats[a], 0) + _on_side(group_seats[b], 1)
		var swapped: int = _on_side(group_seats[a], 1) + _on_side(group_seats[b], 0)
		var a_left: bool = kept >= swapped
		quarters[a] = LEFT_QUARTERS if a_left else RIGHT_QUARTERS
		quarters[b] = RIGHT_QUARTERS if a_left else LEFT_QUARTERS
	elif groups == 3 and _seats_in(group_seats) == 4:
		_lay_pair_half(group_seats)
	elif groups >= 3:
		_lay_quarters(group_seats)
	var used: int = 0
	for at in groups:
		used |= quarters[_firsts[at]]
	if groups == 3 and twin_group < 0:
		for quarter in 4:
			if used & (1 << quarter) == 0:
				blank_quarter = quarter
	var reserved: int = 0
	for seat in ActorsScript.SEATS:
		if elsewhere & (1 << seat) != 0:
			reserved |= 1 << home_spot(seat)
	for at in groups:
		_spots(group_seats[_firsts[at]], quarters[_firsts[at]], reserved)
		_part(group_seats[_firsts[at]], quarters[_firsts[at]], reserved)


## Group `group`'s pane (lowest seat) on a screen of `screen` pixels; an empty rect for no group.
func pane(group: int, screen: Vector2) -> Rect2:
	var mask: int = quarters[group]
	if mask == 0:
		return Rect2()
	var box := Rect2()
	var first: bool = true
	for quarter in 4:
		if mask & (1 << quarter) != 0:
			box = quarter_rect(quarter, screen) if first else box.merge(quarter_rect(quarter, screen))
			first = false
	return box


## The middle of group `group`'s pane (where its view draws its wizards and its anchor stands).
func site(group: int, screen: Vector2) -> Vector2:
	return pane(group, screen).get_center()


## The middle of the blank quarter, or Vector2.INF (none).
func blank_site(screen: Vector2) -> Vector2:
	return quarter_site(blank_quarter, screen) if blank_quarter >= 0 else Vector2.INF


## The middle of quarter `quarter` of the screen (where a blank of that quarter settles).
static func quarter_site(quarter: int, screen: Vector2) -> Vector2:
	return quarter_rect(quarter, screen).get_center()


## Quarter `quarter` of the screen (0 top left, 1 top right, 2 bottom left, 3 bottom right).
static func quarter_rect(quarter: int, screen: Vector2) -> Rect2:
	var half: Vector2 = screen * 0.5
	return Rect2(Vector2(half.x * float(quarter % 2), half.y * float(quarter >> 1)), half)


## Where a blank's site rests while it is not shown: past its quarter's corner of the screen, so far
## that no point of the screen is nearer it than any view's anchor (half again the screen's
## diagonal past the corner); it moves in from there and back out, so the blank grows and shrinks
## from its corner, never appearing at once.
static func blank_rest(quarter: int, screen: Vector2) -> Vector2:
	var at := Vector2(screen.x * float(quarter % 2), screen.y * float(quarter >> 1))
	return at + (at - screen * 0.5) * 3.0


## The number of seats in `seats` (a bit a seat).
static func count_of(seats: int) -> int:
	var n: int = 0
	var mask: int = seats
	while mask != 0:
		mask &= mask - 1
		n += 1
	return n


## How many seats the groups hold.
func _seats_in(group_seats: PackedInt32Array) -> int:
	var n: int = 0
	for seat in ActorsScript.SEATS:
		n += count_of(group_seats[seat])
	return n


## How many of the seats `seats` have their own corner on side `side` (0 left, 1 right).
static func _on_side(seats: int, side: int) -> int:
	var n: int = 0
	for seat in ActorsScript.SEATS:
		if seats & (1 << seat) != 0 and seat % 2 == side:
			n += 1
	return n


## How well quarter `quarter` keeps the seats `seats`' panels: 4 a seat whose own quarter it is, 2
## for one on its side, 1 for one on its row.
static func _score(seats: int, quarter: int) -> int:
	var score: int = 0
	for seat in ActorsScript.SEATS:
		if seats & (1 << seat) == 0:
			continue
		if seat == quarter:
			score += 4
		elif seat % 2 == quarter % 2:
			score += 2
		elif seat >> 1 == quarter >> 1:
			score += 1
	return score


## Three or four groups: a quarter each, the assignment of the best score (the first found on a
## tie, in quarter order of the groups by lowest seat), every way tried (at most 24).
func _lay_quarters(group_seats: PackedInt32Array) -> void:
	var best: int = -1
	var best_score: int = -1
	# Each way as four quarters (2 bits each, a group's at its place in `_firsts`).
	for q0 in 4:
		for q1 in 4:
			if q1 == q0:
				continue
			for q2 in 4:
				if q2 == q0 or q2 == q1:
					continue
				var q3: int = 6 - q0 - q1 - q2
				var score: int = _score(group_seats[_firsts[0]], q0) + _score(group_seats[_firsts[1]], q1) + _score(group_seats[_firsts[2]], q2)
				if groups == 4:
					score += _score(group_seats[_firsts[3]], q3)
				if score > best_score:
					best_score = score
					best = q0 | (q1 << 2) | (q2 << 4) | (q3 << 6)
	for at in groups:
		quarters[_firsts[at]] = 1 << ((best >> (at * 2)) & 3)


## Three groups of four players: the pair a half, the two alone the other half's quarters; the way
## of the best score (the pair 4 a seat whose corner is in its half, the two alone `_score`), the
## first on a tie (the pair left, then the lower seat on top). The pair's half's bottom quarter is
## its twin.
func _lay_pair_half(group_seats: PackedInt32Array) -> void:
	var pair: int = -1
	var one: int = -1
	var other: int = -1
	for at in groups:
		var first: int = _firsts[at]
		if count_of(group_seats[first]) == 2:
			pair = first
		elif one < 0:
			one = first
		else:
			other = first
	var best_score: int = -1
	var best: int = 0
	for way in 4:
		var side: int = way >> 1
		var half: int = LEFT_QUARTERS if side == 0 else RIGHT_QUARTERS
		var top: int = 1 - side
		var bottom: int = 3 - side
		var score: int = 0
		for seat in ActorsScript.SEATS:
			if group_seats[pair] & (1 << seat) != 0 and half & (1 << seat) != 0:
				score += 4
		var one_at: int = top if way & 1 == 0 else bottom
		var other_at: int = bottom if way & 1 == 0 else top
		score += _score(group_seats[one], one_at) + _score(group_seats[other], other_at)
		if score > best_score:
			best_score = score
			best = way
	var picked: int = best >> 1
	quarters[pair] = LEFT_QUARTERS if picked == 0 else RIGHT_QUARTERS
	quarters[one] = 1 << ((1 - picked) if best & 1 == 0 else (3 - picked))
	quarters[other] = 1 << ((3 - picked) if best & 1 == 0 else (1 - picked))
	twin_group = pair
	twin_quarter = 2 + picked


## The spots of the seats `seats` inside the pane of the quarters `mask`, none in `reserved`.
func _spots(seats: int, mask: int, reserved: int) -> void:
	var taken: int = reserved
	var left: int = 0
	for seat in ActorsScript.SEATS:
		if seats & (1 << seat) == 0:
			continue
		if mask & (1 << seat) != 0:
			corner[seat] = home_spot(seat)
			taken |= 1 << home_spot(seat)
		else:
			left |= 1 << seat
	for pass_at in 4:
		for seat in ActorsScript.SEATS:
			if left & (1 << seat) == 0:
				continue
			var spot: int = _free_spot(seat, mask, taken, pass_at)
			if spot >= 0:
				corner[seat] = spot
				taken |= 1 << spot
				left &= ~(1 << seat)


## Two seats of a half on one row each a quarter (the owner, 2026-11-20): in a half (`mask`), a
## seat of `seats` at a quarter's inner side sharing that quarter with another of them moves to
## the half's other quarter, its outer side, while none of them is there and no panel of a seat
## played elsewhere (`reserved`, spots) stands in it; its menus go with it.
func _part(seats: int, mask: int, reserved: int) -> void:
	if mask != LEFT_QUARTERS and mask != RIGHT_QUARTERS:
		return
	for seat in ActorsScript.SEATS:
		if seats & (1 << seat) == 0 or corner[seat] & 1 == 0:
			continue
		var quarter: int = corner[seat] >> 1
		var other: int = quarter ^ 2
		if reserved & (3 << (other * 2)) == 0 and _shared(seats, seat, quarter) and not _shared(seats, seat, other):
			corner[seat] = other * 2


## True when a seat of `seats` but `seat` has its spot in quarter `quarter`.
func _shared(seats: int, seat: int, quarter: int) -> bool:
	for other in ActorsScript.SEATS:
		if other != seat and seats & (1 << other) != 0 and corner[other] >> 1 == quarter:
			return true
	return false


## A free spot for seat `seat` in a quarter of `mask` on pass `pass_at`: 0 its row's outer side,
## 1 its row's inner side, 2 the other row's outer side, 3 its inner side; or -1.
static func _free_spot(seat: int, mask: int, taken: int, pass_at: int) -> int:
	var row: int = seat >> 1 if pass_at < 2 else 1 - (seat >> 1)
	var inner: int = pass_at & 1
	for quarter in 4:
		if mask & (1 << quarter) == 0 or quarter >> 1 != row:
			continue
		var spot: int = quarter * 2 + inner
		if taken & (1 << spot) == 0:
			return spot
	return -1
