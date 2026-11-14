extends Control
## One player's radial staff builder (owner, 2026-10-26), the game's one builder (the older list
## builder was removed, owner 2026-11-11). It fills the player's quarter of the screen, laid out the same in every quarter (the column on
## the left, the ring on its right; owner, 2026-10-31, docs/milestones/M2-builder-tree.md), never
## pauses the game, and is drawn in code at the view's 1x pixels. While it is open the corner
## panel is hidden (`hud/panels`): thin HP and MP bars framed in the player's colour sit on top of
## the column instead, so health stays in view during a wave.
##
## - **The ring:** every card of the bag on a circle, grouped by kind (carriers, modifiers,
##   infusions, triggers, multicasts) with a coloured arc and a gap between kinds, each kind A to Z
##   by the name shown, clockwise from the top (owner, 2026-11-11; `ring_order`); or, with the
##   layout `KIND`, one kind at a time, flipped with the d-pad (`kind_prev`, `kind_next`). Any
##   number of cards fits: the tiles shrink with the count and, below `ICON_MIN` pixels, become
##   plain marks; the card pointed at is always drawn full size. A card the player has several
##   of shows the count, and one of a higher level its level (cards are counted, items I3: a card
##   with none left is not on the ring; levels come with M3's rewards).
## - **Pointing:** the right stick (P1's mouse) points at a card: it pops out with a double gold
##   frame and the middle of the ring (the hub) shows its icon, name, kind and own numbers
##   (`Spells.component_stats`). Landing on a card rumbles the pad briefly; a gap rumbles
##   nothing. Letting go of the stick lets the card go. The pointed card holds on a little past
##   its border (the radial menu's `STICKY_ANGLE`), so a wobbling thumb does not flicker between
##   two cards.
## - **Ring styles** (owner, 2026-10-30): `ring_picker` swaps in another way to pick and draw the
##   ring (`rings/`: a zoom fan, a kinds-first ring), each in its own file so it is easy to drop.
## - **The strip of staffs** (items I3): every staff the player owns, by its number in the
##   inventory: the four hands first (RB, RT, LB, LT), each tab the hand's button glyph (an empty
##   hand's dim), then the staffs in the bag, each tab its staff's head; it scrolls to keep the shown
##   staff in view. The builder builds any of them; a staff in the bag is only compiled for the view.
## - **The slots:** the shown staff's slots in five columns under the strip, with a gold marker
##   that the left stick moves (with key-repeat; P1's move keys, or a click on a slot). The
##   pointed card shows faded in the marked slot, so RT's result is seen before it is pressed:
##   while pointing, the slots show the staff as RT would leave it (the rest pushed on, its casts
##   and wasted cards). The casts of the cycle are framed: the cards one cast reads share a frame,
##   every other cast in the other Bone shade, so what fires together is seen while building
##   (`slot_groups`).
## - **RT** (`staff_2`; P1's left click) puts the pointed card in the marked slot and moves the
##   marker on one. With `put` PUSH (the default), a card already there and the ones after it
##   move one slot right (refused when the last slot is taken); with REPLACE it is replaced.
##   **LT** (`staff_4`; Q) takes the marked card out (PUSH closes the gap). On an empty slot
##   with no card after it, LT takes out the last card before it and the marker steps back to
##   it (an undo while building); with PUSH, on an empty slot with cards after it, it closes
##   the gap. **Held** for `CLEAR_HOLD` seconds, LT clears the rest of the staff: a red frame
##   fills round the slots, then every card fades out at once (the press has already taken one
##   out, so a clear ends the same). **LB, RB** (`page_prev`, `page_next`) show the previous or
##   next staff of the strip, past an empty hand; **B** closes it.
## - **The tree** (owner, 2026-10-31, `tree_view.gd`): **Y** (`extra`; R) swaps the ring (and its
##   kind row) for a tree of the shown staff's cycle in the same space, and back. The right
##   stick (P1's mouse wheel) scrolls it; the left stick still moves the slot marker, whose card's
##   row and tile are marked in the tree; RT has nothing to put in there; P1's click on a tile
##   marks its slot.
## - **The card info panel:** under the slots, the card under the marker: its name, its kind
##   in the kind's colour (and a frame in it), its lore line wrapped (`Spells.component_description`)
##   and, under a line, its numbers (`Spells.component_stats`; none for a trigger). An empty slot
##   says so. A refusal's note shows over its top for a moment.
## - **Numbers:** the hub in the ring's middle shows the staff's cycle when no card is pointed
##   at: the mana of its dearest cast as a share of that staff's own pool (red with "!" above 100 %:
##   it cannot be cast), the damage of the cycle (every shot landing once) and the cycle's time.
##
## What it shows comes only from events: `owned_staff_changed` (every staff owned, by number: the
## plain `Spells.staff_view`), `hands_changed` (which number is on which hand), `bag_changed` (the
## card bag's ids and counts), `build_refused`, `player_stats_changed` (the wizard's health) and
## `staff_mana_changed` (each hand's own pool: the MP bar and the shares are the viewed staff's; a
## staff in the bag shows its staff's pool, full: nothing takes a staff off a hand before items
## I7). What it asks for goes out as `staff_change_requested` (one slot) or `staff_cards_requested`
## (the whole staff: a push, a closed gap, an undo, a clear), naming the staff by its number, so
## this node never changes a staff itself.
## It opens through `core/ui_focus` with itself as the one control, so its owner's gameplay
## input is captured and `back` and the paging buttons come as UIFocus signals; the sticks, the
## triggers are read from `core/input` (press counts and the menu sticks), only for its
## own player. Hints show the buttons (`widgets/action_glyph.gd`), never action names.
## The ring, pointing at it and the hint row are the shared radial menu's (`widgets/radial_menu.gd`,
## items I5): this builder lays its cards out on it and draws them, the inventory will lay out its
## bags and items.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const RadialMenuScript := preload("res://hud/widgets/radial_menu.gd")
const RingPickerScript := preload("res://hud/builder/rings/ring_picker.gd")
const TreeViewScript := preload("res://hud/builder/tree_view.gd")

## How the ring shows the bag: every card at once, or one kind at a time.
enum Layout { ALL, KIND }
## What RT does on a slot that has a card: push it and the rest right, or replace it.
enum Put { PUSH, REPLACE }

const PLAYER_COUNT: int = 4
const STAFF_COUNT: int = 4
## Each hand's button, by hand (0 RB, 1 RT, 2 LB, 3 LT): its tab's glyph.
const HAND_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## The strip of staffs: a bag staff's tab, a tab's height, the gap between tabs and the frame a
## hand's tab draws round its glyph (so a tab never reads as the paging glyphs beside the strip).
const TAB_WIDTH: float = 12.0
const TAB_HEIGHT: float = 12.0
const TAB_GAP: float = 1.0
const TAB_PAD: float = 2.0
const NO_CARD: StringName = &""
const NONE: int = -1

## The kinds in ring order, their words and colours (docs/STYLE.md: none near a player colour).
const KINDS: Array[StringName] = [&"carrier", &"modifier", &"element", &"trigger", &"multicast"]
const KIND_WORDS: Dictionary = {
	&"carrier": "Carrier", &"modifier": "Modifier", &"element": "Infusion", &"trigger": "Trigger", &"multicast": "Multicast",
}
const KIND_COLORS: Dictionary = {
	&"carrier": Color("#ffa23c"), &"modifier": Color("#4fd6dc"), &"element": Color("#b4e82a"),
	&"trigger": Color("#e08ad8"), &"multicast": Color("#d4d0e0"),
}
const OUTLINE: Color = Color("#14121f")
const SHADE: Color = Color(0.078, 0.071, 0.122, 0.86)
const TILE: Color = Color("#2b2840")
const EMPTY: Color = Color("#1b1929")
const LINE: Color = Color("#4a4663")
const TEXT: Color = Color("#f4f1ea")
const MUTED: Color = Color("#a39fb8")
const DIM: Color = Color("#7a7694")
const GOLD: Color = Color("#f2c230")
const WARN: Color = Color("#e0592f")
## The frames round the casts of the cycle in the slots, every other cast in the other shade.
const GROUP_COLORS: Array[Color] = [Color("#f4f1ea"), Color("#a39fb8")]

## The layout, in the view's pixels from the quarter's top left, the same in every quarter.
const EDGE: float = 4.0
const COLUMN_WIDTH: float = 112.0
## The HP and MP bars on top of the column: a 1 px frame in the player's colour round two 2 px
## bars (HP over MP) with a 1 px line between, 7 px in all.
const BARS_HEIGHT: float = 7.0
const TABS_FROM_TOP: float = 11.0
const SLOTS_FROM_TOP: float = 26.0
## The bars' colours, the corner panel's (the theme's HealthBar and ManaBar fills), and each
## player's colour (the theme's PlayerPanel1-4 borders).
const HEALTH_COLOR: Color = Color("#e0592f")
const MANA_COLOR: Color = Color("#f2c230")
const PLAYER_COLORS: Array[Color] = [Color("#3b73c9"), Color("#d9477a"), Color("#3f8f4f"), Color("#8a4fc4")]
const SLOT_SIZE: float = 16.0
const SLOT_STEP: float = 18.0
const SLOT_COLUMNS: int = 5
const SLOT_ROWS: int = 4
## The ring's sizes are the shared radial menu's (`hud/widgets/radial_menu.gd`).
const RING_RADIUS: float = RadialMenuScript.RING_RADIUS
const HUB_RADIUS: float = RadialMenuScript.HUB_RADIUS
const ARC_OUT: float = RadialMenuScript.ARC_OUT
## The ring's middle sits this far below the quarter's top.
const RING_FROM_EDGE: float = 84.0
const TILE_MAX: float = 18.0
const TILE_PICKED: float = 20.0
## Tiles smaller than this are drawn as plain marks in the kind's colour.
const ICON_MIN: float = 10.0
const ICON_SIZE: float = 16.0
## A gap between two kinds is this many cards wide.
const GAP_WIDTH: float = 0.6
const LINE_STEP: float = 9.0
const HINT_HEIGHT: float = RadialMenuScript.HINT_HEIGHT

