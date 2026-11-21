extends "res://tests/support/suite.gd"
## Tests for the corner panels drawn once (`hud/widgets/cached_view.gd`; the owner, 2026-11-21):
## a panel's content is drawn into its picture again on exactly the frames something on it changed,
## never left stale, and not at all while nothing changes.
##
## - Everything a panel shows but its backing is in its picture, and every canvas item there is
##   watched, the ones added later too (a structural guard: a new widget on the panel is covered by
##   itself, and nothing draws live beside the picture).
## - An idle panel is not drawn again, while the HUD steps its staffs every frame.
## - Every change the panel shows draws it again: each of the panel's setters, a cast's cooldown
##   sweep frame by frame, a fizzle, the reload style, a staff's mana, a key's play, a quick-use
##   slot bound and recharging, the menu word, online, a seat waiting to join, a reset, a resize;
##   and over all of those, any frame on which a canvas item's look changed without a draw (its
##   visibility, modulate, place, size, z or material) must have drawn the picture again too.
## - A hidden panel draws nothing; a change meanwhile is drawn as it shows.
## - The content is drawn in a picture the screen's size at the panel's own place, follows the
##   panel, and can be drawn live again (the screenshots' comparison).
##
## The HUD runs on its own bus with the real `Spells`, as `test_staff_strip.gd`'s.
const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const PanelScript := preload("res://hud/panels/player_panel/player_panel.gd")
const RowScript := preload("res://hud/panels/player_panel/staff_row.gd")
const CachedViewScript := preload("res://hud/widgets/cached_view.gd")
const FakeCards := preload("res://tests/support/fake_cards.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const NO_SAVE: String = "user://test_no_save.cfg"
const ICON_PATH: String = "res://icon.svg"

const DT: float = 1.0 / 60.0
const CARDS: int = 8
const FIRST_WIZARD: int = 3

var _bus: EventsScript
var _spells: SpellsScript
var _mgr: ManagerScript
var _hud: HudScript
var _staff: StaffBase
## The frames a look changed with no picture drawn again (`_frames`), as messages.
var _stale: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_mgr.actors = own(ActorSeats.table(4, FIRST_WIZARD)) as ActorSeats.ActorsScript
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = own(FakeCards.registry(CARDS, &"carrier"))
	_spells.bind(_mgr, _bus)
	_staff = StaffBase.new()
	_staff.slots = CARDS
	_staff.cooldown = 0.5
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = own(UIFocusScript.new()) as UIFocusScript
	_hud.spells = _spells
	root.add_child(_hud)
	own(_hud)
	_bus.player_joined.emit(0)
	_bus.room_entered.emit(&"arena_01", 0)
	_stale.clear()


func _panel() -> PanelScript:
	return _hud.get_panel(0)


func _cache() -> CachedViewScript:
	return _panel().cache()


func _build(staff: int, count: int) -> void:
	var row: Array[StringName] = []
	for at in CARDS:
		row.append(FakeCards.id(at) if at < count else &"")
	_spells.install_staff(_mgr.actors.home_of_seat(0), staff, _spells.compile_staff(row, _staff))
	_bus.staff_changed.emit(0, staff, _spells.staff_view(row, _staff))


## Every canvas item of the content, with what of its look a draw does not tell.
func _looks() -> Dictionary[CanvasItem, String]:
	var out: Dictionary[CanvasItem, String] = {}
	var stack: Array[Node] = [_cache().content()]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var item := node as CanvasItem
		if item == null:
			continue
		var rect: String = ""
		var control := item as Control
		if control != null:
			rect = str(control.get_global_rect())
		out[item] = "%s %s %s %s %d %s %s" % [item.visible, item.modulate, item.self_modulate, rect, item.z_index, item.material, item.texture_filter]
	return out


## Steps `count` frames of the real loop (the HUD's own `_process` steps its staffs), the
## simulation stepped by hand, and notes a frame whose looks changed with no picture drawn.
func _frames(count: int, what: String) -> void:
	for frame in count:
		var before: Dictionary[CanvasItem, String] = _looks()
		# A change told before this frame's snapshot is laid out in this frame: drawn this frame too.
		var since: int = Engine.get_process_frames()
		_mgr.step(DT)
		_spells.step(DT)
		await process_frame
		var after: Dictionary[CanvasItem, String] = _looks()
		if _cache().drawn_frame() >= since:
			continue
		for item: CanvasItem in after:
			if not before.has(item) or before[item] != after[item]:
				_stale.append("%s, frame %d: %s changed with no picture drawn" % [what, frame, item.name])


## Applies `change` and checks that the picture is drawn again within a frame or two.
func _redraws(what: String, change: Callable) -> void:
	await process_frame
	var drawn: int = _cache().refreshes
	change.call()
	await process_frame
	await process_frame
	check(_cache().refreshes > drawn, "%s draws the panel's picture again" % what)


func test_everything_but_the_backing_is_in_the_picture_and_watched() -> void:
	await process_frame
	var panel: PanelScript = _panel()
	var cache: CachedViewScript = _cache()
	check(cache != null and cache.get_parent() == panel, "the panel holds its picture")
	for child in panel.get_children():
		check(child == cache, "nothing of the panel draws live beside its picture: %s" % child.name)
	check(cache.view().render_target_update_mode != SubViewport.UPDATE_ALWAYS, "the picture is not drawn every frame")
	_build(0, 3)
	panel.set_quick(0, load(ICON_PATH) as Texture2D, 2, true)
	await process_frame
	var items: int = 0
	var stack: Array[Node] = [cache.content()]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var item := node as CanvasItem
		if item == null:
			continue
		items += 1
		check(item.draw.is_connected(cache.mark), "%s's draws are watched" % item.name)
		check(item.visibility_changed.is_connected(cache.mark), "%s's showing is watched" % item.name)
		if item is Control:
			check((item as Control).item_rect_changed.is_connected(cache.mark), "%s's place is watched" % item.name)
		var shader_material := item.material as ShaderMaterial
		if shader_material != null and shader_material.shader != null:
			check(not shader_material.shader.code.contains("TIME"), "%s's shader changes by itself (TIME): drawn once it would stop" % item.name)
	check(items > 10, "the panel's widgets are in the picture (%d)" % items)


func test_an_idle_panel_is_not_drawn_again() -> void:
	_build(0, 3)
	_build(1, 2)
	_bus.staff_mana_changed.emit(0, 0, 50.0, 100.0)
	_panel().set_quick(1, load(ICON_PATH) as Texture2D, 3, true)
	_panel().set_stats(80.0, 100.0)
	for _frame in 20:
		await process_frame
	var drawn: int = _cache().refreshes
	check(drawn > 0, "the picture was drawn")

	for _frame in 30:
		# The same numbers told again every frame, as the HUD does: nothing new to draw.
		_panel().set_stats(80.0, 100.0)
		_panel().set_staff_mana(0, 50.0, 100.0)
		_panel().set_quick_recharge(1, 0.0, 1.0)
		await process_frame
	check_equal(_cache().refreshes, drawn, "30 frames with nothing new draw the picture no more")


func test_every_change_the_panel_shows_draws_it_again() -> void:
	var panel: PanelScript = _panel()
	var icon: Texture2D = load(ICON_PATH) as Texture2D
	await _redraws("a staff's plan", func() -> void: _build(0, 3))
	await _redraws("a second staff", func() -> void: _build(2, 5))
	await _redraws("the health", func() -> void: panel.set_stats(60.0, 100.0))
	await _redraws("a staff's mana", func() -> void: panel.set_staff_mana(0, 30.0, 100.0))
	await _redraws("the purse", func() -> void: panel.set_purse(12, 1))
	await _redraws("a key", func() -> void: panel.set_keys(1, false))
	await _redraws("a reroll", func() -> void: panel.set_rerolls(2, true))
	await _redraws("a quick-use binding", func() -> void: panel.set_quick(2, icon, 4, false))
	await _redraws("a quick-use recharge", func() -> void: panel.set_quick_recharge(2, 0.5, 1.0, true))
	await _redraws("a fizzle", func() -> void: panel.staff_fizzled(0))
	await _redraws("the reload style", func() -> void: panel.set_reload_style(RowScript.Style.NEXT_CAST))
	await _redraws("online", func() -> void: panel.set_online(true))
	await _redraws("a seat held from joining", func() -> void: panel.set_join_held(true))
	await _redraws("the hold let go", func() -> void: panel.set_join_held(false))
	await _redraws("the menu open", func() -> void: panel.set_menu_open(true))
	await _redraws("the menu shut", func() -> void: panel.set_menu_open(false))
	await _redraws("down", func() -> void: panel.set_stats(0.0, 100.0))
	await _redraws("a cast", func() -> void: _spells.cast_staff(_mgr.actors.home_of_seat(0), 0, Vector2.ZERO, Vector2.RIGHT, 1000.0))
	await _redraws("a reset", func() -> void: panel.reset())
	await _redraws("the staffs cleared", func() -> void: panel.clear_staffs())


func test_no_frame_of_a_change_is_left_stale() -> void:
	var panel: PanelScript = _panel()
	var icon: Texture2D = load(ICON_PATH) as Texture2D
	_build(0, 3)
	_build(1, 6)
	_bus.staff_mana_changed.emit(0, 0, 100.0, 100.0)
	await _frames(5, "laid out")
	var caster: int = _mgr.actors.home_of_seat(0)
	_spells.cast_staff(caster, 0, Vector2.ZERO, Vector2.RIGHT, 1000.0)
	panel.set_stats(40.0, 100.0)
	panel.set_staff_mana(0, 20.0, 100.0)
	panel.set_keys(1, false)
	panel.set_quick(0, icon, 2, false)
	panel.set_quick_recharge(0, 1.0, 1.0)
	# The cooldown's sweep, the lines easing, the key sliding in and the slot's icon coming in, frame
	# by frame: every frame a look changes is drawn.
	await _frames(40, "a cast's cooldown and the plays")
	panel.set_reload_style(RowScript.Style.NEXT_CAST)
	_spells.cast_staff(caster, 1, Vector2.ZERO, Vector2.RIGHT, 1000.0)
	panel.set_keys(0, false)
	await _frames(40, "the next-cast style and the key leaving")
	panel.set_menu_open(true)
	await _frames(3, "the menu")
	panel.set_menu_open(false)
	panel.set_online(true)
	await _frames(3, "online")
	check(_stale.is_empty(), "no look changed without the picture drawn again:\n%s" % "\n".join(_stale))


func test_a_hidden_picture_draws_its_change_as_it_shows() -> void:
	# A picture of its own (the HUD shows and hides its panels by itself every frame).
	var cache: CachedViewScript = CachedViewScript.new()
	var view := SubViewport.new()
	var label := Label.new()
	label.text = "12"
	view.add_child(label)
	cache.add_child(view)
	root.add_child(cache)
	own(cache)
	await process_frame
	await process_frame
	cache.visible = false
	await process_frame
	var drawn: int = cache.refreshes
	label.text = "13"
	await process_frame
	await process_frame
	check_equal(cache.refreshes, drawn, "hidden, it draws nothing")
	check(cache.is_dirty(), "the change waits")
	cache.visible = true
	await process_frame
	check(cache.refreshes > drawn and not cache.is_dirty(), "shown, the change is drawn")


func test_a_change_after_the_frame_is_drawn_is_drawn_the_next_frame() -> void:
	# The review's: a change told after this frame's render (a `frame_post_draw` callback, as the
	# screenshots' `grab`) asks for the next frame's picture, never lost to a frame already asked.
	var cache: CachedViewScript = CachedViewScript.new()
	var view := SubViewport.new()
	var box := VBoxContainer.new()
	var a := Label.new()
	a.text = "a"
	var b := Label.new()
	b.text = "b"
	box.add_child(a)
	box.add_child(b)
	view.add_child(box)
	cache.add_child(view)
	root.add_child(cache)
	own(cache)
	await process_frame
	await process_frame
	# A mark this frame; then, as the renderer does once it drew the picture, the asking undone (a
	# headless run has no `frame_post_draw` to wait for); then a change in that same process frame.
	cache.mark()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	b.visible = false
	check_equal(view.render_target_update_mode, SubViewport.UPDATE_ONCE, "a mark after the render asks for the picture again")
	check(not cache.is_dirty(), "and nothing is left waiting")


func test_the_content_is_drawn_where_the_panel_is() -> void:
	_build(0, 6)
	_build(1, 2)
	await process_frame
	await process_frame
	var cache: CachedViewScript = _cache()
	var content: Control = cache.content()
	check_equal(content.position, cache.get_global_transform_with_canvas().origin, "the content is drawn at the panel's own place on the screen")
	check_equal(content.size, cache.size, "the content takes the panel's room")
	check_equal(cache.view().size, Vector2i(cache.get_viewport().get_visible_rect().size), "in a picture the screen's size, so it lands where it did drawn live")
	check_equal(cache.get_combined_minimum_size(), content.get_combined_minimum_size(), "the panel is as big as its content asks")
	var panel: PanelScript = _panel()
	# The HUD puts its panels in their corners every frame: held still, so the move stays.
	_hud.set_process(false)
	var was: Vector2 = content.position
	await _redraws("the panel moved", func() -> void: panel.position += Vector2(0, 20))
	check_equal(content.position, was + Vector2(0, 20), "the content follows the panel")
	_hud.set_process(true)
	cache.set_live(true)
	await process_frame
	check(cache.is_live() and content.get_parent() == cache and content.position == Vector2.ZERO, "drawn live, the content is the panel's child again")
	cache.set_live(false)
	await process_frame
	check(not cache.is_live() and content.get_parent() == cache.view(), "and back in its picture")
	var wide: Vector2 = cache.size
	_build(2, CARDS)
	await _redraws("a third, longer staff", func() -> void: _build(3, CARDS))
	check(cache.size.y > wide.y, "the panel grew for the rows: %s to %s" % [wide, cache.size])
	check_equal(content.size, cache.size, "and the content with it")


func test_a_cooldown_draws_the_live_layer_only_as_its_shade_moves_a_pixel_and_never_stale() -> void:
	_build(0, 3)
	_bus.staff_mana_changed.emit(0, 0, 100.0, 100.0)
	for _frame in 4:
		await process_frame
	var row: RowScript = _panel().staff_row(0)
	check(row.live, "the row's shade and mana line are drawn live over the picture")
	var caster: int = _mgr.actors.home_of_seat(0)
	check(_spells.cast_staff(caster, 0, Vector2.ZERO, Vector2.RIGHT, 1000.0) >= 0.0, "the staff cast")
	var frames: int = 0
	var pictures: int = _cache().refreshes
	var live_draws: Array[int] = [0]
	var own_draws: Array[int] = [0]
	_panel().live_layer().draw.connect(func() -> void: live_draws[0] += 1)
	(row.get_node("Cover") as CanvasItem).draw.connect(func() -> void: own_draws[0] += 1)
	row.mana_line().draw.connect(func() -> void: own_draws[0] += 1)
	while _spells.cooldown_left(caster, 0) > 0.0 and frames < 120:
		_mgr.step(DT)
		_spells.step(DT)
		await process_frame
		frames += 1
	await process_frame
	var after: int = _cache().refreshes
	check(frames > 10, "the cooldown ran %d frames" % frames)
	# The shade is 8 px tall inside the glyph: a step a pixel, and the ready rim's start and end.
	check(live_draws[0] >= 2 and live_draws[0] <= 11 and live_draws[0] < frames, "the live layer drew %d times of %d frames: only as the shade moved a pixel" % [live_draws[0], frames])
	check_equal(own_draws[0], 0, "the cover and the mana line draw nothing in the picture")
	check(after - pictures <= 3, "the picture was drawn again %d times in the cooldown (the cast's mark, not the sweep)" % (after - pictures))
	# Again, each frame against what the row would draw now from scratch: no skipped draw leaves a
	# stale shade.
	for _frame in 20:
		await process_frame
	check(_spells.cast_staff(caster, 0, Vector2.ZERO, Vector2.RIGHT, 1000.0) >= 0.0, "the staff cast again")
	var checked: int = 0
	while _spells.cooldown_left(caster, 0) > 0.0 and checked < 120:
		_mgr.step(DT)
		_spells.step(DT)
		await process_frame
		await process_frame
		checked += 1
		var shown: Rect2 = row.drawn_shade()
		var outline: int = row.drawn_outline()
		var dashed: int = row.drawn_dashed()
		row.call(&"_redraw_all")
		await process_frame
		check_equal(row.drawn_shade(), shown, "frame %d: the shade shown is the one it would draw" % checked)
		check_equal(row.drawn_outline(), outline, "frame %d: so is the outline" % checked)
		check_equal(row.drawn_dashed(), dashed, "frame %d: and the dashed one" % checked)
	after = _cache().refreshes
	var drew: int = live_draws[0]
	_panel().set_staff_mana(0, 40.0, 100.0)
	for _frame in 6:
		await process_frame
	check(live_draws[0] > drew, "the mana line easing draws the live layer")
	check_equal(_cache().refreshes, after, "and not the picture")


func test_nothing_in_the_panel_lies_past_its_picture_s_pad() -> void:
	# The picture is drawn back over the panel's rect and PAD round it: a part laid out past that
	# would be cut off.
	_build(0, CARDS)
	_build(1, 3)
	_panel().set_keys(3, true)
	_panel().set_rerolls(2, true)
	_panel().set_purse(99, 9)
	_panel().set_online(true)
	_panel().set_quick(0, load(ICON_PATH) as Texture2D, 12, true)
	for _frame in 4:
		await process_frame
	var cache: CachedViewScript = _cache()
	var content: Control = cache.content()
	var room := Rect2(content.get_global_rect().position, cache.size).grow(CachedViewScript.PAD)
	for item in content.find_children("*", "Control", true, false):
		var control := item as Control
		if control.is_visible_in_tree():
			check(room.encloses(control.get_global_rect()), "%s at %s lies inside the picture %s" % [control.name, control.get_global_rect(), room])


func test_the_next_cast_style_s_delay_draws_the_live_layer_only_and_never_stale() -> void:
	# The owner's answer on #905: the shade over the next cast is the live layer's too, so a delay
	# keeps the picture as it is. Staff 1 is short (it never slides): the picture's redraws are
	# counted on it. Staff 0 is long, so the arrows (drawn over that shade) and its slides are
	# checked against draws from scratch.
	_build(0, CARDS)
	_build(1, 3)
	_panel().set_reload_style(RowScript.Style.NEXT_CAST)
	for _frame in 4:
		await process_frame
	var caster: int = _mgr.actors.home_of_seat(0)
	var short_row: RowScript = _panel().staff_row(1)
	var pictures: int = _cache().refreshes
	var live_draws: Array[int] = [0]
	_panel().live_layer().draw.connect(func() -> void: live_draws[0] += 1)
	var frames: int = 0
	var casts: int = 0
	var shaded: int = 0
	while casts < 4 and frames < 300:
		if _spells.cooldown_left(caster, 1) <= 0.0:
			check(_spells.cast_staff(caster, 1, Vector2.ZERO, Vector2.RIGHT, 1000.0) >= 0.0, "cast %d" % casts)
			casts += 1
		_mgr.step(DT)
		_spells.step(DT)
		await process_frame
		frames += 1
		if short_row.drawn_shade().size.x > 0.0:
			shaded += 1
	check(shaded > 10, "the short staff's cards were shaded on %d frames" % shaded)
	check(live_draws[0] > casts, "the live layer drew the shade (%d times)" % live_draws[0])
	check(_cache().refreshes - pictures <= casts * 3, "the picture was drawn again %d times in %d frames of %d casts: for the casts, not the shade" % [_cache().refreshes - pictures, frames, casts])
	# The long staff through its cycle and recharge, each frame against a draw from scratch, the HUD
	# held still meanwhile (its own step would slide the strip on).
	var row: RowScript = _panel().staff_row(0)
	casts = 0
	frames = 0
	while casts < CARDS + 1 and frames < 600:
		if _spells.cooldown_left(caster, 0) <= 0.0:
			check(_spells.cast_staff(caster, 0, Vector2.ZERO, Vector2.RIGHT, 1000.0) >= 0.0, "cast %d" % casts)
			casts += 1
		_mgr.step(DT)
		_spells.step(DT)
		await process_frame
		frames += 1
		if frames % 3 != 0:
			continue
		var shown: Rect2 = row.drawn_shade()
		_hud.set_process(false)
		row.call(&"_redraw_all")
		await process_frame
		check_equal(row.drawn_shade(), shown, "frame %d: the shade shown is the one it would draw" % frames)
		_hud.set_process(true)
