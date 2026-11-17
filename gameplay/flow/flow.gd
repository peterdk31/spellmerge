extends Node
## Flow (autoload `Flow`): starts a run's room, stands the enemies the run puts in it, announces
## `room_entered` and `room_cleared`, and ends the run when the room is won or every player is
## down. No waves (boss OB2a, docs/milestones/boss-old-broom.md, decision 30): a run is a path of
## rooms through its generated map (run generation, docs/milestones/run-generation.md), walked by its
## exits (RG4); the rest of the run comes in M3.
##
## Starting: `play_requested(player)` (the tests, the bots, the online spike). Flow
## begins the run `run_id_to_play` (`crypt`): the run area makes its map and names the first room
## and what stands in it (`run_begun`, answered by `run_room_chosen`; RG3), checks that
## the start recipes compile, builds one `Node2D` world (room scene, a wizard for every joined player,
## the room's enemies, a camera) and makes it the current scene, so the menu goes away. The
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
## A room's fight (boss OB2a, decision 31; run generation RG3): the enemies the run's map puts in it
## (`run_room_chosen`, ids of `EnemyBase.FOLDERS`: enemies and bosses; rooms hold layout only) stand
## at its enemy spawns as it starts, round the spawns in turn (`stacked_position` when one is used
## again). When the last is down, `room_cleared`. A room the run puts nothing in is cleared as it starts.
##
## The way on (run generation RG4): the run names with each room the kinds of the rooms it leads to
## (`run_room_chosen`'s `ways`). Cleared, its exits (props of the role `RoomBase.EXIT_ROLE`) light, one
## a way (`exits`, `ExitRules`), and when every standing wizard stands in one lit exit, Flow tells the
## run (`run_way_taken`), which answers with the room it leads to: the party enters it in the same run
## and the same recording, as it is (`_enter_next_room`: every wizard keeps its health, staffs and
## everything, a downed one stands up with the revive's health; nothing is dealt again, no run's start),
## and what was in the room left goes with it. The run's last room (no way on: the boss's, or the
## deepest fight of a run with no boss) cleared wins the run, and RUN_WON_DELAY seconds later it ends
## as a lost one does: from the hub's stone, back to the hub; from `play_requested`, a new run.
##
## Restart: when every wizard is down, a timer of RESTART_DELAY seconds runs, then
## a fresh world replaces the old one: a new run (its own seed, so its own map), new wizards at full
## health, no projectiles left, and `Spells` cleared (every cooldown and build is forgotten; each
## new wizard builds its start staffs again).
##
## Staffs (staffs A6a, docs/milestones/M2-staffs.md; living staffs H3; owner 2026-11-01: one
## staff file per setup, used as it is): every wizard gets the hands of its run's mode
## (`staffs_for_mode`), straight from the registry under `wizard`, never copied or changed: in
## Play and the hub the first two basic staffs of STARTER_HEADS on RB and RT (`content/wizard/staffs/`,
## each its own head; START_HANDS, items I2: the other two hands empty), in the sandbox four times the `dev` staff (DEV_STAFF: 20 slots,
## no delay, practically infinite mana). The build channel plays no part. With them the mode's
## cards (`start_cards_for_mode`; Play's `start_cards`: A `dash`, X `bolt`, Y and B empty),
## which the wizard builds itself; flow never touches a spell.
##
## Each mode's setup (owner, 2026-11-05): a new wizard gets the mode's staffs, start cards and
## card bag (the cards it may build with, counted: `bag_for_mode`, card id to copies, handed over
## with `seat_wizard`; items I3): Play one `dash` and one `bolt` (PLAY_BAG, `play_bag`: each entry
## a copy); the sandbox and the hub Inventory.DEV_COPIES of every card (the hub's for now, owner
## 2026-11-11: to try combos online until a better way to come by cards comes; owner 2026-11-13:
## 20 of each). The start cards come with their staffs, beside the bag.
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
## (`sandbox`): no fight of its own, the dummies its scene stands (`RoomPlaces.dummies`: the training dummy,
## the shooting dummy, then a group of training dummies to try homing, pierce and spreads on), and `sandbox_changed(true)` so the HUD shows the sandbox page. The page sends
## `sandbox_action_requested`: `clear_enemies` takes the enemies the arena spawned away,
## `reset_dummies` puts fresh dummies back; `sandbox_spawn_requested` (the enemy arena, enemy AI AI8)
## spawns any enemy or boss (`spawn_in_sandbox`, while fewer than SANDBOX_MAX are up). Clearing them ends
## nothing. When every wizard is down, after RESTART_DELAY they all stand up where they are and
## keep their staffs, instead of a restart. Its wizards hold four `dev` staffs and start with
## `sandbox_cards` (SANDBOX_START_CARDS), not `start_cards`: Play's A and X, and two showcase
## builds on Y (the most shots) and B (a decoy turret).
##
## The hub (docs/milestones/online-lobby.md, L1): `hub_requested` (the main menu's Play) starts a run
## in the hub room (`hub`), an island in the void where players join and leave as they like (coop's
## `player_joined` / `player_left`, at the room's spawns), try their staffs on the room's dummies,
## and are hurt by hits as anywhere, but a wizard downed there stands up by itself at full health
## `RoomBase.stand_up_after` seconds later (owner, 2026-11-13: duels between parties and test builds
## without consequences), and everyone down restarts nothing. Its wizards
## have Play's staffs (two, RB and RT: START_HANDS; items I2 took the `dev` staff off RT, the
## rack of items I6 replaces it), Play's start cards, and every card in the bag (above). Its teleporter stone (a
## prop of the role `run_start`, stood on where its area is) is lit while every wizard stands on it:
## counted each tick and whenever a wizard joins or leaves (`hub`, `HubRules`), told by
## `start_stone_changed`, the stone asked to enter `lit` or `unlit` to match, so its look and cue
## are the prop's (props W8).
## The command `run_requested` (a seat's A on the lit stone, from the HUD) starts a run at
## the tick's start, every wizard going in as the player it is: every bag, its staffs with their
## cards and its hands (owner, 2026-11-13: what a run's start takes along is the whole player; items
## I4, `start_run`'s `party`, a `PartyLoadout` of each wizard's `PlayerLoadout`); that run's end
## (everyone down) brings everyone back to the hub with nothing of the run, its staffs neither
## (owner, 2026-11-10: the hub is the arsenal a run's tools are picked from). A run started by
## `play_requested` restarts as before.
##
## Rooms (props W8a/W8c, docs/milestones/props.md): a run builds its room's layout once
## (`RoomBase.build()`) and reads what is where from that instance, the one it shows (`RoomPlaces`:
## spawns, doors, placements, zones, its size). The placements' stand-ins and the zones are taken out
## (`RoomPlaces.strip`), and the room's contents stand the real bodies (`contents`, `RoomContents`:
## props and dummies alike, by their data). The items it places (an `ItemStandIn`'s: items I6) are
## no bodies: Flow hands them to the Items area as the room starts (`room_items_placed`). The zone ZONE_PROP_YARD is the prop yard (`yard`,
## `PropYard`, props W8). The hub's rules (`hub`, `HubRules`) read the props by what they are
## (`PropBase.role`), never by id.
##
## Back to the main menu (`main_menu_requested`, the pause menu's "Main menu"): `stop_run`, so the
## world goes and Flow is idle, then the services are renewed as at a run's start
## (`Tick.begin_run`), so nothing of the run steps under the menu; the HUD shows the menu again, and
## the frames service and net/ end their part themselves. Not a command: only this machine leaves.
##
## A boss's intro (docs/milestones/boss-intro.md): at the end of a run's room's setup (a run's first
## room and the next room alike, `_open_boss_intro`), the first boss with an intro among the room's own
## enemies (`EnemyBase.boss_intro`; never the sandbox's spawns or a phase's adds) stops the game on
## that tick (`boss_intro`, `BossIntroHold`), when the run's rules have intros on
## (`SessionRules.boss_intros`, off for automation where `intro_enabled` is). The command
## `boss_intro_next_requested` (any seat's A, from the HUD) turns its pages; past the last the game goes
## on. It closes by itself when its boss leaves the tree (a step that runs through its stop: Flow's
## own does not run while the game is stopped) or the last seat leaves, and goes with the room's
## enemies. Presses made while it stood still, and on the tick it closes, are dropped
## (`Frames.drop_presses`), so a staff pressed during it casts nothing as the fight starts.
##
## Modes: `mode` says which run this is: MODE_RUN (a run of rooms), MODE_SANDBOX or MODE_HUB (above).
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
## The rooms' registry folder.
const ROOM_FOLDER: StringName = &"rooms"
## The registry folder of the run definitions (content/runs).
const RUN_FOLDER: StringName = &"runs"
## The run a run of rooms is unless `run_id_to_play` says otherwise (a run definition's id,
## content/runs).
const DEFAULT_RUN_ID: StringName = &"crypt"
## The two spells every wizard starts with: A is a fire bolt (M1's bolt plus burn), B a plain bolt.
## The cards each staff starts with in Play: A, X, Y, B (owner, 2026-11-05: dash and a bolt).
const DEFAULT_START_CARDS: Array = [[&"dash"], [&"bolt"], [], []]
## Play's bag: the cards a Play wizard may build with (owner, 2026-11-05), one copy an entry (items I3).
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
## The zone of a room's scene Flow gives a meaning (`RoomPlaces.zone`; a place that is no thing):
## the prop yard (props W8).
const ZONE_PROP_YARD: StringName = &"prop_yard"
## The run modes (`mode`): a run of rooms, the sandbox, the hub.
const MODE_RUN: StringName = &"run"
const MODE_SANDBOX: StringName = &"sandbox"
const MODE_HUB: StringName = &"hub"
## The cue played on every standing wizard as a run's room starts (`_show_room_start`).
const ROOM_START_CUE: StringName = &"room_start"
## The actions of `sandbox_action_requested`.
const ACTION_RESET_DUMMIES: StringName = &"reset_dummies"
## The enemy arena (enemy AI AI8): every enemy the sandbox spawned goes.
const ACTION_CLEAR_ENEMIES: StringName = &"clear_enemies"
## The sandbox's staff, on every button, and the four basic staffs of Play by
## button (RB, RT, LB, LT), by id under `wizard`.
const DEV_STAFF: StringName = &"dev"
const STARTER_HEADS: Array[StringName] = [&"curl", &"star", &"moon", &"crystal"]
## How many of STARTER_HEADS a wizard of Play and the hub holds, from RB on: two, RB and RT; the
## other hands are empty (items I2, owner 2026-11-13: players start with two staffs). The sandbox
## holds the `dev` staff on every hand.
const START_HANDS: int = 2
## Where the enemies stand: round the room's enemy spawns in turn; a spawn used again puts the next
## one a step further along the diagonal (SPAWN_STACK_DEPTH steps, then a lap to the side).
const SPAWN_REPEAT_OFFSET: Vector2 = Vector2(14.0, 14.0)
const SPAWN_STACK_DEPTH: int = 3
const SPAWN_LAP_OFFSET: Vector2 = Vector2(-14.0, 14.0)
## The most enemies the sandbox's enemy arena keeps up.
const SANDBOX_MAX: int = 24
## Seconds from a run's room won until the run ends: the kill seen out.
const RUN_WON_DELAY: float = 2.0
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
const DERIVED: Array[StringName] = [&"events", &"registry", &"frames", &"combat", &"projectiles", &"spells", &"world_parent", &"intro", &"loading", &"world", &"save", &"sandbox", &"_places", &"_layout", &"_layout_of", &"_asking", &"_chosen_room", &"_chosen_enemies", &"_chosen_ways"]
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_enemies", &"_wizards"]
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
## What the next run is made of, by registry id. Later features (the lectern, a loadout)
## set these; the runs, rooms, enemies and spell components themselves are content found by folder,
## so a new one needs no change here. `run_id_to_play` is the run definition a run of rooms begins
## (its rooms and what stands in them are its map's). `wizard_scene` is the wizard every player gets (its art is in
## the scene). The start recipes are component ids (a recipe as in `core/spells`).
var run_id_to_play: StringName = DEFAULT_RUN_ID
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
## The mode of the run in progress, or of the next one (MODE_RUN when idle).
var mode: StringName = MODE_RUN
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
var _wizards: Array[Node2D] = []
var _downed: Array[bool] = [false, false, false, false]
var _restart_left: float = -1.0
## By seat: seconds until that seat's downed wizard stands up by itself (`RoomBase.stand_up_after`,
## the hub), or -1 for none counting.
var _stand_up_left: Array[float] = [-1.0, -1.0, -1.0, -1.0]
## What is where in the room shown (read from the layout built for this run; worked out from it: a
## joining machine builds the same room by the same `start_run` before a snapshot, so nothing
## rebuilds it).
var _places: RoomPlaces = RoomPlaces.new()
## The bodies its placements stand, its prop yard and the hub's rules (props W8c).
var contents: RoomContents = RoomContents.new()
var yard: PropYard = PropYard.new()
var hub: HubRules = HubRules.new()
## The exits of a run's room and the ways they lead (run generation RG4).
var exits: ExitRules = ExitRules.new()
## The adds standing, each with the body that called it (boss plan OB13).
var adds: RoomAdds = RoomAdds.new()
## The boss's intro of the room (docs/milestones/boss-intro.md, `BossIntroHold`).
var boss_intro: BossIntroHold = BossIntroHold.new()
## The room's layout in the world, and the room it is of (a joining machine built the room the run
## started in: a snapshot taken in a later room lays that room's out again, `rebuild_derived`).
var _layout: Node = null
var _layout_of: StringName = &""
## True while the run in progress was started from the hub's stone: its end goes back there.
var _back_to_hub: bool = false
## Scratch: the run area's answer to `run_begun` or `run_way_taken` (`run_room_chosen`), taken only
## while Flow asks for it (`_asking`, `_room_asked`) and read by the same call.
var _asking: bool = false
var _chosen_room: StringName = &""
var _chosen_enemies: Array[StringName] = []
var _chosen_ways: Array[StringName] = []
## The party a run from the stone takes back to the hub when its map could not be made after the hub
## went (`PartyLoadout` bytes; empty: none): what a run starting now takes along (`_party_now`) until
## the hub starts again, so every wizard comes back as it went.
var _party_back: PackedByteArray = PackedByteArray()


