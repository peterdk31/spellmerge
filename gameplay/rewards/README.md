# Rewards

## Purpose

Per-player rolls from loot tables, unspent rewards and shops.

Built by connected biomes CB10 ([docs/milestones/connected-biomes.md](../../docs/milestones/connected-biomes.md), decisions 16 to 18 and 26); its shops and fountains by CB11 (decisions 19 and 20).

Reward tables are content data read through the registry (`content/rewards/`, `RewardTable`), so new ones are added without touching this code. Each player rolls their own rewards.

## What it does

- **A roll per player** (DESIGN rule 3): on `room_rewards_due` (Flow's, a cleared room whose kind names a reward table: a fight's `clear`, the boss's `boss`, a reward room's `reward`, ...; however its foes left it, the owner's answer of 2026-11-19) every seat with a wizard gets its own offer (`RewardOffer`), its choices rolled from that table by `RewardRoll` (by weight, never one twice in an offer; the run's chance, purpose `reward`, keyed by the seat and counted by its rolls, so one seat's roll never shifts another's), as many as the player's `reward_choices` run stat (2: "pick 1 of 2", decision 17).
- **Here or not** (rule 4): `here` when the seat's wizard is in the cleared room (`Actor.room`); the HUD opens a present player's menu at once, and a player who was not there finds the offer waiting, an unspent count on their corner panel. Offers wait all run until picked, oldest first; nobody waits for anyone.
- **A pick** (`reward_pick_requested(player, offer, choice)`, a command): the seat's own offer of that number gives the choice to the seat's wizard (`RewardEntry.CARD`: copies into its card bag; `COINS`: its own wallet; `HEAL` and `MAX_HEALTH`: through Combat, `health_gift_requested`) and goes (`reward_taken`). A full bag, or a heal while down, keeps it unspent. What a reward may be before relics exist (the owner, 2026-11-19): a card, coins, healing or a little more most health; a card upgrade waits for card levels.
- **Run stats** (`RunStats`, core/base): the run's own changes arrive with `run_stats_ruled` (from `run`); `stat_of(seat, stat)` is those, then the relics in the seat's wizard's relics bag (`RelicBase.stat_changes`). Another area that reads a run stat hears `run_stats_ruled` itself and works the stat out with `RunStats` (areas never call each other); `spend` is for this area's own shop (CB11).
- **A shop** (CB11, decision 19): on `special_room_opened` of a shop (Flow's, as it is first entered: its shelf table and spots) its shelf is rolled once (`RewardRoll` under the purpose `shop`, keyed by its room: one item a spot, never one twice, each at its line's `price`). The first standing wizard (seat order) whose own feet come within `SHELF_REACH` of an item, with its price (times that player's `price_scale`) in their own wallet and room for it, buys it: given as a reward's choice is, paid from their wallet, gone from the shelf for everyone (`shelf_changed`). The shelf keeps what is left all run.
- **A fountain** (CB11, decision 20): on `special_room_opened` of a fountain its pool fills with `POOL_HEALTH` times the highest `fountain_pool` of the players then; every hurt standing wizard whose own feet are in it draws `DRAW_RATE` health a second (through Combat, `health_gift_requested`) until whole or the pool is dry (`fountain_changed`).
- **Coins** (decision 18): a foe's death (`enemy_died`) lays its `EnemyBase.coins` round where it fell; the first standing wizard (seat order) whose feet come within `COIN_REACH` takes one, and every player's wallet gains one. Each wallet starts a run with the player's `start_coins`; `spend(seat, amount)` takes from one's own only (CB11's shop). A new world (`room_entered` FIRST_ROOM) and a run's start clear the floor.
- **State:** the offers, the rolls counted, the wallets, the coins, the shelves, the pools and the run's changes are state (hashed, snapshotted); `rebuild_derived` says every coin, shelf item, pool, wallet and waiting list again after a restore.

## Contract

- **Public entry script:** `gameplay/rewards/rewards.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `reward_rolled`, `reward_taken`, `rewards_waiting_changed`, `coin_changed`, `wallet_changed`, `shelf_changed`, `fountain_changed`, `health_gift_requested` (to combat), `reward_refused`.
  - Listens to: `room_rewards_due`, `special_room_opened`, `room_entered`, `enemy_died`, `run_stats_ruled` and `reward_pick_requested` (from the HUD, a command; `reward_taken` is the announced result).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`rewards.gd` (the area: its state, its events, its step in `Tick.STEPS` "Rewards"), `reward_offer.gd` (a row of state), `reward_roll.gd` (the policy, apart, so it changes alone). A new kind of reward is a row of `RewardEntry.KINDS`, its line of `RewardEntry.DESCRIPTIONS` (what it does, for the reward menu's card: a choice's view carries it as `description`, a card's being its builder line), its glyph in the HUD's `hud/menus/reward/reward_card.gd` (`GLYPHS`, a test asks for it) and its branch in `_give`; a new table is a file in `content/rewards/`. Tests: `tests/gameplay/rewards/test_rewards.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here changes how rewards are rolled, kept or bought for each player, reads tables from data, and never makes one player wait for another's choice. Besides the general review:

- Does each player get an independent roll? Are unspent rewards kept and never lost?
- Does it keep to the dependency direction, without calling another area directly?
