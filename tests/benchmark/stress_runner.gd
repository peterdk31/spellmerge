extends Node
## The stress scene as a node: 4 bots with built spells fight a crowd on the real game
## (Flow, Combat, the projectile manager, the spell runtime, Feel and the HUD), with
## enemies and shots kept at the numbers of the PLAN's stress scenario (docs/PLAN.md,
## "Performance budgets"):
##  - web: 100 enemies, shots at the web cap (`DEFAULT_CAP_WEB`: 500 from the first web run,
##    1,000 with the native kernel, as the PLAN first said),
##  - desktop: 200 enemies, shots at the desktop cap (`DEFAULT_CAP_DESKTOP`: 3,000, then 6,000),
## both with four players and full effects (every hit sends its particles, reactions
## and numbers). Between them run two diagnostic variants of the web scenario, to explain the
## web frame time (docs/DECISIONS.md, 2026-10-23): one with the render loop off (nothing is
## drawn, so the frame is game logic only) and one with the hit particles off. The four
## scenarios (web, web with the render loop off, web with hit particles off, desktop) run one
## after the other. A web build skips the desktop one (`scenarios_for`): it is the desktop's
## budget, which the desktop export measures, and in CI's software renderer it alone took about
## seven of the web run's fourteen minutes (2026-10-28, when the run went past its timeout).
##
## How the numbers are held. The bots cast their built spells through the real input
## path (their brains play whatever staffs the wizard holds: RB's dash and the two built staffs). Their
## mana and health are kept full (so they keep casting), and enemies are added whenever
## fewer than the target stand, with more health than the game's imp, so fights go on.
## The shots the spells make are never enough for the caps, so each physics step
## the runner tops the projectile manager up to the target with plain shots owned by the
## players in turn (at most TOP_UP_PER_STEP a step, more for a larger target); the manager's cap is set to the
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

