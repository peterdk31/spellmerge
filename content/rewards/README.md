# content/rewards: reward tables

A reward table is what a reward offers its choices from (connected biomes CB10, docs/milestones/connected-biomes.md, decisions 16 and 17): one weighted line an item (every reward is an inventory item, the owner's decision of 2026-11-19). One file per table, `<id>.tres`, a `RewardTable` (`core/base/reward_table.gd`) of `RewardEntry` lines (`core/base/reward_entry.gd`); the registry finds it by its `id` under `rewards`. The Rewards area (`gameplay/rewards/`) rolls each player's own choices from it, as many as that player's `reward_choices` run stat (`core/base/run_stats.gd`), never one twice in an offer.

## Contract

- A line names an item: its `kind` is an item kind (a row of `ItemKinds.RULES`) and its `id` the content's: `card` (`count` copies of the card `id`, or with no id any card of `content/spells` of at most `max_complexity`, 0 for any), `potion` (`count` potions of `content/potions`: `small_healing`, `healing`, `large_healing`, `max_health`, `vigor`; kept in the inventory and drunk when the player likes), `coin` (`id = &"coin"`, `count` coins onto the player's own coin stack, content/coins). A relic joins with M3's relic work as an item of its own; a card upgrade waits for card levels. The reward's card shows the item's own icon, name and description.
- `weight` is how likely the line is against the table's others (above 0). `price` (connected biomes CB11): what the line costs on a shop's shelf, in coins, before the buyer's `price_scale` run stat (read only by a shelf's table).
- `RewardTable.problems()` must be empty, and every item a line names must be there (`tests/content/rewards/test_reward_tables.gd`).

| Table | What rolls from it |
| --- | --- |
| `clear` | a fight room's clear (a room kind names its table: `RoomKind.rewards`, connected biomes CB11) |
| `boss` | the boss's room's clear: better cards, max health potions |
| `reward` | a reward room, as the party steps in: its rolls among items of the room's type (`RewardType`), so it lists four potions (healing, large healing, max health, vigor) for a potion room to choose among |
| `treasure` | a treasure room (behind its key door) |
| `secret` | a secret room (behind its cracked rock) |
| `challenge` | a challenge room's clear: the bigger reward of an elite fight |
| `shelf` | a shop's shelf (`RoomKind.shelf`): one item a spot, never one twice, each at its line's `price`; the potions small healing (3), healing (6), vigor (9), large healing (11), max health (12); and a reward reroll (8), one copy, weight 1.5 (the owner's answer of 2026-11-19; the room reroll it sold is gone with the room rerolls) |

## Allowed files

`.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```
