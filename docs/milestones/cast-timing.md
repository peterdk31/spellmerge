# Cast timing: wind-up, wind-down and the staff's cooldown

**Status: the owner's direction of 2026-11-06; the owner took every pick in "Questions" ("Fine").** Asked by the owner on 2026-11-06 ("I think we need to rework of cooldowns and staffs work"), then shaped with the owner in one session: every card has a wind-up and a wind-down, a staff has a wind-up and a cooldown, mana limits the big cards, and an unaffordable cast is skipped. The decisions are quoted where they were made; the numbers in "Retune" are drafts for the sandbox.

## What is wrong today

Every staff has one delay timer (`Spells._cooldown`). After a cast it is set to the cast's `delay`, which `StaffCompiler` sums from:

- the staff's `cast_delay`;
- every carrier's `cooldown` times its modifiers' `cooldown_mult`, **payload carriers included** (`_build`, `_cast.delay += spell.cooldown`);
- every multicast card's `cooldown`;
- the staff's `recharge`, when the cast ends the cycle.

What that does in play:

- **One number does two jobs.** A bolt's 0.35 s is its tempo; a familiar's 8 s, a decoy's 4 s and a dash's 2 s are lockouts.
- **Cards hold each other hostage.** `familiar · bolt · bolt` waits 8 s before the bolts, every cycle. The best staff puts one big card alone on a button, which works against combining.
- **Payloads lock the staff for what may never happen.** `on hit · bolt · familiar` is locked 8.4 s after every bolt, hit or miss.
- **The staff's numbers do nothing.** Every player staff has `cast_delay` 0 and `recharge` 0.05; every enemy staff 0 and 0. Staffs differ only in their look, where DESIGN.md says found staffs "differ in slots, speed and recharge".
- **The wind-up is a carrier's.** Only swing and slam have one (`swing.gd`, `slam.gd`: the shot is made at the press and held by its caster until it hits), and a swing within `SWING_CHAIN` of the last skips it. No other card can wind up.

## The model

One cast is one timeline:

```
press ── wind-up ──▶ release ── wind-down ──▶ free     (the cycle's last cast: then the staff's cooldown)
```

- **Every card has `wind_up` and `wind_down`** (owner, 2026-11-06: "they should be on every card. But most cards will then have cast_wind_up set to 0, except for the melee carriers"). A carrier card sets the base; a modifier adds to the wind-up (`wind_up_add`) and scales the wind-down (`wind_down_mult`, today's `cooldown_mult`, same values); a multicast card adds wind-down (today's `cooldown`, 0 on every one).
- **A cast's wind-up** is the staff's `wind_up` plus every card of its own group. **Its wind-down** is the group's. Several carriers add up and leave together (owner).
- **During the wind-up** the cast follows the caster: its aim follows the stick (owner) and it leaves from where the staff tip is at the release. Being hit does not cancel it (owner); being downed does, and so does a rebuild of the staff. The staff's wind pose (`StaffPoses`) plays over it.
- **The staff's `cooldown`** runs after the cycle's last cast, after its wind-down (they add; the corner panel's dashed bar shows it). The dev staff's is 0. `cast_delay` and `recharge` are gone.
- **Payloads add no time to the staff.** A payload group's wind-up delays its launch where its trigger fired (the same rule as a cast; `on hit · charge · bolt` fires a charged bolt from the hit point); it has no wind-down, since no staff waits on it.
- **Mana** is checked at the press and paid at the release (owner), so a cast that never leaves costs nothing. It is what limits the big cards now (familiar, decoy, dash, orbit, teleport, swap).
- **A cast the staff cannot afford is skipped** (owner, 2026-11-06: "Follow your recommendation"): it costs nothing, the cursor moves on, a fizzle cue plays, and the press fires the first affordable cast after it. Skipping past the cycle's end runs the cooldown, as a cast would. A whole cast is skipped, never one card of it: the cycle stays as compiled.
- **Holding a button** chains casts as today (owner).
- **A sustained (`hold`) carrier's switch-off press** frees the staff at once (today it waits the staff's `cast_delay`, 0 on every staff).

### Swing and slam

