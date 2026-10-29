# Log

What each run did, newest first. Claude appends a short entry after each development session; the detailed record of every bot action is in the pinned Daily log issue. The "C2 evidence" section below is a standing section: it stays at the top, and dated entries go under it.

## 2026-10-29: The compiler says what does nothing (phase R, R2)

One table, `CardRules` (`core/spells/card_rules.gd`): every modifier behaviour and trigger event against every carrier motion, runs or a reason. The compiler asks it; the audit's silent cells (growth on a rune, heavy on a dash, timer on a beam, on hit on a familiar, on wall on an orbit, the melee carriers) are now listed as wasted with a reason in the builder and staff view. No shipped combo changed; `test_card_rules_table.gd` checks every cell and that the compiler wastes exactly what the table says. R3 next.

## 2026-10-29: Freezes in co-op (melee I7)

Feel's hit-stop is local now. A hit holds its attacker, its target and the shot that did it (new `Actors.hold` / `spend_hold`, which `Actor.step` obeys, and `Projectiles.freeze_shot`, a frozen shot keeps its life and tests no hits); a kill holds its killer; a reaction holds its caster. Another player, another enemy and every other shot run on. `Engine.time_scale` drops only for `player_downed` and the death of an `EnemyBase.boss`. A body rests `hit_stop_rest` before a plain hit holds it again (per actor). Tests: `test_feel_local_stop.gd` (a hit does not hold another player, a bystander or an unrelated shot; a down still stops the game), `test_projectiles_freeze.gd`; the old feel tests now read the holds.

## 2026-10-29: Screen shake setting (melee I6)

The pause menu's Settings page has a "Screen shake: On/Off" switch. It sends the new `screen_shake_changed(enabled)` event, which feel turns into `Feel.shake_enabled`, and the choice is saved in `user://save.cfg` (`SaveFile.get_setting`/`set_setting`, a `settings` section beside the flags) and read when the menu is bound. Hit-stop, particles and sound stay. Tests in `test_pause_menu.gd` (flip, save, reload), `test_feel_form_looks.gd` and `test_events.gd`.

## 2026-10-29: #417 removed

On the owner's word, the "downed wizard shrinks into its hat" idea left the backlog and its issue is closed.

## 2026-10-29: The later cards' looks (staffs C0b)

The thirteen modifiers with no look got one, and the shares that hid a card on a common build were split. Seven new kinds are table rows in `shot_trail.gdshader` (plus a branch in `shot_particle.gdshaderinc`); a shot's kinds are packed 5 bits each now (4 bits only reached kind 15). The test lists every modifier and the shares allowed. Looked at 4x in `looks_later_*_4x`: zig, double, weight and drift read; ripple and curl and converge are faint (small, sparse pixels), noted in the backlog.

## 2026-10-29: Staff codes in the radial builder (staffs D2 follow-up)

The radial builder copies and pastes staff codes like the list one: X copies the shown staff, A pastes the clipboard over it. A row under the ring shows both buttons, then for 3.5 s a one-line result ("Copied 2 cards", "Pasted 4 cards", or the reason it was refused). The names of the casts (E1) show on a line above it, from the staff as RT would leave it while a card is pointed at. Tests are in `test_radial_builder.gd`.

## 2026-10-29: The Rime Crook and the Bone Scepter (living staffs H5)

Two more strays, content only. The Rime Crook (`content/enemies/rime_crook/`) is a wooden crook with ice fangs and bands that casts frost · hook: it pulls a player toward it from 120 px. The Bone Scepter (`bone_scepter/`) is a skull on a stick whose dark sockets the shared face lights in Void pink; it casts void · rain from 130 px as a zoner. Folders are discovered, so nothing else lists them. `test_strays.gd` now covers five strays (style, glow, cards, valid staff) and runs each new one against four players.

## 2026-10-29: Staff codes (staffs D2)

A staff copies as one line, `sm1:double,fire,-,bolt` (card ids by slot, `-` for an empty slot, the empty tail left off), and pastes back. `StaffCode` (`core/spells`) is pure text work: it takes only lower-case names, at most 40 cards and 600 characters, checks every id with the registry, and never loads or runs anything from the text. The list builder gained a row of "Copy code" and "Paste code" buttons (system clipboard; the d-pad reaches them between the tabs and the slots); a paste sends one `staff_cards_requested`, so the player still refuses cards it does not own. The radial builder and the pause menu have no code buttons yet.

## 2026-10-29: Bots and the emergent combo report (staffs D1)

The bots (`Bot.build_random`, seeded) and the staff fuzz already existed from A6a/A6b; D1 adds the report. `test_spell_fuzz.gd` now prints `REPORT` lines after each run: the five best of its 600 random staffs by kills and by reactions, and the five costliest by mean step time and by safeguards met (dropped shots, then peak live shots), each with its cards and generated name. The fuzz imps now have 60 health (they had 400 and nothing died). Run it with `ci/build/build.sh --quick --tests` and read `build/logs`; paste a run here when cards land.

Review round: ties in a ranking now go to the lower staff number (`sort_custom` is not stable), each line starts with the ranked value and shows `(unnamed)` for a staff without a name, and a `REPORT WARNING` prints when no staff kills an imp, so an empty report is noticed. Tests: `test_report_ranking`, `test_report_ties_are_total`.

First run (seed 20261026, 600 staffs, 2 s each), the lines that do not depend on the machine (cards shortened):

```
REPORT BEST BY KILLS: 2 kills | Skewering Lazy Patient Beam | staff 44 [on_cast pierce slow sniper sniper beam]
REPORT BEST BY KILLS: 1 kills | Overcharged Echoing Rime Beam | staff 191
REPORT BEST BY KILLS: 1 kills | Stuttering-Magnetic Plump Bolt | staff 315
REPORT BEST BY REACTIONS: 4 reactions | Arcing Bloom | staff 89 [arc nova triple storm lightning faster void]
REPORT BEST BY REACTIONS: 4 reactions | Zippy Bloom | staff 531
REPORT BEST BY REACTIONS: 2 reactions | Bolt | staff 70 [bolt frost fire]
REPORT COSTLIEST BY SAFEGUARDS: 105 | Stuttering-Wall | staff 462 [burst wall mirror split echo]
```

So random staffs mostly do little: kills are rare, reactions rarer (one kind), no staff drops a shot at the pool, and nothing needs a limit yet.

## 2026-10-29: The first cards' looks (staffs C0)

Review round: seen at 4x (`looks_hops_4x`, `looks_wake_4x` in `shot_looks.gd`), hops did not draw at all, for three reasons now fixed: its trail window (0.15 s) cut its particles, the spawn rate was read from the wrong table row (`kind_row` now maps kinds 13 and 14 to rows 16 and 17 everywhere), and its every-other-frame blink hid it whenever a still shot was captured on an even frame (now always shown; the dash lines jump sideways). Wake is brighter dashes. READMEs and comments updated.

The three original modifiers without a look now have one: split a burst (9), chain hops (13, new: a pixel that jumps sideways), faster a wake (14, new: pixels flung back fast); sparks and streaks were taken by lightning, pierce and heavy. Carriers and infusions already had theirs; the numbers were reviewed and kept. `test_projectile_looks.gd` uses echo as its card without a look. Test: `test_original_looks.gd`.

## 2026-10-29: Spell names (staffs E1)

Every cast of a staff now has a generated name: `SpellNamer` reads a compiled cast and builds "Twice-Seeking Firefrost Bolt of Sudden Novas" from the cards' `name_words` (a new field on every card, two words each so a name can vary; a plain bolt is "Bolt"). Same cards, same name (a djb2 hash picks between a card's words). `Spells.staff_view` returns it as `name`, and the list builder prints it above each cast of the plan. Tests: `test_spell_names.gd` (exact names, plurals, growth, determinism, and that every real card has words).

## 2026-10-29: Builder tab glyphs

The builder's staff tabs now show the staff button (RB, RT, LB, LT on a pad, keys on the keyboard) drawn by `ActionGlyph`, still marked "[ ]" on the shown staff. Each tab holds a box with its marks and the glyph, so the layout places it; tests check the glyph sits centred in its tab, also on the keyboard, and that four builders still fit. New shot `builder_keyboard_tabs`.

## 2026-10-29: Card familiar (staffs C)

