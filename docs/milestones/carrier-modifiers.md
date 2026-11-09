# Carrier modifiers: Nova and Skyfall

**Status: Part 1 (Nova) merged #648 (2026-11-09). Part 2 (Skyfall) rewritten with the owner the same day around the hole, Part 3 folded into it, and merged #650; Part 4 (rain removed) merged #652 the same day; Part 5 (Orbit) decided with the owner and planned (5A, 5B). The owner's answers below.** The owner, 2026-11-09: "Rain is looking really bad. I dont really like rain. Maybe remove it and add an AOE modifier instead, which makes the modified carrier "rain down" from above. Could be used for a fireballs from above or beams or whatever", and "Nova could probably be replaced by a "Nova" modifier card instead, which would allow us to make novas of other carriers".

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

firing (`_fire_spell`: mirror, echo, recoil, `on cast`) → **nova** (N ways round) → **penta** (a ring round whoever casts it now) → **skyfall** (a hole over where it is cast, or over each Penta point; after the fall, cast by the hole) → the carrier's `launch`.

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

1. **The spot** is where the cast comes from (owner, after the first build: "It should just open up on the spot it is cast from, like over the player, or above a projectile with on_hit skyfall"): over its caster, over the point or shot a trigger fired from. No card moves it: homing steers the falling carrier and Reach lengthens it, as on any carrier; the floor ends it first.
2. **The hole** opens `SKYFALL_HEIGHT` (56 px) straight up the screen from the spot, at a fixed height: nothing changes it (owner: "it doesnt really matter gameplay wise if it is further away"). It stays open `SKYFALL_SECONDS` (0.6 s), the warning; the sim only waits (the runtime's queue, `PendingLaunch`, as the rain's landing waits now).
3. **The cast:** when the hole has opened, the carrier is cast from the hole by that point (`CASTER_POINT`, as a Penta copy is), aimed straight down the screen, with the spot's **floor line**: the horizontal line through the spot. Everything it makes knows that line.
4. **In the air:** a shot (or a beam's length) more than `SKYFALL_BAND` (12 px) above its floor line hits nothing, zaps nothing, pulls nothing and passes over room walls. It still moves by its own cards: homing steers it (onto an enemy near the spot), spiral waves it, a speed card makes it fall faster or slower (owner, question a).
5. **Near the floor** (inside the band) it is an ordinary shot: it hits what stands there, walls stop it. So only what stands close to the floor line is struck (owner, question 1).
6. **At the floor line it ends**, as at the end of its life: `on expire` fires and a blast goes off there. The floor is not a wall (owner): `on wall`, bounce and ghost do nothing at it. A split fan from the hole spreads sideways as it falls and lands along the line, a little apart; a shot that homed or waved sideways lands at the line's height, beside the spot (owner, question c).
7. **Placed carriers land on the floor line** (owner, question 4): a rune, pool, wall, decoy, familiar, portal or orbit is placed at the spot (it circles the spot, for an orbit). While a cast falls, the runtime's placement helper (`_placed_at`) answers the spot; the wall and the pool ask that helper instead of working out their own `ray_length` ahead (wall.gd, pool.gd). A fast streak, like an atom's, flies from the hole down to the spot first: a look only, it hits nothing.
8. **What an airborne shot casts is airborne too** (owner, question b): a `timer` or `on hit` payload fired while a shot falls is cast where the shot is, in the air, with the same floor line, so it rains down after it.
9. **It hits its caster** if it still stands under the hole when the fall lands: the hole is a point and spares no body (owner: "This is just following the general rule"); an `on hit` fall strikes what was hit too. Nova's eight copies stack on the same spot (owner: fine).
10. **Where it does nothing:** carriers held by or carried with the body (MELEE: swing, slam, dash, teleport). Its needs row is `B.SKYFALL: {"needs": {"not": MELEE}}`. A leap is a plan of its own.

So `skyfall · bolt` is a bolt that drops where you stand and strikes what stands there, you too; `on hit · bolt · skyfall · bolt` strikes what the first bolt hit again from above; `skyfall · beam` is a beam from the hole to the floor, a pillar, that strikes only at its foot; `skyfall · split · bolt` drops three bolts landing side by side; `nova · skyfall · bolt` stacks eight falls on your spot; `skyfall · rune` places a rune at the spot after a streak from the sky.

### The other cards

- Echo falls once more; Mirror and Nova cast their copies from the same place, so their holes stack on the same spot.
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
| `ModifierBase`, card folder | behaviour SKYFALL, its needs row, the card, icon, combos, test | small |
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

## Part 4: removing rain (done 2026-11-09; what differed from this plan: docs/DECISIONS.md, "Rain is gone")

- **The carrier and the card:** delete `core/spells/carriers/rain.gd` and `content/spells/forms/rain/`. Its two combos (`rain_blast_drop`, `rain_frost_field`, since #648) move to Skyfall's folder as `skyfall` combos.
- **The payload-carrier code, which only rain used:**
  - `CARRIES_PAYLOAD` (carrier_traits.gd:41-42, carrier.gd:32);
  - `Carrier.land` (carrier.gd:485-488);
  - `FormBase.carries_payload` (form_base.gd:214-217);
  - `CompiledSpell.own_payload` (compiled_spell.gd:167-168);
  - the compiler (staff_compiler.gd:159-161, 705-706), the tree (spells.gd:774-775), CastSense (cast_sense.gd:132, 151-158) and `_group_has` (spells.gd:3519);
  - `PendingLaunch.landing` (spells.gd:191-193, 1766, 1818-1826, 1858, 1872-1873, 1887). Skyfall's own field replaces it.
- **Limits:** `RAIN_REACH` and `RAIN_SPLASH` go (Skyfall falls where it is cast, and a falling shot strikes with its own size in the band).
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

## Part 5: Orbit as a modifier (decided 2026-11-09)

The owner, 2026-11-09, on the orbit's look: "Hmm maybe orbit should also just be a modifier instead of a carrier", then yes (question 11), and in the talk that followed: "Orbit is motion only", "no special cases". The rule and the decisions are below. Two PRs: 5A and 5B.

### The rule

**Orbit changes only how the next carrier moves.** Every row the carrier makes circles its caster instead of going out. Everything else is the carrier's own: its look, size, hits, pierce, payloads, infusions, pose. Orbit adds no count, no spread, no pierce and no look to what circles.

- **Where a row starts:** on the circle, in the direction it would have gone. That is the way from its caster to the row's start point, or its heading when it starts at the caster. So `orbit · bolt` is one orb starting at the aim. `orbit · split · bolt` is Split's fan circling as a tight cluster, which Sniper or a wild card tightens or loosens. `orbit · nova · bolt` is eight orbs spread evenly, because the copies leave eight ways. `orbit · wall` is the wall's stones side by side across the aim, circling as an arc.
- **Its caster** is whatever cast it, as for the orbit carrier today (`CarrierOrbit.spawn_row`'s centre, `Spells._register_shots`): the wizard's body, which it follows, or for a payload the shot or point that cast it. `skyfall · orbit · bolt` falls, then circles the spot it landed on. `on_hit · bolt · orbit · rune` circles where the bolt hit.
- **Radius:** the card's `behaviour_reach`, 36 px. Reach does not widen it (that would give Reach a second meaning). A bigger circle is a later card, such as an upgraded Orbit, with a bigger number. With two orbit cards on one carrier, the larger radius counts, as `behaviour_reach` does for homing.
- **Turn:** `turn = drift + speed / radius`. The carrier keeps its own speed and spends it going round. The card adds a slow drift, its `behaviour_strength` in turns a second (1/3: one turn in the orbit's 3 s), so a carrier with speed 0 still circles. The turn follows the shot's speed through its life, so Faster, Slow and the speed curves (`speed_start`, `speed_end`, `speed_ease`) act on it as on any shot. At 36 px, a rune, pool, wall or beam makes 0.33 turns a second, a bolt 1.3, a swap 1.7 and an atom 5.2.
- **Duration:** fixed, 3 s, through a general card field (below), not through orbit code.
- **No special rules for circling shots.** Room walls end them as they end any shot, and Ghost lets them pass. The AI predicts them like any shot, from their present (tangent) velocity. Homing does nothing on them (owner: question 6 a), because orbit motion has no heading to steer. A deflected one leaves its circle and flies on along its tangent, which is the deflect rule (`deflect_shot`). The spiral-out from the caster when cast is drawing only, so it stays.

### Duration: a new general card field, `lifetime_base`

`ModifierBase.lifetime_base: float = 0.0` (0 means none) sets the carrier's lifetime before any factor applies. The compiler sets the base first, then applies the factors (`lifetime_mult`, and `reach_mult` where it means life), so the order of the cards does not matter. With several cards that set a base, the longest wins.

Orbit's `.tres` says `lifetime_base = 3.0`, and no orbit code knows about it. So a bolt (1.2 s) and a rune (8 s) both circle for 3 s, `orbit · slow · bolt` circles for 9 s slowly, and `orbit · reach · bolt` circles longer, because Reach on a flying shot means more life (owner: question 3 a). `hold` keeps a held carrier going as it does anywhere. The field goes in `staff_compiler.gd` next to `lifetime_mult` (about lines 390 and 500), with its own row in the card text and a test in `tests/core/test_staff_compiler.gd`.

### Where it works: traits only

Orbit is a `ModifierBase.Behaviour.ORBIT`, added at the end of the enum, with a `RULES` row that names no carrier:

- **5A:** `{"needs": {"any": FLIES | LINE, "not": MOVES_CASTER | OWN_POSE}}`, so bolt, atom, swap and beam.
- **5B:** `{"needs": {"any": FLIES | STAYS | LINE, "not": MOVES_CASTER | OWN_POSE | SPAWNS | GATES}}`, which adds rune, pool and wall.

It does nothing on dash and teleport (they move the caster), swing and slam (they strike from the hand), and familiar, decoy and portal (they make actors or gates, not rows). A lone `orbit` lands on the caster or point fallback and does nothing. If actors should circle one day, the row changes; no exception is added. `tests/core/test_card_rules.gd` checks every carrier against the row.

### How it is built (low coupling, like Skyfall)

- **`core/spells/orbit.gd`** (`class_name Orbit`, a RefCounted like `skyfall.gd`) holds all of the modifier. `orbits(spell)` says whether it applies (`spell.behaviour(ORBIT) > 0` and `carrier.works(ORBIT)`). `circle(slot, spell, actor, origin)` puts a live row on its circle: the start angle from the row's start point or heading, the radius, the drift, and the centre by today's rule.
- **One hook in the runtime:** `Spells._land_shots`, which sees every row a carrier makes (Skyfall's hook already sits there), calls `Orbit.circle` on each row of a spell that orbits. No carrier knows about orbit. Each carrier still spawns its rows as before, and they are turned into circlers afterwards.
- **The projectile manager** gains `set_orbit(slot, radius, angle, drift, centre)` on a live slot. It replaces `spawn_orbit`, whose one caller goes with the carrier. The orbit step reads the turn from the shot's present speed (`drift + _speed[slot] / _orbit_radius[slot]`) instead of a stored angular speed. The step, and `set_orbit`'s setup, are mirrored in `native/` (`ShotKernel`) and compared byte for byte by `tests/core/test_native_kernel.gd`.
- **Orbit motion keeps the body's own look.** Today an orbit shot's body, batch and head come from its motion (`KIND_ORBIT`, `BATCH_ORBIT`, `HEAD_ORBIT`, projectile_manager.gd about lines 391, 360, 487, 5100, 5418-5428, 6340, and `feel.gd:1326`). That is a special case, so it goes. A circling bolt draws as a bolt, in the bolt batch; in 5B a circling rune draws as a rune. The body comes from what the carrier spawned (flying head or still quad), not from the motion. GDScript and native alike.
- **The beam sweeps.** `beam.gd`'s step turns its aim round its caster by the turn (drift only, since a beam's speed is 0) each step, for its 3 s. A held beam sweeps for as long as it is held. The beam keeps its own length. Homing does nothing on a sweeping beam, as on a circling shot.
- **The cue:** the card's `cue = &"orbit"`, shown when cast: a ring of motes traced at the radius in the spell's infusion colours (the owner's rule: motes for everything; question 9 yes). It is today's `cast_orbit` remade in motes and renamed. What circles keeps its own look and cues.

### Part 5A: the modifier on flying carriers and the beam; the carrier goes

1. `Behaviour.ORBIT` with its `RULES` row (5A needs), and `lifetime_base` in ModifierBase and the compiler, with tests.
2. `core/spells/orbit.gd`, the `_land_shots` hook, and `set_orbit` plus the speed-driven turn in the manager and `ShotKernel`.
3. Orbit motion draws its body's own head and batch: `KIND_ORBIT`, `BATCH_ORBIT` and `HEAD_ORBIT` go (GDScript, native, Feel).
4. Orbit's special cases go: the room-wall skips (projectile_manager.gd:3099 and 3459), and the AI threat skips (2897, 2958, 3023). `move_shot` refusing an orbit shot (2325) is audited: what pushes a shot (pull, recoil, swap, move) moves a circling shot's centre, unless a real rule turns up. That would be brought to the owner, not decided alone.
5. The beam's sweep.
6. The card: `content/spells/modifiers/orbit/` with `orbit.tres` (`behaviour_id = &"orbit"`, `behaviour_strength = 1/3`, `behaviour_reach = 36`, `lifetime_base = 3.0`, no pierce, damage x1, `mana_mult` about 1.5, `cue = &"orbit"`, a `look_layer`), an icon, `assets.json`, `combos/` and `test_orbit.gd`. Description: "The next spell circles you instead of leaving."
7. **What goes:** `core/spells/carriers/orbit.gd`, `content/spells/forms/orbit/` (the modifier takes the id, as Nova did), `FormBase.orbit_radius` and its range row, `CompiledSpell.orbit_radius`, `SpellLimits.ORBIT_TURN`, `CarrierTraits.RING` (only the orbit carrier has it: cast_sense.gd:139, staff_compiler.gd:532, spells.gd:1971 read it), `spawn_orbit`, and the `cast_orbit` cue (renamed). The carrier count test goes from 14 to 13.
8. **Content:** no staff names `orbit`. The ten combos are rewritten to keep what they show. Today's three orbs become `orbit · split · bolt` (a cluster) or `orbit · nova · bolt` (a ring), whichever the combo means: `fire_fan_orbit`, `void_ring`, `decoy_timer_orbit_deflect`, `frost_carousel` (it adds pierce itself now), `hold_fire_orbit`, `hold_shield_orbit`, `shield_orbit_ring`, `double_beam_and_ring`, `triple_three_ways`, `on_hurt_orbit_nova`.
9. **Tests that name orbit** move to the modifier: test_hold, test_return, test_zap, test_penta, test_decoy, test_on_hurt, test_shield, test_card_rules, test_behaviour_table, test_spells_cast, test_spells_multicast, test_spells_land_shots, test_spells_moves, test_spells_actors, test_spells_deflect, test_projectile_bodies, test_staff_compiler, test_staff_runtime, test_cast_sense, test_trigger_table, test_validators, test_cast_timing, the player bag and build tests, test_radial_builder, test_feel_form_looks, the benchmarks and the screenshot scripts. New tests: start angle from the start point; turn from speed (an atom outturns a bolt, Slow slows it, speed 0 drifts one turn in 3 s); a circling shot ends on a room wall and Ghost passes it; the AI sees a circling shot; `lifetime_base` with factors in any order; a sweeping beam; the native kernel's orbit step.
10. **Docs:** CARRIERS.md, content/spells/README.md, core/README.md, DESIGN.md (the card list), card-looks.md (the orbit look note), BACKLOG.md, and a DECISIONS.md entry: "Orbit is a modifier: motion only, no special cases".

### Part 5B: runes, pools and walls circle

1. The `RULES` row widens to the 5B needs.
2. A still carrier's row becomes a circler through the same `set_orbit`. The manager keeps its body (quad, its card shader, its still-shot age codes `still_since`/`still_left` for the rune) while its motion is orbit. This is the native change: the body is chosen per slot by what was spawned, not by `motion == MOTION_STILL` (projectile_manager.gd:1319, 1338, 2903, 2964, 3028 and the kernel's mirror). `_moves` already counts an orbit as moving, so Linger, Sticky and Spiral read circling runes as moving; the card-rules test is updated to say so.
3. Their motes follow them. Pool and wall motes come from still rows (`gameplay/feel/still_motes.gd`, `look_motes_from`). They read a circling quad body's row the same way, wherever it is.
4. A circling wall still blocks (`BLOCKS`), and a circling pool still slows where it is. Each acts at its row's present place, as its rule already says.
5. Screenshot sheet: `orbit` on bolt, atom, swap, beam, rune, pool and wall, with 1, 2 and 4 infusions. Then a real-GPU check (`webstorm.sh`).

## Order, size, risk

| Phase | Size | Native | Risk |
| --- | --- | --- | --- |
| 1 Nova modifier, nova form gone (done, #648) | medium (most of it mechanical: about 100 files go from `nova` to `nova, bolt`) | no | the pacing count (`copies`); 8 swings or slams start the staff animation once; tests that measured the old nova's single batch (test_spells_land_shots) now see 8 launches |
| 2 Skyfall (the hole, the beam's pillar with it) | medium to large: one PR | yes (each shot's floor line in the move and hit passes, mirrored in the kernel) | a step that jumps past the band must still hit what stands in it, alike in the GDScript and the kernel; the falling context reaching every shot and placement (`_land_shots`, `_placed_at`) and payloads of airborne shots; the waiting queue on rebuilds |
| 4 rain gone (done) | medium | no | the Bone Scepter's staff; the payload-carrier code removed |
| 5A orbit modifier on flyers and the beam, carrier gone | large (many tests name orbit) | yes (turn from speed, body look not by motion) | rows turned into circlers after they spawn; walls and the AI now meet circling shots; the beam's sweep; the kernel compared byte for byte |
| 5B runes, pools and walls circle | medium | yes (a quad body under orbit motion) | still-shot looks, age codes and motes on a moving row; card rules that read MOVES |

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

### On Orbit (2026-11-09, the talk after question 11)

The owner: "no special cases". The answers to the talk, as built into Part 5:

- **Count:** Orbit is motion only and makes one of whatever it carries. More come from Split, Nova and the like.
- **Where a row starts:** in the direction it would have gone (yes).
- **Turn:** the card's own drift, scaled by the carrier's speed: `drift + speed / radius`, with a drift of one turn in the orbit's life (yes). An atom circles faster than a bolt.
- **Radius:** the card's own number. Reach does not widen it, because that would be a special case. A later, upgraded orbit card can have a bigger one.
- **Duration:** fixed, 3 s, "implemented well and with low coupling": the general field `lifetime_base`, set before the factors, so Slow and Reach still act on it (option a).
- **Pierce:** none of its own.
- **Homing:** does nothing on a circling carrier (a).
- **Walls and the AI:** no special rules. Walls end circling shots, Ghost passes them, and the AI sees them.
- **Phasing:** 5A, then 5B. **Look:** a ring of motes traced at the radius when cast.
