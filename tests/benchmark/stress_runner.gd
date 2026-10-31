extends Node
## The stress scene as a node: 4 bots with built spells fight a crowd on the real game
## (Flow, Combat, the projectile manager, the spell runtime, Feel and the HUD), with
## enemies and shots kept at the numbers of the PLAN's stress scenario (docs/PLAN.md,
## "Performance budgets"):
##  - web: 100 enemies, shots at the web cap (500 since the first web run; the PLAN said 1,000),
##  - desktop: 200 enemies, 3,000 shots,
## both with four players and full effects (every hit sends its particles, reactions
## and numbers). Between them run two diagnostic variants of the web scenario, to explain the
## web frame time (docs/DECISIONS.md, 2026-10-23): one with the render loop off (nothing is
## drawn, so the frame is game logic only) and one with the hit particles off. The four
## scenarios (web, web with the render loop off, web with hit particles off, desktop) run one
## after the other. A web build skips the desktop one (`scenarios_for`): it is the desktop's
## budget, which the desktop export measures, and in CI's software renderer it alone took about
## seven of the web run's fourteen minutes (2026-10-28, when the run went past its timeout).
##
## The horde scenarios (Horde H1, docs/milestones/horde.md, "Scale") hold 500+ enemies: mostly
## swarmers (the imp's data with no staff: they only chase and hurt by touch, as the horde's
## swarm enemies do) and a share (`staffed`, 10%) of staff enemies (the imp as above), against
## the same four bots, in the usual room (the 1280x720 horde arena is H2's). `horde` (600
## enemies) is the desktop's, `horde, web` (500) the web's; both keep the web cap of shots (500),
## as the `web` scenario does with 100 enemies, so the enemies are what differs. They are not in the default run
## (`scenarios`): they take longer than the rest together, and the exported runs have fixed
## timeouts (tests/build.json). `stress.gd -- --horde` runs them (`HORDE`), alone. They pass
## like the others plus a frame line (`p95_line_ms`): a provisional line from the first
## measurement (2026-10-30), past which the scenario fails, unlike the others, which only warn.
##
## How the numbers are held. The bots cast their built spells through the real input
## path (`staff_2` and `staff_3` held together, so both built staffs are used). Their
## mana and health are kept full (so they keep casting), and enemies are added whenever
## fewer than the target stand, with more health than the game's imp, so fights go on.
## The shots the spells make are never enough for 500 or 3,000, so each physics step
## the runner tops the projectile manager up to the target with plain shots owned by the
## players in turn (at most TOP_UP_PER_STEP a step); the manager's cap is set to the
## target, so the oldest shot of the richest owner is dropped past it, as in play.
##
## Pass (`STRESS OK`): in each scenario the enemies and the shots averaged at least 90% of
## the target over the measured window, every bot cast during it, spell shots (not
## fillers) hit something, frames were measured, no build was refused and the log has no
## error. The fillers are load only; the hit and reaction paths are exercised by the
## bots' real spells. Frame time never fails the run: past 16.7 ms it prints a `BENCH WARNING:`
## with likely fixes (docs/PLAN.md, "Gates are sparse"). `BENCH:` lines carry the numbers: the
## frame (probe.gd, with its parts: physics steps per frame, physics and process time, renderer
## time) and, timed here in the measured window, one pass over the crowd of the enemy step, of
## the combat lookups it makes and of Feel's step.
##
## Started by `stress.gd` (a SceneTree script run from the command line) or, shortened, by
## `test_stress.gd` (`build.sh --quick --tests`). Part 25 adds the exports. The node prints
## `STRESS OK` or `STRESS FAILED` and quits with 0 or 1.
##
## Reproducibility: the filler shots and the enemy places use a fixed seed. The rest of
## the run varies only with frame timing, like the 4-bot test.

