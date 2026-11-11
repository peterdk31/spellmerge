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
## Play the four basic staffs STARTER_HEADS (`content/wizard/staffs/`, one per
## button, each its own head), in the sandbox four times the `dev` staff (DEV_STAFF: 20 slots,
## no delay, practically infinite mana). The build channel plays no part. With them the mode's
## cards (`start_cards_for_mode`; Play's `start_cards`: A `dash`, X `bolt`, Y and B empty),
## which the wizard builds itself; flow never touches a spell.
##
## Each mode's setup (owner, 2026-11-05): a new wizard gets the mode's staffs, start cards and
## bag (the cards it may build with, `bag_for_mode`, handed over with `seat_wizard`): Play `dash`
## and `bolt` (PLAY_BAG, `play_bag`); the sandbox and the hub every card (the hub's for now, owner
## 2026-11-11: to try combos online until a better way to come by cards comes).
##
## The intro (living staffs H6, `intro.gd`): on a new save (`save`, a `SaveFile`, has no
## INTRO_SEEN flag) Play shows the intro first (state INTRO): one staff dropped per joined player,
## skippable by any of them; when it ends or is skipped the save is marked and the run starts.
## It plays only for people: off (`intro_enabled` false) when a test script is the main loop or
## the game was started with user arguments (the 4-bot test, the stress run, the timing run).
##
## Loading (owner, 2026-10-29): Play and Sandbox first do the work that must be ready before a
## room (`play_tasks`, LoadTasks) behind the loading screen (state LOADING), through
## `core/loading` (the autoload `Loading`, which sends the events the HUD's screen is drawn from);
## then the intro or the run starts. Today that work is the shader warm-up
## (`core/projectiles/shader_warmup.gd`), once a session; with nothing to do Play starts at once.
## `play_load_requested` does the same work ahead of a run that cannot wait at its start (one two
## machines start together: a load takes each its own time, and the run must begin on the same
## tick on both).
## To load something more before playing, add a LoadTask in `play_tasks`. It is off
## (`loading_enabled` false) only when a test script is the main loop; the automated runs (the
## four-bot and stress runs) load like a player, and wait for `room_entered`.
##
## Sandbox (staffs B7, docs/milestones/M2-staffs.md, "The sandbox"): `sandbox_requested` (the
## main menu's Sandbox button, in every build) starts a run in the sandbox room
## (`sandbox`): no waves, the dummies its scene stands (`RoomPlaces.dummies`: the training dummy,
## the shooting dummy, then a group of training dummies to try homing, pierce and spreads on), and `sandbox_changed(true)` so the HUD shows the sandbox page. The page sends
## `sandbox_action_requested`: `clear_enemies` takes the enemies the arena spawned away,
## `reset_dummies` puts fresh dummies back; `sandbox_spawn_requested` (the enemy arena, enemy AI AI8)
## spawns any enemy (`spawn_in_sandbox`, while fewer than WAVE_MAX are up). Clearing them starts no
## build break. When every wizard is down, after RESTART_DELAY they all stand up where they are and
## keep their staffs, instead of a restart. Its wizards hold four `dev` staffs and start with
## `sandbox_cards` (SANDBOX_START_CARDS), not `start_cards`: Play's A and X, and two showcase
## builds on Y (the most shots) and B (a decoy turret).
##
## The hub (docs/milestones/online-lobby.md, L1): `hub_requested` (the main menu's Play) starts a run
## in the hub room (`hub`), an island in the void where players join and leave as they like (coop's
## `player_joined` / `player_left`, at the room's spawns), try their staffs on the room's dummies,
## and take nothing from hits (`RoomBase.invincible`: the hit lands, the health stays). Its wizards
## have Play's staffs and start cards, and every card in the bag (above). Its teleporter stone (the zone ZONE_START_STONE) is lit while every wizard stands
## in it: counted each tick and whenever a wizard joins or leaves, and told by `start_stone_changed`;
## the prop standing on it (the hub's `hub_stone`) enters its state `lit` or `unlit` to match, so
## its look and cue are the prop's (props W8).
## The command `run_requested` (a seat's A on the lit stone, from the HUD) starts a run of waves at
## the tick's start, every wizard keeping its staffs (`start_run`'s `kept`); that run's end
## (everyone down) brings everyone back to the hub with nothing of the run, its staffs neither
## (owner, 2026-11-10: the hub is the arsenal a run's tools are picked from). A run started by
## `play_requested` restarts as before.
##
## Rooms (props W8a, docs/milestones/props.md): what is where is the room's scene, read once
## (`RoomBase.places()`, `RoomPlaces`): spawns, doors, the props and dummies its scene stands (their
## stand-ins are taken out of the room shown, `RoomPlaces.strip`, and real bodies stood there, in
## the scene's order) and its zones by name. What a zone means is Flow's: ZONE_START_STONE (the
## teleporter stone, below; the props standing in it enter STONE_LIT or STONE_UNLIT with it),
## ZONE_ALTAR (the multiplayer altar) and ZONE_PROP_YARD (props W8: every prop of the registry
## that stands in one, `PropBase.in_yard`, in rows by id, `PropYard.places`; one that leaves its
## first state or goes is replaced by a fresh one `PropYard.RETURN_SECONDS` later).
##
## Modes: `mode` says which run this is: MODE_WAVES (Play), MODE_SANDBOX or MODE_HUB (above).
##
## All timing runs in step(delta), so tests drive it with fixed deltas.

