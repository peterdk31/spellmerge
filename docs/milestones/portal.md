# Portal: a carrier that sends shots, beams and bodies elsewhere

**Status: built (2026-11-05), for the owner's playtest.** The owner asked for "a portal cast: one staff fires a portal, you fire a beam into it, and the beam comes out of a different portal, or several in a circle round an enemy, to really cook them." Four answers settled the frame on 2026-11-05: (1) **one cast opens a mouth and its exits**; (2) **shots, beams and bodies all go through**; (3) **a beam leaving several exits is a full copy at each**; (4) this design note first, code after the owner's review. The owner then answered the open questions the same day: (1) the name stays **Portal**; (2) a body smaller than the gate goes through, so `bigger · portal` swallows bigger things; (3) everything that comes out of a portal takes its infusion; (4) **a portal works both ways** ("can be used against you then"); (5) the caster's own body goes through its own portal; (6) shield and deflect do nothing on a portal. Then: "Just build it all".

## Why it fits the pillars

- **Deep spell building (pillar 1).** A portal does nothing alone. It changes where every other spell goes: yours, a teammate's and an enemy's. Its cards do what they do anywhere, to what comes out of it (rework, owner 2026-11-05): split fans its exits, homing steers what leaves them, an infusion goes onto it. A carrier and no special cases.
- **Surprising combos.** It works across systems: beams, flying shots, knockback, magnet, infusions and triggers all do something new with it (the table below).
- **Everything hurts everything.** A portal belongs to no team. An enemy's bolt that flies into your mouth comes out of your exits, and a teammate's beam fired through it cooks your target.
- **Nobody waits (pillar 2).** A portal is walked into, never forced on anybody's choices. Being knocked through one is a hit like any other.
- **Readable chaos (pillar 4).** Each mouth and its exits share one colour (the caster's), and are drawn joined, so anybody can read where a shot will come out.

## The card

A form card, `content/spells/carriers/portal/`, `carrier = &"portal"`, a new `core/spells/carriers/portal.gd` (`CarrierPortal`). Starting numbers, for tuning in the playtest:

| Field | Value | What it means on a portal |
| --- | --- | --- |
| `mana_cost` | 10 | more than a rune (8): it multiplies other spells' damage |
| `cooldown` | 1.5 s | |
| `lifetime` | 4 s | how long the mouth and exits stay open |
| `radius` | 12 px | the size of the mouth and of each exit |
| `ray_length` | 160 px | how far ahead the exit opens (the reach of a beam is 240) |
| `shots` | 1 | how many exits |
| `spread` | 40° | how far apart several exits are fanned |
| `base_damage` | 0.05 (the minimum) | a portal hurts nothing itself |
| `complexity` | 3 | |

## The rules

**P1. One cast opens one mouth and `shots` exits.** The **mouth** opens a step ahead of the staff tip (`kit.placed_at`, as a rune does), facing along the aim. The **exits** open `ray_length` ahead along the aim, stopping before walls (`clip_to_walls`, as teleport and wall do), fanned as a split fans shots (`spread` apart, plus the staff's spread), **each facing out along its own way**. A portal cast as a payload opens where its payload fires, like any carrier (`on hit · bolt · portal` opens one where the bolt hit).

**P2. Its cards act on what comes out of it (rework, owner 2026-11-05: "to not have custom rules").** A portal has no rules of its own for its cards: each does to what leaves an exit what it does to a shot. Its **homing** steers what comes out onto a target (a shot takes the portal's homing when it has none of its own; a beam's leg bends as a homing beam does), its **infusion** goes onto it. So `homing · split · portal` fans three exits ahead, and a beam into its mouth comes out of all three and each leg bends onto the target: a crossfire from three angles, read from the cards. (The first build placed homing exits in a ring round the target, each facing it: a rule split and homing have nowhere else, so it was dropped.)

**P3. Its gates are spheres, and it works both ways (owner, 2026-11-05).** A gate has no front: whatever hits it, from any side, leaves the other gate on the far side, going on the way it went ("whichever direction it is hit from, it comes out from the exit in the reverse of that"). A bolt that hits the mouth from the left comes out of the right of every exit, still flying right. Anything that goes into the mouth leaves every exit; anything that goes into an exit leaves the mouth, so a foe's shot fired back at an exit comes out of the mouth flying at the caster. It leaves just outside the gate, so it does not go straight back in. A portal's gates never move (growth only widens them). (The first build turned what passed by the angle between the gates' facings; an exit's facing now only says where its fan put it and where its timer fires.)

**P4. Beams: the ray jumps.** A beam's ray that meets a mouth stops there and goes on from **every** exit with the reach it had left, going the same way (P3). Each leg is a **full copy** (owner, 2026-11-05) and hits with the beam's full numbers and cards. This is the beam's existing path that turns at walls (`ray_points` with bounces, `_beam_keep_path`), with one more kind of turn that forks. Two exits facing one target means two beams on it; three in a ring cook it. A beam that leaves through an exit and meets another mouth (yours or anyone's) jumps again, up to `SpellLimits.PORTAL_JUMPS` (4) jumps on one leg, and the legs of one beam stop growing at `SpellLimits.PORTAL_LEGS`. Those are engine safeguards against a loop or a runaway fork, not build limits.

**P5. Flying shots: the first goes through, the others are copies.** A flying shot (`MOTION_STRAIGHT`, a bolt, nova shot, swap, dash shot, or any shot with homing or return) whose centre enters a mouth moves to the first exit, going the way it went (P3), keeping its speed, life, pierce, cards and payloads. Each further exit gets a **full copy** of it (a new pool row, its own payloads), as P4's rule for beams. A shot or copy carries how many jumps it has made, and stops passing through portals at `PORTAL_JUMPS`. Still shots (rune, wall, a lingering shot), orbit shots and rain do not travel, so they never pass through. A ghost shot passes through like any other: ghost is about walls.

**P6. Bodies: one exit each, taken in turn.** An actor (a player, its caster included; an enemy, a decoy, a familiar) or a swarm body whose middle goes into a gate, and whose hit circle is no bigger than the gate, is moved to where the gate leads, just outside it, by `target_move_requested` (the mover and the swarm already hear it for swap). From a mouth a body cannot be copied, so the exits are taken **in turn** (a counter on the portal): a crowd magnet pulls in or shoves in is spread round the ring. A body that came through a portal does not go through one again for `SpellLimits.PORTAL_REST` (0.4 s), so it never flickers between two portals that face each other. Being moved is not a hit: it sets off no `on hit` and hurts nothing, but the portal's infusion puts its status on the body (`status_requested`, applied by Combat with no hit). Its velocity is not turned: a body walks on as its controller says.

**P7. It ends at its life's end.** Its end points are the mouth and every exit (`blast`, `on expire` and its `end_cue` happen at each), so `on expire · portal · nova` rings at every exit when it closes. With `hold` it stays while the button is held and reserves its mana, like any held carrier.

**P8. The same on every machine.** Portals are rows on the carrier and gates rows of the projectile manager (state by default, core/sim/README.md), checked in a fixed order: by pool slot for shots, by row for beams, by gate then the target grid's order for bodies. The ring's angles come only from the target's and the caster's positions, the turn counter of P6 is state, and a zap's roll is `SpellRuntime.zap_hash` of the portal's birth and its rolls. Nothing else is random.

## What every card does on a portal

The traits it answers (`traits()`): `STAYS | LASTS | STEERS | REACHES | SHOTS | SPREAD` (`SPEED` until 2026-11-06: it does not travel, so a speed card does nothing there). Not `HITS` (it hurts nothing), not `MEETS_SHOTS` (a shot that touches it goes through: shield and deflect do nothing) and not `FLIES` or `MOVES`. `SPEED` because it lives its `lifetime` (slow keeps it open longer). An infusion counts on it when it has a status to pass on (`Carrier.takes_element`): mend, which only heals, is wasted unless a blast carries it. `NEEDS` works out the rest; `tests/core/test_card_rules.gd` plays every card on it and fails where the answer is wrong. The ones that matter:

| Card | On a portal |
| --- | --- |
| homing | what comes out of it steers onto a target: beam legs bend, shots home (P2) |
| split, multicast | more exits (`shots`); a multicast opens more portals |
| reach | the exits open further away |
| bigger | wider gates: easier to aim into, swallows bigger bodies |
| growth | the gates widen while it is open |
| slow | it stays open longer |
| hold | it stays open while held |
| echo | a second portal 0.3 s later, in the same place |
| mirror | a second portal facing back |
| sniper | its exits follow the aim more truly |
| magnet | every gate pulls bodies toward it: a vacuum that drops enemies at the other side (into a fire rune, a wall, a crossfire) |
| zap | every second, each gate rolls its chance to zap each foe in reach |
| fire, frost, storm, void, lightning | **everything that comes out of it takes the infusion**: shots and beam legs take the element for their hits, bodies its status. A frost portal chills a teammate's plain beam and the enemies walking through it |
| mend | nothing (it has no status), unless a blast carries it |
| blast | a blast at the mouth and every exit when it closes |
| on expire | its payload fires from every gate when it closes |
| timer, on hurt | its payload fires out of every exit, along its facing: `timer · split · portal · bolt` is three turrets ahead |
| on cast, recoil | as on any carrier |
| on hit, on kill, on reaction, chain, pierce, siphon, heavy, possess, relay, pull, overcharge | nothing: a portal hits nothing (marked in the builder, as everywhere) |
| sticky, linger, return, bounce, ghost, spiral, on wall | nothing: it does not move |
| shield, deflect, on block | nothing (owner, 2026-11-05): a portal never stops a shot it should pass |

## Looks and sound

- **The gates** (`gameplay/feel/portal_look.gd`, drawn by Feel every frame; since 2026-11-09 the mote rift, its lens the portal card's shader and its lips real motes: docs/milestones/carrier-looks-fixes.md, phase 2): a ring of the caster's colour round a dark heart, with an inner edge in the portal's tint (its infusion's colour). A mouth's three short arcs swirl inward, an exit's outward, and a glint makes each read as a sphere. A faint dotted line joins a mouth to each of its exits, so anybody can read where a shot will come out (pillar 4, fair difficulty: an enemy's exit facing a player is its telegraph). A portal fades over the last 15% of its life.
- **Something passes through:** `portal_through` (a small ring and a few sparks) where it goes in and where it comes out. A beam is drawn leg by leg: each leg is a beam row of its own.
- **Cues** (`content/cues/`): `cast_gather` (the staff's flash, as the teleport's), `portal_open` (`shown_cue`, at every gate), `portal_through`, `portal_close` (`end_cue`, at every gate). No sound yet: the cues are silent until the audio pass.
- **Staff pose:** the rune's (placing), with a short twist back as it opens.
- **Icon:** 16×16, palette from docs/STYLE.md: two small violet rings joined by a dotted line of sparks (a placeholder until the art pass).
- Spell light: not yet (a later look).

## Penta: the ring, for every carrier

The first build's ring round a target (homing exits, each facing it) was a rule split and homing had nowhere else, so it left the portal (owner, 2026-11-05: option 1, "to not have custom rules") and became a card of its own that every carrier can use: **Penta** (`content/spells/modifiers/penta/`, `ModifierBase.Behaviour.PENTA`).

- **The rule** (`SpellRuntime._penta`, one rule in the runtime, as Mirror's; reworked by the owner the same day: "Penta should cast using the player as point", and "they should just aim towards the point, even if it is the player"): the next carrier is cast `behaviour_strength` times (5 the card; a second card makes 10, at most `SpellLimits.PENTA_MOST`), each copy from a point on a ring round its caster, all aimed in at it. The caster is the wizard's body, or the point or shot that casts a payload, so `on hit · bolt · penta · fire · beam` rings where the bolt hit: five beams burning in at the imp it hit, and with `hold` they stay on while the staff is held. They can hit that imp because a payload that starts outside the body that fired it can hit it (owner, 2026-11-05, docs/DECISIONS.md; an ordinary payload starts on that body and still spares it). **Penta reads no other card** (owner, 2026-11-05: "Drop it, Penta always rings the caster"). For a while homing moved the ring onto its target, a rule between two cards like the one the portal dropped; now homing only steers each copy after it leaves the ring, as on any carrier. The ring stands `SpellLimits.PENTA_RING` (64 px) out, or within `PENTA_WITHIN` (80%) of the carrier's own reach when that is shorter, so a nova's rings still meet in the middle. The ring turns (owner, 2026-11-06: "It should rotate continuously") at `SpellLimits.PENTA_TURN` (once round every 2 s), and each cast turns the other way from the one before ("Penta could simply swap rotation direction every cast"): a cast stands where the card's last ring has turned to, so casts in a row (a held button, a rain cast again, an echo, a mirror) sweep back and forth, and a copy that stays on its point and aims from it (a beam, held or not) turns with its ring while it lasts, still aimed in. A still shot (a rune, a wall) stays where it was placed and a flying one flies off, as anywhere; an orbit circles where its point was. The ring does not follow its centre (owner: "Don't let it follow the centre"). A mirror is the same cast again with its aim reversed (`_cast_once`), so a Penta's mirror is a second ring, which as the next cast turns the other way. It replaced a random angle each cast (2026-11-05). Each point stops short of a wall, and each copy is cast by its point (a beam stays there, an orbit circles it, a payload leaves from it). Round the caster, aimed in, it hurts its caster as everything does, unless the carrier hurts nothing that way: `penta · wall` is a cage round you, `penta · rune` a ring of traps round you.
- **Its price** (owner, 2026-11-05): each copy at 40% damage, 2.5× mana: 2× a single cast's damage on one target, about split's rate.
- **Where it works:** bolt and swap (five shots closing in), beam (as an `on hit` payload, five beams burning in at what the shot hit: the owner's first idea, no portal needed), nova, rune (a ring of traps), wall (a cage), rain, orbit, decoy, familiar, portal. **Wasted** where nothing leaves from a point: a dash or teleport moves its caster, a swing or slam strikes from the hand (`NEEDS`: not `MOVES_CASTER` or `OWN_POSE`).
- **Look:** converge (20), shared with magnet, siphon and possess (docs/DECISIONS.md). Placeholder icon. Combos `penta_beam_cook` and `penta_frost_novas`; tests `content/spells/modifiers/penta/test_penta.gd`; screenshot `shot_penta_looks`.

## The combos (each in its card's `combos/` folder)

- `portal_crossfire`: staff 0 `homing · split · portal`, staff 1 `fire · beam` into the mouth: three legs bend onto an imp off the line and burn it.
- `portal_fire_bolts`: staff 0 `fire · homing · split · portal`, staff 1 a plain `bolt`: its three copies come out burning and home in on an imp off the line.
- `portal_frost_vacuum`: `frost · magnet · portal` pulls an imp beside its exit in and drops it by the caster, chilled.

## How it was built

All in one branch, in GDScript: no C++ changed. The gates are rows of the projectile manager, as the walls are (`open_gate`, `close_gate`, `gate_outs`, `gate_turn`, `gate_cut`); a ray stops where it goes into one when its caller asks (`ray_gates`, a beam only: a zap or a jump passes gates by) and says which (`ray_gate`, `ray_gate_left`); `shots_into_gates` lists the flying shots that went into one on their last step, and `pass_shot` moves one. The portal carrier (`core/spells/carriers/portal.gd`) runs every step after the manager's: it moves those shots (and makes their copies through `land_shot`, so a copy is a full shot of its spell), moves the bodies, pulls, zaps and closes. A beam that stops at a gate opens a leg at every gate it leads to: a beam row of its own (`CarrierBeam._start_leg`), which follows its beam and ends when its beam no longer reaches that gate. Since the shots are moved after the step, outside the kernel's loop, the native shot kernel needed no change and its check (`test_native_kernel`) is unchanged; the swarm's bodies are moved by `target_move_requested`, which the swarm already hears. `content/spells/carriers/portal/test_portal.gd` checks the rules; `test_card_rules` plays every card on it, with a teammate's plain shot sent through every carrier that opens a way through (`GATES`), so what its cards do to what comes out shows.

Not built yet: the enemy AI does not aim through portals (step 4 below; an enemy that holds a portal opens it and fights on as it does), spell light, and sounds.

## The work, in order (as planned)

1. **The carrier and beams** (GDScript only). `CarrierPortal` with its rows, P1–P4 and P7–P8, the card, icon, looks, cues, sounds, `portal_crossfire`, and tests: a beam through one exit and through three, a jump cap, two portals facing each other, `test_card_rules` and the determinism tests passing. Adds `portal_*` to the kit only where it has to (`CarrierKit`: the ray's new turn).
2. **Flying shots** (P5). The projectile manager checks the mouths on each shot's step, moves the shot and asks for copies. **The C++ shot kernel (`native/shot_kernel.cpp`) must match it to the bit**: the kernel only records "slot crossed mouth k" and moves the shot, and the copies are made in GDScript after its step, so the C++ part stays small. `tests/core/test_native_kernel.gd` gets portals in its world. Combo `portal_teammate`.
3. **Bodies** (P6). The actor's mover (`gameplay/actor/mover.gd`), the horde swarm (`gameplay/horde/swarm.gd`) and **its C++ kernel (`SwarmKernel`)**, with `tests/gameplay/horde/test_native_swarm.gd`. Combo `portal_vacuum` and the `moved` check.
4. **The AI** (`CastSense`). A new trait read only by the AI's summary, so enemies and bots that hold a portal fire their beams and shots through it, and so the AI's dodging counts a shot coming out of an exit. Until then an enemy may hold a portal but plays it as a rune.
5. **Tuning after the owner's playtest.**

The card is in the starting cards of `docs/DESIGN.md`, by the owner's direction ("Just build it all", 2026-11-05).

## The owner's answers (2026-11-05)

1. The name: **Portal**.
2. Bosses and big bodies: a body no bigger than the gate goes through ("Sound good").
3. Infusion: everything that comes out takes it ("Yes").
4. Shield and deflect: nothing ("Agreed").
5. **Both ways** ("can be used against you then").
6. The caster's own body goes through its own portal ("Yes I should").

Later the same day: (7) the ring left the portal's homing, which now steers what comes out, and became the Penta card (5 copies at 40% damage, 2.5× mana), its ring round the caster (homing moved it onto its target for a while; dropped the same day: Penta reads no other card), always aimed in; (8) **a gate is a sphere**: "whichever direction it is hit from, it comes out from the exit in the reverse of that", so nothing that passes is turned (P3).