const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const ProbeScript := preload("res://tests/benchmark/probe.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SwarmScript := preload("res://gameplay/horde/swarm.gd")
const TreeProfileScript := preload("res://tests/benchmark/tree_profile.gd")

const PLAYERS: int = 4
## The horde scenarios' frame line (p95, milliseconds; headless, so game logic only):
## provisional, from the first measurement (2026-10-30, docs/milestones/horde.md, "Scale": p95
## about 310 ms at 600 enemies on the build machine, the physics steps at their limit of 8 a
## frame), with room for a slower or busier machine. It only catches a collapse; 60 FPS at 500+
## enemies needs the swarm work described there (H6). Not checked in a web build, whose WASM
## and software renderer are several times slower.
const P95_LINE_HORDE_MS: float = 600.0
## The scenarios: label, enemies, shots, and (variants only) whether the scene is drawn and
## whether hit particles start. The web scenarios follow the web cap on purpose (the web
## budget is that cap); the PLAN's 1,000 is the older figure to compare against. `desktop_only`
## scenarios are left out of a web build (`scenarios_for`). A horde scenario (`staffed`: the
## share of its enemies that carry a staff, the rest are swarmers) has a frame line,
## `p95_line_ms`: its 95th percentile frame must stay under it.
const SCENARIOS: Array[Dictionary] = [
	{"label": "web", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB},
	{"label": "desktop", "enemies": 200, "shots": 3000, "desktop_only": true},
	{"label": "web, render loop off", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "render": false},
	{"label": "web, hit particles off", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "particles": false},
	{"label": "horde", "enemies": 600, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "staffed": 0.1, "p95_line_ms": P95_LINE_HORDE_MS, "desktop_only": true},
	{"label": "horde, web", "enemies": 500, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "staffed": 0.1, "p95_line_ms": P95_LINE_HORDE_MS},
	{"label": "horde, swarm", "enemies": 1016, "swarm": 1000, "staff_enemies": 16, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "p95_line_ms": P95_LINE_HORDE_MS, "desktop_only": true},
	{"label": "horde, swarm, web size", "enemies": 525, "swarm": 500, "staff_enemies": 25, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "p95_line_ms": P95_LINE_HORDE_MS},
]
## The horde scenarios, run by `stress.gd -- --horde` instead of the default ones.
const HORDE: Array[int] = [4, 5]
## The swarm scenarios (docs/milestones/horde-swarm.md, S1 and S4): `swarm` swarmers (the crypt
## mite's kind with ENEMY_HEALTH) in a swarm (`swarm.gd`) the runner steps, with its look (the
## batched `SwarmLook` the director gives it in play), beside `staff_enemies` staff enemies as full
## actors (the bots fight only actors). Swarmers, staff enemies and the four wizards are all actors,
## so together they stay within the actor table (`Actors.ACTORS`, 1,024): 1,000 + 16 + 4. (Asked for
## 1,000 + 50, the runner tried 30 more spawns every frame that the full table refused, each making
## and freeing a node: about 4 ms a frame of nothing, S4.) The runner then steps the projectile
## manager, Spells and Combat itself, before the swarm's step, and times them per physics step
## (`BENCH: stress parts, physics step`), the look's step apart from the swarm's and its drawing
## (Feel's flash and the batches, in its `_process`) per frame. `horde, swarm` is the desktop's
## 1,000; `horde, swarm, web size` the web's 500, also measured on the desktop (scripts in WASM run
## roughly 2-3x slower, so the web frame is estimated from it). Run by `stress.gd -- --horde-swarm`,
## alone; `--swarm=N` and `--staff=M` set the counts of both (a sweep), `--profile` adds the tree
## profile (tree_profile.gd), `--profile-signals` also times the hot events' listeners.
const HORDE_SWARM: Array[int] = [6, 7]
const SWARM_KIND_ID: StringName = &"crypt_mite"
## Swarmers added per frame at most.
const SWARM_SPAWN_PER_FRAME: int = 60
## Game seconds a scenario takes to build up before frames are measured, and to measure.
const WARM_UP: float = 3.0
const MEASURE: float = 10.0
## Health of a stress enemy (the game's imp has 20), so the crowd lasts.
const ENEMY_HEALTH: float = 120.0
## A horde swarmer: the imp's body with no staff, a little faster, hurting by touch.
const SWARM_SPEED: float = 55.0
const SWARM_CONTACT: int = 3
## Enemies added per frame at most, and filler shots per physics step at most.
const SPAWN_PER_FRAME: int = 10
const TOP_UP_PER_STEP: int = 120
## Where enemies appear (inside the walls of the 640x360 room).
const ENEMY_AREA: Rect2 = Rect2(48.0, 48.0, 544.0, 264.0)
## The timing pass over the crowd (`_time_parts`) runs on every PARTS_EVERY-th drawn frame.
const PARTS_EVERY: int = 30
## Filler shots: speed range (px/s), life (s), radius and pierce.
const FILLER_SPEED_MIN: float = 80.0
const FILLER_SPEED_MAX: float = 260.0
const FILLER_LIFE: float = 4.0
const FILLER_RADIUS: float = 4.0
const FILLER_PIERCE: int = 2
const SEED: int = 24
## A scenario passes at this share of its targets.
const REACH: float = 0.9
const FRAME_BUDGET_MS: float = 1000.0 / 60.0

## The build of each player: the cards of staff X and staff Y (the A staff keeps its dash).
## Heavy on purpose: splits, rings, orbits, triggers with payloads, all four elements.
const STAFFS: Array[Array] = [
	[
		[&"fire", &"split", &"bigger", &"on_hit", &"nova", &"storm", &"bolt"],
		[&"frost", &"timer", &"orbit", &"fire", &"split", &"bolt"],
	],
	[
		[&"storm", &"chain", &"pierce", &"beam"],
		[&"void", &"homing", &"split", &"on_expire", &"bolt", &"fire", &"nova"],
	],
	[
		[&"frost", &"timer", &"rune", &"frost", &"nova"],
		[&"storm", &"split", &"pierce", &"nova"],
	],
	[
		[&"fire", &"split", &"homing", &"faster", &"on_hit", &"bolt", &"frost", &"split", &"bolt"],
		[&"void", &"on_hit", &"nova", &"fire", &"nova"],
	],
]

## Game seconds a scenario's two phases last; a test sets them (before the node enters the
## tree) for a short run.
var warm_up: float = WARM_UP
var measure: float = MEASURE
## Whether a horde scenario's frame line can fail it; a short test run turns it off (its
## measured window is too short and its machine too busy for a frame time to mean much).
var frame_lines: bool = true
## The scenarios to run, in order (indexes into SCENARIOS); `_ready` keeps the ones for this
## build (`scenarios_for`).
var scenarios: Array[int] = [0, 2, 3, 1]

var _log: Logger = ErrorLogScript.new()
var _logging: bool = false
var _failures: Array[String] = []
var _events: Node
var _flow: Node
var _feel: Node
var _input: Node
var _projectiles: Node
var _bots: Array[BotScript] = []
var _probe: Node
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Node2D] = []
var _enemy_data: EnemyBase = null
## The horde's swarmer (`_swarm_data`), how many staff enemies a horde scenario keeps standing,
## and how many of the crowd carry a staff now.
var _swarm_data: EnemyBase = null
## The hot events whose listeners the tree profile times (`--profile-signals`).
const PROFILED_SIGNALS: Array[StringName] = [&"damage_dealt", &"projectile_hit", &"enemy_died", &"hit_landed", &"status_applied", &"reaction_triggered", &"spell_cast"]


