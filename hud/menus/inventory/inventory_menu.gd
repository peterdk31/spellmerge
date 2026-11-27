extends Control
## One player's inventory (items I7, docs/milestones/items.md, "The menus"): opened with Select
## (Tab) in play, never pausing the game, in the player's quarter like the radial builder (the
## column on the left, the ring on its right), drawn in code at the view's 1x pixels. It is built on
## the shared radial menu (`hud/widgets/radial_menu.gd`): a ring of places, pointed at with the
## right stick or P1's mouse (or stepped round with the left stick and the move keys), with layers.
##
## - **The first ring:** the bags (`ItemKinds.BAGS`), each with how full it is ("2/4", "2/∞").
##   A or RT (the thumb stays on the stick turning the ring, as in the builder: the owner, 2026-11-19;
##   P1: a left click) enters the bag pointed at; B goes back out a layer, and closes it on the
##   first ring; Select (Tab), Start and going down close it.
## - **Staffs:** every staff owned, the hands' first (each marked with its button), then the bag's.
##   A hand's button (RB, RT, LB, LT; on the keyboard Space, the left and right mouse buttons, Q)
##   puts the staff pointed at on that hand (from the bag the staff there goes into the bag; from
##   another hand the two change places); the button of the hand it is on takes it off into the bag.
##   X drops it on the ground.
## - **Cards:** the kinds the bag holds, then (A or RT) a kind's cards with their counts; X drops one.
## - **Sigils** (staff-language L4): the sigils held, and those on the hands' staffs (count 0 when
##   none is left in the bag). A hand's button puts the sigil pointed at on the staff on that hand, or
##   takes it off when that staff has it (`sigil_put_requested`, `sigil_take_requested`); what is
##   pointed at says which hands' staffs have it. A on a sigil opens the ring of every staff owned,
##   the bag's too (the owner, 2026-11-25), each marked with whether it has that sigil; A there puts
##   it on the staff pointed at, or takes it off.
## - **Relics, Potions, Coins:** the items the bag holds, each its own icon and count (`ItemLooks`);
##   A uses the one pointed at where it has a use (`ItemKinds.usable`; a potion is drunk:
##   `bag_use_requested`, the owner's of 2026-11-19) and X drops one where its kind can be dropped
##   (`ItemKinds.can`). A d-pad arm (`quick_*`; 1-4 on the keyboard) binds the usable item pointed
##   at to that arm's quick-use slot, as a hand's button puts a staff on a hand
##   (`quick_bind_requested`; the owner, 2026-11-20): bound on another arm it moves, bound on that
##   arm already it is let go. Each item bound shows its arm's glyph beside it on the ring, and the
##   hint row says "Bind". **An item bound with none left stays on the ring** (the owner,
##   2026-11-20), after the ones held, its icon greyed and its count 0, so it can be let go or bound
##   to another arm there; it leaves the ring as it is let go. Its icon greys and fills again through
##   GREY_STAGES shades (Smooth). An item recharging after a use (an active relic's cooldown,
##   `item_recharging`) has a shutter over its icon sinking a whole row at a time (`RechargeShutter`),
##   and Use is dimmed until it is ready.
## - **The column:** the HP bar, then the four hands, each its button's glyph, its staff's head and
##   numbers (`NUMBERS`), and while a staff is pointed at an arrow beside each number of every other
##   hand's staff: up or down as the pointed staff's number is higher or lower, green where that is
##   better, red where it is worse (`StaffBase.BETTER`); then what is pointed at (a staff's name and
##   cards, a card's name, kind and lore, a bag's name) and a refusal's note over its top.
##
## It shows only what the seat's events say (`inventory_announced`, `bag_changed`,
## `owned_staff_changed`, `hands_changed`, kept in an `InventoryMirror`; `inventory_refused`; `player_stats_changed` for the HP bar) and asks
## for every change as a command (`staff_hand_requested`, `bag_drop_requested`, `bag_use_requested`), so it holds no
## rules: the simulation checks each request, applies or refuses it, and says what happened. It
## opens through `core/ui_focus` with itself as its one control (capture, the "MENU" word, A as
## `activated`, B as `cancelled`, X as `alternate`), and reads the hand buttons, the sticks and
## Select from `core/input` for its own player only.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const MeterLineScript := preload("res://hud/widgets/meter_line.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const RadialMenuScript := preload("res://hud/widgets/radial_menu.gd")
const CardKindsScript := preload("res://hud/widgets/card_kinds.gd")
const MirrorScript := preload("res://hud/widgets/inventory_mirror.gd")
const StaffHeadScript := preload("res://hud/widgets/staff_head.gd")
const RechargeShutter := preload("res://hud/widgets/recharge_shutter.gd")
const HudArt := preload("res://hud/widgets/hud_art.gd")

const NONE: int = -1
const PLAYER_COUNT: int = 4
const HANDS: int = 4
## Each hand's button, by hand (0 RB, 1 RT, 2 LB, 3 LT).
const HAND_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## The hand whose button (RT) also enters a bag or a card kind, as A does.
const ENTER_HAND: int = 1
## The button that opens and closes it.
const TOGGLE_ACTION: StringName = &"inventory"
## The hint row's buttons: enter, drop, back, close.
const HINT_ACTIONS: Array[StringName] = [&"accept", &"alternate", &"back", &"inventory", &"dpad"]
## The d-pad's arms by quick-use slot (0 up, 1 right, 2 down, 3 left), as the input manager has them.
const QUICK_ACTIONS: Array[StringName] = InputManagerScript.QUICK_ACTIONS
## Each hand's staff in words, by hand, as the builder names it (a sigil's line says which have it).
const HAND_WORDS: Array[String] = ["staff 1", "staff 2", "staff 3", "staff 4"]
## The buttons read here (the rest come as UIFocus signals).
const READ_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4", &"inventory", &"quick_up", &"quick_right", &"quick_down", &"quick_left"]
## Which layer the ring shows.
enum Layer { BAGS, STAFFS, KINDS, CARDS, ITEMS, SIGIL_STAFFS }
## Each bag's word.
const BAG_WORDS: Dictionary = {&"staffs": "Staffs", &"cards": "Cards", &"relics": "Relics", &"potions": "Potions", &"sigils": "Sigils", &"currency": "Currency"}
## The staff numbers the column shows, in order, with their headers and how each is written.
const NUMBERS: Array[String] = ["slots", "cooldown", "max_mana"]
const NUMBER_WORDS: Array[String] = ["Slots", "Delay", "Mana"]
## The key that names each kind of ring entry.
const ENTRY_KEYS: Array[String] = ["bag", "staff", "kind", "card", "item"]

const OUTLINE: Color = Color("#14121f")
const SHADE: Color = Color(0.078, 0.071, 0.122, 0.86)
const TILE: Color = Color("#2b2840")
const LINE: Color = Color("#4a4663")
const TEXT: Color = Color("#f4f1ea")
const MUTED: Color = Color("#a39fb8")
const DIM: Color = Color("#7a7694")
const GOLD: Color = Color("#f2c230")
const WARN: Color = Color("#e0592f")
## The arrows: a better number, a worse one (and their shape says up or down).
const BETTER: Color = Color("#6fd46a")
const WORSE: Color = Color("#e0592f")
## The HUD's health colour (`meter_line.gd`), as on the corner panel and the builder.
const HEALTH_COLOR: Color = MeterLineScript.HEALTH_COLOR