const EventsScript := preload("res://core/events/events.gd")
const TickScript := preload("res://core/sim/tick.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FramesScript := preload("res://core/sim/frames.gd")
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
const PROP_FOLDER: StringName = &"props"
const DEFAULT_ENEMY_ID: StringName = &"ember_imp"
## The two spells every wizard starts with: A is a fire bolt (M1's bolt plus burn), B a plain bolt.
## The cards each staff starts with in Play: A, X, Y, B (owner, 2026-11-05: dash and a bolt).
const DEFAULT_START_CARDS: Array = [[&"dash"], [&"bolt"], [], []]
## Play's bag: the cards a Play wizard may build with (owner, 2026-11-05).
const PLAY_BAG: Array[StringName] = [&"dash", &"bolt"]
## The cards a sandbox run starts with (owner, 2026-11-01: two showcase builds of the trigger
## tree on Y and B, to read in the builder's tree and try on the dummies). A and X as Play's.
## Y, the most shots: a fire nova of bolts split three times (216 shots) whose every shot, when it
## ends, fires a frost nova of bolts split three times (216 each): far past the projectile cap (6,000 on
## desktop), which it holds for a few seconds; 67.5 mana. Two payload levels only: a
## third would queue a million shots, minutes of backlog at `SpellLimits.FIRE_SHOTS_PER_STEP`.
## B, a decoy turret: every 0.5 s it fires a homing fire, frost and lightning bolt (the
## lightning one sets off a chaining lightning atom on hit), and when it is hurt a void nova of
## bolts; 59.6 mana, every card used.
const SANDBOX_START_CARDS: Array = [
	[&"dash"],
	[&"fire", &"bolt"],
	[&"on_expire", &"fire", &"split", &"split", &"split", &"nova", &"bolt", &"frost", &"split", &"split", &"split", &"nova", &"bolt"],
	[&"timer", &"on_hurt", &"decoy", &"triple", &"homing", &"fire", &"bolt", &"homing", &"frost", &"bolt",
		&"on_hit", &"homing", &"lightning", &"bolt", &"chain", &"lightning", &"atom", &"void", &"nova", &"bolt"],
]
## The sandbox room and the hub's (which dummies each stands is its scene's, `RoomPlaces.dummies`).
const SANDBOX_ROOM_ID: StringName = &"sandbox"
const HUB_ROOM_ID: StringName = &"hub"
## The zones of a room's scene Flow gives a meaning (`RoomPlaces.zone`): the teleporter stone that
## starts a run (online lobby L1), the multiplayer altar (L2) and the prop yard (props W8).
const ZONE_START_STONE: StringName = &"start_stone"
const ZONE_ALTAR: StringName = &"altar"
const ZONE_PROP_YARD: StringName = &"prop_yard"
## The states the props standing in ZONE_START_STONE enter as it lights and goes out (the hub's
## `hub_stone`).
const STONE_LIT: StringName = &"lit"
const STONE_UNLIT: StringName = &"unlit"
## The run modes (`mode`): Play's waves, the sandbox, the hub.
const MODE_WAVES: StringName = &"waves"
const MODE_SANDBOX: StringName = &"sandbox"
const MODE_HUB: StringName = &"hub"
## The cue played on every standing wizard as a wave starts (`_show_wave_start`).
const WAVE_START_CUE: StringName = &"wave_start"
## The actions of `sandbox_action_requested`.
const ACTION_RESET_DUMMIES: StringName = &"reset_dummies"
## The enemy arena (enemy AI AI8): every enemy the sandbox spawned goes.
const ACTION_CLEAR_ENEMIES: StringName = &"clear_enemies"
## The sandbox's staff, on every button, and the four basic staffs of Play by
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
## Extra room around the room scene where projectiles may still fly, in pixels.
const PROJECTILE_MARGIN: float = 32.0
## Name of the world node.
const WORLD_NAME: String = "Arena"
## The intro's node name, and the save flag set once it has been seen (or skipped).
const INTRO_NAME: String = "Intro"
const INTRO_SEEN: StringName = &"intro_seen"

enum State { IDLE, RUNNING, CLEARED, INTRO, LOADING }

## Not state: services, caches and scratch, set up again (core/sim/README.md); `sandbox`, worked
## out from `mode` (read only).
const DERIVED: Array[StringName] = [&"events", &"registry", &"frames", &"combat", &"projectiles", &"spells", &"world_parent", &"intro", &"loading", &"world", &"save", &"sandbox", &"_stone_sent", &"_altar_sent", &"_hub_sent"]
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_enemies", &"_dummies", &"_wizards", &"_props", &"_yard"]
## Not state: the functions that only make what is drawn (core/sim/README.md, "The line"): the
## room's camera.
const VIEW: Array[StringName] = [&"_add_camera"]

## Why Flow needs no renewing at a run's start (core/sim/sim_area.gd, `fresh_because`).
const FRESH_BECAUSE: String = "it starts the run: start_run sets the run's members itself"

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null
var frames: FramesScript = null
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
## Play's bag (PLAY_BAG unless a test sets another).
var play_bag: Array[StringName] = PLAY_BAG.duplicate()
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
## The wave in progress (1 for the first of a run; 0 before a run and in the sandbox).
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
var _enemies: Array[Node] = []
## The sandbox's dummies still standing.
var _dummies: Array[Node] = []
var _wizards: Array[Node2D] = []
## The props the room's scene stands (`RoomPlaces.props`) still standing.
var _props: Array[Node] = []
## The prop yard (ZONE_PROP_YARD), a slot a prop: who stands there (null while none: it went),
## which prop, where, and the seconds until a fresh one stands there (-1: none due).
var _yard: Array[Node] = []
var _yard_ids: Array[StringName] = []
var _yard_places: PackedVector2Array = PackedVector2Array()
var _yard_left: PackedFloat64Array = PackedFloat64Array()
var _downed: Array[bool] = [false, false, false, false]
var _restart_left: float = -1.0
var _next_wave_left: float = -1.0
var _enemy_data: EnemyBase = null
## The hub's stone: the wizards on it and in the room at the last count (whether it is lit).
var _stone_standing: int = 0
var _stone_wizards: int = 0
## True while the run of waves in progress was started from the hub's stone: its end goes back there.
var _back_to_hub: bool = false
## What `start_stone_changed` last said, as (standing, wizards): only what is drawn, so a game whose
## state a snapshot replaced sends the stone's count again (DERIVED). (-1, -1) before any.
var _stone_sent: Vector2i = Vector2i(-1, -1)
## The seats last told to stand on the hub's altar (`altar_changed`; -1: nothing sent yet).
var _altar_sent: int = -1
## Whether the party was last told to be in the hub (`hub_changed`).
var _hub_sent: bool = false


func _ready() -> void:
	# The tick steps it (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Flow").steps(&"Flow", step).fresh_because(FRESH_BECAUSE)
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
	if frames == null:
		frames = get_node_or_null("/root/Frames") as FramesScript
	if combat == null:
		combat = get_node_or_null("/root/Combat") as CombatScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if spells == null:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	if frames != null:
		frames.set_carry_source(_carry_now)
	if events == null:
		push_warning("Flow: the Events autoload is missing, so the game cannot be started.")
		return
	events.play_requested.connect(_on_play_requested)
	events.sandbox_requested.connect(_on_sandbox_requested)
	events.hub_requested.connect(_on_hub_requested)
	events.play_load_requested.connect(_on_play_load_requested)
	# Commands, heard at the tick's start (core/events, online-ready N2).
	events.listen(&"sandbox_action_requested", _on_sandbox_action_requested)
	events.listen(&"sandbox_spawn_requested", _on_sandbox_spawn_requested)
	events.listen(&"run_requested", _on_run_requested)
	events.enemy_died.connect(_on_enemy_died)
	events.player_downed.connect(_on_player_downed)
	events.player_revived.connect(_on_player_revived)
	events.player_joined.connect(_on_player_joined)
	events.player_left.connect(_on_player_left)


## Advance the intro, the next wave's and the restart timers by `delta` seconds; the prop yard; in
## the hub, the stone.
func step(delta: float) -> void:
	if intro != null:
		intro.step(delta)
	_forget_gone(_props)
	_tend_yard(delta)
	if mode == MODE_HUB and state == State.RUNNING:
		_count_stone()
		return
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
		elif _back_to_hub:
			# Back in the hub the party is ready for a new run: nothing of the run comes back
			# with it, its staffs neither (owner, 2026-11-10). The hub is the arsenal the next
			# run's tools are picked from.
			_back_to_hub = false
			if frames != null:
				# The hub is a run's start of its own: asked of the frames service, which sends it
				# between ticks, the same on every machine, and begins a new recording there
				# when this run is recorded (a recording never grows past one stretch of play).
				var starter: int = _starter
				stop_run()
				frames.restart(&"hub_requested", starter)
				return
			mode = MODE_HUB
			if not start_run(_starter):
				push_warning("Flow: the hub did not start again after the run, so the run is over.")
				stop_run()
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


## The dummies of the sandbox or the hub still standing.
func dummies() -> Array[Node]:
	return _dummies.duplicate()


## The props the room's scene stands, still standing (the hub's stone and altar).
func room_props() -> Array[Node]:
	return _props.duplicate()


## The props standing in the prop yard now, by slot (null for a slot whose prop went and is not
## back yet).
func yard_props() -> Array[Node]:
	return _yard.duplicate()


## The wizard of player `index` in the current world (the actor whose home seat it is), or
## null. It stays the seat's wizard body while the seat drives another actor (possess, G9).
func get_wizard(index: int) -> Node2D:
	for wizard: Node2D in _wizards:
		if is_instance_valid(wizard) and _seat_of(wizard) == index:
			return wizard
	return null


## A wave starting: its cue (WAVE_START_CUE, content/cues; S6, item 13) on every wizard standing in
## the world, so content gives the moment its look.
func _show_wave_start() -> void:
	for wizard: Node2D in _wizards:
		var actor := wizard as Actor
		if actor != null and is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_down():
			events.cue_shown.emit(actor.id, WAVE_START_CUE, actor.global_position, Vector2.ZERO, 0.0, Color.WHITE, 0)


## The home seat of a wizard actor (its PlayerController's), or -1.
func _seat_of(wizard: Node) -> int:
	var controller: PlayerScript = PlayerScript.of(wizard)
	return controller.seat if controller != null else -1


## Build the world and start the run now, replacing any run in progress. `kept` (by seat, as
## `_staffs_by_seat` makes it) gives a seat's wizard the cards its staffs held before (through the
## hub's stone and back); a seat with none there starts with its mode's start cards. Returns
## false (and starts nothing) when content is missing or no player has a device.
func start_run(requester: int, kept: Array = []) -> bool:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id_for_mode()) as RoomBase if registry != null else null
	var enemy_data: EnemyBase = registry.get_resource(ENEMY_FOLDER, enemy_id_to_play) as EnemyBase if registry != null else null
	if room == null or room.scene == null or enemy_data == null or enemy_data.scene == null:
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
	# The run starts from a fresh game's state (online-ready N3b): the one clock from 0, and every
	# service as a fresh one's (`Tick.begin_run`; the autoload, found on use).
	var tick: TickScript = TickScript.of(self) as TickScript
	if tick == null:
		push_error("Flow: the Tick autoload is missing, so the run starts on the last run's state.")
	else:
		tick.begin_run()
	var layout: Node = room.scene.instantiate()
	var size: Vector2 = room.size_in(layout)
	# The stand-ins and zones are the editor's: the bodies are stood below, by the room's places.
	RoomPlaces.strip(layout)
	if projectiles != null:
		var bounds := Rect2(Vector2.ZERO, size).grow(PROJECTILE_MARGIN)
		projectiles.set_bounds(bounds)
	var new_world := Node2D.new()
	new_world.name = WORLD_NAME
	new_world.add_child(layout)
	_add_camera(new_world, size)
	_spawn_players(new_world, room, players, kept)
	_spawn_props(new_world, room)
	match mode:
		MODE_SANDBOX, MODE_HUB:
			wave = 0
			_spawn_dummies(new_world, room)
		_:
			wave = 1
			_spawn_wave(new_world, room, enemy_data, wave)
	world = new_world
	room_id = room.id
	state = State.RUNNING
	_show_world(new_world)
	_set_walls(new_world)
	for wizard: Node2D in _wizards:
		_take_room_rules(wizard as Actor)
	if events != null:
		events.room_laid_out.emit(Rect2(Vector2.ZERO, size))
		events.room_entered.emit(room.id)
		events.sandbox_changed.emit(mode == MODE_SANDBOX)
		if mode == MODE_WAVES:
			events.wave_started.emit(wave)
			_show_wave_start()
	_count_stone()
	return true


