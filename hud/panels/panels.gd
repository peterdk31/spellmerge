extends CanvasLayer
## The corner panels of all players: the autoload "Hud". P1 is top left, P2 top
## right, P3 bottom left and P4 bottom right (nodes Root/Panel1 to Root/Panel4).
##
## A panel is shown for a joined player once a room has been entered, and hidden
## when the player leaves. A run starting or ending hides all panels and clears
## their numbers, so none stays over the menu. Numbers come only from `player_stats_changed`; the
## "MENU" word follows `UIFocus.opened` and `closed` for that player. Nothing is
## polled and nothing here takes input, so a player in their builder never makes
## another panel wait.
##
## Menus open only while a room is active, and close when the run starts or ends, so none is
## ever left open over the main menu. The pause menu's "Main menu" (`main_menu_requested`) clears
## them all and makes the main menu the current scene again (`main_menu`).
##
## Under each panel's health line, one row per staff with cards (owner, 2026-10-27): its cast
## sequence comes from `staff_changed` (the plain `Spells.staff_view`, icons asked of `Spells`
## once per plan), and its next cast and delay are read each frame from `Spells.cast_index` and
## `Spells.cooldown_left`, plain numbers that allocate nothing (`step_staffs`), and its mana line
## from `staff_mana_changed`.
##
## A panel is the body its seat drives (items I8; owner, 2026-11-13, which replaces "always the
## player's own wizard" of 2026-10-28): its numbers and staff rows (`player_stats_changed`,
## `staff_changed` and the timing of `Spells.shown_of_seat`) are a possessed body's while the seat
## possesses one, and the wizard's while an enemy's AI drives the wizard, so a player sees the body
## they play. Their own wizard's health shows over its head meanwhile (Feel), and the possession's
## time over the possessed actor (`PossessedLook`). When the seat says its things anew
## (`inventory_announced`: the body shown changed, or its wizard was made again) its builder and
## inventory close, so neither sends a request about a staff of the body shown before.
##
## The loading screen (`loading/`, node Root/Loading, over everything but the pause menu, the pad
## line and the frame rate readout)
## shows from `loading_started` to `loading_finished`, while flow compiles the shaders before the
## first room, and while the party departs for a run or back to the hub (`run_departure_changed`).
##
## The boss bar (`boss/boss_bar.gd`, node Root/BossBar, at the top middle) and the entrance banner
## (`boss/boss_banner.gd`, node Root/BossBanner, over the world, under the panels) show what
## `boss_shown`, `boss_health_changed` and `boss_hidden` say (boss plan OB16); the bar is under the
## menus, and the banner waits while the game is paused. Going back to the menu clears them.
##
## The boss intro's overlay (`boss/boss_intro.gd`, node Root/BossIntro, over the world, the corner
## panels and the boss bar, under the menus and the pause shade; docs/milestones/boss-intro.md, rule
## 5) plays a boss's intro from `boss_intro_opened`, `boss_intro_paged` and `boss_intro_closed`, stepped
## every frame (the tree is paused for the whole intro). While it is open a seat's `accept` is its
## (`BossIntro.press`: the next page's command for a seat of this machine), the builder and the
## inventory do not open, and the ones open as it opens close, so A is never two menus' at
## once; the pause menu still opens, and while it is open its A is the menu's. A boss with an intro
## (`boss_shown`'s `has_intro`) keeps the bar and the banner back until its intro is over (a
## `BossIntroWait`, `core/base/`): the bar then fades in; the banner shows only when no intro played.
##
## A red vignette (`vignette/`, node Root/Vignette, behind the panels) glows when a
## wizard's health falls, strongest toward that wizard's corner and fading in under
## half a second. It is read from `player_stats_changed` alone (a drop in health),
## never from a node, and it takes no input.
##
## The buttons that open menus are read here, from the press counters of `core/input` (a tap
## released within a frame is not lost); each menu then takes its input through
## `core/ui_focus` (owner, 2026-10-26):
## - `back` (B; E on the keyboard) opens that player's radial spell builder
##   (`hud/builder/radial_builder.gd`, nodes Root/Radial1 to Root/Radial4, made here; owner,
##   2026-10-26) when they have no menu open, are not down and the pause menu is not open. It
##   never pauses the game; it is the full builder at any time, fights included (staffs A6a).
##   Inside a menu `back` is that menu's own (UIFocus `cancelled`), so a press only opens the
##   builder when the player had no menu open at the poll before it too. (The older list
##   builder is gone, owner 2026-11-11.) The pause menu's Settings page sets the radial's ring (its
##   layout, or a ring style from `builder/rings/`) and full-slot choice
##   (`builder_options_changed`). The same page switches where every corner panel's staff rows
##   show a staff's delay, on the button glyph (the default) or on the next cast
##   (`reload_style_changed`; owner, 2026-10-27).
## - `inventory` (Select; Tab) opens that player's inventory (`hud/menus/inventory/`, nodes
##   Root/Inventory1 to Root/Inventory4, made here; items I7) under the same conditions as the
##   builder; it closes itself on the same button, on B from its first ring and on Start, and the
##   corner panel hides while it is open, as for the builder.
## - `pause` (Start; Escape) closes the menu its player has open (the builder, or the pause menu
##   they opened); with none open it opens the pause menu (`hud/menus/pause/`, node
##   Root/PauseMenu), which stops the game for everyone and is worked by the player who opened
##   it. Another player's `pause` does nothing while it is open.
## - The pad line (`hud/widgets/pad_line.gd`, node Root/PadLine, made here; owner, 2026-11-13):
##   while the game waits for a seat's unplugged gamepad (`pad_wait_changed`), whose controller is
##   gone and how to go on. A waiting seat's open pause menu closes, and the pause menu another
##   player opens offers "Leave game" for this machine's waiting seats.
## - The online line (`hud/widgets/online_line.gd`, node Root/OnlineLine, made here; netcode spike
##   S4): what playing with other machines has to say, at the top middle (`online_changed`'s
##   reason and the line of `online_line_changed`, worded by `hud/widgets/online_words.gd`).
## - A seat played on another machine says so on its corner panel (online-lobby L5c): while this
##   machine plays with others (`online_changed`), a joined seat with no real device of this
##   machine on it (`core/input`) shows ONLINE (`PlayerPanel.set_online`, `poll`).
## - The stone line (`hud/widgets/stone_line.gd`, node Root/StoneLine, made here; online-lobby L1):
##   in the hub, how many wizards stand on the teleporter stone, or that A starts the run, at the
##   top middle under the online line (`start_stone_changed`). While the stone is lit, a player's
##   `accept` (A, Enter) with no menu open sends the command `run_requested` (`poll`).
## - The reward menus (`hud/menus/reward/`, nodes Root/Reward1 to Root/Reward4, made here;
##   connected biomes CB10): a seat's offer not yet picked, "pick 1 of 3". It never opens by itself
##   (the owner, 2026-11-19): a present seat's reward lies as an item in the cleared room, and A at
##   it (the item hints' `reward_of`) opens that offer; a seat with an offer lying nowhere (rolled
##   while away) opens its oldest such on `accept` with no menu open and nothing
##   else for A (no lit stone, no item in reach, no altar). A refused pick opens it again on that
##   offer once the seat may open a menu (`RewardMenu.wants_open`). Its pick is the command
##   `reward_pick_requested`; `back`, `pause` and a boss's intro close it, the offer left unspent.
##   Each corner panel says the seat's coins and its unspent rewards (the coin stack in the coins
##   bag of the body the seat drives, as the rest of the HUD: a possessed foe's while possessing,
##   0 for a body with no coins; `bag_changed`: coins are an inventory item, the owner's of
##   2026-11-19; `rewards_waiting_changed`; `PlayerPanel.set_purse`). Beside the coins, each panel
##   shows the keys in that same currency bag (keys are each body's own, the owner's of 2026-11-19:
##   a possessed foe's while possessing; `PlayerPanel.set_keys`, `hud/widgets/key_count.gd`, Smooth:
##   a change of body plays from the count shown to the new body's).
## - The item hints (`item_hints.gd`, node Root/ItemHints, made here; items I6): over the item in
##   reach of each player's driven body (`item_near_changed`), its name and the A glyph, a staff's
##   numbers and cards under it, shaking red when a take is refused (`item_refused`). `take` (A; F or
##   Enter, never Space, which casts) with no menu open and no lit stone takes it
##   (`item_take_requested`). With no ground item in reach, a shop's item where the wizard stands
##   (`shelf_near_changed`) is shown the same way, "Buy" and its price, and `take` buys it
##   (`shelf_buy_requested`; connected biomes CB11's follow-up): what the wizard stands at decides
##   what A does. The altar's A and a waiting reward's come after.
## - The cheat code (`hud/widgets/cheat_code.gd`, node CheatCode, made here; owner, 2026-11-19):
##   the word `CheatCode.CODE` typed on the keyboard, or `CheatCode.PAD_CODE` on a gamepad, sends `all_cards_requested` (every card, in
##   the hub).
## - The frame rate readout (`hud/widgets/fps_counter.gd`, node Root/FpsCounter, made here; owner,
##   2026-11-02): "60 FPS" at the bottom middle, over everything, shown while the pause menu's
##   "Show FPS" switch is on (read after the menu is bound, then `show_fps_changed`).

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const PauseMenuScript := preload("res://hud/menus/pause/pause_menu.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const InventoryScript := preload("res://hud/menus/inventory/inventory_menu.gd")
const RingZoomScript := preload("res://hud/builder/rings/ring_zoom.gd")
const RingKindsScript := preload("res://hud/builder/rings/ring_kinds.gd")
const PlayerPanelScript := preload("res://hud/panels/player_panel/player_panel.gd")
const StaffRowScript := preload("res://hud/panels/player_panel/staff_row.gd")
const VignetteScript := preload("res://hud/panels/vignette/vignette.gd")
const LoadingScript := preload("res://hud/panels/loading/loading_screen.gd")
const FpsCounterScript := preload("res://hud/widgets/fps_counter.gd")
const OnlineLineScript := preload("res://hud/widgets/online_line.gd")
const StoneLineScript := preload("res://hud/widgets/stone_line.gd")
const PadLineScript := preload("res://hud/widgets/pad_line.gd")
const ItemHintsScript := preload("res://hud/panels/item_hints.gd")
const MapPickerScript := preload("res://hud/panels/map_picker.gd")
const RewardMenuScript := preload("res://hud/menus/reward/reward_menu.gd")
const BossBarScript := preload("res://hud/panels/boss/boss_bar.gd")
const BossBannerScript := preload("res://hud/panels/boss/boss_banner.gd")
const BossIntroScript := preload("res://hud/panels/boss/boss_intro.gd")

const PLAYER_COUNT: int = 4
const PAUSE_ACTION: StringName = &"pause"
const BUILDER_ACTION: StringName = &"back"
## Select (Tab) opens the inventory (items I7); the inventory closes itself on it.
const INVENTORY_ACTION: StringName = &"inventory"
## A on the hub's lit stone starts the run (`run_requested`; online-lobby L1); else it takes the
## item in reach (`item_take_requested`; items I6: `take`, A, F or Enter, never Space, which casts),
## else it opens the altar's room.
const START_ACTION: StringName = &"accept"
const TAKE_ACTION: StringName = &"take"
## Space between the screen edge and a panel.
const EDGE_MARGIN: float = 4.0
## How far below the online line the stone line sits, in pixels.
const STONE_LINE_DROP: float = 12.0
## How far below the top the pad line sits: under the stone line and its second line (where the
## run starts, run generation RG7).
const PAD_LINE_DROP: float = 36.0
## How far below the top the boss bar sits: under the online line (the stone line, which it would
## share the place with, shows only in the hub, where no boss stands).
const BOSS_BAR_DROP: float = 12.0

## The event bus, the UI focus service, the input manager and the spell runtime (the
## radials ask it for names and icons). Only tests set these, before adding the
## node; otherwise the "Events", "UIFocus", "PlayerInput" and "Spells" autoloads.
var events: EventsScript = null
var ui_focus: UIFocusScript = null
var input: InputManagerScript = null
var spells: SpellsScript = null
## The save that keeps the menu's settings; the default one (`user://save.cfg`) when null.
var save: SaveFile = null
## The main menu shown on `main_menu_requested`; null: the game's own (its main scene,
## `hud/menus/main_menu/`). Tests give their own.
var main_menu: PackedScene = null

var _panels: Array[PlayerPanelScript] = []
var _radials: Array[RadialScript] = []
var _inventories: Array[InventoryScript] = []
var _rewards: Array[RewardMenuScript] = []
## By seat: the coins in its currency bag and its offers waiting (`bag_changed`,
## `rewards_waiting_changed`), for its corner panel.
var _coins: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _unspent: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _pause_menu: PauseMenuScript = null
## Per player: the `pause` and `back` press counts at the last poll, and whether a menu of
## theirs was open then.
var _seen_pause: Array[int] = [0, 0, 0, 0]
var _seen_back: Array[int] = [0, 0, 0, 0]
var _seen_inventory: Array[int] = [0, 0, 0, 0]
var _seen_start: Array[int] = [0, 0, 0, 0]
var _seen_take: Array[int] = [0, 0, 0, 0]
## True while the hub's teleporter stone is lit (`start_stone_changed`).
var _stone_lit: bool = false
## The seats whose wizards stand on the hub's multiplayer altar (`altar_changed`), a bit each.
var _altar_seats: int = 0
## Whether this machine plays with others now (`online_changed`): only then is a seat marked.
var _online: bool = false
var _had_menu: Array[bool] = [false, false, false, false]
## Each seat's staffs' mana and what their sustained cards hold (`staff_mana_changed`,
## `mana_reserved`), by seat * STAFF_COUNT + staff: what a press could pay, for the staff rows.
var _staff_mana: PackedFloat32Array = PackedFloat32Array()
var _staff_reserved: PackedFloat32Array = PackedFloat32Array()
var _joined: Array[bool] = [false, false, false, false]
var _in_room: bool = false
var _vignette: VignetteScript = null
var _loading: LoadingScript = null
## The frame rate readout (see the top).
var _fps: FpsCounterScript = null
var _online_line: OnlineLineScript = null
var _stone_line: StoneLineScript = null
## Every player's hint over the item in reach (items I6), and by player whether a menu hides it
## (filled each frame in place).
var _item_hints: ItemHintsScript = null
## The pick on each seat's open Y map: a room to teleport to (the owner, 2026-11-19; `map_picker.gd`).
var _map_picker: MapPickerScript = MapPickerScript.new()
var _hint_menus: Array[bool] = [false, false, false, false]
var _pad_line: PadLineScript = null
## The boss bar (top middle) and the entrance banner (upper middle), boss plan OB16.
var _boss_bar: BossBarScript = null
var _boss_banner: BossBannerScript = null
## The boss intro's overlay, and what keeps a boss with an intro off the bar and the banner meanwhile.
var _boss_intro: BossIntroScript = null
var _intro_wait: BossIntroWait = BossIntroWait.new()
## The menus' focus sounds (sound plan AU8; `widgets/ui_sounds.gd`).
var _ui_sounds: UiSounds = null
## The cheat code's listener (`widgets/cheat_code.gd`).
var _cheat_code: CheatCode = null


func _ready() -> void:
	_staff_mana.resize(PLAYER_COUNT * PlayerPanelScript.STAFF_COUNT)
	_staff_mana.fill(INF)
	_staff_reserved.resize(PLAYER_COUNT * PlayerPanelScript.STAFF_COUNT)
	# The pause menu is worked while the game is paused, so the HUD runs then too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Behind the panels: the first child of Root.
	_vignette = VignetteScript.new()
	_vignette.name = "Vignette"
	var root_control: Control = get_node("Root") as Control
	root_control.add_child(_vignette)
	root_control.move_child(_vignette, 0)
	for player in PLAYER_COUNT:
		var panel := get_node("Root/Panel%d" % (player + 1)) as PlayerPanelScript
		panel.visible = false
		_panels.append(panel)
	_pause_menu = get_node("Root/PauseMenu") as PauseMenuScript
	for player in PLAYER_COUNT:
		var radial := RadialScript.new()
		radial.name = "Radial%d" % (player + 1)
		radial.index = player
		root_control.add_child(radial)
		# Under the corner panels (its shade leaves their band free but never dims them).
		root_control.move_child(radial, _panels[0].get_index())
		_radials.append(radial)
	for player in PLAYER_COUNT:
		var inventory := InventoryScript.new()
		inventory.name = "Inventory%d" % (player + 1)
		inventory.index = player
		root_control.add_child(inventory)
		# Under the corner panels, as the builders.
		root_control.move_child(inventory, _panels[0].get_index())
		_inventories.append(inventory)
	for player in PLAYER_COUNT:
		var reward := RewardMenuScript.new()
		reward.name = "Reward%d" % (player + 1)
		reward.index = player
		root_control.add_child(reward)
		_rewards.append(reward)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if ui_focus == null:
		ui_focus = get_node_or_null("/root/UIFocus") as UIFocusScript
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
	if spells == null:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	# The loading screen (put over everything below, once the rest is made).
	_loading = LoadingScript.new()
	_loading.events = events
	root_control.add_child(_loading)
	if input != null:
		for player in PLAYER_COUNT:
			_seen_pause[player] = input.get_press_count(player, PAUSE_ACTION)
			_seen_back[player] = input.get_press_count(player, BUILDER_ACTION)
			_seen_inventory[player] = input.get_press_count(player, INVENTORY_ACTION)
			_seen_start[player] = input.get_press_count(player, START_ACTION)
			_seen_take[player] = input.get_press_count(player, TAKE_ACTION)
	# The menus' focus moves and backs, heard before any menu hears UIFocus, so it knows a press
	# was a choice or a back before that menu moves the focus in answer (ui_sounds.gd).
	_ui_sounds = UiSounds.new()
	_ui_sounds.name = "UiSounds"
	add_child(_ui_sounds)
	_ui_sounds.bind(events, ui_focus, input)
	_cheat_code = CheatCode.new()
	_cheat_code.name = "CheatCode"
	add_child(_cheat_code)
	_cheat_code.bind(events, input)
	_pause_menu.save = save
	_pause_menu.bind(events, ui_focus, input)
	for radial in _radials:
		radial.bind(events, ui_focus, spells, input)
	for inventory in _inventories:
		inventory.bind(events, ui_focus, spells, input)
	for reward in _rewards:
		reward.bind(events, ui_focus)
	_pause_menu.builder_options_changed.connect(_on_builder_options_changed)
	_pause_menu.reload_style_changed.connect(_on_reload_style_changed)
	# The frame rate readout: over everything, at the bottom middle.
	_fps = FpsCounterScript.new()
	_fps.name = "FpsCounter"
	root_control.add_child(_fps)
	_fps.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN))
	_fps.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fps.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fps.visible = _pause_menu.show_fps
	_pause_menu.show_fps_changed.connect(_on_show_fps_changed)
	# The online line: at the top middle, while a run is played with another machine.
	_online_line = OnlineLineScript.new()
	_online_line.name = "OnlineLine"
	root_control.add_child(_online_line)
	_online_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN))
	_online_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_online_line.bind(events)
	# The stone line: under the online line, while the party is in the hub.
	_stone_line = StoneLineScript.new()
	_stone_line.name = "StoneLine"
	root_control.add_child(_stone_line)
	_stone_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN + STONE_LINE_DROP))
	_stone_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stone_line.bind(events)
	# The pad line: under those, while the game waits for a seat's unplugged gamepad.
	_pad_line = PadLineScript.new()
	_pad_line.name = "PadLine"
	root_control.add_child(_pad_line)
	_pad_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN + PAD_LINE_DROP))
	_pad_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pad_line.bind(events)
	# The boss bar: at the top middle, under the online line, while a boss is in play (boss plan OB16).
	_boss_bar = BossBarScript.new()
	_boss_bar.name = "BossBar"
	root_control.add_child(_boss_bar)
	_boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(EDGE_MARGIN + BOSS_BAR_DROP))
	_boss_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_bar.bind(events)
	# Under the menus and the loading screen (the pause menu's shade dims it).
	root_control.move_child(_boss_bar, _pause_menu.get_index())
	# The entrance banner: over play, under the panels and the menus (just over the vignette).
	_boss_banner = BossBannerScript.new()
	_boss_banner.name = "BossBanner"
	root_control.add_child(_boss_banner)
	root_control.move_child(_boss_banner, 1)
	_boss_banner.bind(events)
	# The boss intro's overlay: over the world, the corner panels and the bar, under the menus.
	_boss_intro = BossIntroScript.new()
	_boss_intro.name = "BossIntro"
	_boss_intro.menu_open = _pause_menu.is_open
	root_control.add_child(_boss_intro)
	root_control.move_child(_boss_intro, _pause_menu.get_index())
	_boss_intro.bind(events)
	_intro_wait.bind(events)
	_intro_wait.released.connect(_boss_bar.release)
	_intro_wait.released.connect(_boss_banner.release)
	# The item hints: in the world's picture, under the panels and the builders.
	_item_hints = ItemHintsScript.new()
	_item_hints.name = "ItemHints"
	root_control.add_child(_item_hints)
	root_control.move_child(_item_hints, 1)
	_item_hints.bind(events, input, spells)
	_map_picker.bind(events)
	# The loading screen over every line and overlay made above. Over it: the pause menu and the pad
	# line, since either stops the game, and a departure from the stone with it (the screen stays down
	# until the run starts), and the frame rate readout (the freeze it covers is what that counts).
	root_control.move_child(_loading, -1)
	for over: Control in [_pause_menu, _pad_line, _fps]:
		root_control.move_child(over, -1)
	if events != null:
		events.pad_wait_changed.connect(_on_pad_wait_changed)
		events.player_joined.connect(_on_player_joined)
		events.player_left.connect(_on_player_left)
		events.join_held.connect(_on_join_held)
		events.player_stats_changed.connect(_on_stats_changed)
		events.room_entered.connect(_on_room_entered)
		events.start_stone_changed.connect(_on_start_stone_changed)
		events.altar_changed.connect(func(seats: int) -> void: _altar_seats = seats)
		events.online_changed.connect(_on_online_changed)
		events.staff_changed.connect(_on_staff_changed)
		events.inventory_announced.connect(_on_inventory_announced)
		events.staff_mana_changed.connect(_on_staff_mana_changed)
		events.mana_reserved.connect(_on_mana_reserved)
		events.cast_fizzled.connect(_on_cast_fizzled)
		events.run_started.connect(_on_run_started)
		events.run_ended.connect(_on_run_ended)
		events.main_menu_requested.connect(_on_main_menu_requested)
		events.boss_intro_opened.connect(_on_boss_intro_opened)
		events.bag_changed.connect(_on_bag_changed)
		events.rewards_waiting_changed.connect(_on_rewards_waiting_changed)
	if ui_focus != null:
		ui_focus.opened.connect(_on_menu_opened)
		ui_focus.closed.connect(_on_menu_closed)


