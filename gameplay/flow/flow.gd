extends Node
## Flow (autoload `Flow`): starts a run in its biome's world, stands the fights the run's map puts
## in its rooms, announces `room_entered` and `room_cleared`, and ends the run back in the hub when
## the boss's room's portal home is taken or every player is down. No waves (boss OB2a,
## docs/milestones/boss-old-broom.md, decision 30): a run is one biome of rooms joined by bridges
## (connected biomes, docs/milestones/connected-biomes.md; the row map of run generation went with
## CB8), walked freely; the rest of the run comes in M3.
##
## Starting: `play_requested(player)` (the tests, the bots, the online spike) or the hub's stone.
## Flow begins the run `run_id_to_play` (`crypt`): the run area makes its biome map and tells each
## room's fight (`run_begun`, answered by `run_room_filled` for every room and `run_biome_chosen`),
## checks that the start recipes compile, builds one `Node2D` world (every room and bridge of the
## map, a wizard for every joined player, a camera) and makes it the current scene, so the menu goes
## away. The whole thing is built in the same frame, far inside the 10 seconds allowed.
##
## Players: one wizard for every player slot that has a device (`core/input`), so
## 1-4 players. A wizard is an actor (actors G7): the wizard scene, seated with
## `PlayerController.seat_wizard` (its seat, its ramp, its staffs) before it is added; its
## Downed component downs, revives and protects it, and its hurtbox registers it with Combat.
## The keyboard joins slot 0 if the Play button was pressed with the mouse and nobody is
## joined there. Joining and leaving mid-run: `coop` sends
## `player_joined` / `player_left` and Flow adds a wizard at the start room's spawn for
## that slot, or removes it (the run goes on; nobody waits for anyone).
##
## A room's fight (boss OB2a, decision 31): the enemies the run's map puts in it (`run_room_filled`,
## ids of `EnemyBase.FOLDERS`: enemies and bosses; rooms hold layout only), standing once the first
## wizard's own body steps onto it (below). A boss stands at its enemy spawns as the fight starts, so
## its intro opens on a body that is there and drawn. Every other one **spawns in** (enemy spawning
## EA3, docs/milestones/enemy-spawning.md): `_stand_enemy` picks its style (`SpawnStyle.pick`: the
## enemy's own, else the room's biome's, else `rise`; spawn styles AS2) and sets it to `Actor.spawn`
## for that style's seconds and id before it enters the tree, so it is not there yet (no hurt shape,
## no touch, no step of its own) while Feel draws a mark and its body rising out of it; a phase's adds
## spawn in too. They come **in groups as the room gets quiet** (EA5: the fight's queue,
## `RoomSpawning`), at the pace the run tells with the room (a group's cost, the cost standing that
## calls the next, the seconds between a group's bodies): the first group as the fight starts; the
## next only once the cost of the room's enemies standing or spawning drops to the refill, never by a
## timer. A group stands at the spawns farthest from every standing wizard (none over a hole nor
## within `RoomSpawning.NEAR` of one), stacked where one is used again (`stacked_position`) and kept on
## clear ground. An id that cannot stand is dropped, so the room is never stuck. When the queue is
## empty and nothing it must beat stands in the room, `room_cleared`.
##
## The run's end: when every wizard is down, a timer of RESTART_DELAY seconds runs, then the party
## goes back to the hub (connected biomes CB7, decision 14), nothing of the run coming along; the
## portal home of the boss's room ends it there too, won.
##
## Staffs (staffs A6a, docs/milestones/M2-staffs.md; living staffs H3; owner 2026-11-01: one
## staff file per setup, used as it is): every wizard gets the hands of its run's mode
## (`staffs_for_mode`), straight from the registry under `wizard`, never copied or changed: in
## Play and the hub the first two basic staffs of STARTER_HEADS on RB and RT (`content/wizard/staffs/`,
## each its own head; START_HANDS, items I2: the other two hands empty). The build channel plays no part. With them the mode's
## cards (`start_cards_for_mode`; Play's `start_cards`: A `dash`, X `bolt`, Y and B empty),
## which the wizard builds itself; flow never touches a spell.
##
## Each mode's setup (owner, 2026-11-05): a new wizard gets the mode's staffs, start cards and
## card bag (the cards it may build with, counted: `bag_for_mode`, card id to copies, handed over
## with `seat_wizard`; items I3): Play one `dash` and one `bolt` (PLAY_BAG, `play_bag`: each entry
## a copy); the hub Inventory.DEV_COPIES of every card (the hub's for now, owner
## 2026-11-11: to try combos online until a better way to come by cards comes; owner 2026-11-13:
## 20 of each). The start cards come with their staffs, beside the bag.
##
## The intro (living staffs H6, `intro.gd`): on a new save (`save`, a `SaveFile`, has no
## INTRO_SEEN flag) Play shows the intro first (state INTRO): one staff dropped per joined player,
## skippable by any of them; when it ends or is skipped the save is marked and the run starts.
## It plays only for people: off (`intro_enabled` false) when a test script is the main loop or
## the game was started with user arguments (the 4-bot test, the stress run, the timing run).
##
## Loading (owner, 2026-10-29): Play and the hub first do the work that must be ready before a
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
## The hub (docs/milestones/online-lobby.md, L1): `hub_requested` (the main menu's Play) starts a run
## in the hub room (`hub`), an island in the void where players join and leave as they like (coop's
## `player_joined` / `player_left`, at the room's spawns), try their staffs on the room's dummies,
## and are hurt by hits as anywhere, but a wizard downed there stands up by itself at full health
## `RoomBase.stand_up_after` seconds later (owner, 2026-11-13: duels between parties and test builds
## without consequences), and everyone down restarts nothing. Its wizards
## have Play's staffs (two, RB and RT: START_HANDS; items I2 took the `dev` staff off RT, the
## rack of items I6 replaces it: its premade staffs are built on the `dev` staff, content/items),
## Play's start cards, and every card in the bag (above). Its teleporter stone (a
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
## A boss's intro (docs/milestones/boss-intro.md): as a room's fight starts
## (`_open_biome_boss_intro`), the first boss with an intro among the room's own enemies (`EnemyBase.boss_intro`; never a phase's adds) stops the game on
## that tick (`boss_intro`, `BossIntroHold`), when the run's rules have intros on
## (`SessionRules.boss_intros`, off for automation where `intro_enabled` is). The command
## `boss_intro_next_requested` (any seat's A, from the HUD) turns its pages; past the last the game goes
## on. It closes by itself when its boss leaves the tree (a step that runs through its stop: Flow's
## own does not run while the game is stopped) or the last seat leaves, and goes with the room's
## enemies. Presses made while it stood still, and on the tick it closes, are dropped
## (`Frames.drop_presses`), so a staff pressed during it casts nothing as the fight starts.
##
## Modes: `mode` says which run this is: MODE_RUN (a run in a biome, below) or MODE_HUB (above).
##
## A biome (connected biomes CB3, docs/milestones/connected-biomes.md, "Room life"): a run is one
## walkable world of rooms joined by bridges (`BiomeMap`, laid by `biome`, a
## `BiomeWorld`), each room with its fight (`RoomFight`), its state Flow's (`life`, `RoomLife`). The
## party starts in its start room (room 0, `Events.FIRST_ROOM`) and goes anywhere. A room's fight
## starts as the first wizard's own body steps onto it (`room_entered` of that room, the first time):
## its bosses stand, the rest spawn in at its pace, and its mouths seal one way (nothing inside leaves,
## a wizard outside walks in); with its last enemy down it is cleared (`room_cleared`) and opens. A
## room's fight is what no seat drives standing in it (`Actor.room`): a possessed enemy leaves its room
## (cleared without it) and fights for the room it ends in, which never seals again once cleared.
## Each place sleeps while nothing acts in it (`RoomLife.wake`). A gated room (connected biomes CB7,
## `gates`, `GatherDoors`: a challenge room's gather door, the boss's gate) is shut until every standing
## wizard is at its door (the gate also while a sealed fight holds a wizard), and then the party comes
## in together (the gate: everyone, downed or far away); its boss's intro opens as it is entered. The
## boss's room cleared opens the portal home: every standing wizard in it wins the run, back to the hub;
## everyone down loses it, back to the hub too. A test plays a map of its own (`start_biome`), or a
## room of its choosing pinned as a biome of that room alone (tests/support/pinned_run.gd).
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
const ActorsScript := preload("res://core/actors/actors.gd")

