extends "res://tests/support/suite.gd"
## Tests for the staff rows under each corner panel's mana bar (owner, 2026-10-27): a row only
## for a staff with cards (0, 1 and 4 rows), the cast sequence in read order with one group per
## cast and wasted cards greyed, the next-cast mark moving after a cast, the delay emptying and
## the recharge read apart from a plain delay, a long staff capped with "+N", four rows still a
## small corner panel, and the rows hiding while their player has a menu open. The two ways to
## show the delay (owner, 2026-10-27): a shade on the button glyph (the default, its next cast
## dashed during a recharge) and a shade on the next cast (the whole cycle during a recharge),
## and the white rim when a staff is ready again.
##
## The HUD runs on its own bus with the real `Spells` (a projectile manager and made-up carriers
## from `tests/support/fake_cards.gd`), stepped by hand. Spells keeps staffs by caster (actors
## G3b): the four wizards sit at actor ids apart from their seats, so the HUD has to ask which
## actor a seat drives.
##
## godot --headless --path . --script res://tests/hud/test_staff_strip.gd

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const PanelScript := preload("res://hud/panels/player_panel/player_panel.gd")
const RowScript := preload("res://hud/panels/player_panel/staff_row.gd")
const FakeCards := preload("res://tests/support/fake_cards.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
## Loaded, not preloaded: the scene is also the "Hud" autoload (tests/README.md).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

const DT: float = 1.0 / 60.0
const CARDS: int = 20
## Unseated actors opened before the wizards: seat s is driving the actor id s + FIRST_WIZARD.
const FIRST_WIZARD: int = 3

var _bus: EventsScript
var _spells: SpellsScript
var _mgr: ManagerScript
var _hud: HudScript
var _staff: StaffBase


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_mgr.actors = own(ActorSeats.table(4, FIRST_WIZARD)) as ActorSeats.ActorsScript
	_spells = own(SpellsScript.new()) as SpellsScript
	# Every made-up card a carrier, so each card is a cast of its own.
	_spells.registry = own(FakeCards.registry(CARDS, &"form"))
	_spells.bind(_mgr, _bus)
	_staff = StaffBase.new()
	_staff.slots = CARDS
	_staff.cast_delay = 0.1
	_staff.recharge = 0.5
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = own(UIFocusScript.new()) as UIFocusScript
	_hud.spells = _spells
	root.add_child(_hud)
	own(_hud)
	for player in 4:
		_bus.player_joined.emit(player)
	_bus.room_entered.emit(&"arena_01")


## The actor id `player`'s seat drives: what Spells keeps its staffs by.
func _caster(player: int) -> int:
	return _mgr.actors.actor_of_seat(player)


## Build `count` made-up carriers into `player`'s staff `staff` and announce it as the player does.
func _build(player: int, staff: int, count: int) -> void:
	var row: Array[StringName] = []
	for at in CARDS:
		row.append(FakeCards.id(at) if at < count else &"")
	_spells.install_staff(_caster(player), staff, _spells.compile_staff(row, _staff))
	_bus.staff_changed.emit(player, staff, _spells.staff_view(row, _staff))


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)
	_hud.step_staffs()


func _cast(player: int, staff: int) -> void:
	check(_spells.cast_staff(_caster(player), staff, Vector2.ZERO, Vector2.RIGHT, 1000.0) >= 0.0, "staff %d of player %d cast" % [staff, player])
	_hud.step_staffs()


func _wait_ready(player: int, staff: int) -> void:
	var guard: int = 0
	while _spells.cooldown_left(_caster(player), staff) > 0.0 and guard < 600:
		_tick(1)
		guard += 1


func test_no_row_for_empty_staffs() -> void:
	for staff in 4:
		_build(0, staff, 0)
	check_equal(_hud.get_panel(0).shown_rows(), 0, "four empty staffs show no row")


