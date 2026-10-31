# M2 proposal: allies and fields (phase J)

**Goal:** four co-op cards that use the people (and things) beside you, and three new carriers that bend other shots. Every one of them works alone, so nobody waits for a teammate.

**Status (2026-10-31): a proposal, not yet scheduled.** It came from a comparison with Noita's wands, done with the owner in a session. Before any code: the owner decides where it goes on the roadmap (an M2 phase like G, H and R, or M3), answers "Open questions", and an independent review checks it against docs/DESIGN.md (the self-critique below is Claude's own, not that review).

**Done when:**

1. The seven cards below are in `content/spells/`, each in two combos (`content/spells/combos/`), with icons and sounds.
2. `tests/core/test_card_rules.gd` plays them on every carrier (and every card on the three new carriers) and passes.
3. Each card does something with **no teammate**, with a decoy, with a familiar and with a teammate, and a test checks all four.
4. The stress run (`tests/benchmark/stress_runner.gd`) with four players holding Well, Portal and Prism staffs keeps its frame budget.
5. The owner's sandbox playtest.

## The cards

| Card | Kind | What it does |
| --- | --- | --- |
| **At Ally** | modifier | The next carrier aims at your nearest ally: a shot flies at them, a placed carrier (rune, nova, rain, wall, well, prism, portal exit) lands on them, a dash or teleport goes to them. |
| **Hand-off** | modifier | The next carrier is cast from your nearest ally's position instead of your hand, in your aim direction. |
| **Link** | modifier | While the next carrier lives, a beam joins it to your nearest ally and hits what crosses it, with the carrier's hit. |
| **Mimic** | multicast | Adds your nearest ally's last cast spell to this cast, from your hand, at your aim. |
| **Well** | carrier | A still point that pulls **shots** in (anyone's) and holds them circling it; when it ends, they fly out. |
| **Portal** | carrier | Two ends: one a step ahead, one at its reach. A shot that enters one end leaves the other, same heading. |
| **Prism** | carrier | A still field: every shot that passes through it takes on the Prism's cards. |

## The ally rule (J1: everything else in the co-op half builds on it)

**Your allies** are the other actors of your team, your own decoys and your own familiars. "Nearest ally" is the nearest of those to the point asked about. **With no ally, it is you**: the general fallback (the caster, M2-staffs.md "Reading a staff", rule 5), so every co-op card works alone. Alone with a decoy, the decoy is your ally.

- **One query for every card:** `kit.nearest_ally(actor, at) -> Vector2` (and the ally's actor id or entity key), in `CarrierKit`. No card asks anything else, so no card has a case for decoys.
- **Teams only aim** (DESIGN.md, "Everything hurts everything"): the ally rule chooses where a card points, never whom a hit hurts. An At Ally bolt hurts your teammate unless it is a mend bolt. That is the point: mend, shield and possess are what you aim at allies.
- **Decoys and familiars stay rows in `Entities`** (`gameplay/ai/entities.gd`). They do not become actors (that is still in docs/BACKLOG.md, from the actors rework). Areas never call each other, so Entities tells core/spells where each one is every step, as it already does for familiars (`Spells.familiar_at`). J1 widens that report to decoys and keeps one ally table in core/spells, with room made at start (no per-frame allocation).
- **Enemies have allies too.** An enemy staff with Hand-off casts from the nearest enemy, so one rule covers every caster (M2-rules.md, rule 6).

## Each card in detail

### At Ally (modifier)

The carrier's aim point becomes the nearest ally. With no ally, it aims at you, and lands on you.

- Works on every carrier: it only changes the aim. `ModifierBase.NEEDS`: none.
- Combos: `at ally · mend · bolt` heals a teammate across the room. `at ally · teleport` jumps to the decoy you left behind. `at ally · rain · frost` freezes whatever is crowding your decoy.

### Hand-off (modifier)

The carrier starts at the nearest ally, aimed the way you aim.

- `NEEDS`: `{"not": MOVES_CASTER}`. A dash would move a teammate, and no player moves another player's body against their will (co-op rule 1). On a dash or a teleport it is wasted.
- Combos: `hand-off · beam` from your decoy (enemies chase the decoy, so the beam hits them from the side). `hand-off · nova` from a familiar circling a teammate. `double · hand-off · bolt · bolt` is a crossfire from two places.

### Link (modifier)

A beam row (`LC_ROW`, as the beam carrier has) runs from the carrier to the nearest ally for as long as the carrier lives, and hits at the beam's tick (`SpellLimits.BEAM_TICK`) with the carrier's hit, infusions and cards. The beam does not hit its two ends.

- `NEEDS`: `{"any": LASTS}`. A slam is over at once, so there is nothing to link.
- With no ally, the beam runs to you, so a linked bolt draws a line from your hand.
- Combos: `link · rune · storm` placed by your decoy is a tripwire. `link · orbit` circles you with spokes. `link · hold · familiar` is a beam that sweeps round you.

### Mimic (multicast)

A new `MulticastBase.Mode.MIMIC`: it adds the nearest ally's last cast to this cast. That means the carriers of that ally's last group, with their cards and payloads, cast from your hand at your aim, for the mana it cost them.

- A decoy is a copy of you, so it counts as you: with a decoy, Mimic copies your own last cast (from any of your four staffs). A familiar's last cast is the last payload it fired. Alone, Mimic copies your own last cast.
- It is a multicast, so like Double it always does something (`card_works` true) and takes no modifiers. The cards around it read as they do today.
- Nothing has been cast yet: it adds nothing, and the builder cannot know beforehand (it is the one card whose result depends on the moment; the cast plan says "your ally's last spell").
- Combos: put your biggest spell on RB and `mimic · bolt` on RT. One teammate's fire nova becomes everyone's.

### Well (carrier)

Placed a step ahead along the aim, like a rune. Every shot within its reach, of any team, is pulled toward it; a shot that gets close is held, circling it. When the Well ends, every held shot flies straight out from it, keeping its cards.

- Traits: `STAYS | LASTS | MEETS_SHOTS | SPREAD`. It hits nothing itself; a blast on it explodes where it ends (`on expire` fires there too).
- `bigger` grows its reach, `hold` keeps it until the staff is cast again, `deflect` makes every shot it holds yours, `homing` creeps it toward a target (as a rune does).
- Engine: pulling uses the pacing that magnet already has (`MAX_PULLS_PER_STEP`); a held shot is a new motion in the projectile manager (circling a point, like `spawn_orbit` but for a shot already flying).
- Combos: `well` then `triple · bolt` fills it, and it lets go as a ring. `hold · deflect · well` eats a boss's volley and throws it back. `on expire · well · nova` ends with a nova.

### Portal (carrier)

Two placed ends: the entry a step ahead, the exit at its reach along the aim. A shot that touches the entry leaves the exit with the same heading, speed and cards; a shot that went through cannot go back through for a moment, so it never jitters on the spot.

- Traits: `STAYS | LASTS | MEETS_SHOTS | REACHES`. It hits nothing itself.
- Its exit is its aim point, so **At Ally** puts the exit on an ally, **homing** puts it on the nearest enemy, and `reach` pushes it further.
- J7a carries shots. J7b carries beams (a beam is a path; it already bends at walls, so the path gets one more break). Walking bodies through portals is left out (see "Out of scope").
- Engine: one new projectile call to move a shot in a single step, which cuts its trail so the tail does not streak across the room.
- Combos: a Portal whose exit is above an enemy turns every bolt into an ambush. Two players fire into one portal. `on hit · bolt · portal` opens a portal where the bolt lands.

### Prism (carrier)

A still field, like a big rune. Each shot (of any team and any player) that passes through takes on the Prism's cards once per Prism.

- **J8a: infusions and numbers.** A passing shot gains the Prism's infusions with their statuses (as `relay` adds a donor's: `Spells._relay`), and its damage, speed and size change by its modifiers. An enemy's fire bolt through your frost Prism reacts on its own hit (Thaw).
- **J8b: behaviours** for which the projectile manager can already change a shot in flight: homing, bounce, ghost, spiral, linger, growth, sticky, return, shield, deflect (each has a setter on a slot). Split, chain, blast, zap and triggers need the compiled spell, so they wait for an open question below.
- Cards on a Prism mean "what it gives", so they work where the shot can take them, not where the Prism itself can. A new trait `LENDS` says so, and `Carrier.works` asks the passing shot's needs instead (one rule, no case per card). `test_card_rules.gd` sends a bolt through a Prism with each card.
- Combos: `fire · homing · prism`, then a teammate shoots through it. `prism · frost` in front of an enemy's mage. `hold · prism · bounce`, then shoot into it with Split.

## Parts

One PR each. The two halves don't depend on each other and can be built in parallel; within each half, in order.

**Allies:**

- **J1:** the ally rule: Entities reports decoy positions, the ally table in core/spells, `kit.nearest_ally`, tests for no ally, decoy, familiar and teammate.
- **J2:** At Ally.
- **J3:** Hand-off.
- **J4:** Link.
- **J5:** Mimic (each actor's last cast group, kept for Mimic as `_last_infused` is kept for Relay).

**Fields:**

- **J6:** Well.
- **J7a / J7b:** Portal for shots, then for beams.
- **J8a / J8b:** Prism with infusions and numbers, then with behaviours.

Each part adds its card folder (`.tres`, icon, `assets.json`), its two combos, its look in `gameplay/feel` and its shader in `core/projectiles/shader_warmup.gd` if it has a new one, its sound ids in docs/BACKLOG.md ("Audio needs") if the sound does not exist yet, and its line in the sandbox bag.

## Open questions for the owner

1. **Where on the roadmap?** M2 (a phase like G, H and R, before D3) or M3 rewards. DESIGN.md's starting-card list is owner-only, so the owner adds the seven names there if they join it.
2. **Hand-off: your aim direction or your aim point?** Direction (this plan) is simpler to read. The aim point would make shots from two places meet at one spot, which needs an aim point for a stick (rain's `RAIN_REACH` ahead).
3. **Prism's split, chain, blast, zap and triggers (after J8b).** Either a passing shot is cast again as one new compile of "its cards plus the Prism's" (cached per pair, so it allocates once), or those cards are wasted on a Prism. The first is crazier and costs more.
4. **Mimic's mana:** what it cost the ally (this plan), or a flat cost.

## Out of scope

- Bodies through portals (walking actors, enemies, decoys): a different kind of thing from shots, and a teammate pushed through one would be moved by another player.
- The other ideas from the comparison (copy cards, Merge, Steal...): in docs/BACKLOG.md or a later proposal.
- Turning decoys and familiars into actors.

## Self-critique against docs/DESIGN.md (Claude's, before the independent review)

- **Pillar 1, deep spell building:** seven cards, each with interactions across systems: allies × every carrier, fields × every shot of every caster. Every new component needs at least two interesting interactions: each has two or three combos above.
- **Pillar 2, nobody waits for anybody:** every co-op card falls back to the caster, and with a decoy or familiar it is as good alone as with a teammate. No card moves another player (Hand-off on a dash is wasted; no bodies through portals). Mimic reads a teammate's last cast and never waits for one.
- **Everything hurts everything:** At Ally, Link and Hand-off hurt teammates as any hit does; the ally rule only aims.
- **Readable chaos:** Well and Portal move shots in ways a player must be able to follow. Their looks must show the pull and the two ends clearly in the player's colour; a Prism must mark the shots it changed (their look gains the Prism's layers, as the shot look already layers cards).
- **No build limits:** none are added. A shot circling between two portals ends with its life; a Well holding hundreds of shots is paced by the existing magnet pacing and checked by the stress run (done-when 4).
- **Risk:** Prism's `LENDS` is a new idea in the card rules (cards judged by what a passing shot can take). It has to stay one rule in `Carrier.works`, never a list of exceptions.