## The swarm's look, timed: its step (inside the swarm's) and its drawing (in `_process`).
class TimedLook:
	extends SwarmLook
	var runner: Node

	func step(delta: float) -> void:
		var start: int = Time.get_ticks_usec()
		super.step(delta)
		runner.call(&"count_look", Time.get_ticks_usec() - start, false)

	func step_feel(real_delta: float) -> void:
		var start: int = Time.get_ticks_usec()
		super.step_feel(real_delta)
		runner.call(&"count_look", Time.get_ticks_usec() - start, true)


## The swarm scenario's swarm, its node, its kind and how many swarmers it keeps; the systems it
## steps itself, and microseconds and steps timed in the measured window.
var _swarm: SwarmScript = null
var _swarm_node: Node2D = null
var _swarm_kind: SwarmKind = null
var _target_swarm: int = 0
var _combat: Node = null
var _spells: Node = null
var _spells_usec: int = 0
var _spells_max_usec: int = 0
var _swarm_usec: int = 0
var _projectiles_usec: int = 0
var _combat_usec: int = 0
var _swarm_max_usec: int = 0
var _projectiles_max_usec: int = 0
var _combat_max_usec: int = 0
var _timed_steps: int = 0
var _target_staffed: int = 0
var _staffed: int = 0
## The wizards of the scenario running and their Downed components, by seat.
var _wizards: Array[Actor] = []
var _downs: Array[Downed] = []
var _casts: Array[int] = [0, 0, 0, 0]
var _current: int = -1
var _target_enemies: int = 0
var _target_shots: int = 0
var _elapsed: float = 0.0
var _measuring: bool = false
var _active: bool = false
var _default_cap: int = 0
var _peak_enemies: int = 0
var _peak_shots: int = 0
var _enemy_sum: int = 0
var _enemy_samples: int = 0
var _shot_sum: int = 0
var _shot_samples: int = 0
var _hits: int = 0
var _reactions: int = 0
var _refused: int = 0
## The projectile manager's `dropped` and the spell runtime's `fires_waited` when the measured
## window began: what the cap dropped and what the fire pacing held back while measured.
var _dropped_at: int = 0
var _waited_at: int = 0
## Microseconds spent in each timed part over the measured frames (see `_time_parts`).
var _enemy_step_usec: int = 0
var _lookup_usec: int = 0
var _feel_step_usec: int = 0
var _enemy_step_max_usec: int = 0
var _lookup_max_usec: int = 0
var _parts_frames: int = 0
var _process_frames: int = 0
## `--profile`: a tree profile (tree_profile.gd) rides along in the measured window (diagnostic: it
## changes the order nodes process in).
var profile: bool = false
var _tree_profile: Node = null
## `--swarm=N` and `--staff=M`: the swarm scenarios' counts instead of their own (-1: their own).
var swarm_override: int = -1
var staff_override: int = -1
## The swarm's look (TimedLook) and its microseconds: its step within the swarm's, per physics step,
## and its drawing per frame.
var _look: SwarmLook = null
var _look_usec: int = 0
var _look_draw_usec: int = 0
var _look_draw_frames: int = 0


