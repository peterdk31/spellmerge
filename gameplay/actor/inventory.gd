class_name Inventory
extends ActorComponent
## The inventory (items I3, docs/milestones/items.md, "The model"): the things an actor holds, in
## bags, and which of its staffs is on which hand. A component of the actor kit, never stepped; the
## wizard has one (`content/wizard/base/wizard.tscn`). What a kind is and which bag holds it is
## `ItemKinds`' (core/items); nothing here names a kind to decide something.
##
## - **Bags:** one per `ItemKinds.BAGS` entry, each a list of `ItemStack`s and a capacity in copies
##   (`capacity_of`; UNLIMITED for none; `set_capacity`), taken at its start from the run's rules
##   (`SessionRules.bag_capacity`, items I4; with no run, UNLIMITED). A kind that stacks keeps one
##   stack per id with its count (`count_of`); every other item is a stack of its own. `add` puts a
##   stack in its kind's bag, refused when that bag has no room (`has_room`); `take` takes copies
##   out. `copies(bag)` is how full it is.
## - **Staffs and hands:** every staff it owns has a number, stable while it owns it (`numbers`, in
##   the builder's order: the hands' by button, then the staff bag's). A hand (one per button, 0 RB,
##   1 RT, 2 LB, 3 LT) holds one staff or none (`hands`, `hand_of`); a staff on a hand is out of the
##   staff bag. **The caster knows only the staffs on hands:** the inventory owns them and hands the
##   caster each hand's cards (`Caster.set_staff`); a staff in the bag is compiled only for the
##   builder's view (`plan_of`), never installed. While a staff is on a hand its pool is the
##   Caster's; off a hand it keeps its mana in its stack (owner, 2026-11-13: it regains none).
## - **The start:** at `setup` it takes the staffs the body was made with as its own (the Caster's
##   hands, as `PlayerController.seat_wizard` or the scene set them: `Caster.holds`, `staff_of`,
##   `start_cards`), each numbered by the button it starts on, so the first staffs' numbers are
##   their buttons; later ones count on from HANDS. The card bag is what `give_cards` gave before
##   then (`cards_given`; the player fills one from the registry otherwise).
## - **The player loadout** (items I4, core/sim/player_loadout.gd): `loadout()` is everything it
##   holds as a run's start takes it along (its counted bags, every staff with its number and cards,
##   its hands), and `take_loadout(loadout, registry)`, before the actor is ready, makes it hold
##   exactly that in place of the start above (then `hand_staffs` and `hand_cards` are what its
##   Caster is made with). A staff's mana is not in a loadout: every pool starts full.
## - **Counted cards** (owner, 2026-11-13): `set_cards(number, cards)` (and `set_card`, one slot)
##   is the builder's change to a staff's cards. A card put in takes one copy from the card bag, a
##   card taken out gives it back; the change is refused, and nothing changes, when a card has no
##   copy left (NO_CARD), the staff is not owned (NO_STAFF), the slot does not exist (NO_SLOT) or the
##   cards given back do not fit the card bag (BAG_FULL; items I6 drops them at the feet instead).
##   The answer is a `Refusal`; the words are the caller's.
##
## Signals (local, for the actor's controller, which turns them into the seat's events):
## `bag_changed(bag)`, `staff_changed(number)` (its cards, or it came or went) and `hands_changed`.

## Why a change was refused (NONE: it was made).
enum Refusal { NONE, NO_STAFF, NO_SLOT, NO_CARD, BAG_FULL }

## A bag with no limit.
const UNLIMITED: int = -1
## No staff (a hand that holds none, a number nobody has).
const NO_STAFF: int = ItemStack.NO_NUMBER
## How many hands: one per staff button.
const HANDS: int = Caster.MAX_STAFFS
## How many of each card the dev bag holds (the sandbox's and the hub's; owner, 2026-11-13).
const DEV_COPIES: int = 20

