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
| Carrier (15) | `FormBase` | Ends a group: something leaves the caster | bolt, beam, nova, rune, orbit, **dash, teleport, hook, swap, boomerang, wall, rain, fissure, decoy, familiar** |
| Modifier (23) | `ModifierBase` | Attaches to the next carrier | split, pierce, homing, chain, bigger, faster, **shield, blast, hold, recoil, bounce, echo, linger, heavy, siphon, overcharge, sticky, magnet, ghost, spiral, mirror, growth, relay** |
| Infusion (6) | `ElementBase` | Attaches to the next carrier; several may | fire, frost, storm, void, lightning, **mend** |
| Trigger (10) | `TriggerBase` | Attaches to the next carrier; the group read after that carrier is its payload | on hit, on expire, timer, **on block, on kill, on cast, on wall, on hurt, on reaction, on ally** |
| Multicast (4) | `MulticastBase` | Pulls more carriers into the same group | **double, triple, scatter, burst** |

58 cards: the 19 that exist and 39 new ones. Pillar 1 says "few components, many combinations"; the per-card tests and the emergent combo report (part D1) are there to find cards that add little, and such a card is cut, not tuned.

`complexity` stays on `SpellComponent` for the validator's range check but nothing reads it any more; part A4 removes the budget. Ids stay unique across all kinds.

**Every card has an end point:** where its effects happen once it is done. A shot's end point is where it hits or expires; a dash's, teleport's and hook's is where the wizard arrives; a decoy's where it dies; the caster's is the caster. `blast`, `on expire` and the look of an ending all use it.

**Who casts a card** (owner, 2026-10-27: "this should not be a special case, but follow the core spell logic"): a staff's own cast is cast by the wizard; a payload is cast by the shot whose trigger fired it, while that shot still flies, and otherwise by the point it fired from (a shot spent on its hit, an expiry, a beam, a rain, an entity); an `on cast` payload by its carrier's caster. Every card that names the caster follows this one rule: dash, teleport, hook, swap and recoil move it (a payload dash makes its shot lunge forward; with only a point there is nothing to move), and orbit, familiar and a returning shot circle it or come back to it (`timer · bolt · orbit` is a ring round the flying bolt, `on expire · bolt · orbit` one round where it ended).

**Live beams** (owner, 2026-10-27): a beam is a carrier that lives its `lifetime` like a shot (0.3 s, one cast cycle of the starter staff, so held fire keeps a beam on with no gap; `hold · beam` stays on until switched off). It follows its caster while it lives (the wizard's aim, or the shot that fired it), hits what is on it at once and then every `SpellLimits.BEAM_TICK` (0.15 s), and a homing beam bends along a curve onto the nearest target within 45 degrees of its aim. Homing stacks by multiplying (owner, 2026-10-27): each homing card after the first turns a shot 1.5 times faster and widens a beam's bend 1.5 times, up to 90 degrees (`SpellLimits.HOMING_STACK`). Multipliers (damage, speed, size, delay, mana) always multiplied; counts (chain jumps, bounces, pierce, shields) add. Its `blast` and `on expire` happen where it got when its life is over.

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
| boomerang | Flies out and comes back to the caster | `blast · boomerang` explodes on you unless you move; `pierce · boomerang` hits twice |
| wall | A line of still shots across the aim | `shield · wall` stops enemy shots; `fire · wall` is a burning fence |
| rain | Its payload falls on the aim point after a telegraphed delay | `rain · nova`; `rain · frost · nova` freezes an area from above |
| fissure | A crack along the ground that hits everything on its line | `on hit · fissure · nova` sets off a nova on every enemy in the line; `bounce · fissure` turns at walls |
| decoy | A still copy of the wizard that enemies target. End point: where it dies | `blast · decoy` is an exploding decoy; `on expire · decoy · nova` |
| familiar | A small helper that orbits the caster and casts its payload at the nearest enemy every second | `hold · familiar · bolt` keeps it; `familiar · mend · bolt` is a healer |

**Modifiers**

| Card | Does | Two interactions |
| --- | --- | --- |
| shield | The carrier blocks one hit (stacks: three shields block three). On a self carrier (dash, teleport) or on the caster it is a barrier on the wizard for the carrier's duration; on a shot it blocks enemy shots | `shield · dash`; `shield · orbit` is a ring of blockers |
| blast | The carrier explodes at its end point (radius damage, hit kind `burst`). On the caster it explodes on the caster | `blast` alone is self-harm a relic can turn around; `blast · bolt` is a rocket |
| hold | Makes the carrier sustained: it stays until switched off, and reserves its mana from the pool while on (see "Mana") | `hold · shield · orbit` is a barrier ring; `hold · fire · orbit` is a permanent fire ring |
| recoil | Pushes the caster back when cast | `recoil · blast · bolt` is a rocket jump; movement on an attack staff |
| bounce | Bounces off walls; `on expire` fires only after the last bounce | `bounce · split · bolt` fills a room; `bounce · boomerang` |
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
| growth | Grows and gets stronger the further it flies | rewards range; `growth · linger · bolt` is a huge slow orb |
| relay | When the shot passes through a teammate it takes on the infusions of that player's last cast | your bolt plus their frost, with nobody waiting (docs/PLAN.md, cross-player linking) |
| short delay | Halves the carrier's delay for 25 % more mana (owner, 2026-10-27; named after the builder's "Delay", so it is not mistaken for `faster`) | `short delay · dash` dashes again sooner; `short delay · beam` keeps a beam on with a slower staff |

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
| on ally | the shot passes through a teammate | `on ally · mend · bolt · nova` heals around a friend |

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
| `spread` | Degrees of random spread on every shot | 0–45 |

