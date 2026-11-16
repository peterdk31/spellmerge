extends Control
## The boss intro's overlay (docs/milestones/boss-intro.md, "What the players see", rule 5): the
## screen-wide close-up of a boss before its fight. It draws what the bus says and sends A, and knows
## nothing of Flow or the hold:
##
## - `boss_intro_opened` (`open`): fresh plays the timeline from the start; not fresh (a snapshot
##   restored it open) shows that page already revealed. An open of the boss and page it shows
##   changes nothing.
## - `boss_intro_paged` (`turn`): the next line types out.
## - `boss_intro_closed` (`close`): the bars slide out, the portrait leaves the way it came and the
##   name's letters fall away over CLOSE_TIME, then it hides.
##
## The timeline is the HUD's frame (`step`, real time; it plays while the tree is paused for the
## intro), its moments `BossIntro`'s (LEAD, SLASH_AT, DARK_AT, REVEAL_AT, LETTER_GAP, LINES_AT,
## TYPE_RATE, FLASH_FRAMES, SHAKE, SHAKE_TIME), so Feel's sounds land on the same moments: the bars
## slide in and the world dims, the accent's slash streaks in from the right with the portrait on it
## (black, rimmed in the accent), its eyes light, then the reveal (a white flash for FLASH_FRAMES
## frames, the mean pose in colour, the overlay shaking SHAKE px and settling within SHAKE_TIME, the
## name slamming in letter by letter from 4× to 2× in the title type, a glint across it, the lore line
## typing out), and from LINES_AT the boss's line typing out in the dialog box (or, with none, the A
## glyph and "Fight" under the name).
##
## **A** (`press`, called by the panels for a seat's `accept` while it is open): before LINES_AT it
## does nothing; on a line still typing it writes the line out, on this machine only; on a line
## written out it sends `boss_intro_next_requested(seat, page)` with the page shown, for a seat played
## on this machine only (`Frames.seats_here`). Never while this machine's pause menu is open
## (`menu_open`, asked of the panels: the tree is paused for the whole intro, so `get_tree().paused`
## says nothing).
##
## The portrait is drawn at 2× only, through the silhouette shader (`silhouette.gdshader`, warmed as
## the overlay is made); its eyes frame glows over it in the dark. The layout keeps its place on the
## view's own width (a narrow view later). Nothing names a boss (rule 9): all of it is `BossIntro`'s.
##
##     intro.bind(events)
##     intro.step(delta)      # every frame, by the panels
##     intro.press(seat)      # a seat's A, by the panels

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const SHADER: Shader = preload("res://hud/panels/boss/silhouette.gdshader")

## The black bars' height, top and bottom, and how dark the world under them goes (0.6: to 40%).
const BAR: float = 36.0
const DIM: float = 0.6
## The portrait's whole-number scale, and its right edge's distance from the view's.
const SCALE: int = 2
const PORTRAIT_RIGHT: float = 24.0
## The name's left edge, and its top as a share of the view's height.
const NAME_LEFT: float = 48.0
const NAME_DROP: float = 1.0 / 3.0
## The name's sizes as a letter slams in (4×, 3×, its 2×; the title type is 16 px a cell), and the
## seconds each holds.
const NAME_SIZES: PackedInt32Array = [64, 48, 32]
const NAME_STEP: float = 0.03
## The glint's seconds across the name, and its reach in letters either side.
const GLINT_TIME: float = 0.4
const GLINT_REACH: float = 1.5
## The small type's size (the lore line) and the dialog's.
const SMALL_SIZE: int = 8
const LINE_SIZE: int = 12
## The gap under the name and under the lore line.
const GAP: float = 6.0
## The dialog box: its size, its left edge, and how far it reaches over the bottom bar's top edge.
const BOX_SIZE: Vector2 = Vector2(352.0, 56.0)
const BOX_LEFT: float = 32.0
const BOX_OVER: float = 16.0
const BOX_PAD: float = 8.0
## The slash: its height, its middle as a share of the view's height (across the middle, under the
## name and the lore line), its slant, and how strong it stays after the reveal.
const SLASH_HEIGHT: float = 28.0
const SLASH_DROP: float = 0.56
const SLASH_SLANT: float = 16.0
const SLASH_ALPHA: float = 0.85
const SLASH_AFTER: float = 0.55
## Seconds the eyes take to light, and the A glyph's blink.
const EYES_IN: float = 0.15
const BLINK: float = 0.6
## Seconds the overlay takes to leave, and how far the letters fall meanwhile.
const CLOSE_TIME: float = 0.4
const FALL: float = 72.0
## The shake's ways, one each SHAKE_FRAME seconds (a fixed pattern: two runs look the same).
const SHAKE_FRAME: float = 1.0 / 30.0
const SHAKE_WAYS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 1), Vector2(0, -1), Vector2(-1, -1), Vector2(1, 1), Vector2(0, 1)]
## The white over the whole view during the flash (the portrait itself goes white).
const FLASH_VIEW: float = 0.35
## A not-fresh open's clock: far past every moment of the timeline.
const SETTLED: float = 60.0
## The word under the name with no lines.
const FIGHT: String = "Fight"
## What A does (the input action `accept`, A, Enter, Space).
const ACCEPT: StringName = &"accept"