func _process(delta: float) -> void:
	poll()
	step_hints(delta)
	_vignette.step(delta)
	# The intro plays while the tree is paused for it; a boss it held back shows once it is over.
	_boss_intro.step(delta)
	_intro_wait.settle()
	_boss_bar.step(delta)
	if not get_tree().paused:
		# The entrance waits while the game is paused.
		_boss_banner.step(delta)
	step_staffs()
	for reward in _rewards:
		reward.step()


## Put every player's item hint over its item as the camera shows it now (none outside a room,
## and none for a player with a menu open). Called every frame; tests call it directly.
func step_hints(delta: float) -> void:
	var menus: Array[bool] = _hint_menus
	for player in PLAYER_COUNT:
		menus[player] = not _in_room or _has_menu(player) or (_pause_menu != null and _pause_menu.is_open())
	var viewport: Viewport = get_viewport()
	var to_screen: Transform2D = viewport.get_canvas_transform() if viewport != null else Transform2D.IDENTITY
	# While the screen is split (connected biomes CB6) each hint follows its player's own view.
	_item_hints.step(delta, menus, transform.affine_inverse() * to_screen, ScreenViews.on(viewport), transform.affine_inverse())


## The item hints (for tests and screenshots).
func get_item_hints() -> ItemHintsScript:
	return _item_hints


