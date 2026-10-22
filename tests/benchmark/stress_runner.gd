extends Node
## The stress scene as a node: 4 bots with built spells fight a crowd on the real game
## (Flow, Combat, the projectile manager, the spell runtime, Feel and the HUD), with
## enemies and shots kept at the numbers of the PLAN's stress scenario (docs/PLAN.md,
## "Performance budgets"):
##  - web: 100 enemies, 1,000 shots,
##  - desktop: 200 enemies, 3,000 shots,
## both with four players and full effects (every hit sends its particles, reactions
## and numbers). The two scenarios run one after the other.
##
## How the numbers are held. The bots cast their built spells through the real input
## path (`cast`, and `swap` every SWAP_EVERY seconds so both spells are used). Their
## mana and health are kept full (so they keep casting), and enemies are added whenever
## fewer than the target stand, with more health than the game's imp, so fights go on.
## The shots the spells make are never enough for 1,000 or 3,000, so each physics step
## the runner tops the projectile manager up to the target with plain shots owned by the
## players in turn (at most TOP_UP_PER_STEP a step); the manager's cap is set to the
## target, so the oldest shot of the richest owner is dropped past it, as in play.
##
## Pass (`STRESS OK`): in each scenario the enemies and the shots reached at least 90% of
## the target, every bot cast, frames were measured, no build was refused and the log has
## no error. Frame time never fails the run: past 16.7 ms it prints a `BENCH WARNING:`
## with likely fixes (docs/PLAN.md, "Gates are sparse"). `BENCH:` lines carry the numbers.
##
## Started by `stress.gd` (a SceneTree script, the editor run) or, shortened, by
## `test_stress.gd` (`build.sh --quick --tests`). Part 25 adds the exports. The node prints
## `STRESS OK` or `STRESS FAILED` and quits with 0 or 1.
##
## Reproducibility: the filler shots and the enemy places use a fixed seed. The rest of
## the run varies only with frame timing, like the 4-bot test.

const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const ProbeScript := preload("res://tests/benchmark/probe.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const AiScript := preload("res://gameplay/ai/ai.gd")

const PLAYERS: int = 4
## The scenarios: label, enemies, shots.
const SCENARIOS: Array[Dictionary] = [
	{"label": "web", "enemies": 100, "shots": 1000},
	{"label": "desktop", "enemies": 200, "shots": 3000},
]
## Game seconds a scenario takes to build up before frames are measured, and to measure.
const WARM_UP: float = 3.0
const MEASURE: float = 10.0
## Health of a stress enemy (the game's imp has 20), so the crowd lasts.
const ENEMY_HEALTH: int = 120
## Enemies added per frame at most, and filler shots per physics step at most.
const SPAWN_PER_FRAME: int = 10
const TOP_UP_PER_STEP: int = 120
## Where enemies appear (inside the walls of the 640x360 room).
const ENEMY_AREA: Rect2 = Rect2(48.0, 48.0, 544.0, 264.0)
## Seconds between the bots' `swap` presses.
const SWAP_EVERY: float = 4.0
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

## The build of each player: slot A and slot B. Heavy on purpose: splits, rings, orbits,
## triggers with held spells, all four elements.
const RECIPES: Array[Array] = [
	[
		{"form": &"nova", "element": &"fire", "modifiers": [&"split", &"bigger"], "trigger": &"on_hit", "held": {"form": &"bolt", "element": &"storm"}},
		{"form": &"orbit", "element": &"frost", "trigger": &"timer", "held": {"form": &"bolt", "element": &"fire", "modifiers": [&"split"]}},
	],
	[
		{"form": &"beam", "element": &"storm", "modifiers": [&"chain", &"pierce"]},
		{"form": &"bolt", "element": &"void", "modifiers": [&"homing", &"split"], "trigger": &"on_expire", "held": {"form": &"nova", "element": &"fire"}},
	],
	[
		{"form": &"rune", "element": &"frost", "trigger": &"timer", "held": {"form": &"nova", "element": &"frost"}},
		{"form": &"nova", "element": &"storm", "modifiers": [&"split", &"pierce"]},
	],
	[
		{"form": &"bolt", "element": &"fire", "modifiers": [&"split", &"homing", &"faster"], "trigger": &"on_hit", "held": {"form": &"bolt", "element": &"frost", "modifiers": [&"split"]}},
		{"form": &"nova", "element": &"void", "trigger": &"on_hit", "held": {"form": &"nova", "element": &"fire"}},
	],
]

## Game seconds a scenario's two phases last; a test sets them (before the node enters the
## tree) for a short run.
var warm_up: float = WARM_UP
var measure: float = MEASURE
## The scenarios to run, in order (indexes into SCENARIOS).
var scenarios: Array[int] = [0, 1]

var _log: Logger = ErrorLogScript.new()
var _logging: bool = false
var _failures: Array[String] = []
var _events: Node
var _flow: Node
var _input: Node
var _projectiles: Node
var _bots: Array[BotScript] = []
var _probe: Node
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Node2D] = []
var _enemy_data: EnemyBase = null
var _casts: Array[int] = [0, 0, 0, 0]
var _current: int = -1
var _target_enemies: int = 0
var _target_shots: int = 0
var _elapsed: float = 0.0
var _swap_left: float = 0.0
var _measuring: bool = false
var _active: bool = false
var _default_cap: int = 0
var _peak_enemies: int = 0
var _peak_shots: int = 0
var _refused: int = 0