- **`starter`:** 4 slots. Used by `nightly` and `stable` builds.
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

- **Small:** a shot is drawn about its hit size (`DRAW_SCALE` and `SHAPE_SCALE` in `core/projectiles` come down), a 3–5 px core with a 2–3 px trail.
- **From the shot's cards:** the **core** from the carrier; the **player colour** on the trail; a particle style per **infusion** (lightning throws sparks, fire drops embers, frost leaves flecks, void pulls pixels in, storm leaves gust streaks, mend shows green motes); some **modifiers** add one (bigger glints, pierce streaks and lengthens the core, blast bursts sparks out, shield's sparks orbit, homing weaves, hold glitters).
- **Every card shows, combined, by what the shot gives off** (the owner, 2026-10-26: "we need a system that can combine all of it", then "the bolts could stay pretty plain, but then emit/sparkle with different added effects" and "the tail of bolts should also emit from added effects randomly"; the first plan drew at most four layers round the core). The body stays plain; each look kind is a particle style; a shot keeps 4 + 2 per style particles alive (at most 12), each born at a random point of its tail with a style picked at random, so one card is a trickle and many a mix, never a crowd. The look is a set with one bit per kind, in the instance colour beside the player and the zoom (room for 24 kinds). Two cards with the same kind add nothing more.
- **No per-shot nodes or particles:** one shader draws the layers; sparks and embers come from one shared pool with a global count, and at the cap trails thin first. This is a visual budget under the effect quality setting, never a build rule.
- **Each card's look is data in its own `.tres`** (`look_layer`, an effect kind the shader knows), so a new card never edits the shader unless it needs a new effect kind. Feel's per-form looks (`cast_looks` in the Feel preset) move to card data the same way.
- **Player colours** (pillar 4) are checked explicitly: the clip sheet includes four players firing the same card, and each player's shots must be told apart at 1x.
- Player shots hit a little wider than they look; enemy shots a little narrower.
- Checked with the clip recorder: a sheet of every carrier with every infusion against `docs/STYLE.md`, and a four-player sandbox clip.

## The sandbox

- `dev` and `preview` builds start in the sandbox; "Play" in the menu still starts the normal game.
- One room of **two shooting lanes split by a wall** (owner, 2026-10-26: "two dummies separated by a wall (so like two shooting range lanes). One dummy for hitting and the other one fires back"); four 20-slot `dev` staffs per player; the full bag; the full builder at any time.
- **Training dummy** (end of one lane): never dies or moves; shows damage numbers, damage per second over the last 5 s, its statuses and reactions.
- **Shooting dummy** (end of the other lane): fires slow, telegraphed shots at the nearest wizard, for shields, blocks and self-harm.
- **The sandbox page** in the pause menu (owner, 2026-10-26: first "an entry in the start button menu - where the builder also is", then Start became the pause menu and B the builder): spawn an imp wave, reset the dummies. Friendly fire is in the pause menu's Settings, Gameplay, for every run; slow motion is not needed (owner). The actions change the room, never another player's choices or menus.
- **Staff codes** (part D2): copy a staff as a short text code and paste one, so builds can be shared in Discussions. A code is only card ids, checked against the registry; nothing in it runs.

## Events

Added in part A3, so later parts in different areas don't all edit `core/events/events.gd`. Each has one sender.