## The menus' focus sounds (for tests).
func get_ui_sounds() -> UiSounds:
	return _ui_sounds


## Read every joined player's `pause`, `back` and `accept` presses since the last poll (several
## presses in one frame count once) and open or close menus as the top of this file says; `accept`
## with no menu open while the hub's stone is lit sends `run_requested`, else with an item in reach
## `item_take_requested`, else on the altar `online_open_requested`. Presses outside a room are
## dropped. Called every frame by _process; tests call it directly. One player's press never
## touches another player's menus.
func poll() -> void:
	if input == null:
		return
	for player in PLAYER_COUNT:
		var pause_count: int = input.get_press_count(player, PAUSE_ACTION)
		var paused_now: bool = pause_count > _seen_pause[player]
		_seen_pause[player] = pause_count
		var back_count: int = input.get_press_count(player, BUILDER_ACTION)
		var back_now: bool = back_count > _seen_back[player]
		_seen_back[player] = back_count
		var inventory_count: int = input.get_press_count(player, INVENTORY_ACTION)
		var inventory_now: bool = inventory_count > _seen_inventory[player]
		_seen_inventory[player] = inventory_count
		var start_count: int = input.get_press_count(player, START_ACTION)
		var start_now: bool = start_count > _seen_start[player]
		_seen_start[player] = start_count
		var take_count: int = input.get_press_count(player, TAKE_ACTION)
		var take_now: bool = take_count > _seen_take[player]
		_seen_take[player] = take_count
		var had_menu: bool = _had_menu[player]
		# The open Y map's pick: A there teleports (the owner, 2026-11-19) and does nothing else.
		var map_held: bool = _in_room and not had_menu and not _has_menu(player) and not _pause_menu.is_open() and not _boss_intro.is_open() and _map_picker.holds(player, input)
		var map_took: bool = _map_picker.poll(player, map_held, input.get_move(player), start_now or take_now)
		if input.is_joined(player) and not map_took:
			if _boss_intro.is_open():
				# A is the intro's while it is open (it asks whether the pause menu is).
				if start_now and not had_menu and not _has_menu(player):
					_boss_intro.press(player)
			elif (start_now or take_now) and not had_menu and not _has_menu(player) and not _pause_menu.is_open() and events != null:
				if _stone_lit:
					if start_now:
						events.run_requested.emit(player)
				elif take_now and _item_hints.item_of(player) >= 0:
					events.item_take_requested.emit(player, _item_hints.item_of(player))
				elif take_now and _item_hints.shelf_of(player) >= 0:
					# A shop's item (or reroll sign) where the wizard stands: A buys it (connected biomes
					# CB11's follow-up; the sign, a reroll of the shelf, the owner's of 2026-11-19).
					events.shelf_buy_requested.emit(player, _item_hints.shelf_of(player))
				elif take_now and _item_hints.reward_of(player) >= 0 and not _panels[player].is_downed():
					# The seat's own reward item where its body stands: A opens its pick (the owner,
					# 2026-11-19: rewards never pop up by themselves).
					_open_reward(player, _item_hints.reward_of(player))
				elif start_now and _altar_seats & (1 << player) != 0:
					events.online_open_requested.emit(player)
				elif start_now and _rewards[player].waiting_away() > 0 and _in_room and not _panels[player].is_downed():
					# An offer lying nowhere (rolled while away): A anywhere opens it.
					_open_reward(player)
			if paused_now:
				_on_pause_pressed(player)
			elif back_now and _may_open_menu(player, had_menu):
				_radials[player].open_builder()
			elif inventory_now and _may_open_menu(player, had_menu):
				_inventories[player].open_inventory()
			elif _rewards[player].wants_open() and _may_open_menu(player, had_menu):
				# A refused pick (or a reroll of another count) opens again once the seat is free for it.
				_open_reward(player, _rewards[player].wanted())
		_had_menu[player] = _has_menu(player)
		# A seat in the game with no device of this machine on it is played on another one. Asked
		# of the input layer each frame: a device handed over or mirrored sends no event.
		_panels[player].set_online(_online and _joined[player] and not _plays_here(player))