## The room the next run of `mode` is in: the sandbox's, the hub's, or `room_id_to_play`.
func room_id_for_mode() -> StringName:
	match mode:
		MODE_SANDBOX:
			return SANDBOX_ROOM_ID
		MODE_HUB:
			return HUB_ROOM_ID
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
	_back_to_hub = false
	wave = 0
	_clear_run()
	state = State.IDLE
	var was: StringName = mode
	mode = MODE_WAVES
	if was == MODE_SANDBOX and events != null:
		events.sandbox_changed.emit(false)
	_count_stone()


func _on_play_requested(player: int) -> void:
	if state != State.IDLE:
		return
	if not _load_then(_start_play.bind(player)):
		_start_play(player)


## Play, once the work before a room is loaded: the intro first on a new save, else the run.
func _start_play(player: int) -> void:
	mode = MODE_WAVES
	_back_to_hub = false
	_intro_then_run(player)


## The intro first on a new save (the run of `mode` starts when it ends), else the run now, its
## seats' wizards with the staffs `kept` (by seat, as `start_run` takes them; the intro keeps none).
func _intro_then_run(player: int, kept: Array = []) -> void:
	# Never in a run that is recorded or played back: the intro takes the machine's own time, and
	# a recording must start the same on the machine that made it and on every one that plays it.
	if wants_intro() and not (frames != null and (frames.is_recording() or frames.is_playing())):
		play_intro(player)
	else:
		start_run(player, kept)


