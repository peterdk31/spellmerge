extends VBoxContainer
## The boss bar (boss plan OB16, docs/milestones/boss-old-broom.md, "HUD: the boss bar and the
## entrance"): one bar at the top middle for everyone while a boss is in play: its name, its health
## and a mark at each phase's health share. It shows what the bus says and nothing else:
## `boss_shown` (a boss entered play), `boss_health_changed` and `boss_hidden` (it died or left);
## in play each boss's own `boss_hidden` takes it away as its body leaves, and the panels clear it
## with the rest (`clear`: a run starting or ending, the main menu). With more than one boss in play
## it shows the first shown that is still in play. Display only: it takes no input.
##
## Marks are drawn on the bar as notches (a shape, so a phase is never shown by colour alone); a
## mark the health has fallen past is drawn dim.

const EventsScript := preload("res://core/events/events.gd")

const FONT_SIZE: int = 8
const OUTLINE: int = 3
## The bar's size in view pixels: it fits between the top corner panels at 640x360.
const BAR_SIZE: Vector2 = Vector2(200.0, 6.0)
## How far a mark's notch stands out above and below the bar, and its colours (ahead, passed).
const MARK_OUT: float = 2.0
const MARK_COLOR: Color = Color(0.96, 0.92, 0.85, 1.0)
const MARK_PASSED: Color = Color(0.96, 0.92, 0.85, 0.35)

## The bosses in play, in the order they were shown (actor ids), and what was told of each:
## id -> [name, marks, health, max_health].
var _order: PackedInt32Array = PackedInt32Array()
var _told: Dictionary = {}
var _name: Label = null
var _bar: ProgressBar = null
var _marks: Control = null
## The marks of the boss shown, for drawing.
var _shown_marks: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 1)
	_name = Label.new()
	_name.name = "Name"
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_name.add_theme_constant_override(&"outline_size", OUTLINE)
	_name.add_theme_color_override(&"font_outline_color", Color.BLACK)
	add_child(_name)
	_bar = ProgressBar.new()
	_bar.name = "Health"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.theme_type_variation = &"HealthBar"
	_bar.show_percentage = false
	_bar.custom_minimum_size = BAR_SIZE
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	add_child(_bar)
	_marks = Control.new()
	_marks.name = "Marks"
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.draw.connect(_draw_marks)
	_bar.add_child(_marks)
	visible = false


func bind(events: EventsScript) -> void:
	if events != null:
		events.boss_shown.connect(show_boss)
		events.boss_health_changed.connect(set_health)
		events.boss_hidden.connect(hide_boss)


## The boss `actor` entered play (`boss_shown`).
func show_boss(actor: int, boss_name: String, _lore: String, marks: PackedFloat32Array, _has_intro: bool = false) -> void:
	if not _order.has(actor):
		_order.append(actor)
	var health: float = 1.0
	var most: float = 1.0
	if _told.has(actor):
		health = (_told[actor] as Array)[2] as float
		most = (_told[actor] as Array)[3] as float
	_told[actor] = [boss_name, marks.duplicate(), health, most]
	_refresh()


## The boss `actor` has `health` of `max_health` (`boss_health_changed`); a boss not shown is ignored.
func set_health(actor: int, health: float, max_health: float) -> void:
	if not _told.has(actor):
		return
	var row: Array = _told[actor] as Array
	row[2] = health
	row[3] = max_health
	_refresh()


## The boss `actor` is out of play (`boss_hidden`).
func hide_boss(actor: int) -> void:
	var at: int = _order.find(actor)
	if at >= 0:
		_order.remove_at(at)
	_told.erase(actor)
	_refresh()


## No boss (a run starts or ends).
func clear() -> void:
	_order.clear()
	_told.clear()
	_refresh()


## The actor id of the boss shown, or -1 for none.
func shown_boss() -> int:
	return _order[0] if not _order.is_empty() else -1


## The share of its most health the boss shown has (0 to 1; 0 for none).
func shown_share() -> float:
	return _bar.value if visible else 0.0


## The name shown.
func shown_name() -> String:
	return _name.text


## The marks of the boss shown.
func shown_marks() -> PackedFloat32Array:
	return _shown_marks


## True when the boss shown has `mark` (a share) behind it: its notch is drawn dim.
func is_passed(mark: float) -> bool:
	return visible and _bar.value <= mark


func _refresh() -> void:
	var actor: int = shown_boss()
	visible = actor >= 0
	if not visible:
		_name.text = ""
		_shown_marks = PackedFloat32Array()
		_marks.queue_redraw()
		return
	var row: Array = _told[actor] as Array
	_name.text = row[0] as String
	var most: float = row[3] as float
	_bar.value = clampf((row[2] as float) / most, 0.0, 1.0) if most > 0.0 else 0.0
	_shown_marks = row[1] as PackedFloat32Array
	_marks.queue_redraw()


func _draw_marks() -> void:
	var size: Vector2 = _marks.size
	for mark in _shown_marks:
		var x: float = roundf(size.x * mark)
		var color: Color = MARK_PASSED if is_passed(mark) else MARK_COLOR
		_marks.draw_rect(Rect2(x, -MARK_OUT, 1.0, size.y + MARK_OUT * 2.0), color)