## Whether seat `player` is played on this machine: a real device sits on it (another machine's
## seat is a virtual device here, as a bot's is; `core/input`).
func _plays_here(player: int) -> bool:
	return input.is_joined(player) and not InputManagerScript.is_virtual(input.device_of(player))


## Playing with other machines began or ended (`online_changed`): the seats are marked only while
## it lasts (a room open or a run played), so offline a bot's or a recording's seat is not called
## online.
func _on_online_changed(phase: StringName, _code: String, _reason: StringName, _facts: Dictionary) -> void:
	_online = phase == EventsScript.ONLINE_CODE or phase == EventsScript.ONLINE_LINKED or phase == EventsScript.ONLINE_PLAYING


## Whether `player` may open their builder or inventory now: in a room, no menu of theirs open at
## this poll or the one before (`had_menu`: the press that closed one never opens another), the
## pause menu closed and not down.
func _may_open_menu(player: int, had_menu: bool) -> bool:
	return not had_menu and not _has_menu(player) and _in_room and not _pause_menu.is_open() and not _panels[player].is_downed() and not _boss_intro.is_open()


## Whether `player` has a menu open: their builder, their inventory, or the pause menu they work.
func _has_menu(player: int) -> bool:
	return _radials[player].is_open() or _inventories[player].is_open() or _rewards[player].is_open() or _pause_menu.owner_player == player




