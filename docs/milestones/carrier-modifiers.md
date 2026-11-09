# Carrier modifiers: Nova and Skyfall

**Status: Part 1 (Nova) merged #648 (2026-11-09). Part 2 (Skyfall) rewritten with the owner the same day around the hole, Part 3 folded into it; Parts 4-5 planned. The owner's answers below.** The owner, 2026-11-09: "Rain is looking really bad. I dont really like rain. Maybe remove it and add an AOE modifier instead, which makes the modified carrier "rain down" from above. Could be used for a fireballs from above or beams or whatever", and "Nova could probably be replaced by a "Nova" modifier card instead, which would allow us to make novas of other carriers".

The same day, on the orbit's look: "Hmm maybe orbit should also just be a modifier instead of a carrier" (Part 5).

Two carrier cards become two modifier cards (three with Orbit). Any carrier can then be a nova, and almost any carrier can fall from the sky. The owner's "Ring multicast" idea (docs/BACKLOG.md:191, 2026-10-30) is done by the first.

## Where they are now

- **Nova** is not a carrier. `forms/nova/nova.tres` is an atom card with `shots = 8`, `spread = 360` (3 damage, 10 mana, 1.0 s wind-down, speed 150, life 0.4: about 60 px). Its ring is a special case in the atom carrier: `atom.gd:30-31` sends `form_shown(&"nova")` when a launch has more than one shot and a full spread, and `atom.gd:39-40` says such a cast reaches 0. CastSense calls a full spread an area (`cast_sense.gd:131`).
- **Rain** is a carrier of its own (`core/spells/carriers/rain.gd`). It marks a spot `ray_length` ahead, stopped at a wall (rain.gd:33-37), and waits its `lifetime` in the runtime's queue (`PendingLaunch.landing`, spells.gd:193, 1825). Then it strikes round the spot with a 16 px splash (`RAIN_SPLASH`, limits.gd:77), fires its blast, drops the payload it carries and fires its `on expire` (rain.gd:53-64). It is the only carrier that `CARRIES_PAYLOAD` (test_staff_base.gd:61-68). That one flag costs a branch in the compiler (staff_compiler.gd:159-161), the tree (spells.gd:774), the text (staff_compiler.gd:705) and CastSense (cast_sense.gd:151). Its look is the `telegraph` cue, then `rainfall` (the `fall` column).

## The idea, one line each

- **Nova:** the next carrier is cast N times from the same place, each aimed out at its own angle round a circle. Mirror already does this with two ways (spells.gd:1611-1616); a nova does it with eight.
- **Skyfall:** the next carrier does not leave the hand. A spot is marked ahead, the carrier falls onto it, and it is cast there, by that spot, when it lands.

Both are modifier behaviours. Each is a row of `ModifierBase.RULES`, a few lines where the runtime makes a cast, and a card that is only data. Neither changes the projectile manager's step, so no native kernel changes.

## One place where a cast is made

Penta already takes over a cast in `_cast_once` (spells.gd:1639). Nova and Skyfall join it as stages, in a fixed order. Each stage hands the next one a place, a way and who casts it:

firing (`_fire_spell`: mirror, echo, recoil, `on cast`) → **nova** (N ways round) → **skyfall** (to a spot ahead; after the fall, cast by that spot) → **penta** (a ring round whoever casts it now) → the carrier's `launch`.

So `nova · skyfall · bolt` drops 8 bolts on a ring of spots round you. `skyfall · penta · beam` falls on a spot and rings it with five beams aimed in. `mirror · skyfall · rune` drops a rune ahead and one behind. Every stage works the same way for every carrier.

## Part 1: the Nova modifier

### How it works

