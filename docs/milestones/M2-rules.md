# M2 rework: cards follow the general rules (phase R)

**Goal:** every card follows a small set of general rules on every carrier, with no special cases, so a player can try any combination and get the result the rules predict. A card that cannot mean anything on a carrier is listed as wasted, with the reason, before the cast. Nothing does nothing silently.

**Status (2026-10-29):** R1a done (echo, zaps, relay and jumps keep the whole hit), R1b done (a flying chain jump keeps every card), R1c done (heavy and growth multiply), R1d done (a missed hook and a rain blast at their end point), R1e and R1f done (moves on a shot add; a hold in a payload is a hold): R1 is complete. R2 and R3 done (the compiler lists every card that does nothing, and `tests/core/test_card_rules.gd` plays every card on every carrier and prints the live matrix; DECISIONS.md), except the rule 2 checks (a card survives a bounce, jump, echo and payload), which are deferred to docs/BACKLOG.md. Next: R4 (owner decisions). The owner asked for "a pass that checks for the general rules, in which there are custom cases that break them" after a homing beam stopped homing at a wall (#453). An audit of the compiler, the runtime and the projectile manager (on main after #453) found 16 confirmed breaks and 7 suspected ones; they are below. Same day as "No limits on spell interactions" (#450).

**The owner's words:** "A general rule should be, that we dont limit the interactions, they follow the rules. Then player can then experiment and always get expected results." And: "It should be the general rule for everything."

**Done when:**

1. Every finding in "Findings" is fixed, listed as wasted on purpose, or re-decided by the owner (R4), and says which in docs/DECISIONS.md.
2. `tests/core/test_card_rules.gd` (R3) runs every card on every carrier and passes, finding both by itself (R3, "Automatic discovery"), so a new card or carrier is checked with nobody updating the test.
3. The matrix in "Card × carrier" has no ✗ left.
4. `tools/ptest.sh` is green; `test_projectiles_step_exact` recorded again where a rule changed what shots do (say why in the PR).

## The general rules

1. **Works or wasted.** Every modifier behaviour and trigger works on every carrier where it can physically mean something, the same way. Where it cannot, the compiler (`StaffCompiler.behaviour_runs` / `_why_not`, `TRAVEL_ONLY`, and a new trigger check) lists the card as wasted with a reason. A card that silently does nothing breaks this rule.
2. **Nothing takes a card away.** A behaviour persists through other events: bounce, wall turn, hit, pierce, chain jump, return, stick, payload firing, echo, mirror, split. (Example fixed in #453: a homing beam homes again after a wall.)
3. **Counts add, multipliers multiply.** Bounces, pierce, chain jumps and shields add; damage, speed, size, knockback (heavy), growth and homing multiply.
4. **A trigger means the same on every carrier,** and fires every time its event happens while its carrier lives. A payload is cast by the shot that fired it, or by its point if that is gone.
5. **No caps on interactions.** Engine load is paced (deferred), never dropped. Accepted limits: the projectile cap (drop oldest), the arc, magnet and hit-work pacing, the beam shader's 80 drawn points (docs/BACKLOG.md).
6. **One rule for every caster and every firing:** players and enemies; a carrier fired from the staff, as a payload, echoed, mirrored, or as a chain jump.

## Findings (audit, 2026-10-29)

Line numbers are from main after #453 and drift; the function names hold. The first four were checked by hand as well.

| # | Where | Card(s) × carrier(s) | Rule | What a player sees |
| --- | --- | --- | --- | --- |
| 1 | `staff_compiler.gd` (`echo_hit`, ~334), `combat.gd` (~776) | echo × mend, heavy, two or more infusions | 2 | The echo hit copies only damage, knockback and the first status: no `heal`, `slam`, later statuses or `kind`. **An echoed mend bolt hurts teammates**; heavy's slam and the second infusion are lost on the echo. |
| 2 | `spells.gd` `_relay` | relay × mend, heavy, multi-infusion | 2 | The merged profile drops `heal`, `slam`, later statuses, `kind`: a relay mend bolt that takes on an element hurts friends. |
| 3 | `spells.gd` `_jump` | chain × homing, bounce, ghost, spiral, linger, growth, sticky, return, shield, pierce | 2, 6 | A jump is spawned with pierce 0 and `_register` without `_apply_travel` / `set_homing`: each jump is a plain bolt. |
| 4 | `spells.gd` `_launch`, `projectile_manager.gd` `_is_flyer` | bounce, ghost, spiral, linger, growth, sticky × orbit, rune, wall | 1 | `_apply_travel` runs only for STRAIGHT, HOOK, SWAP and the setters refuse other motions: `growth · rune`, `sticky · orbit`, `linger · wall` do nothing, nothing is listed. |
| 5 | `_start_beam`, `_shoot_ray`, `ray` | ghost, spiral, linger, growth, sticky, magnet, shield, relay × beam, fissure | 1 | A ray stops at walls (ghost does nothing), beams are never `_register`ed (magnet), no `_apply_shield` for rays, relay is shots only. Silent. |
| 6 | `_move_caster` (no hit path for moves) | chain, siphon, possess, heavy, relay, pierce, bounce, ghost, spiral, linger, growth, sticky, magnet × dash, teleport | 1 | A dash hits nothing: **`heavy · dash` ("shoulder charge", M2-staffs.md) does nothing**, nor the rest. |
| 7 | `_register` (only slot shots get trackers) | timer, on hurt × beam, fissure, wizard dash/teleport, rain, decoy, familiar | 4 | `timer · beam`, `hold · on hurt · beam` never fire; the compiler accepts them (against DECISIONS "a hold carrier's timer for as long as it is on"). |
| 8 | `_land_rain`, entities, moves | on hit, on kill, on reaction, on block, on wall × rain, decoy, familiar, dash, teleport | 4 | These carriers never hit under their own tag: `on hit · familiar`, `on wall · dash` never fire, silently. |
| 9 | `_fire_spell` (mirror) | mirror × hook, swap, wall, rain, dash, teleport, orbit, rune, decoy, familiar | 1 | Mirror fires backwards only for STRAIGHT, RAY, FISSURE (hook and swap are straight shots yet excluded); silent elsewhere. Partly decided (R4). |
| 10 | `_land_rain` / `_telegraph_rain` | blast × rain | 1 | No `_blast` where the rain lands. |
| 11 | `_on_expired` | blast × hook | 2 | A hook's blast is skipped on every expiry, so a hook that misses never blasts (DECISIONS: "every spent shot blasts"). |
| 12 | `_recoil` → `projectile_manager.gd` `move_shot` | mirror · recoil × payload carriers; recoil + hook/dash on a shot | 3, 6 | On the wizard two pushes add and cancel; on a shot `move_shot` replaces the earlier move: a payload's `mirror · recoil` pushes forward, a later hook/dash overwrites a recoil. |
| 13 | `_launch`, `_start_hold` | hold × a carrier in a payload | 6 | Gets a 100000 s life but is not in `_hold_tags`: never switches off, reserves no mana, lives until the staff is rebuilt. |
| 14 | `_beam_cast` (`_echo_spell` restored before `_cast_jumps`), `_zap`, `hit_profile` | echo × beam chain, arc; relay × arc | 2 | An echoed live beam's chain jumps hit at full damage after its first tick (DECISIONS: half damage on jumps); an echoed shot's arc zaps use the full `arc_hit`; relay never reaches zaps. |
| 15 | `_move_caster` (shot branch), `_on_hit_effects` (SWAP) | shield × payload dash/teleport; shield × swap | 1, 6 | Shield on the wizard's dash makes a barrier; on a shot moved by a payload dash nothing. Hook barriers the caster on its pull, swap does not. |
| 16 | `staff_compiler.gd` (behaviour strengths summed), `heavy.tres` (4) | heavy × heavy (and growth × growth) | 3 | Strengths are summed but heavy multiplies knockback: two heavy cards give ×8, not ×16. Growth (2+2 = 2×2) agrees by chance only. |

**Suspected (check while fixing nearby):**
- `projectile_manager.gd` `_pass_return`: a returning shot stops homing (pass-order comment).
- `_register_hit`: sticky ends the remaining pierce at the first hit.
- ~~`_jump`: flying jumps get pierce 0~~ (fixed in R1b; a ray jump still pierces nothing, R4).
- `_fire_payload` from a beam hit uses CASTER_POINT: an orbit payload circles the hit point, not the beam.
- `_on_familiar_cast` uses CASTER_POINT while the familiar lives: an orbit, return or dash payload ignores the familiar.
- `_shield_block`: when the hit-work budget runs out a block is skipped, not deferred (an enemy shot flies through).
- Fissure ends inside its call: `hold · fissure` silently does nothing.

## Card × carrier (audit, before R)

Since R3 the live matrix is printed by `tests/core/test_card_rules.gd` (✓ works, W listed as wasted, ✗ silent: fails). The table below is the audit's, kept for history.

✓ works · W listed as wasted · ✗ silently ignored or special-cased · (n) the finding.

| | Bolt | Rune | Orbit | Beam | Dash | Telep | Hook | Swap | Wall | Rain | Fiss | Decoy | Famil |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| homing | ✓ | W | W | ✓ | ✓ | ✓ | ✓ | ✓ | W | W | W | W | W |
| chain | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ |
| shield | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| blast | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| hold | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ |
| recoil | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| bounce | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ |
| echo | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| linger | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| heavy / siphon / possess | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ |
| sticky | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| magnet | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| ghost | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| spiral | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| mirror | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| growth | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| relay | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| return | ✓ | W | W | W | W | W | ✓ | ✓ | W | W | W | W | W |
| arc | ✓ | ✓ | ✓ | W | W | W | ✓ | ✓ | ✓ | W | W | W | W |

**Triggers (R2b, what the runtime does today):** `StaffCompiler.trigger_runs` and `trigger_why_not`. ✓ fires · W listed as wasted with its payload · s only with a shield or deflect on the carrier (a dash's or teleport's shield is a barrier on the wizard; since R4c a dash and a teleport hit, and their deflect turns the shots they pass or land by) · b only with a blast, whose area hit carries the carrier's tag. On reaction also needs an infusion or relay, and on wall is wasted on a ghost shot. Every W is a cell for R4.

| | Bolt | Rune | Orbit | Beam | Dash | Telep | Hook | Swap | Wall | Rain | Fiss | Decoy | Famil | Swing |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| on hit | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | W | ✓ | W | W | ✓ |
| on expire | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| timer | ✓ | ✓ | ✓ | W | W | W | ✓ | ✓ | ✓ | W | W | W | W | W |
| on block | s | s | s | s | s | s | s | s | s | W | s | W | W | s |
| on kill | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | b | ✓ | b | b | ✓ |
| on cast | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| on wall | ✓ | W | W | ✓ | W | W | ✓ | ✓ | W | W | ✓ | W | W | W |
| on hurt | ✓ | ✓ | ✓ | W | W | W | ✓ | ✓ | ✓ | W | W | W | W | W |
| on reaction | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | b | ✓ | b | b | ✓ |

The melee carriers (swing, slam) arrived on main after the audit: R2 and R3 cover them like the rest.

## Plan

Four phases, in order. Each part is one PR with a regression test that fails before the fix, the docs it changes (core/README.md, M2-staffs.md tables, DECISIONS.md), and `tools/ptest.sh` green. Owner sessions; small PRs.

### R1: the real bugs (rules 2, 3, 6)

Fix what is plainly wrong under the rules; no owner decision needed.

| Part | Fixes | What changes |
| --- | --- | --- |
| R1a | 1, 2, 14 | One way to make a scaled or merged hit: an echo hit is the carrier's whole `HitProfile` (heal, slam, every status, kind) at ECHO_DAMAGE; relay adds infusions to the whole hit. The echo and relay ride on every hit of the carrier: beam chain jumps after the first tick, arc zaps. Tests: echoed mend heals a teammate and hurts an enemy at half the enemy share; echoed heavy slams; relay mend still heals; echoed beam's jumps hit at half. |
| R1b | 3 (+ suspected flying-jump pierce) | A chain jump is the carrier fired again from the hit with every card it has (homing, bounce, ghost, spiral, linger, growth, sticky, return, shield, pierce, its trigger), one jump fewer; only its aim and source exclusion differ. Tests per behaviour on a jump. |
| R1c | 16 | Multiplier behaviours multiply across cards (heavy, growth, as homing does with HOMING_STACK): the compiler keeps a product for them, not a sum. Test: two heavy = ×16. Note the strength numbers in M2-staffs.md. |
| R1d | 11, 10 | Every carrier blasts at its end point: a hook that misses blasts where it ends; a rain blasts where it lands. |
| R1e | 12 | Moves on a shot add, as the wizard's do (`move_shot` sums the offsets in flight); `mirror · recoil` cancels on a payload too. |
| R1f | 13 | Hold in a payload: switched off with its staff, reserves mana, as the cast's own hold. |

### R2: the compiler says what does nothing (rule 1)

Make the compiler's "wasted" list match what the runtime really does, so nothing is silent even before every cell is implemented.

- **R2a.** Replace the three-case `behaviour_runs` with one table: behaviour × motion → runs, or the reason it cannot (from the matrix: every ✗ that R4 does not turn into ✓ becomes W with a reason a player understands, "a rune does not move"). Keep it next to the runtime that implements it, so the two cannot drift: the runtime asks the same table before applying a behaviour.
- **R2b.** Triggers too: `trigger_runs(event, motion)`: `timer` and `on hurt` on carriers without a live slot until R4 gives them one; `on hit`, `on kill`, `on reaction`, `on block` on carriers that never hit under their tag; `on wall` on carriers that never meet a wall. The builder shows them wasted with the reason.
- **R2c.** The builder and staff view show the reasons (they already list wasted cards; check the new ones read well).

### R3: the permanent check (`tests/core/test_card_rules.gd`)

The owner's "pass that checks for the general rules", as a test that runs in the build:

- For every modifier and trigger card in `content/spells/` × every carrier form (the real cards, through the registry, so a new card or carrier is checked the day it lands), compile `[card, carrier]` (a trigger with a plain payload).
- If the compiler lists the card as wasted: the reason must be non-empty. Done.
- Otherwise the card must change something observable: run the cast in a small scene (walls, a few targets, an ally), record a trace (hits and their profiles, shots and their paths, events, payload fires, the caster's moves) and compare with the same cast without the card. Identical traces mean a silent no-op: fail with "`<card>` on `<carrier>` does nothing and is not listed as wasted".
- Per-behaviour probes where a plain diff is not enough (homing needs a target off the line, bounce a wall, ghost a wall behind a target, timer a long life, on wall a wall, on kill a target that dies): a small table of scene setups per card, chosen by the card's behaviour or event, not per carrier.
- Prints the matrix (✓, W, ✗) so the PR shows coverage; a ✗ fails.
- Rule 2 checks in the same test: a card's effect survives a bounce, a chain jump, an echo and a payload firing (the trace of the second leg still shows it). **Deferred:** not built in #468; tracked in docs/BACKLOG.md ("Card rules R3, rule 2 checks"). Done-when 2 holds without it.

Build R3 right after R2 (it needs the honest compiler); R1 parts can land before or after.

#### Automatic discovery (owner, 2026-10-29: "It should just auto discover new cards and carriers")

The test keeps no list of cards or carriers. It finds them itself, so a new card or carrier is checked the day it lands, with nobody updating the test:

- **Cards:** every modifier, trigger, infusion and multicast card the registry finds in `content/spells/` (the folders it already scans for the game).
- **Carriers:** every form card the registry finds (`content/spells/forms/`), the melee carriers included; the carrier's `motion` picks the scene it runs in.
- **What they do:** every value of `ModifierBase.Behaviour` and `TriggerBase.Event`, read from the enums. A card whose behaviour or event has no probe yet fails with "no probe for `<behaviour>`", so adding a new kind of card asks for its probe in the same PR.
- It is a `tests/**/test_*.gd`, so it runs with the rest of the suite (`tools/ptest.sh`, and the daily build, whose bisect reverts a merge that breaks it).

### R4: decide with the owner, then implement (rules 1, 4, 5)

The owner re-decides these under the new rule; each "yes, it should work" becomes a part that turns W into ✓ (with a probe in R3). Present them in one session, with a recommendation each:

- **Decided before, now in question:** mirror only on carriers that "have a back" (DECISIONS); a hold carrier does not echo (silent); a beam has no timer (contradicts the timer-for-hold decision); relay shots only, not on chain children or payloads; hold does nothing on rain; recoil skipped on dash and teleport; a beam's chain jump is a beam that pierces nothing; a hook with pierce fires `on expire` twice ("accepted for now"); a returning shot stops homing; a payload with no live shot is cast by its point (a payload dash or hook does nothing); **recoil pushes past 8 at once are dropped** (`mover.gd` `MAX_RECOILS`: a cap missed by #450, fix under rule 5 without a decision); hit-work starvation skipping shield blocks (defer, not skip). **Editing a staff or switching off a hold drops all its waiting launches** (`_release_hold` calls `_drop_pending` first): payload fires of carriers without hold that only wait for the per-step pacing (`FIRE_SHOTS_PER_STEP`) are lost too, against rule 5 (found in R1f, 2026-10-29).
- **Cells to decide (W or ✓):** travel behaviours on orbit, rune, wall (growth on a rune grows the rune; linger and spiral on an orbit?); ghost, magnet, shield, relay on beams and fissures; **dash and teleport hitting what they pass** (makes `heavy · dash` the shoulder charge the card table promises, and chain, siphon, possess, relay on a dash); triggers on rain, decoy, familiar; mirror on any aimed carrier; one shield rule for every carrier that moves its caster.

#### R4c: moves (owner decisions 2026-10-29; DECISIONS.md "Card rules R4c")

- **Dash and teleport hit.** A dash strikes every body its mover (the wizard's body, or the shot a payload dash moves) passes, once each, within `PASS_REACH` (8 px) of its way, sampled so a fast dash misses nothing; a teleport strikes the bodies within `LAND_REACH` (24 px) of where it lands. Both go through the swing's path (`Projectiles.sweep`, `strike`, the beam hit context), so every hit card works as on a shot: the six infusions, chain, heavy (the shoulder charge of M2-staffs.md), siphon, possess, overcharge, on hit, on kill, on reaction; deflect turns the shots within `MOVE_GUARD_REACH` (24 px, before they reach the body). Pierce is wasted on a dash ("it hits what it passes, once each": it already hits everything on its way); split and sniper stay wasted (one body, no spread). `hits()` now includes them; their `_hits_nothing` rows and the recoil row are gone, and deflect runs on every carrier that hits.
- **Recoil adds to the move.** A dash's recoil is the usual push, which the body adds to the dash; a teleport, over at once, has it taken off its distance (past it, it goes backwards).
- **One shield rule for every move** (`Spells._shield_move`): dash, teleport, hook and swap guard what they move, the wizard by a barrier for the move, a shot (a payload move) by that many more shield charges (kept until spent: a shot's shield has no clock).
- **A point cannot move:** a teleport cast by a point blinks the wizard to it, and a hook or swap cast by one moves the wizard (to the hit, as the wizard's own). A dash cast by a point still does nothing: the wizard's dash goes the way its body walks (staffs A6a), so the mover would need to take a way from the card (open question).

## Notes for the sessions

- Start each part from `origin/main` in a worktree outside the project (`../spellmerge-<slug>`), `build/godot` linked from the main checkout, `tools/ptest.sh` for tests (the kit's timing check can trip under load: run it alone).
- `tests/benchmark/fire_cap.gd` and `fire_cap_view.gd` show the cost of a change to triggers; the stress run prints dropped shots and waiting fires.
- Keep the one-rule shape of #453: when a carrier needs a card's effect, call the one place that implements it (as the ray walk asks `Spells._beam_steer`), never a second copy.