## Open seat `player`'s reward menu on its offer `offer` (-1: its oldest lying nowhere), its cards laid out in their quarter of the view while several
## play, so four open at once never cover each other (a quarter is inside the seat's own cell of a
## split screen, CB6), or in the whole view for one player.
func _open_reward(player: int, offer: int = -1) -> void:
	var reward: RewardMenuScript = _rewards[player]
	reward.room = reward_room(player)
	reward.open_menu(offer)


## The room seat `player`'s reward menu lays its cards out in (view pixels).
func reward_room(player: int) -> Rect2:
	var view: Vector2 = (get_node("Root") as Control).size
	if _joined.count(true) <= 1:
		return Rect2(Vector2(0.0, REWARD_CORNER_BAND), view - Vector2(0.0, REWARD_CORNER_BAND * 2.0))
	var quarter: Vector2 = (view * 0.5).floor()
	var top: float = REWARD_CORNER_BAND if player < 2 else 0.0
	return Rect2(Vector2(float(player % 2), 1.0 if player >= 2 else 0.0) * quarter + Vector2(0.0, top), quarter - Vector2(0.0, REWARD_CORNER_BAND))


## The reward menus keep off the band of the screen's top and bottom edges the corner panels sit in.
const REWARD_CORNER_BAND: float = 32.0