func _ready() -> void:
	OS.add_logger(_log)
	_logging = true
	var root: Node = get_tree().root
	_events = root.get_node_or_null("Events")
	_flow = root.get_node_or_null("Flow")
	_input = root.get_node_or_null("PlayerInput")
	_projectiles = root.get_node_or_null("Projectiles")
	if _events == null or _flow == null or _input == null or _projectiles == null:
		_finish(["the Events, PlayerInput, Flow and Projectiles autoloads must exist"])
		return
	_default_cap = int(_projectiles.call("get_cap"))
	_events.connect("spell_cast", _on_spell_cast)
	_events.connect("build_refused", _on_build_refused)
	_next_scenario()


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
	_elapsed = 0.0
	_swap_left = SWAP_EVERY
	_measuring = false
	_enemies.clear()
	_projectiles.call("set_cap", _target_shots)
	for index in PLAYERS:
		var bot := BotScript.new()
		if not bot.join(index, BotScript.Mode.FIGHTER, _input, _flow):
			_finish(["bot %d could not take its virtual device" % (index + 1)])
			return
		_bots.append(bot)
	_events.emit_signal("play_requested", 0)
	if _flow.get("world") == null:
		_finish(["the run did not start"])
		return
	_enemy_data = _stress_enemy_data()
	if _enemy_data == null:
		_finish(["the enemy data is missing"])
		return
	for index in PLAYERS:
		var wizard := _flow.call("get_wizard", index) as PlayerScript
		if wizard == null:
			_finish(["the wizard of player %d is missing" % (index + 1)])
			return
		for slot in 2:
			if not wizard.set_recipe(slot, RECIPES[index][slot]):
				_finish(["the stress recipe %d of player %d was refused" % [slot, index + 1]])
				return
	print("BENCH: stress scenario %s: %d players, %d enemies, %d shots (cap %d), warm-up %.0f s, measured %.0f s" % [scenario["label"], PLAYERS, _target_enemies, _target_shots, int(_projectiles.call("get_cap")), warm_up, measure])
	_active = true


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
	_swap_left -= delta
	var swap: bool = _swap_left <= 0.0
	if swap:
		_swap_left = SWAP_EVERY
	for bot in _bots:
		bot.step(delta)
		if swap:
			_input.call("send_virtual", bot.player, &"swap", 1.0)
			_input.call("send_virtual", bot.player, &"swap", 0.0)
	_top_up_enemies()
	if not _measuring and _elapsed >= warm_up:
		_measuring = true
		_probe = ProbeScript.new()
		add_child(_probe)
	if _elapsed >= warm_up + measure:
		_end_scenario()


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	_top_up_shots()
	_peak_shots = maxi(_peak_shots, int(_projectiles.call("get_count")))


## Nobody dies and nobody runs dry: this is a stress scene, not a balance test.
func _keep_wizards_up() -> void:
	for index in PLAYERS:
		var wizard := _flow.call("get_wizard", index) as PlayerScript
		if wizard == null:
			continue
		wizard.mana = PlayerScript.MAX_MANA
		if wizard.is_downed():
			wizard.revive(index)
		wizard.protect(1.0)


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
		var enemy := _enemy_data.scene.instantiate() as AiScript
		if enemy == null:
			continue
		enemy.data = _enemy_data
		enemy.position = ENEMY_AREA.position + Vector2(_rng.randf() * ENEMY_AREA.size.x, _rng.randf() * ENEMY_AREA.size.y)
		world.add_child(enemy)
		_enemies.append(enemy)
		alive += 1
	_peak_enemies = maxi(_peak_enemies, alive)


## Fill the manager up to the target with plain shots, owned by the players in turn.
func _top_up_shots() -> void:
	var missing: int = _target_shots - int(_projectiles.call("get_count"))
	var count: int = mini(missing, TOP_UP_PER_STEP)
	for i in count:
		var owner_index: int = i % PLAYERS
		var wizard := _flow.call("get_wizard", owner_index) as Node2D
		if wizard == null:
			continue
		var angle: float = _rng.randf() * TAU
		var speed: float = _rng.randf_range(FILLER_SPEED_MIN, FILLER_SPEED_MAX)
		_projectiles.call("spawn", owner_index, wizard.global_position, Vector2.from_angle(angle) * speed, FILLER_LIFE, FILLER_RADIUS, ProjectileManagerScript.LAYER_ENEMY, FILLER_PIERCE)


func _on_spell_cast(player: int, _spell_id: StringName, _origin: Vector2, _direction: Vector2) -> void:
	if player >= 0 and player < PLAYERS:
		_casts[player] += 1


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
	print("BENCH: stress %s: peak enemies %d of %d, peak shots %d of %d, casts per player %s" % [label, _peak_enemies, _target_enemies, _peak_shots, _target_shots, str(_casts)])
	if _peak_enemies < int(float(_target_enemies) * REACH):
		_failures.append("%s: only %d of %d enemies stood at once" % [label, _peak_enemies, _target_enemies])
	if _peak_shots < int(float(_target_shots) * REACH):
		_failures.append("%s: only %d of %d shots flew at once" % [label, _peak_shots, _target_shots])
	for index in PLAYERS:
		if _casts[index] == 0:
			_failures.append("%s: bot %d never cast a spell" % [label, index + 1])
	if _probe == null or int(_probe.call("frame_count")) == 0:
		_failures.append("%s: no frames were measured" % label)
	_teardown_scenario()
	_next_scenario()


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
	if _probe != null:
		_probe.free()
		_probe = null


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
	if _projectiles != null and _default_cap > 0:
		_projectiles.call("set_cap", _default_cap)
	if failed.is_empty():
		print("STRESS OK: %d scenarios, 4 players with built spells, enemies and shots at the targets, no errors logged" % scenarios.size())
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("STRESS FAILED: " + reason)
		get_tree().quit(1)