## True when Play should show the intro first: it is on and this save has not seen it.
func wants_intro() -> bool:
	return intro_enabled and save != null and not save.has_flag(INTRO_SEEN)


## Show the intro for the joined players (as a run reads them); the run starts
## when it ends or is skipped.
func play_intro(requester: int) -> void:
	_intro_requester = requester
	intro = IntroScript.new()
	intro.name = INTRO_NAME
	intro.setup(_joined_players())
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


## A run will start soon that cannot wait at its start (`play_load_requested`: one two machines
## start together, net/): what must be ready before a room is loaded now, behind the loading
## screen, and Flow is idle again after. With nothing to load, or a run or a load under way,
## nothing happens.
func _on_play_load_requested() -> void:
	if state == State.IDLE:
		_load_then(func() -> void: pass)


func _on_sandbox_requested(player: int) -> void:
	if state != State.IDLE:
		return
	if not _load_then(_start_sandbox.bind(player)):
		_start_sandbox(player)


func _start_sandbox(player: int) -> void:
	mode = MODE_SANDBOX
	if not start_run(player):
		mode = MODE_WAVES


func _on_hub_requested(player: int) -> void:
	# What the hub's wizards take along (the recording's, read before the hub it was made in goes).
	var kept: Array = frames.next_run_carry().as_kept() if frames != null else []
	# Asked for in the hub, the hub starts anew (a recording of it begins: net/ opens the room), each
	# wizard with the staffs it held.
	if state == State.RUNNING and mode == MODE_HUB:
		stop_run()
	if state != State.IDLE:
		return
	if not _load_then(_start_hub.bind(player, kept)):
		_start_hub(player, kept)