## The left stick moves the marker past MOVE_THRESHOLD, again after MOVE_DELAY seconds held, then
## every MOVE_REPEAT. (Pointing, its hysteresis and P1's mouse on the ring are the radial menu's.)
const MOVE_THRESHOLD: float = 0.5
const MOVE_DELAY: float = 0.3
const MOVE_REPEAT: float = 0.11
const MOUSE_INNER: float = RadialMenuScript.MOUSE_INNER
const CLEAR_HOLD: float = 0.6
## LT held this long before the clear's red frame shows, so a quick take-out does not flash it.
const CLEAR_SHOW: float = 0.12
const FADE_TIME: float = 0.25
const FLY_TIME: float = 0.15
const POP_TIME: float = 0.07
const NOTE_TIME: float = 1.4
## Rumbles: (weak, strong, seconds).
const RUMBLE_POINT: Vector3 = Vector3(0.25, 0.0, 0.03)
const RUMBLE_PUT: Vector3 = Vector3(0.2, 0.45, 0.06)
const RUMBLE_TAKE: Vector3 = Vector3(0.35, 0.0, 0.04)
const RUMBLE_CLEAR: Vector3 = Vector3(0.3, 0.7, 0.14)
const RUMBLE_REFUSED: Vector3 = Vector3(0.0, 0.6, 0.09)

const PUT_VERB: String = "Put in"
const TAKE_VERB: String = "Take out"
const UNDO_VERB: String = "Undo"
const GAP_VERB: String = "Close gap"
const CLEAR_VERB: String = "Clear"
const CLOSE_VERB: String = "Close"
const FULL_NOTE: String = "The staff is full"
const POINT_NOTE: String = "Point at a card first"
const EMPTY_NOTE: String = "Nothing to take out"
const NO_CARDS_TEXT: String = "No cards"
const EMPTY_SLOT_TEXT: String = "Empty slot"
const TREE_VERB: String = "Tree"
const RING_VERB: String = "Ring"
## The hint row's buttons (RT, LT, Y, B) and the buttons read here by press count.
const HINT_ACTIONS: Array[StringName] = [&"staff_2", &"staff_4", &"extra", &"back"]
const READ_ACTIONS: Array[StringName] = [&"staff_2", &"staff_3", &"staff_4", &"kind_prev", &"kind_next", &"extra"]
## What LT does on the marked slot.
const LT_TAKE: StringName = &"take"
const LT_UNDO: StringName = &"undo"
const LT_GAP: StringName = &"gap"

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0
## Set by `hud/panels` from the pause menu's Sandbox page.
var layout: Layout = Layout.ALL:
	set(value):
		layout = value
		_kind_page = 0
		_menu.pointed = NONE
		_build_ring()
		_changed()
var put: Put = Put.PUSH:
	set(value):
		put = value
		_refresh_preview()
		_changed()
## A ring style that picks and draws the ring its own way (`rings/`, owner 2026-10-30), or null
## for the plain ring. Set by `hud/panels` from the pause menu's Sandbox page.
var ring_picker: RingPickerScript = null:
	set(value):
		ring_picker = value
		_menu.pointed = NONE
		if ring_picker != null:
			ring_picker.reset()
		_changed()

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _spells: SpellsScript = null
var _input: InputManagerScript = null

## Mirrors of what the player announced: each staff's view by its number, which number each hand
## holds (NONE: empty), the strip's numbers in order (`_strip_order`), each hand's pool.
var _plans: Dictionary = {}
var _hands: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])
var _strip: PackedInt32Array = PackedInt32Array()
var _max_mana: PackedFloat32Array = PackedFloat32Array([100.0, 100.0, 100.0, 100.0])
## The wizard's health (negative until the first `player_stats_changed`) and each staff's mana
## now, for the bars.
var _health: float = -1.0
var _max_health: float = 100.0
var _mana: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

## The ring's entries, one per card id and level in the card bag: {id, level, count, kind}.
var _entries: Array[Dictionary] = []
## The ring itself (its places, pointing, the hint row): the shared radial menu, laid out from
## the entries by `_build_ring`; its entry numbers are indices into `_entries`.
var _menu: RadialMenuScript = RadialMenuScript.new(self)
## The kinds the bag has, in ring order, and the one shown with the layout KIND.
var _kinds: Array[StringName] = []
var _kind_page: int = 0

var _open: bool = false
## The tree view (Y), drawn by its own node in the ring's place, and whether it shows.
var _tree: TreeViewScript = null
var _tree_open: bool = false
## The number of the staff shown (RT's at the start: the start staffs' numbers are their buttons).
var _viewed: int = 1
var _slot: int = 0
var _first_row: int = 0
## The staff as RT would leave it with the pointed card, and its numbers ({} when none).
var _preview: Dictionary = {}
## The staff as RT would leave it with the pointed card: its cards and its plain view (casts and
## wasted), shown in the slots while pointing ([] and {} when nothing is pointed at or RT would
## be refused).
var _preview_cards: Array[StringName] = []
var _preview_view: Dictionary = {}
## The press counts of the buttons read here, at the last poll.
var _seen: Dictionary = {}
var _move_dir: Vector2i = Vector2i.ZERO
var _move_wait: float = 0.0
## Seconds LT has been held (negative when not held), and whether this hold is done (cleared,
## or there was nothing left to clear).
var _clear_held: float = -1.0
var _clear_done: bool = false
var _note: String = ""
var _note_left: float = 0.0
var _clock: float = 0.0
var _marker_at: float = -1.0
## Cards in flight: {texture, from, to, start, fade}.
var _flyers: Array[Dictionary] = []
## The cards of a cleared staff fading out where they were, and when the fade began.
var _fading: Array[StringName] = []
var _fade_start: float = -1.0
var _dirty: bool = true

## Laid out by `_place()`: the quarter, the column on its left, the bars, the tabs and the slots'
## top left, the card info panel, the ring's side and the kind row (the ring's middle and the hint
## row are the menu's `center` and `hints_at`).
var _quarter: Rect2 = Rect2()
var _column: Rect2 = Rect2()
var _bars_at: Vector2 = Vector2.ZERO
var _tabs_at: Vector2 = Vector2.ZERO
var _slots_at: Vector2 = Vector2.ZERO
var _info: Rect2 = Rect2()
var _ring_side: Rect2 = Rect2()
var _kinds_at: Vector2 = Vector2.ZERO

## Button glyphs: the strip's paging (LB, RB) and each hand's tab (RB, RT, LB, LT), the hints
## (`HINT_ACTIONS`) and the kind row (d-pad).
var _glyph_prev: ActionGlyphScript = null
var _glyph_next: ActionGlyphScript = null
var _hand_glyphs: Array[ActionGlyphScript] = []
## The strip's tabs as laid out (`_place_strip`): per tab its number (NONE: an empty hand), its
## hand (NONE: in the bag) and its rect; and the first tab shown.
var _tab_numbers: PackedInt32Array = PackedInt32Array()
var _tab_hands: PackedInt32Array = PackedInt32Array()
var _tab_rects: Array[Rect2] = []
var _strip_first: int = 0
## True when the strip must be laid out again (a staff, a hand or the shown staff changed): only
## then, never on every redraw.
var _strip_stale: bool = true
## The hand glyphs' widths the strip was laid out for (a device change resizes them).
var _strip_glyphs: float = 0.0
var _kind_glyphs: Array[ActionGlyphScript] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)
	_glyph_prev = _make_glyph("GlyphPrev")
	_glyph_next = _make_glyph("GlyphNext")
	for hand in STAFF_COUNT:
		_hand_glyphs.append(_make_glyph("GlyphHand%d" % hand))
	_menu.make_hints(HINT_ACTIONS)
	_kind_glyphs.append(_make_glyph("KindPrev"))
	_kind_glyphs.append(_make_glyph("KindNext"))
	for action in READ_ACTIONS:
		_seen[action] = 0
	_tree = TreeViewScript.new()
	_tree.name = "TreeView"
	_tree.visible = false
	add_child(_tree)


## Connect to the event bus, the focus service, the spell runtime and the input manager (called
## once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript, spells: SpellsScript, input: InputManagerScript = null) -> void:
	_events = events
	_ui_focus = ui_focus
	_spells = spells
	_input = input
	_menu.bind(input, index)
	for glyph in [_glyph_prev, _glyph_next] + _hand_glyphs + _kind_glyphs:
		(glyph as ActionGlyphScript).bind(input)
	for hand in STAFF_COUNT:
		_hand_glyphs[hand].show_action(index, HAND_ACTIONS[hand])
	_tree.kind_colors = KIND_COLORS
	_tree.spells = spells
	_glyph_prev.show_action(index, &"page_prev")
	_glyph_next.show_action(index, &"page_next")
	_kind_glyphs[0].show_action(index, &"kind_prev")
	_kind_glyphs[1].show_action(index, &"kind_next")
	if _events != null:
		_events.owned_staff_changed.connect(_on_owned_staff_changed)
		_events.hands_changed.connect(_on_hands_changed)
		_events.bag_changed.connect(_on_bag_changed)
		_events.build_refused.connect(_on_build_refused)
		_events.player_stats_changed.connect(_on_stats_changed)
		_events.staff_mana_changed.connect(_on_staff_mana_changed)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.paged.connect(_on_paged)