## The frames service whose `seats_here` says which seats this machine plays (null: the "Frames"
## autoload; tests give their own), and what says this machine's pause menu is open (the panels').
var frames: Node = null
var menu_open: Callable = Callable()

var _events: EventsScript = null
## The intro shown: its boss, name and lore, its data and the page shown.
var _actor: int = ActorsScript.NONE
var _boss_name: String = ""
var _lore: String = ""
var _intro: BossIntro = null
var _page: int = 0
## Seconds since it opened (the timeline's clock); seconds since it began closing (-1: not closing).
var _time: float = -1.0
var _closing: float = -1.0
## When the line shown began typing, and whether it was written out at once by a press here.
var _line_from: float = 0.0
var _line_done: bool = false
## Frames of the reveal's flash left to show.
var _flash_left: int = 0
## The accent's shades (shadow, base, light).
var _accent: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])

var _stage: Control = null
var _portrait: Control = null
var _eyes: Control = null
var _name_view: Control = null
var _lore_label: Label = null
var _line: Label = null
var _glyph: ActionGlyphScript = null
var _fight: HBoxContainer = null
var _fight_glyph: ActionGlyphScript = null
var _material: ShaderMaterial = null
var _slash_points: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _font: Font = null
## The name's letters, one string each (made once an open, never while drawing).
var _letters: PackedStringArray = PackedStringArray()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_stage = _control("Stage")
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.draw.connect(_draw_stage)
	add_child(_stage)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_portrait = _control("Portrait")
	_portrait.material = _material
	_portrait.draw.connect(_draw_portrait)
	_stage.add_child(_portrait)
	_eyes = _control("Eyes")
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_eyes.material = glow
	_eyes.draw.connect(_draw_eyes)
	_stage.add_child(_eyes)
	_name_view = _control("Name")
	_name_view.draw.connect(_draw_name)
	_stage.add_child(_name_view)
	_lore_label = _label("Lore", SMALL_SIZE)
	_stage.add_child(_lore_label)
	_line = _label("Line", LINE_SIZE)
	_stage.add_child(_line)
	_glyph = ActionGlyphScript.new()
	_glyph.name = "Glyph"
	_stage.add_child(_glyph)
	_fight = HBoxContainer.new()
	_fight.name = "Fight"
	_fight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fight.add_theme_constant_override(&"separation", 4)
	_fight_glyph = ActionGlyphScript.new()
	_fight_glyph.name = "Glyph"
	_fight.add_child(_fight_glyph)
	var word: Label = _label("Word", LINE_SIZE)
	word.text = FIGHT
	word.autowrap_mode = TextServer.AUTOWRAP_OFF
	_fight.add_child(word)
	_stage.add_child(_fight)


func _ready() -> void:
	# Compiled behind the first loading screen, never at the first boss (rule 6).
	ShaderWarmupScript.want(SHADER, ShaderWarmupScript.RECT)
	if frames == null:
		frames = get_node_or_null("/root/Frames")
	_font = get_theme_font(&"font", &"TitleLabel")