func _ready() -> void:
	OS.add_logger(_log)
	_logging = true
	var root: Node = get_tree().root
	_events = root.get_node_or_null("Events")
	_flow = root.get_node_or_null("Flow")
	_input = root.get_node_or_null("PlayerInput")
	_projectiles = root.get_node_or_null("Projectiles")
	_feel = root.get_node_or_null("Feel")
	if _events == null or _flow == null or _input == null or _projectiles == null:
		_finish(["the Events, PlayerInput, Flow and Projectiles autoloads must exist"])
		return
	_default_cap = int(_projectiles.call("get_cap"))
	scenarios = scenarios_for(scenarios_from_args(OS.get_cmdline_user_args() + OS.get_cmdline_args(), scenarios), OS.has_feature("web"))
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	profile = profile or args.has("--profile")
	for arg in args:
		if arg.begins_with("--swarm="):
			swarm_override = arg.trim_prefix("--swarm=").to_int()
		elif arg.begins_with("--staff="):
			staff_override = arg.trim_prefix("--staff=").to_int()
	if OS.has_feature("web"):
		frame_lines = false
	_events.connect("spell_cast", _on_spell_cast)
	_events.connect("build_refused", _on_build_refused)
	_events.connect("projectile_hit", _on_projectile_hit)
	_events.connect("reaction_triggered", _on_reaction_triggered)
	_next_scenario()


## `wanted` without the desktop-only scenarios when `web` (a web build measures the web budget
## only).
static func scenarios_for(wanted: Array[int], web: bool) -> Array[int]:
	var out: Array[int] = []
	for index in wanted:
		if not (web and bool(SCENARIOS[index].get("desktop_only", false))):
			out.append(index)
	return out


## The scenarios a run's user arguments ask for: the horde ones for `--horde`, else `default`.
static func scenarios_from_args(args: PackedStringArray, default: Array[int]) -> Array[int]:
	if args.has("--horde-swarm"):
		return HORDE_SWARM.duplicate()
	return HORDE.duplicate() if args.has("--horde") else default.duplicate()


func _exit_tree() -> void:
	_stop_logging()


func _stop_logging() -> void:
	if _logging:
		_logging = false
		OS.remove_logger(_log)


## Start the next scenario, or finish when there is none.
func _next_scenario() -> void:
	_current += 1
	if _current >= scenarios.size():
		_finish(_check_log())
		return
	var scenario: Dictionary = SCENARIOS[scenarios[_current]]
	_target_enemies = scenario["enemies"]
	_target_shots = scenario["shots"]
	_target_staffed = ceili(float(_target_enemies) * float(scenario.get("staffed", 1.0)))
	_target_swarm = int(scenario.get("swarm", 0))
	if _target_swarm > 0:
		_target_staffed = int(scenario.get("staff_enemies", 0))
		if swarm_override >= 0:
			_target_swarm = maxi(swarm_override, 1)
		if staff_override >= 0:
			_target_staffed = staff_override
		_target_enemies = _target_swarm + _target_staffed
	_look_usec = 0
	_look_draw_usec = 0
	_look_draw_frames = 0
	_swarm_usec = 0
	_spells_usec = 0
	_spells_max_usec = 0
	_projectiles_usec = 0
	_combat_usec = 0
	_swarm_max_usec = 0
	_projectiles_max_usec = 0
	_combat_max_usec = 0
	_timed_steps = 0
	_staffed = 0
	_rng.seed = SEED
	_casts = [0, 0, 0, 0]
	_peak_enemies = 0
	_peak_shots = 0
	_enemy_sum = 0
	_enemy_samples = 0
	_shot_sum = 0
	_shot_samples = 0
	_hits = 0
	_reactions = 0
	_elapsed = 0.0
	_measuring = false
	_enemy_step_usec = 0
	_lookup_usec = 0
	_feel_step_usec = 0
	_enemy_step_max_usec = 0
	_lookup_max_usec = 0
	_parts_frames = 0
	_enemies.clear()
	RenderingServer.render_loop_enabled = scenario.get("render", true)
	if _feel != null:
		_feel.set("particles_enabled", scenario.get("particles", true))
	_projectiles.call("set_cap", _target_shots)
	for index in PLAYERS:
		var bot := BotScript.new()
		if not bot.join(index, BotScript.Mode.FIGHTER, _input, _flow):
			_finish(["bot %d could not take its virtual device" % (index + 1)])
			return
		_bots.append(bot)
	# As a player starts: the first Play loads behind the loading screen (the shaders compile
	# there, not while this run is measured); the scenario goes on when the room is up.
	_events.emit_signal("play_requested", 0)
	var loading: Node = get_tree().root.get_node_or_null("Loading")
	if loading != null and bool(loading.call("is_loading")):
		_events.connect("room_entered", _on_loaded, CONNECT_ONE_SHOT)
		return
	_start_measuring(scenario)


func _on_loaded(_room_id: StringName) -> void:
	_start_measuring(SCENARIOS[scenarios[_current]])


