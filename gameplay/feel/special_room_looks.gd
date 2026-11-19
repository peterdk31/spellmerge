extends Node2D
## The special rooms' things as the view draws them (connected biomes CB11, decisions 19 to 21): a
## shop's items on their shelf, a fountain's pool and a key on the floor. It shows what the bus says
## (`shelf_changed`, `fountain_changed`, `key_shown`) and nothing else; nothing in the game reads it.
##
## - **A shelf item:** a stone plinth with the item over it (a card's icon, else a mark of its kind:
##   a red cross for health) bobbing a pixel, and its price under it in small gold digits.
## - **A fountain:** a stone basin round its pool, the water in it a band of the water's shades whose
##   height follows the healing left, a ripple running along its top while any is left.
## - **A key:** a small brass key lying on the floor, bobbing a pixel.
##
## **Smooth** (docs/STYLE.md): each comes in and goes by STAGES (a sliver, half, whole), STAGE_FRAMES
## frames each, never popping; a pool's water moves a pixel a frame to its new height. Whole pixels,
## never a fade. After a restore (-1 told for keys and fountains, then each said again; a shelf item
## said again) what is said again in the same frame keeps how far it had come in. A child of Feel, top level (world space); view only, on
## real time.

const EventsScript := preload("res://core/events/events.gd")

## Over the floor and its coins, under the bodies' looks.
const Z: int = 0
## The stages things come in by (the share of their height drawn), and frames each is held at 60 fps.
const STAGES: PackedFloat32Array = [0.34, 0.67, 1.0]
const STAGE_FRAMES: float = 3.0
## How far an item and a key bob, and how fast.
const BOB: float = 1.0
const BOB_RATE: float = 1.2
## An item's icon (drawn at most this big), how high over its spot, and its plinth.
const ICON: float = 16.0
const ICON_LIFT: float = 22.0
const PLINTH: Vector2 = Vector2(14.0, 5.0)
## The digits' size (3 by 5 pixels, a pixel apart).
const DIGIT: Vector2i = Vector2i(3, 5)
## Each digit's pixels, row by row (3 bits a row, the top row first).
const DIGITS: PackedInt32Array = [
	0b111101101101111, 0b010110010010111, 0b111001111100111, 0b111001111001111, 0b101101111001001,
	0b111100111001111, 0b111100111101111, 0b111001001010010, 0b111101111101111, 0b111101111001111,
]
## The colours (docs/STYLE.md): stone, the spark's gold, the fire's red, the water's shades, an outline.
const STONE: PackedColorArray = [Color("2b2840"), Color("4a4663"), Color("7a7694")]
const GOLD: PackedColorArray = [Color("b8801f"), Color("f2c230"), Color("fff3a6")]
const RED: Color = Color("e0592f")
const WATER: PackedColorArray = [Color("0f4a44"), Color("1e9c8c"), Color("6fdcc0")]
const OUTLINE: Color = Color("14121f")

## Shelf items by number: [at, choice view, price, frames come in, going].
var _items: Dictionary = {}
## Fountains by room: [area, pixels of water drawn, wanted pixels, frames come in, forgotten].
var _pools: Dictionary = {}
## Keys by number: [at, frames come in, going, forgotten].
var _keys: Dictionary = {}
var _clock: float = 0.0
## Scratch: the things gone this frame (reused, no allocation a frame).
var _gone: Array[int] = []


func _ready() -> void:
	z_index = Z
	top_level = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func bind(events: EventsScript) -> void:
	if events == null:
		return
	events.shelf_changed.connect(_on_shelf_changed)
	events.fountain_changed.connect(_on_fountain_changed)
	events.key_shown.connect(_on_key_shown)


## How many shelf items, pools and keys it draws, going ones too (for tests).
func items() -> int:
	return _items.size()


func pools() -> int:
	return _pools.size()


func keys() -> int:
	return _keys.size()


## The pixels of water drawn in room `room`'s pool (-1: no pool; for tests).
func water_of(room: int) -> int:
	return int((_pools[room] as Array)[1]) if _pools.has(room) else -1


func _on_shelf_changed(item: int, at: Vector2, choice: Dictionary, price: int, lying: bool) -> void:
	if lying:
		if _items.has(item) and not bool((_items[item] as Array)[4]):
			var row: Array = _items[item]
			row[0] = at
			row[1] = choice
			row[2] = price
		else:
			_items[item] = [at, choice, price, 0.0, false]
	elif _items.has(item):
		(_items[item] as Array)[4] = true
	queue_redraw()


