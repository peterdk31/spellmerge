extends "res://tests/support/suite.gd"
## Two players sharing a half of the equal split have each their own quarter of it, the corner
## panel with its menus (the owner, 2026-11-20 and on #881; gameplay/feel/equal_panes.gd `_part`,
## hud/panels/seat_corners.gd): with two pairs, and with the pair of four players in three groups,
## both players of a half open their builder, inventory or reward menu at once and the two never
## overlap; each stays inside its pane. Panel and menus slide there together by whole pixels; a
## panel hides only while its own open menu covers it.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const RewardMenuScript := preload("res://hud/menus/reward/reward_menu.gd")
const SeatCornersScript := preload("res://hud/panels/seat_corners.gd")
const EqualPanesScript := preload("res://gameplay/feel/equal_panes.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

const COIN: ItemContent = preload("res://content/coins/coin/coin.tres")

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	for seat in 4:
		_input.add_virtual_device(seat)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.save = SaveFile.new("user://test_shared_half_menus_save.cfg")
	root.add_child(_hud)
	own(_hud)
	for seat in 4:
		_bus.player_joined.emit(seat)
	_bus.room_entered.emit(&"test_room", 0)


func _tap(seat: int, action: StringName) -> void:
	_input.send_virtual(seat, action, 1.0)
	_input.send_virtual(seat, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()
	_hud.step_corners()
	for seat in 4:
		_hud.get_reward(seat).step()


## The equal split laid for `groups` (lists of seats), told to the HUD as Feel tells it, and the
## panels and menus settled there. The panes, for their rects.
func _lay(groups: Array) -> EqualPanesScript:
	var by_first := PackedInt32Array([0, 0, 0, 0])
	for group: Array in groups:
		var mask: int = 0
		for seat: int in group:
			mask |= 1 << seat
		by_first[group.min()] = mask
	var panes := EqualPanesScript.new()
	panes.lay(by_first)
	_bus.hud_corners_changed.emit(panes.corner)
	for i in 60:
		_hud.step_corners()
	return panes


func _view() -> Vector2:
	return (_hud.get_node("Root") as Control).size


func _pane_of(panes: EqualPanesScript, groups: Array, seat: int) -> Rect2:
	for group: Array in groups:
		if group.has(seat):
			return panes.pane(group.min(), _view())
	return Rect2()


func _builder_rect(seat: int) -> Rect2:
	return _hud.get_radial(seat).layout_parts()["quarter"]


func _inventory_rect(seat: int) -> Rect2:
	return Rect2(_hud.get_inventory(seat).quarter_at, (_view() * 0.5).floor())


func _reward_rect(seat: int) -> Rect2:
	var menu: RewardMenuScript = _hud.get_reward(seat)
	return Rect2(menu.position, menu.size)


## Seat `seat`'s reward offer `offer` of two choices, lying where it stands, opened with A.
func _open_reward(seat: int, offer: int) -> void:
	var choices: Array[Dictionary] = []
	for amount in [5, 6]:
		choices.append({"kind": ItemKinds.COIN, "id": COIN.id, "count": amount, "name": "%s x%d" % [COIN.shown_name(), amount], "icon": COIN.icon, "description": COIN.description})
	_bus.reward_rolled.emit(seat, offer, choices, true)
	_bus.rewards_waiting_changed.emit(seat, [{"offer": offer, "here": true, "lying": true, "choices": choices}] as Array[Dictionary])
	_bus.reward_near_changed.emit(seat, offer, Vector2.ZERO)
	_tap(seat, &"take")


func _check_apart(groups: Array, pair: Array, what: String) -> void:
	var panes: EqualPanesScript = _lay(groups)
	var a: int = pair[0]
	var b: int = pair[1]
	# The builders, both opened in one frame.
	_tap(a, &"back")
	_tap(b, &"back")
	_frame()
	check(_hud.get_radial(a).is_open() and _hud.get_radial(b).is_open(), "%s: both builders open" % what)
	check(not _builder_rect(a).intersects(_builder_rect(b)), "%s: the builders never overlap (%s, %s)" % [what, _builder_rect(a), _builder_rect(b)])
	for seat: int in pair:
		check(_pane_of(panes, groups, seat).encloses(_builder_rect(seat)), "%s: P%d's builder inside its pane" % [what, seat + 1])
	_tap(a, &"back")
	_tap(b, &"back")
	_frame()
	_frame()
	check(not _hud.get_radial(a).is_open() and not _hud.get_radial(b).is_open(), "%s: both builders closed" % what)
	# The inventories.
	_tap(a, &"inventory")
	_tap(b, &"inventory")
	_frame()
	check(_hud.get_inventory(a).is_open() and _hud.get_inventory(b).is_open(), "%s: both inventories open" % what)
	check(not _inventory_rect(a).intersects(_inventory_rect(b)), "%s: the inventories never overlap" % what)
	for seat: int in pair:
		check(_pane_of(panes, groups, seat).encloses(_inventory_rect(seat)), "%s: P%d's inventory inside its pane" % [what, seat + 1])
	_hud.get_inventory(a).close_inventory()
	_hud.get_inventory(b).close_inventory()
	_frame()
	_frame()
	check(not _hud.get_inventory(a).is_open() and not _hud.get_inventory(b).is_open(), "%s: both inventories closed" % what)
	# The reward menus.
	_open_reward(a, 1)
	_open_reward(b, 2)
	_frame()
	for i in 10:
		_frame()
	check(_hud.get_reward(a).is_open() and _hud.get_reward(b).is_open(), "%s: both reward menus open" % what)
	check(_reward_rect(a).has_area() and not _reward_rect(a).intersects(_reward_rect(b)), "%s: the reward menus never overlap (%s, %s)" % [what, _reward_rect(a), _reward_rect(b)])
	for seat: int in pair:
		check(_pane_of(panes, groups, seat).encloses(_reward_rect(seat)), "%s: P%d's reward menu inside its pane" % [what, seat + 1])
		var panel: Control = _hud.get_panel(seat)
		var covered: bool = _reward_rect(seat).intersects(Rect2(panel.position, panel.size))
		check_equal(panel.visible, not covered, "%s: P%d's panel hidden only if its reward menu covers it" % [what, seat + 1])


func test_two_pairs_open_their_menus_in_their_own_quarters() -> void:
	_check_apart([[0, 1], [2, 3]], [0, 1], "two pairs, the left")


func test_the_right_pair_of_two_pairs_too() -> void:
	_check_apart([[0, 1], [2, 3]], [2, 3], "two pairs, the right")


func test_the_pair_of_four_players_in_three_groups() -> void:
	_check_apart([[0, 1], [2], [3]], [0, 1], "a pair and two alone")


func test_panel_and_menus_slide_to_their_quarter_together_by_whole_pixels() -> void:
	_tap(1, &"back")
	_frame()
	check(_hud.get_radial(1).is_open(), "P2's builder open in its own quarter")
	var last: Vector2 = _hud.get_radial(1).quarter_at
	var target: Vector2 = SeatCornersScript.quarter_origin(2, _view())
	_bus.hud_corners_changed.emit(PackedInt32Array([0, 4, 2, 6]))
	var frames: int = 0
	while _hud.get_corners().is_sliding(1) and frames < 200:
		_hud.step_corners()
		frames += 1
		var at: Vector2 = _hud.get_radial(1).quarter_at
		check(not _hud.get_panel(1).visible, "the panel stays hidden under its sliding builder (frame %d)" % frames)
		check_equal(at, at.round(), "whole pixels (%s)" % at)
		check(at.distance_to(last) <= SeatCornersScript.SLIDE_MOST + 0.01, "never a jump (%s to %s)" % [last, at])
		last = at
	check_equal(_hud.get_radial(1).quarter_at, target, "P2's builder in the bottom left quarter")
	check(frames >= 3, "over at least three frames (%d)" % frames)
	var panel: Control = _hud.get_panel(1)
	check_equal(panel.position, SeatCornersScript.panel_spot(4, _view(), panel.size), "its panel with it, at the bottom left")
	check(not panel.visible, "its panel hidden under its open builder")
	_tap(1, &"back")
	_frame()
	check(panel.visible, "shown again once the builder closes")


## The owner, on #881: a panel hides only while its menu would cover it; a menu open in another
## quarter leaves it shown.
func test_a_panel_hides_only_under_its_own_menu() -> void:
	_tap(1, &"back")
	_frame()
	check(not _hud.get_panel(1).visible, "on its own quarter the builder covers the panel")
	var view: Vector2 = _view()
	var panel: Control = _hud.get_panel(1)
	var rect := Rect2(panel.position, panel.size)
	check(HudScript.menu_covers(SeatCornersScript.quarter_origin(1, view), view, rect), "its own quarter covers it")
	check(not HudScript.menu_covers(SeatCornersScript.quarter_origin(3, view), view, rect), "the quarter under it does not")
	check(not HudScript.menu_covers(SeatCornersScript.quarter_origin(0, view), view, rect), "nor the one beside it")
	_tap(1, &"back")
	_frame()
	check(panel.visible, "shown again once the builder closes")


## Regression (review): a reward menu rolling up and down for a reroll showed the bottom row's panel
## between; it is measured by its whole laid-out height.
func test_a_reward_menu_covers_its_panel_by_its_whole_height_while_it_rolls() -> void:
	_open_reward(2, 1)
	_frame()
	for i in 10:
		_frame()
	var menu: RewardMenuScript = _hud.get_reward(2)
	var panel: Control = _hud.get_panel(2)
	var full := Rect2(menu.position, Vector2(menu.size.x, menu.full_height()))
	var covered: bool = full.intersects(Rect2(panel.position, panel.size))
	check_equal(panel.visible, not covered, "hidden only if the whole menu covers it")
	# Rolled up to nothing (as for a reroll), it still counts its whole height.
	menu.size = Vector2(menu.size.x, 0.0)
	_hud.step_corners()
	check_equal(panel.visible, not covered, "rolled up, the same")
