# M2 rework: staffs (the spell system, second design)

**Goal:** replace the fixed spell template (form → element → up to three modifiers → trigger, under a complexity budget) with **staffs whose cards are read in order**, in the spirit of Magicraft and Noita's wands. Every arrangement of cards is legal and does something, so players find interactions nobody designed (docs/DESIGN.md, pillar 1, and "Discovery"). The builder becomes a row of slots you put cards in.

**Status (2026-10-26):** the owner's verdict on the second C2 checkpoint (#264) is **pivot**, worked out with the owner in an owner session over six rounds. This document replaces the parts of [M2-spell-system.md](M2-spell-system.md) that it names; everything else there (the projectile manager, statuses, reactions, the validator, the bots, the clip recorder) still stands. M2 is not closed: its done-when is replaced by the one below, and C2 is asked again at the end.

**Why:** the owner found the builder hard to use, the template locking builds out, and adding components the only way to get deeper builds.

**Done when:**

1. Every task in "Parts" below is merged, and `ci/build/build.sh --quick --tests` is green.
2. Every card has a test, a lore line, an icon, a look, and appears in at least two combo files that pass.
3. The 4-bot smoke test passes with bots that build random staffs, and the fuzz run (random staffs, part D1) has no error line.
4. The stress benchmark runs with built staffs; over budget it warns (never fails), and the warning names the costliest staffs.
5. The owner has played the sandbox on `/preview/`, and C2 has a verdict.

## Summary of the rules

- Each wizard has **four staffs, one per button**: A, X, Y and B on a gamepad; Space (or Shift), left mouse, right mouse and Q for P1 on keyboard and mouse. There is no separate dodge or cast: the A staff starts with a `dash` card, the X staff with `fire · bolt`.
- A staff is a row of **slots**. The player puts **cards** in any order. A cast reads the cards left to right with the rules in "Reading a staff".
- **No complexity budget and no build limits.** The builder refuses nothing except a full staff. The only limit is the projectile pool (500 shots on web, 3,000 on desktop), which drops the oldest shot when full. If the stress benchmark later shows a staff that freezes the game, a limit, a mana cost or a cheaper effect is decided then (owner, 2026-10-26: "They can be added later if we want to / need to").
- **Self-harm is always on.** A wizard's own spells hurt them (damage, knockback, statuses). Hurting other players stays the friendly-fire option, off by default.
- **One mana pool per wizard**, used by all four staffs. Cards made sustained by `hold` reserve part of it while they are on.
- **The input buffer** (`INPUT_BUFFER`, 0.15 s) applies to every staff button: a tap while the staff is not ready is remembered and fires as soon as it is. Holding a button keeps casting whenever the staff is ready.
- **Projectiles are small** (a 3–5 px core and a short trail) and get their look in **layers** from their cards.
- **`dev` and `preview` builds start in a sandbox** with 20-slot staffs, the full bag and a training dummy. `nightly` and `stable` builds play the normal game with 4-slot starter staffs.

## Cards

A card is a `.tres` on one of five classes in `core/base/`, in its own folder under `content/spells/<kind>s/`. The four existing classes stay, with new fields (part A3); `MulticastBase` is new.

| Kind | Class | Role | Cards (new in bold) |
| --- | --- | --- | --- |
| Carrier (15) | `FormBase` | Ends a cast: something leaves the caster | bolt, beam, nova, rune, orbit, **dash, teleport, hook, swap, boomerang, wall, rain, fissure, decoy, familiar** |
| Modifier (23) | `ModifierBase` | Attaches to the next carrier | split, pierce, homing, chain, bigger, faster, **shield, blast, hold, recoil, bounce, echo, linger, heavy, siphon, overcharge, sticky, magnet, ghost, spiral, mirror, growth, relay** |
| Infusion (6) | `ElementBase` | Attaches to the next carrier; several may | fire, frost, storm, void, lightning, **mend** |
| Trigger (10) | `TriggerBase` | Attaches to the next carrier; the cast after that carrier is its payload | on hit, on expire, timer, **on block, on kill, on cast, on wall, on hurt, on reaction, on ally** |
| Multicast (4) | `MulticastBase` | Pulls more carriers into the same cast | **double, triple, scatter, burst** |

58 cards: the 19 that exist and 39 new ones. Pillar 1 says "few components, many combinations"; the per-card tests and the emergent combo report (part D1) are there to find cards that add little, and such a card is cut, not tuned.

