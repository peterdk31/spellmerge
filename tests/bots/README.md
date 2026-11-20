# Bots

The bots that play headless runs for the smoke tests, the seed sweep and the playtest reports. The whole folder is described in [tests/README.md](../README.md) (`bots/`); this page is the bots' builds and their mend staff.

## Files

- `bot.gd`: one bot, one seat (a `FrameSource`: it fills its seat's input frames as a gamepad would). A fighter plays by the enemies' own AI (`AIBrain`) with `bot_profile.tres`; an idler stands still and opens its builder.
- `bot_builds.gd`: the bots' starting builds (below).
- `bot_route.gd`: the walk over the wall grid between rooms.
- `staff_fuzzer.gd`: seeded random staffs (`build_random`, the spell fuzz test).
- `playtest.gd`: a whole crypt biome played by 1-4 fighters, with a report.
- Tests: `test_bot.gd`, `test_bot_builds.gd`, `test_bot_travel.gd`, `test_room_balance.gd`, `test_spell_fuzz.gd`.

## Starting builds

The owner, 2026-11-20 (on #883): the test bots get more powerful staffs, and a bot can carry a mend staff to heal its allies.

- **The table** (`bot_builds.gd`) is the bots' own, never player content. A build is the cards of each starter staff by number (RB's and RT's staff, 6 slots each), as a person would set them in the builder before the first fight. `FIGHTERS` puts a strong attack on RT (a homing, bigger bolt; a homing split bolt; a faster, overcharged bolt; a beam) and a dash on RB, so the brain fights with RT and dodges with RB. `MENDER` puts the heal on RB (mend on an overcharged, faster bolt) and a dash on RT. The owner allowed bots a third staff (heal, dash and attack; on #886), within the game's rules: in Play a wizard holds only the two starter staffs (`Flow.START_HANDS`; Play's start takes no loadout along), and a third comes only from the hub's rack or one found in a run, so the mender carries the owner's other choice, heal and dash.
- **The draw:** a fighter's build comes from the run's dice (`Sim.chance_int`, purpose `bot_build`, its seat the key, its one roll the counter 0). The same run seed gives the same builds on every machine and every replay. In a team of two or more fighting bots, P2 (`MEND_SEAT`) carries `MENDER` instead (P2 fights in every run the bots play: the 4-bot smoke test's idler is P4).
- **Building:** `bot.build_drawn(team)` sends each staff as one `staff_cards_requested`, as the builder does, from the wizard's card bag. A run the bots play with these builds starts with `bot_builds.bag()` as Play's bag (`stock`, which returns the old bag for the caller to put back): the smoke runner, the sweep (through it) and the playtest do this. `holds_build(wizard)` says whether the staffs hold the build.
- **Valid:** `test_bot_builds.gd` compiles every build on the starter staffs: no card wasted, one cast a staff, the attack hurts, the dash moves its caster, the mend heals and hurts nobody, and the bag builds each.

## The mend staff

- A mend heals whatever it hits, friend or foe (content/spells/elements/mend). A plain bolt stops at the first body it hits, so the bot aims it at a teammate; a spray or a piercing shot would reach past one.
- The brain casts it through the AI's `heal ally` behaviour (gameplay/ai/behaviours/heal_ally.gd): the most hurt teammate (under `TeamBoard.HURT`, 70% health), the lowest health first, in the heal's reach along a clear line. The brain reads its teammates' health from a team board of the bot's own (`_report_mates`, every step, as a person reads the health bars): the AI area's board is simulation state, and a bot changes none.
- **Never a foe:** a heal is held (`held_heal`; only the heal, the staff that hurts still goes) while a foe's body stands within `FOE_CLEAR` (40 px: 24 px let a foe step into the bolt in the 4-bot playtests, and its heals reached foes) of the line of fire out to the heal's whole reach (a heal that misses flies on), or within `FOE_CLOSE` (32 px) of the bot any way round (a shot leaves at the staff's tip, so a foe pressed against the bot is hit as it leaves). A prop counts as a foe here: a heal is wasted on one. A foe that steps into the bolt's way after it left can still be healed; the playtest counts what each bot's heals gave (`PLAYTEST heals: ... to teammates, ... to props, ... to foes`).
- Otherwise it plays as every fighter does with what it holds (its dash hurts what it runs through; it holds fire with a teammate in its line, revives, travels).

## Rules

- A bot plays through its seat's input frames only. It reads no spell field and changes no simulation state of its own.
- A bot never uses the d-pad (quick-use items), the map's teleport or a reroll.
- Play's bag is a test-settable member of Flow, not a run rule (as the smoke test's unscaled run): a recording made by a runner that stocked it plays back only with the same bag, or its `staff_cards_requested` commands are refused.
- **The pinned seed:** the 4-bot smoke test must win `REPLAY_SEED` (tests/smoke/four_bot_runner.gd). A change to the bots' builds that loses it moves the pin to a seed they win and says why.

## Validate

```sh
godot --headless --path . --script res://tests/support/run.gd -- res://tests/bots/test_bot_builds.gd res://tests/bots/test_bot.gd
godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_smoke.gd
godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_sweep.gd -- --seeds=1-60
godot --headless --fixed-fps 60 --path . --script res://tests/bots/playtest.gd -- --players=2 --seed=11
```