func bind(events: EventsScript) -> void:
	_events = events
	if events != null:
		events.boss_intro_opened.connect(open)
		events.boss_intro_paged.connect(turn)
		events.boss_intro_closed.connect(close)


## The boss `actor`'s intro is open on `page` (`boss_intro_opened`): fresh from the start, else that
## page revealed. The boss and page shown already: nothing changes.
func open(actor: int, boss_name: String, lore: String, intro: BossIntro, page: int, fresh: bool) -> void:
	if intro == null:
		return
	if is_open() and actor == _actor and page == _page and intro == _intro:
		return
	_actor = actor
	_boss_name = boss_name
	_letters.clear()
	for i in boss_name.length():
		_letters.append(boss_name.substr(i, 1))
	_lore = lore
	_intro = intro
	_page = page
	_closing = -1.0
	_flash_left = 0
	var shades: PackedColorArray = Palette.shades_of(intro.accent)
	_accent = shades if shades.size() == 3 else PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	_material.set_shader_parameter(&"rim_color", _accent[2])
	_material.set_shader_parameter(&"dark", Palette.OUTLINE)
	if fresh:
		_time = 0.0
		_line_from = BossIntro.LINES_AT
		_line_done = false
	else:
		_time = SETTLED
		_line_from = 0.0
		_line_done = true
	_lore_label.text = lore
	_line.text = _line_text()
	var seat: int = _first_seat_here()
	_glyph.show_action(seat, ACCEPT)
	_fight_glyph.show_action(seat, ACCEPT)
	visible = true
	_apply()


## The intro turned to `page` (`boss_intro_paged`): its line types out from now.
func turn(page: int) -> void:
	if not is_open() or page == _page:
		return
	_page = page
	_line_from = maxf(_time, BossIntro.LINES_AT)
	_line_done = false
	_line.text = _line_text()
	_apply()


## The intro of `actor` closed (`boss_intro_closed`; ActorsScript.NONE: whichever is shown): it leaves.
func close(actor: int) -> void:
	if not is_open():
		return
	if actor != ActorsScript.NONE and actor != _actor:
		return
	_closing = 0.0
	_flash_left = 0
	_apply()


## Hide it at once (a run starts or ends, the main menu).
func clear() -> void:
	_time = -1.0
	_closing = -1.0
	_flash_left = 0
	_intro = null
	_actor = ActorsScript.NONE
	visible = false


## Move it on by `delta` seconds of the HUD's frame (called every frame by the panels, the tree
## paused or not).
func step(delta: float) -> void:
	if _time < 0.0:
		return
	if _flash_left > 0:
		_flash_left -= 1
	if _closing >= 0.0:
		_closing += delta
		if _closing >= CLOSE_TIME:
			clear()
			return
	else:
		var before: float = _time
		_time += delta
		if before < BossIntro.REVEAL_AT and _time >= BossIntro.REVEAL_AT:
			_flash_left = BossIntro.FLASH_FRAMES
	_apply()


## Seat `seat` pressed A (the panels, while it is open). True when it sent the next page's command.
func press(seat: int) -> bool:
	if not is_open() or _events == null:
		return false
	if menu_open.is_valid() and bool(menu_open.call()):
		return false
	if seat < 0 or _seats_here() & (1 << seat) == 0:
		return false
	if _time < BossIntro.LINES_AT:
		# The reveal is not over: nobody skips the silhouette by accident.
		return false
	if not is_line_written():
		# Written out at once, on this machine only.
		_line_done = true
		_apply()
		return false
	_events.boss_intro_next_requested.emit(seat, _page)
	return true


## True while an intro shows and is not leaving (A is its, the builder and the inventory stay shut).
func is_open() -> bool:
	return _time >= 0.0 and _closing < 0.0


## True while anything of it shows (leaving included).
func is_showing() -> bool:
	return _time >= 0.0


## The boss shown (ActorsScript.NONE: none), its page and the timeline's clock (for tests).
func shown_boss() -> int:
	return _actor


func shown_page() -> int:
	return _page


