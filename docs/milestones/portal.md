# Portal: a carrier that sends shots, beams and bodies elsewhere

**Status: a proposal for the owner's review (2026-11-05). Nothing is built.** The owner asked for "a portal cast: one staff fires a portal, you fire a beam into it, and the beam comes out of a different portal, or several in a circle round an enemy, to really cook them." Four answers settled the frame on 2026-11-05: (1) **one cast opens a mouth and its exits**; (2) **shots, beams and bodies all go through**; (3) **a beam leaving several exits is a full copy at each**; (4) this design note first, code after the owner's review. The questions still open are at the end.

"Portal" is the working name. Before the card ships its name gets the same check as any other ("no names from other works", AGENTS.md): the word is generic, but there is a well-known game by that name built on the same mechanic, so the owner may prefer **Gate** or **Warp** (not *Rift*: that is already a reaction).

## Why it fits the pillars

- **Deep spell building (pillar 1).** A portal does nothing alone. It changes where every other spell goes: yours, a teammate's and an enemy's. The ring round an enemy comes from cards that already exist (homing, split), so it adds a carrier and no special cases.
- **Surprising combos.** It works across systems: beams, flying shots, knockback, magnet, infusions and triggers all do something new with it (the table below).
- **Everything hurts everything.** A portal belongs to no team. An enemy's bolt that flies into your mouth comes out of your exits, and a teammate's beam fired through it cooks your target.
- **Nobody waits (pillar 2).** A portal is walked into, never forced on anybody's choices. Being knocked through one is a hit like any other.
- **Readable chaos (pillar 4).** Each mouth and its exits share one colour (the caster's), are drawn joined, and show which way each exit faces.

## The card

A form card, `content/spells/forms/portal/`, `carrier = &"portal"`, a new `core/spells/carriers/portal.gd` (`CarrierPortal`). Starting numbers, for tuning in the playtest:

| Field | Value | What it means on a portal |
| --- | --- | --- |
| `mana_cost` | 10 | more than a rune (8): it multiplies other spells' damage |
| `cooldown` | 1.5 s | |
| `lifetime` | 4 s | how long the mouth and exits stay open |
| `radius` | 12 px | the size of the mouth and of each exit |
| `ray_length` | 160 px | how far ahead the exit opens (the reach of a beam is 240) |
| `shots` | 1 | how many exits |
| `spread` | 40° | how far apart several exits are fanned without homing |
| `base_damage` | 0.05 (the minimum) | a portal hurts nothing itself |
| `complexity` | 3 | |

## The rules

**P1. One cast opens one mouth and `shots` exits.** The **mouth** opens a step ahead of the staff tip (`kit.placed_at`, as a rune does), facing along the aim. Without homing the **exits** open `ray_length` ahead along the aim, stopping before walls (`clip_to_walls`, as teleport and wall do), fanned `spread` apart when there are several, each facing the aim. A portal cast as a payload opens where its payload fires, like any carrier (`on hit · bolt · portal` opens one where the bolt hit).

**P2. With homing, the exits ring the target.** The exits open evenly round the target homing picks (the same pick and reach as every other carrier), on a circle of `SpellLimits.PORTAL_RING` (48 px) beyond its edge, **each facing the target**. The first exit is placed on the far side from the caster, so one exit fires the beam straight on and the others come in from the flanks. No homing target in reach: the exits open as in P1. Exits do not follow the target after they open (see `sticky` in the table).

**P3. The mouth is one way in; the exits are one way out.** Anything that enters the mouth's circle, from any side, leaves from the exits. Its heading turns by the angle between the mouth's facing and the exit's: something that flies straight into the mouth comes straight out of the exit along its facing. Nothing enters through an exit (they hurt nothing and stop nothing). One-way keeps it readable and rules out a loop between a pair. A portal's own mouth and exits never move.

**P4. Beams: the ray jumps.** A beam's ray that meets a mouth stops there and goes on from **every** exit with the reach it had left, turned as P3 says. Each leg is a **full copy** (owner, 2026-11-05) and hits with the beam's full numbers and cards. This is the beam's existing path that turns at walls (`ray_points` with bounces, `_beam_keep_path`), with one more kind of turn that forks. Two exits facing one target means two beams on it; three in a ring cook it. A beam that leaves through an exit and meets another mouth (yours or anyone's) jumps again, up to `SpellLimits.PORTAL_JUMPS` (4) jumps on one leg, and the legs of one beam stop growing at `SpellLimits.PORTAL_LEGS`. Those are engine safeguards against a loop or a runaway fork, not build limits.

