class_name PropLook
extends ActorLook
## A prop's look (props W7, docs/milestones/props.md, "W7: the look"): it shows the look of the
## state the prop is in (`PropBase.look_of`, from the body's `prop`), and the next one as its
## `PropStateTriggers` enters it. A look is data (`PropStateLook`), so this holds no art of its own:
##
## - **its layers:** the first is the body, the actor's own `Sprite` (which a hit flashes and
##   squashes, as any body's); the rest are sprites of its own, drawn among the bodies or over them
##   (`over_bodies`), or not at all (`hidden`: a mask only). Each frame of a layer's picture stands
##   with its bottom middle on the feet, moved by its `offset`; a layer of several frames plays them
##   on this look's own clock.
## - **its motes:** a node in the group `mote_source` for every `MoteSource` of a layer, a mask's
##   reading that layer's sprite (`mote_art`); Feel gives them off (gameplay/feel/source_motes.gd),
##   so they come and go with the state.
## - **its light:** a marker in the group `light_spot` (core/base/light_spot.gd) where it says, in its
##   tint or its layer's art colour; Feel's spell light draws it.
## - **its cue,** played on the bus where the body stands as its state is entered (never for the
##   state it starts in, nor for one a snapshot gave it back: `PropStateTriggers.restored`, which
##   the look follows with no cue).
##
## A still prop is never stepped, so its animated layers run on `_process` (a view's own clock).
## View only: nothing in the game reads it.

## The node the body's own picture is (Feel flashes a hit body's `Sprite`).
const BODY_SPRITE: StringName = &"Sprite"

## The look shown now (null: none), and the nodes made for it.
var shown: PropStateLook = null
var _parts: Array[Node] = []
## The layers' sprites, one a layer (the body's first; null for an empty layer), and how long the look has shown (s, its animations' clock).
var _sprites: Array[Sprite2D] = []
var _clock: float = 0.0


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	set_process(false)
	if actor.state_triggers != null and not actor.state_triggers.entered.is_connected(_on_entered):
		actor.state_triggers.entered.connect(_on_entered)
		actor.state_triggers.restored.connect(_on_restored)
	show_state(actor.state_triggers.state_id() if actor.state_triggers != null else &"", false)


## Show the look of the state `state_id` (`entered`: it was just entered, so its cue plays).
func show_state(state_id: StringName, entered: bool) -> void:
	var look: PropStateLook = actor.prop.look_of(state_id) if actor != null and actor.prop != null else null
	if look == shown and look != null and not entered:
		return
	_clear()
	shown = look
	if look == null:
		return
	for i in look.layers.size():
		var layer: PropLayer = look.layers[i]
		if layer == null:
			# Kept in line with the layers (`PropStateLook.problems` names it).
			_sprites.append(null)
			continue
		var sprite: Sprite2D = _sprite_for(i)
		_draw_layer(sprite, layer)
		_sprites.append(sprite)
		for k in layer.motes.size():
			if layer.motes[k] != null:
				_add_motes(layer.motes[k], sprite, "Motes%d_%d" % [i, k])
	if look.light_reach > 0.0:
		_add_light(look)
	set_process(_animated())
	if entered and look.cue != &"" and actor.events != null:
		var size: float = actor.hurtbox.outer_radius() if actor.hurtbox != null else 8.0
		actor.events.cue_shown.emit(actor.id, look.cue, actor.global_position + actor.body_offset, Vector2.UP, size, Color.WHITE, 0)


## The sprite of layer `i`: the body's own for the first (when the body has one), else a new one.
func _sprite_for(i: int) -> Sprite2D:
	var body: Sprite2D = actor.get_node_or_null(NodePath(BODY_SPRITE)) as Sprite2D
	if i == 0 and body != null:
		return body
	var sprite := Sprite2D.new()
	sprite.name = "Layer%d" % i
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	_parts.append(sprite)
	return sprite


## `sprite` as `layer` says: its picture's first frame, its bottom middle on the feet moved by its
## offset (whole pixels), drawn among the bodies or over them, or hidden.
func _draw_layer(sprite: Sprite2D, layer: PropLayer) -> void:
	sprite.texture = layer.texture
	sprite.hframes = maxi(layer.frames, 1)
	sprite.frame = 0
	sprite.centered = true
	var size: Vector2i = layer.frame_size()
	sprite.position = layer.offset + Vector2(0.0, -float(size.y / 2))
	# An odd side would centre on half a pixel: put the picture back on the pixels.
	sprite.offset = Vector2(size.x % 2, size.y % 2) * 0.5
	sprite.z_index = 1 if layer.over_bodies else 0
	sprite.visible = not layer.hidden


## A node giving off `source` from the feet, its mask (if any) `sprite`'s art.
func _add_motes(source: MoteSource, sprite: Sprite2D, label: String) -> void:
	var node := Node2D.new()
	node.name = label
	node.add_to_group(MoteSource.GROUP)
	node.set_meta(MoteSource.META, source)
	node.set_meta(MoteSource.ART, _path_from_child(sprite))
	add_child(node)
	_parts.append(node)


## Its light: a marker in the light spots' group where the look says, in its tint or its layer's
## art colour.
func _add_light(look: PropStateLook) -> void:
	var marker := Marker2D.new()
	marker.name = "Light"
	marker.position = look.light_at
	marker.set_meta(LightSpot.REACH, look.light_reach)
	marker.set_meta(LightSpot.STRENGTH, look.light_strength)
	marker.set_meta(LightSpot.FLICKER, look.light_flicker)
	if look.light_tint.a > 0.0:
		marker.set_meta(LightSpot.TINT, look.light_tint)
	elif look.light_layer >= 0 and look.light_layer < _sprites.size() and _sprites[look.light_layer] != null:
		marker.set_meta(LightSpot.ART, _path_from_child(_sprites[look.light_layer]))
	marker.add_to_group(LightSpot.GROUP)
	add_child(marker)
	_parts.append(marker)


## The path to `sprite` from a child of this look (the body's own sprite is the actor's child).
func _path_from_child(sprite: Sprite2D) -> NodePath:
	if sprite.get_parent() == self:
		return NodePath("../%s" % sprite.name)
	return NodePath("../../%s" % sprite.name)


## The nodes of the look shown are taken out, and the body's own picture emptied.
func _clear() -> void:
	for node in _parts:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	_parts.clear()
	_sprites.clear()
	shown = null
	_clock = 0.0
	var body: Sprite2D = actor.get_node_or_null(NodePath(BODY_SPRITE)) as Sprite2D if actor != null else null
	if body != null:
		body.texture = null
		body.hframes = 1
		body.frame = 0


func _animated() -> bool:
	if shown == null:
		return false
	for layer in shown.layers:
		if layer != null and layer.frames > 1 and layer.fps > 0.0:
			return true
	return false


## The animated layers' frames, on this look's own clock.
func _process(delta: float) -> void:
	if shown == null:
		return
	_clock += delta
	for i in _sprites.size():
		var layer: PropLayer = shown.layers[i] if i < shown.layers.size() else null
		if layer != null and _sprites[i] != null and layer.frames > 1 and layer.fps > 0.0:
			_sprites[i].frame = floori(_clock * layer.fps) % layer.frames


func _on_entered(state_id: StringName) -> void:
	show_state(state_id, true)


func _on_restored(state_id: StringName) -> void:
	show_state(state_id, false)