func test_one_staff_one_row() -> void:
	_build(1, 2, 3)
	var panel: PanelScript = _hud.get_panel(1)
	check_equal(panel.shown_rows(), 1, "one staff with cards, one row")
	check(panel.staff_row(2).visible and not panel.staff_row(0).visible, "the row is staff 3's")
	check_equal(panel.staff_row(2).card_count(), 3, "its three cards in read order")
	check_equal(panel.staff_row(2).cast_count(), 3, "three carriers are three casts")
	check_equal(_hud.get_panel(0).shown_rows(), 0, "another player's panel is untouched")


func test_four_staffs_four_rows_in_a_small_panel() -> void:
	for staff in 4:
		_build(3, staff, 2 + staff)
	var panel: PanelScript = _hud.get_panel(3)
	check_equal(panel.shown_rows(), 4, "four staffs with cards, four rows")
	var wanted: Vector2 = panel.get_combined_minimum_size()
	check(wanted.x <= 140.0 and wanted.y <= 100.0, "four rows still fit a corner of 640x360, got %s" % wanted)


func test_emptying_a_staff_hides_its_row() -> void:
	_build(0, 1, 2)
	_build(0, 1, 0)
	check_equal(_hud.get_panel(0).shown_rows(), 0, "the emptied staff's row is gone")


func test_a_long_staff_is_capped_with_a_count() -> void:
	_build(0, 0, CARDS)
	# The row learns its width when the panel lays out, on the next frame.
	await process_frame
	var row: RowScript = _hud.get_panel(0).staff_row(0)
	check(row.shown_count() > 0 and row.shown_count() < CARDS, "only the cards that fit show, got %d" % row.shown_count())
	check_equal(row.plus_text(), "+%d" % (CARDS - row.shown_count()), "the rest are counted")


func test_wasted_cards_are_marked() -> void:
	var row: RowScript = _hud.get_panel(0).staff_row(0)
	var cards: Array[StringName] = [&"a", &"b"]
	var icons: Array[Texture2D] = [null, null]
	var casts: Array[Dictionary] = [{"slots": PackedInt32Array([0, 1]), "wasted": {1: "Nothing to change."}}]
	row.set_plan({"cards": cards, "casts": casts}, icons)
	check_equal(row.card_count(), 2, "both cards show")
	check_equal(row.wasted_count(), 1, "the wasted one is greyed")


func test_the_next_cast_mark_moves_after_a_cast() -> void:
	_build(2, 1, 3)
	var row: RowScript = _hud.get_panel(2).staff_row(1)
	_hud.step_staffs()
	check_equal(row.next_cast(), 0, "the first cast is next")
	_cast(2, 1)
	check_equal(row.next_cast(), 1, "after a cast the second is next")
	_wait_ready(2, 1)
	_cast(2, 1)
	check_equal(row.next_cast(), 2, "then the third")
	_wait_ready(2, 1)
	_cast(2, 1)
	check_equal(row.next_cast(), 0, "after the last the cycle starts over")


func test_the_delay_empties() -> void:
	_build(0, 0, 2)
	var row: RowScript = _hud.get_panel(0).staff_row(0)
	_hud.step_staffs()
	check_equal(row.cooldown_fill(), 0.0, "a ready staff has nothing to wait")
	_cast(0, 0)
	check(is_equal_approx(row.cooldown_fill(), 1.0), "full right after a cast, got %s" % row.cooldown_fill())
	check(not row.is_recharging(), "a cast before the last is a plain delay")
	var total: float = _spells.cooldown_left(_caster(0), 0)
	_tick(roundi(total * 0.5 / DT))
	check(row.cooldown_fill() > 0.3 and row.cooldown_fill() < 0.7, "about half way, got %s" % row.cooldown_fill())
	_wait_ready(0, 0)
	_hud.step_staffs()
	check_equal(row.cooldown_fill(), 0.0, "empty again when ready")


