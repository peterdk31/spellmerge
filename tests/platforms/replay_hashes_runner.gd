extends Node
## The same game on every platform, a first look (online-ready N2b, docs/milestones/online-ready.md):
## a scripted sandbox fight and a horde run of a bot are recorded and played back on the real game
## (tests/support/replay_run.gd), and every tick's state hash, per area, is printed, so the runs on
## Linux, Windows and the web can be compared line by line. `tools/platform_hashes.py` exports the
## three builds, runs each and names the first tick and area that part (tools/README.md).
##
## The main menu adds this node in the test exports (Linux Test, Windows Test, Web Test) on the user
## argument `--replay-hashes`, as it adds the stress run on `--stress`:
##
##     build/linux-test/Spellmerge.x86_64 --headless -- --replay-hashes --ticks=600
##
## User arguments (on the web, the page's `args`):
## - `--scenes=sandbox,horde` (SCENES: also `wave`, two bots in the waves);
## - `--ticks=N`, the ticks of each run (TICKS);
## - `--keep=SCENE:TICK`, repeatable: the played run of SCENE prints every leaf of tick TICK
##   (`REPLAY LEAF`), so the compare tool names the members that part;
## - `--no-native`: the projectile manager and the swarm on their GDScript (the Windows Test export
##   has no native module where MinGW is missing; `--no-native` on Linux shows that changes nothing).
##
## Every platform plays the same game: the run's seed is fixed (RUN_SEED), and the projectile cap and
## the horde's alive cap are the web's everywhere (CAP, `Horde.web`; per-machine settings until N11
## makes them a run's). The lines, one
## per tick of the played run (fields separated by tabs, hashes in hex):
##
##     REPLAY START	<scene>	<platform>	ticks=<n>	native=<on|off>	cap=<n>
##     REPLAY INPUT	<scene>	<md5 of the replay's bytes: the same inputs on every platform>
##     REPLAY TICK	<scene>	<tick>	<whole>	<area>=<hash>	...
##     REPLAY LEAF	<scene>	<area>	<md5 of the value's bytes>	<path>	<the value, shown>
##     REPLAY SELF	<scene>	agree | parts at tick <n>	(the recorded run against its replay, here)
##
## then `REPLAY HASHES OK`, or `REPLAY HASHES FAILED: ...` with what went wrong. A desktop build quits.

const ReplayRun := preload("res://tests/support/replay_run.gd")

## The runs, by name: how each starts, its fighter bots and its scripted players.
const SCENES: Dictionary = {
	"sandbox": {"start": &"sandbox_requested", "bots": 0, "scripted": 1},
	"horde": {"start": &"horde_requested", "bots": 1, "scripted": 0},
	"wave": {"start": &"play_requested", "bots": 2, "scripted": 0},
}
const DEFAULT_SCENES: PackedStringArray = ["sandbox", "horde"]
## Ticks of each run: ten seconds of game.
const TICKS: int = 600
## The run's seed on every platform (any fixed one; a random one would deal each a different horde).
const RUN_SEED: int = 20261105
## The projectile cap every platform plays at: the web's (ProjectileManager.DEFAULT_CAP_WEB).
const CAP: int = 1000

var _scenes: PackedStringArray = DEFAULT_SCENES
var _ticks: int = TICKS
var _native: bool = true
## SCENE -> the tick whose leaves are printed.
var _keep: Dictionary = {}


func _ready() -> void:
	_read_arguments(OS.get_cmdline_user_args() + OS.get_cmdline_args())
	_run.call_deferred()


func _read_arguments(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--scenes="):
			_scenes = arg.trim_prefix("--scenes=").split(",", false)
		elif arg.begins_with("--ticks="):
			_ticks = maxi(arg.trim_prefix("--ticks=").to_int(), 1)
		elif arg.begins_with("--keep="):
			var parts: PackedStringArray = arg.trim_prefix("--keep=").split(":")
			if parts.size() == 2:
				_keep[parts[0]] = parts[1].to_int()
		elif arg == "--no-native":
			_native = false


func _run() -> void:
	var problems := PackedStringArray()
	# Out of the main menu's first frames: the menu is ready and the game idle.
	await get_tree().physics_frame
	for scene in _scenes:
		if not SCENES.has(scene):
			problems.append("unknown scene %s" % scene)
			continue
		problems.append_array(await _run_scene(scene))
	if problems.is_empty():
		print("REPLAY HASHES OK")
	else:
		print("REPLAY HASHES FAILED: %s" % "; ".join(problems))
	if not OS.has_feature("web"):
		get_tree().quit(0 if problems.is_empty() else 1)


## One scene recorded and played back; its lines printed. Returns its problems.
func _run_scene(scene: String) -> PackedStringArray:
	var info: Dictionary = SCENES[scene]
	var run := ReplayRun.new(get_tree())
	run.ticks = _ticks
	run.native = _native
	run.cap = CAP
	run.horde_web = 1
	run.run_seed = RUN_SEED
	print("REPLAY START\t%s\t%s\tticks=%d\tnative=%s\tcap=%d" % [scene, OS.get_name(), _ticks, "on" if _native and _native_loaded() else "off", CAP])
	var recorded := Desync.new()
	var replay: Replay = await run.record(info["start"], info["bots"], info["scripted"], recorded)
	if replay == null:
		return PackedStringArray(["%s: nothing was recorded" % scene])
	print("REPLAY INPUT\t%s\t%s" % [scene, _md5(replay.to_bytes())])
	var played := Desync.new(int(_keep.get(scene, -1)))
	await run.play(replay, info["bots"], played)
	for tick in played.hashes.size():
		_print_tick(scene, tick, played.hashes[tick])
	if played.keep_tick >= 0:
		_print_leaves(scene, played)
	var parting: int = Desync.first_parting(recorded, played)
	print("REPLAY SELF\t%s\t%s" % [scene, "agree" if parting < 0 else "parts at tick %d" % parting])
	var problems := PackedStringArray()
	for problem in run.problems:
		problems.append(problem)
	for problem in recorded.problems + played.problems:
		problems.append("%s: %s" % [scene, problem])
	await run.fresh()
	return problems


func _print_tick(scene: String, tick: int, hashes: Dictionary) -> void:
	var typed: Dictionary[String, int] = {}
	var parts := PackedStringArray()
	for area: String in hashes:
		typed[area] = int(hashes[area])
		parts.append("%s=%s" % [area, _hex(int(hashes[area]))])
	print("REPLAY TICK\t%s\t%d\t%s\t%s" % [scene, tick, _hex(SimHash.whole(typed)), "\t".join(parts)])


func _print_leaves(scene: String, run: Desync) -> void:
	for area: String in run.leaves:
		var leaves: Dictionary = run.leaves[area]
		for path: Variant in leaves:
			var value: Variant = leaves[path]
			print("REPLAY LEAF\t%s\t%s\t%s\t%s\t%s" % [scene, area, _md5(var_to_bytes(value)), path, Desync._shown(value).replace("\n", " ").replace("\t", " ")])


func _native_loaded() -> bool:
	return bool(get_tree().root.get_node("Projectiles").call("is_native"))


## A 64-bit hash as 16 hex digits (its bytes, little end first: `%x` would sign a negative one).
static func _hex(value: int) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, value)
	return bytes.hex_encode()


static func _md5(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(bytes)
	return context.finish().hex_encode()
