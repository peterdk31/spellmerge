extends AIBehaviour
## Something worth taking lies near (items I9, docs/milestones/items.md, "I9"): an item of a kind
## its profile takes (`AIProfile.takes`; none, and it never looks) within LOOK of its feet, seen
## through the bus (`AIBrain.look_ground`, never the Items area). It walks to the nearest worth
## taking (`plan_point`) and takes it once it is in reach (`AIBrain.take_item`, the pickup rule's
## reach and room), keyed by its actor, so what it takes is the body's it drives.
##
## - **A staff** that casts something goes on a free hand; the brain plays whatever staffs it
##   holds. With every hand full, it takes the place of the weakest only when its first cast is
##   stronger (`strength`): the weakest goes into the staff bag first, and back on its hand if the
##   take came to nothing. A body with no Caster has no hands, so it leaves staffs.
## - **A card** is tried in each free slot of the staffs on its hands, each staff compiled
##   (`Caster.sense_of_build`, the cache every caster shares), and kept where it does something and
##   the staff's first cast is strongest, never where it is weaker than before; a card that helps
##   nowhere is left. Taken, it goes into the card bag and from there into that slot.
##
## It reads what each build would cast (`CastSense`) and the stacks' ids as they are, never a card.
## Nothing is allocated but the card rows it tries (a decision with a card in sight).

## How far round its feet it looks (pixels).
const LOOK: float = 96.0
## Its want to walk to an item worth taking (above a fight that waits, below one ready to cast).
const WALK: float = 0.6
## Its want once the item is in reach: taking it is one step's work.
const TAKE: float = 0.9
## `picks`: none.
const NONE: int = -1
## The most slots `card_place` counts in a staff (its answer is staff number × SLOTS + slot).
const SLOTS: int = 64


func name() -> String:
	return "pick up"


## `picks[index]` the item's place in the brain's sight (`look_ground`), `memo[index]` the hand (a
## staff) or the staff number × SLOTS + slot (a card) it goes to.
func want(brain: AIBrain) -> float:
	brain.picks[index] = NONE
	brain.memo[index] = -1.0
	var actor: Actor = brain.actor
	if brain.profile.takes.is_empty() or actor.inventory == null or actor.caster == null or actor.is_down():
		return 0.0
	var sight: GroundSight = brain.look_ground(LOOK)
	for at in sight.count:
		var stack: ItemStack = sight.stacks[at]
		if stack == null or not brain.profile.takes.has(stack.kind):
			continue
		var where: int = place_of(actor, stack)
		if where == NONE:
			continue
		brain.picks[index] = at
		brain.memo[index] = float(where)
		return TAKE if sight.in_reach[at] != 0 else WALK
	return 0.0


func act(brain: AIBrain) -> void:
	var at: int = brain.picks[index]
	var sight: GroundSight = brain.look_ground(LOOK) if at >= 0 else null
	if sight == null or at >= sight.count:
		return
	if sight.in_reach[at] == 0:
		brain.plan_move = AIBrain.Move.POINT
		brain.plan_point = sight.places[at]
		return
	var stack: ItemStack = sight.stacks[at]
	var where: int = int(brain.memo[index])
	if ItemKinds.can(stack.kind, ItemKinds.HAND):
		_take_staff(brain, sight.numbers[at], where)
	else:
		_take_card(brain, sight.numbers[at], stack.id, where)


## Where `stack` would go on `actor`, or NONE when it is not worth taking: for a staff the hand
## (`staff_hand`), for a card the staff and slot (`card_place`); nothing for any other kind yet.
static func place_of(actor: Actor, stack: ItemStack) -> int:
	if ItemKinds.can(stack.kind, ItemKinds.HAND):
		return staff_hand(actor, stack)
	if stack.kind == ItemKinds.CARD:
		return card_place(actor, stack.id)
	return NONE


## The hand the staff `stack` would go on: a free one when it casts something, else, every hand
## full, the weakest's when its first cast is stronger; NONE when it is not worth taking.
static func staff_hand(actor: Actor, stack: ItemStack) -> int:
	var caster: Caster = actor.caster
	var gain: float = strength(caster.sense_of_build(stack.staff, stack.cards))
	if gain <= 0.0:
		return NONE
	var free: int = actor.inventory.free_hand()
	if free >= 0:
		return free
	var weakest: int = NONE
	var lowest: float = INF
	for hand in caster.staff_count:
		if not caster.holds(hand):
			continue
		var held: float = strength(caster.sense_of_build(caster.staff_of(hand), caster.cards_of(hand)))
		if held < lowest:
			lowest = held
			weakest = hand
	return weakest if weakest != NONE and gain > lowest else NONE


## Where the card `id` would go, as staff number × SLOTS + slot: the free slot of a staff on a hand
## where it does something and that staff's first cast is strongest (never weaker than before;
## the first such on a tie); NONE for none.
static func card_place(actor: Actor, id: StringName) -> int:
	var caster: Caster = actor.caster
	var hands: PackedInt32Array = actor.inventory.hands()
	var best: int = NONE
	var best_strength: float = -INF
	for hand in caster.staff_count:
		if not caster.holds(hand) or hand >= hands.size() or hands[hand] == Inventory.NO_STAFF:
			continue
		var base: StaffBase = caster.staff_of(hand)
		var cards: Array[StringName] = caster.cards_of(hand)
		var before: float = strength(caster.sense_of_build(base, cards))
		for slot in mini(cards.size(), SLOTS):
			if cards[slot] != &"":
				continue
			cards[slot] = id
			var sense: CastSense = caster.sense_of_build(base, cards, slot)
			cards[slot] = &""
			if sense == null:
				continue
			var after: float = strength(sense)
			if after < before or after <= best_strength:
				continue
			best_strength = after
			best = hands[hand] * SLOTS + slot
	return best


## How strong a cast is, to weigh one build against another: what it may deal (`CastSense.damage`),
## 0 for none.
static func strength(sense: CastSense) -> float:
	return sense.damage if sense != null else 0.0


## Take the staff `item` onto hand `hand`: the staff there first into the staff bag (refused, none
## taken), and back on its hand if the take came to nothing.
static func _take_staff(brain: AIBrain, item: int, hand: int) -> void:
	var inventory: Inventory = brain.actor.inventory
	var there: int = inventory.hands()[hand] if hand >= 0 and hand < Inventory.HANDS else Inventory.NO_STAFF
	if there != Inventory.NO_STAFF and inventory.set_hand(there, Inventory.NO_HAND) != Inventory.Refusal.NONE:
		return
	brain.take_item(item)
	if there != Inventory.NO_STAFF and inventory.hands()[hand] == Inventory.NO_STAFF:
		inventory.set_hand(there, hand)


## Take the card `item` (`id`) into its bag, then into the slot `where` says.
static func _take_card(brain: AIBrain, item: int, id: StringName, where: int) -> void:
	if where < 0:
		return
	var inventory: Inventory = brain.actor.inventory
	var bag: StringName = ItemKinds.bag_of(ItemKinds.CARD)
	var had: int = inventory.count_of(bag, id)
	brain.take_item(item)
	if inventory.count_of(bag, id) > had:
		inventory.set_card(floori(float(where) / float(SLOTS)), where % SLOTS, id)