const PLAYER_SLOTS: int = 4
## The rooms' registry folder.
const ROOM_FOLDER: StringName = &"rooms"
## The room kinds' registry folder (a biome's rooms' kinds: their doors, connected biomes CB7).
const ROOM_KIND_FOLDER: StringName = &"room_kinds"
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
## The hub's room (which dummies it stands is its scene's, `RoomPlaces.dummies`).
const HUB_ROOM_ID: StringName = &"hub"
## The zone of a room's scene Flow gives a meaning (`RoomPlaces.zone`; a place that is no thing):
## the prop yard (props W8).
const ZONE_PROP_YARD: StringName = &"prop_yard"
## The zone of a biome room's template where its portal home opens (connected biomes CB7; none: the
## room's middle), and how much clear ground round its middle it wants.
const ZONE_PORTAL: StringName = &"portal"
const PORTAL_GROUND: float = 16.0
## The run modes (`mode`): a run in a biome, the hub.
const MODE_RUN: StringName = &"run"
const MODE_HUB: StringName = &"hub"
## The cue played on every standing wizard in a room as its fight starts (`_enter_biome_room`).
const ROOM_START_CUE: StringName = &"room_start"
## The four basic staffs of Play by button (RB, RT, LB, LT), by id under `wizard`.
const STARTER_HEADS: Array[StringName] = [&"curl", &"star", &"moon", &"crystal"]
## How many of STARTER_HEADS a wizard of Play and the hub holds, from RB on: two, RB and RT; the
## other hands are empty (items I2, owner 2026-11-13: players start with two staffs).
const START_HANDS: int = 2
## Where the enemies stand: round the room's enemy spawns in turn; a spawn used again puts the next
## one a step further along the diagonal (SPAWN_STACK_DEPTH steps, then a lap to the side).
const SPAWN_REPEAT_OFFSET: Vector2 = Vector2(14.0, 14.0)
const SPAWN_STACK_DEPTH: int = 3
const SPAWN_LAP_OFFSET: Vector2 = Vector2(-14.0, 14.0)
## Seconds from the last wizard going down until the room restarts (under 3).
const RESTART_DELAY: float = 1.5
## Extra room around the hub's scene where projectiles may still fly, in pixels.
const PROJECTILE_MARGIN: float = 32.0
## Name of the world node.
const WORLD_NAME: String = "Arena"
## The intro's node name, and the save flag set once it has been seen (or skipped).
const INTRO_NAME: String = "Intro"
const INTRO_SEEN: StringName = &"intro_seen"

enum State { IDLE, RUNNING, INTRO, LOADING }

