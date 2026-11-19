class_name RewardCards
extends RefCounted
## The spell cards a reward may give (connected biomes CB10; the reward room's type, the owner's ask
## of 2026-11-19): every card the registry has, in the order given (the registry's, id order), each
## with its kind (`SpellComponent.kind`: carrier, element, modifier, trigger or multicast) and its
## complexity, by the same index. Gathered once where it is asked (the biome generator through
## `RunContent`, the Rewards area at a roll), so both read one list the same way. Plain data; it reads
## no file and no node.

var ids: Array[StringName] = []
var kinds: Array[StringName] = []
var complexities: PackedInt32Array = PackedInt32Array()


## The cards among `found` (what the registry's `get_all` gives for the cards' folder): what is no
## card (`ItemKinds.is_content`) is left out, and so is an id met before.
static func gather(found: Array[Resource]) -> RewardCards:
	var made := RewardCards.new()
	for item: Resource in found:
		if not ItemKinds.is_content(ItemKinds.CARD, item):
			continue
		var id := StringName(str(item.get(&"id")))
		if id == &"" or made.ids.has(id):
			continue
		var card := item as SpellComponent
		made.ids.append(id)
		made.kinds.append(card.kind() if card != null else &"")
		made.complexities.append(int(item.get(&"complexity")))
	return made


func size() -> int:
	return ids.size()


## The kind of card `id` (empty: no such card).
func kind_of(id: StringName) -> StringName:
	var at: int = ids.find(id)
	return kinds[at] if at >= 0 else &""


## True when the table line `entry` (a card line) may give card number `at`: a line naming a card
## gives that one, a line of any card those its `max_complexity` allows.
func line_gives(entry: RewardEntry, at: int) -> bool:
	if entry == null or entry.kind != ItemKinds.CARD:
		return false
	if entry.id != &"":
		return ids[at] == entry.id
	return entry.max_complexity <= 0 or complexities[at] <= entry.max_complexity