func test_the_recharge_reads_apart() -> void:
	_build(1, 3, 2)
	var row: RowScript = _hud.get_panel(1).staff_row(3)
	_cast(1, 3)
	_wait_ready(1, 3)
	_cast(1, 3)
	check(row.is_recharging(), "the delay after the last cast is the recharge")
	check(is_equal_approx(row.cooldown_fill(), 1.0), "and it starts full")
	_wait_ready(1, 3)
	_hud.step_staffs()
	check(not row.is_recharging(), "the recharge ends when the staff is ready")


func test_rows_hide_while_a_menu_is_open() -> void:
	_build(0, 0, 2)
	_hud.ui_focus.opened.emit(0)
	check_equal(_hud.get_panel(0).shown_rows(), 0, "the builder shows the staffs; the rows step aside")
	check_equal(_hud.get_panel(0).status_text(), "MENU", "the menu word shows")
	_hud.ui_focus.closed.emit(0)
	check_equal(_hud.get_panel(0).shown_rows(), 1, "and come back when it closes")


func test_a_player_leaving_clears_the_rows() -> void:
	_build(1, 0, 2)
	_bus.player_left.emit(1)
	_bus.player_joined.emit(1)
	check_equal(_hud.get_panel(1).shown_rows(), 0, "a rejoined player waits for their wizard's staffs")


func test_the_header_line_is_gone() -> void:
	var panel: PanelScript = _hud.get_panel(0)
	check(panel.find_child("Name", true, false) == null and panel.find_child("Spell", true, false) == null, "no P1 or Staff N line")


func test_every_rows_cards_start_at_the_same_place_whatever_the_button() -> void:
	for staff in 4:
		_build(0, staff, 2)
	var panel: PanelScript = _hud.get_panel(0)
	# One row's button gets a much wider name (a long key name on the keyboard).
	var wide: Control = panel.staff_row(2).get_node("Glyph") as Control
	wide.custom_minimum_size = Vector2(40.0, wide.custom_minimum_size.y)
	_hud.step_staffs()
	var start: float = panel.staff_row(0).cards_start()
	check(start >= 42.0, "the cards start past the widest button: %s" % start)
	for staff in 4:
		check_equal(panel.staff_row(staff).cards_start(), start, "row %d's cards line up" % staff)


## Regression (owner, 2026-10-27): after a dash's recharge the outline did not come back. Its
## delay counted down in float steps ended on a sliver (1e-7 s) for one frame, and going from that
## sliver to 0 counted as "no change", so the row was never drawn again.
func test_the_outline_comes_back_when_a_recharge_ends_on_a_sliver() -> void:
	_build(0, 0, 1)
	var row: RowScript = _hud.get_panel(0).staff_row(0)
	# The row alone is driven here: the HUD would push the real staff's timing every frame.
	_hud.set_process(false)
	row.set_timing(0, 0.0)
	await process_frame
	await process_frame
	check_equal(row.drawn_outline(), 0, "the outline is drawn on a ready staff")
	row.set_timing(0, 2.0)
	await process_frame
	await process_frame
	check_equal(row.drawn_outline(), -1, "no outline during the recharge")
	row.set_timing(0, 0.0000001)
	await process_frame
	await process_frame
	row.set_timing(0, 0.0)
	await process_frame
	await process_frame
	check_equal(row.drawn_outline(), 0, "the outline is drawn again once the staff is ready")


## A three-cast staff's row of player 0, driven by hand (the HUD would push the real staff's
## timing every frame), drawn twice so `_draw` and the cover's draw ran.
func _hand_row() -> RowScript:
	_build(0, 0, 3)
	_hud.set_process(false)
	return _hud.get_panel(0).staff_row(0)


func _show(row: RowScript, cursor: int, left: float) -> void:
	row.set_timing(cursor, left)
	await process_frame
	await process_frame


func test_the_button_style_is_the_default() -> void:
	for player in 4:
		for staff in 4:
			check(_hud.get_panel(player).staff_row(staff).style == RowScript.Style.BUTTON, "P%d staff %d shows the reload on its button" % [player + 1, staff + 1])


