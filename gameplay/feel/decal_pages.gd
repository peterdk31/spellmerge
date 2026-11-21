extends RefCounted
## A laid room's decals drawn from one page each (the owner's choice of 2026-11-21, after #900: "a
## candle is 1 call instead of 2"). A decal (an instanced scene of plain art: the candles, a torch)
## draws its plain layers one after another: the candles' wax, then their flame's frames, each from
## a file of its own, so a call each. As `room_built` hands a layout over, every decal's plain layers
## (a `Sprite2D`'s texture, an `AnimatedSprite2D`'s frames; shown, with no material and in no group:
## not the glow and core the light reads, `painted_light`) are put on one page (`TexturePage`), the
## page shared by every decal of that art, so a candle is one call, and a row of candles one too.
##
## Nothing else changes: the flame's `SpriteFrames` is a copy of its own with each frame's texture
## the page's copy (the same frames, durations, speed and loop), its animation playing on from the
## frame it was at, so it flickers exactly as before. View only (no node the simulation reads).

const EventsScript := preload("res://core/events/events.gd")

## The flames' frames on a page, by their own frames and the page; and each copy's own frames.
static var _frames: Dictionary = {}
static var _own: Dictionary[SpriteFrames, SpriteFrames] = {}

## How many decals were put on a page (for tests).
var put: int = 0


## Hear `room_built` on `events` for the rooms' layouts.
func bind(events: EventsScript) -> void:
	if events != null and not events.room_built.is_connected(_on_room_built):
		events.room_built.connect(_on_room_built)


func _on_room_built(_room_id: StringName, _room: int, layout_root: Node) -> void:
	put += put_on_pages(layout_root)


## Put every decal under `root` on its page; how many were.
static func put_on_pages(root: Node) -> int:
	var count: int = 0
	if root == null:
		return count
	for node: Node in root.find_children("*", "Node2D", true, false):
		if is_decal(node) and _put(node):
			count += 1
	return count


## True for a decal: an instanced scene whose root is a plain `Node2D` with no script.
static func is_decal(node: Node) -> bool:
	return node.scene_file_path != "" and node.get_class() == "Node2D" and node.get_script() == null


## The decal's plain layers, in the order drawn.
static func plain_layers(decal: Node) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	for child: Node in decal.get_children():
		var item := child as CanvasItem
		if item == null or not item.visible or item.material != null or not item.get_groups().is_empty():
			continue
		if (item is Sprite2D and (item as Sprite2D).texture != null) \
				or (item is AnimatedSprite2D and (item as AnimatedSprite2D).sprite_frames != null):
			found.append(item)
	return found


## The frames `frames` were copied from (itself when it is no copy; for the screenshots).
static func own_frames_of(frames: SpriteFrames) -> SpriteFrames:
	return _own.get(frames, frames) as SpriteFrames


static func _put(decal: Node) -> bool:
	var layers: Array[CanvasItem] = plain_layers(decal)
	if layers.size() < 2:
		return false
	var textures: Array[Texture2D] = []
	for item: CanvasItem in layers:
		if item is Sprite2D:
			textures.append((item as Sprite2D).texture)
		else:
			var frames: SpriteFrames = (item as AnimatedSprite2D).sprite_frames
			for animation: StringName in frames.get_animation_names():
				for k in frames.get_frame_count(animation):
					textures.append(frames.get_frame_texture(animation, k))
	var regions: Array[Texture2D] = TexturePage.regions_of(textures)
	if regions.is_empty() or not (regions[0] is AtlasTexture) or regions[0] == textures[0]:
		return false
	var by: Dictionary[Texture2D, Texture2D] = {}
	for i in textures.size():
		if textures[i] != null:
			by[textures[i]] = regions[i]
	for item: CanvasItem in layers:
		if item is Sprite2D:
			var sprite := item as Sprite2D
			sprite.texture = by.get(sprite.texture, sprite.texture)
		else:
			_swap_frames(item as AnimatedSprite2D, by, (regions[0] as AtlasTexture).atlas)
	return true


## `sprite`'s frames swapped for their copy on the page, playing on as they were.
static func _swap_frames(sprite: AnimatedSprite2D, by: Dictionary[Texture2D, Texture2D], page: Texture2D) -> void:
	var own: SpriteFrames = sprite.sprite_frames
	var key: Array = [own, page]
	var copy: SpriteFrames = _frames.get(key, null)
	if copy == null:
		copy = SpriteFrames.new()
		copy.remove_animation(&"default")
		for animation: StringName in own.get_animation_names():
			copy.add_animation(animation)
			copy.set_animation_loop(animation, own.get_animation_loop(animation))
			copy.set_animation_speed(animation, own.get_animation_speed(animation))
			for k in own.get_frame_count(animation):
				var texture: Texture2D = own.get_frame_texture(animation, k)
				copy.add_frame(animation, by.get(texture, texture), own.get_frame_duration(animation, k))
		_frames[key] = copy
		_own[copy] = own
	var playing: bool = sprite.is_playing()
	var animation: StringName = sprite.animation
	var frame: int = sprite.frame
	var progress: float = sprite.frame_progress
	sprite.sprite_frames = copy
	sprite.animation = animation
	if playing:
		sprite.play(animation)
	sprite.set_frame_and_progress(frame, progress)
