# content/coins: the coin

Coins are a stacked inventory item (the owner, 2026-11-19: "Coins are stacked inventory items. The HUD shows how many are in the inventory. When they are spent in a shop they are removed from the inventory"). Its stack lies in the currency bag, beside the keys (content/keys). There is one coin, `coin/coin.tres` (a `CoinBase`, `core/base/coin_base.gd`; its id `CoinBase.ID`), found by the registry under `coins` (`ItemKinds.COIN`'s row). The Rewards area (gameplay/rewards) adds to a player's stack (a coin taken from the floor, to every player; a reward of coins; a run's `start_coins`) and a shop's buy takes from it.

## Contract

- `coin/` holds `coin.tres` (`id`, `display_name`, `description`, `icon`: an `ItemContent`), its `icon.svg` (16 by 16) and its `assets.json`. `problems()` must be empty.
- A reward table names coins by their kind and id (`kind = &"coin"`, `id = &"coin"`, `count` of them; content/rewards).

## Allowed files

`.tres`, `.svg` or `.png` icons, `assets.json`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file.

## Validate

```sh
tools/check.sh
tools/ptest.sh 8 'test_potions|test_item_kinds|test_reward_tables'
```
