extends Control
## One card of a level-up pick (horde, H5): a row with a stripe in the card's kind colour, its
## 16x16 icon, its name and the word of its kind under it (so the kind is never colour alone),
## the way the radial builder's hub shows a card (`Spells.component_name`, `component_icon`,
## `component_kind`). The chosen card gets a gold frame and a gold ">" mark at its left edge.
## Display only: `horde_pick.gd` sets it and reads the input.

const RadialScript := preload("res://hud/builder/radial_builder.gd")

const ROW_SIZE: Vector2 = Vector2(108.0, 20.0)
const STRIPE_WIDTH: float = 3.0
const ICON_SIZE: float = 16.0
const ICON_LEFT: float = 8.0
const TEXT_LEFT: float = 27.0
const MARK_SIZE: Vector2 = Vector2(3.0, 6.0)

var _id: StringName = &""
var _chosen: bool = false
var _kind_color: Color = RadialScript.MUTED
var _icon: TextureRect = null
var _name_label: Label = null
var _kind_label: Label = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = ROW_SIZE
	clip_contents = true
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.position = Vector2(ICON_LEFT, (ROW_SIZE.y - ICON_SIZE) * 0.5)
	_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	add_child(_icon)
	_name_label = _line("Name", &"BuilderLabel", -1.0)
	_kind_label = _line("Kind", &"BuilderHint", 10.0)


func _line(label_name: String, variation: StringName, top: float) -> Label:
	var label := Label.new()
	label.name = label_name
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.position = Vector2(TEXT_LEFT, top)
	label.size = Vector2(ROW_SIZE.x - TEXT_LEFT - 2.0, 11.0)
	add_child(label)
	return label


## Show the card `id`: its `shown_name`, `icon` (or none) and `kind` (`&"form"`, ...; `&""`
## unknown, shown with no word and a grey stripe).
func show_card(id: StringName, shown_name: String, icon: Texture2D, kind: StringName) -> void:
	_id = id
	_icon.texture = icon
	_name_label.text = shown_name
	_kind_label.text = String(RadialScript.KIND_WORDS.get(kind, ""))
	_kind_color = RadialScript.KIND_COLORS.get(kind, RadialScript.MUTED)
	_kind_label.add_theme_color_override("font_color", _kind_color)
	queue_redraw()


func set_chosen(chosen: bool) -> void:
	if chosen != _chosen:
		_chosen = chosen
		queue_redraw()


func is_chosen() -> bool:
	return _chosen


func card_id() -> StringName:
	return _id


func name_text() -> String:
	return _name_label.text


func kind_text() -> String:
	return _kind_label.text


func icon() -> Texture2D:
	return _icon.texture


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, RadialScript.TILE)
	draw_rect(Rect2(Vector2.ZERO, Vector2(STRIPE_WIDTH, size.y)), _kind_color)
	if _chosen:
		draw_rect(rect.grow(-0.5), RadialScript.GOLD, false, 1.0)
		var tip_y: float = size.y * 0.5
		var left: float = STRIPE_WIDTH + 1.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(left, tip_y - MARK_SIZE.y * 0.5), Vector2(left + MARK_SIZE.x, tip_y),
			Vector2(left, tip_y + MARK_SIZE.y * 0.5)]), RadialScript.GOLD)
	else:
		draw_rect(rect.grow(-0.5), RadialScript.LINE, false, 1.0)