func is_open() -> bool:
	return _open


## Open the builder for its owner (closing any other panel of theirs), on the staff last shown,
## with the marker after its last card. False if the owner has no device.
func open_builder() -> bool:
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
	_menu.pointed = NONE
	if ring_picker != null:
		ring_picker.reset()
	_note = ""
	_clear_held = -1.0
	_clear_done = false
	_move_dir = Vector2i.ZERO
	_flyers.clear()
	_fading.clear()
	if not holds_staff(_viewed):
		_viewed = _held_from(_viewed, 1)
	_strip_first = 0
	_strip_stale = true
	_slot = _end_slot()
	_tree_open = false
	_tree.visible = false
	_prime()
	_refresh_preview()
	set_process(true)
	_changed()
	return true


## Close the builder if it is open.
func close_builder() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## The number of the staff shown.
func viewed_staff() -> int:
	return _viewed


## True when the player owns staff number `staff` (it has a plan).
func holds_staff(staff: int) -> bool:
	return not (_plans.get(staff, {}) as Dictionary).is_empty()


## The strip of staffs: every staff number owned, the hands' by button, then the bag's.
func strip() -> PackedInt32Array:
	return _strip.duplicate()


## `staff` when it is owned; else the strip's first staff from where `staff` would be, `step_by`
## at a time; `staff` when none is owned.
func _held_from(staff: int, step_by: int) -> int:
	if holds_staff(staff) or _strip.is_empty():
		return staff
	return _strip[0] if step_by >= 0 else _strip[_strip.size() - 1]


## The staff `step_by` places along the strip from staff `staff` (round), or `staff` itself.
func _along_strip(staff: int, step_by: int) -> int:
	if _strip.is_empty():
		return staff
	var at: int = _strip.find(staff)
	if at < 0:
		return _held_from(staff, step_by)
	return _strip[posmod(at + step_by, _strip.size())]


## The hand staff `staff` is on, or NONE (in the bag).
func _hand_of(staff: int) -> int:
	return _hands.find(staff) if staff != NONE else NONE


## The mana of staff `staff` now and its pool's size: its hand's (`staff_mana_changed`), or for a
## staff in the bag its staff's pool, full.
func _mana_of(staff: int) -> float:
	var hand: int = _hand_of(staff)
	return _mana[hand] if hand != NONE else _pool_of(staff)


func _pool_of(staff: int) -> float:
	var hand: int = _hand_of(staff)
	if hand != NONE:
		return _max_mana[hand]
	var base: StaffBase = (_plans.get(staff, {}) as Dictionary).get("staff") as StaffBase
	return base.max_mana if base != null else 100.0


## The marked slot of the shown staff.
func marked_slot() -> int:
	return _slot


## The card ids of staff number `staff` as the player announced them, by slot (a copy).
func cards_of(staff: int) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign((_plans.get(staff, {}) as Dictionary).get("cards", []))
	return out


## The ring's entries in ring order (copies): {id, level, count, kind}.
func ring_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for at in _menu.place_entries():
		if at != NONE:
			out.append(_entries[at].duplicate())
	return out


## The id of the card pointed at, or `&""`.
func pointed_id() -> StringName:
	return _entries[_menu.pointed]["id"] if _menu.pointed != NONE else NO_CARD


## The kind the ring shows with the layout KIND.
func shown_kind() -> StringName:
	return _kinds[_kind_page] if not _kinds.is_empty() else &""


## The direction the right stick must point to land on card `id` (zero if it is not on the ring).
func direction_to(id: StringName) -> Vector2:
	for entry in _menu.place_entries():
		if entry != NONE and _entries[entry]["id"] == id:
			return _menu.direction_to(entry)
	return Vector2.ZERO


## Whether the tree shows in the ring's place.
func is_tree_open() -> bool:
	return _tree_open


## The tree view node (for tests and screenshots).
func tree_view() -> TreeViewScript:
	return _tree


## Y: swap the ring for the tree, or back. Pointing ends: the tree has no card to put in.
func toggle_tree() -> void:
	_tree_open = not _tree_open
	_tree.visible = _tree_open
	_menu.pointed = NONE
	if ring_picker != null:
		ring_picker.reset()
	if _tree_open:
		_sync_tree()
		_tree.restart()
	_refresh_preview()
	_changed()


func _sync_tree() -> void:
	_tree.set_plan(_plan(_viewed), _pool_of(_viewed))
	_tree.set_marked(_slot)


## The ring's middle in view pixels (for screenshots).
func ring_center() -> Vector2:
	return _menu.center


## Where the parts sit, in view pixels (for the layout test): `quarter`, `column`, `bars`, `slots`
## (the four rows shown), `info`, `ring` (the ring with its kind arcs) and `hints`.
func layout_parts() -> Dictionary:
	var reach: float = RING_RADIUS + ARC_OUT + 2.0
	var center: Vector2 = _menu.center
	return {
		"quarter": _quarter, "column": _column,
		"bars": Rect2(_bars_at, Vector2(COLUMN_WIDTH, BARS_HEIGHT)),
		"slots": Rect2(_slots_at - Vector2(3.0, 3.0), Vector2(SLOT_STEP * SLOT_COLUMNS + 4.0, SLOT_STEP * SLOT_ROWS + 4.0)),
		"info": _info,
		"ring": Rect2(center - Vector2(reach, reach), Vector2(reach, reach) * 2.0),
		"hints": _menu.hints_rect(),
	}


## What the card info panel shows: the card under the slot marker. `id` (`&""` for an empty
## slot), `name`, `kind` (the kind's word), `lines` (its lore line, wrapped to the panel) and
## `stats` (its numbers; none for a trigger). An empty slot's `name` is "Empty slot".
func card_info() -> Dictionary:
	var cards: Array[StringName] = cards_of(_viewed)
	var id: StringName = cards[_slot] if _slot < cards.size() else NO_CARD
	if id == NO_CARD or _spells == null:
		return {"id": NO_CARD, "name": EMPTY_SLOT_TEXT, "kind": "", "lines": PackedStringArray(), "stats": PackedStringArray()}
	var kind: StringName = _spells.component_kind(id)
	var stats: PackedStringArray = _spells.component_stats(id) if kind != &"trigger" else PackedStringArray()
	return {
		"id": id, "name": _name_of(id), "kind": String(KIND_WORDS.get(kind, "")),
		"lines": _wrap(_spells.component_description(id), _info.size.x - 6.0), "stats": stats,
	}


## The wizard's health and the viewed staff's mana as the bars show them: shares of the
## maximum, 0 to 1.
func bar_shares() -> Vector2:
	if _health < 0.0:
		return Vector2.ZERO
	return Vector2(clampf(_health / maxf(_max_health, 1.0), 0.0, 1.0), clampf(_mana_of(_viewed) / maxf(_pool_of(_viewed), 1.0), 0.0, 1.0))


## The lines the hub shows now.
func hub_lines() -> PackedStringArray:
	var pointed: int = _menu.pointed
	if pointed != NONE:
		var id: StringName = _entries[pointed]["id"]
		var lines := PackedStringArray([_name_of(id), String(KIND_WORDS.get(_entries[pointed]["kind"], ""))])
		lines.append_array(_spells.component_stats(id) if _spells != null else PackedStringArray())
		return lines
	var lines := PackedStringArray([_staff_label(_viewed)])
	lines.append_array(_number_lines(_numbers(_plan(_viewed)), {}))
	return lines


## What the hub calls staff `staff`: "Staff 2" for the staff on RT (its hand's place, as the
## corner panel's rows), else its staff's name (one in the bag).
func _staff_label(staff: int) -> String:
	var hand: int = _hand_of(staff)
	if hand != NONE:
		return "Staff %d" % (hand + 1)
	var shown: String = str(_plan(staff).get("name", ""))
	return shown if shown != "" else "Staff"


## The numbers under the slots, with what RT would make of them.
func number_lines() -> PackedStringArray:
	return _number_lines(_numbers(_plan(_viewed)), _preview)


## The hint row's verbs, as shown (a verb whose button does nothing now is dimmed, not hidden).
func hint_verbs() -> Array[String]:
	return _menu.hint_verbs()


## The short note shown after a refusal or a press that did nothing, or "".
func note_text() -> String:
	return _note if _note_left > 0.0 else ""


## Move the marker as a click on a slot does (for P1's mouse and tests).
func mark_slot(slot: int) -> void:
	var count: int = cards_of(_viewed).size()
	if count == 0:
		return
	_slot = clampi(slot, 0, count - 1)
	_marker_at = _clock
	_scroll_to_marker()
	_tree.set_marked(_slot)
	_refresh_preview()
	_changed()