They follow the plain rule (owner: "Cant swing just follow the new wind_up rules"): their wind-up moves from the carrier into the cast, so the swing is made at the release and hits at once. `SWING_CHAIN` goes; swings still alternate sides (`swing.gd` already turns each first swing of a cast the other way). A chained swing now winds up 0.12 s every time: the same swings a second, each hit a little later.

### Enemies

- **The telegraph is the wind-up** (owner: "regular enemies should just have staffs with a higher wind_up, which then allows for showing the telegraph"). An enemy staff gets a `wind_up` (draft 0.4–0.6 s); `CreatureLook` telegraphs while its caster winds up, instead of while its AI is in `WINDUP`.
- **The AI keeps aiming while it winds up** (owner, 2026-11-06: "Lets try to just have the AI aim while winding up aswell - we can always change this again"). The brain's `WINDUP` state stops being a timer of its own: the AI presses, then tracks its target until the cast leaves. Its aim error is drawn as today.
- A telegraph still always comes true: nothing cancels a wind-up but being downed, and the mana was checked at the press.
- `AIProfile.windup_scale` and "a windup lasts longer for a more dangerous cast" go: how long an enemy warns is its staff's and its cards' data.

## Retune (drafts for the sandbox)

Rule: a card whose cooldown is 1 s or less keeps it as its wind-down; a longer one gets a short wind-down and a higher mana cost. Pools stay 100 mana, 10 a second.

| Card | Today (cooldown, mana) | wind_up | wind_down | mana |
| --- | --- | --- | --- | --- |
| atom | 0.02, 0.6 | 0 | 0.02 | 0.6 |
| beam | 0.25, 4 | 0 | 0.25 | 4 |
| bolt | 0.35, 5 | 0 | 0.35 | 5 |
| swing | 0.3 (wind 0.12), 0 | 0.12 | 0.18 | 0 |
| slam | 0.6 (wind 0.25), 0 | 0.25 | 0.35 | 0 |
| nova | 1.0, 10 | 0 | 1.0 | 10 |
| wall | 1.0, 6 | 0 | 1.0 | 6 |
| rune | 1.2, 8 | 0 | 0.5 | 12 |
| rain | 1.5, 6 | 0 | 0.5 | 12 |
| portal | 1.5, 10 | 0 | 0.5 | 20 |
| dash | 2.0, 0 | 0 | 0.27 | 25 |
| teleport | 2.5, 4 | 0 | 0.3 | 20 |
| swap | 2.5, 3 | 0 | 0.3 | 20 |
| orbit | 3.5, 10 | 0 | 0.5 | 30 |
| decoy | 4.0, 5 | 0 | 0.4 | 30 |
| familiar | 8.0, 6 | 0 | 0.5 | 40 |

- **Modifiers:** `cooldown_mult` becomes `wind_down_mult` with the same values (faster 0.75, short_delay 0.5, bigger 1.15, deflect 1.2, possess 2, pull 3).
- **Player staffs** (crystal, curl, moon, star): `wind_up` 0, `cooldown` 0.15. A lone bolt then fires every 0.5 s (today 0.4); four bolts fire 0.35 s apart, then wait 0.5 s.
- **Dev staff:** `wind_up` 0, `cooldown` 0.
- **Enemy staffs:** `wind_up` 0.5, `cooldown` 0; their pace stays their AI's rest and their mana.

## The charge card

A new modifier, `charge` (draft: +2 s wind-up, 4× damage). It follows the card rules with no special case: a cost alone is no effect (`StaffCompiler`, "costs are no effect"), so charge on a dash, swap or teleport is wasted and greyed out. At 2 s for 4× it deals less damage a second than plain bolts (4 per 2.35 s against about 6.7); it is for one big hit (pierce, blast, an on-hit payload). 1 s for 3× is the fallback if it feels weak.

## Parts

Each part is one PR; in this order.

