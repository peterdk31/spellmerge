extends "res://tests/support/suite.gd"
## A long test file runs as several processes side by side (`# unit-test-shards: N`, run by
## ci/build/unit_tests.sh): each process is handed `--shard=K/N` and runs every Nth test method.


func test_a_shard_argument_is_read() -> void:
	check_equal(shard_of(PackedStringArray(["--shard=2/6"])), Vector2i(2, 6), "the third of six")
	check_equal(shard_of(PackedStringArray(["--other", "--shard=0/3"])), Vector2i(0, 3), "among other arguments")


func test_without_a_sensible_shard_the_whole_file_runs() -> void:
	for args: PackedStringArray in [PackedStringArray(), PackedStringArray(["--shard=6/6"]), PackedStringArray(["--shard=x/2"]), PackedStringArray(["--shard=1"]), PackedStringArray(["--shard=0/0"])]:
		check_equal(shard_of(args), Vector2i(0, 1), "%s: the whole file" % [args])


func test_the_shards_run_every_method_once() -> void:
	var names: Array[String] = []
	for i in 13:
		names.append("test_%02d" % i)
	var seen: Array[String] = []
	for k in 4:
		var mine: Array[String] = of_shard(names, Vector2i(k, 4))
		check(mine.size() >= 3, "shard %d has its share: %s" % [k, mine])
		seen.append_array(mine)
	seen.sort()
	check_equal(seen, names, "each method in exactly one shard")
	check_equal(of_shard(names, Vector2i(0, 1)), names, "one shard runs them all")