func shown_name() -> String:
	return _boss_name


func time() -> float:
	return _time


## The line of the page shown ("" with no lines), and how much of it shows now.
func shown_line() -> String:
	return _line.text


func typed_line() -> String:
	return _line.text.left(_typed())


## True once the page's line is written out (typed to its end, or a press here).
func is_line_written() -> bool:
	if not _has_lines():
		return true
	return _line_done or _typed() >= _line.text.length()


## How far the bars are in (0 to 1), how bright the eyes glow (0 to 1), whether the portrait shows
## its colours, whether the flash shows and the shake's offset now (for tests).
func bars_in() -> float:
	if _closing >= 0.0:
		return 1.0 - _closing_share()
	return clampf((_time - BossIntro.LEAD) / (BossIntro.SLASH_AT - BossIntro.LEAD), 0.0, 1.0)


func eyes_glow() -> float:
	if _time >= BossIntro.REVEAL_AT:
		return 0.0
	return clampf((_time - BossIntro.DARK_AT) / EYES_IN, 0.0, 1.0)


func is_revealed() -> bool:
	return _time >= BossIntro.REVEAL_AT


func is_flashing() -> bool:
	return _flash_left > 0


func shake_offset() -> Vector2:
	var since: float = _time - BossIntro.REVEAL_AT
	if _closing >= 0.0 or since < 0.0 or since >= BossIntro.SHAKE_TIME:
		return Vector2.ZERO
	var reach: float = BossIntro.SHAKE * (1.0 - since / BossIntro.SHAKE_TIME)
	return (SHAKE_WAYS[int(since / SHAKE_FRAME) % SHAKE_WAYS.size()] * reach).round()


## How many of the name's letters show, and the size the letter `at` is drawn at now (0: not yet).
func letters_shown() -> int:
	var count: int = 0
	for i in _boss_name.length():
		if letter_size(i) > 0:
			count += 1
	return count


func letter_size(at: int) -> int:
	var age: float = _time - (BossIntro.REVEAL_AT + at * BossIntro.LETTER_GAP)
	if age < 0.0:
		return 0
	return NAME_SIZES[mini(int(age / NAME_STEP), NAME_SIZES.size() - 1)]


## The moment the name is all in at its 2× (the glint and the lore line follow it).
func name_done_at() -> float:
	return BossIntro.REVEAL_AT + maxi(_boss_name.length() - 1, 0) * BossIntro.LETTER_GAP + NAME_SIZES.size() * NAME_STEP


## The lore line as it shows now (typing out after the name).
func typed_lore() -> String:
	return _lore.left(_typed_lore())


## Whether the A glyph shows (blinking: true on its lit half) and whether "Fight" shows.
func is_glyph_lit() -> bool:
	return _glyph.visible or _fight_glyph.visible


func is_fight_shown() -> bool:
	return _fight.visible


