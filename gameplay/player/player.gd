extends CharacterBody2D
## The wizard controller (M1 part 9: move and dodge). One instance per player,
## any index 0-3. It reads only its own player's input from `core/input` and
## never looks at another player, so nobody waits for anybody.
##
## The scene is content/wizard/base/wizard.tscn, with this script on its root.
## Set `index` before adding the node to the tree.
##
## Dodge: a press of the `dodge` action starts a short dash. The wizard cannot
## be hurt for the first part of it (is_invulnerable()), then there is a cooldown
## before the next dodge. Combat (part 11) asks is_invulnerable() before damage.
## A press made while the dodge is not ready is dropped, not queued.
##
## Health and mana: MAX_HEALTH, and MAX_MANA that regenerates. A hit (the
## `damage_dealt` event with this wizard as target, or take_damage()) does nothing
## while invulnerable or downed. At 0 health the wizard is downed: it cannot move,
## dodge or cast, and `player_downed` is sent. revive(reviver) (called by whoever
## decides a teammate revived it, e.g. coop) brings it back with REVIVE_HEALTH and
## sends `player_revived`. Other wizards are never affected: nobody waits.
##
## Stats: `player_stats_changed` is sent when the wizard appears and whenever health
## changes or mana crosses a whole number, so the HUD shows only what it is told
## (about 10 events a second per regenerating player, none when nothing changes).
##
## Aim: shots go where the wizard aims, not where it walks (twin-stick). The right
## stick aims; the keyboard player aims at the mouse once it has moved (the J key
## switches back); with no aim input the wizard aims the way it walks. After the
## right stick is let go the aim holds AIM_HOLD_TIME, so a quick flick still
## shoots where it pointed. A small reticle in the player colour shows the aim.
## Shots start at the tip of the staff (muzzle_position()), held in front of the
## body at hand height, not at the feet.
##
## Animation: the sprite plays an idle, a walk or a dash strip (frames of 32 px
## side by side, see docs/STYLE.md); _update_animation() picks it from the speed
## and the dodge. The staff is drawn above the sprite along the aim.
##
## Dash look: during a dodge the sprite stretches and leans along the dash and
## fading ghosts of it trail behind (drawn in _draw; no nodes or arrays made).
##
## Cast: while `cast` is held the wizard calls `spell.cast(index, origin, aim, mana)`
## and reads no spell field. If the spell fired it takes the mana returned, sends
## `spell_cast` and plays the sound `cast` from `core/registry` (nothing on null).
##
## All timing runs in step(delta), so tests drive it with fixed deltas and no
## real-time waits. Nothing here allocates per frame.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## Walking speed in pixels per second (the view is 640x360).
const MOVE_SPEED: float = 90.0
## Dash speed, and how long the dash lasts.
const DODGE_SPEED: float = 220.0
const DODGE_TIME: float = 0.25
## The wizard cannot be hurt this long from the start of a dodge (at most DODGE_TIME).
const INVULNERABLE_TIME: float = 0.125
## Seconds from the start of a dodge until the next one may start.
const DODGE_COOLDOWN: float = 0.625
const MAX_HEALTH: int = 100
## Health after a revive.
const REVIVE_HEALTH: int = 50
const MAX_MANA: float = 100.0
## Mana regained per second.
const MANA_REGEN: float = 10.0
## Seconds the aim holds after the right stick is let go.
const AIM_HOLD_TIME: float = 0.6
## A mouse closer than this (pixels) to the wizard gives no direction.
const MOUSE_MIN_DISTANCE: float = 4.0
## The reticle: its distance from the wizard's feet and its size, in pixels.
const RETICLE_DISTANCE: float = 38.0
const RETICLE_SIZE: float = 4.0
## Aim x beyond which the sprite turns (and turns back): a band against flicker.
## The flip also mirrors the painted light; fine for the placeholder art.
const FLIP_BAND: float = 0.3
## The staff: its hand is HAND_HEIGHT above the feet; the tip (where shots start)
## is STAFF_REACH from the hand along the aim.
const HAND_HEIGHT: float = 10.0
const STAFF_REACH: float = 14.0
## Dash look: sprite stretch along the dash, lean in radians, the ghosts' spacing
## in pixels and their opacities (one per ghost).
## The stretch is for a horizontal dash; a mostly vertical one swaps the axes.
const DASH_STRETCH: Vector2 = Vector2(1.2, 0.85)
const DASH_LEAN: float = 0.1
## A ghost is left behind every GHOST_INTERVAL seconds of the dash (3 of them).
const GHOST_INTERVAL: float = 0.04
const GHOST_ALPHAS: Array[float] = [0.45, 0.28, 0.14]
## Sprite strips: every frame is FRAME_SIZE wide, the frame count is the strip's
## width divided by it. Idle and walk loop; the dash plays once and holds its
## last frame. The art shows the poses only; the speeds are set here.
const FRAME_SIZE: int = 32
const IDLE_FPS: float = 2.0
const WALK_FPS: float = 8.0
const DASH_FPS: float = 16.0
## Pixels per second above which the wizard counts as walking.
const WALK_THRESHOLD: float = 10.0
## Where the hand is on staff.svg (its pivot), in pixels from the corner.
const STAFF_PIVOT: Vector2 = Vector2(14.0, 16.0)
enum Anim { IDLE, WALK, DASH }
## Light colour of each player's ramp, for the reticle. The single source is the
## player ramps in docs/STYLE.md; core has only the base colours (projectile manager).
const PLAYER_COLORS: Array[Color] = [
	Color("7fc0f0"), Color("f59ab8"), Color("8fd46a"), Color("c99af0"),
]
const OUTLINE_COLOR: Color = Color("14121f")
## Seconds a wizard who joins mid-run cannot be hurt (see `protect`).
const JOIN_PROTECTION: float = 2.0
## The revive ring over a downed wizard: radius in pixels and the colour of its empty track.
const REVIVE_RING_RADIUS: float = 7.0
## Height of the ring's centre above the feet: over the hat, so the body stays visible.
const REVIVE_RING_HEIGHT: float = 34.0
const REVIVE_RING_BACK: Color = Color("5a5a6e")
## Id of the cast sound (looked up in core/registry; a missing sound is silent).
const CAST_SOUND_ID: StringName = &"cast"
## Physics layers (the plan: 1 walls, 2 players, 3 enemies, 4 projectiles and
## hit boxes; see gameplay/player/README.md): players are on layer 2 and collide only with walls on layer 1,
## so wizards walk through each other and never block a teammate.
const LAYER_WALLS: int = 1
const LAYER_PLAYERS: int = 2

