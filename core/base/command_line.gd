class_name CommandLine
extends RefCounted
## What the game was started with for itself: the one reader of "is this run automated?".
##
## A desktop build is given its own arguments after a `--` (`OS.get_cmdline_user_args()`), the
## engine's before it. The web has no `--`: its page's start config (`args`, which the test pages
## of `smbot.websmoke` fill) reaches the game as `OS.get_cmdline_args()`, and a player's page passes
## none. So on the web those are the game's own arguments too. A check that read only the user
## arguments missed every web automation: the web test build took its replay runs for a player's,
## recorded them with boss intros on (`SessionRules.boss_intros`, a rule in the replay's header)
## and so parted from every desktop at tick 0 (the platform compare, tools/platform_hashes.py).


## The game's own arguments on this machine.
static func user_arguments() -> PackedStringArray:
	return user_arguments_of(OS.get_cmdline_user_args(), OS.get_cmdline_args(), OS.has_feature("web"))


## The game's own arguments, from the two lists and the platform: the user arguments, and on the
## web the engine's list as well (the page's `args`).
static func user_arguments_of(user: PackedStringArray, engine: PackedStringArray, web: bool) -> PackedStringArray:
	var args := PackedStringArray(user)
	if web:
		args.append_array(engine)
	return args


## True when nobody is there to play: under a test script, or started with arguments of the game's
## own (a test, a bot, a benchmark, a replay run).
static func automated() -> bool:
	var tree: MainLoop = Engine.get_main_loop()
	return automated_of(tree != null and tree.get_script() != null, user_arguments())


static func automated_of(scripted: bool, user_args: PackedStringArray) -> bool:
	return scripted or not user_args.is_empty()