## Not state: services, caches and scratch, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"events", &"registry", &"frames", &"combat", &"projectiles", &"spells", &"actors", &"world_parent", &"intro", &"loading", &"world", &"save", &"_places", &"_layout", &"_layout_of", &"_asking", &"_chosen_map", &"_chosen_fights"]
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_enemies", &"_wizards"]
## Not state: the functions that only make what is drawn (core/sim/README.md, "The line"): the
## room's camera.
const VIEW: Array[StringName] = [&"_add_camera", &"_add_camera_over"]

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
## The actor table (a biome's waking: `RoomLife.wake`).
var actors: ActorsScript = null
## Where the world goes. Only tests set this; otherwise the world becomes the
## current scene (the main menu is freed).
var world_parent: Node = null
## What the next run is made of, by registry id. Later features (a loadout)
## set these; the runs, rooms, enemies and spell components themselves are content found by folder,
## so a new one needs no change here. `run_id_to_play` is the run definition a run of rooms begins
## (its rooms and what stands in them are its map's). `wizard_scene` is the wizard every player gets (its art is in
## the scene). The start recipes are component ids (a recipe as in `core/spells`).
var run_id_to_play: StringName = DEFAULT_RUN_ID
var start_cards: Array = DEFAULT_START_CARDS.duplicate(true)
## Play's bag (PLAY_BAG unless a test sets another).
var play_bag: Array[StringName] = PLAY_BAG.duplicate()
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
## The adds standing, each with the body that called it (boss plan OB13).
var adds: RoomAdds = RoomAdds.new()
## The boss's intro of the room (docs/milestones/boss-intro.md, `BossIntroHold`).
var boss_intro: BossIntroHold = BossIntroHold.new()
## A biome's world (connected biomes CB3; its map is the state), its rooms' life, and what the
## run in progress was started with (its map and fights: the run area's, or a test's own,
## `_biome_given`).
var biome: BiomeWorld = BiomeWorld.new()
var life: RoomLife = RoomLife.new()
## A biome's gather doors: its gated rooms' doors (a challenge room's, the boss's gate) and the portal
## home (connected biomes CB7, `GatherDoors`).
var gates: GatherDoors = GatherDoors.new()
var _biome_start: BiomeMap = null
var _biome_fights: Array[RoomFight] = []
var _biome_given: bool = false
## The room's layout in the world, and the room it is of (a joining machine built the room the run
## started in: a snapshot taken in a later room lays that room's out again, `rebuild_derived`).
var _layout: Node = null
var _layout_of: StringName = &""
## True while the run in progress was started from the hub's stone: its end goes back there.
var _back_to_hub: bool = false
## Scratch: the run area's answer to `run_begun` (`run_room_filled` for each room, then
## `run_biome_chosen`), taken only while Flow asks for it (`_asking`, `_begin_run_of_rooms`) and read
## by the same call.
var _asking: bool = false
var _chosen_map: BiomeMap = null
var _chosen_fights: Array[RoomFight] = []
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
	if actors == null:
		actors = get_node_or_null("/root/Actors") as ActorsScript
	if frames != null:
		frames.set_party_source(_party_now)
	boss_intro.events = events
	gates.events = events
	if events == null:
		push_warning("Flow: the Events autoload is missing, so the game cannot be started.")
		return
	events.play_requested.connect(_on_play_requested)
	events.hub_requested.connect(_on_hub_requested)
	events.main_menu_requested.connect(_on_main_menu_requested)
	events.play_load_requested.connect(_on_play_load_requested)
	# Commands, heard at the tick's start (core/events, online-ready N2).
	events.listen(&"run_requested", _on_run_requested)
	events.listen(&"boss_intro_next_requested", _on_boss_intro_next_requested)
	events.enemy_died.connect(_on_enemy_died)
	events.player_downed.connect(_on_player_downed)
	events.player_revived.connect(_on_player_revived)
	events.player_joined.connect(_on_player_joined)
	events.player_left.connect(_on_player_left)
	events.run_room_filled.connect(_on_run_room_filled)
	events.run_biome_chosen.connect(_on_run_biome_chosen)
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
	if mode == MODE_RUN and state == State.RUNNING and _step_biome(delta):
		# The run ended in its step (the portal home): nothing more of it steps.
		return
	_count_stand_ups(delta)
	if mode == MODE_HUB and state == State.RUNNING:
		_count_stone()
		return
	if _restart_left < 0.0:
		return
	_restart_left -= delta
	if _restart_left <= 0.0:
		_restart_left = -1.0
		# A run lost goes back to the hub (connected biomes CB7, decision 14). Back in the hub the
		# party is ready for a new run: nothing of the run comes back with it, its staffs neither
		# (owner, 2026-11-10). The hub is the arsenal the next run's tools are picked from.
		_return_to_hub(_starter)


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


## True while the run's end (the way back to the hub) is counting down.
func is_restarting() -> bool:
	return _restart_left >= 0.0


## Where the `times`-th enemy (0 = first) at `spawn` stands: up to SPAWN_STACK_DEPTH
## steps along the diagonal, then the next row starts a lap further to the side, so
## a stack never runs into a wall.
static func stacked_position(spawn: Vector2, times: int) -> Vector2:
	var step: int = times % SPAWN_STACK_DEPTH
	var lap: int = times / SPAWN_STACK_DEPTH
	return spawn + SPAWN_REPEAT_OFFSET * float(step) + SPAWN_LAP_OFFSET * float(lap)


## Enemies of the rooms' fights still to beat: those alive (those still spawning too) and those still
## to come in the fights under way (their queues); never the dummies.
func enemies_left() -> int:
	var left: int = _enemies.size()
	for fight: RoomFight in life.fights:
		left += fight.queue.left()
	return left


## The dummies of the room (the hub's) still standing.
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


## The home seat of a wizard actor (its PlayerController's), or -1.
func _seat_of(wizard: Node) -> int:
	var controller: PlayerScript = PlayerScript.of(wizard)
	return controller.seat if controller != null else -1


