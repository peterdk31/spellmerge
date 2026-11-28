extends "res://tests/support/suite.gd"
## Feel's view dice are seeded (`FeelDice`): what the motes, the debris and the spectacle draw by chance
## comes out the same every time a run is played, so two runs' screenshots are the same picture. A
## new generator starts at a random seed; each of these starts at its script's `DICE_SEED`.
const SEEDED: Array[Script] = [
	preload("res://gameplay/feel/air_motes.gd"),
	preload("res://gameplay/feel/cover_motes.gd"),
	preload("res://gameplay/feel/source_motes.gd"),
	preload("res://gameplay/feel/remnants.gd"),
	preload("res://gameplay/feel/spectacle.gd"),
]


func test_a_seeded_generator_rolls_the_same_every_time() -> void:
	var first: RandomNumberGenerator = FeelDice.seeded(0xC0E1)
	var again: RandomNumberGenerator = FeelDice.seeded(0xC0E1)
	var other: RandomNumberGenerator = FeelDice.seeded(0xA1E5)
	var rolls: Array[float] = []
	var rolls_again: Array[float] = []
	var rolls_other: Array[float] = []
	for i in 8:
		rolls.append(first.randf())
		rolls_again.append(again.randf())
		rolls_other.append(other.randf())
	check_equal(rolls_again, rolls, "the same seed, the same rolls")
	check(rolls_other != rolls, "another seed, other rolls")


## Each seeded part of Feel has a seed of its own (no two roll in step), and the debris no longer
## draws a random seed when it enters the tree.
func test_each_part_has_its_own_seed() -> void:
	var seeds: Array[int] = []
	for script in SEEDED:
		var value: Variant = script.get_script_constant_map().get("DICE_SEED")
		check(value is int, "%s has a DICE_SEED" % script.resource_path)
		if value is int:
			check(not seeds.has(value), "%s's seed is its own" % script.resource_path)
			seeds.append(value)
	var debris: Script = SEEDED[3]
	var remnants: Node = own(debris.new()) as Node
	root.add_child(remnants)
	var dice: RandomNumberGenerator = remnants.get(&"_rng")
	check_equal(dice.seed, int(debris.get_script_constant_map()["DICE_SEED"]), "the debris keeps its seed in the tree")