func _apply() -> void:
	if _time < 0.0:
		return
	var view: Vector2 = size
	var close_share: float = _closing_share()
	var shake: Vector2 = shake_offset()
	_stage.position = shake
	# The portrait: in on the slash from the right, out the same way.
	var side: float = BossIntro.FRAME * SCALE
	var come: float = clampf((_time - BossIntro.SLASH_AT) / (BossIntro.DARK_AT - BossIntro.SLASH_AT), 0.0, 1.0)
	var away: float = (1.0 - _ease_out(come)) + _ease_in(close_share)
	var at := Vector2(view.x - PORTRAIT_RIGHT - side + roundf(away * (side + PORTRAIT_RIGHT)), view.y - BAR - side)
	_portrait.position = at
	_portrait.size = Vector2(side, side)
	_eyes.position = at
	_eyes.size = _portrait.size
	var revealed: bool = is_revealed()
	_material.set_shader_parameter(&"reveal", 1.0 if revealed else 0.0)
	_material.set_shader_parameter(&"rim", 0.0 if revealed else 1.0)
	_material.set_shader_parameter(&"flash", 1.0 if is_flashing() else 0.0)
	_portrait.visible = come > 0.0
	_eyes.visible = eyes_glow() > 0.0
	_eyes.modulate.a = eyes_glow()
	# The name, the lore under it and the dialog under that.
	var name_at := Vector2(NAME_LEFT, roundf(view.y * NAME_DROP))
	_name_view.position = name_at
	_name_view.size = Vector2(maxf(at.x - NAME_LEFT, 0.0), _name_height())
	var fade: float = 1.0 - close_share
	_lore_label.position = Vector2(NAME_LEFT, name_at.y + _name_height() + GAP)
	_lore_label.size = Vector2(maxf(view.x - PORTRAIT_RIGHT - side - NAME_LEFT - GAP, 0.0), 0.0)
	_lore_label.visible_characters = _typed_lore()
	_lore_label.visible = _lore != "" and _time >= name_done_at()
	_lore_label.modulate.a = fade
	var lines_shown: bool = _time >= BossIntro.LINES_AT
	var box := Rect2(Vector2(BOX_LEFT, view.y - BAR - BOX_SIZE.y + BOX_OVER), BOX_SIZE)
	_line.position = box.position + Vector2(BOX_PAD, BOX_PAD - 2.0)
	_line.size = Vector2(BOX_SIZE.x - BOX_PAD * 2.0, 0.0)
	_line.visible = lines_shown and _has_lines()
	_line.visible_characters = -1 if _line_done else _typed()
	_line.modulate.a = fade
	var lit: bool = fmod(_time, BLINK) < BLINK * 0.5 and _closing < 0.0
	_glyph.visible = _line.visible and is_line_written() and lit
	_glyph.position = (box.end - _glyph.get_combined_minimum_size() - Vector2(BOX_PAD, BOX_PAD * 0.5)).round()
	_fight.visible = lines_shown and not _has_lines()
	_fight_glyph.visible = lit or _closing >= 0.0
	_fight.position = Vector2(NAME_LEFT, _lore_label.position.y + (SMALL_SIZE + GAP if _lore != "" else 0.0) + GAP)
	_fight.modulate.a = fade
	_portrait.queue_redraw()
	_eyes.queue_redraw()
	_name_view.queue_redraw()
	_stage.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if _time < 0.0:
		return
	# The world under it dims as the bars come in, and back as they go; and the flash's white.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, DIM * bars_in()))
	if is_flashing():
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, FLASH_VIEW))


func _draw_stage() -> void:
	if _time < 0.0:
		return
	var view: Vector2 = size
	var margin: float = BossIntro.SHAKE
	var bars: float = bars_in()
	var tall: float = BAR + margin
	_stage.draw_rect(Rect2(-margin, -margin - (1.0 - bars) * tall, view.x + margin * 2.0, tall), Palette.OUTLINE)
	_stage.draw_rect(Rect2(-margin, view.y - BAR + (1.0 - bars) * tall, view.x + margin * 2.0, tall), Palette.OUTLINE)
	# The slash across the middle, streaking in from the right.
	var slash: float = clampf((_time - BossIntro.SLASH_AT) / (BossIntro.DARK_AT - BossIntro.SLASH_AT), 0.0, 1.0)
	if slash > 0.0:
		var top: float = roundf(view.y * SLASH_DROP - SLASH_HEIGHT * 0.5)
		var left: float = roundf(view.x + SLASH_SLANT - _ease_out(slash) * (view.x + SLASH_SLANT * 2.0))
		var colour: Color = _accent[1]
		colour.a = (SLASH_AFTER if is_revealed() else SLASH_ALPHA) * (1.0 - _closing_share())
		_slash_points[0] = Vector2(left, top)
		_slash_points[1] = Vector2(view.x + margin + SLASH_SLANT, top)
		_slash_points[2] = Vector2(view.x + margin, top + SLASH_HEIGHT)
		_slash_points[3] = Vector2(left - SLASH_SLANT, top + SLASH_HEIGHT)
		_stage.draw_colored_polygon(_slash_points, colour)
	# The dialog box, over the bottom bar's top edge.
	if _line.visible:
		var box := Rect2(Vector2(BOX_LEFT, view.y - BAR - BOX_SIZE.y + BOX_OVER), BOX_SIZE)
		var fade: float = 1.0 - _closing_share()
		_stage.draw_rect(box, Color(Palette.OUTLINE, 0.92 * fade))
		var edge: Color = _accent[2]
		edge.a = fade
		_stage.draw_rect(box, edge, false, 1.0)