func _on_fountain_changed(room: int, area: Rect2, left: float, most: float) -> void:
	if room < 0:
		# Forgotten (the world went, or a restore says each again): those not said again by the
		# next frame go; one said again keeps how far it had come in.
		for kept: int in _pools:
			(_pools[kept] as Array)[4] = true
		queue_redraw()
		return
	var wanted: int = _water_pixels(area, left, most)
	if _pools.has(room):
		var row: Array = _pools[room]
		row[0] = area
		row[2] = wanted
		row[4] = false
	else:
		_pools[room] = [area, wanted, wanted, 0.0, false]
	queue_redraw()


func _on_key_shown(key: int, at: Vector2, lying: bool) -> void:
	if key < 0:
		# Forgotten: each key goes unless said again (a restore), keeping how far it had come in.
		for kept: int in _keys:
			(_keys[kept] as Array)[3] = true
		queue_redraw()
		return
	if lying:
		if _keys.has(key):
			var row: Array = _keys[key]
			row[0] = at
			row[2] = false
			row[3] = false
		else:
			_keys[key] = [at, 0.0, false, false]
	elif _keys.has(key):
		(_keys[key] as Array)[2] = true
	queue_redraw()


## How many pixels of water a pool of `area` holding `left` of `most` shows.
static func _water_pixels(area: Rect2, left: float, most: float) -> int:
	var depth: int = maxi(int(area.size.y) - 4, 0)
	if most <= 0.0 or depth == 0:
		return 0
	return ceili(clampf(left / most, 0.0, 1.0) * float(depth))


func _whole_frames() -> float:
	return STAGE_FRAMES * float(STAGES.size())


func _process(delta: float) -> void:
	if _items.is_empty() and _pools.is_empty() and _keys.is_empty():
		return
	_clock += delta
	var frames: float = delta * 60.0
	# What a -1 forgot and was not said again by now goes (keys back down their stages; pools at once).
	_gone.clear()
	for room: int in _pools:
		if bool((_pools[room] as Array)[4]):
			_gone.append(room)
	for room: int in _gone:
		_pools.erase(room)
	for key: int in _keys:
		if bool((_keys[key] as Array)[3]):
			(_keys[key] as Array)[2] = true
			(_keys[key] as Array)[3] = false
	_step_rows(_items, 3, 4, frames)
	_step_rows(_keys, 1, 2, frames)
	for room: int in _pools:
		var row: Array = _pools[room]
		row[3] = minf(float(row[3]) + frames, _whole_frames())
		var drawn: int = int(row[1])
		var wanted: int = int(row[2])
		if drawn != wanted:
			row[1] = drawn + (1 if wanted > drawn else -1)
	queue_redraw()


## Each row of `rows` comes in (its frames at `come`) or, going (`going`), goes; those gone are erased.
func _step_rows(rows: Dictionary, come: int, going: int, frames: float) -> void:
	_gone.clear()
	for key: int in rows:
		var row: Array = rows[key]
		if bool(row[going]):
			row[come] = float(row[come]) - frames
			if float(row[come]) < 0.0:
				_gone.append(key)
		else:
			row[come] = minf(float(row[come]) + frames, _whole_frames())
	for key: int in _gone:
		rows.erase(key)


## The share of its height a thing `come` frames in is drawn at (a stage of STAGES).
func _share(come: float) -> float:
	return STAGES[clampi(floori(come / STAGE_FRAMES), 0, STAGES.size() - 1)]


func _bob(seed_of: int) -> float:
	return roundf(sin((_clock * BOB_RATE + float(seed_of) * 0.37) * PI) * BOB)


func _draw() -> void:
	for room: int in _pools:
		_draw_pool(_pools[room])
	for item: int in _items:
		_draw_item(item, _items[item])
	for key: int in _keys:
		_draw_key(key, _keys[key])


func _draw_pool(row: Array) -> void:
	var area: Rect2 = (row[0] as Rect2)
	var share: float = _share(float(row[3]))
	var box := Rect2i(Vector2i(area.position.round()), Vector2i(area.size.round()))
	# The basin's rim comes in from the bottom up by stages; the water within it.
	var rim_h: int = maxi(roundi(float(box.size.y + 4) * share), 1)
	var outer := Rect2i(box.position - Vector2i(2, 2), box.size + Vector2i(4, 4))
	var top: int = outer.end.y - rim_h
	draw_rect(Rect2(Vector2(outer.position.x, top), Vector2(outer.size.x, rim_h)), STONE[1])
	draw_rect(Rect2(Vector2(outer.position.x, top), Vector2(outer.size.x, 1)), STONE[2])
	draw_rect(Rect2(Vector2(outer.position.x, outer.end.y - 1), Vector2(outer.size.x, 1)), STONE[0])
	var inner := Rect2i(box.position + Vector2i(1, 1), box.size - Vector2i(2, 2))
	if inner.size.x <= 0 or inner.size.y <= 0:
		return
	var inner_top: int = maxi(inner.position.y, top + 2)
	if inner_top < inner.end.y:
		draw_rect(Rect2(Vector2(inner.position.x, inner_top), Vector2(inner.size.x, inner.end.y - inner_top)), STONE[0])
	var water: int = mini(int(row[1]), inner.size.y)
	if water <= 0 or share < 1.0:
		return
	var surface: int = inner.end.y - water
	draw_rect(Rect2(Vector2(inner.position.x, surface), Vector2(inner.size.x, water)), WATER[1])
	draw_rect(Rect2(Vector2(inner.position.x, inner.end.y - maxi(water / 3, 1)), Vector2(inner.size.x, maxi(water / 3, 1))), WATER[0])
	# A ripple running along the surface.
	var phase: int = int(_clock * 8.0) % 6
	var x: int = inner.position.x + phase
	while x < inner.end.x:
		draw_rect(Rect2(Vector2(x, surface), Vector2(mini(2, inner.end.x - x), 1)), WATER[2])
		x += 6


