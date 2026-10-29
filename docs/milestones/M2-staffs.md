# M2 rework: staffs (the spell system, second design)

**Goal:** replace the fixed spell template (form → element → up to three modifiers → trigger, under a complexity budget) with **staffs whose cards are read in order**, in the spirit of Magicraft and Noita's wands. Every arrangement of cards is legal and does something, so players find interactions nobody designed (docs/DESIGN.md, pillar 1, and "Discovery"). The builder becomes a row of slots you put cards in.

**Status (2026-10-26):** the owner's verdict on the second C2 checkpoint (#264) is **pivot**, worked out with the owner in an owner session over six rounds. This document replaces the parts of [M2-spell-system.md](M2-spell-system.md) that it names; everything else there (the projectile manager, statuses, reactions, the validator, the bots, the clip recorder) still stands. M2 is not closed: its done-when is replaced by the one below, and C2 is asked again at the end.

**Why:** the owner found the builder hard to use, the template locking builds out, and adding components the only way to get deeper builds.

**Done when:**

1. Every task in "Parts" below is merged, and `ci/build/build.sh --quick --tests` is green.
2. Every card has a test, a lore line, an icon, a look, a sound id, and appears in at least two combo files that pass.
3. The 4-bot smoke test passes with bots that build random staffs, and the fuzz run (random staffs, part D1) has no error line.
4. The stress benchmark runs with built staffs; over budget it warns (never fails), and the warning names the costliest staffs.
5. The owner has played the sandbox on `/preview/`, and C2 has a verdict.

## Summary of the rules

- Each wizard has **four staffs, one per shoulder button** (owner, 2026-10-26): RB, RT, LB and LT on a gamepad (staffs 1 to 4); Space (or Shift), left mouse, right mouse and Q for P1 on keyboard and mouse. There is no separate dodge or cast: staff 1 (RB) starts with a `dash` card, staff 2 (RT) with `fire · bolt`. The face buttons work the menus: A accepts, B goes back (in play it opens the builder), X is a menu's second action; Y is free for now. Start opens the pause menu.
- A staff is a row of **slots**. The player puts **cards** in any order. A cast reads the cards left to right with the rules in "Reading a staff".
- **No build limits.** The complexity budget, the shot, modifier and depth limits and the number clamps go. The builder refuses nothing except a full staff. What stays are the engine's own safeguards, which never shape a build (see "Engine safeguards"). If the stress benchmark later shows a staff that freezes the game, a limit, a mana cost or a cheaper effect is decided then (owner, 2026-10-26: "They can be added later if we want to / need to").
- **Self-harm is always on.** A wizard's own spells hurt them (damage, knockback, statuses). Hurting other players stays the friendly-fire option, off by default.
- **One mana pool per wizard**, used by all four staffs. Cards made sustained by `hold` reserve part of it while they are on.
- **The input buffer** (`INPUT_BUFFER`, 0.15 s) applies to every staff button: a tap while the staff is not ready is remembered and fires as soon as it is. Holding a button keeps casting whenever the staff is ready.
- **Projectiles are small** (a 3–5 px core and a short trail) and get their look in **layers** from their cards.
- **`dev` and `preview` builds start in a sandbox** with 20-slot staffs, the full bag and a training dummy. `nightly` and `stable` builds play the normal game with 4-slot starter staffs.

## Cards

A card is a `.tres` on one of five classes in `core/base/`, in its own folder under `content/spells/<kind>s/`. The four existing classes stay, with new fields (part A3); `MulticastBase` is new.

| Kind | Class | Role | Cards (new in bold) |
| --- | --- | --- | --- |
| Carrier (14) | `FormBase` | Ends a group: something leaves the caster | bolt, beam, nova, rune, orbit, **dash, teleport, hook, swap, wall, rain, fissure, decoy, familiar** (the boomerang carrier became the `return` modifier, owner 2026-10-27) |
| Modifier (27) | `ModifierBase` | Attaches to the next carrier | split, pierce, homing, chain, bigger, faster, **shield, blast, hold, recoil, bounce, echo, linger, heavy, siphon, overcharge, sticky, magnet, ghost, spiral, mirror, growth, relay, sniper, return, slow, arc** |
| Infusion (6) | `ElementBase` | Attaches to the next carrier; several may | fire, frost, storm, void, lightning, **mend** |
| Trigger (9) | `TriggerBase` | Attaches to the next carrier; the group read after that carrier is its payload | on hit, on expire, timer, **on block, on kill, on cast, on wall, on hurt, on reaction** |
| Multicast (4) | `MulticastBase` | Pulls more carriers into the same group | **double, triple, scatter, burst** |

58 cards: the 19 that exist and 39 new ones. Pillar 1 says "few components, many combinations"; the per-card tests and the emergent combo report (part D1) are there to find cards that add little, and such a card is cut, not tuned.

`complexity` stays on `SpellComponent` for the validator's range check but nothing reads it any more; part A4 removes the budget. Ids stay unique across all kinds.

**Every card has an end point:** where its effects happen once it is done. A shot's end point is where it hits or expires; a dash's, teleport's and hook's is where the wizard arrives; a decoy's where it dies; the caster's is the caster. `blast`, `on expire` and the look of an ending all use it.

**Who casts a card** (owner, 2026-10-27: "this should not be a special case, but follow the core spell logic"): a staff's own cast is cast by the wizard; a payload is cast by the shot whose trigger fired it, while that shot still flies, and otherwise by the point it fired from (a shot spent on its hit, an expiry, a beam, a rain, an entity); an `on cast` payload by its carrier's caster. Every card that names the caster follows this one rule: dash, teleport, hook, swap and recoil move it (a payload dash makes its shot lunge forward; with only a point there is nothing to move), and orbit, familiar and a returning shot circle it or come back to it (`timer · bolt · orbit` is a ring round the flying bolt, `on expire · bolt · orbit` one round where it ended).

