extends Node
## Flow, the M1 slice (autoload `Flow`): starts the arena, spawns the fixed wave,
## announces `room_entered` and `room_cleared`, and restarts the room when every
## player is down. M3 replaces it with the real room sequence, door voting and
## run lifecycle.
##
## Starting: the main menu sends `play_requested(player)` and nothing else. Flow
## asks `core/registry` for the room (`rooms` / `arena_01`) and the enemy, checks that
## the start recipes compile, builds one `Node2D` world (room scene, a wizard for every joined player,
## the wave, a camera) and makes it the current scene, so the menu goes away. The
## whole thing is built in the same frame, far inside the 10 seconds allowed.
##
## Players: one wizard for every player slot that has a device (`core/input`), so
## 1-4 players. A wizard is an actor (actors G7): the wizard scene, seated with
## `PlayerController.seat_wizard` (its seat, its ramp, its staffs) before it is added; its
## Downed component downs, revives and protects it, and its hurtbox registers it with Combat.
## The keyboard joins slot 0 if the Play button was pressed with the mouse and nobody is
## joined there. Joining and leaving mid-run: `coop` sends
## `player_joined` / `player_left` and Flow adds a wizard at the room's spawn for
## that slot, or removes it (the run goes on; nobody waits for anyone).
##
## Waves: wave 1 is WAVE (sized for four players); each wave after it has
## WAVE_GROWTH more enemies, up to WAVE_MAX, from the same spawns and with the same
## single enemy type. `wave_started(wave)` is sent as each begins. `room_cleared`
## is sent when the last enemy of a wave has died, followed by `build_break_started`;
## BUILD_BREAK seconds later, whoever is still building, the next wave stands in the same room (the world is kept; shots in flight are
## cleared) and every downed wizard is back up, so a long run is "how many waves".
## `difficulty` scales this properly in M3.
##
## Restart: when every wizard is down, a timer of RESTART_DELAY seconds runs, then
## a fresh world replaces the old one: new wizards at full health, wave 1, no
## projectiles left, and `Spells` cleared (every cooldown and build is forgotten; each
## new wizard builds its start staffs again).
##
## Staffs (staffs A6a, docs/milestones/M2-staffs.md; living staffs H3; owner 2026-11-01: one
## staff file per setup, used as it is): every wizard gets the four staffs of its run's mode
## (`staffs_for_mode`), straight from the registry under `wizard`, never copied or changed: in
## Play and the horde the four basic staffs STARTER_HEADS (`content/wizard/staffs/`, one per
## button, each its own head), in the sandbox four times the `dev` staff (DEV_STAFF: 20 slots,
## no delay, practically infinite mana). The build channel plays no part. With them the mode's
## cards (`start_cards_for_mode`; Play's `start_cards`: A `dash`, X `fire bolt`, Y and B empty),
## which the wizard builds itself; flow never touches a spell.
##
## The intro (living staffs H6, `intro.gd`): on a new save (`save`, a `SaveFile`, has no
## INTRO_SEEN flag) Play shows the intro first (state INTRO): one staff dropped per joined player,
## skippable by any of them; when it ends or is skipped the save is marked and the run starts.
## It plays only for people: off (`intro_enabled` false) when a test script is the main loop or
## the game was started with user arguments (the 4-bot test, the stress run, the timing run).
##
## Loading (owner, 2026-10-29): Play, Sandbox and Horde first do the work that must be ready before a
## room (`play_tasks`, LoadTasks) behind the loading screen (state LOADING), through
## `core/loading` (the autoload `Loading`, which sends the events the HUD's screen is drawn from);
## then the intro or the run starts. Today that work is the shader warm-up
## (`core/projectiles/shader_warmup.gd`), once a session; with nothing to do Play starts at once.
## To load something more before playing, add a LoadTask in `play_tasks`. It is off
## (`loading_enabled` false) only when a test script is the main loop; the automated runs (the
## four-bot and stress runs) load like a player, and wait for `room_entered`.
##
## Sandbox (staffs B7, docs/milestones/M2-staffs.md, "The sandbox"): `sandbox_requested` (the
## main menu's Sandbox button, in `dev` and `preview` builds) starts a run in the sandbox room
## (`sandbox`): no waves, the training dummy and the shooting dummy at the room's
## `dummy_spawns` (more spawns stand more training dummies, a group to try homing, pierce and
## spreads on), and `sandbox_changed(true)` so the HUD shows the sandbox page. The page sends
## `sandbox_action_requested`: `imp_wave` adds a wave of imps (wave 1's size, while fewer than
## WAVE_MAX are up), `reset_dummies` puts fresh dummies back. Clearing the imps starts no build
## break. When every wizard is down, after RESTART_DELAY they all stand up where they are and
## keep their staffs, instead of a restart. Its wizards hold four `dev` staffs and start with
## `sandbox_cards` (SANDBOX_START_CARDS), not `start_cards`: Play's A and X, and two showcase
## builds on Y (the most shots) and B (a decoy turret).
##
## Modes: `mode` says which run this is: MODE_WAVES (Play), MODE_SANDBOX (above) or MODE_HORDE.
##
## Horde (docs/milestones/horde.md, H2): `horde_requested` (the main menu's Horde button, in every
## build) loads like Play (no intro) and starts a run in the room `horde` (HORDE_ROOM_ID): a wizard
## per joined player, no waves and no dummies; every wizard holds the four basic staffs, as in
## Play, with
## HORDE_START_CARDS (a dash staff and a swing staff). `room_entered(&"horde")` is followed by `horde_started(world)`. Flow spawns no
## enemy here: the director (`gameplay/horde`) does, under its own node. When every wizard is down,
## after HORDE_RESTART_DELAY (once started, a join does not call it off) a fresh world stands and
## `horde_started` is sent again. `horde_ended` is sent when a horde run stops (`stop_run`) or
## a run of another mode replaces it.
##
## All timing runs in step(delta), so tests drive it with fixed deltas.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const DownedScript := preload("res://gameplay/player/downed.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const DefaultWizardScene: PackedScene = preload("res://content/wizard/base/wizard.tscn")
const IntroScript := preload("res://gameplay/flow/intro.gd")
const LoadingScript := preload("res://core/loading/loading.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const LoadTask := preload("res://core/loading/load_task.gd")

const PLAYER_SLOTS: int = 4
## Registry folders, and the ids of the M1 content a run uses unless `room_id_to_play`,
## `enemy_id_to_play` say otherwise.
const ROOM_FOLDER: StringName = &"rooms"
const DEFAULT_ROOM_ID: StringName = &"arena_01"
const ENEMY_FOLDER: StringName = &"enemies"
const DEFAULT_ENEMY_ID: StringName = &"ember_imp"
## The two spells every wizard starts with: A is a fire bolt (M1's bolt plus burn), B a plain bolt.
## The cards each staff starts with: A, X, Y, B (the owner's choice, 2026-10-26).
const DEFAULT_START_CARDS: Array = [[&"dash"], [&"fire", &"bolt"], [], []]
## The cards a horde run starts with instead (owner, 2026-10-31): RB a dash staff, RT a swing staff.
const HORDE_START_CARDS: Array = [[&"dash"], [&"swing"], [], []]
## The cards a sandbox run starts with (owner, 2026-11-01: two showcase builds of the trigger
## tree on Y and B, to read in the builder's tree and try on the dummies). A and X as Play's.
## Y, the most shots: a fire nova split three times (216 shots) whose every shot, when it ends,
## fires a frost nova split three times (216 each): far past the projectile cap (3000 on
## desktop), which it holds for about three seconds; 67.5 mana. Two payload levels only: a
## third would queue a million shots, minutes of backlog at `SpellLimits.FIRE_SHOTS_PER_STEP`.
## B, a decoy turret: every 0.5 s it fires a homing fire, frost and lightning bolt (the
## lightning one sets off a chaining lightning atom on hit), and when it is hurt a void nova
## with a blast; 34.6 mana, every card used.
const SANDBOX_START_CARDS: Array = [
	[&"dash"],
	[&"fire", &"bolt"],
	[&"on_expire", &"fire", &"split", &"split", &"split", &"nova", &"frost", &"split", &"split", &"split", &"nova"],
	[&"timer", &"on_hurt", &"decoy", &"triple", &"homing", &"fire", &"bolt", &"homing", &"frost", &"bolt",
		&"on_hit", &"homing", &"lightning", &"bolt", &"chain", &"lightning", &"atom", &"void", &"blast", &"nova"],
]
## The sandbox room, and the dummies it stands at its `dummy_spawns` (in this order; every
## spawn after these stands another of the first, `dummy_id`).
const SANDBOX_ROOM_ID: StringName = &"sandbox"
const DUMMY_IDS: Array[StringName] = [&"training_dummy", &"shooting_dummy"]
## The horde's room.
const HORDE_ROOM_ID: StringName = &"horde"
## The run modes (`mode`): Play's waves, the sandbox, the horde.
const MODE_WAVES: StringName = &"waves"
const MODE_SANDBOX: StringName = &"sandbox"
const MODE_HORDE: StringName = &"horde"
## The actions of `sandbox_action_requested`.
const ACTION_IMP_WAVE: StringName = &"imp_wave"
const ACTION_RESET_DUMMIES: StringName = &"reset_dummies"
## The sandbox's staff, on every button, and the four basic staffs of Play and the horde by
## button (RB, RT, LB, LT), by id under `wizard`.
const DEV_STAFF: StringName = &"dev"
const STARTER_HEADS: Array[StringName] = [&"curl", &"star", &"moon", &"crystal"]
## The wave, sized for four players: one enemy per entry, placed at the room's
## enemy spawn with that index (wrapped if the room has fewer). An index used
## again puts the enemy a step further along the diagonal.
const WAVE: Array[int] = [0, 1, 2, 3, 4, 5, 0, 3]
const WAVE_REPEAT_OFFSET: Vector2 = Vector2(14.0, 14.0)
const WAVE_STACK_DEPTH: int = 3
const WAVE_LAP_OFFSET: Vector2 = Vector2(-14.0, 14.0)
## Enemies added by each wave after the first, and the most one wave holds.
const WAVE_GROWTH: int = 2
const WAVE_MAX: int = 24
## Seconds from a cleared wave until the next one stands: the build break. A fixed
## length, so nobody's building holds the wave back or speeds it up (a first guess,
## tuned at C2).
const BUILD_BREAK: float = 12.0
## Seconds from the last wizard going down until the room restarts (under 3).
const RESTART_DELAY: float = 1.5
## Seconds from the last wizard going down until a horde run starts over (time to read the summary).
const HORDE_RESTART_DELAY: float = 5.0
## Extra room around the room scene where projectiles may still fly, in pixels.
const PROJECTILE_MARGIN: float = 32.0
## Name of the world node.
const WORLD_NAME: String = "Arena"
## The intro's node name, and the save flag set once it has been seen (or skipped).
const INTRO_NAME: String = "Intro"
const INTRO_SEEN: StringName = &"intro_seen"

enum State { IDLE, RUNNING, CLEARED, INTRO, LOADING }

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null
var input: InputManagerScript = null
var combat: CombatScript = null
var projectiles: ProjectileManagerScript = null
var spells: SpellsScript = null
## Where the world goes. Only tests set this; otherwise the world becomes the
## current scene (the main menu is freed).
var world_parent: Node = null
## What the next run is made of, by registry id. Later features (a room picker, a loadout)
## set these; the room, enemy and spell components themselves are content found by folder, so a
## new one needs no change here. `wizard_scene` is the wizard every player gets (its art is in
## the scene). The start recipes are component ids (a recipe as in `core/spells`).
var room_id_to_play: StringName = DEFAULT_ROOM_ID
var enemy_id_to_play: StringName = DEFAULT_ENEMY_ID
var start_cards: Array = DEFAULT_START_CARDS.duplicate(true)
## What the sandbox's wizards start with instead (SANDBOX_START_CARDS unless a test or a
## screenshot sets other cards).
var sandbox_cards: Array = SANDBOX_START_CARDS.duplicate(true)
var wizard_scene: PackedScene = DefaultWizardScene
## Whether Play may show the intro (see the class doc), and the save it is remembered in.
var intro_enabled: bool = true
var save: SaveFile = null
## The intro on show (null when none), and who pressed Play.
var intro: IntroScript = null
var _intro_requester: int = 0
## Whether Play loads `play_tasks` behind the loading screen first, and the loading service.
var loading_enabled: bool = true
var loading: LoadingScript = null

var state: State = State.IDLE
## The world of the run in progress (null before the first Play).
var world: Node2D = null
## The id of the room of the run in progress.
var room_id: StringName = &""
## The wave in progress (1 for the first of a run; 0 before a run, in the sandbox and the horde).
var wave: int = 0
## The mode of the run in progress, or of the next one (MODE_WAVES when idle).
var mode: StringName = MODE_WAVES
## True while the run is in the sandbox (and for its restarts). Read only: set `mode`.
var sandbox: bool:
	get:
		return mode == MODE_SANDBOX
	set(_value):
		push_error("Flow: `sandbox` is read only; set `mode`.")

var _starter: int = 0
var _room: RoomBase = null
## The wizard scene the run in progress started with (joiners get the same one).
var _wizard_scene: PackedScene = null
## True from a horde run's start until `horde_ended` is sent.
var _horde_on: bool = false
var _enemies: Array[Node] = []
## The sandbox's dummies still standing.
var _dummies: Array[Node] = []
var _wizards: Array[Node2D] = []
var _downed: Array[bool] = [false, false, false, false]
var _restart_left: float = -1.0
var _next_wave_left: float = -1.0
var _enemy_data: EnemyBase = null


func _ready() -> void:
	if save == null:
		save = SaveFile.new()
	if _is_automated():
		intro_enabled = false
	var tree: MainLoop = Engine.get_main_loop()
	if tree != null and tree.get_script() != null:
		loading_enabled = false
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
	if combat == null:
		combat = get_node_or_null("/root/Combat") as CombatScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if spells == null:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	if events == null:
		push_warning("Flow: the Events autoload is missing, so the game cannot be started.")
		return
	events.play_requested.connect(_on_play_requested)
	events.sandbox_requested.connect(_on_sandbox_requested)
	events.sandbox_action_requested.connect(_on_sandbox_action_requested)
	events.horde_requested.connect(_on_horde_requested)
	events.enemy_died.connect(_on_enemy_died)
	events.player_downed.connect(_on_player_downed)
	events.player_revived.connect(_on_player_revived)
	events.player_joined.connect(_on_player_joined)
	events.player_left.connect(_on_player_left)


func _process(delta: float) -> void:
	step(delta)


## Advance the intro, the next wave's and the restart timers by `delta` seconds.
func step(delta: float) -> void:
	if intro != null:
		intro.step(delta)
	if _next_wave_left >= 0.0:
		_next_wave_left -= delta
		if _next_wave_left <= 0.0:
			_next_wave_left = -1.0
			_start_next_wave()
	if _restart_left < 0.0:
		return
	_restart_left -= delta
	if _restart_left <= 0.0:
		_restart_left = -1.0
		if mode == MODE_SANDBOX:
			_stand_everyone_up()
		elif not start_run(_starter):
			# A warning, not an error: the run ends cleanly and a test provokes this on purpose.
			push_warning("Flow: the restart failed, so the run is over; Play starts a new one.")
			stop_run()


## Seconds of the build break left, or 0 when there is none.
func build_break_left() -> float:
	return maxf(_next_wave_left, 0.0)


## True while a restart is counting down.
func is_restarting() -> bool:
	return _restart_left >= 0.0


## Where the `times`-th enemy (0 = first) at `spawn` stands: up to WAVE_STACK_DEPTH
## steps along the diagonal, then the next row starts a lap further to the side, so
## a stack never runs into a wall.
static func stacked_position(spawn: Vector2, times: int) -> Vector2:
	var step: int = times % WAVE_STACK_DEPTH
	var lap: int = times / WAVE_STACK_DEPTH
	return spawn + WAVE_REPEAT_OFFSET * float(step) + WAVE_LAP_OFFSET * float(lap)


## How many enemies wave `number` (1 or more) has.
static func wave_size(number: int) -> int:
	return mini(WAVE.size() + WAVE_GROWTH * maxi(number - 1, 0), WAVE_MAX)


## Enemies of the wave still alive (the sandbox's imps; never its dummies).
func enemies_left() -> int:
	return _enemies.size()


## The sandbox's dummies still standing.
func dummies() -> Array[Node]:
	return _dummies.duplicate()


## The wizard of player `index` in the current world (the actor whose home seat it is), or
## null. It stays the seat's wizard body while the seat drives another actor (possess, G9).
func get_wizard(index: int) -> Node2D:
	for wizard: Node2D in _wizards:
		if is_instance_valid(wizard) and _seat_of(wizard) == index:
			return wizard
	return null


## The home seat of a wizard actor (its PlayerController's), or -1.
func _seat_of(wizard: Node) -> int:
	var controller: PlayerScript = PlayerScript.of(wizard)
	return controller.seat if controller != null else -1


## Build the world and start the run now, replacing any run in progress. Returns
## false (and starts nothing) when content is missing or no player has a device.
func start_run(requester: int) -> bool:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id_for_mode()) as RoomBase if registry != null else null
	var enemy_data: EnemyBase = registry.get_resource(ENEMY_FOLDER, enemy_id_to_play) as EnemyBase if registry != null else null
	# The horde's enemies are the director's: it needs no enemy of its own.
	var needs_enemy: bool = mode != MODE_HORDE
	if room == null or room.scene == null or (needs_enemy and (enemy_data == null or enemy_data.scene == null)):
		push_warning("Flow: the room or the enemy is missing from the registry, so no run starts.")
		return false
	if spells == null:
		push_warning("Flow: the Spells autoload is missing, so no run starts.")
		return false
	if staffs_for_mode().is_empty():
		push_warning("Flow: a staff for the %s mode is missing from the registry, so no run starts." % mode)
		return false
	if not _is_wizard_scene(wizard_scene):
		push_warning("Flow: the wizard scene is missing or has no player script, so no run starts.")
		return false
	_ensure_joined(requester)
	var players: Array[int] = _joined_players()
	if players.is_empty():
		push_warning("Flow: no player has joined a device, so no run starts.")
		return false
	_starter = requester
	_restart_left = -1.0
	_next_wave_left = -1.0
	_clear_run()
	_room = room
	_enemy_data = enemy_data
	_wizard_scene = wizard_scene
	if projectiles != null:
		projectiles.clear()
	spells.clear()
	var layout: Node = room.scene.instantiate()
	var size: Vector2 = room_size(room, layout)
	if projectiles != null:
		var bounds := Rect2(Vector2.ZERO, size).grow(PROJECTILE_MARGIN)
		projectiles.set_bounds(bounds)
	var new_world := Node2D.new()
	new_world.name = WORLD_NAME
	new_world.add_child(layout)
	_add_camera(new_world, size)
	_spawn_players(new_world, room, players)
	match mode:
		MODE_SANDBOX:
			wave = 0
			_spawn_dummies(new_world, room)
		MODE_HORDE:
			wave = 0
		_:
			wave = 1
			_spawn_wave(new_world, room, enemy_data, wave)
	world = new_world
	room_id = room.id
	state = State.RUNNING
	_show_world(new_world)
	_set_walls(new_world)
	var horde_before: bool = _horde_on
	_horde_on = mode == MODE_HORDE
	if events != null:
		if horde_before and not _horde_on:
			events.horde_ended.emit()
		events.room_entered.emit(room.id)
		events.sandbox_changed.emit(mode == MODE_SANDBOX)
		match mode:
			MODE_HORDE:
				events.horde_started.emit(new_world)
			MODE_WAVES:
				events.wave_started.emit(wave)
	return true