## The layout, in the view's pixels from the quarter's top left, the same in every quarter.
const EDGE: float = 4.0
const COLUMN_WIDTH: float = 112.0
const BAR_HEIGHT: float = 4.0
## How far outside the HP line's top-left corner the player's corner mark starts.
const MARK_OUT: Vector2 = Vector2(3.0, 2.0)
const HANDS_FROM_TOP: float = 8.0
const HAND_ROW: float = 18.0
const HEAD_SIZE: float = 16.0
const RING_FROM_EDGE: float = 84.0
const RING_RADIUS: float = RadialMenuScript.RING_RADIUS
const HINT_HEIGHT: float = RadialMenuScript.HINT_HEIGHT
const TILE_SIZE: float = 18.0
const TILE_PICKED: float = 20.0
const ICON_SIZE: float = 16.0
const SMALL_ICON: float = 8.0
const LINE_STEP: float = 9.0
## The left stick steps the pointer round the ring past this push, with key-repeat.
const MOVE_THRESHOLD: float = 0.5
const MOVE_DELAY: float = 0.3
const MOVE_REPEAT: float = 0.14
const POP_TIME: float = 0.07
const NOTE_TIME: float = 1.4

const OPEN_VERB: String = "Open"
const USE_VERB: String = "Use"
## A on a staff of a sigil's ring (staff-language L4).
const PUT_ON_VERB: String = "Put on"
const TAKE_OFF_VERB: String = "Take off"
const BIND_VERB: String = "Bind"
## An item with none left (bound, so on the ring) is drawn in this shade, reached through GREY_STAGES
## whole steps of the tint at GREY_FPS (Smooth), as the panel's cross greys its slot.
const GREY: Color = Color(0.32, 0.31, 0.38, 1.0)
const GREY_STAGES: int = 3
const GREY_FPS: float = 20.0
const DROP_VERB: String = "Drop"
const BACK_VERB: String = "Back"
const CLOSE_VERB: String = "Close"
const EMPTY_TEXT: String = "Empty"
const POINT_TEXT: String = "Point"
const IN_BAG_TEXT: String = "In the bag"

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _spells: SpellsScript = null
## The registry (an item's look, `ItemLooks`), found as it is first needed.
var _registry: RegistryScript = null
var _input: InputManagerScript = null

## What the seat's events said of its inventory.
var _mirror: MirrorScript = MirrorScript.new()
## The ring (its places, pointing, layers and hint row).
var _menu: RadialMenuScript = RadialMenuScript.new(self)
## The layer shown, the bag entered (`&""` on the first ring) and the kind of card entered.
var _layer: Layer = Layer.BAGS
var _bag: StringName = &""
var _kind: StringName = &""
## The sigil whose staffs ring is shown (staff-language L4: A on a sigil), else empty.
var _sigil: StringName = &""
## The ring's entries, by entry number: {"bag"}, {"staff"}, {"kind", "count"}, {"card", "count"} or
## (a relic, a potion, the coins or the keys) {"item", "count"}; the first key names it (`ENTRY_KEYS`).
var _entries: Array[Dictionary] = []

var _open: bool = false
var _health: float = -1.0
var _max_health: float = 100.0
var _note: String = ""
var _note_left: float = 0.0
var _clock: float = 0.0
var _dirty: bool = true
## The press counts of the buttons read here, at the last poll.
var _seen: Dictionary = {}
## The left stick's step round the ring: its way now (-1, 0, 1) and the wait before it repeats;
## and whether the entry pointed at was pointed by the right stick or the mouse (letting go of
## them lets it go) rather than stepped to.
var _step_way: int = 0
var _step_wait: float = 0.0
var _aimed: bool = false

## Laid out by `_place()`: the quarter, the column, the hands' rows' top left and the info box.
var _quarter: Rect2 = Rect2()
var _column: Rect2 = Rect2()
var _hands_at: Vector2 = Vector2.ZERO
var _info: Rect2 = Rect2()
## Each hand's glyph in the column, and on the staffs ring beside each staff on a hand.
var _hand_glyphs: Array[ActionGlyphScript] = []
var _ring_glyphs: Array[ActionGlyphScript] = []
## On a ring of items, each quick-use slot's arm glyph beside the item bound to it.
var _quick_glyphs: Array[ActionGlyphScript] = []
## By item id on the ring of items: its shade drawn (0 its icon ... GREY_STAGES greyed), and the
## clock that steps it.
var _shade: Dictionary = {}
var _shade_clock: float = 0.0
## The ring of items' ids in the order they came onto it while this bag is open (one gone stays
## remembered): an item that runs out (bound, so kept on the ring with 0), or is gone a moment as its
## binding moves, keeps its place instead of jumping to the end (Smooth).
var _item_order: Array[StringName] = []
## Items recharging after a use (`item_recharging`: an active relic's cooldown, told by the
## simulation at each sixteenth): "bag/id" -> the shutter rows told (of ICON_SIZE); drawn as a shutter
## over the item's icon. The ring keeps no clock for it.
var _charges: Dictionary = {}
## By "bag/id": the shutter rows drawn, stepping a row a frame toward those told (Smooth), and the
## clock that steps them.
var _charge_rows: Dictionary = {}
var _charge_clock: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)
	for hand in HANDS:
		_hand_glyphs.append(_make_glyph("GlyphHand%d" % hand))
	for hand in HANDS:
		var glyph: ActionGlyphScript = _make_glyph("RingHand%d" % hand)
		glyph.visible = false
		_ring_glyphs.append(glyph)
	for slot in QUICK_ACTIONS.size():
		var quick: ActionGlyphScript = _make_glyph("RingQuick%d" % slot)
		quick.visible = false
		_quick_glyphs.append(quick)
	_menu.make_hints(HINT_ACTIONS)
	for action in READ_ACTIONS:
		_seen[action] = 0


## Connect to the event bus, the focus service, the spell runtime (names and icons) and the input
## manager (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript, spells: SpellsScript, input: InputManagerScript = null) -> void:
	_events = events
	_ui_focus = ui_focus
	_spells = spells
	_input = input
	_menu.bind(input, index)
	for hand in HANDS:
		for glyph: ActionGlyphScript in [_hand_glyphs[hand], _ring_glyphs[hand]]:
			glyph.bind(input)
			glyph.show_action(index, HAND_ACTIONS[hand])
	for slot in _quick_glyphs.size():
		_quick_glyphs[slot].bind(input)
		_quick_glyphs[slot].show_action(index, QUICK_ACTIONS[slot])
	if _events != null:
		_events.inventory_announced.connect(_on_inventory_announced)
		_events.bag_changed.connect(_on_bag_changed)
		_events.owned_staff_changed.connect(_on_owned_staff_changed)
		_events.hands_changed.connect(_on_hands_changed)
		_events.quick_bound.connect(_on_quick_bound)
		_events.item_recharging.connect(_on_item_recharging)
		_events.inventory_refused.connect(_on_inventory_refused)
		_events.player_stats_changed.connect(_on_stats_changed)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.alternate.connect(_on_alternate)


func is_open() -> bool:
	return _open


