# Art direction samples

Three looks for the game, each a wizard, a crypt floor tile and a fire spell icon, all on the 32×32 grid and in the shared palette ([docs/STYLE.md](../../docs/STYLE.md)). They exist so the owner can pick one (M2 part 27); nothing in the game uses them. Sheet: `tests/screenshots/shot_art_direction.gd` (`art_direction_sheet.png`).

| | A: Chunky (`a_chunky/`) | B: Current | C: Grim (`c_grim/`) |
| --- | --- | --- | --- |
| Wizard | Big head and face, short bell robe, 16×22 px | The game's placeholder: `content/wizard/base/wizard_p1_idle.svg` | Tall hooded cloak, no face, two glowing eyes, 16×20 px |
| Floor | Bold offset bricks, clear joints | `art/tilesets/crypt/floor.svg`: flagstones with fine cracks | Large slabs, thin joints, two cracks |
| Icon | One big round flame | `content/spells/elements/fire/icon.svg` | Narrow flame with a skull-like face |
| Reads at 1× | Best: the face and hat stay clear when four players overlap | Good | Weakest: the dark cloak melts into a dark floor; needs a lighter rim |
| Mood | Friendly, bright, close to a cartoon | Classic fantasy, a little plain | Moody, a dark crypt |
| Fits "readable chaos" (pillar 4) | Yes | Yes | Needs care: the four player colours are the only bright spots |

B is not a new drawing; it is the current placeholder, so "keep what we have and polish it" is a fair choice too.

Notes for whoever picks:

- A and C break one STYLE.md rule on purpose so the owner can see it: the floor has joints that touch the tile edge (the brick joints run across the whole width). They still repeat seamlessly. If the rule stays, the joints move inward.
- C's cloak uses the Player 1 shadow shade for most of its body, which is why it is hard to see on the floor. A lighter version would use the base shade.
- The samples are not final art. Whichever is chosen is redrawn properly across the later milestones, and its files become the golden examples in `art/kit/golden.json` and `docs/STYLE.md`.
