class_name RerollBase
extends ItemContent
## A reroll (the owner, 2026-11-19: "Create new currencies called 'room reroll' and 'reward
## reroll'"; then "I only want the player to be able to reroll rewards, not rooms"): a stacked item
## in the currency bag (`ItemKinds.REROLL`), beside the coins and the keys, each player's own and
## droppable as they are. One id, its file under `content/rerolls/`, found by the registry under
## `rerolls`:
##
## - `REWARD` (`reward_reroll`): X in the reward card picker spends one and rerolls that player's
##   offer (gameplay/rewards).
##
## Every player starts a run with the run stat `start_reward_rerolls` of them (`RunStats`, 1 for
## now), so a relic or a rule change can give more.

## The reward reroll's id.
const REWARD: StringName = &"reward_reroll"
## The run stat each starts from, by id.
const START_STATS: Dictionary[StringName, StringName] = {REWARD: &"start_reward_rerolls"}
