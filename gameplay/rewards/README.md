# Rewards

## Purpose

Per-player rolls from loot tables, unspent rewards, shops, fountains, coins and run stats ([docs/milestones/connected-biomes.md](../../docs/milestones/connected-biomes.md)). Tables are content data (`content/rewards/`, `RewardTable`, through the registry). Each player rolls their own rewards; nobody waits for anyone.

## What it does

- **A roll per player:** on `room_rewards_due` every seat with a wizard gets its own `RewardOffer`, rolled by `RewardRoll` (by weight, never one choice twice), `reward_choices` choices (run stat). Chance purpose `reward`, keyed by seat and counted, so one seat's roll never shifts another's.
- **A reward room's type** (`RewardType`, core/base, from `room_rewards_due`'s `type`): each choice rolls the type's narrowest level first, widening to the whole table; each level under `RewardRoll.LEVEL_PURPOSES`. Cards come from `RewardCards` (core/base).
- **Here or not:** a present player's offer lies as an item at its seat's spot (`RewardOffer.lying`, `at`; `reward_item_changed`); the seat's driven standing body within `REWARD_REACH` is told (`reward_near_changed`). An absent player's offer waits, lying nowhere. An unopened lying offer is lost with its biome (a new world or run start clears the floor); a waiting one waits all run.
- **Pick:** `reward_pick_requested(player, offer, choice)` (command) puts the choice in the seat's wizard's inventory (`reward_taken`); a full bag keeps it unspent (`reward_refused`).
- **Reroll:** `reward_reroll_requested(player, offer)` (command) spends one `RerollBase.REWARD` from the currency bag and re-rolls every choice from `RewardOffer.table` / `type_row` under purpose `reward_reroll` (`reward_rerolled`), else `reward_reroll_refused`. Each wizard starts a run with `start_reward_rerolls` and `start_coins`, once a run (`_funded`, also on rejoin).
- **A reward is an item:** a `RewardEntry` (item kind of `ItemKinds.RULES`, content id, count). Nothing here knows what an item does or how it looks (`ItemLooks`, core/items).
- **Run stats** (`RunStats`, core/base): the run's changes come with `run_stats_ruled`; `stat_of(seat, stat)` adds the relics' `RelicBase.stat_changes`. Other areas hear `run_stats_ruled` and use `RunStats` themselves. Told to the view by `run_stats_told`.
- **A shop:** on `special_room_opened` the shelf is rolled once (purpose `shop`, keyed by room; one item a spot, each at its line's `price`). `shelf_near_changed` within `SHELF_REACH`; `shelf_buy_requested(player, item)` (command; the first seat in a tick takes it): the buyer is the standing body the seat drives (its coins, reach, room); price times `price_scale`; `shelf_changed` or `shelf_refused`. Walking over an item buys nothing. **Reroll sign** (`SHELF_SIGN`, `sign_price(uses)`, purposes `shop_sign`, `shop_sign_fill`; `signs()`).
- **A fountain:** on `special_room_opened` its pool fills with `POOL_HEALTH` × highest `fountain_pool`; hurt standing wizards in it draw `DRAW_RATE` per second via `health_gift_requested` (`fountain_changed`).
- **Coins:** one stack in the wizard's currency bag (`CoinBase.ID`; `coins_of(seat)`; `spend(seat, amount)` from one's own only). A foe carries its coins in its own bag (`EnemyBase.coins`, `coins_most`). On `enemy_died`, by `coin_drop_chance` (purpose `coin_drop`, `_drops`) its carried coins (`Inventory.carried_kept`) land round it; the first standing wizard within `COIN_REACH` takes one and every player's stack gains one. A boss's always go to every player's stack; an add's never drop. Coins it took later drop as plain items (`Inventory.drop_taken`, `item_drop_requested`): no coin is made or lost. Keys it holds drop all or none by `EnemyBase.key_drop_chance` (purpose `key_drop`, `_key_drops`). A rejoining seat keeps its inventory and gets no second `start_coins`.
- **Rooms with rewards left:** `rooms_rewards_left(left, again)`, read from the offers (`rewards_left()`), kept nowhere; `again` after a restore.
- **Pickups said:** `item_picked_up` (coin, shelf item, reward: `EventsScript.PICKUP_REWARD`).
- **State:** offers, rewards in reach, signs, shelves, roll/reroll/drop counters, funded seats, coins on the floor, pools, the run's changes: all hashed and snapshotted. `rebuild_derived` re-tells everything after a restore. Coins and potions are the wizard's inventory's.
- **Performance:** feet are found once a tick for all lying coins (`_find_takers`), not per coin.

## Contract

- **Public entry script:** `gameplay/rewards/rewards.gd`. Nothing else in the folder is public.
- **Dependency direction:** `core` ← `gameplay` ← `content`. Use `core/` and the registry only.
- **Events** (defined in `core/events/events.gd`; matches [gameplay/README.md](../README.md)):
  - Sends: `rooms_rewards_left`, `reward_item_changed`, `reward_near_changed`, `item_picked_up`, `reward_rolled`, `reward_taken`, `reward_rerolled`, `reward_reroll_refused`, `rewards_waiting_changed`, `coin_changed`, `shelf_changed`, `shelf_near_changed`, `shelf_refused`, `fountain_changed`, `run_stats_told`, `health_gift_requested`, `reward_refused`.
  - Listens to: `room_rewards_due`, `special_room_opened`, `room_entered`, `enemy_died`, `run_stats_ruled`, and the HUD's commands `reward_pick_requested`, `reward_reroll_requested`, `shelf_buy_requested`.
- Every roll uses the run's chance under its own purpose, keyed and counted; never shift another roll.
- Areas never call each other directly; they talk through events. Shared rules: [gameplay/README.md](../README.md).

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs.

## Example to copy

`rewards.gd` (state, events, its step `Tick.STEPS` "Rewards"), `reward_offer.gd` (a row of state), `reward_roll.gd` (the roll policy). A new kind of reward is a new item kind (`ItemKinds.RULES` row and its content, core/items); a new table is a file in `content/rewards/`; nothing here changes. Steps and test layout: [gameplay/README.md](../README.md).

## Tests

`tests/gameplay/rewards/test_rewards.gd`.

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

- Does each player get an independent roll? Are unspent rewards kept and never lost? Does nobody wait for another's choice?
- Does it keep to the dependency direction, without calling another area directly?

History and reasons: [docs/history/gameplay-rewards-README.md](../../docs/history/gameplay-rewards-README.md).