**P5. Flying shots: the first goes through, the others are copies.** A flying shot (`MOTION_STRAIGHT`, a bolt, nova shot, swap, dash shot, or any shot with homing or return) whose centre enters a mouth moves to the first exit, turned as P3 says, keeping its speed, life, pierce, cards and payloads. Each further exit gets a **full copy** of it (a new pool row, its own payloads), as P4's rule for beams. A shot or copy carries how many jumps it has made, and stops passing through portals at `PORTAL_JUMPS`. Still shots (rune, wall, a lingering shot), orbit shots and rain do not travel, so they never pass through. A ghost shot passes through like any other: ghost is about walls.

**P6. Bodies: one exit each, taken in turn.** An actor (a player, an enemy, a decoy, a familiar) or a swarm body whose feet enter the mouth is moved to an exit and keeps its velocity and any knockback, turned as P3 says. A body cannot be copied, so the exits are taken **in turn** (a counter on the portal): a crowd magnet pulls in or shoves in is spread round the ring. It arrives by the teleport rule (stops short of walls and backs off until it stands clear, `Mover._teleport`; a swarm body by `target_move_requested`'s path). A body that came through a portal does not enter another for `SpellLimits.PORTAL_REST` (0.4 s), so it never flickers between two portals that face each other. Being moved is not a hit: it sets off no `on hit`.

**P7. It ends at its life's end.** Its end points are the mouth and every exit (`blast`, `on expire` and its `end_cue` happen at each), so `on expire · portal · nova` rings at every exit when it closes. With `hold` it stays while the button is held and reserves its mana, like any held carrier.

**P8. The same on every machine.** Portals are rows on the carrier (state by default, core/sim/README.md), checked in a fixed order: by pool slot for shots, by row for beams, by actor id then swarm row for bodies. The ring's angles come only from the target's and the caster's positions, and the turn counter of P6 is state. Nothing is random.

## What every card does on a portal

The traits it answers (`traits()`): `STAYS | LASTS | STEERS | REACHES | SHOTS | SPREAD | MEETS_SHOTS`. Not `HITS` (it hurts nothing) and not `FLIES` or `MOVES`. `NEEDS` works out the rest; `tests/core/test_card_rules.gd` plays every card on it and fails where the answer is wrong. The ones that matter:

| Card | On a portal |
| --- | --- |
| homing | the exits ring the nearest target, facing it (P2) |
| split, multicast | more exits (`shots`) |
| reach | the exits open further away |
| bigger, growth | a wider mouth and exits: easier to aim into, swallows more bodies |
| slow, linger | it stays open longer |
| hold | it stays open while held |
| echo | a second portal 0.3 s later, in the same place |
| mirror | a second pair facing back: shots fired forward also come out behind you |
| magnet | the mouth pulls bodies toward it: a vacuum that drops enemies at the exits (into a fire rune, a wall, a crossfire) |
| fire, frost, storm, void, lightning, mend | **everything that leaves an exit takes the infusion**: a frost portal chills a teammate's plain beam and the enemies walking through it. The surprise combo of the card, if the owner likes it |
| blast | a blast at the mouth and every exit when it closes |
| on expire | its payload fires from every exit when it closes |
| timer | its payload fires out of every exit, along its facing, every interval: `timer · homing · split · portal · bolt` is a ring of turrets round a target |
| on cast | as on any carrier |
| on hit, on kill, chain, pierce, siphon, heavy, possess, zap | nothing: a portal hits nothing (marked in the builder, as everywhere) |
| sticky, return, bounce, spiral | nothing: it does not move |
| shield, deflect | open: the proposal is that they do nothing, so a portal never stops a shot it should pass |

## Looks and sound

- **Mouth:** a ring of the caster's colour that swirls inward (the `ring_in` flash's motion), with a dark heart. **Exit:** the same ring swirling outward, with a notch showing which way it faces. A faint dotted line joins a mouth to each of its exits while they are open, so anybody can read where a shot will come out (pillar 4, fair difficulty: an enemy's exit facing a player is its telegraph).
- **Something passes through:** a small flash at the mouth and at each exit it leaves. A beam is drawn leg by leg (as it is now after a wall bounce), with a short gap across each jump.
- **Cues** (`content/cues/`): `cast_portal` (the staff's flash), `portal_open` (`shown_cue`), `portal_through`, `portal_close` (`end_cue`); sounds `audio/` `.ogg`.
- **Staff pose:** copied from the rune (placing), with a short twist as it opens.
- **Icon:** 16×16, palette from docs/STYLE.md: two small rings joined by a dotted arc.
- Spell light: each mouth and exit glows softly while open.

## The combos (two at least, `content/spells/combos/`)

- `portal_crossfire`: staff 0 `homing · split · portal`, staff 1 `beam` held into the mouth. Three beams cook one imp. Checks: `damaged`, more than one `beam` alone does in the same seconds.
- `portal_vacuum`: `magnet · portal`, an imp pulled in and dropped at the exit onto a `frost · rune`. Checks: `status` chill. Needs a new check kind, `moved` (an imp ends at least so far from where it started).
- `portal_teammate`: player 0 opens it, player 1 fires a `fire · bolt` through it. Checks: `damaged` and `status` burn on an imp behind a wall the bolt could not reach straight.

## The work, in order (one PR each)

1. **The carrier and beams** (GDScript only). `CarrierPortal` with its rows, P1–P4 and P7–P8, the card, icon, looks, cues, sounds, `portal_crossfire`, and tests: a beam through one exit and through three, a jump cap, two portals facing each other, `test_card_rules` and the determinism tests passing. Adds `portal_*` to the kit only where it has to (`CarrierKit`: the ray's new turn).
2. **Flying shots** (P5). The projectile manager checks the mouths on each shot's step, moves the shot and asks for copies. **The C++ shot kernel (`native/shot_kernel.cpp`) must match it to the bit**: the kernel only records "slot crossed mouth k" and moves the shot, and the copies are made in GDScript after its step, so the C++ part stays small. `tests/core/test_native_kernel.gd` gets portals in its world. Combo `portal_teammate`.
3. **Bodies** (P6). The actor's mover (`gameplay/actor/mover.gd`), the horde swarm (`gameplay/horde/swarm.gd`) and **its C++ kernel (`SwarmKernel`)**, with `tests/gameplay/horde/test_native_swarm.gd`. Combo `portal_vacuum` and the `moved` check.
4. **The AI** (`CastSense`). A new trait read only by the AI's summary, so enemies and bots that hold a portal fire their beams and shots through it, and so the AI's dodging counts a shot coming out of an exit. Until then an enemy may hold a portal but plays it as a rune.
5. **Tuning after the owner's playtest.**

Owner-only edits this needs: adding the card to the starting cards in `docs/DESIGN.md`.

## Open questions for the owner

1. **The name:** Portal, Gate, Warp, or another?
2. **Bosses and big bodies:** do they go through portals too (a boss dropped into a crossfire), or are they too big for one (a `portal_proof` flag on the body)? Proposal: anything whose body is smaller than the mouth goes through, so `bigger · portal` swallows bigger things.
3. **Infusion on exit:** do the exits pass on the portal's infusion to everything that leaves (the table above)? It is the strongest new combo, and also a way to infuse a teammate's spells.
4. **Shield and deflect on a portal:** nothing (the proposal), or a mouth that eats enemy shots instead of passing them on?
5. **One way or two ways:** the proposal is one way (P3). A two-way pair is the classic idea but harder to read, and with several exits it is unclear where something goes back to.
6. **Its own player:** does a caster's own body go through its own portal? The proposal is yes (everything hurts everything, and it gives a movement trick: `portal` then walk in), at the cost of making `teleport` less special.