## The contents of bag `bag` changed (`stacks_in`, `count_of`, `copies`).
signal bag_changed(bag: StringName)
## The staff `number` changed: its cards, or it came or went (`staff` is null once it went).
signal staff_changed(number: int)
## Which staff is on which hand changed (`hands`).
signal hands_changed()

## By bag (each of `ItemKinds.BAGS`): its stacks, in the order they came.
var _bags: Dictionary = {}
## By bag: its capacity in copies (UNLIMITED: none).
var _capacity: Dictionary = {}
## By hand (button): the staff on it, or null.
var _hands: Array[ItemStack] = []
## The number the next staff it is given gets.
var _next_number: int = HANDS
## True once the card bag was given (`give_cards`), so nobody fills it again.
var cards_given: bool = false
## True once its staffs and hands were given (`take_loadout`), so it takes none from the Caster.
var _staffs_given: bool = false
## True once it took the body's start staffs (`setup`).
var _started: bool = false


func _init() -> void:
	for bag: StringName in ItemKinds.BAGS:
		var stacks: Array[ItemStack] = []
		_bags[bag] = stacks
		_capacity[bag] = UNLIMITED
	_hands.resize(HANDS)


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	if _started:
		# Made again from a snapshot: its staffs are as they were saved.
		return
	_started = true
	if actor.sim != null and actor.sim.rules != null:
		for bag: StringName in ItemKinds.BAGS:
			_capacity[bag] = actor.sim.rules.bag_capacity(bag)
	var caster: Caster = actor.caster
	if caster == null or _staffs_given:
		return
	for at in mini(HANDS, caster.staff_count):
		if not caster.holds(at):
			continue
		var cards: Array[StringName] = []
		if at < caster.start_cards.size() and caster.start_cards[at] is Array:
			for id: Variant in caster.start_cards[at]:
				cards.append(StringName(str(id)))
		var stack := ItemStack.of_staff(caster.staff_of(at), cards)
		stack.number = at
		_hands[at] = stack


# --- The player loadout ------------------------------------------------------------------

## Everything it holds, as a run's start takes it along (items I4): every counted stack by bag,
## every staff (the hands' by button, then the staff bag's) under its number with its cards, and
## the hands. What passes the loadout's limits is left out.
func loadout() -> PlayerLoadout:
	var made := PlayerLoadout.new()
	for stack: ItemStack in _hands:
		if stack != null:
			made.add_staff(stack.number, stack.id, stack.cards)
	for bag: StringName in ItemKinds.BAGS:
		for stack: ItemStack in _stacks(bag):
			if stack.number != NO_STAFF:
				made.add_staff(stack.number, stack.id, stack.cards)
			else:
				made.add_stack(bag, stack.id, stack.count)
	var held: PackedInt32Array = hands()
	for at in held.size():
		if held[at] != NO_STAFF and made.staff_id(held[at]) == &"":
			held[at] = NO_STAFF
	made.set_hands(held)
	return made


## Hold exactly what `loadout` says (before the actor is ready, in place of the start staffs and
## `give_cards`): its counted stacks in their bags, its staffs under their numbers (each the staff
## `registry` has of its id; one it has none of is left out), on the hands the loadout puts them on
## or else in the staff bag, every pool full. A bag it has not, and a hand past HANDS, hold nothing.
func take_loadout(loadout: PlayerLoadout, registry: Node) -> void:
	cards_given = true
	_staffs_given = true
	_hands.fill(null)
	_next_number = HANDS
	for bag: StringName in _bags:
		_stacks(bag).clear()
	for bag: StringName in loadout.bags():
		if not _bags.has(bag):
			continue
		var kind: StringName = ItemKinds.kind_in(bag)
		if kind == ItemKinds.STAFF:
			# A staff is never counted: the loadout's staffs are below.
			continue
		var ids: Array[StringName] = loadout.stack_ids(bag)
		var counts: PackedInt32Array = loadout.stack_counts(bag)
		for at in ids.size():
			var stack := ItemStack.new()
			stack.kind = kind
			stack.id = ids[at]
			stack.count = counts[at]
			_put(stack)
	for number: int in loadout.staff_numbers():
		var base: StaffBase = staff_content(registry, loadout.staff_id(number))
		if base == null:
			continue
		var stack := ItemStack.of_staff(base, loadout.staff_cards(number))
		stack.number = number
		_next_number = maxi(_next_number, number + 1)
		var hand: int = loadout.hand_of(number)
		if hand >= 0 and hand < HANDS:
			_hands[hand] = stack
		else:
			_stacks(ItemKinds.bag_of(ItemKinds.STAFF)).append(stack)