1. **T1: the numbers.** `StaffBase`: `wind_up`, `cooldown`; `cast_delay`, `recharge` gone. `FormBase.cooldown` → `wind_down` (`wind_up` stays). `ModifierBase.cooldown_mult` → `wind_down_mult`, new `wind_up_add`. `MulticastBase.cooldown` → `wind_down`. `CompiledCast.delay` → `wind_up`, `wind_down`, `ends_cycle`; payloads add nothing; the staff's cooldown after the cycle (`Spells._after_cast`). Every `.tres` renamed with today's values; wind-ups still run in swing and slam. The validator's ranges, `staff_view`, the builder's numbers, DESIGN.md's staffs line, M2-staffs.md's "Numbers of a cast", "Staffs" and "Mana" (also out of date on one shared pool).
2. **T2: the wind-up in Spells.** A cast waits in its staff's row (`_wind_due`) and leaves from where the caster holds the staff along its aim then (`set_aim`); downed or rebuilt cancels it. Swing and slam lose their own wind (`SWING_CHAIN` gone). Payload wind-ups delay their launch. Staff poses wind over it. `Caster`: mana checked at the press, paid at the release; `Spells.is_winding` and `cooldown_left` (the wind-up while it winds) for the HUD and the AI. Two staffs may wind up at once.
3. **T3: skipping.** An unaffordable cast is skipped (the cursor moves on, a fizzle cue, the cooldown past the cycle's end). `cast_ready` and `next_cast_*` read the cast a press would fire.
4. **T4: the retune.** The table above, the staffs' numbers.
5. **T5: the corner panel and the builder.** The staff row's bar shows the wind-up, the wind-down and the cooldown (dashed); an unaffordable cast shows dimmed. The builder's plan shows each cast's wind-up and wind-down and the cycle's time.
6. **T6: enemies.** Enemy staffs' `wind_up`; the telegraph read from the caster's wind-up; the brain's `WINDUP` timer, `windup_scale` and the aim lock gone, the AI aiming through the wind-up. A chill stretches a wind-up and a freeze holds it, for every caster (`Spells.hold_winds`); a new driver cancels a body's winding casts.
7. **T7: the charge card.**

Proposed by the owner while T6 was built (2026-11-06), not yet planned:

- **T6b (proposed, after T7): the telegraph as a cue.** A card names a `wind_cue` (a lane, a ring where a slam lands, a circle round a nova), played for the wind-up's length and following the aim, only for a caster not on the players' team; `CreatureLook` drops its own line.
- **T8: the timer winds up** (owner, 2026-11-06: "Should the Timer trigger also just have a wind_up and no fixed delay? This way it can be altered with other cards aswell?"). Every trigger has a `wind_up` (`interval` is gone): its payload winds up that long where it fired, before the payload's own cards'. A timer ticks over and over, each tick its payload's whole wind-up, then the payload leaves at once; so a `charge` in its payload slows it. The new multicast `quicken` (`MulticastBase.wind_up_mult` 0.5) halves the wind-up of the group it is read into, a charge's or a timer's tick (a group-level card, as multicasts are, so it also shortens the trigger's own share); it is wasted where its group winds up nothing. The first tick still comes at half a short carrier's life when that is sooner.

The native kernels are untouched: cast timing lives in `Spells` (GDScript). Pending launches are already sim state (core/sim/README.md).

## Questions

Answered by the owner on 2026-11-06 ("Fine" to each pick):

1. **The starter staffs' cooldown:** one value for all four, 0.15 s to start. Different staffs are M3's.
2. **Allies holding a staff with a wind-up** (a possessed enemy, a puppet) wind up too: the wind-up is the staff's. The telegraph is drawn for the enemies' team only, keeping "enemies telegraph, allies don't" as a look rule.
3. **An enemy dodge** on a staff with a wind-up waits for it, so an enemy that dodges holds its dash on a staff with `wind_up` 0 (enemies may have several staffs).
4. **Walking while winding up** costs nothing; if `charge` feels free, a move speed while winding up (on the card or the staff) is the lever, after a playtest.

Later (owner, 2026-11-06):

- **Payload mana paid when the payload fires,** not at the cast: wait.
- **Cards that change the staff's cooldown:** wait.
- **Limited uses** for the strongest cards: "We might implement this later in some form".

## Self-critique against docs/DESIGN.md

- **Deep, combinable spells:** combining no longer costs tempo out of proportion, and skipping lets a dear card share a staff with cheap ones. The cycle-then-cooldown rhythm rewards a full staff.
- **Every death is understandable:** every enemy cast warns for as long as its data says, and a telegraph always comes true.
- **Nobody waits for another player:** nothing here makes a player wait on anyone.
- **Risk:** mana carries the big cards alone now; a wait for regen is a lockout shown on a bar instead of a timer. Dash's mana needs the most care: a dodge that fails for mana feels worse than one on a visible cooldown.
