extends "res://tests/support/suite.gd"
## The d-pad's quick-use slots through the HUD (the owner, 2026-11-20: "each D-pad direction can be
## bound to a usable item"): in the inventory's potions ring a d-pad arm binds the potion pointed at
## (its arm's glyph beside it, "Bind" on the hint row), again lets it go; in play the arm drinks one
## (a command), the corner panel's cross shows each bound item's icon and count, greyed with none
## left and full again as one is taken; while the Y map is held the d-pad moves the teleport pick and
## drinks nothing, and A teleports. The wizard is real (the real registry and spell runtime).
const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const InventoryScript := preload("res://hud/menus/inventory/inventory_menu.gd")
const QuickCrossScript := preload("res://hud/widgets/quick_cross.gd")
const MapLegendScript := preload("res://hud/panels/map_legend.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const NO_SAVE: String = "user://test_no_save.cfg"

const STEP: float = 0.0625
const POTIONS: StringName = &"potions"

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
var _world: WizardFixture
var _wizard: Actor
## Every map_teleport_requested [player, room] and quick_use_requested [player, slot].
var _teleports: Array = []
var _uses: Array = []


func before_each() -> void:
	_world = WizardFixture.new(root)
	own(_world.registry)
	_bus = own(_world.bus) as EventsScript
	_input = own(_world.input) as InputManagerScript
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	own(_world.projectiles)
	own(_world.spells)
	own(_world.combat)
	own(_world.table)
	own(_world.frames)
	_teleports.clear()
	_uses.clear()
	_bus.map_teleport_requested.connect(func(player: int, room: int) -> void: _teleports.append([player, room]))
	_bus.quick_use_requested.connect(func(player: int, slot: int) -> void: _uses.append([player, slot]))
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = _world.spells
	root.add_child(_hud)
	_input.add_virtual_device(0)
	_wizard = own(_world.wizard(0, Vector2.ZERO)) as Actor
	_bus.player_joined.emit(0)
	_bus.room_entered.emit(&"test_room", 0)


func _tap(action: StringName) -> void:
	_input.send_virtual(0, action, 1.0)
	_input.send_virtual(0, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()
	_hud.get_inventory(0).step(STEP)
	_world.step_one(_wizard)
	var cross: QuickCrossScript = _cross()
	for _step in 4:
		if cross.is_moving():
			cross.advance()


func _cross() -> QuickCrossScript:
	return _hud.get_panel(0).quick_cross()


func _open_potions() -> InventoryScript:
	var inventory: InventoryScript = _hud.get_inventory(0)
	_tap(&"inventory")
	_frame()
	_input.send_virtual_aim(0, inventory.menu().direction_to(inventory.entry_of("bag", POTIONS)))
	_frame()
	_tap(&"accept")
	_frame()
	_input.send_virtual_aim(0, Vector2.ZERO)
	_frame()
	check_equal(inventory.layer(), InventoryScript.Layer.ITEMS, "the potions ring")
	return inventory


func _point(inventory: InventoryScript, id: StringName) -> void:
	_input.send_virtual_aim(0, inventory.menu().direction_to(inventory.entry_of("item", id)))
	_frame()


func test_a_dpad_arm_in_the_inventory_binds_the_potion_pointed_at() -> void:
	check(_wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 2)), "two healing potions")
	check(_wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"max_health", 1)), "a max health potion")
	check_equal([_wizard.inventory.quick_id(0), _wizard.inventory.quick_id(1)], [&"healing", &"max_health"], "taken, each filled a free arm (the owner, 2026-11-20)")
	_wizard.inventory.bind_quick(0, POTIONS, &"")
	_wizard.inventory.bind_quick(1, POTIONS, &"")
	_frame()
	var inventory: InventoryScript = _open_potions()
	_point(inventory, &"healing")
	check(inventory.hint_verbs().has("Bind"), "the hint row says Bind")
	_tap(&"quick_up")
	_frame()
	_frame()
	check_equal(_wizard.inventory.quick_id(0), &"healing", "up: bound to the healing potion")
	var glyph := inventory.find_child("RingQuick0", true, false) as Control
	check(glyph != null and glyph.visible, "up's glyph beside it on the ring")
	_point(inventory, &"max_health")
	_tap(&"quick_up")
	_frame()
	_frame()
	check_equal([_wizard.inventory.quick_id(0), _wizard.inventory.quick_id(1)], [&"max_health", &""], "another potion on up takes its place")
	_tap(&"quick_right")
	_frame()
	_frame()
	check_equal([_wizard.inventory.quick_id(0), _wizard.inventory.quick_id(1)], [&"", &"max_health"], "right: it moved off up")
	_tap(&"quick_right")
	_frame()
	_frame()
	check_equal(_wizard.inventory.quick_id(1), &"", "on its own arm again: let go")
	check(_uses.is_empty(), "nothing drunk from inside the menu")