## Build the world and start the run now, replacing any run in progress. `party` (as `_party_of`
## makes it; items I4) gives each seat's wizard the player it was before, everything it held (from
## the hub into a run, or the hub begun anew); a seat with no loadout there, and all of them with no
## `party`, starts with what its mode gives (its staffs, start cards and bag). A run (`MODE_RUN`) is
## the run `run_id_to_play`, its world the biome map the run area makes (`_begin_run_of_rooms`), or
## the map a test gave (`start_biome`). Returns false (and starts nothing) when content is missing or
## no player has a device; a map its templates' shapes cornered (rare) is found only once the last
## run's world went, so Flow is idle then.
func start_run(requester: int, party: PartyLoadout = null) -> bool:
	var room: RoomBase = null
	if mode == MODE_RUN and not _biome_given:
		# What keeps the run's map from being made is asked before anything goes; only its rolls
		# (its seed, dealt below) can still corner it (`Registry.run_problems`).
		var problems: PackedStringArray = registry.run_problems(run_id_to_play) if registry != null else PackedStringArray(["No registry."])
		if not problems.is_empty():
			push_warning("Flow: the run '%s' cannot be made, so no run starts: %s" % [run_id_to_play, "; ".join(problems)])
			return false
	elif mode == MODE_RUN:
		room = registry.get_resource(ROOM_FOLDER, _biome_start.room_templates[0]) as RoomBase if registry != null and _biome_start != null and _biome_start.rooms() > 0 else null
		if room == null:
			push_warning("Flow: the biome has no start room the registry knows, so no run starts.")
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
	if mode == MODE_RUN and not _biome_given:
		room = _begin_run_of_rooms(players.size())
		if room == null:
			stop_run()
			return false
	_room = room
	var new_world := Node2D.new()
	new_world.name = WORLD_NAME
	# The bodies are drawn by their feet (view only): one standing in front of a prop is drawn over
	# it, one behind it under it. The room's layout, at the top left, is one piece drawn first, its
	# floor, walls and tops in their own order and z.
	new_world.y_sort_enabled = true
	if mode == MODE_RUN:
		if not _lay_biome(new_world):
			new_world.free()
			stop_run()
			return false
	else:
		_lay_out(new_world, room, tick.sim if tick != null else null)
	_spawn_players(new_world, room, players, party)
	contents.stand(new_world, _places, registry)
	if mode == MODE_RUN:
		# A later room's placed enemies stand as it is entered (`_enter_biome_room`), not before.
		for other in range(1, life.rooms()):
			contents.stand_more(new_world, biome.room_places(other), registry, false)
	for problem in contents.problems:
		push_warning("Flow: the room's bodies: %s" % problem)
	yard.fill(new_world, _places.zone(ZONE_PROP_YARD), registry)
	world = new_world
	room_id = room.id
	state = State.RUNNING
	_show_world(new_world)
	if mode == MODE_RUN:
		# Laid by the biome (its grid is the whole biome's, `BiomeWorld`): its start room is entered.
		_start_biome_rooms()
		return true
	_set_walls(new_world)
	_announce_room(room)
	_count_stone()
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
		events.room_built.emit(room.id, EventsScript.FIRST_ROOM, layout)
	RoomPlaces.strip(layout)
	if projectiles != null:
		projectiles.set_bounds(Rect2(Vector2.ZERO, _places.size).grow(PROJECTILE_MARGIN))
	into.add_child(layout)
	into.move_child(layout, 0)
	_layout = layout
	_layout_of = room.id
	_add_camera(into, _places.size)


## After a snapshot was restored (core/sim/README.md, "Snapshots"): a run's biome laid again where
## it differs (`_rebuild_biome`); the hub's room laid out again when this world showed another. Its
## bodies are the snapshot's own. The layout is built again by the run's chance as it is now: the
## same as the host's while rooms are fixed scenes (`RoomBase.build` ignores it).
func rebuild_derived() -> void:
	if mode == MODE_RUN:
		_rebuild_biome()
		return
	if world == null or not is_instance_valid(world) or _room == null or _layout_of == _room.id:
		return
	var tick: TickScript = TickScript.of(self) as TickScript
	_lay_out(world, _room, tick.sim if tick != null else null)
	_set_walls(world)


## The room the next run of the hub is in (a run's is its map's start room).
func _room_id_for_mode() -> StringName:
	return HUB_ROOM_ID


## A run begins (on the run's fresh state, after `Tick.begin_run`): the run area makes the biome map
## of `run_id_to_play` for `players` players (the seats joined at its start; run generation RG5) and
## answers with each room's fight and the map (`run_begun`, `run_room_filled`, `run_biome_chosen`;
## connected biomes CB8), kept as the run's start (`_biome_start`, `_biome_fights`). The start room,
## or null (with a warning) when no answer came or the registry lacks it.
func _begin_run_of_rooms(players: int) -> RoomBase:
	_chosen_map = null
	_chosen_fights.clear()
	if events != null:
		_asking = true
		events.run_begun.emit(run_id_to_play, players)
		_asking = false
	var map: BiomeMap = _chosen_map
	_chosen_map = null
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, map.room_templates[0]) as RoomBase if map != null and map.rooms() > 0 and registry != null else null
	if room == null:
		push_warning("Flow: the run '%s' gave no biome it could lay (its map could not be made, or its start room is missing), so no run starts." % run_id_to_play)
		_chosen_fights.clear()
		return null
	_biome_start = map
	_biome_fights.clear()
	for at in map.rooms():
		var fight: RoomFight = _chosen_fights[at] if at < _chosen_fights.size() else null
		_biome_fights.append(fight if fight != null else RoomFight.new())
	_chosen_fights.clear()
	return room


## The run area's fight of room `room` (`run_room_filled`), kept as a `RoomFight`. Heard only while
## Flow asks (`_begin_run_of_rooms`).
func _on_run_room_filled(room: int, enemies: Array[StringName], scale: float, group: int, refill_at: int, stagger: float) -> void:
	if not _asking or room < 0:
		return
	while _chosen_fights.size() <= room:
		_chosen_fights.append(null)
	_chosen_fights[room] = RoomFight.of(enemies, group, refill_at, stagger, scale)


## The run area's biome map (`run_biome_chosen`; a `BiomeMap`), a copy kept. Heard only while Flow
## asks (`_begin_run_of_rooms`).
func _on_run_biome_chosen(map: RefCounted) -> void:
	var made := map as BiomeMap
	if _asking and made != null:
		_chosen_map = made.copy()


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