Added the Familiar carrier (data only: `.tres`, icon, assets, lore), the combos `familiar_bolt` and `familiar_and_frost`, and `test_familiar.gd` (the card's data, the entity it asks for near the caster, four players). The combo arena has no `ai`, so the combos check that the cast asks for a familiar (the `spawned` check) and that the other staff works beside it; the familiar's casts are covered by the Entities and spells tests.

## 2026-10-29: Card decoy (staffs C)

Added the Decoy carrier (data only: `.tres`, icon, assets, lore), the combos `decoy_and_fire` and `decoy_frost_cover`, and `test_decoy.gd` (the card's data, the entity it asks for at the caster's feet, four players). The combos check, with a new combo check kind `spawned` (the arena now records entity spawns), that the cast asks for a decoy and that the other staff works beside it. The combo arena has no `ai`, so the lure and the end point are covered by the Entities and spells tests.

## 2026-10-29: Card swap (staffs C)

Added the Swap carrier (data only: `.tres`, icon, assets, lore), the combos `swap_trade`, `swap_miss` and `swap_frost`, and `test_swap.gd` (the card's data, the caster and target moves it asks for, four players).

## 2026-10-29: Card recoil (staffs C)

Added the Recoil modifier (data only: `.tres`, icon, assets, lore), two combos (`recoil_blast_bolt`, the rocket jump, and `recoil_split_bolts`) and `test_recoil.gd`. Strength: 24 px, about three-quarters of a tile, over `RECOIL_SECONDS`. Recoil is asked once per firing, so a split volley kicks once and `mirror · recoil · bolt` asks two opposite pushes that the player adds up to nothing. All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: Card hook (staffs C)

Added the Hook carrier (data only: `.tres`, icon, assets, lore), the combos `hook_pull`, `hook_miss` and `hook_and_fire`, and `test_hook.gd` (the card's data, the pull on a hit, no pull on a miss or beyond the reach, four players). `tests/core/test_svg_art.gd` still fails on `modifiers/shield/icon.svg` (a `<path>`, open outline), which is not part of this card.

## 2026-10-29: Card teleport (staffs C)

Added the Teleport carrier (data only: `.tres`, icon, assets, lore), the combos `teleport_away`, `teleport_and_fire` and `shield_teleport`, and `test_teleport.gd` (the card's data, the move it asks for, four players).

## 2026-10-29: Card hold (staffs C)

Added the Hold modifier (data only: `.tres`, icon, assets, lore), the combos `hold_fire_orbit` and `hold_shield_orbit` and `test_hold.gd`, which checks that the shots outlive an orbit's lifetime only with the card, that `mana_reserved` goes up and comes back down on the next cast, and four players at once. All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: Card siphon (staffs C)

Added the Siphon modifier (data only: `.tres`, icon, assets, lore), two combos (`siphon_split_bolts`, `siphon_chain_bolt`) and `test_siphon.gd`, which checks the refunds through `mana_refund_requested`. Strength: 1 mana per hit. The bolt costs 5 and split costs 1.5 times that, so a volley of three hits gives back about 3 of 7.5: Siphon softens a cast and never pays for it (a first try at 3 per hit made split bolts net positive; a test now keeps a combo's refund under a bolt's cost). All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: A possessing player cannot strand a room (staffs C)

Found the bug behind the bots' missing `possess`: an enemy that died while possessed sent no `enemy_died` (its team was the wizards'), so flow kept counting it. Fixed in `Combat._die`, added a flow regression test, and put `possess` back in `Bot.build_random`'s bag. All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: Card on reaction (staffs C)

Added the On Reaction trigger (data only: `.tres`, icon, assets, lore), two combos (`on_reaction_thaw_hex`, `on_reaction_shatter_fire`) and `test_on_reaction.gd`. All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: Card on hurt (staffs C)

Added the On Hurt trigger (data only: `.tres`, icon, assets, lore), two combos (`on_hurt_orbit_nova`, `on_hurt_rune_frost`) and `test_on_hurt.gd`. All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: Card on kill (staffs C)

Added the On Kill trigger (data only: `.tres`, icon, assets, lore), two combos (`on_kill_bolt_nova`, `on_kill_bolt_frost`) and `test_on_kill.gd`. Combo imps may now carry a health (`[x, y, health]`) and the check `killed` exists. All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: Card on block (staffs C)

Added the On Block trigger (data only: `.tres`, icon, assets, lore), two combos (`on_block_dash_nova`, `on_block_bolt_nova`) and `test_on_block.gd`. All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: Card mend (staffs C)

Added the Mend infusion (`.tres`, icon, assets, lore), two combos (`mend_blast_self`, `mend_pierce_party`) and `test_mend.gd`. The combo arena gained hurt wizard bodies and heal checks. All unit tests pass except `test_svg_art` on the Shield icon, already on main (see BACKLOG).

## 2026-10-29: Card blast (staffs C)

Added the Blast modifier card (data only: `.tres`, icon, assets, lore), two combos (`blast_rocket`, `blast_wall_burst`) and `test_blast.gd`. 140 of 141 unit tests pass; `test_svg_art` fails on the Shield icon (`<path>` and an open outline), which was already on main (see BACKLOG).

## 2026-10-29: Card magnet (staffs C)

Added the Magnet modifier card (`.tres`, icon, assets, lore), two combos (`magnet_pull_bolt`, `magnet_void_hex`) and `test_magnet.gd`. Unlike the other cards it was not data only: nothing sent `pull_requested` for a magnet shot, so `Spells` now does (`_step_magnets`). The combo arena can move its imps by combat's push (`pushable`, the combo key `pushed`). All 140 unit tests pass.

## 2026-10-29: Card shield (staffs C)

Added the Shield modifier card (`.tres`, icon, assets, lore), three combos (`shield_dash`, `shield_wall_fire`, `shield_orbit_ring`; combo files may now name a `guard`, enemy `foes` and the check `blocked`, so each combo shows a real block) and `test_shield.gd` (valid card, charges add up, a shielded bolt and each wall stone block enemy shots from every seat, a shield on a dash or on the caster is a barrier on it). Engine: `Spells` now sends `wizard_shield_requested` (dash, teleport, hook, caster) and gives orbit and still shots their shield, which it never had. See DECISIONS.

## 2026-10-29: Card heavy (staffs C)

Added the Heavy modifier card (data only: `.tres`, icon, assets, lore), two combos (`heavy_wall_slam`, `heavy_hex_slam`) and `test_heavy.gd`. All 139 unit tests pass.

## 2026-10-29: Card on wall (staffs C)

Added the On Wall trigger card (data only: `.tres`, icon, assets, lore), two combos (`on_wall_bolt_nova`, `on_wall_bolt_rune`) and `test_on_wall.gd` (valid card; each combo holds with it, fails without it, and does nothing with no wall). The B2 engine already fired it.

## 2026-10-29: Card relay (staffs C)

Added the Relay modifier card (data only: `.tres`, icon, assets, lore), two combos (`relay_teammate_frost`, `relay_teammate_fire`) and `test_relay.gd`. The combo format got optional `mates` and a cast `dir`.

## 2026-10-28: Card sticky (staffs C)

Added the Sticky modifier card (data only: `.tres`, icon, assets, lore), two combos (`sticky_plant_nova`, `sticky_frost_plant`) and `test_sticky.gd`. All 136 unit tests pass.

## 2026-10-28: Card wall (staffs C)

Added the Wall carrier card (data only: `.tres`, icon, assets, lore), two combos (`wall_fire_barrier`, `wall_frost_row`) and `test_wall.gd`.

## 2026-10-28: Card fissure (staffs C)

Added the Fissure carrier card (data only: `.tres`, icon, assets, lore), two combos (`fissure_fire_line`, `fissure_hit_nova`) and `test_fissure.gd`.

## 2026-10-28: Card rain (staffs C)

Added the Rain carrier card (data only: `.tres`, icon, assets, lore), two combos (`rain_nova_drop`, `rain_frost_field`) and `test_rain.gd`. All 132 unit tests pass.

## 2026-10-28: Card mirror (staffs C)

Added the Mirror modifier card (data only: `.tres`, icon, assets, lore), two combos (`mirror_back_guard`, `mirror_frost_pincer`) with an imp ahead and one behind, and `test_mirror.gd`. All 131 unit tests pass.

## 2026-10-28: Card scatter (staffs C)

Added the Scatter multicast card (data only: `.tres`, icon, assets, lore), two combos (`scatter_nova_flurry`, `scatter_kindle_flurry`) and `test_scatter.gd`. The combos put an imp 20 px from the caster and check reactions, since how much a scattered nova deals depends on its random turn. All 130 unit tests pass.

## 2026-10-28: Card burst (staffs C)

Added the Burst multicast card (data only: `.tres`, icon, assets, lore), two combos (`burst_triple_bolt`, `burst_nova_pulse`) and `test_burst.gd`. The new card in the bag changed what the 4-bot smoke test's bots built (a `possess` staff) and the room was not cleared; bots now leave `possess` out, and the smoke test prints the builds when it fails. All 129 unit tests pass.

## 2026-10-28: Card echo (staffs C)

Added the Echo modifier card (data only: `.tres`, icon, assets, lore), two combos (`echo_double_tap`, `echo_timer_nova`) and `test_echo.gd`. The combo test learned a `lost_at_least` check, with both combos as control rows (their checks fail without echo). All 128 unit tests pass.

## 2026-10-28: Card on cast (staffs C)

Added the On Cast trigger card (data only: `.tres`, icon, assets, lore), two combos (`on_cast_rune_bolt`, `on_cast_bolt_nova`) and `test_on_cast.gd`. The B2 engine already fired it. All 127 unit tests pass.

## 2026-10-28: Card growth (staffs C), already built

The Growth card was already done: the modifier `.tres`, icon, assets, combos (`growth_far_shot`, `growth_slow_orb`) and `test_growth.gd` exist, and all 126 unit tests pass. Ticked it off; no code changed.

## 2026-10-28: Card linger (staffs C), already built

The Linger card was already done: the modifier `.tres`, icon, assets, combos (`linger_nova_mine`, `linger_frost_mines`), lore and `test_linger.gd` exist, and all 126 unit tests pass. Ticked it off; no code changed.

## 2026-10-28: Card slow (staffs C), already built

The Slow card was already done: the modifier `.tres`, icon, assets, combos and `test_slow.gd` exist, and all 126 unit tests pass. Ticked it off; no code changed.

## 2026-10-28: Card arc (staffs C), already built

The Arc card was already done: the modifier `.tres`, icon, assets, combos (`arc_nova_trap`, `lightning_orb`), lore, `test_arc.gd` and `test_spells_slow_return_arc.gd` exist, and all 126 unit tests pass. Ticked it off; no code changed.

## 2026-10-28: Card return (staffs C), already built

The Return card was already done: the modifier `.tres`, icon, assets, two combos, lore and `test_return.gd` exist, and all 126 unit tests pass. Ticked it off; no code changed.

## 2026-10-28: Card ghost (staffs C), already built

The Ghost card was already done: the modifier `.tres`, icon, assets, two combos, lore and `test_ghost.gd` exist, and all 122 unit tests pass. Ticked it off; no code changed.

## 2026-10-28: Card spiral (staffs C), already built

The Spiral card was already done: the modifier `.tres`, icon, assets, two combos, lore and `test_spiral.gd` exist, and all 125 unit tests pass. Ticked it off; no code changed.

## 2026-10-28: Card bounce (staffs C), already built

The Bounce card was already done: the modifier `.tres`, icon, assets, two combos, lore and `test_bounce.gd` exist, and all 122 unit tests pass. Ticked it off; no code changed.

## 2026-10-28: Card overcharge (staffs C), already built

The Overcharge card was already done: the modifier `.tres` (x2 damage, x2 mana), icon, assets, two combos, lore and `test_overcharge.gd` exist. Ticked it off; no code changed.

## 2026-10-28: Card triple (staffs C), already built

The Triple card was already done: the multicast `.tres`, icon, assets, two combos, lore and `test_triple.gd` exist, and all 122 unit tests pass. Ticked it off. `tools/check.sh` reports errors only for `.idea`, `.vscode` and `scripts`: unreadable folders of this environment that git doesn't track, so none come from the doc files changed here.

## 2026-10-28: Card double (staffs C), already built

The task found the Double card done: the multicast `.tres`, icon, assets, two combos and `test_double.gd` exist, and all 122 unit tests pass. Ticked it off.

## 2026-10-28: Sandbox (staffs B7), already built

The task found B7 done: the sandbox room, both dummies, flow's sandbox events, the main menu button and the pause menu's Sandbox page exist with tests, which pass (`test_flow_sandbox.gd`, `test_sandbox_data.gd`, `test_main_menu_sandbox.gd`, `test_pause_menu.gd`). They landed in owner sessions (#295, #296). The session only ticked it in `docs/NEXT.md`; no code changed. The "Friendly fire" setting in the design row no longer applies since actors G3c; `docs/milestones/M2-staffs.md` now carries a note on those rows. `tools/check.sh` was rerun: none of its findings are in the doc files changed here.

## 2026-10-26: Caster kit (staffs B4)

The wizard now acts on every move a card can ask for. Teleport jumps along the aim and stops short of the first wall; hook and swap pull the wizard to a point over the time asked; recoil pushes it back, with the recoils of a step added up so a mirrored recoil cancels. A later dash, teleport, hook or swap replaces an earlier one, which is still answered (`caster_move_finished`) where the wizard is, so its blast is not lost. Chill and freeze slow and stop walking and dashing, hits push the wizard (combat's knockback), and siphon's refund gives mana back. A move now walks its whole time (before, the last step of a dash was not walked) and is answered by the next step. Tests: `test_player_caster.gd` (14).

## 2026-10-26: Shot look, part 2 (staffs B6b)

Feel's per-form looks are data on the carrier cards now (`FormBase.cast_look`, `impact_look`; the five `.tres` carry the old preset values, the preset has none, the old rune and orbit textures are gone). The shots' particles and bolt trails come from one pool with a global count (`particle_cap`, 1,024): the manager adds up what the drawn shots ask for, particles get their share first, the trails get what is left and thin down to nothing, and only then do the particles thin, every shot alike (the shader reads `particle_share` and `trail_share`). New clips: four players firing the same cards, and a crowd of sparks. Tests: 6 pool tests, the form-look tests read the cards, a clip-scenario test.

## 2026-10-26: Combat kit (staffs B3)

`gameplay/combat` now does what the staff cards need from a fight: every hit has a kind (`hit_landed` before `damage_dealt`), a wizard is hurt by their own spell like any other target (damage, push, status), wizards have burn, chill/freeze, shock, hex and static of their own, barriers (`wizard_shield_requested`, `shield_blocked`), area hits (`area_hit_requested`), several elements on one hit (each reacts with what the one before left), heal hits (`heal_dealt`, which `gameplay/player` now applies), pulls (`pull_requested`) and the heavy wall slam. It sends `kill_landed`, `reaction_landed` and `wizard_hurt` for cards, and `downed_note` for "downed by your own Blast". `gameplay/feel` gives each kind a default stop, shake and sound, the self-hit its own ring, the heal a soft ring, and shows the note. Not switched on yet: `Spells` does not send the shield and pull events or set self-hit on shots (B2 and the cards). Tests: `test_combat_kit.gd` (35), `test_feel_hit_kinds.gd` (11) and four compiler rows.

## 2026-10-26: Trigger kit, part 4 (staffs B2d)

The spell runtime runs the moves, areas and refunds: teleport (a blink along the aim, cut at walls), hook (a hit pulls the caster to it), swap (a hit moves the target to the caster and the caster to the target), recoil (a push back from each firing of the cast, so mirror cancels it); the end of a dash, teleport or hook (`caster_move_finished`) is the carrier's end point, where its blast and `on expire` payload happen; `blast` asks combat for an area hit where a shot or beam ends; siphon refunds mana per hit. Tests: `tests/core/test_spells_moves.gd` (22 tests). **B2 is done.**

## 2026-10-26: Trigger kit, part 3 (staffs B2c)

The spell runtime runs the payload and line carriers: rain (a `form_shown` cue, then its payload on the aim point after its lifetime), familiar and decoy (`entity_spawn_requested`, counted as live until `entity_ended`; a familiar casts its payload on `familiar_cast_requested`; a decoy's end point fires its `on expire` payload and `blast`), wall (a line of still shots across the aim, shields apply) and fissure (a beam through everything on its line). Tests: `tests/core/test_spells_payload_carriers.gd` (28 tests). B2d (moves, areas, refunds) is next.

## 2026-10-26: Trigger kit, part 2 (staffs B2b)

The spell runtime runs the multicast spread: scatter (random directions, seeded per cast), burst (later firings of the group, queued), echo (the carrier again after its strength in seconds, at half damage) and mirror (also fires backwards). Tests: `tests/core/test_spells_multicast.gd` (27 tests). B2c and B2d are next.

## 2026-10-26: Trigger kit, part 1 (staffs B2a)

The spell runtime fires the payloads of the seven new trigger events (on block, on kill, on cast, on wall, on hurt, on reaction, on ally) and runs `relay`. Tests: `tests/core/test_spells_triggers.gd` (10 tests). B2b to B2d (multicast spread, payload carriers, moves and refunds) are next.

## 2026-10-26: Projectile kit (staffs B1)

`core/projectiles` runs the movement and collision behaviours of the staff cards: bounce, ghost, spiral, return, linger, growth, sticky, shield (`shot_blocked`), shots that may hit their caster after leaving the caster's hitbox, shots that pass teammates (`ally_passed`) or hit them (mend), and `expired_on_wall` for `on wall`. The spell runtime hands a shot these from the card strengths, so the cards after B1 (bounce, double and the like) are data. Self-hit and ally-hit are available but not switched on by `Spells` yet: combat has no self-harm until B3. Tests: `tests/core/test_projectiles_kit.gd` (17 tests, including 1,500 shots with behaviours).

## 2026-10-26: The old recipe path removed (owner session, staffs A6c)

Staffs are the one way to build and cast. Removed: the recipe compiler (`Spells.compile`, `builder_view`, the clamps, the budget), the recipe wrappers, the fields only recipes used (`valid`, `reason`, `description`, `complexity`, `depth`, `held` on `CompiledSpell`), the build limits in `SpellLimits` (only the per-step fire and chain caps stay, as engine safeguards) and five events (`build_change_requested`, `spell_swap_requested`, `spell_changed`, `recipe_changed`, `active_spell_changed`). Tests that wrote spells as recipes build staffs through `tests/support/staff_kit.gd`; the limit tests became no-limit tests (a nova with two splits makes 72 shots; four chains jump eight times; payloads nest four deep). Phase A is done, so development is unpaused: the bot starts phase B, and the owner lane opens.

## 2026-10-26: Combos and tests on staffs (owner session, staffs A6b)

The 28 combo files are card rows now (`{"staff": 0, "cards": ["fire", "timer", "orbit", "fire", "split", "bolt"]}`), converted mechanically (infusions and modifiers, the trigger, the carrier, then the payload); all 28 still pass. The clip scenarios cast card rows (a lone card on a bolt; a trigger fires a nova; a multicast pulls three bolts). The fuzz test builds 300 random staffs from every card: no errors, every cycle finite, and the costliest staffs printed (the first run: at most 32 live shots, nothing dropped at the pool, the slowest step 0.3 ms headless).

## 2026-10-26: Player and builder on staffs (owner session, staffs A6a)

The game now plays on staffs. Four buttons cast four staffs (A `cast_a` Space, X `cast_x` left mouse or J, Y `cast_y` right mouse or K, B `cast_b` Q or L); menus activate with A and go back with B; the overlay moved to Start (Back is `leave`). The wizard holds four rows of cards, builds them through `Spells`, offers `free_mana()` (mana minus what `hold` cards keep), and a held button never switches a `hold` off. Dodge is gone: the `dash` card (220 px/s for 0.25 s, no invulnerability) asks the wizard to dash through `caster_move_requested`, and the wizard reports `caster_move_finished`. Flow hands every wizard the `dev` staff (20 slots) in dev and preview builds and the `starter` (4 slots) otherwise, with A `dash` and X `fire bolt`; the staff numbers were retuned so a two-card staff is not slowed by its recharge (starter delay 0, recharge 0.05 s). The builder is new: four staff tabs, the slots and the bag in scrolling lists, picks that fill a staff left to right, the cast plan as text, open at any time, waves included; the quick view and the overlay's Bag drop are gone (owner: "A full builder is always preferred"). Bots build into staff Y and fight with X and Y; the stress runner builds X and Y. The owner's idea of generated spell names became part E1.

## 2026-10-26: The staff runtime (owner session, staffs A5)

The owner paused development (control panel) so the bot would not idle through tasks that wait on A5, and an owner session built it. Staffs cast: four per player, each with its cycle, cursor, delay and recharge; multicast carriers fan out; payloads fire as groups; fallbacks ask combat for an area hit (`area_hit_requested`, which nothing hears until B3); `hold` keeps its shots and reserves mana until the staff is cast again or edited. The tag is now player, staff, generation and node above `1 << 20` (enemy attack tags reach 101,000). Recipes run as staffs of one cast, so the old cast, trigger and combo tests pass unchanged on the new runtime; the three tag tests that assumed two slots now use four staffs. New: `tests/core/test_staff_runtime.gd` (10 tests).

## 2026-10-26: The staff compiler (owner session, staffs A4)

`Spells.compile_staff(cards, staff)` reads a staff into its cycle with the rules of the design (`core/spells/staff_compiler.gd`), and `Spells.staff_view` gives the builder plain values. Every example in the design is a test in `tests/core/test_staff_compiler.gd` (20 tests). Two things the tests taught: wrap-around lets a trailing card reach the first carrier in a later cast (so `fire · bolt · homing` puts homing on a bolt in cast 2, and `double · on hit · bolt · nova · bolt · blast` makes two casts of three spells each), and a 64-slot staff can make more than 128 compiled spells in one cycle, so the tag's node field is 9 bits. Nothing casts a compiled staff yet; that is A5.

## 2026-10-26: Card and staff classes, events (owner session, staffs A3)

The foundation the kits build on, so they never edit the same base file: `MulticastBase` (double, triple, scatter, burst); `FormBase.Motion` DASH to FAMILIAR (`carries_payload()` for rain and familiar), `ModifierBase.Behaviour` SHIELD to RELAY (`behaviour_strength` now up to 256, and every behaviour needs one above 0), `TriggerBase.Event` BLOCK to ALLY, each commented with the kit that runs it; `StaffBase` and the `starter` (4 slots) and `dev` (20 slots) staffs; the staffs events (`staff_change_requested` to `ally_passed`) with their senders; `multicast` as a kind in the Spell atlas and the clip pipeline (`ci/smbot/clips.py`, an owner-path change made in the owner session). Nothing runs the new values yet.

## 2026-10-26: Shared files split (owner session, staffs A2)

So card PRs never edit the same file: the 26 combos are one file each in `content/spells/combos/` (`combos.json` is gone; the test, the clip scenarios and the Spell atlas read the folder), a content folder may list its assets in an `assets.json` beside them (the validator and `test_svg_art` read every one with `art/manifest.json` and `audio/manifest.json`), and no test keeps a card list or count by hand (`test_combos` checks every component the registry finds; the icon count and the drop-list length are derived). AGENTS.md and the spells, art, audio and tests READMEs say so.

## 2026-10-26: Pivot at C2: the staffs rework is planned (owner session, staffs A1)

The owner answered the second C2 checkpoint (#264) with a pivot, planned in an owner session: spells are built in four staffs per wizard from cards read in order (`docs/milestones/M2-staffs.md`). Written: the design (reviewed by a fresh-context session, see `docs/DECISIONS.md`), the owner's new rows in `docs/DESIGN.md`, `docs/NEXT.md` in two lanes (the bot's `## Queue` and the `## Owner lane` for the owner's parallel sessions), later ideas in `docs/BACKLOG.md`, the ROADMAP row, PLAN.md's build elements and builder notes, llms.txt. The unchecked "Spell visuals round 2, part 2" task is dropped as superseded (BACKLOG). No game code changed.

## 2026-10-26: Spell visuals round 2, part 1 (#244, p2)

The owner found the shaped shots too big and the combos plain. Bodies are now 0.8 of the old bolt (was 0.62) with three trail marks each (384 at most, still one draw batch). New event `combo_cast`, sent by `Spells.cast` with `Spells.combo_class`: a flat mark on the caster per class, a ring of ticks (boosted), chevrons along the aim (on_hit), a diamond (on_expire), a dashed ring with a ticking hand (timer), ring over diamond (stacked); made in code in `gameplay/feel/combo_marks.gd`, so no assets. Looked at the sheet `combo_marks` and the clips (`combo_fire_fan_orbit` shows the timer ring); a first version that turned the rings by 22.5 degrees came out ragged, so quarter turns only. The resolution question is assessed in `docs/DECISIONS.md` and added to the C2 second-round text. Part 2 (a release burst per multi-component combo) is in NEXT.md. Tests: `test_feel_combo_marks.gd`, `test_spells_cast.gd`, `test_events.gd`, `test_projectile_shapes.gd`; all unit tests pass.

## 2026-10-26: Scrolling drop lists

The quick view's drop list (11 rows) and the overlay's (6 lines of two) are now windows: a longer list scrolls to follow the focused row (`hud/widgets/row_window.gd`), so a twelfth element or modifier no longer pushes the panel off its quarter of the screen. UIFocus is unchanged. The title shows "n/total" when the list scrolls. Tests: `test_quick.gd` (a 16-row list in the quick view and the overlay, the focused row always in view, the window maths). Screenshots of the 11-row lists look as before. Decisions in `docs/DECISIONS.md`.

## 2026-10-26: Lightning, reactions, combos and the report (#243, part 2)

Two reactions for lightning with fire and frost, four rows (a pair each way): **Overload** (`burn` + lightning, `static` + fire: a burst of 4 in 52 px) and **Superconduct** (`chill` + lightning: freeze 1.5 s; `static` + frost: the charge used up for 4 bonus damage). Colours and power are in the Feel preset (`overload` brown, `superconduct` teal, `discharge` cyan; all at least 0.45 apart from the six older ones in `test_feel_reactions.gd`). The discharge now has its colour, the sound id `reaction_discharge` (no `.ogg` exists, so it is silent like the other reaction sounds; listed under Audio needs) and an arc: the event `discharge_arc(player, from, to)` (`core/events`, sent by combat once per enemy zapped) and Feel draws a jagged `Line2D` from the struck enemy to each, from a pool of eight, 0.25 s. Combos: `overload`, `superconduct` (two players) and `shared_charge` (two players, the discharge). Tests: `test_combat_reactions.gd`, `test_combat_statuses.gd` (arc), `test_feel_reactions.gd`, `test_events.gd`, the combo test over the new rows. `content/spells/README.md` now says what a new element needs outside its folder. Clips `combo_overload`, `combo_superconduct`, `combo_shared_charge`. The extensibility report is in the PR; proposals are in `docs/BACKLOG.md`.

## 2026-10-26: Lightning, status and element (#243, part 1)

Added the fifth element, Lightning (complexity 1), and the `static` status. A static enemy hit again by any player's spell discharges to every other static enemy within 96 px for 60% of the hit (at least 1), as plain hits for the same player, announced as `reaction_triggered` `discharge` at each. One step only: no chain, and a reentrancy guard refuses a discharge started inside another. Looks: a new palette ramp "Arc" (acid lime), a forked-arc shot body with a spark trail, an enemy overlay (lime blink, apart from Storm's yellow), and an icon. Sheets `element_shots`, `statuses_4x`; clips `element_lightning`, `combo_static_bolt`, `combo_static_ring`.

Files changed outside `content/spells/elements/lightning/`, and why:
- `gameplay/combat/combat.gd` (+README): the status and the discharge (two packed arrays, a line in each `match`).
- `core/spells/validator.gd`, `core/spells/spells.gd`: `static` as a known status, and its description verb "Charges".
- `core/base/element_base.gd`: `shape` range 0–5.
- `core/projectiles/projectile_manager.gd`, `shot_core.gdshader`: shape 5 (the arc) and its trail mark; the kind numbers moved (marks 6–10, rune 11, orbit 12) because trail marks were "shape + 4".
- `gameplay/feel/presets/feel_preset.gd` (+README): the status look, `status_order`, the discharge's power.
- `hud/builder/builder.gd`, `hud/panels/overlay/overlay.gd`: the drop lists hold every element and modifier, 11 now, which no longer fit a player's quarter at 14 px rows; rows are 12 px in 8 px text.
- `docs/STYLE.md`, `art/kit/*` (palette, GIMP palette, README, checklist), `tests/core/test_svg_art.gd`: the Arc ramp (40 colours).
- `art/manifest.json`, `content/story/lore/components/lightning.json`, `content/spells/combos.json` (two rows: the combo test needs two per component), `content/spells/README.md`.
- Tests and shots: `test_combos.gd`'s COMPONENTS, `test_validators.gd`, `test_svg_art.gd` (counts), `test_projectile_shapes.gd`, `test_combat_statuses.gd`, `test_quick.gd` (11 rows), `shot_element_shots.gd`, `shot_statuses.gd`.

## 2026-10-25: Visual polish with the clips (#244 rework)

Looked at the 51 clips and the sheets at 1x. Worst finding: the flame body (most visible when Bigger scales it) had a pale, washed-out middle; its light tier is now a small hot head in `shot_core.gdshader`. Four smaller findings (thin storm bolt, two-player coop clips, speckled orbit beads, no volley in the four-wizard sheet) went to `docs/BACKLOG.md`. The particle limit is unchanged and tested in `tests/gameplay/feel/`. After the shader change the sheets were rebuilt and the flame in `shot_form_bodies` and `element_shots` looked at again at the default 0.62 scale: the body is the element colour with a small light head.

## 2026-10-25: Spell visuals, reactions and statuses (#244, part 3)

A reaction is now a burst bigger than a plain hit: a ring that opens next to the flash, a particle burst 2.2 times the size, a hit-stop of 0.09 s (a death's is 0.07) and more shake, scaled per reaction by `reaction_power` (Shatter 1.3 the most, Stillness 0.9 the least), with the sound `reaction_<id>` as before. An enemy with burn, chill, freeze, shock or hex wears a tinted copy of its `Sprite` (orange pulse, steady pale blue, solid white-blue, a yellow blink with a one-pixel jitter, a slow purple pulse), read from `Combat.status_left` every 0.1 s and gone when the status ends; the hit flash covers it for its moment. Data is in the preset (`status_looks`, `status_order`). Sheet: `shot_statuses`; clips `reaction_*`. Tests: `test_feel_reaction_bursts.gd`. The reaction sounds themselves are still not in `audio/` (silent by design).

## 2026-10-25: Spell visuals, forms: bodies in flight (#244, part 2b)

A rune is a diamond that swells and settles while it waits, an orbit shot two beads that turn and breathe (`shot_core.gdshader` kinds 9 and 10, animated from `sim_time`; the manager writes them for every player rune and orbit shot, whatever the element). Shaped bodies are drawn smaller (`SHAPE_SCALE` 0.62) after the owner's note that the new visuals were too big. Elements still show their colour (core) and their shape; the trail marks are the type particles. Tests: `tests/core/test_projectile_shapes.gd`. Sheet: `shot_form_bodies`; clips `form_rune`, `form_orbit`, `form_bolt`. More animation for combined spells is in the backlog.

## 2026-10-25: Spell visuals, forms (#244, part 2)

Bolt, beam, nova, rune and orbit each have a cast flash on the wizard (streak, long flare, ring burst, rune and orbit gathering in), a flare where they end or hit (beam stretched along the beam, nova and rune rings, orbit tick) and a beam that opens wide and thins. Data is `cast_looks` and `impact_looks` in the preset; an enemy's shot always ends in an ember mark on its corner. The flare comes from the shot's own form (`Projectiles.impact_form`), not the last cast. The bodies in flight are a separate Queue task. Tests: `tests/gameplay/feel/test_feel_form_looks.gd`, `tests/core/test_projectile_impacts.gd`. Sheet: `shot_form_looks`; clips `form_bolt`, `form_beam`, `form_nova`, `form_rune`, `form_orbit`.

## 2026-10-25: Spell atlas data (#245, part 2)

`tools/atlas.py <out>` writes the Spell atlas data (`atlas.json`) from the content, with no hand-written list: components, combos and reactions with name, builder line, `does`, clip ids and source file. Tests: `tools/test_atlas.py` (`python3 -m unittest discover -s tools`); `.py` files are only allowed under `tools/`, so the test lives there. No session could run Python (the sandbox refuses it), so the first CI run is the first run of both files; the revision made the reaction wording skip a zero damage or radius and the tests use temp rows. Next: spell visuals (#244).

## 2026-10-25: Spell visuals, elements (#244, part 1)

Fire, frost, storm and void shots have a silhouette, animation and trail of their own (flame, star, zigzag, ring), built in `shot_core.gdshader` from `ElementBase.shape`; the trail is a draw batch of at most 256 marks, not particles, so `Feel.PARTICLE_LIMIT` is untouched. Greyscale strip in `shot_element_shots` shows they read without colour. Four-bot smoke bench unchanged (peak 48 particles of 48).

## 2026-10-25: Clip recorder, Godot side (#245, part 1)

`tests/clips/record.gd` records one clip per scenario to `user://clips/<id>/` (`meta.json` and `frame_0000.png` and up, in the format of `ci/smbot/clips.py`); `build.sh --quick --clips` copies them to `build/clips/`. `scenarios.gd` reads the scenarios from the content: every combo row, every component alone, every reaction and a two-player version of each (51 clips today). `stage.gd` is the live stage (real runtime and Feel, stepped by hand). Test: `test_clip_scenarios.gd`. Ids and format are in `tests/README.md`; what is and isn't deterministic is in `docs/DECISIONS.md`. Next: the atlas data (`tools/atlas.py`).

## 2026-10-25: Planning after the C2 verdict

The owner answered C2 (#235) with iterate: recorder and Spell atlas (#245), spell visuals (#244), Lightning (#243). M2 is in progress again; nine tasks are in `docs/NEXT.md`, and the `ci/` part of the recorder is an owner question. Pet idea #208 stays on the backlog.

## 2026-10-23: Button glyphs instead of action names (owner `/claude` on #4)

The builder hints now show the glyph of the button to press ("[X] Use  [B] back") instead of "(Cast)" and "(Dodge)". New: `core/input/input_glyphs.gd` (the table per controller family), `PlayerInput.glyph_kind(player)` and `glyph_kind_changed`, and the widgets `hud/widgets/action_glyph.gd` and `hint_line.gd`, which redraw live. Tests: `test_input_glyphs.gd`, `test_action_glyph.gd`, and the builder and quick-view tests follow the new hint line; shot `shot_glyphs.gd`. Not done: overlay and Bag hints, a device handover for one player (both in `docs/BACKLOG.md`).

## 2026-10-23: M2 closed for the C2 checkpoint (planning)

The queue was empty. The 13:29 UTC daily run shows the web physics step at 7.58 ms (max 11.10) with one step per frame at the cap of 500, so the Blocked web stress task is answered (docs/DECISIONS.md) and nothing was changed in the limits. M2 stays in progress in the roadmap until the C2 checkpoint issue is opened (a read-only session cannot open it). Done-when item 3 is still open. The web run with rendering still warns (p95 56 ms) in the GPU-less CI browser.

## 2026-10-23: HUD and Builder made easier to use (owner `/claude` on #4, point 2)

Walked the builder through with one keyboard player and four gamepad players and listed nine things that are hard (in `docs/DECISIONS.md`). Fixed the worst three: slots are named in words ("Form", "Elem", "Mod 1", "Trig"), a hint line says what `cast` and `dodge` do for the control in focus, and the focused control has its own bright look (`BuilderButtonFocus`). Test: player 3 of 4 puts a component into a slot with gamepad button events. The rest is in `docs/BACKLOG.md`.

## 2026-10-23: "Drop component" is now "Bag" (owner `/claude` on #4)

The overlay and quick-view action is named "Bag"; its open list is titled "Drop". It already opened in combat for every player (the overlay is not wave-gated), so step 2 needed no code, only tests (1 and 4 players in a wave). The full Builder stays locked in a wave; the reason is in `docs/DECISIONS.md`. I could not read the test and screenshot output in this session (see the PR).

## 2026-10-23: The wave line shows only during a wave (owner `/claude` on #4)

"Wave N" stayed on screen after a wave was cleared, because only `run_started`/`run_ended` hid it and nothing sends them. It now hides at `room_cleared`; regression test in `test_panels.gd`.

## 2026-10-23: Three tasks from the owner's HUD feedback (owner `/claude` on #4)

Wrote three tasks in `docs/NEXT.md`, ahead of stabilisation: the always-visible "Wave N" text, Builder/Bag reachable in a room plus a better name than "Drop component", and a HUD/Builder usability rework. No code changed.

## 2026-10-23: The beam is held (owner `/claude` on #4)

The beam now ticks while fire is held: cooldown 0.25 s (4 hits a second on one enemy), 3 damage and 4 mana a tick (16 mana a second, against 10 regenerated); the drawn beam lasts 0.25 s (one tick, so beams do not stack). New test in `test_forms.gd`. `build.sh --quick --tests` passes.

## 2026-10-23: Web stress parts read, web projectile cap 500 (owner `/claude` on #4)

Read the first web `frame parts` lines in #202: the web physics step is 14 to 20 ms, so the engine runs up to 8 catch-up steps per frame (the 130 ms frame). Enemy, combat and Feel passes are small. Lowered `DEFAULT_CAP_WEB` from 1,000 to 500; the web stress scenarios follow the constant; docs updated. A new Blocked task checks the next daily web run. Not verified in a browser (a session can't run one).

## 2026-10-23: Style N recorded and the wizard made alive (M2 part 27, owner `/claude` on #206)

The owner chose N and asked for character animations, "an eye blink in idle and something that makes it feel alive". Redrew the in-game wizard in N: one shared body strip each for idle (open, closed, glance left, glance right), walk and dash, and four hats on a `Hat` node under `Sprite`; the twelve per-player strips are removed. `player.gd` orders the idle poses (a blink every few seconds, a glance now and then, a double blink), breathes with a 1 px bob and bobs on the walk and dash; the hat follows. Recorded the style in `docs/STYLE.md` and `art/kit/golden.json`. The SVG strips are hand-written rects (a generator script could not be run in this session). `build.sh --quick --tests` passes; the `art_sheet` and `arena_four_wizards` shots were looked at. `tools/check.sh` reports only the untracked `.idea`, `.vscode` and `scripts` folders of the runner.

## 2026-10-23: Fifth art direction round (M2 part 27, owner `/claude` on #206)

The owner answered round four with "4: keep the hat style, add a robe as the clothes, the face just two big eyes, no mouth; give me some examples". Added M (cream robe), N (dusk robe) and O (teal robe) in `art/samples/` (`m_cream/`, `n_dusk/`, `o_teal/`, each a `body.svg` under the existing hats), `tests/screenshots/shot_art_direction_5.gd` and a README section. `test_svg_art.gd` checks them, plus that the face has no cheeks or mouth. `build.sh --quick --tests` passes; the sheet was looked at. The pick is asked again (`art-direction-pick-3`); the record task stays blocked.

## 2026-10-23: Fourth art direction round (M2 part 27, owner `/claude` on #206)

The owner liked F's hat, found the body too wide and wanted a cuter wizard. Added J (tiny cream), K (bean brown) and L (gold, bigger head) in `art/samples/` (`j_tiny/`, `k_bean/`, `l_gold/`, each a `body.svg` under the existing hats), `tests/screenshots/shot_art_direction_4.gd` and a README section. `test_svg_art.gd` checks the new bodies. `build.sh --quick --tests` passes; the sheet was looked at. The pick is asked again (`art-direction-pick-3`); the record task stays blocked.

## C2 evidence

Gathered on 2026-10-23 from `ci/build/build.sh --quick --tests` (headless on the session runner: game logic only, no renderer) and the newest daily post (log #202, the 06:14 run). For the C2 checkpoint issue. M2 is not closed.

**Tests.** The whole build passes: smoke, every unit test, the validators (`test_validators`, 21 tests), `test_combos` (11), `test_spell_fuzz` (5), the 4-bot smoke and the stress run. No error lines logged.

**Fuzz (`test_spell_fuzz.gd`).** 300 seeded random recipes, 244 compile (the rest are refused by the real limits, as intended), all cast in the combo arena. Coverage is checked: among compiled recipes at least 5 have a held spell, 5 have three modifiers, 5 have a trigger and 20 have an element (`MIN_COVERAGE`). Over two runs: slowest mean step 0.45 to 0.50 ms, slowest single step 1.4 to 1.6 ms, most live shots 456. No broken limit, no runaway shot count.

**Headless stress (4 players with built spells, game logic only).** `STRESS OK`: 4 scenarios, no errors.

| Scenario | Enemies / shots | Frame avg | p95 | Max | Physics step (avg) |
|---|---|---|---|---|---|
| web | 100 / 1,000 | 6.90 ms | 11.56 ms | 13.58 ms | 5.26 ms |
| web, render loop off | 100 / 1,000 | 6.89 ms | 11.85 ms | 12.59 ms | 6.32 ms |
| web, hit particles off | 100 / 1,000 | 6.89 ms | 11.18 ms | 11.95 ms | 4.66 ms |
| desktop | 200 / 3,000 | 6.91 ms | 13.47 ms | 17.89 ms | 9.61 ms |

Budget 16.7 ms: web is inside it; desktop p95 is inside and its single worst frame is 1.2 ms over (a warning only). Per pass: enemy step 0.42 ms (100 enemies) and 1.21 ms (200); combat status lookups 0.26 and 0.91 ms (the O(n²) `find` worry in the backlog stays small at these sizes); Feel step 0.015 to 0.020 ms. Peak nodes 1,255 and 1,955; static memory 41 to 45 MiB (budgets 512 web, 1,536 desktop); hit particles at their limit of 48. Projectile timing at cap 1,000 and 3,000 (native): `update_draw` 0.77 and 2.3 ms, homing step 2.8 and 3.5 ms, orbit step 2.0 and 3.1 ms, a spawn 1.4 us.

**Web numbers (read 2026-10-23, 13:29 UTC run, release v0.20261023.3, cap 500).** Render loop off, 100 enemies and 500 shots: physics step 7.58 ms avg (max 11.10), one step per frame. The web run with rendering still warns (p95 56.5 ms) in the GPU-less CI browser, so M2 done-when item 3 is still open on the real-GPU frame rate (BACKLOG); it goes to the owner at C2. The earlier web numbers (before the cap, p95 151 ms) and the reading are in docs/DECISIONS.md, 2026-10-23.

**What the bots build.** In the 4-bot smoke test, bots 1 to 3 build from seeds 2026 to 2028 through `build_change_requested` and bot 4 stays in its builder. The room was cleared in 9.0 game seconds with 28 casts; the builds were an orbit with frost; an orbit with fire and homing, trigger on expire, holding a frost rune (two levels); a fire bolt with split and faster. The fuzz test covers the wider range (above). Wave balance with fighter bots on the default spell: 1 player cleared in 34.9 s (10 health lost), 2 in 26.2 s, 3 in 16.5 s, 4 in 12.9 s, nobody downed. That test follows real frame time, so the numbers move between runs (BACKLOG).

**The 21 combos** (`content/spells/combos.json`; all pass in `test_combos`, and each of the 18 components is in at least two): Burning bolt, Shatter, Big fire ring, Storm lance, Frost pulse rune, Void ring, Homing fan, Storm chain, Blast at the end, Swift line, Wide frost lane, Fire fan orbit, Hexed fire burst, Storm mine, Frost then lightning ray, Frost carousel, Seeking void ray, Fire trap, Quick shock ring, Seeking frost burst, Storm on flame (two players; Flare).

**After the iterate round (2026-10-26).** Facts, not a new run: 26 combos in `content/spells/combos.json` (the 21 above plus Static discharge, Static ring, Overload, Superconduct and Shared charge; `test_combos` runs every row and requires at least 20); Lightning is the fifth element, with two new reactions; the clip recorder (#245) with clips for the elements and the new combos; the drop lists scroll. The stress and fuzz numbers above were not measured again after Lightning, and the real-GPU frame rate (item 3) is still open.

**Carried over from M1 (done-when item 5).**
- Web 4-bot run (#93), web load time (#91), Style Guide page and kit zip (#95): the issues are closed and the owner's PR #98 merged on 2026-10-21. This run read no daily post showing the web 4-bot result, so "passes on web" (done-when item 4) is still to be confirmed from the next daily post.
- WASM projectile timing runner: done (part 25); the first WASM numbers are in (above).
- M0's dry runs and 3 daily releases in a row: owner-run; nothing in this log records them, so treat them as open.

**What M2 cut or left open (BACKLOG).**
- Spell runtime: a held fast or slow shot born on a hit crosses its target and can hit it again (the combo "Hexed fire burst" works around it); a beam has no timer trigger; `test_wave_balance` depends on real time and the 1 and 2 player bots often lose.
- Builder and quick view: no mouse (M4 polish); modifiers are picked one slot at a time; no hint on a disabled slot or button; held-spell levels are two small buttons and refusals name no held slot; a swap needs the quick view closed; the drop list names no slot; read-only slots look disabled; the builder panel is translucent.
- Reactions: the six flashes differ by colour and name only (a problem for colour-blind players); dark names on the dark floor; four flash slots may be too few.
- Art: the art direction is not chosen (owner question `art-direction-pick-3`, A to I); placeholders are redrawn later. Nothing shows a status on an enemy.
- Foundation: the wave is still a constant in `flow`; `player.gd` is large; `ai.gd` has one attack; four sounds (`cast`, `hit`, `enemy_death`, `player_downed`) do not exist; no wave announcement.
- Playtest: no building questions in the weekly playtest; the real-GPU web frame rate is unasked.

**Open M2 tasks:** read the web stress parts (waits on a daily run), record the art direction (waits on the owner), stabilisation and C2.

## 2026-10-23

- C2 evidence (M2 part 28, first half): collected in the section "C2 evidence" at the top of this file, above the daily entries. No bug found, no code changed; `build.sh --quick --tests` passes.
- Web stress frame, first half (M2 part 25 follow-up). No web run could be read (the newest daily log is still #202), so the stress run now measures the frame in parts for the next one: the probe prints physics steps per frame, physics and process time, renderer time and draw calls; the runner times the enemy step, the combat lookups and Feel's step per pass, and runs the web scenario again with the render loop off and with hit particles off. Headless, the web scenario's physics step is 5 to 6 ms, so at the WASM factor of 2 or more it nears or passes 16.7 ms and the engine would run up to 8 steps per frame: a possible reason for 130 ms frames. Nothing was lowered; the Queue task "Read the web stress parts" reads the numbers and decides. Tests: `Feel.particles_enabled`, the probe's step counters.
- Read the first WASM numbers (M2 part 25 follow-up). The daily log #202 had them: projectile timing in WASM is about 2x native (step 5.4 ms, update_draw 4.0 ms, homing step 8.6 ms at 1,000 shots), and the stress scene in the CI browser ran at p95 151 ms (Linux export: 14.6 ms). Homing is over the 8 ms target, so by the M1 part 22 rule `WORK_PER_STEP` went from 8,000 to 6,000 (an estimate; the next web run confirms it). The 130 ms stress frame is unexplained and over budget; a new Queue task times the rest of the frame on the web (`docs/DECISIONS.md`).
- Quick view walkthrough (M2 part 18, polish). `shot_quick.gd` now plays a wave by real input for one and four players (break, fold on `wave_started`, close + swap + reopen, Drop component, unfold on `room_cleared`; `walk_*` shots at 1x and 4x). Looked at all: text reads at 1x. Fixed: folding left a stale "> " on the form slot (two marks on screen), and a full spell folded with focus on a greyed "Drop component" (now Close). Two tests in `test_quick.gd`. The disabled-slot hint stays in BACKLOG (needs focus on disabled controls); other findings in BACKLOG.
- Wave and break lines under four builders (polish). Both lines moved into one strip in the middle of the view, in the 18 px gap between the top and bottom builders (they end at y 171 and start at 189 at 640x360). The gap fits about 17 px of text, so "Wave N" went from 16 to 12 px. Looked at the 1x shots: both readable beside the builders, nothing covered. New test checks both rectangles against all builders and panels.
- Reactions walkthrough (M2 part 8, polish). `shot_reactions.gd` now makes all six reactions by two real bolts each in the combo arena and replays them into the live game, three at a time (feel keeps four reaction flashes live), at 1x and 4x. Looked at the 1x crops: the flashes were the gold spark art tinted, so blue came out olive and violet brown; Shatter, Thaw and Stillness were three pale blues, Kindle and Flare two oranges. Fixed in one pass (flat-colour shader for reaction flashes, six far-apart colours) and looked again: six colours and six names read apart. Tests: colours differ, flash uses the shader. Rest in BACKLOG.

## 2026-10-22

- Builder walkthrough with four players (M2 part 29, polish). `shot_builder.gd` now walks the real input flow (new shots `builder_opened`, `builder_four_players_wave`, `builder_four_players_break_again`; looked at all). Fixed: opens on the form slot, "Close" follows the tabs in the focus order, tabs and held levels put focus on the form slot, a form or element in an empty slot moves on to the next bag (form + element is four presses, was nine), refusal texts say what to do. New tests in `test_builder.gd`; the awkward rest (mouse, wave line under four builders, modifiers) is in `docs/BACKLOG.md`. `build.sh --quick --tests` passes.
- Multimesh upload follows use: bolt, rune, orbit and enemy batches size their MultiMesh and buffer to the shots drawn (power of two, 64 to the cap) instead of cap x 16 floats each frame. Tests: `_test_batches_upload_only_the_used_slice` (0, 1 and the cap), `_test_every_batch_is_sized_to_its_own_shots` (mixed batches) and `_test_batch_room_grows_and_shrinks_with_hysteresis`. The per-batch counts live in a member array, so no per-frame allocation.
- M2 part 27, round three: the owner (#192) liked F's hat, found its body weak, and asked for a hat-only player colour, more options and a palette look. Drew G (brown robe), H (cream robe), body and hat as separate layers (four hats per palette), and I (H with vivid player ramps and a warm floor) in `art/samples/`; new shot `shot_art_direction_3.gd` (looked at: the hats separate the four players at 1× in all three; the eyes under the brim are barely visible). `test_svg_art.gd` allows I's new colours only in `i_warm/` and `hats_vivid/` and checks the hat/body split. The sandbox let me write only through the file tools, so the SVGs were typed out by hand. Pick comes back as owner question `art-direction-pick-3`.

- M2 part 27, round two: the owner answered #190 with "more options". Drew D (A's proportions in C's hooded robe), E (soft, no black outline) and F (big hat, beveled tiles) as rect SVGs in `art/samples/`; new shot `shot_art_direction_2.gd` (looked at: all four columns read; D's arm is a little stiff). `test_svg_art.gd` now expects four sample icons and checks E's against its dark-red outline. Nothing is recorded in `golden.json` or `STYLE.md` yet: the pick comes back as owner question `art-direction-pick-2`. Sessions here could not run Python, so the SVGs were written out by hand.
- M2 part 27: the art direction choice. Drew two new styles by hand as rect SVGs (A Chunky, C Grim: wizard, crypt floor, fire icon each) in `art/samples/`; B is the current placeholder. New shot `shot_art_direction.gd`; I looked at `art_direction_sheet.png`: the three read as different looks at 4x and 1x, and C's dark cloak is hard to see on the floor at 1x (noted in `art/samples/README.md`). Review fix: `test_svg_art.gd` now scans `art/samples/` too (rects only, whole numbers, palette, no overlaps, manifest) and checks the two sample icons for a closed outline; all six passed, so the edge-touching floor joints are allowed by the test as they are. The 1x row of the sheet now shows four overlapping wizards. The owner question is #190 (open, unanswered); nothing in the game changed.
- Closed-outline audit. New `test_every_icon_has_a_closed_outline` (with a self-test) in `test_svg_art.gd`. It found open outlines in storm (2 px), orbit (dots with no outline), chain (the middle link), homing (the arc had none), pierce (plate sides and the shaft at the canvas edge), split (branch dots had none) and timer (a missing row of fill); all fixed. Looked at the 1x sheet again: the icons read. `build.sh --quick --tests` and the screenshots pass.

- Neutral bolt, review fix: measured the cost of the wider draw buffer (`DRAW_STRIDE` 16, four batches) with `build.sh --quick --tests` (headless, so CPU only; the GPU upload itself is not measured). `update_draw` at the full cap: 0.47 ms at 1000 shots (2.8% of a 60 FPS frame), 1.46 ms at 3000 (8.8%); `spawn` 1.2 us per call. Stress (4 players, built spells): web scenario (100 enemies, 1000 shots) average 6.91 ms, p95 11.46 ms, max 13.38 ms; desktop scenario (200 enemies, 3000 shots) average 6.91 ms, p95 13.33 ms, max 16.44 ms; both inside the 16.7 ms budget, no errors. The GPU upload is 3000 x 16 floats = 192 KB per frame at the cap, small next to the budget; a browser number waits for the daily web timing step.
- Neutral bolt for element shots. `bolt.svg` is Bone with a Spark core; a new shader tints the Bone by the owner and the core by the element (`Projectiles.set_core`, set by the spell runtime from `CompiledSpell.tint`). Runes and orbit orbs have their own batches and art; the beam and nova ring are drawn by `feel` from the new event `form_shown`. Tests in `test_projectiles.gd`, `test_spells_cast.gd`, `test_events.gd` and `test_feel_forms.gd`; looked at `element_shots.png` from the new `shot_element_shots.gd`. `build.sh --quick --tests` passes.
- Element colours and icon recolour. Frost, void and homing icons recoloured with the new Ice and Void ramps (no player colours left in any of the 18 icons); frost and void tints set. `on_hit` and `on_expire` redrawn with different silhouettes (star burst vs ring) and the outline they were missing. Audit of the 18 icons, partial, by reading the rects (not pixel-level): all 18 use only palette colours (checked by `test_svg_art.gd`), and none uses a player colour. Outlines: 16 had one; `on_hit` and `on_expire` had none and now do. `timer` and the bolt/beam/chain icons were not pixel-traced for closed corners; a closed-outline check in `test_svg_art.gd` is a possible follow-up.

- M2 part 26: the art pass. New shot `shot_art_pass.gd` (18 icons, element tints against player colours, vfx sprites) looked at against STYLE.md. Findings: the frost, void and homing icons and the frost and void tints use player colours; the orange bolt multiplied by a colour goes olive or brown and shows no element. Both are queued in `docs/NEXT.md`; no art changed.

- M2 part 25: stress in the exports. `--stress` and `--projectile-timing` start the stress run and the projectile timings from the main menu in the Linux Test and Web Test exports (`projectile_timing_runner.gd` is now a node; `test_projectile_timing.gd` starts it from the command line). Spell limits hold on the headless numbers (WASM pending), none lowered. The runner prints `TIMING OK` for the existing web timing step in `build.sh` (not run yet); the `--stress` step is an owner question (#166). Main menu test extended.

- M2 part 20: bots build spells. `tests/bots/recipe_fuzzer.gd` (seeded random recipes and the slot-by-slot build calls), `Bot.build_random(seed)` (spell B, through `build_change_requested`, then a swap) and `Bot.open_builder()` (overlay, `move_down`, `cast`). The 4-bot test has bots 1-3 build with seeds 2026-2028 and bot 4 stay in its builder; it fails on a refused build or a closed builder. New `tests/bots/test_spell_fuzz.gd`: 300 seeded recipes compiled and cast in the combo arena, failing on error lines, broken limits and runaway shot counts (frame time only warns; 244 compile, slowest mean step under 1 ms, 0.8 ms measured). `build.sh --quick --tests` passes.

- M2 part 24: the stress scene. `tests/benchmark/stress_runner.gd` runs 4 bots with built spells against 100 enemies and 1,000 shots (web), then 200 and 3,000 (desktop) on the real game, printing `BENCH:` lines and `STRESS OK`; `stress.gd` starts it, `test_stress.gd` runs a short version in the build. Frame time past the budget warns, never fails. Headless numbers (game logic only, not web): full run p95 13.9 ms (web scenario) and 15.4 ms (desktop); the short build run (2 s measured) p95 16.2 and 16.8 ms, with the full 1,000 and 3,000 shots, 100 and 200 enemies, about 340 spell hits and 30-45 reactions per scenario. Decisions in `docs/DECISIONS.md`.

- M2 part 23: the first lore; Story opens. 18 component descriptions in `content/story/lore/components/`, `StoryValidator` (keys, types, id equals file name, 60-character one-line text, duplicates, a file for every component), registry `get_lore`/`validate_story`, `Spells.component_description` now returns the text so the builder shows it. Story README has the schema and example; Story is open for PRs. New `test_lore.gd`; builder tests adjusted. `build.sh --quick --tests` run.

- M2 part 22: story canon. New `docs/STORY.md` (tone, seven canon points, writing rules, what is still open), listed in `llms.txt`. Docs only; part 23 writes the first lore to fit it.

- M2 part 21: combos to 20+. Nine new rows in `content/spells/combos.json` (21 in all) so that every one of the 18 components is in at least two combos; `test_combos.gd` wants 20 and has a new test for the two-per-component rule. Two catalogue drafts did not work as written and were changed (see `docs/DECISIONS.md`): a held bolt re-hits the imp that fired it, and a rune is used up by its first hit so it never expires on a target. `build.sh --quick --tests` passes.

- M2 part 19: the build break. `BUILD_BREAK` (12 s) replaces `NEXT_WAVE_DELAY` in `flow`; the new event `build_break_started(seconds)` follows `room_cleared`, and the HUD shows a hammer (drawn in code) and "Build N" under the wave line, over the builders, counting down by itself (display only). Tests: `test_flow.gd` (the break is fixed; the wave starts on time for 1, 2 and 4 players while someone builds), `test_panels.gd` (the line), `test_events.gd`; `shot_quick.gd` has a `build_break` shot. `build.sh --quick --tests` and the screenshots pass.

- M2 part 18: the quick view and quick actions. The corner panel shows "Spell A" or "Spell B" (new `player` event `active_spell_changed`); `panels.gd` turns a `swap` press into `spell_swap_requested`; the builder folds into the quick view on `wave_started` (slot chain read only, "Drop component", "Close") and unfolds on `room_cleared`; "Drop component" in the overlay and the quick view lists the bag components that fit the empty element slot or the first free modifier slot of the active spell and sends `build_change_requested` (`hud/widgets/drop_choices.gd`). New `tests/hud/test_quick.gd` (swap, folding, drop, four players, layout at 640×360) and `shot_quick.gd`; `shot_builder.gd` ends the wave first. `build.sh --quick --tests` and the screenshots pass.

- M2 part 17: the builder, part 2. Each builder has an info panel in the free strip of its player's quarter: the complexity bar with "Complexity N/12", damage, shots, cooldown and mana of the spell and held level shown, a code-drawn mini-preview of the shot pattern, and one text line: "Refused: <reason>" after a refused pick, else the focused component's description (empty until part 23). New `Spells.builder_view` and `component_description` (the field-read test forbids the HUD reading a `CompiledSpell`); theme variations `BuilderLabel` and `ComplexityBar`. Eight new builder tests, a refused-pick screenshot, and the one- and four-player shots show the panels. `build.sh --quick --tests` and the screenshots pass.

- M2 part 16: the builder, part 1. `hud/builder/` is a per-player panel beside the corner panel: the slot chain (form, element, three modifiers, trigger, the held spell two levels down), spell tabs A and B, and the bag filtered to the selected slot. It is opened from the overlay's "Build" (replacing the stub), driven only by its owner's device through `core/ui_focus`, and sends `build_change_requested`. It draws from two new `player` events, `recipe_changed` and `bag_changed`, and from three new `Spells` readers (`component_name`, `component_icon`, `component_kind`), since the HUD may not read component fields. New `tests/hud/test_builder.gd` (28 tests, four builders open at once, the layout at 640×360), `shot_builder.gd` for one and four players; overlay and events tests updated. `build.sh --quick --tests` and the screenshots pass.

- M2 part 15: the Spells README and example; Spells opens. `content/spells/README.md` now describes the component classes (fields and ranges per kind, complexity and the budget of 12, reactions, the combo row rule), with the bolt, frost, split and on hit as the examples to copy. ROADMAP (it said part 11 and 21) and CONTRIBUTING say Spells is open. Docs only, no code.
- M2 part 14: the combo catalogue and test. `content/spells/combos.json` has the first 12 combos of the design's catalogue (burning bolt, shatter, big fire ring, storm lance, frost pulse rune, void ring, homing fan, storm chain, blast at the end, swift line, wide frost lane, fire fan orbit), each with its recipe, the plain words, the imps' positions and the checks. `tests/content/spells/combo_arena.gd` is the arena fixture (real registry, runtime, projectile manager and combat, with imps); `test_combos.gd` runs every row through it, also checks the rows (fields, unique ids, recipes compile within the budget, ids are real components), that a failing check is reported, that a plain fan misses what the homing fan reaches, and two players casting together. `build.sh --quick --tests` passes.
- M2 part 13: the three triggers. On hit, on expire and timer are `TriggerBase` resources in `content/spells/triggers/` (no scripts) with placeholder icons (three manifest lines) and `shot_triggers.gd` for a look at them. `test_triggers.gd` checks each against the validator and the registry, its compiled numbers and its real firing (from the hit point, at the end of life or a wall, every half second at most four times), a three-level spell, the refusal of a fourth level, the 32-fires cap and four players at once. `build.sh --quick --tests` and the screenshot ran.
- M2 part 12: the six modifiers. Split, pierce, homing, chain, bigger and faster are `ModifierBase` resources in `content/spells/modifiers/` (no scripts) with placeholder icons (six manifest lines) and `shot_modifiers.gd` for a look at them. `test_modifiers.gd` checks each against the validator and the registry, its compiled numbers, and its effect in a real cast (a fan of three, a bolt through three targets, a bolt curving to a target beside its aim, a chain of two jumps, a wider hit, an earlier arrival), also for four players at once. Owner answer on #140 (option 1, no change to `tools/check.sh`) recorded. Verified in the review round: the unit tests and the screenshot ran, the icons' `.import` files are committed, the pierce icon no longer overlaps its own rects, and a review's finding that faster was free led to a ×0.85 damage cost (split now ×0.5 damage, ×1.5 mana). The four-player test now checks each player's own target is hit by that player's shots.
- M2 part 11: player and flow on the new runtime. A wizard holds two recipes (A, B), swaps between them, and turns `build_change_requested` into a checked build (`Spells.compile` on a copy; `spell_changed` or `build_refused`); its bag is every component in the registry. Flow starts a run with `start_recipe_a`/`_b` instead of a spell id. `SpellBase`, the legacy fire bolt and Combat's `spell_cast` learning are removed; the field-read test is widened to the component classes (`test_spell_field_reads.gd`); new `test_player_build.gd`. Tests and the 4-bot smoke test pass.
- M2 part 10: the five forms. Bolt, beam, nova, rune and orbit are `FormBase` resources in `content/spells/forms/` with placeholder icons and four vfx sprites (manifest lines added). `test_forms.gd` casts each through the real runtime and manager, for one and four players. The M1 `SpellBase` fire bolt moved to `content/spells/legacy/fire_bolt/` (id `fire_bolt`, test renamed `test_fire_bolt_m1.gd`) so that `flow`, `player` and `combat` keep working until part 11 removes it. `build.sh --quick --tests` passes (`test_wave_balance.gd` failed once in a run and passed on the next with no change, a timing flake); looked at `forms_sheet.png` from the new `shot_forms.gd`. I could not run Python in this session, so the SVGs are hand-written rects and were checked by `test_svg_art.gd`.
- M2 part 9: the validator. `core/spells/validator.gd` checks every spell component (id and folder, name, icon and manifest, ranges, complexity, the fields each kind needs) and the reaction table (known status, existing element, real effect, numbers, no pair twice), and returns rule, file, field and fix. `Registry.validate_spells()` runs it, with a warning per problem at start in debug builds and the duplicate ids it saw while scanning. `test_validators.gd` has a broken fixture of each kind and of the table. Asked the owner whether `tools/check.sh` should call it.
- M2 part 8: reactions. `content/spells/reactions.tres` holds the six reactions (shatter, thaw, flare, kindle, stillness, rift) as twelve rows; `ReactionRow` gained `pull` and `consume_status`. `Combat` runs the four effect kinds (burst, consume, extend, spread) after a spell hit instead of the element's own status and sends `reaction_triggered`; `Feel` shows a flash, a burst, the reaction's name and plays `reaction_<id>`. Tests: `test_combat_reactions.gd` (25), `test_feel_reactions.gd` (7); `build.sh --quick --tests` passes. Review fixes: one reaction per enemy per 0.5 s, caps on extended statuses, Shatter doubles on any frozen target, feel caches names and limits repeat sounds, shakes and names. Looked at `build/screenshots/reaction_one.png` and `reaction_four_players.png` (new `shot_reactions.gd`): the name and flash read clearly at 1 and 4 players; the project has no pixel font, so the theme's default font stays. `tools/check.sh` lists only the session home directory's own files.
- M2 part 7: the four elements and statuses. Fire, frost, storm and void in `content/spells/elements/` (`.tres`, placeholder icons, tints from the palette). `Combat` now keeps burn, chill/freeze, shock and hex per enemy and reads `Spells.hit_profile` (M1's table stays for enemy shots); `status_applied` has its sender; the imp respects slow and freeze through `Combat.speed_factor`. Tests in `test_combat_statuses.gd`, `test_ai_statuses.gd`, `test_elements.gd`; `build.sh --quick --tests` passes. `tools/check.sh` lists only the session home directory's own files (as before).

## 2026-10-21

- M2 part 6: casting and triggers. `Spells.install`/`cast`/`step`/`hit_profile`: cooldowns per player and slot, fan, ring, orbit, still and beam shots, held spells on hit, expire and timer (fire cap 32 per player per step, `max_fires` per shot, source excluded for 0.1 s), chain on hit (at most 16 jumps per player per step, counted in `chains_dropped`; a chained beam pierces nothing; the nearest target is picked on the manager's hit circles), every shot counted so a rebuild mid-flight keeps old numbers and a full ring removes the revoked shots. `Projectiles` gained `remove_by_tag`, `shot_ended`, `event_slot`, `exclude` and readers. Tests in `test_spells_cast.gd` and `test_projectiles_ends.gd`; `build.sh --quick --tests` passes. Review fixes: a chained beam's jumps are queued and cast after the outer `ray()` returns (the manager nests only 4 deep, a chain can have 6 jumps); a beam whose `ray()` did nothing fires no on-expire spell; removed the unused `get_target_point`. `tools/check.sh` lists only the session home directory's own files (`.idea`, `.vscode`, `scripts`: unreadable and untracked), nothing in the change. `test_wave_balance` flaked once and was not run on main, so it is not confirmed as pre-existing (it is timing-dependent, see BACKLOG); it passed in the last full run.
- M2 part 5: the spell compiler and limits. `core/spells` (`Spells`, `SpellLimits`, `CompiledSpell`, `SpellTag`): recipes compile to final numbers with a description, refused with a reason or clamped at the complexity, shot, modifier and depth limits; tags carry player, slot, depth and an 8-generation ring so a rebuild mid-flight keeps old shots on their old numbers. Tests in `test_spells_compile.gd`; the field-read test also allows `core/spells`.
- M2 part 4 review fixes: orbit shots documented as piercing shots (test with 5 enemies under a ring), homing skips wizards and freed targets, a target on the beam origin no longer cancels `homing_aim`, `ray` length capped at 360 px, `set_homing(slot, 0)` returns true, and the timing test logs a straight-shot baseline next to homing. The web (WASM) cost of homing is unmeasured: check it in part 25.
- M2 part 4: projectile manager, part 2. Orbit shots (per-player anchors), homing (every 4th step, on the grid, inside the work budget), `homing_aim` and `ray()`; tests in `test_projectiles_motion.gd`; `build.sh --quick --tests` passes. Native timing at the web cap (1,000): a step of homing shots near the 100-enemy crowd 5.5 ms, of orbit shots through it 4.1 ms, a piercing beam through the crowd (23 hits) 0.08 ms; at the desktop cap (3,000) 7.0 ms and 6.1 ms.
- M2 part 3: projectile manager. `projectile_expired` (life end and walls), the `still` motion, `nearest_target` and `targets_in`; tests in `test_projectiles.gd`; `build.sh --quick --tests` passes and the timing test is as before.
- M2 part 2: events. `projectile_expired`, `reaction_triggered`, `spell_changed`, `build_refused` and `spell_swap_requested` in `core/events`; `build_change_requested` takes the `spell` path (the overlay stub sends `[0]`); the `swap` input action (Q, left shoulder, captured like `cast`); the events table and READMEs match; tests in `test_events.gd`, `test_input.gd` and `test_overlay.gd`. No sender for the new events yet (parts 3, 8, 11).
- M2 part 1: spell component base classes in `core/base/` (`SpellComponent`, `FormBase`, `ElementBase`, `ModifierBase`, `TriggerBase`, `ReactionTable`, `ReactionRow`) with ranges in code; test `tests/core/test_spell_components.gd` and a fixture.
- M2 started (owner, in a session): M1 closed on the go verdict at C1; `docs/milestones/M2-spell-system.md` written, reviewed by a fresh-context session against `docs/DESIGN.md` (one blocking finding: the wave must not wait for a builder) and revised; 28 parts queued in `docs/NEXT.md`; ROADMAP, M1 status, llms.txt, README and CONTRIBUTING updated. M1's open owner items carry into M2. No game code changed.

## 2026-10-21: Animated torches, 2.5D pillars, impact particles (owner `/claude` on #4)

- **Torches** (`content/rooms/crypt/decals/`): a looping 4-frame flame and a flickering additive glow, shared frames, each of the eight torches at its own speed and phase; no script. **Pillars:** a base under the characters, a top over them (`z_index` 5), a longer floor shadow; collision unchanged. **Particles:** new event `projectile_impact` from `core/projectiles`; `Feel` sprays hits along the shot (ember for an enemy, the wizard's colour for a wizard, bigger for more damage) and throws stone chips and a coloured spark where a shot ends on a wall or pillar. Within `PARTICLE_LIMIT` and the pools. Tests: `test_projectile_impacts.gd`, `test_feel_impacts.gd`, `test_arena_01_pillars.gd`, `test_arena_01_torches.gd`; shots in `tests/screenshots/shot_impacts.gd`. Details in `docs/DECISIONS.md`.

## 2026-10-21: Smaller enemy bullets (owner `/claude` on #4)

- The imp's shot radius is 5 → 3.5, so its sprite (drawn at 3x the radius) and its hit circle both shrink by 30% (30 px → 21 px quad, orb about 10 px). Players' bolts keep radius 4, and the enemy orb keeps its own spiky art and no tint, so the two stay distinct. Test in `test_ai.gd`.

## 2026-10-20: Foundation review (owner `/claude` on #5)

- New `docs/ARCHITECTURE.md`: layers, where each kind of change goes, the art contract. `Feel` now draws the textures its `FeelPreset` names; `Flow` runs the room, enemy, spell and wizard scene it is told (`*_to_play`, `wizard_scene`). New tests: `test_feel_art.gd`, `test_flow_content_choice.gd`, `tests/content/wizard/test_wizard_art.gd`. Weak spots left for their features: `docs/BACKLOG.md`, "Foundation". Details in `docs/DECISIONS.md`.

## 2026-10-20: Hitboxes on the body (owner `/claude` on #5)

- Bug: hit circles were centred on the feet while sprites are drawn 14 px higher, so shots seemed to pass through. `Projectiles.add_target` has a new `offset`; imp and wizards register their circle at (0, -12) and bigger (imp 11, wizard 8, bolt 5, imp shot 5). The imp's shot and telegraph start at its body. Regression tests in `test_projectiles.gd` and `test_combat.gd`. Details in `docs/DECISIONS.md`.

## 2026-10-20: Art direction pass and a test foundation (owner `/claude` on #102)

- **Art.** The ember imp is redrawn (horns, angry brows, glowing eyes, fangs, bat wings that flap between the idle frames; new windup and hurt poses on it). Its telegraph is a dashed line (`art/vfx/telegraph_dash.svg`) over a danger lane with an arrowhead at the end of the shot's reach (`Lane`, `Tip`, fitted by `ai.gd`). The crypt room has a lit-top wall tile for the top and bottom walls, real pillars, torches, doors at the entry and exit, rubble and skulls on the floor, wall and pillar shadows on the floor and a darker floor so figures stand out. New: `wall_top`, `pillar`, `torch`, `door`, `rubble`, `skull`. Looked at with `build.sh --quick --screenshots` (`art_sheet`, `juice_cast_and_hit`, `enemy_windup`).
- **Tests.** New base `tests/support/suite.gd`: one `test_*` method per behaviour, each independent, a failure names the method. New small tests on it: `tests/core/test_svg_art.gd` (every SVG: rects only, palette, whole numbers, no overlaps, in the manifest), `tests/content/enemies/test_ember_imp_art.gd`, `tests/gameplay/ai/test_ai_telegraph.gd` (17 tests, moved out of `test_ai.gd`) and the old `test_arena_01.gd` split into `test_arena_01_data.gd`, `_layout.gd` and `_art.gd`. Rules in `tests/README.md`.
- Not done: the other big test files still use the old shape (see `docs/BACKLOG.md`); the new art is placeholder and hand-drawn, so the owner may still find it plain.

## 2026-10-20: C1 verdict: iterate

- The owner answered on #97: iterate. `docs/NEXT.md` now queues a human playtest report of round 2 first, then the top items from it. Docs only; no code changed.

## 2026-10-19: Muzzle flash bug (#102)

- The muzzle flash was 138-207 px around a 32 px wizard. `muzzle_flash_size` is now 0.5 (29-43 px); the death puff is unchanged. New test `_test_muzzle_flash_stays_small` (48 px limit, `punchy` preset). Reasoning in `docs/DECISIONS.md`.

## 2026-10-19: C1 round 2 summary

- Wrote the summary comment for #97; the daily run posts it after this merges (a session cannot post or read comments). It covers the six tasks, an honest assessment, what stays untested (no human playtest of round 2, web, sound) and the verdict options. No code changed.

## 2026-10-19: Cleanup: invalid UIDs (C1 round 2, task 6)

- Re-applies #112, which #113 had reverted ("the daily build failed", no cause given; a session cannot read it); the full unit test run passes with it, including `test_uids`.
- Eight `.uid` files held a digit 9 (the backlog listed five; `gameplay/feel/feel.gd.uid`, `tests/gameplay/feel/test_feel.gd.uid` and `tests/hud/test_overlay.gd.uid` had it too). Each 9 became another valid character; no scene or resource referenced those UIDs.
- The new test also found a `z` in `gameplay/feel/feel.gd.uid` (fixed). `test_wave_balance` failed once in a full run and passed on the rerun (bot timing is noisy; unrelated).
- New test `tests/core/test_uids.gd`: scans every `.uid` file in `res://` (not `build/` or `addons/`) and fails on a bad prefix, a character outside a-y and 0-8, or a UID shared by two files; it also checks its own validator.

## 2026-10-18: Wave pacing (C1 round 2, task 5)

- `flow`: after `room_cleared`, `NEXT_WAVE_DELAY` (3 s) later the next wave stands in the same world with 2 more enemies (8, 10, 12 ... up to 24); downed wizards are revived and protected; the restart is 1.5 s and goes back to wave 1. New event `wave_started(wave)`; the HUD shows "Wave N" at the top middle.
- Tests: `test_flow.gd` (growth, same world, cap, downed wizards, restart to wave 1, no stray timer), `test_panels.gd` (wave line), `test_events.gd`. `ci/build/build.sh --quick --tests` passes, including the 4-bot test (clears wave 1 in 13.6 game seconds this run) and the wave balance test (wave 1 is unchanged; its `BALANCE:` lines are as noisy as before: bots never dodge). Screenshot `arena_four_wizards` shows the line.
- `tools/check.sh` reports only untracked files of the session's home directory (`.idea`, `.vscode`, `scripts`), none of them part of the change.

## 2026-10-18: Enemy readability (C1 round 2, task 4)

- Telegraph: the imp swaps to a `windup.svg` pose (glowing mouth and belly, sparks) and flips its two frames faster toward the shot (`frame = floor(progress² × 9) mod 2`), goes brighter for the last 20%, and the line is 3 to 6 px wide in Fire light (was 2 to 4, darker).
- Hurt: `hurt.svg` (eyes shut, mouth open) for 0.25 s after a hit on that imp; the windup is not cancelled.
- Enemy shots: `art/vfx/imp_fireball.svg`, a round ember orb with four spikes and a Spark core, in its own draw batch above the players' shots, untinted. Player shots stay the tinted comet. Looked at in `enemy_shot_beside_player_shot`: round and spiked against a comet, brighter centre.
- Art is hand-written SVG rects from the imp's idle frame, with manifest lines. `ci/build/build.sh --quick --tests` passes; the wave balance and 4-bot runs are real-time and vary between runs (one run had a wave-balance failure that did not repeat).

## 2026-10-18: Dodge and cast feel (C1 round 2, task 3)

- Input buffer: a dodge or cast press is remembered for `INPUT_BUFFER` = 0.15 s (about 9 frames at 60 FPS) and fires when it becomes possible; used once, dropped when the overlay is open, when downed, or when older than the buffer. A held `cast` works as before.
- Invulnerability window: sprite at 55% opacity plus a ring (player colour, dark outline) that closes over `INVULNERABLE_TIME`; shown for every kind of protection. Looked at in the shot `dodge_invulnerable`: the wall shows through the wizard and the ring reads at 640×360.
- Cast rate and mana against the bots (`test_wave_balance`, headless runner, bots never dodge): 1 player 21 casts in 14.2 s (lost), 2 players 67 casts in 26.7 s (lost), 3 players 91 in 29.4 s, 4 players 67 in 15.1 s. No value changed; see `docs/DECISIONS.md`. The 1 and 2 player runs are lost by bots that never dodge, as already noted in the backlog.
- Tests: buffered, too-early, used-once and overlay presses for dodge and cast; the look follows the window and clears when downed. `ci/build/build.sh --quick --tests` passes.

## 2026-10-18: Shots stop at walls (C1 round 2, task 2)

- `core/projectiles` keeps a grid of solid 8 px cells (`set_walls`, `add_wall_body`, `clear_walls`, `clip_to_walls`, counter `wall_hits`). Each step walks the cells the path crosses and ends the shot at the first solid one (piercing shots too; fast shots cannot skip a wall). The wizard clips the staff tip to the wall before it casts, so a wizard against a wall cannot fire through it. `flow` gives the manager the room's wall-layer static bodies after the room is in the tree.
- Timing (`test_projectile_timing`, headless runner, full cap, no targets): 3,000 shots 0.9 ms a step without walls, 3.0 to 4.2 ms with the arena's 10 wall rectangles (refilled each step, so many shots start inside a wall and die); 1,000 shots 0.3 ms and 1.0 to 1.4 ms. The hit tests and their work budget are unchanged (a wall check is not charged to it). A one-cell shortcut for the usual short step cut the 3,000 case from 4.2 to 3.0 ms.
- Review round: the step is now cut at the wall and the hit test runs on the part before it (a fast shot keeps a hit in front of a wall); the wall walk is capped at 64 cells; `spawn` refuses a shot born inside a wall (no slot, no eviction); `test_flow.gd` checks that `start_run` and a restart give the arena's walls (border, pillar, two players' shots). Timing with every shot flying a long path without dying (1,500 px/s, none ending in the first cell, headless): 1,000 shots 1.6 ms a step, 3,000 shots 4.7 ms (28% of a 60 FPS frame; the web build is not measured, so its 1,000 cap is the number to watch). Refusing the cast at a wall was tried and made the 4-bot smoke fail every run, so the cast stays.
- Tests: wall stop, piercing and 100 px steps, all directions, edges, `clip_to_walls`, `add_wall_body` (`test_projectiles.gd`); a wizard against a wall (`test_player_health_cast.gd`).
- The 4-bot smoke started to fail (player 3 down): the bots held fire into pillars. The bots now check the line of sight with a physics ray and strafe along a wall in the way. It passed three runs in a row afterwards, but the `BALANCE:` lines for 1 and 2 players got worse (bots still never dodge); noted in `docs/BACKLOG.md`.

## 2026-10-18: Revive (C1 round 2, task 1)

- `coop` now revives: a standing wizard within 48 px of a downed one for 2 s brings it back (50 health) and it is protected for 1.5 s. The nearest standing wizard is the reviver; progress drains at twice the fill rate when nobody is near; each downed wizard has its own progress, any slots 0-3. New event `revive_progress(player, progress)` drives a ring (a clockwise-sweeping arc with a cross) over the downed wizard's hat.
- Tests: two players, each of four players in turn, three down at once, a leaving reviver or downed player (`test_coop.gd`); the new signal in `test_events.gd`. Shot `revive_ring_half`. Joiner protection has to be stepped away in tests before a joiner can be downed. The "Revive by standing next to a downed wizard" backlog line is gone. Reasoning and numbers: `docs/DECISIONS.md`.

## 2026-10-18: C1 juice leftovers, and six more M1 tasks queued (owner `/claude` on #102)

- All four leftovers are done. (1) New event `wizard_cast(player, wizard)` (sender `player`, right after `spell_cast`); `Feel` squashes the caster's `Sprite` thin and tall for 0.1 s (15%, no white flash; a hit takes it over, a cast never replaces a hit). (2) The muzzle flash is turned along the aim, stretched 1.8× and tinted in the player's light colour. (3) The dead enemy's `Sprite` is copied into a pooled sprite (8 slots) that is white, widens, collapses and fades in 0.25 s while the enemy itself is freed at once. (4) The HUD has a red vignette (`hud/panels/vignette/`, behind the panels) that glows when a wizard's health falls, strongest toward that wizard's corner, gone in about 0.4 s.
- New preset fields: `cast_squash`, `cast_squash_seconds`, `death_anim_seconds`. Nothing in `punchy.tres` changed: the numbers could not be played here (no person at the keyboard), so no value was tuned.
- Review round: looked at the effects in new crops (`juice_muzzle_flash_a/b`, `juice_death_animation`, `juice_cast_and_hit`) and tuned: muzzle flash 0.1 s at 2.4× (was 0.07 s, 1×), cast squash 20% for 0.12 s, death puff 1.6× for 0.14 s and drawn under the death animation (which is now on top). Vignette: stronger, wider corner bias, clear middle, scaled by hit size and player count, with an `enabled` setting. The death copy starts at the rest scale (not the squashed one) and keeps centring and rotation; no cast squash during a dodge; a test that the muzzle colours equal the reticle colours.
- Tests: `test_feel.gd` (aimed and tinted flash, cast squash, death animation and its limit), `test_panels.gd` (vignette on a health drop only, limit, fade, clear), `test_events.gd` (the new signal). New screenshot `juice_cast_and_hit` in `shot_m1.gd`.
- `docs/NEXT.md` now holds the six tasks of the owner's second round: revive, shots stop at walls, dodge and cast feel, enemy readability, wave pacing, cleanup. Not started yet: one session and one PR each.

## 2026-10-18: Juice pass on the core loop (owner `/claude` on #102)

- `gameplay/feel` (all inside `Feel`, driven by events, never touching damage): a white hit flash (a tiny `hit_flash.gdshader` set as the sprite's material for 0.08 s) and a squash on the `Sprite` child of whatever `damage_dealt` names (enemies and wizards; at most 16 at once, tracked by instance id so a freed enemy is safe); a death puff (the hit spark, bigger and fading, 4 slots); a muzzle flash per player at the `spell_cast` origin; a camera kick against the aim (1.5 px per cast, capped at 4 px, off with `shake_enabled` off).
- `punchy.tres`: hit-stop 0.05 s (was 0.04), death 0.09 s (0.07), shake 0.2 / 0.38 / 0.6, up to 7 px, particles faster and a bigger death burst. New preset fields are in `feel_preset.gd`.
- Checked: `ci/build/build.sh --quick --tests` passes with new tests for the flash, the kick and the puffs; looked at the arena shot. The 0.07 s muzzle flash is too short to appear in a still.
- Left for later: see `docs/NEXT.md` (caster squash, aimed muzzle flash, enemy death animation).

## 2026-10-18: Placeholder art iteration (owner `/claude` on #102)

- Redrew the placeholders as SVG rects, same palette and rules: floor (Stone base with flagstone joints, light chips and cracks, nothing on the edge pixels; it is lighter than before, so figures stand out more), wall (four brick courses, each lit on top with a shadow joint), fire bolt (a comet with a round head, tapering tail and Spark core), hit spark (added four diagonal flecks), ember imp (2-frame idle strip, the second bobs 1 px, played by an `AnimationPlayer` in the scene), wizard (no staff in the sprite any more).
- Wizard animation: `wizard_p1..p4_idle.svg` (2 frames), `_walk.svg` (4) and `_dash.svg` (3), 32 px per frame; `player.gd` picks the strip from speed and dodge (`_update_animation`), `walk_textures`, `dash_textures` and `staff_texture` are set in `wizard.tscn`. The dash look (stretch, lean, ghosts) stays but is milder (1.2 x 0.85, lean 0.1) because the dash frames lean already; ghosts draw the current frame.
- The staff is now art: `staff.svg` (Wood pole, fist, Spark gem) is drawn from the hand along the aim, flipped when aiming left so the light stays on top, with a player-colour gem at the tip. The muzzle position did not change.
- Checked: `ci/build/build.sh --quick --tests` passes (new `test_player_animation.gd`), and a new shot `art_sheet` (`tests/screenshots/shot_art.gd`) shows every frame at 2x; looked at it, and at the arena shots.
- Not done: the cast, hurt, downed and death strips; enemy walk or attack frames; a walk and dash for the imp; animated bolt and spark (the projectile manager draws one still). Real art and the art direction stay with M2. The whole session could not run scripts, so the SVGs were written by hand (no generator) and the other three player colours are recolours of player 1 by text replacement.

## 2026-10-18: Playtest fixes (owner `/claude` on #102 and #97)

- Shots were invisible (player and enemy). Two causes, both in `core/projectiles`: the autoload is drawn before the room, so the floor covered the batch (now `DRAW_Z` 50), and the MultiMesh's culling box did not follow the shots, so any shot away from the origin was never drawn (now `custom_aabb` covers the bounds). Found by a screenshot probe: even a hand-set instance rendered only with the box set. Shots are also drawn 3x their hit circle (`DRAW_SCALE`) and tinted only 45% (`TINT_STRENGTH`), because a full multiply turned the orange bolt of a blue wizard nearly black.
- Shots now start at the staff tip (`muzzle_position()`: 10 px above the feet plus 14 px along the aim), and a small staff with a glowing tip in the player colour is drawn. `spell_cast` carries the same origin.
- Dash look: the sprite stretches along the dash axis (1.3 x 0.8, swapped for a mostly vertical dash) and leans; three fading ghosts in the player colour sit at the wizard's last three positions (a fixed 3-value buffer, one tick per 0.04 s) with the same stretch and lean; no art files. The staff and reticle moved to a child node above the sprite (the sprite had hidden most of the staff).
- Tests: `test_player_aim.gd` (muzzle, dash look and reset), `test_projectiles.gd` (z_index and culling box). New shot `shots_and_dash` in `tests/screenshots/shot_m1.gd`; looked at it: three shots in flight, the staffs, and the dash ghosts of player 4.
- Not done: controller and multi-player aim not yet felt by the owner; aim assist is unwanted (a "homing" modifier comes with spell building); enemy shots still start at the enemy's centre; real art and animation wait for M2.

## 2026-10-17

- Owner `/claude` on the C1 issue (#97): iterate on aiming and graphics. Aim is now separate from walking (twin-stick): right stick, or the mouse for the keyboard player, else the walk direction; the sprite turns toward the aim, and a player-colour reticle plus a ground shadow are drawn. New `get_aim`, `send_virtual_aim`, `is_mouse_aiming` in `core/input`; tests `tests/gameplay/player/test_player_aim.gd` and two in `tests/core/test_input.gd`. `ci/build/build.sh --quick --tests` and `--screenshots` pass; looked at `arena_four_wizards` (each wizard aiming a different way). Not done: aim assist, a feel check by a person, new art files.

- M1 part 25: stabilisation and checkpoint C1. `ci/build/build.sh --quick --tests` passes; no open bug in M1's scope, so no bug fix. Added `tests/bots/test_wave_balance.gd` (fighter bots, 1 to 4 players, `BALANCE:` lines; it fails only if a run neither clears nor is lost; who is downed is reported, not gated, because the bots play in real time). One run on a GitHub runner, headless, bots that never dodge:
  - 1 player: cleared in 28.1 game seconds, 80 of 100 health lost, 39 casts.
  - 2 players: 20.5 s, 70 health lost in total, 53 casts.
  - 3 players: 14.4 s, 80 lost, 51 casts.
  - 4 players: 11.3 s, 80 lost (20 each), 58 casts. The 4-bot test with an idler clears in 6.3 s.
  - Reading: the wave sized for four is a close fight alone for a bot that never dodges, and soft for four. Enemy count and health by player count belong to `difficulty` (M3), so no value was changed; a person who dodges does better than the bot. There are no playtest answers yet.
  - The C1 issue is asked as an owner question, with the open owner items first. Done-when items 1 and 4 stay open.
- M1 part 24, starter kit sources: `art/kit/` with the palette as `spellmerge.gpl.txt` (a `.gpl` is not an allowed type, so the zip must rename it) and `palette.hex.txt`, a 32×32 grid template and an animation strip template as SVG, `golden.json` (six existing placeholder files as golden candidates, no duplicate art), the one-page `checklist.md` and a README; a `.gdignore` keeps Godot out. `docs/STYLE.md` got "Golden examples" and "The starter kit". What `ci/smbot/site.py` must add for the Style Guide page and the zip is in `docs/BACKLOG.md`, asked as an `owner` issue. Not checked: how the templates look in an editor (nothing here renders SVG).
- M1 part 23, web 4-bot run, game side only: `Web Test` export preset (no `tests/` exclusion), the main menu reads `--four-bot` from both argument lists, `test_export_presets.gd` covers both Test presets. The `websmoke.py` and `build.sh` change is owner-only: written under "Needs an owner decision" in `docs/BACKLOG.md` and opened as an `owner` issue. Blocked until the owner makes it; nothing was exported or run in Chrome here.
- Web size, load time and WASM projectile timing: not done. A development session can run only `build.sh --quick`, which neither exports the Web preset nor starts Chrome, and `build/godot/templates` is empty. The daily build already exports Web, logs the size against 40 MB and smoke-tests it in Chrome; missing are a load-time line and `test_projectile_timing` in WASM, both in owner-only `ci/` (exact step in `docs/BACKLOG.md`, asked as an owner question). Moved to Blocked in `docs/NEXT.md`; `DEFAULT_CAP_WEB` (1,000) is unchanged and unchecked in WASM.
- M1 part 22 follow-up: bounded the projectile hit test. `ProjectileManager.step` now has a hit-work budget (`WORK_PER_STEP` = 8,000 units per step, after a first try at 16,000 left 81-93% of the 8 ms target; each target examined costs 1, each hit `HIT_WORK` = 40). When it is spent, the rest of the shots move but are not tested; the next step starts at the first untested slot, so nobody is starved. Same hostile benchmark, GitHub runner, native, headless (before; budget 40,000 as a calibration run; after):
  - 1,000 shots: step with fresh hits 108 ms, 16 ms, **2.8 ms** (84 hits a step; 6.5 ms at 16,000); steady state 54, 15, **2.7 ms**.
  - 3,000 shots: 333 ms, 17 ms, **3.1 ms** (7.4 ms at 16,000); steady state 166, 17, **3.3 ms**. Plain movement is 0.6 ms of that at 3,000.
  - Both are under the 8 ms target, with room for WASM only up to about 2.5x. The WASM check (2-4x slower) is the web task in the queue; if it is over 8 ms there, lower `WORK_PER_STEP` first, then `DEFAULT_CAP_WEB`.
  - The benchmark's `_hit_test` line still reads about 36 us a call: it calls `_hit_test` directly, outside the budget.
- M1 part 22: performance probe and budgets. Added `tests/benchmark/`: `probe.gd` (the 4-bot runner adds it; it prints `BENCH:` lines for frame time, peak nodes, projectiles, memory and live hit particles against `Feel.PARTICLE_LIMIT`), `test_projectile_timing.gd` (times the manager at both caps with four players) and `test_probe.gd`. Nothing gates on them. Numbers are from `build.sh --quick --tests` on a GitHub runner, headless and native (not WASM); they vary run to run, so read them as orders of magnitude:
  - 4-bot run: 940 frames, 6.9 ms average, 7.4 ms p95, 7.8 ms max (logic only; time-scaled ×2); peak 189 nodes, 10 projectiles, 30.7 MiB static memory (budget 512 web / 1,536 desktop), 40 of 48 hit particles.
  - `Projectiles.spawn` at a full cap: about 0.9 µs a call (0.9 ms for 1,000 spawns, 2.8 ms for 3,000). Fine.
  - `update_draw` with a full cap: 0.29 ms at 1,000, 0.88 ms at 3,000 (2% and 5% of a 16.7 ms frame). The "upload only the first `drawn` instances" change is not needed: `multimesh.buffer` is already one bulk write and `visible_instance_count` is set to `drawn`.
  - `step` with a full cap and no targets: 0.12 ms (1,000), 0.37 ms (3,000).
  - Hit test, hostile scene (review fix: an earlier version had near-still shots spread over the room and timed the same state repeatedly, so it only measured the remembered-target skip and understated the cost). Now: 100 enemies packed 9 px apart in about four cells, 4 wizards, friendly fire on, every shot piercing, speed 200–400 px/s, all starting inside the crowd, and the shots are refilled before each timed repeat so every call does fresh hits and sends `projectile_hit`. Fresh `_hit_test`: about 16.7 µs a call. A full `step` with fresh hits: 50 ms at 1,000 shots (3,000 hits) and 152 ms at 3,000 (9,000 hits), about 3 and 9 frames. Steady state (the same shots stepped again, targets remembered, still inside the crowd): 25 ms and 75 ms. This is an extreme scene (real play peaks near 10 shots), but it shows the caps are not safe in a dense fight; the cost is hits, up to `HIT_MEMORY` per shot per step, each with a signal. Queued in `docs/NEXT.md` (bound the work, then set the caps).
  - Web size and load time: not measurable in this session. No Web export template is installed (`build/godot/templates` is empty) and Godot runs only through `build.sh`. The project's own files (without tests, docs and ci) are about 1.1 MB, far inside the 40 MB budget; the engine `.wasm` will dominate. The size, load time and WASM timing are a queued task in `docs/NEXT.md` for the daily build.
  - Review fixes: probe created in `_ready` (no leak), `record()` and an injectable `max_samples` so tests cover average, max, p95 and the overflow, a formatting slip restored.

- M1 part 18 follow-up: HUD screenshots. Added the shots `hud_four_overlays`, `hud_player_four_down` and `coop_camera_zoom_half` to `shot_m1.gd` and looked at them (`build.sh --quick --screenshots` passes). Text is legible at 12/14 px over the 0.4-alpha panels; overlays do not overlap their panels; panels cover a few enemies, and in the staged zoom 0.5 shot all four corner wizards, which goes beyond the owner's "now and then" (asked to the owner). The review's state check showed the first zoom shot was not zoomed out (the room's camera limits hold zoom at 1), so it now widens the limits and the script requires zoom 0.5. The script now fails if an overlay, the DOWN state or the zoom-out did not happen. No HUD change.

- M1 part 21 follow-up (#80): the exported binary hangs on `--script`, so the 4-bot test also starts from the main scene now. Checks moved to `tests/smoke/four_bot_runner.gd` (a node); `four_bot_smoke.gd` adds it to the root; the main menu adds it when `--four-bot` is a user argument and the file exists. `build.sh --quick --tests` passes (`SMOKE OK`, 7.2 game seconds). Not run: the export with `-- --four-bot`. Review follow-up: the hook is a tested function (`tests/hud/test_main_menu.gd`: one runner, none without the argument, the warning path, no second runner), and the runner restores `time_scale` and its logger in `_exit_tree` and prints `SMOKE: room_entered`. The task stays open: the owner is asked to run the export once with `-- --four-bot` before the `build.sh` step is requested.

- M1 part 21: the 4-bot test in the Linux export. Running it needs a new step in `ci/build/build.sh` (owner-only); it is asked as an `owner-change` owner question with the exact lines (not written in BACKLOG, per the owner inbox decision), and the step requires the `SMOKE OK` line so an ignored `--script` fails it. Added the `Linux Test` preset to `export_presets.cfg` (tests included, not shipped) and `tests/smoke/test_export_presets.gd`, which keeps it a copy of `Linux`. Not run: the export, and `--script` on the exported binary.

- M1 part 20: bots and the 4-bot smoke test. `tests/bots/bot.gd` plays through virtual devices and `send_virtual` (fighter: walk at the nearest enemy, hold `cast`; idler: tap `overlay`); `tests/smoke/four_bot_smoke.gd` runs four bots through the room with bot 4 idling in its overlay and fails without `room_cleared`, with a downed player 1–3, a closed overlay 4, or any logged error (a `Logger` sees `push_error`, `ERROR:` lines and Flow's "the restart failed" warning). `test_four_bot_smoke.gd` and `test_bot.gd` run under `build.sh --quick --tests`, which passes: the room clears in about 7 game seconds at time scale 2. The logger lives in `tests/smoke/error_log.gd` with a unit test (`test_error_log.gd`, fed by hand: a real `push_error` would print an `ERROR:` line and fail the build). Review follow-up: the smoke test also fails on zero `spell_cast`, polls the overlay every frame, and removes its logger; `test_bot.gd` checks the names the bot calls. 3 of 3 runs passed, each clearing in 6.9 game seconds (headless runs are frame-deterministic). Not checked: that the engine really delivers a real `push_error` to the logger.

- M1 part 19: the overlay. `hud/panels/overlay/` (scene and script, one per player, nodes `Root/Overlay1-4` in `panels.tscn`); `panels.gd` toggles an overlay on its owner's `overlay` press (press counts from `core/input`) and the overlay works through `UIFocus` only. Resume and a stub "Build slot 1" that sends `build_change_requested`. Test `tests/hud/test_overlay.gd` (owner-only control, no pause, with one overlay open the other three players still move, tap in one frame, device leaves). HUD README updated. The weekly "Playtest of the week" issues can start. `ci/build/build.sh --quick --tests` passes, including `test_overlay`; it first found three bugs, all fixed: the overlay was opened in `UIFocus` before it was visible (so nothing could take focus), and the test preloaded the `Hud` scene (cyclic load) and did not wait a frame or call `UIFocus._ready()`. Not seen: the on-screen layout.

- HUD legibility (part 18 follow-up): still no screenshot (sessions have no display). Text legibility is unverified (no contrast computed). Translucency added because the corner panels were opaque and hid a corner (at Coop zoom 0.5 a panel covers 224×110 world px), so their backgrounds are now 60% opaque; font sizes (12/14 px) kept and asserted in `tests/hud/test_panels.gd`. `ci/build/build.sh --quick --tests` passes. The look is still unseen; the real screenshot stays in `docs/BACKLOG.md`.
- HUD verification (part 18 follow-up): `ci/build/build.sh --quick --tests` passes. Visual check not done: no screenshot (headless has no renderer), so the legibility of the 12/14 px text and whether the corner panels hide play stay open. The task stays in `docs/NEXT.md` as "HUD screenshot and legibility check".
- All unit tests pass: `ci/build/build.sh --quick --tests` ran 19 scripts, all `TEST OK`, no `ERROR:` lines. Test fixes: wait a frame before using the tree (the cause of most failures), the `test_events` signal list, typed-array comparisons, signal handlers with the wrong number of arguments, a lane distance beyond the projectile bounds, the coop expectations (mid-run joiners spawn on the farthest spawn and are protected), a leaked audio playback, a preloaded autoload scene. Real bugs fixed: pool with freed objects, registry sort order of StringNames, AI not looking again at once when its target is freed, feel hit-stop frozen by a stream of hits, absolute `get_node` outside the tree in `player.gd` and `combat.gd`. The camera tests pass; the `.uid` files load. The headless screenshot of `arena_01` with four wizards is not possible (`--headless` has no renderer): see `docs/BACKLOG.md`.
- M1 part 18: HUD theme and player panels. `hud/theme/spellmerge_theme.tres` (project theme), `hud/panels/player_panel/` (panel scene and script), `hud/panels/panels.tscn` + `panels.gd` (autoload `Hud`, four corners). New event `player_stats_changed` (sender `player`; READMEs and the events test updated). Tests `tests/hud/test_panels.gd`, `tests/gameplay/player/test_player_stats.gd`. `build.sh --quick` passes (it loads the `Hud` autoload); the two test scripts have not run, since direct Godot runs need approval. The pixel layout at 640×360 has not been seen in a screenshot.

- Co-op verification (part 17 follow-up), blocked after three attempts. `ci/build/build.sh --quick` (pinned Godot 4.7.2 in `build/godot/`) was reported to pass with the `Coop` autoload and the hand-written `.uid` files, but that session kept no log file or CI run, so this is its word, not a checked record. Every direct run of `build/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/gameplay/coop/test_coop.gd` (plain, without `timeout` or a pipe, and inside a compound command) was refused with "This command requires approval". Nothing in the code changed. Still unverified: `test_coop.gd`, the camera tests in it, the `.uid` files and the four-wizard `arena_01` screenshot. The task is now under "Blocked" in `docs/NEXT.md` with an owner item in `docs/BACKLOG.md`, so the HUD task (part 18) can start.

- M1 part 17: co-op. `gameplay/coop/coop.gd` (autoload `Coop`, in `project.godot`): `device_joined`/`device_left` become `player_joined`/`player_left`; `flow` adds or removes the wizard mid-run; friendly fire option (default off) via `Projectiles.friendly_fire` and a target `owner` in `core/projectiles` so a wizard is never hit by its own shot; the shared camera eases to the middle of all wizards and zooms out to fit (flow gives the camera room limits). Test `tests/gameplay/coop/test_coop.gd` (all 64 join orders and leave orders of 1-4 players, camera, friendly fire); coop, flow, core and gameplay READMEs. Revive left in the backlog. Review round 1: zoom floor and centre clamp agree with the room limits, zoom guard while easing, mid-run joiners get a free spawn and 2 s of protection, camera found in Flow's world first, projectile hit test hoisted. No Godot binary: the test and `build.sh --quick` have not run, `.uid` files hand-written.

- M1 part 16: feel. `gameplay/feel/feel.gd` (autoload `Feel`, in `project.godot`): hit-stop (same for every player, longest wins), screen shake with the `shake_enabled` setting (in memory; saving waits for `core/save`), pooled hit particles under `PARTICLE_LIMIT`, a hit sound by id (silent on `null`), all from `damage_dealt`, `enemy_died` and `player_downed`; sets `Projectiles.texture` to the fire bolt art; `presets/feel_preset.gd` + `punchy.tres`; test `tests/gameplay/feel/test_feel.gd` (limit with four players, feel never changes damage); feel README. No Godot binary: the test and `build.sh --quick` have not run, `.uid` files hand-written. Review fixes: bursts live under `Feel` (top level) so freeing the world cannot kill the pool; a 0.15 s rest after hit-stop; a kill upgrades its hit burst and can take a full pool's oldest slot; real time from the clock, `time_scale` reset on exit; camera re-read when a shake starts.

- M1 part 15: arena glue. `gameplay/flow/flow.gd` (autoload `Flow`, in `project.godot`): `play_requested` loads the room, wizards for every joined player and the fixed wave of 8 imps, sends `room_entered` and `room_cleared`, restarts 2 s after the last wizard is down (bolt cooldowns reset); Play button in the main menu that only sends the event; test `tests/gameplay/flow/test_flow.gd`; flow and HUD READMEs. First internal playable build. No Godot binary: the test and `build.sh --quick` have not run.

- M1 part 14: the room. `content/rooms/crypt/arena_01.tscn` + `.tres` on `RoomBase` (space for four, four player spawns, six enemy spawns, entry and exit doors, six pillars for cover); test `tests/content/rooms/test_arena_01.gd`; rooms README example filled in. No Godot binary: scene and test not opened or run, `.uid` hand-written. Review fixes: the test also checks sprites against collision shapes, the floor, doors and spawn reachability (flood fill); still to be run in Godot before part 15.
- M1 part 13, revision 2 (review of PR #53): `test_bolt.gd.uid` had a 9 (invalid in Godot's UID alphabet); now `uid://b3v7h2nq8xk4m`. The single `_profiled_id` coupling is kept, as the review allowed.
- M1 part 13: the fire bolt. `content/spells/forms/bolt/bolt.tres` + `bolt.gd` (extends `SpellBase`, fires through `core/projectiles`; `Combat` reads its hit profile on `spell_cast`, the bolt never calls it; `_fire()` returns `bool`, so a failed shot costs no mana); test `tests/content/spells/test_bolt.gd` (kills the imp, four players, a wizard casting, and a scan that no script outside `content/spells/` and `core/base/` reads a spell field); spells README example filled in. No Godot binary: the test has not run and the `.uid` files are hand-written.
- M1 part 12, revision 3 (review of PR #52): the attack tag now comes from the enemy id and `attack_damage`, so two instances with different damage do not overwrite each other's profile; on `player_downed` only enemies chasing that player retarget at once (no one-frame spike); the telegraph starts at 2 px and alpha 0.5 (placeholders, to check in the part 25 playtest); an enemy leaving the tree unregisters from `Combat`; DECISIONS parts 11 and 12 moved to the top (newest first). Godot is not available in this session, so `test_ai.gd` and `test_combat.gd` still have not run; the "Run the unit tests in CI" item in `docs/BACKLOG.md` already asks the owner for a runner step.
- M1 part 12, revision 2 (review of PR #52): the invalid UID `uid://d2k7r4w9xn5pm` (digit 9 is not in Godot's alphabet) is now `uid://d2k7r4w8xn5pm`. A downed wizard is no longer a projectile target: `Combat` removes it on `player_downed`, re-adds it on `player_revived`, and does not add a downed wizard on `register_player` (so it cannot shield standing teammates); regression test in `test_combat.gd`. `ci/build/build.sh --quick` now passes (import and smoke OK). The session's shell would not let me start Godot directly, so the AI and combat test scripts still have not run; run them by hand.
- M1 part 12: the enemy and its AI. `gameplay/ai/ai.gd` (chase the nearest standing player, then a telegraphed shot: windup with locked aim, flash and line, shot, recover) and the enemy `content/enemies/ember_imp/` (`ember_imp.tres` on `EnemyBase`, `ember_imp.tscn` with the part 4 sprite). `player.gd` joins the `players` group; `Combat.register_player` now also makes the wizard a projectile target (enemy shots could not hit wizards before). Test `tests/gameplay/ai/test_ai.gd` (chase, nearest of four, downed skipped, telegraph before the shot, dodge by stepping aside); combat test extended. READMEs for ai, enemies and combat updated. No Godot binary: the tests and `build.sh --quick` have not run, `.uid` files hand-written.

- M1 part 11: combat. `gameplay/combat/combat.gd` (autoload `Combat`): damage pipeline, hit profiles by tag, hurt and contact hit boxes, knockback, `damage_dealt` and `enemy_died`; test with 1-4 players; README example path. No Godot binary: the test and `build.sh --quick` have not run, `.uid` files hand-written.
- M1 part 10, revision (review of PR #50): new `tests/core/test_spell_base.gd` (REFUSED, per-player cooldowns, tick clamp, `reset_cooldowns`); player tests for the in-tree silent sound and for frozen mana and cooldowns while downed; the player compares with `SpellBase.REFUSED` and warns when the `Events` autoload is missing; DECISIONS notes the frozen cooldowns and no invulnerability after a revive; core README sentence fixed. Still no Godot binary: the tests have not run.
- M1 part 10: player health, mana, downed, revive and cast. `SpellBase.cast/tick/spell_id/_fire` added; `player.gd` calls only those; events `spell_cast`, `player_downed`, `player_revived`; cast sound by id, silent on `null`. Test with two and four players. No Godot binary: the test and `build.sh --quick` have not run, and the `.uid` files are hand-written.
- M1 part 4: placeholder art. Nine hand-written SVGs (crypt floor and wall, wizard idle in the four player colours, ember imp, fire bolt, hit spark) with `.import` files and manifest entries (`origin: ai`, tier `placeholder`); `wizard.tscn` + `player.gd` show the sprite for `index`; test extended. "Audio needs" (`cast`, `hit`, `enemy_death`) added to the backlog. The session could not run scripts or Godot, so the SVGs were written rect by rect and not rendered, and the `.import` files and uids are hand-written: the first CI import is the real check, and a look at a screenshot is still owed.

- M1 part 9, revision (review of PR #48): an overlay opening now ends a dash in progress (test added); a missing `PlayerInput` autoload gives a `push_warning`; the physics layer plan is in the player README and DECISIONS; DECISIONS says why part 9 ran before part 4, and part 4's done-when asks for a sprite per player index. Still no Godot binary: the test and `build.sh --quick` have not run.
- M1 part 9: built `gameplay/player/player.gd` (move, dodge, brief invulnerability, cooldown; `step(delta)` for fixed-delta tests) and `content/wizard/base/wizard.tscn`; test `tests/gameplay/player/test_player_move.gd` with 1, 2 and 4 players through virtual devices. READMEs: `.tscn` allowed for the wizard, `gameplay/` script-only, real example paths. No Godot binary in the session, so the test has not run and the `.uid` files are hand-written. Part 4's sprite was not there yet; the scene's `Sprite` is empty and part 4 is told to fill it.
- M1 part 8: built `core/registry/registry.gd` (autoload `Registry`, registered in `project.godot`): folder scan, lookup by folder and id, `demo_only`, `get_sound(id)` giving `null` when missing. Test in `tests/core/test_registry.gd` with a fixture folder, including an unknown sound id. The session had no Godot binary, so the test and `build.sh --quick` have not run and the `.uid` files were written by hand. Core README updated.
- M1 part 7, second revision (review of PR #46): `clear()` no longer zeroes `drawn`, so the next `update_draw()` really empties the multimesh (before, old shots stayed drawn, frozen); a test reads `visible_instance_count` after `clear()`. Renamed `position` and `owner` (shadowed `Node2D.position` and `Node.owner`) to `origin` and `owner_index`, and the test's `round` to `round_index`. `build.sh --quick` passes; I could not run `tests/core` by hand here (the shell asked for approval), so they have not run.

- M1 part 7 revision (review of PR #46): hit search now follows the path and the largest target radius (big targets and very fast shots are found); the nearest target along the path is hit first, with the contact point reported; a piercing shot remembers 3 targets; dropping at the cap is O(1) (per-owner lists); default cap is 1,000 web / 3,000 desktop; `update_draw` writes one buffer and interpolates; README states what pools are for. New tests for each; the brute-force test tolerates float32 borderline cases. Godot is still not run in this session (see below), and CI still only runs `tests/smoke`; run both `tests/core` tests by hand.
- M1 part 7: built `core/pools/pool.gd` and `core/projectiles/projectile_manager.gd` (autoload `Projectiles`, registered in `project.godot`), with tests in `tests/core/test_pools.gd` and `tests/core/test_projectiles.gd` (cap, reuse, 1,000 projectiles against brute force, piercing, fast shots, handlers that spawn or remove targets); core README updated. The session had no Godot binary, so the tests and `build.sh --quick` have not run and the `.uid` files were written by hand. `projectile_hit` carries no damage, so the bolt (part 13) has to tell `combat` the damage another way; see `docs/DECISIONS.md`.
- M1 part 6 revision (review of PR #45): `UIFocus` now reads presses from a new `PlayerInput.get_press_count` (no lost taps), captures its owner's gameplay input while open (`PlayerInput.set_captured`), re-checks the focused control (disabled, hidden, freed) before activating, uses `is_visible_in_tree`, and refuses to open for a player with no device. New tests for each. Still no Godot binary run in this session, and the `.uid` files were not regenerated. `build.sh` only runs `tests/smoke`, so `tests/core` does not run in CI; that needs the owner (`ci/` is protected).
- M1 part 6: built `core/ui_focus` (`ui_focus.gd`, autoload `UIFocus`): a panel per player that only its owner's device moves, through `PlayerInput`; signals for focus, activate and cancel; closes when the player's device leaves. Registered in `project.godot`; tests in `tests/core/test_ui_focus.gd` (four owners at once, one open while others are not). The session had no Godot binary, so the tests were not run and the `.uid` files were written by hand.
- M1 part 5: built `core/input` (`input_manager.gd`, autoload `PlayerInput`): join by button press, one device per player, keyboard as P1 only, gamepads for P1–P4, leave, virtual devices for bots. Added `device_joined` and `device_left` to `events.gd`, the table and the coop and player READMEs, the nine input actions to `project.godot`, and `tests/core/test_input.gd`. The session had no Godot binary, so the tests were not run.
- M1 part 3: wrote `docs/STYLE.md` (palette of 31 colours, light, outline, shades, 32×32 grid, frame counts, placeholder SVG rules, checklist), added it to `llms.txt` and pointed the Art README at it. Docs only.
- M1 part 2: reconciled the event lists with `core/events/events.gd`. Added `play_requested` (HUD to `flow`) to the table in `gameplay/README.md` and to the `hud` and `flow` READMEs, and removed the "provisional" marks everywhere. Docs only.

## 2026-10-17

- Owner's session: the owner inbox (questions become `owner-question` issues, answered with `/claude`), `ci/build/build.sh --quick --tests` for unit tests (first run: 5 of 17 pass; fixing them is now first in the queue), the bot app's Client ID instead of the deprecated App ID, and opening web links allowed only in `core/links/links.gd`.

## 2026-10-16

- M1 part 1: built the event bus (`core/events/events.gd`, autoload `Events`, 24 typed signals, player index first, new `play_requested`) and the `SpellBase`, `EnemyBase` and `RoomBase` resources in `core/base/`. Tests in `tests/core/`; spells, enemies, rooms and core READMEs reworded. Signal arguments beyond the player index were not specified anywhere, so I chose them (see `docs/DECISIONS.md`); part 2 reconciles the README lists.

- Wrote the M1 design document (`docs/milestones/M1-core-loop.md`): 25 parts in build order (after review, four big parts were split), decisions on events (including the `play_requested` intent from the menu to `flow`), scenes, registry (sounds by id, `null` when missing), the one spell, arena glue and placeholder art, and the owner-only steps. Replaced the task in `docs/NEXT.md` with M1's 25 tasks. `tools/check.sh` reports the same 3 errors and 3 warnings on `main` and here: they are untracked local files (`.idea`, `.vscode`, `scripts`) that are not part of the change.
- Owner's decision: M0 closed early and M1 started. M0's dry runs and the 3-release streak carry into M1's done-when. First M1 task in `docs/NEXT.md`: the M1 design document.
- Owner's session: wrote `tools/README.md` (sessions may not write to `tools/`), unblocking the last README task. `develop` now also starts `daily` and `weekly` when GitHub misses their schedule.
- Tried again to write `tools/README.md`; writes to `tools/` were denied a third time. Moved the task to "Blocked" in `docs/NEXT.md` with what the owner needs to change and the facts for the README.
- Wrote READMEs for `art/`, `audio/` and `tests/` (size limits, `.ogg`-only audio, manifest format, how to validate). `tools/README.md` could not be written: writes to `tools/` were denied by the session, so it stays in the queue.
- Wrote `llms.txt`: an index of every doc with a one-line description, in the llms.txt format (H1, summary, link sections, "Optional" for the maintainer prompts).
- Wrote READMEs for `core/`, `hud/`, a shared `gameplay/README.md` and the 10 gameplay sub-areas (job, built and open milestones, entry script, dependency direction `core` ← `gameplay` ← `content`; `core/` closed to outside PRs). Revised after review: HUD events match the player-intent decision, Feel's hit-stop is named as its only timing effect, gameplay allows `.gd` and `.tres` only.
- Wrote READMEs for the seven content areas (spells, relics, wizard, enemies, bosses, rooms, story), each stating the milestone it opens in and that the example to copy arrives with Claude's first content.
- Repository created with `setup.sh`; all settings verified with `./setup.sh --check`. Spellmerge Bot app installed; secrets stored in the `automation` environment.
- Control panel (#4) and Daily log (#5) issues created by the owner, pinned and locked.
- M0 parts 1 and 2 built in interactive sessions: hard rules check and `checks.yml` (#2); Godot 4.7.2 project, build pipeline with smoke tests (editor, Linux, web in headless Chrome) and daily release (#3).
- M0 parts 3 and 4 in progress: control gate, Control panel verification, owner commands, pacing, alarms, plan files.