## The staff `registry` has of the id `id` in the staff kind's content folders, or null.
static func staff_content(registry: Node, id: StringName) -> StaffBase:
	if registry == null or id == &"":
		return null
	for folder: StringName in ItemKinds.content_of(ItemKinds.STAFF):
		var found: Resource = registry.call(&"get_resource", folder, id) as Resource
		if ItemKinds.is_content(ItemKinds.STAFF, found):
			return found as StaffBase
	return null


## By hand (button): the staff on it, or null for an empty hand: what its Caster is made with
## after `take_loadout` (`Caster.staffs`).
func hand_staffs() -> Array[StaffBase]:
	var out: Array[StaffBase] = []
	for stack: ItemStack in _hands:
		out.append(stack.staff if stack != null else null)
	return out


## By hand (button): the cards of the staff on it by slot (none for an empty hand), beside
## `hand_staffs` (`Caster.start_cards`).
func hand_cards() -> Array:
	var out: Array = []
	for stack: ItemStack in _hands:
		var cards: Array[StringName] = []
		if stack != null:
			cards.assign(stack.cards)
		out.append(cards)
	return out


# --- Bags -------------------------------------------------------------------------------

## The dev bag (the sandbox's and the hub's, and a wizard's given none): DEV_COPIES of every card
## `registry` finds in the card kind's content folders, card id to copies, in the registry's order.
static func dev_cards(registry: Node) -> Dictionary:
	var out: Dictionary = {}
	if registry == null:
		return out
	for folder: StringName in ItemKinds.content_of(ItemKinds.CARD):
		for id: StringName in registry.call(&"get_ids", folder):
			if ItemKinds.is_content(ItemKinds.CARD, registry.call(&"get_resource", folder, id) as Resource):
				out[id] = DEV_COPIES
	return out


## Give the card bag `counts` (card id to copies; before the actor is ready, or to start it over):
## what it holds is exactly that, in the order given.
func give_cards(counts: Dictionary) -> void:
	cards_given = true
	var bag: StringName = ItemKinds.bag_of(ItemKinds.CARD)
	var stacks: Array[ItemStack] = _bags[bag]
	stacks.clear()
	for id: Variant in counts:
		var copies: int = int(counts[id])
		if copies > 0:
			stacks.append(ItemStack.card(StringName(str(id)), copies))
	bag_changed.emit(bag)


## The capacity of `bag` in copies (UNLIMITED: none).
func capacity_of(bag: StringName) -> int:
	return int(_capacity.get(bag, UNLIMITED))


## Set the capacity of `bag` (UNLIMITED: none). What it holds already stays.
func set_capacity(bag: StringName, copies: int) -> void:
	if _capacity.has(bag):
		_capacity[bag] = maxi(copies, UNLIMITED)
		bag_changed.emit(bag)


## How many copies `bag` holds (a stack of a kind that does not stack is one).
func copies(bag: StringName) -> int:
	var total: int = 0
	for stack: ItemStack in _stacks(bag):
		total += stack.count
	return total


## How many copies of `id` `bag` holds.
func count_of(bag: StringName, id: StringName) -> int:
	var total: int = 0
	for stack: ItemStack in _stacks(bag):
		if stack.id == id:
			total += stack.count
	return total


## The stacks of `bag`, as copies, in the order they came.
func stacks_in(bag: StringName) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for stack: ItemStack in _stacks(bag):
		out.append(stack.copy())
	return out