## The reward menu of seat `player` (for tests and screenshots).
func get_reward(player: int) -> RewardMenuScript:
	return _rewards[player]


## A bag of the seat's shown body changed: its currency bag is the purse's coins, its keys and its
## reward rerolls.
func _on_bag_changed(player: int, bag: StringName, ids: Array[StringName], counts: PackedInt32Array, _capacity: int) -> void:
	if player < 0 or player >= PLAYER_COUNT or bag != ItemKinds.bag_of(ItemKinds.COIN):
		return
	var at: int = ids.find(CoinBase.ID)
	_coins[player] = counts[at] if at >= 0 and at < counts.size() else 0
	_panels[player].set_purse(_coins[player], _unspent[player])
	_panels[player].set_keys(_count_in(ids, counts, KeyBase.ID), false)
	_panels[player].set_rerolls(_count_in(ids, counts, RerollBase.REWARD), false)


## The count of `id` in a bag's `ids` and `counts` (0 when it holds none).
static func _count_in(ids: Array[StringName], counts: PackedInt32Array, id: StringName) -> int:
	var at: int = ids.find(id)
	return counts[at] if at >= 0 and at < counts.size() else 0


func _on_rewards_waiting_changed(player: int, offers: Array[Dictionary]) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		# What A anywhere opens: an offer lying as an item waits in its room, its chest says so.
		var away: int = 0
		for offer: Dictionary in offers:
			if not bool(offer.get("lying", false)):
				away += 1
		_unspent[player] = away
		_panels[player].set_purse(_coins[player], away)


## `pause`: close the player's open menu, or open the pause menu for them.
func _on_pause_pressed(player: int) -> void:
	if _radials[player].is_open():
		_radials[player].close_builder()
	elif _inventories[player].is_open():
		_inventories[player].close_inventory()
	elif _rewards[player].is_open():
		_rewards[player].close_menu()
	elif _pause_menu.is_open():
		if _pause_menu.owner_player == player:
			_pause_menu.close_menu()
	elif _in_room:
		_pause_menu.open_menu(player)


