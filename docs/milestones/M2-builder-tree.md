# M2: the builder's tree view (owner, 2026-10-31)

A change to the radial builder (staffs B8, [M2-staffs.md](M2-staffs.md), "The builder"), worked out with the owner on 2026-10-31 over true-scale mockups rendered in the game. It follows the rule that **each trigger before a carrier takes its own payload** (docs/DECISIONS.md, 2026-10-31), which makes a staff a tree: the builder has to show which payload is whose, and the slots alone cannot.

**Why:** with several triggers on one carrier and payloads inside payloads, the slot grid no longer says what a staff does. A tree of the compiled staff does. The mockups also showed what does not fit: brackets and words under 16 px slots, and marks on every tile (they cover the icons and clash when payloads nest).

**Done when:** every part below is merged, `ci/build/build.sh --quick --tests` is green, the screenshots show the four quarters alike, and the owner has tried it in the sandbox.

## What the player sees

The builder is the radial one (the default). The list builder, reachable from the pause menu's Sandbox page, only loses copy/paste and the cast names (parts T1, T2); nothing else of this design goes into it.

### Every quarter alike

All four builders are laid out as player 1's today: **the column on the left of the quarter, the ring (or the tree) on its right**. A right-hand player's column no longer sits at the screen's edge; it can move because:

- **The corner panel is hidden while the builder is open** (HP, MP and the staff rows), and so are **the staff's numbers under the slots** (Mana %, Dmg, Time). They come back when it closes.
- **HP and MP bars** sit on top of the column instead: two 2 px bars (HP in the panel's red, MP in its yellow) in a 1 px frame of the player's colour, 7 px in all, so a player who builds during a wave still sees their health, and the frame says whose builder it is. They follow `player_stats_changed`.

Top to bottom, the column (112 px wide) holds the bars, the staff tabs (LB 1 2 3 4 RB), the 5 × 4 slots, and the **card info panel** in what is left (about 108 × 77 px).

### The card info panel

It shows the card under the slot marker (the left stick moves the marker, as today), in the tree and on the ring alike, never as a popup:

- its name, with its kind on the right in the kind's colour (Carrier, Modifier, Infusion, Trigger, Multicast), and a frame in that colour;
- its description: the card's lore line (`Spells.component_description`), wrapped to the panel;
- under a line, its numbers (`Spells.component_stats`), except for a trigger, whose only number would repeat its name.

An empty slot shows "Empty slot". A wasted card keeps its "!" on the slot.

### The ring's middle

Unchanged: with no card pointed at, the hub shows the staff's Mana, Dmg and Time; pointing at a card shows that card (owner: it is good to see the staff's numbers there).

### Buttons

| Button (keyboard) | Ring | Tree |
| --- | --- | --- |
| Left stick (move keys) | moves the slot marker | the same; the tree follows it |
| Right stick (mouse) | points at a card | scrolls the tree |
| RT (left click) | puts the pointed card in | nothing to put in (no card is pointed at) |
| LT (Q) | takes out, undoes or closes a gap, as today; **held** `CLEAR_HOLD` (0.6 s) it clears the staff | the same |
| Y (R) | opens the tree | back to the ring |
| B | closes the builder | the same |
| LB, RB | the staff before or after | the same |

**LT held clears** (replacing "hold Y"): the press acts at once, as today (so quick take-outs stay as quick), and if LT is still held the red frame fills round the slots as it does now and the rest of the staff is cleared. The first card is gone either way, so a clear ends in the same state. **X and A** have nothing left to do in the builder: copy and paste are gone (part T1).

### The tree view

Y swaps the ring (and the ring's kind row) for a tree of the shown staff's whole cycle, in the same space: the quarter's ring side, from the top down to the hint row, about 196 × 164 px. The slots, the bars and the card info stay.

- **A header** "Tree", then one **row per carrier** and one **per trigger**, 19 px each, built from the actual compiled staff (part T3):
  - a carrier row: on a cast's first row the cast number ("#1"), the carrier's own cards as 16 px tiles (the same tiles as the slots: icon and kind bar; its modifiers and infusions, then the carrier), its name in the carrier colour, and on a cast's first row that cast's mana share and damage on the right;
  - a trigger row, indented 12 px per payload level with a branch line from its parent: the trigger's tile, a small arrow, the tiles of what it fires (the first carrier of its payload with its own cards), and **the trigger card's name** (On Hit, On Expire, Timer, On Hurt, On Wall, ...) in the trigger colour. No other words (owner).
  - a payload with several carriers (a multicast in it) has one row for each further carrier, at the same depth, with no trigger tile.
- **The slot marker links the two:** the row holding the marked card is highlighted, and that card's tile in the tree gets the gold marker frame the slot has.
- **Scrolling:** a tree taller than its space scrolls with the right stick (P1: the mouse wheel), with a 2 px scroll bar on its right edge. Moving the marker scrolls its row into view.
- **The timing replay** (first version): a gold frame steps through the rows of each cast, one row a beat (`TREE_BEAT`, 0.4 s, a first guess), in the tree's own order (a carrier, then its triggers, depth first), and loops. It is drawn in code; nothing is cast in the world. A replay at the real moments (travel time, lifetimes, timer intervals) and a picture of each carrier's shape are left for later (see "Later").
- **P1's mouse:** a click on a tile in the tree marks that card's slot.

### Gone (owner, 2026-10-31)

- **Copy and paste of staff codes** (staffs D2): the code row under the ring, X and A in the builder, the list builder's two buttons, and `StaffCode` with `Spells.staff_code` and `Spells.parse_staff_code`. Sharing a build is a screenshot of the tree.
- **The cast names** (staffs E1): the line of names over the hints, `SpellNamer`, `CompiledCast.spell_name`, the `name` in `Spells.staff_view`, and every card's `name_words`. Where a name was used to call a cast (the fuzz test's titles, the emergent combo report), its plain description (`CompiledCast.description`) is used.

