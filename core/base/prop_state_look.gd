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
## body's; so it is drawn among the bodies, never hidden.

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
## layer that is hidden or drawn over the bodies, each layer's problems, a light whose layer is not
## there or whose numbers are out of range.
func problems(owner: String) -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = "%s: the look of %s" % [owner, state_id if state_id != &"" else "every state"]
	if layers.is_empty():
		found.append("%s has no layers." % name)
	elif layers[0] != null and (layers[0].hidden or layers[0].over_bodies):
		found.append("%s: its first layer is the body; it is neither hidden nor over the bodies." % name)
	for i in layers.size():
		if layers[i] == null:
			found.append("%s: layer %d is empty." % [name, i])
		else:
			found.append_array(layers[i].problems("%s, layer %d" % [name, i]))
	if light_reach > 0.0 and light_tint.a <= 0.0 and (light_layer < 0 or light_layer >= layers.size()):
		found.append("%s: its light takes its colour from layer %d, which it does not have." % [name, light_layer])
	return found