## Open it for its owner on the first ring (closing any other panel of theirs). False if the owner
## has no device.
func open_inventory() -> bool:
	if _open or _ui_focus == null:
		return false
	_place()
	_ui_focus.close(index)
	visible = true
	var controls: Array[Control] = [self]
	if not _ui_focus.open(index, controls):
		visible = false
		return false
	_open = true
	_note = ""
	_note_left = 0.0
	_step_way = 0
	_aimed = false
	_menu.leave_layers()
	_sigil = &""
	_show_layer()
	_prime()
	set_process(true)
	_changed()
	return true


## Close it if it is open.
func close_inventory() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## What the seat's events said of its inventory (for tests and the panels).
func mirror() -> MirrorScript:
	return _mirror


## The layer the ring shows, the bag entered (`&""` on the first ring) and the kind entered.
func layer() -> Layer:
	return _layer


func entered_bag() -> StringName:
	return _bag


## The ring's entries (copies), by entry number.
func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


## The entry pointed at ({} for none).
func pointed() -> Dictionary:
	return _entries[_menu.pointed].duplicate() if _menu.pointed >= 0 and _menu.pointed < _entries.size() else {}


## The shared radial menu the ring is (for tests).
func menu() -> RadialMenuScript:
	return _menu


## Point at entry `entry` (NONE lets go), as the sticks would.
func point_at(entry: int) -> void:
	_aimed = false
	if _menu.point_at(entry, _clock):
		_changed()


## The entry whose `key` is `value`, or NONE (for tests: the staff, the card or the bag on the ring).
func entry_of(key: String, value: Variant) -> int:
	for at in _entries.size():
		if _entries[at].has(key) and _entries[at][key] == value:
			return at
	return NONE


## The note over the info box (a refusal's words), or "" once it faded.
func note_text() -> String:
	return _note if _note_left > 0.0 else ""


## The hint row's verbs, as shown.
func hint_verbs() -> Array[String]:
	return _menu.hint_verbs()


## The words in the ring's middle, top to bottom.
func hub_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var entry: Dictionary = pointed()
	match _layer:
		Layer.BAGS:
			if entry.is_empty():
				lines.append_array(["Inventory", POINT_TEXT])
			else:
				lines.append_array([_bag_word(entry["bag"]), _mirror.fill_text(entry["bag"])])
		Layer.STAFFS:
			if entry.is_empty():
				lines.append_array([_bag_word(_bag), _mirror.fill_text(_bag), EMPTY_TEXT if _entries.is_empty() else POINT_TEXT])
			else:
				var number: int = entry["staff"]
				var hand: int = _mirror.hand_of(number)
				lines.append_array([_staff_name(number), "On a hand" if hand != NONE else IN_BAG_TEXT])
		Layer.KINDS:
			if entry.is_empty():
				lines.append_array([_bag_word(_bag), _mirror.fill_text(_bag), EMPTY_TEXT if _entries.is_empty() else POINT_TEXT])
			else:
				lines.append_array([String(CardKindsScript.WORDS.get(entry["kind"], entry["kind"])), "%d cards" % int(entry["count"])])
		Layer.CARDS:
			if entry.is_empty():
				lines.append_array([String(CardKindsScript.WORDS.get(_kind, _kind)), POINT_TEXT])
			else:
				lines.append_array([_card_name(entry["card"]), "x%d" % int(entry["count"])])
		Layer.ITEMS:
			if entry.is_empty():
				lines.append_array([_bag_word(_bag), _mirror.fill_text(_bag), EMPTY_TEXT if _entries.is_empty() else POINT_TEXT])
			else:
				lines.append_array([String(_look(entry["item"])["name"]), "x%d" % int(entry["count"])])
	return lines