## The hub's room stands in the world shown: `room_entered`, and the items its scene places
## (`room_items_placed`).
func _announce_room(room: RoomBase) -> void:
	if events == null:
		return
	events.room_entered.emit(room.id, EventsScript.FIRST_ROOM)
	var items: Array = RoomContents.items_of(_places)
	events.room_items_placed.emit(room.id, EventsScript.FIRST_ROOM, items[0], items[1])


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
	# A biome's start is its run's: nothing of it outlives the run (a later run hashes as a fresh one's).
	_biome_start = null
	_biome_fights.clear()
	_biome_given = false
	state = State.IDLE
	mode = MODE_RUN
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
	_biome_given = false
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


## The run, from the hub's stone, for seat `seat`: every wizard goes in as the player it
## is, with every bag, its staffs and its hands (owner, 2026-11-13: what a run's start takes along
## is the whole player), and the run's end brings everyone back to the hub.
func _start_run_from_stone(seat: int) -> void:
	var party: PartyLoadout = _party_of()
	mode = MODE_RUN
	_biome_given = false
	_back_to_hub = true
	if not start_run(seat, party):
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
	hub.count(in_hub, _wizards, contents, events)


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
	if at >= 0:
		# Its room is checked at Flow's next step (`_step_biome`).
		_enemies.remove_at(at)


## True while everyone down ends the run: in a run under way (never in the hub, where a fall costs
## nothing).
func _can_be_lost() -> bool:
	return state == State.RUNNING and mode == MODE_RUN


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


## Seconds from everyone down until the restart.
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
	_add_camera_over(parent, Rect2(Vector2.ZERO, size))


## A camera kept inside `area` (a room's, from the origin; a biome's bounds: connected biomes CB3).
func _add_camera_over(parent: Node2D, area: Rect2) -> void:
	for old: Node in parent.get_children():
		if old is Camera2D:
			_detach(old)
	var camera := Camera2D.new()
	camera.position = area.get_center()
	# Feel's party camera moves and zooms it to hold this machine's wizards; the limits keep it
	# inside the room.
	camera.limit_left = floori(area.position.x)
	camera.limit_top = floori(area.position.y)
	camera.limit_right = ceili(area.end.x)
	camera.limit_bottom = ceili(area.end.y)
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
## Play's and the hub's the first START_HANDS basic staffs (STARTER_HEADS) and null for an empty hand
## after them. Empty when one is missing.
func staffs_for_mode() -> Array[StaffBase]:
	var ids: Array[StringName] = []
	for at in STARTER_HEADS.size():
		ids.append(STARTER_HEADS[at] if at < START_HANDS else &"")
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


## The cards each staff of a new wizard starts with in this run's `mode`: `start_cards`, in Play and
## the hub alike.
func start_cards_for_mode() -> Array:
	return start_cards


## The card bag a new wizard gets in this run's `mode`, card id to copies (items I3):
## Inventory.DEV_COPIES of every spell card of the registry in the hub, `play_bag` in Play (an entry
## a copy).
func bag_for_mode() -> Dictionary:
	var out: Dictionary = {}
	match mode:
		MODE_HUB:
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


## Every enemy still waiting in the queue of a fight under way starts spawning now, as if each group
## had come (for tests: they then land them, tests/support/spawning.gd).
func stand_all_now() -> void:
	if world == null:
		return
	for room in life.rooms():
		if not life.has(room, RoomLife.STARTED) or life.has(room, RoomLife.CLEARED):
			continue
		var queue: RoomSpawning = life.fights[room].queue
		var ids: Array[StringName] = queue.take_all()
		if not ids.is_empty():
			_scale_for(room)
		for id: StringName in ids:
			_stand_queued(id, biome.room_places(room), queue, room)
		_check_biome_room(room)


## The queued enemy `id` starts spawning at the spawn its group takes (`RoomSpawning.spawn_for`: the
## farthest from every standing wizard first, none over a hole nor within `RoomSpawning.NEAR` of a
## wizard), stacked where one is used again and moved to the nearest clear ground. An id with no
## enemy, or a room with no spawns, stands nothing: it is dropped (it was taken off the queue).
func _stand_queued(id: StringName, places: RoomPlaces, queue: RoomSpawning, room: int) -> void:
	var data: EnemyBase = _enemy_data_of(id)
	var spawns: PackedVector2Array = places.enemy_spawns
	if data == null or data.scene == null or spawns.is_empty():
		push_warning("Flow: the room's enemy '%s' could not stand, so it is dropped." % id)
		return
	var radius: float = _body_radius_of(data)
	var on_hole: Callable = Callable()
	if projectiles != null and projectiles.grid().has_holes():
		on_hole = func(at: Vector2) -> bool: return projectiles.grid().touches_hole(world.to_global(at), radius)
	var at: Vector2 = queue.spawn_for(spawns, _standing_wizard_places(room), on_hole, stacked_position)
	if projectiles != null:
		# A body stacked beside its spawn may reach a wall or a hole's edge: the nearest clear ground
		# (the spot itself when it is clear; hub rework HR-H2).
		at = world.to_local(projectiles.grid().nearest_ground(world.to_global(at), radius))
	_stand_enemy(world, data, at, true)


## What the room's enemies standing or spawning cost together (`EnemyBase.cost`): how busy the room is
## (a biome's room `room`: those standing in it; NO_PLACE: all of them).
func _standing_cost(room: int = RoomGrid.NO_PLACE) -> int:
	var cost: int = 0
	for enemy: Node in _enemies:
		if not is_instance_valid(enemy):
			continue
		var body := enemy as Actor
		if body != null and room != RoomGrid.NO_PLACE and body.room != room:
			continue
		if body != null and body.data != null:
			cost += body.data.cost
	return cost


## Where the wizards standing (not down) are, in the world (in a biome's room `room` only; NO_PLACE:
## everywhere).
func _standing_wizard_places(room: int = RoomGrid.NO_PLACE) -> PackedVector2Array:
	var places := PackedVector2Array()
	for wizard: Node2D in _wizards:
		if not is_instance_valid(wizard):
			continue
		var actor := wizard as Actor
		if actor != null and room != RoomGrid.NO_PLACE and actor.room != room:
			continue
		if actor != null and not actor.is_down():
			places.append(actor.position)
	return places


