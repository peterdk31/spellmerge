# content/rewards: reward tables

A reward table is what a reward offers its choices from (connected biomes CB10, docs/milestones/connected-biomes.md, decisions 16 and 17): one weighted line a kind of reward. One file per table, `<id>.tres`, a `RewardTable` (`core/base/reward_table.gd`) of `RewardEntry` lines (`core/base/reward_entry.gd`); the registry finds it by its `id` under `rewards`. The Rewards area (`gameplay/rewards/`) rolls each player's own choices from it, as many as that player's `reward_choices` run stat (`core/base/run_stats.gd`), never one twice in an offer.

## Contract

- A line's `kind` is one of `RewardEntry.KINDS`: `card` (`count` copies of the card `id`, or with no id any card of `content/spells` of at most `max_complexity`, 0 for any) `coins` (`count` coins into the player's own wallet), `heal` (`count` health) or `max_health` (`count` more most health, and as much health). A card upgrade waits for card levels; relics join with M3's relic work: a new kind is a row of `KINDS` and its code in the Rewards area.
- `weight` is how likely the line is against the table's others (above 0).
- `RewardTable.problems()` must be empty, and every card a line names must be a card (`tests/content/rewards/test_reward_tables.gd`).

| Table | What rolls from it |
| --- | --- |
| `clear` | a room's clear (every fight and the boss); CB11 gives each kind of room its own |

## Allowed files

`.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```
