# content/rerolls: the room reroll and the reward reroll

Two currencies (the owner, 2026-11-19: "Create new currencies called 'room reroll' and 'reward reroll'. They can be used to reroll rooms or rewards. Players start with 1 of each for now. They are used by pressing X to reroll."). Each is a stacked inventory item in the currency bag beside the coins and the keys (`ItemKinds.REROLL`, a `RerollBase`, `core/base/reroll_base.gd`), each player's own and droppable one at a time (X in the inventory), taken with A into the taker's own bag, as a key is.

- `room_reroll/` (`RerollBase.ROOM`): X at an unvisited room's bridge mouth, where its kind sign shows, spends one and rerolls what lies behind that doorway (gameplay/flow).
- `reward_reroll/` (`RerollBase.REWARD`): X in the reward card picker spends one and rerolls that player's offer (gameplay/rewards).

Every player starts a run with `start_room_rerolls` and `start_reward_rerolls` of them (run stats, `RunStats`: 1 each for now, so a relic can change it).

## Contract

- Each folder holds its `.tres` (`id`, `display_name`, `description`, `icon`: an `ItemContent`), its `icon.svg` (16 by 16) and its `assets.json`. `problems()` must be empty. The ids are `RerollBase`'s; a new kind of reroll is engine work (its id in `ItemKinds.RULES`' `reroll` row and what spends it).

## Allowed files

`.tres`, `.svg` or `.png` icons, `assets.json`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file.

## Validate

```sh
tools/check.sh
tools/ptest.sh 8 'test_item_kinds|test_rerolls'
```
