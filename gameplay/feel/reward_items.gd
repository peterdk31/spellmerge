extends Node2D
## The players' reward items on the floor (the owner's ask of 2026-11-19: a present player's reward
## lies as an item in the cleared room's middle, and that player opens its pick with A at it): each
## one the Rewards area says lies somewhere (`reward_item_changed`) is drawn there, under the bodies,
## as a small chest in its player's colours (their ramp from docs/STYLE.md, so whose it is reads at
## a glance, with the hint's words for its owner) banded in gold, with a shadow, bobbing a pixel, a
## gold glint twinkling over its lid so it reads as something to take.
##
## **Smooth** (docs/STYLE.md): it comes in by STAGES (a sliver, half, whole), STAGE_FRAMES frames
## each, and goes the same way back; the glint runs through its 3 frames and rests. Whole pixels,
## never a fade. After a restore (-1 told, then each lying one said again) one said again keeps how
## far it had come in.
##
## A child of Feel, in world space. View only, on real time: never state, nothing in the game reads
## it. It allocates only as items come and go.

const EventsScript := preload("res://core/events/events.gd")

## Under the bodies, as the items on the ground.
const Z: int = 0
## The share of its height drawn by stage, coming in (the last its whole look), and frames a stage.
const STAGES: PackedFloat32Array = [0.34, 0.67, 1.0]
const STAGE_FRAMES: float = 3.0
## The chest's size, how high it floats over its shadow, how far it bobs and how fast.
const CHEST: Vector2 = Vector2(10.0, 8.0)
const LIFT: float = 4.0
const BOB: float = 1.0
const BOB_RATE: float = 1.2
## The glint's frames (a dot, a small cross, a big cross) and how long each is held, then the rest
## between twinkles (seconds).
const GLINT_FRAME: float = 0.08
const GLINT_REST: float = 1.2
## The players' ramps (docs/STYLE.md: shadow, base, light), the spark's gold, the outline, a shadow.
const PLAYER_RAMPS: Array[PackedColorArray] = [
	[Color("1d3a6b"), Color("3b73c9"), Color("7fc0f0")],
	[Color("7a2347"), Color("d9477a"), Color("f59ab8")],
	[Color("1f4a3a"), Color("3f8f4f"), Color("8fd46a")],
	[Color("4a2a6b"), Color("8a4fc4"), Color("c99af0")],
]
const GOLD: PackedColorArray = [Color("b8801f"), Color("f2c230"), Color("fff3a6")]
const OUTLINE: Color = Color("14121f")
const SHADOW: Color = Color(0.05, 0.04, 0.08, 0.35)

## By offer number: [where, its player, frames come in, going, forgotten].
var _items: Dictionary = {}
var _clock: float = 0.0
## Scratch: the items gone this frame (reused, no allocation a frame).
var _gone: Array[int] = []


func _ready() -> void:
	z_index = Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func bind(events: EventsScript) -> void:
	if events != null:
		events.reward_item_changed.connect(_on_reward_item_changed)


## How many reward items it draws, going ones too (for tests).
func count() -> int:
	return _items.size()


## How many it draws that still lie there (for tests).
func lying() -> int:
	var found: int = 0
	for offer: int in _items:
		if not bool((_items[offer] as Array)[3]):
			found += 1
	return found


## How far item `offer` has come in, in frames (-1: not drawn; for tests).
func frames_of(offer: int) -> float:
	return float((_items[offer] as Array)[2]) if _items.has(offer) else -1.0


func _on_reward_item_changed(player: int, offer: int, at: Vector2, lying: bool) -> void:
	if offer < 0:
		# Forgotten (a restore says each again): those not said again by the next frame go.
		for kept: int in _items:
			(_items[kept] as Array)[4] = true
		return
	if lying:
		if _items.has(offer):
			var row: Array = _items[offer]
			row[0] = at
			row[1] = player
			row[3] = false
			row[4] = false
		else:
			_items[offer] = [at, player, 0.0, false, false]
	elif _items.has(offer):
		(_items[offer] as Array)[3] = true
	queue_redraw()


func _whole_frames() -> float:
	return STAGE_FRAMES * float(STAGES.size())


func _process(delta: float) -> void:
	if _items.is_empty():
		return
	_clock += delta
	var frames: float = delta * 60.0
	_gone.clear()
	for offer: int in _items:
		var row: Array = _items[offer]
		if bool(row[4]):
			row[3] = true
			row[4] = false
		if bool(row[3]):
			row[2] = float(row[2]) - frames
			if float(row[2]) < 0.0:
				_gone.append(offer)
		else:
			row[2] = minf(float(row[2]) + frames, _whole_frames())
	for offer: int in _gone:
		_items.erase(offer)
	queue_redraw()


func _draw() -> void:
	for offer: int in _items:
		_draw_item(offer, _items[offer])


func _draw_item(offer: int, row: Array) -> void:
	var at: Vector2 = (row[0] as Vector2).round()
	var ramp: PackedColorArray = PLAYER_RAMPS[clampi(int(row[1]), 0, PLAYER_RAMPS.size() - 1)]
	var share: float = STAGES[clampi(floori(float(row[2]) / STAGE_FRAMES), 0, STAGES.size() - 1)]
	var bob: float = roundf(sin((_clock * BOB_RATE + float(offer) * 0.37) * PI) * BOB)
	draw_rect(Rect2(at + Vector2(-5.0, 0.0), Vector2(11.0, 2.0)), SHADOW)
	# The chest, coming in from its bottom up by stages.
	var height: float = maxf(roundf(CHEST.y * share), 1.0)
	var bottom: Vector2 = at + Vector2(-CHEST.x * 0.5, -LIFT + bob)
	var box := Rect2(bottom - Vector2(0.0, height), Vector2(CHEST.x, height))
	draw_rect(box.grow(1.0), OUTLINE)
	draw_rect(box, ramp[1])
	draw_rect(Rect2(box.position, Vector2(box.size.x, 1.0)), ramp[2])
	draw_rect(Rect2(box.position + Vector2(0.0, box.size.y - 1.0), Vector2(box.size.x, 1.0)), ramp[0])
	if share < 1.0:
		return
	# Its lid's line, the gold band down its middle and its clasp.
	draw_rect(Rect2(box.position + Vector2(0.0, 3.0), Vector2(box.size.x, 1.0)), OUTLINE)
	draw_rect(Rect2(box.position + Vector2(4.0, 0.0), Vector2(2.0, box.size.y)), GOLD[1])
	draw_rect(Rect2(box.position + Vector2(4.0, 3.0), Vector2(2.0, 2.0)), GOLD[2])
	# The glint over the lid: a dot, a small cross, a big cross, then a rest.
	var period: float = GLINT_FRAME * 3.0 + GLINT_REST
	var phase: float = fmod(_clock + float(offer) * 0.41, period)
	if phase < GLINT_FRAME * 3.0:
		var frame: int = floori(phase / GLINT_FRAME)
		var spot: Vector2 = box.position + Vector2(8.0, -2.0)
		draw_rect(Rect2(spot, Vector2.ONE), GOLD[2])
		for arm in frame:
			var reach: float = float(arm + 1)
			draw_rect(Rect2(spot + Vector2(-reach, 0.0), Vector2.ONE), GOLD[1])
			draw_rect(Rect2(spot + Vector2(reach, 0.0), Vector2.ONE), GOLD[1])
			draw_rect(Rect2(spot + Vector2(0.0, -reach), Vector2.ONE), GOLD[1])
			draw_rect(Rect2(spot + Vector2(0.0, reach), Vector2.ONE), GOLD[1])