## The seats the game waits for (their gamepad is unplugged; `pad_wait_changed`). A waiting seat
## cannot work a menu, so whatever it had open closes (its builder, or the pause menu, which another
## player may then open), as when a device left; the pause menu offers "Leave game" for the waiting
## seats of this machine (another machine's are its own to let go).
func _on_pad_wait_changed(seats: int) -> void:
	var here: int = 0
	for player in PLAYER_COUNT:
		if seats & (1 << player) == 0:
			continue
		if ui_focus != null:
			ui_focus.close(player)
		if input != null and input.is_waiting(player):
			here |= 1 << player
	_pause_menu.set_waiting_seats(here)


## The pad line (for tests and screenshots).
func get_pad_line() -> PadLineScript:
	return _pad_line


## The pause menu (for tests and screenshots).
func get_pause_menu() -> PauseMenuScript:
	return _pause_menu


## The radial builder of `player`, or null for a bad index.
func get_radial(player: int) -> RadialScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _radials[player]


## The inventory of `player`, or null for a bad index.
func get_inventory(player: int) -> InventoryScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _inventories[player]


## The pause menu's builder switches: the radial's ring and what a full slot does.
func _on_builder_options_changed(ring: PauseMenuScript.Ring, push: bool) -> void:
	for builder in _radials:
		builder.layout = RadialScript.Layout.KIND if ring == PauseMenuScript.Ring.ONE_KIND else RadialScript.Layout.ALL
		builder.put = RadialScript.Put.PUSH if push else RadialScript.Put.REPLACE
		# Each radial its own style object: they keep per-player state.
		match ring:
			PauseMenuScript.Ring.ZOOM:
				builder.ring_picker = RingZoomScript.new()
			PauseMenuScript.Ring.KINDS_HOLD:
				builder.ring_picker = RingKindsScript.new(RingKindsScript.Enter.HOLD)
			PauseMenuScript.Ring.KINDS_DEPTH:
				builder.ring_picker = RingKindsScript.new(RingKindsScript.Enter.DEPTH)
			_:
				builder.ring_picker = null


## The pause menu's reload switch: every panel's staff rows show the delay on the button glyph,
## or on the next cast.
func _on_reload_style_changed(on_button: bool) -> void:
	var style: StaffRowScript.Style = StaffRowScript.Style.BUTTON if on_button else StaffRowScript.Style.NEXT_CAST
	for panel in _panels:
		panel.set_reload_style(style)


func _on_show_fps_changed(on: bool) -> void:
	_fps.visible = on
	if on:
		_fps.refresh()


## The frame rate readout (for tests and screenshots).
func get_fps_counter() -> FpsCounterScript:
	return _fps


## The boss bar and the entrance banner (for tests).
func get_boss_bar() -> BossBarScript:
	return _boss_bar


func get_boss_banner() -> BossBannerScript:
	return _boss_banner


## The boss intro's overlay (for tests and screenshots).
func get_boss_intro() -> BossIntroScript:
	return _boss_intro


## A boss's intro opened: every builder and inventory closes, so A is only the
## intro's (the pause menu stays as it is).
func _on_boss_intro_opened(_actor: int, _boss_name: String, _lore: String, _intro: BossIntro, _page: int, _fresh: bool) -> void:
	for player in PLAYER_COUNT:
		_radials[player].close_builder()
		_inventories[player].close_inventory()
		_rewards[player].close_menu()


## The red vignette (for tests).
func get_vignette() -> VignetteScript:
	return _vignette


## The panel of `player`, or null for a bad index.
func get_panel(player: int) -> PlayerPanelScript:
	if player < 0 or player >= PLAYER_COUNT:
		return null
	return _panels[player]


## A corner panel shows while its player is in a room, except while their radial builder is open:
## the radial shows the bars itself, so its column can sit where the panel was (owner,
## 2026-10-31, docs/milestones/M2-builder-tree.md). The radial is shown before its menu opens and
## hidden before it closes, so `visible` is already right when UIFocus says so.
func _refresh(player: int) -> void:
	_panels[player].visible = _in_room and _joined[player] and not _radials[player].visible and not _inventories[player].visible


func _on_player_joined(player: int) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_joined[player] = true
	_refresh(player)


## Seat `player` waits to join (the party left the biome's start room) or no more (`join_held`): its
## corner panel says so.
func _on_join_held(player: int, held: bool) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_join_held(held)


func _on_player_left(player: int) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	_joined[player] = false
	_panels[player].reset()
	_panels[player].clear_staffs()
	_refresh(player)


## The hub's stone lit or out: while lit, a seat's `accept` with no menu open starts the run.
func _on_start_stone_changed(_standing: int, _wizards: int, lit: bool) -> void:
	_stone_lit = lit


func _on_room_entered(_room_id: StringName, _room: int) -> void:
	_in_room = true
	for player in PLAYER_COUNT:
		_refresh(player)


## A staff was built or changed: its row shows the plan's cast sequence, with each card's icon
## asked of `Spells` once here (never per frame).
func _on_staff_changed(player: int, staff: int, plan: Dictionary) -> void:
	if player < 0 or player >= PLAYER_COUNT:
		return
	var icons: Array[Texture2D] = []
	for id: Variant in plan.get("cards", []):
		var card: StringName = StringName(id)
		icons.append(spells.component_icon(card) if spells != null and card != &"" else null)
	_panels[player].set_staff_plan(staff, plan, icons)


