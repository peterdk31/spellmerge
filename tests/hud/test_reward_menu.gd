extends "res://tests/support/suite.gd"
## The reward menu on screen (connected biomes CB10, hud/menus/reward, hud/panels; its cards by the
## owner's redesign of 2026-11-19): an offer rolled for a seat whose wizard was there opens that
## seat's menu by itself, "Pick 1 of 2" over a row of cards, one a choice, each with its name and
## what it does; right and left move along the row (wrapping), A on one sends the command
## `reward_pick_requested` with its offer and closes it; B closes it with nothing sent, and the
## corner panel says the reward waits; the seat's A with nothing else for it opens it again. An offer
## rolled for a seat that was not there opens nothing. It closes by itself when its offer goes. The
## cards of 1 to 5 choices lay out evenly inside the menu and the menu inside its room, at full
## screen and in a quarter of it (past what fits, the row scrolls, keeping the focused card in
## view), their words wrapped, never clipped. Opening, closing and a move of the focus play their
## frames (Smooth). The corner panel says the seat's coins.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const RewardMenuScript := preload("res://hud/menus/reward/reward_menu.gd")
const RewardCardScript := preload("res://hud/menus/reward/reward_card.gd")
const LayoutScript := preload("res://hud/menus/reward/reward_layout.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

const FULL: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)
const QUARTER: Rect2 = Rect2(320.0, 180.0, 320.0, 180.0)
## A card's builder line as long as a card's may be (StoryValidator.MAX_LORE_CHARS).
const LONG_LINE: String = "Splits into a ring of frostfire shards that seek the nearest."

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
## Every `reward_pick_requested` sent, as [seat, offer, choice].
var _picked: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_picked = []
	_bus.reward_pick_requested.connect(func(seat: int, offer: int, choice: int) -> void: _picked.append([seat, offer, choice]))
	for seat in 2:
		_input.add_virtual_device(seat)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.save = SaveFile.new("user://test_reward_menu_save.cfg")
	root.add_child(_hud)
	own(_hud)
	for seat in 2:
		_bus.player_joined.emit(seat)
	_bus.room_entered.emit(&"test_room", 0)