## The enemy or boss `enemy_id` (`EnemyBase.FOLDERS`, in turn), or null.
func _enemy_data_of(enemy_id: StringName) -> EnemyBase:
	if registry == null:
		return null
	for folder: StringName in EnemyBase.FOLDERS:
		var data: EnemyBase = registry.get_resource(folder, enemy_id) as EnemyBase
		if data != null:
			return data
	return null


## One enemy of `data` stands at `at` in `parent`, among the room's fight: counted for the wizards in
## play (`Actor.players`, boss plan OB13) and told to difficulty (`enemy_standing`: scaled to the
## room, run generation RG5), both before its data is applied. With `spawn_in` it spawns in (enemy
## spawning EA3: `Actor.spawn`, set before it enters the tree, so its hurt shape is never registered
## while it spawns in), in the style `spawn_style_for` picks. Null when no body could be made.
func _stand_enemy(parent: Node2D, data: EnemyBase, at: Vector2, spawn_in: bool = false) -> Actor:
	var enemy := RoomContents.make_body(data) as Actor
	if enemy == null:
		return null
	enemy.position = at
	enemy.players = _players_in_play()
	if spawn_in:
		var style: SpawnStyle = spawn_style_for(data)
		enemy.spawn(style.seconds, style.id)
	if events != null:
		events.enemy_standing.emit(enemy)
	parent.add_child(enemy)
	enemy.find_room()
	_enemies.append(enemy)
	return enemy


## The style an enemy of `data` spawns in in, in the room played now (spawn styles AS2): `SpawnStyle.pick`
## from the registry, the enemy and the room's biome (none with no room).
func spawn_style_for(data: EnemyBase) -> SpawnStyle:
	return SpawnStyle.pick(registry, data, _room.biome if _room != null else &"")


## The room's enemies are forgotten (they went with the room), those still to come,
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
## OB13): as many as the entry names for the wizards in play, under its cap of those alive, on a
## ring round the body or at the room's enemy spawns, each spawning (`_stand_enemy`). Only for a body Flow stood,
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
	var spawns: PackedVector2Array = _places_for(caller.room).enemy_spawns
	if mode == MODE_RUN:
		_scale_for(caller.room)
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
		# An add spawns in as the room's enemies do (enemy spawning, the owner's question 3).
		var add: Actor = _stand_enemy(world, data, at, not data.boss)
		if add != null:
			add.is_add = true
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
	for add: Node in adds.orphans():
		var actor := add as Actor
		if actor == null or actor.is_dying() or actor.is_spawning():
			# One still spawning crumbles once it has landed (a later step), its death told, so it
			# never leaves mid-rise in one jump.
			continue
		events.crumble_requested.emit(actor.id)
		if is_instance_valid(actor) and not actor.is_dying():
			# Combat could not crumble it: it goes from the room's fight as it is.
			adds.orphan(actor)
			_enemies.erase(actor)
			_detach(actor)
	adds.forget_gone()
	for at in range(_enemies.size() - 1, -1, -1):
		if not is_instance_valid(_enemies[at]):
			_enemies.remove_at(at)
	# Their rooms are checked by Flow's step (`_step_biome`).


## Forget the old run: wizards leave `Combat` (the enemies do it themselves when
## they leave the tree) and the old world is freed.
func _clear_run() -> void:
	if combat != null:
		for wizard: Node2D in _wizards:
			if is_instance_valid(wizard):
				combat.unregister_actor(wizard)
	_wizards.clear()
	if biome.map != null and events != null:
		# A biome's world goes as a whole: what was cast in it ends with it.
		events.room_left.emit(EventsScript.ALL_ROOMS)
	if biome.map != null and projectiles != null:
		# No place is left once the biome goes (a later room lays its own grid).
		projectiles.grid().clear_places()
	_forget_enemies()
	contents.clear()
	yard.clear()
	biome.clear()
	life.clear()
	gates.clear()
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


# --- A biome (connected biomes CB3) -----------------------------------------------------------

## Start a run in the biome `map`, a map of a test's own (connected biomes CB3; see the class doc; a
## run's own is the run area's, `start_run`): each room's fight `fights[room]` (a room past their
## end, or null, has none), for seat `requester`, each seat's wizard as `party` says (as `start_run`
## takes it). Everyone down ends it back in the hub (CB7).
## False (nothing started) when its map or content is missing or nobody has joined.
func start_biome(requester: int, map: BiomeMap, fights: Array[RoomFight], party: PartyLoadout = null) -> bool:
	if map == null:
		return false
	_biome_start = map.copy()
	_biome_fights.clear()
	for fight: RoomFight in fights:
		_biome_fights.append(fight.fresh() if fight != null else RoomFight.new())
	mode = MODE_RUN
	_biome_given = true
	_back_to_hub = false
	if start_run(requester, party):
		return true
	_biome_given = false
	return false


## Lay the biome's map in `into` (the world being built): every piece (each told as it is laid,
## `room_built`), the whole biome's grid, the rooms' life begun and the camera over the biome. False
## (a warning) when the map has problems.
func _lay_biome(into: Node2D) -> bool:
	biome.attach(into, registry, projectiles, _on_piece_built)
	var problems: PackedStringArray = biome.lay(into, _biome_start.copy())
	if not problems.is_empty():
		push_warning("Flow: the biome cannot be laid, so no run starts: %s" % "; ".join(problems))
		return false
	_layout = null
	_layout_of = &""
	_places = biome.room_places(EventsScript.FIRST_ROOM)
	life.begin(biome.map.rooms(), biome.places(), _biome_fights)
	_begin_gates(biome.map)
	if projectiles != null:
		life.tell_seals(projectiles.grid())
		_add_camera_over(into, biome.area())
	return true