- A new behaviour, `NOVA`, at the end of `ModifierBase.Behaviour`. `behaviour_strength` is how many ways: 8 on the card. More cards add (`Stack.ADD`), with no cap (built 2026-11-09: the owner's rule that cards are not limited; the plan first proposed a cap of 24).
- The runtime casts the carrier N times from the same origin, by the same caster. Copy k goes along the aim turned by k/N of a full turn (`DMath.rotated`); copy 0 goes along the aim. Each copy is a whole launch, so a carrier keeps its own shots: `split · nova · bolt` is 8 fans of 3.
- **Why not shots and spread, like Split?** Split is `shot_mult` (staff_compiler.gd:497), and a spread only means something on a carrier that fans (`SPREAD`). A nova built that way would do nothing on a wall and nothing to an orbit. It is not a multicast either: a multicast draws more carriers, and the owner asked for a card that changes the next one.
- **Its look:** the card's `cue`, `nova` (content/cues/nova.tres: the ring out, a ring of motes, the `burn_ring` mark), played once per nova at its centre with `cue_shown`, the way a blast plays its cue (spells.gd:1741). The atom's special case goes (atom.gd:27-32, 39-40).

### On every carrier

| Carrier | A nova of it |
| --- | --- |
| atom, bolt, swap | 8 shots out in a ring (`nova · bolt` is the old Nova) |
| beam | 8 beams out round you; held, 8 held beams on one hold |
| rune | 8 runes, each a step out round you |
| pool | 8 pools, each `ray_length` out round you |
| wall | 8 walls, each across its own way: a ring of walls round you |
| orbit | 8 launches starting at their own angles: 24 orbs evenly round one circle |
| swing | 8 sweeps at once: a spin |
| slam | 8 slams on a ring round you |
| decoy, familiar | 8 bodies round you (at 60 and 80 mana) |
| portal | 8 mouths a step out, each with its exits |
| dash, teleport | 8 moves round a circle add up to almost none: you stay, and each move still strikes round you (a dash's pass, a teleport's landing). Mirror does the same today (DECISIONS.md:866; test_behaviour_table.gd:75). See question 1. |
| on you, on what fired it, right there | the strike happens 8 times, as Mirror makes it strike twice (docs/CARRIERS.md:158) |

Its needs row: `B.NOVA: {}`, the same as Mirror's (modifier_base.gd:120). It is wasted nowhere. If the owner prefers Penta's rule, the row becomes `{"not": MOVES_CASTER}` (question 1).

### Numbers

The Nova card: `damage_mult = 0.6`, `mana_mult = 2.0`, `wind_down_mult = 3.0`, `behaviour_strength = 8`, `look_layer = 9` (a burst, Split's), `cue = &"nova"`, complexity 2. Its description: "Casts the next spell eight times in a ring, aimed out."

| Cast | Per copy | All of it | Mana | Wind-down |
| --- | --- | --- | --- | --- |
| old Nova | 3 | 8 x 3 | 10 | 1.0 s |
| `nova · bolt` | 3 | 8 x 3 | 10 | 1.05 s |
| `nova · beam` | 1.2 a tick | 8 beams | 8 | 0.75 s |
| `nova · rune` | 4.8 | 8 runes | 24 | 1.5 s |
| `nova · wall` | 1.8 a stone | 8 walls | 12 | 3.0 s |

`nova · bolt` matches the old Nova except in range: a bolt flies about 264 px, not about 60 (question 2). For comparison, Penta is x0.4 damage and x2.5 mana for five copies that all meet in the middle, and Split is x0.5 and x1.5 for three shots.

### What else has to follow

- **Fire pacing counts copies.** `_shots_of` (spells.gd:2316) counts only `spell.shots`. A payload with a nova would make 8 times the shots its budget counts; Mirror already makes 2 times and Penta 5 times. A compiled `copies` (mirror x nova x penta) multiplies the count, so the per-step budget (`FIRE_SHOTS_PER_STEP`) stays true. The test is the sandbox Y build (flow.gd:135): 216 payloads of 216 shots, paced as today.
- **CastSense** reads the behaviour, not `spread >= 360` (cast_sense.gd:131). A nova is an area, its damage is times its copies, and a flying carrier's close reach is still its flight.
- **Comments and docs** that name "a nova's ring" go: spells.gd:1676-1680 (Penta) and events.gd:106 (`form_shown`).

### The nova folder and every `nova`

The modifier takes the id `nova`, and ids are unique across all kinds of card (content/spells/README.md:21). So the form goes in the same PR.

- **Cards:** delete `content/spells/forms/nova/`. Add `content/spells/modifiers/nova/`: `nova.tres`, icon, `assets.json`, two combos (a ring of walls that traps imps; a ring of beams), and `test_nova.gd`.
- **Cues:** `nova` stays as the modifier's cue. `cast_nova` was only the form's staff flash, so it is deleted (test_feel_form_looks.gd:96, test_motes.gd:692). `impact_ring` stays (dash, teleport, swap and wall use it). `wind_area` stays (orbit).
- **Every staff that names it:** `nova` becomes `nova, bolt`, which keeps 8 shots of 3.
  - The sandbox Y and B builds (flow.gd:135, 137). The `dev` staff has 20 slots.
  - The Bone Scepter (Part 4).
  - 44 combo files in other cards' `combos/`.
  - About 60 test files. The most are test_staff_compiler (49 lines), test_spells_land_shots, test_staff_runtime, test_radial_builder and test_cards_together.
  - Benchmarks: fire_cap_runner, fire_cap_view, stress_runner, sandbox_storm.
  - Clips: scenarios.gd.
  - Screenshots: shot_form_looks drops nova from its forms and shows the cue instead; shot_staff_poses, shot_hud_staffs, shot_radial_tree and shot_radial_builder.
- **Not touched:**
  - The Play bag (`dash`, `bolt`; flow.gd:115) and the horde's (`dash`, `swing`; flow.gd:119-122) never held a nova. The horde's level-up offers every card in the registry, so it offers the Nova modifier from now on.
  - Saves hold no cards (`SaveFile`: flags and settings). A replay names its content by a hash (replay.gd:253), so an old replay is another game, as after any card change.
  - The intro and the HUD name no card.
- **Docs:** DESIGN.md:27 (starting cards), STORY.md:31, content/spells/README.md (the carrier list, line 33; the examples, line 86), core/README.md, docs/CARRIERS.md (line 3, the launch table at line 174), gameplay/feel/README.md:35, content/cues/README.md, BACKLOG.md:191 (now done), and a DECISIONS.md entry.
- **Left alone:** `art/vfx/nova_ring.svg`. Only `FeelPreset.nova_texture` loads it (feel_preset.gd:90), which nothing reads, and one screenshot. It can go in a cleanup.

## Part 2: Skyfall, the falling modifier (rewritten 2026-11-09 with the owner)

The owner's picture: "A hole opens up and whatever carrier it modifies will shoot out from the hole. It always shoots downwards." The sim has no height, so the fall is drawn and played on the floor plane: the carrier is cast from a hole a little above a spot (up the screen), aimed straight down the screen, and ends on a floor line through the spot. While it falls it is *in the air* and touches nothing; near the floor it is an ordinary shot. One rule for every carrier, no table of what each carrier becomes.

### The rule

1. **The spot** is `behaviour_reach` ahead along the copy's way (120 px on the card, the old rain's), stopped short of the first wall. Reach multiplies it; Homing moves it onto a target near it (the rain's `_homed_place`, moved into the runtime).
2. **The hole** opens `SKYFALL_HEIGHT` (56 px) straight up the screen from the spot, at a fixed height: nothing changes it (owner: "it doesnt really matter gameplay wise if it is further away"). It stays open `SKYFALL_SECONDS` (0.6 s), the warning; the sim only waits (the runtime's queue, `PendingLaunch`, as the rain's landing waits now).
3. **The cast:** when the hole has opened, the carrier is cast from the hole by that point (`CASTER_POINT`, as a Penta copy is), aimed straight down the screen, with the spot's **floor line**: the horizontal line through the spot. Everything it makes knows that line.
4. **In the air:** a shot (or a beam's length) more than `SKYFALL_BAND` (12 px) above its floor line hits nothing, zaps nothing, pulls nothing and passes over room walls. It still moves by its own cards: homing steers it (onto an enemy near the spot), spiral waves it, a speed card makes it fall faster or slower (owner, question a).
5. **Near the floor** (inside the band) it is an ordinary shot: it hits what stands there, walls stop it. So only what stands close to the floor line is struck (owner, question 1).
6. **At the floor line it ends**, as at the end of its life: `on expire` fires and a blast goes off there. The floor is not a wall (owner): `on wall`, bounce and ghost do nothing at it. A split fan from the hole spreads sideways as it falls and lands along the line, a little apart; a shot that homed or waved sideways lands at the line's height, beside the spot (owner, question c).
7. **Placed carriers land on the floor line** (owner, question 4): a rune, pool, wall, decoy, familiar, portal or orbit is placed at the spot (it circles the spot, for an orbit). While a cast falls, the runtime's placement helper (`_placed_at`) answers the spot; the wall and the pool ask that helper instead of working out their own `ray_length` ahead (wall.gd, pool.gd). A fast streak, like an atom's, flies from the hole down to the spot first: a look only, it hits nothing.
8. **What an airborne shot casts is airborne too** (owner, question b): a `timer` or `on hit` payload fired while a shot falls is cast where the shot is, in the air, with the same floor line, so it rains down after it.
9. **Where it does nothing:** carriers held by or carried with the body (MELEE: swing, slam, dash, teleport). Its needs row is `B.SKYFALL: {"needs": {"not": MELEE}}`. A leap is a plan of its own.

So `skyfall · bolt` is a bolt that drops onto the spot and strikes what stands there; `skyfall · beam` is a beam from the hole to the floor, a pillar, that strikes only at its foot; `skyfall · split · bolt` drops three bolts landing side by side; `nova · skyfall · bolt` opens eight holes round you; `skyfall · rune` places a rune at the spot after a streak from the sky.

### The other cards

- Echo falls once more; Mirror also falls behind; Nova makes a ring of spots, one hole each.
- **Penta with Skyfall (owner: "The penta reading is ok!"):** Penta's ring points become the spots: `skyfall · penta · bolt` opens five holes on the ring round its caster and drops a copy onto each, all falling straight down.
- `on cast` fires at the cast, from the hand. Held: a held falling bolt falls again and again (as the held rain did); a held beam stays a pillar while held.
- A rebuild drops a fall the wizard cast, as the rain's landing was dropped; a payload's fall keeps its build. No dice: every machine drops on the same spots.

### What is drawn

All of it in motes first (owner: motes are the world's magic building blocks):
- **The hole:** the card's `shown_cue`, a new cue `skyfall`: a rift of motes in the sky above the spot (the portal's chosen mote-rift look), opening over the warning, in the spell's colours and cards, and the `telegraph` ring closing on the spot. Data only.
- **The fall:** the carrier's own look. A shot is drawn where it is, so it is seen falling; a beam is drawn from the hole to the floor by its own shader.
- **A placed carrier's streak:** a short fast streak flash from the hole to the spot (a flash kind, data), then the carrier's own appear look.
- **The landing:** the card's `cue`, `skyfall_land` (today's `rainfall` renamed): motes thrown up where it lands.
- **The staff:** the carrier's own `staff_pose` plays at the cast and holds through the warning (as the rain's raised staff).

### What changes in the engine

| Where | What | Size |
| --- | --- | --- |
| `ModifierBase`, card folder | behaviour SKYFALL, its needs row, the card (`behaviour_reach` 120), icon, combos, test | small |
| `core/spells/spells.gd` | the Skyfall stage (spot, hole, the wait in the queue, the cast from the hole aimed down); a "falling" context while it casts, read by `_land_shots` (every shot a carrier makes) and `_placed_at` (every placed carrier); a payload cast by an airborne shot takes its floor | medium |
| `core/projectiles/projectile_manager.gd` + `native/src/shot_kernel.cpp` | one number per shot, its floor line (none for every other shot). The move pass ends a shot at its line (as its expiry); the wall walk and the hit pass look only at the part of its step inside the band. The same lines in the GDScript and the kernel, compared byte for byte by test_native_kernel | medium (the one native change) |
| `beam.gd` + the manager's ray walk | a falling beam row keeps its floor line; its length is the drop, and its ray hits and meets walls only in the band (a one-shot setting before the ray, as `ray_gates` is) | small |
| wall.gd, pool.gd | ask `_placed_at` instead of their own `ray_length` ahead | small |
| CastSense, `next_cast_reach` | a falling cast is an area at the spot's distance (as the rain was) | small |
| Feel, content | cues `skyfall`, `skyfall_land`, a streak flash kind: data | small |

What it does *not* need, compared with the first version of this plan: no second set of yes/no answers per carrier (`fallen_traits`, `CompiledSpell.traits`), no extra columns in test_card_rules (the carrier keeps every card it had; Skyfall's probe is "target behind a wall": it falls over the wall), and no pillar mode in the beam (Part 3 is gone: the pillar is just a beam cast down from the hole).

### Checks

- The card's test: a bolt drops onto the spot; an enemy just up the screen from the spot (in the column, above the band) is not hit, one at the spot is; a wall between caster and spot is passed; a split lands three apart along the line; a rune is placed at the spot; a timer payload falls too; nova makes eight holes; MELEE carriers waste it.
- The projectile manager: a shot with a floor line ends at it and hits only in the band, at any speed (a step that jumps past the band still hits what stands in it), in the GDScript and the kernel alike.
- test_card_rules: Skyfall's probe (target behind a wall), and its needs row.
- test_determinism and test_state_declared for the new state (the shots' floor lines, the falls waiting in the queue).

## Part 3: the beam's pillar (folded into Part 2)

Gone as a phase: with the owner's hole, a falling beam is cast down from the hole to its floor line and strikes only near the floor, so it is a pillar with no beam code of its own beyond its floor line.

## Part 4: removing rain

- **The carrier and the card:** delete `core/spells/carriers/rain.gd` and `content/spells/forms/rain/`. Its two combos (`rain_blast_drop`, `rain_frost_field`, since #648) move to Skyfall's folder as `skyfall` combos.
- **The payload-carrier code, which only rain used:**
  - `CARRIES_PAYLOAD` (carrier_traits.gd:41-42, carrier.gd:32);
  - `Carrier.land` (carrier.gd:485-488);
  - `FormBase.carries_payload` (form_base.gd:214-217);
  - `CompiledSpell.own_payload` (compiled_spell.gd:167-168);
  - the compiler (staff_compiler.gd:159-161, 705-706), the tree (spells.gd:774-775), CastSense (cast_sense.gd:132, 151-158) and `_group_has` (spells.gd:3519);
  - `PendingLaunch.landing` (spells.gd:191-193, 1766, 1818-1826, 1858, 1872-1873, 1887). Skyfall's own field replaces it.
- **Limits:** `RAIN_REACH` becomes `SKYFALL_REACH`'s card number (`behaviour_reach` 120); `RAIN_SPLASH` goes (a falling shot strikes with its own size in the band).
- **Cues:** `rainfall` becomes `skyfall_land`. `telegraph` stays, for Skyfall.
- **The AI:** nothing special-cases rain. The hits in team_board, evade, open, close_in, fight, heal_ally, behaviour, brain, entities, decoy_controller, dummy_look and creature_look are the words `brain` and `AIBrain`; swarm.gd's is `AIBrain` and coop.gd's is `DRAIN`. The only real mention is a comment in gameplay/ai/README.md:21. The AI reads CastSense (`area`, `repeats_held`), which reads answers, so it sees a falling bolt the way it saw a rain.
- **The Bone Scepter** (bone_scepter.tres:24): `rain · void · blast` (since #648) becomes `void · skyfall · bolt` (owner, answer 3). Also test_strays.gd:29 and 159-160, and the reasoning in DECISIONS.md:918.
- **Tests:**
  - port to `skyfall · bolt`: test_spells_payload_carriers (20 lines), test_trigger_table (67-69, 109-141, 158), test_carriers (98, 114-116) and test_behaviour_table (`shield · rain`, `blast · rain`, `hold · rain`);
  - remove test_staff_base.gd:61-68 (no carrier carries a payload now) and test_card_rules.gd:373-374;
  - also test_cast_sense, test_spells_live_carriers, test_fallback_carriers, the Feel tests (test_feel_forms, test_feel_carrier_cues), the deflect, decoy, homing, blast and penta card tests, and the screenshots (shot_staff_poses.gd:69, shot_carrier_moments).
- **Comments that name rain:**
  - spells.gd: 88-89, 174, 191, 289, 292-293, 372, 413, 749, 1062, 1386, 1417, 1477, 1600, 1655, 1864-1865, 1883, 3349, 3479-3480;
  - ray_hit.gd:4, carrier_traits.gd:35 and 43, events.gd:106 and 108, homing.gd:8, carrier_kit.gd:106, point.gd:5, compiled_group.gd:5;
  - form_base.gd:53, 60, 74, 104, 108, staff_poses.gd:91, modifier_base.gd:223, feel.gd:1665 and 2382.
- **Docs:** CARRIERS.md (lines 26, 88, 107, 174, 183), content/spells/README.md:33 and 45, core/README.md, DESIGN.md:27, BACKLOG.md:40 (the rain cue item goes), and a DECISIONS.md entry.

## Part 5 (proposal): Orbit as a modifier too

The owner, 2026-11-09, on the orbit's look: "Hmm maybe orbit should also just be a modifier instead of a carrier". Not yet decided; this part says what it would take, so it can be weighed with the other two.

- **The idea:** the next carrier circles its caster instead of going out. `orbit · bolt` is a bolt circling you; `orbit · rune` runes circling you; `orbit · wall` a ring of stones turning round you; `orbit · pool` a puddle that follows you round; `orbit · beam` a beam sweeping round like a lighthouse.
- **How:** a behaviour, `ORBIT`, with `behaviour_reach` the circle's radius and the carrier's speed as how fast it turns (`turn = speed / radius`, as `CarrierOrbit.spawn_row` does now, orbit.gd:26-29). The carrier spawns its rows through the manager's orbit motion (`spawn_orbit`) instead of its own. Copies are spread evenly round the circle by the stages above: `orbit · triple · bolt` is today's three orbs, and with Nova, eight.
- **Still carriers that orbit** (rune, wall, pool) move, so they gain MOVES. Their looks are quads, and the card-looks rule sends a shot whose motion draws another mesh to its motion's plain batch (card-looks.md, phase 1): an orbiting rune would draw as a plain orbit shot. Orbit motion would have to draw the body's own mesh (a quad body stays a quad while it circles), in the GDScript and the native kernel. This is the one native change in the whole plan.
- **A beam that sweeps** turns its aim round the caster each step. It is beam work, like Part 3's pillar.
- **Where it does nothing:** carriers that move the caster or are held by the body (MELEE: swing, slam, dash, teleport), and the familiar, which already circles.
- **What goes:** `core/spells/carriers/orbit.gd`, `content/spells/forms/orbit/` (the modifier takes the id `orbit`, as Nova does), and every staff naming `orbit` becomes `orbit, triple, bolt` (or whatever keeps today's three orbs). The orbit card needs no look of its own: whatever circles keeps its own.
- **Lifetime:** a bolt lives about a second, today's orbit three. The card would lengthen its carrier's life (a `lifetime_mult`), or circling bolts are gone almost at once (question 13).

## Order, size, risk

| Phase | Size | Native | Risk |
| --- | --- | --- | --- |
| 1 Nova modifier, nova form gone (done, #648) | medium (most of it mechanical: about 100 files go from `nova` to `nova, bolt`) | no | the pacing count (`copies`); 8 swings or slams start the staff animation once; tests that measured the old nova's single batch (test_spells_land_shots) now see 8 launches |
| 2 Skyfall (the hole, the beam's pillar with it) | medium to large: one PR | yes (each shot's floor line in the move and hit passes, mirrored in the kernel) | a step that jumps past the band must still hit what stands in it, alike in the GDScript and the kernel; the falling context reaching every shot and placement (`_land_shots`, `_placed_at`) and payloads of airborne shots; the waiting queue on rebuilds |
| 4 rain gone | medium | no | the Bone Scepter's staff; the payload-carrier code removed |
| 5 orbit as a modifier (if wanted) | large | yes (orbit motion draws a quad body's own mesh) | every carrier's rows through orbit motion; still shots that move; a sweeping beam; the kernel compared byte for byte |

One PR each. Phase 4 needs phase 2, so the Bone Scepter and the combos have something to move to; phase 3 is part of phase 2.

**Cards together, for the record:** Mirror on a nova of an even number casts each copy twice (the reversed ring falls on the same angles), so double damage. Penta on a nova makes eight Penta rings on the same five points. Both follow the rules. Question 7 offers a one-line change so the second case spreads out instead.

## Questions for the owner

1. **Nova on a dash or teleport:** like Mirror (it works: the moves cancel, you stay, and each move strikes round you) or like Penta (it does nothing)? *Recommended: like Mirror, so the rule is one: a nova is a mirror with eight ways.*
2. **Nova's reach:** each carrier keeps its own (a nova of bolts flies about 264 px, the old Nova about 60), or the card shortens it with Reach x0.5? *Recommended: keep each carrier's own reach.*
3. **The falling card's name:** Skyfall, Downpour or From Above? *Recommended: Skyfall, with Downpour for the several-drop card.*
4. **One drop or several?** *Recommended: both on one behaviour. Skyfall drops once, Downpour four times scattered by the run's dice; the second card is data only.*
5. **A falling beam:** a pillar on the spot (Part 3), or a beam cast from the spot along the aim? *Recommended: the pillar.*
6. **Skyfall on a dash or teleport:** nothing now (they are melee), and a leap later as its own plan? *Recommended: yes.*
7. **Penta with a nova:** let each Penta ring start at its copy's way, so eight rings spread to 40 points instead of stacking on 5 (Mirror with Penta would then interleave too)? *Recommended: yes, it is one line.*
8. **Walls:** a falling carrier stops at the first wall, as the rain did, rather than landing behind it? *Recommended: stop at the wall for now.*
9. **The falling body's look:** the shared `drop` flash in the spell's colours and cards, rather than each card's own look while it falls? *Recommended: the shared flash now; a card's own falling look later, if wanted.*
10. **The Bone Scepter:** `void · downpour · bolt`? *Recommended: yes, or `void · skyfall · bolt` if Downpour does not ship.*
11. **Orbit as a modifier:** yes or keep the carrier? *Recommended: yes, after Nova and Skyfall land; it reuses their stages and is the biggest of the three (the only native change).*
12. **If yes, orbiting runes, walls and pools:** let them circle (the native change), or orbit only flying carriers and the beam? *Recommended: let them circle; a turning ring of stones is the best thing it makes.*
13. **Orbit's lifetime:** the card stretches its carrier's life to about 3 s, or each carrier keeps its own? *Recommended: the card sets it (x3 on a bolt), so `orbit · triple · bolt` plays like today's Orbit.*

14. **Penta with Skyfall:** Penta's ring points become the spots (five holes on the ring, each dropping a copy), or Penta rings the hole's spot after the fall? *Recommended: the ring points become the spots.*

## The owner's answers (2026-11-09)

1. **Nova on a dash or teleport:** like Mirror (the moves cancel, each still strikes).
2. **Nova's reach:** each carrier keeps its own.
3. **No Downpour.** Several drops are made with other cards: `split · skyfall · bolt` drops a row of three, Scatter or Triple in front scatter or triple the drops. One card, Skyfall, with one drop. So the Bone Scepter becomes `void · skyfall · bolt` (question 10).
4. **The falling beam is the pillar, and it comes from above:** drawn from high above the spot straight down onto it, striking round the spot when it meets the floor, for its life.
5. **Orbit as a modifier:** yes, after Nova and Skyfall (Part 5).

On how Skyfall works, the owner asked whether it is "an opening in the sky that shoots down towards the ground, with a small invisible wall placed there to make it look like it hits the floor". At first the plan kept a sim that only waits and casts at the spot, because a shot from a hole up the screen would hit what stands on the way. After discussing it the owner chose the hole (Part 2 rewritten):
- The carrier shoots down from a hole up the screen and ends on a floor line through the spot; the beam's pillar is then just a beam cast down (Part 3 folded in).
- Enemies in the column are only hit near the floor: a falling shot is in the air (no hits, no walls) until it is within a small band of its floor line (owner: "only hit, if they stand close to the fake floor wall"); it passes over room walls on the way down.
- The floor is not a wall (owner: "It does not!"): it ends the shot as its expiry; `on wall`, bounce and ghost do nothing there.
- Placed carriers land on the floor line, after "a simple fast ray (like atom would look like), that flies down from the heavens and places it".
- The hole's height is fixed; Reach and Bigger do not change it.
- Penta with Skyfall (question 14): Penta's ring points become the spots (owner: "The penta reading is ok!"). Build it so it adds little complexity and is easy to remove again (owner).
- Then (questions a to c, owner: "I agree!"): an airborne shot still homes and waves but touches nothing; what an airborne shot casts falls too, to the same floor line; the floor is a horizontal line through the spot.

Then (the same day): "Please use motes for everything you can. I really like that they are sorta the 'magic' building blocks in this world we are creating." So the opening in the sky, the falling body and the landing are built of motes first (the falling carrier a stream of motes in its colours, the pillar's edges shedding motes, motes thrown up where it lands), and Nova's ring cue gets more motes too.