## The room the next run of `mode` is in: the sandbox's, the horde's, or `room_id_to_play`.
func room_id_for_mode() -> StringName:
	match mode:
		MODE_SANDBOX:
			return SANDBOX_ROOM_ID
		MODE_HORDE:
			return HORDE_ROOM_ID
	return room_id_to_play


## End the run in progress and free its world. Flow is idle again, so the next
## `play_requested` starts a run. Nothing shows a menu yet; M3's run area will.
func stop_run() -> void:
	if state == State.LOADING and loading != null:
		loading.cancel()
	if intro != null:
		var shown: IntroScript = intro
		intro = null
		if is_instance_valid(shown):
			_detach(shown)
	_restart_left = -1.0
	_next_wave_left = -1.0
	wave = 0
	_clear_run()
	state = State.IDLE
	var was: StringName = mode
	mode = MODE_WAVES
	if was == MODE_SANDBOX and events != null:
		events.sandbox_changed.emit(false)
	if _horde_on:
		_horde_on = false
		if events != null:
			events.horde_ended.emit()


func _on_play_requested(player: int) -> void:
	if state != State.IDLE:
		return
	if not _load_then(_start_play.bind(player)):
		_start_play(player)


## Play, once the work before a room is loaded: the intro first on a new save, else the run.
func _start_play(player: int) -> void:
	mode = MODE_WAVES
	if wants_intro():
		play_intro(player)
	else:
		start_run(player)


