extends CharacterBody2D
## The wizard controller (M1 part 9: move and dodge). One instance per player,
## any index 0-3. It reads only its own player's input from `core/input` and
## never looks at another player, so nobody waits for anybody.
##
## The scene is content/wizard/base/wizard.tscn, with this script on its root.
## Set `index` before adding the node to the tree.
##
## Dash (staffs A6a): there is no dodge button any more. A `dash` card in a staff makes the
## spell runtime send `caster_move_requested(player, &"dash", to, seconds, tag)`; the wizard
## then dashes the way it walks (the way it faces when standing) as far and as long as asked,
## and sends `caster_move_finished` where it stops. A dash gives no invulnerability: shields
## do that (staffs B1, B3). `protect(seconds)` still makes the wizard unhurtable for a while (a
## wizard who joins mid-run), drawn translucent with a closing ring in its colour. Combat asks
## is_invulnerable() before damage.
##
## Moves (staffs B4): `teleport` jumps along the aim and stops at the first wall (`TELEPORT_CLEARANCE`
## short of it); `hook` and `swap` pull the wizard to a point over the time asked (like a dash that
## ignores the walk; it stops at walls); `recoil` pushes it back. A request is acted on when it
## comes, so a later dash, teleport, hook or swap replaces an earlier one (the replaced one is
## answered where the wizard is); the `recoil` requests of one step are added up first (so
## `mirror` and `recoil` cancel) and applied by the next `step`. A dash, teleport or hook answers
## `caster_move_finished`. Wizard statuses (`Combat.wizard_speed_factor`) slow or stop walking
## and dashing, and a hit's push (`Combat.consume_wizard_knockback`) is added to the movement.
## `mana_refund_requested` (siphon) gives mana back, up to MAX_MANA.
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
## body at hand height, not at the feet. The aim, the staff, the reticle and the
## shot share one line from the hand (aim_pivot()), so a shot flies through the
## mouse and the reticle sits on its path. Anything that aims at a point (the
## mouse now; aim assist or a targeted spell later) takes its direction from
## aim_at(point), never from the feet (global_position): a direction from the feet
## sends the shot past the point. Everything drawn along the aim is placed with
## aim_pivot(), muzzle_position() or reticle_position().
##
## Animation: the sprite plays an idle, a walk or a dash strip (frames of 32 px
## side by side, see docs/STYLE.md); _update_animation() picks it from the speed
## and the dodge. The body has no player colour; the hat is a second sprite in it
## (`Hat`), moved with the body's bob. The idle blinks, glances and breathes
## (IDLE_SEQUENCE, BREATH_STEPS). The staff is drawn above the sprite along the aim.
##
## Dash look: during a dodge the sprite stretches and leans along the dash and
## fading ghosts of it trail behind (drawn in _draw; no nodes or arrays made).
##
## Staffs (staffs A6a, docs/milestones/M2-staffs.md): four staffs, one per button: `staff_1` to
## `staff_4` cast staff 0 to 3 (RB, RT, LB, LT on a pad; owner, 2026-10-26). Each staff is a row of card
## ids, `staff.slots` long (`staff` is the StaffBase flow hands over: `starter` or `dev`),
## compiled and installed by `Spells`; the wizard reads no spell field. Holding a button casts
## that staff whenever it is ready; a press while it is not ready is remembered for
## INPUT_BUFFER seconds, so a tap just before its delay ends still fires. While a staff has a
## sustained (`hold`) card on, only a new press casts it (which switches it off), so a held
## button does not switch it on and off. Mana: what the wizard has minus what its sustained
## cards reserve (`mana_reserved`). A cast takes the mana returned, sends `spell_cast` (the
## carrier) and `staff_cast`, and plays the sound `cast` from `core/registry` (nothing on null).
##
## Building: `start_cards` (four lists of card ids, flow sets them) are built when the wizard
## enters the tree. `staff_change_requested` puts one card in one slot, `card_move_requested`
## moves or swaps cards between slots and staffs (a staff of -1 is the bag) and
## `staff_cards_requested` sets a whole staff (the radial builder). A change is only
## refused when the slot does not exist or the card is not in the `bag`; then `build_refused`
## says why. Every built staff is announced with `staff_changed(player, staff, plan)`, the plain
## view of `Spells.staff_view`. The `bag` holds the ids the player may build with (every card
## in the registry until M3's rewards fill it). Orbit shots circle the body: the anchor is
## pushed to the projectile manager each step and cleared when the wizard is downed or leaves.
##
## All timing runs in step(delta), so tests drive it with fixed deltas and no
## real-time waits. Nothing here allocates per frame.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