## Each shown panel's staff rows get their staff's next cast and delay left from `Spells`
## (plain numbers; nothing allocated). Called every frame by _process; tests call it directly.
func step_staffs() -> void:
	if spells == null:
		return
	for player in PLAYER_COUNT:
		var panel: PlayerPanelScript = _panels[player]
		if not panel.visible:
			continue
		# Spells keeps staffs by caster (actors G3b): the body the seat drives, else its wizard.
		var actor: int = spells.shown_of_seat(player)
		for staff in PlayerPanelScript.STAFF_COUNT:
			# The cast a press would fire with the staff's mana (one it cannot pay is skipped;
			# docs/milestones/cast-timing.md); unknown until the staff's mana was told.
			var mana: float = _staff_mana[player * PlayerPanelScript.STAFF_COUNT + staff]
			var firing: int = StaffRowScript.FIRING_UNKNOWN
			if is_finite(mana):
				firing = spells.firing_cast(actor, staff, maxf(mana - _staff_reserved[player * PlayerPanelScript.STAFF_COUNT + staff], 0.0))
			panel.set_staff_timing(staff, spells.cast_index(actor, staff), spells.cooldown_left(actor, staff), spells.is_winding(actor, staff), firing)


## A new run starts with no room entered yet: panels wait for `room_entered`.
func _on_run_started(_player_count: int) -> void:
	_reset_all()
	_staff_mana.fill(INF)
	_staff_reserved.fill(0.0)


## A run is over: no panels over the menu, and the next run starts clean (its wizards announce
## their staffs again when they appear).
func _on_run_ended(_victory: bool) -> void:
	_reset_all()
	_item_hints.clear()
	for panel in _panels:
		panel.clear_staffs()


## This machine goes back to the main menu (`main_menu_requested`): no panel or menu stays, and
## the main menu becomes the current scene again (Flow takes the run's world away itself). Nothing
## here asks Flow or net/: each does its own part of leaving.
func _on_main_menu_requested(_player: int) -> void:
	_on_run_ended(false)
	# The run's stops went with it (Flow); a seat still waiting says so again in the next room.
	_pad_line.show_seats(0)
	_pause_menu.set_waiting_seats(0)
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var scene: PackedScene = main_menu
	if scene == null:
		scene = load("res://hud/menus/main_menu/main_menu.tscn") as PackedScene
	var menu: Node = scene.instantiate() if scene != null else null
	if menu == null:
		push_warning("Hud: the main menu could not be made.")
		return
	tree.root.add_child(menu)
	tree.current_scene = menu


func _reset_all() -> void:
	_in_room = false
	_vignette.clear()
	_boss_bar.clear()
	_boss_banner.clear()
	_boss_intro.clear()
	_intro_wait.clear()
	_pause_menu.close_menu()
	for player in PLAYER_COUNT:
		_radials[player].close_builder()
		_inventories[player].close_inventory()
		_panels[player].reset()
		_refresh(player)


## A seat's numbers: the panel shows the health (each staff row its own mana, from
## `staff_mana_changed`).
func _on_stats_changed(player: int, health: float, max_health: float, _mana: float, _max_mana: float) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		var before: float = _panels[player].health()
		_panels[player].set_stats(health, max_health)
		if _in_room and before >= 0.0 and health < before:
			_vignette.flash_hit(player, (before - health) / maxf(max_health, 1.0), _joined.count(true))
		if health <= 0.0:
			_radials[player].close_builder()
			_inventories[player].close_inventory()


## The seat says its things anew (the body shown changed, items I8, or its wizard was made again):
## its builder and inventory close, so neither names a staff of the body shown before, and its
## panel's numbers start over (the body's own follow at once).
func _on_inventory_announced(player: int, _body: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_radials[player].close_builder()
		_inventories[player].close_inventory()
		# Another body's numbers follow: no hit flash for the change, and none of the last body's
		# mana held or told is read for this one's staff rows (review, items I8).
		_panels[player].forget_health()
		# The purse is the new body's: 0 until its currency bag is said (a body with none says nothing).
		_coins[player] = 0
		_panels[player].set_purse(0, _unspent[player])
		for staff in PlayerPanelScript.STAFF_COUNT:
			_staff_mana[player * PlayerPanelScript.STAFF_COUNT + staff] = INF
			_staff_reserved[player * PlayerPanelScript.STAFF_COUNT + staff] = 0.0
			_panels[player].set_staff_mana(staff, INF, 0.0)




func _on_menu_opened(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(true)
		_refresh(player)


func _on_menu_closed(player: int) -> void:
	if player >= 0 and player < PLAYER_COUNT:
		_panels[player].set_menu_open(false)
		_refresh(player)


## A seat's staff's mana changed (the player sends whole numbers): its row's mana line, and what a
## press could pay.
func _on_staff_mana_changed(player: int, staff: int, mana: float, max_mana: float) -> void:
	if player >= 0 and player < PLAYER_COUNT and staff >= 0 and staff < PlayerPanelScript.STAFF_COUNT:
		_staff_mana[player * PlayerPanelScript.STAFF_COUNT + staff] = mana
		_panels[player].set_staff_mana(staff, mana, max_mana)


## What a seat's staff's sustained cards hold of its mana.
func _on_mana_reserved(player: int, staff: int, amount: float) -> void:
	if player >= 0 and player < PLAYER_COUNT and staff >= 0 and staff < PlayerPanelScript.STAFF_COUNT:
		_staff_reserved[player * PlayerPanelScript.STAFF_COUNT + staff] = amount


## A press found no cast its mana pays (docs/milestones/cast-timing.md): the seat whose shown body
## it was shows it on that staff's row.
func _on_cast_fizzled(caster: int, staff: int) -> void:
	if spells == null:
		return
	for player in PLAYER_COUNT:
		if spells.shown_of_seat(player) == caster:
			_panels[player].staff_fizzled(staff)

