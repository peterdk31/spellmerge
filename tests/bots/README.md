# Bots

The bots that play headless runs for the smoke tests, the seed sweep and the playtest reports. The whole folder is described in [tests/README.md](../README.md) (`bots/`); this page is the bots' hub errand, their builds and their mend staff.

## Files

- `bot.gd`: one bot, one seat (a `FrameSource`: it fills its seat's input frames as a gamepad would). A fighter plays by the enemies' own AI (`AIBrain`) with `bot_profile.tres`; an idler stands still and opens its builder.
- `bot_builds.gd`: the bots' starting builds (below).
- `bot_hub.gd`: a bot's errand in the hub before a run (below).
- `bot_route.gd`: the walk over the wall grid between rooms (and in the hub).
- `staff_fuzzer.gd`: seeded random staffs (`build_random`, the spell fuzz test).
- `playtest.gd`: a whole crypt biome played by 1-4 fighters, with a report.
- Tests: `test_bot.gd`, `test_bot_builds.gd`, `test_bot_hub.gd`, `test_bot_travel.gd`, `test_room_balance.gd`, `test_spell_fuzz.gd`.

## Rules

- A bot plays through its seat's input frames only. It reads no spell field and changes no simulation state of its own.
- No game rule is the bots' own: everything they do is a player's way.
- A bot never uses the d-pad (quick-use items), the map's teleport or a reroll.
- A bot never takes a dev staff or the Wild star; only the rack's normal staffs.
- Play's bag is a test-settable member of Flow, not a run rule: a recording made by a runner that stocked it plays back only with the same bag.
- **The pinned seed:** the 4-bot smoke test must win `REPLAY_SEED` (tests/smoke/four_bot_runner.gd). A change to the bots' builds that loses it moves the pin to a seed they win and says why.

## The hub

The bots' runs start in the hub, where each bot takes a staff from the rack as a player would.

- **The runners start the hub:** the smoke runner, the sweep and the playtest record `hub_requested` (`Frames.record`), not `play_requested`. The replay seed deals the hub's seed then the run's (`ReplayTape.next_run_seed`); the run seed a runner prints is the run's.
- **The errand** (`bot_hub.gd`, `bot.plan_hub(team, starter)`): draw a build from the hub's dice, walk to the rack staff it names (`rack`, found in `Items.lying`), press A (`take`) once it is the item in reach (`Items.near_of`), set the build (`send_build`), walk to its own corner of the teleporter stone (`spot_on`); the starter (P1) presses A (`accept`) once the stone is lit. The walk is `bot_route.gd`'s field. The brain plays nothing in the hub.
- **The run takes the whole player along:** the runners check each bot carried its build in.
- **Once:** after the party departs the errand is done; a later hub is a room with no fight.

## Starting builds

- **The table** (`bot_builds.gd`) is the bots' own, never player content: a build is its rack staff (`rack`) and the cards of each hand's staff (RB, RT, then LB). `FIGHTERS` put a strong attack on RT and a dash on RB. `MENDER` heals on RB, dashes on RT and holds the Firebolt on LB. `FIGHTER_RACKS` gives each seat a different rack staff (P4 none).
- **Picking the staff:** the brain plays every hand by what each staff casts next (`CastSense`), never by its button.
- **The draw:** `Sim.chance_int`, purpose `bot_build`, the seat the key, counter 0, from the hub's dice. In a team of two or more fighting bots, P2 (`MEND_SEAT`) carries `MENDER`.
- **Building:** `bot.draw(team)` picks the build, `send_build()` sends each hand's staff as one `staff_cards_requested`; `build_drawn(team)` is both. A bot run starts with `bot_builds.bag()` as Play's bag (`stock` returns the old bag to put back). `holds_build(wizard)` checks it.
- **Valid:** `test_bot_builds.gd` compiles every build on the staffs it goes on (no card wasted, one cast a staff, the attack hurts, the dash moves, the mend heals and hurts nobody) and holds every rack staff to a starter's mana and a cooldown.

## The mend staff

- A mend heals whatever it hits, friend or foe (content/spells/elements/mend); the bot aims a plain bolt at a teammate.
- Cast through the AI's `heal ally` behaviour (gameplay/ai/behaviours/heal_ally.gd): the most hurt teammate under `TeamBoard.HURT`, in reach along a clear line, read from a team board of the bot's own (`_report_mates`), never the AI area's.
- **Never a foe:** the heal is held (`held_heal`) while a foe (a prop counts) stands within `FOE_CLEAR` of the line of fire to the heal's reach, or within `FOE_CLOSE` of the bot. The playtest counts what heals gave (`PLAYTEST heals: ...`).

## Validate

```sh
godot --headless --path . --script res://tests/support/run.gd -- res://tests/bots/test_bot_builds.gd res://tests/bots/test_bot_hub.gd res://tests/bots/test_bot.gd
godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_smoke.gd
godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_sweep.gd -- --seeds=1-60
godot --headless --fixed-fps 60 --path . --script res://tests/bots/playtest.gd -- --players=2 --seed=11
```

History and reasons: [docs/history/tests-bots-README.md](../../docs/history/tests-bots-README.md).
