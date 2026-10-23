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

## Round three: G, H and I (after the owner's answer on #192)

The owner liked F's hat, found its body weak, and asked that only the hat take the player's colour, for more options, and for a look at the palette. Sheet: `tests/screenshots/shot_art_direction_3.gd` (`art_direction_sheet_3.png`, in `build/screenshots/` after `ci/build/build.sh --quick --screenshots`): F again for reference, then G, H and I. Each column has the floor, the wizard at 4×, four players overlapping at 1× and 2×, and the four players apart at 1×. As before, "Reads at 1×" and "Mood" are the author's opinion, not a verdict.

**How the hat-only colour works.** F is one sprite in Player 1's blue. G, H and I are two layers of the same 32×32 canvas: a `body.svg` with no player colour, and a `hat_pN.svg` (the hat and its brim) drawn on top in player N's ramp. Everything else, robe, beard, boots, staff, is the same for all four players, so a colour on screen still means a player, and only the hat has to be redrawn per player (the game would tint nothing: it picks the right hat file by player index). The hat is F's hat, unchanged; only the body is new.

| | F: Big hat (`f_bighat/`) | G: Brown robe (`g_brown/`) | H: Cream robe (`h_cream/`) | I: New palette (`h_cream/` + `hats_vivid/` + `i_warm/`) |
| --- | --- | --- | --- | --- |
| Body | 12 px wide box, all blue | A bell robe in Wood with a gold belt and hem, a white beard, both hands, boots | A cream robe with wide shoulders, a Wood belt, cuff and hem, a golden beard, both hands, boots | H's body |
| Hat | Blue | The player's colour, standard palette | The player's colour, standard palette | The player's colour, more vivid ramps (below) |
| Floor | Four beveled Stone tiles | F's | F's | Four beveled tiles in a warm brown |
| Reads at 1× | One colour for all four players | Hats separate the players clearly; the brown robe is dark but sits apart from the Stone floor | Brightest body, so the wizard pops most against the dark floor; the hats are the only colour | Same as H, and the warm floor makes the cool hats (blue, green, purple) stand out more; rose is closest to the floor's warmth |
| Mood | Whimsical | Cosy, traveller | Classic white-robed wizard | Warmer, a lit crypt |

**The palette option (I) is a proposal, not an edit of STYLE.md.** It changes two things: the four player ramps are brighter and more saturated (Player 1 `#1b3a8c / #3b7bf0 / #8ec8ff`, Player 2 `#8c1f48 / #f0457f / #ffa0c0`, Player 3 `#1d5a2e / #3fc060 / #a6f08a`, Player 4 `#4f2090 / #9a55f0 / #d4a8ff`), so the four hats are easier to tell apart at 1×; and the floor ramp is warm (`#4d3c3a / #6e5a50 / #93806e`) instead of the violet-grey Stone, so the dark outlines and the cool hats have more contrast. These colours are allowed only in `i_warm/` and `hats_vivid/` (`tests/core/test_svg_art.gd`); picking I means `docs/STYLE.md`, `art/kit/palette.hex.txt` and the styleguide test's palette count change with it, and the walls and props would need a warm ramp too.

Notes for whoever picks:

- G and H differ only in the robe; the pick between them is mostly colour. H has the clearest contrast against the current floor.
- The two pale eyes sit in the dark under the brim (as in F) and are hard to see at 1×; at that size the hat, the beard and the staff are what is read.
- The hat covers the face, so the body layer has no face to share between players; if a face or the beard is ever player-specific it needs its own layer.
- D, E and C are not redrawn in this round; the owner moved on from them.

## Round four: J, K and L (after the owner's answer on #206)

The owner liked F's hat but said the body was too wide and the wizard should be cuter, and asked for more examples. Sheet: `tests/screenshots/shot_art_direction_4.gd` (`art_direction_sheet_4.png`, in `build/screenshots/` after `ci/build/build.sh --quick --screenshots`): H again for reference, then J, K and L, each with the same four views as round three. The hat is F's hat in each player's colour, unchanged; only the body is new, still without a player colour. As before, "Reads at 1×" and "Mood" are the author's opinion, not a verdict.