func _ready() -> void:
	# The tick steps it (core/sim/tick.gd, core/sim/sim_area.gd).
	# Its intro's watch runs through the intro's own stop, when nothing else of Flow steps.
	SimArea.join(self, &"Flow").steps(&"Flow", step).steps(&"Flow", _watch_boss_intro, [BossIntroHold.STOP]).fresh_because(FRESH_BECAUSE)
	if save == null:
		save = SaveFile.new()
	if _is_automated():
		intro_enabled = false
		# Nobody is there to press A: the runs this machine starts have no boss intros (a rule, so
		# a replay of such a run plays back the same anywhere).
		SessionRules.machine().boss_intros = 0
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
		frames.set_party_source(_party_now)
	boss_intro.events = events
	if events == null:
		push_warning("Flow: the Events autoload is missing, so the game cannot be started.")
		return
	events.play_requested.connect(_on_play_requested)
	events.sandbox_requested.connect(_on_sandbox_requested)
	events.hub_requested.connect(_on_hub_requested)
	events.main_menu_requested.connect(_on_main_menu_requested)
	events.play_load_requested.connect(_on_play_load_requested)
	# Commands, heard at the tick's start (core/events, online-ready N2).
	events.listen(&"sandbox_action_requested", _on_sandbox_action_requested)
	events.listen(&"sandbox_spawn_requested", _on_sandbox_spawn_requested)
	events.listen(&"run_requested", _on_run_requested)
	events.listen(&"start_depth_picked", _on_start_depth_picked)
	events.listen(&"boss_intro_next_requested", _on_boss_intro_next_requested)
	events.enemy_died.connect(_on_enemy_died)
	events.player_downed.connect(_on_player_downed)
	events.player_revived.connect(_on_player_revived)
	events.player_joined.connect(_on_player_joined)
	events.player_left.connect(_on_player_left)
	events.run_room_chosen.connect(_on_run_room_chosen)
	events.adds_requested.connect(_on_adds_requested)