func _tap(seat: int, action: StringName) -> void:
	_input.send_virtual(seat, action, 1.0)
	_input.send_virtual(seat, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()


## The views of `count` choices, each kind in turn: a card (with a builder line as long as one may
## be), coins, a heal, more most health.
func _choices(count: int) -> Array[Dictionary]:
	var made: Array[Dictionary] = []
	var kinds: Array[StringName] = [RewardEntry.CARD, RewardEntry.COINS, RewardEntry.HEAL, RewardEntry.MAX_HEALTH]
	for at in count:
		var kind: StringName = kinds[at % kinds.size()]
		var amount: int = 5 + at
		var words: String = "Frostfire Cascade" if kind == RewardEntry.CARD else "%d %s" % [amount, kind]
		var says: String = LONG_LINE if kind == RewardEntry.CARD else RewardEntry.describe(kind, amount)
		made.append({"kind": kind, "id": &"fire" if kind == RewardEntry.CARD else &"", "count": amount, "name": words, "icon": null, "description": says})
	return made


## Seat `seat`'s offer `offer` rolled (`here` or not), waiting with any earlier ones in `waiting`.
func _roll(seat: int, offer: int, here: bool, waiting: Array[Dictionary] = [], count: int = 2) -> Array[Dictionary]:
	var choices: Array[Dictionary] = _choices(count)
	var offers: Array[Dictionary] = waiting.duplicate()
	offers.append({"offer": offer, "here": here, "choices": choices})
	_bus.reward_rolled.emit(seat, offer, choices, here)
	_bus.rewards_waiting_changed.emit(seat, offers)
	return offers


func _words(seat: int) -> Array[String]:
	var found: Array[String] = []
	for card: RewardCardScript in _hud.get_reward(seat).cards():
		found.append(card.words())
	return found


## Step `menu` until its looks rest (at most `most` frames); the frames it took.
func _settle(menu: RewardMenuScript, most: int = 30) -> int:
	var frames: int = 0
	while menu.is_moving() and frames < most:
		menu.step()
		frames += 1
	return frames


## Seat 0's menu opened on an offer of `count` choices, laid out in `space`, rested.
func _open_in(space: Rect2, count: int) -> RewardMenuScript:
	_roll(0, 1, false, [], count)
	var menu: RewardMenuScript = _hud.get_reward(0)
	menu.room = space
	check(menu.open_menu(), "it opens (%d choices)" % count)
	_settle(menu)
	return menu


func test_an_offer_for_a_seat_that_was_there_opens_its_menu() -> void:
	_roll(1, 4, true)
	_frame()
	var menu: RewardMenuScript = _hud.get_reward(1)
	check(menu.is_open() and menu.visible, "the seat's menu opens by itself")
	check(not _hud.get_reward(0).is_open(), "nobody else's")
	check_equal(_words(1), ["Frostfire Cascade", "6 coins"] as Array[String], "a card a choice")
	check_equal(menu.title_text(), "Pick 1 of 2", "pick 1 of 2")
	check(_hud.reward_room(1).encloses(Rect2(menu.position, Vector2(menu.size.x, menu.full_height()))), "inside its seat's quarter")
	_tap(1, &"accept")
	_frame()
	check_equal(_picked, [[1, 4, 0]], "A picks the focused choice, naming the offer")
	check(not menu.is_open(), "and closes it")


func test_right_and_left_move_along_the_row_and_a_picks_the_focused_card() -> void:
	_roll(0, 7, true, [], 3)
	_frame()
	var menu: RewardMenuScript = _hud.get_reward(0)
	check_equal(menu.focused_card(), 0, "the first card is focused")
	_tap(0, &"move_right")
	_frame()
	check_equal(menu.focused_card(), 1, "right: the next")
	_tap(0, &"move_right")
	_frame()
	_tap(0, &"move_right")
	_frame()
	check_equal(menu.focused_card(), 0, "past the last it wraps round")
	_tap(0, &"move_left")
	_frame()
	check_equal(menu.focused_card(), 2, "left from the first: the last")
	_tap(0, &"accept")
	_frame()
	check_equal(_picked, [[0, 7, 2]], "A picks the focused card")


func test_the_cards_lay_out_evenly_and_readable_for_one_to_five_choices() -> void:
	for space: Rect2 in [FULL, QUARTER]:
		for count in range(1, 6):
			var menu: RewardMenuScript = _open_in(space, count)
			var where: String = "%d choices in %s" % [count, space.size]
			var box := Rect2(menu.position, Vector2(menu.size.x, menu.full_height()))
			check(space.encloses(box), "%s: the menu is inside its room (%s in %s)" % [where, box, space])
			var lay: LayoutScript = menu.layout()
			check(lay.card_width >= LayoutScript.CARD_MIN or not lay.scrolls, "%s: cards no narrower than CARD_MIN unless the room is too small" % where)
			check(lay.card_width <= LayoutScript.CARD_MAX, "%s: no wider than CARD_MAX" % where)
			var cards: Array[RewardCardScript] = menu.cards()
			check_equal(cards.size(), count, "%s: a card a choice" % where)
			var first: int = menu.first_in_view()
			var in_view: Array[Rect2] = []
			for at in range(first, first + lay.shown):
				var card: RewardCardScript = cards[at]
				var on_screen := Rect2(card.get_global_rect().position, card.size)
				check(box.encloses(on_screen), "%s: card %d inside the menu" % [where, at])
				for other: Rect2 in in_view:
					check(not other.intersects(on_screen), "%s: card %d overlaps no other" % [where, at])
				in_view.append(on_screen)
			if count <= 4 or space == FULL:
				check(not lay.scrolls and lay.shown == count, "%s: every card shows side by side" % where)
			for card: RewardCardScript in cards:
				var inner: float = card.size.x - 2.0 * RewardCardScript.PAD
				check_equal("".join(card.name_lines()).replace(" ", ""), card.words().replace(" ", ""), "%s: the whole name shows" % where)
				check_equal("".join(card.description_lines()).replace(" ", ""), card.description().replace(" ", ""), "%s: the whole description shows" % where)
				for line: String in card.name_lines() + card.description_lines():
					check(card.text_width(line) <= inner, "%s: '%s' fits the card's width" % [where, line])
				check(card.size.y >= card.fit_width(card.size.x), "%s: the card is as tall as its words" % where)
			menu.close_menu()
			_settle(menu)
	var quarter_of_four: RewardMenuScript = _open_in(QUARTER, 4)
	check(not quarter_of_four.layout().scrolls, "four fit a quarter of the screen side by side")
	quarter_of_four.close_menu()
	_settle(quarter_of_four)
	var quarter_of_five: RewardMenuScript = _open_in(QUARTER, 5)
	check(quarter_of_five.layout().scrolls, "five in a quarter scroll")
	check(quarter_of_five.layout().shown < 5, "showing as many as fit")


func test_a_scrolled_row_keeps_the_focused_card_in_view() -> void:
	_roll(0, 2, true, [], 6)
	_frame()
	var menu: RewardMenuScript = _hud.get_reward(0)
	var lay: LayoutScript = menu.layout()
	check(lay.scrolls, "six in a quarter scroll")
	for step in 6:
		_tap(0, &"move_right")
		_frame()
		_settle(menu)
		var focused: int = menu.focused_card()
		check(focused >= menu.first_in_view() and focused < menu.first_in_view() + lay.shown, "card %d in view" % focused)
		var card: RewardCardScript = menu.cards()[focused]
		var strip: Control = menu.get_node("Strip") as Control
		check(strip.get_global_rect().encloses(card.get_global_rect()), "card %d drawn inside the strip" % focused)


func test_each_kind_of_reward_says_what_it_does() -> void:
	var menu: RewardMenuScript = _open_in(FULL, 4)
	var cards: Array[RewardCardScript] = menu.cards()
	check_equal(cards[0].description(), LONG_LINE, "a card says its own builder line")
	for at in range(1, 4):
		var kind: StringName = cards[at].choice["kind"]
		check(cards[at].description() != "", "%s says what it does" % kind)
		check_equal(cards[at].description(), RewardEntry.describe(kind, 5 + at), "%s: its kind's line, with its count" % kind)
		check(cards[at].description().contains(str(5 + at)), "%s: naming how much" % kind)
	for kind: StringName in RewardEntry.KINDS:
		if kind != RewardEntry.CARD:
			check(RewardEntry.DESCRIPTIONS.has(kind), "every kind but a card has its line (%s)" % kind)
			check(RewardCardScript.GLYPHS.has(kind), "and its glyph (%s)" % kind)


func test_opening_closing_and_moving_play_their_frames() -> void:
	_roll(0, 3, true, [], 3)
	_frame()
	var menu: RewardMenuScript = _hud.get_reward(0)
	var heights: Array[float] = [menu.size.y]
	while menu.is_moving() and heights.size() < 30:
		menu.step()
		heights.append(menu.size.y)
	check_equal(heights[0], 0.0, "it opens rolled up")
	check_equal(heights[-1], menu.full_height(), "and unrolls to its full height")
	check(heights.size() - 2 >= 3, "with at least 3 frames between (%s)" % [heights])
	for at in range(1, heights.size()):
		check(heights[at] >= heights[at - 1] and heights[at] == roundf(heights[at]), "growing by whole pixels")
	var cards: Array[RewardCardScript] = menu.cards()
	check_equal(cards[0].lift, RewardCardScript.LIFT, "the focused card stands up")
	var rim_start: Rect2 = menu.rim_rect()
	_tap(0, &"move_right")
	_frame()
	var rims: Array[Rect2] = []
	var lifts: Array[Vector2i] = []
	while menu.is_moving() and rims.size() < 30:
		menu.step()
		rims.append(menu.rim_rect())
		lifts.append(Vector2i(cards[0].lift, cards[1].lift))
	check(rims.size() >= 4, "the move takes frames (%d)" % rims.size())
	var between: int = 0
	for rim: Rect2 in rims:
		check(rim.position == rim.position.round(), "the rim by whole pixels")
		if rim.position.x > rim_start.position.x and rim.position.x < rims[-1].position.x:
			between += 1
	check(between >= 3, "the rim slides through at least 3 frames between the cards (%d)" % between)
	check_equal(lifts[-1], Vector2i(0, RewardCardScript.LIFT), "the old card sinks and the new stands up")
	for at in range(1, lifts.size()):
		check(absi(lifts[at].y - lifts[at - 1].y) <= 1, "a pixel a frame")
	menu.close_menu()
	check(menu.visible, "closing, it still shows")
	var closing: int = 0
	while menu.visible and closing < 30:
		menu.step()
		closing += 1
	check(not menu.visible, "and hides once rolled up")
	check(closing - 1 >= 3, "after at least 3 frames between (%d)" % closing)


func test_back_leaves_it_unspent_and_a_opens_it_again() -> void:
	var waiting: Array[Dictionary] = _roll(0, 2, true)
	_frame()
	_tap(0, &"back")
	_frame()
	check(not _hud.get_reward(0).is_open(), "B closes it")
	check(_picked.is_empty(), "with nothing sent")
	check_equal(_hud.get_panel(0).purse_text(), "1 to pick", "the corner panel says it waits")
	_settle(_hud.get_reward(0))
	_frame()
	_tap(0, &"accept")
	_frame()
	check(_hud.get_reward(0).is_open(), "A with nothing else for it opens it again")
	_bus.rewards_waiting_changed.emit(0, [] as Array[Dictionary])
	check(not _hud.get_reward(0).is_open(), "it closes when its offer goes")
	check_equal(_hud.get_panel(0).purse_text(), "", "the panel's line hides")
	check_equal(waiting.size(), 1, "one was waiting")


func test_an_offer_for_a_seat_that_was_not_there_waits() -> void:
	_roll(0, 1, false)
	_frame()
	check(not _hud.get_reward(0).is_open(), "nothing opens by itself")
	check_equal(_hud.get_panel(0).purse_text(), "1 to pick", "the unspent icon (rule 4)")


func test_a_refused_pick_opens_the_menu_again_saying_so() -> void:
	_roll(0, 6, true)
	_frame()
	_tap(0, &"accept")
	_frame()
	check(not _hud.get_reward(0).is_open(), "picked and closed")
	_settle(_hud.get_reward(0))
	_bus.reward_refused.emit(0, 6)
	# The poll after the one that closed it (the press that closed a menu never opens another).
	_frame()
	_frame()
	check(_hud.get_reward(0).is_open(), "a refused pick opens it again")
	check_equal(_hud.get_reward(0).title_text(), "Can't take that now", "saying so")


func test_one_player_lays_it_out_in_the_whole_view() -> void:
	_bus.player_left.emit(1)
	var view: Vector2 = (_hud.get_node("Root") as Control).size
	var band: float = HudScript.REWARD_CORNER_BAND
	check_equal(_hud.reward_room(0), Rect2(0.0, band, view.x, view.y - band * 2.0), "the whole view for one player, off the corner panels' bands")
	_bus.player_joined.emit(1)
	check_equal(_hud.reward_room(1).size, (view * 0.5).floor() - Vector2(0.0, band), "a quarter while several play, off its corner panel's band")
	check_equal(_hud.reward_room(0).position.y, band, "a top quarter starts under the band")


## Regression (review): a refused pick opened it again while it was still rolling up, and its
## height jumped to 0 in one frame; it now rolls up, then unrolls, a step a frame.
func test_a_refused_pick_rolls_up_before_it_opens_again() -> void:
	_roll(0, 6, true)
	_frame()
	var menu: RewardMenuScript = _hud.get_reward(0)
	_settle(menu)
	var whole: float = menu.full_height()
	var step_most: float = ceilf(whole / float(RewardMenuScript.OPEN_FRAMES))
	_tap(0, &"accept")
	_frame()
	_bus.reward_refused.emit(0, 6)
	var last: float = menu.size.y
	var heights: Array[float] = [last]
	for frame in 20:
		menu.step()
		_frame()
		check(absf(menu.size.y - last) <= step_most, "never jumps (%s)" % [heights])
		last = menu.size.y
		heights.append(last)
	check(menu.is_open(), "it opens again")
	check_equal(menu.title_text(), "Can't take that now", "saying so")
	check(heights.has(0.0), "after rolling up")


## Regression (review): its height was not fitted, so a low room left it off its room.
func test_it_stays_inside_a_low_room() -> void:
	for space: Rect2 in [Rect2(320.0, 180.0, 320.0, 110.0), Rect2(10.0, 10.0, 90.0, 60.0)]:
		var menu: RewardMenuScript = _open_in(space, 3)
		check(space.encloses(Rect2(menu.position, Vector2(menu.size.x, menu.full_height()))) or menu.full_height() > space.size.y, "inside %s, or at its top left when bigger" % space)
		check(menu.position.x >= space.position.x and menu.position.y >= space.position.y, "never above or left of %s" % space)
		menu.close_menu()
		_settle(menu)


func test_the_panel_says_the_coins() -> void:
	_bus.wallet_changed.emit(1, 12)
	check_equal(_hud.get_panel(1).purse_text(), "12 coins", "the seat's wallet")
	_roll(1, 3, false)
	check_equal(_hud.get_panel(1).purse_text(), "12 coins  1 to pick", "and its rewards waiting")
