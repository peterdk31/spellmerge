class_name RerollBase
extends ItemContent
## A reroll (the owner, 2026-11-19: "Create new currencies called 'room reroll' and 'reward
## reroll'. They can be used to reroll rooms or rewards"): a stacked item in the currency bag
## (`ItemKinds.REROLL`), beside the coins and the keys, each player's own and droppable as they are.
## Two ids, one file each under `content/rerolls/`, found by the registry under `rerolls`:
##
## - `ROOM` (`room_reroll`): X at an unvisited room's bridge mouth spends one and rerolls what lies
##   behind that doorway (gameplay/flow).
## - `REWARD` (`reward_reroll`): X in the reward card picker spends one and rerolls that player's
##   offer (gameplay/rewards).
##
## Every player starts a run with the run stats `start_room_rerolls` and `start_reward_rerolls`
## of each (`RunStats`, 1 for now), so a relic or a rule change can give more.

## The room reroll's id and the reward reroll's.
const ROOM: StringName = &"room_reroll"
const REWARD: StringName = &"reward_reroll"
## The run stat each starts from, by id.
const START_STATS: Dictionary[StringName, StringName] = {ROOM: &"start_room_rerolls", REWARD: &"start_reward_rerolls"}