## The hub, once the work before a room is loaded: after the intro on a new save, as Play's run;
## each seat's wizard with its staffs in `kept` (by seat; a seat with none: the start cards).
func _start_hub(player: int, kept: Array = []) -> void:
	mode = MODE_HUB
	_back_to_hub = false
	_intro_then_run(player, kept)
	if state == State.IDLE:
		# Nothing started (content missing): idle is MODE_WAVES.
		mode = MODE_WAVES


## The command `run_requested` (a seat pressed A on the lit stone; the HUD sends it, heard at the
## tick's start): the run of waves starts, for that seat, while the stone is lit. The stone's count
## is the last tick's, made again when a wizard joined or left since, so it is exact here.
func _on_run_requested(player: int) -> void:
	if not is_stone_lit() or state != State.RUNNING or get_wizard(player) == null:
		return
	_start_run_from_stone(player)


## The run of waves, from the hub's stone, for seat `seat`: every wizard keeps its staffs, and the
## run's end brings everyone back to the hub.
func _start_run_from_stone(seat: int) -> void:
	var kept: Array = _staffs_by_seat()
	mode = MODE_WAVES
	_back_to_hub = true
	if not start_run(seat, kept):
		# It refused before freeing anything (content missing): the hub stands as it was.
		push_warning("Flow: the run from the stone did not start, so the party stays in the hub.")
		_back_to_hub = false
		mode = MODE_HUB


## The cards every wizard's staffs hold now, by seat (empty for a seat with none): what
## `start_run` makes each seat's wizard with, so staffs follow the party from the hub into the
## run (owner, 2026-11-10); nothing comes back from it.
func _staffs_by_seat() -> Array:
	var out: Array = [[], [], [], []]
	for wizard: Node2D in _wizards:
		var seat: int = _seat_of(wizard) if is_instance_valid(wizard) else -1
		if seat >= 0 and seat < PLAYER_SLOTS:
			out[seat] = PlayerScript.staff_cards(wizard as Actor)
	return out


## What a run that starts now takes along (the frames service asks, and writes it into a recording's
## header; core/sim/run_carry.gd): in the hub, every wizard's staffs, so the hub begun anew for a
## joining machine keeps them, on every machine; anywhere else nothing, since nothing comes back
## from a run (owner, 2026-11-10).
func _carry_now() -> RunCarry:
	if mode != MODE_HUB or state != State.RUNNING:
		return RunCarry.new()
	return RunCarry.of_kept(_staffs_by_seat())


## The wizards in the world now.
func _wizard_count() -> int:
	var count: int = 0
	for wizard: Node2D in _wizards:
		if is_instance_valid(wizard):
			count += 1
	return count


## True while the hub's stone is lit: every wizard of the hub stands on it, and there is one.
func is_stone_lit() -> bool:
	return mode == MODE_HUB and _stone_wizards > 0 and _stone_standing == _stone_wizards