## Read the buttons and sticks and act, then animate. Called every frame while open; tests call
## it with fixed steps.
func step(delta: float) -> void:
	if not _open:
		return
	_clock += delta
	_poll_buttons()
	_poll_marker(delta)
	_poll_pointer(delta)
	_poll_clear(delta)
	if _note_left > 0.0:
		_note_left -= delta
		_dirty = true
	if not _flyers.is_empty() or not _fading.is_empty() or _clear_held >= 0.0 or _menu.pointed_for(_clock) < POP_TIME or _clock - _marker_at < POP_TIME \
			or (ring_picker != null and ring_picker.is_animating()):
		_dirty = true
	if _fading.size() > 0 and _clock - _fade_start >= FADE_TIME:
		_fading.clear()
	for at in range(_flyers.size() - 1, -1, -1):
		if _clock - float(_flyers[at]["start"]) >= FLY_TIME:
			_flyers.remove_at(at)
	if _dirty:
		_dirty = false
		if _tree_open:
			_tree.set_marked(_slot)
		_refresh_hints()
		if _strip_stale or _hand_glyph_widths() != _strip_glyphs:
			_place_strip()
		queue_redraw()


func _process(delta: float) -> void:
	step(delta)


# --- Input ------------------------------------------------------------------------------

func _prime() -> void:
	if _input == null:
		return
	for action in READ_ACTIONS:
		_seen[action] = _input.get_press_count(index, action)


## New presses since the last poll of one action (a tap within a frame counts).
func _presses(action: StringName) -> int:
	if _input == null:
		return 0
	var count: int = _input.get_press_count(index, action)
	var new: int = count - int(_seen[action])
	_seen[action] = count
	return maxi(new, 0)


func _poll_buttons() -> void:
	var mouse_slot: int = _mouse_slot()
	for _press in _presses(&"extra"):
		toggle_tree()
	for _press in _presses(&"staff_2"):
		if mouse_slot != NONE:
			mark_slot(mouse_slot)
		elif _tree_open:
			# The tree has no card pointed at; P1's click on a tile marks its slot.
			var tile: int = _tree.slot_at(get_global_mouse_position()) if _uses_mouse() else NONE
			if tile != NONE:
				mark_slot(tile)
		else:
			_put_in()
	for _press in _presses(&"staff_3"):
		# P1's right click on a slot takes that card out.
		if mouse_slot != NONE:
			mark_slot(mouse_slot)
			_take_out()
	for _press in _presses(&"staff_4"):
		_take_out()
	var flips: int = _presses(&"kind_next") - _presses(&"kind_prev")
	if flips != 0 and layout == Layout.KIND and not _kinds.is_empty():
		_kind_page = posmod(_kind_page + flips, _kinds.size())
		_menu.pointed = NONE
		_build_ring()
		_refresh_preview()
		_changed()


## The left stick (or the move keys) moves the marker in the slot grid, with key-repeat.
func _poll_marker(delta: float) -> void:
	var move: Vector2 = _input.menu_move(index) if _input != null else Vector2.ZERO
	var dir := Vector2i.ZERO
	if move.length() > MOVE_THRESHOLD:
		dir = Vector2i(int(signf(move.x)), 0) if absf(move.x) > absf(move.y) else Vector2i(0, int(signf(move.y)))
	if dir != _move_dir:
		_move_dir = dir
		_move_wait = MOVE_DELAY
		if dir != Vector2i.ZERO:
			_move_marker(dir)
	elif dir != Vector2i.ZERO:
		_move_wait -= delta
		if _move_wait <= 0.0:
			_move_wait = MOVE_REPEAT
			_move_marker(dir)


func _move_marker(dir: Vector2i) -> void:
	var count: int = cards_of(_viewed).size()
	if count == 0:
		return
	var next: int = _slot + dir.x + dir.y * SLOT_COLUMNS
	if dir.y != 0 and (next < 0 or next >= count):
		return
	mark_slot(clampi(next, 0, count - 1))


## The right stick (P1's mouse) picks the card it points at; letting go (the mouse leaving the
## ring) lets the card go too, so the hub shows the staff's numbers again. A ring style
## (`ring_picker`) picks in its own way.
func _poll_pointer(delta: float) -> void:
	if _tree_open:
		# The right stick scrolls the tree.
		_tree.step(delta, _input.menu_tilt(index).y if _input != null else 0.0)
		return
	var aim: Vector2 = _menu.aim()
	if _menu.follow(aim):
		_dirty = true
	if _menu.is_empty():
		return
	var picked: int = ring_picker.pick(self, delta) if ring_picker != null else _menu.pick_on_ring(aim)
	if not _menu.point_at(picked, _clock):
		return
	if picked != NONE:
		_rumble(RUMBLE_POINT)
	_refresh_preview()
	_changed()


## The shared radial menu the ring is (for the ring styles, which pick and draw with it).
func menu() -> RadialMenuScript:
	return _menu


## The ring's angle of a direction: 0 is up, clockwise, 0 to TAU (the radial menu's).
static func angle_of(aim: Vector2) -> float:
	return RadialMenuScript.angle_of(aim)


## The direction of a ring angle (the inverse of `angle_of`).
static func direction_of(angle: float) -> Vector2:
	return RadialMenuScript.direction_of(angle)


## Hold LT (`staff_4`) to clear the rest of the staff, once per hold (owner, 2026-10-31). Its
## press has already acted (`_take_out`); with no card left there is nothing to clear and the
## hold ends quietly.
func _poll_clear(delta: float) -> void:
	var held: bool = _input != null and _input.is_held(index, &"staff_4")
	if not held:
		if _clear_held >= 0.0:
			_changed()
		_clear_held = -1.0
		_clear_done = false
		return
	if _clear_done:
		return
	if not cards_of(_viewed).any(func(id: StringName) -> bool: return id != NO_CARD):
		_clear_held = -1.0
		_clear_done = true
		_changed()
		return
	_clear_held = maxf(_clear_held, 0.0) + delta
	if _clear_held >= CLEAR_HOLD:
		_clear_held = -1.0
		_clear_done = true
		_clear()


## The slot under P1's mouse, or NONE.
func _mouse_slot() -> int:
	if not _uses_mouse():
		return NONE
	return _slot_at(get_global_mouse_position())


## P1's mouse wheel scrolls the tree.
func _unhandled_input(event: InputEvent) -> void:
	if not _open or not _tree_open or not _uses_mouse():
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_tree.wheel(-1)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_tree.wheel(1)


## P1's mouse works the slots and the tree too: whether it is P1's is the radial menu's question.
func _uses_mouse() -> bool:
	return _menu.uses_mouse()


# --- Building ---------------------------------------------------------------------------

func _put_in() -> void:
	var pointed: int = _menu.pointed
	if pointed == NONE:
		_say(POINT_NOTE)
		return
	var cards: Array[StringName] = cards_of(_viewed)
	if _slot >= cards.size():
		return
	var id: StringName = _entries[pointed]["id"]
	if put == Put.PUSH and cards[_slot] != NO_CARD:
		if cards[cards.size() - 1] != NO_CARD:
			_say(FULL_NOTE)
			_rumble(RUMBLE_REFUSED)
			return
		cards.insert(_slot, id)
		cards.resize(cards.size() - 1)
		_ask_all(cards)
	else:
		_ask_one(_slot, id)
	_fly(_spells.component_icon(id) if _spells != null else null, _menu.tile_center(_menu.angle_of_entry(pointed), RING_RADIUS), _slot_rect(_slot).get_center(), false)
	_rumble(RUMBLE_PUT)
	if _slot + 1 < cards.size():
		_slot += 1
		_marker_at = _clock
		_scroll_to_marker()
	_refresh_preview()
	_changed()


## What LT does on the marked slot: LT_TAKE, LT_UNDO, LT_GAP or `&""` (nothing).
func lt_action() -> StringName:
	var cards: Array[StringName] = cards_of(_viewed)
	if _slot >= cards.size():
		return &""
	if cards[_slot] != NO_CARD:
		return LT_TAKE
	var after: bool = false
	for slot in range(_slot + 1, cards.size()):
		after = after or cards[slot] != NO_CARD
	if after:
		return LT_GAP if put == Put.PUSH else &""
	for slot in _slot:
		if cards[slot] != NO_CARD:
			return LT_UNDO
	return &""


func _take_out() -> void:
	var action: StringName = lt_action()
	if action == &"":
		_say(EMPTY_NOTE)
		return
	var cards: Array[StringName] = cards_of(_viewed)
	var at: int = _slot
	if action == LT_UNDO:
		at = _slot - 1
		while at > 0 and cards[at] == NO_CARD:
			at -= 1
	var id: StringName = cards[at]
	if put == Put.PUSH:
		cards.remove_at(at)
		cards.append(NO_CARD)
		_ask_all(cards)
	else:
		_ask_one(at, NO_CARD)
	if id != NO_CARD:
		_fly(_spells.component_icon(id) if _spells != null else null, _slot_rect(at).get_center(), _menu.center, true)
	_rumble(RUMBLE_TAKE)
	if at != _slot:
		_slot = at
		_marker_at = _clock
		_scroll_to_marker()
	_refresh_preview()
	_changed()


func _clear() -> void:
	var cards: Array[StringName] = cards_of(_viewed)
	if not cards.any(func(id: StringName) -> bool: return id != NO_CARD):
		_say(EMPTY_NOTE)
		return
	_fading = cards
	_fade_start = _clock
	_ask_all([] as Array[StringName])
	_rumble(RUMBLE_CLEAR)
	_slot = 0
	_first_row = 0
	_marker_at = _clock
	_refresh_preview()
	_changed()


