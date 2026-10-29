extends "res://tests/support/screenshot.gd"
## The art of the wizard, the ember imp and the crypt at 2x on the crypt floor (`art_sheet`):
## the wizard's idle, walk and dash frames under player 1's hat, the four players, the imp's
## idle, windup and hurt poses, the staff, the bolt, the hit spark, the dash telegraph, the
## crypt's wall, pillar, door and floor dressing, and the torch flame's frames. The spell
## cards' art is in `shot_cards.gd`.

const SCALE := 2.0
const FRAME := 32.0

const WALL := preload("res://art/tilesets/crypt/wall.svg")
const IDLE := preload("res://content/wizard/base/wizard_idle.svg")
const WALK := preload("res://content/wizard/base/wizard_walk.svg")
const DASH_STRIP := preload("res://content/wizard/base/wizard_dash.svg")
const HATS: Array[Texture2D] = [
	preload("res://content/wizard/base/wizard_hat_p1.svg"),
	preload("res://content/wizard/base/wizard_hat_p2.svg"),
	preload("res://content/wizard/base/wizard_hat_p3.svg"),
	preload("res://content/wizard/base/wizard_hat_p4.svg"),
]
const STAFF := preload("res://content/wizard/base/staff.svg")
const IMP := preload("res://content/enemies/ember_imp/idle.svg")
const SPLINTER := preload("res://content/enemies/splinter/idle.svg")
const FORK := preload("res://content/enemies/storm_fork/idle.svg")
const CROOK := preload("res://content/enemies/rime_crook/idle.svg")
const SCEPTER := preload("res://content/enemies/bone_scepter/idle.svg")
const WALL_TOP := preload("res://art/tilesets/crypt/wall_top.svg")
const PILLAR := preload("res://art/tilesets/crypt/pillar.svg")
const PILLAR_TOP := preload("res://art/tilesets/crypt/pillar_top.svg")
const TORCH_FLAME := preload("res://art/tilesets/crypt/torch_flame.svg")
const DOOR := preload("res://art/tilesets/crypt/door.svg")
const TORCH := preload("res://art/tilesets/crypt/torch.svg")
const RUBBLE := preload("res://art/tilesets/crypt/rubble.svg")
const SKULL := preload("res://art/tilesets/crypt/skull.svg")
const DASH := preload("res://art/vfx/telegraph_dash.svg")
const BOLT := preload("res://art/vfx/bolt.svg")
const SPARK := preload("res://art/vfx/hit_spark.svg")


func take() -> void:
	settle_frames = 10
	lay_floor()
	# Row 1: the wizard's idle (4: open, closed, glance left, glance right), walk (4) and
	# dash (2) frames, each under player 1's hat.
	var x: float = 4.0
	x = _strip(IDLE, x, 40.0, HATS[0])
	x = _strip(WALK, x, 40.0, HATS[0])
	x = _strip(DASH_STRIP, x, 40.0, HATS[0])
	# Row 2: the four players, the imp, the staff, the bolt and the spark.
	x = 32.0
	for hat: Texture2D in HATS:
		_frame(IDLE, 0, x, 120.0)
		_frame(hat, 0, x, 120.0)
		x += FRAME * SCALE
	x = _strip(IMP, x, 120.0)
	for texture: Texture2D in [STAFF, BOLT, SPARK]:
		_frame(texture, 0, x, 120.0)
		x += FRAME * SCALE
	# Row 3: floor and wall tiles side by side, as in the room.
	x = 32.0
	for texture: Texture2D in [WALL, WALL_TOP, PILLAR_TOP, PILLAR, DOOR, TORCH, RUBBLE, SKULL, DASH]:
		_frame(texture, 0, x, 200.0)
		x += FRAME * SCALE
	# Row 4: the other strays (the face carries their mood), then the torch flame and glow frames.
	_frame(SPLINTER, 0, 32.0, 266.0)
	_frame(FORK, 0, 32.0 + FRAME * SCALE, 266.0)
	_frame(CROOK, 0, 32.0 + FRAME * SCALE * 2.0, 266.0)
	_frame(SCEPTER, 0, 32.0 + FRAME * SCALE * 3.0, 266.0)
	x = 32.0 + FRAME * SCALE * 4.0
	_strip(TORCH_FLAME, x, 266.0)
	await shot("art_sheet")


## Every frame of a strip, left to right from `x`. Returns the x after the strip.
func _strip(texture: Texture2D, x: float, y: float, hat: Texture2D = null) -> float:
	var frames: int = int(texture.get_width() / FRAME)
	for i in frames:
		_frame(texture, i, x, y)
		if hat != null:
			_frame(hat, 0, x, y)
		x += FRAME * SCALE
	return x + FRAME * 0.5


func _frame(texture: Texture2D, frame: int, x: float, y: float) -> void:
	var sprite: Sprite2D = place(texture, SCALE, Vector2(x, y))
	sprite.hframes = maxi(int(texture.get_width() / FRAME), 1)
	sprite.frame = frame