## Walking speed in pixels per second (the view is 640x360).
const MOVE_SPEED: float = 90.0
## A staff cast pressed this long (seconds) before the staff is ready still happens.
const INPUT_BUFFER: float = 0.15
## The four staffs and their buttons (0 RB, 1 RT, 2 LB, 3 LT).
const STAFF_COUNT: int = 4
const CAST_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## The ring of `protect` closes over this many seconds at most (it shows how much is left).
const INVULNERABLE_TIME: float = 2.0
## Sprite opacity and ring size while the wizard cannot be hurt.
const INVULNERABLE_ALPHA: float = 0.55
const INVULNERABLE_RING_RADIUS: float = 15.0
const INVULNERABLE_RING_HEIGHT: float = 14.0
const MAX_HEALTH: int = 100
## Health after a revive.
const REVIVE_HEALTH: int = 50
const MAX_MANA: float = 100.0
## Mana regained per second.
const MANA_REGEN: float = 10.0
## Seconds the aim holds after the right stick is let go.
const AIM_HOLD_TIME: float = 0.6
## A point closer than this (pixels) to the hand gives no direction (aim_at()).
const MOUSE_MIN_DISTANCE: float = 4.0
## The reticle: its distance from the wizard's hand and its size, in pixels.
const RETICLE_DISTANCE: float = 38.0
const RETICLE_SIZE: float = 4.0
## Aim x beyond which the sprite turns (and turns back): a band against flicker.
## The flip also mirrors the painted light; fine for the placeholder art.
const FLIP_BAND: float = 0.3
## The staff: its hand is HAND_HEIGHT above the feet; the tip (where shots start)
## is STAFF_REACH from the hand along the aim.
const HAND_HEIGHT: float = 10.0
const STAFF_REACH: float = 14.0
## A teleport that meets a wall ends this many pixels short of it, and is then backed off in
## steps of TELEPORT_BACKOFF until the body (radius BODY_RADIUS, as in wizard.tscn) is clear.
const TELEPORT_CLEARANCE: float = 8.0
const TELEPORT_BACKOFF: float = 4.0
const BODY_RADIUS: float = 6.0
## Most recoils that run at once (a push past this is dropped).
const MAX_RECOILS: int = 8
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
const IDLE_FPS: float = 6.0
const WALK_FPS: float = 8.0
const DASH_FPS: float = 16.0
## The idle strip has four poses: 0 eyes open, 1 eyes closed, 2 glance left, 3 glance
## right (on screen: the sprite is mirrored when the wizard faces left, so the two
## glances swap then). IDLE_SEQUENCE says which one shows at each idle step (8 s, then
## it loops): a blink, a glance left, a double blink and a glance right, so the wizard
## looks alive. Each player starts IDLE_STEP_OFFSET steps further in, so a group of
## wizards does not blink and glance on the same beat.
const IDLE_SEQUENCE: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0,
	0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 3, 3, 3, 3,
]
const IDLE_STEP_OFFSET: int = 13
## Breathing: for the second half of every BREATH_STEPS idle steps the body sits 1 px
## lower (the feet dip 1 px below the standing line; the shadow stays).
const BREATH_STEPS: int = 12
## How many pixels the body (and the hat) sit lower on each frame of the walk, and
## on each frame of the dash (a crouch, then lifted off the ground; the shadow stays).
const WALK_BOB: Array[int] = [1, 0, 1, 0]
const DASH_BOB: Array[int] = [1, -2]
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
## `card_move_requested`'s staff for the bag.
const BAG: int = -1
## Where orbit shots circle, above the feet (the same body offset as the hit circle).
const ORBIT_ANCHOR_OFFSET: Vector2 = Vector2(0.0, -12.0)
## Physics layers (the plan: 1 walls, 2 players, 3 enemies, 4 projectiles and
## hit boxes; see gameplay/player/README.md): players are on layer 2 and collide only with walls on layer 1,
## so wizards walk through each other and never block a teammate.
const LAYER_WALLS: int = 1
const LAYER_PLAYERS: int = 2

## The player index 0-3.
@export var index: int = 0

## One idle strip per player index. The scene lists the four strips (the body has no
## player colour, so they can be the same file); _ready() shows the one for `index` on
## the `Sprite` node.
@export var textures: Array[Texture2D] = []

## The walk and dash strips, one per player index like `textures`. An empty
## list (or a missing index) keeps the idle strip.
@export var walk_textures: Array[Texture2D] = []
@export var dash_textures: Array[Texture2D] = []

## The hat, one 32x32 picture per player index: the only part in the player colour.
## It is drawn by the `Hat` node under `Sprite`, which follows the body's bob.
@export var hat_textures: Array[Texture2D] = []

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

