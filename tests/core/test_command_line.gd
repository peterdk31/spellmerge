extends "res://tests/support/suite.gd"
## The game's own arguments and "is this run automated?" (core/base/command_line.gd). The web's
## page arguments come without a `--` (as the engine's list): a check that read only the user list
## took the web test build's replay runs for a player's, recorded them with boss intros on and
## parted the web from every desktop at tick 0 (the daily platform compare, 2026-11-22).


func test_the_web_pages_arguments_are_the_games_own() -> void:
	var page := PackedStringArray(["--replay-hashes", "--ticks=600"])
	var args: PackedStringArray = CommandLine.user_arguments_of(PackedStringArray(), page, true)
	check_equal(args, page, "the page's args are the game's")
	check(CommandLine.automated_of(false, args), "a web page with args is automated (no boss intros)")


func test_a_players_web_page_is_not_automated() -> void:
	var args: PackedStringArray = CommandLine.user_arguments_of(PackedStringArray(), PackedStringArray(), true)
	check(not CommandLine.automated_of(false, args), "a page with no args is a player's")


func test_a_desktops_engine_arguments_are_not_the_games() -> void:
	var engine := PackedStringArray(["--rendering-driver", "opengl3"])
	var args: PackedStringArray = CommandLine.user_arguments_of(PackedStringArray(), engine, false)
	check(args.is_empty(), "the engine's own arguments stay the engine's")
	check(not CommandLine.automated_of(false, args), "a player who starts the game with an engine argument still gets boss intros")
	var user := PackedStringArray(["--four-bot"])
	check_equal(CommandLine.user_arguments_of(user, engine, false), user, "after a --: the game's")
	check(CommandLine.automated_of(false, user), "a desktop run with arguments is automated")


func test_a_test_script_is_automated() -> void:
	check(CommandLine.automated_of(true, PackedStringArray()), "under a test script")
	check(CommandLine.automated(), "this run, under the test runner")