## The player index 0-3.
@export var index: int = 0

## One idle texture per player index (the player colour). The scene lists the four
## textures; _ready() shows the one for `index` on the `Sprite` node.
@export var textures: Array[Texture2D] = []

## The walk and dash strips, one per player index like `textures`. An empty
## list (or a missing index) keeps the idle strip.
@export var walk_textures: Array[Texture2D] = []
@export var dash_textures: Array[Texture2D] = []

## The staff, drawn from the hand along the aim; pointing right, hand at STAFF_PIVOT.
## Without it a plain line is drawn.
@export var staff_texture: Texture2D = null

## The input manager. Only tests set this, before adding the node; otherwise the
## "PlayerInput" autoload is used.
var input: InputManagerScript = null

## The event bus, the registry and the projectile manager (asked where the walls
## are). Only tests set these, before adding the node; otherwise the "Events",
## "Registry" and "Projectiles" autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null
var projectiles: ProjectileManagerScript = null

## The equipped spell. The wizard only calls its cast() method.
var spell: SpellBase = null

var health: int = MAX_HEALTH
var mana: float = MAX_MANA

## The last move direction (unit length); a dodge without a direction goes this way.
var facing: Vector2 = Vector2.DOWN

## Where spells are fired (unit length): see _update_aim().
var aim: Vector2 = Vector2.DOWN

## Only tests set this: the mouse position in the world, instead of the real one.
## Vector2.INF means "ask the viewport".
var mouse_world_override: Vector2 = Vector2.INF

var _aim_hold_left: float = 0.0
## What the last _draw() drew, to redraw only when the reticle moved.
var _drawn_aim: Vector2 = Vector2.ZERO
## The `Sprite` node (null in bare-script tests) and which way it is turned.
var _sprite: Sprite2D = null
var _faces_left: bool = false
## True while the dash look is applied (to redraw and to reset it once).
var _dash_look: bool = false
## Which strip the sprite shows and the seconds it has played.
var _anim: Anim = Anim.IDLE
var _anim_time: float = 0.0
## Where the wizard was at the last ghost ticks of the dash (newest first; a
## fixed array, only overwritten), and the time to the next tick.
var _trail: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _trail_timer: float = 0.0
## Child drawn above the sprite: the staff and the reticle (null in bare scripts).
var _overlay: Node2D = null

