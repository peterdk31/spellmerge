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
## All timing runs in step(delta), so tests drive it with fixed deltas and no
## real-time waits. Nothing here allocates per frame.

const InputManagerScript := preload("res://core/input/input_manager.gd")

## Walking speed in pixels per second (the view is 640x360).
const MOVE_SPEED: float = 90.0
## Dash speed, and how long the dash lasts.
const DODGE_SPEED: float = 220.0
const DODGE_TIME: float = 0.25
## The wizard cannot be hurt this long from the start of a dodge (at most DODGE_TIME).
const INVULNERABLE_TIME: float = 0.125
## Seconds from the start of a dodge until the next one may start.
const DODGE_COOLDOWN: float = 0.625
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

## The way the wizard faces: the last move direction (unit length).
var facing: Vector2 = Vector2.DOWN

var _dodge_left: float = 0.0
var _invulnerable_left: float = 0.0
var _cooldown_left: float = 0.0
var _dodge_direction: Vector2 = Vector2.ZERO
var _seen_dodge_presses: int = 0


func _init() -> void:
	collision_layer = LAYER_PLAYERS
	collision_mask = LAYER_WALLS
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


## Show the idle texture for this player index on the `Sprite` node.
func apply_texture() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	if index < 0 or index >= textures.size():
		push_warning("Wizard %d: no texture for this player index." % index)
		return
	sprite.texture = textures[index]


func _ready() -> void:
	apply_texture()
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
		if input == null and is_inside_tree():
			push_warning("Wizard %d: the PlayerInput autoload is missing, so this wizard cannot move." % index)
	if input != null:
		_seen_dodge_presses = input.get_press_count(index, &"dodge")


func _physics_process(delta: float) -> void:
	step(delta)
	move_and_slide()


## Advance the wizard by `delta` seconds: read input, start a dodge, set
## `velocity`. The caller moves the body (_physics_process does).
func step(delta: float) -> void:
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


func is_dodging() -> bool:
	return _dodge_left > 0.0


## True while a hit must do nothing (the first INVULNERABLE_TIME of a dodge).
func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


## True if a dodge pressed now would start.
func can_dodge() -> bool:
	return _dodge_left <= 0.0 and _cooldown_left <= 0.0


func _start_dodge(move: Vector2) -> void:
	_dodge_direction = move.normalized() if move != Vector2.ZERO else facing
	_dodge_left = DODGE_TIME
	_invulnerable_left = INVULNERABLE_TIME
	_cooldown_left = DODGE_COOLDOWN
