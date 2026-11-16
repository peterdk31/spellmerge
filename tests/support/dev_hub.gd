extends RefCounted
## The hub with every seat's wizard holding the `dev` staff (content/wizard/staffs/dev: 20 slots, no
## delay, a million mana) on all four hands, each built as asked, and the hub's bag of every card,
## for the screenshots that show built staffs (crypt rework CR-S, docs/DECISIONS.md 2026-11-16:
## before, a room of its own gave its wizards these). Started the way a party comes back to the hub
## with what it holds (`Flow.start_run` with a `PartyLoadout`, items I4), so nothing in the game
## knows of it.
##
##     if not DevHub.start(flow, root.get_node("Registry")):
##         fail("the hub did not start")
##
## A seat that joins after holds the hub's own staffs, as any joiner.

## The staff on every hand, by id under `wizard`.
const DEV_STAFF: StringName = &"dev"
## The premade builds (content/items/staffs/) on the third and fourth hands when no cards are given:
## the most shots, and a decoy turret.
const SHOWCASE_ITEMS: Array[StringName] = [&"frostfire_cascade", &"patient_sentry"]


## The builds by hand when none are given: a dash (A), a fire bolt (X), then SHOWCASE_ITEMS' cards
## (Y and B), read from the registry (an empty hand for one it lacks).
static func default_cards(registry: Node) -> Array:
	var cards: Array = [[&"dash"], [&"fire", &"bolt"]]
	for id: StringName in SHOWCASE_ITEMS:
		var item := registry.call("get_resource", &"items", id) as StaffItem
		cards.append(item.cards.duplicate() if item != null else [])
	return cards


## Every seat (0-3) with the dev staff on each hand, hand `h` holding `cards[h]` (card ids), and
## Inventory.DEV_COPIES of every card in its bag.
static func party(cards: Array, registry: Node) -> PartyLoadout:
	var out := PartyLoadout.new()
	var bag: Dictionary = Inventory.dev_cards(registry)
	for seat in 4:
		var loadout := PlayerLoadout.new()
		for id: StringName in bag:
			loadout.add_stack(&"cards", id, int(bag[id]))
		var hands := PackedInt32Array()
		for hand in 4:
			var built: Array[StringName] = []
			for card: Variant in (cards[hand] as Array if hand < cards.size() else []):
				built.append(StringName(card))
			loadout.add_staff(hand, DEV_STAFF, built)
			hands.append(hand)
		loadout.set_hands(hands)
		out.put(seat, loadout)
	return out


## The hub starts now for the seats joined, each holding `party(cards)` (`default_cards` when empty).
## False when it did not start (Flow is idle again).
static func start(flow: Node, registry: Node, cards: Array = []) -> bool:
	flow.set(&"mode", &"hub")
	var started: bool = bool(flow.call("start_run", 0, party(cards if not cards.is_empty() else default_cards(registry), registry)))
	if not started:
		flow.set(&"mode", &"run")
	return started