## Per hand: the arrows beside its staff's numbers (`NUMBERS`) against the staff pointed at: 1 the
## pointed one is better there, -1 worse, 0 the same, neither way, no staff on the hand, the hand's
## own staff or none pointed at. Allocates; for drawing and tests.
func hand_arrows(hand: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(NUMBERS.size())
	var entry: Dictionary = pointed()
	var held: StaffBase = _mirror.base_of(_mirror.on_hand(hand))
	if _layer != Layer.STAFFS or entry.is_empty() or held == null or _mirror.on_hand(hand) == int(entry["staff"]):
		return out
	var other: StaffBase = _mirror.base_of(entry["staff"])
	if other == null:
		return out
	for at in NUMBERS.size():
		out[at] = held.compared(other, NUMBERS[at])
	return out


## Read the buttons and sticks and act. Called every frame while open; tests call it with fixed
## steps.
func step(delta: float) -> void:
	if not _open:
		return
	_clock += delta
	if _presses(TOGGLE_ACTION) > 0:
		close_inventory()
		return
	_poll_hands()
	_poll_quick()
	_poll_step(delta)
	_poll_pointer()
	if _note_left > 0.0:
		_note_left -= delta
		_dirty = true
	_step_shades(delta)
	_step_charges(delta)
	if _menu.pointed_for(_clock) < POP_TIME:
		_dirty = true
	if _dirty:
		_dirty = false
		_refresh_hints()
		_place_ring_glyphs()
		queue_redraw()


func _process(delta: float) -> void:
	step(delta)


# --- Input ------------------------------------------------------------------------------

func _prime() -> void:
	if _input == null:
		return
	for action in READ_ACTIONS:
		_seen[action] = _input.get_press_count(index, action)


func _presses(action: StringName) -> int:
	if _input == null:
		return 0
	var count: int = _input.get_press_count(index, action)
	var new: int = count - int(_seen[action])
	_seen[action] = count
	return maxi(new, 0)


## The hand buttons: on the staffs ring, the pointed staff onto that hand (or off it); on the bags'
## and the card kinds' rings, RT (`staff_2`, P1's left click) enters what is pointed at as A does
## (the owner, 2026-11-19), and P1's left click does on any other ring too.
func _poll_hands() -> void:
	for hand in HANDS:
		for _press in _presses(HAND_ACTIONS[hand]):
			if _layer == Layer.STAFFS:
				put_on_hand(hand)
			elif _layer == Layer.ITEMS and _in_sigils():
				sigil_to_hand(hand)
			elif hand == ENTER_HAND and (_layer == Layer.BAGS or _layer == Layer.KINDS or _menu.uses_mouse()):
				enter_pointed()


## The d-pad's arms: on a ring of items, the usable item pointed at bound to that arm (`bind_pointed`).
func _poll_quick() -> void:
	for slot in QUICK_ACTIONS.size():
		for _press in _presses(QUICK_ACTIONS[slot]):
			bind_pointed(slot)


## The left stick (P1's move keys) steps the pointer round the ring, with key-repeat.
func _poll_step(delta: float) -> void:
	var move: Vector2 = _input.menu_move(index) if _input != null else Vector2.ZERO
	var way: int = 0
	if move.length() > MOVE_THRESHOLD:
		way = int(signf(move.x)) if absf(move.x) >= absf(move.y) else int(signf(move.y))
	if way != _step_way:
		_step_way = way
		_step_wait = MOVE_DELAY
		if way != 0:
			_step_round(way)
	elif way != 0:
		_step_wait -= delta
		if _step_wait <= 0.0:
			_step_wait = MOVE_REPEAT
			_step_round(way)


## Point at the entry `way` places round the ring from the one pointed at (the first with none).
func _step_round(way: int) -> void:
	var places: PackedInt32Array = _menu.place_entries()
	if places.is_empty():
		return
	var at: int = places.find(_menu.pointed)
	var next: int = 0 if at < 0 else posmod(at + way, places.size())
	_aimed = false
	if _menu.point_at(places[next], _clock):
		_rumble(UiHaptics.POINT)
		_changed()


## The right stick (P1's mouse) points; letting go of it lets go what it pointed at.
func _poll_pointer() -> void:
	var aim: Vector2 = _menu.aim()
	if _menu.follow(aim):
		_dirty = true
	if aim == Vector2.ZERO:
		if _aimed:
			_aimed = false
			if _menu.point_at(NONE, _clock):
				_changed()
		return
	var picked: int = _menu.pick_on_ring(aim)
	_aimed = true
	if _menu.point_at(picked, _clock):
		if picked != NONE:
			_rumble(UiHaptics.POINT)
		_changed()


## Rumble the player's pad (`UiHaptics`): pointing is felt, not heard (owner, 2026-11-19).
func _rumble(motors: Vector3) -> void:
	UiHaptics.pulse(_input, index, motors)


## The menu sound `id` (`UiSounds`, sound plan AU8), only while the inventory is open: a refusal
## that comes back after it closed says nothing.
func _sound(id: StringName) -> void:
	if _open:
		UiSounds.send(_events, id)


# --- What the buttons do ----------------------------------------------------------------

## A: enter the bag or the kind pointed at; on an item that can be used, use one
## (`bag_use_requested`: a potion drunk). Nothing on a ring with nothing to enter.
func enter_pointed() -> void:
	var entry: Dictionary = pointed()
	if _layer == Layer.ITEMS and _events != null and _item_usable(entry) and int(entry["count"]) > 0:
		_sound(UiSounds.CHOOSE)
		_events.bag_use_requested.emit(index, _bag, entry["item"], _mirror.body)
		return
	if _layer == Layer.ITEMS and _in_sigils() and entry.has("item"):
		# A sigil: the ring of every staff owned, to put it on or take it off.
		_sigil = entry["item"]
		_menu.enter(_menu.pointed)
		_aimed = false
		_sound(UiSounds.CHOOSE)
		_show_layer()
		_changed()
		return
	if _layer == Layer.SIGIL_STAFFS and _events != null and entry.has("staff"):
		_sound(UiSounds.CHOOSE)
		var number: int = entry["staff"]
		if _mirror.sigils_of(number).has(_sigil):
			_events.sigil_take_requested.emit(index, number, _sigil, _mirror.body)
		else:
			_events.sigil_put_requested.emit(index, number, _sigil, _mirror.body)
		return
	if entry.is_empty() or not (_layer == Layer.BAGS or _layer == Layer.KINDS):
		return
	if _layer == Layer.BAGS:
		_bag = entry["bag"]
	else:
		_kind = entry["kind"]
	_menu.enter(_menu.pointed)
	_aimed = false
	_sound(UiSounds.CHOOSE)
	_show_layer()
	_changed()


## B: back out one layer; on the first ring, close.
func go_back() -> void:
	if _menu.depth() == 0:
		close_inventory()
		return
	if _layer == Layer.CARDS:
		_kind = &""
	elif _layer == Layer.SIGIL_STAFFS:
		_sigil = &""
	else:
		_bag = &""
	_menu.back()
	_aimed = false
	var keep: int = _menu.pointed
	_show_layer()
	_menu.pointed = keep if keep >= 0 and keep < _entries.size() else NONE
	_changed()


## A hand's button on the staffs ring: the pointed staff onto hand `hand`, or off it into the bag
## when it is on that hand already (`staff_hand_requested`).
func put_on_hand(hand: int) -> void:
	var entry: Dictionary = pointed()
	if _layer != Layer.STAFFS or entry.is_empty() or _events == null:
		return
	var number: int = entry["staff"]
	_sound(UiSounds.CHOOSE)
	_events.staff_hand_requested.emit(index, number, NONE if _mirror.hand_of(number) == hand else hand, _mirror.body)


## A hand's button on the sigils ring: the pointed sigil onto the staff on hand `hand`, or off it when
## that staff has it already (staff-language L4; the simulation checks: `sigil_put_requested`,
## `sigil_take_requested`).
func sigil_to_hand(hand: int) -> void:
	var entry: Dictionary = pointed()
	if not entry.has("item") or _events == null:
		return
	var number: int = _mirror.on_hand(hand)
	if number == NONE:
		return
	var id: StringName = entry["item"]
	_sound(UiSounds.CHOOSE)
	if _mirror.sigils_of(number).has(id):
		_events.sigil_take_requested.emit(index, number, id, _mirror.body)
	else:
		_events.sigil_put_requested.emit(index, number, id, _mirror.body)


## True while the ring shows the sigils bag.
func _in_sigils() -> bool:
	return _bag != &"" and ItemKinds.kind_in(_bag) == ItemKinds.SIGIL


## A d-pad arm on a ring of items: the usable item pointed at bound to quick-use slot `slot` (or let
## go when it is bound there already: the simulation's rule, `quick_bind_requested`).
func bind_pointed(slot: int) -> void:
	var entry: Dictionary = pointed()
	if _layer != Layer.ITEMS or _events == null or not _item_usable(entry):
		return
	_sound(UiSounds.CHOOSE)
	_events.quick_bind_requested.emit(index, slot, _bag, entry["item"], _mirror.body)


## X: drop the staff pointed at, or one copy of the card or item (`bag_drop_requested`).
func drop_pointed() -> void:
	var entry: Dictionary = pointed()
	if entry.is_empty() or _events == null:
		return
	if _layer == Layer.ITEMS:
		if int(entry["count"]) > 0 and (_item_can(entry, ItemKinds.DROP) or _item_can(entry, ItemKinds.DROP_ONE)):
			_sound(UiSounds.CHOOSE)
			_events.bag_drop_requested.emit(index, _bag, entry["item"], NONE, _mirror.body)
		return
	if _layer == Layer.STAFFS or _layer == Layer.CARDS:
		_sound(UiSounds.CHOOSE)
	if _layer == Layer.STAFFS:
		var base: StaffBase = _mirror.base_of(entry["staff"])
		_events.bag_drop_requested.emit(index, _bag, base.id if base != null else &"", int(entry["staff"]), _mirror.body)
	elif _layer == Layer.CARDS:
		_events.bag_drop_requested.emit(index, _bag, entry["card"], NONE, _mirror.body)


# --- What it hears ----------------------------------------------------------------------

func _on_inventory_announced(player: int, body: int) -> void:
	if player != index:
		return
	_charges.clear()
	_charge_rows.clear()
	_mirror.clear(body)
	_refill()


func _on_bag_changed(player: int, bag: StringName, ids: Array[StringName], counts: PackedInt32Array, capacity: int) -> void:
	if player != index:
		return
	_mirror.hear_bag(bag, ids, counts, capacity)
	_refill()


func _on_owned_staff_changed(player: int, staff: int, plan: Dictionary) -> void:
	if player != index:
		return
	_mirror.hear_staff(staff, plan)
	_refill()


func _on_hands_changed(player: int, hands: PackedInt32Array) -> void:
	if player != index:
		return
	_mirror.hear_hands(hands)
	_refill()


func _on_quick_bound(player: int, slot: int, bag: StringName, id: StringName) -> void:
	if player != index:
		return
	_mirror.hear_quick(slot, bag, id)
	# An item with none left is on the ring only while bound.
	_refill()


func _on_inventory_refused(player: int, reason: String) -> void:
	if player != index:
		return
	_note = reason
	_note_left = NOTE_TIME
	_sound(UiSounds.DENY)
	_changed()


func _on_stats_changed(player: int, health: float, max_health: float, _mana: float, _max_mana: float) -> void:
	if player != index:
		return
	_health = health
	_max_health = maxf(max_health, 1.0)
	_changed()


func _on_closed(player: int) -> void:
	if player != index:
		return
	_open = false
	visible = false
	set_process(false)


func _on_activated(player: int, _control: Control) -> void:
	if player == index and _open:
		enter_pointed()


func _on_cancelled(player: int) -> void:
	if player == index and _open:
		go_back()


func _on_alternate(player: int, _control: Control) -> void:
	if player == index and _open:
		drop_pointed()


# --- The ring ---------------------------------------------------------------------------

## The inventory changed: the ring is laid out again, keeping what was pointed at if it is still
## there (a kind or a bag entered that emptied stays open, empty).
func _refill() -> void:
	var keep: Dictionary = pointed()
	_show_layer()
	_menu.pointed = NONE
	for key: String in ENTRY_KEYS:
		if keep.has(key):
			_menu.pointed = entry_of(key, keep[key])
	_changed()


## Lay the ring out for the layer the bag and kind entered say.
func _show_layer() -> void:
	var was_items: bool = _layer == Layer.ITEMS
	_entries.clear()
	if _bag == &"":
		_layer = Layer.BAGS
		for bag: StringName in ItemKinds.BAGS:
			_entries.append({"bag": bag})
	else:
		var kind: StringName = ItemKinds.kind_in(_bag)
		if kind == ItemKinds.SIGIL and _sigil != &"":
			_layer = Layer.SIGIL_STAFFS
			for number in _mirror.staffs():
				_entries.append({"staff": number, "sigil": _sigil})
		elif kind == ItemKinds.STAFF:
			_layer = Layer.STAFFS
			for number in _mirror.staffs():
				_entries.append({"staff": number})
		elif kind == ItemKinds.CARD and _kind == &"":
			_layer = Layer.KINDS
			for card_kind: StringName in CardKindsScript.KINDS:
				var count: int = _cards_of_kind(card_kind).size()
				if count > 0:
					_entries.append({"kind": card_kind, "count": count})
		elif kind == ItemKinds.CARD:
			_layer = Layer.CARDS
			for id: StringName in _cards_of_kind(_kind):
				_entries.append({"card": id, "count": _mirror.count_of(_bag, id)})
		else:
			_layer = Layer.ITEMS
			var ids: Array[StringName] = _mirror.ids_in(_bag)
			for slot in QUICK_ACTIONS.size():
				var bound: StringName = _mirror.quick_id(slot)
				if bound != &"" and _mirror.quick_slot_of(_bag, bound) == slot and not ids.has(bound):
					ids.append(bound)
			if _in_sigils():
				# The sigils on the hands' staffs stay on the ring with none left, to take off there.
				for hand in HANDS:
					for id: StringName in _mirror.sigils_of(_mirror.on_hand(hand)):
						if not ids.has(id):
							ids.append(id)
			if not was_items:
				_shade.clear()
				_item_order.clear()
			for id: StringName in _kept_order(ids):
				_entries.append({"item": id, "count": _mirror.count_of(_bag, id)})
			_keep_shades()
	var places := PackedInt32Array()
	var widths := PackedFloat32Array()
	for at in _entries.size():
		places.append(at)
		widths.append(1.0)
	_menu.lay_out(places, widths)
	if _menu.pointed >= _entries.size():
		_menu.pointed = NONE


## The card ids of kind `kind` in the card bag, A to Z by the name shown.
func _cards_of_kind(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _mirror.ids_in(ItemKinds.bag_of(ItemKinds.CARD)):
		if _spells != null and _spells.component_kind(id) == kind:
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var by_name: int = _card_name(a).naturalnocasecmp_to(_card_name(b))
		return by_name < 0 if by_name != 0 else String(a) < String(b))
	return out


func _refresh_hints() -> void:
	var entry: Dictionary = pointed()
	var can_enter: bool = not entry.is_empty() and (_layer == Layer.BAGS or _layer == Layer.KINDS)
	var can_drop: bool = not entry.is_empty() and (_layer == Layer.STAFFS or _layer == Layer.CARDS)
	var first: String = OPEN_VERB
	if _layer == Layer.SIGIL_STAFFS:
		var has: bool = entry.has("staff") and _mirror.sigils_of(entry["staff"]).has(_sigil)
		first = TAKE_OFF_VERB if has else PUT_ON_VERB
		can_enter = entry.has("staff")
	elif _layer == Layer.ITEMS and _in_sigils():
		first = OPEN_VERB
		can_enter = entry.has("item")
		can_drop = entry.has("item") and int(entry["count"]) > 0
	elif _layer == Layer.ITEMS:
		first = USE_VERB
		var held: bool = entry.has("item") and int(entry["count"]) > 0
		can_enter = held and _item_usable(entry) and not recharging(entry["item"])
		can_drop = held and (_item_can(entry, ItemKinds.DROP) or _item_can(entry, ItemKinds.DROP_ONE))
	var can_bind: bool = _layer == Layer.ITEMS and _item_usable(entry)
	var verbs: Array[String] = [first, DROP_VERB, CLOSE_VERB if _menu.depth() == 0 else BACK_VERB, CLOSE_VERB, BIND_VERB]
	var live: Array[bool] = [can_enter, can_drop, true, true, can_bind]
	_menu.set_hints(verbs, live)


## On the staffs ring, each hand's glyph beside the staff on it.
func _place_ring_glyphs() -> void:
	for hand in HANDS:
		var glyph: ActionGlyphScript = _ring_glyphs[hand]
		var entry: int = entry_of("staff", _mirror.on_hand(hand)) if _open and _layer == Layer.STAFFS and _mirror.on_hand(hand) != NONE else NONE
		glyph.visible = entry != NONE
		if entry == NONE:
			continue
		var middle: Vector2 = _menu.tile_center(_menu.angle_of_entry(entry), RING_RADIUS + TILE_SIZE * 0.5 + 6.0)
		glyph.position = (middle - glyph.custom_minimum_size * 0.5).round()
	for slot in _quick_glyphs.size():
		var quick: ActionGlyphScript = _quick_glyphs[slot]
		var bound: StringName = _mirror.quick_id(slot)
		var at: int = entry_of("item", bound) if _open and _layer == Layer.ITEMS and bound != &"" and _mirror.quick_slot_of(_bag, bound) == slot else NONE
		quick.visible = at != NONE
		if at == NONE:
			continue
		# Inside the ring, so an item at its top never pushes the glyph off the view.
		var spot: Vector2 = _menu.tile_center(_menu.angle_of_entry(at), RING_RADIUS - TILE_SIZE * 0.5 - 7.0)
		quick.position = (spot - quick.custom_minimum_size * 0.5).round()


## The top left of the quarter it lays itself out in (view pixels; INF: its own corner's), set by
## `panels.gd` as its seat's HUD spot moves (`hud/panels/seat_corners.gd`).
var quarter_at: Vector2 = Vector2.INF


## Lay it out in the quarter at `at` from now on (`quarter_at`), at once while it is open: `panels.gd`
## calls it a frame at a time as the quarter slides by whole pixels.
func move_quarter(at: Vector2) -> void:
	quarter_at = at
	if visible:
		_place()
		queue_redraw()


# --- Layout and drawing -----------------------------------------------------------------

func _place() -> void:
	# In layout pixels: the HUD is laid out at 640 x 360 and drawn at the picture's scale (PictureGrid).
	var view: Vector2 = PictureGrid.layout_of(get_viewport())
	var half: Vector2 = (view * 0.5).floor()
	var right: bool = index % 2 == 1
	var bottom: bool = index >= 2
	_quarter = Rect2(Vector2(half.x if right else 0.0, half.y if bottom else 0.0), half)
	if quarter_at.is_finite():
		# Its seat's quarter as the HUD has it now (the equal split's panes may move it).
		_quarter.position = quarter_at
	var column_x: float = _quarter.position.x + EDGE
	var top: float = _quarter.position.y + 2.0
	_column = Rect2(column_x, top, COLUMN_WIDTH, _quarter.size.y - 4.0)
	_hands_at = Vector2(column_x + 2.0, top + HANDS_FROM_TOP + LINE_STEP)
	for hand in HANDS:
		_hand_glyphs[hand].position = Vector2(_hands_at.x, _hands_at.y + hand * HAND_ROW + 3.0)
	var info_top: float = _hands_at.y + HANDS * HAND_ROW + 3.0
	_info = Rect2(column_x + 2.0, info_top, COLUMN_WIDTH - 4.0, _quarter.end.y - 3.0 - info_top)
	var ring_left: float = column_x + COLUMN_WIDTH + EDGE
	var ring_right: float = _quarter.end.x - EDGE
	_menu.center = Vector2(floorf((ring_left + ring_right) * 0.5), _quarter.position.y + RING_FROM_EDGE)
	_menu.hints_at = Vector2(ring_left, _quarter.end.y - HINT_HEIGHT - 2.0)


func _changed() -> void:
	_dirty = true
	if _open and not is_processing():
		set_process(true)


func _draw() -> void:
	if not _open:
		return
	draw_rect(_quarter, SHADE)
	_draw_bar()
	_draw_hands()
	_draw_info()
	_draw_ring()
	_draw_hub()
	_menu.draw_hints()


## The HP line on top of the column in its trough, with no frame round it (ART4, the owner,
## 2026-11-27: no HUD boxes); the player's small corner L just outside its top-left corner (inside the quarter) says
## whose inventory it is.
func _draw_bar() -> void:
	var share: float = clampf(_health / _max_health, 0.0, 1.0) if _health >= 0.0 else 1.0
	HudArt.meter(self, Rect2(_column.position, Vector2(COLUMN_WIDTH, BAR_HEIGHT - 1.0)), share, HEALTH_COLOR, MeterLineScript.HEALTH_SHADE)
	HudArt.corner_mark(self, _column.position - MARK_OUT, HudArt.player_ramp(index))


## The four hands: the numbers' headers, then per hand its glyph, its staff's head and numbers,
## with the arrows against the staff pointed at.
func _draw_hands() -> void:
	var number_x: float = _hands_at.x + 34.0
	var step_x: float = (_column.end.x - 2.0 - number_x) / NUMBERS.size()
	for at in NUMBER_WORDS.size():
		_text(NUMBER_WORDS[at], Vector2(number_x + at * step_x, _hands_at.y - LINE_STEP), DIM)
	for hand in HANDS:
		var y: float = _hands_at.y + hand * HAND_ROW
		var number: int = _mirror.on_hand(hand)
		var base: StaffBase = _mirror.base_of(number)
		var head := Rect2(Vector2(_hands_at.x + 14.0, y + 0.0), Vector2(HEAD_SIZE, HEAD_SIZE))
		var pointed_here: bool = _layer == Layer.STAFFS and not pointed().is_empty() and int(pointed()["staff"]) == number and number != NONE
		# A quiet slot with no frame; a gold one round the staff pointed at (ART4).
		draw_rect(HudArt.inside_cut(head), TILE if base != null else OUTLINE)
		if pointed_here:
			HudArt.tile(self, head, HudArt.SPARK[HudArt.LIGHT], HudArt.SPARK[HudArt.BASE])
		if base == null:
			_text("-", Vector2(head.get_center().x, y + 4.0), DIM, true)
			continue
		StaffHeadScript.draw(self, base.head, head.grow(-1.0), index)
		var arrows: PackedInt32Array = hand_arrows(hand)
		var other: StaffBase = _mirror.base_of(int(pointed()["staff"])) if _layer == Layer.STAFFS and not pointed().is_empty() else null
		for at in NUMBERS.size():
			var x: float = number_x + at * step_x
			var words: String = _number_text(base, NUMBERS[at])
			_text(words, Vector2(x, y + 4.0), TEXT)
			if arrows[at] != 0 and other != null:
				var up: bool = float(other.get(NUMBERS[at])) > float(base.get(NUMBERS[at]))
				_draw_arrow(Vector2(x + _text_width(words) + 4.0, y + 8.0), up, BETTER if arrows[at] > 0 else WORSE)


## A small arrow, pointing up or down, its middle at `at`.
func _draw_arrow(at: Vector2, up: bool, color: Color) -> void:
	var tip: float = -3.0 if up else 3.0
	var points := PackedVector2Array([at + Vector2(0.0, tip), at + Vector2(-3.0, -tip), at + Vector2(3.0, -tip)])
	draw_colored_polygon(points, color)


## A staff's number `field` as the column writes it.
func _number_text(base: StaffBase, field: String) -> String:
	return number_text(float(base.get(field)), field == "cooldown" or field == "wind_up")


## A number as the column writes it, short enough for its place: seconds with an "s" and no
## trailing zeros ("0.15s", "0.5s", "2s"), anything else whole, a big one in thousands ("12k") or
## millions ("1M").
static func number_text(value: float, seconds: bool) -> String:
	if seconds:
		var words: String = ("%.2f" % value).rstrip("0").rstrip(".")
		return (words if words != "" else "0") + "s"
	var whole: int = int(roundf(value))
	if absi(whole) >= 1000000:
		return "%dM" % int(roundf(value / 1000000.0))
	if absi(whole) >= 10000:
		return "%dk" % int(roundf(value / 1000.0))
	return str(whole)


## The info box: what is pointed at, and a refusal's note over its top.
func _draw_info() -> void:
	var box: Rect2 = _info
	# No box round it (ART4): a rule along its top.
	HudArt.rule(self, box.position, box.size.x, LINE)
	var entry: Dictionary = pointed()
	var at: Vector2 = box.position + Vector2(3.0, 2.0)
	if entry.has("staff"):
		var number: int = entry["staff"]
		_text(_fit(_staff_name(number), box.size.x - 6.0), at, TEXT)
		var hand: int = _mirror.hand_of(number)
		var where: String = "On a hand" if hand != NONE else IN_BAG_TEXT
		if _layer == Layer.SIGIL_STAFFS:
			where += ", has it" if _mirror.sigils_of(number).has(_sigil) else ", has it not"
		_text(_fit(where, box.size.x - 6.0), at + Vector2(0.0, LINE_STEP), MUTED)
		var x: float = at.x
		var y: float = at.y + LINE_STEP * 2.0 + 1.0
		for id: StringName in _mirror.cards_of(number):
			var tile := Rect2(Vector2(x, y), Vector2(SMALL_ICON, SMALL_ICON))
			draw_rect(tile, TILE)
			if id != &"":
				var icon: Texture2D = _spells.component_icon_for(id, SMALL_ICON) if _spells != null else null
				if icon != null:
					draw_texture_rect(icon, tile, false)
			x += SMALL_ICON + 1.0
			if x + SMALL_ICON > box.end.x - 3.0:
				x = at.x
				y += SMALL_ICON + 1.0
				if y + SMALL_ICON > box.end.y - 2.0:
					break
	elif entry.has("card"):
		var id: StringName = entry["card"]
		var kind: StringName = _spells.component_kind(id) if _spells != null else &""
		_text(_fit(_card_name(id), box.size.x - 6.0), at, TEXT)
		_text(String(CardKindsScript.WORDS.get(kind, "")), at + Vector2(0.0, LINE_STEP), CardKindsScript.COLORS.get(kind, MUTED))
		var lines: PackedStringArray = _wrap(_spells.component_description(id) if _spells != null else "", box.size.x - 6.0)
		var room: int = maxi(floori((box.end.y - 2.0 - (at.y + LINE_STEP * 2.0)) / LINE_STEP), 0)
		for line in mini(lines.size(), room):
			_text(lines[line], at + Vector2(0.0, LINE_STEP * (2 + line)), MUTED)
	elif entry.has("item"):
		var look: Dictionary = _look(entry["item"])
		_text(_fit(String(look["name"]), box.size.x - 6.0), at, TEXT)
		var count_line: String = "x%d" % int(entry["count"])
		if _in_sigils():
			var on: PackedStringArray = PackedStringArray()
			for hand in _mirror.hands_with_sigil(entry["item"]):
				on.append(HAND_WORDS[hand])
			count_line += ("  on " + ", ".join(on)) if not on.is_empty() else "  on no staff"
		_text(_fit(count_line, box.size.x - 6.0), at + Vector2(0.0, LINE_STEP), MUTED)
		var said: PackedStringArray = _wrap(String(look["description"]), box.size.x - 6.0)
		var rows: int = maxi(floori((box.end.y - 2.0 - (at.y + LINE_STEP * 2.0)) / LINE_STEP), 0)
		for line in mini(said.size(), rows):
			_text(said[line], at + Vector2(0.0, LINE_STEP * (2 + line)), MUTED)
	elif entry.has("bag"):
		_text(_bag_word(entry["bag"]), at, TEXT)
		_text(_mirror.fill_text(entry["bag"]), at + Vector2(0.0, LINE_STEP), MUTED)
	elif entry.has("kind"):
		_text(String(CardKindsScript.WORDS.get(entry["kind"], entry["kind"])), at, CardKindsScript.COLORS.get(entry["kind"], TEXT))
	if note_text() != "":
		var note := Rect2(box.position, Vector2(box.size.x, LINE_STEP + 3.0))
		draw_rect(note, OUTLINE)
		HudArt.rule(self, Vector2(note.position.x, note.end.y - HudArt.A), note.size.x, WARN)
		_text(_fit(_note, box.size.x - 6.0), note.position + Vector2(3.0, 1.0), WARN)


func _draw_ring() -> void:
	if _menu.is_empty():
		return
	_menu.draw_ring_line()
	if _layer == Layer.CARDS or _layer == Layer.KINDS:
		_menu.draw_group_arcs(_group_of_entry, CardKindsScript.COLORS)
	_menu.draw_pointer()
	var size: float = clampf(floorf(_menu.place_room()) - 2.0, 3.0, TILE_SIZE)
	var places: PackedInt32Array = _menu.place_entries()
	var angles: PackedFloat32Array = _menu.place_angles()
	for at in places.size():
		if places[at] != _menu.pointed:
			_draw_entry(places[at], _menu.tile_center(angles[at], RING_RADIUS), size, false)
	if _menu.pointed != NONE:
		var pop: float = clampf(_menu.pointed_for(_clock) / POP_TIME, 0.0, 1.0)
		_draw_entry(_menu.pointed, _menu.tile_center(_menu.angle_of_entry(_menu.pointed), RING_RADIUS + 4.0 * pop), TILE_PICKED, true)


## The kind an entry's arc is drawn in: a kind's own, a card's kind.
func _group_of_entry(entry: int) -> Variant:
	var data: Dictionary = _entries[entry]
	if data.has("kind"):
		return data["kind"]
	return _spells.component_kind(data["card"]) if _spells != null and data.has("card") else &""


func _draw_entry(entry: int, middle: Vector2, size: float, picked: bool) -> void:
	var data: Dictionary = _entries[entry]
	var rect := Rect2((middle - Vector2(size, size) * 0.5).round(), Vector2(size, size))
	draw_rect(rect, TILE)
	if data.has("bag"):
		var bag: StringName = data["bag"]
		_text(_bag_word(bag).left(1), Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.5 - 5.0), TEXT, true)
		_text(_mirror.fill_text(bag), Vector2(middle.x, rect.end.y + 1.0), MUTED, true)
	elif data.has("staff"):
		var base: StaffBase = _mirror.base_of(data["staff"])
		if base != null:
			StaffHeadScript.draw(self, base.head, rect.grow(-1.0), index)
	elif data.has("kind"):
		var color: Color = CardKindsScript.COLORS.get(data["kind"], DIM)
		_text(String(CardKindsScript.WORDS.get(data["kind"], "?")).left(1), Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.5 - 5.0), color, true)
		draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), color)
	elif data.has("card"):
		var id: StringName = data["card"]
		var side: float = minf(ICON_SIZE, rect.size.x - 2.0)
		var icon: Texture2D = _spells.component_icon_for(id, side) if _spells != null else null
		if icon != null and size >= SMALL_ICON:
			draw_texture_rect(icon, Rect2((rect.get_center() - Vector2(side, side) * 0.5).round(), Vector2(side, side)), false)
		var kind: StringName = _spells.component_kind(id) if _spells != null else &""
		draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), CardKindsScript.COLORS.get(kind, DIM))
	elif data.has("item"):
		var look: Dictionary = _look(data["item"])
		var side: float = floorf(minf(ICON_SIZE, rect.size.x - 2.0))
		var item_icon: Texture2D = IconDetail.fitting(look["icon"] as Texture2D, look["icon_small"] as Texture2D, side)
		if item_icon != null and size >= SMALL_ICON:
			var icon_rect := Rect2((rect.get_center() - Vector2(side, side) * 0.5).round(), Vector2(side, side))
			draw_texture_rect(item_icon, icon_rect, false, shade_tint(int(_shade.get(data["item"], 0))))
			RechargeShutter.draw(self, icon_rect, recharge_rows(data["item"]))
	var none_left: bool = data.has("item") and int(data["count"]) == 0
	if data.has("count") and (int(data["count"]) > 1 or none_left) and not data.has("kind"):
		var number: String = str(int(data["count"]))
		var badge := Rect2(rect.end - Vector2(_text_width(number) + 2.0, 8.0), Vector2(_text_width(number) + 2.0, 8.0))
		draw_rect(badge, OUTLINE)
		var stage: int = int(_shade.get(data["item"], 0)) if data.has("item") else 0
		_text(number, badge.position + Vector2(1.0, -1.0), TEXT.lerp(DIM, float(stage) / float(GREY_STAGES)))
	if picked:
		_frame(rect.grow(1.0), GOLD)
		_frame(rect.grow(2.0), GOLD)