## True when Play should show the intro first: it is on and this save has not seen it.
func wants_intro() -> bool:
	return intro_enabled and save != null and not save.has_flag(INTRO_SEEN)


## Show the intro for the joined players (`requester` joins first, as for a run); the run starts
## when it ends or is skipped.
func play_intro(requester: int) -> void:
	_ensure_joined(requester)
	_intro_requester = requester
	intro = IntroScript.new()
	intro.name = INTRO_NAME
	intro.setup(_joined_players(), input)
	intro.finished.connect(_on_intro_finished)
	state = State.INTRO
	_show_world(intro)


func _on_intro_finished(_skipped: bool) -> void:
	var shown: IntroScript = intro
	intro = null
	state = State.IDLE
	if save != null:
		save.set_flag(INTRO_SEEN)
	var started: bool = start_run(_intro_requester)
	# A run replaces the intro as the current scene; under `world_parent`, or with no run, it goes here.
	if shown != null and is_instance_valid(shown) and shown.is_inside_tree():
		_detach(shown)
	if not started:
		push_warning("Flow: the run after the intro did not start; Play starts a new one.")


## What must be ready before a room starts, as LoadTasks done behind the loading screen (empty:
## nothing to wait for). Add a task here to load something more before playing.
func play_tasks() -> Array[LoadTask]:
	var tasks: Array[LoadTask] = []
	if not ShaderWarmupScript.warmed:
		tasks.append(ShaderWarmupScript.new())
	return tasks


