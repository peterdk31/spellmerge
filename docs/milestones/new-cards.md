# New cards: nine cards for wilder builds

**Status: parked by the owner (2026-11-25), before any of it was built.** The owner: "I'm not sure that these new cards will actually enable builds I really want in the game. I think the fundamental building blocks needs more work." The foundations come first (a floor of materials, field carriers, staff-logic cards); Boulder and Grip may come back with them. What follows is the design as it stood. The owner asked for new cards "to make the game more fun and enable even crazier builds", picked six of fourteen proposals, turned a seventh into Electric Fence ("arcs flying between affected bolts") and asked for more carriers ("to increase the build diversity"), of which two were picked. Each card below has its rule, its starting numbers, what is there today and what is new code, two combos and the engine work. A review against the code (2026-11-25) corrected the first draft; what it could not settle is marked "to check in the build". The open points at the end are the owner's to answer before the build.

| Card | Kind | Builder line (at most 60 characters) | Engine work |
| --- | --- | --- | --- |
| Chorus | multicast | "Every carrier on the staff leaves together, as one cast." | small: the compiler |
| Fervor | modifier | "Each cast in a row is faster, until you stop." | small: a count per staff |
| Last Drop | modifier | "Spends all the staff's mana; hits harder for each point." | medium: Caster, Spells, a factor per cast |
| Blood Price | modifier | "The next carrier costs health, not mana." | medium: compiler, Caster, Spells, Combat |
| On Cross | trigger | "Casts its spell where its shot meets another shot." | medium: a new sweep of shots, measured |
| Electric Fence | modifier | "Arcs join the next shots; what crosses an arc is zapped." | medium to large: behaviour and look |
| Grip | carrier | "Lifts what you aim at, then throws it where you aim." | medium to large: a carrier, a new kind of carry |
| Raise | modifier | "What the next shot kills gets up and fights for you, 8 s." | medium to large: `gameplay/actor`, Flow, Rewards |
| Boulder | carrier | "A heavy stone. Hit it, and it rolls: yours or anyone's." | large: a carrier that is a body |

## Why they fit the pillars