## The room is up (or should be): give the wizards their stress staffs and start the scenario.
func _start_measuring(scenario: Dictionary) -> void:
	if _flow.get("world") == null:
		_finish(["the run did not start"])
		return
	_enemy_data = _stress_enemy_data()
	if _enemy_data == null:
		_finish(["the enemy data is missing"])
		return
	_swarm_data = swarm_data(_enemy_data)
	if _target_swarm > 0 and not _start_swarm():
		_finish(["the swarm could not start"])
		return
	_wizards.clear()
	_downs.clear()
	for index in PLAYERS:
		var wizard := _flow.call("get_wizard", index) as Actor
		if wizard == null:
			_finish(["the wizard of player %d is missing" % (index + 1)])
			return
		_wizards.append(wizard)
		_downs.append(Downed.of(wizard))
		for at in 2:
			var cards: Array[StringName] = []
			cards.assign(STAFFS[index][at])
			if not wizard.caster.set_staff(at + 1, cards):
				_finish(["the stress staff %d of player %d was refused" % [at + 1, index + 1]])
				return
	var crowd: String = "%d enemies" % _target_enemies
	if _target_swarm > 0:
		crowd = "%d enemies (%d swarmers with their look, %d staff enemies)" % [_target_enemies, _target_swarm, _target_staffed]
	print("BENCH: stress scenario %s: %d players, %s, %d shots (cap %d), warm-up %.0f s, measured %.0f s" % [scenario["label"], PLAYERS, crowd, _target_shots, int(_projectiles.call("get_cap")), warm_up, measure])
	_active = true


## The swarm scenario: a swarm of the crypt mite's kind (with ENEMY_HEALTH) under a node of the
## world, on the room's floor; the projectile manager, Spells and Combat are stepped by the runner.
func _start_swarm() -> bool:
	var registry: Node = get_tree().root.get_node_or_null("Registry")
	var mite: EnemyBase = registry.call("get_resource", &"enemies", SWARM_KIND_ID) as EnemyBase if registry != null else null
	_combat = get_tree().root.get_node_or_null("Combat")
	_spells = get_tree().root.get_node_or_null("Spells")
	var world := _flow.get("world") as Node2D
	if mite == null or _combat == null or _spells == null or world == null:
		return false
	var data: EnemyBase = mite.duplicate() as EnemyBase
	data.max_health = ENEMY_HEALTH
	_swarm_kind = SwarmKind.new()
	_swarm_kind.enemy_id = SWARM_KIND_ID
	if not _swarm_kind.prepare(data):
		return false
	_swarm_node = Node2D.new()
	_swarm_node.name = "Swarm"
	world.add_child(_swarm_node)
	_swarm = SwarmScript.new()
	_swarm.start(_swarm_node, ENEMY_AREA)
	# Its look, as the director gives it (horde.gd, `_start_swarm`): a child of the same node.
	var look := TimedLook.new()
	look.runner = self
	look.setup(_swarm)
	_swarm_node.add_child(look)
	_swarm.look = look
	_look = look
	_projectiles.set_physics_process(false)
	_spells.set_physics_process(false)
	_combat.set_physics_process(false)
	return true


## The imp's data with more health, so the crowd is not killed within seconds.
func _stress_enemy_data() -> EnemyBase:
	var registry: Node = get_tree().root.get_node_or_null("Registry")
	if registry == null:
		return null
	var data: EnemyBase = registry.call("get_resource", &"enemies", _flow.get("enemy_id_to_play")) as EnemyBase
	if data == null:
		return null
	var copy: EnemyBase = data.duplicate() as EnemyBase
	copy.max_health = ENEMY_HEALTH
	return copy


## A horde swarmer made from a staff enemy's data: the same body with no staff, cards or mana,
## so it only chases and hurts by touch (the horde's swarm enemies are made in parallel, Horde
## H4; the run does not depend on their folders).
static func swarm_data(from: EnemyBase) -> EnemyBase:
	var copy: EnemyBase = from.duplicate() as EnemyBase
	copy.staff = null
	copy.cards = [] as Array[StringName]
	copy.max_mana = 0.0
	copy.mana_regen = 0.0
	copy.move_speed = SWARM_SPEED
	copy.contact_damage = SWARM_CONTACT
	return copy


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_keep_wizards_up()
	for bot in _bots:
		bot.step(delta)
	_top_up_enemies()
	_process_frames += 1
	if _measuring and _process_frames % PARTS_EVERY == 0:
		_time_parts()
	if not _measuring and _elapsed >= warm_up:
		_measuring = true
		_casts = [0, 0, 0, 0]
		_dropped_at = int(_projectiles.get("dropped"))
		_waited_at = _fires_waited()
		_probe = ProbeScript.new()
		add_child(_probe)
		if profile:
			_start_tree_profile()
	if _elapsed >= warm_up + measure:
		_end_scenario()


