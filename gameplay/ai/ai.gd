extends CharacterBody2D
## Enemy AI (M1 part 12): chase the nearest standing player, then one telegraphed
## attack. The script goes on the root of an enemy scene (content/enemies/ember_imp/
## ember_imp.tscn); the spawner sets `data` (the enemy's `EnemyBase` resource)
## before adding the node, like `index` on a wizard.
##
## States: CHASE (walk to the nearest player who is not downed), WINDUP (stand
## still; the telegraph shows and the aim is locked at its start, so a player can
## step aside), then the shot flies and RECOVER (stand still) before CHASE again.
## An enemy never targets "the player": every player in the `players` group (or
## in `targets`) is a candidate, indices 0-3, and a downed one is skipped.
##
## The attack is a shot from `core/projectiles` that hits wizards (LAYER_PLAYER);
## Combat turns its hit into damage through a hit profile for `ATTACK_TAG`.
## Health, hurt box and knockback live in `gameplay/combat`: _ready() registers the
## enemy there and step() adds `consume_knockback_step` to the velocity. Death is
## Combat's (it frees the node), so there is no death code here.
##
## Telegraph: an optional `Sprite` child flashes (`modulate`) and an optional `Telegraph` child
## (staffs F8b: a Sprite2D drawn by `telegraph.gdshader` in this folder, in Fire colours, its
## material local to the scene) turns toward the locked aim and shows. It runs from
## TELEGRAPH_START to the real reach of the next cast (`next_cast_reach`; the old attack's
## `attack_speed * attack_lifetime`), its lane as wide as what is coming plus a margin, and its
## dashes march, its arrowhead grows and it brightens with `telegraph_progress()`.
##
## Poses: with `windup_texture` set (a strip of 32 px frames), the `Sprite` shows it from the
## start of the windup and flips between its frames faster and faster (WINDUP_FLASHES), and
## goes brighter still for the last stretch (TELEGRAPH_LAST_FROM). With `hurt_texture` set,
## a hit on this enemy (`damage_dealt` with this node as target) shows it for HURT_TIME
## seconds, over the windup too. A hit never cancels the windup: the shot still comes,
## so the telegraph stays honest (knockback and Feel's flash and squash are Combat's and
## Feel's). An `AnimationPlayer` child is paused while a pose other than the idle shows.
## Nothing here allocates per frame. Retargeting runs every RETARGET_TIME seconds
## (staggered per enemy), at once when `player_downed` arrives or the current target
## is lost, and once at the first step; with no explicit `targets` it reads the
## `players` group then. With nobody to chase it looks only every RETARGET_TIME.
##
## Decoys and swaps (staffs B5): a decoy (`entities.gd`) within its lure range is chased
## before any wizard, and a decoy that breaks is dropped at once (it reads as downed). A swap
## card moves an enemy with `target_move_requested`; the enemy it names goes there at once and
## keeps its state.
##
## Staffs (staffs F8a, "Enemy staffs"): an enemy whose `data` has a staff and cards attacks by
## casting them like a wizard (`uses_staff`). It opens a caster row in `core/spells` when it is
## ready (`caster`) and closes it when it leaves the tree; the staff is compiled once per enemy
## type and installed as its staff 0; its body is its row's projectile target, so its own spells
## skip it; it tells the manager and the runtime where it stands and aims every step (orbits and
## beams follow it). It pays each cast from `mana` (`data.max_mana`, `data.mana_regen` a second,
## plus what siphon gives back), so a dear staff casts less often. The windup starts only when the
## next cast is ready (its delay nearly over and the mana there), so a telegraph is always followed
## by its cast; until then it holds where it stands. The telegraph's reach is the next cast's
## first carrier's (a shot's speed x life, a beam's length); a carrier that is not aimed (a nova,
## an orbit) shows only the pose and the flash.
##
## Moves (staffs F8c): the moves its own cards ask for (`caster_move_requested` with NO_PLAYER and
## a tag of its row) move it as they move a wizard: a dash goes from its staff tip to where the
## card says over the card's time, a hook and a swap pull it to a point, a recoil pushes it, all
## through `velocity` (so walls stop it); a teleport jumps there at once, stopping short of a
## wall and backing off until the body is clear. A dash, hook or teleport says where it ended
## (`caster_move_finished`), where its card's blast and `on expire` go off. A later move replaces
## one still running; a cast aims a move at the target, as it aims everything.
##
## Statuses: a chilled enemy walks and winds up slower, a frozen one stands still and its
## attack waits (`Combat.speed_factor`); knockback still moves it.
##
## All timing runs in step(delta), so tests drive it with fixed deltas.
## _physics_process() calls step() and then move_and_slide().