func _draw_hub() -> void:
	_menu.draw_hub()
	var lines: PackedStringArray = hub_lines()
	var top: float = _menu.center.y - lines.size() * LINE_STEP * 0.5
	for at in lines.size():
		var line: String = _fit(lines[at], RadialMenuScript.HUB_RADIUS * 2.0 - 8.0)
		_text(line, Vector2(_menu.center.x, top + at * LINE_STEP), TEXT if at == 0 else MUTED, true)


# --- Words and helpers ------------------------------------------------------------------

func _bag_word(bag: StringName) -> String:
	return String(BAG_WORDS.get(bag, String(bag).capitalize()))


## How item `id` of the bag entered looks (`ItemLooks`: its name, icon and description).
func _look(id: StringName) -> Dictionary:
	return ItemLooks.of(ItemKinds.kind_in(_bag, id), id, _content(), _spells)


## The registry, found as it is first needed (null outside the tree).
func _content() -> RegistryScript:
	if _registry == null and is_inside_tree():
		_registry = get_node_or_null("/root/Registry") as RegistryScript
	return _registry


## True when the item entry `entry` of the bag entered has a use (`ItemKinds.usable`): A uses
## it, a d-pad arm binds it.
func _item_usable(entry: Dictionary) -> bool:
	return entry.has("item") and ItemKinds.usable(_bag, StringName(entry["item"]), _content())