## The spell runtime. Only tests set this, before adding the node; otherwise the "Spells"
## autoload is used.
var spells: SpellsScript = null
## Combat, for the statuses and pushes on this wizard (the "Combat" autoload; tests set it).
var combat: CombatScript = null

## The staff every one of the four staffs is (its slots, delay and recharge). Flow sets it by
## build channel; without one a staff has 4 slots and casts with no delay of its own.
var staff: StaffBase = null
## The card ids built into staff 0 to 3 when the wizard enters the tree. Flow sets them.
var start_cards: Array = [[], [], [], []]

## The card ids this player may build with. Filled from the registry in `_ready`.
var bag: Array[StringName] = []

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
## The `Hat` node under `Sprite` (null without one).
var _hat: Sprite2D = null
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

## The dash in progress: seconds left, the way, the speed, and the tag of its card.
var _dash_left: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO
var _dash_speed: float = 0.0
## The homing of the dash in progress (`Spells.move_homing`), or null.
var _dash_homing: Homing = null
var _dash_tag: int = 0
## What the dash state is doing: &"dash", or &"hook"/&"swap" (a pull to a point, not walking).
var _dash_mode: StringName = &"dash"
## True when the move's time ran out in the last step: the next step answers it.
var _dash_done: bool = false
## Recoil asked for since the last step (pixels to move, the longest time asked), and the pushes
## being applied, each with its own velocity and seconds left (the first `_recoil_count` count).
var _recoil_pending: Vector2 = Vector2.ZERO
var _recoil_pending_seconds: float = 0.0
var _recoil_velocities: Array[Vector2] = []
var _recoil_lefts: PackedFloat32Array = PackedFloat32Array()
var _recoil_count: int = 0
var _invulnerable_left: float = 0.0
## Per staff: the button's press count last seen, and the seconds left in which a remembered
## press still counts (0 = none remembered).
var _seen_presses: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _buffer_left: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Mana the sustained cards of this wizard's staffs hold (from `mana_reserved`).
var _reserved: float = 0.0
## True while the invulnerable look (translucent sprite and ring) is shown.
var _invulnerable_look: bool = false
var _downed: bool = false
## How far a teammate's revive has got (0 to 1), from `revive_progress`; drawn as a ring.
var _revive_progress: float = 0.0
var _sound_player: AudioStreamPlayer = null
## The card ids of each staff, `slots` long (`&""` is an empty slot), and whether it built.
var _cards: Array = [[], [], [], []]
var _has_build: Array[bool] = [false, false, false, false]
## What the last `player_stats_changed` said, to send it only on a change.
var _sent_health: int = -1
var _sent_mana: int = -1


func _init() -> void:
	_recoil_velocities.resize(MAX_RECOILS)
	_recoil_lefts.resize(MAX_RECOILS)
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
	_hat = _sprite.get_node_or_null("Hat") as Sprite2D
	if _hat != null and index < hat_textures.size():
		_hat.texture = hat_textures[index]
	_set_bob(0)


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
	if is_dashing():
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
		_set_bob(DASH_BOB[mini(_sprite.frame, DASH_BOB.size() - 1)])
	elif _anim == Anim.WALK:
		_sprite.frame = step_index % _sprite.hframes
		_set_bob(WALK_BOB[_sprite.frame % WALK_BOB.size()])
	else:
		step_index += index * IDLE_STEP_OFFSET
		var pose: int = IDLE_SEQUENCE[step_index % IDLE_SEQUENCE.size()]
		if _faces_left and pose >= 2:
			pose = 5 - pose
		_sprite.frame = mini(pose, _sprite.hframes - 1)
		_set_bob(1 if step_index % BREATH_STEPS >= BREATH_STEPS / 2 else 0)


## Sit the body `pixels` lower than its place (the hat goes with it), or higher if negative.
func _set_bob(pixels: int) -> void:
	_sprite.offset = Vector2(0.0, float(pixels))
	if _hat != null:
		_hat.position = Vector2(0.0, float(pixels))


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
	if events != null and not events.heal_dealt.is_connected(_on_heal_dealt):
		events.heal_dealt.connect(_on_heal_dealt)
	if events != null and not events.revive_progress.is_connected(_on_revive_progress):
		events.revive_progress.connect(_on_revive_progress)
	if registry == null and in_tree:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if projectiles == null and in_tree:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if spells == null and in_tree:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	if combat == null and in_tree:
		combat = get_node_or_null("/root/Combat") as CombatScript
	_connect_build_events()
	_fill_bag()
	for at in STAFF_COUNT:
		var cards: Array[StringName] = []
		if at < start_cards.size() and start_cards[at] is Array:
			for id: Variant in start_cards[at]:
				cards.append(StringName(str(id)))
		set_staff(at, cards)
	if _overlay == null:
		_overlay = Node2D.new()
		_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay)
	if is_inside_tree() and _sound_player == null:
		_sound_player = AudioStreamPlayer.new()
		add_child(_sound_player)
	_forget_presses()
	_announce_stats()