## Parts

One session and one PR each, in this order unless "after" says otherwise. Each keeps `tools/check.sh` and the quick build green, updates the READMEs it touches, and redoes the screenshots it changes (`ci/build/build.sh --quick --screenshots`).

| Part | What | Paths | After | Done when |
| --- | --- | --- | --- | --- |
| T1 | **Copy and paste gone** | `core/spells/` (`staff_code.gd`, `spells.gd`), `hud/builder/` (both builders), `tests/core/test_staff_code.gd`, `tests/hud/`, `hud/README.md`, `core/README.md` | the trigger rule | No staff code anywhere: the files, the calls, the code row and its glyphs, the list builder's buttons; X and A do nothing in the builders; their tests are removed or changed; the radial's freed row is left empty (T4 takes it) |
| T2 | **Cast names gone** | `core/spells/` (`spell_namer.gd`, `staff_compiler.gd`, `compiled_cast.gd`, `spells.gd`), `core/base/spell_component.gd`, every card `.tres` under `content/spells/` (`name_words`), `content/spells/README.md`, `tests/core/test_spell_names.gd`, `tests/bots/test_spell_fuzz.gd`, `hud/builder/radial_builder.gd` | T1 | No `SpellNamer`, `spell_name`, `name_words` or names line; the fuzz test and the combo report call a cast by its description; a test that loads every card still passes (no unknown property left in a `.tres`) |
| T3 | **The tree's data** | `core/spells/` (`staff_compiler.gd`, `compiled_spell.gd`, `spells.gd`), `tests/core/` | T2 | Each `CompiledSpell` knows its own card slots (`card_slots`: the cards attached to it, its carrier, in slot order; a fallback's cards too), set where the compiler attaches them, not guessed afterwards. `Spells.staff_view` gives each cast a `tree`: rows of plain values (`depth`, `trigger` slot or -1, `slots`, `name`: the carrier's or trigger card's display name, and on a cast's first row `mana` and `damage`), depth first, payloads' further carriers as rows of their own. Tests for `on hit · on expire · bolt · fire · nova · zap · nova`, a nested payload (`timer · on hurt · hold · decoy · on expire · fire · bolt · blast · frost · nova · bolt`: the blast joins the frost nova, so on hurt fires the last bolt), a payload with a multicast, a fallback, and a wasted trigger (no row) |
| T4 | **One layout for all, bars and card info** | `hud/builder/radial_builder.gd`, `hud/panels/panels.gd`, `tests/hud/test_radial_builder.gd`, `tests/screenshots/shot_radial_builder.gd` | T1, T2 | The column on the left of every quarter, the ring on its right; the corner panel and the staff numbers hidden while the radial is open (back when it closes); the HP and MP bars in the player's colour frame, following `player_stats_changed`; the card info panel for the marked slot; LT held clears (Y no longer does); the four builders still fit 640 × 360 with four players (the layout test); a screenshot of four players |
| T5 | **The tree view** | `hud/builder/` (a `tree_view.gd` beside the radial, drawn in code), `tests/hud/`, `tests/screenshots/` | T3, T4 | Y swaps the ring for the tree and back; rows, tiles, branch lines and names from `staff_view`'s `tree`; the marked card's row and tile marked; right stick and mouse wheel scroll, with the bar; the marker scrolls its row into view; P1's click on a tile marks its slot; the timing replay; tests for the rows drawn from a plan, the marker link and the scroll; screenshots `radial_tree` (one player, a nested staff) and `radial_tree_four_players` |

## Later (not in these parts)

- A replay at the real moments of a cast, and a small drawing of each carrier's shape on its row (a dot for a bolt, a ring for a nova).
- A live preview, the staff cast at a dummy in a small separate world: it needs a second, isolated spell runtime per open builder while the game runs, and a performance check first.
- Whether the list builder gets the tree too, or goes.

## Self-critique against docs/DESIGN.md

- **Deep spell building (pillar 1):** the tree makes the new branching rule readable, so deeper staffs stay buildable.
- **Co-op, nobody waits:** the builder still never pauses; hiding the corner panel is per player and only while their builder is open, and the bars keep health in view during a wave.
- **Readable at a glance, nothing by colour alone:** the tree's rows are tiles and names, the marked card has the gold frame and the row band as well as colours, and the bars are told apart by their place (HP above MP) as well as their colour.
- **Every quarter the same:** a player who switches seats finds the same builder.
- **Removed features:** staff codes (D2) and cast names (E1) were shipped parts; removing them is the owner's call (2026-10-31), recorded in docs/DECISIONS.md.