## True when `stack`'s bag has room for all of it.
func has_room(stack: ItemStack) -> bool:
	if stack == null or not ItemKinds.has(stack.kind) or stack.count <= 0:
		return false
	return _fits(ItemKinds.bag_of(stack.kind), stack.count)


## Put `stack` (a copy of it) in its kind's bag: a kind that stacks joins its id's stack, a staff
## gets a number. Returns false, and nothing changes, when the bag has no room (`has_room`).
func add(stack: ItemStack) -> bool:
	if not has_room(stack):
		return false
	var numbered: PackedInt32Array = _put(stack)
	bag_changed.emit(ItemKinds.bag_of(stack.kind))
	for number in numbered:
		staff_changed.emit(number)
	return true


## Take `count` copies of `id` out of `bag` (a stack left empty goes; of a kind that does not
## stack, the first `count` stacks of that id: a staff taken is said gone, `staff_changed`).
## Returns false, and nothing changes, when it holds fewer.
func take(bag: StringName, id: StringName, count: int = 1) -> bool:
	if count <= 0 or count_of(bag, id) < count:
		return false
	var gone: PackedInt32Array = PackedInt32Array()
	if ItemKinds.stacks(ItemKinds.kind_in(bag)):
		_change_count(bag, id, -count)
	else:
		var stacks: Array[ItemStack] = _bags[bag]
		var left: int = count
		var at: int = 0
		while left > 0 and at < stacks.size():
			if stacks[at].id == id:
				if stacks[at].number != NO_STAFF:
					gone.append(stacks[at].number)
				left -= stacks[at].count
				stacks.remove_at(at)
			else:
				at += 1
	bag_changed.emit(bag)
	for number in gone:
		staff_changed.emit(number)
	return true


# --- Staffs and hands -------------------------------------------------------------------

## Every staff number it owns: the hands' by button, then the staff bag's in the order they came.
func numbers() -> PackedInt32Array:
	var out := PackedInt32Array()
	for stack: ItemStack in _hands:
		if stack != null:
			out.append(stack.number)
	for stack: ItemStack in _stacks(ItemKinds.bag_of(ItemKinds.STAFF)):
		out.append(stack.number)
	return out


## By hand (button): the number of the staff on it, NO_STAFF for none.
func hands() -> PackedInt32Array:
	var out := PackedInt32Array()
	for stack: ItemStack in _hands:
		out.append(stack.number if stack != null else NO_STAFF)
	return out


## The hand (button) staff `number` is on, or -1 (in the bag, or not owned).
func hand_of(number: int) -> int:
	for at in _hands.size():
		if _hands[at] != null and _hands[at].number == number:
			return at
	return -1


## A copy of staff `number`'s stack, or null when it owns none of that number.
func staff(number: int) -> ItemStack:
	var found: ItemStack = _staff(number)
	return found.copy() if found != null else null


## The cards of staff `number` by slot (a copy; empty for a staff it does not own).
func cards_of(number: int) -> Array[StringName]:
	var found: ItemStack = _staff(number)
	var out: Array[StringName] = []
	if found != null:
		out.assign(found.cards)
	return out


## The plain view of staff `number` for a builder (`Spells.staff_view`, as `Caster.plan_of`); empty
## for a staff it does not own, or without Spells.
func plan_of(number: int) -> Dictionary:
	var found: ItemStack = _staff(number)
	if found == null or found.staff == null or actor == null or actor.spells == null:
		return {}
	return actor.spells.staff_view(found.cards, found.staff)


## Put `card_id` in slot `slot` of staff `number` (`&""` empties it), counted (see the class doc).
func set_card(number: int, slot: int, card_id: StringName) -> Refusal:
	var found: ItemStack = _staff(number)
	if found == null:
		return Refusal.NO_STAFF
	if slot < 0 or slot >= found.slots():
		return Refusal.NO_SLOT
	var row: Array[StringName] = found.cards.duplicate()
	row[slot] = card_id
	return set_cards(number, row)