var _dodge_left: float = 0.0
var _invulnerable_left: float = 0.0
var _cooldown_left: float = 0.0
var _dodge_direction: Vector2 = Vector2.ZERO
var _seen_dodge_presses: int = 0
var _downed: bool = false
## How far a teammate's revive has got (0 to 1), from `revive_progress`; drawn as a ring.
var _revive_progress: float = 0.0
var _sound_player: AudioStreamPlayer = null
## What the last `player_stats_changed` said, to send it only on a change.
var _sent_health: int = -1
var _sent_mana: int = -1


func _init() -> void:
	collision_layer = LAYER_PLAYERS
	collision_mask = LAYER_WALLS
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


## Show the idle texture for this player index on the `Sprite` node.
func apply_texture() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as Sprite2D
	if _sprite == null:
		return
	if index < 0 or index >= textures.size():
		push_warning("Wizard %d: no texture for this player index." % index)
		return
	_anim = Anim.IDLE
	_anim_time = 0.0
	_show_strip(textures[index])


## Show a strip on the sprite from its first frame.
func _show_strip(strip: Texture2D) -> void:
	_sprite.texture = strip
	_sprite.hframes = maxi(int(strip.get_width()) / FRAME_SIZE, 1)
	_sprite.frame = 0


## The strip for an animation: the walk or dash one when the scene has it for
## this player, else the idle one.
func _strip_for(anim: Anim) -> Texture2D:
	var list: Array[Texture2D] = textures
	if anim == Anim.WALK:
		list = walk_textures
	elif anim == Anim.DASH:
		list = dash_textures
	if index >= 0 and index < list.size() and list[index] != null:
		return list[index]
	return textures[index] if index >= 0 and index < textures.size() else null


## Choose the strip (idle, walk, dash) from what the wizard does, and the frame
## from the time since it started. Changes nothing if the strip is the same.
func _update_animation(delta: float) -> void:
	if _sprite == null:
		return
	var wanted: Anim = Anim.IDLE
	if is_dodging():
		wanted = Anim.DASH
	elif velocity.length() > WALK_THRESHOLD:
		wanted = Anim.WALK
	if wanted != _anim:
		_anim = wanted
		_anim_time = 0.0
		var strip: Texture2D = _strip_for(wanted)
		if strip != null:
			_show_strip(strip)
	else:
		_anim_time += delta
	var fps: float = IDLE_FPS
	if _anim == Anim.WALK:
		fps = WALK_FPS
	elif _anim == Anim.DASH:
		fps = DASH_FPS
	var step_index: int = int(_anim_time * fps)
	if _anim == Anim.DASH:
		_sprite.frame = mini(step_index, _sprite.hframes - 1)
	else:
		_sprite.frame = step_index % _sprite.hframes


func _ready() -> void:
	add_to_group(&"players")
	apply_texture()
	# Absolute paths only work inside the tree (tests build wizards outside it).
	var in_tree: bool = is_inside_tree()
	if input == null and in_tree:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
		if input == null:
			push_warning("Wizard %d: the PlayerInput autoload is missing, so this wizard cannot move." % index)
	if events == null and in_tree:
		events = get_node_or_null("/root/Events") as EventsScript
		if events == null:
			push_warning("Wizard %d: the Events autoload is missing, so this wizard sends no events." % index)
	if events != null and not events.damage_dealt.is_connected(_on_damage_dealt):
		events.damage_dealt.connect(_on_damage_dealt)
	if events != null and not events.revive_progress.is_connected(_on_revive_progress):
		events.revive_progress.connect(_on_revive_progress)
	if registry == null and in_tree:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if projectiles == null and in_tree:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if _overlay == null:
		_overlay = Node2D.new()
		_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay)
	if is_inside_tree() and _sound_player == null:
		_sound_player = AudioStreamPlayer.new()
		add_child(_sound_player)
	if input != null:
		_seen_dodge_presses = input.get_press_count(index, &"dodge")
	_announce_stats()


func _physics_process(delta: float) -> void:
	step(delta)
	move_and_slide()


