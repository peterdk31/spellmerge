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

## Round two: D, E and F (after the owner's answer on #190)

The owner leaned towards A, liked C's robe, and asked for more options, new styles included. Sheet: `tests/screenshots/shot_art_direction_2.gd` (`art_direction_sheet_2.png`, not committed: it is in `build/screenshots/` after `ci/build/build.sh --quick --screenshots`, and in the CI screenshots artifact of this PR): A again for reference, then D, E and F. Same palette, same 32×32 grid. As before, "Reads at 1×" and "Mood" are the author's opinion of its own drafts, not a verdict.

| | D: Chunky hood (`d_hood/`) | E: Soft (`e_soft/`) | F: Big hat (`f_bighat/`) |
| --- | --- | --- | --- |
| What it is | A's big face and bell shape inside C's pointed hooded robe, in the Player 1 base shade (C's was too dark) | A new look: no black outline, each part outlined in its own shadow shade; wide-brimmed hat, round robe | A new look: the hat is as big as the body, the face is only two pale eyes in the shadow under the brim |
| Wizard | 14 px wide, 24 px tall, hood peak, Bone beard in the hood opening | 16 px wide, 24 px tall, brim 16 px wide | 20 px wide, 29 px tall with the hat; the body is 12 px wide |
| Floor | A's (not redrawn) | Calm 8 px checkerboard of two Stone shades | Four big beveled 16 px tiles |
| Icon | A's (not redrawn) | Teardrop flame, outline in Fire's dark shade | The same teardrop with the black outline |
| Reads at 1× | Hood and face stay apart; the peak keeps each wizard narrow | Softest and calmest, but with no black the wizard has the least contrast against the floor | Strongest silhouette: four tall hats overlap into a row of peaks; the face is almost lost |
| Mood | Friendly but a little mysterious | Gentle, storybook | Whimsical, classic wizard |

- **E departs from STYLE.md's outline rule on purpose** ("1 px, colour `#14121f`, around the whole outside of every sprite"). Picking E means that rule changes with it. `test_svg_art.gd` checks E's icon against the dark red instead of the black.
- **D reuses A's floor and icon;** only the wizard is new. D's floor and icon would be A's.
- **E's checkerboard and F's beveled tiles are plain on purpose:** calm floors keep the busy part of the screen for the wizards and spells (pillar 4). F's tiles also leave STYLE.md's "nothing on the outer edge" rule, like A and C.
- The owner liked C's robe: that is D. C itself is unchanged (`c_grim/`).