## Count the wizards on the hub's stone and in the room (none out of the hub) into the state that
## decides whether it is lit, put the props standing on it in their state to match (`lit`,
## `unlit`: their look and cue are theirs), and send `start_stone_changed` when what was last sent
## differs (also after a snapshot restored the state under a game that had sent another count).
func _count_stone() -> void:
	var standing: int = 0
	var wizards: int = 0
	var at_altar: int = 0
	if mode == MODE_HUB and state != State.IDLE and _room != null:
		wizards = _wizard_count()
		for wizard: Node2D in _wizards:
			if not is_instance_valid(wizard):
				continue
			if _room.places().zone(ZONE_START_STONE).has_point(wizard.position):
				standing += 1
			var seat: int = _seat_of(wizard)
			if seat >= 0 and seat < PLAYER_SLOTS and _room.places().zone(ZONE_ALTAR).has_point(wizard.position):
				at_altar |= 1 << seat
	# Where the party is, for whoever lets other machines join it (net/): told as it changes.
	var in_hub: bool = mode == MODE_HUB and state != State.IDLE and _room != null
	if in_hub != _hub_sent and events != null:
		_hub_sent = in_hub
		events.hub_changed.emit(in_hub)
	# Who stands on the altar is told to the HUD only (A there opens the room, net/'s to do).
	if at_altar != _altar_sent and events != null:
		_altar_sent = at_altar
		events.altar_changed.emit(at_altar)
	_stone_standing = standing
	_stone_wizards = wizards
	_light_stone_props(is_stone_lit())
	var now := Vector2i(standing, wizards)
	if now == _stone_sent or events == null:
		return
	_stone_sent = now
	events.start_stone_changed.emit(standing, wizards, is_stone_lit())


## The room's props standing on its stone (ZONE_START_STONE) enter STONE_LIT or STONE_UNLIT as it
## is lit or not (a state they are in already is not entered again; one they lack is not).
func _light_stone_props(lit: bool) -> void:
	var stone: Rect2 = _room.places().zone(ZONE_START_STONE) if _room != null else Rect2()
	if not stone.has_area():
		return
	var want: StringName = STONE_LIT if lit else STONE_UNLIT
	for node: Node in _props:
		var prop := node as Actor if is_instance_valid(node) else null
		if prop == null or prop.state_triggers == null or not stone.has_point(prop.position):
			continue
		if prop.state_triggers.state_id() != want:
			prop.state_triggers.enter(want)


## A sandbox page's action. Ignored out of the sandbox. It changes the room only, never a
## player's staffs or menus.
func _on_sandbox_action_requested(player: int, action: StringName) -> void:
	if mode != MODE_SANDBOX or state == State.IDLE or world == null or _room == null or player < 0 or player >= PLAYER_SLOTS:
		return
	match action:
		ACTION_CLEAR_ENEMIES:
			clear_sandbox_enemies()
		ACTION_RESET_DUMMIES:
			for dummy: Node in _dummies:
				if is_instance_valid(dummy):
					_detach(dummy)
			_dummies.clear()
			_spawn_dummies(world, _room)
		_:
			push_warning("Flow: unknown sandbox action '%s'." % action)