## Listen again if the wizard is put back in the tree (_ready runs only once).
func _enter_tree() -> void:
	_connect_build_events()


func _connect_build_events() -> void:
	if events == null:
		return
	if not events.staff_change_requested.is_connected(_on_staff_change_requested):
		events.staff_change_requested.connect(_on_staff_change_requested)
	if not events.card_move_requested.is_connected(_on_card_move_requested):
		events.card_move_requested.connect(_on_card_move_requested)
	if not events.staff_cards_requested.is_connected(_on_staff_cards_requested):
		events.staff_cards_requested.connect(_on_staff_cards_requested)
	if not events.caster_move_requested.is_connected(_on_caster_move_requested):
		events.caster_move_requested.connect(_on_caster_move_requested)
	if not events.mana_reserved.is_connected(_on_mana_reserved):
		events.mana_reserved.connect(_on_mana_reserved)
	if not events.mana_refund_requested.is_connected(_on_mana_refund):
		events.mana_refund_requested.connect(_on_mana_refund)


## Stop listening to build requests (a wizard that left is freed a frame later) and stop
## the orbit shots that circled it.
func _exit_tree() -> void:
	if events != null:
		if events.staff_change_requested.is_connected(_on_staff_change_requested):
			events.staff_change_requested.disconnect(_on_staff_change_requested)
		if events.card_move_requested.is_connected(_on_card_move_requested):
			events.card_move_requested.disconnect(_on_card_move_requested)
		if events.staff_cards_requested.is_connected(_on_staff_cards_requested):
			events.staff_cards_requested.disconnect(_on_staff_cards_requested)
		if events.caster_move_requested.is_connected(_on_caster_move_requested):
			events.caster_move_requested.disconnect(_on_caster_move_requested)
		if events.mana_reserved.is_connected(_on_mana_reserved):
			events.mana_reserved.disconnect(_on_mana_reserved)
		if events.mana_refund_requested.is_connected(_on_mana_refund):
			events.mana_refund_requested.disconnect(_on_mana_refund)
	if projectiles != null:
		projectiles.clear_anchor(index)
	if spells != null:
		spells.clear_aim(index)


func _physics_process(delta: float) -> void:
	step(delta)
	move_and_slide()


## Advance the wizard by `delta` seconds: read input, cast staffs, run a dash, set
## `velocity`. The caller moves the body (_physics_process does).
func step(delta: float) -> void:
	if projectiles != null:
		if _downed:
			projectiles.clear_anchor(index)
		else:
			projectiles.set_anchor(index, global_position + ORBIT_ANCHOR_OFFSET)
	if _downed:
		if spells != null:
			# A downed wizard holds no beam.
			spells.clear_aim(index)
		velocity = Vector2.ZERO
		_clear_recoil()
		# Presses made while downed are not held against the wizard after a revive.
		_forget_presses()
		_update_invulnerable_look()
		return
	mana = minf(mana + MANA_REGEN * delta, MAX_MANA)
	_announce_stats()
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	for at in STAFF_COUNT:
		_buffer_left[at] = maxf(_buffer_left[at] - delta, 0.0)
	if _dash_done:
		# The last step of the move has been walked (the body moved after the last step call).
		_finish_dash()
	if input == null:
		# No input (only in tests): stand still, but a push still applies.
		velocity = _recoil_step(delta)
		_update_invulnerable_look()
		return
	var move: Vector2 = input.get_move(index)
	var captured: bool = input.is_captured(index)
	if captured and is_dashing():
		# An overlay opened: freeze, and end a dash in progress.
		_dash_left = 0.0
		_finish_dash()
	if move != Vector2.ZERO:
		facing = move.normalized()
	_update_aim(move, delta)
	if spells != null:
		# A beam this wizard cast follows the staff tip and the aim while it lives.
		var tip: Vector2 = muzzle_position()
		spells.set_aim(index, projectiles.clip_to_walls(global_position, tip) if projectiles != null else tip, aim)
	if _dash_look:
		_tick_trail(delta)
	var pace: float = combat.wizard_speed_factor(index) if combat != null else 1.0
	if is_dashing():
		if _dash_mode == &"dash" and _dash_homing != null:
			# A homing dash turns toward an enemy as it goes, as a homing shot does.
			_dash_direction = _dash_homing.steer(projectiles, index, global_position, _dash_direction, delta)
		velocity = _dash_direction * _dash_speed
		if _dash_mode == &"dash":
			velocity *= pace
		# The move lasts its whole time: it is answered by the next step, once walked.
		_dash_left = maxf(_dash_left - delta, 0.0)
		_dash_done = _dash_left <= 0.0
		if _dash_done:
			_apply_dash_look(false)
	else:
		velocity = move * MOVE_SPEED * pace
	velocity += _recoil_step(delta)
	if combat != null:
		velocity += combat.consume_wizard_knockback(index, delta)
	_update_animation(delta)
	_update_invulnerable_look()
	# Count presses rather than asking "just pressed": a tap released again before this
	# frame is not lost. The staff buttons are hidden while an overlay is open (captured), so
	# a menu tap never casts, and a press made meanwhile is not held against the player later.
	for at in STAFF_COUNT:
		var presses: int = input.get_press_count(index, CAST_ACTIONS[at])
		var fresh: bool = presses != _seen_presses[at]
		_seen_presses[at] = presses
		if captured:
			_buffer_left[at] = 0.0
			continue
		if fresh:
			_buffer_left[at] = INPUT_BUFFER
		if not _has_build[at] or spells == null:
			continue
		# A held button casts whenever the staff is ready, except while it holds a sustained
		# card: then only a new press casts, which switches it off.
		var held: bool = input.is_action_pressed(index, CAST_ACTIONS[at]) and not spells.is_holding(index, at)
		if (held or _buffer_left[at] > 0.0) and cast_staff(at):
			_buffer_left[at] = 0.0