## The tint of an item's icon at shade `stage` (0 its own colours ... GREY_STAGES greyed): whole steps.
static func shade_tint(stage: int) -> Color:
	return Color.WHITE.lerp(GREY, float(clampi(stage, 0, GREY_STAGES)) / float(GREY_STAGES))


## The shade an entry's icon is going to: greyed with none left.
func _shade_wanted(entry: Dictionary) -> int:
	return GREY_STAGES if int(entry.get("count", 1)) == 0 else 0


## Item `id`'s shade drawn on the ring (0 its icon ... GREY_STAGES greyed; for tests).
func shade_of(id: StringName) -> int:
	return int(_shade.get(id, 0))


func _on_item_recharging(player: int, bag: StringName, id: StringName, left: float, whole: float) -> void:
	if player != index:
		return
	var key: String = "%s/%s" % [bag, id]
	var shut: int = RechargeShutter.rows(left, whole, int(ICON_SIZE))
	if shut > 0:
		_charges[key] = shut
	else:
		_charges.erase(key)
	if not _open:
		# Not shown: drawn as it stands when it is.
		_charge_rows[key] = shut
	_dirty = true


## The shutter rows drawn over item `id` of the bag entered (0: none; for tests).
func recharge_rows(id: StringName) -> int:
	return int(_charge_rows.get("%s/%s" % [_bag, id], 0))