## Time one pass over the crowd of each part the web frame might be spent on, apart from the
## engine's own work, which probe.gd reads from the monitors. It is an extra pass on top of
## the real steps (about 1.5 ms or more in WASM), so it adds to the frame it runs in; it runs
## on only every PARTS_EVERY-th frame to keep that out of the averages (a maximum or p95 can
## still contain it). A step with delta 0 is nearly a no-op, but not exactly: an enemy may
## retarget or start a windup, and the knockback and Feel's step move their own state. Per pass, not per physics step: the engine runs
## several steps in a late frame.
func _time_parts() -> void:
	var start: int = Time.get_ticks_usec()
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.call("step", 0.0)
	var stepped: int = Time.get_ticks_usec()
	# The two lookups an actor's step makes in Combat (its pace and its knockback).
	for enemy in _enemies:
		if is_instance_valid(enemy):
			var combat: Object = enemy.get("combat")
			if combat != null:
				combat.call("pace", enemy)
				combat.call("consume_knockback", enemy, 0.0)
	var looked: int = Time.get_ticks_usec()
	if _feel != null:
		_feel.call("step", 0.0)
	var done: int = Time.get_ticks_usec()
	var enemy_usec: int = stepped - start
	var lookup_usec: int = looked - stepped
	_enemy_step_usec += enemy_usec
	_lookup_usec += lookup_usec
	_feel_step_usec += done - looked
	_enemy_step_max_usec = maxi(_enemy_step_max_usec, enemy_usec)
	_lookup_max_usec = maxi(_lookup_max_usec, lookup_usec)
	_parts_frames += 1


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _swarm != null:
		_step_swarm_timed(delta)
	_top_up_shots()
	var count: int = int(_projectiles.call("get_count"))
	_peak_shots = maxi(_peak_shots, count)
	if _measuring:
		_shot_sum += count
		_shot_samples += 1


## The swarm scenario's physics step: the projectile manager, Spells, Combat and the swarm, each
## timed. (The runner steps after the world, so the systems run after the actors' step here instead
## of before it; that changes the order within a step, not its cost.)
func _step_swarm_timed(delta: float) -> void:
	var start: int = Time.get_ticks_usec()
	_projectiles.call("step", delta)
	var shot: int = Time.get_ticks_usec()
	_spells.call("step", delta)
	var cast: int = Time.get_ticks_usec()
	_combat.call("step", delta)
	var fought: int = Time.get_ticks_usec()
	_swarm.step(delta)
	var done: int = Time.get_ticks_usec()
	if not _measuring:
		return
	_timed_steps += 1
	_projectiles_usec += shot - start
	_spells_usec += cast - shot
	_spells_max_usec = maxi(_spells_max_usec, cast - shot)
	_combat_usec += fought - cast
	_swarm_usec += done - fought
	_projectiles_max_usec = maxi(_projectiles_max_usec, shot - start)
	_combat_max_usec = maxi(_combat_max_usec, fought - cast)
	_swarm_max_usec = maxi(_swarm_max_usec, done - fought)


## The tree profile (`--profile`); with `--profile-signals` the hot events' listeners are timed too.
func _start_tree_profile() -> void:
	_tree_profile = TreeProfileScript.new()
	add_child(_tree_profile)
	var names: Array[StringName] = []
	for signal_name in PROFILED_SIGNALS:
		if _events.has_signal(signal_name):
			names.append(signal_name)
	if (OS.get_cmdline_user_args() + OS.get_cmdline_args()).has("--profile-signals"):
		_tree_profile.call(&"time_signals", _events, names)


## The look's time (TimedLook): `usec` of its step (`drawn` false) or of its drawing.
func count_look(usec: int, drawn: bool) -> void:
	if not _measuring:
		return
	if drawn:
		_look_draw_usec += usec
		_look_draw_frames += 1
	else:
		_look_usec += usec


## Nobody dies and nobody runs dry: this is a stress scene, not a balance test.
func _keep_wizards_up() -> void:
	for index in _wizards.size():
		var wizard: Actor = _wizards[index]
		if not is_instance_valid(wizard):
			continue
		wizard.caster.mana = wizard.caster.max_mana
		_downs[index].revive(index)
		_downs[index].protect(1.0)