## Advance the wizard by `delta` seconds: read input, start a dodge, set
## `velocity`. The caller moves the body (_physics_process does).
func step(delta: float) -> void:
	if _downed:
		velocity = Vector2.ZERO
		if input != null:
			# Presses made while downed are not held against the wizard after a revive.
			_seen_dodge_presses = input.get_press_count(index, &"dodge")
		return
	mana = minf(mana + MANA_REGEN * delta, MAX_MANA)
	_announce_stats()
	if spell != null:
		spell.tick(index, delta)
	_dodge_left = maxf(_dodge_left - delta, 0.0)
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if input == null:
		velocity = Vector2.ZERO
		return
	var move: Vector2 = input.get_move(index)
	if input.is_captured(index):
		# An overlay opened: freeze, and end a dash in progress (the cooldown stays).
		_dodge_left = 0.0
		_invulnerable_left = 0.0
	if move != Vector2.ZERO:
		facing = move.normalized()
	_update_aim(move, delta)
	if _dash_look:
		_tick_trail(delta)
	# Count presses rather than asking "just pressed": a tap released again
	# before this frame is not lost. A captured player (overlay open) is skipped,
	# and a press made meanwhile is not held against them later.
	var presses: int = input.get_press_count(index, &"dodge")
	var pressed: bool = presses != _seen_dodge_presses
	_seen_dodge_presses = presses
	if pressed and not input.is_captured(index) and can_dodge():
		_start_dodge(move)
	if is_dodging():
		velocity = _dodge_direction * DODGE_SPEED
	else:
		velocity = move * MOVE_SPEED
	_update_animation(delta)
	# Held, not pressed: the spell's own cooldown sets the rate. `cast` is hidden
	# while an overlay is open (captured), so a menu tap never fires.
	if spell != null and input.is_action_pressed(index, &"cast"):
		cast()


## Choose `aim` for this step: the right stick, else the mouse (keyboard player),
## else the held stick aim, else the move direction.
func _update_aim(move: Vector2, delta: float) -> void:
	var stick: Vector2 = input.get_aim(index)
	if stick != Vector2.ZERO:
		aim = stick
		_aim_hold_left = AIM_HOLD_TIME
	elif input.is_mouse_aiming(index):
		var to_mouse: Vector2 = _mouse_world() - global_position
		if to_mouse.length() >= MOUSE_MIN_DISTANCE:
			aim = to_mouse.normalized()
		_aim_hold_left = 0.0
	else:
		_aim_hold_left = maxf(_aim_hold_left - delta, 0.0)
		if _aim_hold_left <= 0.0 and move != Vector2.ZERO:
			aim = move.normalized()
	_refresh_look()


## Where shots start: the tip of the staff, in front of the wizard at hand height.
func muzzle_position() -> Vector2:
	return global_position + Vector2(0.0, -HAND_HEIGHT) + aim * STAFF_REACH


func _mouse_world() -> Vector2:
	if mouse_world_override != Vector2.INF:
		return mouse_world_override
	return get_global_mouse_position() if is_inside_tree() else global_position


## Turn the sprite toward the aim and redraw the reticle if the aim changed.
func _refresh_look() -> void:
	# Flip below -FLIP_BAND, unflip above FLIP_BAND: no flicker while the aim wobbles.
	if aim.x < -FLIP_BAND:
		_faces_left = true
	elif aim.x > FLIP_BAND:
		_faces_left = false
	if _sprite != null:
		_sprite.flip_h = _faces_left
	var dashing: bool = is_dodging() and not _downed
	if dashing or _dash_look:
		_apply_dash_look(dashing)
	if not aim.is_equal_approx(_drawn_aim):
		_drawn_aim = aim
		_redraw()


## Redraw the parts below the sprite (shadow, ghosts) and the overlay above it.
func _redraw() -> void:
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


## The sprite scale of a dash: stretched along the dominant axis of the dash.
func _dash_scale() -> Vector2:
	if absf(_dodge_direction.x) >= absf(_dodge_direction.y):
		return DASH_STRETCH
	return Vector2(DASH_STRETCH.y, DASH_STRETCH.x)


## Lean in radians, into the dash. A node's rotation is not mirrored by flip_h,
## so the sign needs no care for a sprite that faces left.
func _dash_lean() -> float:
	return clampf(_dodge_direction.x, -1.0, 1.0) * DASH_LEAN


## Stretch and lean the sprite along the dash, or put it back when it ends.
func _apply_dash_look(dashing: bool) -> void:
	_dash_look = dashing
	if _sprite != null:
		_sprite.scale = _dash_scale() if dashing else Vector2.ONE
		_sprite.rotation = _dash_lean() if dashing else 0.0
	_redraw()