## Advance the intro and the run's end (restart) timer by `delta` seconds; the prop yard; in the hub,
## the stone.
func step(delta: float) -> void:
	if intro != null:
		intro.step(delta)
	contents.forget_gone()
	if world != null and state != State.IDLE:
		yard.tend(delta, world, registry)
		_crumble_orphans()
	_count_stand_ups(delta)
	if mode == MODE_HUB and state == State.RUNNING:
		_count_stone()
		return
	if mode == MODE_RUN and state == State.CLEARED and exits.open and world != null:
		var way: int = _count_exits()
		if way != ExitRules.NONE:
			_take_way(way)
			return
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
			_return_to_hub(_starter)
		elif not start_run(_starter):
			# A warning, not an error: the run ends cleanly and a test provokes this on purpose.
			push_warning("Flow: the restart failed, so the run is over; Play starts a new one.")
			stop_run()


## The party goes back to the hub, for seat `starter`, with nothing of the run (the run's end); with
## `party`, each seat as it says (a run from the stone that never started).
func _return_to_hub(starter: int, party: PartyLoadout = null) -> void:
	_back_to_hub = false
	if frames != null:
		# The hub is a run's start of its own: asked of the frames service, which sends it
		# between ticks, the same on every machine, and begins a new recording there
		# when this run is recorded (a recording never grows past one stretch of play).
		stop_run()
		if party != null:
			party.encode_into(_party_back)
		frames.restart(&"hub_requested", starter)
		return
	mode = MODE_HUB
	if not start_run(starter, party):
		push_warning("Flow: the hub did not start again after the run, so the run is over.")
		stop_run()


## True while the run's end (a restart, or the way back to the hub) is counting down.
func is_restarting() -> bool:
	return _restart_left >= 0.0


## Where the `times`-th enemy (0 = first) at `spawn` stands: up to SPAWN_STACK_DEPTH
## steps along the diagonal, then the next row starts a lap further to the side, so
## a stack never runs into a wall.
static func stacked_position(spawn: Vector2, times: int) -> Vector2:
	var step: int = times % SPAWN_STACK_DEPTH
	var lap: int = times / SPAWN_STACK_DEPTH
	return spawn + SPAWN_REPEAT_OFFSET * float(step) + SPAWN_LAP_OFFSET * float(lap)


## Enemies of the room's fight (or the sandbox's arena) still alive; never its dummies.
func enemies_left() -> int:
	return _enemies.size()


## The dummies of the sandbox or the hub still standing.
func dummies() -> Array[Node]:
	return contents.of_kind(EnemyBase)


## The props the room's scene stands, still standing (the hub's stone and altar).
func room_props() -> Array[Node]:
	return contents.of_kind(PropBase)


## The props standing in the prop yard now, by slot (null for a slot whose prop went and is not
## back yet).
func yard_props() -> Array[Node]:
	return yard.bodies()


## The wizard of player `index` in the current world (the actor whose home seat it is), or
## null. It stays the seat's wizard body while the seat drives another actor (possess, G9).
func get_wizard(index: int) -> Node2D:
	for wizard: Node2D in _wizards:
		if is_instance_valid(wizard) and _seat_of(wizard) == index:
			return wizard
	return null


## A run's room starting: its cue (ROOM_START_CUE, content/cues; S6, item 13) on every wizard
## standing in the world, so content gives the moment its look.
func _show_room_start() -> void:
	for wizard: Node2D in _wizards:
		var actor := wizard as Actor
		if actor != null and is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_down():
			events.cue_shown.emit(actor.id, ROOM_START_CUE, actor.global_position, Vector2.ZERO, 0.0, Color.WHITE, 0)


## The home seat of a wizard actor (its PlayerController's), or -1.
func _seat_of(wizard: Node) -> int:
	var controller: PlayerScript = PlayerScript.of(wizard)
	return controller.seat if controller != null else -1


## Build the world and start the run now, replacing any run in progress. `party` (as `_party_of`
## makes it; items I4) gives each seat's wizard the player it was before, everything it held (from
## the hub into a run, or the hub begun anew); a seat with no loadout there, and all of them with no
## `party`, starts with what its mode gives (its staffs, start cards and bag). A run of rooms
## (`MODE_RUN`) is the run `run_id_to_play`, its room the first of the map the run area makes, or
## the first of the row `start_depth` names (the lectern's pick, for the stone's run only;
## `_begin_run_of_rooms`). Returns false (and starts nothing) when content is missing or no player
## has a device; a map its rolls cornered (rare: only `KindRule.not_after` can) is found only once
## the last run's world went, so Flow is idle then.
func start_run(requester: int, party: PartyLoadout = null, start_depth: int = 0) -> bool:
	var room: RoomBase = null
	if mode == MODE_RUN:
		# What keeps the run's map from being made is asked before anything goes; only its rolls
		# (its seed, dealt below) can still corner it (`Registry.run_problems`).
		var problems: PackedStringArray = registry.run_problems(run_id_to_play) if registry != null else PackedStringArray(["No registry."])
		if not problems.is_empty():
			push_warning("Flow: the run '%s' cannot be made, so no run starts: %s" % [run_id_to_play, "; ".join(problems)])
			return false
	else:
		room = registry.get_resource(ROOM_FOLDER, _room_id_for_mode()) as RoomBase if registry != null else null
		if room == null or room.scene == null:
			push_warning("Flow: the room is missing from the registry, so no run starts.")
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
	_party_back = PackedByteArray()
	_restart_left = -1.0
	_stand_up_left.fill(-1.0)
	_clear_run()
	_wizard_scene = wizard_scene
	# The run starts from a fresh game's state (online-ready N3b): the one clock from 0, and every
	# service as a fresh one's (`Tick.begin_run`; the autoload, found on use).
	var tick: TickScript = TickScript.of(self) as TickScript
	if tick == null:
		push_error("Flow: the Tick autoload is missing, so the run starts on the last run's state.")
	else:
		tick.begin_run()
	exits.leave()
	if mode == MODE_HUB:
		hub.forget_start()
	if mode == MODE_RUN:
		room = _begin_run_of_rooms(players.size(), start_depth)
		if room == null:
			stop_run()
			return false
		exits.enter(_chosen_ways)
	_room = room
	var new_world := Node2D.new()
	new_world.name = WORLD_NAME
	# The bodies are drawn by their feet (view only): one standing in front of a prop is drawn over
	# it, one behind it under it. The room's layout, at the top left, is one piece drawn first, its
	# floor, walls and tops in their own order and z.
	new_world.y_sort_enabled = true
	_lay_out(new_world, room, tick.sim if tick != null else null)
	_spawn_players(new_world, room, players, party)
	contents.stand(new_world, _places, registry)
	for problem in contents.problems:
		push_warning("Flow: the room's bodies: %s" % problem)
	yard.fill(new_world, _places.zone(ZONE_PROP_YARD), registry)
	if mode == MODE_RUN:
		_stand_room_enemies(new_world, room, _chosen_enemies)
	world = new_world
	room_id = room.id
	state = State.RUNNING
	_show_world(new_world)
	_set_walls(new_world)
	_announce_room(room)
	if events != null:
		events.sandbox_changed.emit(mode == MODE_SANDBOX)
		if mode == MODE_RUN:
			_show_room_start()
	_count_stone()
	_count_exits()
	_check_room_won()
	_open_boss_intro()
	return true