func _ask_one(slot: int, id: StringName) -> void:
	_note = ""
	if _events != null:
		_events.staff_change_requested.emit(index, _viewed, slot, id)


func _ask_all(cards: Array[StringName]) -> void:
	_note = ""
	if _events != null:
		_events.staff_cards_requested.emit(index, _viewed, cards)


func _say(text: String) -> void:
	_note = text
	_note_left = NOTE_TIME
	_changed()


func _rumble(motors: Vector3) -> void:
	if _input != null:
		_input.rumble(index, motors.x, motors.y, motors.z)


## The slot after the last card (the last slot when the staff is full; 0 when it is empty).
func _end_slot() -> int:
	var cards: Array[StringName] = cards_of(_viewed)
	var last: int = NONE
	for slot in cards.size():
		if cards[slot] != NO_CARD:
			last = slot
	return clampi(last + 1, 0, maxi(cards.size() - 1, 0))


func _show_staff(staff: int) -> void:
	_viewed = staff
	_strip_stale = true
	_slot = _end_slot()
	_first_row = 0
	_scroll_to_marker()
	if _tree_open:
		_sync_tree()
	_marker_at = _clock
	_refresh_preview()
	_changed()


func _scroll_to_marker() -> void:
	var row: int = _row_of(_slot)
	if row < _first_row:
		_first_row = row
	elif row >= _first_row + SLOT_ROWS:
		_first_row = row - SLOT_ROWS + 1


# --- Numbers ----------------------------------------------------------------------------

## The staff as RT would leave it with the pointed card, compiled for its numbers.
func _refresh_preview() -> void:
	_preview = {}
	_preview_cards = []
	_preview_view = {}
	if _menu.pointed == NONE or _spells == null:
		return
	var plan: Dictionary = _plan(_viewed)
	var staff: StaffBase = plan.get("staff") as StaffBase
	var cards: Array[StringName] = cards_of(_viewed)
	if staff == null or _slot >= cards.size():
		return
	var id: StringName = _entries[_menu.pointed]["id"]
	if put == Put.PUSH and cards[_slot] != NO_CARD:
		if cards[cards.size() - 1] != NO_CARD:
			return
		cards.insert(_slot, id)
		cards.resize(cards.size() - 1)
	else:
		cards[_slot] = id
	_preview_view = _spells.staff_view(cards, staff)
	_preview_cards = cards
	_preview = _numbers(_preview_view)


## A staff view's numbers: the dearest cast's mana, the cycle's damage and time.
func _numbers(plan: Dictionary) -> Dictionary:
	var mana: float = 0.0
	var damage: float = 0.0
	var seconds: float = 0.0
	var casts: Variant = plan.get("casts", [])
	if casts is Array:
		for cast: Variant in casts:
			if cast is Dictionary:
				mana = maxf(mana, float((cast as Dictionary).get("mana", 0.0)))
				damage += float((cast as Dictionary).get("damage", 0.0))
				# Its wind-up, then its wait (docs/milestones/cast-timing.md).
				seconds += float((cast as Dictionary).get("wind_up", 0.0)) + float((cast as Dictionary).get("delay", 0.0))
	return {"mana": mana, "damage": damage, "seconds": seconds}


## The share of the viewed staff's pool, in whole percent.
func _percent(mana: float) -> int:
	return roundi(mana / maxf(_pool_of(_viewed), 1.0) * 100.0)


func _number_lines(now: Dictionary, then: Dictionary) -> PackedStringArray:
	var mana: String = "Mana %d%%%s" % [_percent(float(now["mana"])), "!" if _percent(float(now["mana"])) > 100 else ""]
	# To a tenth: an atom's cast is 0.3.
	var damage: String = "Dmg %s" % SpellsScript._short(snappedf(float(now["damage"]), 0.1))
	var seconds: String = "Time %ss" % SpellsScript._short(float(now["seconds"]))
	if not then.is_empty():
		if _percent(float(then["mana"])) != _percent(float(now["mana"])):
			mana += " > %d%%%s" % [_percent(float(then["mana"])), "!" if _percent(float(then["mana"])) > 100 else ""]
		if not is_equal_approx(snappedf(float(then["damage"]), 0.1), snappedf(float(now["damage"]), 0.1)):
			damage += " > %s" % SpellsScript._short(snappedf(float(then["damage"]), 0.1))
		if not is_equal_approx(float(then["seconds"]), float(now["seconds"])):
			seconds += " > %ss" % SpellsScript._short(float(then["seconds"]))
	return PackedStringArray([mana, damage, seconds])


# --- Events -----------------------------------------------------------------------------

## The plan of staff number `staff` as announced (`{}` for one not owned).
func _plan(staff: int) -> Dictionary:
	return _plans.get(staff, {}) as Dictionary


func _on_owned_staff_changed(player: int, staff: int, plan: Dictionary) -> void:
	if player != index:
		return
	if plan.is_empty():
		_plans.erase(staff)
	else:
		_plans[staff] = plan.duplicate(true)
	_strip_order()
	_strip_stale = true
	if staff == _viewed:
		if not holds_staff(_viewed):
			# The staff shown went: show another, from its first slot.
			if holds_staff(_held_from(_viewed, 1)):
				_show_staff(_held_from(_viewed, 1))
			return
		var count: int = cards_of(_viewed).size()
		_slot = clampi(_slot, 0, maxi(count - 1, 0))
		_refresh_preview()
		if _tree_open:
			_sync_tree()
	_changed()


func _on_hands_changed(player: int, hands: PackedInt32Array) -> void:
	if player != index:
		return
	for hand in STAFF_COUNT:
		_hands[hand] = hands[hand] if hand < hands.size() else NONE
	_strip_order()
	_strip_stale = true
	_changed()


## The strip's order: the hands' staffs by button, then every other staff owned by number.
func _strip_order() -> void:
	_strip.clear()
	for hand in STAFF_COUNT:
		if _hands[hand] != NONE and holds_staff(_hands[hand]):
			_strip.append(_hands[hand])
	var rest: Array[int] = []
	for staff: int in _plans:
		if not _strip.has(staff):
			rest.append(staff)
	rest.sort()
	for staff in rest:
		_strip.append(staff)


func _on_bag_changed(player: int, bag: StringName, ids: Array[StringName], counts: PackedInt32Array, _capacity: int) -> void:
	if player != index or bag != ItemKinds.bag_of(ItemKinds.CARD):
		return
	var keep: StringName = pointed_id()
	var copies: Dictionary = {}
	for at in ids.size():
		if at < counts.size() and counts[at] > 0:
			copies[ids[at]] = int(copies.get(ids[at], 0)) + counts[at]
	_entries.clear()
	var held: Array[StringName] = []
	held.assign(copies.keys())
	var ordered: Array[StringName] = ring_order(held)
	# Every card at level 1, counted (items I3). Levels come with M3's rewards.
	for kind in KINDS:
		for id in ordered:
			if _spells == null or _spells.component_kind(id) != kind:
				continue
			_entries.append({"id": id, "level": 1, "count": int(copies[id]), "kind": kind})
	_kinds.clear()
	for kind in KINDS:
		if _entries.any(func(entry: Dictionary) -> bool: return entry["kind"] == kind):
			_kinds.append(kind)
	_kind_page = clampi(_kind_page, 0, maxi(_kinds.size() - 1, 0))
	_build_ring()
	_menu.pointed = NONE
	for at in _entries.size():
		if _entries[at]["id"] == keep:
			_menu.pointed = at
	_refresh_preview()
	_changed()


## `ids` A to Z by the name each card shows (natural order, any case: "Card 2" before "Card 10"),
## then by id. Only the ring's order: the bag itself stays as the player has it.
func ring_order(ids: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = ids.duplicate()
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var by_name: int = _name_of(a).naturalnocasecmp_to(_name_of(b))
		return by_name < 0 if by_name != 0 else String(a) < String(b))
	return out


func _on_build_refused(player: int, reason: String) -> void:
	if player != index:
		return
	_say(reason)


func _on_stats_changed(player: int, health: float, max_health: float, _mana_shown: float, _max_mana_shown: float) -> void:
	if player != index:
		return
	_health = health
	_max_health = maxf(max_health, 1.0)
	_changed()


func _on_staff_mana_changed(player: int, staff: int, mana: float, max_mana: float) -> void:
	if player != index or staff < 0 or staff >= _mana.size():
		return
	_mana[staff] = mana
	if max_mana > 0.0:
		_max_mana[staff] = max_mana
	if _tree_open and staff == _hand_of(_viewed) and max_mana > 0.0:
		_tree.set_plan(_plan(_viewed), _pool_of(_viewed))
	_changed()


func _on_closed(player: int) -> void:
	if player != index:
		return
	_open = false
	visible = false
	set_process(false)


func _on_cancelled(player: int) -> void:
	if player == index and _open:
		close_builder()


func _on_paged(player: int, step_by: int) -> void:
	if player == index and _open:
		_show_staff(_along_strip(_viewed, signi(step_by)))


# --- The ring ---------------------------------------------------------------------------