| Event | Sender | Heard by |
| --- | --- | --- |
| `staff_change_requested(player, staff, slot, card_id)` | hud | player |
| `card_move_requested(player, from_staff, from_slot, to_staff, to_slot)` (`-1` staff means the bag) | hud | player |
| `staff_cards_requested(player, staff, cards)` (the whole staff at once; the radial builder) | hud | player |
| `staff_changed(player, staff, plan: Dictionary)` | player | hud |
| `staff_cast(player, staff, origin, direction)` | player | feel |
| `caster_move_requested(player, mode: StringName, to: Vector2, seconds: float, tag: int)` (dash, teleport, hook, swap, recoil) | spells | player |
| `caster_move_finished(player, mode: StringName, position: Vector2, tag: int)` | player | spells (the end point of dash, teleport, hook) |
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
| `wizard_hurt(player, amount, position, tag, kind: StringName)` (`tag` 0 for an enemy's hit) | combat | spells, feel, hud |
| `reaction_landed(player, reaction_id, target, position, tag)` | combat | spells |
| `ally_passed(player, ally, position, tag)` | projectiles | spells |

`build_change_requested`, `spell_swap_requested`, `spell_changed`, `recipe_changed` and `active_spell_changed` are removed in part A6c, when nothing sends them any more. A kit that finds it needs one more event adds it in its own PR.

## Tags

A shot's int tag becomes **player (2 bits), staff (2), generation (3), node (9)**, with `SpellTag.FLAG` at `1 << 20`, so spell tags (1,048,576 and up) never meet the enemy attack tags of `gameplay/ai` (1,000 to 101,000). The node is the index of a compiled node in the staff's cycle: every carrier of every cast, payloads included, **and every fallback** (the caster or a payload origin); at most 512 per staff. Only the last cast of a cycle can wrap, so a cycle reads each card at most twice, and each group adds at most one fallback: a 64-slot staff stays under 512 (A4 found that 128 was not enough). The generation ring (8 per staff) and the rule that a shot in the air keeps its old numbers after a rebuild stay as they are (part A5).

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
| B7 | **Sandbox** | `gameplay/flow`, `content/rooms`, `content/enemies`, `hud/menus/` | B6 | B7a: the two-lane sandbox room, both dummies, the sandbox page (imp wave, reset dummies); `dev` and `preview` start in it (a focused Sandbox button above Play). Then the controls rework (owner): staffs on RB, RT, LB, LT, the builder on B, the pause menu on Start with the sandbox page and Settings, Gameplay, Friendly fire |
| B8 | **Builder** | `hud/builder` | A6c | Pick and place (pick a card up, put it down, swapping; `card_move_requested`), links in the cast plan, live numbers, mouse drag for P1, and quicker moves than one control at a time (A6a's builder walks tabs, slots and bag in one line, so from the bag back to the tabs is many presses: left and right between tabs, slots and bag, or a jump); screenshots at 1 and 4 players; every slot reachable with the d-pad alone |

B1 and B6 both change `core/projectiles/projectile_manager.gd`, so B6 waits for B1. B3 and B4 both reach the wizard's movement and health, so B4 waits for B3. B7 adds its own folders in `hud/menus/`; B8 owns `hud/builder/`.

### Phase C: cards, one PR each, in parallel

A card task touches only its own folder (`.tres`, icon, look, `assets.json`), `content/spells/combos/<id>-*.json` (two combos), `content/story/lore/components/<id>.json` and `tests/content/spells/test_<id>.gd`. It starts when its kits have merged:

| Needs | Cards |
| --- | --- |
| A6c | double, triple, overcharge |
| B1 | bounce, ghost, spiral, boomerang, linger, growth |
| B2 | on cast, echo, burst, scatter, mirror, rain, fissure, wall |
| B1 + B2 | sticky, relay, on ally, on wall |
| B1 + B3 | heavy, magnet |
| B1 + B2 + B3 | shield, blast, mend, on block, on kill, on hurt, on reaction |
| B2 + B4 | teleport, hook, recoil, siphon, hold |
| B2 + B4 + B5 | swap |
| B2 + B5 | decoy, familiar |

C0 (after B6): the 19 existing cards get their look data and a second look at their numbers without the budget.

### Phase E: extras the owner asked for along the way

| # | Part | Area | After | Delivers |
| --- | --- | --- | --- | --- |
| E1 | **Spell names** | `core/spells` (a namer beside the compiler), `hud/builder` | A6c | A name for every cast from its cards (see "The builder"): word lists per card in the card's own `.tres` (`name_words`, so a new card brings its words and edits no shared list), rules for multicast, triggers and payloads, `Spells.staff_view` gives each cast's `name`; the builder shows the names above the plan; tests that names are deterministic and grow with the build |

### Phase D: proof

| # | Part | Delivers |
| --- | --- | --- |
| D1 | **Bots and the emergent combo report** | Bots build random staffs (seeded); `test_spell_fuzz.gd` on staffs; a weekly report in `docs/LOG.md`: the best random staffs by kills and reactions, and the costliest by frame time and by safeguards met |
| D2 | **Staff codes** | Copy and paste in the sandbox; parsing rejects anything but known ids |
| D3 | **Stress and C2** | The stress run with built staffs; then the C2 issue, with the owner's sandbox playtest on `/preview/`. The playtest asks explicitly about fairness: the dash without invulnerability, self-harm and random scatter together |

## Later (in `docs/BACKLOG.md`)

- **Staff types (M3):** an always-cast slot, a shuffle staff, built-in recoil, cheaper `hold`.
- **Relics (M3):** explosion immunity (hit kind `burst`), self-damage refunded as mana, immunity to one element, triggers that fire twice.
- **Enemies with staffs (M3–M4):** elites and bosses on the same compiler; their cards can drop as rewards.
- **Elements on the room (M3 rooms):** fire lights grass, frost freezes water into floor, lightning electrifies water, void breaks weak walls.
- **Codex (M5):** the first time a reaction, a combo or an unknown chain happens, the game notes it.

## Out of scope

- M3's rewards, relics, staff types, rooms and the door rule; M5's saving.
- Build limits, until the stress benchmark asks for one.

## Self-critique against docs/DESIGN.md

An independent review with fresh context checked this document before it merged. Its findings and what changed are in `docs/DECISIONS.md` ("Staffs design review").