## The biome's gather doors begin from its rooms' kinds (`RoomKind.door`, `portal_home`; a kind the
## registry lacks has none) and are laid into the grid, every door shut.
func _begin_gates(map: BiomeMap) -> void:
	var rules := PackedByteArray()
	var homes := PackedByteArray()
	rules.resize(map.rooms())
	homes.resize(map.rooms())
	for room in map.rooms():
		var kind: RoomKind = registry.get_resource(ROOM_KIND_FOLDER, map.room_kinds[room]) as RoomKind if registry != null and map.room_kinds[room] != &"" else null
		rules[room] = GatherDoors.RULE_NONE
		if kind != null and kind.door == RoomKind.DOOR_GATHER:
			rules[room] = GatherDoors.RULE_GATHER
		elif kind != null and kind.door == RoomKind.DOOR_GATE:
			rules[room] = GatherDoors.RULE_GATE
		homes[room] = 1 if kind != null and kind.portal_home else 0
	gates.begin(map, rules, homes)
	gates.lay(biome, projectiles.grid() if projectiles != null else null)


## A piece of the biome was laid (`BiomeWorld.built`): `room_built` for it.
func _on_piece_built(template: StringName, number: int, layout: Node) -> void:
	if events != null:
		events.room_built.emit(template, number, layout)


## The biome's world is up: its start room entered (a new world: `room_entered` of FIRST_ROOM), then
## the items every room's scene places (`room_items_placed`, the start room's first), and its places
## woken or put to sleep.
func _start_biome_rooms() -> void:
	# Who is where first: the start room's fight (if any) stands away from its wizards.
	life.wake(actors, projectiles)
	_enter_biome_room(EventsScript.FIRST_ROOM)
	if events != null:
		for room in life.rooms():
			var items: Array = RoomContents.items_of(biome.room_places(room))
			events.room_items_placed.emit(biome.map.room_templates[room], room, items[0], items[1])
	_count_stone()
	life.wake(actors, projectiles)


## A biome's tick (Flow's step): every room a wizard's own body stepped onto entered (its fight
## starting), every fight under way spawning at its pace and cleared once its last enemy is down,
## then the gather doors counted (CB7), then every place woken or put to sleep (`RoomLife.wake`).
## True when the run ended here (the portal home taken).
func _step_biome(delta: float) -> bool:
	for wizard: Node2D in _wizards:
		if not is_instance_valid(wizard):
			continue
		var actor := wizard as Actor
		if actor == null:
			continue
		actor.find_room()
		# A wizard standing (a downed one crawling in starts nothing).
		# A gated room is entered only once it opened (its lip outside the shut door is its place).
		if not actor.is_down() and actor.room >= 0 and actor.room < life.rooms() and not life.has(actor.room, RoomLife.ENTERED) and gates.is_open(actor.room):
			_enter_biome_room(actor.room)
	for room in life.rooms():
		if life.has(room, RoomLife.STARTED) and not life.has(room, RoomLife.CLEARED):
			if life.is_awake(room):
				_call_room_spawning(room, delta)
			_check_biome_room(room)
	var gated: int = gates.count_doors(_wizards, life)
	if gated != GatherDoors.NONE:
		_open_gate(gated)
	if gates.count_portal(_wizards):
		_take_portal_home()
		return true
	life.wake(actors, projectiles)
	return false


## Every standing wizard is at a door of gated room `room` (and a gate is not held): it opens and the
## party comes in onto its player spawns, each at its seat's (connected biomes CB7): a gather door's
## standing wizards, the gate's everyone, downed or far away (decision 25). A standing one is
## protected for a moment, as a wizard coming into a row run's room is; a downed one stays down for a
## teammate's revive. The room is entered at once (its fight starts and seals, its boss's intro opens).
func _open_gate(room: int) -> void:
	var everyone: bool = gates.rule_of(room) == GatherDoors.RULE_GATE
	gates.open(room, projectiles.grid() if projectiles != null else null)
	var places: RoomPlaces = biome.room_places(room)
	var middle: Vector2 = biome.room_rect(room).get_center()
	for wizard: Node2D in _wizards:
		var actor := wizard as Actor if is_instance_valid(wizard) else null
		if actor == null or (actor.is_downed() and not everyone):
			continue
		var seat: int = _seat_of(actor)
		var at: Vector2 = places.player_spawns[seat] if places != null and seat >= 0 and seat < places.player_spawns.size() else middle
		if projectiles != null:
			at = world.to_local(projectiles.grid().nearest_ground(world.to_global(at), actor.wall_radius()))
		actor.position = at
		actor.placed()
		actor.find_room()
		var hero: DownedScript = DownedScript.of(actor)
		if hero != null and not actor.is_downed():
			hero.protect(DownedScript.JOIN_PROTECTION)
	if not life.has(room, RoomLife.ENTERED):
		_enter_biome_room(room)


## Every standing wizard stands in the portal home (connected biomes CB7, decision 7): the run is won
## and ends back in the hub, nothing of it coming along (as a row run's end from the stone).
func _take_portal_home() -> void:
	_return_to_hub(_starter)