## Runs `play_tasks` behind the loading screen; when they are done, `next` starts what was
## pressed. False when there is nothing to do or loading is off: the caller starts at once.
func _load_then(next: Callable) -> bool:
	# The autoload comes after Flow (last, so the game's exit frees what it should): found on use.
	if loading == null:
		loading = get_node_or_null("/root/Loading") as LoadingScript
	if not loading_enabled or loading == null:
		return false
	if not loading.run(play_tasks(), _on_loaded.bind(next)):
		return false
	state = State.LOADING
	return true


func _on_loaded(next: Callable) -> void:
	state = State.IDLE
	next.call()


## True when nobody is playing: a test script is the main loop, or the game was started with user
## arguments (the automated runs).
func _is_automated() -> bool:
	var tree: MainLoop = Engine.get_main_loop()
	return (tree != null and tree.get_script() != null) or not OS.get_cmdline_user_args().is_empty()


func _on_sandbox_requested(player: int) -> void:
	if state != State.IDLE:
		return
	if not _load_then(_start_sandbox.bind(player)):
		_start_sandbox(player)


func _start_sandbox(player: int) -> void:
	mode = MODE_SANDBOX
	if not start_run(player):
		mode = MODE_WAVES


func _on_horde_requested(player: int) -> void:
	if state != State.IDLE:
		return
	if not _load_then(_start_horde.bind(player)):
		_start_horde(player)


