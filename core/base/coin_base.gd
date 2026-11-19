class_name CoinBase
extends ItemContent
## The coin (connected biomes CB10, decision 18; the owner, 2026-11-19: "Coins are stacked inventory
## items"): one stack in the currency bag (`ItemKinds.COIN`), which a shop's buy takes from and the
## corner panel counts. The Rewards area adds to it (a coin taken from the floor, to every player;
## a reward of coins; a run's `start_coins`). One file, `content/coins/coin/coin.tres` (`ID`),
## found by the registry under `coins`.

## The coin's id: the one coin there is.
const ID: StringName = &"coin"
