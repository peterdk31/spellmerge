extends ColorRect
## A red glow at the screen edges when a wizard is hurt, strongest toward that
## wizard's corner. It only shows and fades; it takes no input and decides nothing.
##
##     vignette.flash(2)       # player 3 (bottom left) lost health
##     vignette.step(delta)    # called every frame by the HUD

const SHADER: Shader = preload("res://hud/panels/vignette/vignette.gdshader")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
## How much each hit adds, the most it shows, and how fast it fades (per second).
const HIT_STRENGTH: float = 0.7
const MAX_STRENGTH: float = 1.0
const FADE_PER_SECOND: float = 2.0
## A hit that takes this share of the maximum health (or more) adds the full
## HIT_STRENGTH; a smaller one adds less, but never less than a fifth of it.
const FULL_HIT_SHARE: float = 0.25

## The setting: false shows no vignette at all (kept in memory, like Feel.shake_enabled).
var enabled: bool = true
## Current strength, 0 to MAX_STRENGTH.
var strength: float = 0.0
var _material: ShaderMaterial = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	ShaderWarmupScript.want(SHADER, ShaderWarmupScript.RECT)
	material = _material
	visible = false


## Show the glow for a hit on `player` (0-3): corners are P1 top left, P2 top right,
## P3 bottom left, P4 bottom right. A bad index glows evenly.
func flash(player: int) -> void:
	flash_hit(player, FULL_HIT_SHARE, 1)


## Like `flash`, for a hit that took `share` (0 to 1) of the wizard's maximum health
## while `players` wizards are playing. Each hit adds less the more wizards are in the
## fight (by the square root of their number: half as much for four), so four
## wizards under fire do not keep the screen red.
func flash_hit(player: int, share: float, players: int) -> void:
	if not enabled:
		return
	var weight: float = clampf(share / FULL_HIT_SHARE, 0.2, 1.0)
	strength = minf(strength + HIT_STRENGTH * weight / sqrt(float(maxi(players, 1))), MAX_STRENGTH)
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