## Lay `room`'s layout in `into` (a world), built once by the run's chance `sim`, under everything
## else: what is where is read from the layout shown (props W8c, `_places`), the stand-ins and zones
## taken out (the editor's: the bodies are stood by the room's places), the shots kept to the room,
## and its camera. Any layout and camera there were go. Whoever needs the layout itself (the ground
## cover, worked out from its walls, places and fields) hears it as `room_built`, before the stand-ins
## and zones are taken out (ground cover GC2).
func _lay_out(into: Node2D, room: RoomBase, sim: Sim) -> void:
	if _layout != null and is_instance_valid(_layout):
		_detach(_layout)
	var layout: Node = room.build(sim)
	_places = RoomPlaces.read(layout)
	for problem in _places.problems():
		push_warning("Flow: the room '%s': %s" % [room.id, problem])
	# Told while its placements and zones are still in it (the cover's fields), before they go.
	if events != null and layout != null:
		events.room_built.emit(room.id, layout)
	RoomPlaces.strip(layout)
	if projectiles != null:
		projectiles.set_bounds(Rect2(Vector2.ZERO, _places.size).grow(PROJECTILE_MARGIN))
	into.add_child(layout)
	into.move_child(layout, 0)
	_layout = layout
	_layout_of = room.id
	_add_camera(into, _places.size)


## After a snapshot was restored (core/sim/README.md, "Snapshots"): a joining machine built the room
## the run started in, so a snapshot taken after the party went on lays out the room it is in now.
## Its bodies are the snapshot's own. The layout is built again by the run's chance as it is now:
## the same as the host's while rooms are fixed scenes (`RoomBase.build` ignores it); a room put
## together from pieces (M3) must build from what does not move on (its node's own key).
func rebuild_derived() -> void:
	if world == null or not is_instance_valid(world) or _room == null or _layout_of == _room.id:
		return
	var tick: TickScript = TickScript.of(self) as TickScript
	_lay_out(world, _room, tick.sim if tick != null else null)
	_set_walls(world)


## The room the next run of the sandbox or the hub is in (a run of rooms' is its map's).
func _room_id_for_mode() -> StringName:
	return SANDBOX_ROOM_ID if mode == MODE_SANDBOX else HUB_ROOM_ID


## A run of rooms begins (on the run's fresh state, after `Tick.begin_run`): the run area makes the
## map of `run_id_to_play` and answers with its first room and what stands in it (`run_begun`,
## `run_room_chosen`; run generation RG3). The room, or null (with a warning) when no answer came or
## the registry lacks the room it names. The run is made for `players` players (the seats joined at
## its start; run generation RG5) and entered at `start_depth` (the lectern's pick for the stone's
## run, run generation RG7; 0 for every other: its first room).
func _begin_run_of_rooms(players: int, start_depth: int) -> RoomBase:
	var room: RoomBase = _room_asked(func() -> void: events.run_begun.emit(run_id_to_play, players, start_depth))
	if room == null:
		push_warning("Flow: the run '%s' gave no room it could build (its map could not be made, or its room is missing), so no run starts." % run_id_to_play)
	return room


## The room the run area names in answer to what `ask` sends (`run_room_chosen`: `run_begun` for the
## first room, `run_way_taken` for the next), with what stands in it and its ways (`_chosen_*`); null,
## with a warning, when no answer came or the registry lacks the room it names.
func _room_asked(ask: Callable) -> RoomBase:
	_chosen_room = &""
	_chosen_enemies = [] as Array[StringName]
	_chosen_ways = [] as Array[StringName]
	if events == null:
		return null
	_asking = true
	ask.call()
	_asking = false
	if _chosen_room == &"":
		return null
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, _chosen_room) as RoomBase if registry != null else null
	if room == null or room.scene == null:
		push_warning("Flow: the run's room '%s' is missing from the registry." % _chosen_room)
		return null
	return room


## The run area's answer: the room of the run's map the party enters, what stands in it and the
## kinds of the rooms it leads to (copies of its own). Heard only while Flow asks (`_room_asked`).
func _on_run_room_chosen(room: StringName, enemies: Array[StringName], ways: Array[StringName]) -> void:
	if not _asking:
		return
	_chosen_room = room
	_chosen_enemies = enemies.duplicate()
	_chosen_ways = ways.duplicate()


## The exits of a run's room counted (`ExitRules.count`): each lit or dark as its way says, the view
## told, and the way every standing wizard stands in (ExitRules.NONE for none).
func _count_exits() -> int:
	return exits.count(_wizards, contents, events)


## Every standing wizard stands in the lit exit of way `way`: the run moves on through its map
## (`run_way_taken`) and the party enters the room it names. A room the run cannot name keeps the
## party where it is (a warning).
func _take_way(way: int) -> void:
	var room: RoomBase = _room_asked(func() -> void: events.run_way_taken.emit(way))
	if room == null:
		# The run and its exits disagree (never in play): the room is the run's last, so the run
		# is won, once, rather than the party held in an exit that leads nowhere.
		push_error("Flow: the way %d out of the room '%s' leads to no room, so the run ends here." % [way, room_id])
		exits.leave()
		_count_exits()
		if _restart_left < 0.0:
			_restart_left = RUN_WON_DELAY
		return
	_enter_next_room(room)


## The party goes on into `room`, the run's next room (run generation RG4), in the same world, run
## and recording: no run's start, nothing dealt again. Everything of the room left goes: what was cast
## in it (`room_left`: Spells ends its carriers, holds and waiting launches quietly), the shots in
## flight, its layout and bodies; every wizard stays itself, as it is (health, staffs, cards, bag,
## everything), stood at its seat's spawn, a downed one up again with the revive's health (owner,
## 2026-11-15), each protected for a moment; then the room's bodies and enemies stand, as at a run's
## start, and the room is entered.
func _enter_next_room(room: RoomBase) -> void:
	if events != null:
		events.room_left.emit()
	if projectiles != null:
		projectiles.clear()
	_forget_enemies()
	contents.clear()
	yard.clear()
	for child: Node in world.get_children():
		if not (child is Node2D and _wizards.has(child as Node2D)):
			_detach(child)
	_layout = null
	_room = room
	_restart_left = -1.0
	_stand_up_left.fill(-1.0)
	var tick: TickScript = TickScript.of(self) as TickScript
	_lay_out(world, room, tick.sim if tick != null else null)
	for wizard: Node2D in _wizards:
		_bring_in(wizard)
	contents.stand(world, _places, registry)
	for problem in contents.problems:
		push_warning("Flow: the room's bodies: %s" % problem)
	_stand_room_enemies(world, room, _chosen_enemies)
	exits.enter(_chosen_ways)
	room_id = room.id
	state = State.RUNNING
	_set_walls(world)
	_announce_room(room)
	if events != null:
		_show_room_start()
	_count_exits()
	_check_room_won()
	_open_boss_intro()


