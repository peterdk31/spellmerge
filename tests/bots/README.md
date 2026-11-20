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

## The hub

The owner, 2026-11-20 (after #886): the bots' runs start in the hub, where each bot takes a staff from the hub's rack as a player would, and the run starts through the hub's own run start. No game rule is the bots' own: everything here is a player's way.

- **The runners start the hub:** the smoke runner (and the sweep through it) and the playtest record `hub_requested` (`Frames.record`), not `play_requested`. The replay seed deals the hub's seed and then the run's (`ReplayTape.next_run_seed`), so the builds, drawn in the hub, and the run are the same on every start. The run seed a runner prints is the run's, read as its start room is entered.
- **The errand** (`bot_hub.gd`, `bot.plan_hub(team, starter)`; fighters and the idler alike): a bot draws its build from the hub's dice, walks to the rack staff its build names (`bot_builds.gd`, `rack`; found by its staff and cards in `Items.lying`, as a person knows it by its look and name) and presses A (`take`) once it is the item in reach (`Items.near_of`, the hint), sets its build (`send_build`), and walks onto the teleporter stone, each seat to its own corner of it (`spot_on`). The starter (P1) presses A (`accept`) once the stone is lit. The HUD's panels turn those presses into the commands `item_take_requested` and `run_requested`, as a gamepad's. The walk is the route's field over the hub's walls and holes (`bot_route.gd`), round a wall toward the point where the field has no way (a prop's ground, the stone's). The brain plays nothing in the hub (the training dummies are no fight).
- **The run takes the whole player along** (Flow's run from the stone, items I4): every staff, its cards and its hand, so the rack staff and the builds are in the run. The runners check it as the run starts (the smoke test fails a bot that did not carry its build in; the playtest says `P2 carried ...`).
- **Once:** after the party departs, the errand is done; a later hub (a lost run's end) is stood in as a room with no fight.

## Starting builds

The owner, 2026-11-20 (on #883): the test bots get more powerful staffs, and a bot can carry a mend staff to heal its allies.

- **The table** (`bot_builds.gd`) is the bots' own, never player content. A build is the rack staff it takes in the hub (`rack`; none for most) and the cards of the staff on each hand (RB, RT, then LB, where a taken staff goes), as a person would set them in the builder before a run; a hand past the build's list keeps its cards. `FIGHTERS` puts a strong attack on RT (a homing, bigger bolt; a homing split bolt; a faster, overcharged bolt; a beam) and a dash on RB, so the brain fights with RT and dodges with RB. `MENDER` (the owner, on #886 and #891: heal, dash and a fire bolt) takes the hub rack's Firebolt and holds three staffs: the heal on RB (mend on an overcharged, faster bolt), a dash on RT, and on LB the Firebolt as it lay on the rack (fire on a bolt, on the moon staff).
- **Only normal rack staffs** (the owner, 2026-11-20, on #891): a bot never takes a dev staff (no mana cost, no cooldown: it would win every fight and the sweep would measure nothing) or the Wild star. The rack's normal staffs (content/items: the Firebolt, the Frost seeker and the Twin bolt, each on a starter staff) are a player's real choices; the mender takes the Firebolt, P1 the Frost seeker and P3 the Twin bolt (`FIGHTER_RACKS`, by seat: each a different one), each used as it lies on LB, a third attack; P4 takes none and walks straight to the stone. With the fighters' rack staffs the playtests cleared more fights (seed 11: 5 of 9 alone, 8 of 9 with two, against 2 and 4). `test_bot_builds.gd` holds every build's rack staff to a starter's mana and a cooldown.
- **Picking the staff:** the brain plays every hand by what each staff casts next (`CastSense`), never by its button, so the mender heals with RB (the `heal ally` behaviour, a hurt teammate in reach), gets away with RT (an urgent dodge or escape taps whichever staff's next cast moves its caster), and otherwise fights with LB. `test_bot_builds.gd` checks each on a mender built in a run.
- **The draw:** a fighter's build comes from the dice of the run under way when it is drawn, the hub's (`Sim.chance_int`, purpose `bot_build`, its seat the key, its one roll the counter 0). The same replay seed gives the same builds on every machine and every replay. In a team of two or more fighting bots, P2 (`MEND_SEAT`) carries `MENDER` instead (P2 fights in every run the bots play: the 4-bot smoke test's idler is P4).
- **Building:** `bot.draw(team)` picks the build, `send_build()` sends each hand's staff as one `staff_cards_requested` (by the number of the staff on that hand), as the builder does, from the wizard's card bag; `build_drawn(team)` is both (a test's run with no hub). A run the bots play with these builds starts with `bot_builds.bag()` as Play's bag, which the hub hands out too (`stock`, which returns the old bag for the caller to put back): the smoke runner, the sweep (through it) and the playtest do this. `holds_build(wizard)` says whether the staffs hold the build, the rack staff on a hand.
- **Valid:** `test_bot_builds.gd` compiles every build on the staffs it goes on (the starters, the rack staff's): no card wasted, one cast a staff, the attack hurts, the dash moves its caster, the mend heals and hurts nobody, and the bag builds each.

## The mend staff

- A mend heals whatever it hits, friend or foe (content/spells/elements/mend). A plain bolt stops at the first body it hits, so the bot aims it at a teammate; a spray or a piercing shot would reach past one.
- The brain casts it through the AI's `heal ally` behaviour (gameplay/ai/behaviours/heal_ally.gd): the most hurt teammate (under `TeamBoard.HURT`, 70% health), the lowest health first, in the heal's reach along a clear line. The brain reads its teammates' health from a team board of the bot's own (`_report_mates`, every step, as a person reads the health bars): the AI area's board is simulation state, and a bot changes none.
- **Never a foe:** a heal is held (`held_heal`; only the heal, the staff that hurts still goes) while a foe's body stands within `FOE_CLEAR` (40 px: 24 px let a foe step into the bolt in the 4-bot playtests, and its heals reached foes) of the line of fire out to the heal's whole reach (a heal that misses flies on), or within `FOE_CLOSE` (32 px) of the bot any way round (a shot leaves at the staff's tip, so a foe pressed against the bot is hit as it leaves). A prop counts as a foe here: a heal is wasted on one. A foe that steps into the bolt's way after it left can still be healed; the playtest counts what each bot's heals gave (`PLAYTEST heals: ... to teammates, ... to props, ... to foes`).
- Otherwise it fights as every fighter does (it holds fire with a teammate in its line, revives, travels).

## Rules

- A bot plays through its seat's input frames only. It reads no spell field and changes no simulation state of its own.
- A bot never uses the d-pad (quick-use items), the map's teleport or a reroll.
- Play's bag is a test-settable member of Flow, not a run rule (as the smoke test's unscaled run): a recording made by a runner that stocked it plays back only with the same bag, or its `staff_cards_requested` commands are refused.
- **The pinned seed:** the 4-bot smoke test must win `REPLAY_SEED` (tests/smoke/four_bot_runner.gd). A change to the bots' builds that loses it moves the pin to a seed they win and says why.

## Validate

```sh
godot --headless --path . --script res://tests/support/run.gd -- res://tests/bots/test_bot_builds.gd res://tests/bots/test_bot_hub.gd res://tests/bots/test_bot.gd
godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_smoke.gd
godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_sweep.gd -- --seeds=1-60
godot --headless --fixed-fps 60 --path . --script res://tests/bots/playtest.gd -- --players=2 --seed=11
```
