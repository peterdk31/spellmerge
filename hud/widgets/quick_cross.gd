extends Control
## A seat's four quick-use slots on its corner panel (the owner, 2026-11-20: "each D-pad direction can
## be bound to a usable item"): a small d-pad cross, each arm a cell with the bound item's icon and how
## many of it the shown body holds, the cross's middle its nub. A slot with none left keeps its item,
## greyed, its count 0 (it is full again as one is taken); a slot bound to nothing is an empty cell.
## **The cross always shows** (the owner, 2026-11-20), every arm an empty cell before anything is
## bound, as a hint that the d-pad binds: it takes its SIDE × SIDE from the start, beside the staff
## rows (no taller than four six-slot rows, and inside a quarter pane of the Equal split).
## `player_panel.gd` puts it beside the staff rows; `panels.gd` tells it (`set_slot`) from
## `quick_bound` and `bag_changed`.
##
## **Smooth** (docs/STYLE.md): nothing jumps. A slot steps through its looks at FPS (its cell's
## frame, its icon in shadow, two shades between, its icon): to its frame for a slot bound to
## nothing, to its shadow for one with none left (greying and filling again through the shades
## between); its icon goes out the same way before another comes in. A count that changes nods its
## cell up a pixel (more) or dips it (fewer) through NOD's poses. Whole pixels, never a fade or a
## blur. A slot whose item recharges (an active relic's cooldown: `set_recharge`, told by the
## simulation at each sixteenth) has a shutter over its icon; the rows drawn step toward the rows told
## a row a frame, so it drops in over its rows after a use and sinks a row at a time as it recharges
## (`RechargeShutter`). The cross keeps no clock for it.
##
## Display only: no input, no simulation state; it processes only while something steps and
## allocates nothing a frame.

const RechargeShutter := preload("res://hud/widgets/recharge_shutter.gd")

const SLOTS: int = 4
## A cell's side (an 8-pixel icon in a 1-pixel frame) and where each slot's cell sits in the cross
## (0 up, 1 right, 2 down, 3 left), its nub in the middle.
const CELL: int = 10
const ICON: int = 8
const SIDE: int = CELL * 3
const AT: Array[Vector2i] = [Vector2i(CELL, 0), Vector2i(CELL * 2, CELL), Vector2i(CELL, CELL * 2), Vector2i(0, CELL)]
const NUB: Vector2i = Vector2i(CELL, CELL)
## A slot's looks: 1 its frame (an empty cell), 2 its icon in shadow, 3 and 4 shades between, 5 its
## icon.
const FRAMED: int = 1
const SHADOW: int = 2
const FULL: int = 5
## How fast every stage steps.
const FPS: float = 20.0
## A count's nod: its cell's offsets (pixels, negative up), a pose a step.
const NOD_UP: PackedInt32Array = [-1, -1, 0]
const NOD_DOWN: PackedInt32Array = [1, 1, 0]
## The digits, 3 × 5 pixels each: digit d's rows are DIGITS[d * 5] to DIGITS[d * 5 + 4] (`#` lit).
const DIGITS: PackedStringArray = [
	"###", "#.#", "#.#", "#.#", "###", ".#.", "##.", ".#.", ".#.", "###",
	"###", "..#", "###", "#..", "###", "###", "..#", "###", "..#", "###",
	"#.#", "#.#", "###", "..#", "..#", "###", "#..", "###", "..#", "###",
	"###", "#..", "###", "#.#", "###", "###", "..#", ".#.", ".#.", ".#.",
	"###", "#.#", "###", "#.#", "###", "###", "#.#", "###", "..#", "###",
]
const OUTLINE: Color = Color("#14121f")
const CELL_FACE: Color = Color("#2b2840")
const LINE: Color = Color("#4a4663")
const TEXT: Color = Color("#f4f1ea")
const DIM: Color = Color("#7a7694")
## An icon with none left is drawn in this shade.
const GREY: Color = Color(0.32, 0.31, 0.38, 1.0)

## By slot: the icon bound and its count (told), the icon drawn, its stage, its count drawn and its nod.
var _icon: Array[Texture2D] = [null, null, null, null]
var _count: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _drawn_icon: Array[Texture2D] = [null, null, null, null]
var _stage: PackedInt32Array = PackedInt32Array([FRAMED, FRAMED, FRAMED, FRAMED])
var _drawn_count: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _nod: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _nod_way: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _clock: float = 0.0
## By slot: the shutter rows told (its item's recharge) and the rows drawn, stepping toward them.
var _charge_told: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _charge_rows: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(SIDE, SIDE)
	set_process(false)


## Slot `slot` holds `icon` (null: bound to nothing) and `count` of it. With `at_once`, drawn as it
## stands (a run's start, a snapshot restored).
func set_slot(slot: int, icon: Texture2D, count: int, at_once: bool = false) -> void:
	if slot < 0 or slot >= SLOTS:
		return
	if icon != _icon[slot]:
		# Another item: its own recharge, if any, is told next.
		_charge_told[slot] = 0
	_icon[slot] = icon
	_count[slot] = maxi(count, 0)
	if at_once:
		_drawn_icon[slot] = icon
		_stage[slot] = _wanted(slot)
		_drawn_count[slot] = _count[slot]
		_nod[slot] = 0
		_charge_rows[slot] = _charge_target(slot)
	set_process(is_moving())
	queue_redraw()