func test_in_play_an_arm_drinks_one_and_the_panel_shows_it() -> void:
	check(_wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 1)), "one healing potion")
	check_equal(_wizard.inventory.bind_quick(2, POTIONS, &"healing"), Inventory.Refusal.NONE, "on down")
	_frame()
	_frame()
	var cross: QuickCrossScript = _cross()
	check(cross.is_bound(2) and not cross.is_bound(0), "the panel's cross: down bound, up not")
	check_equal([cross.stage_of(2), cross.count_of(2), cross.cross_stage()], [QuickCrossScript.FULL, 1, QuickCrossScript.CROSS_STAGES], "its icon and its count, the cross in")
	check_equal(cross.stage_of(0), QuickCrossScript.FRAMED, "an unbound arm an empty cell")
	_world.hurt(_wizard, 50)
	_tap(&"quick_down")
	_frame()
	_frame()
	check_equal(_uses, [[0, 2]], "the press asks once")
	check_equal(_wizard.health.health, 80.0, "drunk: healed")
	check_equal(_wizard.inventory.quick_id(2), &"healing", "none left, the binding stays")
	check_equal([cross.stage_of(2), cross.count_of(2)], [QuickCrossScript.SHADOW, 0], "greyed with 0")
	check(_wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 1)), "another picked up")
	_frame()
	_frame()
	check_equal([cross.stage_of(2), cross.count_of(2)], [QuickCrossScript.FULL, 1], "full again")
	_wizard.inventory.bind_quick(2, POTIONS, &"healing")
	for _step in 12:
		_frame()
	check_equal(cross.cross_stage(), 0, "nothing bound: the cross goes")
	check_equal(cross.custom_minimum_size, Vector2.ZERO, "and takes no room")


func test_the_cross_steps_in_never_jumps() -> void:
	var cross := QuickCrossScript.new()
	own(cross)
	cross.set_slot(1, PlaceholderTexture2D.new(), 3)
	var widths: Array[float] = []
	var stages: Array[int] = []
	while cross.is_moving():
		cross.advance()
		widths.append(cross.custom_minimum_size.x)
		stages.append(cross.stage_of(1))
	check(widths.size() >= QuickCrossScript.CROSS_STAGES, "it grows in steps: %s" % [widths])
	check_equal(widths[0], float(QuickCrossScript.SIDE / QuickCrossScript.CROSS_STAGES), "a third first")
	check_equal(stages.filter(func(stage: int) -> bool: return stage > 0).size() >= QuickCrossScript.SLOT_STAGES, true, "the slot through its looks: %s" % [stages])
	for at in widths.size():
		check(widths[at] == floorf(widths[at]), "whole pixels")


func test_greying_and_filling_again_pass_the_shades_between() -> void:
	var cross := QuickCrossScript.new()
	own(cross)
	var icon := PlaceholderTexture2D.new()
	cross.set_slot(0, icon, 1, true)
	check(cross.visible and cross.stage_of(0) == QuickCrossScript.FULL, "drawn as it stands")
	cross.set_slot(0, icon, 0)
	var stages: Array[int] = []
	while cross.is_moving():
		cross.advance()
		stages.append(cross.stage_of(0))
	check_equal(stages.slice(0, 3), [4, 3, 2] as Array[int], "none left: full to shadow a shade a frame (Smooth)")
	cross.set_slot(0, icon, 2)
	stages.clear()
	while cross.is_moving():
		cross.advance()
		stages.append(cross.stage_of(0))
	check_equal(stages.slice(0, 3), [3, 4, 5] as Array[int], "refilled: back through the shades")


func test_an_empty_cross_is_hidden_and_adds_no_gap() -> void:
	var panel: Control = _hud.get_panel(0)
	var plan: Dictionary = {"cards": [&"bolt"], "casts": [{"slots": PackedInt32Array([0])}]}
	var icons: Array[Texture2D] = [null]
	panel.call("set_staff_plan", 0, plan, icons)
	panel.set("visible", true)
	await process_frame
	var cross: QuickCrossScript = _cross()
	check(not cross.visible, "nothing bound: the cross is hidden")
	var staffs := panel.find_child("Staffs", true, false) as Control
	var lower := panel.find_child("Lower", true, false) as Control
	check_equal(staffs.size.x, lower.size.x, "the staff rows take the whole row: no gap for an empty cross")