## The portrait: its rest frame (the silhouette's shape) until the reveal, then its mean pose.
func _draw_portrait() -> void:
	_draw_frame(_portrait, BossIntro.MEAN if is_revealed() else BossIntro.REST)


func _draw_eyes() -> void:
	_draw_frame(_eyes, BossIntro.EYES)


func _draw_frame(node: Control, frame: int) -> void:
	if _intro == null or _intro.portrait == null:
		return
	var side: float = BossIntro.FRAME
	node.draw_texture_rect_region(_intro.portrait, Rect2(Vector2.ZERO, Vector2(side, side) * SCALE), Rect2(frame * side, 0.0, side, side))


func _draw_name() -> void:
	if _font == null or _boss_name == "":
		return
	var final_size: int = NAME_SIZES[NAME_SIZES.size() - 1]
	var height: float = _font.get_height(final_size)
	var glint: float = -INF
	var since: float = _time - name_done_at()
	if since >= 0.0 and since < GLINT_TIME:
		glint = since / GLINT_TIME * (_boss_name.length() + GLINT_REACH * 2.0) - GLINT_REACH
	var fall: float = _ease_in(_closing_share())
	var x: float = 0.0
	for i in _letters.size():
		var code: int = _boss_name.unicode_at(i)
		var advance: float = _font.get_char_size(code, final_size).x
		var font_size: int = letter_size(i)
		if font_size > 0:
			var cell := Vector2(_font.get_char_size(code, font_size).x, _font.get_height(font_size))
			var middle := Vector2(x + advance * 0.5, height * 0.5)
			var top: Vector2 = (middle - cell * 0.5).round()
			top.y += roundf(fall * FALL * (1.0 + 0.25 * float(i % 3)))
			var baseline: Vector2 = top + Vector2(0.0, _font.get_ascent(font_size))
			var alpha: float = 1.0 - _closing_share()
			var shadow: Color = _accent[0]
			shadow.a = alpha
			_name_view.draw_char(_font, baseline + Vector2(SCALE, SCALE), _letters[i], font_size, shadow)
			var near: float = clampf(1.0 - absf(float(i) - glint) / GLINT_REACH, 0.0, 1.0)
			var colour: Color = Color.WHITE.lerp(_accent[2], near)
			colour.a = alpha
			_name_view.draw_char(_font, baseline, _letters[i], font_size, colour)
		x += advance


func _name_height() -> float:
	return _font.get_height(NAME_SIZES[NAME_SIZES.size() - 1]) if _font != null else 32.0


func _line_text() -> String:
	if _intro == null or _page < 0 or _page >= _intro.lines.size():
		return ""
	return _intro.lines[_page]


func _has_lines() -> bool:
	return _intro != null and not _intro.lines.is_empty()


func _typed() -> int:
	if _line_done:
		return _line.text.length()
	return clampi(int((_time - _line_from) * BossIntro.TYPE_RATE), 0, _line.text.length())


func _typed_lore() -> int:
	return clampi(int((_time - name_done_at()) * BossIntro.TYPE_RATE), 0, _lore.length())


func _closing_share() -> float:
	return clampf(_closing / CLOSE_TIME, 0.0, 1.0) if _closing >= 0.0 else 0.0


func _seats_here() -> int:
	return int(frames.call(&"seats_here")) if frames != null and frames.has_method(&"seats_here") else 0


## The lowest seat this machine plays, whose A glyph shows (0 with none).
func _first_seat_here() -> int:
	var mask: int = _seats_here()
	for seat in 4:
		if mask & (1 << seat) != 0:
			return seat
	return 0


static func _ease_out(share: float) -> float:
	return 1.0 - (1.0 - share) * (1.0 - share)


static func _ease_in(share: float) -> float:
	return share * share


static func _control(node_name: String) -> Control:
	var node := Control.new()
	node.name = node_name
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return node


static func _label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	return label
