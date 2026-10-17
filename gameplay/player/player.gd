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
## Light colour of each player's ramp, for the reticle. The single source is the
## player ramps in docs/STYLE.md; core has only the base colours (projectile manager).
const PLAYER_COLORS: Array[Color] = [
	Color("7fc0f0"), Color("f59ab8"), Color("8fd46a"), Color("c99af0"),
]
const OUTLINE_COLOR: Color = Color("14121f")
## Seconds a wizard who joins mid-run cannot be hurt (see `protect`).
const JOIN_PROTECTION: float = 2.0
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

## The input manager. Only tests set this, before adding the node; otherwise the
## "PlayerInput" autoload is used.
var input: InputManagerScript = null

## The event bus and the registry. Only tests set these, before adding the node;
## otherwise the "Events" and "Registry" autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null

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

var _dodge_left: float = 0.0
var _invulnerable_left: float = 0.0
var _cooldown_left: float = 0.0
var _dodge_direction: Vector2 = Vector2.ZERO
var _seen_dodge_presses: int = 0
var _downed: bool = false
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
	_sprite.texture = textures[index]


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
	if registry == null and in_tree:
		registry = get_node_or_null("/root/Registry") as RegistryScript
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
	if not aim.is_equal_approx(_drawn_aim):
		_drawn_aim = aim
		queue_redraw()


## A soft shadow under the feet and the aim reticle (a chevron in the player
## colour with an outline). No arrays are made: lines only.
func _draw() -> void:
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not _reticle_visible():
		return
	var tip: Vector2 = aim * RETICLE_DISTANCE
	var side: Vector2 = aim.orthogonal()
	var back: Vector2 = tip - aim * RETICLE_SIZE
	var color: Color = PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]
	draw_line(back + side * RETICLE_SIZE, tip, OUTLINE_COLOR, 3.0)
	draw_line(back - side * RETICLE_SIZE, tip, OUTLINE_COLOR, 3.0)
	draw_line(back + side * RETICLE_SIZE, tip, color, 1.0)
	draw_line(back - side * RETICLE_SIZE, tip, color, 1.0)


## True when _draw() shows the aim reticle: not while downed.
func _reticle_visible() -> bool:
	return not _downed and aim != Vector2.ZERO


## Fire the equipped spell now. Returns true if it fired. Does nothing when
## downed or without a spell.
func cast() -> bool:
	if _downed or spell == null:
		return false
	var spent: float = spell.cast(index, global_position, aim, mana)
	if spent == SpellBase.REFUSED:
		return false
	mana -= spent
	_announce_stats()
	if events != null:
		events.spell_cast.emit(index, spell.spell_id(), global_position, aim)
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
		queue_redraw()
		_dodge_left = 0.0
		_invulnerable_left = 0.0
		velocity = Vector2.ZERO
		if events != null:
			events.player_downed.emit(index)
	return true


## Bring a downed wizard back with REVIVE_HEALTH; `reviver` is the index of the
## teammate who did it. Returns false if the wizard was not downed.
func revive(reviver: int) -> bool:
	if not _downed:
		return false
	_downed = false
	queue_redraw()
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