const EventsScript := preload("res://core/events/events.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

enum State { CHASE, WINDUP, RECOVER }
enum Pose { IDLE, WINDUP, HURT }

## The group every wizard is in (player.gd adds it).
const PLAYERS_GROUP: StringName = &"players"
## Hit profile tags of enemy shots start here, plus a number derived from the enemy
## id (see `attack_tag`), so two enemy types do not overwrite each other's damage.
## Tag 0 means "no tag"; the fire bolt will use other tags.
const ATTACK_TAG_BASE: int = 1000
const ATTACK_TAG_SPREAD: int = 100000
## Collision layers of this body (see player.gd's LAYER_PLAYERS): its own and the walls.
const LAYER_ENEMIES: int = 4
const LAYER_WALLS: int = 1
## The telegraph line starts this far from the enemy; its look at 0% and 100% progress.
const TELEGRAPH_START: float = 10.0
## The telegraph's lane is the hit width of what is coming plus this margin.
const TELEGRAPH_LANE_MARGIN: float = 8.0
## The telegraph sprite's region height (its texture's), with the lane in its middle.
const TELEGRAPH_HEIGHT: float = 32.0
## Seconds between looking for the nearest player again.
const RETARGET_TIME: float = 0.5
## `Sprite` modulate while the telegraph shows, and for its last part.
const TELEGRAPH_COLOR: Color = Color(1.6, 1.3, 1.3)
const TELEGRAPH_COLOR_LAST: Color = Color(2.0, 1.8, 1.5)
## Where the last part of the windup starts (0..1 progress): from here the sprite is drawn in
## TELEGRAPH_COLOR_LAST and holds its bright frame instead of flipping.
const TELEGRAPH_LAST_FROM: float = 0.8
## Windup frame flips before the last part: frame = floor(progress² × this) mod frames, so it
## starts slow and speeds up, to about 5 bright-dark cycles a second at most.
const WINDUP_FLASHES: float = 5.0
## Seconds the hurt pose shows after a hit.
const HURT_TIME: float = 0.25
## A teleport stops this far short of a wall, then backs off by steps of TELEPORT_BACKOFF until
## the body (BODY_RADIUS, about the hurt circle's) is clear (as a wizard's, gameplay/player).
const TELEPORT_CLEARANCE: float = 8.0
const TELEPORT_BACKOFF: float = 4.0
const BODY_RADIUS: float = 6.0
## Recoil pushes that can run at once (more in one step are added to the last).
const MAX_RECOILS: int = 4

## The enemy's numbers (speed, health, contact damage). Set before adding to the tree.
var data: EnemyBase = null
## Players to chase. Left empty, the `players` group is used.
var targets: Array = []

## Walk until a player is this close, then start the attack.
@export var attack_range: float = 90.0
## Seconds the telegraph shows before the shot.
@export var windup_time: float = 0.75
## Seconds standing still after the shot.
@export var recover_time: float = 1.0
@export var attack_damage: int = 10
## Shot speed in pixels per second and its life in seconds.
@export var attack_speed: float = 140.0
@export var attack_lifetime: float = 1.25
@export var attack_radius: float = 3.5
## Radius of the enemy's hurt box in pixels.
@export var hurt_radius: float = 11.0
## Where the hurt circle, the shots and the telegraph start, relative to the node (the feet).
## -12 and not the sprite's -14: a little below the sprite's centre, where the torso is.
## Shots are not clipped at the spawn point, so an imp pressed against a wall can shoot
## into it and the shot ends at once (the same as before for its feet).
@export var hurt_offset: Vector2 = Vector2(0.0, -12.0)
## Optional poses for the `Sprite`: strips of square frames (width / height frames).
@export var windup_texture: Texture2D = null
@export var hurt_texture: Texture2D = null

## The event bus, Combat, the projectile manager and the decoys. Only tests set these, before
## _ready(); otherwise the "Events", "Combat", "Projectiles" and "Entities" autoloads are used.
var events: EventsScript = null
var combat: CombatScript = null
var projectiles: ProjectileManagerScript = null
var entities: EntitiesScript = null
var spells: SpellsScript = null

var state: State = State.CHASE
## The player being chased, or null.
var target: Node2D = null
## Direction of the attack, locked when the windup starts (unit length).
var aim: Vector2 = Vector2.DOWN
## Hit profile tag of this enemy's shot, set in _ready() from `data.id`.
var attack_tag: int = ATTACK_TAG_BASE
## How often the players were looked up (tests count it).
var lookup_count: int = 0
## This enemy's caster row in `core/spells` while it casts a staff, else -1.
var caster: int = -1
## The mana it has to cast with (staffs F8a).
var mana: float = 0.0

## Each enemy type's staff, compiled once (EnemyBase -> CompiledStaff).
static var _compiled: Dictionary = {}

## The move a card asked for (dash, hook, swap): its mode, seconds left, velocity and tag.
var _move_mode: StringName = &""
var _move_left: float = 0.0
var _move_velocity: Vector2 = Vector2.ZERO
var _move_tag: int = 0
## Recoil pushes running: velocity and seconds left each.
var _recoil_velocity: PackedVector2Array = PackedVector2Array()
var _recoil_left: PackedFloat32Array = PackedFloat32Array()

var _state_left: float = 0.0
var _retarget_left: float = 0.0
var _retarget_offset: float = 0.0
var _looked: bool = false
## Instance id of `target` when it was chosen, or 0 for none.
var _target_id: int = 0
var _sprite: Sprite2D = null
var _telegraph: Sprite2D = null
var _animation: AnimationPlayer = null
var _idle_texture: Texture2D = null
var _idle_hframes: int = 1
## Seconds the hurt pose still shows.
var _hurt_left: float = 0.0
## The pose now on the sprite.
var _pose: Pose = Pose.IDLE


func _init() -> void:
	collision_layer = LAYER_ENEMIES
	collision_mask = LAYER_WALLS
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func _ready() -> void:
	_sprite = get_node_or_null("Sprite") as Sprite2D
	_animation = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _sprite != null:
		_idle_texture = _sprite.texture
		_idle_hframes = _sprite.hframes
	_telegraph = get_node_or_null("Telegraph") as Sprite2D
	if _telegraph != null:
		_telegraph.visible = false
		# Starts where the shot does (the body), whatever the scene says.
		_telegraph.position = hurt_offset
		_telegraph.centered = false
		_telegraph.region_enabled = true
		_fit_telegraph(maxf(attack_speed * attack_lifetime, TELEGRAPH_START), attack_radius)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if combat == null:
		combat = get_node_or_null("/root/Combat") as CombatScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	# Tests build enemies outside the tree, where absolute paths do not work.
	if entities == null and is_inside_tree():
		entities = get_node_or_null("/root/Entities") as EntitiesScript
	if spells == null and is_inside_tree():
		spells = get_node_or_null("/root/Spells") as SpellsScript
	if events != null and not events.target_move_requested.is_connected(_on_target_move_requested):
		events.target_move_requested.connect(_on_target_move_requested)
	if events != null and not events.player_downed.is_connected(_on_player_downed):
		events.player_downed.connect(_on_player_downed)
	if events != null and not events.damage_dealt.is_connected(_on_damage_dealt):
		events.damage_dealt.connect(_on_damage_dealt)
	if events != null and not events.caster_move_requested.is_connected(_on_caster_move_requested):
		events.caster_move_requested.connect(_on_caster_move_requested)
	_recoil_velocity.resize(MAX_RECOILS)
	_recoil_left.resize(MAX_RECOILS)
	if data == null:
		push_warning("Ai: no enemy data set, so this enemy stands still.")
	if combat != null:
		if data != null and not uses_staff():
			attack_tag = ATTACK_TAG_BASE + absi(hash([data.id, attack_damage])) % ATTACK_TAG_SPREAD
			combat.set_hit_profile(attack_tag, attack_damage, 0.0)
		if data != null:
			combat.register_enemy(self, data.max_health, hurt_radius, data.contact_damage, hurt_offset)
	_open_staff()
	# Spread retargeting over the half second so 200 enemies do not all look at once.
	_retarget_offset = RETARGET_TIME * float(get_instance_id() % 8) / 8.0
	_retarget_left = _retarget_offset


func _exit_tree() -> void:
	if events != null and events.target_move_requested.is_connected(_on_target_move_requested):
		events.target_move_requested.disconnect(_on_target_move_requested)
	if events != null and events.player_downed.is_connected(_on_player_downed):
		events.player_downed.disconnect(_on_player_downed)
	if events != null and events.damage_dealt.is_connected(_on_damage_dealt):
		events.damage_dealt.disconnect(_on_damage_dealt)
	if events != null and events.caster_move_requested.is_connected(_on_caster_move_requested):
		events.caster_move_requested.disconnect(_on_caster_move_requested)
	# Leaving the tree without being freed must not leave a target behind in Combat.
	if combat != null and is_instance_valid(combat):
		combat.unregister_enemy(self)
	close_staff()


## True when this enemy attacks by casting its staff (its data has a staff and cards).
func uses_staff() -> bool:
	return data != null and data.staff != null and not data.cards.is_empty()


## Open a caster row and install the staff (once, in `_ready`). With every row taken the
## enemy has no attack and only chases.
func _open_staff() -> void:
	if not uses_staff() or spells == null or caster >= 0:
		return
	caster = spells.open_enemy_caster()
	if caster < 0:
		push_warning("Ai: every enemy caster row is open, so %s casts nothing." % data.id)
		return
	var compiled: CompiledStaff = _compiled.get(data) as CompiledStaff
	if compiled == null:
		compiled = spells.compile_staff(data.cards, data.staff)
		_compiled[data] = compiled
	spells.install_staff(caster, 0, compiled)
	mana = data.max_mana
	if projectiles != null:
		projectiles.set_target_owner(self, caster)
		projectiles.set_anchor(caster, _position_of(self) + hurt_offset)
	if entities != null:
		entities.set_enemy(caster, self)


## Give the caster row back (the enemy left the tree or died): its spells in the air fly on; its
## decoys and familiars end where they are (F8d), before the row closes, so their ends still count.
func close_staff() -> void:
	if caster < 0:
		return
	if entities != null and is_instance_valid(entities):
		entities.enemy_gone(caster)
	if spells != null and is_instance_valid(spells):
		spells.close_enemy_caster(caster)
	if projectiles != null and is_instance_valid(projectiles):
		projectiles.clear_anchor(caster)
	caster = -1


## True when the next cast can leave the moment a windup started now would end: its delay is no
## longer than the windup and the mana is there.
func cast_ready() -> bool:
	if caster < 0 or spells == null:
		return false
	var cost: float = spells.next_cast_mana(caster, 0)
	if cost < 0.0:
		return false
	return spells.cooldown_left(caster, 0) <= windup_time and mana - spells.reserved_mana(caster) >= cost


## How far the next cast reaches along the aim, for the telegraph: its first carrier's flight
## (speed x life), a beam's or fissure's length, a rain's aim point; 0 for a carrier that is not
## aimed (a nova, an orbit, a decoy...), which shows no line.
func next_cast_reach() -> float:
	if caster < 0 or spells == null:
		return maxf(attack_speed * attack_lifetime, TELEGRAPH_START)
	return spells.next_cast_reach(caster, 0)


func _physics_process(delta: float) -> void:
	step(delta)
	move_and_slide()


## Advance the AI by `delta` seconds and set `velocity`. The caller moves the body
## (_physics_process does).
func step(delta: float) -> void:
	_retarget_left -= delta
	# Look on the timer, at the first step (staggered afterwards) or when the target
	# was just lost. With no target at all only the timer applies.
	# A freed target reads as null, so the id tells "never had one" from "lost it".
	var lost: bool = _target_id != 0 and not _is_valid_target(target)
	if _retarget_left <= 0.0 or lost or not _looked:
		_retarget_left = RETARGET_TIME if _looked else _retarget_offset
		_looked = true
		target = _find_target()
		_target_id = target.get_instance_id() if target != null else 0
	# Chill slows the walk and the attack timers, freeze stops them (Combat's `speed_factor`).
	var pace: float = combat.speed_factor(self) if combat != null else 1.0
	if caster >= 0:
		_step_staff(delta)
	match state:
		State.CHASE:
			_step_chase(pace)
		State.WINDUP:
			velocity = Vector2.ZERO
			_state_left -= delta * pace
			if _state_left <= 0.0:
				_attack()
			else:
				_update_telegraph()
		State.RECOVER:
			velocity = Vector2.ZERO
			_state_left -= delta * pace
			if _state_left <= 0.0:
				state = State.CHASE
	_hurt_left = maxf(_hurt_left - delta, 0.0)
	_update_sprite()
	_step_moves(delta)
	if combat != null:
		velocity += combat.consume_knockback_step(self, delta)


## True from the start of the windup until the shot leaves: the attack is coming.
func is_telegraphing() -> bool:
	return state == State.WINDUP


## 0.0 at the start of the telegraph, 1.0 when the shot leaves; 0.0 when not telegraphing.
func telegraph_progress() -> float:
	if state != State.WINDUP or windup_time <= 0.0:
		return 0.0
	return clampf(1.0 - _state_left / windup_time, 0.0, 1.0)


## Mana back, and where the caster stands and aims (its orbits circle it, its beams follow it).
## The aim follows the target while it chases; the windup locks it, and so does the recovery, so
## a beam it holds does not track a wizard who stepped aside.
func _step_staff(delta: float) -> void:
	mana = minf(mana + data.mana_regen * delta + spells.take_refund(caster), data.max_mana)
	var origin: Vector2 = _position_of(self) + hurt_offset
	if state == State.CHASE and target != null:
		var to_target: Vector2 = _position_of(target) - _position_of(self)
		if to_target != Vector2.ZERO:
			aim = to_target.normalized()
	if projectiles != null:
		projectiles.set_anchor(caster, origin)
	spells.set_aim(caster, origin, aim)


func _step_chase(pace: float) -> void:
	_show_telegraph(false)
	if target == null or data == null:
		velocity = Vector2.ZERO
		return
	var to_target: Vector2 = _position_of(target) - _position_of(self)
	if to_target.length_squared() <= attack_range * attack_range:
		if to_target != Vector2.ZERO:
			aim = to_target.normalized()
		if uses_staff() and not cast_ready():
			# In reach but the cast is not ready: hold, so the telegraph only ever shows a cast that comes.
			velocity = Vector2.ZERO
			return
		state = State.WINDUP
		_state_left = windup_time
		velocity = Vector2.ZERO
		_show_telegraph(true)
		return
	velocity = to_target.normalized() * data.move_speed * pace


func _attack() -> void:
	if caster >= 0:
		var spent: float = spells.cast_staff(caster, 0, _position_of(self) + hurt_offset, aim, mana - spells.reserved_mana(caster))
		if spent > 0.0:
			mana -= spent
	elif not uses_staff() and projectiles != null:
		projectiles.spawn(EventsScript.NO_PLAYER, _position_of(self) + hurt_offset, aim * attack_speed,
				attack_lifetime, attack_radius, ProjectileManagerScript.LAYER_PLAYER, 0, attack_tag)
	state = State.RECOVER
	_state_left = recover_time
	_show_telegraph(false)


## The telegraph from TELEGRAPH_START to `reach` along +X, its lane `radius` plus half the margin
## either side (its sprite's region and the shader's length and lane).
func _fit_telegraph(reach: float, radius: float) -> void:
	var length: float = maxf(reach - TELEGRAPH_START, 1.0)
	_telegraph.offset = Vector2(TELEGRAPH_START, -TELEGRAPH_HEIGHT * 0.5)
	_telegraph.region_rect = Rect2(0.0, 0.0, length, TELEGRAPH_HEIGHT)
	var material: ShaderMaterial = _telegraph.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(&"beam_length", length)
		material.set_shader_parameter(&"telegraph_lane", radius + TELEGRAPH_LANE_MARGIN * 0.5)


## How far the telegraph reaches now (0 when hidden), for tests.
func telegraph_reach() -> float:
	if _telegraph == null or not _telegraph.visible:
		return 0.0
	return TELEGRAPH_START + _telegraph.region_rect.size.x


func _show_telegraph(on: bool) -> void:
	if _telegraph != null:
		var reach: float = next_cast_reach() if on and caster >= 0 else 0.0
		if on and caster >= 0 and reach > TELEGRAPH_START:
			_fit_telegraph(reach, spells.next_cast_radius(caster, 0))
		# A cast that is not aimed (a nova, an orbit) shows no line: the pose and flash say it.
		_telegraph.visible = on and (caster < 0 or reach > TELEGRAPH_START)
		if on:
			_telegraph.rotation = aim.angle()
			_update_telegraph()
	if _sprite != null:
		_sprite.modulate = TELEGRAPH_COLOR if on else Color.WHITE


## Make the telegraph brighter, its dashes march and its arrowhead grow as the cast gets closer.
func _update_telegraph() -> void:
	var progress: float = telegraph_progress()
	if _sprite != null:
		_sprite.modulate = TELEGRAPH_COLOR_LAST if progress >= TELEGRAPH_LAST_FROM else TELEGRAPH_COLOR
	if _telegraph == null:
		return
	var material: ShaderMaterial = _telegraph.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(&"telegraph_progress", progress)


## True while the hurt pose shows (a hit landed in the last HURT_TIME seconds).
func is_hurt() -> bool:
	return _hurt_left > 0.0


## Which pose the sprite shows: the hurt one over the windup one over the idle strip. A pose
## without its texture is skipped.
func _update_sprite() -> void:
	if _sprite == null:
		return
	var pose: Pose = Pose.IDLE
	if _hurt_left > 0.0 and hurt_texture != null:
		pose = Pose.HURT
	elif state == State.WINDUP and windup_texture != null:
		pose = Pose.WINDUP
	if pose != _pose:
		_pose = pose
		match pose:
			Pose.HURT:
				_show_strip(hurt_texture)
			Pose.WINDUP:
				_show_strip(windup_texture)
			_:
				_sprite.hframes = _idle_hframes
				_sprite.texture = _idle_texture
				if _animation != null and _animation.is_inside_tree():
					_animation.play()
	if pose == Pose.WINDUP:
		var progress: float = telegraph_progress()
		if progress >= TELEGRAPH_LAST_FROM:
			_sprite.frame = _sprite.hframes - 1
		else:
			_sprite.frame = int(progress * progress * WINDUP_FLASHES) % _sprite.hframes


## Show a strip of square frames on the sprite and stop the idle animation.
func _show_strip(strip: Texture2D) -> void:
	_sprite.hframes = maxi(roundi(float(strip.get_width()) / maxf(float(strip.get_height()), 1.0)), 1)
	_sprite.texture = strip
	_sprite.frame = 0
	if _animation != null and _animation.is_inside_tree():
		_animation.pause()


func _on_damage_dealt(_player: int, target: Node, _amount: int, _position: Vector2) -> void:
	if target == self:
		_hurt_left = HURT_TIME
		_update_sprite()


func _find_target() -> Node2D:
	lookup_count += 1
	var here: Vector2 = _position_of(self)
	var decoy: Node2D = entities.lure(here) if entities != null else null
	if decoy != null:
		return decoy
	var best: Node2D = null
	var best_distance: float = INF
	var candidates: Array = targets
	if candidates.is_empty() and is_inside_tree():
		candidates = get_tree().get_nodes_in_group(PLAYERS_GROUP)
	for candidate: Variant in candidates:
		if not _is_valid_target(candidate):
			continue
		var wizard: Node2D = candidate as Node2D
		var distance: float = here.distance_squared_to(_position_of(wizard))
		if distance < best_distance:
			best_distance = distance
			best = wizard
	return best


## A freed player may still sit in `targets` or in `target`, hence the Variant.
func _is_valid_target(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	return not (node.has_method("is_downed") and node.is_downed())


## True while a card's dash, hook or swap is moving this enemy.
func is_moving() -> bool:
	return _move_left > 0.0


## A move its own card asked for (a tag of its caster row; the event names NO_PLAYER for an enemy).
func _on_caster_move_requested(player: int, mode: StringName, to: Vector2, seconds: float, tag: int) -> void:
	if caster < 0 or player != EventsScript.NO_PLAYER or not to.is_finite() or not SpellTag.is_spell_tag(tag) or SpellTag.caster_of(tag) != caster:
		return
	var muzzle: Vector2 = _position_of(self) + hurt_offset
	if mode == &"recoil":
		var push_time: float = maxf(seconds, 0.01)
		var free: int = _recoil_left.find(0.0)
		var at: int = free if free >= 0 else MAX_RECOILS - 1
		_recoil_velocity[at] += (to - muzzle) / push_time
		_recoil_left[at] = maxf(_recoil_left[at], push_time)
		return
	if mode != &"dash" and mode != &"teleport" and mode != &"hook" and mode != &"swap":
		return
	if _move_left > 0.0:
		_finish_move()
	if mode == &"teleport":
		_teleport(to, tag)
		return
	var time: float = maxf(seconds, 0.01)
	# A dash is measured from the staff tip, a pull (hook, swap) is to the point itself.
	var goal: Vector2 = _position_of(self) + (to - muzzle) if mode == &"dash" else to
	_move_mode = mode
	_move_left = time
	_move_velocity = (goal - _position_of(self)) / time
	_move_tag = tag


## Jump to where a teleport card aimed (`to` is measured from the staff tip), stopping short of
## the first wall and backing off until the body is clear, then say where it landed.
func _teleport(to: Vector2, tag: int) -> void:
	var start: Vector2 = _position_of(self)
	var goal: Vector2 = start + (to - (start + hurt_offset))
	if projectiles != null:
		var reached: Vector2 = projectiles.clip_to_walls(start, goal)
		if reached != goal:
			reached = reached.move_toward(start, TELEPORT_CLEARANCE)
		goal = reached
		while goal != start and projectiles.circle_blocked(goal, BODY_RADIUS):
			goal = goal.move_toward(start, TELEPORT_BACKOFF)
	_set_position(goal)
	if events != null:
		events.caster_move_finished.emit(EventsScript.NO_PLAYER, &"teleport", goal, tag)


## The running move and the recoil pushes set `velocity` (walls stop them, as `move_and_slide`
## does any walk); a move whose time is up says where it ended.
func _step_moves(delta: float) -> void:
	if _move_left > 0.0:
		# The last step is shortened, so a move goes exactly its distance.
		velocity = _move_velocity * minf(delta, _move_left) / delta
		_move_left -= delta
	elif _move_mode != &"":
		# Answered the step after its last, when the body has got there.
		_finish_move()
	for i in MAX_RECOILS:
		if _recoil_left[i] > 0.0:
			velocity += _recoil_velocity[i] * minf(delta, _recoil_left[i]) / delta
			_recoil_left[i] = maxf(_recoil_left[i] - delta, 0.0)
			if _recoil_left[i] == 0.0:
				_recoil_velocity[i] = Vector2.ZERO


## The move is over: say where (a swap says nothing; its blast went off at the target).
func _finish_move() -> void:
	var mode: StringName = _move_mode
	_move_left = 0.0
	_move_mode = &""
	_move_velocity = Vector2.ZERO
	if events != null and mode != &"swap" and mode != &"":
		events.caster_move_finished.emit(EventsScript.NO_PLAYER, mode, _position_of(self), _move_tag)


func _set_position(at: Vector2) -> void:
	if is_inside_tree():
		global_position = at
	else:
		position = at


## A swap card moved this enemy: it is there at once, its state and aim kept.
func _on_target_move_requested(_player: int, moved: Node, to: Vector2) -> void:
	if moved != self or not to.is_finite():
		return
	if is_inside_tree():
		global_position = to
	else:
		position = to


func _on_player_downed(player: int) -> void:
	# Only enemies chasing the downed wizard look again at once; the rest keep their
	# staggered timer, so a death does not make every enemy search in one frame.
	if is_instance_valid(target) and target.get("index") == player:
		_retarget_left = 0.0


func _position_of(node: Node2D) -> Vector2:
	return node.global_position if node.is_inside_tree() else node.position
