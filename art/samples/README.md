# Art direction samples

Three looks for the game, each a wizard, a crypt floor tile and a fire spell icon, all on the 32×32 grid and in the shared palette ([docs/STYLE.md](../../docs/STYLE.md)). They exist so the owner can pick one (M2 part 27); nothing in the game uses them. Sheet: `tests/screenshots/shot_art_direction.gd` (`art_direction_sheet.png`, in `build/screenshots/` after `ci/build/build.sh --quick --screenshots`; the owner question is #190). The "Reads at 1×" and "Mood" rows are the author's opinion, not a verdict.

| | A: Chunky (`a_chunky/`) | B: Current | C: Grim (`c_grim/`) |
| --- | --- | --- | --- |
| Wizard | Big head and face, short bell robe, 16×22 px | The game's placeholder: `content/wizard/base/wizard_p1_idle.svg` | Tall hooded cloak, no face, two glowing eyes, 16×20 px |
| Floor | Bold offset bricks, clear joints | `art/tilesets/crypt/floor.svg`: flagstones with fine cracks | Large slabs, thin joints, two cracks |
| Icon | One big round flame | `content/spells/elements/fire/icon.svg` | Narrow flame with a skull-like face |
| Reads at 1× (the author's look at the sheet's 1× row, four wizards overlapping; judge it yourself) | The face and the hat stay apart when four overlap | The four hats stay apart; the fine floor cracks are busy | The dark cloak is close to the dark floor; four overlapping are a dark clump |
| Mood | Friendly, bright, close to a cartoon | Classic fantasy, a little plain | Moody, a dark crypt |

The two rows above ("Reads at 1×" and "Mood") are the author's opinion of its own drafts, not a measurement; nothing here was tested with players. Pillar 4 (readable chaos) is left for the owner to judge from the sheet.

B is not a new drawing; it is the current placeholder, so "keep what we have and polish it" is a fair choice too.

Notes for whoever picks:

- A and C depart from STYLE.md's floor rules on purpose so the owner can see the effect: "floors are flat, with only a few inner details" (A's bold brick joints and C's slab joints are a shadow line plus a light line each, well past a few details) and "nothing on the outer edge" (the joints run across the whole width and touch the tile edge). They still repeat seamlessly. Picking A or C means STYLE.md's floor section changes with it; if the rules stay, the joints are thinner and move inward.
- C's cloak uses the Player 1 shadow shade for most of its body, which is why it is hard to see on the floor. A lighter version would use the base shade.
- The samples are not final art. Whichever is chosen is redrawn properly across the later milestones, and its files become the golden examples in `art/kit/golden.json` and `docs/STYLE.md`.