`complexity` stays on `SpellComponent` for the validator's range check but nothing reads it any more; part A4 removes the budget. Ids stay unique across all kinds.

### What each new card does

Numbers are first guesses for the card's own task to set.

**Carriers**

| Card | Does | Two interactions |
| --- | --- | --- |
| dash | The wizard dashes along the move direction (today's dodge, **without** the invulnerable window). Its "hit point" is where the dash ends. | `shield · dash` blocks one hit during the dash; `blast · dash` explodes at the end |
| teleport | Blink along the aim, stopping before walls; a small burst where the wizard lands | `blast · teleport` arrives with an explosion; `on expire` fires at the arrival point |
| hook | A shot that pulls the caster to where it hits | `shield · hook` is a safe gap-closer; `blast · hook` charges in with a bang |
| swap | A shot that trades places with the target it hits | an escape through an enemy; `frost · swap` leaves a chilled target where you stood |
| boomerang | Flies out and comes back to the caster | with `blast` it explodes on you unless you dodge; `pierce` hits twice |
| wall | A line of still shots across the aim | `shield · wall` stops enemy shots; `fire · wall` is a burning fence |
| rain | The payload falls on the aim point after a telegraphed delay | `rain · nova`; `rain · frost` freezes an area from above |
| fissure | A crack along the ground that hits everything on its line | `fissure · on hit` sets something off on every enemy in the line; `bounce` turns it at walls |
| decoy | A still copy of the wizard that enemies target | `blast · decoy` is an exploding decoy; `on expire` fires your payload when it dies |
| familiar | A small helper that orbits the caster and casts its payload at the nearest enemy every second | `hold · familiar` keeps it; `mend · familiar` is a healer |

**Modifiers**

| Card | Does | Two interactions |
| --- | --- | --- |
| shield | The carrier blocks one hit (stacks: three shields block three). On a self carrier (dash, teleport) or on the caster it is a barrier on the wizard for the carrier's duration; on a shot it blocks enemy shots | `shield · dash`; `shield · orbit` is a ring of blockers |
| blast | The carrier explodes where it hits (radius damage, `hit kind` burst). On the caster it explodes on the caster | `blast` alone is self-harm a relic can turn around; `blast · bolt` is a rocket |
| hold | Makes the carrier sustained: one cast switches it on, the next off; while on it lasts and reserves its mana from the pool | `hold · shield` is a barrier that regrows; `hold · orbit · fire` is a permanent ring |
| recoil | Pushes the caster back when cast | `recoil · blast` is a rocket jump; movement on an attack staff |
| bounce | Bounces off walls; `on expire` fires only after the last bounce | `bounce · split` fills a room; `bounce · boomerang` |
| echo | The cast repeats 0.3 s later at half damage | doubles triggers; `echo · teleport` is a double blink |
| linger | The shot stops mid-air for 1 s, then goes on | traps; `linger · nova` is a delayed ring |
| heavy | Slower, much more knockback; an enemy knocked into a wall takes damage | sets up hex; `heavy · dash` is a shoulder charge |
| siphon | Hits refund mana | feeds `hold`; pays for big multicasts |
| overcharge | Double mana cost, more damage | the opposite of siphon |
| sticky | The shot sticks to the target it hits and fires `on expire` from there | `sticky · blast` is a sticky bomb; a timer planted on a boss |
| magnet | The shot pulls enemies toward its path | gathers a crowd for `nova` or `blast`; void makes it stronger |
| ghost | Passes through walls | `ghost · homing` hunts through rooms; never sets off `on wall` |
| spiral | Flies in a sine wave | covers an area; `spiral · split` is a curtain |
| mirror | Also fires backwards | guards your back; `mirror · recoil` cancels the push |
| growth | Grows and gets stronger the further it flies | rewards range; `growth · linger` is a huge slow orb |
| relay | When the shot passes through a teammate it takes on the infusions of that player's last cast | your bolt plus their frost, with nobody waiting (docs/PLAN.md, cross-player linking) |

**Infusion:** mend: hits heal wizards (bypassing the friendly-fire setting) and do almost nothing to enemies. `mend · blast` is a self-heal burst; `mend · chain` jumps a heal through the party.

**Triggers** (each fires the payload from where the event happened)

| Card | Fires when | Two interactions |
| --- | --- | --- |
| on block | a shield on the carrier absorbs a hit | `shield · dash · on block · nova` is a counter |
| on kill | the carrier's hit kills | chains through crowds; with `split` it snowballs |
| on cast | at once, from the caster | a teleport that leaves something behind |
| on wall | the shot hits a wall | `bounce` plus this is a trap at every corner |
| on hurt | the caster takes damage while the carrier lives (use with `hold`) | `hold · on hurt · nova` is a thorns aura |
| on reaction | the carrier's hit causes a reaction | reactions that start more reactions |
| on ally | the shot passes through a teammate | `mend` chains between players |

**Multicast:** double (2 carriers in one cast), triple (3), scatter (3, in random directions, seeded per cast), burst (the group fires 3 times in quick succession).

## Reading a staff

The compiler (`Spells.compile_staff`, part A4) turns a staff's slots into its **cycle**: the list of casts the staff makes before it recharges. Reading is deterministic, so the cycle is computed once per build change, and the builder shows it.

1. **A cast draws one group** starting at the staff's cursor (0 after a recharge). A group wants **one carrier** (a staff's `draw`, 1 for every staff for now).
2. Cards are read left to right; empty slots are skipped.
   - A **modifier or infusion** is kept for the next carrier of this group.
   - A **multicast** card adds its `extra_draws` to the carriers this group wants (double adds 1, triple 2), or repeats the group (burst).
   - A **trigger** is kept for the next carrier. That carrier's **payload** is the group read right after the carrier (recursively, by these same rules). A second trigger before the same carrier is wasted.
   - A **carrier** takes every kept modifier, infusion and trigger, and the group wants one carrier fewer. When it wants none, the group ends.
