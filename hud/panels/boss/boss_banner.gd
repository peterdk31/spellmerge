extends VBoxContainer
## The entrance banner (boss plan OB16, docs/milestones/boss-old-broom.md, "HUD: the boss bar and
## the entrance"): as a boss enters play (`boss_shown`) its name and its lore line show over play in
## the upper middle of the view for a few seconds, fading in and out. It stops nothing and takes no
## input; nobody waits for it, and it waits while the game is paused (the panels do not step it).
## A second boss shown meanwhile takes its place; the panels clear it with the rest (`clear`). Its sound is the `boss_intro` cue, Feel's.
##
## A boss with an intro (`boss_shown`'s `has_intro`, docs/milestones/boss-intro.md, rule 5) has the
## overlay for its entrance, not the banner: it is kept back until it is released (`release`, the
## panels' `BossIntroWait`), and shows then only when no intro played (the run's rule off, a boss a
## phase called).
##
##     banner.show_boss(actor, "The Old Broom", "Its lore line.", marks)
##     banner.step(delta)    # called every frame by the HUD

const EventsScript := preload("res://core/events/events.gd")

const NAME_SIZE: int = 16
const LORE_SIZE: int = 8
const OUTLINE: int = 4
## Seconds it fades in, holds and fades out.
const FADE_IN: float = 0.3
const HOLD: float = 3.0
const FADE_OUT: float = 0.6
## How far down the view its top stands, as a share of the view's height.
const DROP: float = 0.22

var _name: Label = null
var _lore: Label = null
## Seconds since it began showing; negative while it shows nothing.
var _time: float = -1.0
## The bosses with an intro kept back, by actor id: [name, lore].
var _kept: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 2)
	_name = _line("Name", NAME_SIZE)
	_lore = _line("Lore", LORE_SIZE)
	visible = false


func _ready() -> void:
	# The view's width, its top DROP down the view, growing down as its lines need.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = DROP
	anchor_bottom = DROP
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	grow_vertical = Control.GROW_DIRECTION_END


func bind(events: EventsScript) -> void:
	if events != null:
		events.boss_shown.connect(show_boss)
		events.boss_hidden.connect(forget)


## Show the banner of the boss that entered play (`boss_shown`); one with an intro is kept back.
func show_boss(actor: int, boss_name: String, lore: String, _marks: PackedFloat32Array, has_intro: bool = false) -> void:
	if has_intro:
		_kept[actor] = [boss_name, lore]
		return
	_show(boss_name, lore)


## The boss `actor` kept back is released: its banner shows only when no intro `played`.
func release(actor: int, played: bool) -> void:
	var row: Array = _kept.get(actor, []) as Array
	_kept.erase(actor)
	if not played and row.size() == 2:
		_show(row[0] as String, row[1] as String)


## The boss `actor` left play (`boss_hidden`): nothing kept back of it shows.
func forget(actor: int) -> void:
	_kept.erase(actor)


func _show(boss_name: String, lore: String) -> void:
	_name.text = boss_name
	_lore.text = lore
	_lore.visible = lore != ""
	_time = 0.0
	modulate.a = 0.0
	visible = true


## Move it on by `delta` seconds (the HUD's frame): in, held, out, then hidden.
func step(delta: float) -> void:
	if _time < 0.0:
		return
	_time += delta
	modulate.a = alpha_at(_time)
	if _time >= FADE_IN + HOLD + FADE_OUT:
		_hide()


## Hide it at once (a run starts or ends).
func clear() -> void:
	_kept.clear()
	_hide()


func _hide() -> void:
	_time = -1.0
	modulate.a = 0.0
	visible = false


## True while it shows.
func is_showing() -> bool:
	return _time >= 0.0


## The name and the lore line it shows.
func shown_name() -> String:
	return _name.text


func shown_lore() -> String:
	return _lore.text


## How opaque it is `time` seconds after it began.
static func alpha_at(time: float) -> float:
	if time < 0.0:
		return 0.0
	if time < FADE_IN:
		return time / FADE_IN
	if time < FADE_IN + HOLD:
		return 1.0
	return clampf(1.0 - (time - FADE_IN - HOLD) / FADE_OUT, 0.0, 1.0)


func _line(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_constant_override(&"outline_size", OUTLINE)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	add_child(label)
	return label
