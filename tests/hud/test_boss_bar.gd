extends "res://tests/support/suite.gd"
## The boss bar and the entrance banner (boss plan OB16, hud/panels/boss/): both show only what the
## bus says (`boss_shown`, `boss_health_changed`, `boss_hidden`). The bar, at the top middle for
## everyone while a boss is in play, shows its name, its health and a notch at each phase's mark (dim
## once passed), the first boss shown while there are two, and nothing once it is hidden or the run
## ends; it fits between the top corner panels. The banner shows its name and lore over play for a
## few seconds, fading in and out, stopping nothing. The bodies that send it are tested in
## tests/gameplay/actor/test_boss_presence.gd.
##
## godot --headless --path . --script res://tests/hud/test_boss_bar.gd

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const BossBarScript := preload("res://hud/panels/boss/boss_bar.gd")
const BossBannerScript := preload("res://hud/panels/boss/boss_banner.gd")
## Loaded when needed, not preloaded: the scene is also the "Hud" autoload (see test_panels.gd).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const NO_SAVE: String = "user://test_no_save.cfg"
## The widest a corner panel may be (test_panels.gd's bound), and the view's width.
const PANEL_MOST: float = 140.0
const VIEW_WIDTH: float = 640.0
const MARKS: PackedFloat32Array = [0.6, 0.25]

var hud: HudScript
var bus: EventsScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	var focus: UIFocusScript = own(UIFocusScript.new()) as UIFocusScript
	hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	hud.events = bus
	hud.save = SaveFile.new(NO_SAVE)
	hud.ui_focus = focus
	root.add_child(hud)


func after_each() -> void:
	hud.free()


func test_nothing_shows_with_no_boss() -> void:
	check(not hud.get_boss_bar().visible, "no bar")
	check(not hud.get_boss_banner().visible, "no banner")


func test_a_boss_shown_fills_the_bar_and_its_health_follows() -> void:
	var bar: BossBarScript = hud.get_boss_bar()
	bus.boss_shown.emit(7, "The Test Boss", "A line.", MARKS)
	bus.boss_health_changed.emit(7, 400.0, 400.0)
	check(bar.visible, "the bar shows")
	check_equal(bar.shown_boss(), 7, "of this boss")
	check_equal(bar.shown_name(), "The Test Boss", "its name")
	check_equal(bar.shown_marks(), MARKS, "a mark at each phase")
	check_equal(bar.shown_share(), 1.0, "full")
	bus.boss_health_changed.emit(7, 100.0, 400.0)
	check_equal(bar.shown_share(), 0.25, "a quarter")
	bus.boss_health_changed.emit(3, 1.0, 400.0)
	check_equal(bar.shown_share(), 0.25, "another actor's health is not its")
	bus.boss_hidden.emit(7)
	check(not bar.visible, "hidden with it")
	check_equal(bar.shown_boss(), -1, "none")


func test_with_two_bosses_the_first_shows_until_it_goes() -> void:
	var bar: BossBarScript = hud.get_boss_bar()
	bus.boss_shown.emit(4, "First", "", PackedFloat32Array())
	bus.boss_health_changed.emit(4, 50.0, 100.0)
	bus.boss_shown.emit(9, "Second", "", PackedFloat32Array([0.5]))
	bus.boss_health_changed.emit(9, 30.0, 40.0)
	check_equal(bar.shown_name(), "First", "the first shown")
	check_equal(bar.shown_share(), 0.5, "with its own health")
	bus.boss_hidden.emit(4)
	check_equal(bar.shown_name(), "Second", "then the next")
	check_equal(bar.shown_share(), 0.75, "with the health told of it meanwhile")
	check_equal(bar.shown_marks(), PackedFloat32Array([0.5]), "and its marks")


func test_a_run_ending_or_starting_clears_both() -> void:
	bus.boss_shown.emit(7, "The Test Boss", "A line.", MARKS)
	bus.run_ended.emit(false)
	check(not hud.get_boss_bar().visible, "no bar after the run")
	check(not hud.get_boss_banner().visible, "no banner after the run")
	bus.boss_shown.emit(7, "The Test Boss", "A line.", MARKS)
	bus.run_started.emit(1)
	check(not hud.get_boss_bar().visible, "none as a run starts")


func test_the_banner_shows_its_name_and_lore_and_fades() -> void:
	var banner: BossBannerScript = hud.get_boss_banner()
	bus.boss_shown.emit(7, "The Test Boss", "It was made for this test.", MARKS)
	check(banner.visible and banner.is_showing(), "the banner shows")
	check_equal(banner.shown_name(), "The Test Boss", "its name")
	check_equal(banner.shown_lore(), "It was made for this test.", "its lore line")
	check_equal(banner.modulate.a, 0.0, "fading in from nothing")
	banner.step(BossBannerScript.FADE_IN)
	check_equal(banner.modulate.a, 1.0, "then full")
	banner.step(BossBannerScript.HOLD + BossBannerScript.FADE_OUT * 0.5)
	check(banner.modulate.a < 1.0 and banner.visible, "fading out after its hold")
	banner.step(BossBannerScript.FADE_OUT)
	check(not banner.visible and not banner.is_showing(), "then gone")
	check(hud.get_boss_bar().visible, "the bar stays")
	check_equal(banner.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it takes no input")


func test_the_banner_spans_the_view_in_its_upper_middle() -> void:
	var banner: BossBannerScript = hud.get_boss_banner()
	bus.boss_shown.emit(7, "The Test Boss", "It was made for this test.", MARKS)
	await process_frame
	var view: Vector2 = banner.get_parent_area_size()
	check_equal(banner.size.x, view.x, "as wide as the view, so its lines are centred and never squeezed")
	check(is_equal_approx(banner.position.y, view.y * BossBannerScript.DROP), "its top in the upper middle, got %s" % banner.position.y)
	check(banner.size.y < view.y * 0.3, "a band, got %s" % banner.size.y)


func test_a_boss_with_no_lore_shows_its_name_alone() -> void:
	var banner: BossBannerScript = hud.get_boss_banner()
	bus.boss_shown.emit(7, "Nameless", "", PackedFloat32Array())
	check_equal(banner.shown_name(), "Nameless", "its name")
	check(not (banner.get_node("Lore") as Label).visible, "no empty lore line")


func test_the_bar_fits_between_the_top_corner_panels() -> void:
	var bar: BossBarScript = hud.get_boss_bar()
	bus.boss_shown.emit(7, "The Test Boss", "", MARKS)
	check_equal(bar.anchor_left, 0.5, "anchored to the middle")
	check_equal(bar.grow_horizontal, Control.GROW_DIRECTION_BOTH, "and grows both ways")
	var wide: float = bar.get_combined_minimum_size().x
	check(wide <= VIEW_WIDTH - 2.0 * (HudScript.EDGE_MARGIN + PANEL_MOST), "it fits between the corner panels, got %s" % wide)
	check(bar.get_combined_minimum_size().y <= 24.0, "a thin band, got %s" % bar.get_combined_minimum_size().y)
	check(bar.mouse_filter == Control.MOUSE_FILTER_IGNORE, "it takes no input")
