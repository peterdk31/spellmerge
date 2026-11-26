# Foundations: a floor that answers, fields, and the staff as a language

**Status (2026-11-25): the owner decided to build it, Part 1 first** (its first slice: [floor.md](floor.md)), Part 4 beside it in another session; the owner's answers to the open points are below. **Before that: design, for the owner to read (2026-11-25).** The owner parked the nine new cards ([new-cards.md](new-cards.md)): "I'm not sure that these new cards will actually enable builds I really want in the game. I think the fundamental building blocks needs more work", and asked for a design of three foundations: (1) a floor of materials, (2) field carriers, (3) staff-logic cards and wider numbers. This doc starts from the builds they should make possible, then gives each part's mechanism, what it does to the cards there are, and the decisions that are the owner's. Tuning numbers are left for each part's own milestone doc. A review against the code (2026-11-25) corrected the first draft; each part now says what is there today and what is new engine work. The owner continues it later.

**Part 2, fields, is built (2026-11-26):** its doc is [field.md](field.md). **The owner's answers (2026-11-25):** the order can turn: Part 4, the language (builds 9 to 12), is built now, beside Part 1, the floor; its own doc is [staff-language.md](staff-language.md). **Open point 6, a card that stands for another card, stays not proposed.**

## Why these three

A spell today flies, hits a body and puts a status on it. The cards are deep in that one line. Three things a spell cannot do:

1. **Meet the world.** The floor answers only where there is grass or cobweb, and only to where a spell ends.
2. **Meet another spell and change it.** Only a Portal changes a shot that is already flying, and only its element.
3. **Change how its own staff is read.** Four multicasts are the whole of it.

Each part below opens one of them. Each is judged by the builds it opens, so the builds come first.

## The builds to make possible

| # | The build, as played | Needs |
| --- | --- | --- |
| 1 | **The lake.** A water Nova soaks the floor round a crowd. One lightning atom into the water, and everybody standing in it is zapped. | 1 |
| 2 | **Oil and a match.** A spray lays oil down a corridor as the enemies come. One fire atom, and the corridor burns; they will not walk into it. | 1 |
| 3 | **The fire road.** A dash that spills oil behind it, and a second staff that lights it: a wall of fire drawn by moving. | 1 |
| 4 | **Ice bridge.** A fountain's puddle, frozen: whoever stands on it is chilled, and fire cannot cross it. Thawed by fire, it is water again, for the lake. | 1 |
| 5 | **The gun line.** One player lays a fire field. Everybody's bolts through it come out burning; a frost bolt through it sets off Thaw on what it hits. | 2 |
| 6 | **The ricochet gate.** A bounce field at a corridor's mouth: everybody's bolts through it come off the walls beyond. | 2 |
| 7 | **The dam.** A field that stops every shot that enters it until it ends. A volley piles up in it, the enemies' too, and leaves all at once. | 2 |
| 8 | **The bend.** A homing field between you and a pillar: straight shots fired past the pillar turn toward the foe behind it. | 2 |
| 9 | **The echo chamber.** A familiar that fires whenever any of your staffs casts. Four staffs, one orchestra. | 3 |
| 10 | **The panic button.** A staff whose first cast, a barrier and a blink, only leaves when you are below half health; otherwise the same press goes on to its second cast. | 3 |
| 11 | **Point blank.** A bolt whose life is cut to nothing: it ends at the staff's tip, so its blast and its `on expire` go off there. Any payload becomes a melee strike. | 3 |
| 12 | **The quick hand.** A dear, slow cast made spammable by cards that take its wind-down away, at a price in mana. | 3 |
| 13 | **All of it.** Oil road, lit through a fire field by a staff that fires at once: three players, three parts. | 1, 2, 3 |

A block below that none of these needs is not in this doc.

## What the first answer got wrong

Three things said to the owner before the code was read, corrected here:

