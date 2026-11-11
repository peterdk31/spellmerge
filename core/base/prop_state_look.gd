class_name PropStateLook
extends Resource
## What a prop looks like in one of its states (props W7, docs/milestones/props.md, "W7: the look"):
## its art layers and the motes they give off, a light, and the cue played as the state is entered.
## A row of `PropBase.looks`, found by `state_id` (empty: the look of every state with none of its
## own). Looks live on the prop, not on its states, so two props of one states file (a small and a
## big exploding barrel) look as each wants. View only: nothing in the game reads it. It has no
## `id`, so the registry never takes it for content.
##
## Its first layer is the body: the prop's `Sprite`, which a hit flashes and squashes as any
## body's; so it is drawn among the bodies or on the floor (a slab), never over them nor hidden. A mask (`MoteSource.From.MASK`) is read
## once, as its layer is drawn when the state is entered, so it is never on the body's layer (a hit
## squashes it) nor on a layer of several frames: a mask is a layer of its own, as
## `tools/pixel_grid.py` writes one.

## The state it is the look of (`PropState.state_id`); empty: every state with no look of its own.
@export var state_id: StringName = &""
## Its layers, drawn in order (the first is the body, see above).
@export var layers: Array[PropLayer] = []
## Its light (Feel's spell light, as a torch's: core/base/light_spot.gd): how far it reaches
## (0: none), from where (from the feet), how bright, how much it flickers, in the colour of which
## layer's art (`light_layer`) unless `light_tint` is set (its alpha above 0).
@export_range(0.0, 256.0, 1.0) var light_reach: float = 0.0
@export var light_at: Vector2 = Vector2(0.0, -8.0)
@export_range(0.0, 1.0, 0.05) var light_strength: float = LightSpot.DEFAULT_STRENGTH
@export_range(0.0, 1.0, 0.05) var light_flicker: float = LightSpot.DEFAULT_FLICKER
@export var light_layer: int = 0
@export var light_tint: Color = Color(0, 0, 0, 0)
## The cue (`content/cues/<cue>.tres`) played where the prop stands as the state is entered (not
## the state it starts in): a barrel's blast is its staff's, a crate's splinters are its broken
## state's. Empty: none.
@export var cue: StringName = &""


## What is wrong with it, one line each after `owner` (empty when nothing is): no layers, a first
## layer that is hidden or drawn over the bodies, a mask on the body's layer or on one of several
## frames, each layer's problems, a light whose layer is not there or whose numbers are out of
## range.
func problems(owner: String) -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = "%s: the look of %s" % [owner, state_id if state_id != &"" else "every state"]
	if layers.is_empty():
		found.append("%s has no layers." % name)
	elif layers[0] != null and layers[0].drawn in [PropLayer.Drawn.HIDDEN, PropLayer.Drawn.OVER_BODIES]:
		found.append("%s: its first layer is the body; it is neither hidden nor over the bodies." % name)
	for i in layers.size():
		if layers[i] == null:
			found.append("%s: layer %d is empty." % [name, i])
			continue
		found.append_array(layers[i].problems("%s, layer %d" % [name, i]))
		if layers[i].has_mask() and (i == 0 or layers[i].frames > 1):
			found.append("%s, layer %d: a mask is read once, so it is a still layer of its own, never the body's (layer 0) nor one of several frames." % [name, i])
	if light_reach < 0.0:
		found.append("%s: light_reach is %s; 0 (none) or more." % [name, light_reach])
	if light_reach > 0.0:
		if light_strength < 0.0 or light_strength > 1.0 or light_flicker < 0.0 or light_flicker > 1.0:
			found.append("%s: light_strength and light_flicker are 0 to 1 (%s, %s)." % [name, light_strength, light_flicker])
		if light_tint.a <= 0.0 and (light_layer < 0 or light_layer >= layers.size()):
			found.append("%s: its light takes its colour from layer %d, which it does not have." % [name, light_layer])
	return found
