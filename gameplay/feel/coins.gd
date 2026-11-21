extends Node2D
## The coins on the floor (connected biomes CB10, decision 18): each one the Rewards area says lies
## somewhere (`coin_changed`) is drawn there, on the floor under the bodies, a small gold disc with
## a shadow and a glint, bobbing a pixel. It comes in by stages (`STAGES`: a speck, a sliver, the
## whole coin, each held `STAGE_FRAMES` frames) and goes the same way back while it lifts a pixel a
## stage, so a coin never pops in or out (docs/STYLE.md, "Smooth"); whole pixels, never a fade.
##
## A child of Feel, in world space. View only, on real time: never state, nothing in the game reads
## it. It allocates only as coins come and go.

const EventsScript := preload("res://core/events/events.gd")
const UnseenMaskScript := preload("res://gameplay/feel/unseen_mask.gd")

## Under the bodies, as the items on the ground.
const Z: int = 0
## The coin's half-widths by stage, coming in (the last its whole look); going, the other way.
const STAGES: PackedInt32Array = [0, 1, 2]
## Frames each stage is held (at 60 frames a second).
const STAGE_FRAMES: float = 3.0
## How high it floats over its shadow, how far it bobs and how fast.
const LIFT: float = 3.0
const BOB: float = 1.0
const BOB_RATE: float = 1.1
const GOLD: Color = Color(0.98, 0.78, 0.28)
const GOLD_DARK: Color = Color(0.71, 0.45, 0.13)
const GLINT: Color = Color(1.0, 0.97, 0.8)
const SHADOW: Color = Color(0.05, 0.04, 0.08, 0.35)

## Where nothing is drawn because nobody has seen it yet (Feel's `UnseenDark.mask`; null: drawn
## everywhere): what lies there is left out, and drawn as it stands from the room's reveal (Feel
## draws this again whenever the mask changes).
var unseen: UnseenMaskScript = null
## By coin number: [where, how far it has come in (0 to `_whole_frames`, in frames), whether it goes].
var _coins: Dictionary = {}
var _clock: float = 0.0
## The coins gone this frame (reused: no allocation a frame).
var _gone: Array[int] = []


func _ready() -> void:
	z_index = Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func bind(events: EventsScript) -> void:
	if events != null:
		events.coin_changed.connect(_on_coin_changed)


## How many coins it draws, going ones too (for tests).
func count() -> int:
	return _coins.size()


## How many coins it draws that still lie there (for tests).
func lying() -> int:
	var found: int = 0
	for coin: int in _coins:
		if not bool((_coins[coin] as Array)[2]):
			found += 1
	return found


func _on_coin_changed(coin: int, at: Vector2, there: bool) -> void:
	if there:
		if _coins.has(coin) and not bool((_coins[coin] as Array)[2]):
			# Said again (a restore): it keeps how far it has come in, never popping in anew.
			(_coins[coin] as Array)[0] = at
		else:
			_coins[coin] = [at, 0.0, false]
	elif _coins.has(coin):
		# Going: back down the stages from where it is now.
		(_coins[coin] as Array)[2] = true
	queue_redraw()


## The frames a coin takes to come in whole (and to go).
func _whole_frames() -> float:
	return STAGE_FRAMES * float(STAGES.size())


func _process(delta: float) -> void:
	if _coins.is_empty():
		return
	_clock += delta
	var frames: float = delta * 60.0
	_gone.clear()
	for coin: int in _coins:
		var row: Array = _coins[coin]
		if bool(row[2]):
			row[1] = float(row[1]) - frames
			if float(row[1]) < 0.0:
				_gone.append(coin)
		else:
			row[1] = minf(float(row[1]) + frames, _whole_frames())
	for coin: int in _gone:
		_coins.erase(coin)
	queue_redraw()


## The stage (`STAGES`' index) a coin `come` frames in is drawn at.
func _stage_of(come: float) -> int:
	return clampi(floori(come / STAGE_FRAMES), 0, STAGES.size() - 1)


func _draw() -> void:
	for coin: int in _coins:
		var row: Array = _coins[coin]
		var at: Vector2 = (row[0] as Vector2).round()
		if unseen != null and unseen.hides(at):
			continue
		var stage: int = _stage_of(float(row[1]))
		var half: int = STAGES[stage]
		# Going, it lifts a pixel a stage as it shrinks.
		var rise: float = float(STAGES.size() - 1 - stage) if bool(row[2]) else 0.0
		var lift: float = LIFT + rise + roundf(sin((_clock * BOB_RATE + float(coin) * 0.41) * PI) * BOB)
		draw_rect(Rect2(at + Vector2(-2.0, 0.0), Vector2(5.0, 1.0)), SHADOW)
		var top: Vector2 = at + Vector2(0.0, -lift)
		# A disc of whole pixels: its rim dark, its face gold, a glint at its upper left; edge on
		# (half 0) a sliver of rim.
		var left: float = -float(half)
		var width: float = float(half * 2 + 1)
		if half == 0:
			draw_rect(Rect2(top + Vector2(0.0, -1.0), Vector2(1.0, 3.0)), GOLD_DARK)
			continue
		draw_rect(Rect2(top + Vector2(left + 1.0, -2.0), Vector2(width - 2.0, 5.0)), GOLD_DARK)
		draw_rect(Rect2(top + Vector2(left, -1.0), Vector2(width, 3.0)), GOLD_DARK)
		draw_rect(Rect2(top + Vector2(left + 1.0, -1.0), Vector2(width - 2.0, 3.0)), GOLD)
		draw_rect(Rect2(top + Vector2(left + 1.0, -1.0), Vector2(1.0, 1.0)), GLINT)