- "Every carrier becomes a way to paint the room." Today only a spell's end touches the floor (a shot's or a ray's end, a blast, a pulse's end, a pool's landing and ticks). A shot in flight, a dash and a spray's cone touch nothing. Who touches the floor where is a decision (part 1).
- "The reaction table could carry it." Reactions run only in Combat, on a body. Ground cover has its own rows (an element moves a cell to another state). Part 1 uses cover's rows and does not join the two.
- "Card numbers are held in ranges." Nothing clamps a compiled number, and stacking has no end already (four Slow cards: 81 times the life). What stops the wilder builds is that a wind-up and a wind-down stop at 0, no card can add or take away a fixed amount, and each card is read once (part 3).

## Part 1: a floor that answers

### What is there

Ground cover (`gameplay/cover/`) is already most of this: a 16 px grid in the simulation, hashed and in snapshots, stepped only where a room is awake. A cell has a state of its kind; a state has a look, a status it gives the bodies standing in it, a spread to its neighbours by an element, and moves to other states (by an element that touches it, or after a time). Grass catches fire, burns, spreads, and turns to ash; wet grass will not light; a cobweb chills. Enemies already avoid cover that harms.

What is missing: **bare floor is nothing.** A touch on a cell with no cover is dropped, so water on flagstones does nothing.

### The mechanism

**Bare floor becomes a kind of cover**, `content/cover/floor/`, on every open cell no other kind has. Its states, all on rules and statuses there are today:

| State | Comes from | Gives who stands in it | Moves on |
| --- | --- | --- | --- |
| dry (rest, nothing drawn) | | nothing | water: wet. oil: oiled |
| wet | water on dry | soak | frost: ice. lightning: live. fire: steam. A while: dry |
| live | lightning on wet | a zap: a small lightning hit, which on a soaked body sets off Current | spreads to wet neighbours fast; a moment: spent |
| spent | live, after | soak | a moment: wet (lightning does not light it, so a lake is live once and not for ever) |
| ice | frost on wet | chill | fire: wet. A while: wet |
| steam | fire on wet | nothing | a moment: dry |
| oiled | oil on dry | nothing | fire: burning. A long while: dry |
| burning | fire on oiled | burn | spreads to oiled neighbours; a while: scorched |
| scorched | burning, after | nothing | a while: dry |

- **No new state in the simulation.** The cell's kind stays worked out from the room; only the state and age that every cover cell has are kept, and a cell at rest costs nothing. (To check in the build: the cost of every room having cover, where rooms without any skip the step today.)
- **No new status.** Soak, chill and burn are what the floor gives. Slipping on ice would be new code in the mover and is left out (open point 5).
- **New in the cover's engine, found by the review:**
  - **A state that hits.** Cover gives statuses only, and static does nothing until a hit lands. So live water needs a state that sends a small hit to who stands in it.
  - **A faster spread.** A spread is at most once a second a neighbour today; a lake that goes live needs it within a few ticks.
  - **Harm apart from status.** The AI walks out of every cell that gives a status, soak and chill too, so enemies would leave a puddle before the lightning comes. Only states that hurt (burning, live) should count as danger.
  - **Ice's chill** must wear off between two askings, as the cobweb's does by its data, or standing on ice freezes.