## The horde run, once loaded: never the intro.
func _start_horde(player: int) -> void:
	mode = MODE_HORDE
	if not start_run(player):
		mode = MODE_WAVES


## A sandbox page's action. Ignored out of the sandbox, and an imp wave while WAVE_MAX imps
## are up. It changes the room only, never a player's staffs or menus.
func _on_sandbox_action_requested(player: int, action: StringName) -> void:
	if mode != MODE_SANDBOX or state == State.IDLE or world == null or _room == null or player < 0 or player >= PLAYER_SLOTS:
		return
	match action:
		ACTION_IMP_WAVE:
			if _enemy_data != null and _enemies.size() < WAVE_MAX:
				_spawn_enemies(world, _room, _enemy_data, mini(WAVE.size(), WAVE_MAX - _enemies.size()))
		ACTION_RESET_DUMMIES:
			for dummy: Node in _dummies:
				if is_instance_valid(dummy):
					_detach(dummy)
			_dummies.clear()
			_spawn_dummies(world, _room)
		_:
			push_warning("Flow: unknown sandbox action '%s'." % action)


## Add the wizard of a player who joined mid-run. Ignored while no run is up, and
## for a slot that already has a wizard.
func _on_player_joined(player: int) -> void:
	if state == State.IDLE or world == null or _room == null or player < 0 or player >= PLAYER_SLOTS:
		return
	if get_wizard(player) != null:
		return
	_add_wizard(world, _room, player, _joiner_spawn(_room, player))
	var joiner: DownedScript = DownedScript.of(get_wizard(player))
	if joiner != null:
		joiner.protect(DownedScript.JOIN_PROTECTION)
	_downed[player] = false
	if _restart_left >= 0.0 and not _all_down() and mode != MODE_HORDE:
		_restart_left = -1.0