## Lay the ring out from the entries: every kind in order with a gap before each (layout ALL),
## or the shown kind alone (KIND). The first card sits at the top.
func _build_ring() -> void:
	var places := PackedInt32Array()
	var widths := PackedFloat32Array()
	if layout == Layout.ALL:
		for kind in _kinds:
			if _kinds.size() > 1:
				places.append(NONE)
				widths.append(GAP_WIDTH)
			for at in _entries.size():
				if _entries[at]["kind"] == kind:
					places.append(at)
					widths.append(1.0)
	elif not _kinds.is_empty():
		for at in _entries.size():
			if _entries[at]["kind"] == _kinds[_kind_page]:
				places.append(at)
				widths.append(1.0)
	_menu.lay_out(places, widths)
	if _menu.is_empty():
		return
	if ring_picker != null:
		ring_picker.reset()


## The kind of ring entry `entry` (the ring's arcs are by kind).
func _kind_of_entry(entry: int) -> StringName:
	return _entries[entry]["kind"]


# --- Layout -----------------------------------------------------------------------------

func _place() -> void:
	var view: Vector2 = get_viewport_rect().size
	var half: Vector2 = (view * 0.5).floor()
	var right: bool = index % 2 == 1
	var bottom: bool = index >= 2
	_quarter = Rect2(Vector2(half.x if right else 0.0, half.y if bottom else 0.0), half)
	# Every quarter as player 1's: the column on the left, the ring on its right (owner, 2026-10-31).
	var column_x: float = _quarter.position.x + EDGE
	var top: float = _quarter.position.y + 2.0
	_column = Rect2(column_x, top, COLUMN_WIDTH, _quarter.size.y - 4.0)
	_bars_at = Vector2(column_x, top)
	_tabs_at = Vector2(column_x + 2.0, top + TABS_FROM_TOP)
	_slots_at = Vector2(column_x + 4.0, top + SLOTS_FROM_TOP)
	var info_top: float = _slots_at.y + SLOT_STEP * SLOT_ROWS + 2.0
	_info = Rect2(column_x + 2.0, info_top, COLUMN_WIDTH - 4.0, _quarter.end.y - 3.0 - info_top)
	var ring_left: float = column_x + COLUMN_WIDTH + EDGE
	var ring_right: float = _quarter.end.x - EDGE
	_menu.center = Vector2(floorf((ring_left + ring_right) * 0.5), _quarter.position.y + RING_FROM_EDGE)
	_menu.hints_at = Vector2(ring_left, _quarter.end.y - HINT_HEIGHT - 2.0)
	_kinds_at = Vector2(_menu.center.x, _quarter.position.y + 2.0)
	# The ring's side, from the top down to the hint row: the tree's space (part T5).
	_ring_side = Rect2(ring_left, top, ring_right - ring_left, _menu.hints_at.y - 1.0 - top)
	_tree.position = _ring_side.position
	_tree.size = _ring_side.size
	var tab_x: float = _tabs_at.x
	_glyph_prev.position = Vector2(tab_x, _tabs_at.y)
	_glyph_next.position = Vector2(tab_x + _glyph_prev.custom_minimum_size.x + 3.0 + _strip_width() + 1.0, _tabs_at.y)


func _row_of(slot: int) -> int:
	return floori(float(slot) / float(SLOT_COLUMNS))


func _slot_rect(slot: int) -> Rect2:
	var row: int = _row_of(slot) - _first_row
	var col: int = slot % SLOT_COLUMNS
	return Rect2(_slots_at + Vector2(col * SLOT_STEP, row * SLOT_STEP), Vector2(SLOT_SIZE, SLOT_SIZE))


func _slot_shown(slot: int) -> bool:
	var row: int = _row_of(slot) - _first_row
	return row >= 0 and row < SLOT_ROWS


func _slot_at(point: Vector2) -> int:
	var count: int = cards_of(_viewed).size()
	for slot in count:
		if _slot_shown(slot) and _slot_rect(slot).grow(1.0).has_point(point):
			return slot
	return NONE


## Lay the hint row out for what the buttons do now: RT, LT (its verb follows the marked
## slot), Y (the tree or the ring) and B, each glyph then its verb.
func _refresh_hints() -> void:
	var lt: StringName = lt_action()
	var verbs: Array[String] = [PUT_VERB, UNDO_VERB if lt == LT_UNDO else (GAP_VERB if lt == LT_GAP else TAKE_VERB), RING_VERB if _tree_open else TREE_VERB, CLOSE_VERB]
	var live: Array[bool] = [_menu.pointed != NONE and not _tree_open, lt != &"", true, true]
	_menu.set_hints(verbs, live)
	var show_kinds: bool = layout == Layout.KIND and _kinds.size() > 1 and not _tree_open
	for glyph in _kind_glyphs:
		glyph.visible = show_kinds
	if show_kinds:
		var width: float = _kind_tabs_width()
		_kind_glyphs[0].position = Vector2(_kinds_at.x - width * 0.5 - _kind_glyphs[0].custom_minimum_size.x - 3.0, _kinds_at.y)
		_kind_glyphs[1].position = Vector2(_kinds_at.x + width * 0.5 + 3.0, _kinds_at.y)


func _kind_tabs_width() -> float:
	var width: float = 0.0
	for kind in _kinds:
		width += _text_width(String(KIND_WORDS[kind]).left(1)) + 7.0
	return width - 2.0


# --- Drawing ----------------------------------------------------------------------------

func _changed() -> void:
	_dirty = true
	if _open and not is_processing():
		set_process(true)


func _text_width(text: String) -> float:
	return _menu.text_width(text)


## Draw `text` with its top left at `at` (or centred on `at.x`).
func _text(text: String, at: Vector2, color: Color, centered: bool = false) -> void:
	_menu.draw_text(text, at, color, centered)


func _frame(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color, false, 1.0)


func _draw() -> void:
	if not _open:
		return
	draw_rect(_quarter, SHADE)
	_draw_bars()
	_draw_tabs()
	_draw_slots()
	_draw_info()
	if not _tree_open:
		_draw_ring()
		_draw_hub()
	_menu.draw_hints()
	_draw_flyers()


## Lay the strip of staffs out (see the class doc): the hands' tabs (each its glyph's width), then
## the bag's, scrolled so the shown staff's tab is in view; each hand's glyph on its tab.
func _place_strip() -> void:
	_strip_stale = false
	_strip_glyphs = _hand_glyph_widths()
	_tab_numbers.clear()
	_tab_hands.clear()
	_tab_rects.clear()
	var widths: Array[float] = []
	for hand in STAFF_COUNT:
		_tab_numbers.append(_hands[hand] if holds_staff(_hands[hand]) else NONE)
		_tab_hands.append(hand)
		widths.append(maxf(_hand_glyphs[hand].custom_minimum_size.x + TAB_PAD * 2.0, TAB_WIDTH))
	for staff in _strip:
		if _hand_of(staff) == NONE:
			_tab_numbers.append(staff)
			_tab_hands.append(NONE)
			widths.append(TAB_WIDTH)
	var left: float = _tabs_at.x + _glyph_prev.custom_minimum_size.x + 3.0
	var room: float = _strip_width()
	_glyph_next.position = Vector2(left + room + 1.0, _tabs_at.y)
	var shown: int = _tab_numbers.find(_viewed)
	if shown >= 0:
		_strip_first = mini(_strip_first, shown)
		while _strip_first < shown and _width_of(widths, _strip_first, shown) > room:
			_strip_first += 1
	_strip_first = clampi(_strip_first, 0, maxi(_tab_numbers.size() - 1, 0))
	var x: float = left
	for at in _tab_numbers.size():
		var rect := Rect2(x, _tabs_at.y - 1.0, widths[at], TAB_HEIGHT)
		var visible_tab: bool = at >= _strip_first and rect.end.x <= left + room
		if at < _strip_first:
			rect.position.x = -1000.0
		else:
			x += widths[at] + TAB_GAP
		if not visible_tab:
			rect.position.x = -1000.0
		_tab_rects.append(rect)
		var hand: int = _tab_hands[at]
		if hand != NONE:
			var glyph: ActionGlyphScript = _hand_glyphs[hand]
			glyph.visible = _open and visible_tab
			glyph.position = rect.position + Vector2(floorf((rect.size.x - glyph.custom_minimum_size.x) * 0.5), 1.0)
			glyph.modulate = Color(1.0, 1.0, 1.0, 1.0 if _tab_numbers[at] != NONE else 0.35)


## The hand glyphs' widths added up (a device change resizes them; no allocation).
func _hand_glyph_widths() -> float:
	var total: float = _glyph_prev.custom_minimum_size.x + _glyph_next.custom_minimum_size.x
	for glyph in _hand_glyphs:
		total += glyph.custom_minimum_size.x
	return total


## The strip's width: the column's room between the paging glyphs, less the shown rows' range
## when the staff has more slots than show.
func _strip_width() -> float:
	var room: float = COLUMN_WIDTH - 4.0 - _glyph_prev.custom_minimum_size.x - 3.0 - 1.0 - _glyph_next.custom_minimum_size.x
	var count: int = cards_of(_viewed).size()
	if ceili(float(count) / float(SLOT_COLUMNS)) > SLOT_ROWS:
		room -= _text_width("%d-%d" % [count, count]) + 4.0
	return room


## The width of tabs `from` to `to` (both in) with their gaps.
static func _width_of(widths: Array[float], from: int, to: int) -> float:
	var total: float = 0.0
	for at in range(from, to + 1):
		total += widths[at] + (TAB_GAP if at > from else 0.0)
	return total


