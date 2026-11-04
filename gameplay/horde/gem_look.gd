class_name GemLook
extends Resource
## How the horde's experience gems look (docs/milestones/horde.md, "Experience"; S6 item 14 of
## docs/milestones/spell-spectacle-2.md: their colours are data, not code). One file,
## `gameplay/horde/gem_look.tres`, read by `horde_gems.gd` when it is made: a soft additive glow
## round a tiny white-hot core (the glow style) that breathes.

## The glow's colours, from the white-hot core out to nothing; the glow's middle ring is
## `glow_color` at `GLOW_FADE` of its alpha.
@export var core_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var glow_color: Color = Color(0.45, 1.0, 0.75, 0.85)
@export var edge_color: Color = Color(0.2, 0.8, 0.6, 0.0)
## The quad a gem is drawn on, pixels (the glow; the core is its middle).
@export_range(4.0, 64.0, 1.0) var size: float = 14.0
## The glow breathes: its brightness swings this much, this many times a second.
@export_range(0.0, 1.0, 0.01) var pulse_depth: float = 0.2
@export_range(0.0, 8.0, 0.1) var pulse_rate: float = 1.5

const GLOW_FADE: float = 0.35


## The glow's gradient, white-hot core to nothing (made once, when the gems are made).
func gradient() -> Gradient:
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.18, 0.4, 1.0])
	glow.colors = PackedColorArray([core_color, glow_color, glow_color * Color(1.0, 1.0, 1.0, GLOW_FADE), edge_color])
	return glow