3. **Wrap-around:** reading past the last slot goes on from the first. A cast that wrapped makes the staff recharge after it.
4. **Use once:** a card already read in this cast ends the reading where it is (this is what keeps wrap-around from looping forever, and why every staff's cycle is finite).
5. **The caster as fallback carrier:** if the reading ends with modifiers or infusions kept and no carrier to take them, **they land on the caster**. `blast` explodes on the caster, `fire` sets the caster burning, `shield` gives the caster a barrier. Cards that mean nothing on a wizard (homing, pierce) are wasted. A kept trigger with no carrier is wasted.
6. **Wasted cards** do nothing and are shown greyed out in the builder's cast plan, with the reason. They are never refused.
7. **After a cast** the cursor moves past the last card read. If the cast wrapped, or no card is left to the right, the staff recharges and the cursor goes back to 0.

A modifier or infusion affects **only the next carrier**, not every carrier of a multicast: `double · fire · bolt · bolt` is one fire bolt and one plain bolt. One card, one target, so the cast plan can draw one arrow per card.

**Examples** (`·` separates slots):

- `fire · bolt · frost · nova`: cast 1 is a fire bolt, cast 2 a frost nova, then recharge.
- `blast · bolt · blast`: cast 1 is a blasting bolt. Cast 2 reads the last `blast`, wraps to slot 1 (`blast`, unused in this cast), then the `bolt`: a bolt with two blasts. Then recharge.
- `blast`: an explosion on the caster every cast.
- `double · fire · bolt · on hit · bolt · frost · nova`: a fire bolt and a bolt, cast together; the second one, on hit, fires a frost nova.
- `on hit · bolt`: the payload wraps to slot 0 (`on hit`, already used), so it is empty; the trigger is wasted.

### Numbers of a cast

- **Mana:** the sum over every carrier in the cast, payloads included, of its `mana_cost` times the `mana_mult` of its modifiers, plus each multicast card's `mana_cost`. Paid at the cast.
- **Delay:** the staff's `cast_delay` plus every carrier's `cooldown` times the `cooldown_mult` of its modifiers. When the staff recharges, its `recharge` is added.
- **Damage, speed, radius, shots, pierce:** the carrier's numbers, then each infusion's `damage_scale`, then each modifier in slot order, as today. Nothing is clamped by a build limit; the speed, radius and pierce ranges the projectile manager needs to work (for example a shot faster than a grid cell per step skipping a target) are its own business.
- **Several infusions:** the hit carries all of them. The first one's status lands first; each later element then reacts with it through the reaction table, so `fire · frost · bolt` thaws on its own hit. The shot's tint and shape come from the first infusion.

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

- Every hit, the caster's own included, goes through `gameplay/combat`. A shot does not hit its caster while it is still leaving the caster's hitbox (the manager's existing `exclude`, for as long as the shot overlaps the caster); anything that lands later, and everything centred on the caster (blast, nova on the caster, reactions), does.
- **Statuses on wizards** are new: burn, chill and freeze, shock, hex and static get a version for wizards in `combat`. A downed wizard takes none.
- **Hit kinds:** every hit carries a kind: `shot`, `ray`, `burst`, `reaction`, `status`, `heal`. A relic (M3) such as "explosion immunity" matches a kind.
- **Fairness** (DESIGN.md, "every death is understandable"): a self-hit has its own flash, and a wizard downed by their own spell is told so ("downed by your own Blast").
- **Shield charges** are per carrier: a shot with three shields blocks three enemy shots, a dash with one blocks one hit on the wizard.

## Mana

- One pool per wizard (`gameplay/player` keeps it, as today), shared by all four staffs.
- `hold` reserves the held cast's mana: the pool's usable maximum shrinks by it while the card is on. Casting the staff again switches it off and frees the reservation.
- `siphon` refunds mana on hits through an event (`mana_refund_requested`), so `core/spells` never writes the player's numbers.

## The builder

The aim is a builder each player can use quickly and without help, in their own corner with four players on screen. Scrolling panels are allowed where they make that easier; they are not a requirement (owner).

- **Four staff tabs**, labelled with their button glyphs; LB and RB switch.
- **The slot rows** of the shown staff (20 slots wrap into rows) and **the bag** below.
- **Pick and place:** A picks a card up and places it (swapping if the slot is taken); X sends a card back to the bag; B cancels. P1 can also drag with the mouse.
- **The cast plan strip** under the slots: brackets each cast of the cycle, draws a link from each modifier or infusion to the carrier it affects (or to the caster), greys out wasted cards with the reason, and reads in plain words: *Cast 1: fire bolt and bolt; on hit: frost nova · Cast 2: beam · recharge 0.6 s*.
- **Live numbers** per cast (damage, mana, delay) and the card's lore line.
- **Quick view** during waves (the normal game): place one card from the bag into an empty slot. In the sandbox the full builder is open at any time.
- The HUD only shows what events say: `Spells.staff_view(...)` returns plain values (as `builder_view` does today), and the HUD sends intent events.

## The look of a shot

- **Small:** a shot is drawn about its hit size (`DRAW_SCALE` and `SHAPE_SCALE` in `core/projectiles` come down), a 3–5 px core with a 2–3 px trail.
- **Layers**, from the shot's cards: the **core** from the carrier; the **player colour** on the trail only; one layer per **infusion** (lightning throws sparks and the odd 1-frame arc, fire flickers and drops embers, frost has flecks, void pulls pixels in, storm leaves gust streaks, mend shows green motes); some **modifiers** add a layer (bigger scales, pierce stretches, blast pulses a rim, shield adds a ring, homing wobbles, hold glows).
- **No per-shot nodes or particles:** each shot carries bits (infusions, modifiers, a seed) in the batch's custom data, and one shader draws the layers. Sparks and embers come from one shared pool with a global count; at the cap trails thin first. This is a visual budget under the effect quality setting, never a build rule.
- **Each card's look is data in its own `.tres`** (`look_layer`, an effect kind the shader knows), so a new card never edits the shader unless it needs a new effect kind.
- Player shots hit a little wider than they look; enemy shots a little narrower.
- Checked with the clip recorder: a sheet of every carrier with every infusion against `docs/STYLE.md`, and a four-player sandbox clip.

## The sandbox

- `dev` and `preview` builds start in the sandbox; "Play" in the menu still starts the normal game.
- One room; four 20-slot `dev` staffs per player; the full bag; the full builder at any time.
- **Training dummy:** never dies or moves; shows damage numbers, damage per second over the last 5 s, its statuses and reactions.
- **Shooting dummy:** fires slow, telegraphed shots at the nearest wizard, for shields, blocks and self-harm.
- **Sandbox menu** (in the overlay): spawn an imp wave, reset the dummies, friendly fire on or off, slow motion (0.25x).
- **Staff codes** (part D2): copy a staff as a short text code and paste one, so builds can be shared in Discussions. A code is only card ids, checked against the registry; nothing in it runs.

## Events

Added in part A3, so later parts in different areas don't all edit `core/events/events.gd`. Each has one sender.

| Event | Sender | Heard by |
| --- | --- | --- |
| `staff_change_requested(player, staff, slot, card_id)` | hud | player |
| `card_move_requested(player, from_staff, from_slot, to_staff, to_slot)` (`-1` staff means the bag) | hud | player |
| `staff_changed(player, staff, plan: Dictionary)` | player | hud |
| `staff_cast(player, staff, origin, direction)` | player | feel |
| `caster_move_requested(player, mode: StringName, to: Vector2, seconds: float)` (dash, teleport, hook, swap, recoil) | spells | player |
| `mana_refund_requested(player, amount: float)` | spells | player |
| `mana_reserved(player, amount: float)` | spells | player, hud |
| `shield_blocked(player, position, tag)` | combat | spells, feel |
| `kill_landed(player, target, position, tag)` | combat | spells |
| `wizard_hurt(player, amount, position, tag, kind: StringName)` (`tag` 0 for an enemy's hit) | combat | spells, feel, hud |
| `reaction_landed(player, reaction_id, target, position, tag)` | combat | spells |
| `ally_passed(player, ally, position, tag)` | projectiles | spells |

`build_change_requested`, `spell_swap_requested`, `spell_changed`, `recipe_changed` and `active_spell_changed` are removed in part A6, when nothing sends them any more.

## Tags

A shot's int tag becomes **player (2 bits), staff (2), generation (3), node (7)**: the node is the index of the compiled carrier in the staff's cycle (all casts, payloads included), at most 128 per staff. The generation ring (8 per staff) and the rule that a shot in the air keeps its old numbers after a rebuild stay as they are (part A5).

## Working in parallel

The owner runs external Claude sessions next to the bot. The bot takes the first unchecked task under `## Queue` in `docs/NEXT.md` and reads no other section (`ci/smbot/nexttask.py`), so:

- **Two lanes in `docs/NEXT.md`:** `## Queue` is the bot's; `## Owner lane` is for the owner's sessions. The owner rebalances by moving lines between them.
- **Owner sessions** take the first task of the owner lane that no open PR names, and open a draft PR at once (branch `owner/<task-slug>`, the task name in the PR body as `Task: <name>`), so two sessions never take the same task. They follow AGENTS.md like any session.
- **External PRs do not edit `docs/NEXT.md`.** The bot's planning session ticks a task off when a PR with `Task: <name>` has merged.
- **Shared files are split first** (part A2): combos become one file each (`content/spells/combos/<id>.json`), and every card folder lists its own assets in an `assets.json` beside them (the validator and the art test read `art/manifest.json`, `audio/manifest.json` and every `assets.json`). Lore was one file per card already.
- **Foundation first, one PR at a time** (phase A). Then the **kits** (phase B) run at the same time: each lives in one area. Then **every card is one PR** that touches only its own folder, its combo files, its lore file and its test file, so all of them can run at once.
- A task whose kit has not merged yet answers `nothing_to_do` and is skipped for now (docs/PLAN.md, "Never stuck").

## Parts

Each part is one session and one PR, with tests, a green `tools/check.sh` and `ci/build/build.sh --quick --tests`.

### Phase A: foundation, in order

| # | Part | Delivers |
| --- | --- | --- |
| A1 | **The plan** | This document; `docs/DESIGN.md` (owner); `docs/NEXT.md` with both lanes; the later ideas in `docs/BACKLOG.md`; `docs/DECISIONS.md` |
| A2 | **Shared files split** | `content/spells/combos/<id>.json` (one combo per file) read by `test_combos`, the clip scenarios and `tools/atlas.py`; `assets.json` per folder read by the validator and `test_svg_art`; the READMEs and AGENTS.md say so |
| A3 | **Card and staff classes, events** | `MulticastBase`; every new field and enum value of the five card classes (motions, behaviours, trigger events, look, hit kind, heal); `StaffBase` with the `starter` and `dev` staffs; every event above; the validator knows them; tests |
| A4 | **The staff compiler** | `Spells.compile_staff(cards, staff) -> CompiledStaff`: the reading rules, the caster as fallback carrier, multicast, payloads, wrap-around, use-once, wasted cards with reasons, several infusions, the numbers of a cast, a plain description per cast; `Spells.staff_view` for the builder; table-driven tests (slots in, casts out). Additive: the recipe compiler stays until A6 |
| A5 | **The staff runtime** | The new tag layout; `Spells.install_staff(player, staff, compiled)` and `Spells.cast_staff(player, staff, origin, direction, mana)`; four staffs per player with their own cursor, delay and recharge; multicast casts; payload groups (a list, not one held spell); casting on the caster; `hold` on and off with `mana_reserved`; tests with 4 players × 4 staffs and a rebuild mid-flight. Additive |
| A6 | **The switch to staffs** | `gameplay/player`: four staffs, four cast actions (`cast_a`, `cast_x`, `cast_y`, `cast_b`), the buffer for each, the dash card (today's dodge without the invulnerable window) through `caster_move_requested`; `dodge`, `cast` and `swap` removed, the overlay on View/Back; `gameplay/flow`: start staffs by channel; the builder on staffs (the existing builder edits a staff's slots; the full rewrite is B8); bots and the 4-bot test on staffs; every combo file as slot lists; the recipe compiler and the old events removed; `docs/ARCHITECTURE.md` updated |

### Phase B: kits, in parallel after A6

| # | Kit | Area | Delivers |
| --- | --- | --- | --- |
| B1 | **Projectile kit** | `core/projectiles` | bounce, ghost (through walls), spiral, return to caster, linger, growth, magnet, sticking to a target, shots that block enemy shots (shield charges), the wall-hit flag for `on wall`, `ally_passed`; the timing test still within budget |
| B2 | **Trigger kit** | `core/spells` | the seven new trigger events; echo, burst and scatter; relay; the rain delay; fissure's ground line; siphon's refund |
| B3 | **Combat kit** | `gameplay/combat` | self-harm with the leaving-the-caster rule; hit kinds; several elements per hit; statuses on wizards; shield charges on wizards; heal hits; the heavy wall slam; `shield_blocked`, `kill_landed`, `wizard_hurt`, `reaction_landed`; the self-hit flash and "downed by your own …" |
| B4 | **Caster kit** | `gameplay/player` | teleport, hook, swap and recoil through `caster_move_requested`, wall-safe; the mana pool with reservations and refunds |
| B5 | **Entity kit** | `gameplay/ai` | decoy and familiar as pooled entities; the AI targets decoys |
| B6 | **Shot look** | `core/projectiles` (draw), `art/vfx` | small shots; the layer shader and its effect kinds; per-card look data; the shared spark pool; the player colour on the trail; the clip sheet. **Before B7** (the sandbox is judged by eye) |
| B7 | **Sandbox** | `gameplay/flow`, `content/rooms`, `hud/menus` | the sandbox room, both dummies, the sandbox menu; `dev` and `preview` start in it |
| B8 | **Builder** | `hud/builder` | four tabs, slot rows, the bag, pick and place, mouse drag for P1, the cast plan strip, live numbers, the quick view; screenshots at 1 and 4 players; every slot reachable with the d-pad alone |

### Phase C: cards, one PR each, in parallel

A card task touches only its own folder (`.tres`, icon, look, `assets.json`), `content/spells/combos/<id>-*.json` (two combos), `content/story/lore/components/<id>.json` and `tests/content/spells/test_<id>.gd`. It starts when its kits have merged:

| Needs | Cards |
| --- | --- |
| A6 | double, triple, overcharge, mirror |
| B1 | bounce, ghost, spiral, boomerang, linger, growth, magnet, wall |
| B2 | on cast, on wall, echo, burst, scatter, rain, fissure |
| B1 + B2 | sticky, relay, on ally |
| B2 + B3 | on block, on kill, on hurt, on reaction, hold, siphon |
| B1 + B3 | shield, heavy |
| B3 | blast, mend |
| B4 | teleport, hook, swap, recoil |
| B5 | decoy, familiar |

C0 (after A6 and B6): the 19 existing cards get their look data and a second look at their numbers without the budget.

### Phase D: proof

| # | Part | Delivers |
| --- | --- | --- |
| D1 | **Bots and the emergent combo report** | Bots build random staffs (seeded); `test_spell_fuzz.gd` on staffs; a weekly report in `docs/LOG.md`: the best random staffs by kills and reactions, and the costliest by frame time |
| D2 | **Staff codes** | Copy and paste in the sandbox; parsing rejects anything but known ids |
| D3 | **Stress and C2** | The stress run with built staffs; then the C2 issue, with the owner's sandbox playtest on `/preview/` |

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