## The strip's tabs as drawn (for tests): per tab {staff (NONE: an empty hand), hand (NONE: in the
## bag), rect (off to the left when scrolled out)}.
func strip_tabs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for at in _tab_numbers.size():
		out.append({"staff": _tab_numbers[at], "hand": _tab_hands[at], "rect": _tab_rects[at]})
	return out


func _draw_tabs() -> void:
	var hidden_before: bool = false
	var hidden_after: bool = false
	for at in _tab_numbers.size():
		var rect: Rect2 = _tab_rects[at]
		if rect.position.x < 0.0:
			if at < _strip_first:
				hidden_before = true
			else:
				hidden_after = true
			continue
		var staff: int = _tab_numbers[at]
		if staff == NONE:
			# An empty hand: an outline under its dim glyph, never shown.
			_frame(rect, LINE)
			continue
		var on: bool = staff == _viewed
		draw_rect(rect, LINE if not on else GOLD.darkened(0.35))
		_frame(rect, GOLD if on else DIM)
		if _tab_hands[at] == NONE:
			# A staff in the bag: its head.
			var base: StaffBase = _plan(staff).get("staff") as StaffBase
			if base != null and base.head != null:
				draw_texture_rect(base.head, Rect2(rect.position + Vector2(1.0, 0.5), Vector2(10.0, 10.0)), false)
			else:
				_text("*", Vector2(rect.get_center().x, rect.position.y + 1.0), OUTLINE if on else TEXT, true)
	# More staffs past an end of the strip: a small gold notch under that end.
	var y: float = _tabs_at.y + TAB_HEIGHT
	if hidden_before:
		draw_rect(Rect2(_glyph_prev.position.x + _glyph_prev.custom_minimum_size.x + 1.0, y, 2.0, 2.0), GOLD)
	if hidden_after:
		draw_rect(Rect2(_glyph_next.position.x - 3.0, y, 2.0, 2.0), GOLD)
	var count: int = cards_of(_viewed).size()
	var rows: int = ceili(float(count) / float(SLOT_COLUMNS))
	if rows > SLOT_ROWS:
		# Which rows show, when the staff has more than fit.
		_text("%d-%d" % [_first_row * SLOT_COLUMNS + 1, mini((_first_row + SLOT_ROWS) * SLOT_COLUMNS, count)], Vector2(_glyph_next.position.x + _glyph_next.custom_minimum_size.x + 4.0, _tabs_at.y + 1.0), DIM)


func _draw_slots() -> void:
	# While a card is pointed at, the slots show the staff as RT would leave it: the card faded in
	# at the marker, the rest pushed on, and that staff's casts and wasted cards (owner, 2026-10-27).
	var previewing: bool = not _preview_cards.is_empty()
	var cards: Array[StringName] = _preview_cards if previewing else cards_of(_viewed)
	var plan: Dictionary = _preview_view if previewing else _plan(_viewed)
	var wasted: Dictionary = plan.get("wasted", {}) as Dictionary
	var fade: float = 1.0 - clampf((_clock - _fade_start) / FADE_TIME, 0.0, 1.0) if not _fading.is_empty() else 0.0
	var landing: Dictionary = {}
	for flyer in _flyers:
		if not bool(flyer["fade"]):
			landing[int(flyer["slot"])] = true
	for slot in cards.size():
		if not _slot_shown(slot):
			continue
		var rect: Rect2 = _slot_rect(slot)
		var id: StringName = cards[slot]
		if id == NO_CARD or landing.has(slot):
			draw_rect(rect, EMPTY)
			_frame(rect, TILE)
		elif previewing and slot == _slot:
			draw_rect(rect, EMPTY)
			_draw_icon(id, rect, 0.55)
		else:
			_draw_card(id, rect, 1.0)
		if id != NO_CARD and not landing.has(slot) and wasted.has(slot):
			_text("!", rect.position + Vector2(rect.size.x - 4.0, -1.0), WARN)
		if fade > 0.0 and slot < _fading.size() and _fading[slot] != NO_CARD:
			_draw_card(_fading[slot], rect, fade)
	_draw_groups(_groups_of(plan, cards.size()))
	# The marked slot: the pointed card faded in it (drawn above when previewing; a caret where a
	# push is refused, the staff being full), then the gold marker with corner ticks, so it reads
	# without its colour.
	if _slot < cards.size() and _slot_shown(_slot):
		var mark: Rect2 = _slot_rect(_slot)
		if _menu.pointed != NONE and not previewing:
			var ghost: StringName = _entries[_menu.pointed]["id"]
			if put == Put.PUSH and cards[_slot] != NO_CARD:
				draw_rect(Rect2(mark.position.x - 2.0, mark.position.y - 1.0, 2.0, mark.size.y + 2.0), GOLD)
			else:
				draw_rect(mark, EMPTY)
				_draw_icon(ghost, mark, 0.55)
		var grow: float = 1.0 if _clock - _marker_at < POP_TIME else 0.0
		var frame: Rect2 = mark.grow(2.0 + grow)
		_frame(frame, GOLD)
		draw_rect(Rect2(frame.position - Vector2(1.0, 1.0), Vector2(3.0, 1.0)), GOLD)
		draw_rect(Rect2(frame.position - Vector2(1.0, 1.0), Vector2(1.0, 3.0)), GOLD)
		draw_rect(Rect2(frame.end - Vector2(2.0, 0.0), Vector2(3.0, 1.0)), GOLD)
		draw_rect(Rect2(frame.end - Vector2(0.0, 2.0), Vector2(1.0, 3.0)), GOLD)
	if _clear_held >= CLEAR_SHOW:
		var share: float = clampf(_clear_held / CLEAR_HOLD, 0.0, 1.0)
		var shown: int = mini(cards.size() - _first_row * SLOT_COLUMNS, SLOT_ROWS * SLOT_COLUMNS)
		var box := Rect2(_slots_at - Vector2(3.0, 3.0), Vector2(SLOT_STEP * SLOT_COLUMNS + 4.0, SLOT_STEP * ceili(float(shown) / float(SLOT_COLUMNS)) + 4.0))
		_frame(box, Color(WARN, 0.3 + 0.6 * share))
		draw_rect(Rect2(box.position.x, box.end.y, box.size.x * share, 2.0), WARN)


## The casts of the cycle (owner, 2026-10-27: "show these groups when building the staff"): the
## slots each cast reads share one frame per row, every other cast in the other Bone shade, so
## the cards that fire together read as a group and a break between frames ends a cast. A slot
## read again by a wrapped last cast keeps the frame of its first cast.
func _draw_groups(groups: PackedInt32Array) -> void:
	for slot in groups.size():
		var group: int = groups[slot]
		if group < 0 or not _slot_shown(slot):
			continue
		var color: Color = GROUP_COLORS[group % GROUP_COLORS.size()]
		var box: Rect2 = _slot_rect(slot).grow(1.0)
		var joined_left: bool = slot % SLOT_COLUMNS > 0 and groups[slot - 1] == group
		var joined_right: bool = slot % SLOT_COLUMNS < SLOT_COLUMNS - 1 and slot + 1 < groups.size() and groups[slot + 1] == group
		draw_rect(Rect2(box.position.x, box.position.y, box.size.x, 1.0), color)
		draw_rect(Rect2(box.position.x, box.end.y - 1.0, box.size.x, 1.0), color)
		if not joined_left:
			draw_rect(Rect2(box.position.x, box.position.y, 1.0, box.size.y), color)
		if not joined_right:
			draw_rect(Rect2(box.end.x - 1.0, box.position.y, 1.0, box.size.y), color)


## Per slot of the shown staff, the cast of its cycle that first reads it (0 first), or -1 for a
## slot no cast reads; while a card is pointed at, of the staff as RT would leave it. Allocates;
## called when the radial redraws and by tests.
func slot_groups() -> PackedInt32Array:
	if not _preview_cards.is_empty():
		return _groups_of(_preview_view, _preview_cards.size())
	return _groups_of(_plan(_viewed), cards_of(_viewed).size())


func _groups_of(plan: Dictionary, count: int) -> PackedInt32Array:
	var groups := PackedInt32Array()
	groups.resize(count)
	groups.fill(-1)
	var casts: Variant = plan.get("casts", [])
	if not casts is Array:
		return groups
	for c in (casts as Array).size():
		var cast: Variant = (casts as Array)[c]
		if not cast is Dictionary:
			continue
		for slot: int in (cast as Dictionary).get("slots", PackedInt32Array()):
			if slot >= 0 and slot < groups.size() and groups[slot] < 0:
				groups[slot] = c
	return groups


func _draw_card(id: StringName, rect: Rect2, alpha: float) -> void:
	draw_rect(rect, Color(TILE, alpha))
	_draw_icon(id, rect, alpha)
	var kind: StringName = _spells.component_kind(id) if _spells != null else &""
	draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), Color(KIND_COLORS.get(kind, DIM), alpha))


func _draw_icon(id: StringName, rect: Rect2, alpha: float) -> void:
	var icon: Texture2D = _spells.component_icon(id) if _spells != null else null
	if icon == null:
		return
	var size: float = minf(ICON_SIZE, rect.size.x)
	var at: Vector2 = (rect.get_center() - Vector2(size, size) * 0.5).round()
	draw_texture_rect(icon, Rect2(at, Vector2(size, size)), false, Color(1.0, 1.0, 1.0, alpha))