## True while item `id` of the bag entered recharges (its Use is dimmed).
func recharging(id: StringName) -> bool:
	return _charges.has("%s/%s" % [_bag, id])


## Each shutter's drawn rows a row nearer what was told at GREY_FPS (Smooth: it drops in and sinks by
## whole rows, never jumps).
func _step_charges(delta: float) -> void:
	var moving: bool = false
	for key: String in _charges:
		if int(_charge_rows.get(key, 0)) != int(_charges[key]):
			moving = true
	for key: String in _charge_rows:
		if not _charges.has(key) and int(_charge_rows[key]) != 0:
			moving = true
	if not moving:
		_charge_clock = 0.0
		return
	_charge_clock += delta
	while _charge_clock >= 1.0 / GREY_FPS:
		_charge_clock -= 1.0 / GREY_FPS
		for key: String in _charges:
			if not _charge_rows.has(key):
				_charge_rows[key] = 0
		for key: String in _charge_rows:
			var at: int = int(_charge_rows[key])
			_charge_rows[key] = at + signi(int(_charges.get(key, 0)) - at)
	_dirty = true


## `ids` in the order the ring has shown them, each new one remembered after them in its own order.
func _kept_order(ids: Array[StringName]) -> Array[StringName]:
	for id: StringName in ids:
		if not _item_order.has(id):
			_item_order.append(id)
	var out: Array[StringName] = []
	for id: StringName in _item_order:
		if ids.has(id):
			out.append(id)
	return out