func test_the_button_shade_pulls_back_as_the_delay_runs() -> void:
	var row: RowScript = _hand_row()
	await _show(row, 1, 1.0)
	var full: Rect2 = row.drawn_shade()
	check(full.size.y >= 7.0, "just after a cast the glyph is shaded, got %s" % full)
	check(full.end.x <= row.cards_start(), "the shade stays on the glyph, off the cards: %s" % full)
	await _show(row, 1, 0.5)
	var half: Rect2 = row.drawn_shade()
	check(half.size.y > 2.0 and half.size.y < full.size.y, "half way it covers about half, got %s" % half)
	check_equal(half.position.y, full.position.y, "it pulls back toward the top")
	check_equal(row.drawn_outline(), 1, "the next cast keeps its gold frame during a delay")
	await _show(row, 1, 0.0)
	check_equal(row.drawn_shade(), Rect2(), "no shade on a ready staff")


func test_a_recharge_dashes_the_next_cast_on_the_button_style() -> void:
	var row: RowScript = _hand_row()
	await _show(row, 0, 2.0)
	check_equal(row.drawn_dashed(), 0, "the first cast, next after the recharge, has the dashed frame")
	check_equal(row.drawn_outline(), -1, "and no solid one")
	check(row.drawn_shade().size.y > 0.0, "the glyph is shaded too")
	await _show(row, 0, 0.0)
	check_equal(row.drawn_dashed(), -1, "the dashes go when it is ready")
	check_equal(row.drawn_outline(), 0, "and the solid frame is back")


func test_the_next_cast_style_shades_the_next_cast() -> void:
	var row: RowScript = _hand_row()
	_hud.get_pause_menu().reload_style_changed.emit(false)
	check(row.style == RowScript.Style.NEXT_CAST, "the pause menu's switch reaches the row")
	await _show(row, 1, 1.0)
	var start: float = row.cards_start()
	# One card per cast: cast 1's frame starts one frame and one gap after the first.
	var second: float = start + RowScript.ICON_STEP + 1.0 + RowScript.CAST_GAP
	var shade: Rect2 = row.drawn_shade()
	check(shade.position.x > second and shade.end.x < second + RowScript.ICON_STEP + 1.0, "the shade is inside the next cast's frame, got %s from %s" % [shade, second])
	check(shade.size.x >= RowScript.ICON - 1.0, "and covers it just after a cast")
	check((row.get_node("Glyph") as CanvasItem).modulate != Color.WHITE, "the glyph greys while the staff waits")
	await _show(row, 1, 0.5)
	check(row.drawn_shade().size.x < shade.size.x and is_equal_approx(row.drawn_shade().end.x, shade.end.x), "it pulls back from the left, got %s" % row.drawn_shade())
	await _show(row, 0, 2.0)
	var cycle: Rect2 = row.drawn_shade()
	check(cycle.position.x < second and cycle.end.x > second + RowScript.ICON_STEP, "a recharge shades the whole cycle, got %s" % cycle)
	check(row.drawn_outline() == -1 and row.drawn_dashed() == -1, "with no gold frame")
	await _show(row, 0, 0.0)
	check_equal(row.drawn_shade(), Rect2(), "no shade on a ready staff")
	check_equal((row.get_node("Glyph") as CanvasItem).modulate, Color.WHITE, "and the glyph is lit again")
	_hud.get_pause_menu().reload_style_changed.emit(true)
	check(row.style == RowScript.Style.BUTTON, "and the switch goes back")


func test_a_rim_marks_the_staff_ready_for_a_few_frames() -> void:
	var row: RowScript = _hand_row()
	row.set_timing(1, 0.3)
	check(not row.is_rimmed(), "no rim while waiting")
	row.set_timing(1, 0.0)
	check(row.is_rimmed(), "the rim shows when the staff is ready")
	for i in RowScript.RIM_FRAMES:
		row.set_timing(1, 0.0)
	check(not row.is_rimmed(), "and goes after a few frames")
