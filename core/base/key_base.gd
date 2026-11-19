class_name KeyBase
extends ItemContent
## The key (connected biomes CB11, decision 21; the owner, 2026-11-19: "Keys are also just inventory
## items ... in a currency bag (along with coins). They should not be 'global', but each player picks
## up keys individually and uses them individually"): one stack in the currency bag
## (`ItemKinds.KEY`), beside the coins. The body whose feet reach a key lying on the floor takes it
## into its own bag, and a treasure room's door spends one from the bag of the body at it
## (gameplay/flow/lock_doors.gd). Any key opens any key door. One file,
## `content/keys/key/key.tres` (`ID`), found by the registry under `keys`.

## The key's id: the one key there is.
const ID: StringName = &"key"