## The end of a run's room's setup (the world in the tree, its ids open, the room announced): the
## first boss with an intro among the room's own enemies opens it, and the game stops on this tick.
func _open_boss_intro() -> void:
	if mode == MODE_RUN and state == State.RUNNING:
		boss_intro.open_in(_enemies, Sim.found(self))


## A seat pressed A on page `page` of the boss's intro (a command, at the tick's start): the page
## turns while it is still that page, and past the last the game goes on.
func _on_boss_intro_next_requested(player: int, page: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	if boss_intro.turn(page, Sim.found(self)):
		_drop_stood_presses()


## Flow's step through the intro's stop: the intro closes when its boss left the tree.
func _watch_boss_intro(_delta: float) -> void:
	if boss_intro.watch(Sim.found(self)):
		_drop_stood_presses()


## The intro closed: the presses of the ticks it stood still, and of this one, never reach the fight.
func _drop_stood_presses() -> void:
	if frames != null:
		frames.drop_presses()


## The room `room` stands in the world shown: `room_entered`, and the items its scene places
## (`room_items_placed`), at a run's start and as the party goes on into the next room alike.
func _announce_room(room: RoomBase) -> void:
	if events == null:
		return
	events.room_entered.emit(room.id)
	var items: Array = RoomContents.items_of(_places)
	events.room_items_placed.emit(room.id, items[0], items[1])


## A wizard of the party comes into the next room: at its seat's spawn, still (its moves, a dash's
## or a pull's, end there), up again if it was down (the revive's health), protected for a moment.
func _bring_in(wizard: Node2D) -> void:
	if not is_instance_valid(wizard):
		return
	var seat: int = _seat_of(wizard)
	if seat >= 0 and seat < _places.player_spawns.size():
		wizard.position = _places.player_spawns[seat]
	var actor := wizard as Actor
	if actor != null:
		# Still, out of any fall, with no last ground yet (hub rework HR-H2).
		actor.placed()
	var hero: DownedScript = DownedScript.of(wizard)
	if hero == null:
		return
	if hero.revive(seat) and seat >= 0 and seat < PLAYER_SLOTS:
		_downed[seat] = false
	hero.protect(DownedScript.JOIN_PROTECTION)


## End the run in progress and free its world. Flow is idle again, so the next
## `play_requested` starts a run. The main menu is the HUD's to show (`main_menu_requested`).
func stop_run() -> void:
	if state == State.LOADING and loading != null:
		loading.cancel()
	if intro != null:
		var shown: IntroScript = intro
		intro = null
		if is_instance_valid(shown):
			_detach(shown)
	_restart_left = -1.0
	_stand_up_left.fill(-1.0)
	_back_to_hub = false
	_party_back = PackedByteArray()
	_clear_run()
	state = State.IDLE
	exits.leave()
	_count_exits()
	var was: StringName = mode
	mode = MODE_RUN
	if was == MODE_SANDBOX and events != null:
		events.sandbox_changed.emit(false)
	_count_stone()


## This machine goes back to the main menu (`main_menu_requested`, the pause menu): the run, the
## intro or the loading stops and its world goes; the HUD shows the menu.
func _on_main_menu_requested(_player: int) -> void:
	stop_run()
	# Every service as a fresh game's (as a run's start makes them, after its bodies left with the
	# world above): no shot, decoy or stop of the run goes on under the menu.
	var tick: TickScript = TickScript.of(self) as TickScript
	if tick != null:
		tick.begin_run()


func _on_play_requested(player: int) -> void:
	if state != State.IDLE:
		return
	if not _load_then(_start_play.bind(player)):
		_start_play(player)


## Play, once the work before a room is loaded: the intro first on a new save, else the run.
func _start_play(player: int) -> void:
	mode = MODE_RUN
	_back_to_hub = false
	_intro_then_run(player)


## The intro first on a new save (the run of `mode` starts when it ends), else the run now, its
## seats' wizards as `party` says (as `start_run` takes it; the intro keeps none).
func _intro_then_run(player: int, party: PartyLoadout = null) -> void:
	# Never in a run that is recorded or played back: the intro takes the machine's own time, and
	# a recording must start the same on the machine that made it and on every one that plays it.
	if wants_intro() and not (frames != null and (frames.is_recording() or frames.is_playing())):
		play_intro(player)
	else:
		start_run(player, party)


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
		mode = MODE_RUN


func _on_hub_requested(player: int) -> void:
	# What the hub's wizards take along (the recording's, read before the hub it was made in goes).
	var party: PartyLoadout = frames.next_run_party() if frames != null else null
	# Read once: a hub that then fails to start leaves no party behind for a later recording.
	_party_back = PackedByteArray()
	# Asked for in the hub, the hub starts anew (a recording of it begins: net/ opens the room), each
	# wizard with everything it held.
	if state == State.RUNNING and mode == MODE_HUB:
		stop_run()
	if state != State.IDLE:
		return
	if not _load_then(_start_hub.bind(player, party)):
		_start_hub(player, party)


## The hub, once the work before a room is loaded: after the intro on a new save, as Play's run;
## each seat's wizard as `party` says (a seat with no loadout: the hub's staffs, start cards and bag).
func _start_hub(player: int, party: PartyLoadout = null) -> void:
	mode = MODE_HUB
	_back_to_hub = false
	_intro_then_run(player, party)
	if state == State.IDLE:
		# Nothing started (content missing): idle is MODE_RUN.
		mode = MODE_RUN


## The command `run_requested` (a seat pressed A on the lit stone; the HUD sends it, heard at the
## tick's start): the run starts, for that seat, while the stone is lit. The stone's count
## is the last tick's, made again when a wizard joined or left since, so it is exact here.
func _on_run_requested(player: int) -> void:
	if not is_stone_lit() or state != State.RUNNING or get_wizard(player) == null:
		return
	_start_run_from_stone(player)


## The command `start_depth_picked` (a seat's pick on its lectern menu, run generation RG7; heard at
## the tick's start): in the hub, while that seat's wizard stood at the lectern at the last count,
## the stone's run starts at that depth of its map (within the depths offered; `HubRules.pick`).
func _on_start_depth_picked(player: int, depth: int) -> void:
	if mode != MODE_HUB or state != State.RUNNING or get_wizard(player) == null:
		return
	hub.pick(player, depth, start_depths())


## How many depths the lectern offers the stone's run to start at: the run definition
## `run_id_to_play`'s (`RunDefinition.start_depths`; 0 when the registry lacks it).
func start_depths() -> int:
	var definition: RunDefinition = registry.get_resource(RUN_FOLDER, run_id_to_play) as RunDefinition if registry != null else null
	return definition.start_depths() if definition != null else 0


## The run, from the hub's stone, for seat `seat`: every wizard goes in as the player it
## is, with every bag, its staffs and its hands (owner, 2026-11-13: what a run's start takes along
## is the whole player), and the run's end brings everyone back to the hub.
func _start_run_from_stone(seat: int) -> void:
	var party: PartyLoadout = _party_of()
	mode = MODE_RUN
	_back_to_hub = true
	if not start_run(seat, party, hub.start_depth):
		if state == State.IDLE:
			# The hub went before the run's map was found cornered: the party goes back there, each
			# wizard as it went.
			push_warning("Flow: the run from the stone did not start, so the party goes back to the hub.")
			_return_to_hub(seat, party)
			return
		# It refused before freeing anything (content missing): the hub stands as it was.
		push_warning("Flow: the run from the stone did not start, so the party stays in the hub.")
		_back_to_hub = false
		mode = MODE_HUB


## Every wizard's player loadout now, by its seat (items I4): what `start_run` makes each seat's
## wizard from, so the whole player follows the party from the hub into the run (owner,
## 2026-11-13); nothing comes back from it.
func _party_of() -> PartyLoadout:
	var out := PartyLoadout.new()
	for wizard: Node2D in _wizards:
		var seat: int = _seat_of(wizard) if is_instance_valid(wizard) else -1
		if seat >= 0 and seat < PLAYER_SLOTS:
			out.put(seat, PlayerScript.loadout_of(wizard as Actor))
	return out


## What a run that starts now takes along (the frames service asks, and writes it into a recording's
## header; core/sim/party_loadout.gd): in the hub, every wizard's loadout, so the hub begun anew for a
## joining machine keeps them, on every machine; on the way back from a run from the stone that never
## started, the party that went (`_party_back`); anywhere else nothing, since nothing comes back
## from a run (owner, 2026-11-10).
func _party_now() -> PartyLoadout:
	if mode == MODE_HUB and state == State.RUNNING:
		return _party_of()
	var back := PartyLoadout.new()
	if _party_back.is_empty():
		return back
	var problem: String = back.decode_at(_party_back, 0)
	if problem != "":
		push_warning("Flow: the party going back to the hub could not be read (%s), so it takes nothing." % problem)
		return PartyLoadout.new()
	return back


## The wizards in the world now.
func _wizard_count() -> int:
	var count: int = 0
	for wizard: Node2D in _wizards:
		if is_instance_valid(wizard):
			count += 1
	return count


## True while the hub's stone is lit: every wizard of the hub stands on it, and there is one.
func is_stone_lit() -> bool:
	return mode == MODE_HUB and hub.is_lit()


## The hub's rules count the wizards on its stone and altar (none out of the hub), light the stone
## and tell what changed (`HubRules.count`).
func _count_stone() -> void:
	var in_hub: bool = mode == MODE_HUB and state != State.IDLE and _room != null
	hub.count(in_hub, _wizards, contents, events, start_depths() if in_hub else 0)


## A sandbox page's action. Ignored out of the sandbox. It changes the room only, never a
## player's staffs or menus.
func _on_sandbox_action_requested(player: int, action: StringName) -> void:
	if mode != MODE_SANDBOX or state == State.IDLE or world == null or _room == null or player < 0 or player >= PLAYER_SLOTS:
		return
	match action:
		ACTION_CLEAR_ENEMIES:
			clear_sandbox_enemies()
		ACTION_RESET_DUMMIES:
			contents.stand_again(world, _places, EnemyBase)
		_:
			push_warning("Flow: unknown sandbox action '%s'." % action)


## The enemy arena's spawn (enemy AI AI8): `count` enemies of `enemy_id`. Ignored out of the sandbox.
func _on_sandbox_spawn_requested(player: int, enemy_id: StringName, count: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	spawn_in_sandbox(enemy_id, count)


## Put `count` enemies of the registry's `enemy_id` in the sandbox room, at its enemy spawns, while
## fewer than SANDBOX_MAX are up (the enemy arena: to play against one kind, or tune it; tests use it
## too). Returns how many came; 0 out of a sandbox run or for an unknown id.
func spawn_in_sandbox(enemy_id: StringName, count: int) -> int:
	if mode != MODE_SANDBOX or state == State.IDLE or world == null or _room == null or registry == null:
		return 0
	var data: EnemyBase = _enemy_data_of(enemy_id)
	if data == null or data.scene == null:
		push_warning("Flow: no enemy '%s' to spawn in the sandbox." % enemy_id)
		return 0
	var room_left: int = SANDBOX_MAX - _enemies.size()
	var wanted: int = clampi(count, 0, room_left)
	var before: int = _enemies.size()
	_spawn_enemies(world, data, wanted, before)
	return _enemies.size() - before


## Every enemy the sandbox spawned goes (its dummies stay).
func clear_sandbox_enemies() -> void:
	for enemy: Node in _enemies:
		if is_instance_valid(enemy):
			_detach(enemy)
	_forget_enemies()


## Add the wizard of a player who joined mid-run: at the room's spawn for joiners when it has them
## (the hub: beside the altar, where a joining machine's wizards arrive), else at the player spawn
## farthest from danger. Ignored while no run is up, and for a slot that already has a wizard.
func _on_player_joined(player: int) -> void:
	if state == State.IDLE or world == null or _room == null or player < 0 or player >= PLAYER_SLOTS:
		return
	if get_wizard(player) != null:
		return
	var joiners: PackedVector2Array = _places.joiner_spawns
	var at: Vector2 = joiners[player] if player < joiners.size() else _joiner_spawn(_room, player)
	_add_wizard(world, _room, player, at)
	_count_players()
	var joiner: DownedScript = DownedScript.of(get_wizard(player))
	# In a room where a fall costs nothing (the hub), a joiner needs no moment of protection.
	if joiner != null and not _stands_up_by_itself():
		joiner.protect(DownedScript.JOIN_PROTECTION)
	_downed[player] = false
	_stand_up_left[player] = -1.0
	if _can_be_lost() and _restart_left >= 0.0 and not _all_down():
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
	_stand_up_left[player] = -1.0
	var parent: Node = wizard.get_parent()
	if parent != null:
		parent.remove_child(wizard)
	wizard.queue_free()
	_count_players()
	_count_stone()
	# Nobody is left to press A, and Flow does not step while the intro stops the game.
	if _wizards.is_empty() and boss_intro.close(Sim.found(self)):
		_drop_stood_presses()
	if _can_be_lost() and _restart_left < 0.0 and _all_down() and not _stands_up_by_itself():
		_restart_left = restart_delay()


func _on_enemy_died(_player: int, enemy: Node, _position: Vector2, _shot: int) -> void:
	contents.forget(enemy)
	adds.orphan(enemy)
	var at: int = _enemies.find(enemy)
	if at < 0:
		return
	_enemies.remove_at(at)
	_check_room_won()


## A run's room with no enemy left is cleared (decision 30): `room_cleared`. Its exits light, one a
## way on (run generation RG4); the run's last room (no way on) wins the run, which ends
## RUN_WON_DELAY seconds later, as a lost one does.
func _check_room_won() -> void:
	if not _enemies.is_empty() or state != State.RUNNING or mode != MODE_RUN:
		return
	state = State.CLEARED
	var last: bool = exits.ways.is_empty()
	# Everyone already down (the last enemy fell to a shot still flying): that end keeps its time.
	if last and _restart_left < 0.0:
		_restart_left = RUN_WON_DELAY
	if events != null:
		events.room_cleared.emit(room_id)
	if not last:
		exits.open = true
		_count_exits()


## True while everyone down ends the run: in a run's room under way, or in a cleared one its exits
## lead on from (the last room won ends the run by itself).
func _can_be_lost() -> bool:
	return state == State.RUNNING or (state == State.CLEARED and exits.open)


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
	if _stands_up_by_itself():
		# Every fall there costs nothing: the wizard stands up by itself, and nothing restarts.
		_stand_up_left[player] = _room.stand_up_after
		return
	if _can_be_lost() and _all_down() and _restart_left < 0.0:
		_restart_left = restart_delay()


## True while the run's room stands a downed wizard up by itself (`RoomBase.stand_up_after`: the hub).
func _stands_up_by_itself() -> bool:
	return state != State.IDLE and _room != null and _room.stand_up_after >= 0.0


## Count each seat's stand-up down by `delta`; at 0 its wizard stands up where it fell, at full
## health, protected for a moment (`_stand_up`).
func _count_stand_ups(delta: float) -> void:
	for seat in PLAYER_SLOTS:
		if _stand_up_left[seat] < 0.0:
			continue
		_stand_up_left[seat] -= delta
		if _stand_up_left[seat] <= 0.0:
			_stand_up_left[seat] = -1.0
			_stand_up(seat)


## Seat `seat`'s downed wizard stands up by itself at full health, protected for a moment.
func _stand_up(seat: int) -> void:
	var wizard: Node2D = get_wizard(seat)
	var hero: DownedScript = DownedScript.of(wizard) if wizard != null else null
	if hero == null:
		return
	var full: float = (wizard as Actor).health.max_health if (wizard as Actor).health != null else DownedScript.REVIVE_HEALTH
	if hero.revive(seat, full):
		_downed[seat] = false
	hero.protect(DownedScript.JOIN_PROTECTION)


## Seconds from everyone down until the restart (or, in the sandbox, until everyone stands up).
func restart_delay() -> float:
	return RESTART_DELAY


func _on_player_revived(player: int, _reviver: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS:
		return
	_downed[player] = false
	_stand_up_left[player] = -1.0
	if _can_be_lost() and _restart_left >= 0.0 and not _all_down():
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


## Tell the projectile manager where the walls and holes are: every static body on the wall layer
## (`RoomBase.WALL_LAYER`) of the room, and every one on exactly the hole layer (`HOLE_LAYER`). The
## world must be in the tree.
func _set_walls(new_world: Node2D) -> void:
	if projectiles == null or not new_world.is_inside_tree():
		return
	projectiles.clear_walls()
	for node: Node in new_world.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if (body.collision_layer & RoomBase.WALL_LAYER) != 0:
			projectiles.add_wall_body(body)
		elif body.collision_layer == RoomBase.HOLE_LAYER:
			# The room's holes (hub rework HR-H1, RoomBase.HOLE_LAYER), in their own grid.
			projectiles.add_hole_body(body)
	# Outside the room is the void in a room with holes (hub rework HR-H2, question 9).
	projectiles.set_holes_outside(Rect2(Vector2.ZERO, _places.size) if _places != null else projectiles.bounds())


func _add_camera(parent: Node2D, size: Vector2) -> void:
	for old: Node in parent.get_children():
		if old is Camera2D:
			_detach(old)
	var camera := Camera2D.new()
	camera.position = size * 0.5
	# Feel's party camera moves and zooms it to hold this machine's wizards; the limits keep it
	# inside the room.
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ceili(size.x)
	camera.limit_bottom = ceili(size.y)
	# The picture shows this room from the moment it is in the tree, whatever camera was current.
	camera.ready.connect(camera.make_current, CONNECT_ONE_SHOT)
	parent.add_child(camera)


func _spawn_players(parent: Node2D, room: RoomBase, players: Array[int], party: PartyLoadout = null) -> void:
	_wizards.clear()
	for index in PLAYER_SLOTS:
		_downed[index] = false
	for index: int in players:
		_add_wizard(parent, room, index, Vector2.INF, party.of(index) if party != null else null)


## The player spawn for a mid-run joiner: the one farthest from every enemy and
## every wizard already there (the joiner's own slot wins a tie).
func _joiner_spawn(room: RoomBase, index: int) -> Vector2:
	var spawns: PackedVector2Array = _places.player_spawns
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


## The four hands of a wizard of this run's `mode`, by button, as the registry has their staffs:
## the sandbox's the `dev` staff on every button, Play's and the hub's the first START_HANDS basic
## staffs (STARTER_HEADS) and null for an empty hand after them. Empty when one is missing.
func staffs_for_mode() -> Array[StaffBase]:
	var ids: Array[StringName] = []
	for at in STARTER_HEADS.size():
		ids.append(STARTER_HEADS[at] if at < START_HANDS else &"")
	if mode == MODE_SANDBOX:
		ids = [DEV_STAFF, DEV_STAFF, DEV_STAFF, DEV_STAFF]
	var out: Array[StaffBase] = []
	if registry == null:
		return out
	for id in ids:
		if id == &"":
			out.append(null)
			continue
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


## The card bag a new wizard gets in this run's `mode`, card id to copies (items I3):
## Inventory.DEV_COPIES of every spell card of the registry in the sandbox and the hub, `play_bag`
## in Play (an entry a copy).
func bag_for_mode() -> Dictionary:
	var out: Dictionary = {}
	match mode:
		MODE_SANDBOX, MODE_HUB:
			out = Inventory.dev_cards(registry)
		_:
			for id: StringName in play_bag:
				out[id] = int(out.get(id, 0)) + 1
	return out


## Add the wizard of seat `index` at `at` (INF: its spawn): the player `loadout` says (items I4,
## `PlayerController.seat_loadout`), or with none the mode's staffs, start cards and bag.
func _add_wizard(parent: Node2D, room: RoomBase, index: int, at: Vector2 = Vector2.INF, loadout: PlayerLoadout = null) -> void:
	var wizard := _wizard_scene.instantiate() as Actor
	if loadout != null:
		PlayerScript.seat_loadout(wizard, index, loadout, registry)
	else:
		PlayerScript.seat_wizard(wizard, index, null, start_cards_for_mode().duplicate(true), staffs_for_mode(), bag_for_mode())
	if at != Vector2.INF:
		wizard.position = at
	elif index < _places.player_spawns.size():
		wizard.position = _places.player_spawns[index]
	# Its hurtbox registers it with Combat when it enters the tree.
	parent.add_child(wizard)
	_wizards.append(wizard)


## The enemies the run puts in the room (`enemies`: ids, one per body) stand at its enemy spawns,
## round them in turn. An id the registry has no enemy or boss for stands nothing (a warning).
func _stand_room_enemies(parent: Node2D, room: RoomBase, enemies: Array[StringName]) -> void:
	_forget_enemies()
	var placed: int = 0
	if not enemies.is_empty() and _places.enemy_spawns.is_empty():
		push_warning("Flow: the room '%s' has no enemy spawns, so its enemies cannot stand." % room.id)
		return
	for id: StringName in enemies:
		var data: EnemyBase = _enemy_data_of(id)
		if data == null or data.scene == null:
			push_warning("Flow: the run puts '%s' in the room '%s', which the registry has no enemy or boss for." % [id, room.id])
			continue
		_spawn_enemies(parent, data, 1, placed)
		placed += 1


## The enemy or boss `enemy_id` (`EnemyBase.FOLDERS`, in turn), or null.
func _enemy_data_of(enemy_id: StringName) -> EnemyBase:
	if registry == null:
		return null
	for folder: StringName in EnemyBase.FOLDERS:
		var data: EnemyBase = registry.get_resource(folder, enemy_id) as EnemyBase
		if data != null:
			return data
	return null


## Add `count` enemies of `data` to `_enemies`, the first as the `first`-th of the room's fight: each
## at the next enemy spawn in turn, stacked where a spawn is used again (`stacked_position`), told
## to difficulty before it stands (`enemy_standing`: scaled to the room).
func _spawn_enemies(parent: Node2D, data: EnemyBase, count: int, first: int) -> void:
	var spawns: PackedVector2Array = _places.enemy_spawns
	if spawns.is_empty():
		push_warning("Flow: the room has no enemy spawns, so its enemies cannot stand.")
		return
	for at: int in count:
		var nth: int = first + at
		var spawn: int = nth % spawns.size()
		var times: int = nth / spawns.size()
		_stand_enemy(parent, data, stacked_position(spawns[spawn], times))


## One enemy of `data` stands at `at` in `parent`, among the room's fight: counted for the wizards in
## play (`Actor.players`, boss plan OB13) and told to difficulty (`enemy_standing`: scaled to the
## room, run generation RG5), both before its data is applied. Null when no body could be made.
func _stand_enemy(parent: Node2D, data: EnemyBase, at: Vector2) -> Actor:
	var enemy := RoomContents.make_body(data) as Actor
	if enemy == null:
		return null
	enemy.position = at
	enemy.players = _players_in_play()
	if events != null:
		events.enemy_standing.emit(enemy)
	parent.add_child(enemy)
	_enemies.append(enemy)
	return enemy


## The room's enemies are forgotten (they went with the room, or the sandbox's arena was cleared),
## their adds and the boss's intro too (closed if open: the game goes on).
func _forget_enemies() -> void:
	_enemies.clear()
	adds.clear()
	var was_open: bool = boss_intro.opened
	boss_intro.clear(Sim.found(self))
	if was_open:
		_drop_stood_presses()


## The wizards in play (1 at least): what an enemy's health and a phase's adds are counted for.
func _players_in_play() -> int:
	return maxi(_wizards.size(), 1)


## A wizard joined or left: every enemy standing counts the wizards in play again (its health by
## `EnemyBase.health_per_player`, keeping its share).
func _count_players() -> void:
	var players: int = _players_in_play()
	for enemy: Node in _enemies:
		var actor := enemy as Actor
		if actor != null and is_instance_valid(actor):
			actor.count_players(players)


## The body `actor` calls the adds `entry` (its entry `key`; a `wave` or its phase's burst; boss plan
## OB13): as many as the entry names for the wizards in play, under its cap of those alive (and the
## sandbox's most), on a ring round the body or at the room's enemy spawns. Only for a body Flow stood,
## while a room is up; an id the registry has no enemy for stands nothing (a warning).
func _on_adds_requested(actor: int, entry: EnemyAdds, key: int, wave: bool) -> void:
	if entry == null or world == null or state == State.IDLE:
		return
	var caller: Actor = _enemy_of(actor)
	if caller == null:
		return
	var data: EnemyBase = _enemy_data_of(entry.enemy)
	if data == null or data.scene == null:
		push_warning("Flow: '%s' calls the adds '%s', which the registry has no enemy for." % [caller.name, entry.enemy])
		return
	var players: int = _players_in_play()
	var wanted: int = entry.wave_for(players) if wave else entry.burst_for(players)
	var count: int = entry.allowed(wanted, adds.alive(caller, key), players)
	if mode == MODE_SANDBOX:
		count = mini(count, maxi(SANDBOX_MAX - _enemies.size(), 0))
	var spawns: PackedVector2Array = _places.enemy_spawns
	var at_spawns: bool = entry.at == EnemyAdds.At.SPAWNS and not spawns.is_empty()
	var centre: Vector2 = world.to_local(caller.global_position)
	var reach: float = caller.hurtbox.outer_radius() if caller.hurtbox != null else caller.wall_radius()
	var slide: Callable = projectiles.grid().slide_body if projectiles != null else Callable()
	var radius: float = _body_radius_of(data)
	var turn: int = adds.stood
	for n: int in count:
		var at: Vector2
		if at_spawns:
			at = stacked_position(spawns[adds.stood % spawns.size()], adds.stood / spawns.size())
		else:
			at = RoomAdds.ring(centre, reach, radius, n, count, slide, turn)
			if projectiles != null and projectiles.grid().touches_hole(world.to_global(at), radius):
				# A spot on the ring over a hole takes the nearest ground (hub rework HR-H2).
				at = world.to_local(projectiles.grid().nearest_ground(world.to_global(at), radius))
		var add: Actor = _stand_enemy(world, data, at)
		if add != null:
			adds.track(add, caller, key)


## The enemy standing in the room whose actor id is `actor`, or null.
func _enemy_of(actor: int) -> Actor:
	for enemy: Node in _enemies:
		var body := enemy as Actor
		if actor >= 0 and body != null and is_instance_valid(body) and body.id == actor:
			return body
	return null


## How wide the ground of an enemy of `data` is against the walls (its scene's `Footprint` circle, else
## the default one), at its data's size: the room an add needs on the ring. Read from its scene's
## state (`SceneState`), no body made.
static func _body_radius_of(data: EnemyBase) -> float:
	var base: float = Footprint.DEFAULT_RADIUS
	var scene_state: SceneState = data.scene.get_state() if data.scene != null else null
	if scene_state != null:
		for node in scene_state.get_node_count():
			if scene_state.get_node_name(node) != &"Footprint" or scene_state.get_node_path(node, true) != NodePath("."):
				continue
			for p in scene_state.get_node_property_count(node):
				if scene_state.get_node_property_name(node, p) == &"radius":
					base = float(scene_state.get_node_property_value(node, p))
	return base * (data.size if data.size > 0.0 else 1.0)


## The adds whose caller died crumble (boss plan OB13), each through Combat (`crumble_requested`):
## its death is told as any other, and the room is cleared when the last is down.
## An add that went without a death told, or that Combat could not crumble (no health), is forgotten
## here, so the room is cleared all the same.
func _crumble_orphans() -> void:
	if events == null or not adds.has_orphans():
		return
	var left: int = 0
	for add: Node in adds.orphans():
		var actor := add as Actor
		if actor == null or actor.is_dying():
			continue
		events.crumble_requested.emit(actor.id)
		if is_instance_valid(actor) and not actor.is_dying():
			# Combat could not crumble it: it goes from the room's fight as it is.
			adds.orphan(actor)
			_enemies.erase(actor)
			_detach(actor)
			left += 1
	var gone: int = adds.forget_gone()
	for at in range(_enemies.size() - 1, -1, -1):
		if not is_instance_valid(_enemies[at]):
			_enemies.remove_at(at)
			gone += 1
	if left + gone > 0:
		_check_room_won()


## Forget the old run: wizards leave `Combat` (the enemies do it themselves when
## they leave the tree) and the old world is freed.
func _clear_run() -> void:
	if combat != null:
		for wizard: Node2D in _wizards:
			if is_instance_valid(wizard):
				combat.unregister_actor(wizard)
	_wizards.clear()
	_forget_enemies()
	contents.clear()
	yard.clear()
	if world != null and is_instance_valid(world):
		_detach(world)
	world = null
	_layout = null
	_layout_of = &""


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