**Live beams** (owner, 2026-10-27): a beam is a carrier that lives its `lifetime` like a shot (0.3 s, one cast cycle of the starter staff, so held fire keeps a beam on with no gap; `hold · beam` stays on until switched off). It follows its caster while it lives (the wizard's aim, or the shot that fired it), hits what is on it at once and then every `SpellLimits.BEAM_TICK` (0.15 s), and a homing beam bends along a curve onto the nearest target within 45 degrees of its aim. Homing stacks by multiplying (owner, 2026-10-27): each homing card after the first turns a shot 1.5 times faster and widens a beam's bend 1.5 times (`SpellLimits.HOMING_STACK`), up to all the way round (owner, 2026-10-29: no cap). Multipliers (damage, speed, size, delay, mana) always multiplied, and since rules R1c (2026-10-29) the factor behaviours too: heavy's knockback (two cards ×16) and growth's rate (`StaffCompiler.stacked`, `MULTIPLIED`); counts (chain jumps, bounces, pierce, shields) add. Its `blast` and `on expire` happen where it got when its life is over. `bounce · beam` turns at walls (owner, 2026-10-29): it reflects off the wall face, once per bounce, and goes on for the length it has left, hitting what is on every leg.

**Two carriers carry a payload of their own:** `rain` and `familiar` read the group after them as their payload, the way a trigger does (rain drops it on the aim point; familiar casts it). If one of them also has a trigger, the carrier's own payload is read first, then the trigger's.

### What each new card does

Numbers are first guesses for the card's own task to set. Examples are written in slot order: modifiers, infusions and triggers come **before** their carrier, a payload **after** it.

**Carriers**

| Card | Does | Two interactions |
| --- | --- | --- |
| dash (Short Dash), medium dash, long dash | The wizard dashes along the move direction (today's dodge, **without** the invulnerable window) a fixed 48, 80 or 128 px (`ray_length`); its speed only sets how long that takes, so `faster` arrives sooner, never farther (owner, 2026-10-27). 2 s delay each. End point: where the dash ends | `shield · dash` blocks one hit during the dash; `blast · dash` explodes at the end |
| teleport | Blink a fixed `ray_length` along the aim, stopping before walls. End point: the arrival | `blast · teleport` arrives with an explosion; `on expire · teleport · nova` rings out on arrival |
| hook | A shot that pulls the caster to where it hits | `shield · hook` is a safe gap-closer; `blast · hook` charges in with a bang |
| swap | A shot that trades places with the target it hits | an escape through an enemy; `frost · swap` leaves a chilled target where you stood |
| wall | A line of still shots across the aim | `shield · wall` stops enemy shots; `fire · wall` is a burning fence |
| rain | Its payload falls on the aim point after a telegraphed delay | `rain · nova`; `rain · frost · nova` freezes an area from above |
| fissure | A crack along the ground that hits everything on its line | `on hit · fissure · nova` sets off a nova on every enemy in the line; `bounce · fissure` turns at walls |
| decoy | A still copy of the wizard that enemies target. End point: where it dies | `blast · decoy` is an exploding decoy; `on expire · decoy · nova` |
| familiar | A small helper that orbits the caster and casts its payload at the nearest enemy every second | `hold · familiar · bolt` keeps it; `familiar · mend · bolt` is a healer |
| swing | Melee (owner, 2026-10-29; see "Phase I"): the staff sweeps a 90° arc in front of its tip, about 24 px, hitting every body in it. No mana, a short delay, strong knockback. End point: the end of the arc | `shield · swing` is a parry; `heavy · swing` bats enemies into walls |
| slam | Melee (owner, 2026-10-29; see "Phase I"): the staff rises and slams the floor in front of its tip, a shockwave ring that hits every body in it and throws them outward. No mana, a longer wind-up and delay than swing. End point: the impact | `burst · swing` then `slam` is a combo string; `on expire · swing · slam` ends a sweep in a slam |

**Modifiers**

| Card | Does | Two interactions |
| --- | --- | --- |
| shield | The carrier blocks one hit (stacks: three shields block three). On a self carrier (dash, teleport) or on the caster it is a barrier on the wizard for the carrier's duration; on a shot it blocks enemy shots | `shield · dash`; `shield · orbit` is a ring of blockers |
| blast | The carrier explodes at its end point (radius damage, hit kind `burst`). On the caster it explodes on the caster | `blast` alone is self-harm a relic can turn around; `blast · bolt` is a rocket |
| hold | Makes the carrier sustained: it stays until switched off, and reserves its mana from the pool while on (see "Mana") | `hold · shield · orbit` is a barrier ring; `hold · fire · orbit` is a permanent fire ring |
| recoil | Pushes the caster back when cast | `recoil · blast · bolt` is a rocket jump; movement on an attack staff |
| bounce | Bounces off walls; `on expire` fires only after the last bounce | `bounce · split · bolt` fills a room; `bounce · return · bolt` |
| echo | The carrier fires again 0.3 s later at half damage | doubles triggers; `echo · teleport` is a double blink |
| linger | The shot stops mid-air for 1 s, then goes on | traps; `linger · nova` is a delayed ring |
| heavy | Slower, much more knockback; an enemy knocked into a wall takes damage | sets up hex; `heavy · dash` is a shoulder charge |
| siphon | Hits refund mana | feeds `hold`; pays for big multicasts |
| overcharge | Double mana cost, more damage | the opposite of siphon |
| sticky | The shot sticks to the target it hits and expires there | `sticky · blast · bolt` is a sticky bomb; `sticky · on expire · bolt · nova` plants a nova on a boss |
| magnet | The shot pulls enemies toward its path | `magnet · bolt · blast · bolt`, a pull then a blast; `magnet · void · bolt` |
| ghost | Passes through walls | `ghost · homing · bolt` hunts through rooms; never sets off `on wall` |
| spiral | Flies in a sine wave | covers an area; `spiral · split · bolt` is a curtain |
| mirror | Also fires the carrier backwards | guards your back; `mirror · recoil · bolt` cancels the push |
| growth | Grows the further it flies (x2 a second, up to 4x): a wider hit circle, the same damage (owner, 2026-10-27; damage is overcharge's) | rewards range; `growth · linger · bolt` is a huge slow orb; `growth · pierce · bolt` sweeps a wide lane |
| relay | When the shot hits an actor it takes on the infusions of that actor's last cast (owner, 2026-10-28: any actor, since shots no longer pass teammates) | your bolt plus a teammate's frost, or an imp's fire stolen off the imp |
| short delay | Halves the carrier's delay for 25 % more mana (owner, 2026-10-27; named after the builder's "Delay", so it is not mistaken for `faster`) | `short delay · dash` dashes again sooner; `short delay · beam` keeps a beam on with a slower staff |
| sniper | The carrier keeps a quarter of its staff's spread (`spread_mult` 0.25, a factor; owner, 2026-10-27). Free: the dev and starter staffs aim true, so it waits for staffs with spread (M3) | `sniper · pierce · bolt` lines up a crowd; `sniper · double · bolt · bolt`, one true bolt and one wild |
| return | Flies out for half its life, then back to its caster (owner, 2026-10-27: a modifier, not a weak boomerang carrier). Wasted on a carrier that does not fly out (beam, rune, orbit, dash) | `pierce · return · bolt` hits twice; `blast · return · bolt` explodes on you unless you move; `spiral · return · bolt` is a wavy loop |
| slow | A third of the speed for three times the life, so it crawls about as far (`lifetime_mult`, owner 2026-10-27) | `slow · lightning · arc · bolt`, the lightning orb; `slow · growth · bolt` grows three times as long |
| arc | While the shot lives it zaps the nearest enemy within 60 px twice a second, at half its damage, with its infusions. A zap is a hit: it sets off `on hit` and chains (owner, 2026-10-27; see BACKLOG for making that a staff mod or relic later). Wasted on a carrier that is not a shot in the air (beam, dash) | `slow · lightning · arc · bolt` is a lightning orb; `arc · orbit` a ring of zappers; `arc · on hit · rune · nova` a trap that rings out at whatever comes near |
| deflect | Shots of another team that touch the carrier turn around and become its caster's (owner, 2026-10-29; see "Phase I"). Works on every carrier | `deflect · swing` bats shots back; `deflect · orbit` is a reflecting ring; `deflect · wall` a mirror wall |

**Infusion:** mend: hits heal wizards (whatever the friendly-fire setting) and do almost nothing to enemies. `mend · blast` is a self-heal burst; `mend · chain · bolt` jumps a heal through the party.

**Triggers** (each fires the payload from where the event happened)

| Card | Fires when | Two interactions |
| --- | --- | --- |
| on block | a shield on the carrier absorbs a hit | `shield · on block · dash · nova` is a counter |
| on kill | the carrier's hit kills | chains through crowds; `on kill · split · bolt · bolt` snowballs |
| on cast | at once, from the caster | `on cast · teleport · rune` leaves a rune where you stood |
| on wall | the shot hits a wall | `bounce · on wall · bolt · nova`, a nova at every bounce |
| on hurt | the caster takes damage while the carrier lives (use with `hold`) | `hold · on hurt · orbit · nova` is a thorns aura |
| on reaction | the carrier's hit causes a reaction | `on reaction · frost · bolt · fire · nova`, reactions that start more reactions |

**Multicast:** double (2 carriers in one group), triple (3), scatter (3, in random directions, seeded per cast), burst (the group fires 3 times in quick succession).

## Reading a staff

The compiler (`Spells.compile_staff`, part A4) turns a staff's slots into its **cycle**: the list of casts the staff makes before it recharges. Reading is deterministic, so the cycle is computed once per build change, and the builder shows it.

1. **A cast reads one group** starting at the staff's cursor (0 after a recharge). A group wants **one carrier** (a staff's `draw`, 1 for every staff for now).
2. Cards are read left to right; empty slots are skipped.
   - A **modifier or infusion** is kept for the next carrier of this group.
   - A **multicast** card adds its `extra_draws` to the carriers this group wants (double adds 1, triple 2, scatter 2); burst marks the group to fire 3 times.
   - A **trigger** is kept for the next carrier. A second trigger before the same carrier is wasted.
   - A **carrier** takes every kept modifier, infusion and trigger. If it has a trigger (or is `rain` or `familiar`), its **payload** is read right now, as a new group by these same rules; the payload's cards are part of this cast. Then this group wants one carrier fewer. When it wants none, the group ends.
3. **Wrap-around:** reading past the last slot goes on from the first. If any reading in the cast (payloads included) wrapped, the staff recharges after the cast.
4. **Use once:** a card already read in this cast ends the current group where it is. This is what keeps wrap-around from looping forever, and why every staff's cycle is finite.
5. **The fallback carrier:** if a group ends with modifiers or infusions kept and no carrier to take them, they land on a fallback carrier: **the caster** for the cast's own group, **the payload's origin point** for a payload (an instant hit there, radius 8 px). `blast` explodes there, `fire` burns whatever is there, `shield` gives the caster a barrier (on the caster only). Cards that mean nothing there (homing, pierce) are wasted. A kept trigger with no carrier is wasted.
6. **Wasted cards** do nothing and are shown greyed out in the builder's cast plan, with the reason. They are never refused.
7. **After a cast** the cursor moves past the last card the cast read, payloads included (a payload is read inline, right after its carrier, so that is the furthest card read). If the cast wrapped, or no card is left to the right, the staff recharges and the cursor goes back to 0.
8. **Multicast counts per group:** a double in a payload wants two carriers for that payload only; the outer group's count is its own. Burst fires the same compiled group 3 times; nothing is read again.

A modifier or infusion affects **only the next carrier**, not every carrier of a multicast: `double · fire · bolt · bolt` is one fire bolt and one plain bolt. One card, one target, so the cast plan can draw one arrow per card.

**Examples** (`·` separates slots; each is a test row in A4):

- `fire · bolt · frost · nova`: cast 1 is a fire bolt, cast 2 a frost nova, then recharge.
- `blast · bolt · blast`: cast 1 is a blasting bolt. Cast 2 reads the last `blast`, wraps to slot 1 (`blast`, unused in this cast), then the `bolt`: a bolt with two blasts. It wrapped, so the staff recharges.
- `blast`: an explosion on the caster, every cast.
- `double · fire · bolt · on hit · bolt · frost · nova`: a fire bolt and a bolt, cast together; the second one, on hit, fires a frost nova.
- `double · on hit · bolt · nova · bolt`: the first bolt fires a nova on hit; the payload ends after the nova; the outer group still wants one carrier, so the last bolt joins the cast. One cast, then recharge.
- `on hit · bolt · blast`: the payload is a lone `blast`, which lands on the payload's origin: the bolt explodes where it hits, not on the caster.
- `on hit · bolt`: the payload wraps to slot 1 (`on hit`, already used), so it is empty and the trigger is wasted. It wrapped: recharge.
- `bolt · on hit`: cast 1 is a bolt. Cast 2 reads `on hit`, wraps to the `bolt` (unused in this cast) which takes it; the payload wraps to `on hit` again, used, so it is empty and the trigger is wasted. Recharge.
- `shield · on block · dash · nova`: a dash with one shield; when the shield blocks a hit, a nova fires from there.

### Numbers of a cast

- **Mana:** the sum over every carrier in the cast, payloads included, of its `mana_cost` times the `mana_mult` of its modifiers, plus each multicast card's `mana_cost`. Paid at the cast.
- **Delay:** the staff's `cast_delay` plus every carrier's `cooldown` times the `cooldown_mult` of its modifiers. When the staff recharges, its `recharge` is added.
- **Damage, speed, radius, shots, pierce:** the carrier's numbers, then each infusion's `damage_scale`, then each modifier in slot order, as today. No build limit clamps them; the ranges in each class's `ranges()` stay for the validator.
- **Several infusions:** the hit carries all of them. The first one's status lands first; each later element then reacts with it through the reaction table, so `fire · frost · bolt` thaws on its own hit. The shot's tint and shape come from the first infusion.

## Engine safeguards

These are not build rules: they keep a frame from running away, never refuse or change a build, and are documented in `core/spells/limits.gd` and `core/projectiles`.

- **The projectile pool** (500 on web, 3,000 on desktop) is the pre-allocated buffer every shot lives in. When it is full, the oldest shot **of the player who owns the most** is dropped, so one player's huge cast eats its own shots first, not a teammate's. One cast never spawns more shots than the pool holds.
- **Per-step work caps** (held spells fired and chain jumps per player per physics step, ray hits per step) stay: extra work in that step is dropped, never queued, so a cascade cannot snowball across frames. They are set high enough that no normal staff meets them, and the stress run reports when one is met.
- **Removed:** `MAX_COMPLEXITY`, `MAX_SHOTS` per cast, `MAX_MODIFIERS`, `MAX_DEPTH`, `MAX_TIMER_FIRES`, `MAX_CHAIN_JUMPS`, `MAX_DAMAGE` and the speed, radius and pierce clamps. Payload depth is bounded by the staff's slots (use once).

## Staffs

`StaffBase` (`core/base/staff_base.gd`, part A3) is a `.tres` in `content/wizard/staffs/<id>/`:

| Field | Meaning | Range |
| --- | --- | --- |
| `slots` | Number of card slots | 1–64 |
| `draw` | Carriers one cast wants | 1–4 |
| `cast_delay` | Seconds added to every cast's delay | 0–2 |
| `recharge` | Seconds added when the staff recharges | 0–5 |
| `spread` | Degrees a shot may leave off its line, either side, at random (seeded per cast); the carriers of a multicast leave along one aim and only this sets them apart (owner, 2026-10-27) | 0–45 |

- **`starter`:** 4 slots. Used by `nightly` and `stable` builds.
- **Spread:** both staffs aim true (0). Later staffs (M3) get spread, at random or high and upgradable to lower; a modifier's `spread_mult` scales it for the next carrier (Sniper).
- **`dev`:** 20 slots, short delay and recharge. Used by `dev` and `preview` builds. The slot count is one field in `content/wizard/staffs/dev/dev.tres`.
- **Start cards:** A `dash`; X `fire · bolt`; Y and B empty. The bag holds every card until M3's rewards fill it.
- **The build channel** comes from `BuildInfo.channel()` (`core/base/build_info.gd`), which `ci/build/build.sh --channel` already writes (`preview.yml` passes `preview`). No owner change is needed.
- Every staff of a player has its own cursor, delay and recharge; they share one mana pool. Holding two buttons casts both staffs.
- Staff customization (found staffs, staff types) is M3 (rewards, staffs).

## Self-harm and hits

- Every hit, the caster's own included, goes through `gameplay/combat`. Today a wizard is never hit by their own shot (`core/projectiles`); part B1 changes that: a shot may hit its caster **once it has left the caster's hitbox** (a per-shot flag, set the first step the shot no longer overlaps the caster). Anything centred on the caster (blast or a nova on the caster, reactions) hits at once.
- **Statuses on wizards** are new: burn, chill and freeze, shock, hex and static get a version for wizards in `combat`. A downed wizard takes none.
- **Hit kinds:** every hit carries a kind: `shot`, `ray`, `burst`, `reaction`, `status`, `heal`. A relic (M3) such as "explosion immunity" matches a kind.
- **Area hits:** `blast`, the payload fallback and later relics ask combat for an area hit with `area_hit_requested`; combat applies it to every enemy and wizard in the circle (the caster included).
- **Fairness** (DESIGN.md, "every death is understandable"): a self-hit has its own flash, shown on the hit's frame, and a wizard downed by their own spell is told so ("downed by your own Blast").
- **Shield charges** are per carrier: a shot with three shields blocks three enemy shots, a dash with one blocks one hit on the wizard.
- **Feel:** every hit kind has a default flash, hit-stop and sound in Feel (B3), so a new card feels like something before it has its own sound. A card's own sound is an id (`<card id>`), silent until its `.ogg` exists, like the reactions.

## Mana

- One pool per wizard (`gameplay/player` keeps it, as today), shared by all four staffs.
- `hold` reserves the held carrier's mana: the pool's usable maximum shrinks by it while the carrier is on.
- **Switching off:** pressing a staff's button while any of that staff's held carriers is on switches them all off and frees their reservations; that press casts nothing. The next press casts normally. A held carrier also ends (and frees its reservation) when its shot ends for any reason, and **editing a staff switches its held carriers off**, so a build change never leaves a stale reservation or an orphaned sustained shot.
- `siphon` refunds mana on hits through an event (`mana_refund_requested`), so `core/spells` never writes the player's numbers.

## The builder

The aim is a builder each player can use quickly and without help, in their own corner with four players on screen. Scrolling panels are allowed where they make that easier; they are not a requirement (owner).

- **Four staff tabs**, labelled with their button glyphs; LB and RB switch.
- **The slot rows** of the shown staff (20 slots wrap into rows) and **the bag** below.
- **Pick and place:** A picks a card up and places it (swapping if the slot is taken); X sends a card back to the bag; B cancels. P1 can also drag with the mouse.
- **The cast plan strip** under the slots: brackets each cast of the cycle, draws a link from each modifier or infusion to the carrier it affects (or to the fallback), greys out wasted cards with the reason, and reads in plain words: *Cast 1: fire bolt and bolt; on hit: frost nova · Cast 2: beam · recharge 0.6 s*.
- **Live numbers** per cast (damage, mana, delay) and the card's lore line.
- **A name for every spell** (owner, 2026-10-26: "generate a name for the spell dynamically ... a long funny convoluted name, which is funny to try and read out loud"): `Spells` builds a name for each cast from its cards, deterministic (the same cards always give the same name), original words only (no names from other works), growing with the build: a plain bolt is "Bolt", `double · fire · frost · bolt · on hit · nova` is something like "Twice-Thawing Firefrost Bolt of Sudden Novas". The builder shows the names (part E1); a spell's name is also what a staff code (D2) and the emergent combo report (D1) call it.
- **The full builder at any time,** in waves too (owner, 2026-10-26: "The quick action is not needed. A full builder is always preferred"). There is no quick view and no "Bag" drop in the overlay; a player who builds during a wave stands still and can be hit, as in any menu.
- The HUD only shows what events say: `Spells.staff_view(...)` returns plain values (as `builder_view` does today), and the HUD sends intent events.
- **The radial builder** (owner, 2026-10-26; the default builder, with the list builder still reachable from the pause menu's Sandbox page in `dev` and `preview` builds): B taps it on and off. The bag's cards sit on a ring, every card grouped by kind with a coloured arc, or one kind at a time flipped with the d-pad (a switch on the same page); any number of cards fits, tiles shrinking to marks. The right stick points at a card: it pops out, the pad rumbles briefly (only on a card, never a gap) and the ring's middle shows its name, kind and numbers; letting go of the stick lets it go, and the middle shows the staff's numbers again (owner, 2026-10-27). The left stick moves a marker through the shown staff's slots, where the pointed card shows faded; the cards each cast of the cycle reads share a frame, every other cast in the other shade, so what fires together shows while building, and while a card is pointed at the slots show the staff as RT would leave it, frames included (owner, 2026-10-27). RT puts it in and moves the marker on (a card already there is pushed right with the rest, or replaced: a switch; a full staff refuses a push); LT takes the marked card out, and past the last card takes the last one out and steps back (an undo); holding Y clears the staff (a red frame fills, then every card fades at once); LB and RB switch staffs. Under the slots: the mana of the staff's dearest cast as a share of the wizard's mana (red with "!" above 100 %: it cannot be cast), the cycle's damage and time, and what RT would make of each. A card the player has several of shows the count, and a higher level its level, once the bag has them (M3).
- **The staffs on the corner panel** (owner, 2026-10-27: "The PX Staff X line should be removed. The PX is redundant. The Staff X should be replaced by 1-4 wands under the mana bar. They should visually show cooldown and the cast sequence of a wand, to help with identifying errors in the wand build."): under the mana bar, one row per staff with cards: its button glyph, then its cast sequence as small card icons in read order, framed per cast, the next cast in gold, wasted cards greyed and struck through, "+N" past the row's width, and a bar for the delay (dashed during the recharge). The sequence comes from `staff_changed`; the next cast and the delay left are read each frame from `Spells.cast_index` and `Spells.cooldown_left` (details in `hud/README.md`).

## The look of a shot

- **Small and hot, with a long tail and a glow** (the owner, 2026-10-27, replacing "a 3–5 px core with a 2–3 px trail"): a 3 px white-hot core (a bigger shot's grows a pixel each side per zoom), a tail of about 48 px whose pixels cool from white-hot to shadow and fray at its end, and a soft glow in the shot's colour round both. The tail follows the path: an orbit shot's bends round its circle, a homing or spiralling shot's with each turn. The colours are the palette ramp of the first infusion's tint; a plain shot's are its player's.
- **From the shot's cards:** the **core** from the carrier; the **player colour** in a quarter of an infused shot's tail pixels, and all of a plain shot's; a particle style per **infusion** (lightning throws sparks and draws a jagged tail, fire drops embers that drift up, frost leaves flecks and a longer tail, void pulls pixels in round a dark heart, storm blows gusts back and sways its tail, mend shows green motes); some **modifiers** add one (bigger glints, pierce streaks and lengthens the core, blast bursts sparks out, shield's sparks orbit, homing weaves, hold glitters).
- **Every card shows, combined, by what the shot gives off** (the owner, 2026-10-26: "we need a system that can combine all of it", then "the bolts could stay pretty plain, but then emit/sparkle with different added effects" and "the tail of bolts should also emit from added effects randomly"; the first plan drew at most four layers round the core). The body stays plain; each look kind is a particle style; a shot keeps 4 + 2 per style particles alive (at most 12), each born at a random point of its tail with a style picked at random, so one card is a trickle and many a mix, never a crowd. The look is a set with one bit per kind, in the instance colour beside the player and the zoom (room for 24 kinds). Two cards with the same kind add nothing more.
- **No per-shot nodes or particles:** one shader draws the layers; sparks and embers come from one shared pool with a global count, and at the cap trails thin first. This is a visual budget under the effect quality setting, never a build rule.
- **Each card's look is data in its own `.tres`** (`look_layer`, an effect kind the shader knows), so a new card never edits the shader unless it needs a new effect kind. Feel's per-form looks (`cast_looks` in the Feel preset) move to card data the same way.
- **Player colours** (pillar 4) are checked explicitly: the clip sheet includes four players firing the same card, and each player's shots must be told apart at 1x.
- Player shots hit a little wider than they look; enemy shots (an enemy's spells, from phase F) a little narrower.
- Checked with the clip recorder: a sheet of every carrier with every infusion against `docs/STYLE.md`, and a four-player sandbox clip.

## The sandbox

- `dev` and `preview` builds start in the sandbox; "Play" in the menu still starts the normal game.
- One room of **two shooting lanes split by a wall** (owner, 2026-10-26: "two dummies separated by a wall (so like two shooting range lanes). One dummy for hitting and the other one fires back"); four 20-slot `dev` staffs per player; the full bag; the full builder at any time.
- **Training dummy** (end of one lane): never dies or moves; shows damage numbers, damage per second over the last 5 s, its statuses and reactions.
- **Shooting dummy** (end of the other lane): fires slow, telegraphed shots at the nearest wizard, for shields, blocks and self-harm.
- **The sandbox page** in the pause menu (owner, 2026-10-26: first "an entry in the start button menu - where the builder also is", then Start became the pause menu and B the builder): spawn an imp wave, reset the dummies. Friendly fire is in the pause menu's Settings, Gameplay, for every run; slow motion is not needed (owner). The actions change the room, never another player's choices or menus. *(Friendly fire and Enemy fire went in G3c: everything hurts everything, no setting. Kept as history.)*
- **Staff codes** (part D2): copy a staff as a short text code and paste one, so builds can be shared in Discussions. A code is only card ids, checked against the registry; nothing in it runs.

## Enemy staffs

The owner, 2026-10-27: "I actually want the enemies to have their own staff and fire spells. That way we can easily make new enemy types, by adding a new sprite and giving them a staff with some combined spell on it." Moved into M2 from "Later" (it was M3–M4) the same day. Built in phase F.

- **An enemy is a sprite and a staff.** `EnemyBase` gains a `staff` (a `StaffBase`), its `cards`, `max_mana` and `mana_regen`. The AI compiles the staff once per enemy type and casts it through `Spells.cast_staff` like a wizard; a new enemy type is a folder with a sprite, a scene and a `.tres`, and no code.
- **Player cards only.** There are no enemy-only cards: the imp becomes something like `fire · bolt` and its shot plays like that bolt, not like the old imp shot. Every caster-side card works on an enemy too (dash, teleport, hook, swap, recoil, decoy, familiar, shield, hold...), and the AI aims and uses them: it dashes toward or away from its target, teleports near a wizard, keeps a decoy between them.
- **Enemies pay mana like players:** a pool and a regen per enemy type, so a dear staff casts less often. The AI checks the next cast's cost (`Spells.next_cast_mana`) before it winds up.
- **One look for every spell** (the owner, 2026-10-27: the new style only, no separate enemy shot look): an enemy's spell is drawn by the shot shader exactly as a wizard's, with the **enemy ramp** where a player's colour would show (a plain shot's ramp, a quarter of an infused shot's tail, beams, effects). The enemy ramp is a new palette material, **Blight ochre**: shadow `#4d3f12`, base `#a68a2a`, light `#e3cf6b`, far from the four player colours. The old enemy look goes: the hostile batch, `imp_fireball.svg`, Feel's ember burst for enemy impacts.
- **The telegraph is the cast.** The windup starts only when the cast is ready (its delay nearly over and the mana there), so a telegraph is always a promise; it shows the next cast's reach and lane from its first carrier (a shot's speed × life, a beam's length), a pose and flash for carriers that are not aimed (nova, orbit), and rain's own marker. It is drawn in the shot look by its own small shader (`gameplay/ai/telegraph.gdshader`), not a `Line2D`.
- **Enemy spells on wizards** do everything a spell does: damage, knockback, statuses and **reactions** (the same reaction table as on enemies). Area hits (blast, fallbacks) take the caster's side: an enemy's blast hits wizards (decoys only through its shots), a wizard's hits enemies. Wizards react to every spell, a teammate's and their own included (one rule for every target, part F6).
- **Enemy spells on other enemies: a setting, off by default** (pause menu, Settings, Gameplay, "Enemy fire", beside Friendly fire). Off, an enemy's spells pass other enemies. *(Went in G3c: no fire settings, everything hurts everything.)*
- **Fair at any player count:** enemy shots hit a little narrower than they look (as before); enemies get a capped share of the shared runtime limits (beams, delayed firings) so they never take a slot from a player's spell; an enemy that dies drops its pending firings and holds, and its shots in the air fly on.
- **Under the hood** (parts F2–F5): a spell's caster is a player 0–3 or an enemy row 4 and up (`ENEMY_CASTERS`, 256 rows; an enemy opens one when it spawns and closes it when it dies). Events keep `NO_PLAYER` for an enemy's cast, so no area mistakes an enemy for a player; the tag names the row (see "Tags").

## Events

Added in part A3, so later parts in different areas don't all edit `core/events/events.gd`. Each has one sender.

| Event | Sender | Heard by |
| --- | --- | --- |
| `staff_change_requested(player, staff, slot, card_id)` | hud | player |
| `card_move_requested(player, from_staff, from_slot, to_staff, to_slot)` (`-1` staff means the bag) | hud | player |
| `staff_cards_requested(player, staff, cards)` (the whole staff at once; the radial builder) | hud | player |
| `staff_changed(player, staff, plan: Dictionary)` | player | hud |
| `staff_cast(player, staff, origin, direction)` | player | feel |
| `caster_move_requested(player, mode: StringName, to: Vector2, seconds: float, tag: int)` (dash, teleport, hook, swap, recoil) | spells | player, ai (an enemy's own row, F8c) |
| `caster_move_finished(player, mode: StringName, position: Vector2, tag: int)` | player, ai (an enemy's, F8c) | spells (the end point of dash, teleport, hook) |
| `target_move_requested(target: Node, to: Vector2)` (swap) | spells | ai |
| `area_hit_requested(player, position: Vector2, radius: float, tag: int)` | spells | combat |
| `entity_spawn_requested(player, kind: StringName, position: Vector2, seconds: float, tag: int, caster: int)` (decoy, familiar; `caster` -1 the wizard, a projectile slot, or -2 the point) | spells | ai |
| `entity_end_requested(player, tag: int)` (a `hold` switched off; added in B5) | spells | ai |
| `entity_ended(player, kind: StringName, position: Vector2, tag: int)` | ai | spells (a decoy's end point) |
| `familiar_cast_requested(player, position: Vector2, direction: Vector2, tag: int)` | ai | spells |
| `mana_refund_requested(player, amount: float)` | spells | player |
| `mana_reserved(player, amount: float)` | spells | player, hud |
| `shot_blocked(player, position: Vector2, tag: int)` (a shot's shield stopped an enemy shot) | projectiles | spells, feel |
| `shield_blocked(player, position: Vector2, tag: int)` (a wizard's barrier stopped a hit) | combat | spells, feel |
| `kill_landed(player, target, position, tag)` | combat | spells |
| `wizard_hurt(player, amount, position, tag, kind: StringName)` (`tag` 0 for contact damage; an enemy's spell hit carries its spell tag from part F6, so `SpellTag.caster_of` names the enemy row) | combat | spells, feel, hud |
| `reaction_landed(player, reaction_id, target, position, tag)` | combat | spells |
| `ally_passed(player, ally, position, tag)` | projectiles | spells |

`build_change_requested`, `spell_swap_requested`, `spell_changed`, `recipe_changed` and `active_spell_changed` are removed in part A6c, when nothing sends them any more. A kit that finds it needs one more event adds it in its own PR.

## Tags

A shot's int tag becomes **player (2 bits), staff (2), generation (3), node (9)**, with `SpellTag.FLAG` at `1 << 20`, so spell tags (1,048,576 and up) never meet the enemy attack tags of `gameplay/ai` (1,000 to 101,000). The node is the index of a compiled node in the staff's cycle: every carrier of every cast, payloads included, **and every fallback** (the caster or a payload origin); at most 512 per staff. Only the last cast of a cycle can wrap, so a cycle reads each card at most twice, and each group adds at most one fallback: a 64-slot staff stays under 512 (A4 found that 128 was not enough). The generation ring (8 per staff) and the rule that a shot in the air keeps its old numbers after a rebuild stay as they are (part A5).

**Enemy casters (part F3):** bit 16 marks an enemy's spell tag and bits 21–28 hold its enemy row (0–255), above the flag; the player field is then unused. `SpellTag.caster_of(tag)` gives the caster (0–3 a player, 4 and up an enemy row plus 4), `player_of` gives `NO_PLAYER` for an enemy's tag, and `is_spell_tag` accepts every tag below `1 << 29`. Tags stay below 2³¹, since combat keeps shield tags in a `PackedInt32Array`, and every spell tag stays above the AI's attack tags until those go (part F9).

## Working in parallel

The owner runs external Claude sessions next to the bot. The bot takes the first unchecked task under `## Queue` in `docs/NEXT.md` and reads no other section (`ci/smbot/nexttask.py`), so:

- **Two lanes in `docs/NEXT.md`:** `## Queue` is the bot's; `## Owner lane` is for the owner's sessions. The owner rebalances by moving lines between them.
- **Owner sessions** take the first task of the owner lane that no open PR names, and open a draft PR at once (branch `owner/<task-slug>`, the task name in the PR body as `Task: <name>`), so two sessions never take the same task. They follow AGENTS.md like any session. `tools/check.sh` treats a run without `--author` as an outside contributor's; owner sessions run `tools/check.sh --author peterdk31`.
- **External PRs do not edit `docs/NEXT.md`.** The bot's planning session ticks a task off when a PR with `Task: <name>` has merged.
- **Shared files are split first** (part A2): combos become one file each (`content/spells/combos/<id>.json`), every card folder lists its own assets in an `assets.json` beside them (the validator and the art test read `art/manifest.json`, `audio/manifest.json` and every `assets.json`), and no test keeps a hand-written list or count of cards. Lore was one file per card already (`content/story/lore/components/<id>.json`).
- **Foundation first, one PR at a time** (phase A). Then the **kits** (phase B), with the order below where two kits share files. Then **every card is one PR** that touches only its own files.
- **Cards are data only.** A card PR adds its folder (`.tres`, icon, look data, `assets.json`), its combo files, its lore file and its test file, and nothing else. If a card needs code, the code belongs in its kit: the card's session adds it to the kit's area in a separate PR first.
- **Kits may add fields** to the card classes for their own behaviours, in a block of their own at the end of the class; A3 adds the enum values and the fields it can foresee.
- A task whose parts have not merged yet answers `nothing_to_do` and is skipped for now (docs/PLAN.md, "Never stuck").

## Parts

Each part is one session and one PR, with tests, a green `tools/check.sh` and `ci/build/build.sh --quick --tests`. Main stays green between every two PRs.

### Phase A: foundation, in order

| # | Part | Delivers |
| --- | --- | --- |
| A1 | **The plan** | This document; `docs/DESIGN.md` (owner); `docs/NEXT.md` with both lanes; the later ideas in `docs/BACKLOG.md`; `docs/DECISIONS.md` |
| A2 | **Shared files split** | `content/spells/combos/<id>.json` (one combo per file) read by `test_combos`, the clip scenarios and `tools/atlas.py`; `assets.json` per folder read by the validator and `test_svg_art`; tests derive card lists and counts from the registry (`test_combos`'s `COMPONENTS`, the icon count, the drop-list length); the READMEs and AGENTS.md say so |
| A3 | **Card and staff classes, events** | `MulticastBase`; the enum values of the card classes (motions, behaviours, trigger events) and the fields A4 needs; `StaffBase` with the `starter` and `dev` staffs; every event above; the validator knows them; tests |
| A4 | **The staff compiler** | `Spells.compile_staff(cards, staff) -> CompiledStaff`: the reading rules, fallbacks, multicast, payloads, wrap-around, use-once, wasted cards with reasons, several infusions, the numbers of a cast, a plain description per cast; `Spells.staff_view` for the builder; every example above as a table test (slots in, casts out). Additive: the recipe compiler stays until A6c |
| A5 | **The staff runtime** | The new tag layout (`SpellTag`), with the recipe runtime moved onto it (a recipe becomes its cards, slot A and B become staffs 0 and 1), so there is one runtime; `Spells.install_staff(player, staff, compiled)` and `Spells.cast_staff(player, staff, origin, direction, mana)`; four staffs per player with their own cursor, delay and recharge; multicast groups; payload groups; fallback casts; `hold` on and off with `mana_reserved`, switched off on edit; tests with 4 players × 4 staffs and a rebuild mid-flight. The staff compiler never had the build limits; they leave with the recipe compiler in A6c |
| A6a | **Player and builder on staffs** | `gameplay/player`: four staffs, four cast actions (`cast_a`, `cast_x`, `cast_y`, `cast_b`) with the buffer each, the dash card (today's dodge without the invulnerable window: spells sends `caster_move_requested`, player moves and answers `caster_move_finished`); `dodge`, `cast` and `swap` actions gone, the overlay on Start (Back is `leave`); `gameplay/flow`: start staffs by channel; a first staff builder (four staff tabs, the slots, the bag, the cast plan as text; open at any time, waves included; the quick view and the overlay's "Bag" drop are removed) sending `staff_change_requested`, with B8 adding pick and place, links in the cast plan and mouse drag; bots send the new events; the 4-bot test green |
| A6b | **Combos and tests on staffs** | Every combo file as a slot list; the combo arena, clip scenarios, fuzz test and `tools/atlas.py` on staffs |
| A6c | **The old path removed** | The recipe compiler and API, the old events, the old `SpellLimits` constants; `docs/ARCHITECTURE.md`, the spells README and its examples rewritten for cards and staffs |

### Phase B: kits, in parallel after A6c

| # | Kit | Area | After | Delivers |
| --- | --- | --- | --- | --- |
| B1 | **Projectile kit** | `core/projectiles` | A6c | Shots that may hit their caster once they leave the caster's hitbox; bounce, ghost (through walls), spiral, return to caster, linger, growth, sticking to a target; shots that block enemy shots (shield charges, `shot_blocked`); the wall-hit flag for `on wall`; passing through teammates (`ally_passed`, and mend shots that hit wizards); the timing test still within budget |
| B2 | **Trigger kit** | `core/spells` | A6c | The seven new trigger events; echo, burst, scatter, mirror; relay; the payload carriers (rain's delay, familiar's casts via `familiar_cast_requested`); wall's line and fissure's ground line; the spells side of hook, swap, teleport and recoil; `area_hit_requested` for blast and fallbacks; siphon's refund; entity spawns for decoy and familiar |
| B3 | **Combat kit** | `gameplay/combat`, `gameplay/feel` | A6c | Self-harm; hit kinds; area hits; several elements per hit; statuses on wizards; shield charges on wizards (`shield_blocked`); heal hits; pulls (magnet, through the knockback velocity combat keeps); the heavy wall slam; `kill_landed`, `wizard_hurt`, `reaction_landed`; the self-hit flash and "downed by your own …"; feel defaults per hit kind |
| B4 | **Caster kit** | `gameplay/player` | B3 | Teleport, hook, swap and recoil moves, wall-safe, answering `caster_move_finished`; wizard statuses that slow or freeze movement; the mana pool with reservations and refunds |
| B5 | **Entity kit** | `gameplay/ai` | A6c | Decoy and familiar as pooled entities (`entity_spawn_requested`, `entity_ended`, `familiar_cast_requested`); the AI targets decoys; `target_move_requested` for swap |
| B6 | **Shot look** | `core/projectiles` (drawing), `art/vfx` | B1 | Small shots; the layer shader and its effect kinds; per-card look data (and Feel's per-form looks moved to card data); the shared spark pool; the player colour on the trail; the clip sheets. Before B7 |
| B7 | **Sandbox** | `gameplay/flow`, `content/rooms`, `content/enemies`, `hud/menus/` | B6 | B7a: the two-lane sandbox room, both dummies, the sandbox page (imp wave, reset dummies); `dev` and `preview` start in it (a focused Sandbox button above Play). Then the controls rework (owner): staffs on RB, RT, LB, LT, the builder on B, the pause menu on Start with the sandbox page and Settings, Gameplay, Friendly fire *(went in G3c)* |
| B8 | **Builder** | `hud/builder` | A6c | Pick and place (pick a card up, put it down, swapping; `card_move_requested`), links in the cast plan, live numbers, mouse drag for P1, and quicker moves than one control at a time (A6a's builder walks tabs, slots and bag in one line, so from the bag back to the tabs is many presses: left and right between tabs, slots and bag, or a jump); screenshots at 1 and 4 players; every slot reachable with the d-pad alone |

B1 and B6 both change `core/projectiles/projectile_manager.gd`, so B6 waits for B1. B3 and B4 both reach the wizard's movement and health, so B4 waits for B3. B7 adds its own folders in `hud/menus/`; B8 owns `hud/builder/`.

### Phase C: cards, one PR each, in parallel

A card task touches only its own folder (`.tres`, icon, look, `assets.json`), `content/spells/combos/<id>-*.json` (two combos), `content/story/lore/components/<id>.json` and `tests/content/spells/test_<id>.gd`. It starts when its kits have merged:

| Needs | Cards |
| --- | --- |
| A6c | double, triple, overcharge |
| B1 | bounce, ghost, spiral, linger, growth |
| Slow, return and arc kit (owner, 2026-10-27) | return, slow, arc |
| B2 | on cast, echo, burst, scatter, mirror, rain, fissure, wall |
| B1 + B2 | sticky, relay, on wall |
| B1 + B3 | heavy, magnet |
| B1 + B2 + B3 | shield, blast, mend, on block, on kill, on hurt, on reaction |
| B2 + B4 | teleport, hook, recoil, siphon, hold |
| B2 + B4 + B5 | swap |
| B2 + B5 | decoy, familiar |

C0 (after B6): the 19 existing cards get their look data and a second look at their numbers without the budget.

C0b (after C0): the later modifiers get their look data, the same way (owner, 2026-10-29).

### Phase E: extras the owner asked for along the way

| # | Part | Area | After | Delivers |
| --- | --- | --- | --- | --- |
| E1 | **Spell names** | `core/spells` (a namer beside the compiler), `hud/builder` | A6c | A name for every cast from its cards (see "The builder"): word lists per card in the card's own `.tres` (`name_words`, so a new card brings its words and edits no shared list), rules for multicast, triggers and payloads, `Spells.staff_view` gives each cast's `name`; the builder shows the names above the plan; tests that names are deterministic and grow with the build |

### Phase F: enemy staffs (owner, 2026-10-27)

Owner sessions, one PR each, in this order: F2, F3 and F4 may run in parallel; F5 after F3 and F4; F6, F7 and F8a after F5, then F8b, F8c and F8d (split from F8 while building it: one area each); then F9a and F9b; then F10. Before D3, so the stress run and the playtest see enemies that cast.

| # | Part | Area | Delivers |
| --- | --- | --- | --- |
| F1 | **The plan** | `docs/` | This section, "Enemy staffs", the tag layout, the READMEs' notes, `docs/DECISIONS.md` |
| F2 | **Enemy palette** | `docs/STYLE.md`, `core/projectiles` (shader) | Blight ochre in the palette table; the shader's fifth ramp, chosen by bit 7 of the instance red (`look_red(ramp, zoom)` in the manager, shared by Feel and Entities); the beam's enemy ramp; `tint_of(NO_PLAYER)`. Tests: the decode, and the players' bytes unchanged |
| F3 | **Enemy tags** | `core/spells/spell_tag.gd` | The layout above. Tests: round trips, no overlap with the AI's attack tags, below 2³¹ |
| F4 | **Enemy casters in the projectile manager** | `core/projectiles` | `ENEMY_CASTERS`; anchors for enemy rows; events with `NO_PLAYER`; one drop bucket for every enemy; shields and homing on wizards for enemy shots; `set_target_owner` (an enemy's shots skip its own body); `enemy_fire`; enemy shots in the shot shader's batches (still drawn above players'). The timing test still within budget |
| F5 | **Enemy casters in the spell runtime** | `core/spells` | `open_enemy_caster`, `close_enemy_caster`; state sized for players and enemy rows; hit layers by the caster's side; handlers that find the caster from the tag; the enemies' share of the shared limits; `next_cast_mana`; caster-side moves and entities routed to the enemy. Tests: cast, payloads, chains, the beam share, closing mid-flight, every row in use, a four-player staff unchanged |
| F6 | **Combat** | `gameplay/combat` | Area hits by side; enemy spell hits on wizards with statuses and reactions; the `wizard_hurt` tag |
| F7 | **Feel** | `gameplay/feel` | Enemy impacts, casts, beams and rain markers as normal effects in the enemy ramp; the ember burst and the hostile texture hand-off removed |
| F8a | **Enemies cast staffs** | `core/base/enemy_base.gd`, `gameplay/ai` | `staff`, `cards`, `max_mana`, `mana_regen` on `EnemyBase`; the AI's mana, caster row, anchor and aim; the windup gated on the next cast; the telegraph's reach from the cast; one compile per enemy type |
| F8b | **The telegraph in the new style** | `gameplay/ai`, `gameplay/feel` | The windup's line drawn by the shot shader (an effect) instead of the `Line2D`, in the enemy ramp |
| F8c | **Moves on enemies** | `gameplay/ai` | Dash, teleport, hook, swap and recoil moving the enemy (answering `caster_move_requested` by tag, `caster_move_finished` where it ends); a cast aims a move at the target as it aims everything |
| F8d | **Decoys and familiars for enemies** | `gameplay/ai` (Entities) | An enemy's decoy (a copy of the enemy that wizards' shots hit and homing picks) and familiar (circling it, casting at the nearest wizard), in the enemy ramp; two of a kind per enemy in 32 rows of their own; they end with their enemy |
| F9a | **The imp and the shooting dummy on staffs** | `content/enemies`, tests | Both on player-card staffs (`fire · bolt`, `slow · bolt`). Tests: the dummies, the waves, the 4-bot test; a stress run at the web cap (numbers in DECISIONS) |
| F9b | **The old enemy attack removed** | `gameplay/ai`, `gameplay/combat`, `gameplay/feel`, `core/projectiles` | `ATTACK_TAG`, its hit-profile table, the attack exports, `imp_fireball.svg` and the hostile batch removed (split from F9 while building it, as F8 was) |
| F10 | **Enemy fire setting** | `core/settings`, `hud/menus/pause`, `gameplay/ai` | `core/settings/enemy_fire.gd` (off by default), `enemy_fire_requested` and `enemy_fire_changed`, the pause menu row, applied to the projectile manager |

### Phase G: actors (owner, 2026-10-28)

Wizards and enemies become one kind of body (components and a controller), with no sides and a `possess` card. Its own document, with its parts: [M2-actors.md](M2-actors.md). Before D3.

### Phase I: melee (owner, 2026-10-29)

Owner sessions, not queued for the bot. Melee is **carriers**, not a staff type, so every modifier, infusion and trigger works on it through the rules it already follows, with no special cases. Only `swing` for now; `lunge`, `whirl` and `saw` (a chainsaw: tiny hits at the tip, close to 0 delay) wait in the backlog until swing has been played. The player is a living staff, so a swing is the staff head swinging.

- **Mana-free:** a swing costs no mana, like the dashes; its price is standing next to the enemies. This makes it a candidate for the story's starting spell (owner: to be discussed).
- **Built beside the live beam** (I2): a swing has rows of its own next to the live beams (a beam hits along a line every `BEAM_TICK`; a swing must strike each body in a wedge once, within a few steps), but hits in the beam's hit context, so infusions, payloads, chains, `blast` and `on expire` work as on a beam. It turns round the hand (`set_aim`'s pivot) and follows it.
- **Everything hurts everything:** a swing skips only its caster's body, so it hits a teammate in its arc.
- **Enemies get it for free** (they cast from staffs); a melee stray needs a clear wind-up, like every attack.
- **Aim:** the arc is centred on the aim and locks to it at the cast (the swing's beam keeps its start angle, unlike a live beam). Swings alternate forehand and backhand; a backhand right after a forehand starts where it ended, with no wind-up. The body steps through the head sheet's 16 directions (lean back to −67.5°, sweep to +67.5°; only −45° to +45° hits) while the trail follows the true arc. The staff covering the face when aiming up or down is accepted.
- **The look** (owner's picks from the mockup, 2026-10-29): the head swings (Feel's squash) through its 16 frames, and a world-space trail in the glow style follows the arc; no new art style.
  - Trail: a brief line at the arc's reach that sheds pixel sparks outward, cooling through the ramp.
  - Hit: small streaks flung along the swing, and a small screen shake (2 px), off with the screen shake setting (I6).
  - Parry (`shield · swing`): a big four-point star in Spark gold, and a 60 ms local stop (I7) on the parrying player and the shot.
  - Deflect: the bolt flashes big and white, then leaves faster with a longer tail. The speed-up is a rule too (owner): every deflect makes the shot 1.7× faster, so a rally speeds up each time, within the engine's limits.
  - A stray's wind-up: the head leans back and its orb swells and pulls in sparks until the swing.
- **Wasted on a swing:** `return`, `bounce`, `ghost` (it does not fly out), as on `beam` and `rune`.
- **Tuning** (the playground, owner 2026-10-29: "felt good"; the sweep as short as possible). Starting numbers, not rules: they live in the swing card's data and named constants, and change freely after playtests. Arc 90°, reach 24 px, wind-up 0.12 s, sweep 0.06 s (`heavy` 1.3× longer), delay 0.3 s, chain window 0.25 s (a press within it after a sweep chains the backhand with no wind-up), knockback 170 px/s with drag 7 (about 24 px), damage 2, local hit stop 0.05 s, parry stop 0.06 s, deflect 1.7×, a stray's wind-up 0.55 s, slower walking (0.35×) while swinging (not built yet), and a knock into a wall hurts only with `heavy`, as for every carrier (combat's slam). In the game the knockback is the card's `knockback` 240 px/s with combat's linear fade, about the playground's 24 px.
- **Hits between ticks:** a 0.06 s sweep is about four physics ticks, so the beam turns about 34° a tick. Each tick hits what lies in the whole wedge swept since the last tick, not only on the beam's line, so nothing slips between two angles.

**Slam** (owner, 2026-10-29): a second melee carrier. The staff rises (the wind-up) and slams the floor in front of its tip; a shockwave ring hits every body in it and throws them outward from the impact, with a crack and dust in the glow style and a shake. Proposed, to be tuned in the playground before its card: no mana, wind-up 0.25 s, delay 0.6 s, impact 20 px ahead of the hand, ring radius 16 px, knockback outward. End point: the impact, so `blast`, `on expire` and payloads happen there. Wasted on it: `return`, `bounce`, `ghost`, like swing. Combos by the reading rules, with no special cases: a staff of `burst · swing` then `slam` is a combo string (one press: three swings, forehand and backhand by turns; the next press: the slam); `on expire · swing · slam` ends one sweep in a slam in a single press; `double · swing · slam` swings and slams at once; `shield · slam` blocks shots in its ring; `deflect · slam` throws them back outward.

Combos to prove (two per card in its task, the rest for the combo report): `shield · swing` (parry), `shield · on block · swing · nova` (riposte), `heavy · swing`, `fire · swing`, `echo · swing`, `burst · swing` (flurry), `on hit · swing · bolt`, `mirror · swing`, `split · swing` (cleave), `relay · swing` (a teammate enchants your blade), `linger · swing` (a hanging arc), `deflect · swing`.

**Freezes in co-op (owner, 2026-10-29):** Feel's hit-stop dropped `Engine.time_scale` on hits, kills and downs, so one player's hit froze all four players. Decided: (1) a **local stop** for hits and kills: only the bodies in the hit (the attacker, the target and the shot) hold for a moment while the rest of the world, the other players included, runs on; (2) a **game-wide stop only for rare moments**: a downed player and a boss kill. The parry's freeze is a local stop too.

**Deflect:** a shot of another team touching the carrier turns around and takes the carrier's caster (its actor, team and hit credit), so a homing shot deflected hunts the new caster's targets. A shot can be deflected again (a rally), within the engine's limits. Decided for I3 (owner, 2026-10-29):

- **Deflect goes first**, a fixed rule, not card order (order deciding between two modifiers would be a special rule only these two follow): a touching shot is turned and a shield keeps its charge. On a carrier whose shield only stops shots touching it (a shot, a beam, a fissure, a swing) a shield beside a deflect never blocks, so the compiler lists it as wasted ("deflect turns every shot that touches it first"); a hook's, dash's or teleport's shield also guards the caster and is kept.
- **A deflect sets off `on block`** (a deflect is a block): `shot_deflected` fires the carrier's block payload as `shot_blocked` does.
- **No count:** a deflect turns every shot that touches the carrier while it lives; more deflect cards add nothing.
- **Swings and beams touch shots** (the rules audit's shield × beam ✗): a swing's sweep each step (its wedge) and a beam's or fissure's line (every step, not only on hits) deflect or block the shots of other teams they touch, so `shield · swing` parries and `shield · beam` blocks.
- **How a shot turns:** it is mirrored off what it touched (outward from a swing's hand, off a deflecting shot's body, off a beam's line); one already going away keeps its way. It flies 1.7× faster and its life starts again; an orbiting shot leaves its circle. It keeps its own cards (its tag), may hit what it hit before, and is drawn in its new caster's colours.

| # | Part | Area | Delivers |
| --- | --- | --- | --- |
| I1 | **Mockup** | scratchpad, artifact | A playable HTML mockup of swing, parry and deflect, to feel the arc, reach, knockback and delay before anything is built. Done 2026-10-29: the numbers are under "Tuning" |
| I2 | **Swing kit** | `core/spells`, `core/projectiles` | The turning anchored beam (`motion` or a beam field for the arc), the swing's knockback, the head's swing on the actor (a cast look). Tests: the arc hits what is in it and nothing behind, the caster is skipped, a teammate is hit |
| I3 | **Deflect kit** | `core/projectiles`, `core/spells` | Turning a shot and handing it to a new caster (tag, team, hit credit) and making it 1.7× faster, on every carrier. Tests: swing, orbit and wall deflect; a deflected homing shot changes target; a rally speeds up each time. Built 2026-10-29 (`Behaviour.DEFLECT`, `deflect_shot`, `shot_deflected`, swing and beam guards; `tests/core/test_spells_deflect.gd`) |
| I4 | **Card: swing** | `content/spells/forms/swing/` | The card (data), icon, look, two combos, lore, `test_swing.gd`. Built 2026-10-29: the playground's numbers; the trail (`shot_swing.gdshader`, drawn by Feel's `swing_trails.gd`), the `swing` hit kind (a 0.05 s local stop, about 2 px of shake); combos `swing_fire_arc` and `swing_hit_nova`. Left for later: a stray's wind-up charge (the parry's star came with I5) (when an enemy carries a swing) |
| I5 | **Card: deflect** | `content/spells/modifiers/deflect/` | The same for deflect. Built 2026-10-29: mana ×1.25, delay ×1.2, complexity 2, the zig look (18); combos `deflect_swing_return` and `deflect_wall_mirror` (a new `deflected` check); the deflect's big white flash in the new caster's ramp (its longer tail comes from the 1.7× speed) and the parry's gold star with a 0.06 s local stop on the parrier (Feel, `shot_blocked` with `impact_form` `swing`) |
| I6 | **Screen shake setting** | `hud/menus/`, `core/save` | `Feel.shake_enabled` as a saved option in the menu (on by default), so players can turn screen shake off. Independent of I1–I5 |
| I8 | **Card: slam** | the playground, `core/spells`, `content/spells/forms/slam/` | Slam in the playground first (tune its wind-up, ring and knockback), then the card on the area hit at its impact; tests: the ring hits what is in it, the caster is skipped, outward knockback, `on expire · swing · slam` |
| I7 | **Freezes in co-op** | `gameplay/feel/`, `core/projectiles` | Feel's hit-stop as a local stop on the attacker, target and shot ("Freezes in co-op" below); `Engine.time_scale` only for a downed player and a boss kill; the parry's local stop. Tests: one player's hit does not slow another player or an unrelated shot; a down still stops the game |

### Phase D: proof

| # | Part | Delivers |
| --- | --- | --- |
| D1 | **Bots and the emergent combo report** | Bots build random staffs (seeded); `test_spell_fuzz.gd` on staffs; a weekly report in `docs/LOG.md`: the best random staffs by kills and reactions, and the costliest by frame time and by safeguards met |
| D2 | **Staff codes** | Copy and paste in the sandbox; parsing rejects anything but known ids |
| D3 | **Stress and C2** | The stress run with built staffs; then the C2 issue, with the owner's sandbox playtest on `/preview/`. The playtest asks explicitly about fairness: the dash without invulnerability, self-harm and random scatter together |

## Later (in `docs/BACKLOG.md`)

- **Staff types (M3):** an always-cast slot, a shuffle staff, built-in recoil, cheaper `hold`.
- **Relics (M3):** explosion immunity (hit kind `burst`), self-damage refunded as mana, immunity to one element, triggers that fire twice.
- **Enemy cards as rewards (M3–M4):** elites and bosses with dearer staffs, whose cards can drop as rewards. Enemies casting from staffs moved into M2 (phase F).
- **Elements on the room (M3 rooms):** fire lights grass, frost freezes water into floor, lightning electrifies water, void breaks weak walls.
- **Codex (M5):** the first time a reaction, a combo or an unknown chain happens, the game notes it.

## Out of scope

- M3's rewards, relics, staff types, rooms and the door rule; M5's saving.
- Build limits, until the stress benchmark asks for one.

## Self-critique against docs/DESIGN.md

An independent review with fresh context checked this document before it merged. Its findings and what changed are in `docs/DECISIONS.md` ("Staffs design review").