## The ring of items laid out anew: an item already on it keeps the shade it is drawn in (it steps on
## from there), one new to it is drawn as it stands.
func _keep_shades() -> void:
	var kept: Dictionary = {}
	for entry: Dictionary in _entries:
		var id: StringName = entry["item"]
		kept[id] = int(_shade.get(id, _shade_wanted(entry)))
	_shade = kept


## Each icon's shade a step nearer its wanted one at GREY_FPS (Smooth: greying and filling again pass
## the shades between).
func _step_shades(delta: float) -> void:
	if _layer != Layer.ITEMS:
		return
	var moving: bool = false
	for entry: Dictionary in _entries:
		if int(_shade.get(entry["item"], 0)) != _shade_wanted(entry):
			moving = true
	if not moving:
		_shade_clock = 0.0
		return
	_shade_clock += delta
	while _shade_clock >= 1.0 / GREY_FPS:
		_shade_clock -= 1.0 / GREY_FPS
		for entry: Dictionary in _entries:
			var id: StringName = entry["item"]
			var at: int = int(_shade.get(id, 0))
			_shade[id] = at + signi(_shade_wanted(entry) - at)
	_dirty = true


## True when the item entry `entry` of the bag entered is of a kind that can be `action`ed.
func _item_can(entry: Dictionary, action: StringName) -> bool:
	return entry.has("item") and _events != null and ItemKinds.can(ItemKinds.kind_in(_bag, StringName(entry["item"])), action)


func _staff_name(number: int) -> String:
	var plan: Dictionary = _mirror.plan_of(number)
	var base: StaffBase = plan.get("staff") as StaffBase
	var named: String = String(plan.get("name", ""))
	if named == "" and base != null:
		named = base.shown_name()
	return named if named != "" else "Staff"


func _card_name(id: StringName) -> String:
	var shown: String = _spells.component_name(id) if _spells != null else ""
	return shown if shown != "" else String(id)


func _text_width(text: String) -> float:
	return _menu.text_width(text)


func _text(text: String, at: Vector2, color: Color, centered: bool = false) -> void:
	_menu.draw_text(text, at, color, centered)


func _frame(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color, false, 1.0)


## `text` cut with ".." to fit `width` pixels.
func _fit(text: String, width: float) -> String:
	if _text_width(text) <= width:
		return text
	var cut: String = text
	while cut.length() > 1 and _text_width(cut + "..") > width:
		cut = cut.left(cut.length() - 1)
	return cut + ".."


## `text` broken into lines of at most `width` pixels, at spaces.
func _wrap(text: String, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var line: String = ""
	for word in text.split(" ", false):
		var tried: String = word if line == "" else line + " " + word
		if line != "" and _text_width(tried) > width:
			lines.append(line)
			line = word
		else:
			line = tried
	if line != "":
		lines.append(_fit(line, width))
	return lines


func _make_glyph(node_name: String) -> ActionGlyphScript:
	var glyph: ActionGlyphScript = ActionGlyphScript.new()
	glyph.name = node_name
	add_child(glyph)
	return glyph