## Slot `slot`'s item recharges for `left` more seconds of its `whole` cooldown (0: ready), as the
## simulation told it. With `at_once`, drawn as it stands.
func set_recharge(slot: int, left: float, whole: float, at_once: bool = false) -> void:
	if slot < 0 or slot >= SLOTS:
		return
	_charge_told[slot] = RechargeShutter.rows(left, whole, ICON)
	if at_once:
		_charge_rows[slot] = _charge_target(slot)
	set_process(is_moving())
	queue_redraw()


## The shutter rows drawn over slot `slot`'s icon (0: none; for tests).
func recharge_rows(slot: int) -> int:
	return _charge_rows[slot]


## Slot `slot`'s stage (FRAMED ... FULL; for tests), its count drawn and whether it is bound.
func stage_of(slot: int) -> int:
	return _stage[slot]


func count_of(slot: int) -> int:
	return _drawn_count[slot]


func is_bound(slot: int) -> bool:
	return _icon[slot] != null


## True while a stage still steps.
func is_moving() -> bool:
	for slot in SLOTS:
		if _charge_rows[slot] != _charge_target(slot):
			return true
		if _stage[slot] != _wanted(slot) or _drawn_icon[slot] != _icon[slot] or _drawn_count[slot] != _count[slot] or _nod[slot] != 0:
			return true
	return false


## One step of every stage (a frame at FPS; tests call it directly).
func advance() -> void:
	for slot in SLOTS:
		_charge_rows[slot] += signi(_charge_target(slot) - _charge_rows[slot])
	for slot in SLOTS:
		if _nod[slot] != 0:
			_nod[slot] = (_nod[slot] + 1) % (NOD_UP.size() + 1)
			continue
		if _drawn_icon[slot] != _icon[slot]:
			# Another item: the one drawn goes out to its frame before the next comes in.
			if _stage[slot] > FRAMED:
				_stage[slot] -= 1
			else:
				_drawn_icon[slot] = _icon[slot]
			continue
		var wanted: int = _wanted(slot)
		if _stage[slot] != wanted:
			_stage[slot] += signi(wanted - _stage[slot])
		elif _drawn_count[slot] != _count[slot] and _stage[slot] >= SHADOW:
			_nod_way[slot] = signi(_count[slot] - _drawn_count[slot])
			_drawn_count[slot] = _count[slot]
			_nod[slot] = 1
		elif _drawn_count[slot] != _count[slot]:
			_drawn_count[slot] = _count[slot]
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	while _clock >= 1.0 / FPS:
		_clock -= 1.0 / FPS
		advance()
	if not is_moving():
		_clock = 0.0
		set_process(false)


## The rows slot `slot`'s shutter is going to: what was told, none while its icon goes out.
func _charge_target(slot: int) -> int:
	return _charge_told[slot] if _drawn_icon[slot] == _icon[slot] else 0


func _wanted(slot: int) -> int:
	if _icon[slot] == null:
		return FRAMED
	return FULL if _count[slot] > 0 else SHADOW


func _draw() -> void:
	var nub := Rect2(Vector2(NUB), Vector2(CELL, CELL))
	draw_rect(nub.grow(-2.0), OUTLINE)
	draw_rect(nub.grow(-3.0), LINE)
	for slot in SLOTS:
		_draw_slot(slot)


func _draw_slot(slot: int) -> void:
	var stage: int = _stage[slot]
	var nod: int = 0
	if _nod[slot] > 0:
		nod = (NOD_UP if _nod_way[slot] > 0 else NOD_DOWN)[_nod[slot] - 1]
	var cell := Rect2(Vector2(AT[slot] + Vector2i(0, nod)), Vector2(CELL, CELL))
	draw_rect(cell, OUTLINE)
	if stage < SHADOW:
		# An empty cell: a frame round nothing, so the arm reads as a slot to bind.
		draw_rect(cell.grow(-1.0), LINE)
		draw_rect(cell.grow(-2.0), OUTLINE)
		return
	draw_rect(cell.grow(-1.0), CELL_FACE)
	if _drawn_icon[slot] != null:
		# Shadow, the shades between, full: whole steps of the tint, never a fade of the icon.
		var tint: Color = GREY.lerp(Color.WHITE, float(stage - SHADOW) / float(FULL - SHADOW))
		draw_texture_rect(_drawn_icon[slot], Rect2(cell.position + Vector2(1, 1), Vector2(ICON, ICON)), false, tint)
		RechargeShutter.draw(self, Rect2(cell.position + Vector2(1, 1), Vector2(ICON, ICON)), _charge_rows[slot])
		_draw_count(cell, _drawn_count[slot], TEXT if _drawn_count[slot] > 0 else DIM)


## `count` in the 3 × 5 digits at `cell`'s lower right, on a dark backing (99 at most).
func _draw_count(cell: Rect2, count: int, colour: Color) -> void:
	var shown: int = mini(count, 99)
	var digits: int = 2 if shown >= 10 else 1
	var width: int = digits * 4 - 1
	var corner := Vector2(cell.end.x - width - 1.0, cell.end.y - 6.0)
	draw_rect(Rect2(corner - Vector2(1, 1), Vector2(width + 2, 7)), OUTLINE)
	var at: Vector2 = corner
	for place in digits:
		var digit: int = (shown / 10) if digits == 2 and place == 0 else shown % 10
		for y in 5:
			var row: String = DIGITS[digit * 5 + y]
			for x in row.length():
				if row.unicode_at(x) == 35:
					draw_rect(Rect2(at + Vector2(x, y), Vector2.ONE), colour)
		at.x += 4.0
