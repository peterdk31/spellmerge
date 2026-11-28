class_name FeelDice
extends RefCounted
## A view's own dice, seeded: what Feel draws by chance (motes, debris, the spectacle's sparks)
## comes out the same every time a run is played, so two runs' screenshots are the same picture.
## View only: nothing the game plays by (that is `Sim.chance`).

const VIEW_ONLY: bool = true


## A generator seeded with `seed_value`.
static func seeded(seed_value: int) -> RandomNumberGenerator:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value
	return dice