func _top_up_enemies() -> void:
	var alive: int = 0
	_staffed = 0
	for i in range(_enemies.size() - 1, -1, -1):
		var enemy: Node2D = _enemies[i]
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			alive += 1
			if (enemy as Actor).data == _enemy_data:
				_staffed += 1
		else:
			_enemies.remove_at(i)
	var world := _flow.get("world") as Node2D
	if world == null:
		return
	var add: int = mini(_target_enemies - alive, SPAWN_PER_FRAME)
	for i in add:
		if _target_swarm > 0 and _staffed >= _target_staffed:
			break
		var data: EnemyBase = _enemy_data if _staffed < _target_staffed else _swarm_data
		var enemy := data.scene.instantiate() as Actor
		if enemy == null:
			continue
		enemy.data = data
		if data == _enemy_data:
			_staffed += 1
		enemy.position = ENEMY_AREA.position + Vector2(_rng.randf() * ENEMY_AREA.size.x, _rng.randf() * ENEMY_AREA.size.y)
		world.add_child(enemy)
		_enemies.append(enemy)
		alive += 1
	if _swarm != null:
		var room: int = mini(_target_swarm - _swarm.count, SWARM_SPAWN_PER_FRAME)
		for i in room:
			_swarm.spawn(_swarm_kind, ENEMY_AREA.position + Vector2(_rng.randf() * ENEMY_AREA.size.x, _rng.randf() * ENEMY_AREA.size.y))
		alive += _swarm.count
	_peak_enemies = maxi(_peak_enemies, alive)
	if _measuring:
		_enemy_sum += alive
		_enemy_samples += 1


## Fill the manager up to the target with plain shots, cast by the players' wizards in turn.
func _top_up_shots() -> void:
	var missing: int = _target_shots - int(_projectiles.call("get_count"))
	var count: int = mini(missing, TOP_UP_PER_STEP)
	for i in count:
		var owner_index: int = i % PLAYERS
		var wizard := _flow.call("get_wizard", owner_index) as Actor
		if wizard == null:
			continue
		var angle: float = _rng.randf() * TAU
		var speed: float = _rng.randf_range(FILLER_SPEED_MIN, FILLER_SPEED_MAX)
		# A shot's caster is the wizard's actor id (actors G3b), not its seat.
		_projectiles.call("spawn", wizard.id, wizard.global_position, Vector2.from_angle(angle) * speed, FILLER_LIFE, FILLER_RADIUS, ProjectileManagerScript.LAYER_ENEMY, FILLER_PIERCE)


func _on_spell_cast(player: int, _spell_id: StringName, _origin: Vector2, _direction: Vector2) -> void:
	if player >= 0 and player < PLAYERS:
		_casts[player] += 1


## Only shots made by spells have a tag; the fillers have tag 0.
func _on_projectile_hit(_caster: int, _target: Node, _position: Vector2, tag: int, _shot: int) -> void:
	if tag != 0:
		_hits += 1


func _on_reaction_triggered(_caster: int, _reaction_id: StringName, _position: Vector2, _shot: int) -> void:
	_reactions += 1


func _on_build_refused(_player: int, _reason: String) -> void:
	_refused += 1


## Report the scenario, check it and go on to the next.
func _end_scenario() -> void:
	_active = false
	var scenario: Dictionary = SCENARIOS[scenarios[_current]]
	var label: String = scenario["label"]
	if _probe != null:
		print("BENCH: stress %s results" % label)
		_probe.call("report")
		_warn_when_slow(label)
		_report_parts()
		if _tree_profile != null:
			_tree_profile.call(&"report")
			_tree_profile.queue_free()
			_tree_profile = null
	var mean_enemies: float = float(_enemy_sum) / maxf(1.0, float(_enemy_samples))
	var mean_shots: float = float(_shot_sum) / maxf(1.0, float(_shot_samples))
	if scenario.has("staffed"):
		print("BENCH: stress %s: staff enemies standing at the end %d (target %d), the rest swarmers" % [label, _staffed, _target_staffed])
	print("BENCH: stress %s: enemies mean %.0f peak %d of %d, shots mean %.0f peak %d of %d, spell hits %d, reactions %d, casts per player (measured window) %s" % [label, mean_enemies, _peak_enemies, _target_enemies, mean_shots, _peak_shots, _target_shots, _hits, _reactions, str(_casts)])
	# The run holds the cap full on purpose, so `dropped` is how often shots pushed past it; the
	# fires that waited are the trigger fires the pacing moved to a later step (none is lost).
	print("BENCH: stress %s: shots dropped by the cap %d, trigger fires that waited for a later step %d (measured window)" % [label, int(_projectiles.get("dropped")) - _dropped_at, _fires_waited() - _waited_at])
	if mean_enemies < float(_target_enemies) * REACH:
		_failures.append("%s: on average only %.0f of %d enemies stood" % [label, mean_enemies, _target_enemies])
	if mean_shots < float(_target_shots) * REACH:
		_failures.append("%s: on average only %.0f of %d shots flew" % [label, mean_shots, _target_shots])
	if _hits == 0:
		_failures.append("%s: no spell shot hit anything" % label)
	for index in PLAYERS:
		if _casts[index] == 0:
			_failures.append("%s: bot %d never cast a spell while measured" % [label, index + 1])
	if _probe == null or int(_probe.call("frame_count")) == 0:
		_failures.append("%s: no frames were measured" % label)
	elif frame_lines and scenario.has("p95_line_ms"):
		var p95: float = _probe.call("percentile_95")
		var line: float = scenario["p95_line_ms"]
		if p95 > line:
			_failures.append("%s: p95 frame time %.2f ms is over its line of %.1f ms" % [label, p95, line])
	_teardown_scenario()
	_next_scenario()