## The enemy arena's spawn (enemy AI AI8): `count` enemies of `enemy_id`. Ignored out of the sandbox.
func _on_sandbox_spawn_requested(player: int, enemy_id: StringName, count: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	spawn_in_sandbox(enemy_id, count)


## Put `count` enemies of the registry's `enemy_id` in the sandbox room, at its enemy spawns, while
## fewer than WAVE_MAX are up (the enemy arena: to play against one kind, or tune it; tests use it
## too). Returns how many came; 0 out of a sandbox run or for an unknown id.
func spawn_in_sandbox(enemy_id: StringName, count: int) -> int:
	if mode != MODE_SANDBOX or state == State.IDLE or world == null or _room == null or registry == null:
		return 0
	var data: EnemyBase = registry.get_resource(&"enemies", enemy_id) as EnemyBase
	if data == null or data.scene == null:
		push_warning("Flow: no enemy '%s' to spawn in the sandbox." % enemy_id)
		return 0
	var room_left: int = WAVE_MAX - _enemies.size()
	var wanted: int = clampi(count, 0, room_left)
	var before: int = _enemies.size()
	_spawn_enemies(world, _room, data, wanted)
	return _enemies.size() - before


## Every enemy the sandbox spawned goes (its dummies stay).
func clear_sandbox_enemies() -> void:
	for enemy: Node in _enemies:
		if is_instance_valid(enemy):
			_detach(enemy)
	_enemies.clear()


## Add the wizard of a player who joined mid-run: at the room's spawn for joiners when it has them
## (the hub: beside the altar, where a joining machine's wizards arrive), else at the player spawn
## farthest from danger. Ignored while no run is up, and for a slot that already has a wizard.
func _on_player_joined(player: int) -> void:
	if state == State.IDLE or world == null or _room == null or player < 0 or player >= PLAYER_SLOTS:
		return
	if get_wizard(player) != null:
		return
	var joiners: PackedVector2Array = _room.places().joiner_spawns
	var at: Vector2 = joiners[player] if player < joiners.size() else _joiner_spawn(_room, player)
	_add_wizard(world, _room, player, at)
	var joiner: DownedScript = DownedScript.of(get_wizard(player))
	# In a room where hits take nothing (the hub), a joiner needs no moment of protection.
	if joiner != null and not _room.invincible:
		joiner.protect(DownedScript.JOIN_PROTECTION)
	_downed[player] = false
	if _restart_left >= 0.0 and not _all_down():
		_restart_left = -1.0
	# Heard at the tick's start: the stone goes out under a joiner before any command is applied.
	_count_stone()


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
	_count_stone()
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
		_show_wave_start()


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
	return RESTART_DELAY


func _on_player_revived(player: int, _reviver: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	_downed[player] = false
	if _restart_left >= 0.0 and not _all_down():
		_restart_left = -1.0


func _all_down() -> bool:
	if _wizards.is_empty():
		return false
	for wizard: Node2D in _wizards:
		var seat: int = _seat_of(wizard) if is_instance_valid(wizard) else -1
		if seat >= 0 and seat < PLAYER_SLOTS and not _downed[seat]:
			return false
	return true


## The seats joined now (the frames service's: the devices', or a replay's), who play a run that
## starts. Nobody has joined when a run is asked for with the mouse: the input layer joins the
## keyboard first (core/input, `_on_run_requested`).
func _joined_players() -> Array[int]:
	return frames.joined_seats() if frames != null else [] as Array[int]


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


func _add_camera(parent: Node2D, size: Vector2) -> void:
	var camera := Camera2D.new()
	camera.position = size * 0.5
	# Feel's party camera moves and zooms it to the party's view (Coop's `view_fitted`); the
	# limits keep it inside the room, as Coop keeps the view (`room_laid_out`).
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ceili(size.x)
	camera.limit_bottom = ceili(size.y)
	# The picture shows this room from the moment it is in the tree, whatever camera was current.
	camera.ready.connect(camera.make_current, CONNECT_ONE_SHOT)
	parent.add_child(camera)


func _spawn_players(parent: Node2D, room: RoomBase, players: Array[int], kept: Array = []) -> void:
	_wizards.clear()
	for index in PLAYER_SLOTS:
		_downed[index] = false
	for index: int in players:
		var cards: Array = kept[index] if index < kept.size() else []
		_add_wizard(parent, room, index, Vector2.INF, cards)


## The player spawn for a mid-run joiner: the one farthest from every enemy and
## every wizard already there (the joiner's own slot wins a tie).
func _joiner_spawn(room: RoomBase, index: int) -> Vector2:
	var spawns: PackedVector2Array = room.places().player_spawns
	var best: Vector2 = spawns[index] if index < spawns.size() else Vector2.ZERO
	var best_gap: float = -1.0
	for i in spawns.size():
		var point: Vector2 = spawns[i]
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
## the sandbox's the `dev` staff on every button, Play's the four basic staffs
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


## The cards each staff of a new wizard starts with in this run's `mode`: `sandbox_cards` in the
## sandbox, `start_cards` in Play.
func start_cards_for_mode() -> Array:
	if mode == MODE_SANDBOX:
		return sandbox_cards
	return start_cards


## The bag a new wizard gets in this run's `mode`: every spell card of the registry in the
## sandbox and the hub, `play_bag` in Play.
func bag_for_mode() -> Array[StringName]:
	var out: Array[StringName] = []
	match mode:
		MODE_SANDBOX, MODE_HUB:
			if registry != null:
				for id: StringName in registry.get_ids(&"spells"):
					if registry.get_resource(&"spells", id) is SpellComponent:
						out.append(id)
		_:
			out.assign(play_bag)
	return out


## Add the wizard of seat `index` at `at` (INF: its spawn) with the staffs `cards` (by staff; empty:
## the mode's start cards).
func _add_wizard(parent: Node2D, room: RoomBase, index: int, at: Vector2 = Vector2.INF, cards: Array = []) -> void:
	var wizard := _wizard_scene.instantiate() as Actor
	var staff_cards: Array = cards if not cards.is_empty() else start_cards_for_mode()
	PlayerScript.seat_wizard(wizard, index, null, staff_cards.duplicate(true), staffs_for_mode(), bag_for_mode())
	if at != Vector2.INF:
		wizard.position = at
	elif index < room.places().player_spawns.size():
		wizard.position = room.places().player_spawns[index]
	# Its hurtbox registers it with Combat when it enters the tree.
	parent.add_child(wizard)
	_wizards.append(wizard)
	# A joiner's world is in the tree, so its components are found; a new run's wizards get it once
	# their world is shown (`start_run`).
	if wizard.is_inside_tree():
		_take_room_rules(wizard)


## The room's rules on wizard `wizard` (in the tree, its components found): in an `invincible` room
## (the hub) hits take nothing from it.
func _take_room_rules(wizard: Actor) -> void:
	if wizard.health != null and _room != null:
		wizard.health.invincible = _room.invincible


func _spawn_wave(parent: Node2D, room: RoomBase, data: EnemyBase, number: int) -> void:
	_enemies.clear()
	_spawn_enemies(parent, room, data, wave_size(number))


## Add `count` enemies to `_enemies`, placed as a wave of that size is.
func _spawn_enemies(parent: Node2D, room: RoomBase, data: EnemyBase, count: int) -> void:
	var spawns: PackedVector2Array = room.places().enemy_spawns
	if spawns.is_empty():
		push_warning("Flow: the room has no enemy spawns, so the wave is empty.")
		return
	var uses: Dictionary = {}
	for at: int in count:
		# Wave 1 is WAVE as written; a bigger wave carries on round the spawns.
		var entry: int = WAVE[at] if at < WAVE.size() else at
		var spawn: int = entry % spawns.size()
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
		enemy.position = stacked_position(spawns[spawn], times)
		parent.add_child(enemy)
		_enemies.append(enemy)


## Stand the dummies the room's scene stands (`RoomPlaces.dummies`, each an enemy's data, at its
## place). One whose scene is no actor is skipped with a warning; the room runs without it.
func _spawn_dummies(parent: Node2D, room: RoomBase) -> void:
	var places: RoomPlaces = room.places()
	for i in places.dummies.size():
		var data: EnemyBase = places.dummies[i]
		var node: Node = data.scene.instantiate() if data.scene != null else null
		var dummy := node as Actor
		if dummy == null:
			push_warning("Flow: the dummy '%s' is not an actor, so it is skipped." % data.id)
			if node != null:
				node.free()
			continue
		dummy.data = data
		dummy.position = places.dummy_places[i]
		parent.add_child(dummy)
		_dummies.append(dummy)


## Stand the props the room's scene stands (`RoomPlaces.props`, at their places) and fill its prop
## yard (ZONE_PROP_YARD) with every prop of the registry that stands in one (`PropBase.in_yard`), in
## id order (`PropYard.places`; one that does not fit is left out with a warning).
func _spawn_props(parent: Node2D, room: RoomBase) -> void:
	var places: RoomPlaces = room.places()
	_props.clear()
	for i in places.props.size():
		var body: Actor = _stand_prop(parent, places.props[i], places.prop_places[i])
		if body != null:
			_props.append(body)
	_yard.clear()
	_yard_ids.clear()
	_yard_left.clear()
	_yard_places = PackedVector2Array()
	var yard: Rect2 = places.zone(ZONE_PROP_YARD)
	if not yard.has_area() or registry == null:
		return
	var kinds: Array[PropBase] = []
	for resource: Resource in registry.get_all(PROP_FOLDER):
		var data := resource as PropBase
		if data != null and data.in_yard and data.scene != null:
			kinds.append(data)
	var at: PackedVector2Array = PropYard.places(yard, kinds)
	for i in kinds.size():
		if at[i] == Vector2.INF:
			push_warning("Flow: the prop yard of '%s' is full; '%s' and the props after it do not stand there." % [room.id, kinds[i].id])
			break
		_yard_ids.append(kinds[i].id)
		_yard_places.append(at[i])
		_yard_left.append(-1.0)
		_yard.append(_stand_prop(parent, kinds[i], at[i]))


## A fresh body of the prop `data` (`PropBody.make`), its feet at `at`, added to `parent`; null
## (with a warning) when it makes none.
func _stand_prop(parent: Node2D, data: PropBase, at: Vector2) -> Actor:
	var body: Actor = PropBody.make(data) if data != null else null
	if body == null:
		push_warning("Flow: the prop '%s' has no body, so the room runs without it." % (data.id if data != null else &""))
		return null
	body.position = at
	parent.add_child(body)
	return body


## The yard's props: one that left its first state or went starts its slot's count
## (`PropYard.RETURN_SECONDS`); when it runs out the slot's body, if any, goes and a fresh one
## stands. A body going is forgotten in the tick it goes (the yard's state never points at a freed
## one).
func _tend_yard(delta: float) -> void:
	if _yard.is_empty() or world == null or _room == null or state == State.IDLE:
		return
	_forget_gone(_yard, true)
	for i in _yard.size():
		var prop := _yard[i] as Actor
		var fresh: bool = prop != null and (prop.state_triggers == null or prop.state_triggers.state == 0)
		if not fresh and _yard_left[i] < 0.0:
			_yard_left[i] = PropYard.RETURN_SECONDS
		if _yard_left[i] < 0.0:
			continue
		_yard_left[i] -= delta
		if _yard_left[i] > 0.0:
			continue
		_yard_left[i] = -1.0
		if prop != null:
			_detach(prop)
		_yard[i] = _stand_prop(world, registry.get_resource(PROP_FOLDER, _yard_ids[i]) as PropBase if registry != null else null, _yard_places[i])


## The bodies of `list` that went (freed, or dying: freed at the frame's end) are taken out of it,
## or, with `keep_slots`, left as null in their place.
func _forget_gone(list: Array[Node], keep_slots: bool = false) -> void:
	for i in range(list.size() - 1, -1, -1):
		var body: Node = list[i]
		if body == null or (is_instance_valid(body) and not (body is Actor and (body as Actor).is_dying())):
			continue
		if keep_slots:
			list[i] = null
		else:
			list.remove_at(i)


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
	_props.clear()
	_yard.clear()
	_yard_ids.clear()
	_yard_places.clear()
	_yard_left.clear()
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
