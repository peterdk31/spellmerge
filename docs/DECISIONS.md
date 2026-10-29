# Decisions

Why things were decided, so they aren't reversed by accident. Newest first.

## 2026-10-28: Wall card numbers

Wall is a complexity-2 carrier: five still stones 9 px apart (a 36 px row plus the stone radius). The stones are 10 px across, so neighbours overlap by 1 px on purpose: the row has no gap to slip through, and an enemy touching two stones at once can take both hits, which is what a wall of stones should do raised 28 px ahead (the engine's `WALL_REACH`), 3 damage each, 6 mana, a 1 s cooldown, and stones that last 5 s. A stone is spent by its first hit (no pierce), so the row is a barrier of several small hits rather than one big trap like the rune. Not in the free demo.

## 2026-10-28: Fissure card numbers

Fissure is a complexity-2 carrier: 2 damage, 5 mana, a 0.8 s cooldown, a 200 px line 6 px wide (the engine pierces up to 16 targets). Its line is a little shorter than the beam's 240 px because it hits everything on it. Not in the free demo. Its `lifetime` is unused: a fissure hits once, as one instant ray. Its cast and impact looks are modelled on the beam's, to be tuned in the Feel work (B6b). `bounce · fissure` still stops at walls (backlog).

## 2026-10-28: Rain card numbers

Rain is a complexity-2 carrier: 6 mana and a 1.5 s cooldown (its payload pays its own on top), a 0.8 s warning before it lands, and an aim point 120 px ahead (the engine's default reach). It has no damage of its own. Not in the free demo.

## 2026-10-28: Mirror card numbers

Mirror is a complexity-1 modifier with no mana or cooldown of its own (the back shot is free, so `mirror · recoil · bolt` cancels the push), strength 1.0 (the engine only tests for more than 0).

## 2026-10-28: Scatter card numbers

Scatter draws 2 extra carriers (three in all, as the design says) for 4 mana once, like triple. Its combos check reactions (thaw, kindle), which do not depend on the random direction, rather than damage totals; orbit combos were left out because an imp keeps one status at a time, so which orbit hexed or chilled it was not reliable.

## 2026-10-29: A possessed enemy's death still counts as an enemy's

The burst PR's bots left the room uncleared after possessing an enemy. The cause was `Combat._die`: it sends `enemy_died` only for a body not on the wizards' team, and a possessed enemy is on its driver's team, so flow never removed it from the wave. `_die` now judges an actor by its own (home) controller's team, not the driver's; the death itself ends the possession before `_die` runs, so `possessed_by` is no use there. Familiars and other allies of the wizards still send none. Regression test in `tests/gameplay/flow/test_flow.gd`; `Bot.build_random` builds `possess` again.

## 2026-10-28: Burst card numbers; bots build without possess

Burst fires the group 3 times, 0.1 s apart (the interval the engine tests use), for 4 mana once (like triple; the later firings are free), and draws no extra carrier. The 4-bot smoke test builds seeded random staffs from the whole bag, so a new card can change them; with Burst a bot built `possess` and the room never cleared, so `Bot.build_random` takes `possess` out of the bag. Whether a possessing player can strand a room is a queued task in `docs/NEXT.md` ("Test: a possessing player cannot strand a room"), which also puts `possess` back in the bag.

## 2026-10-26: Controls: staffs on the shoulders, a pause menu, the builder on B

The owner's direction after B7a: "The 4 staffs should be mapped to lb/rb lt/rt instead of the face buttons", "The spellbuilder should open by pressing B", "The settings menu should be in a pause menu, opened by pressing start", "Friendly fire should be located in a settings menu under gameplay", "Slow-motion is not needed".

- **Staffs:** RB staff 1 (starts with `dash`), RT staff 2 (`fire · bolt`), LB staff 3, LT staff 4 (the owner's order). The actions are `staff_1` to `staff_4`; the keyboard and mouse keep Space, left mouse, right mouse and Q. The triggers are axes, routed in `core/input` (LT was unused before). Text names a staff by number ("Staff 2", tabs "1 2 3 4"); the glyphs show RB/RT/LB/LT, R1/R2/L1/L2 or R/ZR/L/ZL, and the triggers have their own glyph shape.
- **The face buttons are the menus':** new actions `accept` (A; Enter, Space), `back` (B; Tab, E) and `alternate` (X; X, Delete), so a menu no longer reads a staff button. Y is free: the owner will find a use for A, X and Y later (a map view is one idea, in BACKLOG).
- **B opens the builder in play.** It is the same action as a menu's back, so `panels.gd` opens the builder only when the player had no menu open at this poll and the one before; the B that closes a menu never reopens the builder.
- **Start opens a pause menu** (`hud/menus/pause/`) that stops the game for everyone (co-op rule 6) and is worked by the player who opened it: Resume, Sandbox (in the sandbox), Settings > Gameplay > Friendly fire. Start (or Escape) also closes the builder. The per-player overlay is gone; its only jobs were opening the builder and the sandbox page. `PlayerInput`, `UIFocus` and the HUD run while the tree is paused.
- **Friendly fire for every run, through events:** `friendly_fire_requested(player, on)` (hud to coop) and `friendly_fire_changed(on)` (coop to hud); the menu shows coop's answer. In memory until `core/save`.
- **Slow motion is dropped** (owner), so Feel's hit-stop keeps `Engine.time_scale` to itself.

## 2026-10-26: Caster kit details (staffs B4)

- **Only recoil is held to the next step.** The events ask for "the recoils of a step added up, a later dash, teleport, hook or swap replaces an earlier one". A move that is not a recoil is acted on the moment it arrives (so "later replaces earlier" is the order of arrival), and the replaced one is answered with `caster_move_finished` where the wizard stands, so its blast and `on expire` payload are not lost. Recoil requests are summed and applied by the next `step`; the distance of each is measured from the staff tip.
- **A move walks its whole time.** The dash used to end at the start of the step in which its time ran out, so it walked one step too few (a quarter of a short swap). The time now runs after the step's velocity is set and the move is answered by the next step, when the body has got there.
- **Statuses and pushes.** Chill and freeze slow walking and dashing; a hook, swap, recoil and combat's push are not slowed (they are done to the wizard, not by it). A swap sends no `caster_move_finished` (core/spells ignores it; its blast goes off at the target).
- **Wall safety.** A teleport is clipped by the projectile manager's wall grid and backs off `TELEPORT_CLEARANCE` (8 px); hook, swap and recoil are moved by `move_and_slide` and so stop at walls.

## 2026-10-26: The spark pool and the form looks on cards (staffs B6b)

- **The pool is a budget, not nodes.** The shader draws a shot's particles, so "one shared pool with a global count" is an accounting the manager does each `update_draw`: every drawn player shot asks for `particles_of(look)` (4 + 2 per emitting kind, at most 12) and a bolt's trail for `TRAIL_COST` (4); the cap is `particle_cap` (1,024, a var so the effect quality setting can set it later). Particles are served first, the trails get the rest (`trail_share`, 0 to 1, shortens the trail), and past the cap the particles thin by the same share for every shot (a shot rounds its own count by its seed, so the total stays near the share). Enemy shots and plain shots ask for nothing. Two uniforms carry it, so no per-shot data changes.
- **Form looks are `FormBase` dictionaries** (`cast_look`, `impact_look`), not new typed fields: the keys are the ones the preset used, all optional, and Feel reads them once per card id (a cache, no allocation per cast). Feel looks the card up in the registry folder `spells` (forms live there with every other card); a card with no look, or no registry, gets the muzzle flash and the wall spark. The preset lost `cast_looks`, `impact_looks`, `rune_texture` and `orbit_texture` (the shader has drawn runes and orbit shots since B6a); the SVG files stay, other sheets use them.
- **Clips:** the two four-player clips have kind `combo` (the clip pipeline's kinds are owner-path), ids `combo_four_players` and `combo_spark_crowd`.

## 2026-10-26: Combat kit details (staffs B3)

- **New events** (`core/events`): `wizard_shield_requested` and `pull_requested` (from `core/spells`, so spells never call combat), `hit_landed` (kind, just before `damage_dealt`; Feel reads it, so `damage_dealt` keeps its shape) and `heal_dealt` (`gameplay/player` applies it, so combat never writes a wizard's health).
- **Statuses on wizards** needed a meaning for each: burn is damage over time that a barrier does not stop (a tick is not a hit); chill and freeze slow (`wizard_speed_factor`, used by B4); hex adds damage taken; shock adds its share to the next hit and is spent; static makes the wizard a lightning rod that discharges that share of the next hit to enemies near. Reactions do not run on wizards (no rows for them); revisit if C2 asks.
- **Barriers** stop a hit whole (no damage, status or push); a wizard's `is_invulnerable` is checked first, so the dash (no invulnerability since A6a) is the barrier's use case.
- **Mend** is a field on the element (`ElementBase.heals`); enemies take a tenth of the damage (`SpellLimits.HEAL_ENEMY_SHARE`, at least 1). **Heavy** multiplies the knockback and arms a slam of `SLAM_SHARE` times the damage; combat finds the wall itself (`clip_to_walls`), so the enemy mover needs no change.
- **`kill_landed` only for a spell's hit,** not for a burn tick, a slam, a shock jump, a static discharge or a reaction's damage: "on kill" needs a carrier whose own hit killed. A burn tick on a wizard is not a hit either: no hex bonus, no shock or static spent. Several elements: reactions are one per hit on a target, but the elements of one hit chain; on a wizard every element's status goes on and none reacts. A slam is told as kind `reaction`.
- **"Downed by your own ..."** is text from combat (`downed_note`) shown by Feel, with `HitProfile.source_name` filled by the namer (E1); until then the kind's word is used.
- **An old test changed:** "wizards get no status from player spells" was the pre-staffs rule and now says the opposite (the design: statuses on wizards).

## 2026-10-26: Trigger kit, part 4 (staffs B2d)

- **Where each card asks for movement.** Teleport (and dash) ask at cast; hook and swap ask when their shot hits (a miss moves nobody); recoil asks for each firing of the cast's own group (not payloads), `strength` pixels against the firing's heading, so `mirror` pushes both ways and cancels. Durations are `SpellLimits.HOOK_SECONDS`, `SWAP_SECONDS`, `RECOIL_SECONDS`; a teleport is at once. Why: the design describes the cards this way; recoil per firing makes `mirror · recoil` cancel without special cases.
- **Swap needs the caster's place**, read from the manager's anchor; without one nothing is traded. `target_move_requested` carries the player first (as in `events.gd`, which differs from the milestone table).
- **End points from `caster_move_finished`** (dash, teleport, hook; other modes are ignored) fire the carrier's `blast` and its `on expire` payload at the arrival. The payload goes along the move's heading. A forgotten build (tag unknown) does nothing.
- **Blast on shots** goes off where a spent shot hit, where a shot expired (also a sticky one, or a wall), and at the end of a beam or fissure. A piercing shot or beam does not blast per target. A hook's blast waits for the arrival, so a missing hook does not explode.
- **Simultaneous moves.** The player (B4) sums the `recoil` requests of one step and lets a later non-recoil move replace an earlier one (written in `events.gd` and the B4 task). `Spells` keeps one move heading per player, so the last asked move wins: of two moves in flight, the first one's `on expire` payload leaves along the later heading. A hook with pierce left can fire its `on expire` payload at the arrival and again when the shot expires; both are accepted for now.
- **Every spent shot blasts.** The blast rule is per shot: each chain jump shot, each echo and each shot of a wall or orbit blasts where it is spent, so a wall of N shots expiring together sends N area hits in one step. A piercing shot does not blast at a hit it survives. Pinned by tests.
- **Siphon** sends one refund of its strength per hit (a beam's every target too); the pool is `player`'s concern (B4).

## 2026-10-26: Trigger kit, part 3 (staffs B2c)

- **Rain's aim point** is `ray_length` (else `SpellLimits.RAIN_REACH`, 120 px) along the aim, stopped at a wall; the delay is the form's `lifetime`. A rain's own `on expire` trigger fires as it lands, after its payload; other events never fire on a rain (it has no shot). Why: the design says the carrier's own payload is read first, then the trigger's; landing is its only end point.
- **Entities count as live shots** of their carrier's tag from `entity_spawn_requested` to `entity_ended`. Why: a familiar casts long after the cast, so its build (and payload) must stay known; it also makes `hold` work for them with the existing machinery, and a revoked or rebuilt-over `hold` build sends `entity_end_requested`. `entity_ended` for a tag with no live entity is ignored.
- **A decoy's or familiar's end point** fires its `on expire` payload (heading right) and its `blast` as `area_hit_requested`. Why: the design names `blast · decoy` and `on expire · decoy · nova`.
- **Wall** is placed `WALL_REACH` (28 px) ahead of the caster, `spread` pixels apart (a shot's diameter if 0). **Fissure** is a beam piercing up to `FISSURE_PIERCE` (16) targets, drawn as a beam cue. Fissure does not yet turn at walls for `bounce` (backlog).

## 2026-10-26: Trigger kit, part 2 (staffs B2b)

- **Scatter is the full circle:** each carrier of a scatter group leaves at a random angle from 0 to 360 degrees off the aim, as the design says "random directions"; the owner's fairness question at D3 covers it. The generator is seeded from player, staff and the staff's cast count, so a replay is the same; a burst's later firings and an echo each carry a seed derived from the cast's, so they point the same way whatever else is cast in between. A payload fired from a hit draws from whatever stream is current, so its directions depend on when the hit lands; only the cast's own firings are reproducible.
- **Later firings are queued, not timed on shots:** a burst's later firings and an echo wait in `Spells` (`SpellLimits.MAX_PENDING` records made once and reused, so a cast allocates nothing; overflow is counted in `delayed_dropped`), start from the original point moved by however far the caster's anchor has moved (the cast's own group only; a payload's stay where they were), and are dropped when the staff is rebuilt or switched off. They cost no mana; the cast paid once.
- **Echo** hits through a second shared `HitProfile` (`echo_hit`, half damage rounded, at least 1), built by the compiler, so no hit allocates. It fires after the strength in seconds, does not echo again, keeps its half damage on chain jumps, and a `hold` carrier does not echo (a sustained shot has nothing to repeat). An echo of a carrier with a trigger registers its own trigger, which is why `echo` doubles triggers. `on cast` fires on the carrier's first launch and again on its echo.
- **Mirror** fires the second shot straight behind the first and only for straight, returning and beam carriers (an orbit, a rune and a dash have no back). Like every modifier it is on one carrier only. `on cast` fires once, not for the back shot.
- **Burst of a payload:** a burst inside a payload fires the payload group again from the same point. Burst repeats of a `scatter` group draw new directions.

## 2026-10-26: Trigger kit, part 1 (staffs B2a)

- **One path for the events that name a shot's tag** (`_fire_event`): it looks the tag up, checks the trigger matches, and uses the shot's record for `max_fires` when the event is being sent for that very shot (`event_slot` with the same tag). `shot_blocked` now sets `event_slot`. A beam has no slot, so while its `ray()` runs an event naming its tag (a kill or reaction its hit caused) counts against `_ray_fires`, the same count `_on_hit` uses. An event with no live shot behind it (a wizard's barrier, `shield_blocked`, a kill from a status tick after the shot is gone) has no count to keep and is limited only by the per-step fire cap; we chose that over keeping a per-tag, per-step table, because it is rare and the cap already bounds it.
- **`on wall` fires on walls only; `on expire` still fires on a wall too** (as before B2a), so existing builds do not change.
- **`on cast`** fires from `_launch_group` right after its carrier launched, from the carrier's origin and heading; payloads nest finitely, and the per-step fire cap bounds it.
- **`on hurt`** keeps a list of live shots with that trigger (cleaned lazily, like timers); it fires for the hurt player's carriers only, from the wizard's position, `max_fires` times each.
- **`relay`** reads the ally's player from the manager (`target_owner_of`), and takes the elements and status of that player's last cast that had an infusion (the first such carrier). The result is a per-slot `HitProfile` that `Spells.hit_profile(tag)` returns while that shot's hit is being sent; it costs one small allocation per pass, not per frame. Several elements per hit are used by combat once B3 lands; until then combat reads the first element and the status. Chain children and payloads do not inherit it.
- **Bounces do not send `on wall`:** a bounced shot does not end, so `projectile_expired` is not sent; the card example "a nova at every bounce" needs a manager event for it, noted in BACKLOG.

## 2026-10-26: Projectile kit (staffs B1)

- **Behaviours are per-shot setters,** called by the spell runtime right after `spawn` (a small `_apply_travel` in `core/spells`, so the cards after B1 are data only). Plain shots keep the old path: flags 0, no extra work.
- **Self-hit and ally-hit exist but are off.** The design says shots may hit their caster; `combat` cannot yet hurt a wizard with a shot (that is B3), so `Spells` does not switch the flag on. B3 turns it on with the self-harm flash. Until then a wizard is never hit by their own shot, as before.
- **Meanings of the numbers:** bounce = times; spiral = full width in px (a wave takes 0.5 s); linger = seconds, stopping at half the shot's life, and the stop is added to its life; growth = factor per second, capped at 4x the first radius (`get_growth_of` is the strength multiplier for B3 to use); sticky = seconds on the target, then an expiry there; shield = charges (summed over cards); return = out for half the life, then back to the caster's anchor at the same speed, hits remembered again on the turn.
- **A returning shot ends with `projectile_expired` at its caster,** so an `on expire` payload fires there. A shield only stops shots of enemies (owner none), costs one charge per shot, and runs after every shot has moved in the step, testing the shield's path against the enemy shot's path (in the enemy shot's frame), so a fast shot cannot tunnel through whatever the slot order.
- **Passing a teammate** is reported once per teammate and shares the hit memory (the last three targets) of the shot. A piercing shot that passes three wizards in a 4-player game can therefore forget an enemy it hit and hit it again; accepted, since it is rare and costs one more hit. A bounce or the return turn clears the memory, so a wizard is passed again after it.
- **A sticky shot keeps its velocity** while stuck (`_advance` never moves it by that), so its payloads fly the way it was flying; a shot that sticks on a step where it also reached a wall stays stuck.

## 2026-10-29: Relay card (staffs C)

- **Relay is complexity 2, strength 1.0, no mana change.** The combo format gained two optional keys so a combo can show it: `mates` (`[x, y, player]`, a teammate's body that shots hit, `ComboArena.add_mate`) and a cast's `dir` (`[x, y]`). The donor teammate casts away from everything, then the relay bolt (with `pierce`) hits the donor's body and carries its element on to the imp behind. The imps in the arena cannot cast, so the "steal from an enemy" case stays in `test_spells_triggers.gd`. The clip recorder ignores the two keys, so the relay combos' clips show no teammate.

## 2026-10-29: Magnet card (staffs C)

- **Magnet reaches 70 px and pulls at 200 px/s** (`behaviour_strength`; `SpellLimits.MAGNET_PULL`), complexity 2, no mana change. Each step every live magnet shot sends `pull_requested` from where it is; combat keeps the pull as a push that the next pull replaces, so it does not pile up. The event pulls enemies only (`Combat.pull(..., foes_only)`): the caster, who is inside the reach for the first 0.3 s, and teammates in co-op are left alone and keep their push and slam arming. `Combat.pull` called directly still pulls every actor (the owner's rule). At most `SpellLimits.MAX_PULLS_PER_STEP` (16) magnet shots pull per step, rotating, so a many-shot staff costs at most 16 grid queries a step. A bolt (220 px/s) drags an imp 40 px off its line into its path; 140 px/s was not enough.
- **The engine hook was missing**, so this card added `Spells._step_magnets` (a list of magnet slots, like arc's). Magnet is listed as wasted on a payload that fires from a point (`TRAVEL_ONLY`).
- **Combo arena imps can now be pushed**, opt in: `ComboArena.pushable`, and the combo key `pushed`. Off by default so other combos behave as before. The clip recorder ignores `pushed`, so the magnet clips show no pull.

## 2026-10-29: Mend card (staffs C)

- **Mend is an infusion** (`heals`, no status, damage x1, complexity 2, look layer 6 green motes, tint Player 3's light green). Combat already healed, so the card is data only; the builder hub now says "Heals wizards". Its combos use hurt wizard bodies in the arena (`guard`, `allies`, `hurt`) and the checks `healed` and `lost_at_most`. The tint is close to Player 3's green; the art pass may pick another.

## 2026-10-29: Blast card (staffs C)

- **Blast is a 40 px radius**, complexity 2, no mana change, look layer 9. The engine already ran it (`Spells._blast`, combat's area hit), so the card is data only. Its combos use a bolt (a hit, and a wall end), each with an imp that only the burst reaches. A blast on a dash cannot be a combo yet: the combo arena does not move its caster, so no move ever ends (`test_spells_moves` covers it).

## 2026-10-29: Shield card (staffs C)

- **Shield is one charge a card** (`behaviour_strength` 1.0, charges add), complexity 2, no mana change, look layer 10 (orbiting sparks, as the design says). Its combos check the blocking itself: a combo may name a `guard` (the caster's own body, so a barrier on it works), enemy `foes` (a real enemy bolt cast at the caster from a point) and the check `blocked` (enemy shots stopped). Each of the three combos is a control row (without the card its checks fail).
- **The caster barrier is wired in this card** (as Magnet's pull was): `Spells._shield_caster` sends `wizard_shield_requested(actor, charges, seconds, tag)` when the wizard's own dash, teleport, a hook that hit, or cards that landed on the caster (a fallback) carry `shield`. Charges are `behaviour(SHIELD)`; seconds are the carrier's lifetime or the move's time, whichever is longer, and combat keeps at least its 0.5 s minimum (so a dash's barrier is half a second). A fallback sends it after its area hit, which can reach the caster and would spend the charge. A payload's fallback (a point) and a shot that dashes get none.
- **Orbit and still shots were never shielded:** `_apply_travel` only ran for flying shots, so `shield · orbit` set no charge. `_apply_shield` now covers them too (found by the first real block in `shield_orbit_ring`).

## 2026-10-29: Heavy card (staffs C)

- **Heavy is knockback x4 and speed x0.6**, complexity 2, no mana change. The slam is combat's (`SLAM_SHARE`: as much as the hit's damage). The combos put the wall within 12 px of the imp (combat looks `SLAM_REACH` past its hurt circle), because arena imps are not moved by knockback.
- **Heavy shares look layer 8 with Pierce for now.** The look layers run 0 to 12 and all are taken; some already double up (Bigger and Growth share 7, Arc and Possess share 10). A layer of its own means a shader change, which is left to the art pass.

## 2026-10-28: Sticky card (staffs C)

- **Sticky holds 1 s** (`behaviour_strength` 1.0), complexity 2, no mana change. A stuck shot's payload starts inside the target, so a nova planted by `sticky · on expire` hits the target itself with every shot of its ring, not its neighbours: the combos check the target's damage and chill, not an imp beside it.

## 2026-10-26: Player, input and builder on staffs (staffs A6a)

- **Buttons:** A, X, Y, B cast staffs 0 to 3 (`cast_a` Space or Shift, `cast_x` left mouse, J, right trigger or RB, `cast_y` right mouse or K, `cast_b` Q or L). **Menus activate with A and go back with B**, the gamepad standard, now that the old activate (`cast`) and back (`dodge`) buttons are gone. **The overlay is on Start** (and Tab, E): the design said View/Back, but Back is `leave`; Start only joins a device that has not joined yet.
- **The full builder at any time, waves included** (owner: "The quick action is not needed. A full builder is always preferred"). The quick view, the overlay's Bag drop list and `drop_choices.gd` are gone; a player building in a wave stands still and can be hit, as in any menu.
- **The first staff builder is a list builder** (tabs, slots, bag, one line per control) so A6a could land on main green; B8 makes it quicker to use (pick and place, links, mouse, moving between tabs, slots and bag without walking every control).
- **The dash comes from its card** and goes the way the wizard walks (the way it faces when standing), as far and as long as the card's `speed` x `lifetime`, with no invulnerability. `protect()` (join and revive) is the only invulnerability left.
- **A held button never switches a `hold` off;** only a new press does, so holding a button does not flicker a sustained card.
- **Staff numbers retuned:** starter delay 0 and recharge 0.05 s, dev delay 0 and recharge 0, because a two-card staff such as `fire · bolt` recharges after every cast; with the first numbers (0.1 and 0.5 s) a bolt would have taken 0.95 s instead of 0.35 s. The dash card's cooldown (0.575 s) keeps the old dodge's rhythm.
- **The corner panel shows the staff cast last** ("Staff X"), from `staff_cast`; there is no swap.

## 2026-10-26: Staff runtime details (staffs A5)

- **Recipes run as staffs of one cast.** `install` and `cast` wrap a recipe's spell (its held spells as payloads, its depth as its node), so there is one runtime and every M2 cast and trigger test keeps checking it until A6c removes recipes.
- **Switching a `hold` off is a cast of the staff that spends nothing** (`cast_staff` returns 0.0). Which presses may do it is the player's call (A6a): a button held down must not switch on and off again and again.
- **A cast with nothing in it** (every card wasted) still moves the staff on and starts its delay, so a staff can never stick on it; it returns `REFUSED`.
- ~~**Carriers of one group fan out 12° apart** (`MULTICAST_SPREAD`).~~ Replaced on 2026-10-27 by the staff's `spread` (see "Spread belongs to the staff").
- **Fallbacks are area hits on the spot,** as wide as the larger of the spell's radius and its blast strength; combat makes them hurt in B3.

## 2026-10-26: Planning after the pivot verdict (#264)

- **Verdict adopted as given:** the owner's pivot at C2 (#264) is carried out by the merged staffs design (`M2-staffs.md`, DESIGN.md rows, parts A1–A4 in #266–#269). ROADMAP, NEXT and the entry below already say so; per the owner, the design and both lanes of `docs/NEXT.md` stay as they are and no task is rewritten or reordered. #264 is closed by this PR. The bot starts at the top of `## Queue` (A5); owner sessions take `## Owner lane`.
- **Milestone state:** M2 is in progress, not done; no new checkpoint until D3.
- **Idea #208 (pet):** stays on the backlog, not scheduled. The staffs plan now covers its shape as cards, `familiar` and `decoy` (owner lane, after B2 and B5), so a separate pet system is not needed; a kill-count unlock would be a later-milestone progression item (see the earlier #208 entry below, and BACKLOG, "Ideas from the community").
- **Queue moves:** none. No re-examination task: the only recently finished work is the owner's A2–A4, still unused by the game.

## 2026-10-26: Staffs design review

An independent fresh-context session reviewed `docs/milestones/M2-staffs.md` against `docs/DESIGN.md`, the code and the bot's task picker. Fourteen findings; thirteen changed the design, one was wrong.

- **Examples broke the reading rules** (modifiers and triggers come before their carrier, payloads after it). Every example is now in slot order, and the reading examples are A4's table tests.
- **Rule holes:** leftover cards in a payload now land on the payload's origin, not the caster; a group resumes after its payload; multicast counts per group; burst repeats the same compiled group; a wrap anywhere in the cast means a recharge; the cursor moves past payload cards. `rain` and `familiar` carry a payload of their own; every card has an end point.
- **Tag collision:** enemy attack tags reach 101,000, inside the planned spell range; `SpellTag.FLAG` moves to `1 << 20`. Fallback casts get node numbers too.
- **Self-harm needs projectile code** (a wizard is never hit by their own shot today): moved into B1, with the per-shot "left the caster" flag.
- **Missing events:** where a dash or teleport ends, decoy ends, familiar casts, enemy moves for swap, area hits, and a projectiles-sent `shot_blocked` beside combat's `shield_blocked`.
- **The card dependency table** was rebuilt from what each card touches (hold and siphon need B4; on wall needs B1; blast and mend need B1, B2 and B3; wall's line is B2's).
- **Parallel conflicts:** B6 waits for B1 (both in the projectile manager), B4 waits for B3 (both reach the wizard); cards are data only, and kits may add their own fields.
- **No build limits vs the runtime:** the per-step work caps and the pool stay as engine safeguards that never shape a build; the pool already drops the oldest shot of whoever owns the most, so one player's huge cast eats its own shots first. The build limits go.
- **Co-op rules:** slow motion and friendly fire, which change the game for everyone, are in the pause menu, not a player's overlay.
- **Pillar 4 and game feel:** the clip sheet checks that four players' shots can be told apart; every card has a sound id and every hit kind default feel.
- **Hold vs the generation ring:** editing a staff switches its held carriers off, so no stale reservation or orphaned sustained shot survives a rebuild.
- **Phase A sizing:** A6 is split into A6a (player and builder), A6b (combos and tests) and A6c (the old path removed), each keeping main green; A5 moves the recipe runtime onto the new tags.
- **Shot look data:** the batch's custom data has little room left, so at most four layers per shot are drawn.
- **Not changed:** the review said the lore files live in `content/story/lore/`; they are in `content/story/lore/components/`, as written.

## 2026-10-26: Pivot at C2: spells are built in staffs

**Decided by:** the owner, in an owner session over six rounds of planning (answer to #264: pivot). The design is `docs/milestones/M2-staffs.md`; the owner's DESIGN.md rows changed with it.

- **Why:** the builder was hard to use, the form → element → modifiers → trigger template locked builds out, and the only way to deepen builds was more components. The owner wants players to find interactions nobody designed.
- **Staffs, cards read in order** (Magicraft and Noita as references): four staffs per wizard, one per button (A, X, Y, B), so there is no built-in dodge or attack; the A staff starts with `dash`. Cards attach to the next carrier, or to the caster when none follows (owner: "if build without a projectile, it will explode on the caster"). Wrap-around is on; each card is read once per cast, which is what keeps every staff's cycle finite.
- **No build limits** (owner: "Lets disable the hard limits for now. They can be added later if we want to / need to"). The projectile pool stays: it is the pre-allocated buffer every shot lives in, not a build rule, and it drops the oldest shot when full. The stress benchmark and the emergent combo report say when a limit is needed.
- **The dash has no invulnerable window;** protection is built (`shield · dash`), and shield charges stack (owner).
- **Self-harm always on;** hit kinds exist so relics (M3) can grant immunities, for example to explosions (owner).
- **One mana pool per wizard;** sustained cards reserve mana (owner).
- **The input buffer applies to every staff button,** not to the dash alone (owner).
- **Smaller shots with layered looks** (owner: "they are way too big"; "apply eg. electricity to one, which makes it emit sparks").
- **`dev` and `preview` builds are a sandbox** with 20-slot staffs (one field, easy to change), the full bag and a training dummy; building is possible at any time there (owner).
- **The sandbox's controls live in the Start-button overlay,** as a "Sandbox" entry beside "Build", not in a pause menu (owner, 2026-10-26, part B7). Replaced the same evening: Start now opens the pause menu, which holds the sandbox page (see "Controls: staffs on the shoulders").
- **The sandbox room is two shooting lanes split by a wall:** the training dummy at the end of one, the shooting dummy at the end of the other (owner, 2026-10-26). The wall stops short of the bottom, so wizards cross between the lanes.
- **`dev` and `preview` builds start in the sandbox through a focused "Sandbox" button above Play** (one press), not by skipping the menu, so the menu's test runners and Play still work as before (part B7 session's choice).
- **The builder may scroll** where that makes it easier to use; it is not a requirement (owner).
- **All 39 new cards are in scope**, including the second batch of ideas (owner: "All of them"), and the card batches do not wait for an owner playtest between them (owner: "no need to wait for my input").
- **Two lanes in `docs/NEXT.md`:** the owner runs external sessions in parallel with the bot. The bot reads only `## Queue` (`ci/smbot/nexttask.py`), so an `## Owner lane` section needs no change in `ci/`. Shared lists (combos, the asset manifests) are split per file first, and kits come before cards, so card PRs touch only their own files.

## 2026-10-26: Spell visuals round 2, part 1: bolt size, trails, combo marks (#244, p2)

- **Why:** the owner found the shaped bodies too big (the earlier coloured bolts were better, with particles for the element or type) and asked for many more, clearer animations for combined spells.
- **Size and particles:** `SHAPE_SCALE` is 0.8 (was 0.62, the old plain bolt is 1.0), and a shaped bolt leaves three trail marks instead of two (`TRAIL_MARKS` 3, `TRAIL_MAX` 384 marks in one draw batch). The marks are the element's particles (embers, glints, sparks, motes, arc flecks); they are still a draw batch, so `Feel.PARTICLE_LIMIT` is untouched. If 0.8 is still too big the number is one line.
- **Combo classes:** `Spells.combo_class` sorts a compiled spell into `boosted` (modifiers only), `on_hit`, `on_expire`, `timer` (a trigger holds a spell) or `stacked` (a trigger with two or more modifiers, or a chain of three spells); a plain shot has none. `Spells.cast` sends the new event `combo_cast(player, class, origin, direction, tint)` after a cast made a shot. It is new, not a fifth argument on `spell_cast`, because that would break every listener, and `core/spells` is the one place that has the compiled spell (Feel has only the form id).
- **Look:** Feel puts a flat mark at the spot of the cast (the staff tip in whole pixels; it stays there, it does not follow the wizard) for 0.36 s (`combo_mark_seconds`): a ring of ticks (boosted), two chevrons toward the nearest of four directions to the aim (on_hit), a diamond with a dot (on_expire), a dashed ring with a clock hand that ticks in quarter turns (timer), a ring over a diamond with ticks (stacked). Pictures are made in code (`gameplay/feel/combo_marks.gd`, white pixels, tinted to the element colour at runtime), so no asset files and no manifest lines. The mark is drawn at its own size, then at 2x (whole multiples, quarter turns only, no fade), one sprite per player (a new cast takes over), so four players show at most four. The first version turned the rings by 22.5 degrees and the pixels came out ragged, which is why only quarter turns are used.
- **Not done, left for the next parts (listed in `docs/NEXT.md`):** a distinct burst per multi-component combo row (reactions in combos, held-spell payoffs), per-element sparks around hits, and the combo sheet in the Spell atlas. The marks tell the class of a cast; they do not yet tell two combos of the same class apart except by element colour and form.

## 2026-10-26: Should the render resolution be raised? An assessment for the owner (#244, p2)

The owner asked. The art direction is locked, so nothing changes here; this is the information for the next C2 checkpoint, where it is named as a question.

- **Now:** the game renders at 640x360 (`project.godot`: viewport stretch, integer scale, window 1280x720 by default), so one art pixel is one render pixel, 2x2 screen pixels in the default window. Every sprite is a 32x32 grid, and `docs/STYLE.md` rule 1 says one art pixel is one screen pixel.
- **What a higher render size would change.** (a) The same art at the same scale on 960x540 or 1280x720 shows *more room* around the players: the camera, room sizes, shot reach and four-player framing all change, so it is a design change, not a sharpness change. (b) To show the same view sharper, the art has to be drawn at 2x (64x64 sprites): the locked pixel look and all 32x32 art would be redrawn, or scaled by a whole 2x, which looks exactly as now. (c) Effects (the shot shader, rings, particles) could be drawn at 1280x720 while sprites stay at 640x360: sharper edges, but two pixel densities on screen, which the style rejects ("no scaling other than whole multiples", pixel art with mixed grids reads as a mistake).
- **Cost on web.** The Compatibility renderer on WebGL2 is fill-rate bound on integrated GPUs and phones. Pixels drawn per frame: 640x360 is 230,400; 960x540 is 518,400 (2.25x); 1280x720 is 921,600 (4x). The shot batches, rings, beams and statuses overdraw, so cost grows about with the pixel count. The CPU side (simulation, MultiMesh uploads) does not change. Nothing here is measured: the CI browser has no GPU, and the real-GPU frame rate is still open (C2 done-when item 3). The 4x figure is arithmetic, not a benchmark.
- **What it would not fix.** The visuals read badly today because of size, silhouette and colour choices (this task's part 1), not because the grid is coarse. A higher resolution would not make combos easier to tell apart.
- **Recommendation:** keep 640x360. If the owner wants sharper output, the cheapest honest step is a measured 2x test build (one frame-rate number on a real GPU, which only the owner can take), before any art is redrawn.
- **Question for the owner (asked at the next C2 checkpoint, not now):** "Keep the 640x360 render, or run a 2x resolution test build to measure the web cost first?" Meanwhile nothing changes.

## 2026-10-26: The drop lists scroll, they do not page

- **A scrolling window, not pages.** The quick view's drop list shows 11 rows at most and the overlay's 6 lines of two (`hud/widgets/row_window.gd`); a longer list sits in a clipping `Control` and slides to keep the focused row in view. Paging would need extra "next page" controls or a change of what UIFocus walks; with a window every row stays a visible control, so UIFocus (`core/ui_focus`) is unchanged and wraps around the whole list as before.
- **The step is the row's real height.** A quick row is 14 px tall in the theme (not the 12 of `QUICK_ROW_HEIGHT`, which is only its minimum), so the window uses the row's own minimum height; otherwise the list would slide by the wrong amount.
- **The title shows where you are** ("P1 Drop 12/16") only when the list is longer than the window. The full builder's bag list is unchanged (it is as high as its rows).
- **The test uses a longer bag than any content has** (the real ids repeated, via `bag_changed`), so the 12th element or modifier can be added without a new test.

## 2026-10-26: Lightning's reactions and the discharge arc (#243, part 2)

- **Overload and Superconduct, only with fire and frost.** The task asked for at least two existing elements; storm and void are left out so lightning is not a copy of storm (an electric element that reacts with everything) and each new reaction needs a colour 0.45 apart from all the others, which gets hard with more. Lightning on storm or void just charges, as before.
- **A pair's two rows may differ.** Frost on a charged enemy is CONSUME, not EXTEND: after a discharge the struck enemy has lost its charge, and EXTEND would have charged it again. Lightning on a chilled enemy is a short freeze (1.5 s, less than Stillness's 2 s).
- **Fire on a charged enemy does both.** The hit discharges (if others are charged near) and Overload bursts: one hit, two effects, on purpose. The discharge is plain damage that starts nothing, so it does not loop.
- **A new event for the arc.** `discharge_arc(player, from, to)`, sender combat, listener feel; the arc is a `Line2D` pool in Feel (16 arcs of 6 points, corners and width on whole pixels, and an arc past 16 in one frame takes over the oldest, written with `set_point_position`, no allocation per arc), not a particle, so `PARTICLE_LIMIT` is untouched. Corners stray with Feel's own seeded `_rng`, so combat stays deterministic.
- **Colours.** `discharge` cyan `#00f0ff` (electric and far from the others), `overload` hot pink `#ff6ba0` (the first pick, brown `#7a3f18`, was too dark on the dark floor; orange was too near Flare's gold and Kindle's red), `superconduct` teal `#14a38b`. The colour test now also wants every reaction colour to have a bright channel (at least 0.6) and a colour for every row in `reactions.tres`.
- **The discharge's sound** is the id `reaction_discharge`. Sessions can't make `.ogg` files, so it is silent until one is made (BACKLOG, Audio needs), as for every reaction.

## 2026-10-26: Lightning and the static status (#243, part 1)

- **Why:** the owner asked for a fifth element that tests how extensible the spell system is, with a status of its own (a charged enemy discharges to the others, not a second jump).
- **Status rules:** lightning puts `static` (5 s, strength 60 = percent of the hit that discharges). A player's spell hit on a static enemy deals 60% (at least 1) to every other static enemy within 96 px, as plain hits for the same player. The discharge sets off no reaction, no status and no discharge; a guard also refuses one started from a listener inside it. The struck enemy is spent only if it discharged to someone (a lone charged enemy keeps its charge), and a discharging lightning hit does not charge it again; the zapped ones stay charged, so a charged pack keeps passing damage as long as the players keep hitting. A hit with no player index, or a shot that is not a spell, never discharges.
- **Announced as a reaction:** the discharge sends `reaction_triggered` with id `discharge` at each zapped enemy instead of a new event, so Feel shows a burst with no new signal in `core/events`. It is white and silent for now: lime was too near Thaw and Flare in the colour-distance test; part 2 picks a colour and a sound.
- **Colour:** a new palette material, Arc (`#3f6b10` `#b4e82a` `#eeffa6`), an acid lime apart from Spark's gold, the players' greens and Ice's cyan; the palette is 40 colours (the bot may add colours, see the Ice and Void decision). Silhouette: a forked arc (shape 5) that is redrawn every frame; Storm's zigzag has no fork.
- **Charged enemies stay charged, on purpose.** Only the struck enemy is spent; the ones it zapped keep `static`, so in a tight cluster every player hit on any charged enemy zaps all the others (60% each, as plain hits that start no further discharge). The damage per hit grows with the number of charged enemies within 96 px, and so does the work, but both are bounded: one step, no chain, and the struck enemy loses its charge. Punishing a cluster is the element's point (it rewards grouping enemies); if playtests find it too strong, the first knob is a cap on zaps per discharge.
- **Shader kinds moved:** trail marks were "shape + 4", which collided with the rune at 9 for a fifth shape; marks are now 6–10 (`TRAIL_KIND_OFFSET`), rune 11, orbit 12. The encoding has room up to 15, so two more shapes fit before it must be widened.
- **HUD:** the quick drop list and the overlay's list show every element and modifier at once, now 11, which no longer fit a player's quarter at 14 px rows. They are 12 px rows with 8 px text. This is the limit for the next element too (12 rows overflow again): see the BACKLOG item.

## 2026-10-25: Form bodies are shader kinds, and shaped bodies are smaller (#244, part 2b)

- **Why:** a rune and an orbit shot looked the same in flight as a bolt of the same element, and the owner said the new spell visuals are way too big and liked bolts in different colours.
- **Now:** the manager writes kind 9 (rune: pulsing diamond) or 10 (orbit: two spinning, breathing beads) for every player's rune and orbit shot, whatever the element; the element stays as the core colour, so colours still tell the element and the silhouette tells the form. A bolt keeps its element shape. Every shaped body (and its trail) is drawn at `SHAPE_SCALE` 0.62 of the old size; hit circles are unchanged, so a drawn body is smaller than its hit circle by design (the circle is the fair reach; if playtests say a rune hits what it does not seem to touch, raise `SHAPE_SCALE`). The existing trail marks stay as the "what type is it" particles.
- **Not done:** the owner's "way more animations for advanced combinations of spells" is a larger piece (BACKLOG); a further size cut is a one-number change if 0.62 is still too big.

## 2026-10-25: Form looks are Feel presets, keyed by form id (#244, part 2)

- **Why:** each form needed its own cast flash, body and payoff, and a new form should be new data, not an edit to `feel.gd`. `spell_cast` already carries the form id (the player sends it), so no event changed.
- **Now:** `FeelPreset.cast_looks` (the flash on the wizard) and `impact_looks` (where a shot ends or hits) are dictionaries by form id with keys `seconds`, `size`, `stretch`, `tall`, `aim`, `grow` and `ring`. A bolt streaks along the aim; a beam is a long thin flare and opens extra wide (`beam_flare`) then thins and flickers; a nova bursts as a ring; a rune and an orbit gather in (negative `grow`, the build-up) and pop at the end (payoff). A form not listed gets the old muzzle flash and wall spark.
- **Impacts take the form from the shot itself.** The event signature stays (a fifth argument would break every listener and test), so the manager has `impact_form` (`bolt`, `rune`, `orbit`, `beam`, `""` for an enemy's shot), set only while it sends `projectile_impact`, from the shot's draw batch or from `ray`. Feel reads it. A bolt fired after a rune, or a rune that pops seconds later, gets its own flare; nothing is remembered per player, so nothing goes stale between runs. `nova` has an impact look in the preset but the manager never sends one (a nova is an area, not a shot).
- **Beam flicker is data:** `beam_flare_share`, `beam_flicker_rate` (steps a second, in real time) and `beam_flicker_depth` (10%, every other step) are preset knobs. The first version stepped by the beam's life fraction, about 80 Hz, which could alias into a strobe.
- **Enemy shots:** they show one ember mark turned on its corner (`enemy_impact_*`), whatever any player cast, beside their own sprite and batch (part 1). No player flare is turned on its corner.
- **Not done:** the in-flight bodies of the bolt, rune and orbit keep their art and the element shapes of part 1; no new art files. A rune pulse and an orbit spin are their own Queue task (`shot_core.gdshader`, `sim_time`).

## 2026-10-25: Element shapes are drawn by the shot shader, trails are a draw batch (#244, part 1)

- **Why:** four elements had to read without colour with four players firing. New art per element would have needed a texture per batch and four more sprites; a shape in the shader costs no files, no per-shot memory beyond one byte and one draw call for the trails.
- **Now:** `ElementBase.shape` (0 plain, 1 flame, 2 star, 3 zigzag, 4 ring) goes through `CompiledSpell.shape` to `Projectiles.set_shape`. It travels in the alpha of the MultiMesh custom data (`1 - kind / 16`, room for kinds 0-15; kinds 5-8 are the trail marks, 9-10 the form bodies). A new element with `shape = 0` keeps the plain sprite; a fifth shape means a new function in the shader and a constant, which the Lightning task (#243) will show.
- **Trails are not particles:** `Feel.PARTICLE_LIMIT` is for hit bursts; the trail marks are at most `TRAIL_MAX` (256) quads of one batch, only behind straight player bolts. Runes keep their glyph, enemy shots keep the enemy sprite (they stay unmistakable), orbit shots take the body shape without a trail.
- **Frame rates** (fire 12, storm 20, frost 4, void 6 a second) count `Projectiles.sim_time` (seconds stepped, handed to the shader as the `sim_time` uniform in `update_draw`) with a per-shot phase, so a volley does not blink together. Not the engine's `TIME`: these shots are what the clips show, and the recorder steps by hand, so the same steps must give the same frames. The flame has its own 16-pixel grid so its tail reads at 1x.

## 2026-10-25: How the clip recorder works and what is deterministic (#245, part 1)

- **A fresh stage per clip, stepped by hand.** The recorder builds its own event bus, projectile manager, spell runtime, combat and Feel for each clip (not the autoloads, which keep cooldowns, statuses and Feel's random numbers from one clip to the next), puts the drawing nodes in the tree, and turns their own processing off. It moves 1/60 s at a time in the order of project.godot and draws a frame every third step (20 frames a second), so the frames do not depend on the machine's speed.
- **Clip ids carry the kind:** `combo_<id>`, `form_<id>`, `element_<id>`, `modifier_<id>`, `trigger_<id>`, `reaction_<id>`, `reaction_<id>_coop`, because the combo "shatter" and the reaction "shatter" share a name.
- **Frames:** 320×180 game pixels at 1x around the middle of the casters and imps, RGB, at most 240 frames and 3.5 MB per clip. Full-size 640×360 frames would pass the 4 MB limit in a few seconds; the pixel art stays exact at 1x and the page scales it.
- **A reaction's elements are read from its two rows:** a pair of elements reacts both ways, so the table has two rows per `reaction_id`; the first row's `element_id` is the bolt that sets it off, the second row's is the bolt that puts the status on first. A reaction with one row has no clip. (Reading an element's `status_id` instead would break the rule that only `core/spells` and `content/spells` read component fields: `test_spell_field_reads.gd`. Component names and kinds come from `Spells.component_name` and `component_kind`.)
- **Determinism, and what is left out for it.** The pipeline tells a changed clip from an unchanged one by its frames (`atlas/hashes.json`), so two takes of a clip must match pixel for pixel. The simulation is checked headless (`test_clip_scenarios.gd`: two runs agree at every frame); the pixels need a display, so a unit test can't compare them. I recorded all 51 clips twice under `xvfb-run` (Mesa llvmpipe, OpenGL) through `ci/build/build.sh --quick --clips` and compared the folders with `diff -rq`. Two things were not deterministic and are handled in `stage.gd`: (1) the projectile manager draws a shot between its last two steps by the engine's real time since the last physics tick, so the stage draws every shot where its last step put it; (2) Feel's hit sprays are `CPUParticles2D`, which simulate by the real time of each frame (a fixed seed was not enough: about 400 of the 2,000 frames still differed), so the clips are recorded without them (`HIT_SPRAYS = false`; the hit flash, squash, reaction names, beams, rings and shot art are in). With that, all 51 clips were identical in two takes. The way back is in `docs/BACKLOG.md`. Hit-stop is not played either (Feel does not touch `Engine.time_scale` there).

## 2026-10-25: The clip pipeline: animated PNG, recorded apart from the build (owner session, #246)

- **Format: animated PNG (APNG), not GIF or WebP.** It is built from the recorder's own PNG frames without decoding them (`ci/smbot/clips.py`), so it needs no image library or tool in CI, keeps style N's palette exactly (a GIF would need a 256-colour quantiser; WebP needs a converter), and is still a `.png`. Chrome, Firefox, Safari and GitHub play it inline; viewers that don't (some apps) show the first frame. Identical frames in a row are merged into one longer frame, so a still moment costs nothing.
- **Recorded in its own job,** `record-clips` in daily.yml, after the build and on the build's commit, with no secrets and a read-only token. A recorder that fails or runs long never holds back the release; the job that has a token (`publish-clips`) only reads the frames as data and refuses any that break the format.
- **The atlas lives on the `screenshots` branch** (`atlas/`, replaced each day) and Pages copies it from there on every deploy, so a preview deploy between daily runs keeps it. `atlas/hashes.json` says what each clip looked like, so the Daily log shows only the clips that are new or changed, at most 8, with a link to the atlas for the rest.
- **On a PR,** a session names at most 4 clips in `clips` (like `screenshots`); they're recorded on the PR and on main and shown in the same comment, so the Daily log's repeat of that comment carries them too.

## 2026-10-23: Glyphs for buttons, resolved in `core/input` and drawn in code (owner `/claude` on #4)

- **Owner's instruction:** wherever the game shows how to interact, show a glyph of the button, not words; a controller strategy that swaps type by itself when a player changes from, say, an Xbox pad to the keyboard, with glyphs updating live.
- **Strategy:** `InputGlyphs` (`core/input/input_glyphs.gd`) is the lookup (kind and action to shape, label, colour); `PlayerInput.glyph_kind(player)` holds the per-player kind and fires `glyph_kind_changed`. Pad family comes from `Input.get_joy_name` when the device joins (name fragments for Xbox, PlayStation, Switch; anything else is a plain pad with Xbox letters). The kind is per player, so four players can hold four different pads. The keyboard player is `KEYBOARD` or `KEYBOARD_MOUSE` (cast is a click while the mouse aims). The signal lives on `PlayerInput`, not on the Events bus: only the widgets use it.
- **"Swap when it detects a switch":** in this game a player's device only changes by leave and join (the keyboard joins only as P1, a pad takes the lowest free slot), so the live swap happens there, and for keys against mouse. A device taking over a live player's slot is a new rule and is in BACKLOG for a decision.
- **Drawn in code**, like the hammer icon, so no art files or manifest lines; 10 px high, 8 px text. Real glyph sprites are in BACKLOG.
- **Scope:** only the builder's hint line shows a prompt today (the Cast/Dodge words were the only ones; the "(F)" in a refusal text is a form letter and stays). The overlay and Bag list have no hint yet.

## 2026-10-23: The web stress run after the cap of 500 is read; the limits stay (planning)

- **Read:** the Daily run post of 13:29 UTC in #202 (release v0.20261023.3, after the web cap went from 1,000 to 500). Web, render loop off (game logic only), 100 enemies and 500 shots: physics steps per frame avg 1.0 (max 1), physics step avg 7.58 ms (max 11.10), process 2.43 ms. That meets the rule (a step of 12 ms or less, steps per frame near 1); the catch-up of about 8 steps per frame is gone. Enemy step 0.57 ms, combat lookups 0.24 ms, Feel 0.05 ms per pass.
- **Still over:** the web run with the render loop on has p95 56.5 ms, the particles-off run 51.8 ms (2.5 steps per frame), and the desktop-size scenario in the web export 119 ms. They run in the CI browser, which has no GPU (software rendering), so the time is most likely in the renderer and on a shared runner, not in game code. That is unconfirmed: the particles-off run is not faster than the one with particles (51.8 ms against 56.5 ms, still 2.5 steps per frame), and the 119 ms desktop-size run is not explained. The BACKLOG item "Real-GPU web frame rate" settles it. The warning is not a failure (docs/PLAN.md, "Gates are sparse").
- **Decision:** `DEFAULT_CAP_WEB`, `MAX_SHOTS` and `MAX_FIRES_PER_STEP` stay. The game logic is inside the web budget. Frame rate on real hardware in Chrome and Firefox is for the owner and web players (BACKLOG, "Real-GPU web frame rate"). M2's done-when item 3 ("met when the warning is gone") is not changed and is still open: only its game-logic part is shown. The remaining warning is named in the C2 checkpoint and left to the owner's verdict.

## 2026-10-23: HUD and Builder walkthrough: what is hard, and the three fixes (owner `/claude` on #4, point 2)

- **Walked through** with real input: one player on keyboard, four players on gamepads (player 3 in detail), in the break (full builder) and in a wave (overlay, quick view, Bag), at 1x and 4x screenshots.
- **What is hard** (worst first):
  1. **Slot names are code letters.** "F: Bolt", "E: Fire", "M1: -", "T: -": a new player does not know F, E, M or T. Same in the refusal text ("Pick a form (F) first", from `player`).
  2. **Nothing says what a button does.** The builder never says that `cast` picks and `dodge` goes back, nor what the focused control will do (a slot opens a list, a row applies, a tab switches spell).
  3. **The focus is faint.** The focused control differs from the others only by a "> " and a slightly lighter fill; with four builders open it is easy to lose.
  4. The description line cuts off at three lines ("Reliable, which the...").
  5. A greyed slot ("Mod 2", "Held >") gives no reason (already in the backlog).
  6. The bag rows mark the current component with " *", which says nothing by itself.
  7. The hint names the actions ("Cast", "Dodge"), not the physical buttons, which differ for keyboard and gamepad.
  8. In a wave, the quick view does not say that the full builder comes back after the wave (the title just changes).
  9. The corner panel never says which button opens the overlay.
- **Fixed (three, in `hud/`):** (1) words for slots: "Form", "Elem", "Mod 1-3", "Trig" ("Element" and "Trigger" do not fit next to the longest component name in the 100 px column, checked by the existing width test); (2) a hint line (8 px, theme variation `BuilderHint`) under the info panel's note that changes with the focus; the panel is full, so the complexity words now sit on the bar (one row, 12 px) and the preview is 14 px high, which pays for it ("Pick a part (Cast)" on a slot, "Use (Cast), back (Dodge)" on a bag row, and so on). The hint also shows in the quick view, where the info panel is hidden: a second label (`QuickHint`) under the chain, with the left column's spacing 0 so the longest quick view still fits its quarter (a test checks it). The words name the action in brackets because the physical button is not known yet, so this part is only partly solved (item 7 stays in the backlog); (3) a visible focus: the focused control takes the theme variation `BuilderButtonFocus` (brighter fill, 2 px light border, white text, 4 px side margins) besides the "> " mark. Its top and bottom margins stay 1 px: 2 px makes a focused quick row (14 px) taller than the others and the longest quick view no longer fits; in the screenshots the text does not touch the border.
- **Still faint:** the overlay menu and the quick-view Bag list (`widgets/drop_choices.gd`) keep the old focus look and have no hint (BACKLOG).
- **Looked at** (1x screenshots `builder_one_player`, `builder_four_players`, `quick_view_four_players`, `quick_view_drop_list`): the 8 px hint reads at 1x though small; "Complexity 2/12" on the 12 px bar stays readable (the outline helps over the fill); the focus border is clear of the text.
- **The common case** (a component into a slot) was already short: the builder opens on the form slot, and a form or element into an empty slot moves on to the next bag. With a gamepad as player 3 of 4 it is: Y, down, X (open), down ×2 (to Mod 1), X, down to the row, X. A test (`test_player_three_of_four_puts_a_component_in_a_slot_with_a_gamepad`) runs that with real joypad button events on gamepad 2 of 4 and checks that only player 3's builder and recipe change.
- **To the backlog:** items 4 to 9 (item 5 was there already), and the "(F)" in the refusal text, which is in `gameplay/player/` and so outside this task.

## 2026-10-23: The wave line shows only while a wave is on (owner `/claude` on #4)

- **Why:** the line was hidden only by `run_started` and `run_ended`; no code sends them yet, and a cleared wave sent only `room_cleared`, so "Wave N" stayed mid-screen for good.
- **Decision:** keep the small 12 px line in the middle strip (the gap that stays clear of four open builders), but show it only from `wave_started` to `room_cleared`; the build line takes its place during the break. No fading banner: the number is useful all through a wave.
- **A wave that is never cleared:** the line stays up while it runs, which is right. `Flow.stop_run` sends no event, so a run stopped mid-wave would leave the line; `room_entered` (sent right before `wave_started` at every run start) now hides it too. Until the next run starts, a stopped run still shows the old line.

## 2026-10-23: The beam is a held tick, 4 hits a second on one enemy (owner `/claude` on #4)

- **Why:** the owner wants a continuous beam that fires while fire is held, uses mana continuously, and hits the same enemy only x times a second.
- **x = 4.** While `cast` is held the player already casts whenever the cooldown allows, so the beam's cooldown is its tick: 0.25 s. Two a second reads as a pulse; eight or more makes hit flashes and particles strobe and buys nothing. The drawn beam lasts 0.25 s, one tick, so each tick joins the next without two beams overlapping (`faster` shortens the tick below that, and then they overlap a little). A ray ignores `lifetime`, so it stays 0.15.
- **Numbers:** 3 damage a tick (12 a second per enemy, a little under the bolt's 14; pierce 1 hits two in line), 4 mana a tick = 16 mana a second against 10 regenerated, so a full pool lasts about 17 s of holding. `faster` still shortens the tick, so it raises the hit rate.
- **No new mechanism:** a per-enemy hit limiter would duplicate the cooldown; one enemy is hit once per cast.

## 2026-10-23: Style N chosen; the wizard has a shared body and a separate hat, and idles with a blink

- **Why:** the owner answered round five (#206, key `art-direction-pick-3`) with "lets go with N" and asked for character animations, such as an eye blink in idle and something that makes it feel alive. The earlier open question, a second sprite per wizard or a baked sheet per player, is decided here.
- **A hat sprite, not four baked sheets.** The hat is the only player colour (DESIGN.md), so the body strips (`wizard_idle.svg`, `wizard_walk.svg`, `wizard_dash.svg`) are one set for all players and the hat is a `Hat` node under `Sprite` with `hat_textures` per player index, listed in the scene by literal `preload` paths (no computed path, nothing for `core/registry` to do). One body to draw and fix instead of four, and a new hat is one 32×32 file. `textures`, `walk_textures` and `dash_textures` stay lists of four, so the scene can still give a player another body.
- **The art is poses; the code is time.** The idle strip has four poses (eyes open, closed, glance left, glance right) and `IDLE_SEQUENCE` (48 steps at 6 fps, 8 s) orders them: a blink, a glance left, a double blink, a glance right. Breathing is a 1 px bob of body and hat in the code (`BREATH_STEPS`), as are the walk's dip (`WALK_BOB`) and the dash's crouch and lift (`DASH_BOB`; the shadow stays on the ground), so no frame has to be redrawn to change a rhythm. STYLE.md's idle row says so.
- **Cost:** the body shifts as a whole, so the feet leave the ground by 1 px while breathing; the hat moves with the body, never alone. The dash lost its banded lean frames (the code already stretches and leans the sprite) and has 2 frames.
- **Golden example:** `art/kit/golden_wizard.svg` is the body with player 1's hat as one picture, since the Style Guide page shows one image per example.

## 2026-10-23: A fifth art direction round (M, N, O), the pick asked again

- **Why:** the owner answered round four (#206, key `art-direction-pick-3`) with "4: keep the hat style, but maybe add a robe as the clothes and the face just needs two big eyes, no mouth. Give me some examples". Option 4 is "another round", not a pick, so the record task cannot be done yet.
- **Done:** F's hat stays; three new bodies under the four hats, all with a face of two big tall eyes (2x3 px, with a highlight) and no mouth, no cheeks, and a clearer robe than J to L: a front placket, a belt with a buckle, long sleeves and a hem band. M cream, N dusk (Stone violet-grey), O teal (Ice). Standard palette only. Sheet `art_direction_sheet_5.png`; comparison in `art/samples/README.md`.
- **Same key:** the pick is asked again as `art-direction-pick-3`, and the task stays under "Blocked".
- **Hand-written SVGs again:** written as rects by hand from J's body; `test_svg_art` checks them.

## 2026-10-23: A fourth art direction round (J, K, L), the pick asked again

- **Why:** the owner answered #206 (key `art-direction-pick-3`) with "the body is too wide, I like the hat, the wizard needs to be more cute, give me some more examples". That is not a pick, so the record task cannot be done and nothing in `golden.json` or `STYLE.md` changes.
- **Done:** F's hat stays; three new bodies, each under the four hats: J (tiny cream), K (bean brown), L (gold, bigger head). All are 8 to 10 px wide with a big round face, two big eyes with a highlight, Fire-light cheeks and a small smile, and no beard. Standard palette only. Sheet `art_direction_sheet_4.png`; comparison in `art/samples/README.md`.
- **Same key:** the pick is asked again as `art-direction-pick-3` (one decision keeps one issue), and the task stays under "Blocked".
- **Hand-written SVGs:** the session could not run a generator script, so the three files were written as rects by hand; the sheet was looked at, and `test_svg_art` checks palette, overlaps, bounds and that no body carries a player colour.

## 2026-10-25: C2 answered with iterate; M2 reworked

- **Verdict:** the owner answered #235 with iterate: the clip recorder and Spell atlas (#245), spell visuals (#244), Lightning (#243), in that order. M2 is in progress again; its next end is a new C2 checkpoint. Nothing from M3 is written.
- **Order and split:** recorder first, because the owner judges the visuals with its clips. Visuals are split into elements, forms, and reactions with statuses (the split #244 suggests), then a polish pass with the clips; Lightning is last and is built to the visual bar. Each is one session.
- **`ci/` is owner-only:** the Godot recorder (`tests/clips/`) and the atlas data (`tools/`) are built here; GIF encoding and publishing, the Pages page, Daily log and PR clips are `ci/` work, asked as owner question `clip-pipeline-ci` and Blocked in NEXT.
- **Idea #208 (pet):** unchanged, stays on the backlog; M3 and M5 are not started. The preferred shape is still a spell form or modifier ("familiar"), not a pet system.
- **Queue moves:** none; #243 to #245 are the owner's own issues and are covered by NEXT tasks.

## 2026-10-23: planning with an empty queue; the pet idea (#208)

- **Why:** the work queue ran empty: the only doable Queue task, "Read the web stress parts", needs a daily run newer than #202, and none exists yet. A session would only answer `nothing_to_do`, so planning ran.
- **Now:** that task waits in Blocked for the next daily run. A new first task, "Collect the C2 evidence", needs no web numbers and the checkpoint needs it anyway. M2 is not done (stabilisation and the web numbers are open), so no checkpoint yet.
- **Idea #208 (summonable pet):** kept on the backlog, not scheduled (not for M2). A pet as its own system conflicts with "the game is about building spells" and multiplies bodies by four players. What fits DESIGN is a spell form or modifier (a "familiar" shot with its own health that enemies prefer) or a relic or reward in M3; a kill-count unlock is an M5 progression item that unlocks a component. Written in BACKLOG, "Ideas from the community".
- **Re-examined feature:** the quick view and reactions walkthroughs already had polish passes this week and the web stress frame is the live item, so no new polish task.

## 2026-10-23: Reaction flashes are flat colour, and the six colours are far apart

- **Weak (six reactions made by real hits, looked at at 1x).** The flash was the gold spark art with the reaction's colour multiplied in, so it came out wrong (Stillness olive, Rift brown) and not the colour of the name above it. The palette was also close: Shatter, Thaw and Stillness were three pale blue-greys, Kindle and Flare two oranges.
- **Now.** Reaction flashes use `reaction_flash.gdshader` (the art's shape in the plain tint). `reaction_colors` are ice white (Shatter), green (Thaw), yellow (Flare), red (Kindle), blue (Stillness) and violet (Rift); a test keeps every pair at least 0.45 apart in RGB. One fix pass was enough; the 1x crops were looked at again afterwards.
- **Left (BACKLOG).** All six flashes share one shape, so apart from the name only colour tells them apart; red and blue names are dim on the dark floor; feel keeps four reaction flashes at once.

## 2026-10-22: Multimesh batches are sized by use, not cut mid-buffer

- **Why.** `MultiMesh.buffer` must hold exactly instance_count x 16 floats, so a partial upload is not possible; the only way to send less is a smaller MultiMesh.
- **Now.** Each batch's room is the shots it draws rounded up to a power of two (at least 64, at most the cap); it grows at once and shrinks only when use is under a quarter of it, so the MultiMesh is rebuilt rarely. No shot is dropped by it; the cap is unchanged. An empty batch keeps its room (it uploads nothing), so a batch that empties between volleys never reallocates. Sizing costs one extra read-only pass over the live shots per frame; keeping per-batch counts at every spawn and free was judged riskier than that pass.

## 2026-10-22: One decision keeps one issue until it's made

- **Why.** When the owner answered a question with "more options", the next round became a new issue (#190, then #192, then the next), and the PR closed the old one. The owner had to follow a decision across issues, and their answers were split between them.
- **What.** A session's question that matches an open question the owner has answered (same key or a similar title) is its next round: it's posted as a comment in that issue, mentioning the owner, with its own screenshots. The PR leaves that issue open: `with_closes` doesn't add `Closes #N` for it and turns a `Closes #N` the session wrote into `Continues #N`. The issue is closed only by the PR that carries out the final answer.
- **Keys.** A next round under a new key adds that key to the issue, so a task blocked on either key waits on the same issue. After the round is posted the issue waits for the owner again, so the blocked task stays blocked until the next `/claude`.

## 2026-10-22: Only questions still waiting for the owner stop a new one

- **Why.** A question that matched one closed in the last 30 days was dropped, and an answered question stays open until the PR carrying out the answer merges. So the next round of a decision (#190, then #192) could be dropped with only a line in the log, and the owner would never see it.
- **What.** A question is only not asked when one with the same key or a similar title is open and has no `/claude` answer yet. That still stops sessions that hit the same blocker from asking it again in other words (#72/#73, #79/#80/#83). Closed and answered questions never stop a new one; a next round gets a new key and says which issue it follows.

## 2026-10-22: Owner questions carry their own screenshots, in the question

- **Why.** The owner reads a question after its PR has merged. Copying the PR's before/after comment onto the question afterwards put the pictures in a later comment, missing from the notification, and they showed what the PR changed rather than what the question asks.
- **What.** A question can name up to three shot scripts (`screenshots` in `owner_questions`), staged to show exactly what is being decided. They run in the screenshots job with the PR's, on the same commit (on `main` when there is no PR), and appear under "What it looks like", right after the question. A question that names none shows the PR's screenshots instead.
- **Order.** Questions are asked by a new `ask` job after the screenshots are posted, not when the PR opens, so the issue is created with its pictures. The revision is told the first session's questions, since they aren't issues yet, so it doesn't ask them twice; `finish` waits for `ask`, so the next session sees them.

## Planning 2026-10-23: queue nearly empty, M2 still not done

- **Why:** only stabilisation was queued. No "Daily run" post with "Stress and timing results" exists yet (#202 is the newest daily log), so the WASM task stays blocked. The art recording task still waits on `art-direction-pick-3`; no issue for that key is open (#190 and #192 are closed), so it is asked again. No issues were in the queue or backlog.
- **Now:** a reactions walkthrough is added as the polish re-examination (reactions are what make combos surprising). `shot_reactions.gd` already shows four of the six by hand-sent events; the task extends it to all six by real hits and checks that they can be told apart at 1x, with at most two fix passes. Stabilisation follows it. M2 is not done (done-when items 3, 5 and 6 are open), so no checkpoint.

## Planning 2026-10-22: queue empty, M2 not done

- **Why:** the queue held only the WASM numbers task (parked: no web `BENCH:` post exists yet), the art recording task (waits on `art-direction-pick-3`) and stabilisation. M2 is not done: done-when items 3 (WASM numbers), 5 (owner items) and 6 (stabilisation) are open, so no checkpoint yet.
- **Now:** the WASM task is under Blocked with its trigger; the multimesh slice upload is split out as a task that needs no data; a builder walkthrough is added as the polish re-examination (the builder is what C2 asks about and only has tests so far); stabilisation follows. No scope was cut; no issues were in the queue or backlog.

## 2026-10-22: A third round of art samples: the hat is its own layer

- **Why.** The owner answered #192 (key `art-direction-pick-2`) with "F's hat is nice, the body needs work, maybe only the hat changes colour per player, give me more options, maybe the palette needs work", and re-posted it as "not a pick" after the first session dropped it. So the question is asked again, with a new key `art-direction-pick-3`, as the owner asked.
- **What.** F's hat is kept as it is and split from the body: a body sprite with no player colour plus one hat sprite per player. That keeps "a colour on screen means a player" (STYLE.md) and cuts per-player art to the hat. G (brown robe) and H (cream robe) are two bodies; I is H with a palette proposal (brighter player ramps, a warm floor). The proposal's colours are allowed only in `art/samples/i_warm/` and `hats_vivid/`; they are not in STYLE.md or the palette test until the owner picks I.
- **Cost if picked.** A hat layer means two sprites per wizard frame (or a baked sheet per player); the animation task has to decide which. Not decided here.

## 2026-10-22: A second round of art direction samples, and a second owner question

- **Why.** The owner answered #190 (key `art-direction-pick`) with a lean towards A, a liking for C's robe, and a request for more options, a new style included. That is not a pick, so the task "record the chosen art direction" cannot be done yet and the first question is answered, not repeated.
- **What.** D (A with C's robe) is the owner's own hint made real. E (soft, no black outline) and F (big hat, plain beveled floor) are the new styles: one changes the outline rule, the other the silhouette. Both are checked against pillar 4 (readable chaos): F is the strongest silhouette, E the weakest contrast.
- **E breaks the outline rule on purpose** and says so in the README; the sample-icon test takes its outline colour per sample so the closed-outline rule still holds.
- **New key.** The pick is asked again as `art-direction-pick-2` because the options are new; the task stays under "Blocked" in `docs/NEXT.md` with that key. Nothing is recorded in `golden.json` or `STYLE.md` until the answer.

## 2026-10-22: Art direction samples live in `art/samples/`

- **Three options, one of them the status quo.** A (chunky) and C (grim) are new; B is the current placeholder files, so "keep and polish" is a real choice. All use the existing palette: the choice is about proportions, shading and mood, not colour.
- **Folder.** `art/kit/` has a `.gdignore`, so Godot would not import files there and the shot script could not load them; the samples are in `art/samples/` instead. `test_svg_art.gd` does scan it (rects only, whole numbers, palette, no overlaps, manifest entry, closed icon outline). The edge-touching floor joints still pass, because no test checks that STYLE.md rule. The files are in `art/manifest.json` as placeholders.
- **Not asked of the owner here:** the pick itself and the lock in `docs/DESIGN.md` (owner-only); the question key is `art-direction-pick`. Until it is answered nothing changes: STYLE.md stays provisional and the golden examples stay candidates.

## 2026-10-22: What "closed outline" means in the icon test

- Every non-outline pixel needs a filled pixel on its four sides (not the diagonals), and none may touch the icon edge. STYLE.md allows diagonal steps in an outline, so diagonals are not checked. Only the spell icons are checked; vfx may outline in their own shadow shade.

## 2026-10-22: A neutral bolt with an element core

- **One shader, no new palette colour.** The bolt, rune, orbit orb, beam and ring are Bone art whose Spark pixels are the "core"; `shot_core.gdshader` treats warm pixels (red well above blue) as core and keeps their three shades as dark, mid and light. Bone is near neutral, so the test of the palette (`test_svg_art.gd`) needed no change.
- **Body = player, core = element.** The body tint stays the 45% mix with the owner's colour, so the four players stay apart; the element shows only in the core. Frost and void still share a colour with Player 1 and Player 4 until the blocked recolour task changes the elements' ramps; the core's position (the centre) keeps them apart meanwhile.
- **Per-shot core in the MultiMesh custom data** (`DRAW_STRIDE` 16), set with `set_core(slot, color)` after `spawn` rather than a new `spawn` argument, like `set_homing`. The runtime sets it in `_register`, so chain jumps and held spells get it too.
- **Runes and orbit shots have batches of their own** (chosen by motion, so `spawn` is unchanged), with `rune_texture` and `orbit_texture` falling back to `texture`.
- **Beam and nova ring through a new event, `form_shown`** (sender `core/spells`, listener `feel`): a beam holds no row and a nova is ordinary shots, so nothing else tells feel about them. A nova sends one event for the whole ring; a beam one per ray (a chain's jumps included), inside Feel's pool: 24 slots per player, so a split fan is drawn whole, and a player's oldest is taken over. A plain spell (no element) has a white core on purpose: the core shows the element, and arcane has none.
- **`fire_bolt.svg` renamed `bolt.svg`**, since it is no longer fire.

## 2026-10-22: Element tints use Ice base and Void light

The frost tint is Ice base (`#4fd6dc`), not Ice light (`#c4f6f2`, nearly white); the void tint is Void light (`#e08ad8`), not base (`#a0309a`, too dark on the Stone floor). The icons keep the shadow, base and light of each ramp. The on_hit icon is a star burst and on_expire a ring so they differ in a black silhouette.

## 2026-10-22: Stress in the exports, and the limits (M2 part 25)

- **Both benchmarks are nodes the main menu adds on a user argument** (`--stress`, `--projectile-timing`), exactly like `--four-bot`, so the Linux Test and Web Test exports (which keep `tests/`) can run them. The projectile timing script became `projectile_timing_runner.gd` (a node); `test_projectile_timing.gd` is now a thin SceneTree starter, so the command line and `build.sh --tests` behave as before. The menu has one `_start_runner` for all three, with literal `load` paths.
- **The limits hold headless; WASM is pending.** Headless stress with four heavy builds: p95 13.9 ms (100 enemies, 1,000 shots) and 15.4 ms (200, 3,000), inside 16.7 ms; nothing lowered. Game logic only, not WASM: the web numbers need the export run. If they are over, the first things to lower are `DEFAULT_CAP_WEB`, `MAX_SHOTS` and `MAX_FIRES_PER_STEP`.
- **The web projectile timing step already exists in `build.sh`** and waits for `TIMING OK`; the runner prints it (and `TIMING FAILED`). That step is untested until the daily build runs it. The `--stress` step is missing and is an owner question (#166); it only prints and warns.
- **If the first daily web timing run fails or times out:** first check the 240 s timeout in `ci/build/build.sh` (owner-only) and whether the web run should time only the web cap (1,000 shots) instead of the desktop 3,000. Then read the first real WASM `BENCH:` lines and confirm or lower the limits (task "Read the first WASM numbers" in `docs/NEXT.md`).

## 2026-10-22: The stress scene (M2 part 24)

- **Real game, topped-up shots.** The scene is the real Flow, Combat, spell runtime and Feel with four bots, not a stand-in. Spells alone never make 1,000 or 3,000 shots, so each physics step the runner adds plain filler shots (load only, no spell effects; the effects come from the bots' real spells; fixed seed, owned by the players in turn) up to the target; the manager's cap is set to the target, so dropping the oldest shot is part of the load. Enemies are added whenever fewer than the target stand, with 120 health instead of the imp's 20, so the crowd lasts. Wizards stay protected with full mana: it is a stress scene, not a balance test.
- **Pass means the load was real, not fast.** `STRESS OK` needs the mean of enemies and shots over the measured window at 90% of the target (not one peak frame), every bot casting in that window, spell shots (tag not 0) hitting something, no refused build and no logged error. Frame time only prints (`BENCH WARNING:` past 16.7 ms p95), as PLAN says ("Gates are sparse"). The build runs a short version (`test_stress.gd`); the full one is `stress.gd`. Part 25 puts it in the exports.

## 2026-10-22: The first lore (M2 part 23)

- **One JSON file per component** (`lore/components/<id>.json`, keys `id`, `about`, `text`) rather than one big file: contributors add content as new files and conflicts cannot happen. `about` is there so relic, item and enemy lore can share the schema later without a new folder rule.
- **The registry reads the lore** (it is the one script allowed to load from computed paths); `Spells.component_description` asks it, so the HUD still reads no component field. Invalid lore files are never given out.
- **Validator in `core/story/`**, not in the spells validator: story belongs to its own area. It runs in tests and as debug-build warnings (`tools/check.sh` is owner-protected, see #140). A missing lore file for any spell component is reported as `missing-lore` in the debug-build warnings, but the test does not fail on it: a Spells PR must not fail CI for a rule outside its area. The builder shows an empty note and Story or Claude fills the gap; `content/spells/README.md` lists the file as a step.
- **Descriptions state the real numbers only where they are fixed** (eight shots, three orbs, up to twice, every half second, up to four times); other effects are said in words so a retune does not make them lie.

## 2026-10-22: Story canon (M2 part 22)

- **Short, with seven fixed points.** `docs/STORY.md` fixes only what the game already shows or needs (the wizards as guild apprentices, the build-from-parts magic, the four elements' characters, the crypt, imps, the stakes, relics). Biomes after the crypt, bosses, hub and dialogue are left open, so later writing and contributors add canon instead of fighting it.
- **Tone reading of pillar 3:** dry rather than silly, with the danger never made small. Descriptions follow the 60-character limit that part 23 validates.
- **Component names are quoted from the registry** (Bolt, Frost, On Hit, ...), so lore and builder agree.

## 2026-10-22: Combos to 20+ (M2 part 21)

- **Nine rows added, two changed from the draft.** Draft row 13 (nova + void, on hit → fire *bolt*) became a fire *nova*: a held bolt starts inside the hexed imp and, since the 0.1 s exclusion ends before it has crossed the imp, hits it again and is used up, so it never reached the imps behind (the known issue in `docs/BACKLOG.md`). Draft row 21 (fire rune that ends in a frost nova, Thaw) became a fire rune that bursts into a fire nova on expiry: a rune has no pierce, so its first hit uses it up and it never expires on a target. A rune that expires needs imps standing just outside its reach, which the nova then burns. Both stay faithful to the pillar (small parts, deep results) and avoid pinning a bug.
- **Two drafts are not rows yet.** Draft rows 16 (clamp refusal) and 17 (depth 3) stay with `test_spells_cast.gd` and `test_triggers.gd`, which already cover them; rows 20 to 24 beyond the two-player one are not needed for the two-per-component rule. More rows can be added any time.
- **The two-per-component rule is a test.** `test_every_component_is_in_two_combos` reads a `COMPONENTS` list in the test; a new component is added to it together with its rows, as the spells README asks; a second test compares the list with the registry, so a missed component fails. Rows for chain, pierce, faster and on expire also have a control: the same row without that component must fail a check. The control showed that a bolt that hits ends by hit, not by expiry, so "Seeking frost burst" now pierces and bursts where its flight ends.

## 2026-10-22: The build break

**Decided by:** Claude (M2 part 19).
- **`BUILD_BREAK` (12 s) replaces `NEXT_WAVE_DELAY`.** Flow's timer is fixed: no builder, open overlay or build request holds the next wave back or brings it forward, for 1, 2 or 4 players (co-op rules 1 and 2). 12 s is the design's first guess, tuned at C2.
- **New event `build_break_started(seconds)`, sender `flow`, listener `hud`,** sent right after `room_cleared`. The HUD may only show what events say and `Flow.build_break_left()` is not an event, so the HUD counts down by itself from `seconds` in `_process`. It is display only: if it drifts, the wave still starts on Flow's clock. `wave_started` ends the line.
- **The hammer is drawn in code** (`hud/widgets/hammer_icon.gd`), not an art file: no asset, no manifest line; the art pass (part 26) may replace it.
- **The break line is drawn over the builders,** on a dark backing: four open builders cover the whole top middle, and the countdown is the one thing that must stay visible.

## 2026-10-22: The quick view and quick actions

**Decided by:** Claude (M2 part 18).
- **A wave is "in progress" from `wave_started` to `room_cleared`.** `panels.gd` folds every builder into the quick view on `wave_started` and unfolds it on `room_cleared`, `run_started` and `run_ended`. No new event: the break between waves is exactly the time after `room_cleared` until the next `wave_started`, which part 19 (`BUILD_BREAK`) makes longer without changing this.
- **New event `active_spell_changed(player, slot)`, sender `player`.** The HUD may only show what events say, and `swap` changed a private variable. The wizard sends it when it appears and after each swap; the corner panel shows "Spell A"/"Spell B" from it, and the quick view and overlay follow it.
- **The HUD turns `swap` presses into `spell_swap_requested`** in `panels.gd` (like the `overlay` toggle, from the press counter). Presses are dropped, not kept, when the player is in a menu (`swap` is captured there like `cast`), down, not joined or outside a room. At most two requests per poll.
- **Drop component offers the empty element slot and the first free modifier slot only** (`hud/widgets/drop_choices.gd`, shared by the overlay and the quick view). The form and the trigger need the full builder; the design says "a free modifier slot, or the empty element slot". It always acts on the active spell, level 0, with `build_change_requested(player, [active], slot, id)`; `player` checks it like every request.
- **The quick view keeps the slot chain read only and hides tabs, held levels, bag and info panel.** It follows the active spell. Its drop list has no icons and tighter rows, and the overlay's list is two columns that replace the three buttons while it is shown, so the longest list (spell B: four elements and six modifiers) fits each player's quarter of 640×360. Tested with four players.
- **`Build` pressed during a wave opens the quick view.** The full builder is for the break, as in the design.
- Left for later: the hammer icon on a building player's panel is part 19.

## 2026-10-22: The M1 fire bolt moves to `legacy/fire_bolt`; the new bolt takes the id `bolt`

**Decided by:** Claude (M2 part 10).
**Decision:** The M2 form `bolt` lives in `content/spells/forms/bolt/` with id `bolt` (the id equals the folder, and the design's recipes say `bolt`). The M1 `SpellBase` bolt, which `flow` hands to the wizards and `combat` profiles until part 11, moved to `content/spells/legacy/fire_bolt/` with id `fire_bolt`; `Flow.DEFAULT_SPELL_ID` and the tests that named it follow. Part 11 deletes the `legacy/` folder with `SpellBase`.
**Why:** two resources cannot share an id (the registry keeps one), and migrating the bolt in place would have broken the playable game for a whole task.
**Forms' numbers (first tuning, from the M2 design table):** bolt 1 complexity (damage 5, 5 mana, 0.35 s), the others 2: beam (4 damage, pierce 1, reach 240, 0.8 s), nova (8 shots of 3 over 360°, reach about 60 px, 1 s), rune (8 damage, waits 8 s, radius 14, 1.2 s), orbit (3 orbs of 3 damage at 36 px turning 4 rad/s for 3 s, pierce 4, 3.5 s). The stress benchmark and playtests will retune them.
**Not seen in the game yet:** the beam's `lifetime = 0.15` is the time the drawn beam stays on screen (the hit itself is instant), for the part-26 art pass. The four vfx sprites in `art/vfx/` (beam, nova ring, rune, orbit orb) are not wired to anything yet, so nobody should expect them in the game.

## 2026-10-21: Gates are sparse; hard gates notify the owner

**Decided by:** the owner ("Gating should in general be sparse. Development should be prioritized to continue instead of gating stuff. Of course a hard gate can happen, in that case I should be notified").
**Decision:** written into docs/PLAN.md, "Gates are sparse".
- The hard gates are a broken build (build, tests, smoke tests, error lines) plus the security and copyright rules. Each one already mentions the owner when it trips: a broken build's Daily log post, a failed revert, and the alarm issues.
- Budgets warn with likely fixes: web load time (above), download size (`build.sh` no longer fails over 40 MB or 300 MB), frame time and the M2 stress benchmark (a warning, not a gate, when part 25 adds it). The 10% frame-time regression no longer reverts.
- The stable channel still promotes only builds that are within budget. Nightly builds always ship.
**Consequence:** a budget can be broken for a while. The warning in the build log, and a task once it repeats, are what bring it back.

## 2026-10-21: A slow web load warns, it never fails the build

**Decided by:** the owner ("loosen up a bit on the load timing. It should not hinder development ... it should just give warnings and potential fixes").
**Decision:** `smbot.websmoke --warn-load 10` prints `WEB LOAD: N s` and, over 10 s, a `::warning::` that lists likely fixes: the zip size, big new assets, work at start (autoloads, `Registry.scan`), trimming demo content, and a slow runner. The web smoke test still fails on errors, exceptions and a missing expected line. `--max-load` is gone. The 10 s load in docs/PLAN.md stays a target, not a gate.
**Consequence:** a slow web start shows up in the daily build log and never reverts a merge. Acting on the warning is a normal task, filed when it repeats.

## 2026-10-22: Reactions (M2 part 8)

**Decided by:** Claude.

- **Six reactions, twelve rows.** The table is looked up by (status on the target, element of the hit), so each pair has a row for each direction and both carry the same `reaction_id`. In the other direction the reaction works on the other status: Shatter eats shock when frost hits a shocked enemy, Kindle spreads hex when fire hits a hexed one. Without that, a pair would only react one way round.
- **Two new row fields:** `pull` (Rift) and `consume_status` (Thaw uses the burn up). The design's "consume, then a burst" for Thaw is a BURST with `consume_status`, so no fifth effect kind. A burst includes the struck enemy.
- **Order:** the reaction is picked from the statuses the target had when the shot arrived (first of burn, chill, shock, hex with a row for that element); the hit's damage lands first; the reaction runs only if the enemy lived, and replaces the hit's own status. A frozen enemy counts as chilled. A shock is still spent by the hit, so the shock jump and a shock reaction can both happen.
- **No chains:** reaction damage and spread statuses go through `hit` and `apply_status`, never through `projectile_hit`, so a reaction can't set off another one.
- **Stillness** freezes a chilled enemy for 2 s and lengthens a freeze by 2 s (a long freeze, as designed); on hex it adds 2 s and +25 %.
- **Limits (review fix).** Flare, Rift, Kindle and Stillness leave the status on the target, so without a limit every later hit of that element would react again. Decided: each enemy reacts at most once per `REACTION_WAIT` (0.5 s); a hit inside the wait does its own status instead. A per-enemy wait rather than consuming the status, because Kindle must keep the burn it spreads and Stillness must keep the freeze it extends. EXTEND is capped (`MAX_FREEZE` 4 s; other statuses 8 s; hex and shock extra damage 100 %; burn rate 20), so rapid fire cannot freeze for ever or stack hex without end. Shatter doubles whenever the target is frozen (not only on the chill row) and then ends the freeze. Feel plays a reaction's sound and shake at most once per 0.3 s per id, and skips a name already rising within 40 px.
- **Numbers** (Shatter 6, doubled when frozen; Thaw 3 in 40 px; Flare 2 in 56 px; Rift 2 in 48 px with a 120 px/s pull; Kindle 48 px) are first tuning for the playtest.
- **Feel** gets a flash, a burst, the reaction's name as a rising label and the sound `reaction_<id>` from the preset (`reaction_colors`, `reaction_sound_prefix`). The "number" is the name: the damage already shows through `damage_dealt`.

## 2026-10-22: The validator (M2 part 9)

**Decided by:** Claude.

- **It is a class of static functions fed with resources** (`SpellValidator`), not a scanner. The registry is the only script that loads from computed paths, so it hands the validator what it found (`validate_spells()`); a test can hand it any fixture the same way.
- **Known statuses are a list in the validator** (burn, chill, shock, hex), because `core/` may not depend on `gameplay/combat`. A test compares it with combat's `REACTING_STATUSES`. `freeze` is left out: no element sets it.
- **Duplicate ids are seen through the registry,** which keeps the first file and used to only warn; it now also remembers the duplicates under `spells`, and the validator reports them. Ids are unique across all four kinds because they share the `spells` folder.
- **Beyond the design's list,** a form must have the number its motion uses (speed, orbit radius or ray length), an element with a status needs a duration, a homing or chain modifier needs a strength and a timer trigger needs an interval: a component that does nothing is a mistake, not a choice. Reaction rows get ranges of their own (`REACTION_RANGES`), wide sanity bounds like the component ones.
- **Resources in `spells` that are not components** (M1's `SpellBase` bolt, until part 10) are skipped.
- **`tools/check.sh`:** asked of the owner (issue #140). The validator already runs in `ci/build/build.sh --quick --tests`; `check.sh` needs only git and Python, and Godot may only be run through `build.sh`.

## 2026-10-21: Spell component base classes (M2 part 1)

**Decided by:** Claude.

- **The ranges live in code.** Each class has `ranges()`, and `SpellComponent.range_problems()` checks them. The validator (part 9) and the docs then read the same numbers, so they can't drift from a separate table. The ranges are wide sanity bounds, not balance.
- **The beam is a fourth motion, `RAY`,** next to `STRAIGHT`, `STILL` and `ORBIT`, with the extra fields `ray_length` and `orbit_radius`, each used by one motion only. The alternative, deriving the ray length from speed × lifetime, hid a meaning in two unrelated fields.
- **Split is `shot_mult`, not a behaviour.** The `Behaviour` enum is only `NONE`, `HOMING` and `CHAIN`, the two that need code at run time; `behaviour_strength` is the turn rate or the number of jumps.
- **Reactions are sub-resource rows (`ReactionRow`) in one `ReactionTable`.** Neither has an `id`, so the registry never registers them, which a test checks.

## 2026-10-21: M1 closes on the owner's go; M2 starts

**Decided by:** owner ("Start milestone 2", in a session on 2026-10-21).
**Context:** C1 (#97) had two iterate rounds; the second (2026-10-20) queued a round-2 playtest report. Still open from M1's done-when: the web 4-bot run (#93, in the owner's PR #98), M0's dry runs and 3 daily releases in a row. The Claude-side WASM projectile timing runner was also unfinished.
**Decision:** the C1 verdict is **go**. M1 is closed and M2 starts with its design document. The open items are not dropped: they carry into M2's done-when (item 5), as M0's carried into M1. The WASM runner is folded into M2 part 25. The two round-2 playtest tasks are dropped from the queue; the weekly playtest goes on and asks about building from part 20.
**Consequence:** the web 4-bot run is still unproven while M2 is built, until PR #98 merges.

## 2026-10-21: M2 design choices the plan left open

**Decided by:** Claude (details in `docs/milestones/M2-spell-system.md`).

- **The spell runtime is a new core service, `core/spells/` (autoload `Spells`),** not in the plan's `core/` list. Content may depend only on `core/` and the player may read no spell field, so compile, cast and triggers must sit in core. `combat` asks `Spells.hit_profile(tag)` (gameplay → core).
- **Tags carry player, slot, depth and a generation ring of 8,** so shots in flight keep their old profile after a rebuild.
- **Six reactions from four effect kinds in a data table;** every element reacts with the three others, more than DESIGN.md's "at least 2 interactions".
- **Limits:** complexity 12 per spell (with the table of provisional costs), 24 shots per cast, trigger depth 3, 32 trigger fires per player per step. The stress benchmark confirms or lowers them.
- **The bag holds every component in M2;** `rewards` (M3) fills it per player instead.
- **The full builder is used in the break between waves, which becomes a fixed `BUILD_BREAK` (12 s)** with a countdown. When a wave starts, an open builder folds into a quick view. Nothing waits for a builder (see the review below).
- **Spells opens at part 15** (all four kinds, the validator and the example exist), **Story at part 23.**

## 2026-10-21: M2 design review

**Decided by:** Claude, after an independent review with fresh context against `docs/DESIGN.md` (docs/PLAN.md, "Autonomy").
**Findings and changes:**

- **Blocking, fixed:** the first draft held the next wave up to 20 s for a player in the full builder. That made the others wait on one player (pillar 2) and borrowed M3's door rule. Now the break has a fixed length, the wave never waits, and the hammer icon is a display only.
- The full builder was allowed during waves, against PLAN ("cleared rooms and the hub"; quick actions in combat). Now it is used in breaks and folds into a quick view in a wave.
- The draft relied on a nearest-target query that `core/projectiles` doesn't have. Part 3 now adds `nearest_target` and `targets_in`.
- Elements came after the parts that need them. They now come right after casting (part 7), and the validator is its own part.
- `flow` holds a `SpellBase`. Part 11 now moves it to start recipes and updates ARCHITECTURE.md.
- Tag lifetime after a rebuild, the type of the `spell` path (`PackedInt32Array`), and the origin, direction and source exclusion of held spells are now specified. Triggered spells send no `spell_cast`.
- Combos 5, 6, 8, 15, 19 and 20 promised things the rules don't do; they are reworded or changed. Combos 22 and 23 and a split in 12 make every component appear twice. Provisional complexities are given, and every combo fits under 12.
- Spells opened before modifiers and triggers existed; it now opens at part 15.
- The path-tier wording now leaves out the owner-only docs. The projectile manager and the stress parts are each split in two. Nits fixed: modifiers may repeat, ids are unique across kinds, the reaction table has no id, cooldown is the cast time, and there are no particle counts to validate yet.

## 2026-10-21: Animated torches, 2.5D pillars and impact particles (owner `/claude` on #4)

**Decided by:** Claude, on the owner's four requests.

- **Torches: engine animation, no script.** Rooms carry no scripts, so a torch is a scene (`content/rooms/crypt/decals/torch.tscn`) of a bracket, an `AnimatedSprite2D` flame (4 frames, played in an 8-step order, 5 fps) and an additive glow made of a static disc plus an `AnimatedSprite2D` core (3 sizes, 9-step order, 6 fps). The two `SpriteFrames` are shared by all eight torches; the room only sets `speed_scale` (0.85 to 1.25) and a start `frame` per instance, so no two torches share both. STYLE gives animated tiles 4 fps; the flame runs at 5 because 4 fps looked like a slideshow in the sheet. Looked at in the `crypt_pillars_torches` screenshot: the flame is small at game scale but reads as a flame; further tuning waits for a human playtest. The glow is two flat stepped discs at low opacity, per STYLE's "one or two flat rings"; no `PointLight2D` (it costs a lighting pass per torch for the same look). 16 animated sprites cost the engine's animation step and a redraw per frame change.
- **Other decals: nothing else to animate.** The crypt room has no braziers or candles; skulls, rubble and doors are floor or wall detail that does not move. Braziers or candles, when they are added, copy `torch.tscn`.
- **Pillars: split sprite, no y-sort.** The world is a plain `Node2D` with the room, wizards and enemies as siblings, so y-sorting would also have sorted the floor, walls and rubble against the wizards (the room's floor decals would pop over a walking wizard). Instead the pillar is two 32×32 sprites: the base (shaft's lower half and plinth) on the footprint in `Pillars` at z 0 and in tree order under the characters, and the top (capital and upper shaft) one tile higher in `PillarTops` at z 5, over every character. A wizard behind the pillar is covered by the top; one in front is drawn over the base. The cost is that a wizard behind the pillar is covered yet still targetable, so `PillarTops` is 60% opaque (`modulate`): in the `crypt_pillar_walk_behind` screenshot the wizard behind it shows through and the top still reads as a capital. A wizard beside the pillar can still have its head slightly under the top. Feel's bursts sit at z 19 (above the tops, below the flashes) because Feel draws before the room; a refused shot born inside a wall shows no impact, and an impact only aims the damage that follows in the same physics frame. Collision is unchanged (one tile). The pillar sprites left `Walls` because the test there ties every sprite to a collision rectangle of the same size.
- **Impact event: one signal, `projectile_impact(player, target, position, direction)`.** The hit burst needs the shot's direction, and `projectile_hit` (read by `combat`) and `damage_dealt` carry none; changing their signatures would have touched their listeners and tests. A new event sent by `core/projectiles` just before `projectile_hit` carries it, and the same event with `target = null` reports a shot ending on a wall (`Feel` cannot reach into the manager). `Feel` keeps the latest character impact and uses it for the `damage_dealt` of the same target that follows at once, then forgets it; damage with no impact (contact hits) stays the old round puff.
- **Spray numbers (all in the preset; seen in the `impact_*` screenshots, not yet by a human playtest).** Cone 35° to each side, 1.4× the puff's speed, 8 particles (a burst is still 8, so `PARTICLE_LIMIT` 48 holds), size ±6% per damage point from 5 (the bolt), clamped to 0.7 to 1.6. Ember for enemies, the wizard's reticle colour for a wizard (the node in group `players` with an `index`, so `Feel` names no player script). A kill keeps the hit's burst and its colour.
- **Wall impact numbers.** One burst of stone chips (`#a39fb8`, 60° cone back off the surface, wall-normal not known so it is the reverse of the shot's heading) and one spark sprite in the shot's colour (4 extra sprites, 0.1 s). Chips only start while fewer than 4 of the 6 bursts are in use, so four players firing at a wall never take the last two bursts from hits on characters.
## 2026-10-21: Enemy shots shrink to radius 3.5 (owner `/claude` on #4)

**Decided by:** Claude, on the owner's request.

- `attack_radius` goes 5 to 3.5. One number sets both the hit circle and the drawn size, so sprite and collision stay matched. The orb is about 10 px wide, readable at 32 px scale, and smaller than a wizard's default bolt (radius 4). A wizard's hit circle is 8, so a 12 px sidestep clears the shot; the telegraph lane narrows with it. Each shot is checked against all players the same way, so co-op dodging is unchanged. Not playtested by a human: This partly undoes the bigger hit circles of the 2026-10-20 hit-box fix (#5) for enemy shots only: the wizard's circle of 8 plus the shot's 3.5 is still a body-sized hit. The 10 px orb inside its quad was not checked by eye. The next playtest report should ask whether shots feel like they pass through the wizard.

## 2026-10-20: Foundation review: data over constants (owner `/claude` on #5)

**Decided by:** Claude, from the owner's request to make the foundation solid, easy to extend and art easy to swap.

- **The review found the layering sound** (events, registry, dependency direction, content by folder, art in scenes) and three spots where a change would have needed a code edit: `Feel` loaded three art files by path, `Flow` fixed the room, enemy, spell and wizard scene as constants, and the wizard's art contract was not tested. Fixed those only; no restructuring.
- **Art paths live in data.** `FeelPreset` has `spark_texture`, `bolt_texture` and `hostile_texture` (defaults preloaded, so a preset that sets nothing still draws). A re-skin is a preset. Scenes already held every other texture.
- **`Flow` takes ids and the wizard scene as fields** (`room_id_to_play`, `enemy_id_to_play`, `spell_id_to_play`, `wizard_scene`), defaulting to the M1 content. A room picker or loadout sets them; unknown ids start no run, as before. The old `ROOM_ID`, `ENEMY_ID` and `SPELL_ID` consts became `DEFAULT_*`.
- **Not done, on purpose:** wave data on rooms, splitting `player.gd`, enemy attack patterns, the M2 spell components. Each is large and belongs to the feature that needs it (`docs/BACKLOG.md`, "Foundation"); doing them now would be guessing the shape.
- **Tests do not check looks** (already the rule in `tests/README.md`): the art tests check strip sizes and wiring only, so a redraw cannot break them. The feel test that compared against fixed art files was replaced by one that swaps the preset's textures.

## 2026-10-20: Hit circles sit on the body, and are bigger (owner `/claude` on #5)

**Decided by:** Claude, on the owner's bug report: hitboxes too small, shots seem to pass through sprites.

- Cause: sprites are drawn 14 px above the node origin (the feet), but every hit circle was centred on the origin, so a shot through the drawn body at body height was up to 14 px from the circle's centre and often missed. Radii were also small (imp 8, wizard 6, shots 4).
- Fix: `Projectiles.add_target` takes an `offset`; `Combat.register_enemy`/`register_player` pass it on. Both the imp (`Ai.hurt_offset`) and the wizards (`Flow.PLAYER_HIT_OFFSET`) use (0, -12). Radii: imp 8 to 11, wizard 6 to 8, bolt 4 to 5, imp shot 4 to 5. The imp's shot and telegraph now start at its body, not its feet. Contact damage compares the hit circles too (each node's origin plus its offset), so it is consistent with the shots. With both at (0, -12) the offsets cancel and the contact range is only the larger radii: 14 px (6 + 8) became 19 px (8 + 11), about 36% more. The balance tests did not need new `BALANCE:` numbers.
- Not changed: the shot's drawn size (3x its radius) and the walls (still a point check). Tuning by feel waits for the playtest.

## 2026-10-20: Art direction before M2, and tests that break one at a time

**Decided by:** Claude, from the owner's `/claude` on #102 (art first, smaller isolated tests).

- **Art stays inside M1** (one enemy, one room); nothing from M2 was started. The final style is still the M2 art direction call; these are better placeholders under the same rules in `docs/STYLE.md`.
- **Depth without new colours.** The floor is darkened by the scene (`modulate` on the `Floor` sprite) and soft shadows are `Polygon2D` strips in the scene, not baked into art, so the art keeps the palette rule (no partial transparency). The top and bottom walls get a new tile with a lit top face; the side walls keep the old brick tile, because a lit cap repeated down a side wall would look like steps.
- **Telegraph.** The line is dashed by a repeating 8×8 tile, with a `Lane` strip (16 px wide, the shot's hit width plus margin) and a `Tip` arrowhead, all children of `Telegraph` so one `modulate` fades them together. `ai.gd` fits them to the shot's real reach, so the picture still shows where the shot goes. Width range 4-8 px (was 3-6).
- **Tests.** Every new test script extends `tests/support/suite.gd`: each `test_*` method is its own test, with its own setup, so one failure names one behaviour and cannot hide or break the next. Tests check behaviour and wiring, not how things look (no pixel colours, no count of decorations): an art or tuning change should not need a test change unless a rule is broken. `test_svg_art.gd` is the one place that checks the look rules (style rules for SVGs, manifest entries), data-driven over every file, so new art is covered without writing a test. Old test files are moved to the new shape when they are touched, not in one go (a mass rewrite would be a large, risky change with no new coverage); the list is in `docs/BACKLOG.md`.
- **Tests I did not move out of `test_ai.gd`:** chase, target choice, knockback, the damage test: they still work and are not coupled to art.

## 2026-10-19: Muzzle flash: size 0.5 (a small flare, not a blast)

**Decided by:** Claude, from the owner's bug report on #102.

- `muzzle_flash_size` goes from 2.4 to 0.5 (the `@export_range` minimum was already 0.1). With the 32 px `hit_spark.svg`, `MUZZLE_STRETCH` 1.8 and the 1.5× growth while it fades, the flash is 29 px long at the start and 43 px at its largest, about the size of the 32 px wizard. Before it was 138 px growing to 207 px.
- The stretch stays, so the flash still reads along the aim. The death puff has its own size (`death_puff_size`) and is unchanged.
- `test_feel.gd` fails if the `punchy` muzzle flash is longer than 48 px at any step.

## 2026-10-18: Wave pacing: waves in the same room, +2 enemies a wave, downed wizards stand up between waves

**Decided by:** Claude, from the owner's round-2 task list (#102).

- **Growth is +2 enemies per wave, capped at 24** (`WAVE_GROWTH`, `WAVE_MAX`). Wave 1 stays the fixed 8-imp list the balance and 4-bot tests were tuned on; later waves carry on round the room's spawns (stacked with the existing diagonal offset). Linear, because the bots (which never dodge) already struggle with 1 and 2 players at wave 1; faster growth would end runs at wave 2. The cap keeps the enemy count (and the shot count) inside the performance budgets. Real scaling by player count and level belongs to `difficulty` in M3.
- **3 s between a clear and the next wave** (`NEXT_WAVE_DELAY`): enough to see the clear, not long enough to idle. The world, the wizards and their positions are kept (a "same room" feel); only the shots in flight are cleared.
- **Downed wizards are back up at the start of the next wave** (with `revive`, 50 health, plus the 2 s join protection for everyone), so one mistake does not leave a player watching for the rest of the run, and nobody waits (pillar). Health is otherwise not refilled: a wave is a real cost. If this proves too hard, a heal belongs to rewards (M4), not here.
- **Quick restart: `RESTART_DELAY` 2.0 s to 1.5 s.** A lost room goes back to wave 1. The restart still builds a new world and sends `room_entered`; the wave counter restarts with `wave_started(1)`.
- **New event `wave_started(wave)`** (sender `flow`, heard by `hud`), so the HUD never reads `flow`. `room_entered` is not repeated for a new wave; `room_cleared` is sent for every wave.
- **HUD:** a plain "Wave N" label at the top middle (between the P1 and P2 panels), shown from the first `wave_started`, hidden when a run ends. Not tuned by playing (not possible here).

## 2026-10-18: Enemy readability: shape and brightness, a second draw batch, a hit never cancels a windup

**Decided by:** Claude, from the owner's round-2 task list (#102).

- **Enemy shots get their own batch, not a second texture in one.** A multimesh has one texture; an atlas needs a shader and per-instance data. A second `MultiMeshInstance2D` (one layer above) costs a second buffer of the same size and no extra loop. Enemy shots are untinted so they stay the brightest thing on screen; the player's comet keeps its 45% tint. Shape differs (round and spiked against a comet with a tail), so colour is not the only signal (docs/STYLE.md, "Readability").
- **Poses are textures, not new frames in `idle.svg`.** STYLE says one strip per animation, named by it. `ai.gd` swaps `Sprite.texture` and `hframes` and pauses the `AnimationPlayer` for the pose; the exports `windup_texture` and `hurt_texture` are optional, so another enemy without them behaves as before.
- **A hit does not cancel the windup.** Stun-locking would let one fast shooter cancel every imp, and the telegraph would stop meaning "a shot comes". The imp still has knockback (Combat) and Feel's flash; the hurt pose shows on top for 0.25 s and the telegraph line stays.
- **The windup flips by progress², not by time.** The pose slows at the start and speeds up, so "about to fire" is readable without a number. It is 5 flips-worth before the last 20%, where the bright frame is held (with the brighter colour), so the flash never goes above about 5 bright-dark cycles a second, however many imps wind up at once.
- **Cost of the second batch.** The enemy batch reserves `cap` instances and uploads its whole buffer when any enemy shot exists (Godot's `MultiMesh.buffer` takes all of it, like the player batch), so memory for draws doubles and a frame with enemy shots writes up to about 144 KB more on desktop. Accepted: the earlier decision showed the bulk write is cheap; a smaller enemy cap or a sliced upload is a later option if the web build needs it.
- **Not done:** no sound cue (audio is not in M1), no windup frames for the other directions (the imp is drawn from the front).

## 2026-10-18: Revive is automatic proximity in `coop`: 2 s hold, 48 px, 1.5 s protection

**Decided by:** Claude (owner `/claude` on #102, C1 round 2 task 1).
**Context:** `Player.revive(reviver)` existed but nothing called it, so a downed wizard stayed down until the room restarted. The earlier decision gave "how" to `coop`.
**Decision:** `coop` runs the revive (`step_revive`, from `_process`). No button: a standing wizard who stays within `REVIVE_RANGE` (48 px, centre to centre) of a downed one fills that wizard's progress in `REVIVE_HOLD_TIME` (2 s). "Holding" is staying put; it works the same on every device and needs no input action, and the reviver can still dodge or fire from there. Per downed wizard: the nearest standing wizard in range is the reviver, and a second helper does not speed it up (simple and predictable; two revives of different wizards run at the same time, for any indices 0-3). When nobody is in range the progress drains at twice the fill rate, so a quick step away to dodge costs a little and walking off loses all of it. A downed wizard never revives another. Leaving or a new room clears the progress.
**Numbers and why:** 2 s is long enough to be a decision (a wave of imps fires about that often, so reviving in the open is a risk the team must accept) and short enough that a downed player is not left out for long (pillar: nobody waits). 48 px is a body and a half (32 px sprite) so the reviver must really be beside the body, but a dodge (220 px/s) crosses it in 0.2 s so help is easy to give. 1.5 s of protection (the dodge's is 0.125 s, a joiner's 2 s) is enough to get out of the shot that downed the wizard; 2 s+ would let a revived wizard walk through fire. Revive health stays 50.
**How the downed player sees it:** a new event `revive_progress(player, progress)` (sender `coop`, heard by `player`), sent when the progress changes (0 when it stops or is done). The wizard draws a ring over its hat: a dark ring with an empty track and an arc that sweeps clockwise from the top, with a white cross in the middle. Progress reads from the arc length, not the colour (the arc is also in the player colour). The HUD may not look at wizards, and an event keeps `coop` from touching the wizard's drawing.
**Deliberate exception:** `coop` preloads `gameplay/player/player.gd` to read `index` and `is_downed()` and to call `revive`/`protect` on typed wizards, not just by `has_method`. This is the one direct link between two gameplay areas, kept because revive is the one place `coop` must act on a specific wizard every frame; everything else still goes through events.
**Consequence:** the numbers are untested by play (no person here); tune `REVIVE_*` in `coop.gd`. A team that wants a pause for revive-while-fighting will find the 2 s costly with many enemies, which is the intended tension. Co-op remains playable: there is no way to be blocked by another player.

## 2026-10-18: Juice leftovers: a `wizard_cast` event, a copied sprite for deaths, a vignette read from health

**Decided by:** Claude (owner `/claude` on #102, the "C1 juice, leftovers" task).
**Context:** The four things left from the juice pass each needed a node or a position that Feel may not look up.
**Decision:** (1) A new event `wizard_cast(player, wizard)`, sent by `player` right after `spell_cast`, hands Feel the caster node, so the squash needs no lookup. It is a second event rather than a changed `spell_cast`, which `combat` and the bots already use. The squash is thin and tall (the opposite of a hit's) for 0.1 s, 15%, without the white flash. (2) The muzzle flash gets rotation, a 1.8× stretch along the aim and the player's light colour from a table in `feel.gd` that repeats the reticle colours (`docs/STYLE.md` is the source). (3) The enemy is still freed at once (`combat` and `flow` depend on it); on `enemy_died` Feel copies the dead node's `Sprite` (texture, frames, region, offset, flip, world scale) into one of 8 pooled sprites, white, that widens, collapses and fades over 0.25 s. A full set takes the oldest slot. (4) The vignette lives in the HUD and is driven by a drop in `player_stats_changed` health, not by `damage_dealt`, because that event names a node, not a player index, and the HUD must not look nodes up. It is one shared overlay (one screen, four wizards) that is strongest toward the hurt wizard's corner, so "who" is shown by position and not by colour alone (the panel's HP number also falls).
**Review round (same day), after looking at crops of each effect at 4× from the screenshot script:** the muzzle flash was a thin blue sliver that was gone in 2 frames, so it is now 0.1 s at 2.4× (it still reads small beside the bolt in a still taken on a slow software renderer; at 60 FPS the first frames are larger). The big death puff (2.5×) hid the imp, so it is 1.6× for 0.14 s and the white death copy is drawn above it. The cast squash is 20% for 0.12 s (visible on the 32 px wizard). The vignette, shared by up to four wizards, adds per hit `0.7 × (share of max health lost / 0.25, 0.2 to 1) / √players`, so a four-player brawl peaks well under the limit (tested), the corner bias is 0.15 to 1 (was 0.45 to 1) and the middle of the screen is clear; the `enabled` flag turns it off for comfort. The death copy starts at the sprite's rest scale, and a cast during a dodge makes no squash because the dash look owns the scale then.
**Consequence:** a new enemy dies with the animation if its sprite node is named `Sprite`. Values are in `feel_preset.gd` (defaults, not `punchy.tres`, which sets none of these); nobody could play it in this session. If the cast squash feels too strong, lower `cast_squash` in `punchy.tres` only. The vignette numbers are constants in `vignette.gd` (the HUD may not read a gameplay preset).

## 2026-10-18: Juice lives in Feel and reaches sprites only through the event's target

**Decided by:** Claude (owner `/claude` on #102).
**Context:** The owner wants punchier hits, casts and deaths. Feel may not call other areas, and `damage_dealt` carries the hit node.
**Decision:** Feel flashes and squashes the `Sprite` child of the `damage_dealt` target (the same convention `ai.gd` and `player.gd` already use), with a shared white shader material it removes again. Feel stores instance ids, because a typed or plain array cannot hold an enemy freed in the same frame. Casts get a muzzle flash and a camera kick from `spell_cast`; the caster's own squash was left out, since the event has no node and a lookup would break the area rule. Hit-stop keeps the defaults (0.04 s hit, 0.15 s rest, so about 21% of real time slowed in a four-player fight, under the 30% test limit); extra punch comes from flash, squash and shake. Deaths stop 0.09 s. Everything else is tuned in `punchy.tres`.
**Consequence:** a new enemy gets the flash and squash if its sprite node is named `Sprite`. Flash and squash replace `Sprite.material` for 0.08 s, so a scene must not rely on a material there. Feel multiplies its squash onto the scale it finds; if the owner sets `scale` meanwhile (the dash look), Feel adopts that as the base and returns to it. Past 16 sprites reacting at once, a hit skips its flash and squash.

## 2026-10-18: Placeholder animation uses fewer frames than the table, and the staff is drawn by the game

**Decided by:** Claude (owner `/claude` on #102).
**Context:** The owner asked for readable placeholders, a visible staff and simple idle, walk and dash frames "if it fits in one session". `docs/STYLE.md` lists 4 idle, 6 walk and 4 dodge frames, but "use fewer frames rather than more", and a session that cannot run scripts has to write every pixel rect by hand.
**Decision:** idle 2 frames (2 fps), walk 4 (8 fps), dash 3 (16 fps, plays once, the last frame is held), imp idle 2. The strips are placeholders (tier `placeholder`); M2 replaces them. The staff is not in the wizard strips: the shots start at the muzzle along the aim, so a staff painted into the sprite pointed the wrong way for any aim but one. `staff.svg` is drawn from the hand, turned along the aim (the pixel art is rotated at runtime, which is only acceptable for a placeholder). Frames are composed with whole-number `translate` on rects, which `docs/STYLE.md` allows, so one hat or body is shifted per frame instead of redrawn.
**Consequence:** the playback speeds are constants in `player.gd` (`IDLE_FPS`, `WALK_FPS`, `DASH_FPS`), not set in the scene, and differ from the table (idle 2 fps, walk 8 fps); they move to the scene with the final art. The frame counts in the table are targets for final art, not checked. `player.gd` reads the frame count from the strip's width, so a better strip with more frames works with no code change.

## 2026-10-17: C1 changes no wave or feel value (M1 part 25)

**Decided by:** Claude.
**Context:** The task says to tune from bot logs and playtest answers. There are no playtest answers, no owner feedback and no open bug. The only data is the new `tests/bots/test_wave_balance.gd` run: bots that never dodge clear the wave of 8 imps alone with 20 of 100 health left, and with four players lose 20 health each.
**Decision:** keep every value (imp health 20, bolt damage 5 and cooldown 0.35, mana, move and dodge numbers, `WAVE`). One bot run does not say how moving, dodging and casting feel, which is the C1 question; a change made from it would be a guess, and player scaling is `difficulty`'s job in M3. The probe stays so the next round (iterate) starts from numbers.
**Consequence:** the owner's playtest answer decides what to tune; the C1 issue asks for it.

## 2026-10-17: The web 4-bot test starts from the page config, in a `Web Test` export (M1 part 23)

**Decided by:** Claude.
**Context:** Web has no command line and `JavaScriptBridge` is banned, so the game can't read a URL query. The shipped `Web` preset excludes `tests/*`.
**Decision:** a fifth preset `Web Test` (copy of `Web`, no exclusion, `build/web-test/`, never packaged), kept in step by `test_export_presets.gd`. The start argument comes from the `args` entry of the page's `GODOT_CONFIG`, which `websmoke.py` can inject when it serves `index.html`. The main menu now looks for `--four-bot` in `OS.get_cmdline_user_args()` and `OS.get_cmdline_args()`, because the web config may not include a `--` separator. The `ci/` change is asked as an `owner` issue.
**Consequence:** unverified in a browser until the owner makes the change; the task is reported blocked until then.

## 2026-10-17: The projectile caps are not validated; the draw code stays (M1 part 22)

**Decided by:** Claude.
**Context:** The task required timing `spawn`, `update_draw` and `_hit_test` at the cap before relying on 1,000 (web) and 3,000 (desktop). The numbers are in `docs/LOG.md`.
**Decision:** `update_draw` stays: spawning at the cap (about 1 µs) and the draw copy (0.3 and 0.9 ms) are cheap, and `multimesh.buffer` is one bulk write, so uploading only the first `drawn` instances would save nothing measurable. The hit test is different. In a hostile scene (fast shots, all piercing and starting inside 100 packed targets, each hit sending a signal) one step costs about 50 ms at 1,000 shots and 150 ms at 3,000, natively, and still 25 ms and 75 ms once the targets are remembered. Real play is far from that (the 4-bot run peaks at 10 shots), but the caps cannot be called safe. The caps are left as they are for now only because nothing in M1 gets near them; the work to bound the hit test and set the caps from the numbers is queued in `docs/NEXT.md`, with the rule that the web cap drops if the WASM step is over 8 ms. The probe prints and gates nothing, as the task said.
**Consequence:** the caps are provisional, not validated, on native or WASM; the queued tasks decide them.

## 2026-10-17: The 4-bot test runs in a separate `Linux Test` export (M1 part 21)

**Decided by:** Claude.
**Context:** The shipped presets exclude `tests/*`, so the exported game has no `four_bot_smoke.gd`. Dropping the exclusion would put test scripts in every release.
**Decision:** a fourth preset, `Linux Test`, in `export_presets.cfg` (Claude-maintained) with no exclusion and its own path `build/linux-test/`; the release presets are unchanged. It is a copy of `Linux` (including `custom_features="full"`, so the test runs the same feature set as the shipped desktop build) and must stay one: `tests/smoke/test_export_presets.gd` fails if the two differ in anything but name, `runnable`, `exclude_filter` and `export_path`. The step that exports it and runs the test is in `ci/build/build.sh` (owner-only), so it is asked as an `owner-change` owner question with the exact lines. The step greps the run's log for `SMOKE OK`, so a release template that ignores `--script` fails the step instead of passing without running the test.
**Consequence:** until the owner adds the step, the test runs only through `build.sh --quick --tests`. If the exported binary refuses `--script`, the fallback is an autoload reading a user argument (`-- --four-bot`), a game-side change.

## 2026-10-17: The export starts the 4-bot test from the main menu (#80)

The `Linux Test` binary hangs on `--script` while the autoloads start, so it can't run a `SceneTree` script. The checks are now a node (`tests/smoke/four_bot_runner.gd`); the main menu adds it when the user argument `--four-bot` is given and `ResourceLoader.exists` finds the file. Why the menu and not an export-only autoload: autoloads live in `project.godot`, shared by every export, and a missing autoload script would break the normal builds. The menu holds a literal-path `load` behind that check, and `tests/*` is excluded from every shipped export, so there the argument only logs a warning. Cost: a small hook in `hud/` that mentions `tests/`.

## 2026-10-17: The owner inbox

**Decided by:** owner.
**Context:** Questions for the owner were written into `docs/BACKLOG.md` ("Needs an owner decision"). Nothing notified the owner, there was no clear way to answer, and sessions never learned the answer.
**Decision:** a session that needs the owner puts the question in `owner_questions` in its structured output (development, revision and weekly planning). The publish step opens one issue per question, labelled `owner-question` (plus `owner-change` when the answer needs an owner-only change, with the exact change), mentioning the owner, with the options, Claude's recommendation and what happens meanwhile; a question already open under the same title isn't asked again. The owner answers with `/claude <answer>` in the issue; the next session carries it out and its PR says `Closes #N`. The Daily log lists the open questions. Sessions still decide everything they can themselves (docs/PLAN.md, "Never waiting for humans").
**Consequence:** `docs/BACKLOG.md` no longer holds owner questions. Its four open ones were answered in the same change (below).

## 2026-10-17: Unit tests run through `build.sh --tests`

**Decided by:** owner.
**Context:** Sessions were refused when they ran the Godot binary directly, and `build.sh` ran only the boot smoke test, so no unit test had ever run.
**Decision:** `ci/build/build.sh --quick --tests` runs every `tests/**/test_*.gd` in its own Godot process after the import and smoke test, and fails if any test fails or logs an error. Sessions may run exactly that command, the only way they run Godot. `--quick` alone is unchanged, because the implement job runs it before Claude starts. The daily build doesn't run the tests yet: a first run passed 5 of 17, so making them pass is first in the queue, and the bot asks the owner to make the daily build run them once they all pass.

## 2026-10-17: The bot app's Client ID

**Decided by:** owner. The workflows mint the bot's token with `client-id: Iv23lirdyRvc0KC6625s` (public, from the app's settings page) instead of the deprecated `app-id`. The `BOT_APP_ID` secret is no longer read; it can stay until `setup.sh` stops checking for it.

## 2026-10-17: Opening web links, narrowly

**Decided by:** owner.
**Context:** The feedback button and the main menu's Contribute button need `OS.shell_open`, a banned API.
**Decision:** it is allowed in one file only, `core/links/links.gd` (bot-maintained, closed to outside PRs). There the rules check allows `OS.shell_open(URLS[key])` and nothing else, requires `URLS` to be a `const`, refuses any change to it at run time, and refuses any address that isn't the project's own (`github.com/peterdk31/spellmerge`, `peterdk31.github.io/spellmerge`, `peterdk31.itch.io/spellmerge`). Everywhere else, and for every other process call, the ban stays.

## 2026-10-17: HUD theme and player panels (M1 part 18)

**Decided by:** Claude (details the plan left open).

- **One new event, `player_stats_changed(player, health, max_health, mana, max_mana)`, sender `player`.** The HUD may only show what events say, and no event carried health or mana. It is sent when a wizard appears, on a health change, and when mana crosses a whole number (about 10 a second per regenerating player, none when nothing changes). Rejected: the HUD reading the wizard nodes (a direct call into gameplay), and a per-frame event.
- **"Downed" is derived from health 0**, not from `player_downed`/`player_revived`, so a restart that builds new full-health wizards clears it with no extra event.
- **The panels are an autoload scene `Hud`** (a `CanvasLayer`), so neither `flow` nor the menu has to add them and areas keep not calling each other. They show for a joined player after `room_entered`. Rejected: `flow` adding the HUD to its world.
- **The theme is the project theme** (`gui/theme/custom`), so every control, including the main menu, uses it. Player colours are theme type variations, not per-control overrides. Rejected: a theme set on each scene root.
- **No information by colour alone:** the panel says "P1".."P4", "HP"/"MP" with numbers, and the words "DOWN" and "MENU". Health uses Fire and mana Spark from `docs/STYLE.md`; no new colour was invented.
- **The corner panels are display-only.** They take no input; "on `core/ui_focus`" means they show `UIFocus.opened`/`closed` as the "MENU" word. The overlay that uses `UIFocus` to take input is part 19.

## 2026-10-17: Co-op (M1 part 17)

**Decided by:** Claude (details the task left open).

- **`flow` adds and removes the wizards; `coop` only announces.** Coop turns `device_joined` / `device_left` into `player_joined` / `player_left` (once per real change) and flow, which owns the world and the wizards, listens. This keeps "areas never call each other"; the events table lists `flow` as a listener of both.
- **Friendly fire lives in `core/projectiles` as a flag** (`Projectiles.friendly_fire`, default off, set by `Coop.set_friendly_fire`), because spells (content) fix their own hit mask and must not read gameplay settings. A player's shot spawned while it is on also hits `LAYER_PLAYER`; targets carry an `owner` (`add_target(..., owner)`, set by `combat`) so a wizard is never hit by its own shot. Damage is the same pipeline as any hit. In memory only until `core/save`.
- **Camera:** `coop` drives the world's `Camera2D` (found after `room_entered`): centre of all wizards' bounding box, zoom out (never in past 1, never out past 0.5) until all fit with 48 px of margin, easing at 6 per second. Downed wizards count, so a body can be found. `flow` sets the camera's limits to the room, and `coop` makes the zoom agree with them: the zoom never goes below `max(view.x / room.x, view.y / room.y)` and the centre is clamped the way Godot does, so the shot never shows empty space. In `arena_01` (640×384 for a 640×360 view) that means no zoom-out at all: the view is pushed in from the edges instead (a wizard at the top or bottom wall may sit up to 12 px from the view's edge). Padding the limits was rejected, since it would show void beyond the walls. Each frame the zoom is also lowered, if needed, so everyone is inside a view centred where the camera is now, not where it is heading (zooming out is immediate, zooming in is eased). Mid-run joiners spawn on the free spawn farthest from enemies and wizards and are invulnerable for `Player.JOIN_PROTECTION` (2 s). Shake only touches `offset`, so the two do not clash.
- **Coop no longer listens to `player_downed`** (the old README line): the camera fits downed wizards too, so there was nothing to do with it. It listens to `room_entered` instead.
- **Revive is not part of this task** and stays in the backlog (nothing calls `Player.revive` yet).
- A player leaving when the only standing wizard remains while the rest are down starts flow's restart timer; one joining while all are down cancels it. With nobody left the run just waits.

## 2026-10-17: Feel (M1 part 16)

**Decided by:** Claude (details the task left open).

- **One autoload, `Feel`, listening to three events and sending none.** It cannot change damage: it never calls `Combat` or a wizard (tested by running the same hits with and without it).
- **Hit-stop is `Engine.time_scale`** dropped to 0.05 (not 0, so physics still steps) for 0.04 s on a hit and 0.07 s on a death or a downed wizard, counted in real time from `Time.get_ticks_usec()` (not delta divided by the time scale, so other uses of `time_scale` cannot skew it; `Feel` resets it to 1.0 when it leaves the tree). The longest stop wins, so four players hitting in one frame never stack. Same numbers for every player: the event's player index is ignored.
- **Hit-stop rest (review fix):** after a plain hit's stop, plain hits cannot stop the game again for 0.15 s (`hit_stop_rest`), so a four-player bolt fight spends about 21% of real time slowed, not most of it (a test holds it under 30%). Deaths and downed wizards ignore the rest: they are rarer and are the moments worth a punch.
- **Particle limit:** `PARTICLE_LIMIT = 48` live hit particles in total, as 6 pooled `CPUParticles2D` bursts of 8 (`core/pools`). With the pool empty, a hit burst is skipped (degrade by dropping, like the projectile cap), but a death takes over the burst closest to ending. A killing blow sends `damage_dealt` then `enemy_died` at one spot: the death upgrades the hit's burst (1.6x speed, life and size) and cuts the hit sound, so a kill costs one slot and one sound and looks bigger than a hit. The downed event carries no position, so a downed wizard gets stop, shake and sound but no burst.
- **Where bursts live (review fix):** under the `Feel` node, `top_level` so they sit in world space. Not under the current scene: `Flow` frees the world on Play and on every restart, which would have killed the pool.
- **Shake** is a trauma value (0–1, squared into pixels, 6 px at most) on the current `Camera2D`'s `offset` (looked up again whenever a shake starts; the old camera is put back at rest), so the co-op camera (part 17) can move the camera's position freely. The setting `Feel.shake_enabled` is kept in memory only: the hard rules ban file loading and saving calls, so saving it waits for `core/save`, and so does the settings screen that flips it. Hit-stop is not part of that setting.
- **Sounds:** `hit`, `enemy_death` and `player_downed` by id from the registry, 8 voices round-robin, silent on `null`. `player_downed` was added to "Audio needs" in the backlog.
- **Presets** are `FeelPreset` resources in `gameplay/feel/presets/`; the first is `punchy.tres` (the script's defaults). Feel also sets `Projectiles.texture` to `art/vfx/fire_bolt.svg` if nothing set it (DECISIONS part 13 left this to feel).
- Values are first guesses to tune at C1. No Godot binary in the session: the test has not run.

## 2026-10-17: Arena glue (M1 part 15)

**Decided by:** Claude (details the task left open).

- **Flow builds the whole world and makes it the current scene.** The menu only sends `play_requested(0)`; flow adds one `Arena` node (room scene, `Camera2D`, wizards, enemies), makes it `current_scene` and removes the menu at once. A restart removes the old world from the tree at once (so its enemies leave `Combat` in the same frame) and frees it.
- **Wizards: one per player slot with a device.** If Play is pressed by the mouse and slot 0 is free, the keyboard joins as P1. A request from another slot with nobody joined starts nothing (with a warning). Joining mid-run is `coop`'s job (part 17).
- **Flow reaches `Combat`, `Projectiles` and `PlayerInput` through the autoload nodes**, as the AI does, since `core/events` has no event for "register this wizard"; it sets bounds for the projectiles and clears them on a run. Flow preloads `content/wizard/base/wizard.tscn` by a literal path: the wizard has no registry resource yet. The room, the enemy and the bolt come from the registry by id (`arena_01`, `ember_imp`, `bolt`).
- **The wave:** 8 imps at the six enemy spawns (two spawns used twice, the repeat 14 px along the diagonal), a constant in `flow.gd`. 8 × 20 health is 32 bolt hits; it is a first guess for C1.
- **Restart after 2 seconds** from the last wizard going down (`RESTART_DELAY`, under the 3 s limit); a revive cancels it; a cleared room never restarts. After `room_cleared` nothing happens yet (no reward or next room until M3); listed in the flow README.
- **A second `play_requested` during a run is ignored.** `stop_run()` returns flow to idle (tests; later the run area).

## 2026-10-17: Work resumes when a usage limit resets; late scheduled runs don't repeat

**Decided by:** owner.
**Context:** On 2026-10-17 a usage limit stopped development at 03:28 with a reset at 05:10, but GitHub's hourly schedule didn't fire again until hours later, so no session ran. The same night the daily run was started by the catch-up at 04:55, and GitHub then fired the 03:00 schedule at 07:35, so it built and released twice.
**Decision:** when the develop gate or a session's finish job sees a back-off, it starts `resume.yml`, which waits until just after the reset and starts `develop`. `daily.yml` and `weekly.yml` skip a scheduled run when another run since their due time is running or succeeded.
**Consequence:** work stops only as long as the limit lasts. A waiting `resume` run shows in the Actions list; a newer request replaces it.

## 2026-10-17: The room (M1 part 14)

**Decided by:** Claude (details the task left open).

- The room is built from repeated `Sprite2D` tiles plus one `StaticBody2D`, not a `TileMapLayer`: a tilemap needs a `TileSet` resource and packed cell data that cannot be written or checked without Godot in a session. Rejected: a hand-encoded tilemap, which would likely fail to load unseen. Revisit when a tileset resource exists (M3).
- 20×12 tiles (640×384 px): the camera frame is 640×360, and part 17's shared camera zooms out for four players. Six single-tile pillars give cover. The two centre pillars touch at a corner and form a diagonal block; the test flood-fills the 32 px grid to check that every spawn can be reached (it does not measure lane widths).
- Spawn positions live twice, as `Marker2D` nodes in the scene and as arrays in the `.tres` (the base class fields); the test checks they match. `flow` reads the `.tres`.
- One entry (bottom, next to the players) and one exit (top) door; the doors are markers only, closed doors are the wall. Door logic is M3.

## 2026-10-17: The fire bolt (M1 part 13)

**Decided by:** Claude (details the task left open).

- **`bolt.tres` uses `bolt.gd`, a script that extends `SpellBase`,** so everyone who loads it gets a `SpellBase`, but the firing code is content, not `core/base`. It reaches only `Projectiles` (a `core/` autoload; tests set `projectiles`), looked up once and kept. **Content never calls `gameplay/`** (the spells and combat READMEs agree): the bolt answers `hit_tag()`, `hit_damage()` and `hit_knockback()` (new `SpellBase` methods), and `Combat` reads them through `core/registry` the first time it hears `spell_cast` for that spell id and sets the hit profile itself. A spell that is cast without `spell_cast` (nothing sends it today but the player) has no profile, so its hits do nothing; the test covers this. `_fire()` now returns `bool`; `false` (no projectile manager, or `spawn` returned -1) makes `cast()` return `REFUSED` with no mana taken and no cooldown started.
- **No separate `core/pools` pool for shots.** The projectile manager's packed arrays are already a fixed-size pool (a free-slot list, no allocation per spawn), so wrapping it in `Pool` would add a layer for nothing. `Pool` stays for node-based things (hit sparks, part 16).
- **The tag is `BOLT_TAG = 1`** (the imp's attack tags start at 1000). The hit profile is set by `Combat` on the first `spell_cast` of the bolt, with knockback 120 px/s. The values (5 mana, 0.35 s cooldown, 5 damage, 220 px/s, 1.2 s) are first guesses for C1 tuning: four bolts kill a 20-health imp.
- **The "no field reads" test is a text scan** of every `.gd` outside `content/spells/`, `core/base/` and `test_*.gd` files (tests build fixtures by setting fields): a variable named like a spell followed by a field name, or `.mana_cost`, `.cooldown`, `.lifetime`, `.display_name`. It is a heuristic; a self-check in the test makes sure the scanner still catches what it should.
- The bolt has no texture yet: the projectile manager draws tinted quads. Setting `Projectiles.texture` to `art/vfx/fire_bolt.svg` belongs to feel (part 16), where `docs/NEXT.md` lists it.
- **Cooldowns are on the shared resource.** `Registry` hands out one `bolt.tres`, so all holders share its cooldowns (kept per player index, so four players do not clash). `flow` (part 15) calls `reset_cooldowns()` on a new run. A restarted `Combat` simply learns the profile again on the next `spell_cast`. A test shows two holders of the shared resource block each other until `reset_cooldowns()`.
- `Registry` finds the bolt as `spells` / `bolt` (a folder is a direct child of `content/`; the `.tres` may be at any depth below); the test checks it.

## 2026-10-17: The enemy and its AI (M1 part 12)

**Decided by:** Claude (details the task left open).

- **`ai.gd` is the script on the enemy scene's root** (a `CharacterBody2D`), as the wizard scene does with `player.gd`; `gameplay/` stays script-only. The spawner sets `data` (the `EnemyBase`) before adding the node. The scene does not point back to the `.tres` (that would be a resource cycle), so speed and health come from `data` and the attack numbers are exports on the root. The exports are scene-level, set in the enemy's `.tscn`, not per spawn.
- **The attack is a shot**, not a lunge: Combat's contact damage is always on, so it cannot be telegraphed. The imp has `contact_damage = 0` and its damage is `attack_damage` (an export in `ai.gd`) through a hit profile for the enemy's `attack_tag`, set by the AI in `_ready` as 1000 plus a number from `data.id` and `attack_damage` (so another enemy type, or the same one with another damage, does not overwrite the profile; two ids could still collide by chance, which Combat's tag-changed warning would show, and the spawner (part 15) may take over the tags). The shot belongs to `Events.NO_PLAYER` and uses `LAYER_PLAYER`. The telegraph is a 0.75 s windup standing still, a flash and a `Telegraph` line as long as the shot's real reach (`attack_speed * attack_lifetime`) that grows wider and brighter with progress (2 to 4 px, alpha 0.5 to 1; placeholders, to check at 640×360 with four players in the part 25 playtest); the aim is locked at the start, so stepping aside works. First guesses, for the C1 tuning.
- **The AI talks to `Combat` and `Projectiles` through the autoload nodes** (found by path, replaceable in tests, as `player.gd` does with `Events`), not through events: `core/events` has no event for "register this enemy" or "spawn a shot", and the part 11 design already has the mover add `consume_knockback_step`. Revisit if a spawner (`flow`, part 15) should register enemies instead. Leaving the tree unregisters the enemy from `Combat` (so a room swap leaves no hidden target); it is not registered again on re-entry, so spawn a new enemy instead.
- **Targets:** every node in the `players` group (`player.gd` joins it in `_ready`), or an explicit `targets` list; the nearest one that is not downed, rechecked every 0.5 s (staggered by instance id), at once when the current target is lost, and at once on `player_downed` only for enemies whose target was that player (the others keep their stagger, so a death is not a one-frame spike). With no target (all downed, nobody joined) it still looks only every 0.5 s. The group read allocates a small array twice a second per enemy; if 200 enemies show it in the part 22 probe, share one list refreshed by `flow`.
- Combat's `register_player` now also adds the wizard as a projectile target (see the part 11 notes).

## 2026-10-17: Combat (M1 part 11)

**Decided by:** Claude (details the task left open).

- **Combat owns the tag table.** The earlier note said the spawner keeps the table from `tag` to damage and `combat` looks it up there. Combat keeps the table (changed in part 13: the bolt does not call `Combat`; Combat fills the table from the spell's `hit_tag()` etc. after `spell_cast`, see "The fire bolt"). Tag 0 stays "no tag".
- **Enemy health lives in combat,** in packed rows, not on the enemy node: `register_enemy(node, health, hurt_radius, contact_damage)`; the AI (part 12) and the enemy scene hold no health. Death sends `enemy_died` and frees the node.
- **Wizards decide their own damage.** Combat sends `damage_dealt` and the wizard takes it. It skips the event (no hit-stop or shake for nothing) when the wizard answers `is_invulnerable()` or `is_downed()`, found by `has_method` on registered wizard nodes. Wizards are not knocked back in M1; the player owns its movement.
- **Contact damage** is a distance check per enemy row and registered wizard (4 at most), once per `CONTACT_COOLDOWN` (1 s) per wizard, since wizards have no invulnerability after a hit. First guesses, for the C1 tuning.
- `damage_dealt` carries the requested amount, not the health actually removed (overkill is not trimmed).
- Knockback speed is `direction * strength` (a hit overwrites any earlier push) and falls by `KNOCKBACK_DECAY` per second; Combat never moves the enemy: it only keeps the velocity (`get_knockback`), and the node that moves the enemy (AI or enemy base, part 12) adds `consume_knockback_step(enemy, delta)` to its own `move_and_slide()` each physics frame, which also fades it. That way walls and parent transforms are respected and only one node owns the enemy's movement.
- **(Part 12 addition.)** `register_player` also makes the wizard a projectile target on `LAYER_PLAYER` (and `unregister_player` removes it); without that an enemy shot could never hit a wizard. Part 11 left this out.
- Re-registering an enemy also updates its projectile target radius. A freed enemy is dropped in `step()`; the projectile manager prunes its own freed targets (tested). Contact hits are sent after the enemy loop and `hit()` re-finds its row after `damage_dealt`, so listeners may change registrations. A tag whose profile changes is replaced with a warning; the spawner picks the tags.

## 2026-10-17: Player health, mana, downed and cast (M1 part 10)

**Decided by:** Claude (details the task left open).

- **One cast method, no fields read.** `SpellBase.cast(player, origin, direction, mana)` returns the mana spent, or `REFUSED` (-1) if it is cooling down or too costly; the player subtracts what it returns. The spell keeps its own cooldown per player index (a 4-slot array), run by `tick(player, delta)` each step, so one spell resource can be shared by four players. The event id comes from the method `spell_id()`, not the field. Part 13 overrides `_fire()`; its test checks that nobody outside `content/spells/` and `core/base/` reads a field.
- **Cast is held, not tapped:** while `cast` is held the spell's cooldown sets the rate. A player with an overlay open is captured, so `cast` is hidden and nothing fires.
- **Numbers (placeholders to tune in part 25):** 100 health, 100 mana, 10 mana per second, 50 health after a revive. A downed wizard does not regenerate mana, cannot move, dodge or cast, and ignores later hits; its dodge and spell cooldowns freeze too. A revived wizard gets no invulnerability window (a hit on the same frame can down it again); `coop` (part 17) may add one. Hits during a dodge's invulnerability do nothing.
- **Revive is a method, `revive(reviver)`:** who revives and how (standing next to a body) belongs to `coop` (part 17). The player sends `player_revived`.
- **Damage:** the player listens to `damage_dealt` and takes it when `target` is itself; `combat` (part 11) decides when to send it.
- **Sound:** the `AudioStreamPlayer` is made once in `_ready()` (only inside the tree); the stream is looked up by id at each cast and `null` plays nothing. Only the silent path is tested (no `.ogg` can be made in a session).

## 2026-10-17: Placeholder art (M1 part 4)

**Decided by:** Claude (details the task left open).

- Four wizard files, one per player colour (`wizard_p1_idle.svg` to `wizard_p4_idle.svg`), not one file tinted in code: a tint multiplies colours, so the result would leave the palette. `wizard.tscn` lists the four textures in `textures` and `player.gd` shows `textures[index]` on `Sprite` in `_ready()`. The files differ only in the three ramp colours.
- Filtering off: Godot's texture importer has no filter option, so the `.import` files keep the defaults. Filtering is set by the project (`rendering/textures/canvas_textures/default_texture_filter=0`, nearest) and the wizard's `Sprite` also sets `texture_filter` to nearest. Size is exact because the SVG is 32×32 and `svg/scale` is 1.0.
- The `.import` files and their uids were written by hand (the session had no Godot, and the md5 in each `path` follows Godot's rule: the md5 of the `res://` path). Godot rewrites them if they differ.
- SVGs are written rect by rect, with outlines inside the grid, as `docs/STYLE.md` asks. The session could not run scripts or render, so the pictures were checked by reading the rects, not by eye; the no-overlap rule and the look (a screenshot) are still unchecked. The crypt floor uses the darkest stone as its base so it reads apart from the wall.
- The wizard staff carries a Spark gem (light source) and the imp uses only Fire, Bone and Spark, so no player colour appears on an enemy. The floor tile is flat; the wall tile has the lit and shaded edges.
- Sounds are not made here: `cast`, `hit` and `enemy_death` are under "Audio needs" in the backlog.

## 2026-10-17: Pools and the projectile manager (M1 part 7)

**Decided by:** Claude (details the task left open).

- **Pool:** GDScript has no generics, so a pool is typed by its factory Callable and the caller casts `acquire()`. It makes all objects up front and never grows: at capacity `acquire()` returns `null` and the caller degrades. A growing pool would allocate mid-frame, which the budgets forbid.
- **Projectiles are rows in packed arrays** (struct of arrays), simulated in `_physics_process` and drawn by one `MultiMeshInstance2D`, tinted by player colour (STYLE.md base colours; enemy shots Fire). A texture can be set later for the real bolt art.
- **Targets are registered, not searched for:** `add_target(node, radius, layer)`. The manager reads their positions each step into a grid of 64 px cells, so it depends on no gameplay class and `core/` keeps its dependency direction. Hit layers (`LAYER_ENEMY`, `LAYER_PLAYER`) let enemy shots hit players and player shots hit enemies, and a shot's owner can be `NO_PLAYER`. Friendly fire (part 17) means a player shot with `LAYER_PLAYER` in its mask.
- **Hits test the path, not the point:** each step's segment against the target circle. The grid cells searched are those the segment touches, widened by the shot's radius and the largest target radius, so neither fast shots nor big targets (bosses) are missed. Among the targets a segment touches, the nearest along the path is hit first and the event carries the closest point on the path. A piercing shot remembers its last 3 hit targets, so overlapping enemies are hit once each (a fourth overlapping one could be hit again; accepted).
- **The cap degrades by dropping, never by refusing:** at the cap, the oldest projectile of whoever owns the most is dropped. A refused shot would feel like a broken button; dropping the oldest of the richest means a player who floods the screen loses only their own old shots, and nobody is starved (pillar 2). The default cap is the PLAN budget per platform (1,000 on the web, 3,000 on desktop); `set_cap` changes it. Dropping is O(1): each owner has a list of its slots in spawn order, so a flooding player cannot cause a scan. Projectiles deliberately do not use `core/pools`: they are rows with their own slot free list, and `Pool` is for nodes and effects (enemies, damage numbers).
- **A hit carries an opaque `tag`:** `spawn(..., pierce, tag)` stores an int per projectile and `projectile_hit(player, target, position, tag)` sends it back unread (the event changed from part 1 for this). The manager still knows nothing about damage: the spawner (the bolt, part 13) keeps its own table from tag to damage and effects, and `combat` (part 11) looks the tag up there. An int, not a Variant, so it stays a packed array row. Default 0 means "no tag".
- **Piercing shots hit up to 3 targets per step** (`HIT_MEMORY`), nearest first, so a fast piercing shot through a crowd hits all of them; a shot that would pierce more than 3 targets in one step (very rare) hits the rest on later steps only if they are still on its path. It remembers the last 3 targets hit and forgets the oldest after that.
- **Draw cost is unmeasured.** `step` and `update_draw` loop over all slots in GDScript and `update_draw` writes the whole cap-sized buffer. Part 22 must time `spawn` at the cap and `update_draw` with a full cap before these caps are relied on; if slow, upload only the first `drawn` instances and lower the web cap.
- Removing a target or spawning a projectile inside a `projectile_hit` handler is safe: removal waits for the next step and new shots start moving on the next step.

## 2026-10-17: Per-player focus (M1 part 6)

**Decided by:** Claude (details the task left open).

- One autoload, `UIFocus`. A panel is opened for one player with an ordered list of controls; only that player's input moves it. It reads `PlayerInput` by index, never `Input`, and never calls `grab_focus`, so Godot's single global focus plays no part and the mouse cannot steal a panel.
- Navigation uses the gameplay actions, no new ones: up/left and down/right step through the controls (wrapping), `cast` activates, `dodge` cancels. Cancel only sends `cancelled`; the panel decides whether to close. The `overlay` action that opens panels is handled by the overlay (M1 part 19).
- It detects presses with a press counter added to `PlayerInput` (`get_press_count`), compared with the value seen at the last poll. A first version compared `is_action_pressed` between polls and lost a tap released within one frame (bots do that with `send_virtual`); `is_action_just_pressed` is tied to one frame and also needs the caller in `_process`. The counter loses nothing and works from any call. Presses from before the panel opened (the button that opened it) are ignored.
- An open panel captures its owner's gameplay input: `PlayerInput.set_captured(player, true)` makes `get_move`, `get_strength`, `is_action_pressed` and `is_action_just_pressed` answer "nothing" for move, `cast` and `dodge` (not `overlay`, so the overlay can close itself). Gameplay needs no check, nothing is paused, and the other players are untouched. The alternative, separate `ui_*` actions, would need a second binding set for every device. Capture ends on close and when the device leaves.
- Focus is re-checked every frame and before each activation: a control that was disabled, hidden (also through a hidden parent, when in the tree) or freed loses focus to the next usable one, and the press that found it stale activates nothing. `focus_mode` is ignored, since Godot's focus is never used. A panel opens only for a joined player, and opening over an open panel sends `closed` then `opened`.
- Results are signals with the player first (`opened`, `closed`, `focus_changed`, `activated`, `cancelled`); widgets check that the player is their owner. A panel closes when its player's device leaves. Nothing is paused.

## 2026-10-17: Input devices and join (M1 part 5)

**Decided by:** Claude (details the task left open).

- One autoload, `PlayerInput`, routes every input event by device to a player index and keeps per-player action state. Gameplay asks it by index and never reads `Input` directly, so one global action map serves all four players.
- A gamepad takes the lowest free index. The keyboard and mouse count as one device that may only take index 0, matching "P1 keyboard or gamepad, P2–P4 gamepads"; if a gamepad already holds P1, the keyboard cannot join.
- `join` (Enter, Space, gamepad A or Start) and `leave` (Backspace, gamepad Back) are actions. An unplugged gamepad leaves; plugging one in never joins without a button press.
- Bots use virtual devices, ids 1000 + index. They send `InputEventAction`s through the same `handle_event` path as real events, so bot tests exercise the real input code.
- The device events are `device_joined(player, device)` and `device_left(player, device)`, sent by `core/input`; `coop` (M1 part 17) turns them into `player_joined` and `player_left`.

## 2026-10-17: The provisional palette and style rules (M1 part 3)

**Decided by:** Claude (details the plan left open).
**Decision:** `docs/STYLE.md` fixes a 31-colour palette: outline `#14121f` plus ten 3-shade materials (stone, bone, fire, spark, wood, skin and one ramp per player: blue, rose, green, purple). Player ramps are used only for players. Animations are horizontal strips of 32 px frames with fixed counts per animation type. Placeholder SVGs use only `<rect>`s with whole-number coordinates, palette fills and `shape-rendering="crispEdges"`.
**Reason:** Part 4 and outside Art PRs need concrete values to check against. Rects-only SVG guarantees no antialiasing. The style is provisional: the M2 art direction call may replace it (the plan already says so), and then the palette changes in one file.

## 2026-10-17: Event lists in the READMEs are final (M1 part 2)

**Decided by:** Claude (details the plan left open).
**Decision:** `core/events/events.gd` is the source of truth for event names and senders. The "Events at a glance" table in `gameplay/README.md` and every area's event list match it, and the "provisional" marks are gone. `play_requested` (sender: HUD, listener: `flow`) joins the HUD's player-intent requests, so the HUD sends five events. This completes the 2026-10-16 entry "Entry script names, event names and file types", which expected the marks to go once the bus was built.
**Reason:** The bus exists, so the lists can be checked against code and later parts can rely on the names.

## 2026-10-16: Event signatures and base class shapes (M1 part 1)

**Decided by:** Claude (details the plan left open).
**Decision:** `Events` signals take the player index as an `int` named `player`, first. Events with no player (`run_started(player_count)`, `run_ended(victory)`, `room_entered(room_id)`, `room_cleared(room_id)`, `difficulty_changed(level)`, `reward_rolled(reward_ids)`, `unlock_gained(unlock_id)`, `currency_changed(currency_id, amount)`) don't. `damage_dealt`, `status_applied`, `enemy_died` and `projectile_hit` name the source player, or `Events.NO_PLAYER` (-1) when an enemy is the source. `door_voted` and `reward_taken` carry the voting or picking player, as the results of the matching request events. Base resources use `PackedVector2Array` positions for spawns and doors and have only the M1 fields, plus `id: StringName` and `demo: bool`.
**Reason:** Typed signals with a fixed shape let tests and later parts rely on them; -1 avoids a fake player index for enemy damage. M2 and M3 may change the base fields and event arguments; part 2 and those milestones update the docs with them.

## 2026-10-16: M1 design choices the plan left open

**Decided by:** Claude (details the plan left open), in `docs/milestones/M1-core-loop.md`.
**Decision:**
- The ten `gameplay/` sub-areas, `content/spells` and `content/wizard` don't allow `.tscn` (`hud/`, `content/enemies` and `content/rooms` do), so M1 scenes live with their content (`content/wizard/base`, which gets `.tscn` in its README, `content/enemies`, `content/rooms`, `hud/`); `gameplay/` stays script-only and gets scenes through `core/registry`. Rejected: allowing `.tscn` in `gameplay/`, because the Areas table in `docs/PLAN.md` lists only `.gd` and `.tres` for it. The allowed-files paragraph of `gameplay/README.md`, which left this open for M1, is rewritten to say so (part 9).
- The main menu starts the arena only through a new HUD intent event, `play_requested(player)`, that `flow` listens to; areas never call each other.
- Sounds are the Audio contributors' job. Gameplay code asks `core/registry` for a sound by id; the registry (the one place that loads by a computed path) returns `null` for a missing one and nothing plays, so a missing sound is silent and the literal-path rule holds.
- M1 is 25 parts: input, the player, combat with the enemy, and the HUD are each split in two so a task fits one session.
- The player and bots only call one cast method and read no spell fields, so M2 can replace the fire bolt.
- The registry scans folders at start; the build-time manifest waits until content is large.
- The one spell is a fire bolt on a small base class that M2 replaces; nothing else may depend on its fields.
- A minimal slice of `flow` (load the room, spawn the wave, restart) is built in M1 instead of M3, so the loop is playable. M3 replaces it. There is no pause menu in M1.
- Placeholder art is hand-written SVG, since sessions have no image tools. The web 4-bot run and the Style Guide page and kit zip need small owner-only changes in `ci/smbot/`, which their tasks file in `docs/BACKLOG.md`.

**Reason:** each keeps M1 small, inside the path rules, and playable for the first checkpoint.

## 2026-10-16: M1 starts before M0's dry runs

**Decided by:** owner.
**Context:** All seven M0 parts are built, and the bot now develops, reviews and merges its own PRs. M0's done-when also asks for 3 daily releases in a row and 15 dry runs. GitHub hasn't fired the daily schedule yet (the catch-up in `develop.yml` covers it from now on), and most dry runs need a second GitHub account or a deliberately broken build, so the bot's queue was empty with nothing it could do.
**Decision:** M0 is closed early and M1 starts now. The dry runs and the 3-release streak are not dropped: they carry into M1 and are part of M1's done-when, so M1 can't finish without them. The first M1 task is the M1 design document, which goes through the normal review before any M1 code. Art and Audio open for PRs with M1, as planned.
**Consequence:** the pipeline's end-to-end checks (rule-breaking PRs auto-closed, CLA, votes, quarantine, kill switch, token alarm, revert of a broken build) are still unproven while M1 is built and Art and Audio take outside PRs. The owner runs them during M1.

## 2026-10-16: llms.txt uses relative links and lists maintainer prompts as Optional

**Decided by:** Claude (details the plan left open).
**Context:** The llms.txt convention expects absolute URLs, but the repo may be forked or renamed, and agents read it from a checkout.
**Decision:** `llms.txt` at the repo root uses repo-relative paths. The `.github/maintainer/` prompts go under "Optional" since contributors rarely need them. Any PR that adds or removes a doc updates `llms.txt`.

## 2026-10-16: Entry script names, event names and file types in the code-area READMEs

**Decided by:** Claude (details the plan left open).
**Context:** docs/PLAN.md gives `combat/combat.gd` as an example entry script but doesn't list the rest, and the event bus doesn't exist yet.
**Decision:** Each gameplay sub-area's entry script is `gameplay/<area>/<area>.gd`. `core/events` owns the event definitions; each README only lists the events its area sends (each event has one sender) and listens to, marked **provisional** until the event bus is built in M1, when the READMEs are updated. The HUD's sent events are the player-intent requests from "The HUD sends player-intent events": `build_change_requested` (listener `player`), `reward_pick_requested` (`rewards`), `door_vote_requested` (`flow`) and `pause_requested` (`run`), all in the table in `gameplay/README.md`. Text shared by all sub-areas lives in `gameplay/README.md`. Gameplay PRs allow `.gd` and `.tres` only, as in the plan's Areas table. `core/` services get their entry scripts and sections when built.

## 2026-10-16: The bot can merge its own approved PRs

**Decided by:** owner.
**Context:** The `main` ruleset had "Require approval of the most recent reviewable push", which needs an approving review from someone other than the last pusher. The bot pushes its own PRs and can't approve them, and the merge script never approves anything, so GitHub refused every automated merge ("the base branch policy prohibits the merge") and every bot PR waited for the owner.
**Decision:** `require_last_push_approval` is off (`ci/settings/rulesets/main.json`, and on GitHub). Owner-only paths still need the owner's code-owner review, and the merge script still merges only the exact reviewed commit, after the required checks and the hard rules pass.
**Consequence:** the bot's PRs merge the same day, as the plan intends. What contributor PRs may change is unaffected: the hard rules and the code-owner review still apply.

## 2026-10-16: develop also runs on every push to main

**Decided by:** owner.
**Context:** GitHub never fired this repository's schedule: no scheduled run of any workflow on its first day, through two cron changes and turning the workflow off and on. When a session chain stops (an error, a usage limit, an empty queue), nothing started it again.
**Decision:** a push to `main` (any merge, by the bot or the owner) runs a small `kick` job in `develop.yml`. If no develop run is running or queued, it starts one with `workflow_dispatch`; otherwise the running chain carries on by itself. The kick job runs no Claude step, because `claude-code-action` doesn't accept `push` events, and it sits outside the `develop` concurrency group, so it never waits behind a session. The hourly schedule stays for when GitHub does fire it.

## 2026-10-16: Sessions don't wait for each other or for the owner

**Decided by:** owner.
**Context:** The next session started only after a merge, and only within 2 hours of the first. Any PR that didn't merge (a failed review, a blocked task, a merge GitHub refused) ended the chain, and work waited for the next hourly check. A stuck task also stayed at the top of the queue, so the next session tried it again.
**Decision:**
- When a session ends, the next one starts right away if the session made progress (it merged, opened or updated a PR, or reported the task blocked), the budget allows it, and there is a task. There is no time cap; the pacing budget limits usage. The chain stops on an error, a usage limit, nothing to do, or paused merging, and the hourly check starts it again.
- A task that can't move without someone else is parked in the state's `task_failures` and skipped, so the next task goes first: for 7 days when it failed review twice or was reported blocked, and for 1 day when its approved PR wasn't merged. Afterwards it is picked up again, and its open PR is continued.
**Consequence:** Work only waits on the owner for things only the owner can do, and even then other tasks go ahead. A task that failed review once is still retried straight away, with the review's problems.

## 2026-10-16: The HUD sends player-intent events

**Decided by:** owner.
**Context:** The plan said "The HUD only listens." But the spell builder, reward picks, door votes and the pause menu are all HUD scenes whose choices must reach gameplay. With a listen-only HUD, that input would have to go through direct calls into gameplay, which principle 2 forbids.
**Decision:** The HUD may send events, but only player-intent events: a request carrying the player index (0–3), such as a builder change, a reward pick, a door vote or opening the pause menu. Gameplay owns all state. It checks each request, applies it or refuses it, and announces the result as a normal state event. The HUD shows only what those state events say, never its own guess of the outcome. It still never calls gameplay directly, and other areas never call into the HUD.
**Consequence:** Plan principle 2 now says this. Event names are settled when the event bus is built in M1; intent events are named as requests, so they can't be mistaken for state events.

## 2026-10-16: Content READMEs name no field or file layout before the example exists

**Decided by:** Claude, within the plan.
**Decision:** The content area READMEs describe the contract as "the base class (arrives in milestone X)" and point to an example that arrives with Claude's first content, instead of inventing field names. Sub-folder `.gitkeep` files (spells, wizard, story) stay because those sub-folders have no README.
**Reason:** The base classes don't exist yet; documenting invented names would contradict the code later. Each README gets the real example path when its area opens.

## 2026-10-16: Claude never holds a write token where it has a shell

**Decided by:** Claude, after reviewing the session design.
**Context:** The implementing and revising sessions can effectively run code: through git, file commands, or Godot running scripts they wrote. If a prompt injection ever reached them (say, from a merged contribution's comments), a write token on that runner could be stolen and used to merge.
**Decision:**
- Those sessions get a read-only app token and commit only locally. Their commits leave the runner as a git bundle, which is plain data.
- A `publish` job on a fresh runner fetches the bundle into a clean checkout of `main` (with git hooks disabled), pushes only to a `claude/...` branch, and opens or updates the PR from Claude's structured output. It also records usage and posts `/ask` answers, only on issues where the owner asked.
- Claude is also denied edits under `.git/`, `.github/`, `ci/` and `tools/`, and gets only specific `git` subcommands.
- Sessions without shell or file-writing tools (rating, review, digest) still mint a write token after Claude finishes, because they can't run code.
**Residual risk:** a session could still leak its read-only token or its Claude token over the network. The next hardening step would be an egress firewall on those runners (see `docs/BACKLOG.md`).

## 2026-10-16: How the weekly planning run works

**Decided by:** Claude, within the plan.

- **`weekly.yml`** runs on Sundays at 06:00 UTC, in the same concurrency group as development, so the two never overlap.
- **Untrusted community text** (Discussions, spell ideas, bug reports) is read only by a digest session with read-only tools (`Read`, `Glob`, `Grep`; no shell) and no write token. Its structured output (verdicts, short replies, neutral bug restatements) is all the planning session sees, and only as data.
- **Replies to ideas** are posted by script with the workflow token, because the bot app has no Discussions permission and the plan keeps it to three. They are limited to about 1,200 characters, with no @mentions and no links outside this repository.
- **The planning session** is a normal work session (`session.yml`, mode `plan`), with the same critique, revision, final review and scripted merge as development. It edits the plan files, and writes the next milestone's design once the current milestone is done. Its structured output becomes the devlog post (Discussions, Announcements), contributor task issues (the fixed template with a "Brief for your AI", at most 10 open per area), owner issues (milestone start, checkpoints) and, from M1 on, the playtest of the week.
- **`session.yml`** holds the implement, critique, revise, final review, merge and finish chain for both `develop.yml` and `weekly.yml`.

## 2026-10-16: How the contribution pipeline works

**Decided by:** Claude, within the plan and the owner's CLA decision.

- **Triage** (daily, script): the hard rules are re-run from `main` against each PR head, with no PR code run. Closing comments list rule, file, line and fix. After 2 closed PRs in a day, an author's further PRs that day are closed. Unsigned authors get one CLA reminder, and the PR closes after 7 days. Area and skill labels come from the changed paths.
- **CLA records:** new signatures go into `docs/cla-signatures.json` through an `automated` bot PR that the merge step merges after checks. `automated` PRs may only change that file, or, for a quarantine, the reported asset and the manifests.
- **Rating:** one fresh Claude session per PR (matrix job, at most 8 a day). It has read-only tools and a read-only token, and the PR's files are checked out without being run. A script holds Claude's decision to the plan's thresholds (merge needs an average of at least 3.5 and no criterion below 2) and posts the comment, with a marker recording the rated SHA. A push means a new rating.
- **Merging:** the rated SHA must still be the head. Votable PRs (art, audio, gameplay, spells) wait for the vote, and the rating comment's vote line is updated daily. Candidates are test-merged in score order on a local `staging` branch, with the quick build after each, in a job without secrets. Then the merge script merges each one (checks, hard rules, `--match-head-commit`). On a conflict, the higher-rated PR wins and the other gets a rebase request.
- **Follow-ups:** the rating's fix-ups for merged PRs become the next development session's task, crediting the contributor. They are treated as suggestions, not instructions.
- **Broken daily build:** in a job without secrets, the day's merges are reverted newest first until the build passes. The culprits are then reverted on `main` through bot PRs, with a comment on each, and the daily run starts again once (no second round of reverts).
- **Claims:** `/claim` (anyone) assigns an issue labelled `now`, hourly. A reminder comes after 1 day and the claim is released after 2 days without a PR that mentions the issue.
- **No-git submissions:** issue forms for art, sound and writing. In a job without secrets, the file is downloaded only from GitHub's attachment hosts. PNGs are fully decoded and re-encoded (only pixels survive) and OGG is re-encoded by ffmpeg. Then a privileged job checks that both agreement boxes were ticked and that only the author edited the issue, and opens a bot PR (label `submission`, contributor as co-author) that is rated like any outside PR.
- **Copyright reports:** the reported asset is replaced by a same-size placeholder (audio is removed) and marked `quarantined` in the manifest, through an `automated` PR merged before the build. The owner is notified.
- **Votes:** the thresholds, window, eligibility phases and coordinated-vote discount are implemented in `ci/smbot/votes.py`. They are dormant while there are 0–2 active voters.

## 2026-10-16: How a development session works

**Decided by:** Claude, within the plan.

- **The flow:** `develop.yml` runs hourly, as implement, critique, revise, final review, merge, finish. Each Claude step runs in its own job on a fresh runner, so a session with a shell can't tamper with its reviewers or with the merge script. The merge job runs no AI and uses only scripts from a clean checkout of `main`.
- **Reviewers** (`review.yml`) get a read-only app token and read-only tools (`gh pr view/diff`, `git diff/log/show`). Their verdict is structured JSON. A PR merges only with `approve` and no blocker or major problems, and only after the required checks and the hard rules (re-run from `main`) pass, pinned to the reviewed commit.
- **The implementer** gets a curated command list: git, `gh pr`, `gh issue view/comment`, `tools/check.sh`, `ci/build/build.sh --quick`, and basic file commands. No `curl`, `wget`, Python, web fetch or web search. Secrets are scrubbed from its subprocesses where the action supports it. Prompts are in owner-only `.github/maintainer/`.
- **One critique and one revision round** per session. If the final review rejects, the PR stays open, and the next session sees the problems and continues. After the second failed attempt, the task is marked blocked, with the reason, and work moves on.
- **Continuous work:** after every session that made progress, the next one starts with `workflow_dispatch` while there is a task and budget (see "Sessions don't wait for each other or for the owner"). One session at a time, through the `develop` concurrency group.
- **Usage accounting** reads each step's execution file. Cache reads count a tenth, because they cost far less quota. A usage-limit message starts the back-off; a rejected token opens the token alarm, and the alarm closes after the next good run.

## 2026-10-16: How the control gate, owner commands and pacing work

**Decided by:** Claude, within the plan.

- **The gate:** every run starts with `ci/smbot/control.py`. Nothing runs unless the `AUTOMATION_ENABLED` variable is `true` and the Control panel (issue #4) allows it.
- **Panel trust:** values come from GitHub's edit history (each `userContentEdits` entry holds the full body of that revision), from the newest revision whose editor is the owner's numeric ID. A newer edit by anyone else is ignored and reported in the Daily log with a mention of the owner. If no owner revision exists, the gate fails closed.
- **Owner commands:** processed only by the hourly run, so two runs never act on one command. `/pause` pauses development and PR merging; releases continue, because only the kill switch stops releases. `/merge` refuses if the PR head was pushed after the command, judged by when GitHub started that commit's checks run, since commit dates can be faked. `/priority`, `/claude` and `/ask` are queued for the next Claude session.
- **Merge method:** squash for every merge, so each PR is one commit that one `git revert` undoes. The PR author stays the commit author.
- **State:** bookkeeping lives in `state.json` on the `automation-state` branch: token usage, back-off, processed commands and alarm issues. Writes use the file's SHA, so concurrent runs can't silently overwrite each other. It is never trusted for security decisions.
- **Pacing:** each run records its tokens for the Daily log. Runs are not gated by estimated quota: learning the window size from token counts disagreed with the real usage (it stopped at an estimated 104% when the account showed 69%), so `DEV_INTENSITY`, `WEEKLY_SHARE` and the 30% review cap were removed (2026-10-22). When Claude reports a usage limit, runs back off until the reset it names.
- **Schedule:** the hourly run starts at minute 35, away from the busy top of the hour.
- **Alarms:** each alarm is an issue labelled `alarm` that mentions the owner, opened once and closed automatically when the problem is resolved.
- The bot app's token is minted with `app-id`, which is deprecated in favour of `client-id` (see `docs/BACKLOG.md`).

## 2026-10-16: How builds and releases work

**Decided by:** Claude, within the plan.

- **Engine:** Godot 4.7.2-stable is pinned in `ci/build/godot.env`. The editor and export templates are checked against Godot's own SHA-512 sums. Only the checked downloads are cached; Godot is unpacked fresh on every run, so a tampered cache can't supply a binary.
- **Display:** a 640×360 viewport with integer scaling for crisp 32×32 pixel art, the Compatibility renderer, and a single-threaded web export (no special server headers needed on GitHub Pages or itch.io).
- **Smoke tests every build must pass:** the main scene in the editor, the exported Linux binary, and the exported web build in headless Chrome (`ci/smbot/websmoke.py`). Any engine or script error in the logs fails the build. Windows builds can't be run on Linux runners.
- **Channel:** decided before the build. A build that passes every test is stable unless an issue labelled `crash` or `blocker` is open, in which case it is nightly. Failing tests stop the release entirely. The benchmark joins the gate in M2.
- **Releases:** tagged `v0.YYYYMMDD` (`.2`, `.3` for extra runs on the same day). The assets are attached to a draft, which is then published, so the immutable release is complete. Nightlies are pre-releases; stable releases are marked latest.
- **Pages:** `/play/` serves the latest stable web build, `/nightly/` today's build, and `/` a landing page until the Contribute page exists.
- **itch.io:** pushed with butler 15.31.0 (hash-pinned) once the `ITCH_TARGET` variable (for example `peterdk31/spellmerge`) is set. Stable builds go to the `web`, `windows` and `linux` channels, nightlies to `*-nightly`.
- Only `core/` and `tests/` may load files dynamically. Tests are never exported.

## 2026-10-16: How the hard rules check works

**Decided by:** Claude, within the plan's rules.

- The check is `ci/smbot/rules.py`, Python 3 standard library only, so nothing is installed in jobs that hold secrets. `tools/check.sh` runs the same code locally.
- The owner-only paths are read from `.github/CODEOWNERS`, so there is one list. `addons/` was added, because the plan allows third-party addons only from the owner. `project.godot` and `export_presets.cfg` are bot-maintained, because they can register autoload scripts and change export settings.
- In CI, the rules and `ci/config.json` come from a checkout of `main`, never from the PR. The fixed identities (owner and bot, with numeric IDs) live in owner-only `ci/config.json` rather than in repository variables, because the check must also work for fork PRs.
- Untyped GDScript is a warning for outside contributors, since the review stance has Claude fix it after merging, and an error for the bot's own PRs. `project.godot` therefore reports untyped code as a warning, not an error, so a contributor's untyped code can't break the build.
- Size limits: 1 MB for `.png` and `.svg`, 5 MB for `.ogg`, as in the plan, and 1 MB for any other file, against abuse.
- Banned in `.gd`, `.tscn` and `.tres`, beyond the plan's list, because each can hide a banned call: calling singletons by name (`OS.call`, `Engine.get_singleton`), creating code at runtime (`GDScript.new`, `Expression`, `set_script`), `@tool` and editor plugins, and loading from a computed or `user://` path outside `core/`.
- Also rejected: symbolic links, submodules, binaries disguised as `.png` or `.ogg` (the magic bytes are checked), and SVGs with scripts or external links. Dependabot PRs may only change GitHub Actions files.
- The owner's own PRs get warnings only.
- The required `rules` status alone is never trusted, because a PR could rewrite `checks.yml`. Such a PR needs the owner's review, and the merge script re-runs the check from `main` before merging.

## 2026-10-16: Own CLA check instead of CLA Assistant; no lawyer review

**Decided by:** owner.
**Context:** cla-assistant.io keeps an OAuth token for the owner's account with `repo:status`, `write:repo_hook` and `gist` scopes on all repos. The owner account is what the whole security model protects.
**Decision:**
- `CLA.md` is adapted from the Apache Individual CLA v2.2, because a standard, widely used text is the safest choice without a lawyer.
- Contributors sign by commenting `I have read the CLA and I agree to it.` on their PR. For no-git submissions, the issue-form checkbox counts.
- The daily run records signatures in the bot-maintained `docs/cla-signatures.json` by numeric user ID and CLA version.
- Unsigned PRs get a how-to-sign comment and are closed only if still unsigned after 7 days, because a signature is only seen at the next daily run. They are never merged unsigned.
- The plan's "short lawyer review before selling" item is dropped entirely.

## 2026-10-16: PRs merge into `main`; `staging` is only a test branch

**Decided by:** owner.
**Context:** The plan had approved PRs merged into `staging`, with `main` fast-forwarded at release. A `main` ruleset that requires PRs and code-owner review would only allow that if the bot were a bypass actor, and then the bot could also push owner-only paths past CODEOWNERS.
**Decision:** The bot is never a bypass actor. The merge script merges candidates together on a throwaway `staging` branch and runs the content validators there, then merges each passing PR into `main` with `gh pr merge --match-head-commit <reviewed SHA>`. A broken daily build is fixed with revert PRs that the bot opens and merges itself. The release tags `main`.
**Consequence:** Every protection that GitHub enforces stays in place for the bot. `main` can briefly hold a merge that the daily smoke test later reverts, but releases are cut only from a tested `main`.

## 2026-10-16: Code license is GPL-3.0-or-later

**Decided by:** owner. Assets stay CC-BY-SA-4.0. Recorded in `REUSE.toml` and `LICENSE`.

## 2026-10-16: Setup, security docs and REUSE.toml are owner-only

**Decided by:** owner. `setup.sh`, `REUSE.toml`, `docs/SECURITY-CHECKLIST.md` and `docs/SETUP-APP.md` join the owner-only tier, so the bot can't weaken the security setup or its checklist, or change the license that every file falls under. Repository settings data lives in `ci/settings/`, which is owner-only already.

## 2026-10-16: The project board is user-owned and follows labels

**Decided by:** owner.
**Context:** GitHub Apps can't access projects owned by a personal account; that needs a classic personal access token, which the plan rules out.
**Decision:** The board stays under `peterdk31`. GitHub's built-in auto-add workflow fills it, and views filter by label. The bot keeps issue labels correct and never edits the board itself.

## 2026-10-16: Names chosen during setup

**Decided by:** Claude (details the plan left open).

- The protected environment is called `automation`. Its secrets are `BOT_APP_ID`, `BOT_APP_PRIVATE_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` and `BUTLER_API_KEY` (the name itch.io's `butler` tool reads).
- The repository variables are `AUTOMATION_ENABLED` (the kill switch), `OWNER_ID` (the owner's numeric user ID) and `BOT_LOGIN`.
- The required PR status check is the `checks.yml` job named `rules`, pinned to the GitHub Actions app.
- Only GitHub-owned actions plus `anthropics/claude-code-action` and `oven-sh/setup-bun` are allowed, all pinned by SHA (`ci/settings/allowed-actions.json`). claude-code-action uses `oven-sh/setup-bun` internally, pinned by SHA in its own `action.yml`.

## 2026-10-17: Registry shape (M1 part 8)

**Decided by:** Claude (details the plan left open).

- Sounds are found by file name under `audio/` only (any depth), as the task says; item sounds in `content/` are not indexed yet. A sound id is the file name without `.ogg`.
- Content is any `.tres` with an `id` below `content/<folder>/`, so M2 components need no registry change; the first in sorted path order wins a duplicate id.
- `demo_only` is a runtime variable set from the `demo` feature tag, so tests and the web build share one code path.
- `scan()` takes roots and a sound extension list so tests can use a fixture: a valid `.ogg` cannot be written in a session, so the fixture sound is an `AudioStreamWAV` `.tres`.

## 2026-10-17: Player movement and dodge (M1 part 9)

**Decided by:** Claude (details the plan left open).

- The wizard is a `CharacterBody2D` in floating mode on physics layer 2, colliding only with walls (layer 1): wizards walk through each other, so nobody blocks a teammate.
- The values are binary fractions (walk 90 px/s, dodge 220 px/s for 0.25 s, invulnerable the first 0.125 s, cooldown 0.625 s) so fixed-step tests add up exactly; tune them at C1.
- A dodge is detected with `get_press_count`, not `is_action_just_pressed`, so a tap released within a frame is not lost. A press made while the dodge is not ready, or while the player's input is captured by an overlay, is dropped, never queued.
- The scene was built before the part 4 sprite existed, with an empty `Sprite` node; part 4 fills it in rather than part 9 inventing art. Part 9 ran before part 4 because the session picked it; it needs no art, and parts 10–12 build on the script. Part 4's done-when now asks for a visible sprite per player index.
- Opening an overlay ends a dash in progress (cooldown stays), so a captured player is fully frozen.
- Physics layers: 1 walls, 2 players, 3 enemies, 4 projectiles and hit boxes (in the player README); `core/` is asked to name them in `project.godot`.

## 2026-10-17: The overlay (M1 part 19)

- The `overlay` action is read in `hud/panels/panels.gd` from `PlayerInput.get_press_count`, not by each overlay, so one place owns the toggle and a tap released within a frame is not lost. Everything after opening goes through `UIFocus`; the overlay ignores every signal that names another player.
- An overlay opens only for a joined player and only if that player's `UIFocus` panel is free, so it never replaces another panel. Closing comes from Resume, `dodge`, the `overlay` action, or the device leaving (`UIFocus` closes it).
- The stub button sends `build_change_requested(player, 0, &"stub")` and nothing else; the `player` area has no listener yet and will refuse unknown ids. The overlay never pauses and never changes `Engine.time_scale`.
- The overlay is made visible before `UIFocus.open`, because `UIFocus` only focuses controls that are shown; it is hidden again if opening fails.
- An overlay opens only while a room is active (`room_entered` seen, no `run_started`/`run_ended` since), so a press on the menu does nothing and the player's input is not captured there. It closes on `run_started`, `run_ended` and when its owner goes down. A downed player cannot open it (they would be frozen and the team would lose sight of who needs a revive); the panel word keeps DOWN above MENU.
- The overlay offset is not a fixed number: `panels.gd` derives it from the panel's minimum height plus a 4 px edge margin and a 2 px gap (under the panel in the top corners, over it in the bottom ones), and again when that height changes. `test_overlay` checks the rectangles at 640×360.
- Focus is shown with a "> " text mark because Godot's own focus is unused (`UIFocus` decision), and state is never colour alone.


## 2026-10-17: Unfinished sessions keep their work

**Decided by:** the owner ("work should not be thrown out").

- A session that stops before it is done (usage limit, error, timeout, or no result) but has commits pushes them to its task's branch in a draft PR titled `Unfinished: <task>`, with a note saying why. It is not reviewed or merged; the next session for the task finds the PR by its branch and continues it, and the PR becomes ready for review when that session finishes.
- An unfinished revision is pushed to its PR with the same note, and the final review is skipped, so the next session continues the PR.
- The implement job may run 4 hours (its Claude step stops at 200 minutes) and the revise job 3 hours (150 minutes), so a step that runs too long still leaves time to package and keep its commits.
- Triage already skips draft PRs, so an unfinished PR is never rated as a contribution.

## 2026-10-17: The bot may push main's workflow changes, never its own

**Decided by:** the owner.

- GitHub refuses a push from the bot app when any pushed commit changes a file in `.github/workflows/`, even a merge that only takes in main's version. Run #103 lost a finished session this way: it merged main after #67 had changed `session.yml`.
- The push tokens in `session.yml` ask for `workflows: write`, and the bot app has that permission.
- Before every push, `publish` checks each file under `.github/`: it must match main or the branch as already pushed, or nothing is pushed. So the bot can take in the owner's workflow changes, but it can't make its own.

## 2026-10-17: Making the unit tests pass

- **Unit tests wait one frame** (`await process_frame` first in `_initialize`): in Godot 4.7 the root is not in the scene tree during `_initialize`. The rules for tests are in `tests/README.md`.
- **Sorting `StringName`:** `Array.sort()` orders StringNames by address, not by letters. The registry sorts ids and folders by their text.
- **Pool:** a pooled object is held as a `Variant` until checked, since assigning a freed object to an `Object` variable is an error.
- **AI:** a freed target reads as `null`, so the AI keeps the target's instance id to know it was lost and looks again at once, as documented.
- **Feel:** a plain hit never starts or extends a hit-stop while one runs; before, four players hitting every frame froze the game for ever. A kill still lengthens a shorter stop.
- **Flow:** a failed restart is a `push_warning`, not a `push_error`: the run ends cleanly, a test provokes it, and the build fails on `ERROR:` lines. The 4-bot smoke test (M1 part 20) must therefore also fail on the warning text "the restart failed".
- **Mid-run joiners** take the free spawn farthest from enemies and wizards (part 17), so the coop test checks "a player spawn", not the one numbered like the slot.
- **`player.gd` and `combat.gd`** read absolute autoload paths only inside the tree (tests build them outside it).

## 2026-10-17: HUD panels 60% translucent, fonts unchanged (replaces the entry below on sizes)

Still no display in sessions, so decided from sizes, not from a screenshot, and text legibility over the floor is NOT verified (no contrast was computed or seen). Only the translucency was added; fonts stay 12/14 px at 640×360 (integer-scaled ×2); no licensed pixel font is in the repo, so none was added. An opaque 112×55 corner panel can hide a wizard or enemy in a room corner (at Coop zoom 0.5 it covers 224×110 world px), so the panel background alpha is now 0.6; border and text stay opaque and state stays in words. If a real screenshot shows text hard to read over bright floor, raise the alpha to 0.75 in `hud/theme/spellmerge_theme.tres`; the four `panel_p1`–`panel_p4` styleboxes there hold the same literal and must change together (the test only checks the range 0.4 to below 1). The real screenshot stays in `docs/BACKLOG.md`.

## 2026-10-17: HUD sizes unchanged for now, visual check still open

The HUD screenshot cannot be taken in a session (no display, `docs/BACKLOG.md`), so no HUD size or font was changed. This is not a finding that they are fine. The four 112×55 panels are screen-space corners: a wizard or enemy standing in a corner can be hidden by one, and the Coop camera moves and zooms (0.5–1.0), so a paper check at one camera position says little. The legibility of the smooth default font at 12/14 px on the 640×360 canvas is unverified, and the design calls for pixel art, so a pixel font may be wanted (side note: a font file would need a licence entry). Decide on panel size, a translucent background and the font after the display run; tracked in `docs/NEXT.md` ("HUD screenshot and legibility check").

## 2026-10-17: the 4-bot smoke test

- The test is `tests/smoke/four_bot_smoke.gd`; `tests/smoke/test_four_bot_smoke.gd` only extends it, because `build.sh` runs `test_*.gd` and sessions may not edit `ci/`. Part 21 decides how the export runs it.
- A downed bot 4 is not a failure (it only idles); its overlay closing while it is not downed is, and so is zero `spell_cast` events. The logger (`tests/smoke/error_log.gd`) is unit-tested with hand-fed calls and starts after the autoloads load, so startup errors are not covered.
- Errors are caught by a `Logger` (`OS.add_logger`), not by reading a log file, so the test works the same in the editor and in an export. A warning counts as a failure only for "the restart failed" (see "Flow" above).
- Bots call nothing on a spell (a deliberate deviation from "calling only the cast method" in the old NEXT.md wording): they hold the `cast` action and the wizard calls the cast method. "Alive or revived" is checked as "not down at the end"; revive itself is still in `docs/BACKLOG.md`.
- Game time runs at `Engine.time_scale` 2 with a limit of 120 game seconds, since no real-time wait is wanted.

## 2026-10-17: The daily build runs the unit tests and takes screenshots

**Decided by:** the owner (#72: "make the daily build run the unit tests and fail when one fails"; and screenshots "posted somewhere").

- The full `ci/build/build.sh` (the daily build) runs every unit test. A failing test fails the build, which then goes through the usual find-and-revert of the merge that broke it.
- `ci/build/build.sh --quick --screenshots`, also part of the full build, runs every `tests/screenshots/shot_*.gd` under `xvfb-run` with the OpenGL renderer (Mesa's software renderer on the runners). The shots save 640×360 PNGs to `user://screenshots/`, and the script copies them to `build/screenshots/`. The first shot script, `shot_m1.gd`, takes the main menu and the arena with four wizards.
- **Where they are posted:**
  - The daily build publishes a gallery at `/screenshots/` on the Pages site.
  - Every bot PR gets a comment with the screenshots of its latest commit. The images are stored on the orphan `screenshots` branch under `pr-<N>/<sha7>/` and linked by commit.
  - The game code that takes the PR's shots runs in a job with no secrets and a read-only token. A separate job posts the images and accepts only plain PNGs under 1 MB.
- Sessions may run `--screenshots` and open the PNGs with Read, so Claude can see what it built.

## 2026-10-17: Translucent player panels (replaces the 60% entry above)

**Decided by:** the owner ("it's generally fine [that the HUD covers imps]... but the HUD could be transparent").

- A corner panel may sometimes cover a wizard or an enemy; that is accepted, not something to design around.
- The four player panels in `hud/theme/spellmerge_theme.tres` are translucent: background alpha 0.4, border 0.8, and the bar backs 0.7, so whatever is behind a panel shows through. `panel_plain`, the default panel for menus and overlays, stays opaque.
- The values were checked on the `arena_four_wizards` screenshot: the imps in the top corners show through and the labels stay legible.

## 2026-10-17: Hit work is budgeted per step; the projectile caps stay

- `ProjectileManager.step` spends at most `WORK_PER_STEP` (6,000 since 2026-10-23, was 8,000) units of hit-test work a step: 1 per target examined, `HIT_WORK` (40) per hit. Counting examined targets as well as hits bounds both costs the benchmark found (a hit limit alone would not bound the crowd scans of the steady state). The budget is work, not time, so tests stay deterministic.
- When it runs out, the remaining shots still move and are not tested; the next step starts from the first untested slot, so a flood cannot starve high slots. The price: in a crowd at the caps a shot can hit a step late, and a very fast one can skip a target. Real play (about 10 shots) never gets near it.
- With the work bounded, the hostile step no longer grows with the number of shots, only plain movement does (0.2 ms at 1,000, 0.6 ms at 3,000). Measured 2.8 and 3.1 ms natively. A first try with 16,000 gave 6.5 and 7.4 ms, 81-93% of the 8 ms target: too close when WASM may be 2-4x slower, so the budget was halved. At 4x, 2.8 ms is still about 11 ms, so the web task re-checks it in WASM and lowers `WORK_PER_STEP`, then `DEFAULT_CAP_WEB`, if needed. The caps stay 1,000 web / 3,000 desktop: the budget, not the cap, now sets the hostile cost.
- The budget is per `step` call, not per frame: catch-up physics steps in one frame (up to 8 by default) each get their own. Slot order is not player-fair, so in a flood the player whose shots sit in the starved slots hits a step late; the resume point moves on each step, so it evens out over a few steps. Tested with piercing shots that never die (`_test_spent_budget_resumes_at_the_first_untested_shot`).
- Not done: a per-layer grid and cheaper overlapping-target handling. The budget alone met the target; they stay options.

## 2026-10-17: Starter kit sources live in `art/kit/`; golden examples are existing art

- The kit sources are in `art/kit/` with a `.gdignore`, so Godot neither imports nor ships them, and they have no manifest entries (templates and lists, not game assets).
- `.gpl` is not an allowed file type (hard rule 2), so the GIMP palette is `spellmerge.gpl.txt`; the kit zip ships it as `spellmerge.gpl`. Binary palettes (Aseprite, Photoshop, Krita) can't be written by sessions; the hex list and the `.gpl` cover those editors' import functions.
- The golden example candidates are not copies. A second wizard would duplicate `content/wizard/base/wizard_p1_idle.svg`, so `art/kit/golden.json` lists the six best existing placeholder files by path with what each shows, and the zip build copies them. The M2 art direction call confirms or replaces them.
- The checklist's source stays `docs/STYLE.md`; `art/kit/checklist.md` is its one-page export, kept in step by hand until the site build generates it.

## 2026-10-17: Aim is separate from walking (C1 iterate round 1)

**Decided by:** the owner ("iterate a bit more on the basics like aiming etc. And also a bit on the graphics", #97); the details are Claude's.

- Before, shots went the way the wizard last walked, so it could not shoot one way and retreat the other. Now `player.gd` has `aim`: the right stick, else (keyboard player only) the mouse once it has moved 8 pixels (a brush does not count), else the walk direction. The stick aim holds 0.6 s after release so a flick still shoots where it pointed; then it follows the walk again, so a player who never touches the right stick keeps the one-stick behaviour.
- The mouse is only a flag in `core/input` (`is_mouse_aiming`); the wizard turns it into a direction with the world mouse position. The J key switches the keyboard player back to walk-direction aim.
- Aim assist toward enemies is not done: it needs the wizard to look at enemies, which crosses areas; decide with playtest answers.
- Graphics, small and code-drawn (no new art files): the sprite flips toward the aim (with a 0.3 band either side against flicker; the flip also mirrors the painted light, accepted for the placeholder art), a soft ground shadow, and a chevron reticle in the player's light ramp colour with a 1 px outline. Shots still start at the wizard's feet, in line with the shadow.

## 2026-10-18: Weekly planning, M1 stays open

**Decided by:** Claude (weekly run). The digest was empty; the owner gave no instructions and no focus.

- M1 is not complete: C1 (#97) has no verdict, and the web 4-bot run (#93) and the Style Guide site step (#95) wait on the owner. No M2 design is written; the 7-day default for C1 is iterate on 2026-10-24.
- No task added. Shots keep starting at the feet, in line with the shadow, as decided on 2026-10-17; that is revisited only with a feel-check answer or the C1 verdict, not on a re-read of the code.

## 2026-10-18: Playtest fixes: shots at the staff, visible, and a dash look

**Decided by:** Claude, on the owner's `/claude` in #102 (playtest) and #97 (C1).

- **Shots start at the staff tip, reversing the 2026-10-17 "feet" choice.** The owner asked for it and could not see the shots anyway. `muzzle_position()` is hand height (10 px) plus 14 px along the aim; the same point goes out in `spell_cast`. The staff is drawn in code, not a sprite part, so it works for every player colour and aim angle until real art arrives (M2).
- **No aim assist.** The owner does not want it; a "homing" spell modifier is the planned way, so nothing is added to `player` for it.
- **Projectile visibility lives in `core/projectiles`.** The batch is drawn at `z_index` 50 (above room and wizards) with a `custom_aabb` over the bounds, and drawn at 3x the hit circle with a 45% tint. Reason: the bugs were in how the batch is drawn, not in spells or the player.
- **Dash look is code-drawn** (stretch along the dash axis, lean, three ghosts at the wizard's last three positions with the same stretch and lean), no frames: no art files are needed and it works for all four colours. Real animation is M2 art. The staff and reticle are drawn by a child node above the sprite, the shadow and ghosts below it.
- **Known limit: shots can start behind a wall.** The muzzle is 14 px out and 10 px up, and projectiles do not collide with room geometry in M1, so a wizard pressed to a wall can fire from the far side. Fixed on 2026-10-18, see "Shots stop at walls" below.
- **Shot colours.** At 4 players the five shot colours (players 0-3 and the enemy) all differ and none is dark (`test_projectiles.gd`). Enemy orange and player pink are the closest pair; enemy shots are also told apart by where they come from. The 3x draw size against the hit circle is a feel value for the C1 round: if shots look bigger than they hit, lower `DRAW_SCALE`.
- Not decided here: controller and 4-player feel (the owner has not tried them); they stay in the C1 round.

## 2026-10-18: Shots stop at walls (C1 round 2, task 2)

**Decided by:** Claude, from the owner's round-2 task list (#102).

- **No bouncing.** A shot that meets a wall ends there, piercing shots included (`pierce` is for targets). A bouncing modifier is a spell-design question for M2+, not decided here; when it comes, it belongs in `core/projectiles` as a per-shot bounce count, using the same wall grid.
- **Own wall grid, not physics queries.** The manager rasterises the room's solid rectangles into 8 px cells and walks the cells a step crosses. A physics ray per shot would cost thousands of queries a step against the 1,000 web / 3,000 desktop budgets. Walls are rounded out to whole cells (exact for the 32 px tiles); the shot is a point, not a circle, so its 4 px radius can overlap a wall by that much. The wall check is not charged to `WORK_PER_STEP`; its walk is capped at 64 cells a shot instead, and a path not fully walked counts as a hit (a shot never crosses a wall it did not check).
- **Walls cut the step, they do not pre-empt it.** The step is shortened to the wall and the hit test runs on that part, so a fast shot still hits a target in front of a wall (a target behind it is not hit). Checking the wall first and dropping the whole step had lost those hits.
- **Only rectangles.** `add_wall_body` reads `RectangleShape2D` shapes (turned ones as their bounding box) and ignores the rest. Rooms with other wall shapes need `set_walls` rects or a new case.
- **Who tells it.** `core/` does not know rooms, so `flow` finds the static bodies on physics layer 1 in the room scene after it is in the tree and calls `add_wall_body`. `set_bounds` clears the walls, so a new run starts empty.
- **Clip from the feet.** The wizard clips the segment from its feet (always outside a wall: the body collides) to the staff tip, and casts from the clipped point. A shot from a tip behind a wall therefore starts at the wall and ends on it at the next step; the cast still spends mana and cooldown, as a swing at a wall does, but `spawn` refuses a shot that starts inside a wall, so it takes no pool slot and evicts no one. Refusing the cast instead (no mana) was tried: the 4-bot smoke failed four runs in a row with it, so it stays a spent cast. The hand point could be inside a wall for a wizard against a top wall, so it is not the start.
- **Wall hits are silent for now.** `wall_hits` is a counter; no event, spark or sound (backlog).
- **Bots.** The wave bots hold fire without a line of sight and strafe along the wall instead of walking at it. Reason: with walls they fired into pillars and the 4-bot smoke failed.

## 2026-10-18: Dodge and cast feel (C1 round 2, task 3)

**Decided by:** Claude, from the owner's round-2 task list (#102).

- **Buffer 0.15 s for both.** A press made while the action is not yet possible counts if it becomes possible within 0.15 s (about 9 frames at 60 FPS: long enough to forgive a mistimed tap, short enough that nobody dodges "by surprise" after the cooldown). One buffered press is used once and a new press restarts the window. Pressing in an overlay, being downed or a captured wizard clears it, as before for the dodge press itself. A held `cast` is unchanged; the buffer matters for taps.
- **Invulnerability look is one rule for every kind of protection** (dodge, join 2 s, revive 1.5 s): the sprite is 55% opaque and a ring in the player colour closes over the time (full for join and revive protection until the last `INVULNERABLE_TIME`). Shape and opacity, not colour alone. The sprite's `material` stays free for the hit flash in `Feel`; only `modulate` is used.
- **Cast rate and mana cost: no change.** The fire bolt costs 5 mana at a 0.35 s cooldown: 2.9 casts a second would use 14.3 mana a second against 10 regenerated, so from a full 100 mana a wizard who holds fire without a break runs dry after about 23 s and then fires at the regeneration rate (2 a second). The bots in `test_wave_balance` fire 1 to 1.5 casts per player-second (they walk, and hold fire without a line of sight), so mana never limits them and the cost is not what decides the fight. Five damage per hit against 20 imp health is four hits. With no person's playtest on the cast rate and the bots too crude to tell (they never dodge, which is why the 1 and 2 player runs are lost), changing a number would be a guess; revisit with a playtest answer.

## 2026-10-20: C1 verdict iterate, playtest report first

**Decided by:** the owner (verdict on #97); Claude (the queue).

- The verdict is iterate. The next work is a human playtest of round 2, then the top items from its answers, not more guessing from code and bot logs: round 2's feel values are still unverified by a human.
- The plan allows at most 2 iterate rounds, counted by the owner's iterate requests on #97, not by the "round N" labels in `docs/NEXT.md` (those number batches of work: aiming, playtest fixes, art, juice and the six tasks). Round one was the owner's first `/claude` on #97 (aiming and graphics, then the 2026-10-18 playtest fixes); round two was the six tasks and their summary. This verdict, given on that summary, closes round two. After it the next checkpoint must be go or pivot, and the next assessment must say so in plain words.
- Controller and 4-player feel are still untried by a human; the playtest questions ask for them.

## 2026-10-17: Panels may hide the wizards at zoom 0.5; walls are tested

**Decided by:** the owner (#87: "It's fine as it is").

- At the widest Coop zoom (0.5), each corner panel may cover its player's wizard. The panels stay as they are: translucent at alpha 0.4.
- The staged screenshot is now named `staged_zoom_half_wizards_placed_outside_room`, because `shot_m1.gd` places the wizards outside the one-screen room to force the zoom-out, and the old name looked like gameplay. A new test, `tests/gameplay/flow/test_walls_hold.gd`, has four wizards walk and dodge into the walls through the real input path and checks that none leaves the room.

## 2026-10-21: Events for M2 (M2 part 2)

**Decided by:** Claude, following the M2 design ("Intent and result", "Projectile manager").

- `build_change_requested(player, spell, slot, component_id)`: `spell` is a `PackedInt32Array` path, as the design says. The overlay's stub sends `[0]` (spell A).
- New events: `spell_swap_requested(player)` (HUD, heard by `player`), `projectile_expired(player, position, tag)` (`core/projectiles`), `spell_changed(player, spell, description)` and `build_refused(player, reason)` (`player`), `reaction_triggered(player, reaction_id, position)` (`combat`). Each has one sender; the senders arrive in parts 3, 8 and 11, so their listeners are "none yet" in the table until then.
- `build_refused` has exactly `(player, reason)`, as in the design: the HUD shows only the reason in plain words.
- The `swap` action is bound to Q and the left shoulder, which were free. It is in `CAPTURED_ACTIONS`, so a player in the overlay or builder does not swap spells by accident.

## M2 part 3: projectile manager, part 1

- `projectile_expired` is sent only when a shot's life runs out or it ends on a wall, after the shot is removed (a handler may spawn at that spot). A hit, leaving the bounds and a cap drop send nothing: an on-expire trigger should not fire for a shot that did its job or was evicted.
- `still` is a `motion` argument at the end of `spawn` (velocity ignored), so part 4's `orbit` fits the same argument.
- The queries count a target when its hit circle overlaps the query circle (the rule of a hit) and return the nearest by centre distance. They read the grid of the latest step; `add_target` and `remove_target` outside a step mark it stale and the next query refills it. A target freed since the last step is skipped.

## M2 part 4: projectile manager, part 2

**Decided by:** Claude, following the M2 design ("`core/projectiles` grows only what the forms and modifiers need").

- Orbit and homing are separate calls, not more `spawn` arguments: `spawn_orbit(player, orbit_radius, angle, angular_speed, lifetime, ...)` and `set_homing(slot, turn_rate)`. `spawn` already takes nine arguments, and an orbit needs three more numbers. `spawn` still refuses `MOTION_ORBIT`.
- An orbit shot ignores walls (its caster holds it, and a wizard against a wall would lose the half of the ring in the wall) and ends quietly when its owner's anchor is cleared, so a wizard who leaves or falls drops their ring. A player with no anchor cannot spawn one.
- Homing keeps the speed and only turns it, toward the point found by the last search (every `HOMING_PERIOD` = 4th step, staggered by slot so a full cap does not search all at once). Range `HOMING_RANGE` = 160 px. It skips the shooter's own body and targets the shot remembers hitting; the search costs 1 work unit per target examined, so a spent budget only delays the next search. Only straight shots can home.
- `ray()` has one more optional argument than the design, `width`, so "bigger" can widen a beam. It returns the pixels reached (to the last target when `pierce + 1` were hit, else the wall or the length) and sends `projectile_impact` before each `projectile_hit`; a beam that ends on a wall sends a wall impact (not counted in `wall_hits`, which counts shots). At most `RAY_MAX_HITS` = 64 targets. Hits are found first and sent after, so a handler may free targets or fire a ray itself (an on-hit beam trigger): scratch is kept per nesting level, up to `RAY_MAX_DEPTH` = 4, deeper returns 0.
- `homing_aim(player, origin, direction, max_angle, layers)` is the beam's homing: it returns the direction bent to the nearest target in the cone, for the spell runtime to call before `ray`.
- Review of part 4: an orbit shot is an ordinary piercing shot. `pierce` is how many hits it survives (0 ends it on its first touch) and it remembers only its last `HIT_MEMORY` = 3 targets, so a ring over more than 3 enemies hits some again. There is no once-per-revolution rule: a per-target timer would need memory per shot and target, which the pool has no room for, and the orbit form (part 10) can pick `pierce` for the effect it wants. The test `_test_orbit_ring_over_a_crowd` pins this.
- Homing (shots and `homing_aim`) never picks a `LAYER_PLAYER` target, even with friendly fire on: a seeking shot should not curve into a teammate. A freed target is skipped.
- `ray()` cuts `length` to `RAY_MAX_LENGTH` = 360 px (what the 64-cell wall walk covers on a diagonal) and is not charged to the hit-work budget; the spell runtime's fire cap (part 6) bounds how many rays a spell and its nested handlers fire.
- `set_homing` returns true whenever the rate was applied, 0 included; false only for a refusal.

## M2 part 5: the compiler and limits

**Decided by:** Claude, following the M2 design ("The spell runtime lives in `core/spells/`", "Tags", "The spell limits are the performance limits").

- A recipe is a plain Dictionary (`form`, `element`, `modifiers`, `trigger`, `held`), so it can come from JSON (the combo catalogue) and from the builder alike; ids may be Strings or StringNames. `compile` never errors: bad input gives `valid == false` with a reason in plain words.
- Refused (nothing can fix it by clamping): no form, unknown id, wrong kind in a slot, more than 3 modifiers, a held spell without a trigger, nesting below depth 2, complexity over 12. Clamped and said in the description: shots over 24; speed, radius, pierce and the cooldown floor are clamped silently to the form ranges. A trigger with nothing held is valid (it costs complexity and fires nothing), so the builder can place a trigger before the spell it holds.
- Number rules: damage is form x element scale x modifier multipliers, rounded, at least 1; mana, cooldown, speed and radius multiply; shots multiply and pierce adds; homing keeps the largest turn rate; chain jumps add. More than one shot with no spread of its own opens a 30 degree fan (`SPLIT_SPREAD`), except an orbit.
- Tag layout: bit 8 is always set so no tag is 0 (combat treats 0 as "no tag"), then player (2 bits), slot (1), depth (2) and generation (3). A built spell registers its held spells at depth 1 and 2 under the same generation.
- Ring wrap: when the generation about to be reused still has live shots, its tags go into `revoked_tags` and its counts are cleared before the new spell takes the tag; the caller removes those shots. `Projectiles` gets no remove-by-tag in this part; part 6, the first caller, adds it (queued in `docs/NEXT.md`).
- Review fix: live shots are counted per generation across all depths, and a generation's profiles are freed together, because a shot that fires a held spell on its hit needs the depth 1 and 2 profiles after the rebuild. Part 6 starts a child's shot before it ends the parent's, and removes the shots of `revoked_tags` before the next `begin_generation` or `shot_ended`. New limits in `SpellLimits`: chain jumps 6, timer interval 0.1 to 10 s, lifetime 0.05 to 20 s. A malformed recipe field (wrong type) is refused with a reason. The compiled spell keeps its form and element display names, so the description needs no second registry look-up.
- `Spells.registry` can be set to a stand-in with `get_resource(folder, id)`, so the tests need no content files.

## M2 part 6: casting and triggers

**Decided by:** Claude, following the M2 design ("How a held spell fires", "Tags", "Hits, statuses and reactions").

- **The end of a shot is a signal of the manager, not an event.** `Projectiles.shot_ended(tag)` is sent for every tagged shot that ends, after its `projectile_hit` or `projectile_expired` handlers, so a held spell is started before its parent is counted out (the order part 5 asked for). It is not on the bus (`core/events` is for areas talking to each other; this is core talking to core) and it needs no change in the events table. `remove_by_tag` is the one silent removal, because the caller revoked those tags.
- **Per-shot state lives in `Spells`, keyed by projectile slot.** The manager keeps no spell data. `Spells` has packed arrays (fires left, chain left, previous target, timer clock) indexed by slot and valid only while the shot's spawn number (`get_seq_of`) matches; the manager sets `event_slot` while a hit or expiry event is sent so the handler knows which shot it is. The record is written back before any child is spawned, because a child can take the slot of a shot that just ended.
- **A beam is one shot, fired and ended inside the call.** Its context (tag, direction, fires left) is kept in fields while `ray()` runs and restored afterwards, so a held beam fired from a hit handler nests. A beam's chain jumps do not nest: `ray()` allows only 4 levels but a chain may have 6 jumps (and split or pierce beams jump from several hits), so a jump is put in a fixed 64-entry queue and the outermost beam casts the queue, in order, after its own `ray()` returns. A full queue drops the jump and counts it in `chains_dropped`. A beam whose `ray()` did nothing fires no on-expire spell. A beam fires an on-expire spell at its end, has no timer, and passes the target that fired it to `ray(..., exclude)` instead of waiting 0.1 s.
- **Where a held spell goes.** From the hit point (expiry: 2 px back along the path, so a shot that died on a wall fires in front of it; timer: the shot's place); along the shot's velocity, or outward from the caster's anchor for an orbit or still shot; the source target is excluded for 0.1 s (`Projectiles.exclude`, one target per shot).
- **Fire cap.** `MAX_FIRES_PER_STEP` (32) is per player and counts held spells fired, from every slot and depth. The window is one `Spells.step` to the next (hits of the projectile step in between count). A dropped fire consumes nothing: the shot keeps its fires and a timer waits its next interval.
- **Chain** picks the nearest other target within 96 px that is neither the one just hit nor the one before it, so two enemies are not bounced between. The chain shot is a plain straight shot of the same tag (speed at least 300 px/s) that carries the trigger's fires left.
- **`hit_profile(tag)` returns a `HitProfile`** (damage, knockback, element, status) made once per compiled spell, so a hit allocates nothing and `combat` reads no spell field. Knockback is one constant (120, M1's value) until a form or modifier needs its own. `combat` is switched over in part 7; M1's table stays until then.
- **`install` is the call for a build.** `begin_generation` stays as in part 5; `install` also removes the revoked shots, so no caller can forget to.

## M2 part 7: elements and statuses

**Decided by:** Claude, following the M2 design ("Hits, statuses and reactions").

- **Status numbers are in the element, the rules are in `combat`.** `status_strength` means: burn damage per second; the percent of speed chill takes (capped at 90%); the percent of the hit's damage a shock jump deals; the percent of extra damage a hex adds. First values: fire burn 2/s for 3 s, frost chill 40% for 3 s, storm shock 75% for 4 s, void hex 25% for 4 s. All elements keep `damage_scale` 1.0 until the combo test retunes them.
- **Stacking.** Burn, shock and hex refresh their time and keep the stronger number; they do not add up. Chill adds a stack; the third freezes for 1 s (`FREEZE_TIME`) and clears the chill; a frozen enemy takes no more chill, so hitting it cannot extend the freeze (Stillness, part 8, extends it on purpose).
- **Order in one hit:** hex raises the damage and turns the knockback into a half-strength pull toward the hit; a shock is used up and jumps after the damage (also when the hit kills); then the hit's own status goes on, only if the target survived. So the hit that applies a status never feels it itself.
- **The jump** goes to the nearest other enemy within 64 px, deals the damage times the share (at least 1), pushes nothing and puts on no status, so shock cannot chain forever. The neighbour comes from the projectile manager's target grid, rebuilt each step: an enemy that joined this frame is found next frame.
- **Burn** deals whole points of damage (a fraction is carried) through the same pipeline as `hit()`, so a hex raises it and the caster gets the kill credit. It is quiet: a tick that leaves the enemy alive sends no `damage_dealt`, so Feel's hit-stop, shake, spray and sound and the AI's hurt pose do not fire twice a second per burning enemy. The tick that kills sends `damage_dealt` and `enemy_died` as any kill does.
- **A frozen enemy still hurts on contact.** Freeze stops it moving and attacking with shots, not touching; a wizard must not stand in it. Tested.
- **A shock is spent only by a hit that counted.** Burn is collected during the status loop and sent after it, as contact hits are.
- **The AI is slowed by `Combat.speed_factor(enemy)`** (1 free, less when chilled, 0 frozen), applied to walking and to the windup and recover timers, so a frozen imp's telegraph stops where it is and the warning stays honest. Knockback is not scaled.
- **Players get no statuses** from player spells (friendly fire is damage only), as the design says.
- **Tints and icons use palette colours only** (STYLE.md has no ice or storm colour): fire is Fire base, frost is Player 1 light blue, storm is Spark gold, void is Player 4 light purple. Frost and void are close in hue to players 1 and 4, which STYLE.md warns about for base colours; the art pass (M2 part 26) checks this on one sheet and may ask for new palette entries (an owner decision).

## M2 part 11: player and flow on the new runtime

**Decided by:** Claude, following the M2 design ("Building spells, without anyone waiting", "The fire bolt migrates").

- **Slot numbers in `build_change_requested`.** The design left the meaning of `slot` open. It is the position in a spell's chain: 0 form, 1 element, 2 to 4 modifiers, 5 trigger; an empty `component_id` clears the slot. Modifiers stay in a compact list: a new one goes in the first free place, clearing one closes the gap. Clearing the trigger drops the held spell with it, as a held spell without a trigger does not compile.
- **A held spell is reached by the path** (`[0, 0]`), and the held part is created by the first request that names it (it still needs a trigger, or the compile refuses it).
- **A change is made on a copy of the recipe** and kept only if `Spells.compile` accepts the whole thing, so a refusal changes nothing and the old spell keeps casting. The bag and the component's `kind()` are checked first, each with its own reason.
- **`spell_changed` always names the prepared spell** (`[0]` or `[1]`), also when the change was made in a held spell, because the whole chain is recompiled and its description covers it.
- **`player` reads no field of a compiled spell except `valid`, `reason` and `description`**, which are the answer to a compile. `spell_cast` now carries the form id of the recipe (what M1 sent as the spell id).
- **The bag is every visible component in the registry** (so the web demo offers only demo components), filled when the wizard enters the tree. M3's rewards change who fills it.
- **Cooldowns belong to `Spells`,** per player and slot, and tick on the autoload's physics step. The wizard ticks nothing, so a downed wizard's cooldown now runs on (it cannot cast anyway). A rebuild does not reset its slot's cooldown. `Flow` calls `Spells.clear()` on a new run, after `Projectiles.clear()` (which ends every counted shot), so a restart forgets all builds and cooldowns.
- **Start recipes are in `flow`:** `start_recipe_a` = bolt + fire (M1's bolt plus burn) and `start_recipe_b` = bolt, as the design says. Flow checks that both compile before it starts a run (a missing component or a refused recipe logs a warning and keeps flow idle, as a missing room does) and hands each wizard a copy. A player who leaves and rejoins mid-run gets the start spells again; builds last for a run and are not kept per slot yet (saving is `core/save`, M5).
- **The orbit anchor is the player's job** (as the M2 design says): each step the wizard calls `Projectiles.set_anchor(index, body position)`, and `clear_anchor` when it is downed or leaves the tree. The body offset is the hit circle's.
- **`SpellBase` and the legacy bolt are removed** together with `Combat`'s learning of hit profiles from `spell_cast` (every player shot now carries a tag that `Spells.hit_profile` knows). Combat keeps `set_hit_profile` for enemy shots. The scan that no script reads a spell field moved to `tests/core/test_spell_field_reads.gd` and covers the component classes and `CompiledSpell`; `HitProfile` is left out because combat reads it by design. The registry test fixtures became `FormBase` resources.
- **No event for a swap yet.** Part 18 (the corner panel shows A or B) needs one; `core/events` gets it then, with `player` as the sender.

## M2 part 12: the six modifiers

- **The modifiers are plain `ModifierBase` `.tres` files with an icon, no scripts.** Split's fan, pierce's extra targets, homing's turn and chain's jumps are all expressed by fields the compiler and the runtime already read. First numbers (the combo test and playtests retune them): split ×3 shots, ×0.5 damage, ×1.5 mana, complexity 2; pierce +2 pierce, ×0.9 damage, complexity 1; homing 3 rad/s, ×0.9 damage, complexity 2; chain 2 jumps, ×0.8 damage, complexity 2; bigger ×1.6 radius, ×1.3 damage, ×0.85 speed, ×1.15 cooldown, complexity 1; faster ×1.5 speed, ×0.75 cooldown, ×0.85 damage, complexity 1 (a review found faster free at first; the damage cost leaves it about 13% more damage per second, and two stack to about 28%). Every modifier that adds power costs something (split: damage per shot and mana; homing and chain: damage; bigger: speed and cooldown; faster: damage), so none makes another obsolete. Complexities are the design table's.
- **Owner answer on #140: option 1, no change.** `tools/check.sh` stays free of Godot; the spell validator keeps running in `ci/build/build.sh --quick --tests`, which AGENTS.md already asks contributors to run.
- **The icons are placeholders** drawn as non-overlapping SVG rects like the forms' and elements'; the part-26 art pass looks at all 18 together.

## M2 part 13: the three triggers

- **The triggers are plain `TriggerBase` `.tres` files with an icon, no scripts;** the runtime already fires them from the fields. Ids `on_hit`, `on_expire` and `timer`. First numbers from the design table (the combo test and playtests retune them): on hit and on expire fire once per shot (`max_fires` 1), complexity 1 each; timer every 0.5 s (the combos' "every half second") with `max_fires` 4, the limit, complexity 2.
- **A rune dropped by an on-hit trigger on a living target is used up on it** (it does not pierce, and the 0.1 s source exclusion ends), so a pulsing rune works best where its target moved or died. Left as is; the combo test (part 14) will show whether runes need a longer ignore time for their own source.
- **The icons are placeholders** drawn as rects like the other components'; the part-26 art pass looks at all 18 together.

## M2 part 14: the combo catalogue and test

- **The catalogue is data, the checks are a few kinds.** A row in `content/spells/combos.json` holds the recipe(s), the imps' positions, the seconds to run and a list of checks (`damaged`, `status`, `status_count`, `keeps_burning`, `reaction`, `max_shots`). One data-driven test runs every row, so a new combo (part 21, and contributors) needs a JSON row and no code, unless it needs a new check kind.
- **The arena is the real thing, not a mock:** `tests/content/spells/combo_arena.gd` wires the real registry, projectile manager, spell runtime and combat, and steps them in `project.godot`'s order. Imps are plain `Node2D`s with 400 health, so no combo kills one by accident.
- **Two draft combos reworded to what the runtime does.** "Three homing bolts that find three different imps" is now "bend toward imps well off the aim" (each shot picks the nearest target, so they may share one; a control test shows a plain fan misses those imps), and "a wide ray that reaches an imp a plain ray misses" is now "chills the imp in its lane" (the widening is about a pixel, a tuning number not worth a test).
- **The first 12 are the design's draft rows 1-12.** "Blast at the end" runs in open space; the wall case stays with `test_spells_cast.gd`. Part 21 adds the rest and makes sure each component is in two combos.

## M2 part 15: Spells opens

- **Spells is open for PRs from this part.** The README states that every new component needs at least one combo row (the combo test runs it without new test code), so the catalogue grows with the content. The ROADMAP row said "from part 11, Story from part 21", left over from before the design review; it now matches the design (15 and 23).

## M2 part 16: the builder, part 1

- **The builder sits beside the corner panel, not over it.** The design says it "expands the corner panel toward the middle"; a panel under or over the corner panel would leave about 120 px of height in a four-player quarter, too little for the chain and the bag. Beside it (about 200×170 px) a player keeps seeing their health and mana while building, and four builders and four panels fit 640×360 without touching (tested).
- **Two new events, `recipe_changed(player, slot, recipe)` and `bag_changed(player, ids)`, both from `player`.** The HUD may only show what events say, and `spell_changed` carries a description, not the chain. Sending the recipe next to `spell_changed` keeps `spell_changed` as the design has it and each event with one sender. `bag_changed` is sent when the wizard appears, so M3's rewards change who fills the bag without changing the builder.
- **Names, icons and kinds come from `Spells`** (`component_name`, `component_icon`, `component_kind`). `test_spell_field_reads.gd` rightly forbids the HUD reading a component's fields; a small accessor set in the runtime keeps that rule and gives the builder what the design asks it to show.
- **One linear focus list, with focus helping.** `core/ui_focus` moves through a plain list, so the builder lists tabs, slots, held buttons, bag rows and Close in that order, moves focus to the bag after a slot is chosen and back to the slot on `dodge`. Rows that cannot be used are disabled or hidden, and UIFocus skips them.
- **A modifier slot opens only in the first free place,** as `player` fills modifiers (a new one goes in the first free place; clearing one closes the gap). A held spell's form must be chosen first, since the compiler refuses a held spell without one; the refusal reason is shown from part 17.
- **The builder opens at any time for now.** Part 18 folds it into the quick view and part 19 makes the break between waves, as the design says.

## M2 part 17: the builder, part 2

- **The info panel sits in the quarter's free strip, not in the builder.** The builder (about 190×168) already fills the space beside the corner panel, but the strip at the screen edge under (P1, P2) or over (P3, P4) the corner panel was empty. A 112×112 panel there keeps all builders, corner panels and info panels apart (tested at 640×360). It is a top-level child of the builder, so it shows and hides with it and the builder's own layout is unchanged.
- **`Spells.builder_view` gives plain values.** `test_spell_field_reads.gd` forbids the HUD reading a `CompiledSpell`; the view returns a Dictionary (complexity of the whole spell, numbers and shot pattern of the spell at the shown level), so the compiler can change without touching the HUD. It compiles the recipe on each render (on events and key presses, never per frame).
- **The refusal reason is text and lasts until the next try.** It comes from `build_refused` for the owner only and clears on the next request, the next successful change or the next opening. It shares one text line with the component description; the reason wins while it is set.
- **Descriptions are empty until part 23:** `Spells.component_description(id)` returns "" for now; part 23 reads Story there.

## M2 part 20: bots build spells

- **One generator, two users.** `tests/bots/recipe_fuzzer.gd` makes seeded random recipes from the component ids by kind. The bot uses it with a `compiles` filter (the recipe always builds); the fuzz test uses `candidate` unfiltered, so the compiler's refusals are fuzzed too. The same seed always gives the same recipes; a failure prints the seed and the recipe.
- **Bots build like people.** `Bot.build_random(seed)` sends `build_change_requested` slot by slot (first it empties spell B's element, modifiers and trigger, then form, element, modifiers, trigger and the held spell one level down; every prefix compiles, tested), then `spell_swap_requested`. It builds into spell B so spell A stays the start spell. The 4-bot test builds when the room starts: the build break exists only after `room_cleared`, and that run ends at the clear. Seeds are `2026 + bot index`.
- **Bot 4 walks into the builder** with the real input path: the overlay tap, then `move_down` and `cast` on "Build" on later steps. The test now needs the builder to have opened and neither the overlay nor the builder to close afterwards. Folding into the quick view in waves is `hud/builder`'s own job and is covered in `test_quick.gd`.
- **Fuzz budgets.** 300 recipes at seed 20261022, each cast (and re-cast every 20 steps) for 2 s against seven imps in the combo arena. It fails on an error line, a broken `SpellLimits` limit, a refusal without a reason, the manager dropping any shot at the arena's cap of 512, more than 480 live shots at once (today's worst is 456), or a runaway shot count. A mean step above 5 ms or a single step above 100 ms only prints a warning (a busy CI machine is not a spell; the live-shot count guards cost without the clock). It also needs at least 5 compiled recipes each with a held spell, three modifiers and a trigger, and 20 with an element. First numbers: 244 of 300 compile, slowest mean step under 1 ms (0.8 ms measured). The 4-bot test compares recipes after turning every id into a String, so a type difference cannot fail it.
- **The weekly playtest** is written by the weekly run from what changed (`.github/maintainer/plan.md`, owner-only), so no change was needed: from now on its questions should include building (is the builder readable, are refusals clear, is a break long enough).

## Owner: a web preview after each merge

- **`preview.yml` builds main after each merge and puts the web build at `/preview/`.** The owner wanted to see progress more often than once a day. Sessions merge about hourly, so that is about one preview an hour, and only when something changed; a newer merge cancels a build still running. It runs the same `build.sh` as the daily run (tests and smoke tests included, about 4 minutes), with no release, no itch.io, no AI and no secrets. Public-repo Actions minutes cost nothing.
- **`/nightly/` and `/play/` stay the daily releases.** Pages replaces the whole site on each deploy, so the preview rebuilds it (`smbot.site --preview`): `/nightly/` from the newest release, `/play/` from the latest stable one. The daily run puts its build at `/preview/` too, and both Pages jobs share one concurrency group so deploys never overlap.

## Owner: clearer logging

- **One Daily log issue per day** ("Daily log YYYY-MM-DD" in the owner's time zone, label `daily-log`) instead of the pinned #5, which had grown past 100 comments. The first post of a day opens it and closes the older logs, so the open log is always today's and a past day is easy to find. Each post also goes to the run's job summary in the Actions tab. `ci/config.json` no longer names a log issue.
- **Owner questions are not asked twice.** Each has a stable `key` (kept as a hidden marker in the issue), and a question with the same key or a similar title (most words shared, or one title contained in the other) as one that is open or was closed in the last 30 days is dropped and only noted in the log. #72/#73 and #79/#80/#83 were the same questions in other words.
- **Session log lines name the PR by its title** and cut summaries at a sentence end, not mid-word. The token usage line is in the daily run's summary only, not in every session's post.

## Owner: the community intake replaces outside PRs

- **People outside the project post in Issues and Discussions; the bot writes all code and assets.** Rating, voting on and merging outside PRs, the CLA check, claims, no-git submissions and the copyright quarantine are removed (`triage`, `rate`, `votes`, `community`, `communitymerge`, `cla`, `claims`, `submissions`, `quarantine`). That was about half the automation, and with no outside files there is nothing to sandbox, license or vote on.
- **A daily intake decides each new post** (`smbot.intake`, `daily.yml`): a script gathers new issues, discussions and outside PRs with a read-only token; Claude decides each one with read-only tools and no write token (`.github/maintainer/intake.md`); a script carries the decisions out within fixed rules (at most 5 newly scheduled a run, spam always declined, copyright always `p1`, duplicates only of open issues). Outside PRs are read as suggestions and closed with a pointer to Issues and Discussions.
- **Scheduled issues are the top of the work queue,** before `docs/NEXT.md`, by priority then age. The session sees the intake's neutral restatement (kept in the automation state as `intake_tasks`), not the poster's words, and its PR closes the issue. Weekly planning moves issues between the queue and the backlog (`schedule_issues`, `unschedule_issues`) instead of reading a digest and creating contributor task issues.
- **The vote settings leave the Control panel;** an old panel's `VOTE_` line is ignored. The Contribute page shows the queue, the backlog and community reports done, instead of wanted-now counts and top contributors.

## Owner: development always flows

- **An empty queue plans instead of stopping.** The gate (`smbot.control`) runs a planning session when no scheduled issue or `NEXT.md` task is left, at most every 3 hours; before, development waited for Sunday's planning. Planning branches carry the time (`claude/YYYYMMDD-HHMM-planning`), since there can be several a day.
- **A milestone end is the one gate that waits for the owner** (owner, 2026-10-22). Planning marks the milestone done and outputs a `checkpoint`; once that PR merges, a `checkpoint` issue asks for `/go`, `/iterate <what>` or `/pivot <how>` (verified owner commands, only in that issue). Until then the gate starts no planning and no milestone work, but scheduled issues still run. The answer starts a planning session at once (`smbot.checkpoint`), which writes the next milestone, the rework tasks or the new direction; when it merges, the issue closes. No timeout: the old 7-day default to iterate is gone.
- **Errors are retried, then alarm.** A session that ends in an error starts the next one at once; after 3 in a row the bot stops and opens the "Development stopped" alarm, which closes after the next session that makes progress. A merged planning PR chains into development too.
- **What still stops development:** a checkpoint, the owner's switches, a usage limit (resumes at the reset), a rejected token, 3 errors in a row, and planning that finds nothing to do. Each, except the usage limit, mentions the owner.

## Owner: review of the reworked harness

An independent review of the branch found these, all fixed with a regression test each:

- **Every planning session crashed:** `prepare_plan`'s `weekly` parameter hid the `weekly` module. Renamed to `weekly_run`.
- **The weekly planning is started by the gate,** not `weekly.yml` (deleted). With development always running, the separate workflow sat behind a session in the shared concurrency group and was cancelled, and catch-up counted the cancelled run as done. The gate now runs the next session as the weekly planning once Sunday 06:00 UTC has passed (`last_weekly` in the state).
- **"Stopped after 3 errors" stops for real:** the gate refuses to develop until `/resume`, which resets the count; the alarm is posted once, not on every later failure.
- **Idle is said once:** planning that finds nothing sets `idle`; the gate then waits for new work or the Sunday planning instead of planning (and pinging the owner) every 3 hours.
- **An `/ask` with an empty queue looped,** because instructions were only cleared on a merge and the answers were only posted with commits. Answers now post in their own step, and a session that ends with nothing to do clears its instructions.
- **A checkpoint really holds milestone work:** while it waits, only scheduled issues count as tasks (the gate and the session both); a carried-out answer closes the issue even when the PR's `Closes #N` closed it first.
- **Cooldowns and limits wake the bot by themselves** (`wake_at` → `resume.yml`). Failed planning PRs are continued instead of piling up.
- **The Claude action is copied aside before a session switches branches,** so an older PR branch without it can't break the step; the next session starts even if a planning step fails.
- **Intake text is safer:** `inert()` also removes secrets (tokens, private keys), uppercase and `www.` links and look-alike repository links; raw titles never reach the log; Claude may not read `/proc`, `/sys` or its own config. An answered post is closed; a needs-info reply on a closed PR asks for an issue.
- **Simpler:** one label list (`ci/settings/labels.json`, `smbot.labels`), no project board, no `settings` plumbing, no unused CLI commands; owner questions only merge on a close match (0.75).

## Owner: contributions come back, through the intake

- **Anyone may send a pull request or attach art and sound to a discussion** (owner, 2026-10-22), and the owner's own issues and discussions go through the intake as direction (`from_owner`). The intake handles PRs like other posts: schedule, backlog, needs info, duplicate or decline.
- **A scheduled PR is finished by the bot, not merged as is.** It stays open and becomes the task "finish PR #N by @x": a session builds on the contributor's commits (authorship stays), reviews and finishes them, and the normal critique, final review and merge script apply. When that merges, the contributor's PR closes with credit. This keeps one merge path (the bot's own) instead of bringing back rating, votes and a staging merge.
- **The CLA is back, once per contributor** (owner's choice over inbound=outbound licensing, to keep the Steam and console option): the signing comment on the PR or discussion, kept in the automation state with a link next to `docs/cla-signatures.json`. No signature, no schedule or backlog: the reply asks for it.
- **A PR is only scheduled when the `rules` check passes,** so outside GDScript only runs in a session's sandbox after the banned-API rules have passed. That is a step up from "no outside code ever runs"; the sandbox, the read-only session token and the reviews are the guard.
- **Files from Discussions** (`smbot.contrib`): Claude names the target paths, a job with no secrets downloads (GitHub attachments only, the poster's own), re-encodes and size-checks them, and the apply step puts them on `submissions/discussion-N` for the session to take. An "Art submissions" Discussions category is added by hand (setup.sh lists it).

## Owner: contributions, hardened after a security review

- **The hard rules are run by the intake itself, on the exact head commit,** as an outside contributor, from main's scripts in the gather job (`intake.pr_rules`). The PR's own `rules` check can't be trusted for this: a fork can rewrite the workflow that runs it. Backlog needs passing rules too.
- **A session may only build on the checked commit.** The task names it, and publishing refuses any commit that isn't on main, isn't in that commit's history and isn't the bot's own (`session.unchecked_commits`). Commits the contributor pushes later never reach the bot's PR without a new intake check.
- **Weekly planning can't schedule a backlog PR;** it sends it back to the intake, which checks the rules and the CLA again on its current head.
- **The PR to close after a merge is only read from the fixed start of a finish task,** so text inside a task can't name another PR.
- **Attachments are handled defensively:** strict asset paths (`art|audio|content/…/lowercase.png|ogg`), URL-encoded API paths, downloads only from GitHub's file hosts (checked on every redirect), a bounded PNG decode with a checked header, one bad file only affects its own post, and the apply step checks (and re-encodes) every prepared file again.

## Owner: screenshots show what a PR changes

- **Every PR used to get the first 12 shots of every shot script,** whatever it changed. Now the session names the shot scripts that show its change (`screenshots` in its result, each with a caption; a revision may change the choice) and writes a new shot when none shows it. Only those run, on the PR and on `main`, and the comment shows each shot before and after (a new one alone), leaving out shots that came out identical. A change with nothing visible posts no screenshots.
- `build.sh --screenshots` writes `shots.txt` (which script made which PNG) and runs only `SHOTS_ONLY` when set. The daily Pages gallery is unchanged.

## Owner: four Discussions categories

- **Announcements** (the weekly devlog; the intake skips it), **Ideas**, **Spell combos** and **Art submissions** (attachments the intake can take as assets). Art feedback (never used; feedback goes in Ideas, art in Art submissions) and GitHub's defaults (General, Polls, Q&A, Show and tell) are removed by hand, since GitHub has no API for categories. The first devlog post (#101) was deleted; the weekly devlog continues.

## Owner: parked tasks are visible, and park for a day first

- **Why:** PR #156 (M2 part 20) failed the final review twice on consistency points (numbers in comments and docs that didn't match the code) and was parked for 7 days. Nothing said so where the owner looks, "revisited by the weekly planning run" wasn't true (planning can't clear a park), and the PR drifted into conflicts while the queue moved on.
- **Now:** two failed reviews (or conflicts) park a task for **1 day**; a third failure parks it for a week and mentions the owner. Every park is announced on the task's PR (a comment with the reason, the date and the review's points, plus the `parked` label) and in the Daily log; the daily summary lists all parked tasks. **`/retry`** on the PR (or the issue a task comes from) puts it back in the queue with two fresh attempts, the last review's points as its brief.
- #156 and four stale parks (tasks done or gone) were cleared by hand on 2026-10-22.

## M2 part 26: the art pass found two replacements, not quick fixes

- **Why:** the sheet showed that the frost and void colours need new palette ramps (STYLE.md says element colours are added to its table first), and element-coloured shots need a neutral bolt sprite. Both touch the palette and the art direction choice (part 27), so changing icons now would likely be redone.
- **Now:** two replacement tasks in `docs/NEXT.md`, to run after or together with the direction choice. Nothing in the game waits on them.

## M2 part 29: the builder walkthrough (four players)

- **Why:** the builder had only had tests and bot input. Walking it with real input at 640x360 (`shot_builder.gd`: overlay, Build, slot, component, tab, refusal, wave, break; one and four players) showed a clumsy order: it opened on tab A (two presses from the form slot), "Close" sat in the tabs row but was reached last, picking a form walked back to the chain for the element, and tabs and "Held >" left focus on themselves.
- **Now:** it opens on the form slot; "Close" follows the tabs in the focus order (the quick view keeps "Drop component", rows, "Close"); a tab, "< Up" and "Held >" put focus on the form slot of what they show; a form or element put into an empty slot moves on to the next slot's bag (the element, then the first free modifier), while a replacement or a refusal stays, so a second try is one press. A form plus an element is four presses after opening, not nine. Refusal texts say what to do: "Pick a form (F) first." and "Too complex: 13 of 12. Remove one." (three lines at most in the note).
- **Not done:** the mouse, and the wave line hidden under four open builders: see `docs/BACKLOG.md`, "From M2 part 29".

## Owner: Ice and Void ramps; the palette is the bot's to change

- **Why:** the frost, void and homing icons and the frost and void tints borrowed Player 1 and Player 4 colours, which STYLE.md keeps for players (#178, #179).
- **Now:** `docs/STYLE.md`, the `art/kit` palette files and the SVG art test carry an Ice ramp (`#1f7080` `#4fd6dc` `#c4f6f2`) and a Void ramp (`#4a1450` `#a0309a` `#e08ad8`), giving 37 colours. `ci/tests/test_styleguide.py` no longer pins the palette's size: it only checks that STYLE.md's table, both `art/kit` palette files and the SVG art test's list match. So the bot may add, change or remove colours without asking the owner, as long as it updates every copy. Recolouring the icons and tints is still the element colours task in `docs/NEXT.md`.

## 2026-10-23: Planning with an empty queue, M2 not closed yet

**Context:** Only the stabilisation task was left, and the daily run found no bug (`build.sh --quick --tests` passes, 4-bot p95 7.7 ms). M2's done-when item 3 (stress within budget on web) still has no WASM numbers: no "Daily run" post with "Stress and timing results" exists as of the 2026-10-23 daily log (#202). The art direction pick (#206) is open; nothing waits on it.
**Decision:** M2 stays in progress and no C2 issue is opened: closing it with the web numbers unread would put an unchecked done-when item in front of the owner. Two polish tasks go first (the wave and break lines hidden under four builders, a quick view walkthrough as the re-examination of part 18), so sessions have useful work while the next daily build runs. If the numbers still do not appear after a few more daily builds, the next planning run should ask the owner whether the web stress step runs.

## 2026-10-23: the wave and break lines go in the gap between the builders

- **Why:** four open builders leave 20 px at the top middle, so "Wave N" was hidden and "Build N" covered a builder's top row (this reverses the earlier "break line is drawn over the builders" choice).
- **Now:** one strip at the screen centre holds both lines side by side, in the 18 px gap between the top builders (end y 171) and the bottom ones (start y 189). Narrowing the builders by 10 px was not chosen: it costs builder width, and the gap is free. The gap fits about 17 px of text, so the wave line is 12 px (was 16) with a 3 px outline. Cost: during a wave the line sits in the middle of the arena, also with one player, and small; it has the same dark backing as the break line so it reads over enemies, but it can still cover a few pixels of play. If that hides play, the "Wave announcement" backlog item can move or fade it.

## 2026-10-23: the first WASM numbers; hit-work budget lowered

- **Why:** the daily log #202 has the first web results (M2 done-when item 3). Projectile timing in WASM at cap 1,000: `step` with fresh hits 5.5 ms, steady state 5.4 ms, `update_draw` 4.0 ms, homing 8.6 ms (about 2x native; `_hit_test` 63 us against 31 us). The web stress run in the CI browser: p95 151 ms, average 130 ms (78 frames in 10 s), with 100 enemies, 1,000 shots and four heavy builds; the Linux export ran the same scenario at p95 14.6 ms.
- **Homing breaks the 8 ms rule.** The M1 part 22 follow-up said: if the web step is over 8 ms, lower `WORK_PER_STEP` first, then `DEFAULT_CAP_WEB`. Homing at 8.6 ms is over. Worst steady case on the web, homing shots: 8.6 ms step + 4.0 ms `update_draw` = 12.6 ms of 16.7, leaving 4.1 ms for everything else (enemies, combat, particles, UI, four players). That is too little.
- **Decision:** `WORK_PER_STEP` goes from 8,000 to 6,000. Homing searches are paid from that budget, so the step should fall about in proportion (8.6 ms to roughly 6.5 ms, worst case about 10.5 ms, about 6 ms left). That is an estimate, not a measurement: the next daily web `BENCH:` lines confirm it, and if homing is still over 8 ms the next lever is `DEFAULT_CAP_WEB`. Normal play uses a tiny part of the budget; a packed crowd tests its shots over a few more steps. `DEFAULT_CAP_WEB` and `MAX_SHOTS` stay for now.
- **Open and unexplained:** the web stress frame (p95 151 ms, average 130 ms; the Linux export 14.6 ms) is about 9x over budget and we do not know why. The spell and projectile work measured in WASM (about 12.6 ms) cannot explain 130 ms. Software rendering in the CI browser (no GPU) is a guess, not a finding; enemy AI, combat and hit particles in WASM are not timed. The real-GPU frame rate is unmeasured too. This is not closed: a Queue task ahead of stabilisation times the rest of the frame on the web (NEXT), and the weekly playtest asks web players about frame rate in a busy room. If it is poor, lower `DEFAULT_CAP_WEB`, `MAX_SHOTS` and `MAX_FIRES_PER_STEP`, then the per-enemy step.

## 2026-10-23: the web stress frame read; the web projectile cap is 500

- **Why:** the Daily run post in #202 (11:23 UTC) has the first web `frame parts` lines (owner `/claude` on #4: do it now).
- **What the numbers say:** the hypothesis holds. Web, render loop off: physics step 14.3 ms avg, 21.4 max, 1.0 steps per frame (max 2), frame 16.7 ms: the game logic alone fills the budget. Drawn, the web scenario had p95 131 ms; with hit particles off the step was 19.8 ms and 5.5 steps per frame (92 ms); the desktop scenario in the web build had a 32 ms step and 8 steps (183 ms). So steps over 16.7 ms make the engine catch up with up to 8 steps. The parts are small: enemy step 0.8 to 0.9 ms, combat lookups 0.4 to 0.45 ms, Feel's step 0.05 ms; hit particles are not the cause (frames were worse with them off, which is noise or an effect of the catch-up). Renderer CPU is 1 to 2 ms. The rest of the 14 ms is the projectile manager (web: 3.8 ms steady, 7.5 ms with fresh hits at cap 1,000), spells and the engine. The homing step at cap 1,000 is 5.7 ms, under 8 ms, so the lowered `WORK_PER_STEP` (6,000) worked and stays.
- **Decision:** per the rule above (make the step cheaper, do not lower `max_physics_steps_per_frame`), `DEFAULT_CAP_WEB` goes from 1,000 to 500, and the web stress scenarios use the constant. Half the shots roughly halves the projectile cost, about 3 ms, which is an estimate, not a measurement. Linear combat lookups stay in the backlog (under 0.5 ms). `MAX_SHOTS` and `MAX_FIRES_PER_STEP` stay: spell hits are about 100 a second in the stress run, so the fire cap is not what costs.
- **Open:** the expected web step is about 11 ms (14.3 ms minus the estimated 3 ms), still tight on a slow device. The next daily web run decides, with one threshold: 12 ms or less with steps per frame near 1 is accepted; between 12 and 16.7 ms is a warning; over 16.7 ms means this fix was not enough. In both of the last two cases `MAX_SHOTS` and the per-enemy step are next (Blocked task in NEXT). A real-GPU frame rate still needs a human (BACKLOG).

## 2026-10-23: the web stress frame is measured in parts; nothing lowered yet

- **Why:** the task was to time the rest of the web frame, but no web run newer than the daily log #202 exists (that run is the one that made the 151 ms), and a session cannot run a browser. So the numbers cannot be read yet, and the `WORK_PER_STEP` check waits for them too.
- **Now:** the stress run (`tests/benchmark/`) carries the measurements, so the next daily web run answers. Per scenario: `BENCH: frame parts` (the probe: physics steps per drawn frame, physics process and process time from the engine monitors, renderer CPU time, draw calls) and `BENCH: stress parts` (enemy step, the combat lookups of that step, Feel's step; one pass over the crowd, timed with the clock). The web scenario runs three times: as before, with `RenderingServer.render_loop_enabled` off (nothing drawn, so game logic only; this replaces "low resolution", a stronger check for the same question) and with `Feel.particles_enabled` off (a new switch, default on, for the benchmark). The desktop scenario runs last.
- **The hypothesis, from the headless numbers:** the web scenario's physics frame is 5 to 6 ms headless (enemy step 0.4 ms of it, combat lookups 0.25 ms, Feel's own step 0.02 ms; the rest is the projectile manager, spells and physics). WASM is 2x or more, so a physics step of about 12 to 16 ms or over. When a step takes longer than 16.7 ms the engine runs extra steps to catch up, up to `max_physics_steps_per_frame` (8), so one drawn frame is about 8 steps: 8 x 16 ms is the 130 ms seen. The hypothesis only holds for a step near 16.7 ms (the catch-up needs a step at or over the budget). Lowering `max_physics_steps_per_frame` is not a free fix: whenever a step is longer than 16.7 ms it trades about 8 frames a second at full speed for more frames at less than real-time speed (the simulation falls behind the clock). The rule: if the web run shows steps per frame near 8 and a physics step (the probe's last-step reading) over 16.7 ms, make the step cheaper (the limits in `core/spells/limits.gd`, `DEFAULT_CAP_WEB`, `MAX_SHOTS`, `MAX_FIRES_PER_STEP`), do not lower the cap; only for a step clearly under 16.7 ms with steps per frame still above 1 is a lower cap harmless. Nothing was changed now. The timing pass (`stress parts`) is an extra pass inside the measured frame, taken on every 30th frame, so it can show in a maximum.
- **Cheap fixes now: none.** The headless numbers show no single hot spot: the combat lookups (`Array.find` per enemy, two per step) are 0.25 ms of 0.41 ms for 100 enemies and 0.85 ms of 1.2 ms for 200, so they grow with the square of the crowd but are small at the web crowd; they stay in `docs/BACKLOG.md`. Hit particles' own cost sits in the engine, so only the particles-off run shows it.
- **The real-GPU frame rate** needs a human with a browser; it is in `docs/BACKLOG.md` as a weekly playtest question. Queue task "Read the web stress parts" reads the next web run and keeps the stabilisation task from closing M2 before then.

## M2 part 18: the quick view walkthrough

- **Why:** the quick view had only tests and one staged shot. Walking a wave by real input (1 and 4 players, 1x and 4x) showed a stale focus mark after folding (the read-only form slot kept "> ") and focus on a greyed "Drop component" when a full spell folded.
- **Now:** both fixed (`set_quick` clears the mark and focuses Close when nothing can be dropped). Text size (10 px) and the corner's "Spell A/B" read fine at 1x with four players; left as is.
- **Not done:** (1) the disabled-slot hint: `UIFocus` skips disabled controls by design, so a hint needs a new way to read them, a core change bigger than a polish pass; the BACKLOG entry stays. (2) `swap` is ignored inside a menu (the wizard stands still there), so a player closes the quick view to swap. (3) the drop list names no slot. (4) read-only slots look greyed like disabled ones. (2) to (4) are in BACKLOG.

## Statuses are shown by Feel as an overlay read from Combat (#244, part 3)

- **Why:** the enemy's own `Sprite` already carries the telegraph (`modulate`) and the hit flash (`material`), so a status painted on it would fight both. The task named `gameplay/enemies/`, which does not exist; enemies are content plus `gameplay/ai`.
- **Now:** Feel keeps up to 16 tinted copies of enemy sprites (`STATUS_SLOTS`), made once and reused. `status_applied` starts one; every 0.1 s Feel asks the `Combat` autoload `status_left(enemy, id)` (a duck-typed read, like the projectile manager) to pick the first of `status_order` the enemy has, and the overlay ends when none is left. The hit flash hides it while it shows. Only one status shows at a time: freeze, shock, burn, hex, chill in that order.
- **Reactions** add a ring, a bigger burst (inside the particle limit), a hit-stop longer than a death's and shake, scaled by `reaction_power`.

## "Bag" replaces "Drop component"; no full editing in a wave

- **Why:** the name said nothing about why the action exists. The owner (`/claude` on #4) asked for a name that says what it does, with "Drop" clear inside it, reachable by every player in a room and in a wave.
- **Now:** the action is "Bag" in the overlay and the quick view; the list it opens is titled "P1 Drop" (the overlay title otherwise reads "MENU"). It opens in a wave for every player because the overlay is not gated by waves.
- **Full editing mid-wave: no.** The M2 design locks the Builder in a wave (the quick view is the in-combat form, "choices so far kept"), and a player in a menu stands still and can be hit; a full six-slot editor in combat would break that trade-off. The quick Bag view (list, drop) is the answer; a wider in-wave Bag is for the HUD/Builder usability task.

## 2026-10-26: M2 closed again for C2

- **M2 done:** all iterate tasks (#245, #244, #243) are built; the roadmap row reads "In progress, all tasks done, waiting for the checkpoint". Nothing from M3 is planned until the owner answers.
- **The checkpoint text is written, not yet posted.** This session cannot open issues (read-only token). The assessment and recommendation are in `docs/milestones/M2-spell-system.md`, "Checkpoint C2, second round", and the evidence in `docs/LOG.md`, "C2 evidence", "After the iterate round". Opening the issue is an unchecked task in `docs/NEXT.md` ("Open the C2 checkpoint issue"), for the first session with a token that can open issues; it is removed once the issue exists. The recommendation is go only conditional on the owner confirming item 3, because the stress numbers predate Lightning. The ROADMAP row keeps "In progress" because the site's roadmap parser (`ci/smbot/contribute.py`, owner-only) finds the current milestone by that phrase; a "Done" row made `test_the_real_plan_files_parse` fail on PR #263.
- **Idea #208 (pet):** deferred until M3's design is written (one-line note in `docs/BACKLOG.md`).

## 2026-10-26: a radial builder to try beside the list builder

- **Why:** the owner wants combining cards to be quick on a pad: a ring of cards under the right stick, the slots under the left, the triggers to put in and take out. Settled with a playable mockup first (tap B rather than hold, since B and the right stick share a thumb; both ring layouts; push right by default; an undo on LT; a held clear).
- **Now:** `hud/builder/radial_builder.gd`, made by `hud/panels` for each player and opened by B; the owner made it the default the same day, so every build uses it, and the pause menu's Sandbox page (`dev`, `preview`) switches back to the list builder (`builder_options_changed`). A push, a closed gap, an undo and a clear are each one change through a new intent event, `staff_cards_requested(player, staff, cards)` (sender hud, heard by player), rather than one `staff_change_requested` per moved slot. `core/input` gained `extra` (Y), `kind_prev` and `kind_next` (the d-pad only), `menu_move` and `menu_aim` (the sticks for a player's own open menu, captured or not) and `rumble`; `Spells` gained `component_stats` and hands the staff back in `staff_view` for the preview.
- **Not yet:** card counts and levels have nowhere to come from until M3's rewards fill the bag; the ring already groups a bag by id and level and draws both.

## 2026-10-27: one homing rule for every form

- **Why:** a homing beam looked for targets only 160 px away, a homing shot's range, while the beam is 240 px long; the far third of the beam never homed. The 160 was a default in the projectile manager that the beam took without saying so. The owner asked for one rule that new cards cannot get wrong, with the range on the Homing card, dashes and teleports homing too, and a random pick so a group of shots spreads over a group of enemies.
- **Now:** homing turns whatever its carrier moves toward a target in reach: what moves over time (a shot in flight, a dash of the wizard or of a shot) turns at the card's turn rate, what is over at once (a beam, a teleport) bends its way as far as its turn rate turns in `SpellLimits.INSTANT_HOMING_SECONDS` (`homing_angle`; 43 degrees for one card), so the card's turn rate and reach say everything. `StaffCompiler.homing_steers(motion)` says which forms, `homing_range(motion, ray_length, reach)` how far: the Homing card's `behaviour_reach` (the largest card's), and a beam or teleport at least as far as it goes. A form homing cannot steer (rune, orbit, wall...) lists the card as wasted and leaves it off the spell, so it no longer cuts damage or adds the homing look. The target is picked at random among those in reach, from a seed (the shot's sequence number, the beam's birth, the dash's tag), and kept while it stays valid; one search, `_home_pick` in `core/projectiles`, serves every case, and `set_homing`, `homing_point`, `homing_aim` and `home_velocity` take the range, the kept target and the seed with no defaults. Outside the manager's own shots, each homing thing holds a `Homing` (`core/spells/homing.gd`) with its numbers, kept target and seed, so a new kind of carrier holds one and calls `steer`, `point` or `aim`. `tests/content/spells/test_homing_forms.gd` checks every form card in the registry: a steered form must reach a target 20 degrees off its aim near the end of its reach, and an unsteered one must list the card as wasted.
- **Instant homing ends at its target** (2026-10-27, so a chain of teleports hops like a strike from enemy to enemy): a homing beam ends on its target, and a homing teleport whose target is within its distance lands at its edge (`SpellLimits.LAND_CLEARANCE` outside its hit circle); one further away keeps its distance, turned. A teleport's payload is cast by the wizard where they land, so a teleport in it hops on from there; after landing at an enemy, the wizard's next homing teleport picks another while one is in reach (`homing_point`'s `avoid`), as a homing shot picks a new target after a hit.
- **Pierce:** one Pierce card is one pierce (was two), so n cards are n pierces. The beam has no pierce of its own any more (it had 1 from the first tuning): a bare beam stops at its first target. The orbit keeps its 4, so its ring survives several hits.
- **Beams and pierce:** a homing beam bends onto its pick, and for each pierce it has bends on from there toward another (`SpellLimits.BEAM_LEGS` at most), as a homing shot picks a new target after a hit; past the last it goes straight on. A beam never reaches past its own `ray_length` (`ray_points` cuts it), even when its card looks further. The sandbox has four more training dummies round the first, to try these on.
- **Not yet:** a shot in flight picks from all around it, so a random pick can be behind it and it turns back; a cone in front would stop that if it plays badly.

## 2026-10-27: Spread belongs to the staff (owner)

- **Every shot a staff fires leaves up to the staff's `spread` degrees off its line, either side, at random** (`StaffBase.spread`, 0–45). The generator is seeded per cast (player, staff, cast count), so the same cast spreads the same way. It turns each shot after its card shape (a split's fan, a nova's ring), so a fan stays a fan. Moves, rain, walls and entities are not turned.
- **The carriers of a multicast leave along the same aim;** only the staff's spread sets them apart. `SpellLimits.MULTICAST_SPREAD` (12°) is gone. A `scatter` group still sends each carrier its own random way.
- **The `dev` and `starter` staffs have 0 spread** (they aim true). Staffs with spread come with staff types (M3): random, or high and upgradable to lower (docs/BACKLOG.md).
- **`ModifierBase.spread_mult`** (0–4, several multiply) scales the staff's spread for the next carrier: a factor, not a flat number of degrees, so a card is worth the same share on every staff and two of them stack without a floor. The first card to use it is Sniper.

## 2026-10-27: Return, slow and arc (owner)

- **The boomerang carrier is gone; `return` is a modifier behaviour** (`ModifierBase.Behaviour.RETURN`), so any shot that flies out can come back. `StaffCompiler.behaviour_runs(behaviour, motion)` is the one rule for which carriers run a behaviour (homing where it steers, return on a shot that flies out, arc on a shot in the air); a card that cannot run is wasted with its reason.
- **`ModifierBase.lifetime_mult`** (0.1–4, multiplies) lets a card change how long its carrier lives; slow is speed x0.3 and life x3.
- **`arc`** (`ModifierBase.Behaviour.ARC`): a shot zaps the nearest enemy within `behaviour_reach` `behaviour_strength` times a second (arc cards add up, at least `SpellLimits.ARC_MIN_INTERVAL` apart), at `SpellLimits.ARC_DAMAGE` (0.5) of its damage with its infusions, as a short ray (`CompiledSpell.arc_hit`, kind `ray`). No enemy in reach: it tries again next step. At most `SpellLimits.MAX_ARCS_PER_STEP` zaps a step. This is how slow orbs that emit lightning are built from cards: `slow · lightning · arc · bolt`.
- **A zap sets off `on hit` and chains for now** (owner): it uses the shot's trigger fires. Later that should come from a staff mod or a relic instead (BACKLOG).
- ~~**Growth hits harder**~~ (2026-10-27, #321): taken back the same day (owner). A grown shot already hits wider (its radius is its hit circle, and blocks enemy shots wider), so up to 4x damage on top for x1.4 mana outdid overcharge (x2 damage for x2 mana). **Growth is size only:** a wider hit circle, the same damage; damage boosts are overcharge's. `get_growth_of` keeps answering for the shot whose hit spent it.

## 2026-10-27: Shots glow (owner)

The owner asked for new looks for the carriers: smaller bolts with much longer tails, and infusions that glow. Claude made a live mockup (every carrier and infusion, today's look beside it, the glow soft, banded or off); the owner chose **soft glow**, was fine with an infused shot showing its player only in part of its tail, and left darker floors (so the glow carries) to level design.

- **Soft glow on spell shots only.** docs/STYLE.md banned glow halos and partial transparency; spell shots are now the exception, and the glow lives in the shader, never in an asset.
- **The glow is the shot shader's, not the engine's.** The game runs on the Compatibility renderer, where 2D HDR and environment glow are not something to count on, and a full-screen pass would light everything. `shot_core.gdshader` blends premultiplied: a shot's pixels are opaque (alpha 1) and the glow round them is added light (alpha 0), so the same pass and the same instance data draw both, with no extra node, and it costs only the shots' own quads.
- **The body:** a 3 px white-hot cross (a pixel more each side per zoom, so an orbit shot or a bigger bolt is a little bigger, not double); the ramp is the palette material the core's tint names (Fire, Spark, Ice, Void, Arc, Bone), a plain shot's its player's. The player's shadow-shade outline is gone: the glow does that work, and the player shows in a quarter of an infused shot's tail pixels.
- **The tail is about 48 px** (frost x1.2, lightning x0.7), drawn in a quad 72 px long with the shot 12 px from its front; at the spark pool's cap it shortens first, as the trail did.
- **The tail bends with the path.** The quad's alpha carries a bend code beside the kind (1 - (kind + code) / 16, the code below 0.5 so the kind still rounds back): an orbit shot's bend is 1 / its radius, any other shot's comes from its last step (the chord lags the heading by half the turn), so homing, spiral and return tails curve too. A turn of more than 0.5 rad in a step is a corner (a bounce) and draws straight; on a bend the tail covers at most 0.6 rad of the circle, so it stays in the quad.
- **Infusions shape the tail with their look kinds,** so no element is special-cased: sparks make it jagged and flicker the glow, gusts make it sway, flecks make it longer, pull gives the shot a dark heart and a dimmer glow.
- Beams, dashes and impacts (drawn by `gameplay/feel`) get the same look in a second part.
- **Part 2a: effects in the shot shader.** Feel's flares for players' casts and impacts are new kinds of the same shader (burst, ring out, ring in, rune burst, cast), drawn in one MultiMesh of 256 (about 850 bursts a second before the oldest is taken; under 1% of what the shots draw at their cap) with their age in the code slot beside the kind (as a bolt's bend). The projectile manager names the impacting shot's core colour and look (`impact_core`, `impact_look`, like `impact_form`), so a frost bolt lands in flecks and a lightning one throws sparks, in its own ramp. A rune traces itself onto the floor over its first quarter second (its age in the same slot; `_born` per shot). Enemy impacts keep their ember sprite; beam bodies and dashes are part 2b.
- **Part 2b: beams and dashes.** Beams (live `Line2D`s and the one-shot sprites) are drawn by a beam mode of the same shader: a one-pixel white-hot core, a breathing rim, motes, flares at both ends, the cast's card particles, a glow; lightning jagged, storm swaying, fire wavering, void dark-cored. The old flare, flicker and fade knobs keep their meaning but swell the rim and glow (`beam_swell`) and dissolve the pixels (`beam_fade`) instead of stretching the art, and `beam_alpha` is now the glow's strength. `form_shown` carries the cast's `look`, and `core/spells` sends it for a dash too (its length clipped to the walls), which Feel draws as a dash effect; the length travels in the zoom's place, 4 px a step, up to 252 px. A nova's ring is an effect in the element's ramp instead of the ring art. Screenshot sheets run Feel on game time (`drive_engine` off), since on a slow virtual display the real clock ends a tenth-of-a-second flash before the frame is drawn.
- **Effect slots are a setting** (owner, 2026-10-27: "Make a setting for effect slots (a slider)"). Settings in the pause menu has an "Effect slots" slider, 64 to 1024 in steps of 64, 256 by default: left and right move it (the menu's UIFocus navigator keeps the focus on it), `accept` steps up and wraps, up and down leave it. Each move sends `effect_slots_changed(slots)` (hud to feel; areas talk through events), and feel resizes its effect batch, ending the effects showing. Kept in memory until core/save, as friendly fire is. The numbers live in `core/settings/effect_slots.gd` (`EffectSlots`), which both read, because areas only depend on core (the owner asked whether that rule should go; it stays: a number two areas share belongs in core).

## 2026-10-27: Development and preview builds show every card (owner)

The owner found none of the new cards in the web development build. The Web preset carries the `demo` feature, so every web build hid the cards with `demo = false`, which new cards are told to leave (arc, bounce, double, ghost, growth, lightning, linger, overcharge, return, slow, sniper, spiral, triple). The owner chose a channel rule over marking the cards: `Registry.demo_only_for(demo_feature, channel)` limits only builds with the `demo` feature on a release channel (`nightly`, `stable`); `dev` and `preview` (`EVERY_CARD_CHANNELS`, the channels that start in the sandbox) show everything. What the public web demo holds stays a choice per card (`demo`), and a new card is never missing from the builds the owner plays.

## 2026-10-27: Every effect in the new style (owner)

The owner saw the old effects still in the screenshots ("I thought all VFX was replaced") and asked: "Replace all the old VFX with the new system! I only want the new style going forward!" Part 3a moves the rest of Feel onto the effect batch of the shot shader: hit sprays (`KIND_SPRAY`) and puffs (`KIND_PUFF`) instead of `CPUParticles2D` bursts, stone chips (`KIND_CHIPS`, the one effect that does not glow), reaction puffs and rings, the self-hit, heal and death rings, lightning's discharge (`KIND_ARC`) instead of `Line2D`s, and statuses as an effect that follows its character (`KIND_STATUS`, the element's own particles) instead of a tinted copy of the sprite. Reaction and status colours are not palette colours, so an `EXACT` look bit makes the ramp from the colour itself. The death animation is the dead sprite drawn by the shot shader's `dissolve`: white-hot, then pixel by pixel gone, never stretched or faded. `reaction_flash.gdshader` and the particle pool are gone; `particles_enabled` now switches the hit effects. The white flash and squash on a hit sprite stay (they are the sprite's own animation). The enemy's shot keeps its ember burst until enemies cast from staffs (the owner rejected a separate enemy look: enemies will fire spells like wizards, with an enemy ramp, mana, and enemy-on-enemy hits as a setting, default off).
- **Part 3b: the rest outside Feel.** The shot shader's sprite path gains `sprite_glow` (light round a sprite's own pixels, from its neighbours) and `dissolve_color`. Combo marks glow (their pictures get `PAD` empty pixels for it); a dash's three ghosts are solid copies turned to the player's colour and falling apart, the older the more, with a glow, instead of see-through sprites; decoys are solid, part fallen apart in their player's colour, with a glow, instead of see-through; familiars are orbit shots (white-hot core, a tail bending round the circle) instead of flat circles. The enemy windup telegraph is rebuilt when enemies cast from staffs (it will show the cast), so it changes then.


## 2026-10-27: Enemies cast from staffs (owner)

The owner: "I actually want the enemies to have their own staff and fire spells. That way we can easily make new enemy types, by adding a new sprite and giving them a staff with some combined spell on it." It was in "Later" for M3–M4; the owner moved it into M2 (phase F of docs/milestones/M2-staffs.md, before D3, so the stress run and the playtest see it). The owner's answers to the open questions, all final:

1. **Enemy spells carry an enemy ramp**, the new palette material Blight ochre (`#4d3f12`, `#a68a2a`, `#e3cf6b`), wherever a player's colour shows in a shot. It is far from the four player hues; it shares Spark's hue but is duller and darker, so part F2 checks at 1x that an enemy's plain bolt is not taken for a hit spark.
2. **Enemies pay mana like players** (a pool and a regen), so an expensive staff casts less often. This keeps a strong staff's strength in its cost, the same rule as for wizards.
3. **Enemy spells hitting other enemies is a setting, off by default**, in Settings, Gameplay, beside Friendly fire.
4. **Player cards only**, no enemy-only cards. The imp becomes something like `fire · bolt`, and its shot may feel different from today's (dmg 10, speed 140, life 1.25 s, radius 3.5, no knockback; a bolt is 5, 220, 1.2 s, 5, with knockback). Part F9 tunes the imp with cards and its staff's delay, never with a special case.
5. **Wizards take reactions** from enemy elements now, from the same reaction table.
6. **Caster-side cards work on enemies now** (dash, teleport, hook, swap, recoil, decoy, familiar, shield, hold...), with AI to use and aim them.
7. **The old enemy shot look goes:** the hostile batch, `imp_fireball.svg`, Feel's ember burst for enemy impacts, and the texture hand-off that served only them. The owner wants one look for every spell.

How it is built (parts F2–F10):

- **Caster rows, not more players.** A spell's caster is 0–3 (a player) or 4 and up (an enemy row; `ENEMY_CASTERS` is 256). Events keep `NO_PLAYER` for an enemy's cast, so no area can mistake an enemy for a player 4; the core handlers find the row from the tag. Rows are opened and closed by the AI (a free list), and each enemy uses one staff. 256 rows cover the 200-enemy stress scene; a spawn beyond that casts nothing rather than share a row.
- **The tag** gets an enemy bit (16) and the row in bits 21–28, so every tag still fits an `int32`.
- **The shader** chooses the enemy ramp with bit 7 of the instance red (the player and zoom use at most 6 bits), so the players' encodings do not change.
- **Shared limits** (beams, delayed firings) give enemies a capped share, so a crowd of casters never ends a player's beam or drops a player's firing.
- **The telegraph is a promise:** the windup waits until the cast is ready and the mana is there, so it never shows a cast that does not come.
- **Enemy shots keep hitting a little narrower than they look,** the fairness rule of "The look of a shot".

## 2026-10-27: The enemy ramp is a look flag (staffs F2)

- **Not bit 7 of red, as planned.** The red byte holds the player and the zoom, and a dash's or arc's length travels in the zoom's place in steps of 4 px up to 63 steps, so every bit of red is used. The enemy ramp is a flag in the look instead: kind 23 (`LOOK_ENEMY_RAMP`, `1 << 22`), beside Feel's `EXACT` (kind 24). The particle kinds stop at 12, so ten are still free between them.
- **One encoder:** `ProjectileManager.look_color(player, zoom, look)` (with `look_red` and `ramp_look`) writes the instance colour for the manager's shots, Feel's effects and Entities' familiars, so a caster below 0 is drawn in the enemy ramp everywhere once its shots reach the shader (F4, F7). The players' bytes are unchanged.
- **Blight ochre** is the shader's fifth ramp (`ENEMY_PLAYER`), `ENEMY_COLOR` and `tint_of(NO_PLAYER)`; an enemy's beam is `beam_player` -1. The 1x check that an enemy's plain bolt does not read as a hit spark waits for F4, when enemy shots are drawn by the shader.

## 2026-10-27: Enemy casters in the projectile manager (staffs F4)

- **A caster number, not a fifth player.** A shot's owner is 0–3, an enemy caster row (`FIRST_ENEMY_CASTER` 4 to `CASTERS - 1`, 256 rows, matching `SpellTag`'s enemy rows) or `NO_PLAYER`. Every check that meant "a player's shot" is `is_player_caster`, every one that meant "an enemy's" is its opposite, and every event names `event_player(caster)`, so listeners only ever see 0–3 or `NO_PLAYER`.
- **Sides, not special cases:** homing skips its own side (`side_layer`), a shield blocks the other side's shots (each side's list made once a step), a mend shot's allies are its own side, `enemy_fire` mirrors `friendly_fire`. `NO_PLAYER` (the AI's old attack) keeps its old rules until F9: no anchor, no shield, no enemy fire.
- **One drop bucket for all enemies,** as before, so a crowd of casters never drops a player's shot at the cap.
- **One more batch, not three:** the shader reads the body kind per instance, so every enemy caster's bolt, rune and orbit shot goes in one batch one layer above the players'. The timing run is within noise of main (cap 500 `update_draw` 1.6–1.8 ms, the fresh-hit step 2.9–3.2 ms).
- **The 1x look:** the looks sheet has an enemy caster beside the four players. Its tail pixels are a dull ochre and brown, apart from the players' colours; a plain enemy bolt's head is a pale yellow near Spark's gold, its tail is what tells it apart. The owner judges it on the sheet.

## 2026-10-28: Enemy casters in the spell runtime (staffs F5)

- **`player` in `Spells` is a caster number.** Every array is sized for the 4 players and the 256 enemy rows (1,040 staffs), so an enemy goes through exactly the code a wizard does: the same compiler output, cast, payloads, chains, beams, holds and moves. No enemy-only branch decides what a card does; only where a caster's side matters (what it hits, `_foes`; what events call it, `_ev`; whose budget it spends, `_budget`).
- **Rows are opened, not assigned.** An enemy asks for a row when it spawns and gives it back when it dies, so 256 rows serve any number of enemies over a run. The row closed longest ago is handed out first, and each staff keeps its place on the generation ring (`_ring`), so a reused row's new build never takes the tag of the dead enemy's shots still in the air (they would otherwise be revoked).
- **A closed row is out of range,** so a stale caster number cannot build or cast; its shots keep their numbers until they end.
- **Shares:** all enemies share one per-step fire count and one chain count (one player's worth), hold at most 16 of the 64 live beams (an enemy's beam only ever ends another enemy's) and 32 of the 128 waiting launches. These are engine safeguards, as the players' are; the stress run (F9) checks them.
- **What the AI reads instead of events:** siphon refunds wait in `take_refund`, reservations in `reserved_mana`, and the next cast's cost in `next_cast_mana`; `mana_reserved` and `mana_refund_requested` stay the players'.
- **Not yet:** `on hurt` and `relay` stay the players' (they listen to wizards' events); an enemy's decoys and familiars are asked for with `NO_PLAYER`, which Entities ignores until F8; combat still treats a `NO_PLAYER` area hit as hitting enemies until F6.

## 2026-10-28: Wizards react, and area hits take sides (staffs F6)

- **Wizards react to every spell, not only to enemies'.** The owner asked for wizards to take reactions from enemy elements (decision 5 of "Enemies cast from staffs"). Combat makes that one rule for every target: a wizard's statuses react with a hit's elements from the same table as an enemy's, whoever cast it, so friendly fire and self-harm (`fire` on yourself, then your own `frost`) react too. An enemy-only branch would be a special case the owner does not want ("one general rule").
- **Each effect on a wizard is the enemy's, on the wizards' side:** CONSUME hurts the wizard (double when frozen), BURST hurts every wizard in its circle (it never reaches enemies: it is the side the spell was against), EXTEND lengthens or freezes, SPREAD copies the status to the wizards near. A wizard waits `REACTION_WAIT` (0.5 s) before reacting again, as an enemy does. Reaction damage carries no spell tag (no `on hurt` credit, no kill), as on enemies.
- **`reaction_landed` on a wizard names the caster's tag,** so an enemy's `on reaction` cards fire from it.
- **An enemy's area hit** hits every wizard in its circle, other enemies only with `enemy_fire`, never the enemy that cast it (its body is owned by its caster row, `set_target_owner`, from F8). A player's is unchanged.
- **Not yet:** an enemy's mend heals nothing (combat has no enemy heal); area hits do not reach decoys (they are Entities' targets, hit only by shots).

## 2026-10-28: Enemy spells look like spells (staffs F7)

- **No enemy special case in Feel.** An enemy's impact, nova ring, dash and beam take the same path as a wizard's, with NO_PLAYER as the player: the effect batch and the beam shader turn that into the enemy ramp (F2's look flag; `beam_player` -1). The ember burst for enemy shots is gone, so the AI's old shot (until F9) lands in a plain burst in the enemy ramp too. A hit spray on an enemy's body and its death puff keep `enemy_hit_color`: those are the enemy's own colours, not its spell's.
- **The enemies share one player's worth of beam sprites** (24), so a crowd of casters never takes a player's.
- **A rain shows a marker,** for wizards and enemies alike: a ring closing on its point for the seconds until it falls. Feel drew nothing for `rain` before, which an enemy's rain would have made unfair.
- **The hostile texture hand-off stays until F9,** with the hostile batch it serves (the AI's old shot still uses it).

## 2026-10-28: Enemies cast their staffs (staffs F8a)

- **The staff is data on the enemy type** (`EnemyBase.staff`, `cards`, `max_mana`, `mana_regen`), so a new enemy is a sprite and a `.tres`, as the owner asked. It is compiled once per type and installed into each enemy's own caster row, so 200 imps share one compiled staff but each has its own delay, cycle and generations.
- **The telegraph is a promise:** the windup starts only when the next cast can leave as it ends (its delay no longer than the windup, its mana there), and the enemy holds in reach until then. A refused cast after a telegraph would teach players to ignore telegraphs.
- **The aim is locked through the windup and the recovery,** so a beam the enemy holds follows where it aimed, not the wizard; it follows the target again once the enemy chases.
- **F8 is three parts:** the casting (F8a), the telegraph in the new style (F8b, Feel) and caster-side cards on enemies (F8c, with Entities), so no PR touches two areas' internals at once.

## 2026-10-28: The telegraph in the new style (staffs F8b)

- **A beam mode, not an effect.** The effect batch has no kind left (the alpha holds kinds 0 to 15, all used), so the telegraph is beam mode 3 of the shot shader on the enemy's own `Telegraph` sprite, as Feel's beam sprites are mode 2. It needs no event and no Feel slot, and it goes when the enemy goes.
- **What it shows:** the next cast's reach, a lane as wide as what is coming plus 4 px each side with dotted edges, dashes down the middle that march toward the tip as the windup runs, an arrowhead that grows, and a lane that brightens, white-hot for the last fifth (as the pose already does). Fire colours (docs/STYLE.md: enemy telegraphs use Fire), so a telegraph is never taken for an enemy's spell (Blight) or a player's.
- **Each enemy's material is its own** (`resource_local_to_scene`), since every telegraph has its own progress.
- **A gotcha:** a `vec4` shader parameter saved in a `.tscn` must be a `Vector4`; a `Color` there is dropped on load (it reads as null), though `set_shader_parameter` with a Color works from code.
- The shooting dummy keeps its Void telegraph, so the sandbox's two lanes stay told apart. `art/vfx/telegraph_dash.svg` is no longer in a scene; the art sheets still show it.

## 2026-10-28: Moves on enemies (staffs F8c)

- **The enemy answers its own row's moves as a wizard answers its own:** the same modes, the same distances (a dash from the staff tip, a pull to the point), the same end-point answer, so a card's blast or `on expire` goes off where the enemy lands. Walls stop it because it moves through `velocity`, as it walks.
- **No separate move AI yet:** a staff's move is aimed at the target like any cast (a dash or teleport goes toward the wizard). Moving away, or around, is a later choice for staffs that want it; the owner's "AI to use and aim them" starts with the aim every cast already has.
- **Barriers on the caster** (a shield on a dash or on the caster) are not built for wizards either (nothing sends `wizard_shield_requested` yet), so enemies get them when wizards do.
- F8 grew a fourth part: decoys and familiars for enemies (F8d, Entities).

## 2026-10-28: The telegraph gets its own shader (preview build fix)

- **The preview build failed** after F8b: the web stress run did not print `STRESS OK` within its 600 s. In the browser (CI's software renderer) a rendered frame went from about 0.5 s to 1.7 s, while the game logic (the render-loop-off run, the stress parts) barely moved. Every imp in the crowd winding up drew a 165 × 32 telegraph with the whole shot shader, so each of those pixels cost what a shot's does.
- **The telegraph is now `gameplay/ai/telegraph.gdshader`**, a shader of its own with the same look (the ramp's base and light, hot halfway to white, the glow, premultiplied), its ramp set in the scene as `ramp_base` and `ramp_light`. Beam mode 3 is gone from the shot shader, which is back to what it was before F8b. This replaces F8b's "a beam mode, not an effect": being a sprite of the enemy's own still holds, only the shader changed.
- **Measured** (the same local machine, the exported Web Test build in headless Chromium on SwiftShader, as CI runs it): a drawn frame of the web scenario 1,112 ms before, 706 ms after (p95 1,591 to 836); the desktop scenario 4,263 to 2,749 ms; the whole stress run 10 min 49 s to 7 min 23 s. The render-loop-off run, which is game logic, did not get slower.
- **The web stress run's timeout goes from 600 to 900 s** (`tests/build.json`). Before F8b it already took 356 s of its 600 in CI, and it measures 73 frames of each scenario however slow the software renderer draws them, so more content keeps creeping toward the limit. The job's own limit is 60 minutes. The budget warnings (`BENCH WARNING`) are untouched: they are what says the game got slower, not this timeout.

## 2026-10-28: Decoys and familiars for enemies (staffs F8d)

- **The same entities, the other side.** An enemy's decoy and familiar are a wizard's with the sides swapped: the decoy is a target on `LAYER_ENEMY` owned by the enemy's caster row (wizards' shots hit it, their homing and familiars pick it, its own enemy's shots pass it) and only wizards' shots wear it down; the familiar casts at the nearest wizard or wizard's decoy. Both are in the enemy ramp (Blight), the decoy copying the enemy's sprite.
- **Enemies never chase an enemy's decoy:** `lure` looks at wizards' decoys only, so a decoy card on an enemy is a distraction for wizards' aim and homing, not for the crowd.
- **A share of their own:** two of a kind per enemy, in 32 rows after the players' 32. A crowd of casters fills only those; then the oldest enemy entity ends (with `entity_ended`, so Spells' count of live shots stays right). Wizards always get all four of each kind.
- **They end with their enemy.** A wizard's familiar stays when its wizard is gone, but an enemy dies for good, and a `hold` familiar of a dead enemy would cast at wizards until the room ends. The AI ends its entities where they are as it closes its row (`Entities.enemy_gone`), with `entity_ended`, so their `on expire` and blast still go off there.
- The AI hands Entities its body directly (`set_enemy`): both are `gameplay/ai`, so no event is needed.

## 2026-10-28: The imp and the shooting dummy on staffs (staffs F9a)

- **F9 is two parts:** the enemies move onto staffs (F9a, content and tests), then the unused old attack goes (F9b: `ATTACK_TAG`, Combat's table, the attack exports, `imp_fireball.svg`, the hostile batch), so each PR stays readable.
- **The imp casts `fire · bolt`** (owner decision 4): 5 damage and a burn instead of the old 10, 220 px/s for 1.2 s instead of 140 for 1.25, radius 5 instead of 3.5 (a wizard clears it with a 13 px sidestep instead of 11.5), with knockback. 10 mana and 3 a second back: one cast every 1.7 s or so once its two full-mana casts are spent, about the old windup plus recovery (1.75 s).
- **The shooting dummy casts `slow · bolt`**: 66 px/s for 3.6 s (the old shot was 70 for 4), 5 damage (was 6), no element, so it stays a plain target for practising shields and blocks. 5 mana and 2 a second back: about one cast per windup plus recovery (2.75 s). Its telegraph stays Void, so the sandbox's two lanes stay told apart.
- **Each staff is a sub-resource of its enemy's `.tres`:** an enemy type is still one folder, and no other content shares these staffs.
- **The stress run at the web cap** (headless, same machine, before and after): web scenario frame 7.38 to 7.20 ms avg, p95 15.7 to 14.2 ms; one pass of the enemy step over 100 enemies 0.86 to 1.13 ms (the staff's mana, anchor and aim each step); enemies and shots at 100% of their targets. The desktop scenario was the same before and after.

## 2026-10-28: The old enemy attack removed (staffs F9b)

- **Gone:** the AI's own shot (`ATTACK_TAG_BASE`, `attack_tag`, the `attack_damage`, `attack_speed`, `attack_lifetime` and `attack_radius` exports), Combat's hit table (`set_hit_profile`, `clear_hit_profile`), the projectile manager's sprite batch for NO_PLAYER shots (`hostile_texture`, `drawn_hostile`), Feel's preset `hostile_texture` and `art/vfx/imp_fireball.svg`. `attack_range`, `windup_time` and `recover_time` stay: they pace a staff's casts.
- **Every hit now has a spell's profile.** Combat asks `Spells.hit_profile(tag)` for every shot; a tag without one does nothing. Tests that used the table as a quick "shot that does N" register a hit profile in Spells instead.
- **An enemy without a staff only chases** (and hurts by touch, if its data has `contact_damage`). The same holds when every enemy caster row is taken.
- **A NO_PLAYER shot is drawn as an enemy's spell:** in the enemy batch by the shot shader, in the enemy ramp, with a tail, and its impacts name its body's form (`bolt`), not `&""`. Nothing in the game spawns one any more; tests and tools still may.

## 2026-10-28: The enemy-fire setting (staffs F10)

- **Settings > Gameplay > "Enemy fire: Off/On"** (owner decision 3): off by default (`EnemyFire.DEFAULT` in `core/settings`), so a crowd of casters never thins itself. On, an enemy's spells also hit other enemies, never the enemy itself; it applies to shots cast from then on, as friendly fire does.
- **The AI area owns it, in Entities** (its one autoload), the way coop owns friendly fire: `enemy_fire_requested(player, on)` from the pause menu, the projectile manager's `enemy_fire` set, `enemy_fire_changed(on)` back to the menu, whose word follows the answer, never the press. Kept in memory until core/save exists, as the other settings are.
- That ends phase F: enemies cast player-card staffs, pay mana, telegraph each cast, move, make decoys and familiars, and with this setting may hurt each other.

## 2026-10-28: The web stress run skips the desktop scenario

- **The daily build failed** at the web stress run's 900 s timeout (run 40663824357), and the bot's bisect reverted the last merge, F10 (#351), though the enemy-fire setting draws nothing. The run is just slow: under CI's software renderer each of its 73 measured frames of the desktop scenario (200 enemies, 3,000 shots) took about 6 s, about seven of the run's fourteen minutes, so runner speed alone decided pass or fail.
- **A web build now runs the three web scenarios only** (`StressRunner.scenarios_for`): the desktop scenario is the desktop's budget, and the desktop export measures it. The Linux export still runs all four, and the headless unit test too.
- F10 comes back as it was, in its own PR.

## 2026-10-28: Actors (actors G1, the plan)

- **Why:** phase F gave enemies staffs in ten PRs, most of them teaching core that a caster can be something other than "player 0–3". The player index meant four things (seat, side, look, budget); the caster kit, mana and aiming were written twice, and Combat kept two body models whose status rules had drifted apart. The owner asked whether a player could be "just an entity with a HUD and a player controller" and an enemy "an entity with an AI controller and no HUD", swapped by moving nodes.
- **A component architecture** (owner): an actor is a body of components (Health, Hurtbox, Contact, Mover, Caster; Downed and a look for wizards) driven by one controller (`PlayerController`, which is the seat; `AIController`). Components hold configuration and behaviour; Combat, Spells and the projectile manager keep the hot state in packed arrays indexed by one actor id; only the actor runs `_physics_process`, stepping its components in a fixed order. Design: [M2-actors.md](milestones/M2-actors.md).
- **No sides** (owner: "Everything should be able to damage everything. So there should be no sides."): friendly fire and enemy fire are always on and both settings go (G3c). DESIGN.md's spell rule changed to match ("Everything hurts everything").
- **Teams only aim** (owner): the AI's target, homing, chain and arc, familiars and the decoy lure pick another team; damage never asks. The team follows the controller, so a possessed body aims for its driver; an AI hurt by its own team may turn on the one who hurt it.
- **Combat, one rule each** (owner, the recommended set): shock jumps to the nearest other actor; static discharge goes off on any hit, arcs to the victim's other-team actors and is always spent; hex pulls; pull and shields work on every actor; the complete later-status loop; quiet burn ticks.
- **Possess is a card** (owner: "Make this a card! A possess card, possess enemies hit for x seconds"): the hit actor is driven by the caster's controller for its seconds; the caster's body stands, vulnerable. Enemies may possess wizards by the same rule (owner); the D3 playtest asks about it, as it is the nearest thing to making a player wait.
- **Order:** G2, then G3a, G3b and G4 in parallel (G3c independent), G5 to G10 in turn, all before D3.

## 2026-10-28: The actor table (actors G2)

- **`core/actors` (autoload `Actors`)** holds every actor's id (0–511), team, ramp and seat in packed arrays (docs/milestones/M2-actors.md). Ids are handed out lowest free first, so a run is the same every time. `budget_of` is the seat while a seat drives the actor, else `SHARED` (4).
- **A seat drives one actor at a time; the newer driver wins.** Seating an actor (`open` with a seat, or `set_driver`) takes the seat from whoever held it, which is left unseated. A possession moves the seat in one call, and the actor left behind needs no second call to stop being driven.
- **The tag has one caster field:** staff bits 0–1, generation 2–4, node 5–13, caster 14–22 (every actor id), `FLAG` bit 23 (still above the AI's old attack tags), all below `LIMIT` 1 << 29 so Combat's int32 shield tags still hold them. `make` keeps its argument order (caster, staff, node, generation), so no caller changed meaning. `make_for`, `make_enemy`, `is_enemy_tag`, `player_of`, `row_of`, `FIRST_ENEMY_CASTER` and `ROW_MASK` stay as deprecated wrappers with the same answers until G3a and G3b move their callers; `ENEMY_BIT` is gone (only a test used it).
- **Spells keeps its caster numbers in G2.** Players are still 0–3 and enemy rows 4–259 (oldest closed first), so every array sized `CASTERS`, every event and every test is unchanged; each open enemy row also opens an actor (the enemies' team, `RAMP_ENEMY`, no seat) and records its id (`actor_of_caster`). The other route, reserving actor ids 0–3 for the seats so the numbers matched, would have tied the table to the seats and changed the row order; G3b switches Spells to actor ids outright instead. A full table leaves the row casting without an actor (nothing reads the id yet), and `clear` and freeing the runtime close its rows' actors, so a test's runtime never leaves ids open in the shared table.

## 2026-10-28: The actor kit (actors G4)

- **`gameplay/actor/` is the shared body kit** (docs/milestones/M2-actors.md): `Actor` (the root of an actor scene), `ActorIntent`, `ActorController`, Health, Hurtbox, Contact, Mover, Caster and the bases `ActorComponent` and `ActorLook`, each with a `class_name` so scenes and tests use them by type. No scene uses it yet: enemies move onto it in G6, wizards in G7. Every area may use its public scripts (gameplay/README.md's one stated exception).
- **One seam to Spells' numbering.** The actor opens its own id in `Actors`; what it casts under is `Actor.caster_number()`: until G3 a seat's 0–3, or an enemy row (`Spells.open_enemy_caster`, which opens a second actor of its own for now) for an actor no seat drives at home. After G3 it is the actor id, a one-line change.
- **Combat's actor API** (`register_actor`, `unregister_actor`, `pace`, `consume_knockback`) is four small functions over the enemy model for now; G5 reimplements them by actor id. Health is fed by `damage_dealt` and `heal_dealt` with the actor as target until Combat calls it.
- **The caster kit is one implementation.** The wizard's and the AI's copies differed; one rule each, following the owner's "one core rule, no special cases" (2026-10-27):
  - **Whose move:** a request is the actor's when its tag's caster is the actor's caster number. The event's player argument is not asked (the wizard asked it, the AI asked the tag), so it holds unchanged when G3 makes events carry the actor id.
  - **Dash direction:** the way the intent walks; standing, the way the actor aims. A walking wizard dashes as before and a standing AI along its aim as before; a standing wizard now dashes along its aim instead of its last walk direction, which is the same unless it aims with the stick or mouse.
  - **Pace:** chill and freeze scale walking and a dash (the actor's own legs), not a hook, a swap or a recoil (the spell moves it): the wizard's rule. A frozen enemy no longer dashes.
  - **Homing dash** (`Spells.move_homing`) for every actor, as wizards had it.
  - **Recoil:** the recoils of one step are added up (`mirror · recoil` cancels) into one push over the longest time asked; at most 8 run at once and a push past that is dropped (the wizard's; the AI kept 4 and added the extra to the last).
  - **Exact distance:** a move's and a push's last step is shortened, so each goes exactly its distance even when its time is not a whole number of steps (the AI did this for moves, the wizard for pushes only).
  - **Answers:** a dash, hook or teleport answers `caster_move_finished` (a teleport at once, the others the step after their last); a replaced move is answered where the actor stands, also when it had arrived and its answer was due (the AI lost that answer).
  - **Teleport and recoil are measured from the staff tip** (`muzzle_position`), as both copies did; a cast leaves from the staff tip clipped to walls from the feet for every actor (the AI did not clip).
  - **Swap as target:** `target_move_requested` naming the actor puts it there at once for every actor (the wizard ignored it).
  - **Down:** a down actor stands; its move ends unanswered and its recoil is dropped (the wizard's).
- **Casting from the intent:** a staff casts when pressed this step, or while held unless it holds a sustained card on (then only a new press switches it off). The input buffer and the press counting stay the player controller's (G7).
- **One compiled-staff cache for every caster**, keyed by the Spells, the staff and the cards (the AI's was per enemy type), cleared past 256 entries.
- **Actors are on no physics body layer** and collide only with walls: they walk through each other, and spells find them by the hurt circle.

## 2026-10-28: No more fire settings (actors G3c)

- **The owner:** "Everything should be able to damage everything. So there should be no sides." Friendly fire and Enemy fire are no longer settings; both are always on.
- **Gone:** `Projectiles.friendly_fire` and `enemy_fire`, `Coop.set_friendly_fire`, `Entities.set_enemy_fire`, `core/settings/enemy_fire.gd` (`EnemyFire`), the events `friendly_fire_requested`, `friendly_fire_changed`, `enemy_fire_requested` and `enemy_fire_changed`, and the pause menu's Gameplay page (it held only those two rows; Settings is now Fullscreen, Effect slots, Back).
- **The hit rule is one rule:** every shot and beam hits both actor layers (`ACTOR_LAYERS`), whoever cast it: a wizard's hits the other wizards, an enemy's the other enemies, a NO_PLAYER shot both. Only targets the caster owns (its body, its decoys) are skipped, as before, unless the shot is self-hitting. An area hit lands on every wizard and every enemy in the circle, the enemy that cast it included (its blast at its feet hurts it, as a wizard's always did); an enemy's mend still heals no wizard. Every hit wears a decoy down, whoever's it was.
- **Teams only aim:** homing, chain and arc jumps, familiars, lure and the AI's target still pick the other side; nothing that decides whether a hit lands asks.
- **No shot passes a teammate any more,** so the projectile manager's pass (`ally_passed`, `set_ally_hit`, `F_ALLY`) is gone. Spells still answers `ally_passed` (the `relay` modifier and the `on ally` trigger, which no shipped card uses), but nothing sends it: what they mean with no passing is for a later part. Their tests send the event by hand.
- **An enemy's own shots still skip its body,** as a wizard's do: no card sets self-hit for anyone yet.
- **The stress run** (headless, the same machine, main after G2 and this branch run alternately, twice, with other sessions on the machine, so the noise is a millisecond or two): web scenario frame avg 6.9 and 9.5 ms before, 9.3 and 8.2 after, p95 14.3 and 17.3 before, 17.0 and 16.4 after; spell hits in the measured window 1,577 and 1,430 before, 2,018 and 2,089 after (enemies' bolts now stop on the enemy in front), reactions up too; one pass of the enemy step about 1 ms both. The desktop scenario (200 enemies, 3,000 shots) avg 77 ms before and 110 and 155 ms after, p95 about 200 ms either way, with about 1,100 hits before and 1,700 after: the extra hits cost there. Enemies and shots at 100% of their targets in every run. Nothing lowered; if the web frame shows it, the answer is in the hit path, not a setting.

## 2026-10-28: on ally removed, relay on any actor (actors)

- **Why:** with friendly fire always on (G3c), a shot hits a teammate instead of passing through, so `on ally` ("the shot passes through a teammate") and `relay` (takes the passed teammate's infusions) had no trigger left.
- **`on ally` is gone** (owner): as "hits a teammate" it was `on hit` limited to one team, the only trigger that asked about teams, and its support use (`on ally · mend · bolt · nova`) now hurt the friend first. Nine triggers remain.
- **`relay` works on any actor a shot hits** (owner): the shot takes on the infusions of that actor's last cast. A teammate's frost as before, or an enemy's element taken off it; one rule, no teams.

## 2026-10-28: The VFX as the mockup draws them (owner)

The owner compared the game with the carrier mockup (2026-10-27) and listed what was missing: tails turned with the shot (bad on homing shots), the orbit did not grow out from the wizard or end in anything, beams did not move and lacked the mockup's crisp pixels, the dash look went another way than the wizard, and the bolt's tail did not leave its little cooling pixels behind. "Please go over them, and make this right."

- **Trails, not tails drawn round the shot.** The tail was drawn in a quad that turned with the shot, bent by its last step only. Now the projectile manager keeps each flying shot's path (`TRAIL_SAMPLES` = 32 points, one every 1/30 s plus every bounce, blink and end, each with how far the shot had gone and when) in one data texture, and the shader leaves the tail where the shot was: one pixel per pixel of travel, thrown back and drifting a little, cooling in its own 0.1-0.3 s (the mockup's numbers), so a tail follows any path and frays by itself. The card particles are born along the path the same way (embers rise, flecks hang, gusts blow back and curl, sparks jump, void pulls in to the shot, a plain shot's twinkles rise), each numbered by its moment so it is the same particle from frame to frame. A trail outlives its shot by `TRAIL_KEEP` (1 s) so a tail cools where the shot hit; rows are 2 x the cap, and a shot with none is drawn by its core alone.
- **On the world's pixel grid.** Everything of a trail is drawn axis-aligned on world pixels (the quad was turned with the shot, so a diagonal core was an x and lines doubled): the core is always a `+`, lines are one pixel per step. Beams likewise: one pixel per step of the longer axis whatever their angle (a `round()` tie at a pixel edge drew the core two pixels thick), and their flares are upright crosses at the world points Feel hands over.
- **Beams move.** No beam material was ever given `sim_time`, so the breathing rim, motes and flicker stood still. Feel now sets it every frame; a beam also splashes sparks back where it lands.
- **Orbits spiral out** from the caster over `ORBIT_GROW` (0.25 s), drawn only: the shot hits at its circle from the start, so rings hit as before. Any bolt or orbit shot whose life runs out pops in a small flare of its own (`projectile_expired`; a wall end keeps its impact, a rune its burst).
- **The dash is drawn where the wizard goes.** Feel drew it along the aim; the wizard dashes the way it walks (and homes, and slides on walls). `core/spells` now opens a caster trail (`follow_caster`) that follows the caster's anchor for the dash's time: speed streaks in the player's colours and the cards (flames on the floor, frost that stays a while). Feel keeps the dust where it left (`KIND_DASH`) and lands it on `caster_move_finished`: a ring, lightning's arc from the start, an infused flare.
- **Cost:** at the web cap the step is about 0.2 ms and the draw about 0.4 ms dearer (sampling the paths, writing the texture). On the GPU each trail's quad is fitted round its path in the vertex shader and a pixel walks at most the path's 32 pieces, skipping those out of reach.
- Familiars still use the older bent-quad look (`KIND_ORBIT`); they circle forever, so the bend is exact for them.
- The clip stage now gives Feel the spell runtime, so live beams show in the clips (they never did).
- **The combo marks are gone** (the owner: "needs to be either reworked or removed ... if they are worth keeping, then rework them to look better in the new vfx style"). They came from the recipe builder (#244): a glowing picture (sun, chevrons, diamond, clock, ring) stamped on the wizard for any cast that was more than a plain shot. On staffs every shot already shows each of its cards as its own particles, and a payload shows when it fires, so the mark only repeated that, and its glow at 2x washed out the wizard. Removed with them: `combo_cast`, `Spells.combo_class`, `combo_marks.gd`, `FeelPreset.combo_mark_seconds` and the `combo_marks` sheet.

## 2026-10-28: Core by actor (actors G3a, G3b)

- **The caster number is the actor id everywhere in core** (docs/milestones/M2-actors.md, "Core: the actor table and one caster number"). Spells and the projectile manager size their per-caster arrays by `Actors.ACTORS` (512) and index them by actor id; tags carry it (`SpellTag.make`, `caster_of`; the deprecated wrappers, `FIRST_ENEMY_CASTER` and the split limits are gone). A body opens its own id: a wizard in `_ready` (`actor_id`: the wizards' team, ramp and seat of its index), an enemy that casts a staff (`caster`: the enemies' team, `RAMP_ENEMY`, no seat), every actor of the kit (`id`). Spells has `open_caster(id)` (a clean row) and `close_caster(id)` (staffs, waiting launches, holds and beams end; shots in the air fly on) instead of enemy rows.
- **Core never asks "player or enemy"; it asks the table one of four questions:** damage asks nothing (every spell hits both actor layers; only the caster's own body is skipped); aim asks the **team** (homing, chain and arc jumps, familiars and shields: a shield stops every shot of another team, a shot of no actor included); looks ask the **ramp** (batch, `look_color`, `tint_of`; `PLAYER_COLORS` is now `RAMP_COLORS`, four hat colours and Blight, and the shader's encoding is unchanged: two bits and `LOOK_ENEMY_RAMP`); limits ask the **budget** (the per-step fire and chain caps, the projectile manager's drop buckets, `SHARED_BEAMS` and `SHARED_PENDING`: a seat's own, one `SHARED` by every actor no seat drives; at the cap a tie drops from the shared bucket first). Only the HUD's events ask the **seat** (`mana_reserved` goes to the seat that drives the caster; the HUD's panels read `Spells.actor_of_seat`).
- **A shot keeps what the table said when it was spawned** (team, ramp, budget), so a possession later does not recolour or re-budget shots in the air; a target's team is read every step from its owner (a target no actor owns takes its layer's team until G6 makes every body an actor). An id that is not open is no actor: no team, the enemy ramp, the shared budget.
- **Events:** every caster-keyed signal's first parameter is `caster`, an actor id (`NO_PLAYER` only where no actor did it); `enemy_died(killer, ...)`; `entity_spawn_requested`'s last parameter is `anchor`. `wizard_hurt` is `actor_hurt(actor, amount, position, tag, kind)`, keyed by the hurt actor, so `on hurt` fires on an enemy's carriers too (a design change); `shield_blocked(actor, ...)` names the shielded actor. `mana_refund_requested(caster, amount)` is sent for every actor (an enemy's AI and the kit's Caster hear it; `take_refund` is gone). Seat events (HUD intent, builder, stats, downed, `spell_cast`, `staff_cast`, `wizard_cast`) stay keyed by seat. `ally_passed` and the `on ally` trigger are gone (owner, above); `relay` is wired from Spells' own `projectile_hit` handler, which runs before Combat's (autoload order), so the hit itself takes on the infusion.
- **Combat until G5:** attackers pass through as actor ids; its four wizard slots stay by seat, and the three rules that need a seat ask the table (a mend area hit of an actor no seat drives heals no wizard; only a seat's spell discharges static; "downed by player N's" names the seat of the actor that did it). A wizard's target is owned by its actor id, and the wizard names itself the owner again once its actor opens (the four-bot smoke test caught a wizard added outside the tree being registered before its actor existed, so its own shots hit it).
- **Determinism:** scatter, staff spread, teleport and dash seeds hash the actor id instead of the player index. Ids are handed out lowest free first, so a run is still the same every time; a replay recorded before differs once, where wizards' ids are not their seats.
- **Timing** (`tests/benchmark/test_projectile_timing.gd`, headless, main and this branch alternately, three times each, with other sessions on the machine, so step numbers move by 20-50% run to run): spawning at the cap costs about 1 µs more a shot (2.7-3.6 µs before, 3.8-4.4 after: three table reads, made once per shot); step with fresh hits (500 cap) 2.3-3.0 ms before and 2.2-4.3 after, homing 4.2-5.8 ms and 3.7-5.7, orbits 2.4-4.0 and 2.0-3.2, rays 108-196 µs a beam and 98-137, update_draw 1.4-1.8 ms both: within the noise. Nothing in the step or the draw asks the table per shot.

## 2026-10-28: Wizards are actors (actors G7)

- **A wizard is an actor of the kit** (docs/milestones/M2-actors.md, "The tree"): `content/wizard/base/wizard.tscn` is an `Actor` with Health (100), a hurtbox (radius 8 at (0, -12)), a mover (90 px/s), a Caster (4 staffs, mana 100, regen 10), `Downed`, the `PlayerController` and `WizardLook`, its numbers in the scene. `gameplay/player/player.gd` is the `PlayerController` (the seat): no body, health, mana, staff or move code is left in it. The caster kit, mana and casting are the kit's, one implementation for wizards and enemies.
- **The controller is the seat.** It turns its seat's input into the actor's intent (the walk, the stick, mouse and held aim, press counting and the 0.15 s buffer, held buttons, an overlay's capture) and the driven actor's local signals into the seat's events (`player_stats_changed`, `spell_cast`, `staff_cast`, `wizard_cast`, `staff_changed`, `bag_changed`, `build_refused`), and the builder's requests for its seat into `Caster.set_staff` on the actor it drives. It binds to the actor handed to `started` and lets go in `stopped`, so when G9's possess hands it another actor, the panel and the builder follow the seat there and the body left behind sends nothing. The bag stays with the seat.
- **Downed** (gameplay/player) makes its actor downable: 0 health downs it (`player_downed` by its home seat), `revive` stands it up with 50, `protect` is Health's. Coop and flow revive and protect through it; coop finds wizards by a `wizards` group the scene puts the root in (chosen over `Actors.actor_of_seat`, which names the actor a seat drives, not the body that is downed and revived) and reads each one's Downed once per change of the group, so a frame allocates nothing. The old `players` group stays on the scene for the AI, Entities and Feel until G8.
- **`Flow.get_wizard(seat)`** still returns the seat's wizard body (the actor whose home controller has that seat), also while the seat drives another actor in G9: the callers (coop, bots, tests) want the body.
- **Combat until G5: a bridge, not the kit's `register_actor`.** The G4 shim registers an actor on Combat's enemy model, which for a wizard would count it in the wave, free it at 0 health with `enemy_died`, hit it twice from an area (once as an enemy, once as a wizard) and leave out every wizard-only rule (barriers, its statuses, `downed_note`, enemies' touch). So the scene uses two small subclasses until G5: `WizardHurtbox` registers the wizard in its home seat's Combat slot (`register_player`, from the hurtbox itself, so flow no longer registers wizards), and `WizardMover` asks that slot for the pace and the push (`wizard_speed_factor`, `consume_wizard_knockback`; the kit's Mover gained `_pace()`/`_push()` hooks for it). The Actor answers `is_downed()`/`is_invulnerable()`, the names Combat's slots ask by. When G5 lands the scene goes back to the kit's Hurtbox and Mover and the two files go.
- **What changes for players:**
  - A standing wizard dashes the way it aims, not the way it last walked (one rule for every actor, the kit's; owner, 2026-10-28).
  - The HUD hears mana from regen one physics step later (the controller looks before the step's regen); health and casts as before.
  - A wizard is on no physics body layer (layer 2 before); nothing read it.
- **Colours have one home:** the ramps' light shades (docs/STYLE.md) join the base colours in the projectile manager (`RAMP_LIGHT_COLORS`, `ramp_light`); the look draws the reticle, gem and rings in them, the colours player.gd kept its own copy of. Feel's copy goes in G8.
- **Feel and Entities** read a wizard by its actor `id` and `ramp` where they read `actor_id` and `index` (a small bridge; G8 reads every target by actor).

## 2026-10-28: Combat by actor (actors G5)

- **One body model:** Combat keeps every body that can be hurt as one row of packed arrays sized `Actors.ACTORS` and indexed by its actor id; the four wizard slots and the enemy list (with its `find()` on every hit and 23 `remove_at`s per death) are gone. A row is found by id (an array read) or by node (one dictionary read) and freed in O(1). A body with no actor id of its own (a non-casting enemy, the training dummy) gets one Combat opens on the enemies' team and closes again, so every body has an owner.
- **The actor API:** `register_actor(node, ...) -> id`, `unregister_actor`, `apply_status(caster, actor, ...)`, `status_left`, `has_status`, `chill_stacks`, `give_shield`, `shield`, `pull`, `downed_note_of`, `health_of`, `knockback_of`, `pace`/`pace_of`, `consume_knockback`. A parameter named `actor` takes an id or a node; `pace` and `consume_knockback` (a body asking about itself every step) take the node, as the kit's Mover calls them. Every older call stays as a thin wrapper marked deprecated, so ai.gd, flow, Feel and the dummy (and G6, in parallel) compile unchanged; G8/G10 remove them.
- **Health:** a kit Actor's Health is called by Combat (`take`, `heal`) and no longer listens to `damage_dealt`/`heal_dealt`; at 0 the actor dies (`die(killer)`) unless something downs it (a wizard's Downed). A quiet burn tick still goes to Health, so the seat's HUD hears it through `Health.changed`. Bodies without the kit (until G6) keep their health in the row. `enemy_died` is still Combat's, for every body not on the wizards' team.
- **G7's bridge is gone:** with one row per actor, the wizard scene uses the kit's Hurtbox (`register_actor`: one row, downable, never counted as an enemy) and Mover (`pace`, `consume_knockback`); `WizardHurtbox` and `WizardMover` are deleted. The seat wrappers find a wizard by its *home* seat (kept when it registers), never by the actor its seat drives, so a possession (G9) does not move them. `register_player` stays as a wrapper only for the tests and flow's clean-up that still call it.
- **One rule each (owner, the recommended set):** shock: the next *spell* hit also jumps to the nearest other actor of the victim's team (a wizard's shock no longer adds damage to any hit). Static: any hit but a burn tick sets it off and it is always spent; it arcs to the victim's actors of *other* teams in `STATIC_RANGE`, credited to the charged actor (so a charged imp zaps the wizards near it, a charged wizard the enemies; imps never zap imps, and the two combos that showed imp-to-imp chains now say so). Hex: a spell hit pulls every actor toward it. Pull: every actor, wizards too. Barriers: any actor (`wizard_shield_requested` gives the caster's own actor one, an enemy's too). Later statuses: the wizard's complete loop for everyone. Burn ticks: quiet for everyone, no hex bonus. Reactions (burst, spread) reach every actor in the circle.
- **Two rules the table did not name, made one the same way:** contact: any actor with contact damage hurts each actor of *another team* it touches, once per second per victim, credited to the toucher (was `NO_PLAYER`); an imp walking through imps hurts none. Mend: a heal hit heals an actor of the caster's team and is a plain hit on the others (teams aim: a mend is for friends); before, a wizard was healed by anyone's mend shot and an enemy never.
- **`actor_hurt` for every actor**, so `on hurt` carriers fire on enemies' staffs from Combat's side too.
- **Not measured here:** the owner asked to skip the full suite and the stress run for this part; they come with the final phase-G check. The stress run before this part (headless, other sessions on the machine): web avg 10.2 and 10.8 ms (p95 21.5 and 25.7), desktop avg 181 and 188 ms (p95 255 and 267), combat lookups for one pass over the crowd 0.40 ms (web) and 1.5 ms (desktop).

## 2026-10-28: Living staffs (the owner; phase H planned)

- **Every character is a living staff** (the owner: "every character in the game being an alive staff. So enemies are just staffs that look kinda evil. And our main protagonist is a goofy looking staff"). Designed over nine rounds of mockups in one owner session; the plan is [M2-living-staffs.md](milestones/M2-living-staffs.md), phase H, after phase G and before D3.
- **The player:** a floating staff that points where it aims, with cartoon floating eyes and separate floating brows over the grip ("Close" height). Its four staffs are four personalities, one per button, each with its own head and face (curl, star, moon, crystal); a different button swaps them in a 0.18 s cloud poof that never delays the cast. The player colour is on the heads only.
- **The story:** a wizard throws staffs down a hole in the tower floor just because (new is better); the staff thinks it was an accident. The strays are the wizard's earlier staffs; bosses are powerful old staffs; the final boss is the wizard's current staff, the Favourite, and then the wizard picking it up. Ending A: the wizard keeps your staff ("Huh. Still works.") and drops the Favourite down the hole. STORY.md's canon is rewritten.
- **DESIGN.md:** the build element "Wizard" is now "Staff", and the locked art direction is the living staff; the style N wizard of 2026-10-23 becomes the villain (owner session, at the owner's direction).
- **Actors G6 and G7** build one look for every actor instead of a `CreatureLook` and a `WizardLook`, so phase H's face layers have one home.
- **Defaults not yet overruled:** the enemy name "strays"; strays hop while players float; the starter heads and personality names.

## 2026-10-28: Enemies are actors (actors G6)

- **Every enemy is an actor scene** (docs/milestones/M2-actors.md): the ember imp and the shooting dummy are an `Actor` root with Health, Hurtbox (11 px at (0, -12)), Contact, Mover, Caster, the `AIController`, the `CreatureLook`, the `Telegraph` sprite, the `Sprite` (kept by that name: Feel and the decoys find it), an `AnimationPlayer` (the imp) and a `CollisionShape2D`; `hand_offset` = `body_offset` = (0, -12) and `staff_reach` 0, so spells start at the body as before. The `.tres` fills the components (health, speed, contact damage, staff, cards, mana), so a new enemy type is still a folder with sprites, a scene and a `.tres`, no code. Every enemy body opens an actor id (the enemies' team, the enemy ramp, no seat) that owns its hurt circle, casting or not, and closes it when it leaves the tree.
- **`gameplay/ai/ai.gd` is the `AIController`** (kept as the area's public entry script, now `class_name AIController`): it only writes the intent. Walking, the caster kit, mana, casting, knockback and pace are the kit's components; the old copies in ai.gd are gone. The windup is gated on `Caster.cast_ready(windup_time)` and the cast is `intent.press(0)` at its end; the windup and recovery timers slow by `Combat.pace` as before.
- **Targets come from the projectile manager's target grid:** the nearest hurt circle of another team than the actor's (`nearest_target` with the team), a wizard's decoy in lure range first. The `targets` list and the `players` group scan are gone, and anything of another team that can be hit is a candidate, so a wizard's decoy beyond the lure range is chased when it is the nearest. A downed wizard has no hurt circle, so it is skipped as before.
- **Grudges (infighting):** an AI hurt by an actor of its own team targets it for `GRUDGE_TIME` (3 s), then goes back to its team's targets; a wizard's hit and its own blast earn none. Heard from `damage_dealt` (it names the attacker's actor id for every hit, before and after G5), not `actor_hurt` (only wizards send it until G5, and its tag is 0 for touches and reactions).
- **An enemy without a staff walks into its target** (and hurts by its Contact) instead of stopping at attack range.
- **All drawing is in looks:** `CreatureLook` is a straight port of ai.gd's poses, flash and telegraph; it reads the AI driving the actor, so a seat-driven actor (possess, G9) shows no telegraph. The hurt pose still follows `damage_dealt` naming the actor (a burn tick that does not kill sends none, so burning enemies do not flinch twice a second; Health's `changed` would after G5).
- **The training dummy** is an actor with Health (its data's billion), a Hurtbox at (0, -14), no controller and no Mover (so nothing moves it), on the enemies' team by `idle_team`, and a `DummyLook` (`gameplay/ai/dummy_look.gd`) for its numbers, DPS, statuses and reactions; `training_dummy.gd` is gone.
- **Nodes:** an imp goes from 5 nodes to 12, the shooting dummy from 4 to 11, the training dummy from 13 to 16: about 700 more nodes at 100 imps, none with a process callback (only the actor steps).
- **The stress run** (before: web frame avg 10.6 ms, p95 22.3 ms, peak nodes 1,588; desktop 169 ms, peak nodes 2,093; headless, a noisy shared machine) is to be repeated after this part with the final phase-G check, at the owner's word, so the after numbers come there.

## 2026-10-28: Possess (actors G9)

The owner approved `possess` as a card (M2-actors.md, "Possess (a card)"); built as planned, with these choices:

- **The card:** a modifier, `behaviour` POSSESS (21), `behaviour_strength` 3 s (two cards add up), `mana_mult` 2.5 (the dearest modifier; 4.0 made some fuzz staffs uncastable at 100 mana), `cooldown_mult` 2, complexity 4, look 10 (orbiting sparks). Wasted on a fallback (it needs a hit). Combos `possess_bolt` and `possess_chain_bolt`.
- **One possession per cast:** Spells keeps a flag per actor and staff, cleared by each cast of that staff; the first hit on an actor some other actor owns sends `possess_requested(caster, target, seconds, tag)`. An unowned target or the caster's own body spends nothing.
- **The rule is in the actor kit** (`gameplay/actor/possession.gd`), not in Spells or an autoload: each actor hears the request for its own id and steps the possession holding it, before its controller thinks.
- **`Actor.drive` takes the controller off the body it drove** (`ActorController.driving`): the flaw found in G7 (one controller on two bodies, builder signals bound twice) is gone.
- **Where the driver goes back to:** the body it came from, unless another controller possessed that body meanwhile; then it waits behind that possession and comes back when it ends. A downed body still takes its seat back.
- **A seat set aside** (an enemy drives its wizard) sends `player_possessed(seat, seconds)`; the panel shows "POSSESSED n" (priority after DOWN). A seat driving an actor with fewer staffs announces the rest empty.
- **The builder on a possessed actor** builds that actor's staffs; they are put back as they were when the possession ends. Compiled staffs stay shared (the cache is keyed by cards, so a change never touches another actor's).
- **The camera** keeps both a wizard's standing body and the actor its seat drives in view.
- **Sound id** `possess` for Feel; no sound or Feel cue yet (`possess_started`/`possess_ended` have no listener).

## 2026-10-28: The docs (actors G10)

- **AGENTS.md's "No single the player" rule** now reads: everything that acts is an actor and takes its actor id; a seat (0–3) is a human, and only HUD, input and co-op rules take seats; never assume an actor id is a seat.
- **docs/ARCHITECTURE.md** gains the actor layer: actors made of components and driven by one controller, systems keeping the hot state by actor id, and where a new body behaviour (a component) or a new driver (a controller) goes. The wizard scene's art contract is the `WizardLook`'s.
- **Two rules phase G made by "one rule" without naming them in the plan** (G5): contact damage hurts only actors of other teams (an imp walking through imps hurts none), and `mend` heals the caster's team and is a plain hit on everyone else (an enemy's mend heals enemies).
- **Tests run in parallel:** each unit test is its own Godot process, so the whole suite (with the 4-bot smoke test) runs in under a minute with one import and a data folder per test, instead of 20–40 minutes one by one. `test_projectiles_kit` times the manager and can fail under that load; it is run again alone.

## 2026-10-28: Feel and Entities by actor (actors G8)

- **Feel reads every hit body by its actor** (`Actor.id`), never a group or a player index: its colours are its ramp's (`Actors.ramp_of`; a hat ramp in its own colours, the enemy ramp in ember), and a hit whose caster is the hit actor is a self-hit, for every actor (an imp caught in its own blast gets the self-hit ring too; before, only wizards). Feel's copy of the light shades (`PLAYER_COLORS`) is gone; the projectile manager's `ramp_light` is the one home.
- **The cast squash for every actor:** `wizard_cast(player, wizard)` (sent by the seat) is replaced by `actor_cast(caster, actor)`, sent by the kit's Caster after every cast, so enemies squash when they cast as wizards do. One event from the one place every cast passes, rather than a second sender beside the seat's.
- **The downed note** finds the seat's own body by `Combat.home_actor_of(seat)` (the actor whose home controller has that seat, so a possession does not move it) and reads `downed_note_of(actor)`; the note is in that actor's ramp's light shade.
- **Possess in Feel** (G9 left its events unheard): `possess_started` shows a ring closing on the possessed actor in the driver's ramp and plays the sound `possess` (silent until Audio adds it); `possess_ended` a ring going out from it.
- **Entities** finds a caster's body by `Actors.node_of` (or the body the AI named); the `players` group scan is gone. The pool's parts stay by seated or not.
- **Phase G's bridges are gone:** the `players` group (the wizard scene keeps `wizards`, which coop reads); Combat's deprecated wrappers (`register_enemy`, `register_player`, `get_health`, `apply_wizard_status`, `downed_note`, `wizard_of` and the rest), its `BODY_WIZARD` body kind (nothing registers a wizard without the kit) and `WIZARD_SHIELD_MIN_TIME`, and `test_combat_compat.gd`; the Mover's `_pace()`/`_push()` hooks; flow's unused `AiScript`. Flow's clean-up unregisters its wizards by node; tests, the clips stage and the screenshots use the actor API (the dash and trail shots open their casters in the `Actors` table instead of `FIRST_ENEMY_CASTER`, which no longer existed).
- **Left for later:** `Actor.is_downed`/`is_invulnerable` (the names the old wizard slots asked by; the AI and the bots still ask `is_downed`) and Combat's `actor_id`/`caster` lookups for plain test bodies.
- **Found on the way:** a GDScript runtime error in a test (a call to a removed function, a wrong argument type) is printed but does not fail the test, so the suite passed with two such errors before they were fixed here. A test log is worth a grep for `SCRIPT ERROR`.

## 2026-10-28: Possess: the HUD stays the player's (owner)

The owner's decision after G9: a player must always see their own wizard, which stands vulnerable while they drive another actor.

- **A seat's corner panel and builder are always its own wizard** (the home body), whether the seat drives another actor or an enemy's AI drives the wizard, and its numbers stay live in both cases. `PlayerController` binds the home body once (its Health, its Caster's `staff_built`, the builder's requests) and the driven actor only for its casts (`spell_cast`, `staff_cast`): the buttons still cast the driven actor's staffs. A home controller that is away watches its body each step (`ActorController.watch_home`, after the looks), so the wizard's mana regen reaches the panel with no seat driving it.
- **The HUD finds the home body in the actor table:** `Actors.set_home(id, seat)` (the actor sets it from its home controller's seat when it opens its id) and `home_of_seat(seat)`; `Spells.home_of_seat` replaces `Spells.actor_of_seat` for the staff rows' timing. `mana_reserved` still follows the driving seat (no HUD reads it yet).
- **Gone:** the panel's "POSSESSED n" word and `player_possessed` (no other listener); the empty staffs announced while driving an actor with fewer; the builder on a possessed actor's staffs and the possession putting them back (`Possession._keep_cards`, `_give_cards_back`), now dead; `Actor.is_invulnerable()` (no callers).
- **Over the possessed actor** (`PossessedLook`), just above the 32 px character: the timer as a small ring like the wizard's revive ring (outline, Stone back ring, the time left as an arc in the driver's light shade). Over an actor a seat drives that is not its own wizard, its health (Fire) and mana (Spark) beside it as two 16x2 px bars in a 1 px outline on a Stone trough, the panel's bar colours. A wizard an enemy's AI drives shows only the timer. The ring round the body is gone (Feel's rings mark the start and the end).
- **The sound `possess`** is listed in docs/BACKLOG.md, "Audio needs".

## 2026-10-28: The floating staff (living staffs H3)

- **A staff per button** (the owner, 2026-10-28, asked in this part): a player's Caster holds one `StaffBase` per button (`Caster.staffs`; `staff` stays for a button without one and for enemies), so a head, its tip and its personality are the staff's, and a staff found in a run (M3) is a data swap of one button. The four starter heads are four staffs, `curl`, `star`, `moon` and `crystal` (RB, RT, LB, LT), each with the old starter's numbers; `starter` is gone (moved to `curl`). Dev and preview builds give each head the `dev` staff's numbers (copies made once by flow), so the sandbox keeps its 20 slots with the new heads.
- **The staff on show is the Caster's `current`:** the staff pressed or held last, set before it casts, so the shot leaves from the new head's tip on the press (`Actor.reach`: the staff's `tip`, else `staff_reach`). Pressing an empty staff shows it too: the button picks the personality. Until the poof (H4) the swap is instant.
- **`StaffBase` gains its look:** `head` (a sheet of 48×48 frames, 16 directions × 4 ramps, the grip at (24, 27)), `tip` (0–32 px), `face_style` and `resting_mood` as ints in `Face`'s order (core cannot name gameplay's enums).
- **The hurt circle is unchanged** (radius 8 at (0, -12)): it already covers the face and the grip, and moving it up 3 px broke the dodge distances the AI tests hold (the plan: hits stay as fair as now). The grip (`hand_offset`) is at (0, -12), 2 px above the old hand.
- **The moon is redrawn sharper:** a thin crescent with its horns up, carved straight down instead of to the upper right, so it no longer reads as a blob (the mockup's weak spot).
- **No more flip:** each direction has its own frame (the curl's spiral is drawn on top either way), so `flip_h` and the turn band are gone; between two directions the nearer shows.
- **The style N wizard art stays** in `content/wizard/base/` for the villain (H6); the clips stage and the art screenshots still show it. `docs/STYLE.md` and the golden examples move to the staff in H7.
- **The sheets** are drawn by a generator from the mockup's pixel rules (the same as the face sheets'); each head folder lists its sheet in an `assets.json`.

## 2026-10-28: The poof (living staffs H4)

- **The poof is a look bit on the puff, not a new effect kind:** the shot shader's kinds 1–15 are all taken (the kind travels in four bits of the instance data), so `KIND_POOF` from the plan is `KIND_PUFF` with the `POOF` look bit (kind 22, `1 << 21`), as `EXACT` is. Bone clouds along the staff that peak at 35% and dot away, sparks in the ramp; no new pool.
- **A new event, `staff_shown(caster, actor, staff)`,** sent by the Caster when another staff goes on show, before that press casts (the cast is never delayed). Feel draws the cloud from it; `StaffLook` needs no event (it reads `Caster.current`).
- **The body changes at 35% of the newest cloud:** every press of another staff starts the poof again (Feel shows a cloud per press), so a fast double swap lands on the last staff at the last cloud's biggest. The same staff again, or holding one, never poofs.
- **Followed effects sit at an offset** (`_effect_offset`, was the status's fixed rise), so the cloud stays on the staff while it moves.
- **Feel ages effects by the wall clock** (so hit-stop cannot slow them). On a software renderer a frame takes far longer than 1/60 s and a 0.18 s cloud is gone in a frame, so `shot_poof.gd` puts Feel on frame time for its pictures. The game is unaffected.

## 2026-10-28: The strays (living staffs H5)

- **The Cinder Rod keeps the id `ember_imp`.** Flow's default enemy, the sandbox's imp wave, the tests and the clips all name `ember_imp`; renaming it buys nothing a player sees. The look, the art and the staff's display name are the Cinder Rod's; its numbers and staff (fire · bolt) are unchanged.
- **Built now: the Cinder Rod, the Splinter (dash, contact damage 8, one eye) and the Storm Fork (triple · lightning · bolt).** The Rime Crook waits for a `hook` card and the Bone Scepter for `rain` (the plan: a stray waits for its cards); both are in NEXT.
- **The wave is unchanged:** flow spawns one enemy type (`enemy_id_to_play`) at the wave's spawns, so mixing strays into a wave is flow work, not data; the Splinter and the Storm Fork exist as content (and in the registry) until a mixed wave or M3's rooms use them.
- **No poses on strays:** the imp's windup and hurt strips are gone; the face carries the mood (furious while winding up, worried when hit) and the flash and telegraph are unchanged. `CreatureLook` keeps the poses as an option (tested on strips made in code).
- **The hop is the sprite's offset only,** so the telegraph and the hurt circle never move with it: dodging stays exactly as fair as before.
- **Eye glow** is the light shade of the stray's element ramp (Fire `#ffa23c` for the Cinder Rod and the Splinter); the Storm Fork's eyes are Acid's base `#b4e82a`, since Acid's light shade is too pale to read as a glow.
- **The dummies** are staffs staked in a Stone mound (the training dummy with a target on a straw crossbar, the shooting dummy with a muzzle head); no face, since they are props. Their behaviour is unchanged.

## 2026-10-28: The intro (living staffs H6)

- **"A new save" is a flag in a new save file.** There was no save yet (`core/save/` was empty), so H6 adds the smallest one: `SaveFile`, a ConfigFile at `user://save.cfg` holding flags. The intro sets `intro_seen` when it ends or is skipped; a missing or broken file is a new save. Runs, unlocks and settings move into it when they exist (M3).
- **Only people see it:** Flow's `intro_enabled` is off when a test script is the main loop or the game was started with user arguments (the 4-bot test, the stress run, the timing run), since every automated run starts on a fresh `user://` and would otherwise sit through it. The intro's tests and its screenshot switch it on with a save file of their own. The sandbox never shows it.
- **Skip by press count,** not "just pressed": a tap between two of Flow's steps still skips, for any joined player, on accept, back, pause or any staff button.
- **Drawn in code, not a scene:** the world (tower room, shaft, crypt) is rects in docs/STYLE.md's palette, as in the owner's mockup, at 3× under a clipped window with the caption below. The dropped staffs are the curl head sheet; their eyes and brows are frames of `art/faces/` drawn directly, because `Face` needs an actor. Each staff is its player's colour.
- **The villain wears Blight** (`art/story/wizard_hat.svg`, the style N hat recoloured): the hats in `content/wizard/base/` are all player colours, which stay the players' only. The Favourite (`art/story/favourite.svg`) is the mockup's 'fav' body pointing up.
- **More players, same length:** the drops come 0.45, 0.3 and 0.2 s apart ("Oops. Oops. Oops. Oops."), the wizard leaves after the last, and the staffs land 0.12 s apart, so four players still finish at 14.5 s.
- **The captions are in code** (`intro.gd`): `content/story/` takes only JSON, and there is no cutscene schema or loader yet (lore is the only story kind the registry reads). Moving them to story data is M3's, with the events schema.
- **Kept from the mockup:** the closing line "Merge spells. Find your way home." after "Home is up there." (the owner saw it in round 9).

## 2026-10-28: The docs (living staffs H7)

- **"Player" in the prose, not "staff":** every README, docs/ARCHITECTURE.md and llms.txt now call the player's character the player (its body the staff where that is meant), never the wizard. "Staff" alone already names each of a player's four card rows, so "the staff's staffs" would not read; the plan's "staff for the player" is kept where it is unambiguous. The wizard in the prose is now only the villain.
- **Identifiers keep "wizard":** `content/wizard/`, `wizard.tscn`, the `wizards` group, `TEAM_WIZARDS`, `seat_wizard`, `WizardFixture` and the like. Renaming them is a refactor across code, scenes, tests and the bot's scripts for no change in play; the folder's README says why it keeps its name.
- **docs/STYLE.md** gains "The living staffs" (the face layers, moods and personalities, head sheets of 16 drawn directions, strays' glow and hop, silhouette families) and its player-colour rule moves from the hat to the head. **Golden examples:** `art/kit/golden_staff.svg` (the curl with the Optimist's face) and `art/kit/golden_stray.svg` (the Cinder Rod with its face), each composited from the game's own sheets as the game layers them; `golden_wizard.svg` stays in the kit as the villain's look and leaves the list.
- **In the game,** the two combo descriptions that said "One wizard's" say "One player's"; the intro's lines about the wizard are about the villain.

## 2026-10-28: Actors made fast again (performance pass)

The owner, after phase G: "It should be possible to optimize this a lot". Measured headless with the stress benchmark (`tests/benchmark/stress.gd`) on one quiet machine, the branch's merged main (with the living staffs, phase H) and the branch back to back:

| | before phase G (077169e) | main (6edd294) | this pass |
|---|---|---|---|
| web: frame avg / p95 | 7.19 / 14.54 ms | 11.69 / 19.23 ms | 7.14 / 15.44 ms |
| web: enemy step pass | 10.4 µs each | 30.9 µs each | 19.2 µs each |
| desktop: frame avg / p95 | 155 / 190 ms | 231 / 301 ms | 169 / 191 ms |

No rule, cap, limit or effect changed: the gain is in calls not made. A GDScript call costs about 0.5 µs here, more than a few field reads, and a crowd makes each one a hundred times a step. What each step bought (web frame avg, measured before the merge of phase H, from 9.85 ms on this machine):

- **Hits are heard on the actor, not on the bus** (≈0.3 ms): `damage_dealt` had three listeners per enemy (the AI's grudge, the look's hurt pose, and with phase H the Face), each called for every hit on anyone and comparing the target with itself: about 110 µs per hit with 100 enemies. Combat now also sends the actor's own `Actor.damaged(by, amount)` right after `damage_dealt`; the AI, `CreatureLook` and `Face` listen there (21 µs per hit). The AI's `player_downed` listener is gone: its step already drops a target that is down. `DummyLook` (one sandbox dummy) stays on the bus; `possess_requested`, `caster_move_requested` and `mana_refund_requested` stay too (rare, a cast's).
- **The step calls a component only with something to do** (enemy step 18.9 → 13 µs before phase H): Health only while `protecting`, the Hurtbox only when `registered` differs from down; the intent's buttons are bit masks, and the Caster skips its staffs with no button; Combat answers an actor's pace and push by its own id (`own_pace`, `own_knockback`: its row is its id, no node lookup); the AI asks the pace only while winding up or recovering, checks an actor target without the Variant checks, and asks `Spells.cast_ready` once instead of five calls; `CreatureLook` and `Face` set nothing on their nodes that did not change.
- **The Caster sends its anchor and aim only when the body moved, turned or showed another staff**, in one call to the projectile manager (`place_caster`: the anchor and the wall-clipped staff tip), and again before every cast, in case a new run cleared the systems while it stood still.
- **The shots' drawing** (update_draw 2.96 → 1.28 ms a frame): what a shot is drawn as (batch, look colour, size, particles) is kept per slot with its spawn, radius and look, not worked out with a dozen calls per shot per frame; a cooling trail's colour is worked out when it is let loose; a direction is only normalised for a rune.
- **The hit test** (≈4.9 → 3.7 µs a shot): the path test comes before the hit memory (a call), and a distance to the path's middle turns most targets in the cells away first; the targets' teams are read with the table looked up once a step. A short wall check (at most one cell each way, corner cells clear) skips the cell walk.
- **Tried and dropped:** 32 px target cells (more cells cost more than the fewer targets saved, worst on desktop); skipping the per-step aim for actors without a beam (a delayed launch or a dash's end can start a beam from the aim later, so it must stay current).
- **Where the rest goes:** desktop is the projectile step (3,000 shots × 8 steps a frame; the hit-work budget already bounds the hit tests), and web's p95 is the frames with a physics step. Stress's "frame parts" physics and process figures are the engine's per-second maxima, not averages.

## 2026-10-29: Shots stepped by behaviour (performance)

The owner: restructure the projectile step from "for each shot, check every behaviour" to passes by behaviour, with exactly the same behaviour, and so that a new behaviour is easy to add. `ProjectileManager.step` now runs a common pass (life, and every straight shot flies on), one pass per behaviour over a list of only the shots that have it (stuck, growth, linger, orbit, return, homing, spiral, a card's move; one table, `B_*` with `BEHAVIOUR_PASSES`, says which there are and in which order, and the comment above it why), then the hit pass over every shot in the order the step always took (the ends the passes marked, bounds, walls, hits, events), then the passes after the hits (shield). The lists are kept by `_join`, `_leave` and `_kill` (swap-remove, no allocation). core/README.md has "How to add a shot behaviour": its numbers, its setter (`_join`), its `B_*` and pass name in the one table, and its pass; nothing else.

- **Exactly the same:** `tests/core/test_projectiles_step_exact.gd` steps a busy scene with every behaviour (homing searches, orbits and returns round wizards and round shots in lower and higher slots, the cap dropping shots, the hit-work budget running out and resuming, handlers that spawn shots, push targets and take them away) and compares every event and every live shot's state, step by step, with a recording made on main (c900bd4; cacf0a9 passes it too). To be exact, a shot whose motion reads something a hit handler may change (a stuck shot's target, an orbit's or return's caster shot, the targets left for a homing search or a homing move) or the hit-work budget waits for its turn in the hit pass (`_wait`, `_catch_up`), and a caster shot is read where it was before its turn.
- **What changes, at the edges:** a hit handler now sees every shot already moved for this step, also those whose turn has not come. So a handler's change to another shot (a hook pulling its carrier, a blink) takes effect from that shot's next step whatever the slot order; before, it took effect in this step when that shot's slot came later. A shot a handler ends before its turn had already moved, so its trail ends one step on.
- **Numbers** (headless, one machine, main cacf0a9 and this branch back to back, two rounds; the machine was shared, so the whole-frame figures are noisy):

| | main | this branch |
|---|---|---|
| step, 3,000 shots, no targets | 4.15 / 4.05 ms | 1.79 / 1.45 ms |
| step, 3,000 shots, arena walls | 4.81 / 4.97 ms | 2.72 / 2.13 ms |
| step, 3,000 shots, fresh hits in a crowd | 5.25 / 5.77 ms | 3.70 / 2.25 ms |
| step, 3,000 shots, steady state | 3.20 / 3.12 ms | 2.02 / 2.07 ms |
| step, 500 shots, fresh hits in a crowd | 1.70 / 1.94 ms | 1.31 / 0.95 ms |
| stress web: frame avg / p95 | 9.29 / 19.08, 8.00 / 16.24 ms | 7.60 / 15.73, 7.22 / 15.06 ms |
| stress desktop: frame avg / p95 | 102.8 / 219.0, 172.1 / 257.8 ms | 111.0 / 227.2, 88.5 / 227.4 ms |
| final pair after merging main (59bc8c9): stress web avg / p95 | 8.28 / 16.71 ms | 7.75 / 15.71 ms |
| final pair: stress desktop avg / p95 | 179.8 / 198.2 ms | 166.4 / 187.1 ms |
| final pair: step, 3,000 shots, no targets / fresh hits | 2.93 / 4.13 ms | 1.81 / 3.33 ms |

- **What each change bought:** the passes themselves (a plain shot costs one short loop; no behaviour checks per shot; the shield check walks its list, not every slot): the step without targets about 4.1 → 1.6 ms at 3,000. The trail sampling with its two calls a shot written out: 2.1 → 1.1 ms a sample at 3,000 shots (every other step). The hit test: a count and a box per grid cell, so a cell the path cannot touch is passed at once and charged to the budget in one go (2.6 → 2.2 µs a test in the stress crowd), the distance to the path's middle before anything else is read of a target, and the grid's corner kept as two numbers.
- **Tried and dropped:** the wall check's one-cell answer written out in the hit pass (3%, not worth the lines); working a hit test's path out only at its first cell with a target near it (within the noise).
- **Not met:** web p95 stays about 15 ms (aim was 13 or less). The projectile step is about 3 ms of the web physics step's 14 to 15 (0.5 ms of it the hit handlers in Combat, Spells and Feel); the rest is the enemies (2 ms), spells, combat, Feel and the engine. GDScript costs about 30 to 70 ns an operation here, so a hit test cannot go much below 1.5 µs. Desktop frames are 8 physics steps; the step's own cost is down by about a third, the frame by less, as the handlers and the rest of the game stay.

## 2026-10-29: One shader per kind, trails as ribbons (owner)

- **The bug:** the preview web build died with "WebGL context lost, please reload the page" right after the loading bar on the owner's real GPU (a Windows browser). Headless Chrome (SwiftShader) and CI never showed it. Bisected on the owner's machine: the build before #359 ("The VFX as the mockup draws them", 7f03ccf) loads, the one after does not; current main with `trail_frag()` returning `vec4(0.0)` at once loads; making every loop bound non-constant (no unrolling) did not help. So it was the trails' per-pixel cost: every pixel of a trail's quad (the bounding box of its whole path plus up to 36 px) walked up to 32 history samples, and for each piece its tail pixels (up to ~25) and its births (up to 6 moments x 3 particles), with texel fetches from the RGBAF `trail_data`, all in one 1,758-line shader that also held every other look (shots, beams, effects, statuses, sprites).
- **The decision (the owner):** no giant shader; one shader per kind of thing drawn, each in its own batch, with the shared code in includes; and trails drawn as ribbon geometry, so a pixel evaluates only its own piece of the path.
- **The shader set** (lines): `shot_trail` 823 (a shot in flight: head, tail, card particles; the manager's bolt, orbit and enemy batches), `shot_effect` 243 (Feel's flares, rings, sprays, puffs and poofs, chips, dash dust), `shot_orbit` 186 (Entities' familiars), `shot_beam` 169, `shot_rune` 119 (the rune batches, the enemy runes now in a batch of their own), `shot_sprite` 66 (deaths, afterimages, dash ghosts, decoys), `shot_arc` 52 and `shot_status` 48 (each now its own batch in Feel); includes `shot_palette` 135, `shot_look` 150, `shot_particle` 90. `.gdshaderinc` is now an allowed file type (ci/smbot/rules.py, AGENTS.md rule 2, CONTRIBUTING.md; the owner approved the change to those paths).
- **Ribbons:** a trail is still one instance (the CPU writes the same 16 floats a trail as before, so the frame's draw prep is unchanged), but of a mesh of 66 quads (`ProjectileManager.trail_mesh()`): the head and one quad per piece between two samples, each twice (a light pass, then a pixels pass, oldest piece first and the head last). The vertex shader reads the piece's two ends from `trail_data` and puts the quad round that piece alone (a piece out of the window is folded to nothing); no fragment reads the path (a test checks the shader text). Per pixel: one piece's tail pixels (at most 49, usually about 13) and its few births, instead of up to 32 pieces of them; and only the pixels near the path are covered, not the path's whole bounding box (an orbit's circle, a homing curve). A pixel near the path is covered by about 4-6 pieces' quads in each pass, so the total is roughly 3-6 times less and the longest single fragment about 30 times shorter.
- **Per-piece stand-ins for what needed the whole history:** the tail's light is the nearest piece's (each piece knows its neighbours' far ends; a tie goes to the newer), not the brightest of all pieces, which reads the same; the particles that circle the shot (void's pull, shields, glitter) are drawn by the head, which walks the moments of their short lives (at most 64, in its own quad of at most 42 px); a pixel's colour where two pieces overlap is the newer piece's (it is drawn later) rather than the youngest pixel's, the same almost everywhere.
- **Look differences (screenshots before and after, compared by eye and by pixel; run-to-run noise is real, the trail and beam scripts draw at the engine's real interpolation fraction):** none on the effects, reactions, looks, moving looks, form looks, dash looks, the poof and impact sheets beyond that noise. At a bounce, where the bounce sample and the step's sample share a moment, the old shader threw that zero-time piece's tail pixels up to ~30 px off the path; they now stay within the piece's quad. Effects, arcs and statuses take their random seed from their place in their own batch (as before, from their place in the one batch), so a given frame's sparks are arranged differently.
- **Numbers:** the stress benchmark (headless, CPU only) web avg / p95 9.25 / 17.86 ms before, 7.48 / 15.21 ms after, desktop 194 / 246 → 185 / 204 ms: the draw prep did not change, the difference is the machine's noise. Web smoke and the four-bot web run pass with no console errors in headless Chrome; the real GPU is the owner's test.

## 2026-10-29: Trail particles as geometry: a small trail fragment shader (owner)

- **The bug, found on the real GPU:** the ribbons above fixed the context lost at load, but on the owner's GPU (Windows Chrome, ANGLE on Direct3D) the build of #400 still lost its GPU process about 90 s after "main menu ready": "GPU process exited unexpectedly", then "CanvasShaderGLES3: Program linking failed" and "WebGL context lost". The Direct3D shader compiler ground on `shot_trail.gdshader`'s fragment stage until Chrome's watchdog killed the GPU process. Bisected on that machine: the build with the trail's `fragment()` body replaced by `COLOR = vec4(0.0);` stayed up 2 minutes, the #400 build died at ~90 s; stubbing the vertex stage's texture reads or the look-decode loops did not help, nor (on the old one-shader build) loop bounds the compiler cannot unroll. It was the size and branchiness of the fragment code: 561 lines reachable from `fragment()` (28 functions, 4 loops), every pixel walking its piece's tail pixels and births and running the particle code with a branch per look kind (`trail_particle`, `dash_particle`, births, glitter, void's pull, shields). Headless Chrome (SwiftShader) and CI compile it in milliseconds and never show it.
- **The fix (the owner's design):** the trail's particles, tail pixels and lights are geometry. A trail is one instance of a mesh of 300 small quads (`ProjectileManager.trail_mesh()`, `TRAIL_QUADS`): the core's light, 32 pieces' tail lights (a dash: its speed streaks' lights), 61 particles' lights and 61 particles (one per 60th of a second of the trail's last second), 128 tail pixels (one per pixel of travel back from the head; a dash: its speed streaks), 16 steps of lightning's jagged line and the core. The vertex stage works out from `trail_data` what its slot is now (a 5-step binary search finds the piece a moment or a pixel of travel is on) and puts its quad round it alone, or folds it away. The fragment stage only colours a pixel of its own quad in one of four small modes (a round light, a piece's tail light, pixels with an optional cross and line, a one-pixel line): 69 lines with what it calls, no loops, no look kinds, nothing read from the path (a test checks the text). The look kinds are data: one row each in a LOOK TABLE in the shader (life, start, throw, drag, curl, float, circle, line, blink, colours, light, rate; a dash's streaks and feet are three more rows), read by one routine, `spark`; the trail's window (how far back its particles are drawn, the longest of its kinds' and its tail's) is a small table too.
- **Compile times on the real GPU** (the owner's Windows Chrome, ANGLE on Direct3D 11; each program's link timed in a page with the exact GLSL Godot sends, captured from the build; a program with a stub other stage times one stage; runs vary by about ±30%): the trail's fragment stage **68 ms** (it was ~90 s and a dead GPU process), its vertex stage 1.0-1.9 s (the particle routine about 1 s of it; the table reads, the hash and the searches' loop bounds measured as not the cost, it is plain code volume), the whole trail program about 2 s. The others: `shot_effect` 1.8 s (fragment 1.95 s), `shot_beam` 2.2 s (fragment 2.0 s), `shot_orbit` 0.67 s, `shot_rune` 0.54 s, `shot_status` 0.22 s, `shot_arc` 0.05 s, `shot_sprite` 0.04 s; Godot's own canvas shader 1.5 s. Godot compiles each in two variants. In the four-bot run the first frames in the room wait 12-14 s for all of them (one long frame; the game then runs at frame p95 ~19 ms with 20 shots). `shot_effect` and `shot_beam` are the heaviest fragment stages left (per-pixel loops over their particles with `particle()`'s branch per kind): within the limit, a candidate for the same treatment.
- **Real-GPU tests:** CI and headless Chrome cannot catch this class of bug (SwiftShader compiles anything at once), so the fix was proven on the owner's Windows desktop with a script that serves a web export from WSL, opens it in a separate Windows Chrome (fresh temp profile), waits, closes it and reads the page console from Chrome's log: FAIL on a lost GPU process, a lost context, or a shader that fails to compile or link. Results: the Web export stayed up 150 s on the menu (PASS; #400 died at ~90 s), and the Web Test export's four-bot run passed with "SMOKE OK" (the bots cast spells, so every shot shader compiled and drew), twice. The same runs with a WebGL wrapper in the page logged every program that blocked over 100 ms, which named the heavy ones above.
- **Look differences** (screenshots before (two runs, identical) and after, compared by eye and by pixel, at 1x and 3-4x): the same tails, cores, lights and particle kinds, motions and colours. Differences: each particle's random numbers are new (one seed range per table row), so a given frame's particles are placed differently, with the same spread; a particle is no longer clipped to its trail's margin round where it was born (a far-flying ember or gust is drawn whole); inside a trail every particle pixel is under every tail pixel, lightning's line over both and the core on top (before, the youngest pixel won on its piece and newer pieces were on top); a tail longer than 128 px loses its oldest, sparsest end (a shot faster than ~430 px/s, or ~280 px/s for frost's longer-lived tail: a Faster frost bolt at 330 px/s loses its last ~20 px, where few tail pixels still live); lightning's jagged line is a straight step between its 4-px bends, so at a bounce it cuts the corner inside one step; with homing and void together the dark heart is centred on the woven core (it was 1 px off).
- **Cost:** a trail is 1,200 vertices (was 264) of straight-line work, and much less fragment work: each quad covers only its pixel, line or light.

## 2026-10-29: Teleport numbers (staffs C)

- **Teleport blinks 96 px for 4 mana, 2.5 s cooldown, complexity 2.** The three dashes move 48, 80 and 128 px, all free every 2 s. A blink is at once (a dash takes time to travel and can be hit on the way), so it costs mana and a longer cooldown; 96 px is only a little past the medium dash and short of the long one, so the 4 mana and 2.5 s pay for the instant arrival, not for range. `speed` (0) and `lifetime` (0.1) are placeholders: the compiler takes the distance from `ray_length` alone. Its combos do not test an end point (blast, on expire): the combo arena does not move its caster, as for dash.