## Note where the wizard is every GHOST_INTERVAL of the dash (shifts 3 values).
func _tick_trail(delta: float) -> void:
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = GHOST_INTERVAL
	for i in range(_trail.size() - 1, 0, -1):
		_trail[i] = _trail[i - 1]
	_trail[0] = global_position


## A soft shadow under the feet and the dash ghosts, both below the sprite.
func _draw() -> void:
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _dash_look and _sprite != null and _sprite.texture != null:
		_draw_ghosts()


## The staff and the aim reticle (a chevron in the player colour with an
## outline), above the sprite. No arrays are made: lines only.
func _draw_overlay() -> void:
	if _downed:
		_draw_revive_ring()
		return
	if not _reticle_visible():
		return
	_draw_staff()
	var tip: Vector2 = aim * RETICLE_DISTANCE
	var side: Vector2 = aim.orthogonal()
	var back: Vector2 = tip - aim * RETICLE_SIZE
	var color: Color = PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]
	_overlay.draw_line(back + side * RETICLE_SIZE, tip, OUTLINE_COLOR, 3.0)
	_overlay.draw_line(back - side * RETICLE_SIZE, tip, OUTLINE_COLOR, 3.0)
	_overlay.draw_line(back + side * RETICLE_SIZE, tip, color, 1.0)
	_overlay.draw_line(back - side * RETICLE_SIZE, tip, color, 1.0)


## The revive ring over a downed wizard: a dark ring with an arc that sweeps
## round clockwise from the top as the hold goes on, so the progress reads from the
## length, not the colour. A small cross in the middle marks it as a revive.
func _draw_revive_ring() -> void:
	var centre := Vector2(0.0, -REVIVE_RING_HEIGHT)
	var color: Color = PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]
	_overlay.draw_arc(centre, REVIVE_RING_RADIUS, 0.0, TAU, 24, OUTLINE_COLOR, 4.0)
	_overlay.draw_arc(centre, REVIVE_RING_RADIUS, 0.0, TAU, 24, REVIVE_RING_BACK, 2.0)
	if _revive_progress > 0.0:
		_overlay.draw_arc(centre, REVIVE_RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * _revive_progress, 24, color, 2.0)
	_overlay.draw_line(centre + Vector2(-2, 0), centre + Vector2(2, 0), OUTLINE_COLOR, 3.0)
	_overlay.draw_line(centre + Vector2(0, -2), centre + Vector2(0, 2), OUTLINE_COLOR, 3.0)
	_overlay.draw_line(centre + Vector2(-2, 0), centre + Vector2(2, 0), Color.WHITE, 1.0)
	_overlay.draw_line(centre + Vector2(0, -2), centre + Vector2(0, 2), Color.WHITE, 1.0)