- **New in the layout** (still worked out from the room, so still no state): the `floor` kind fills, as a last pass, every open cell no other kind took, a door's, a spawn's and a placement's too, which no cover takes today. A cell holds one kind, so a cell of grass or cobweb is a hole in a lake until those kinds get rows of their own for lightning and oil.
- **A new look.** Cover is drawn as tufts. A puddle, oil and ice are flat and join their neighbours, so the view needs a second way to draw a kind (as a pool's overlapping shots are drawn as one). This and its art are most of part 1's work.
- **Props join in with no change:** a fountain's pulse wets the floor round it, and a barrel's fire blast lights oil.
- **Rooms that start with oil or water** need more: a room lays a kind today, never a state. To design in part 1's own doc.

### Two new cards

- **Oil** (infusion): "Coats the floor where it lands. Burns long once lit." An infusion with no status, as Mend has none: its point is the floor. On a body it does nothing by itself in the first build.
- **Spill** (modifier): "The next carrier touches the floor all along its way." A shot in flight, a dash and a swing touch nothing today; with Spill they lay their infusions as they go. This is the card that makes builds 2 and 3.

### Who touches the floor

Proposed, as one rule: **a spell touches the floor where it lands, and a spell that pours touches it where it pours.** That keeps today's ends, and adds a Spray's cone and a Beam's end on each of their ticks. Everything else that moves touches along its way only with Spill.

### What it does to the cards there are

- Every infusion gains a second use: water, frost, fire and lightning each change the floor.
- Blast, Nova, Skyfall, Pulse, Pool and Rune become ways to shape a patch (they end, so they touch).
- Split and Scatter cover ground; Linger and Slow choose where.
- `on reaction` and Chain do not read the floor: it is no body.
- Mend, Storm and Void do nothing to the floor in the first build. (Storm fanning a fire's spread is the natural next rule.)

### What it costs and risks

- **Whose harm is it?** The floor's statuses are sent as nobody's today. So a kill by a burning floor sets off no `on kill`, pays no Siphon, and is nobody's in the run's numbers. Remembering who lit a cell is a byte a cell of new state (open point 3).
- **Readability.** A room half on fire with four players is the chaos pillar 4 asks to keep readable. The states are few on purpose, and each needs a look that reads at a glance.
- **More touches reach the other listeners.** Element locks and secret rocks also hear a touch on the floor. A Spray or a Spill touches far more often than an end does, so they open those more easily. To check against the rooms that use them.
- **Names.** "Ground material" already means the drawn floor of a room (`content/grounds/`). This is cover of kind `floor`, and the docs say "the floor's cover".

## Part 2: fields

### What is there

A Portal already changes a shot that is flying: a shot that comes out of it takes its elements, and homing if it had none (`Spells._infuse_shot`). The projectile manager can set on a live shot: its speed curve, homing, linger, growth, bounce, ghost, spiral, return, sticky, shield and deflect. Bodies in an area are served already: a Pool strikes whoever stands in it, and cover gives a status.

So a field is defined narrowly: **a zone that changes shots.** Bodies stay the Pool's and the floor's.

### The mechanism

One carrier, **Field** (`content/spells/carriers/field/`, `core/spells/carriers/field.gd`): "A circle ahead. Shots through it take the cards on it."

- **It hits nothing.** It stays where it is cast for its life, as a rune does.
- **A card's numbers shape the field; a card's behaviour or element is what it gives.** Bigger and Reach make it wider and farther, Slow makes it last; an infusion or a behaviour card before it is given to each shot that enters. (So Faster and Slow, which are numbers only, change the field and never a shot's speed. A field that speeds shots up needs a behaviour of its own and a new way to scale a live shot's speed: later.)
- **Anyone's shots,** as with a portal: a teammate's and an enemy's.
- **A shot takes a field once each time it enters.**
- **Every shot is seen (new).** The test of shots against a portal's gates takes only shots that fly straight. A field's test must see the others too (an orbiting shot, a spiral), and what each may take: Homing and Return are refused on an orbiting shot today.
- **What a shot can take** is what can be set on a live shot:

| Card on the field | A shot that enters |
| --- | --- |
| an infusion | takes the element and its status |
| Homing | homes |
| Linger | stops until the field ends (build 7; a new hold that the field lets go, since a shot's own Linger stops it once, at half its life) |
| Bounce, Ghost, Spiral, Return, Sticky, Growth | gains it |
| Shield, Deflect | becomes a ward, or turns others' shots |

- **What it cannot take, and so does nothing on a field** (marked in the builder, checked by `test_card_rules`): Split, Chain, Pierce, Overcharge and the other damage numbers, Blast, Zap. A flying shot's damage and its count are its build's, and a field does not rebuild a shot. (Pierce is a number a shot, with no way to set it live today; it could get one.)
- **Triggers:** Timer, `on near`, `on recast` and `on expire` work on it as on any carrier that lasts.
- **Beams** take the elements for the stretch past the field, as through a portal. Not in the first build.

### What it costs and risks

- **A shot that takes an element is hit alone** from then on: its hits are no longer merged with its build's others (as a relayed shot's today). A crowd's worth of shots through a fire field must be measured in the stress run before it merges.
- **It hands enemies your cards too.** An enemy bolt through your homing field homes on you. That is the rule everywhere else (a portal, a deflect), and it is the reason to place a field with care.
- **This is the pane the owner passed on** in the first proposals ("shots through it take its cards"), made into the general thing: one carrier whose cards are its meaning. The carrier that catches shots is now `linger · field`, with no code of its own.
- **Not in it:** haste for bodies (a body's pace cannot go above 1 today, and the owner dropped slow motion), and a field that bends paths toward its middle (a new pass in the shots' hot loop and its native mirror). Each can come later as a field's card.

### Carriers after Field

Boulder and Grip ([new-cards.md](new-cards.md)) are the other new kinds of carrier: things with weight, and a hand on a body. They get better with part 1 (a boulder through oil, a body thrown into fire) and are better judged once the floor is in.

## Part 3: the staff as a language

### What is there

Compiling a staff is pure: cards in, a fixed plan out, and nothing about a card's meaning is decided while playing. The rules that shape it:

- Each card is read once in a cast, and meeting a card already read ends the cast. That is what keeps every staff finite.
- A modifier lands on one carrier ("one card, one target").
- At runtime the only choice is which cast leaves: one the pool cannot pay is skipped.
- A build of more than 512 nodes is refused.

So the language has two places a new kind of card can live without breaking it: **in the compiler** (the plan changes, play does not) and **in the skip rule** (a cast leaves or is skipped).

### Three mechanisms

**A. Numbers that add and take away** (compiler only; builds 11 and 12)

Most numbers on a modifier are factors today; a wind-up and a pierce can be added to, and nothing can be taken away. Two new kinds of number:

- **A fixed amount off the wind-down** (`wind_down_add`, below 0 allowed). The floor at 0 is each carrier's today and would become the cast's, a change; the staff's own cooldown after a cycle stays out of any card's reach. A card with it, priced in mana, makes a slow cast quick when stacked: the quick hand.
- **A most for the life** (new: `lifetime_base` is there but the longest of them counts, so it can only lengthen). A card that caps the next shot's life at almost nothing ends it at the staff's tip: point blank. Its blast strikes its caster too, as every blast does.

These are numbers cards: the engine work is the two fields in the compiler.

**B. Gates** (the skip rule; build 10)

A gate is a card that says when its cast may leave: **"this cast leaves only while X; otherwise it is skipped, as a cast the pool cannot pay."** The skip, the cursor moving on and the cycle's end are today's code.

- X is read from the simulation at the press, so it is the same on every machine: the caster below half health, a foe within reach, the pool full. The Caster hands these to Spells with the press, as it hands the mana.
- A gate is a modifier with a behaviour (a sixth class of card would fall through the reader), so it sits in the staff like any card, and its cast is marked in the tree with its condition.
- **One rule in three places:** the HUD's ready mark and the AI's telegraph ask the same question as the skip (`firing_cast`, `next_cast_mana`, `cast_ready`), so all three read the gate.
- **A staff of gated casts only** fizzles when none may leave, and its cooldown runs, as a staff the pool cannot pay. A gated cast wants an ungated one after it.
- **The word:** "gate" is already the portal's in the code; the card kind needs another name (a condition).
- Enemy staffs get them too: a gate is a boss phase written as a card.

**C. Hearing the other staffs** (one trigger; build 9)

The four staffs are separate, and no card knows another staff exists. The smallest thing that joins them: a trigger, **On Any Cast**: "Casts its spell when any of your staffs casts." It is one of the triggers that listen while their carrier lasts (as `on hurt` listens for a hurt), hearing an event there is already (`cast_left`).

- It does not cast a staff from a staff, so every staff keeps its own cursor, cooldown and pool. A payload sends no such event, so two of them cannot set each other off for ever.
- The event is sent for every cast of a staff, each one of a held spray too, so a held stream fires it at the stream's pace.
- The carrier that casts the next staff, which the owner passed on, stays possible on top of it later.

### What is not proposed, and why

- **A card that stands for another card** (a copy, a repeat). It breaks "one card, one target" and "each card is read once", the tree draws each slot as the card that lies in it, and the owner passed on it once. It is the strongest card of this kind in any game of the sort, so it is an open point and not a proposal (open point 6).
- **Anything on the "wait" list** of cast-timing.md: payloads paying their own mana, cards that change a staff's cooldown, limited uses.

### Reading it in the builder

A card that was "hard to understand" was cut once (Quicken). So each mechanism has a reading test:

- A: a number, shown as every card's numbers are ("Delay -0.25 s").
- B: the gated cast's row in the tree carries the gate's icon and four words ("only when hurt").
- C: a trigger like the others; its row says "any cast".

## The order

1. **The floor's first slice:** the `floor` kind with dry, wet, ice, live and steam, the flat look, and Spray and Beam touching where they pour. No new card: builds 1 and 4 work with the cards there are.
2. **Oil and Spill:** the two cards and the oiled, burning and scorched states. Builds 2 and 3.
3. **Field:** the carrier and the table above. Builds 5 to 8.
4. **The language:** the two numbers, the gates, On Any Cast. Builds 9 to 12.

Each is a milestone doc of its own before it is built, with its numbers, its tests and its measures.

## Open points for the owner

**The owner's answers (2026-11-25):** 1. yes, bare floor is cover everywhere. 2. **The other way:** everything touches the floor as it passes, every shot, dash and swing, not only what pours; its cost designed and measured (the projectile manager's passes and its native kernel, a budget test, the stress run and play frames before and after). 3. **The other way:** a cell remembers who lit it, so `on kill` and Siphon count (simulation state: hashed, snapshotted, determinism tests). 4. yes, a field serves enemies' shots too, one rule (for Part 3). 5. ice chills, no slipping. So Spill's point changes, and the owner set it (2026-11-25): **Spill makes a shot touch a wide area where it lands** (a bigger splash), for Part 2's own doc.

The points as they were put:


1. **Bare floor as cover everywhere.** Proposed: yes; it is what makes the floor answer with no new state. The other way is cover only where a spell has laid it, which needs the cell's kind kept as state.
2. **Who touches the floor along the way.** Proposed: only what pours (Spray, a Beam's end), and everything else with the Spill card. The other way is every shot, dash and swing touching as it goes: more chaos with no card, less control, and a cost for every shot in flight.
3. **Whose harm the floor's is.** Proposed for the first slice: nobody's, as today. The other way is a cell remembering who lit it, so `on kill` and Siphon count.
4. **A field serves enemies' shots too.** Proposed: yes, one rule. The other way is a field for its team only, which is a rule about teams deciding more than aim.
5. **Ice.** Proposed: it chills. Slipping (a body keeps its way on ice) is new code in the mover and its native mirror; a milestone of its own if wanted.
6. **A card that stands for another card.** Not proposed, and it stays so (the owner, 2026-11-25). If the owner wants it later, it needs its own design: how the tree shows it, and what "read once" becomes.
7. **Which builds matter most.** The order above follows the builds' numbers. If builds 5 to 8 or 9 to 12 are the ones the owner wants first, the parts do not depend on each other and the order can turn.
