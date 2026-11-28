extends "res://tests/support/suite.gd"
## Feel's view dice are seeded (`FeelDice`): what the motes, the debris and the spectacle draw by chance
## comes out the same every time a run is played, so two runs' screenshots are the same picture. A
## new generator starts at a random seed; each of these starts at its script's `DICE_SEED` and its
## count (`FeelDice.made`), so several of one kind at once never roll in step.
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const SEEDED: Array[Script] = [
	preload("res://gameplay/feel/air_motes.gd"),
	preload("res://gameplay/feel/cover_motes.gd"),
	preload("res://gameplay/feel/source_motes.gd"),
	preload("res://gameplay/feel/remnants.gd"),
	preload("res://gameplay/feel/spectacle.gd"),
]


func _rolls(dice: RandomNumberGenerator) -> Array[float]:
	var out: Array[float] = []
	for i in 8:
		out.append(dice.randf())
	return out


func test_a_seeded_generator_rolls_the_same_every_time() -> void:
	check_equal(_rolls(FeelDice.seeded(0xC0E1)), _rolls(FeelDice.seeded(0xC0E1)), "the same seed, the same rolls")
	check(_rolls(FeelDice.seeded(0xA1E5)) != _rolls(FeelDice.seeded(0xC0E1)), "another seed, other rolls")


## Two of a kind made one after the other roll apart, each from its seed and its count.
func test_two_of_a_kind_never_roll_in_step() -> void:
	var first: RandomNumberGenerator = FeelDice.made(0x7E57)
	var second: RandomNumberGenerator = FeelDice.made(0x7E57)
	check(_rolls(first) != _rolls(second), "two made with one seed roll apart")
	var count: int = -1
	for k in 1000:
		if first.seed == hash(Vector2i(0x7E57, k)):
			count = k
			break
	check(count >= 0, "the first is the seed with its count")
	check_equal(second.seed, hash(Vector2i(0x7E57, count + 1)), "the next, the seed with the count after")


## Each seeded part of Feel has a seed of its own and takes its dice from `FeelDice.made` (its seed
## and a count): a new one's dice are seeded so, never at random (the debris drew a random seed when
## it entered the tree).
func test_each_part_takes_seeded_dice_of_its_own() -> void:
	var seeds: Array[int] = []
	for script in SEEDED:
		var value: Variant = script.get_script_constant_map().get("DICE_SEED")
		check(value is int, "%s has a DICE_SEED" % script.resource_path)
		if value is int:
			check(not seeds.has(value), "%s's seed is its own" % script.resource_path)
			seeds.append(value)
	var table: RefCounted = RampTableScript.new()
	var made: Array[Object] = [SEEDED[0].new(table), SEEDED[1].new(), SEEDED[2].new(table), own(SEEDED[3].new()), own(SEEDED[4].new())]
	# The debris and the spectacle in the tree, where the debris used to draw a random seed.
	root.add_child(made[3] as Node)
	root.add_child(made[4] as Node)
	for i in made.size():
		var dice: RandomNumberGenerator = made[i].get(&"_rng")
		var seed_value: int = int(SEEDED[i].get_script_constant_map()["DICE_SEED"])
		var found: bool = false
		for k in 1000:
			if dice != null and dice.seed == hash(Vector2i(seed_value, k)):
				found = true
				break
		check(found, "%s's dice are its seed and a count" % SEEDED[i].resource_path)
