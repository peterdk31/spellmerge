# The boss intro: a screen-wide overlay before the fight

**Status (2026-11-16): waiting for the owner's approval.** Written with the owner in an owner session on 2026-11-16. It replaces the boss plan's entrance (docs/milestones/boss-old-broom.md, "The entrance", and OB16's banner) for a boss that has an intro; a boss with none keeps the banner.

**The owner (2026-11-16):** "We need a cool screen wide overlay when facing a boss in its arena. It should animate in. The boss should be completely dark at first like a silhouette. And then when its name appears (with a cool font and effects), the boss should show looking mean. If it has dialog, now would be the place to show it. After the last dialog (if any) a player should press A to close the overlay and start the fight."

**The owner's answers (2026-11-16):** every player can move it on (any seat's A, on any machine); a drawn portrait for each boss; the boss is the only speaker; only at the fight's start (no intro at a phase change).

The steps are **BI1 to BI6** (BI for boss intro). Each is one PR with its tests, in order.

## What the players see

The view is 640×360. The overlay's timing is the HUD's frame (real time, as the banner's); only its pages and its end are the game's (rule 2).

| Time | What happens |
| --- | --- |
| 0.0 s | The room has just appeared, the boss standing in it; the game has stopped on that tick. |
| 0.4–0.7 s | Black bars slide in from the top and the bottom (36 px each); the world under them dims to 40%. The room's music drops to its first layer. |
| 0.7–1.2 s | A slash in the boss's accent colour streaks across the middle from the right. The **portrait** slides in on it from the right, **completely black**, with a 1 px rim in the accent colour. |
| 1.2–1.9 s | The silhouette holds. Its eyes light up: a few pixels in the dark. A low creak (the cue's first sound). |
| 1.9 s | **The reveal:** a white flash for two frames, the portrait in full colour in its **mean pose**, the overlay shaking 4 px and settling within 0.3 s. The **name slams in letter by letter** (each letter from 3× to 1× in whole-number steps, 40 ms apart) in the title type, then a glint sweeps across it. The lore line types out under it in the small type. The `boss_intro` cue's sting plays; the boss's music starts. |
| 2.9 s → | **Dialog**, if the boss has lines: a box at the bottom left, the boss's line typing out (30 characters a second), a blinking A glyph (`action_glyph`) once the line is out. With no lines, the A glyph and "Fight" show under the name. |
| A on the last page | The bars slide out, the portrait leaves the way it came, the name's letters fall away, the boss bar fades in; the game goes on from the next tick. |

**The layout:** the portrait at the right, its feet on the bottom bar (a 96×96 frame drawn at 2×, 192 px); the name at the left, 48 px in and about a third of the way down; the lore line under it; the dialog box under that, 352×56 px, over the bottom bar's top edge. With a narrow view (a split screen later) everything keeps its place on the view's own width.

**Pressing A:**
- Before the reveal is over, a press does nothing (nobody skips the silhouette by accident).
- On a line still typing, a press writes the line out at once, on that machine only.
- On a line written out, a press is the next page for everyone: the next line, or after the last line (or with none) the fight.
- Any seat's A, on any machine; nobody waits for one player in particular (decision 1).

## The rules

1. **An intro is a boss's data.** `BossIntro` (core/base, new; a sub-resource of the boss's `.tres`) on `EnemyBase.intro` (null: no intro, the banner as now):
   - `portrait: Texture2D`: a sheet of three 96×96 frames in the boss's folder: **rest** (the silhouette's shape), **mean** (the reveal), **eyes** (only the pixels that light up in the dark, drawn over the silhouette).
   - `lines: Array[String]`: what the boss says, the boss alone (decision 3), at most `MAX_LINES` (3) of at most `StoryValidator.MAX_SPEECH_CHARS` (60) each. STORY.md's speech rule applies from now on; the story check holds every boss's lines to it.
   - `accent: StringName`: a palette ramp of docs/STYLE.md (the slash, the rim, the glint, the name's shadow).
   - `problems()`: the portrait's size (three frames of `FRAME`), the lines, the ramp. `test_bosses` checks it for every boss with an intro.
   - The timeline's constants (`LEAD`, `REVEAL_AT`, `LETTER_GAP`, ...) are on `BossIntro` too, so the HUD and Feel time the same moments without naming each other.
   The name is `EnemyBase.shown_name()` and the line under it `lore`, as the banner's.
2. **The game stops on a tick, and only commands move it on.** The pause and the page are the simulation's, so on every machine and in a replay they happen on the same tick (online-ready, "Commands at the next tick's start"):
   - `BossIntroHold` (gameplay/flow, new; Flow's, as `RoomAdds` is, its members state) is told by Flow as it stands a room's enemies (`_stand_room_enemies`): the first boss with an intro stood in the room, when the run's rules have intros on (rule 4). It stops the game (`Sim.stop(&"boss_intro")`), keeps the boss's actor id and the page (0), and sends `boss_intro_opened(actor, intro, page)` (core/events, new).
   - `boss_intro_next_requested(seat, page)` (core/events and `InputFrame.COMMAND_NAMES`, new; the frame's version 5) is a seat's A on a page written out, carrying the page that seat's HUD showed. The hold, hearing it through `Events.listen`, turns the page only when that is still the page: two players pressing on the same tick turn one page, not two (the menus' body key, items I8, is the same idea). It sends `boss_intro_paged(page)`; past the last page it lets the game go (`Sim.go`) and sends `boss_intro_closed(actor)`.
   - Only bosses of the run's own rooms: never the sandbox's spawns or a phase's adds, and never again in the same room.
   - A stop for another reason (the pause menu, an unplugged pad: `Coop.MENU_OF`, `PAD_OF`) stacks with it: closing the intro while a menu is open lets the game go only when the menu shuts too (`Sim.stops`). A run's start lets every stop go (`Tick.begin_run`), and the hold is cleared with the run.
   - The boss's first cast still waits its `first_wait` in game time, from the fight's start.
3. **Snapshots and joins.** The hold's state (the boss's id, the page, whether it is open) is saved and restored with the rest. Its `rebuild_derived()` sends `boss_intro_opened` again while it is open, so a machine that joins mid-intro shows the overlay at that page, already revealed (the HUD skips the lead-in for a page past 0, or for an open that is not the room's first tick).
4. **A run's rule, on by default.** `SessionRules.boss_intros` (a byte; `BYTES` grows by one), on in a run people play. Tests, bots and screenshots start runs with it off, as the intro is off for a test script (`Flow.intro_enabled`), unless they test the intro itself. It is a rule and not a machine's setting because it changes when the game stops: a replay recorded with it on would not play back the same with it off.
5. **The HUD shows it and sends A.** `hud/panels/boss/boss_intro.gd` (node `Root/BossIntro`, over the world and the corner panels, under the menus and the pause shade) hears the three events, plays the timeline, writes the lines out, gates A (the reveal first; a line typing is finished locally) and sends `boss_intro_next_requested` for this machine's seats (`Frames.seats_here`). It knows nothing of Flow or the hold. While it is open the boss bar stays hidden and fades in on `boss_intro_closed`; the banner (OB16) shows only for a boss without an intro.
6. **The silhouette is a shader on the same art.** `hud/panels/boss/silhouette.gdshader`: `reveal` (0 black, 1 its colours), `rim` (the accent colour round the edge, 1 px), `flash` (white); the eyes frame drawn over it, glowing. Warmed through `ShaderWarmup.want` where the HUD first uses it. The portrait is drawn at whole-number scale only (2×).
7. **A title type.** One bitmap face, original and drawn for the game: `art/ui/fonts/title.png` (a glyph sheet, imported as Godot's image font, so no `.ttf`: the allowed file types), listed in art/manifest.json, all printable ASCII on a 12×16 grid, heavy and a little worn, for boss names now and biome titles later. A theme variation `TitleLabel` in `hud/theme`, drawn at 2× (32 px) for a boss's name. docs/STYLE.md allows it beside the one body font (decision 5). A test checks every boss's shown name has a glyph for each character.
8. **Sound and music from Feel.** Feel hears `boss_intro_opened` and plays the boss's `boss_intro` cue on the boss's body at `REVEAL_AT` (its creak earlier, at the silhouette, if the cue has one: a cue part's delay), not on `boss_shown` for a boss with an intro. The boss's `music` starts at the reveal rather than at `boss_shown`. Feel's players for these play while the tree is paused (their `process_mode`), as the pause menu's sounds do.
9. **Nothing names the broom.** The hold, the HUD and Feel read only `BossIntro` and the boss's data; a second boss with an intro needs a portrait, its lines and a ramp in its own folder.

## Steps

| Step | What | Areas |
| --- | --- | --- |
| BI1 | This plan, approved; DESIGN.md (no-waiting rule 7), STYLE.md (the title type), STORY.md (speech in use), the boss plan's entrance and the roadmap pointing here; DECISIONS.md | docs |
| BI2 | **The game's part:** `BossIntro` with `problems()`, `EnemyBase.intro`, the story check of its lines; `SessionRules.boss_intros`; `BossIntroHold` in Flow; the three events and the command (frame version 5). Tests (`tests/gameplay/flow/test_boss_intro_hold.gd`, new): the stop on the room's tick and only for a boss with an intro, with the rule on; any seat turns a page; a stale page is ignored (two presses on one tick turn one page); the last page lets the game go; stacked with the pause menu and a waiting pad; none in the sandbox or for adds; a snapshot mid-intro restores the page and opens the HUD again; a replay of an intro plays back the same (`test_determinism`); `test_state_declared`, `test_state_walked` cover the hold | core, gameplay/flow, core/sim |
| BI3 | **The title type:** the glyph sheet, its import, `TitleLabel`, its manifest row. Tests: it loads as a font; every boss's shown name is covered | art/ui, hud/theme |
| BI4 | **The overlay:** `boss_intro.gd`, the silhouette shader (warmed up), the bar and banner rules, Feel's sting and music at the reveal; a test boss under tests/ with a stand-in portrait. Tests (`tests/hud/test_boss_intro.gd`, new): the timeline's moments at fixed deltas, A ignored before the reveal, a typing line finished locally, the command sent with the shown page for this machine's seats only, joined mid-intro shows the page revealed, the bar hidden until closed. A filmstrip, `tests/screenshots/shot_boss_intro.gd` (silhouette, eyes, reveal, each line, closing), for every boss with an intro | hud, gameplay/feel, tests |
| BI5 | **The broom's intro:** its portrait (rest: hunched on its bristles; mean: reared up, the bristles splayed, its angry brows and slanted eyes; eyes), its lines (below, for the owner), its accent (`spark`); its cue's creak; the filmstrip for the owner's review | content/bosses/old_broom, content/cues |
| BI6 | **Playtest and tune:** the owner's playtest on `/preview/` (timings, the shake, how long the lines feel with four players); folded into the boss plan's OB17 if it comes first | content/bosses, hud |

**The broom's lines (a draft for BI5, the owner to change):**
1. "Oh. Visitors. And I'd only just swept."
2. "I was the first staff. Now I do floors."
3. "Hold still. You're making a mess."

**Names:** "intro" alone is the game's opening (`gameplay/flow/intro.gd`, `Flow.intro`), so everything here is `boss_intro`: `BossIntro`, `BossIntroHold`, `boss_intro_opened`, `boss_intro_paged`, `boss_intro_closed`, `boss_intro_next_requested`, the stop `&"boss_intro"`. The `boss_intro` cue (OB15) keeps its name: it is this overlay's sound.

## Decisions (owner, 2026-11-16)

1. **Any player moves it on, on any machine.** The one exception to pillar 2 beside the pause menu and an unplugged pad: the boss's entrance is a moment everyone sees together, and since any one A moves it on, nobody waits for a particular player. Online it stops every machine, unlike the pause menu (DESIGN.md, no-waiting rule 7).
2. **A drawn portrait for each boss,** not the body scaled up: the overlay is the boss's close-up, and the mean pose is drawn for it.
3. **The boss is the only speaker.** No wizard lines, so nothing in the story speaks for a player (STORY.md, "Together").
4. **Only at the fight's start.** A phase change keeps its look, its shudder and its transition (OB8, OB9), with no overlay.
5. **A title type beside the one pixel font** (the session's recommendation, for the owner to overrule in review): a bitmap face for names, since the allowed file types have no `.ttf`.

## Not in this plan

Cutscenes of other kinds (they wait for M3's story schema, as `gameplay/flow/intro.gd` says); a wizard speaking; an intro at a phase change; a setting to turn intros off (it would be a run's rule, rule 4, and an M4 option).