What makes them cuter: a big round face under the brim with the eyes in plain view (two 2×2 eyes with a pale highlight, blushing cheeks in Fire light, a small smile) instead of two pale dots in shadow, and a small body, so the head and hat carry the figure. The body is 8 to 10 px wide (H's robe flares to about 14), with tiny boots.

| | H: Cream (round 3, `h_cream/`) | J: Tiny cream (`j_tiny/`) | K: Bean brown (`k_bean/`) | L: Gold, big head (`l_gold/`) |
| --- | --- | --- | --- | --- |
| Face | Two pale eyes in shadow, a golden beard | Big face, 10 px wide, big eyes, cheeks, smile | J's face | The biggest face, 12 px wide |
| Robe | Cream, wide shoulders, flared hem, about 14 px | Cream, 8 px at the chest, a small flare to 10 px, Wood belt and hem | Wood brown, a round bean 10 px wide, Bone collar, Spark belt | Spark gold, 8 px wide, Bone collar, Wood belt and hem |
| Reads at 1× | Brightest body, widest | The light robe pops against the floor | The darkest body: the brown robe is close to the floor, so the hat and face carry it | The warm robe stands out most; the big head makes the figure top-heavy |
| Mood | Classic white wizard | Sweet, an apprentice | Cosy, a little bear-like | Sunny, a storybook child |

Notes:

- The beard is gone in all three: the face is the cute part. A beard can come back as its own layer if the owner wants one.
- Cheeks use Fire light (`#ffa23c`), which no player colour is close to. All three use only the standard palette.
- L's gold robe is the Spark gold (`#f2c230`), the same as the Spark pickups and the gold UI text. In the game the robe is a large 8 px patch with a Bone collar and a Wood belt, so it would not be mistaken for a 2–4 px pickup, but a figure that is mostly the pickup colour could make pickups harder to spot near it. This is a judgement from the colours, not from playing it; it is a point against L, not a blocker.
- Where to see the sheet: `art_direction_sheet_4.png` is in `build/screenshots/` after `ci/build/build.sh --quick --screenshots`, and the PR shows it as a screenshot, so nobody has to run the build to judge the look.
- Picking one of these still leaves the hat file and sheet questions in `docs/NEXT.md` ("Record the chosen art direction").

## Round five: M, N and O (after the owner's second answer on #206)

The owner kept F's hat and asked for a robe as the clothes and a face of just two big eyes, no mouth, with more examples. Sheet: `tests/screenshots/shot_art_direction_5.gd` (`art_direction_sheet_5.png`, in `build/screenshots/` after `ci/build/build.sh --quick --screenshots`, and shown in the question): J again for reference, then M, N and O, each with the same four views as before. The hat is F's hat in each player's colour; the body has no player colour. As before, "Reads at 1×" and "Mood" are the author's opinion, not a verdict.

What changed from J, K and L: the face is two big tall eyes (2×3 px, black, with a white highlight) on plain skin, with no mouth and no cheeks. The clothes read as a robe: a front placket down the middle, a belt with a buckle, sleeves down to the hands, and a hem band. The body is the same narrow size as J (10 px at the chest, 12 px at the hem).

| | M: Cream robe (`m_cream/`) | N: Dusk robe (`n_dusk/`) | O: Teal robe (`o_teal/`) |
| --- | --- | --- | --- |
| Robe | Bone, Spark placket and hem, Wood belt | Stone violet-grey, Spark placket and hem, dark belt | Ice teal, Bone placket and hem, Wood belt |
| Reads at 1× | Brightest body: pops most against the floor; the gold placket is a clear mark | Darkest body, close to the floor's value by eye (not measured); the gold trim and the hat carry it | Bright and cool, but the same teal as the Ice element and the frost tint |
| Mood | Apprentice, classic | Night wizard, mysterious | Fresh, a water mage |

Notes:

- The eyes carry the cuteness: at 1× they are two dark dots under the brim, so the face still reads as a face.
- Gold (the placket and hem of M and N) is also the Spark colour of pickups and the gold UI text; here it is a thin line, not a large patch like L.
- O's teal is the Ice ramp, used by frost spells and icons. It is a body colour here, never a player colour, but it could blur the line between a player and an ice effect.
- **N was chosen** (owner, #206). The hat stays a separate layer in the player's colour, and `n_dusk/blink.svg` is the blink layer (closed eyes) drawn over the body's eyes. See "The wizard" in `docs/STYLE.md`. `n_dusk/` and `hats_std/` are also referenced by `art/kit/golden.json` (the style guide page, the kit zip and `test_styleguide` use them), so do not remove or rename them until the wizard redraw task moves them into `content/wizard/` and updates the golden list. The other samples stay here for reference.