const HashLabel := preload("res://tests/benchmark/hash_label.gd")
const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const ProbeScript := preload("res://tests/benchmark/probe.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const TreeProfileScript := preload("res://tests/benchmark/tree_profile.gd")
const TickScript := preload("res://core/sim/tick.gd")

const PLAYERS: int = 4
## The scenarios: label, enemies, shots, and (variants only) whether the scene is drawn and
## whether hit particles start. The web and desktop scenarios follow the caps on purpose (each
## budget is its cap). `desktop_only` scenarios are left out of a web build (`scenarios_for`).
const SCENARIOS: Array[Dictionary] = [
	{"label": "web", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB},
	{"label": "desktop", "enemies": 200, "shots": ProjectileManagerScript.DEFAULT_CAP_DESKTOP, "desktop_only": true},
	{"label": "web, render loop off", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "render": false},
	{"label": "web, hit particles off", "enemies": 100, "shots": ProjectileManagerScript.DEFAULT_CAP_WEB, "particles": false},
]
## Game seconds a scenario takes to build up before frames are measured, and to measure.
const WARM_UP: float = 3.0
const MEASURE: float = 10.0
## Health of a stress enemy (the game's imp has 20), so the crowd lasts.
const ENEMY_HEALTH: float = 120.0
## Enemies added per frame at most, and filler shots per physics step at most: TOP_UP_PER_STEP,
## or more for a larger target (one TOP_UP_SHARE of it a step). Sized for 3,000 shots; at the
## desktop's 6,000 more shots end on the crowd each step than 120 can replace, and the run fell
## short of its target (2026-11-02).
const SPAWN_PER_FRAME: int = 10
const TOP_UP_PER_STEP: int = 120
const TOP_UP_SHARE: int = 25
## Where enemies appear (inside the walls of the 640x360 room).
const ENEMY_AREA: Rect2 = Rect2(48.0, 48.0, 544.0, 264.0)
## The timing pass over the crowd (`_time_parts`) runs on every PARTS_EVERY-th drawn frame.
const PARTS_EVERY: int = 30
## The state hashes timed at a scenario's end (`_report_state_hash`).
const HASH_PASSES: int = 5
## The parts the spread hash is timed in (`SimHash.slice`): one a tick for a second.
const HASH_SLICES: int = 60
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
## The hot events whose listeners the tree profile times (`--profile-signals`).
const PROFILED_SIGNALS: Array[StringName] = [&"damage_dealt", &"projectile_hit", &"enemy_died", &"hit_landed", &"status_applied", &"reaction_triggered", &"spell_cast"]

## The build of each player: the cards of RT and LB (RB keeps its dash). A Play wizard holds two
## staffs (items I2), so the runner hands each wizard three (`Caster.replace_staffs`, every hand it
## is given held): Play's RB and RT and the moon staff on LB, as the wizards held before. Until the
## inventory (I3) puts a staff on a hand, that is the one call that does.
## Heavy on purpose: splits, rings, orbits, triggers with payloads, all four elements.
const STAFFS: Array[Array] = [
	[
		[&"fire", &"split", &"bigger", &"on_hit", &"nova", &"bolt", &"storm", &"bolt"],
		[&"frost", &"timer", &"orbit", &"fire", &"split", &"bolt"],
	],
	[
		[&"storm", &"chain", &"pierce", &"beam"],
		[&"void", &"homing", &"split", &"on_expire", &"bolt", &"fire", &"nova", &"bolt"],
	],
	[
		[&"frost", &"timer", &"rune", &"frost", &"nova", &"bolt"],
		[&"storm", &"split", &"pierce", &"nova", &"bolt"],
	],
	[
		[&"fire", &"split", &"homing", &"faster", &"on_hit", &"bolt", &"frost", &"split", &"bolt"],
		[&"void", &"on_hit", &"nova", &"bolt", &"fire", &"nova", &"bolt"],
	],
]

## Game seconds a scenario's two phases last; a test sets them (before the node enters the
## tree) for a short run.
var warm_up: float = WARM_UP
var measure: float = MEASURE
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
	scenarios = scenarios_for(scenarios, OS.has_feature("web"))
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	profile = profile or args.has("--profile")
	# `--no-native` runs the projectile manager's and WallSlide's GDScript in place of the module
	# (native/README.md).
	if args.has("--no-native"):
		_projectiles.set(&"native", false)
		WallSlide.use_native(false)
	print("BENCH: native module %s" % ("on" if _projectiles.call(&"is_native") else "off"))
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
	# The run takes this machine's rules at its start (online-ready N11): the scenario's cap is this
	# machine's "Max shots" for its run.
	SessionRules.machine().shot_cap = _target_shots
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
	_wizards.clear()
	_downs.clear()
	for index in PLAYERS:
		var wizard := _flow.call("get_wizard", index) as Actor
		if wizard == null:
			_finish(["the wizard of player %d is missing" % (index + 1)])
			return
		_wizards.append(wizard)
		_downs.append(Downed.of(wizard))
		var held: Array[StaffBase] = _stress_hands()
		if held.is_empty():
			_finish(["a basic staff is missing from the registry"])
			return
		var rows: Array = [wizard.caster.cards_of(0)]
		rows.append_array(STAFFS[index])
		wizard.caster.replace_staffs(held, rows)
		for at in 2:
			if not wizard.caster.has_staff(at + 1):
				_finish(["the stress staff %d of player %d was refused" % [at + 1, index + 1]])
				return
	print("BENCH: stress scenario %s: %d players, %d enemies, %d shots (cap %d), warm-up %.0f s, measured %.0f s" % [scenario["label"], PLAYERS, _target_enemies, _target_shots, int(_projectiles.call("get_cap")), warm_up, measure])
	_active = true


## The hands of a stress wizard: Play's two staffs and the moon staff on LB (empty when one is
## missing).
func _stress_hands() -> Array[StaffBase]:
	var out: Array[StaffBase] = []
	var registry: Node = get_tree().root.get_node_or_null("Registry")
	if registry == null:
		return out
	for id: StringName in [&"curl", &"star", &"moon"]:
		var held: StaffBase = registry.call("get_resource", &"wizard", id) as StaffBase
		if held == null:
			out.clear()
			return out
		out.append(held)
	return out


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


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_keep_wizards_up()
	# The bots think at each tick's start, filling their seats' frames (the Frames autoload).
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
	_top_up_shots()
	var count: int = int(_projectiles.call("get_count"))
	_peak_shots = maxi(_peak_shots, count)
	if _measuring:
		_shot_sum += count
		_shot_samples += 1


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


## Nobody dies and nobody runs dry: this is a stress scene, not a balance test.
func _keep_wizards_up() -> void:
	for index in _wizards.size():
		var wizard: Actor = _wizards[index]
		if not is_instance_valid(wizard):
			continue
		for at in wizard.caster.staff_count:
			wizard.caster.set_mana(at, wizard.caster.max_mana_of(at))
		_downs[index].revive(index)
		_downs[index].protect(1.0)


func _top_up_enemies() -> void:
	var alive: int = 0
	for i in range(_enemies.size() - 1, -1, -1):
		var enemy: Node2D = _enemies[i]
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			alive += 1
		else:
			_enemies.remove_at(i)
	var world := _flow.get("world") as Node2D
	if world == null:
		return
	var add: int = mini(_target_enemies - alive, SPAWN_PER_FRAME)
	for i in add:
		var enemy := _enemy_data.scene.instantiate() as Actor
		if enemy == null:
			continue
		enemy.data = _enemy_data
		enemy.position = ENEMY_AREA.position + Vector2(_rng.randf() * ENEMY_AREA.size.x, _rng.randf() * ENEMY_AREA.size.y)
		world.add_child(enemy)
		_enemies.append(enemy)
		alive += 1
	_peak_enemies = maxi(_peak_enemies, alive)
	if _measuring:
		_enemy_sum += alive
		_enemy_samples += 1


## Fill the manager up to the target with plain shots, cast by the players' wizards in turn.
func _top_up_shots() -> void:
	var missing: int = _target_shots - int(_projectiles.call("get_count"))
	var count: int = mini(missing, maxi(TOP_UP_PER_STEP, _target_shots / TOP_UP_SHARE))
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
		_report_state_hash(label)
		if _tree_profile != null:
			_tree_profile.call(&"report")
			_tree_profile.queue_free()
			_tree_profile = null
	var mean_enemies: float = float(_enemy_sum) / maxf(1.0, float(_enemy_samples))
	var mean_shots: float = float(_shot_sum) / maxf(1.0, float(_shot_samples))
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
	print("BENCH: stress parts, Feel step (hit particles, flashes, labels; the particles' own work is in the renderer and the particles-off run): avg %.3f ms per pass" % (float(_feel_step_usec) / frames / 1000.0))


## The state hash's cost at the scenario's full load (online-ready N3c; core/sim/README.md, "The
## hash"): HASH_PASSES hashes of every area the Tick names (`state_areas`), as the netcode would
## make them (no paths), after the measured window so they stay out of its frames; with the areas
## that cost most (the bodies together), and spread over a second, one part a tick
## (`SimHash.slice`), as a netcode checking once a second would.
func _report_state_hash(label: String) -> void:
	var tick: TickScript = get_tree().root.get_node_or_null("Tick") as TickScript
	if tick == null:
		return
	var total: int = 0
	var most: int = 0
	var named: Dictionary = {}
	var problems: PackedStringArray = PackedStringArray()
	var by_area: Dictionary[String, int] = {}
	for i in HASH_PASSES:
		var start: int = Time.get_ticks_usec()
		# An area with parts as its parts (Spells' casters, props W3), as `SimHash.areas` takes it.
		named = SimHash.split_by_actor(tick.state_areas())
		var walk := StateWalk.new()
		walk.with_paths = false
		var hashes: Dictionary[String, int] = {}
		for name: String in named:
			var area_start: int = Time.get_ticks_usec()
			hashes[name] = SimHash.area(walk, name, named[name] as Object)
			var key: String = "bodies" if name.begins_with(SimHash.BODY_PREFIX) else HashLabel.of(name, named[name] as Object)
			by_area[key] = by_area.get(key, 0) + Time.get_ticks_usec() - area_start
		SimHash.whole(hashes)
		problems = walk.problems
		var took: int = Time.get_ticks_usec() - start
		total += took
		most = maxi(most, took)
	var bodies: int = 0
	for name: String in named:
		if name.begins_with(SimHash.BODY_PREFIX):
			bodies += 1
	var parts: Array[String] = []
	var keys: Array = by_area.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return by_area[a] > by_area[b])
	for key: String in keys.slice(0, 4):
		parts.append("%s %.2f" % [key, float(by_area[key]) / float(HASH_PASSES) / 1000.0])
	print("BENCH: stress %s: state hash avg %.2f ms max %.2f ms over %d areas (%d bodies; most: %s ms), %d problems" % [label, float(total) / float(HASH_PASSES) / 1000.0, float(most) / 1000.0, named.size(), bodies, ", ".join(parts), problems.size()])
	for problem in problems.slice(0, 5):
		print("BENCH: stress %s: state hash problem: %s" % [label, problem])
	# Spread over a second, one part a tick (`SimHash.slice`): what a tick pays.
	var part_total: int = 0
	var part_most: int = 0
	for slice in HASH_SLICES:
		var part_start: int = Time.get_ticks_usec()
		var part_walk := StateWalk.new()
		part_walk.with_paths = false
		SimHash.areas(SimHash.slice(tick.state_areas(), slice, HASH_SLICES), part_walk)
		var part_took: int = Time.get_ticks_usec() - part_start
		part_total += part_took
		part_most = maxi(part_most, part_took)
	print("BENCH: stress %s: state hash spread over %d ticks: avg %.2f ms max %.2f ms a tick" % [label, HASH_SLICES, float(part_total) / float(HASH_SLICES) / 1000.0, float(part_most) / 1000.0])


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
	_restore_diagnostics()
	if _probe != null:
		_probe.free()
		_probe = null


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
		SessionRules.machine().shot_cap = _default_cap
		_projectiles.call("set_cap", _default_cap)
	if failed.is_empty():
		print("STRESS OK: %d scenarios, 4 players with built spells, enemies and shots at the targets, no errors logged" % scenarios.size())
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("STRESS FAILED: " + reason)
		get_tree().quit(1)