## Take the press counts as they are now, so no press made before counts later.
func _forget_presses() -> void:
	for at in STAFF_COUNT:
		_buffer_left[at] = 0.0
		if input != null:
			_seen_presses[at] = input.get_press_count(index, CAST_ACTIONS[at])


## Choose `aim` for this step: the right stick, else the mouse (keyboard player),
## else the held stick aim, else the move direction.
func _update_aim(move: Vector2, delta: float) -> void:
	var stick: Vector2 = input.get_aim(index)
	if stick != Vector2.ZERO:
		aim = stick
		_aim_hold_left = AIM_HOLD_TIME
	elif input.is_mouse_aiming(index):
		var toward: Vector2 = aim_at(_mouse_world())
		if toward != Vector2.ZERO:
			aim = toward
		_aim_hold_left = 0.0
	else:
		_aim_hold_left = maxf(_aim_hold_left - delta, 0.0)
		if _aim_hold_left <= 0.0 and move != Vector2.ZERO:
			aim = move.normalized()
	_refresh_look()


## The hand: the point the aim, the staff, the reticle and the shot line up from.
func aim_pivot() -> Vector2:
	return global_position + Vector2(0.0, -HAND_HEIGHT)


## The aim (unit length) for a shot that flies through `point` (world position):
## measured from the hand, so the shot from muzzle_position() passes `point`.
## Vector2.ZERO when `point` is within MOUSE_MIN_DISTANCE of the hand.
func aim_at(point: Vector2) -> Vector2:
	var to_point: Vector2 = point - aim_pivot()
	if to_point.length() < MOUSE_MIN_DISTANCE:
		return Vector2.ZERO
	return to_point.normalized()


## Where shots start: the tip of the staff, in front of the wizard at hand height.
func muzzle_position() -> Vector2:
	return aim_pivot() + aim * STAFF_REACH


## Where the reticle's point is drawn, on the line of the shot.
func reticle_position() -> Vector2:
	return aim_pivot() + aim * RETICLE_DISTANCE


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
		if _hat != null:
			_hat.flip_h = _faces_left
	var dashing: bool = is_dashing() and not _downed
	if dashing or _dash_look:
		_apply_dash_look(dashing)
	if not aim.is_equal_approx(_drawn_aim):
		_drawn_aim = aim
		_redraw()


## Show or hide the invulnerable look when the state changes; while it shows, the
## closing ring is redrawn every step.
func _update_invulnerable_look() -> void:
	var now: bool = is_invulnerable() and not _downed
	if not now and not _invulnerable_look:
		return
	_invulnerable_look = now
	if _sprite != null:
		_sprite.modulate = Color(1.0, 1.0, 1.0, INVULNERABLE_ALPHA if now else 1.0)
	_redraw()


## Redraw the parts below the sprite (shadow, ghosts) and the overlay above it.
func _redraw() -> void:
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


## The sprite scale of a dash: stretched along the dominant axis of the dash.
func _dash_scale() -> Vector2:
	if absf(_dash_direction.x) >= absf(_dash_direction.y):
		return DASH_STRETCH
	return Vector2(DASH_STRETCH.y, DASH_STRETCH.x)