## The HP and MP bars on top of the column, framed in the player's colour (owner, 2026-10-31).
func _draw_bars() -> void:
	var frame := Rect2(_bars_at, Vector2(COLUMN_WIDTH, BARS_HEIGHT))
	draw_rect(frame, PLAYER_COLORS[clampi(index, 0, PLAYER_COUNT - 1)])
	var inner := Rect2(frame.position + Vector2(1.0, 1.0), Vector2(frame.size.x - 2.0, 2.0))
	var shares: Vector2 = bar_shares()
	draw_rect(inner, OUTLINE)
	draw_rect(Rect2(inner.position, Vector2(roundf(inner.size.x * shares.x), 2.0)), HEALTH_COLOR)
	var lower := Rect2(inner.position + Vector2(0.0, 3.0), inner.size)
	draw_rect(lower, OUTLINE)
	draw_rect(Rect2(lower.position, Vector2(roundf(lower.size.x * shares.y), 2.0)), MANA_COLOR)


## The card info panel: the card under the slot marker (`card_info`), and a refusal's note over its top.
func _draw_info() -> void:
	var box: Rect2 = _info
	var info: Dictionary = card_info()
	draw_rect(box, OUTLINE)
	if info["id"] == NO_CARD:
		_frame(box, LINE)
		_text(info["name"], box.position + Vector2(3.0, 2.0), DIM)
	else:
		var kind: StringName = _spells.component_kind(info["id"]) if _spells != null else &""
		var color: Color = KIND_COLORS.get(kind, DIM)
		_frame(box, color)
		var kind_word: String = info["kind"]
		var kind_x: float = box.end.x - 3.0 - _text_width(kind_word)
		_text(_fit(info["name"], kind_x - box.position.x - 6.0), box.position + Vector2(3.0, 2.0), TEXT)
		_text(kind_word, Vector2(kind_x, box.position.y + 2.0), color)
		var stats: PackedStringArray = info["stats"]
		var stats_y: float = box.end.y - 2.0 - stats.size() * LINE_STEP
		var first_y: float = box.position.y + 2.0 + LINE_STEP
		var bottom: float = stats_y - 2.0 if not stats.is_empty() else box.end.y - 2.0
		var lines: PackedStringArray = info["lines"]
		var room: int = maxi(floori((bottom - first_y) / LINE_STEP), 0)
		for at in mini(lines.size(), room):
			var line: String = lines[at]
			if at == room - 1 and lines.size() > room:
				line = _fit(line + "..", box.size.x - 6.0)
			_text(line, Vector2(box.position.x + 3.0, first_y + at * LINE_STEP), MUTED)
		if not stats.is_empty():
			draw_rect(Rect2(box.position.x + 2.0, stats_y - 2.0, box.size.x - 4.0, 1.0), LINE)
			for at in stats.size():
				_text(stats[at], Vector2(box.position.x + 3.0, stats_y + at * LINE_STEP), TEXT)
	if note_text() != "":
		var note := Rect2(box.position, Vector2(box.size.x, LINE_STEP + 3.0))
		draw_rect(note, OUTLINE)
		_frame(note, WARN)
		_text(_fit(_note, box.size.x - 6.0), note.position + Vector2(3.0, 1.0), WARN)


## `text` broken into lines of at most `width` pixels, at spaces (a word too long is cut).
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


func _draw_ring() -> void:
	if _menu.is_empty():
		return
	if ring_picker != null and ring_picker.draw(self):
		return
	_menu.draw_ring_line()
	# The kind arcs, outside the ring.
	_menu.draw_group_arcs(_kind_of_entry, KIND_COLORS)
	if layout == Layout.KIND and _kinds.size() > 1:
		_draw_kind_tabs()
	# Where the stick points.
	_menu.draw_pointer()
	var size: float = clampf(floorf(_menu.place_room()) - 2.0, 3.0, TILE_MAX)
	var places: PackedInt32Array = _menu.place_entries()
	var angles: PackedFloat32Array = _menu.place_angles()
	var pointed: int = _menu.pointed
	for at in places.size():
		var entry: int = places[at]
		if entry == NONE or entry == pointed:
			continue
		_draw_ring_card(entry, _menu.tile_center(angles[at], RING_RADIUS), size, false)
	if pointed != NONE:
		var since: float = _menu.pointed_for(_clock)
		var pop: float = clampf(since / POP_TIME, 0.0, 1.0)
		var shake: float = 1.0 if since < POP_TIME * 1.5 and int(since / 0.03) % 2 == 1 else 0.0
		_draw_ring_card(pointed, _menu.tile_center(_menu.angle_of_entry(pointed), RING_RADIUS + 4.0 * pop) + Vector2(shake, 0.0), TILE_PICKED, true)


func _draw_ring_card(entry: int, middle: Vector2, size: float, picked: bool) -> void:
	var id: StringName = _entries[entry]["id"]
	var kind: StringName = _entries[entry]["kind"]
	var rect := Rect2((middle - Vector2(size, size) * 0.5).round(), Vector2(size, size))
	if size < ICON_MIN:
		draw_rect(rect, KIND_COLORS[kind])
		return
	draw_rect(rect, TILE)
	_draw_icon(id, rect.grow(-1.0) if size < ICON_SIZE + 2.0 else rect, 1.0)
	draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), KIND_COLORS[kind])
	if picked:
		_frame(rect.grow(1.0), GOLD)
		_frame(rect.grow(2.0), GOLD)
	var count: int = int(_entries[entry]["count"])
	if count > 1:
		var number: String = str(count)
		var badge := Rect2(rect.end - Vector2(_text_width(number) + 2.0, 8.0), Vector2(_text_width(number) + 2.0, 8.0))
		draw_rect(badge, OUTLINE)
		_text(number, badge.position + Vector2(1.0, -1.0), TEXT)
	var level: int = int(_entries[entry]["level"])
	if level > 1:
		var word: String = "L%d" % level
		draw_rect(Rect2(rect.position, Vector2(_text_width(word) + 2.0, 8.0)), OUTLINE)
		_text(word, rect.position + Vector2(1.0, -1.0), GOLD)


func _draw_kind_tabs() -> void:
	var x: float = _kinds_at.x - _kind_tabs_width() * 0.5
	for kind in _kinds:
		var letter: String = String(KIND_WORDS[kind]).left(1)
		var rect := Rect2(x, _kinds_at.y, _text_width(letter) + 5.0, 10.0)
		var on: bool = kind == _kinds[_kind_page]
		draw_rect(rect, KIND_COLORS[kind] if on else LINE)
		_text(letter, Vector2(rect.get_center().x, rect.position.y), OUTLINE if on else MUTED, true)
		x += rect.size.x + 2.0


func _draw_hub() -> void:
	_menu.draw_hub()
	var center: Vector2 = _menu.center
	var pointed: int = _menu.pointed
	var lines: PackedStringArray = hub_lines()
	if pointed != NONE:
		var id: StringName = _entries[pointed]["id"]
		_draw_icon(id, Rect2(center + Vector2(-8.0, -34.0), Vector2(ICON_SIZE, ICON_SIZE)), 1.0)
		_text(lines[0], center + Vector2(0.0, -17.0), TEXT, true)
		_text(lines[1], center + Vector2(0.0, -8.0), KIND_COLORS.get(_entries[pointed]["kind"], MUTED), true)
		for at in range(2, lines.size()):
			_text(lines[at], center + Vector2(0.0, 1.0 + (at - 2) * LINE_STEP), MUTED, true)
		return
	_text(lines[0], center + Vector2(0.0, -26.0), TEXT, true)
	for at in range(1, lines.size()):
		var line: String = lines[at]
		_text(line, center + Vector2(0.0, -13.0 + (at - 1) * LINE_STEP), WARN if line.ends_with("!") else MUTED, true)
	# An empty bag says so; otherwise the hub asks for a card.
	_text(NO_CARDS_TEXT if _menu.is_empty() else "Point", center + Vector2(0.0, 17.0), DIM, true)


## `text` cut with ".." to fit `width` pixels.
func _fit(text: String, width: float) -> String:
	if _text_width(text) <= width:
		return text
	var cut: String = text
	while cut.length() > 1 and _text_width(cut + "..") > width:
		cut = cut.left(cut.length() - 1)
	return cut + ".."


func _draw_flyers() -> void:
	for flyer in _flyers:
		var share: float = clampf((_clock - float(flyer["start"])) / FLY_TIME, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - share, 3.0)
		var at: Vector2 = (flyer["from"] as Vector2).lerp(flyer["to"] as Vector2, eased)
		var icon: Texture2D = flyer["texture"]
		if icon != null:
			var alpha: float = 1.0 - share if bool(flyer["fade"]) else 1.0
			draw_texture_rect(icon, Rect2((at - Vector2(8.0, 8.0)).round(), Vector2(ICON_SIZE, ICON_SIZE)), false, Color(1.0, 1.0, 1.0, alpha))


func _fly(icon: Texture2D, from: Vector2, to: Vector2, fade: bool) -> void:
	_flyers.append({"texture": icon, "from": from, "to": to, "start": _clock, "fade": fade, "slot": _slot})


func _make_glyph(node_name: String) -> ActionGlyphScript:
	var glyph: ActionGlyphScript = ActionGlyphScript.new()
	glyph.name = node_name
	add_child(glyph)
	return glyph


func _name_of(id: StringName) -> String:
	var shown: String = _spells.component_name(id) if _spells != null else ""
	return shown if shown != "" else String(id)