## Fading copies of the sprite where the wizard was, stretched and leaned like it.
func _draw_ghosts() -> void:
	var texture: Texture2D = _sprite.texture
	var size: Vector2 = Vector2(FRAME_SIZE, texture.get_height())
	var source: Rect2 = Rect2(Vector2(_sprite.frame * FRAME_SIZE, 0.0), size)
	var tint: Color = PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]
	var flip: float = -1.0 if _faces_left else 1.0
	var stretch: Vector2 = _dash_scale()
	var lean: float = _dash_lean()
	for i in GHOST_ALPHAS.size():
		var at: Vector2 = _sprite.position + _trail[i] - global_position
		draw_set_transform(at, lean, Vector2(flip * stretch.x, stretch.y))
		draw_texture_rect_region(texture, Rect2(-size * 0.5, size), source, Color(tint, GHOST_ALPHAS[i]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The staff: the staff art turned along the aim with the hand on the wizard
## (a plain line without the art), and a gem in the player colour at the tip.
func _draw_staff() -> void:
	var hand: Vector2 = Vector2(0.0, -HAND_HEIGHT)
	var tip: Vector2 = hand + aim * STAFF_REACH
	var color: Color = PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]
	if staff_texture != null:
		# Aiming left the art is also flipped, so its lit side stays on top.
		var flip: float = -1.0 if aim.x < 0.0 else 1.0
		_overlay.draw_set_transform(hand, aim.angle(), Vector2(1.0, flip))
		_overlay.draw_texture(staff_texture, -STAFF_PIVOT)
		_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_overlay.draw_line(hand, tip, OUTLINE_COLOR, 3.0)
		_overlay.draw_line(hand, tip, Color("8a5a44"), 1.0)
		_overlay.draw_circle(tip, 2.5, OUTLINE_COLOR)
	_overlay.draw_circle(tip, 1.5, color)


## True when _draw() shows the aim reticle: not while downed.
func _reticle_visible() -> bool:
	return not _downed and aim != Vector2.ZERO


## Fire the equipped spell now. Returns true if it fired. Does nothing when
## downed or without a spell.
func cast() -> bool:
	if _downed or spell == null:
		return false
	var origin: Vector2 = muzzle_position()
	if projectiles != null:
		# A staff tip behind a wall: the shot starts at the wall and ends on it
		# (the manager takes no pool slot for a shot that starts inside a wall).
		origin = projectiles.clip_to_walls(global_position, origin)
	var spent: float = spell.cast(index, origin, aim, mana)
	if spent == SpellBase.REFUSED:
		return false
	mana -= spent
	_announce_stats()
	if events != null:
		events.spell_cast.emit(index, spell.spell_id(), origin, aim)
		events.wizard_cast.emit(index, self)
	_play_cast_sound()
	return true


func _play_cast_sound() -> void:
	if registry == null or _sound_player == null:
		return
	var stream: AudioStream = registry.get_sound(CAST_SOUND_ID)
	if stream == null:
		return
	_sound_player.stream = stream
	_sound_player.play()


## Send `player_stats_changed` if health or whole mana differ from the last one sent.
func _announce_stats() -> void:
	var whole_mana: int = floori(mana)
	if events == null or (health == _sent_health and whole_mana == _sent_mana):
		return
	_sent_health = health
	_sent_mana = whole_mana
	events.player_stats_changed.emit(index, health, MAX_HEALTH, float(whole_mana), MAX_MANA)


func is_downed() -> bool:
	return _downed


## How far a teammate's revive has got, 0 to 1 (0 when standing).
func revive_progress() -> float:
	return _revive_progress


func _on_revive_progress(player: int, progress: float) -> void:
	if player != index:
		return
	_revive_progress = clampf(progress, 0.0, 1.0)
	if _overlay != null:
		_overlay.queue_redraw()


func _on_damage_dealt(_player: int, target: Node, amount: int, _position: Vector2) -> void:
	if target == self:
		take_damage(amount)


## Lose `amount` health. Ignored while invulnerable or downed. Returns true if it
## was applied. At 0 health the wizard is downed and `player_downed` is sent.
func take_damage(amount: int) -> bool:
	if _downed or is_invulnerable() or amount <= 0:
		return false
	health = maxi(health - amount, 0)
	_announce_stats()
	if health == 0:
		_downed = true
		_apply_dash_look(false)
		_dodge_left = 0.0
		_invulnerable_left = 0.0
		velocity = Vector2.ZERO
		_revive_progress = 0.0
		_redraw()
		if events != null:
			events.player_downed.emit(index)
	return true


## Bring a downed wizard back with REVIVE_HEALTH; `reviver` is the index of the
## teammate who did it. Returns false if the wizard was not downed.
func revive(reviver: int) -> bool:
	if not _downed:
		return false
	_downed = false
	_revive_progress = 0.0
	_redraw()
	health = REVIVE_HEALTH
	_announce_stats()
	if events != null:
		events.player_revived.emit(index, reviver)
	return true


func is_dodging() -> bool:
	return _dodge_left > 0.0


## True while a hit must do nothing (the first INVULNERABLE_TIME of a dodge).
func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


## Cannot be hurt for `seconds` (at least what is left). Flow uses this for a
## wizard who joins mid-run. A downed wizard stays as it is.
func protect(seconds: float) -> void:
	if not _downed:
		_invulnerable_left = maxf(_invulnerable_left, seconds)


## True if a dodge pressed now would start.
func can_dodge() -> bool:
	return _dodge_left <= 0.0 and _cooldown_left <= 0.0


func _start_dodge(move: Vector2) -> void:
	_dodge_direction = move.normalized() if move != Vector2.ZERO else facing
	_dodge_left = DODGE_TIME
	_invulnerable_left = INVULNERABLE_TIME
	_cooldown_left = DODGE_COOLDOWN
	# The ghosts start on the wizard and grow out behind as the dash goes on.
	_trail.fill(global_position)
	_trail_timer = GHOST_INTERVAL