## Room `room` is entered for the first time: `room_entered`, and its fight starts (its bosses stand,
## the first group spawns in, its mouths seal, `room_start` on the wizards in it); a room with no fight
## is cleared at once.
func _enter_biome_room(room: int) -> void:
	life.set_flag(room, RoomLife.ENTERED, true)
	if room != EventsScript.FIRST_ROOM and world != null:
		# Its placed enemies (a dummy, a stand-in) stand now, as the party first comes (connected
		# biomes CB8); the start room's stood with the world.
		contents.stand_enemies(world, biome.room_places(room))
	if events != null:
		events.room_entered.emit(biome.map.room_templates[room], room)
	var fight: RoomFight = life.fights[room]
	if not fight.has_enemies():
		_clear_biome_room(room)
		return
	life.set_flag(room, RoomLife.STARTED, true)
	life.set_flag(room, RoomLife.SEALED, true)
	if projectiles != null:
		life.tell_seals(projectiles.grid())
	_scale_for(room)
	var places: RoomPlaces = biome.room_places(room)
	var queued: Array[StringName] = []
	var queued_costs := PackedInt32Array()
	var bosses: int = 0
	var stood: Array[Node] = []
	for id: StringName in fight.enemies:
		var data: EnemyBase = _enemy_data_of(id)
		if data == null or data.scene == null or places.enemy_spawns.is_empty():
			push_warning("Flow: the biome's room %d cannot stand '%s', so it is dropped." % [room, id])
			continue
		if data.boss:
			var spawn: int = bosses % places.enemy_spawns.size()
			var boss: Actor = _stand_enemy(world, data, stacked_position(places.enemy_spawns[spawn], bosses / places.enemy_spawns.size()), false)
			if boss != null:
				stood.append(boss)
			bosses += 1
		else:
			queued.append(id)
			queued_costs.append(data.cost)
	fight.queue.begin(queued, queued_costs, fight.group, fight.refill_at, fight.stagger)
	_call_room_spawning(room, 0.0)
	if events != null:
		for wizard: Node2D in _wizards:
			var actor := wizard as Actor if is_instance_valid(wizard) else null
			if actor != null and actor.room == room and not actor.is_down():
				events.cue_shown.emit(actor.id, ROOM_START_CUE, actor.global_position, Vector2.ZERO, 0.0, Color.WHITE, 0)
	_check_biome_room(room)
	_open_biome_boss_intro(stood)


## A biome's room's fight began with `bosses` standing (connected biomes CB7; docs/milestones/
## boss-intro.md): the first with an intro opens it, as a row run's room's does, and the game stops on
## this tick for everyone (any seat's A moves it on). A room is entered once, so its intro opens once.
func _open_biome_boss_intro(bosses: Array[Node]) -> void:
	if bosses.is_empty() or state != State.RUNNING:
		return
	var game: Sim = Sim.found(self)
	# The last room's intro is done with (it closed before anyone could walk on): this room's may open.
	boss_intro.clear(game)
	boss_intro.open_in(bosses, game)


## Room `room`'s queue `delta` seconds on: each enemy it calls spawns in at the room's spawns
## (`_stand_queued`, against the wizards in that room).
func _call_room_spawning(room: int, delta: float) -> void:
	var queue: RoomSpawning = life.fights[room].queue
	if queue.is_done() or world == null:
		return
	var places: RoomPlaces = biome.room_places(room)
	var id: StringName = queue.next(delta, _standing_cost(room))
	if id != &"":
		_scale_for(room)
	while id != &"":
		_stand_queued(id, places, queue, room)
		id = queue.next(0.0, _standing_cost(room))


## Difficulty told room `room`'s scale (its `RoomFight.scale`; 0: as it is) before an enemy of its
## fight stands: two fights at once each stand at their own.
func _scale_for(room: int) -> void:
	if events != null and room >= 0 and room < life.rooms() and life.fights[room].scale > 0.0:
		events.run_room_scaled.emit(life.fights[room].scale)


## Room `room`'s fight is over when its queue is empty and nothing it must beat stands in it (an
## enemy no seat drives, `Actor.room` that room): cleared.
func _check_biome_room(room: int) -> void:
	if not life.has(room, RoomLife.STARTED) or life.has(room, RoomLife.CLEARED) or not life.fights[room].queue.is_done():
		return
	for enemy: Node in _enemies:
		if not is_instance_valid(enemy):
			continue
		var body := enemy as Actor
		if body != null and not body.is_dying() and body.room == room and (body.controller == null or body.controller.seat < 0):
			return
	_clear_biome_room(room)


## Room `room` is cleared: its seal opens and `room_cleared` is sent, once.
func _clear_biome_room(room: int) -> void:
	life.set_flag(room, RoomLife.CLEARED, true)
	life.set_flag(room, RoomLife.SEALED, false)
	if projectiles != null:
		life.tell_seals(projectiles.grid())
	if events != null:
		events.room_cleared.emit(biome.map.room_templates[room], room)
	if gates.opens_home(room):
		_open_portal_home(room)


## Room `room`, cleared, opens the portal home on its floor (connected biomes CB7): at its zone
## `ZONE_PORTAL` when its template has one, else at its middle, on the nearest clear ground.
func _open_portal_home(room: int) -> void:
	var places: RoomPlaces = biome.room_places(room)
	var zone: Rect2 = places.zone(ZONE_PORTAL) if places != null else Rect2()
	var middle: Vector2 = zone.get_center() if zone.has_area() else biome.room_rect(room).get_center()
	if projectiles != null and world != null:
		middle = world.to_local(projectiles.grid().nearest_ground(world.to_global(middle), PORTAL_GROUND))
	gates.open_portal(room, middle)


## What is where in the room a body of `room` stands in: a biome's room's (its places in the world),
## else the room shown's.
func _places_for(room: int) -> RoomPlaces:
	if mode == MODE_RUN and room >= 0 and room < life.rooms():
		return biome.room_places(room)
	return _places


## After a snapshot was restored into a biome: the biome laid again where it differs (the world's
## own `rebuild_derived`, or here into a world that laid none), its start room's places, and the
## seals and the places' sleep told to the grid again (they are not state there).
func _rebuild_biome() -> void:
	if world == null or not is_instance_valid(world):
		return
	if _layout != null and is_instance_valid(_layout):
		# A row room's layout this world showed before (a restore from another kind of run).
		_detach(_layout)
		_layout = null
		_layout_of = &""
	biome.attach(world, registry, projectiles, _on_piece_built)
	biome.rebuild_derived()
	if biome.map != null:
		_places = biome.room_places(EventsScript.FIRST_ROOM)
		if projectiles != null:
			_add_camera_over(world, biome.area())
	if projectiles != null:
		life.tell_seals(projectiles.grid())
		life.tell_awake(projectiles.grid())
		gates.lay(biome, projectiles.grid())
	gates.tell_all(_wizards, life)