func _draw_item(item: int, row: Array) -> void:
	var at: Vector2 = (row[0] as Vector2).round()
	var share: float = _share(float(row[3]))
	var choice: Dictionary = row[1]
	# The plinth.
	var plinth_h: float = maxf(roundf(PLINTH.y * share), 1.0)
	draw_rect(Rect2(at + Vector2(-PLINTH.x * 0.5, -plinth_h), Vector2(PLINTH.x, plinth_h)), STONE[1])
	draw_rect(Rect2(at + Vector2(-PLINTH.x * 0.5, -plinth_h), Vector2(PLINTH.x, 1.0)), STONE[2])
	# The item, coming in from a sliver to whole.
	var size: float = maxf(roundf(ICON * share), 1.0)
	var middle: Vector2 = at + Vector2(0.0, -ICON_LIFT + _bob(item))
	var icon: Texture2D = choice.get("icon") as Texture2D
	var rect := Rect2((middle - Vector2(size, size) * 0.5).round(), Vector2(size, size))
	if icon != null:
		draw_texture_rect(icon, rect, false)
	else:
		var kind: StringName = StringName(str(choice.get("kind", "")))
		var colour: Color = RED if kind == ItemKinds.POTION else GOLD[1]
		var arm: float = maxf(roundf(size / 3.0), 1.0)
		draw_rect(Rect2(rect.position + Vector2(arm, 0.0), Vector2(arm, size)), colour)
		draw_rect(Rect2(rect.position + Vector2(0.0, arm), Vector2(size, arm)), colour)
	if share < 1.0:
		return
	_draw_number(int(row[2]), at + Vector2(0.0, 3.0))


## `value` in gold digits centred on `at` (its top), with a dark outline.
func _draw_number(value: int, at: Vector2) -> void:
	var text: String = str(maxi(value, 0))
	var width: int = text.length() * (DIGIT.x + 1) - 1
	var left := Vector2(at.x - float(width / 2), at.y).round()
	draw_rect(Rect2(left - Vector2.ONE, Vector2(width + 2, DIGIT.y + 2)), OUTLINE)
	for i in text.length():
		var bits: int = DIGITS[text.unicode_at(i) - 48]
		for y in DIGIT.y:
			for x in DIGIT.x:
				if bits & (1 << ((DIGIT.y - 1 - y) * DIGIT.x + (DIGIT.x - 1 - x))) != 0:
					draw_rect(Rect2(left + Vector2(i * (DIGIT.x + 1) + x, y), Vector2.ONE), GOLD[1])


func _draw_key(key: int, row: Array) -> void:
	var at: Vector2 = (row[0] as Vector2).round()
	var share: float = _share(float(row[1]))
	var lift: float = 4.0 + _bob(key)
	draw_rect(Rect2(at + Vector2(-3.0, 0.0), Vector2(7.0, 1.0)), Color(0.05, 0.04, 0.08, 0.35))
	var top: Vector2 = at + Vector2(0.0, -lift)
	var length: float = maxf(roundf(8.0 * share), 1.0)
	# Its bow (a ring), its shaft and its bit, in brass with a dark edge.
	draw_rect(Rect2(top + Vector2(-5.0, -2.0), Vector2(4.0, 4.0)), GOLD[0])
	draw_rect(Rect2(top + Vector2(-4.0, -1.0), Vector2(2.0, 2.0)), OUTLINE)
	draw_rect(Rect2(top + Vector2(-1.0, 0.0), Vector2(length, 1.0)), GOLD[1])
	draw_rect(Rect2(top + Vector2(-1.0, -1.0), Vector2(length, 1.0)), GOLD[2])
	if share >= 1.0:
		draw_rect(Rect2(top + Vector2(length - 3.0, 1.0), Vector2(1.0, 2.0)), GOLD[0])
		draw_rect(Rect2(top + Vector2(length - 1.0, 1.0), Vector2(1.0, 2.0)), GOLD[0])