## Lean in radians, into the dash. A node's rotation is not mirrored by flip_h,
## so the sign needs no care for a sprite that faces left.
func _dash_lean() -> float:
	return clampf(_dash_direction.x, -1.0, 1.0) * DASH_LEAN


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
	_draw_invulnerable_ring()
	_draw_staff()
	var tip: Vector2 = reticle_position() - global_position
	var side: Vector2 = aim.orthogonal()
	var back: Vector2 = tip - aim * RETICLE_SIZE
	var color: Color = PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]
	_overlay.draw_line(back + side * RETICLE_SIZE, tip, OUTLINE_COLOR, 3.0)
	_overlay.draw_line(back - side * RETICLE_SIZE, tip, OUTLINE_COLOR, 3.0)
	_overlay.draw_line(back + side * RETICLE_SIZE, tip, color, 1.0)
	_overlay.draw_line(back - side * RETICLE_SIZE, tip, color, 1.0)


## A ring round the body that closes as the invulnerable time runs out.
func _draw_invulnerable_ring() -> void:
	if not _invulnerable_look:
		return
	var left: float = clampf(_invulnerable_left / INVULNERABLE_TIME, 0.0, 1.0)
	var centre: Vector2 = Vector2(0.0, -INVULNERABLE_RING_HEIGHT)
	var color: Color = PLAYER_COLORS[clampi(index, 0, PLAYER_COLORS.size() - 1)]
	var end: float = -PI * 0.5 + TAU * left
	_overlay.draw_arc(centre, INVULNERABLE_RING_RADIUS, -PI * 0.5, end, 24, OUTLINE_COLOR, 4.0)
	_overlay.draw_arc(centre, INVULNERABLE_RING_RADIUS, -PI * 0.5, end, 24, color, 2.0)


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
		var shade: Color = Color(tint, GHOST_ALPHAS[i])
		draw_texture_rect_region(texture, Rect2(-size * 0.5 + _sprite.offset, size), source, shade)
		if _hat != null and _hat.texture != null:
			draw_texture_rect_region(_hat.texture, Rect2(-size * 0.5 + _hat.position, size), Rect2(Vector2.ZERO, size), shade)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The staff: the staff art turned along the aim with the hand on the wizard
## (a plain line without the art), and a gem in the player colour at the tip.
func _draw_staff() -> void:
	# The same points the shot uses, in the overlay's space (the wizard's).
	var hand: Vector2 = aim_pivot() - global_position
	var tip: Vector2 = muzzle_position() - global_position
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


## True when staff `at` (0-3) has a build that can cast.
func has_staff(at: int) -> bool:
	return spells != null and at >= 0 and at < STAFF_COUNT and _has_build[at]


