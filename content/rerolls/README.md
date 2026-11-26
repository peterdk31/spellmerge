# content/rerolls: the reward reroll

A currency (the owner, 2026-11-19: "Create new currencies called 'room reroll' and 'reward reroll'. [...] Players start with 1 of each for now. They are used by pressing X to reroll."; then, the same day: "I only want the player to be able to reroll rewards, not rooms", so the room reroll is gone). It is a stacked inventory item in the currency bag beside the coins and the keys (`ItemKinds.REROLL`, a `RerollBase`, `core/base/reroll_base.gd`), each player's own and droppable one at a time (X in the inventory), taken with A into the taker's own bag, as a key is.

- `reward_reroll/` (`RerollBase.REWARD`): X in the reward card picker spends one and rerolls that player's offer (gameplay/rewards).

Every player starts a run with `start_reward_rerolls` of them (run stats, `RunStats`: 1 for now, so a relic can change it).

## Contract

- The folder holds its `.tres` (`id`, `display_name`, `description`, `icon`: an `ItemContent`), its `icon@2x.svg` (16 by 16 world units, 32 by 32 art pixels at 2x detail; drawn by `tools/pickup_art.py`, docs/STYLE.md "The picture and the art's detail") and its `icon.svg` (16 by 16, `icon_small` for the HUD's small cells, from the same parts) and its `assets.json`. `problems()` must be empty. The id is `RerollBase`'s; a new kind of reroll is engine work (its id in `ItemKinds.RULES`' `reroll` row and what spends it).

## Allowed files

`.tres`, `.svg` or `.png` icons, `assets.json`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file.

## Validate

```sh
tools/check.sh
tools/ptest.sh 8 'test_item_kinds|test_rerolls'
```