## The spell runtime's `fires_waited`, or 0 without the Spells autoload.
func _fires_waited() -> int:
	var spells: Node = get_tree().root.get_node_or_null("Spells")
	return int(spells.get("fires_waited")) if spells != null else 0


## One `BENCH:` line each for the timed parts: milliseconds for one pass over the crowd.
func _report_parts() -> void:
	var frames: float = maxf(1.0, float(_parts_frames))
	var crowd: float = maxf(1.0, float(_enemies.size()))
	print("BENCH: stress parts, enemy step: avg %.3f ms max %.3f ms for one pass over %d enemies (%.1f us each; includes the combat lookups)" % [float(_enemy_step_usec) / frames / 1000.0, float(_enemy_step_max_usec) / 1000.0, _enemies.size(), float(_enemy_step_usec) / frames / crowd])
	print("BENCH: stress parts, combat status lookups (speed factor and knockback): avg %.3f ms max %.3f ms per pass" % [float(_lookup_usec) / frames / 1000.0, float(_lookup_max_usec) / 1000.0])
	if _timed_steps > 0:
		var steps: float = float(_timed_steps)
		print("BENCH: stress parts, physics step (%d steps, %d swarmers at the end): swarm without its look avg %.3f ms (max with it %.3f), swarm look step avg %.3f ms, projectile manager avg %.3f ms max %.3f, Spells avg %.3f ms max %.3f, Combat avg %.3f ms max %.3f" % [_timed_steps, _swarm.count if _swarm != null else 0, float(_swarm_usec - _look_usec) / steps / 1000.0, float(_swarm_max_usec) / 1000.0, float(_look_usec) / steps / 1000.0, float(_projectiles_usec) / steps / 1000.0, float(_projectiles_max_usec) / 1000.0, float(_spells_usec) / steps / 1000.0, float(_spells_max_usec) / 1000.0, float(_combat_usec) / steps / 1000.0, float(_combat_max_usec) / 1000.0])
		print("BENCH: stress parts, swarm look drawing (Feel's flash and squash, the batches' buffers; its _process): avg %.3f ms a frame" % (float(_look_draw_usec) / maxf(1.0, float(_look_draw_frames)) / 1000.0))
	print("BENCH: stress parts, Feel step (hit particles, flashes, labels; the particles' own work is in the renderer and the particles-off run): avg %.3f ms per pass" % (float(_feel_step_usec) / frames / 1000.0))


## A warning, never a failure, when the 95th percentile frame is over the 60 FPS budget.
func _warn_when_slow(label: String) -> void:
	var p95: float = _probe.call("percentile_95")
	if p95 > FRAME_BUDGET_MS:
		print("BENCH WARNING: stress %s: p95 frame time %.2f ms is over the %.1f ms budget. Likely fixes: lower the shot cap or the limits in core/spells/limits.gd, fewer hit particles in Feel, a cheaper per-enemy step in the AI, and Combat's linear status lookups (docs/BACKLOG.md)." % [label, p95, FRAME_BUDGET_MS])


func _teardown_scenario() -> void:
	for bot in _bots:
		bot.leave()
	_bots.clear()
	if _flow != null:
		_flow.call("stop_run")
	_enemies.clear()
	_stop_swarm()
	_restore_diagnostics()
	if _probe != null:
		_probe.free()
		_probe = null


## The swarm scenario's end: the swarm forgotten, the systems step themselves again.
func _stop_swarm() -> void:
	if _swarm != null:
		_swarm.stop()
	_swarm = null
	_look = null
	_swarm_node = null
	_target_swarm = 0
	_projectiles.set_physics_process(true)
	if _spells != null:
		_spells.set_physics_process(true)
	if _combat != null:
		_combat.set_physics_process(true)


## Back to drawing with particles, after a variant (and when the run ends).
func _restore_diagnostics() -> void:
	RenderingServer.render_loop_enabled = true
	if _feel != null:
		_feel.set("particles_enabled", true)


func _check_log() -> Array[String]:
	var found: Array[String] = _failures.duplicate()
	if _refused > 0:
		found.append("%d builds were refused" % _refused)
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		found.append("the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	return found


func _finish(failed: Array[String]) -> void:
	_active = false
	_stop_logging()
	_restore_diagnostics()
	if _projectiles != null and _default_cap > 0:
		_projectiles.call("set_cap", _default_cap)
	if failed.is_empty():
		print("STRESS OK: %d scenarios, 4 players with built spells, enemies and shots at the targets, no errors logged" % scenarios.size())
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("STRESS FAILED: " + reason)
		get_tree().quit(1)