- **Deep spell building (pillar 1).** The cards today are strong on what a shot is and how it flies. These add what the set lacks: how a staff is read (Chorus), what a cast is paid with and how fast (Blood Price, Last Drop, Fervor), shots that answer other shots (On Cross, Electric Fence), and two carriers that are things the other cards act on (Boulder, Grip).
- **No special cases** (the owner, 2026-10-27). Each card is one rule, and what happens with the other cards follows from the rules those cards already have. Where a rule would need an exception, it is an open point instead.
- **Everything hurts everything.** A fence's arc zaps its caster, a boulder runs its caster over, a grip lifts a friend as it lifts a foe, and Blood Price can down the wizard who pays it.
- **No build limits.** None of the cards has a cap of its own.
- **The same on every machine.** Nothing here rolls dice. Where an order matters (a fence's nearest posts, which body a grip takes), ties go to the older shot or the lower actor id.
- **Readable chaos (pillar 4).** A fence's arcs are drawn where they hit, a boulder is a body anybody can see coming, and a raised enemy loses its angry brows.
- **No card made obsolete** (content/spells/README.md: one that does needs a rebalance, not an addition). Each card names the card nearest to it and why both keep a use.

## The cards

### Chorus (multicast)

`content/spells/multicasts/chorus/`, a `MulticastBase` with a new mode, `ALL`; 6 mana.

**Rule:** its group is every other carrier on the staff: it reads on from its slot, wraps, and stops when it is back at itself. No carrier is drawn twice (as a multicast reads today, `StaffCompiler`).

- **Where it sits matters.** A staff's cycle starts at its first slot, so a carrier before Chorus is a cast of its own first, and is then drawn into the chorus as well. Chorus in the first slot makes the whole staff one cast.
- Mana, wind-ups and wind-downs add up as a multicast's do today, so a full staff is one long, dear cast. That is its price.
- A trigger still takes what follows its carrier as its payload.
- In a payload it reads on round the staff as a payload does today.
- **Nearest card:** Triple. On a staff of three carriers they do the same; Triple keeps a cycle of several casts on a longer staff, and Chorus ends it.

Combos:
- `chorus_escape`: `chorus · rune · wall · decoy · dash` leaves a rune, a wall and a decoy behind one dash.
- `chorus_flare`: `chorus · fire · bolt · storm · bolt` lands burn and gust together, which sets off Flare.

Engine work: the mode in `MulticastBase`, its read in `StaffCompiler` (`_read_group`, `_take_multicasts`). No runtime change.

### Fervor (modifier)

`content/spells/modifiers/fervor/`, behaviour `fervor`, strength 0.9, `mana_mult` 1.2.

**Rule:** every staff counts its casts in a row. A cast with Fervor has its cards' wind-up and its wind-down multiplied by 0.9 for each cast counted. The count ends when the staff has been ready and not pressed for `SpellLimits.FERVOR_REST` (0.5 s).

- The count is the staff's, and every cast of the staff adds to it. Only casts with Fervor are faster.
- Two Fervor cards multiply (0.81 a cast).
- **What it leaves alone:** the staff's own wind-up, which is an enemy's telegraph, the staff's cooldown (cards that change it are on "wait" in cast-timing.md, "Later") and a trigger's own share of a payload's wind-up (cast timing T9).
- It has no floor of its own. Mana is the brake: a stream that speeds up empties its pool sooner.
- **Nearest card:** Faster Casting, which is always on and halves at once. Fervor is earned over many casts and lost by resting.

Combos:
- `fervor_stream`: `fervor · atom`, held, fires faster with every atom until the pool is empty.
- `fervor_hammer`: `fervor · charge · slam` shortens the charge with every swing in a row.

Engine work: a count and a rest clock per actor and staff in `Spells` (state, so snapshots keep it), read where a cast's timings are set (`cast_staff`, `_after_cast`). Small.

### Last Drop (modifier)

`content/spells/modifiers/last_drop/`, behaviour `last_drop`, `wind_down_mult` 1.5.

**Rule:** the cast it is in spends all the free mana of its staff's pool, and the carrier after the card hits harder by what the cast paid over what it would have cost.

- A cast the pool cannot pay at its usual cost is skipped, as today.
- Mana set aside by a Hold is not free and is not spent.
- The factor is linear and has no most: a 5 mana bolt from a pool of 100 hits 20 times as hard.
- **In a payload:** a cast pays once, at the press, for its payloads too (`StaffCompiler`). So the pool is spent at the press, and the factor rides with the cast to the payload's carrier.
- **Nearest card:** Overcharge, which doubles a hit and lets the staff keep casting. Last Drop empties the staff for one hit.

Combos:
- `last_drop_refill`: `last drop · siphon · pierce · bolt` spends the pool on one piercing shot, and each body it passes pays some back.
- `last_drop_ring`: `last drop · nova · beam` on a full pool is one ring of beams.

Engine work: the pool is the Caster's (`gameplay/actor/caster.gd`), so the press tells Spells the free mana and spends what Spells says; the factor is a number of that cast (the compiled profile is shared by every cast of the build, so it cannot sit there). Medium. It is the card form of the backlog's relic idea (#416).

### Blood Price (modifier)

`content/spells/modifiers/blood_price/`, behaviour `blood_price`, strength 0.5 (health a point of mana: a wizard has 100 health, so a 5 mana bolt costs 2.5).

**Rule:** the share of its cast that the next carrier costs is paid by the caster's body as a hurt, not from the staff's pool.

- **The compiler splits the cast's cost** into a mana part and a health part: the carrier's own share (its cost times its cards' `mana_mult`) moves to the health part. Whether the cast can be paid is asked of the mana part only.
- **When:** at the press, with the rest of the cast, as a cast pays once for its payloads too. A Blood Price carrier in a payload moves its share the same way, so a Timer's payload is paid for once, however often it fires.
- **The payment is a hit on the caster** through Combat, so a barrier takes it whole (a free cast while one lasts), `actor_hurt` goes out and `on hurt` fires, and it can down the caster. A hex on the caster makes it dearer, as it does any hit.
- **It is a cost, not a blow:** a hit of kind `price` has no hit-stop, shake or shove, only a small cue of its own, and starts no protection after it (to check in the build: `Health`'s protection).
- A cast that is all Blood Price is never skipped for mana.
- **Hold** sets the mana part aside; the health part is paid once, at the press.
- **With Last Drop:** Last Drop spends the pool whatever the cast costs, and Blood Price moves only the carrier's usual share to health. Both are paid.
- It does nothing on a carrier that costs no mana (a swing, a slam), and the builder marks it so.
- **Nearest card:** Siphon, which gives mana back only when the shot hits. Blood Price always works and always costs.

Combos:
- `blood_price_nova`: staff 0 holds `on hurt · orbit · hold · bolt · nova · atom`; every cast of staff 1, `blood price · bolt`, sets the nova off.
- `blood_price_heavy`: `blood price · overcharge · lumber · bolt` leaves its pool full and takes its 27.5 mana as 13.75 health.

Engine work: the split in `StaffCompiler`, the health part through the press (`Caster`, `Spells`), and a new event with an amount that Combat hears and deals as a hit (it hears none today). Medium.

### On Cross (trigger)

`content/spells/triggers/on_cross/`, a new `TriggerBase.Event.CROSS`, with `NEEDS` of `MEETS_SHOTS`.

**Rule:** the payload fires where its carrier touches another shot, anybody's.

- **This is a new sweep.** What Shield and Deflect meet today is other teams' shots only (`ProjectileManager`). On Cross meets every team's, its own caster's too.
- **What counts as a shot:** the projectile manager's shots (an atom, a bolt, a rune, a pool, a wall's pieces, a swap's charm, an orbiting shot). A beam, a swing and a ring are no shots, so they cross nothing.
- A shot is spared from the shots it is touching when either is born, until they have parted, as a carrier spares the body it starts on. So a Split's fan fires nothing as it leaves.
- **A step's meetings of one shot are one meeting** (as a step's hits of one spell on one body are one hit: the owner, 2026-11-17). Five bolts that meet in one point fire five payloads, not twenty.
- Two shots that part and meet again (an orbit's laps) fire again.
- Neither shot is stopped or turned. That stays Shield's and Deflect's.
- When both shots have On Cross, both fire.
- **Nearest card:** On Block, which needs a Shield or a Deflect and stops or turns the shot. On Cross needs neither and stops nothing.

Combos:
- `on_cross_pentagon`: `penta · pierce · on cross · bolt · blast · pulse`: five bolts meet in the middle of their ring and each sends a ring out there. (Pierce takes them through a body that stands in the middle. Cast by a wizard and not from a payload, that body is the wizard, as with any Penta.)
- `on_cross_ward`: `on cross · orbit · hold · bolt · nova · atom`: a ward that answers every shot that crosses it with eight atoms.

Engine work: the event, and an any-team sweep of shots against shots in the projectile manager, only for shots whose build has the trigger. Its cost is measured in the stress benchmark before it merges; if the sweep sits in the shots' hot loop, the native kernel mirrors it (to check in the build).

### Electric Fence (modifier)

`content/spells/modifiers/fence/`, behaviour `fence`, strength 2 (arcs a post), `behaviour_reach` 96 px, `mana_mult` 1.5, needs `STAYS`.

**Rule:** every live shot with the card is a post, whoever cast it (the owner, 2026-11-25: anyone's). A post arcs to its two nearest posts in reach, and whatever crosses an arc is zapped.

- **What can be a post:** a shot that stays in the world: a bolt, an atom, a rune, a pool, a wall's pieces, a swap's charm, a portal's gate. Not a beam.
- **Which posts:** the nearest in reach; of two as near, the older shot. Two posts share one arc between them.
- **Walls:** an arc never passes a wall. Ghost on a post takes its arcs through.
- **The hit:** every `SpellLimits.BEAM_TICK` an arc hits each body its line crosses, at `SpellLimits.ZAP_DAMAGE` of a post's damage with that post's infusions. The two ends take turns, so an arc between a fire post and a frost post sets off Thaw on what stands in it.
- **It hits every body,** as a beam's line does, its caster too. (The Zap card picks only its caster's foes; a fence picks nobody, it is crossed.) A fence is not walked through; a ring of orbiting posts round the caster passes them by.
- An arc's hit sets off `on hit` and chains, as a zap's does.
- More cards add arcs a post (two cards: four).
- **Its look:** each arc is spark motes along a jagged line between its posts, in the tint of the end whose turn it is. It grows from one post to the other when it forms and draws back when it breaks (docs/STYLE.md, "Smooth").
- **Nearest card:** Zap, which hits foes near one shot, by chance. A fence hits what is between two shots, always.

Combos:
- `fence_net`: `fence · split · bolt` is a net of three bolts that zaps what passes between them.
- `fence_ring`: `fence · nova · slow · bolt` is a ring of eight posts that widens, zapping what its arcs sweep over.

Engine work: the posts kept by the projectile manager, the pairing every few steps, the arcs' hits (`ProjectileManager.ray`, the line query a beam uses) and the look in `gameplay/feel`. Medium to large.

### Grip (carrier)

`content/spells/carriers/grip/`, `carrier = &"grip"`, a new `core/spells/carriers/grip.gd`.

| Field | Value | What it means on a grip |
| --- | --- | --- |
| `mana_cost` | 10 | |
| `lifetime` | 1.2 s | how long it holds before it throws |
| `ray_length` | 96 px | how far along the aim it takes a body |
| `base_damage` | 1 | each tick on the held body, and the throw |
| `knockback` | 700 px/s | the throw |
| `wind_down` | 0.3 s | |
| `complexity` | 3 | |

**Rule:** it takes the first body on its aim line and holds it ahead of the staff for its life. Its last hit throws the body along the aim.

- **One cast, one hold.** It is not renewed by holding fire. `hold · grip` keeps the body until the next cast, by Hold's own rule.
- **What it takes:** what Plow may carry: never a body that cannot move, one carried already, one that carries a body itself, or its own caster. A friend is taken as a foe is.
- **With no body on its line** it holds nothing: the cast is spent.
- **Held:** the body is carried `SpellLimits.GRIP_FRONT` (28 px) ahead of the staff tip and follows the aim. It can still aim and cast.
- **What frees it, by Plow's rule:** a body put far away is let go with no throw. So a held body's own dash, teleport or swap, or a portal it is pushed into, ends the grip.
- **New: a held body's own walk does not move it.** A body that Plow carries can walk out sideways today; a grip that anybody walks out of would hold nothing.
- **Walls, by Plow's rule:** pressed head on into a wall it is pinned: the pin's damage is dealt and the grip ends. Aiming a held body into a wall is a way to use it.
- **The hit:** every `SpellLimits.BEAM_TICK` the held body takes the carrier's hit with its infusions. `fire · grip` burns what it holds and `mend · grip` heals it.
- **The throw is the grip's last hit,** with its knockback. So Heavy multiplies it and arms the hurt at a wall, and a storm grip throws twice as hard. (A carry that is only let go shoves and arms nothing today.)
- **Its traits:** `LASTS`, `HITS`, `STEERS`, `MELEE`, with `SHOTS` and `PIERCE` (Split takes three bodies, Pierce takes more along its line). By the rules that follows from: Hold, Homing, Chain, Heavy, Possess, Barrier and Pull work on it; Bounce, Return, Orbit, Skyfall, Magnet and Electric Fence do nothing.
- **Triggers:** `on hit` fires at the held body on each tick, Timer fires from the held body along the aim, `on expire` fires from where it is thrown.
- **Nearest card:** Plow. `plow · dash` carries a body along a path the caster takes; a grip holds it where the caster aims, and throws.

Combos:
- `grip_throw`: `heavy · grip` on an imp, thrown at a wall: the wall hurts it.
- `grip_gun`: `timer · grip · bolt` holds an imp and fires bolts from it into the ones behind.

Engine work: the carrier script; a new kind of carry in `Plow` (its carrier a point that follows the aim, and no walking out); its staff pose and look. Medium to large.

### Raise (modifier)

`content/spells/modifiers/raise/`, behaviour `raise`, strength 8 (seconds), `mana_mult` 2.0, `wind_down_mult` 1.5, needs `HITS` (or a Blast).

**Rule:** a body the carrier's hit kills gets up where it fell, on its caster's team, for 8 seconds. Then it falls for good.

- **The death is a death.** Today a killed enemy's body is freed at once, and Flow and Rewards count it (`enemy_died`). That stays: the kill counts once, for the room and for rewards.
- **What gets up is a new body of the same kind,** made as a summon is, after `SpellLimits.RAISE_SECONDS` (0.6 s, its getting-up frames), with half its health and its own brain, which aims at its new team's foes (a body's team follows its controller, as with Possess).
- **Its fall is no enemy's death:** it counts for no room and no reward, as a decoy's does not (to check in the build: how Flow tells them apart).
- It hurts and is hurt as everything is. A Raise that kills it raises it again.
- **Resist:** it reads the stat Possess reads (`Stats.POSSESS`): the time is (1 - share) as long, and a share of 1 never rises. The Old Broom resists 0.7, so it would rise for 2.4 s (open point 8).
- A downed wizard is not killed, so Raise does nothing to one.
- **Its look:** its brows are no longer angry, and it trails motes in its raiser's colour. (A stray's eye colour already means its element, so the eyes stay.)
- **Nearest card:** Possess, which takes the living for 3 seconds and the player drives them. Raise takes the dead for 8 and they drive themselves.

Combos:
- `raise_chain`: `raise · chain · bolt` on three weak imps: each jump that kills adds a fighter.
- `raise_blast`: `raise · on kill · bolt · blast · pulse`: each kill raises a fighter and bursts.

Engine work: `raise_requested` in `core/events`, the rule in `gameplay/actor` beside `possession.gd`, the summon's spawn, Flow's and Rewards' count, and its look. Medium to large.

### Boulder (carrier)

`content/spells/carriers/boulder/`, `carrier = &"boulder"`, a new `core/spells/carriers/boulder.gd`.

| Field | Value | What it means on a boulder |
| --- | --- | --- |
| `mana_cost` | 12 | |
| `wind_up` | 0.25 s | the heave |
| `wind_down` | 0.8 s | |
| `speed` | 60 px/s | the first shove it is cast with |
| `lifetime` | 12 s | |
| `radius` | 10 px | |
| `base_damage` | 6 | what it deals at 100 px/s |
| `complexity` | 3 | |

**Rule:** it is a body. Every hit shoves it, and it hits what it runs into by its speed.

- **A body of the world:** Combat knows it, with no health (possible today) and the world's team (`Actors.TEAM_WORLD`). Its end is its lifetime. Being the world's, nothing aims at it: homing, Magnet and Zap pass it by, as they pass a prop.
- **Its speed is its own (new).** Any body's shove today replaces the last one and dies away fast, so a beam's ticks build nothing. A boulder adds each hit's knockback to its speed and loses it slowly (`SpellLimits.BOULDER_DRAG`). A swing bats it, a beam pushes it faster every tick, a storm hit shoves it twice as hard, Heavy more.
- **Its strike:** above `SpellLimits.BOULDER_HURT_SPEED` (80 px/s) a body it runs into is hit for its damage times its speed over 100 and shoved along its way, and the boulder keeps 0.7 of its speed. Its cards ride on that hit: infusions, `on hit`, Chain, Possess, Raise.
- **It runs its caster over** like anybody.
- **Shots:** a shot that hits it is spent on it, as on any body.
- **What moves any body moves it, by rules that exist:** a portal takes it through (to check in the build: the gate's size), Swap trades places with it, Plow and Grip carry it, Pull drags its caster to it.
- **Its traits:** `FLIES`, `MOVES`, `HITS`, `LASTS`, `STEERS`, `MEETS_SHOTS`, `BLOCKS`, `SPAWNS`, `CASTS_FROM_BODY`. A carrier that says it flies must answer every card that needs one (`ModifierBase.RULES`), and the boulder answers them itself, in new code: Bounce (off a wall at the speed it had), Return (rolls back), Ghost (through walls), Plow (carries what it hits), Linger, Sticky, Spiral, Homing (rolls toward a foe) and `on wall` (it stops at a wall). This is most of its cost (open point 1).
- **What does nothing on it, by the rules as they are:** Orbit (it makes a body, not a row: `SPAWNS`), and Magnet, Zap, Growth and Electric Fence (it is no shot that stays: not `STAYS`).
- **Triggers:** `on hurt` fires when the boulder is hit (a carrier that is a body is hurt when its body is, as a decoy), Timer fires along its way, `on expire` where it ends.
- **Nearest cards:** Wall, which is wider and never moves, and Decoy, which draws fire. Nothing aims at a boulder.

Combos:
- `boulder_bat`: `boulder` on staff 0, then `heavy · swing` on staff 1 into it: it rolls through the imps beyond.
- `boulder_fountain`: `on hurt · boulder · nova · bolt` on staff 0 and a beam on staff 1: every tick of the beam on the boulder is eight bolts.

Engine work: the carrier script, a body with a mover and no brain, its own speed and strike, every flying card's answer, the AI's summary, its staff pose and look (a stone with a seam in its infusion's colour, dust motes by its speed). Large.

## The build

- **Order, cheapest first:** Chorus, Fervor, Last Drop, Blood Price, On Cross, Electric Fence, Grip, Raise, Boulder.
- **Each card is its folder:** the `.tres`, icon, `assets.json`, two combo files (named above) and `test_<id>.gd`. New behaviours and the new event get their rows in `ModifierBase.RULES` and `TriggerBase.NEEDS`, and `tests/core/test_card_rules.gd` plays them on every carrier by itself.
- **Tests are written with each card and run once, at the end** (the owner, 2026-11-25: "defer testing to the very end, to minimize the amount of time we are waiting for tests"): `tools/check.sh --author peterdk31`, `ci/build/native.sh linux` if a kernel changed, then `tools/ptest.sh`, then the review.
- **Outside the card folders:** `docs/DESIGN.md`'s list of cards, `content/spells/README.md` (the new carriers and mode), `docs/CARRIERS.md` (Grip and Boulder), cast-timing.md (Fervor, Blood Price's split), and the benchmark numbers for On Cross and Electric Fence in `docs/DECISIONS.md`.

## Open points for the owner

1. **Boulder's size.** Answering every flying card is most of its cost. The other way is a first Boulder that does not say it flies (Bounce, Return, Ghost, Plow and `on wall` do nothing on it, marked in the builder) and gets them later.
2. **Boulder's health.** Proposed: none, only its lifetime, so it also stops shots for 12 s. The other way is health, and it breaks (`on expire`) when it runs out.
3. **Fervor and the staff's cooldown.** Proposed: Fervor leaves it alone, as cast-timing.md has cards that change it on "wait". Including it makes Fervor far stronger on slow staffs.
4. **Fervor's floor.** Proposed: none. A staff with Fervor and Blood Price then casts as fast as its staff's own timings allow for as long as its wizard lives.
5. **Thrown bodies.** A body a grip throws does not hurt the bodies it lands on; only a wall does, with Heavy. One rule for all would be "a shoved body above a speed hits what it runs into, as a boulder does", which changes every knockback in the game. Not in this batch unless the owner wants it.
6. **Grip and pillar 2.** A grip on a friend moves them against their stick, more firmly than Plow does (they cannot walk out), and `hold · grip` holds them until the gripper casts again. Proposed: allowed, by "everything hurts everything"; the friend can still cast, at the gripper too, and a dash, teleport or swap of their own frees them.
7. **Raise and props.** A crate or a barrel has no brain. Proposed: Raise takes only bodies with a brain; a prop stays broken.
8. **Raise and bosses.** Proposed: no rule of its own. A boss's death counts as it does today, and what rises is a body of its kind on the raiser's team for the time its resist leaves (the Old Broom: 2.4 s). The other way is a possess resist of 1 on every boss, which is data, not a rule.
9. **One pull request or nine.** The cards touch the same tables (`ModifierBase.Behaviour`, `SpellLimits`), so nine branches would conflict. Proposed: one branch, one commit a card, in the order above.

## Not in this batch

Proposed and not picked (2026-11-25): a card that copies the card beside it, a carrier that casts the next staff, a payload that inherits its parent's cards, damage by distance flown, a pane that gives passing shots its cards, damage by statuses on the target, a random infusion; and the carriers that catch shots, mark a place to return to, follow the aim as a growing chain, and lay the spell where the caster walks.
