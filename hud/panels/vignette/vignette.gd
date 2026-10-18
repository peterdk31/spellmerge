extends ColorRect
## A red glow at the screen edges when a wizard is hurt, strongest toward that
## wizard's corner. It only shows and fades; it takes no input and decides nothing.
##
##     vignette.flash(2)       # player 3 (bottom left) lost health
##     vignette.step(delta)    # called every frame by the HUD

const SHADER: Shader = preload("res://hud/panels/vignette/vignette.gdshader")
## How much each hit adds, the most it shows, and how fast it fades (per second).
const HIT_STRENGTH: float = 0.6
const MAX_STRENGTH: float = 0.85
const FADE_PER_SECOND: float = 2.2

## Current strength, 0 to MAX_STRENGTH.
var strength: float = 0.0
var _material: ShaderMaterial = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	visible = false


## Show the glow for a hit on `player` (0-3): corners are P1 top left, P2 top right,
## P3 bottom left, P4 bottom right. A bad index glows evenly.
func flash(player: int) -> void:
	strength = minf(strength + HIT_STRENGTH, MAX_STRENGTH)
	var corner := Vector2(0.5, 0.5)
	if player >= 0 and player < 4:
		corner = Vector2(float(player % 2), floorf(player * 0.5))
	_material.set_shader_parameter("corner", corner)
	_material.set_shader_parameter("strength", strength)
	visible = true


## Fade by `delta` seconds.
func step(delta: float) -> void:
	if strength <= 0.0:
		return
	strength = maxf(strength - FADE_PER_SECOND * delta, 0.0)
	_material.set_shader_parameter("strength", strength)
	if strength == 0.0:
		visible = false


## Hide at once (a run starts or ends).
func clear() -> void:
	strength = 0.0
	visible = false
