# The staff as a language: two numbers, conditions, On Any Cast

**Status (2026-11-25): approved by the owner. L1 built (#936), L2 built (#938) and replaced by L4, L3 built (#941), L4 being built (this PR).** Part 4 of [foundations.md](foundations.md) ("Part 3: the staff as a language"), which the owner chose on 2026-11-25 to build now, beside Part 1 (the floor). It opens builds 9 to 12 of foundations.md's table. The numbers below are proposals; those that are really the owner's are under "Open points". Open point 6 of foundations.md, **a card that stands for another card, stays not proposed** (the owner, 2026-11-25): nothing here copies or repeats a card.

## What it keeps

The rules of a staff stay as they are (foundations.md, "What is there"): compiling is pure, each card is read once in a cast, a modifier lands on one carrier, and at runtime the only choice is which cast leaves. Every new card lives in one of the two places foundations.md names: **in the compiler** (the two numbers) or **in the skip rule** (the conditions). On Any Cast is one more trigger that listens while its carrier lasts, as `on recast` does.

## The slices

| Slice | What | Builds | Engine work |
| --- | --- | --- | --- |
| L1 | Two numbers: **Quick Hand** and **Point Blank** | 11, 12 | two fields of `ModifierBase`, read in `StaffCompiler._build` |
| L2 | Conditions: **When Hurt** and **When Close** (replaced by L4) | 10 | a behaviour `WHEN`, a cast's conditions, the skip rule in `Spells._firing_cast`, the caster's health handed to Spells |
| L3 | **On Any Cast** | 9 | a trigger event `ANY_CAST`, heard in `Spells._leave` |
| L4 | Sigils: **Cast when Hurt**, **Cast when Close** (staffs that cast by themselves; replaces L2's cards) | 10 | an item kind, `ItemStack.sigils`, two commands, the auto cast in `Caster.step`, rewards, the shelf, the HUD |

Each slice is its own PR, with its cards (one folder each: the `.tres` with its builder description, icon, `assets.json`, two combos and `test_<id>.gd`), and its screenshots (the builder showing the card, and the build in play).

## L1: two numbers

### Quick Hand (modifier)

`content/spells/modifiers/quick_hand/`: "Next carrier's wind-down is a quarter second shorter."

- **New number:** `ModifierBase.wind_down_add`, seconds added to the carrier's wind-down after its factors (`wind_down_mult`), below 0 allowed. Range −1 to 1 s. The card: −0.25 s, `mana_mult` 1.5.
- **The floor at 0 moves from the carrier to the cast** (foundations.md): a carrier's wind-down may be below 0 once its cards are read, and the cast's wind-down (its carriers' and its multicast cards' added up) is floored at 0. So in `double · quick hand · bolt · bolt` the card takes a quarter second off the whole cast, not only off its own bolt's 0.35.
- **What it leaves alone:** the staff's own cooldown after a cycle (no card reaches it), any wind-up (a telegraph), and a payload, which adds no wind-down to its staff (so it is wasted on a payload's carrier, as Faster Casting's wind-down is).
- **Nearest card:** Faster Casting, which halves wind-up and wind-down at once. Quick Hand takes a fixed amount off, so it is worth most on a slow cast (a Lumber bolt's 0.46 s, a charged slam) and stacks to nothing: two on a bolt make it 0. Mana is the brake.

### Point Blank (modifier)

`content/spells/modifiers/point_blank/`: "Next carrier ends almost at once, at the staff's tip."

- **New number:** `ModifierBase.lifetime_most`, seconds: the longest the carrier may live, after every other life card (`lifetime_base`, `lifetime_mult`, `reach_mult`), so Slow cannot lengthen it again. 0 is none; with several, the shortest counts. Range 0 to 30 s. The card: 0.05 s (the shortest life a carrier card may have), no other number.
- A bolt with it flies about 24 px and ends: its blast, its `on expire` and its `on hit` (if it touched a body on the way) go off at the staff's tip. Any payload becomes a melee strike (build 11). Its blast strikes its caster too, as every blast does. So an enemy's AI reads such a cast as a blast on its caster (`CastSense.blast_on_caster`: a carrier that ends nearer than its own blast) and never casts it at a foe.
- It counts where the carrier has a life that matters (`Carrier.SPEED` or `LASTS`, as `lifetime_mult`): a rune, a pool, a familiar end almost as they are made, and a swing sweeps in a blink. A dash and a teleport are wasted: a move's time is its distance over its speed, not its life.
- **With Hold** a carrier that lasts is kept on for as long as it is held, whatever its life (`HOLD_LIFETIME`), so Point Blank does nothing on it and the compiler lists it as wasted there (L2; `StaffCompiler._modifiers_on`, `held`). A held spray or swing is cast anew, each with its own life, so it still works on those.

### L1's tests

- `test_quick_hand.gd`: the cast's wind-down is the bolt's less 0.25; two cards make it 0, never below; on a multicast cast the card takes from the cast; wasted on a payload's carrier.
- `test_point_blank.gd`: the life is 0.05 s whatever Slow, Reach or Orbit's base say, in any slot order; `point blank · blast · bolt` hurts an imp at the wizard's shoulder.
- `test_card_rules` (every card on every carrier) and `test_content_determinism` pick them up by folder.
- Combos (each fails without its card): `quick_hand_lumber` (the quick hand, build 12: a second Lumber bolt at 0.25 s leaves too), `quick_hand_stream` (two Quick Hands: a bolt every tenth of a second); `point_blank_spark_ring` (build 11: a lightning nova from the hand strikes the imps beside and behind), `point_blank_frost_ring` (`on expire · point blank · bolt · frost · nova · atom`: a frost nova from the hand chills the imp behind).

## L2: conditions (replaced by L4)

**Replaced (the owner, 2026-11-25):** a condition card is pointless ("if I simply omit the card, the spell will always do it"). The cards and the skip rule below are gone with L4; the text stays as the record of what was built in #938.

foundations.md calls these gates; "gate" is the portal's in the code, so the kind is a **condition** and its behaviour `WHEN`.

### The rule

A condition is a modifier with the behaviour `WHEN`: **"this cast leaves only while X; otherwise it is skipped, as a cast the pool cannot pay."** Its X is named by a new field, `ModifierBase.when_id` (one of `ModifierBase.WHEN_IDS`: `hurt`, `close`), with `behaviour_strength` its amount. The compiler gathers a cast's conditions into `CompiledCast.when_ids` and `when_amounts` (each name once, the strictest amount), and its words into `when_text`.

- **It belongs to the whole cast,** whichever carrier of the cast's own group it lands on (it attaches to the next carrier, as every modifier does, so its tile sits on that carrier's row). Several conditions in one cast must all hold.
- **In a payload it is wasted** (first build): a payload is not a cast and is never skipped. A condition on a payload ("on hit, if hurt, heal") is a later card.
- **It costs nothing** and changes no number.
- **The skip** is today's code: `Spells._firing_cast` passes a cast whose conditions do not hold as it passes one the pool cannot pay. The cursor moves on, a staff of conditioned casts only fizzles when none may leave and its cooldown runs (`cast_fizzled`). So a conditioned cast wants a plain one after it, the panic button's pattern.
- **One rule in three places:** the corner panel's ready mark (`firing_cast`), the AI's telegraph (`next_cast_mana`, `cast_ready`) and the skip all go through `_firing_cast`, so all three read the condition, and an enemy never telegraphs a cast that will not leave.

### What X is read from

X is read from the simulation at the press, the same on every machine:

| `when_id` | Card | Holds while | Strength (the card's) |
| --- | --- | --- | --- |
| `hurt` | **When Hurt**: "This cast leaves only while you are below half health." | the caster's health is below `behaviour_strength` of its most | 0.5 |
| `close` | **When Close**: "This cast leaves only while a foe is close to you." | a foe of the caster (`Actors.is_foe`) stands within `behaviour_strength` px of its body | 96 px |

- **Health:** Spells is in `core/` and does not read Combat's health. The Caster tells it, as it hands the mana: when it attaches and whenever the body's `Health.changed` fires, `Spells.sense_health(actor, share)` sets a per-actor share (state in Spells, so a snapshot keeps it and the hash covers it; 1 for an actor that never told, and again when its id is closed). A body with no health counts as whole.
- **Close:** a foe's hit shape within the reach of the caster's anchor, by the caster's team. At the press (in the tick) Spells asks `nearest_target`, as `on near` does. Every other ask (the corner panel every drawn frame, an AI's look) goes through `ProjectileManager.has_foe_near`, a pure read of the target grid as the simulation left it, so a frame drawn between ticks changes no state (`test_when_close.gd` checks it).
- A new X is a name in `ModifierBase.WHEN_IDS` and a line in `Spells._when_holds`, never a card's script.

### Enemy staffs

A condition is a boss phase written as a card: `when hurt · nova · bolt` before a boss's plain cast opens a ring of bolts once it is below half. The AI needs nothing new (`cast_ready` reads it, and `test_ai_combos` has an enemy play both cards' combos). No enemy or boss gets one now (the owner, 2026-11-25).

### L2's tests

- `test_when_hurt.gd`: a cast with it is skipped at full health and leaves below half; a staff of only conditioned casts fizzles; `firing_cast`, `cast_ready` and the press agree; an id closed and opened again starts whole; wasted in a payload; the builder's line and tree row. The panic button is a combo.
- `test_when_close.gd`: skipped with no foe near, leaves with one within 96 px; a teammate does not count.
- `test_card_rules`: a scene for `WHEN` (the open scene: the condition does not hold there, so the cast is skipped and the trace differs from the cast without it).
- `test_content_determinism` and the snapshot tests: the new per-actor share is state.
- Combos: `when_hurt_panic` (build 10: a hurt wizard's barrier and blink), `when_hurt_whole` (a whole wizard's nova is skipped for the bolt after it; fails without the card); `when_close_slam` (a slam leaves for an imp at arm's length), `when_close_far` (no foe near: the nova is skipped; fails without the card).

## L3: On Any Cast

`content/spells/triggers/on_any_cast/`: "Casts its spell whenever any of your staffs casts."

- **A new event,** `TriggerBase.Event.ANY_CAST`, added at the end of the enum (cards store the event as a number). It needs a carrier that lasts (`NEEDS`: `LASTS`) and is one of the events listed while its carrier lives (`TriggerBase.LIVE`).
- **What it hears:** a cast of any staff of its caster leaving (`Spells._leave`, where `cast_left` is sent), its own staff too. Every live carrier of that caster with the trigger fires its payload from where it is, as `on recast` fires on a press.
- **Once the new cast's shots started:** it is heard by the live carriers listed before the leaving cast's own joined, so a carrier never hears the cast that made it; and a cast whose every shot would start inside a wall (refused: no mana paid, no cooldown) is no cast and sets nothing off.
- **No loop:** a payload is not a cast and sends no `cast_left`, so two On Any Cast carriers cannot set each other off. Each staff keeps its own cursor, cooldown and pool.
- **A held spray** leaves a cast at every pour, so a stream sets it off at the stream's pace. The spell runtime's per-step fire cap still bounds it.
- **Nearest card:** On Cast fires once, as its own carrier is cast. On Any Cast fires every time, for as long as its carrier lasts.
- **The echo chamber** (build 9): `on any cast · familiar · bolt` on one staff, any casts on the other three: the familiar fires a bolt with every cast of any of them.

### L3's tests

- `test_on_any_cast.gd`: a rune with it fires its payload for each cast of the caster's other staffs and of its own staff's next cast, every time; not for the cast that made it; not for another actor's casts; not for a payload (two of them never chain); not for a cast refused in a wall.
- `test_card_rules`: a scene for `ANY_CAST`, "open, another staff casts" (a second staff of the wizard casts an atom behind it while the carrier lives: its own staff is often still busy then, a dash's or a swing's).
- Combos (each fails without the card): `on_any_cast_echo` (build 9: a familiar fires frost bolts as another staff casts), `on_any_cast_rune` (a rune answers another staff's cast with a fire blast).

## L4: staffs that cast by themselves (sigils)

**The owner (2026-11-25):** When Hurt and When Close as cards are pointless: "if I simply omit the card, the spell will always do it". In their place, a modifier on a whole **staff**, not a card in its tree, that makes the staff fire **by itself** while its condition holds, where its owner aims, at its normal cooldown and mana; the owner can still press it too. Players get them as a new reward and in the shop, and a staff can hold several. This slice replaces L2's cards.

### What goes

- The cards **When Hurt** and **When Close** (their folders, combos and tests).
- The `WHEN` behaviour, `ModifierBase.when_id` and `WHEN_IDS`, `CompiledCast.when_ids`, `when_amounts` and `when_text`, the skip in `Spells._firing_cast` and `_when_holds`, `Spells.sense_health` and its per-actor health share, and the Caster's `Health.changed` hook. Nothing else needs them.
- Their test support: the card-rules scene for `WHEN`, `content_fight`'s plain cast after a condition, the spell fuzzer's all-conditioned case, the combo arena's `sense_health`.
- **What stays:** `ProjectileManager.has_foe_near` (the close check of L4 uses it) and Point Blank's waste on a held carrier.

### A sigil

A new item kind, **sigil** (`content/sigils/<id>/`, a `SigilBase` on `ItemContent`: its icon, name, the one line the HUD shows, and its condition), stacking in the bag like a potion. Two to start:

| Sigil | Its staff casts by itself while | Amount |
| --- | --- | --- |
| **Cast when Hurt** | its holder's health is below half its most | 0.5 |
| **Cast when Close** | a foe's hit shape is within 96 px of its holder's body | 96 px |

- **On a staff:** a staff's sigils are its own (`ItemStack.sigils`, ids in the order put on), so they travel with it: a staff swapped to another hand, put in the bag, or carried to the next run keeps them. At most **3** a staff; the same sigil twice adds nothing, so it is refused.
- **Putting one on, taking one off:** from the bag onto one of your staffs, and back, in the inventory menu, each a command (`InputFrame.COMMAND_NAMES`: `sigil_put_requested(seat, sigil id, staff number)` and `sigil_take_requested(seat, staff number, sigil id)`), applied at the next tick's start, refused as any inventory change is while a menu cannot be used. A fourth, or a second of the same, is refused and stays in the bag.
- **How a player gets one:**
  - a **reward**: a line of kind `sigil` in the clear, treasure and challenge tables (rare), picked from a chest as any item is, into the bag;
  - a **shop item**: on the shelf (`shelf.tres`), for coins.

### Casting by itself

- **When:** each tick, in `Caster.step`, after the controller's intent and before the presses are read. For each staff on a hand with sigils: when any of its sigils holds, and its owner is not pressing or holding that staff, the staff is cast as a held button's repeat is (`Caster.cast(at, pressed = false)`): along the owner's aim (`actor.aim`, the seat's own from its `InputFrame`), from its tip, with its free mana.
- **Its normal cooldown and mana:** Spells refuses a staff still busy or a cast its pool cannot pay, as for any press, so a sigil never casts faster or cheaper than the owner could. It fires as soon as the staff is ready, for as long as the condition holds.
- **A press too:** the owner may still press it; a press is a press as today. An auto cast is no new press, so it does not set off `on recast` (only a press does).
- **Never a switch-off:** a staff with sustained (`hold`) cards on is never cast by its sigil (that cast would switch them off), and one that winds up winds up as any cast.
- **Read from the simulation only:** health from the body's `Health`, close from the projectile manager's target grid (`has_foe_near`), aim from the actor. No device, no camera, no clock. The sigils are part of the staff's `ItemStack`, which is state (hashed and snapshotted), so a restored game casts the same.
- **Not while** its holder is down, in a menu that pauses its casting, or the staff is on no hand (in the bag).
- **Enemies too** (the owner, 2026-11-25): an enemy's staff entry (`StaffCards.sigils`) may name sigils, and its staff casts by itself by the same rule in the same `Caster.step`, along the foe's aim. **Its warning:** an enemy's cast always winds up with its staff's telegraph (`cast_winding`, the staff's `wind_up`), and a staff entry with a sigil and no wind-up is a data problem (`StaffCards.problems`), so a foe never casts by itself without its warning and players can still react. Which foes:

| Enemy | Staff | Sigil | Why |
| --- | --- | --- | --- |
| Ember Imp | its fire bolt (wind-up 0.7 s) | Cast when Close | come close and it spits fire at you, telegraphed |
| Storm Fork | its triple lightning (wind-up 0.75 s) | Cast when Hurt | wounded, it lashes out on its own |

  Every other foe, and the Old Broom, has none for now.

### Reading it

- **The corner panel's staff row:** a small icon for each sigil beside the staff's glyph, and while one holds, a slow glow round the glyph (by whole pixels, in at least 3 frames; Smooth) so the player sees why the staff is firing.
- **The builder:** under the staff's name, its sigils' icons and words ("Casts by itself: when hurt, when close").
- **The inventory menu:** a sigil's icon and its line; on a staff, its sigils beside its slots.

### L4's tests

- A sigil's staff casts with no press while the condition holds and not when it does not; at its cooldown (no faster than a held button); refused without mana; never switches a held staff off; does not set off `on recast`; not while down; casts along the owner's aim.
- Several sigils: any one fires it. The same sigil twice is refused; a fourth is refused.
- Put and take are commands, refused in a menu that cannot be used; a staff keeps its sigils through a hand swap, the bag and the next run's loadout.
- Determinism: a fight with a sigil plays the same twice and through a snapshot (`test_content_determinism` covers a new item kind by folder, or a test of its own).
- Rewards: a `sigil` line rolls and is given; the shelf sells one.
- Screenshots: the staff row with sigils and the glow; the builder line; a wizard below half health whose staff fires by itself.

### The owner's answers (2026-11-25)

1. Sigils **attach and come off freely** in the inventory menu.
2. **Up to 3 a staff, no two the same.**
3. **A rare reward line, a shelf price of twice a potion's.**
4. The name **sigil**.
5. **Enemies get sigils too**: some foes' staffs cast by themselves by the same rule (the same tick logic, along the foe's aim, at its cooldown and mana), as a choice of a few enemies, not every foe; the AI's telegraph reads it, so no foe casts by itself without its wind-up warning.

## Reading it in the builder

A card once cut for being "hard to understand" (Quicken) sets the bar: each new card reads in its own words where the builder shows cards.

- **Quick Hand:** its numbers line, as every card's: "Delay -0.25s", "Mana x1.5".
- **Point Blank:** "Life 0.05s at most".
- **A condition:** its numbers line says "Only when hurt" / "Only when close". The cast it is in carries the same words in the tree, after the cast's first carrier's name ("#1 Pulse, only when hurt"), and in the cast's description ("Only when hurt. ..."), so the plan says why a cast may not leave.
- **On Any Cast:** a trigger row like the others, named by its card ("On Any Cast"); its numbers line says "On any cast".
- Text sizes follow the HUD's scale (ART0's HUD at 2×), since the tree's rows and the card's lines are drawn by the code there is.

## Measures

- **No per-frame allocations:** the condition check reads two numbers and at most one target-grid look; On Any Cast walks the live carrier list once a cast, as `recast_staff` does a press.
- **Determinism:** no new clock or dice. The health share is state; everything else is compiled.
- **Builds 9 to 12 work** as combos in `test_combos.gd` (casting in the test arena with the real runtime), each with `needs` set to its card so the combo fails without it.

## The owner's answers (2026-11-25)

- **L1 as proposed:** Quick Hand −0.25 s wind-down at 1.5× mana; Point Blank's 0.05 s life cap with no damage bonus. Tuned later from play.
- **L2's conditions:** When Hurt (below half) and When Close (a foe within 96 px), nothing else yet.
- **No enemy or boss gets a condition now.**
- **Conditions in payloads:** wasted, as proposed.

## The open points as they were put

1. **Quick Hand's price.** Proposed: −0.25 s for 1.5× mana. Cheaper makes Faster Casting obsolete on slow casts; dearer makes it a card for big pools only.
2. **Point Blank's numbers.** Proposed: 0.05 s and nothing else. A damage bonus (a melee strike deserves one) would make it a damage card; left out, its point is placing a payload.
3. **Which conditions.** Proposed: When Hurt (below half) and When Close (a foe within 96 px). Others that read the simulation the same way: When Full (the staff's pool full: a big opener), When Clear (no foe within reach: a ranged cast that gives way to a melee one), When Whole (above half). Each is a row and a line.
4. **An enemy with a condition.** Proposed: none changed in this milestone; the Old Broom's second phase is the natural first (its phases are already state).
5. **Conditions in payloads.** Proposed: wasted for now.
