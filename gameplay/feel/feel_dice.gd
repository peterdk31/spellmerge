class_name FeelDice
extends RefCounted
## A view's own dice, seeded: what Feel draws by chance (motes, debris, the spectacle's sparks)
## comes out the same every time a run is played, so two runs' screenshots are the same picture.
## View only: nothing the game plays by (that is `Sim.chance`).

const VIEW_ONLY: bool = true

## How many generators each seed has made (`made`): the next takes the count with the seed.
static var _made: Dictionary[int, int] = {}


## A generator seeded with `seed_value`.
static func seeded(seed_value: int) -> RandomNumberGenerator:
	var dice := RandomNumberGenerator.new()
	dice.seed = seed_value
	return dice


## A generator for one more of a kind whose seed is `seed_value` (its script's `DICE_SEED`): each
## one made gets the seed and how many were made before it, so several at once (the spectacle's
## air layers, a room's air) never roll in step, and a run played again makes them in the same order
## with the same seeds.
static func made(seed_value: int) -> RandomNumberGenerator:
	var count: int = _made.get(seed_value, 0)
	_made[seed_value] = count + 1
	return seeded(hash(Vector2i(seed_value, count)))