## Remove the wizard of a player who left. If everyone still here is down, the
## restart timer starts, as when the last standing wizard goes down.
func _on_player_left(player: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	var wizard: Node2D = get_wizard(player)
	if wizard == null:
		return
	_wizards.erase(wizard)
	_downed[player] = false
	var parent: Node = wizard.get_parent()
	if parent != null:
		parent.remove_child(wizard)
	wizard.queue_free()
	if state == State.RUNNING and _restart_left < 0.0 and _all_down():
		_restart_left = restart_delay()


func _on_enemy_died(_player: int, enemy: Node, _position: Vector2, _shot: int) -> void:
	_dummies.erase(enemy)
	var at: int = _enemies.find(enemy)
	if at < 0:
		return
	_enemies.remove_at(at)
	if _enemies.is_empty() and state == State.RUNNING and mode == MODE_WAVES:
		state = State.CLEARED
		_next_wave_left = BUILD_BREAK
		if events != null:
			events.room_cleared.emit(room_id)
			events.build_break_started.emit(BUILD_BREAK)


## The next wave in the same room: downed wizards stand up (and are protected for
## a moment), stray shots go, and a bigger wave spawns.
func _start_next_wave() -> void:
	if state != State.CLEARED or world == null or _room == null or _enemy_data == null:
		return
	if projectiles != null:
		projectiles.clear()
	_stand_up_wizards()
	_restart_left = -1.0
	wave += 1
	_spawn_wave(world, _room, _enemy_data, wave)
	state = State.RUNNING
	if events != null:
		events.wave_started.emit(wave)


## The sandbox's answer to everyone down: they all stand up where they are, protected for a
## moment, with their staffs as they were; stray shots go.
func _stand_everyone_up() -> void:
	if projectiles != null:
		projectiles.clear()
	_stand_up_wizards()


## Every downed wizard stands up (revived by itself) and every wizard is protected for a moment.
func _stand_up_wizards() -> void:
	for wizard: Node2D in _wizards:
		var hero: DownedScript = DownedScript.of(wizard) if is_instance_valid(wizard) else null
		if hero == null:
			continue
		var seat: int = hero.seat()
		if hero.revive(seat) and seat >= 0 and seat < PLAYER_SLOTS:
			_downed[seat] = false
		hero.protect(DownedScript.JOIN_PROTECTION)


func _on_player_downed(player: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	_downed[player] = true
	if state == State.RUNNING and _all_down() and _restart_left < 0.0:
		_restart_left = restart_delay()


## Seconds from everyone down until the restart (or, in the sandbox, until everyone stands up).
func restart_delay() -> float:
	return HORDE_RESTART_DELAY if mode == MODE_HORDE else RESTART_DELAY


func _on_player_revived(player: int, _reviver: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	_downed[player] = false
	if _restart_left >= 0.0 and not _all_down() and mode != MODE_HORDE:
		_restart_left = -1.0


func _all_down() -> bool:
	if _wizards.is_empty():
		return false
	for wizard: Node2D in _wizards:
		var seat: int = _seat_of(wizard) if is_instance_valid(wizard) else -1
		if seat >= 0 and seat < PLAYER_SLOTS and not _downed[seat]:
			return false
	return true


## The Play button may be pressed with the mouse by nobody who has joined: the
## keyboard then takes slot 0, provisionally (a gamepad that joins before the keyboard is used
## takes P1 over; core/input). Anyone already joined (a gamepad, in any slot) plays as they are
## and the keyboard stays out.
func _ensure_joined(requester: int) -> void:
	if input == null or requester != 0 or input.joined_count() > 0:
		return
	input.join(InputManagerScript.KEYBOARD, true)


func _joined_players() -> Array[int]:
	var players: Array[int] = []
	if input == null:
		return players
	for index in PLAYER_SLOTS:
		if input.is_joined(index):
			players.append(index)
	return players


## Tell the projectile manager where the walls are: every static body on the wall
## layer (1) of the room. The world must be in the tree.
func _set_walls(new_world: Node2D) -> void:
	if projectiles == null or not new_world.is_inside_tree():
		return
	projectiles.clear_walls()
	for node: Node in new_world.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if (body.collision_layer & 1) != 0:
			projectiles.add_wall_body(body)


## The room's size in pixels, from (0, 0): at least 640×360, every spawn and door a tile in, and
## the layout's `Floor` sprite (the whole room, under the walls) when `layout` is given.
static func room_size(room: RoomBase, layout: Node = null) -> Vector2:
	var size := Vector2(640.0, 360.0)
	var floor_sprite: Sprite2D = layout.get_node_or_null("Floor") as Sprite2D if layout != null else null
	if floor_sprite != null and floor_sprite.texture != null:
		var extent: Vector2 = floor_sprite.region_rect.size if floor_sprite.region_enabled else floor_sprite.texture.get_size()
		size = size.max(floor_sprite.position + extent)
	for point: Vector2 in room.player_spawns:
		size = size.max(point + Vector2(32.0, 32.0))
	for point: Vector2 in room.enemy_spawns:
		size = size.max(point + Vector2(32.0, 32.0))
	for point: Vector2 in room.doors:
		size = size.max(point + Vector2(32.0, 32.0))
	return size


func _add_camera(parent: Node2D, size: Vector2) -> void:
	var camera := Camera2D.new()
	camera.position = size * 0.5
	# `coop` moves and zooms this camera to fit everyone; the limits keep it inside the room.
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ceili(size.x)
	camera.limit_bottom = ceili(size.y)
	parent.add_child(camera)


func _spawn_players(parent: Node2D, room: RoomBase, players: Array[int]) -> void:
	_wizards.clear()
	for index in PLAYER_SLOTS:
		_downed[index] = false
	for index: int in players:
		_add_wizard(parent, room, index)


## The player spawn for a mid-run joiner: the one farthest from every enemy and
## every wizard already there (the joiner's own slot wins a tie).
func _joiner_spawn(room: RoomBase, index: int) -> Vector2:
	var best: Vector2 = room.player_spawns[index] if index < room.player_spawns.size() else Vector2.ZERO
	var best_gap: float = -1.0
	for i in room.player_spawns.size():
		var point: Vector2 = room.player_spawns[i]
		var gap: float = INF
		for enemy: Node in _enemies:
			if is_instance_valid(enemy) and enemy is Node2D:
				gap = minf(gap, point.distance_squared_to((enemy as Node2D).position))
		for other in PLAYER_SLOTS:
			var wizard: Node2D = get_wizard(other)
			if wizard != null:
				gap = minf(gap, point.distance_squared_to(wizard.position))
		if gap > best_gap or (gap == best_gap and i == index):
			best_gap = gap
			best = point
	return best


## True when `scene` is set and its root is an actor with a player's controller (a wizard scene
## must carry `PlayerController`, gameplay/player/player.gd).
func _is_wizard_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false
	var probe: Node = scene.instantiate()
	var ok: bool = probe is Actor and PlayerScript.of(probe) != null
	probe.free()
	return ok


## The four staffs a wizard of this run's `mode` holds, by button, as the registry has them:
## the sandbox's the `dev` staff on every button, Play's and the horde's the four basic staffs
## (STARTER_HEADS). Empty when one is missing.
func staffs_for_mode() -> Array[StaffBase]:
	var ids: Array[StringName] = STARTER_HEADS
	if mode == MODE_SANDBOX:
		ids = [DEV_STAFF, DEV_STAFF, DEV_STAFF, DEV_STAFF]
	var out: Array[StaffBase] = []
	if registry == null:
		return out
	for id in ids:
		var staff: StaffBase = registry.get_resource(&"wizard", id) as StaffBase
		if staff == null:
			out.clear()
			return out
		out.append(staff)
	return out


## The cards each staff of a new wizard starts with in this run's `mode`: HORDE_START_CARDS in
## the horde, `sandbox_cards` in the sandbox, `start_cards` in Play.
func start_cards_for_mode() -> Array:
	match mode:
		MODE_HORDE:
			return HORDE_START_CARDS
		MODE_SANDBOX:
			return sandbox_cards
	return start_cards


func _add_wizard(parent: Node2D, room: RoomBase, index: int, at: Vector2 = Vector2.INF) -> void:
	var wizard := _wizard_scene.instantiate() as Actor
	var cards: Array = start_cards_for_mode()
	PlayerScript.seat_wizard(wizard, index, null, cards.duplicate(true), staffs_for_mode())
	if at != Vector2.INF:
		wizard.position = at
	elif index < room.player_spawns.size():
		wizard.position = room.player_spawns[index]
	# Its hurtbox registers it with Combat when it enters the tree.
	parent.add_child(wizard)
	_wizards.append(wizard)


func _spawn_wave(parent: Node2D, room: RoomBase, data: EnemyBase, number: int) -> void:
	_enemies.clear()
	_spawn_enemies(parent, room, data, wave_size(number))


## Add `count` enemies to `_enemies`, placed as a wave of that size is.
func _spawn_enemies(parent: Node2D, room: RoomBase, data: EnemyBase, count: int) -> void:
	if room.enemy_spawns.is_empty():
		push_warning("Flow: the room has no enemy spawns, so the wave is empty.")
		return
	var uses: Dictionary = {}
	for at: int in count:
		# Wave 1 is WAVE as written; a bigger wave carries on round the spawns.
		var entry: int = WAVE[at] if at < WAVE.size() else at
		var spawn: int = entry % room.enemy_spawns.size()
		var times: int = uses.get(spawn, 0)
		uses[spawn] = times + 1
		var node: Node = data.scene.instantiate()
		var enemy := node as Actor
		if enemy == null:
			push_warning("Flow: the enemy scene's root is not an actor, so it is skipped.")
			if node != null:
				node.free()
			continue
		enemy.data = data
		enemy.position = stacked_position(room.enemy_spawns[spawn], times)
		parent.add_child(enemy)
		_enemies.append(enemy)


## The dummy the sandbox stands at its `spawn`-th dummy spawn: DUMMY_IDS in order, then more
## training dummies.
static func dummy_id(spawn: int) -> StringName:
	return DUMMY_IDS[spawn] if spawn < DUMMY_IDS.size() else DUMMY_IDS[0]


## Stand the sandbox's dummies at the room's `dummy_spawns` (`dummy_id`), from the registry. A
## missing one is skipped with a warning; the sandbox runs without it.
func _spawn_dummies(parent: Node2D, room: RoomBase) -> void:
	for i in room.dummy_spawns.size():
		var id: StringName = dummy_id(i)
		var data: EnemyBase = registry.get_resource(ENEMY_FOLDER, id) as EnemyBase if registry != null else null
		if data == null or data.scene == null:
			push_warning("Flow: the dummy '%s' is missing from the registry, so the sandbox runs without it." % id)
			continue
		var node: Node = data.scene.instantiate()
		var dummy := node as Actor
		if dummy == null:
			push_warning("Flow: the dummy '%s' is not an actor, so it is skipped." % id)
			if node != null:
				node.free()
			continue
		dummy.data = data
		dummy.position = room.dummy_spawns[i]
		parent.add_child(dummy)
		_dummies.append(dummy)


## Forget the old run: wizards leave `Combat` (the enemies do it themselves when
## they leave the tree) and the old world is freed.
func _clear_run() -> void:
	if combat != null:
		for wizard: Node2D in _wizards:
			if is_instance_valid(wizard):
				combat.unregister_actor(wizard)
	_wizards.clear()
	_enemies.clear()
	_dummies.clear()
	if world != null and is_instance_valid(world):
		_detach(world)
	world = null


## Put the world in the tree. Without `world_parent` it becomes the current scene
## and whatever scene was current (the main menu) goes away.
func _show_world(new_world: Node2D) -> void:
	if world_parent != null:
		world_parent.add_child(new_world)
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var old: Node = tree.current_scene
	tree.root.add_child(new_world)
	tree.current_scene = new_world
	if old != null and old != new_world:
		_detach(old)


## Take a node out of the tree now (so its enemies and wizards stop at once) and free it.
func _detach(node: Node) -> void:
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()