## Make the cards of staff `number` `cards` by slot (fewer than its slots empties the rest),
## counted: refused, and nothing changes, as the class doc says.
func set_cards(number: int, cards: Array[StringName]) -> Refusal:
	var found: ItemStack = _staff(number)
	if found == null:
		return Refusal.NO_STAFF
	if cards.size() > found.slots():
		return Refusal.NO_SLOT
	var row: Array[StringName] = found.fit(cards)
	var bag: StringName = ItemKinds.bag_of(ItemKinds.CARD)
	# What each card id changes by in the bag: + given back, - taken.
	var change: Dictionary = {}
	for id: StringName in found.cards:
		if id != &"":
			change[id] = int(change.get(id, 0)) + 1
	for id: StringName in row:
		if id != &"":
			change[id] = int(change.get(id, 0)) - 1
	var net: int = 0
	for id: StringName in change:
		var by: int = int(change[id])
		if by < 0 and count_of(bag, id) < -by:
			return Refusal.NO_CARD
		net += by
	if net > 0 and not _fits(bag, net):
		return Refusal.BAG_FULL
	var hand: int = hand_of(number)
	var caster: Caster = actor.caster if actor != null else null
	if hand >= 0 and caster != null and not caster.holds(hand):
		# The Caster lost the hand behind the inventory's back (`Caster.replace_staffs`): refused.
		return Refusal.NO_STAFF
	var counted: bool = false
	for id: StringName in change:
		if int(change[id]) != 0:
			_change_count(bag, id, int(change[id]))
			counted = true
	found.cards = row
	if hand >= 0 and caster != null:
		caster.set_staff(hand, row)
	if counted:
		bag_changed.emit(bag)
	staff_changed.emit(number)
	return Refusal.NONE


# --- Inside -----------------------------------------------------------------------------

## Put `stack` (a copy of it) in its kind's bag, whatever room there is, and tell nobody: a kind
## that stacks joins its id's stack, any other is a stack a copy, a staff each with a new number.
## Returns the numbers given.
func _put(stack: ItemStack) -> PackedInt32Array:
	var numbered := PackedInt32Array()
	var stacks: Array[ItemStack] = _bags[ItemKinds.bag_of(stack.kind)]
	if ItemKinds.stacks(stack.kind):
		for held: ItemStack in stacks:
			if held.id == stack.id:
				held.count += stack.count
				return numbered
		stacks.append(stack.copy())
		return numbered
	for _copy in stack.count:
		var made: ItemStack = stack.copy()
		made.count = 1
		if made.kind == ItemKinds.STAFF:
			made.number = _next_number
			_next_number += 1
			made.cards = made.fit(made.cards)
			numbered.append(made.number)
		stacks.append(made)
	return numbered


func _stacks(bag: StringName) -> Array[ItemStack]:
	if _bags.has(bag):
		return _bags[bag]
	var none: Array[ItemStack] = []
	return none


## The stack of staff `number`, on a hand or in the bag (the inventory's own), or null.
func _staff(number: int) -> ItemStack:
	if number == NO_STAFF:
		return null
	for stack: ItemStack in _hands:
		if stack != null and stack.number == number:
			return stack
	for stack: ItemStack in _stacks(ItemKinds.bag_of(ItemKinds.STAFF)):
		if stack.number == number:
			return stack
	return null


## True when `bag` has room for `more` copies.
func _fits(bag: StringName, more: int) -> bool:
	var most: int = capacity_of(bag)
	return most == UNLIMITED or copies(bag) + more <= most


## Change the copies of `id` in `bag` (a kind that stacks) by `by`: a stack is made for one it had
## none of, and goes when none are left. The caller has checked there are enough.
func _change_count(bag: StringName, id: StringName, by: int) -> void:
	var stacks: Array[ItemStack] = _bags[bag]
	for at in stacks.size():
		if stacks[at].id == id:
			stacks[at].count += by
			if stacks[at].count <= 0:
				stacks.remove_at(at)
			return
	if by > 0:
		var made := ItemStack.new()
		made.kind = ItemKinds.kind_in(bag)
		made.id = id
		made.count = by
		stacks.append(made)
