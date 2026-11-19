# content/keys: the key

Keys are a stacked inventory item beside the coins, in the currency bag (the owner, 2026-11-19: "Keys are also just inventory items, right? I think they should go in a currency bag (along with coins). They should not be 'global', but each player picks up keys individually and uses them individually"). There is one key, `key/key.tres` (a `KeyBase`, `core/base/key_base.gd`; its id `KeyBase.ID`), found by the registry under `keys` (`ItemKinds.KEY`'s row). Flow's `LockDoors` (gameplay/flow) puts a key lying on the floor into the bag of the body that reaches it, and a treasure room's door spends one from the bag of the body at it. A key is never dropped.

## Contract

- `key/` holds `key.tres` (`id`, `display_name`, `description`, `icon`: an `ItemContent`), its `icon.svg` (16 by 16) and its `assets.json`. `problems()` must be empty.

## Allowed files

`.tres`, `.svg` or `.png` icons, `assets.json`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file.

## Validate

```sh
tools/check.sh
tools/ptest.sh 8 'test_item_kinds|test_special_rooms'
```