func test_on_the_held_map_the_dpad_moves_the_pick_and_drinks_nothing() -> void:
	check(_wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 2)), "potions")
	_wizard.inventory.bind_quick(3, POTIONS, &"healing")
	_world.hurt(_wizard, 50)
	_bus.teleport_rooms_shown.emit(0, PackedInt32Array([0, 3]), PackedVector2Array([Vector2(500, 500), Vector2(100, 500)]))
	_frame()
	_input.send_virtual(0, &"map", 1.0)
	_frame()
	check_equal(_hud.get_map_picker().pick_of(0), 0, "held: the first room picked")
	_input.send_virtual(0, &"move_left", 1.0)
	_frame()
	check_equal(_hud.get_map_picker().pick_of(0), 0, "the left stick walks, it picks nothing")
	_input.send_virtual(0, &"move_left", 0.0)
	_tap(&"quick_left")
	_frame()
	_frame()
	check_equal(_hud.get_map_picker().pick_of(0), 3, "the d-pad's left: the room west")
	check(_uses.is_empty(), "and no potion asked for")
	check_equal(_wizard.inventory.count_of(POTIONS, &"healing"), 2, "none drunk")
	_tap(&"take")
	_frame()
	check_equal(_teleports, [[0, 3]], "A teleports there")
	_input.send_virtual(0, &"map", 0.0)
	_frame()
	_tap(&"quick_left")
	_frame()
	_frame()
	check_equal(_uses, [[0, 3]], "the map let go: the same arm drinks")
	check_equal(_wizard.inventory.count_of(POTIONS, &"healing"), 1, "one drunk")


func test_the_legend_rises_under_an_open_frame_while_picking() -> void:
	var legend: MapLegendScript = _hud.get_map_legend()
	_bus.teleport_rooms_shown.emit(0, PackedInt32Array([0]), PackedVector2Array([Vector2(500, 500)]))
	_bus.map_frame_shown.emit(0, Rect2i(40, 30, 200, 120), true)
	_input.send_virtual(0, &"map", 1.0)
	_frame()
	var stages: Array[int] = []
	for _step in 6:
		legend.step(1.0 / MapLegendScript.FPS, 1, Transform2D.IDENTITY)
		stages.append(legend.stage_of(0))
	check_equal(stages, [1, 2, 3, 4, 4, 4], "it rises a stage a frame (Smooth)")
	var strip: Control = legend.strip_of(0)
	check(strip.visible, "shown")
	check_equal(strip.get_rect(), Rect2(40, 150 - MapLegendScript.HEIGHT, 200, MapLegendScript.HEIGHT), "along the inside of the frame's lower edge")
	var dpad := strip.find_child("*", true, false)
	check(dpad != null, "with its glyphs")
	_bus.map_frame_shown.emit(0, Rect2i(40, 30, 200, 120), false)
	stages.clear()
	for _step in 5:
		legend.step(1.0 / MapLegendScript.FPS, 1, Transform2D.IDENTITY)
		stages.append(legend.stage_of(0))
	check_equal(stages, [3, 2, 1, 0, 0], "the frame closing: it sinks the same way")
	check(not strip.visible, "and hides")
	legend.step(0.0, 0, Transform2D.IDENTITY)
	_bus.map_frame_shown.emit(0, Rect2i(40, 30, 200, 120), true)
	legend.step(1.0, 0, Transform2D.IDENTITY)
	check_equal(legend.stage_of(0), 0, "open but nothing to pick (in a fight): no legend")


func test_the_cross_fits_beside_six_slot_staffs_in_an_equal_pane() -> void:
	var panel: Control = _hud.get_panel(0)
	var plan: Dictionary = {"cards": [&"bolt", &"bolt", &"bolt", &"bolt", &"bolt", &"bolt"], "casts": [{"slots": PackedInt32Array([0, 1, 2, 3, 4, 5])}]}
	var icons: Array[Texture2D] = [null, null, null, null, null, null]
	for staff in 4:
		panel.call("set_staff_plan", staff, plan, icons)
	panel.set("visible", true)
	await process_frame
	var without: Vector2 = panel.get_combined_minimum_size()
	for slot in 4:
		panel.call("set_quick", slot, PlaceholderTexture2D.new(), 12, true)
	await process_frame
	var with: Vector2 = panel.get_combined_minimum_size()
	check_equal(with.y, without.y, "beside four staff rows the cross adds no height: %s, %s" % [without, with])
	check(with.x - without.x <= QuickCrossScript.SIDE + 3.0, "and only its own width: %s, %s" % [without, with])
	# The smallest Equal pane (#875, gameplay/feel/equal_panes.gd): a quarter of the 640 × 360 screen.
	check(with.x <= 160.0 and with.y <= 90.0, "the panel fits a quarter pane's corner: %s" % with)