## The card ids of staff `at` as a copy, one per slot (`&""` for an empty slot).
func cards_of(at: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if at >= 0 and at < STAFF_COUNT:
		out.assign(_cards[at])
	return out


## How many slots every staff has.
func slot_count() -> int:
	return staff.slots if staff != null else SpellLimits.STAFFS


## Build `cards` (card ids by slot) into staff `at` (0-3): cut or padded to the staff's slots,
## compiled and installed by `Spells`, and announced with `staff_changed`. Nothing is refused
## for what the cards do; an empty staff simply casts nothing. Returns false only for a staff
## that does not exist or without the spell runtime.
func set_staff(at: int, cards: Array[StringName]) -> bool:
	if spells == null or at < 0 or at >= STAFF_COUNT:
		return _refuse("There is no such staff.")
	var row: Array[StringName] = []
	for slot in slot_count():
		row.append(cards[slot] if slot < cards.size() else &"")
	_cards[at] = row
	_has_build[at] = spells.install_staff(index, at, spells.compile_staff(row, _staff_or_default())) != 0
	if events != null:
		events.staff_changed.emit(index, at, spells.staff_view(row, _staff_or_default()))
	return true


## The staff the cards sit in: `staff`, or a plain one of 4 slots when flow set none.
func _staff_or_default() -> StaffBase:
	if staff != null:
		return staff
	var plain := StaffBase.new()
	plain.slots = SpellLimits.STAFFS
	plain.cast_delay = 0.0
	plain.recharge = 0.0
	return plain


func _refuse(reason: String) -> bool:
	if events != null:
		events.build_refused.emit(index, reason)
	return false


func _fill_bag() -> void:
	bag.clear()
	if registry == null:
		return
	for id: StringName in registry.get_ids(&"spells"):
		if registry.get_resource(&"spells", id) is SpellComponent:
			bag.append(id)
	if events != null:
		events.bag_changed.emit(index, bag.duplicate())


## A builder asked to put `card_id` into `slot` of staff `at` (`&""` empties it).
func _on_staff_change_requested(player: int, at: int, slot: int, card_id: StringName) -> void:
	if player != index:
		return
	if at < 0 or at >= STAFF_COUNT or slot < 0 or slot >= slot_count():
		_refuse("There is no such slot.")
		return
	if card_id != &"" and not bag.has(card_id):
		_refuse("You do not have that card.")
		return
	var row: Array[StringName] = cards_of(at)
	row[slot] = card_id
	set_staff(at, row)


## A builder asked to set every slot of staff `at` at once (`cards` by slot; fewer than the
## staff's slots empties the rest). Refused, and nothing changes, for a staff that does not
## exist, more cards than slots, or a card not in the `bag`.
func _on_staff_cards_requested(player: int, at: int, cards: Array[StringName]) -> void:
	if player != index:
		return
	if at < 0 or at >= STAFF_COUNT or cards.size() > slot_count():
		_refuse("There is no such slot.")
		return
	for card_id in cards:
		if card_id != &"" and not bag.has(card_id):
			_refuse("You do not have that card.")
			return
	set_staff(at, cards)


## A builder asked to move a card: from a slot of one staff to a slot of another (or the same),
## swapping with what is there; from the bag (`from_staff` BAG, `from_slot` the bag index) it is
## put in, and to the bag (`to_staff` BAG) the slot is emptied.
func _on_card_move_requested(player: int, from_staff: int, from_slot: int, to_staff: int, to_slot: int) -> void:
	if player != index:
		return
	var slots: int = slot_count()
	var from_ok: bool = (from_staff == BAG and from_slot >= 0 and from_slot < bag.size()) or (from_staff >= 0 and from_staff < STAFF_COUNT and from_slot >= 0 and from_slot < slots)
	var to_ok: bool = to_staff == BAG or (to_staff >= 0 and to_staff < STAFF_COUNT and to_slot >= 0 and to_slot < slots)
	if not from_ok or not to_ok:
		_refuse("There is no such slot.")
		return
	if from_staff == BAG:
		if to_staff != BAG:
			_on_staff_change_requested(index, to_staff, to_slot, bag[from_slot])
		return
	if to_staff == BAG:
		_on_staff_change_requested(index, from_staff, from_slot, &"")
		return
	var moving: StringName = _cards[from_staff][from_slot]
	var there: StringName = _cards[to_staff][to_slot]
	var source: Array[StringName] = cards_of(from_staff)
	source[from_slot] = there
	if from_staff == to_staff:
		source[to_slot] = moving
		set_staff(from_staff, source)
		return
	var target: Array[StringName] = cards_of(to_staff)
	target[to_slot] = moving
	set_staff(from_staff, source)
	set_staff(to_staff, target)


func _on_mana_reserved(player: int, amount: float) -> void:
	if player == index:
		_reserved = maxf(amount, 0.0)


## Siphon gives mana back (never above MAX_MANA).
func _on_mana_refund(player: int, amount: float) -> void:
	if player != index or _downed or not is_finite(amount) or amount <= 0.0:
		return
	mana = minf(mana + amount, MAX_MANA)
	_announce_stats()


## Mana a cast may use now: what the wizard has, minus what sustained cards hold.
func free_mana() -> float:
	return maxf(mana - _reserved, 0.0)


## Cast staff `at` (0-3) now. Returns true if it cast (or switched its sustained cards off).
## Does nothing when downed or when the staff has no build.
func cast_staff(at: int) -> bool:
	if _downed or not has_staff(at):
		return false
	var origin: Vector2 = muzzle_position()
	if projectiles != null:
		# A staff tip behind a wall: the shot starts at the wall and ends on it
		# (the manager takes no pool slot for a shot that starts inside a wall).
		origin = projectiles.clip_to_walls(global_position, origin)
	var spent: float = spells.cast_staff(index, at, origin, aim, free_mana())
	if spent == SpellsScript.REFUSED:
		return false
	mana -= spent
	_announce_stats()
	if events != null:
		var form: StringName = spells.last_form(index, at)
		if form != &"":
			events.spell_cast.emit(index, form, origin, aim)
		events.staff_cast.emit(index, at, origin, aim)
		events.wizard_cast.emit(index, self)
	_play_cast_sound()
	return true


## A card of this wizard asked to move it (staffs A6a, B4). A dash goes the way the wizard walks
## (or faces), a teleport jumps, a hook or swap pulls it to a point, a recoil pushes it back.
## Anything but a recoil replaces the move in progress, which is answered where the wizard is.
func _on_caster_move_requested(player: int, mode: StringName, to: Vector2, seconds: float, tag: int) -> void:
	if player != index or _downed or not to.is_finite():
		return
	if mode == &"recoil":
		_recoil_pending += to - muzzle_position()
		_recoil_pending_seconds = maxf(_recoil_pending_seconds, maxf(seconds, 0.01))
		return
	if mode != &"dash" and mode != &"teleport" and mode != &"hook" and mode != &"swap":
		return
	if is_dashing() or _dash_done:
		_finish_dash()
	if mode == &"teleport":
		_teleport(to, tag)
		return
	var time: float = maxf(seconds, 0.01)
	_dash_mode = mode
	if mode == &"dash":
		_dash_direction = facing
		if input != null and input.get_move(index) != Vector2.ZERO:
			_dash_direction = input.get_move(index).normalized()
		_dash_speed = (to - muzzle_position()).length() / time
		_dash_homing = spells.move_homing(index) if spells != null else null
	else:
		var pull: Vector2 = to - global_position
		_dash_direction = pull.normalized()
		_dash_speed = pull.length() / time
	_dash_left = time
	_dash_tag = tag
	# The ghosts start on the wizard and grow out behind as the dash goes on.
	_trail.fill(global_position)
	_trail_timer = GHOST_INTERVAL


## Jump to where a teleport card aimed (`to` is measured from the staff tip), stopping short of
## the first wall, then backing off along the path until the whole body is clear of walls and
## inside the room (or staying put), and say where the wizard landed.
func _teleport(to: Vector2, tag: int) -> void:
	var start: Vector2 = global_position
	var goal: Vector2 = start + (to - muzzle_position())
	if projectiles != null:
		var reached: Vector2 = projectiles.clip_to_walls(start, goal)
		if reached != goal:
			reached = reached.move_toward(start, TELEPORT_CLEARANCE)
		goal = reached
		while goal != start and projectiles.circle_blocked(goal, BODY_RADIUS):
			goal = goal.move_toward(start, TELEPORT_BACKOFF)
	global_position = goal
	if events != null:
		events.caster_move_finished.emit(index, &"teleport", goal, tag)


## The move ended: say where, so its card can go off there (blast, a trigger; staffs B2). A swap
## sends nothing (its blast goes off at the target).
func _finish_dash() -> void:
	_dash_left = 0.0
	_dash_done = false
	if events != null and _dash_mode != &"swap":
		events.caster_move_finished.emit(index, _dash_mode, global_position, _dash_tag)


## The recoil asked for since the last step becomes a push of that distance over the time asked,
## which ends on its own time; returns the velocity of all pushes to add now (a push's last step
## is shortened, so each moves exactly its distance).
func _recoil_step(delta: float) -> Vector2:
	if _recoil_pending != Vector2.ZERO and _recoil_count < MAX_RECOILS:
		_recoil_velocities[_recoil_count] = _recoil_pending / _recoil_pending_seconds
		_recoil_lefts[_recoil_count] = _recoil_pending_seconds
		_recoil_count += 1
	_recoil_pending = Vector2.ZERO
	_recoil_pending_seconds = 0.0
	var total: Vector2 = Vector2.ZERO
	var at: int = 0
	while at < _recoil_count:
		var left: float = _recoil_lefts[at]
		total += _recoil_velocities[at] * minf(left, delta) / maxf(delta, 0.0001)
		left -= delta
		if left <= 0.0:
			# Done: the last push takes its place.
			_recoil_count -= 1
			_recoil_velocities[at] = _recoil_velocities[_recoil_count]
			_recoil_lefts[at] = _recoil_lefts[_recoil_count]
			continue
		_recoil_lefts[at] = left
		at += 1
	return total


func _clear_recoil() -> void:
	_recoil_pending = Vector2.ZERO
	_recoil_pending_seconds = 0.0
	_recoil_count = 0


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


func _on_heal_dealt(_player: int, target: Node, amount: int, _position: Vector2) -> void:
	if target == self:
		heal(amount)


## Gain `amount` health, up to MAX_HEALTH. Ignored while downed (a revive is the way back).
## Returns true if any health was added.
func heal(amount: int) -> bool:
	if _downed or amount <= 0 or health >= MAX_HEALTH:
		return false
	health = mini(health + amount, MAX_HEALTH)
	_announce_stats()
	return true


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
		_dash_left = 0.0
		_dash_done = false
		_clear_recoil()
		_invulnerable_left = 0.0
		velocity = Vector2.ZERO
		_revive_progress = 0.0
		_update_invulnerable_look()
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


func is_dashing() -> bool:
	return _dash_left > 0.0


## True while a hit must do nothing (`protect`, for a wizard who just joined).
func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


## Cannot be hurt for `seconds` (at least what is left). Flow uses this for a
## wizard who joins mid-run. A downed wizard stays as it is.
func protect(seconds: float) -> void:
	if not _downed:
		_invulnerable_left = maxf(_invulnerable_left, seconds)
